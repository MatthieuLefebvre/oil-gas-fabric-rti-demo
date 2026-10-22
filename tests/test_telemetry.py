"""Focused offline acceptance; no live resources or optional dependencies needed."""

from __future__ import annotations

import csv
import hashlib
import hmac
import io
import json
import math
import unittest
from contextlib import redirect_stderr, redirect_stdout
from dataclasses import asdict
from datetime import timedelta
from pathlib import Path
from unittest.mock import MagicMock, patch
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, quote

from simulator import publish as transport
from simulator.telemetry import (
    AS_OF, FIELDS, ROOT, build_record, canonical_time, fingerprint,
    fixture_summary, iter_fixture, iter_live, load_measurements, parse_time,
    read_ndjson, validate_record, write_corpus,
)

EXPECTED = {
    "Raw": 147, "ParseValid": 141, "ParseInvalid": 6, "Unknown": 5,
    "Future": 4, "Eligible": 132, "Deduplicated": 120, "High": 10,
    "Late": 8, "Replay": 12,
}


class RegistryTests(unittest.TestCase):
    def test_registry_structure_and_scoped_keys(self) -> None:
        def read(name: str) -> list[dict[str, str]]:
            with (ROOT / "data" / name).open(encoding="utf-8", newline="") as stream:
                return list(csv.DictReader(stream))

        assets = read("assets.csv")
        measurements = load_measurements()
        relationships = read("relationships.csv")
        self.assertEqual(len(assets), 14)
        self.assertEqual(len(measurements), 12)
        self.assertEqual(len(relationships), 24)
        ids = {row["AssetId"] for row in assets}
        all_ids = ids | {row.MeasurementId for row in measurements}
        self.assertEqual(len(all_ids), 26)
        self.assertEqual(len({row.key for row in measurements}), 12)
        self.assertEqual(len({row["RelationshipId"] for row in relationships}), 24)
        for row in assets:
            self.assertTrue(not row["ParentAssetId"] or row["ParentAssetId"] in ids)
        for row in measurements:
            self.assertIn(row.AssetId, ids)
            self.assertEqual(sum(edge["ToId"] == row.MeasurementId for edge in relationships), 1)
        for edge in relationships:
            self.assertIn(edge["FromId"], all_ids)
            self.assertIn(edge["ToId"], all_ids)
        for kind, count in {"Site": 2, "Battery": 2, "System": 2, "Compressor": 4, "Component": 4}.items():
            self.assertEqual(sum(row["AssetType"] == kind for row in assets), count)
        scoped = [row for row in measurements if row.UnitNum == "1" and row.MeasurementType == "DischargePressure"]
        self.assertEqual(len(scoped), 2)
        self.assertNotEqual(scoped[0].Name, scoped[1].Name)


