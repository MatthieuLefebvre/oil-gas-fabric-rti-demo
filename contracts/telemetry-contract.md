# Synthetic contract

All labels, units, thresholds and operating patterns are fictional demonstrations,
not engineering limits or maintenance advice. Registry lookups use exact
`(Source, UnitNum, Name)` strings; UnitNum and display names are not global IDs.
CSV columns are PascalCase; keys are stable across seeded runs.

The supplied illustrative shape
`Badlands_21x_13/Tank_Battery/Gas_Lift/Compressors/Compressor_1/Performance/Throw_3/DisplayedDiscPress`
maps positionally to Site/Battery/System/collection/Compressor/category/Component/
Measurement. Collection/category path segments are not extra ontology entities.
Generated tags use fictional `Fictional_Aspen` / `Fictional_Birch` prefixes, never
the supplied site label. Compressor-owned suction and vibration omit `Throw_3`.
Every generated `Name` is copied exactly from its registry entry, not heuristically
parsed to infer identity.

The nine-field schema has no event ID. `Value` deliberately differs from plan
4.2: numeric **strings** preserve a stable Eventstream schema, including invalid
nonnumeric strings. Numeric normalization must reject nonfinite values.
`RecordDateTimeUTC` is authoritative event time; `RecordDateTime` preserves the
explicit synthetic -06:00 local offset. `RecordAdded` is source addition time,
`ProcessedDate` is optional source processing time and `IngestionTime` is null.
None of these proves Fabric receipt. Capture actual Eventhouse receipt separately.
Optional timestamps, when present, must parse. Source addition before event time
is a clock-skew diagnostic, not a fabricated correction or silent rejection.

Duplicate fingerprint version 1 is SHA256 of UTF-8 compact JSON array:
`[Source,UnitNum,Name,canonical_event_time,canonical_record_added,Value]`.
Canonical UTC timestamps are `yyyy-MM-ddTHH:mm:ss.fffffffZ` (seven fractional
digits, Python microseconds followed by zero); other fields retain exact strings.
Use KQL `hash_sha256(tostring(pack_array(Source,UnitNum,Name,
strcat(format_datetime(EventTime,"yyyy-MM-dd"),"T",format_datetime(EventTime,"HH:mm:ss.fffffff"),"Z"),
strcat(format_datetime(SourceAdded,"yyyy-MM-dd"),"T",format_datetime(SourceAdded,"HH:mm:ss.fffffff"),"Z"),RawValue)))`.
This ASCII synthetic corpus has no JSON escape ambiguity. Do not stringify a
numeric parsed value instead of the original Value string. Processing and receipt
times are excluded. This is a demo heuristic, not an authoritative event identity.
Preserve raw rows; curated reads alone deduplicate over an explicitly bounded window.
Latest display chooses greatest event time, then greatest fingerprint; conflicting
values at the same scoped key/event time remain flagged as ambiguous. The
tie-break is deterministic display ordering, not source correction precedence.

Validation reports parse rejection, unknown mapping, future (>asOf +30 seconds),
late source addition (>60 seconds), and negative source latency independently.
Missing/blank Source, UnitNum or Name rejects a record. Unknown/malformed paths
are never guessed into assets. No-data and stale state are not zero or healthy.
The fixture intentionally makes parse-invalid/unknown/future groups disjoint.

Fixture reference is 2026-10-20T12:00:00Z: 120 eligible unique baseline readings,
8 late within baseline, 10 high discharge readings on CMP-A1, 12 exact replays,
6 rejects (3 bad event times, 3 nonnumeric values), 5 unknown tags, 4 future rows.
Totals: raw 147, parse-valid 141, known/time-eligible 132, deduplicated 120.
The eight late originals are emitted after the other 112 baseline rows (zero-based
arrival sequences 112..119), preserving out-of-order event-time evidence. Replays
occupy sequences 120..131. Neither sequence is added to the wire payload.
Target pressure transitions normal → ten high observations → recovery; comparator
CMP-B1 remains normal. Live profile omits intentional quality injections.

## Local finite commands

Run from the project root with Python 3.10+:

```
python -m simulator.telemetry fixture --output tests\fixtures
python -m simulator.telemetry generate --output data\generated --count 3000 --seed 42 --start 2026-10-20T12:00:00Z
python -m simulator.telemetry stdout --count 10 --rate 10
python -m simulator.publish --transport stdout --count 10 --rate 10
python -m simulator.publish --transport kafka --count 3000 --rate 10
python -m simulator.publish --transport eventhubs-rest --count 3000 --rate 10
python -m simulator.publish --transport stdout --input tests\fixtures\telemetry.ndjson --rate 250
```

Generated corpora stream directly to NDJSON and a manifest recording seed, bounds,
SHA256 and byte/count totals. Fixed start plus seed reproduces exact bytes; default
live start is current UTC. Replay is line streamed; publish count caps replay rows.
Publish is finite, bounded in-flight, timeout-limited and aborts explicitly on
failure. Summaries go to stderr without endpoints, payloads or credentials. A
bounded `FirstFailure` object reports an allowlisted code/message, numeric HTTP
status when available, and attempts. Arbitrary exception text and remote response
bodies are never included; subsequent failures do not grow or overwrite it. A
transport retry may create duplicates; success is transport acceptance, not query
visibility. No automatic resource creation or notifications.

Kafka is optional: install `kafka-python>=2.2.15,<3` separately. Environment:
`TELEMETRY_KAFKA_BOOTSTRAP_SERVERS`, `TELEMETRY_KAFKA_TOPIC`,
`TELEMETRY_KAFKA_SECURITY_PROTOCOL` (SSL, SASL_SSL, or explicit local PLAINTEXT),
optional `TELEMETRY_KAFKA_SASL_MECHANISM`, `TELEMETRY_KAFKA_USERNAME`,
`TELEMETRY_KAFKA_PASSWORD`, `TELEMETRY_KAFKA_CA_FILE`.
No broker, topic or authentication defaults are inherited from another project.
SASL requires TLS.

Event Hubs custom-endpoint fallback uses standard-library HTTPS REST, not a claim
of Kafka connectivity. Supply `TELEMETRY_EVENTHUB_CONNECTION_STRING` (sb Endpoint,
EntityPath, SharedAccessKeyName, base64 SharedAccessKey), or
`TELEMETRY_EVENTHUB_RESOURCE_URI` plus exactly one of
`TELEMETRY_EVENTHUB_SAS_TOKEN` / `TELEMETRY_EVENTHUB_BEARER_TOKEN`.
Resource URI is HTTPS host/entity, without `/messages`, query or credentials.
Keys sign the resource with HMAC-SHA256 using UTF-8 key text (not base64-decoded),
as specified by the Event Hubs SAS authentication examples.
Tokens/connection strings come only from environment, never CLI arguments or
output. External secret injection is the caller's responsibility. Redirects are
disabled to prevent sending Authorization elsewhere. Expired tokens fail
explicitly; connection-string SAS is refreshed per request.

Adaptation evidence: reviewed Allstate `build_policy_event`, bounded sender
retry/pacing and `comparison/ingestion_volume.py` NDJSON/hash/manifest patterns.
This package replaces their customer schema and configuration entirely; it also
bounds pending futures instead of collecting all futures/results in memory.
