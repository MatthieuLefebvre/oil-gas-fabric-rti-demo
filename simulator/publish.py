"""Finite paced publishing with bounded in-flight work and sanitized failures."""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import importlib
import itertools
import json
import math
import os
import sys
import time
from concurrent.futures import FIRST_COMPLETED, Future, ThreadPoolExecutor, wait
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping, Protocol
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

from .telemetry import Telemetry, iter_live, parse_time, read_ndjson


ERROR_MESSAGES = {
    "PublishFailed": "Publishing failed; inspect transport configuration privately",
    "EventHubsHttpError": "Event Hubs rejected the request",
    "EventHubsNetworkError": "Event Hubs network failure; retry budget exhausted",
    "KafkaDependencyMissing": "Kafka transport requires optional kafka-python>=2.2.15,<3",
    "KafkaInitializationError": "Kafka initialization failed; inspect broker/auth configuration privately",
    "KafkaSendError": "Kafka send failed; retry budget exhausted or non-retriable error",
    "KafkaCloseError": "Kafka close failed",
    "SendError": "Sender failed; inspect sender implementation privately",
    "InputError": "Input could not be read or decoded",
    "CloseError": "Sender cleanup failed",
    "InvalidConfiguration": "Invalid configuration; verify transport settings and limits",
}


@dataclass(frozen=True)
class FailureDetail:
    Code: str
    Message: str
    HttpStatus: int | None
    Attempts: int


class PublishError(RuntimeError):
    """Public errors intentionally omit remote responses, endpoints and secrets."""

    def __init__(self, message: str, *, attempts: int = 1,
                 code: str = "PublishFailed", http_status: int | None = None) -> None:
        super().__init__(message)
        self.attempts = attempts if type(attempts) is int and 1 <= attempts <= 9 else 1
        safe_code = code if code in ERROR_MESSAGES else "PublishFailed"
        safe_status = http_status if type(http_status) is int and 100 <= http_status <= 599 else None
        self.detail = FailureDetail(safe_code, ERROR_MESSAGES[safe_code], safe_status, self.attempts)


class Sender(Protocol):
    def send(self, row: Telemetry) -> int:
        """Return attempts on transport acceptance, or raise sanitized PublishError."""

    def close(self) -> None: ...


def positive_config(rate: float, concurrency: int, timeout: float, retries: int) -> None:
    if not math.isfinite(rate) or rate <= 0 or not 1 <= concurrency <= 64:
        raise ValueError("Rate must be finite/positive; concurrency must be 1..64")
    if not math.isfinite(timeout) or not 0 < timeout <= 120 or not 0 <= retries <= 8:
        raise ValueError("Timeout must be (0,120]; retries must be 0..8")


def resource_uri(value: str) -> str:
    parsed = urlsplit(value)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.query or parsed.fragment or parsed.port not in (None, 443)
            or not parsed.path.strip("/") or parsed.path.rstrip("/").endswith("/messages")):
        raise ValueError("Event Hubs resource must be HTTPS host/entity without credentials, query or /messages")
    return value.rstrip("/")


def sas_token(uri: str, key_name: str, key: str, expiry: int) -> str:
    encoded = quote(resource_uri(uri), safe="")
    # Event Hubs signs using the UTF-8 key text, not base64-decoded key bytes.
    signature = base64.b64encode(
        hmac.new(key.encode("utf-8"), f"{encoded}\n{expiry}".encode("utf-8"), hashlib.sha256).digest()
    ).decode("ascii")
    return (
        f"SharedAccessSignature sr={encoded}&sig={quote(signature, safe='')}"
        f"&se={expiry}&skn={quote(key_name, safe='')}"
    )


