"""Deterministic nine-field generation and reference quality validation."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import random
import re
import sys
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable, Iterator, Mapping, TypedDict

ROOT = Path(__file__).resolve().parent.parent
AS_OF = datetime(2026, 10, 20, 12, tzinfo=timezone.utc)
FIELDS = (
    "RecordDateTime", "RecordDateTimeUTC", "UnitNum", "Source", "Name",
    "Value", "RecordAdded", "ProcessedDate", "IngestionTime",
)
NUMERIC = re.compile(r"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$")


class Telemetry(TypedDict):
    RecordDateTime: str
    RecordDateTimeUTC: str
    UnitNum: str
    Source: str
    Name: str
    Value: str
    RecordAdded: str
    ProcessedDate: str | None
    IngestionTime: str | None


@dataclass(frozen=True)
class Measurement:
    MeasurementId: str
    AssetId: str
    Source: str
    UnitNum: str
    Name: str
    MeasurementType: str
    Unit: str
    HighThreshold: str
    RecoveryThreshold: str
    NominalMin: str
    NominalMax: str

    @property
    def key(self) -> tuple[str, str, str]:
        return self.Source, self.UnitNum, self.Name


def load_measurements(path: Path = ROOT / "data" / "measurements.csv") -> tuple[Measurement, ...]:
    with path.open(encoding="utf-8", newline="") as stream:
        return tuple(Measurement(**row) for row in csv.DictReader(stream))


def parse_time(value: object) -> datetime:
    if not isinstance(value, str):
        raise ValueError("Timestamp must be a string")
    # datetime truncates sub-microsecond precision; reject precision we cannot retain.
    match = re.search(r"\.(\d+)", value)
    if match and (len(match[1]) > 7 or (len(match[1]) == 7 and match[1][-1] != "0")):
        raise ValueError("Timestamp precision exceeds Python microseconds")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("Timestamp requires explicit offset")
    return parsed.astimezone(timezone.utc)


def timestamp(value: datetime) -> str:
    if value.tzinfo is None:
        raise ValueError("Timestamp requires explicit offset")
    return value.astimezone(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def canonical_time(value: object) -> str:
    return parse_time(value).strftime("%Y-%m-%dT%H:%M:%S.%f") + "0Z"


def fingerprint(row: Mapping[str, object]) -> str:
    values = [
        row["Source"], row["UnitNum"], row["Name"],
        canonical_time(row["RecordDateTimeUTC"]), canonical_time(row["RecordAdded"]), row["Value"],
    ]
    return hashlib.sha256(json.dumps(values, ensure_ascii=False, separators=(",", ":")).encode("utf-8")).hexdigest()


def build_record(
    measurement: Measurement, event_time: datetime, value: str,
    added: datetime | None = None,
) -> Telemetry:
    added = added if added is not None else event_time + timedelta(seconds=2)
    return {
        "RecordDateTime": event_time.astimezone(timezone(timedelta(hours=-6))).isoformat(timespec="microseconds"),
        "RecordDateTimeUTC": timestamp(event_time),
        "UnitNum": measurement.UnitNum, "Source": measurement.Source, "Name": measurement.Name,
        "Value": value, "RecordAdded": timestamp(added),
        "ProcessedDate": timestamp(added + timedelta(seconds=1)), "IngestionTime": None,
    }


def synthetic_value(measurement: Measurement, rng: random.Random, high: bool = False) -> str:
    if high and measurement.HighThreshold:
        threshold = float(measurement.HighThreshold)
        return f"{rng.uniform(threshold + 5, threshold + 15):.3f}"
    return f"{rng.uniform(float(measurement.NominalMin), float(measurement.NominalMax)):.3f}"


def iter_live(
    count: int, *, seed: int = 42, start: datetime | None = None,
    rate: float = 10.0, scenario: bool = False,
) -> Iterator[Telemetry]:
    if count <= 0 or not math.isfinite(rate) or rate <= 0:
        raise ValueError("Count and finite rate must be positive")
    measurements = load_measurements()
    rng = random.Random(seed)
    start = start if start is not None else datetime.now(timezone.utc)
    for sequence in range(count):
        measurement = measurements[sequence % len(measurements)]
        cycle = sequence // len(measurements)
        high = scenario and measurement.MeasurementId == "MSR-A1-DP" and 5 <= cycle % 20 < 15
        yield build_record(measurement, start + timedelta(seconds=sequence / rate), synthetic_value(measurement, rng, high))


def iter_fixture(seed: int = 42, as_of: datetime = AS_OF) -> Iterator[Telemetry]:
    measurements = load_measurements()
    rng = random.Random(seed)
    # Twenty target observations provide normal, ten high, then recovery.
    slots = [measurements[0]] * 20 + list(measurements[1:]) * 9 + [measurements[1]]
    replay: list[Telemetry] = []
    late_rows: list[Telemetry] = []
    for sequence, measurement in enumerate(slots):
        event_time = as_of - timedelta(minutes=10) + timedelta(seconds=4 * sequence)
        late = as_of - timedelta(seconds=90) if sequence < 8 else None
        row = build_record(measurement, event_time, synthetic_value(measurement, rng, 5 <= sequence < 15), late)
        if sequence < 12:
            replay.append(row.copy())
        if sequence < 8:
            late_rows.append(row)
        else:
            yield row
    yield from late_rows
    yield from replay
    for sequence in range(6):
        row = build_record(measurements[0], as_of - timedelta(seconds=20 + sequence), "115.000")
        if sequence < 3:
            row["RecordDateTimeUTC"] = "invalid-event-time"
        else:
            row["Value"] = "not-a-number"
        yield row
    for sequence in range(5):
        row = build_record(measurements[0], as_of - timedelta(seconds=10 + sequence), "115.000")
        row["Name"] += f".Unknown{sequence}"
        yield row
    for sequence in range(4):
        yield build_record(measurements[0], as_of + timedelta(minutes=2, seconds=sequence), "115.000")


@dataclass(frozen=True)
class Validation:
    Reasons: tuple[str, ...]
    UnknownTag: bool = False
    Future: bool = False
    Late: bool = False
    NegativeSourceLatency: bool = False
    Value: float | None = None

    @property
    def ParseValid(self) -> bool:
        return not self.Reasons


def validate_record(
    row: Mapping[str, object], *, as_of: datetime = AS_OF,
    registry: tuple[Measurement, ...] | None = None, future_tolerance: float = 30,
) -> Validation:
    reasons: list[str] = []
    if set(row) != set(FIELDS):
        reasons.append("InvalidFields")
    for field in ("Source", "UnitNum", "Name"):
        if not isinstance(row.get(field), str) or not str(row.get(field)).strip():
            reasons.append(f"Invalid{field}")
    times: dict[str, datetime] = {}
    for field in ("RecordDateTime", "RecordDateTimeUTC", "RecordAdded", "ProcessedDate", "IngestionTime"):
        if row.get(field) is None and field in ("ProcessedDate", "IngestionTime"):
            continue
        try:
            times[field] = parse_time(row.get(field))
        except (ValueError, TypeError, OverflowError):
            reasons.append(f"Invalid{field}")
    value = row.get("Value")
    numeric: float | None = None
    if isinstance(value, str) and NUMERIC.fullmatch(value):
        numeric = float(value)
    if numeric is None or not math.isfinite(numeric):
        reasons.append("InvalidValue")
    if reasons:
        return Validation(tuple(reasons))
    registry = registry if registry is not None else load_measurements()
    key = row["Source"], row["UnitNum"], row["Name"]
    event = times["RecordDateTimeUTC"]
    latency = (times["RecordAdded"] - event).total_seconds()
    return Validation(
        (), key not in {measurement.key for measurement in registry},
        event > as_of + timedelta(seconds=future_tolerance), latency > 60, latency < 0, numeric,
    )


def fixture_summary(rows: Iterable[Telemetry], as_of: datetime = AS_OF) -> dict[str, int]:
    counts = dict(Raw=0, ParseValid=0, ParseInvalid=0, Unknown=0, Future=0,
                  Eligible=0, Deduplicated=0, High=0, Late=0, Replay=0)
    registry = load_measurements()
    lookup = {measurement.key: measurement for measurement in registry}
    seen: set[str] = set()
    for row in rows:
        counts["Raw"] += 1
        validation = validate_record(row, as_of=as_of, registry=registry)
        counts["ParseValid" if validation.ParseValid else "ParseInvalid"] += 1
        if not validation.ParseValid:
            continue
        counts["Unknown"] += int(validation.UnknownTag)
        counts["Future"] += int(validation.Future)
        if validation.UnknownTag or validation.Future:
            continue
        counts["Eligible"] += 1
        identity = fingerprint(row)
        if identity in seen:
            counts["Replay"] += 1
            continue
        seen.add(identity)
        counts["Deduplicated"] += 1
        counts["Late"] += int(validation.Late)
        measurement = lookup[(row["Source"], row["UnitNum"], row["Name"])]
        if measurement.HighThreshold and validation.Value is not None:
            counts["High"] += int(validation.Value > float(measurement.HighThreshold))
    return counts


def write_corpus(
    rows: Iterable[Telemetry], directory: Path, *, seed: int = 42,
    start: datetime = AS_OF, fixture: bool = False, rate: float = 10,
) -> dict[str, object]:
    directory.mkdir(parents=True, exist_ok=True)
    filename = "telemetry.ndjson"
    digest = hashlib.sha256()
    count = size = 0
    with (directory / filename).open("wb") as stream:
        for row in rows:
            line = (json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
            stream.write(line)
            digest.update(line)
            count += 1
            size += len(line)
    manifest: dict[str, object] = {
        "ContractVersion": 1, "Profile": "Fixture" if fixture else "Live",
        "RunId": str(uuid.uuid5(uuid.NAMESPACE_URL, "synthetic-telemetry:" + digest.hexdigest())),
        "Seed": seed, "AsOf": timestamp(start), "File": filename, "Count": count,
        "EventsPerSecond": rate,
        "CorpusBytes": size, "CorpusSha256": digest.hexdigest(),
        "FingerprintVersion": 1, "FutureToleranceSeconds": 30,
        "ValueWireType": "String", "SyntheticOnly": True,
    }
    if fixture:
        manifest["Expected"] = fixture_summary(read_ndjson(directory / filename), start)
        manifest["LateArrivalSequences"] = list(range(112, 120))
        manifest["ReplaySequences"] = list(range(120, 132))
    manifest_name = "scenario-manifest.json" if fixture else "manifest.json"
    (directory / manifest_name).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def read_ndjson(path: Path) -> Iterator[Telemetry]:
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            yield json.loads(line)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("fixture", "generate", "stdout"))
    parser.add_argument("--output", type=Path, default=ROOT / "tests" / "fixtures")
    parser.add_argument("--count", type=int, default=3000)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--rate", type=float, default=10)
    parser.add_argument("--start", type=parse_time)
    parser.add_argument("--scenario", action="store_true")
    args = parser.parse_args()
    start = args.start or (AS_OF if args.mode == "fixture" else datetime.now(timezone.utc))
    if args.mode == "fixture":
        manifest = write_corpus(iter_fixture(args.seed, start), args.output, seed=args.seed, start=start, fixture=True)
    else:
        rows = iter_live(args.count, seed=args.seed, start=start, rate=args.rate, scenario=args.scenario)
        if args.mode == "stdout":
            began = time.monotonic()
            for sequence, row in enumerate(rows):
                time.sleep(max(0, sequence / args.rate - (time.monotonic() - began)))
                print(json.dumps(row, separators=(",", ":")), flush=True)
            return
        manifest = write_corpus(rows, args.output, seed=args.seed, start=start, rate=args.rate)
    print(json.dumps(manifest, indent=2), file=sys.stderr)


if __name__ == "__main__":
    main()