class GeneratorTests(unittest.TestCase):
    def test_exact_acceptance(self) -> None:
        self.assertEqual(fixture_summary(iter_fixture()), EXPECTED)

    def test_late_arrival_order_and_exact_replays(self) -> None:
        rows = list(iter_fixture())
        self.assertTrue(all(validate_record(row).Late for row in rows[112:120]))
        self.assertTrue(all(not validate_record(row).Late for row in rows[:112]))
        self.assertLess(parse_time(rows[112]["RecordDateTimeUTC"]), parse_time(rows[111]["RecordDateTimeUTC"]))
        self.assertEqual(rows[120:128], rows[112:120])
        self.assertEqual(rows[128:132], rows[:4])

    def test_determinism_and_wire_contract(self) -> None:
        self.assertEqual(list(iter_fixture()), list(iter_fixture()))
        self.assertNotEqual(list(iter_fixture(seed=4)), list(iter_fixture(seed=5)))
        registry = {row.key for row in load_measurements()}
        for row in iter_live(3000, start=AS_OF):
            self.assertEqual(set(row), set(FIELDS))
            self.assertIsInstance(row["Value"], str)
            self.assertIsNone(row["IngestionTime"])
            self.assertIn((row["Source"], row["UnitNum"], row["Name"]), registry)
            self.assertTrue(validate_record(row).ParseValid)
            self.assertEqual(parse_time(row["RecordDateTime"]), parse_time(row["RecordDateTimeUTC"]))

    def test_transition_and_comparator(self) -> None:
        measurements = load_measurements()
        baseline = list(iter_fixture())[:120]
        target = [float(row["Value"]) for row in sorted(baseline, key=lambda row: row["RecordDateTimeUTC"])
                  if row["Name"] == measurements[0].Name]
        self.assertEqual(len(target), 20)
        self.assertTrue(all(110 <= value <= 120 for value in target[:5]))
        self.assertTrue(all(value > 140 for value in target[5:15]))
        self.assertTrue(all(value < 135 for value in target[15:]))
        comparator = [float(row["Value"]) for row in baseline if row["Name"] == measurements[6].Name]
        self.assertTrue(comparator)
        self.assertTrue(all(110 <= value <= 120 for value in comparator))

    def test_live_profiles_and_bounds(self) -> None:
        live = list(iter_live(240, start=AS_OF, rate=10))
        scenario = list(iter_live(240, start=AS_OF, rate=10, scenario=True))
        self.assertFalse(any(float(row["Value"]) > 140 for row in live))
        self.assertEqual(sum(float(row["Value"]) > 140 for row in scenario), 10)
        self.assertEqual(len(live), 240)
        for count, rate in [(0, 10), (1, 0), (1, math.inf), (-1, 10)]:
            with self.assertRaises(ValueError):
                list(iter_live(count, rate=rate))

    def test_checked_in_fixture_hash_and_manifest(self) -> None:
        directory = ROOT / "tests" / "fixtures"
        manifest = json.loads((directory / "scenario-manifest.json").read_text(encoding="utf-8"))
        corpus = (directory / "telemetry.ndjson").read_bytes()
        self.assertEqual(manifest["Expected"], EXPECTED)
        self.assertEqual(manifest["CorpusSha256"], hashlib.sha256(corpus).hexdigest())
        self.assertEqual(manifest["CorpusBytes"], len(corpus))
        self.assertEqual(manifest["Count"], 147)
        self.assertEqual(fixture_summary(read_ndjson(directory / "telemetry.ndjson")), EXPECTED)
        self.assertEqual(list(read_ndjson(directory / "telemetry.ndjson")), list(iter_fixture()))

    def test_manifest_stream_writer_without_disk(self) -> None:
        directory = MagicMock(spec=Path)
        byte_stream = io.BytesIO()
        byte_stream.close = lambda: None
        directory.__truediv__.return_value.open.return_value = byte_stream
        manifest = write_corpus(iter_live(2, start=AS_OF), directory, start=AS_OF)
        self.assertEqual(manifest["Count"], 2)
        self.assertEqual(manifest["CorpusSha256"], hashlib.sha256(byte_stream.getvalue()).hexdigest())


class ValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.row = next(row for row in iter_fixture() if validate_record(row).Late)

    def test_fingerprint_matches_compact_array_and_utc_normalization(self) -> None:
        expected_values = [
            self.row["Source"], self.row["UnitNum"], self.row["Name"],
            canonical_time(self.row["RecordDateTimeUTC"]), canonical_time(self.row["RecordAdded"]),
            self.row["Value"],
        ]
        expected = hashlib.sha256(json.dumps(expected_values, separators=(",", ":")).encode()).hexdigest()
        self.assertEqual(fingerprint(self.row), expected)
        changed = self.row.copy()
        changed["RecordDateTimeUTC"] = parse_time(changed["RecordDateTimeUTC"]).astimezone(
            parse_time("2026-10-20T00:00:00-06:00").tzinfo
        ).isoformat()
        changed["ProcessedDate"] = None
        changed["IngestionTime"] = "2026-10-20T12:01:00Z"
        self.assertEqual(fingerprint(changed), fingerprint(self.row))
        self.assertEqual(canonical_time("2026-10-20T06:00:00-06:00"), "2026-10-20T12:00:00.0000000Z")
        changed["Value"] = "115.0"
        self.assertNotEqual(fingerprint(changed), fingerprint(self.row))

    def test_invalids_do_not_become_zero(self) -> None:
        for value in ["NaN", "Infinity", "1e999", "", "not-a-number", None, 115]:
            changed = dict(self.row, Value=value)
            result = validate_record(changed)
            self.assertFalse(result.ParseValid)
            self.assertIn("InvalidValue", result.Reasons)
        for field, value in [("UnitNum", ""), ("Source", None), ("RecordDateTimeUTC", "bad"),
                             ("RecordAdded", "2026-10-20"), ("ProcessedDate", "bad")]:
            result = validate_record(dict(self.row, **{field: value}))
            self.assertFalse(result.ParseValid)
            self.assertIn(f"Invalid{field}", result.Reasons)
        self.assertFalse(validate_record(dict(self.row, Extra="not-allowed")).ParseValid)

    def test_unknown_future_late_negative_and_optional_nulls(self) -> None:
        unknown = validate_record(dict(self.row, Name="malformed.path"))
        self.assertTrue(unknown.ParseValid)
        self.assertTrue(unknown.UnknownTag)
        measurement = load_measurements()[0]
        self.assertFalse(validate_record(build_record(measurement, AS_OF + timedelta(seconds=30), "110")).Future)
        self.assertTrue(validate_record(build_record(measurement, AS_OF + timedelta(seconds=31), "110")).Future)
        self.assertTrue(validate_record(self.row).Late)
        negative = build_record(measurement, AS_OF, "110", AS_OF - timedelta(seconds=5))
        self.assertTrue(validate_record(negative).NegativeSourceLatency)
        negative["ProcessedDate"] = None
        self.assertTrue(validate_record(negative).ParseValid)

    def test_equal_time_conflicts_remain_distinct(self) -> None:
        changed = dict(self.row, Value="999.0")
        self.assertEqual(changed["RecordDateTimeUTC"], self.row["RecordDateTimeUTC"])
        self.assertNotEqual(fingerprint(changed), fingerprint(self.row))
        self.assertEqual(fixture_summary([])["Deduplicated"], 0)

    def test_unretained_timestamp_precision_rejected(self) -> None:
        with self.assertRaises(ValueError):
            parse_time("2026-10-20T12:00:00.1234567Z")
        self.assertEqual(canonical_time("2026-10-20T12:00:00.1234560Z"), "2026-10-20T12:00:00.1234560Z")


