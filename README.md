# Synthetic oil-and-gas Fabric RTI demo

P0/P1 implementation for workspace `21733624-95b6-4740-b892-d29ff7889aa4`,
folder **Dev/Matthieu/OilandGas**. **P2 is excluded.** All sites, assets, telemetry
and thresholds are synthetic; this is not a production control system.

**Current state: verified analytical core, not an end-to-end-ready streaming demo.**
Deployment observations below were recorded on October 21, 2026; they are not
a live service-health check. The completed direct Eventhouse load is separate
from the blocked Eventstream route.
The direct-ingestion Eventstream destination is Warning; its publishing endpoint
returns HTTP 401 from both local and Fabric-hosted Python. A verified-TLS AMQP
SDK probe on port 5671 also returned 401 with an explicit IP access denial;
the source's endpoint, entity path and policy name match the supplied connection.
External Kafka is not configured. See [deployment status](docs/deployment-status.md)
for deployed IDs, exact results and open acceptance gates.

## What works

- One shared deterministic generator, finite concurrent publishers and exact
  147-row fixture; nine-field [wire contract](contracts/telemetry.schema.json).
- Eventhouse raw landing, transactional parsing, actual receipt preservation,
  quality flags, heuristic deduplication, 11 curated functions and one internal normalizer.
- Native six-tile dashboard and six-tab queryset deployed.
- Thirteen small reference Delta tables materialized and read back from OneLake:
  six entity types, relationship inventory and six per-edge tables.
- Legacy JSON ontology deployed with static bindings and direct Eventhouse
  Measurement time-series binding. Native graph queries verify six entity counts,
  24 edges, the complete component-pressure path and its compound-key telemetry join.
- Published Data Agent with selected KQL, legacy ontology and ontology-backed
  GraphModel sources. Historical count, current freshness, site inventory,
  historical comparison and ambiguous-asset answers pass strict CSV checks.
  Legacy ontology planning and GraphModel CSV scalar encoding still
  prevent full context-answer acceptance; this is not represented as an AI pass.
- Stopped Activator source/object scaffold, with no rule, action or recipient.
- Physical Telemetry OneLake availability enabled; all 147 rows read back as
  Delta version 1, independently of Spark.

## Local validation

Use Python 3.12+ and PowerShell 7 for the documented workflow. The telemetry
core and its tests are stdlib-only; local validation needs no Azure credentials
and does not deploy or ingest anything:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
.\.venv\Scripts\python.exe -m unittest discover -s .\tests -v
.\scripts\Test-Local.ps1
```

Activation ensures scripts that invoke `python` use the same environment.
For optional Delta/OneLake tools, install
`pip install -r .\requirements-fabric.txt` in that environment.
The optional AMQP probe dependencies are in
[requirements-eventhubs.txt](requirements-eventhubs.txt); the REST publisher
does not require them. Optional Kafka publishing requires
`pip install "kafka-python>=2.2.15,<3"` and approved broker configuration.

## Remote validation without deployment or ingestion

Requires authenticated Azure CLI (`az login`), access to the approved Fabric
target, optional Fabric dependencies for the Delta verifier, and the existing
ignored deployment state/evidence under `local-only`. That state is not
included in a clone. Deployment scripts create it during an authorized
deployment; do not redeploy existing items merely to run validation.

```powershell
.\scripts\Test-Ontology.ps1
.\scripts\Test-Demo.ps1
# Original fixture-only database ONLY; not the current expanded deployment:
# .\scripts\Test-Demo.ps1 -Fixture
# .\.venv\Scripts\python.exe .\scripts\verify_onelake_telemetry.py
```

`Test-Demo -Fixture` and the Telemetry Delta verifier assume the original corpus
only. Additional live ingestion changes exact counts; do not reload the fixture
to make a failing assertion pass. Read-only structure validation can be run
without `-Fixture`. These checks do not deploy or ingest, but they persist
evidence locally; the ontology check also records the discovered graph ID in
local deployment state.

## Repository contents and scope

- `simulator/`, `contracts/`, `data/` and `tests/`: shared generator, wire
  contract, synthetic registries and deterministic test corpus.
- `kql/`, `fabric/`, `ontology/` and `agent/`: deployable definitions and queries.
- `scripts/` and `docs/`: scoped deployment, validation and operating guidance.
- [ontologyprompt.md](ontologyprompt.md) describes a proposed **new** compressor
  monitoring ontology. It is a design prompt, not evidence that this separate
  ontology has been implemented. The checked-in deployment scripts still target
  the existing `OilGasOperationalOntology`.

Credentials, virtual environments, editor settings, Office lock files and
`local-only/` runtime evidence are excluded from Git. The repository does
include target-specific resource IDs and historical deployment documentation;
it is not a portable deployment template. Never commit connection strings,
tokens or private keys.

## Demonstration options

### Direct Eventhouse ingestion

For the requested direct route, use the shared generator without Eventstream:

```powershell
# Append and verify one small batch.
.\scripts\Invoke-DirectIngestion.ps1 -BatchSize 12
# Repeated micro-batches for approximately 30 minutes.
.\scripts\Invoke-DirectIngestion.ps1 -BatchSize 12 -Batches 180 -IntervalSeconds 10
# Three hours, nominally 10 rows/second: 108,000 rows.
.\scripts\Invoke-DirectIngestion.ps1 -BatchSize 100 -Batches 1080 -IntervalSeconds 10 -Scenario
```

Do not start another copy if a load is already running. The script uses
Azure CLI/Entra authentication and the existing `TelemetryJson`
mapping to append to `RawTelemetry`; its transactional update policy populates
`Telemetry`. A single generator timeline preserves changing values and the
normal/high/recovery scenario across batches. Samples are released in scheduled
micro-batches and verified by their returned extent IDs; API delays can increase
observation age and reduce achieved throughput. It neither replays the fixture nor updates
reference tables. A live 12-row test verified all raw rows and independently
confirmed all 12 normalized rows, with 12 fresh measurements at query time.
The requested three-hour run subsequently completed: **108,000 new raw rows,
108,000 normalized rows, 108,000 distinct fingerprints and zero parse errors**.
It ran from 09:02:42 to 12:02:42 UTC on October 21, 2026 and stopped automatically.
Progress is updated after each verified batch in the printed
`local-only/direct-ingestion-evidence-<runId>.json` file. Multiple-batch runs
include the final interval in their scheduled duration. An ingestion/receipt
failure stops the run explicitly; do not blindly replay an ambiguous command.

This is **demo-volume inline ingestion**, not the streaming ingestion API,
Eventstream delivery, Kafka qualification or a production/high-volume path.
The Eventstream publisher notebook still uses REST against its configured
Eventstream, not this direct helper. Do not run `Test-Demo.ps1 -Fixture` or the
original exact-count OneLake verifier after adding direct samples.

### Fixed historical corpus

Use [fixed-time queries](kql/05-fixture-demo.kql), explicitly labeling the
October 20, 2026 snapshot. It has 120 unique eligible observations and ten
synthetic high-pressure observations. The current-time dashboard correctly
shows stale/missing readings or empty recent windows; historical data is not
relabeled as live. Threshold exceedance is not a diagnosis.

## Deployment and live operation

See [manual Fabric steps](docs/manual-fabric-steps.md) before making changes.
The scripts are deliberately restricted to this approved workspace/folder;
they are not a general multi-tenant deployment framework.

```powershell
.\scripts\Deploy-Demo.ps1 -WhatIf
# Apply/reapply canonical definitions only after reviewing manual changes:
.\scripts\Deploy-Demo.ps1 -IngestionMode DirectIngestion
.\scripts\Load-Reference.ps1    # Registry/snapshot only; no fixture replay
# On an initially empty database ONLY: Load-Reference.ps1 -IncludeFixture
.\.venv\Scripts\python.exe .\scripts\materialize_reference.py `
  --tables-path 'https://msit-onelake.dfs.fabric.microsoft.com/21733624-95b6-4740-b892-d29ff7889aa4/8c85629d-eecd-4c9f-b005-b19ea610a08d/Tables'
.\scripts\Deploy-Context.ps1
.\scripts\Test-Ontology.ps1
.\scripts\Deploy-Agent.ps1 -IncludeOntology -IncludeGraph
.\scripts\Publish-Agent.ps1
.\scripts\Deploy-PublisherNotebook.ps1
.\scripts\Deploy-Activator.ps1   # Stopped scaffold; no recipient or rule
.\scripts\Enable-OneLake.ps1 -Backfill
```