def eventhubs_auth(env: Mapping[str, str]) -> tuple[str, Callable[[], str]]:
    connection = env.get("TELEMETRY_EVENTHUB_CONNECTION_STRING", "")
    supplied_uri = env.get("TELEMETRY_EVENTHUB_RESOURCE_URI", "")
    sas = env.get("TELEMETRY_EVENTHUB_SAS_TOKEN", "")
    bearer = env.get("TELEMETRY_EVENTHUB_BEARER_TOKEN", "")
    if connection:
        if supplied_uri or sas or bearer:
            raise ValueError("Choose connection string OR resource URI with one token")
        parts = dict(part.split("=", 1) for part in connection.split(";") if "=" in part)
        required = ("Endpoint", "EntityPath", "SharedAccessKeyName", "SharedAccessKey")
        if not all(parts.get(field) for field in required):
            raise ValueError("Event Hubs connection string lacks required fields")
        endpoint = urlsplit(parts["Endpoint"])
        entity = parts["EntityPath"]
        if (endpoint.scheme != "sb" or not endpoint.hostname or endpoint.username or endpoint.password
                or endpoint.query or endpoint.fragment or endpoint.path not in ("", "/")
                or endpoint.port is not None or "/" in entity or "?" in entity or "#" in entity):
            raise ValueError("Invalid Event Hubs connection endpoint or entity")
        uri = resource_uri(f"https://{endpoint.hostname}/{quote(entity, safe='')}")
        return uri, lambda: sas_token(uri, parts["SharedAccessKeyName"], parts["SharedAccessKey"], int(time.time()) + 3600)
    if not supplied_uri or bool(sas) == bool(bearer):
        raise ValueError("Provide Event Hubs resource URI and exactly one SAS or bearer token")
    uri = resource_uri(supplied_uri)
    token = sas if sas else f"Bearer {bearer}"
    if "\r" in token or "\n" in token or (sas and not sas.startswith("SharedAccessSignature ")):
        raise ValueError("Invalid Event Hubs authorization token")
    return uri, lambda: token


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req: Any, fp: Any, code: int, msg: str,
                         headers: Any, newurl: str) -> None:
        return None