class PublishingTests(unittest.TestCase):
    def test_bounded_finite_and_retry_summary(self) -> None:
        sender = MagicMock()
        sender.send.return_value = 2
        summary = transport.publish(iter_live(100, start=AS_OF), sender, rate=100000, concurrency=3, limit=17)
        self.assertEqual(summary.Attempted, 17)
        self.assertEqual(summary.Accepted, 17)
        self.assertEqual(summary.Retries, 17)
        self.assertIsNone(summary.FirstFailure)
        self.assertLessEqual(summary.MaxInFlight, 3)
        self.assertFalse(summary.Aborted)
        sender.close.assert_called_once()

    def test_abort_failure_no_secret_output(self) -> None:
        sender = MagicMock()
        sender.send.side_effect = transport.PublishError("secret-example-never-report", attempts=3)
        output = io.StringIO()
        with redirect_stdout(output), redirect_stderr(output):
            summary = transport.publish(iter_live(100), sender, rate=100000, concurrency=1)
        self.assertTrue(summary.Aborted)
        self.assertEqual(summary.Failed, 1)
        self.assertEqual(summary.Attempted, 1)
        self.assertEqual(summary.Retries, 2)
        self.assertNotIn("secret-example", output.getvalue())
        self.assertEqual(summary.FirstFailure.Code, "PublishFailed")
        self.assertNotIn("secret-example", json.dumps(asdict(summary)))

    def test_input_error_aborts_and_closes(self) -> None:
        def broken():
            raise ValueError("payload or secret must not leak")
            yield
        sender = MagicMock()
        summary = transport.publish(broken(), sender)
        self.assertTrue(summary.Aborted)
        self.assertEqual(summary.FirstFailure.Code, "InputError")
        sender.close.assert_called_once()

    def test_failure_details_allowlist_and_first_failure_survives_cleanup(self) -> None:
        sender = MagicMock()
        sender.send.side_effect = transport.PublishError(
            "Bearer secret-example from https://private.invalid",
            code="EventHubsHttpError", http_status=401, attempts=3,
        )
        sender.close.side_effect = transport.PublishError("cleanup secret", code="KafkaCloseError")
        summary = transport.publish(iter_live(100), sender, rate=100000)
        self.assertEqual(asdict(summary)["FirstFailure"], {
            "Code": "EventHubsHttpError", "Message": "Event Hubs rejected the request",
            "HttpStatus": 401, "Attempts": 3,
        })
        self.assertEqual(summary.Retries, 2)
        serialized = json.dumps(asdict(summary))
        self.assertNotIn("secret", serialized)
        self.assertNotIn("private.invalid", serialized)
        invalid = transport.PublishError("secret", code="secret-code", http_status="secret-status", attempts="secret")
        self.assertEqual(invalid.detail.Code, "PublishFailed")
        self.assertIsNone(invalid.detail.HttpStatus)
        self.assertEqual(invalid.detail.Attempts, 1)

    def test_sender_runtime_and_cleanup_errors_have_distinct_safe_codes(self) -> None:
        sender = MagicMock()
        sender.send.side_effect = OSError("PRIVATE-ENDPOINT-DO-NOT-PRINT")
        summary = transport.publish(iter_live(1), sender, rate=100000)
        self.assertEqual(summary.FirstFailure.Code, "SendError")
        self.assertNotIn("PRIVATE-ENDPOINT-DO-NOT-PRINT", json.dumps(asdict(summary)))
        sender = MagicMock()
        sender.send.return_value = 1
        sender.close.side_effect = OSError("PRIVATE-ENDPOINT-DO-NOT-PRINT")
        summary = transport.publish(iter_live(1), sender, rate=100000)
        self.assertEqual(summary.FirstFailure.Code, "CloseError")
        self.assertTrue(summary.Aborted)
        self.assertNotIn("PRIVATE-ENDPOINT-DO-NOT-PRINT", json.dumps(asdict(summary)))

    def test_programming_errors_are_not_silently_swallowed(self) -> None:
        sender = MagicMock()
        sender.send.side_effect = AssertionError("implementation bug")
        with self.assertRaises(AssertionError):
            transport.publish(iter_live(1), sender, rate=100000)
        sender.close.assert_called_once()

    def test_cli_reports_http_status_without_response_or_credentials(self) -> None:
        stdout, stderr = io.StringIO(), io.StringIO()
        env = {"TELEMETRY_EVENTHUB_RESOURCE_URI": "https://private.invalid/demo",
               "TELEMETRY_EVENTHUB_BEARER_TOKEN": "secret-token"}
        error = HTTPError("https://private.invalid?token=secret-token", 401,
                          "secret-response", {}, io.BytesIO(b"secret-response"))
        with patch.object(transport.sys, "argv", [
            "publish", "--transport", "eventhubs-rest", "--count", "4", "--rate", "100000",
        ]), patch.dict(transport.os.environ, env, clear=True), \
                patch.object(transport, "build_opener") as opener, \
                redirect_stdout(stdout), redirect_stderr(stderr):
            opener.return_value.open.side_effect = error
            with self.assertRaises(SystemExit) as caught:
                transport.main()
        self.assertEqual(caught.exception.code, 1)
        self.assertEqual(stdout.getvalue(), "")
        result = json.loads(stderr.getvalue())
        self.assertTrue(result["Aborted"])
        self.assertEqual(result["FirstFailure"]["Code"], "EventHubsHttpError")
        self.assertEqual(result["FirstFailure"]["HttpStatus"], 401)
        self.assertEqual(result["FirstFailure"]["Attempts"], 1)
        self.assertNotIn("secret", stderr.getvalue())
        self.assertNotIn("private.invalid", stderr.getvalue())

    def test_cli_configuration_error_is_structured_and_sanitized(self) -> None:
        stderr = io.StringIO()
        with patch.object(transport.sys, "argv", ["publish", "--transport", "eventhubs-rest"]), \
                patch.dict(transport.os.environ, {"TELEMETRY_EVENTHUB_CONNECTION_STRING": "secret"}, clear=True), \
                redirect_stderr(stderr):
            with self.assertRaises(SystemExit):
                transport.main()
        result = json.loads(stderr.getvalue())
        self.assertEqual(result["FirstFailure"]["Code"], "InvalidConfiguration")
        self.assertNotIn("secret", stderr.getvalue())

    def test_finite_limits(self) -> None:
        for rate, concurrency, timeout, retries in [
            (0, 1, 15, 3), (math.nan, 1, 15, 3), (1, 65, 15, 3),
            (1, 1, 0, 3), (1, 1, 15, 9),
        ]:
            with self.assertRaises(ValueError):
                transport.positive_config(rate, concurrency, timeout, retries)

    def test_eventhubs_sas_matches_official_utf8_key_signing(self) -> None:
        uri = "https://example.invalid/demo"
        token = transport.sas_token(uri, "send", "ZmFrZS1rZXk=", 1000)
        parsed = parse_qs(token.removeprefix("SharedAccessSignature "))
        import base64
        signature = base64.b64encode(hmac.new(
            b"ZmFrZS1rZXk=", (quote(uri, safe="") + "\n1000").encode(), hashlib.sha256
        ).digest()).decode()
        self.assertEqual(parsed["sig"], [signature])
        self.assertEqual(parsed["sr"], [uri])
        env = {"TELEMETRY_EVENTHUB_CONNECTION_STRING":
               "Endpoint=sb://example.invalid/;EntityPath=demo;SharedAccessKeyName=send;SharedAccessKey=ZmFrZS1rZXk="}
        resource, authorize = transport.eventhubs_auth(env)
        self.assertEqual(resource, uri)
        self.assertTrue(authorize().startswith("SharedAccessSignature "))

    def test_eventhubs_auth_and_endpoint_guards(self) -> None:
        for uri in ["http://example.invalid/demo", "https://u:p@example.invalid/demo",
                    "https://example.invalid", "https://example.invalid/demo?token=secret",
                    "https://example.invalid/demo/messages"]:
            with self.assertRaises(ValueError):
                transport.resource_uri(uri)
        with self.assertRaises(ValueError):
            transport.eventhubs_auth({})
        env = {"TELEMETRY_EVENTHUB_RESOURCE_URI": "https://example.invalid/demo",
               "TELEMETRY_EVENTHUB_BEARER_TOKEN": "fake-token"}
        self.assertEqual(transport.eventhubs_auth(env)[1](), "Bearer fake-token")
        with self.assertRaises(ValueError):
            transport.eventhubs_auth(dict(env, TELEMETRY_EVENTHUB_SAS_TOKEN="SharedAccessSignature fake"))
        with self.assertRaises(ValueError):
            transport.eventhubs_auth(dict(env, TELEMETRY_EVENTHUB_BEARER_TOKEN="fake\r\nsecret"))
        self.assertIsNone(transport.NoRedirect().redirect_request(None, None, 302, "", None, "https://other.invalid"))

    def test_rest_transient_retry_and_permanent_failure_sanitized(self) -> None:
        env = {"TELEMETRY_EVENTHUB_RESOURCE_URI": "https://example.invalid/demo",
               "TELEMETRY_EVENTHUB_BEARER_TOKEN": "fake"}
        sender = transport.EventHubsRestSender(env, retries=1)
        response = MagicMock()
        response.__enter__.return_value.status = 201
        row = next(iter_fixture())
        error = HTTPError("https://example.invalid", 429, "secret", {}, None)
        with patch.object(transport, "build_opener") as opener, patch.object(transport.time, "sleep"):
            opener.return_value.open.side_effect = [error, response]
            self.assertEqual(sender.send(row), 2)
        with patch.object(transport, "build_opener") as opener:
            opener.return_value.open.side_effect = HTTPError("secret", 401, "secret", {}, None)
            with self.assertRaisesRegex(transport.PublishError, r"HTTP 401") as caught:
                sender.send(row)
            self.assertNotIn("secret", str(caught.exception))
        with patch.object(transport, "build_opener") as opener, patch.object(transport.time, "sleep"):
            opener.return_value.open.side_effect = URLError("secret")
            with self.assertRaises(transport.PublishError):
                sender.send(row)
            self.assertEqual(opener.return_value.open.call_count, 2)
        with patch.object(transport, "build_opener") as opener, patch.object(transport.time, "sleep"):
            opener.return_value.open.side_effect = HTTPError("secret", 503, "secret", {}, None)
            summary = transport.publish([row], sender, rate=100000)
            self.assertEqual(summary.FirstFailure.Code, "EventHubsHttpError")
            self.assertEqual(summary.FirstFailure.HttpStatus, 503)
            self.assertEqual(summary.FirstFailure.Attempts, 2)
            self.assertEqual(summary.Retries, 1)

    def test_kafka_explicit_config_and_optional_dependency(self) -> None:
        with self.assertRaises(ValueError):
            transport.KafkaSender({})
        env = {"TELEMETRY_KAFKA_BOOTSTRAP_SERVERS": "example.invalid:9093",
               "TELEMETRY_KAFKA_TOPIC": "synthetic", "TELEMETRY_KAFKA_SECURITY_PROTOCOL": "SSL"}
        with patch.object(transport.importlib, "import_module", side_effect=ImportError):
            with self.assertRaisesRegex(transport.PublishError, "optional kafka-python"):
                transport.KafkaSender(env)
        with self.assertRaises(ValueError):
            transport.KafkaSender(dict(env, TELEMETRY_KAFKA_SECURITY_PROTOCOL="SASL_SSL"))
        with self.assertRaises(ValueError):
            transport.KafkaSender(dict(env, TELEMETRY_KAFKA_SECURITY_PROTOCOL="PLAINTEXT",
                                       TELEMETRY_KAFKA_PASSWORD="secret"))
        module = MagicMock()
        module.errors.KafkaError = RuntimeError
        with patch.object(transport.importlib, "import_module", return_value=module):
            sender = transport.KafkaSender(env)
            self.assertEqual(sender.send(next(iter_fixture())), 1)
            sender.close()
            self.assertEqual(module.KafkaProducer.call_args.kwargs["buffer_memory"], 4 * 1024 * 1024)
            module.KafkaProducer.return_value.send.side_effect = RuntimeError("secret-broker-detail")
            summary = transport.publish([next(iter_fixture())], sender, rate=100000)
            self.assertEqual(summary.FirstFailure.Code, "KafkaSendError")
            self.assertNotIn("secret-broker-detail", json.dumps(asdict(summary)))

    def test_stdout_cli_has_only_wire_records(self) -> None:
        stdout, stderr = io.StringIO(), io.StringIO()
        with patch.object(transport.sys, "argv", ["publish", "--count", "2", "--rate", "10000"]), \
                redirect_stdout(stdout), redirect_stderr(stderr):
            transport.main()
        rows = [json.loads(line) for line in stdout.getvalue().splitlines()]
        self.assertEqual(len(rows), 2)
        self.assertEqual(set(rows[0]), set(FIELDS))
        self.assertEqual(json.loads(stderr.getvalue())["Accepted"], 2)


if __name__ == "__main__":
    unittest.main()
