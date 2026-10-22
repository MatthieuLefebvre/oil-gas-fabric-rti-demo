# Bounded load qualification

Use the shared generator and publisher; do not create a notebook-only simulator.
The Eventstream endpoint/network failure blocks qualification of that route.
A separately requested three-hour direct Eventhouse micro-batch load completed;
it does not qualify Eventstream or Kafka. A 3,000-row local file also exists;
file generation is not evidence of Fabric throughput or latency.
The destination now uses direct ingestion and is Warning, not the retired failed
processed ASA path. Finite attempts accepted zero events both locally and from
a Fabric-hosted Jupyter notebook. No live latency claim follows from deploying
the notebook or from its scheduler reporting Completed.
Verified-TLS native AMQP on port 5671 also returned an explicit 401 IP denial.
The workspace policy API reports inbound/outbound Allow and zero IP firewall
rules; an owner/Fabric support investigation of the effective managed-endpoint
restriction is required. Do not repeatedly send probes or change routes to
work around the denial. Preserve the user's manually configured destination.

## Requested direct Eventhouse volume load

The completed three-hour run used:

```powershell
.\scripts\Invoke-DirectIngestion.ps1 -BatchSize 100 -Batches 1080 -IntervalSeconds 10 -Scenario
```

It loaded 108,000 rows at approximately ten rows/second. This is Entra-authenticated
prototype inline ingestion, not an Eventstream send or production benchmark.
The approved direct path appends to `RawTelemetry`; the transactional update
policy populates `Telemetry`. Exact raw receipts are verified per batch, and
the final time-window reconciliation found exactly 108,000 raw rows, 108,000
normalized rows, 108,000 distinct normalized fingerprints and zero parse errors.
The shared generator runs once so values and the high/recovery cycle continue
across batches. The configured duration includes the final batch interval.
Actual API latency can lower throughput or lengthen a run.

The run started at 09:02:42 UTC on October 21, 2026 and completed at
12:02:42 UTC after 10,800.034 measured seconds. It exited with code zero and
cleaned up its temporary input. No loader remains running.
For future runs, do not start another copy while one is active. Monitor the printed progress
JSON for `status`, `verifiedRawRows`, `completedBatches`, `updatedAtUtc` and
`scheduledCompletionUtc`; `Running` is not a completed-load verdict.
Failures stop the run rather than silently retrying possibly committed writes.
Do not run fixed-corpus assertions against the growing database.

## Reproducible local corpus

```powershell
python -m simulator.telemetry generate `
  --output .\local-only\load-profile --count 3000 --rate 100 `
  --start '2026-10-20T12:00:00Z' --scenario
```

Observed corpus: 3,000 rows, 1,127,000 bytes, SHA-256
`54880f29c3f4d2cdb2f490a658fb88444040ff68cb472adeee8be11c0a184887`.
`EventsPerSecond` in its manifest controls intended event-time spacing; file
generation does not publish at that rate. A manifest Profile of Live describes
the generator profile, not a successful live transport.

Use current timestamps for live latency tests. Replaying the fixed historical
corpus measures a historical backfill, not normal current-event latency.

## Live stages after network/connector qualification

Obtain owner agreement for spend and run one finite stage at a time:

| Stage | Count | Rate | Intended duration |
|---|---:|---:|---:|
| Connectivity and receipt | 12 | 1/s | about 12 seconds |
| Baseline | 300 | 10/s | about 30 seconds |
| Modest ramp | 1,500 | 50/s | about 30 seconds |
| Bounded burst | 3,000 | 100/s | about 30 seconds |

For the custom-endpoint fallback, pass Count/Rate to `Invoke-Simulation.ps1`.
For manual setup, `-WaitForReady -ConnectionWaitMinutes 15` waits only for HTTP
401 to clear, using one readiness event per 30 seconds and freshly fetched
in-memory credentials. It is bounded and explicitly reports failed probes.
One accepted readiness event is additional to Count and must be included in
receipt reconciliation. No throughput/latency measurement includes the waiting
period, and configuration waiting does not bypass networking controls.
These limits are small qualification runs, not an enterprise benchmark.
External Kafka uses the same publisher with its optional Kafka dependency and
owner-provided environment configuration; qualify its distinct path separately.
Never relabel a fallback result as Kafka acceptance.

For every stage capture:

1. Sender attempted/accepted/failed counts, retries, duration and safe first
   failure. Abort on transport failures; do not retry indefinitely.
2. Raw-table growth and matching actual receipt-time window; wait for queued
   ingestion and reconcile in-flight events before declaring loss.
3. Typed parse, unknown-tag, future-event, duplicate and conflicting-reading
   counts. Do not count deduplication as unexplained loss.
4. Event-time-to-receipt p50/p95/p99, separately reporting negative clock skew.
   Report fixture backfill age separately from transport latency.
5. Query execution time for latest/history/trend/platform health under the same
   bounded window; inspect cache effects and avoid cross-unit aggregation.
6. Eventstream destination health, capacity metrics, ingestion failures,
   backlog and actual OneLake export completion. Stop if a destination fails or
   capacity pressure/owner limits are reached.

The original sub-ten-second live experience target remains **unverified**.
The transactional `ingestion_time()` requirement led to a ten-second queued
batching target; that target alone does not guarantee total arrival latency.
No tenant-wide load, indefinite publisher, capacity resizing or paid benchmark
was started.