class EventHubsRestSender:
    def __init__(self, env: Mapping[str, str], timeout: float = 15, retries: int = 3) -> None:
        self.uri, self.authorization = eventhubs_auth(env)
        self.timeout = timeout
        self.retries = retries

    def send(self, row: Telemetry) -> int:
        body = json.dumps(row, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        for attempt in range(self.retries + 1):
            request = Request(
                self.uri + "/messages", data=body, method="POST",
                headers={"Authorization": self.authorization(), "Content-Type": "application/json"},
            )
            try:
                with build_opener(NoRedirect()).open(request, timeout=self.timeout) as response:
                    if 200 <= response.status < 300:
                        return attempt + 1
                    raise PublishError("Event Hubs returned non-success status", attempts=attempt + 1,
                                       code="EventHubsHttpError", http_status=response.status)
            except HTTPError as error:
                status = error.code
                error.close()
                if status not in (408, 429, 500, 502, 503, 504) or attempt == self.retries:
                    raise PublishError(f"Event Hubs send failed (HTTP {status})", attempts=attempt + 1,
                                       code="EventHubsHttpError", http_status=status) from None
            except (URLError, TimeoutError, OSError):
                if attempt == self.retries:
                    raise PublishError("Event Hubs network failure; retry budget exhausted", attempts=attempt + 1,
                                       code="EventHubsNetworkError") from None
            time.sleep(min(2 ** attempt, 10))
        raise PublishError("Event Hubs retry budget exhausted")

    def close(self) -> None:
        pass


class KafkaSender:
    def __init__(self, env: Mapping[str, str], timeout: float = 15, retries: int = 3) -> None:
        bootstrap = env.get("TELEMETRY_KAFKA_BOOTSTRAP_SERVERS", "")
        self.topic = env.get("TELEMETRY_KAFKA_TOPIC", "")
        protocol = env.get("TELEMETRY_KAFKA_SECURITY_PROTOCOL", "")
        if not bootstrap or not self.topic or protocol not in ("SSL", "SASL_SSL", "PLAINTEXT"):
            raise ValueError("Kafka requires bootstrap servers, topic and explicit SSL/SASL_SSL/PLAINTEXT protocol")
        config: dict[str, Any] = {
            "bootstrap_servers": bootstrap.split(","), "security_protocol": protocol,
            "acks": "all", "retries": 0, "max_block_ms": int(timeout * 1000),
            "request_timeout_ms": max(1000, int(timeout * 1000)),
            "buffer_memory": 4 * 1024 * 1024, "max_in_flight_requests_per_connection": 1,
            "value_serializer": lambda row: json.dumps(row, separators=(",", ":")).encode("utf-8"),
        }
        if protocol == "SASL_SSL":
            for source, target in (
                ("TELEMETRY_KAFKA_SASL_MECHANISM", "sasl_mechanism"),
                ("TELEMETRY_KAFKA_USERNAME", "sasl_plain_username"),
                ("TELEMETRY_KAFKA_PASSWORD", "sasl_plain_password"),
            ):
                if not env.get(source):
                    raise ValueError("SASL_SSL requires mechanism, username and password")
                config[target] = env[source]
        elif any(env.get(name) for name in (
            "TELEMETRY_KAFKA_SASL_MECHANISM", "TELEMETRY_KAFKA_USERNAME", "TELEMETRY_KAFKA_PASSWORD",
        )):
            raise ValueError("Kafka SASL credentials require SASL_SSL")
        if env.get("TELEMETRY_KAFKA_CA_FILE"):
            config["ssl_cafile"] = env["TELEMETRY_KAFKA_CA_FILE"]
        try:
            kafka = importlib.import_module("kafka")
        except ImportError:
            raise PublishError("Kafka transport requires optional kafka-python>=2.2.15,<3",
                               code="KafkaDependencyMissing") from None
        self.kafka_error = kafka.errors.KafkaError
        try:
            self.producer = kafka.KafkaProducer(**config)
        except (self.kafka_error, OSError, ValueError, TypeError):
            raise PublishError("Kafka initialization failed; inspect broker/auth configuration privately",
                               code="KafkaInitializationError") from None
        self.timeout, self.retries = timeout, retries

    def send(self, row: Telemetry) -> int:
        key = f"{row['Source']}|{row['UnitNum']}|{row['Name']}".encode("utf-8")
        for attempt in range(self.retries + 1):
            try:
                self.producer.send(self.topic, key=key, value=row).get(timeout=self.timeout)
                return attempt + 1
            except self.kafka_error as error:
                if not getattr(error, "retriable", False) or attempt == self.retries:
                    raise PublishError("Kafka send failed; retry budget exhausted or non-retriable error",
                                       attempts=attempt + 1, code="KafkaSendError") from None
                time.sleep(min(2 ** attempt, 10))
        raise PublishError("Kafka retry budget exhausted")

    def close(self) -> None:
        try:
            self.producer.close(timeout=self.timeout)
        except self.kafka_error:
            raise PublishError("Kafka close failed", code="KafkaCloseError") from None


class StdoutSender:
    def send(self, row: Telemetry) -> int:
        print(json.dumps(row, separators=(",", ":")), flush=True)
        return 1

    def close(self) -> None:
        pass


@dataclass
class PublishSummary:
    Attempted: int = 0
    Accepted: int = 0
    Failed: int = 0
    Retries: int = 0
    MaxInFlight: int = 0
    ElapsedSeconds: float = 0
    AchievedEventsPerSecond: float = 0
    Aborted: bool = False
    FirstFailure: FailureDetail | None = None


def publish(
    rows: Iterable[Telemetry], sender: Sender, *, rate: float = 10,
    concurrency: int = 1, limit: int = 3000,
) -> PublishSummary:
    positive_config(rate, concurrency, 15, 0)
    if limit <= 0:
        raise ValueError("Publish limit must be positive")
    summary = PublishSummary()
    pending: set[Future[int]] = set()
    began = time.monotonic()

    def record_failure(error: PublishError) -> None:
        summary.Aborted = True
        if summary.FirstFailure is None:
            summary.FirstFailure = error.detail

    def collect(done: set[Future[int]]) -> None:
        for future in done:
            if future.cancelled():
                summary.Failed += 1
                summary.Aborted = True
                continue
            try:
                attempts = future.result()
                summary.Accepted += 1
                summary.Retries += attempts - 1
            except PublishError as error:
                summary.Failed += 1
                summary.Retries += error.attempts - 1
                record_failure(error)
            except (OSError, ValueError, TypeError, RuntimeError):
                summary.Failed += 1
                record_failure(PublishError("Sender failed", code="SendError"))

    try:
        with ThreadPoolExecutor(max_workers=concurrency) as executor:
            try:
                for sequence, row in enumerate(itertools.islice(rows, limit)):
                    if len(pending) >= concurrency:
                        done, pending = wait(pending, return_when=FIRST_COMPLETED)
                        collect(done)
                        if summary.Aborted:
                            break
                    time.sleep(max(0, sequence / rate - (time.monotonic() - began)))
                    pending.add(executor.submit(sender.send, row))
                    summary.Attempted += 1
                    summary.MaxInFlight = max(summary.MaxInFlight, len(pending))
            except (OSError, ValueError, TypeError):
                record_failure(PublishError("Input read failed", code="InputError"))
            finally:
                if summary.Aborted:
                    for future in pending:
                        future.cancel()
                if pending:
                    done, _ = wait(pending)
                    collect(done)
    finally:
        try:
            sender.close()
        except PublishError as error:
            record_failure(error)
        except (OSError, ValueError, TypeError, RuntimeError):
            record_failure(PublishError("Sender close failed", code="CloseError"))
        summary.ElapsedSeconds = round(time.monotonic() - began, 6)
        summary.AchievedEventsPerSecond = round(summary.Accepted / max(summary.ElapsedSeconds, 0.000001), 3)
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--transport", choices=("stdout", "kafka", "eventhubs-rest"), default="stdout")
    parser.add_argument("--input", type=Path)
    parser.add_argument("--count", type=int, default=3000)
    parser.add_argument("--rate", type=float, default=10)
    parser.add_argument("--concurrency", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=15)
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--start", type=parse_time)
    parser.add_argument("--scenario", action="store_true")
    args = parser.parse_args()
    try:
        positive_config(args.rate, args.concurrency, args.timeout, args.retries)
        if args.count <= 0:
            raise ValueError("Count must be positive")
        if args.transport == "stdout" and args.concurrency != 1:
            raise ValueError("Stdout requires concurrency 1 to retain deterministic ordering")
        sender: Sender
        if args.transport == "kafka":
            sender = KafkaSender(os.environ, args.timeout, args.retries)
        elif args.transport == "eventhubs-rest":
            sender = EventHubsRestSender(os.environ, args.timeout, args.retries)
        else:
            sender = StdoutSender()
        rows = read_ndjson(args.input) if args.input else iter_live(
            args.count, seed=args.seed, start=args.start or datetime.now(timezone.utc),
            rate=args.rate, scenario=args.scenario,
        )
        summary = publish(rows, sender, rate=args.rate, concurrency=args.concurrency, limit=args.count)
        print(json.dumps(asdict(summary)), file=sys.stderr)
        if summary.Aborted or summary.Failed:
            raise SystemExit(1)
    except PublishError as error:
        print(json.dumps(asdict(PublishSummary(Aborted=True, FirstFailure=error.detail))), file=sys.stderr)
        raise SystemExit(1) from None
    except ValueError:
        error = PublishError("Invalid configuration", code="InvalidConfiguration")
        print(json.dumps(asdict(PublishSummary(Aborted=True, FirstFailure=error.detail))), file=sys.stderr)
        raise SystemExit(1) from None


if __name__ == "__main__":
    main()
