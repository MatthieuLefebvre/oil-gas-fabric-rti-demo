# Oil-and-gas operational intelligence with Fabric RTI and Fabric IQ

## Business and industrial context

Oil-and-gas operations depend on equipment distributed across production sites,
tank batteries and gas-lift systems. Compressors support gas-lift operations,
while pressure and vibration measurements help teams understand how those
assets behave over time. Operators and engineers need to move from individual
telemetry tags to a clear operational picture: **what was measured, on which
equipment, at which site, and how recently?**

Industrial telemetry often arrives from SCADA systems, historians or messaging
platforms as timestamps, tag paths and values. A tag can encode a site, a
compressor and even a specific component, but that context is not immediately
usable as a business model. Repeated equipment names across sites, late or
duplicate events, mixed engineering units and stale readings make simple
time-series charts insufficient for answering operational questions reliably.

This repository provides a **synthetic compressor-monitoring demonstration**
for exploring how Microsoft Fabric Real-Time Intelligence (RTI) and Fabric IQ
can bring telemetry, asset context and conversational exploration together.
It is intended for customer demonstrations, architecture discussions and
hands-on learning, not production equipment monitoring or control.

## What the demo is designed to show

The business story connects three questions:

1. **What is happening?** Use Fabric RTI to ingest and query telemetry, inspect
   pressure history, compare compressors and distinguish fresh observations
   from stale or missing data.
2. **Where is it happening, and what does it belong to?** Explore the
   ontology-based operational context central to the Fabric IQ story, linking
   sites and equipment to their components and measurements.
3. **How can people explore it?** Combine dashboards, curated queries and
   Data Agent questions so users can navigate from a business question to
   scoped assets and supporting observations.

| Demonstration area | Fabric capabilities explored | Industrial value illustrated |
|---|---|---|
| Telemetry ingestion | Eventstream definitions and publisher, plus a separate direct Eventhouse ingestion option | Bring changing synthetic measurements into an analytical workflow |
| Time-series analysis | Eventhouse, KQL normalization and curated functions | Explore pressure trends, compare assets, identify synthetic threshold exceedances and inspect data quality |
| Operational visibility | Real-Time Dashboard and KQL Queryset | Present readings with their units, observation times and freshness |
| Shared reference data | Lakehouse Delta tables and OneLake | Make asset and measurement context available alongside telemetry |
| Business context / Fabric IQ | Ontology entities, relationships, measurement bindings and ontology-backed graph traversal | Navigate from a site to the specific equipment and tag behind a reading |
| Conversational exploration | Fabric Data Agent with selected KQL and contextual sources | Ask operational questions grounded in scoped assets and query evidence |
| Event-driven follow-up | Activator scaffold | Introduce the alerting design pattern without enabling notifications or equipment actions |

These are demonstration surfaces, not a claim that every integration or
conversational path is qualified end to end. Environment-specific prerequisites,
validation evidence and limitations belong in the
[deployment notes](docs/deployment-status.md) and
[presenter runbook](docs/manual-fabric-steps.md).

## The compressor-monitoring scenario

The synthetic asset model contains two sites, two tank batteries, two gas-lift
systems, four compressors, four components and twelve measurements. It connects:

```text
Site -> Battery -> System -> Compressor -> Component -> Measurement
                                   \-----------------> Measurement
```

Discharge pressure is associated with a compressor's Throw 3 component;
suction pressure and vibration are associated directly with the compressor.
Measurements use the compound identity `Source + UnitNum + Name`, so a tag is
not identified by an equipment number alone.

The generator provides changing values and a normal/high/recovery scenario,
as well as a deterministic corpus for exploring duplicates, late arrivals,
invalid records and freshness. All sites, assets, values and thresholds are
synthetic; no customer operational data is required.

### Questions to explore

- Which compressors and measurements belong to Site A?
- What is the discharge-pressure history for a specific compressor component?
- How do two compressors compare over the same observation window?
- Which readings exceed the synthetic pressure threshold in that window?
- Which measurements are fresh, stale or missing?
- When someone asks about "Compressor 1," which site do they mean?

The goal is to demonstrate value beyond storing time series: connect an
observation to its industrial meaning, preserve the evidence behind an answer,
and make the same operational model approachable through queries, visual
exploration and natural language.

## Suggested demonstration journey

1. **Start with a telemetry tag.** Inspect the nine-field
   [wire contract](contracts/telemetry-contract.md) and show why a timestamp
   and value alone do not explain an asset's operational context.
2. **Explore the time series.** Use the
   [demo queries](kql/04-demo-queries.kql) and dashboard to examine history,
   comparisons, freshness and quality without mixing units or treating
   missing data as normal.
3. **Add the asset context.** Follow the
   [site-to-pressure graph query](ontology/site-a-pressure.gql) from a site
   through its equipment to a measurement, then resolve its telemetry.
4. **Ask a business question.** Use the Data Agent with the
   [grounding rules](agent/instructions.md), requiring asset scope, units,
   observation window and freshness in the answer.
5. **Discuss responsible follow-up.** Explain how an Activator design could
   route an observation for human review. The scaffold does not enable a rule,
   recipient or action.

This is decision support, not equipment diagnosis, a safety system, a
maintenance recommendation engine or autonomous control. A synthetic threshold
exceedance is an observation to investigate, not proof of an equipment fault.

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
# Original fixture-only database ONLY; never after additional ingestion:
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

- [simulator/](simulator/), [contracts/](contracts/), [data/](data/) and
  [tests/](tests/): shared generator, wire
  contract, synthetic registries and deterministic test corpus.
- [kql/](kql/), [fabric/](fabric/), [ontology/](ontology/) and [agent/](agent/):
  deployable definitions and queries.
- [scripts/](scripts/) and [docs/](docs/): scoped deployment, validation and
  operating guidance.
- [ontologyprompt.md](ontologyprompt.md): a separate ontology design proposal,
  not the canonical deployment definition.

Credentials, virtual environments, editor settings, Office lock files and
`local-only/` runtime evidence are excluded from Git. The repository does
include target-specific resource IDs and historical deployment documentation;
it is not a portable deployment template. Never commit connection strings,
tokens or private keys.

## Demonstration options

### Direct Eventhouse ingestion

Use the shared generator without Eventstream for a bounded direct-ingestion demo:

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
reference tables.
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
The scripts are deliberately restricted to workspace
`21733624-95b6-4740-b892-d29ff7889aa4`, folder **Dev/Matthieu/OilandGas**;
they are not a general multi-tenant deployment framework. The ontology
deployment targets `OilGasOperationalOntology`. Review that target and export
existing definitions before applying changes.

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
configuration. The Spark reference-loader notebook is an optional alternative
to direct Delta materialization, not a required step.
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

Evaluate answer correctness, not just successful tool execution:
`rpcCallCompleted` is not semantic acceptance. Graph CSV containing
JSON-encoded strings such as a literal `"SITE-A"` is deliberately rejected,
not silently trimmed into a passing identifier.

With an authorized, reachable Eventstream custom endpoint, exercise the bounded
publisher using:

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

- [Implementation plan](IMPLEMENTATION-PLAN.md)
- [Environment-specific deployment evidence and limitations](docs/deployment-status.md)
- [Fabric validation, recovery and presenter runbook](docs/manual-fabric-steps.md)
- [Coexistence and governance](docs/coexistence.md)
- [Bounded load qualification](docs/load-testing.md)
- [Data Agent grounding rules](agent/instructions.md)
- [Original requirements](prompt.md)