Do not run the Spark notebook and direct Delta materializer concurrently.
Direct materialization refuses modified tables and verifies matching initial
tables without overwriting. Deployment updates replace canonical item
definitions: export portal edits first, especially a Kafka connector or agent
configuration. The notebook is an optional alternative, not a required step;
its attempted run failed, whereas direct materialization succeeded.
Both deployment entry points preserve the recorded ingestion mode when it is
omitted. Explicitly requesting a different mode changes the canonical topology.
Agent redeployment replaces schema selections and reruns supported selection
APIs; publish and evaluate the new version deliberately. Publishing changes no
sharing permissions. Creating the publisher notebook does not run it.

Bounded, billable published-agent checks are separate from read-only structure
validation:

```powershell
.\scripts\Test-Agent.ps1 -AcceptanceCase HighCount
```

The current-time, graph-path and ambiguity evaluations are retained in local
evidence. `rpcCallCompleted` is not semantic acceptance. Graph CSV containing
JSON-encoded strings such as a literal `"SITE-A"` is deliberately rejected,
not silently trimmed into a passing identifier.

After the owner resolves the network/service issue, the bounded custom-endpoint
fallback can be exercised using:

```powershell
.\scripts\Invoke-Simulation.ps1 -Count 300 -Rate 10 -Scenario
```

While manually configuring the existing custom endpoint, a bounded wait mode
can start the feed automatically once authentication/network access permits it:

```powershell
.\scripts\Invoke-Simulation.ps1 -Count 18000 -Rate 10 -Scenario `
  -WaitForReady -ConnectionWaitMinutes 15
```

This checks one event every 30 seconds only while HTTP 401 persists, refreshing
the endpoint credentials in memory each time. Other errors stop immediately.
After a successful readiness event, the finite run starts; the example sends
for approximately 30 minutes. A successful probe is one additional real event.
Waiting is not successful ingestion, and no network controls are changed.
Do not run fixed-corpus assertions once any probe or live event is accepted.

This is **not** a Kafka connector test. Kafka requires an approved existing
connection/topic and separate connector qualification. No secrets belong in
configuration files or source control.

## Documentation

- [Reviewed implementation plan](IMPLEMENTATION-PLAN.md)
- [Deployment status and blockers](docs/deployment-status.md)
- [Fabric validation, recovery and presenter runbook](docs/manual-fabric-steps.md)
- [Coexistence and governance](docs/coexistence.md)
- [Bounded load qualification](docs/load-testing.md)
- [Data Agent grounding rules](agent/instructions.md)
- [Original requirements](prompt.md)
