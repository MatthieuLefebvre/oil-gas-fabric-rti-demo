# ExxonMobil Fabric RTI demo: implementation plan

**Status:** P0/P1 implementation approved by the user; P2 explicitly excluded. Implementation is deployed in part, with runtime acceptance gates still open. See [deployment status](docs/deployment-status.md) for verified outcomes and blockers.

**Approved target:** workspace `21733624-95b6-4740-b892-d29ff7889aa4`, folder `Dev/Matthieu/OilandGas` (`975ffc5a-edee-4558-a62d-3a2bfe72110c`). No capacity resizing, external infrastructure, recipients, or plant-control actions have been configured.

**Assessment date:** October 20, 2026, Pacific time. Official documentation was retrieved during this assessment. Preview behavior and tenant availability must be rechecked before implementation.

**Requirements:** [prompt.md](prompt.md). This document records the reviewed design; the dated deployment status is the implementation evidence. Original backlog proposals below are retained as design context, not claims of acceptance.

## 1. Executive summary

Build a connected, approximately 15-minute operational story:

**Connect -> Understand -> Contextualize -> Ask -> Act -> Integrate -> Scale.**

Use synthetic oil-and-gas telemetry with the supplied nine-field schema. Start with Kafka feeding a Fabric Eventstream and a physically ingested Eventhouse database. Interpret long industrial tags through a small, explicit asset/tag registry. Show the same compressor condition through KQL, an operational ontology, natural-language experiences, and an optional notification. Finish by explaining governed downstream reuse and an enterprise scaling path.

The distinction from an ADX-only demonstration is the integrated experience: managed streaming, shared operational context, AI-assisted exploration, operational notifications, OneLake exposure, and governance. **Do not claim that KQL analytics or natural-language query generation alone are unique to Fabric.** Current RTI Copilot documentation also supports ADX connections [S4].

### Recommended scope

- **P0:** Schema and deterministic synthetic scenarios; one Kafka-to-Eventhouse ingestion lane; operational KQL and dashboard; instantiated ontology hierarchy and telemetry bindings; KQL Copilot demonstration; domain-aware Data Agent; monitoring, coexistence documentation, and rehearsed fallbacks.
- **P1:** One focused Activator email/Teams notification; verified OneLake read; optional Databricks read; representative backfill/ramp experiments; additional automation.
- **P2, excluded by user:** Physical/3D scene using existing assets; live Snowflake/ADX integrations beyond the documented coexistence story. P2 backlog entries and file proposals below are not authorized work.
- Ontology, Copilot, and Data Agent are P0 **validation gates**, not capabilities to assume away. If unavailable, a clearly labeled fallback preserves the meeting but does not satisfy full P0 acceptance.

### Reviewed design decisions

1. Keep the oil-and-gas demo separate from other customer projects. Reuse reviewed infrastructure and transport code, not their customer data, credentials, or deployed endpoints.
2. Adapt one existing generator/publisher implementation; do not create separate notebook and CLI payload generators.
3. Prefer the supported Kafka Eventstream connector for the main POC-aligned lane. A custom-endpoint replay is an explicitly labeled fallback, not proof of Kafka connectivity.
4. Use a small Lakehouse for stable asset and relationship tables, and Eventhouse for telemetry. This provides explicit relationship-instance evidence without copying all telemetry into a graph.
5. Select the actual tenant ontology experience before compiling definitions. Existing neighboring scripts target older contracts; their acceptance does not certify the updated experience.
6. Do not introduce a new UI, JVM ingestion gateway, anomaly-ML service, production control integration, or 3D application for the core demo.

## 2. Repository assessment

### 2.1 Evidence and limits

The current directory initially contained only [prompt.md](prompt.md), 552 lines, and is **not a Git repository**. There is no existing oil-and-gas application, dependency manifest, deployment configuration, test suite, simulator, KQL package, ontology, or README to modify.

Read-only discovery covered top-level projects in `C:\Work`, targeted documentation/source in the projects below, and the first 100 owned repositories returned by the authenticated GitHub CLI. The CLI returned 20 repositories. Relevant local repositories also have organizational remotes not present in that owned-repository list. This is not an exhaustive search of every organization or branch.

No Fabric workspace, capacity, connection, existing ExxonMobil Kafka topic, license, or live data plane was inspected. Existing projects' deployment claims below are documentation evidence, **not independently repeated live tests**. No customer sample files, secrets, `.env` files, local credential configuration, or private presenter materials were needed or read.

### 2.2 Important reusable components

| Component | Evidence inspected | Classification | Recommended use and limits |
|---|---|---|---|
| Current oil-and-gas implementation | Current directory and requirements | **Missing** | Create only after plan review; retain the requirements unchanged. |
| Synthetic generator and bounded Eventstream sender | [Allstate notebook source](../Allstate/fabric/notebooks/SimulateAllstatePolicyEvents.py); README; `build_policy_event`, `send_event`, `run_simulation` | **Modify** | Adapt pacing, bounded concurrency, authentication selection, retries, and run summaries. Replace the insurance payload builder with nine-field telemetry; remove all inherited endpoints and defaults. Verify the exact supported endpoint protocol rather than transplanting transport assumptions. |
| Deterministic corpus/reconciliation tooling | [Allstate volume runner](../Allstate/comparison/ingestion_volume.py) | **Modify** | Reuse frozen NDJSON, manifest, run identity, hash, and reconciliation patterns. Replace insurance-specific fan-out and gold assertions. Use a single shared payload builder. |
| Kafka integration precedent | [Allstate Kafka walkthrough](../Allstate/comparison/kafka-spring-eventhouse-bridge/README.md) and Java source inventory | **Reuse selectively** | Reuse producer/test-harness and offset/retry lessons. The current listener validates insurance envelopes and writes directly to Eventhouse; it is not a generic drop-in telemetry bridge. Embedded Kafka is a local test option, not enterprise connector evidence. |
| Fabric/Eventstream/KQL deployment | [Allstate project](../Allstate/README.md), [Airlines deployment script](../Airlines/scripts/Deploy-Fabric.ps1) | **Modify** | Reuse definition packaging, item discovery, and long-running-operation polling patterns. Audit pagination, permissions, dry run, target scoping, and failure reporting before use. No automatic capacity creation. |
| KQL operational monitoring | [Allstate monitoring queries](../Allstate/Eventhouse/06_monitoring.kql) | **Modify** | Reuse freshness, ingestion timestamp, and trace patterns. Replace all domain tables and identifiers; distinguish source timestamps from actual Eventhouse receipt. |
| Ontology with Eventhouse bindings | [Airlines ontology deployment](../Airlines/scripts/Deploy-Ontology.ps1), [manual runbook](../Airlines/docs/manual-fabric-steps.md) | **Modify** | Useful multipart/TimeSeries binding example. It defines relationship types but documents missing relationship instances. Add actual mapping data and validate the currently supported definition contract; do not copy its whole deployment as-is. |
| Portable ontology and guarded deployment | [Elite ontology adapter](../Elite/elite-fabric-ontology-demo/fabric/ontology_adapter.py), [project overview](../Elite/elite-fabric-ontology-demo/README.md) | **Reuse selectively** | Reuse stable logical keys, explicit unsupported-capability failures, and contract checks. The legal-finance model and multi-tenant topology are not appropriate for this demo. Avoid two parallel ontology compilers. |
| Data Agent instructions and evaluation | [Airlines instructions](../Airlines/ontology/data-agent-instructions.md), [Elite agent deployment step](../Elite/elite-fabric-ontology-demo/fabric/steps/step08_agent.py) | **Modify** | Reuse timestamp, approved-source, no-invented-answer, and negative-test patterns. Elite deliberately blocks undocumented ontology-agent automation; preserve that honesty. Instructions are not an authorization boundary. |
| Dashboard and Activator precedent | [Airlines project](../Airlines/README.md), [manual configuration](../Airlines/docs/manual-fabric-steps.md) | **Modify** | Reuse build-spec/runbook approach, not airline fields, notification recipient, or assumptions about rule options. |
| Enterprise schema-drift/reference assets | Local Thermoking reference-project inventory; owned GitHub repository descriptions for schema drift and SQL CDC | **Reuse selectively** | Optional reference for governance/drift documentation; not selected as core dependencies. No claim that their full source or live deployments were assessed. |
| Cluster-health workbench | [Kusto Cluster Health README](../kusto-cluster-health/README.md) | **Replace for this demo** | Its backend requires an internal diagnostics database. Use customer-accessible Fabric monitoring instead; do not expose or depend on internal diagnostic access. Reuse only conceptual metric categories. |
| Physical/3D and Fabric integration | [projectllama README](../projectllama/README.md), source inventory | **Reuse, P2** | Existing Babylon.js/USD layouts, ontology discovery, Fabric sidecar, and Eventhouse pose polling are relevant. Live arbitrary scalar-status bindings are explicitly not implemented; a pressure-to-live-color story needs separate work. Its local Copilot SDK panel is not Fabric Data Agent or RTI Copilot. |

GitHub provenance: Allstate maps to `MatthieuLefebvre/allstate-fabric-rti-eventhouse`; Elite to the accessible `elite-fabric-ontology-demo` project; Airlines' local remote is `malefe_microsoft/fabric-bos-airlines-operations-demo`; projectllama's is `dredudek_microsoft/projectllama`. Confirm licenses and permission to reuse organizational/private code before copying it into a new repository. Do not copy customer-specific material.

**Replace** refers to the proposed oil-and-gas design, not an instruction to change or remove a neighboring project.

## 3. Gap analysis

All existing implementations in this matrix are **neighboring assets**, unless explicitly stated otherwise.

| Demo requirement | Existing implementation | Gap | Recommended change | Priority |
|---|---|---|---|---|
| Exact source shape and privacy-safe domain | Insurance/airline generators | No oil-and-gas schema, units, or time semantics | Contract, synthetic registry, one adapted payload builder | P0 |
| Continuous telemetry and Kafka alignment | Eventstream sender, Kafka test lane | No approved target topic/connector | Adapt publisher; configure Kafka source and Eventhouse destination | P0 |
| Duplicates, disorder, invalid values | Frozen corpus and reconciliation patterns | No defined identity or late-event policy | Deterministic fixture, explicit heuristic identity, diagnostics and quarantine visibility | P0 |
| Time-series operational questions | Existing domain-specific KQL | No compressor views/functions | Bounded operational functions and live-query scripts | P0 |
| Operational hierarchy and telemetry mapping | Airline TimeSeries definition; Elite contract | No site-to-measurement instances, units, or tag mapping | Stable asset dimensions, relationship rows, ontology bindings | P0 |
| Copilot without starting in KQL | Documented RTI product capability | Tenant permissions, metadata, questions untested | Docstrings; five approved prompts; inspect and manually execute generated KQL | P0 |
| Domain-aware Data Agent | Instructions/evaluation patterns | No oil-and-gas grounding or evaluation truth | KQL plus ontology source, domain instructions, scored questions | P0 |
| Concise operational visual | Airline dashboard build spec | No pressure/freshness/asset comparison view | Small native Real-Time Dashboard; no custom frontend | P0 |
| Platform versus asset monitoring | KQL freshness patterns; internal health app | Customer-accessible monitoring not configured | Native Eventstream metrics, workspace monitoring, Eventhouse diagnostics | P0 |
| Action from observation | Airline Activator policy/runbook | No safe compressor rule or tested recipient | One per-asset threshold-transition notification | P1 |
| OneLake availability | Product feature; no local oil-and-gas configuration | No eligible table, freshness measurement, or consumer | Enable one physical table; read-only notebook comparison | P1 |
| ADX, Databricks, Snowflake, Power BI coexistence | Existing platform patterns | No verified integration story | Explicit query/follower/physical-ingestion decision table; no unsupported zero-copy claims | P0 documentation; P1/P2 live |
| Enterprise architecture and scale | No oil-and-gas implementation | No isolation, retention, capacity or backfill position | Architecture decisions and representative sizing/load plan | P0 documentation; P1 experiments |
| Repeatable setup and live fallbacks | Existing deployment/runbook patterns | No portable config, acceptance suite, or presenter sequence | Parameterized deployment, verification, setup and rehearsal package | P0 |
| Physical/3D | Existing projectllama prototype | No compressor scene or live scalar adapter | Optional small scene; defer if new integration is required | P2 |

## 4. Target architecture

### 4.1 Boundaries and major flow

```text
EXTERNAL / LOCAL
  One synthetic generator + deterministic scenario/corpus
           |
           +--> approved Kafka / Confluent topic (main lane)
           |       |
           |       v
           |   FABRIC Eventstream Kafka source
           |       |
           +------>| custom endpoint (fallback only; explicitly labeled)
                   v
              Eventhouse RawTelemetry (original payload preserved)
                   |
              typed normalization / validation
                   v
              Telemetry fact + visible rejected/invalid diagnostics
                   |
              curated KQL functions <----- asset/tag registry
                   |                          |
                   +--> Real-Time Dashboard   +--> small Lakehouse dimensions
                   +--> KQL Queryset/Copilot          + relationship tables
                   |                                 |
                   +----------- ontology bindings <--+
                   |                |
                   +---------> Fabric Data Agent
                   |
                   +--> selected physical table --> OneLake Delta availability
                                                      |
                                                  read-only notebook
                                                  Power BI / Databricks

  Eventstream enriched, fresh, recognized telemetry --> Activator --> test notice
  Platform metrics/logs --> monitoring item / native diagnostics (separate view)
```

The diagram is a logical design, not a deployed topology. Activator does not automatically subscribe to KQL function results. Its P1 feed is an explicitly configured, validated Eventstream branch.

**Repository components:** contracts, synthetic asset registry, adapted generator/publisher and replay runner, KQL definitions/functions/examples, portable ontology/binding specifications, agent instructions/evaluation fixtures, dashboard/alert build specifications, deployment/verification scripts, runbooks, and sanitized rehearsal evidence.

**Fabric components:** approved workspace/capacity, Kafka connection, Eventstream, Eventhouse/KQL database, small reference Lakehouse, ontology item, KQL Queryset, Real-Time Dashboard, Data Agent, monitoring item, and optional Activator/OneLake configuration.

**External dependencies:** approved Kafka broker/topic/authentication/network, Microsoft Entra identity, approved secret store if needed; optional existing ADX, Databricks, Snowflake and NVIDIA/Omniverse environments. No real historian/SCADA connection is required or claimed. PI/PHD, OPC UA and MQTT/Sparkplug B are future edge/source integration lanes through approved connectors or gateways, not native support assumed by this plan.

### 4.2 Source contract and time semantics

Preserve all nine field names and the original payload. Choose and document the following **synthetic contract**, pending validation against an approved real sample:

| Source field | Synthetic wire representation | Normalized meaning |
|---|---|---|
| `RecordDateTime` | ISO string with explicit site offset | Original source-local time; retain it, never guess DST/time zone |
| `RecordDateTimeUTC` | ISO UTC string | Authoritative event time, parsed as KQL `datetime` |
| `UnitNum` | String | Source unit identifier, not globally unique asset identity |
| `Source` | String | Synthetic source-system identifier |
| `Name` | Full hierarchical tag string | Exact registry lookup key, scoped by source/unit |
| `Value` | JSON number for valid synthetic records; malformed variants in negative tests | Numeric `real` only after successful validation; units come from tag metadata |
| `RecordAdded` | ISO UTC string | Source record-add timestamp |
| `ProcessedDate` | ISO UTC string or null | Source processing timestamp; not Fabric processing time |
| `IngestionTime` | ISO UTC string or null | Source-provided field retained as supplied; **not** proof of Fabric receipt |

Capture actual Eventhouse receipt separately as `EventhouseIngestedAt`, using `ingestion_time()` on the raw table with its ingestion-time policy enabled. Carry this timestamp into normalized data rather than later substituting normalized-table ingestion time. It is an approximate service ingestion timestamp, not a globally ordered sequence. Also record query observation time. Never have the generator fabricate a future Eventhouse ingestion timestamp.

Do not add required fields to the customer's nine-field payload. Keep run ID, seed, sequence, expected fingerprint/counts, Kafka offset evidence and corpus hash in a manifest or supported transport metadata. Confirm which metadata the chosen connector actually preserves; do not assume headers arrive in a payload-only table.

Define timestamp ordering, nullability and rejection reasons explicitly. Report negative apparent latency/clock skew separately. Invalid timestamps or nonnumeric values must not silently become zero. Unknown tags remain visible as unmapped, not inferred into arbitrary assets. Future timestamps are flagged/excluded from current-state claims using a configurable, documented tolerance (proposed 30 seconds).

### 4.3 Synthetic operational scenario and data quality

- Two explicitly fictional sites, one battery and gas-lift system per site, two compressors per system, and a Throw 3 component per compressor: **2 sites, 2 batteries, 2 systems, 4 compressors, 4 components**.
- Three measurements per compressor: discharge pressure on Throw 3, suction pressure and vibration on the compressor. Total: **12 measurement identities**.
- Include the provided path shape in the mapping specification. Use fictional site prefixes in generated data. Never imply that a path supplied in the requirements contains measured ExxonMobil operating data.
- Synthetic-only discharge pressure: nominal 110-120 psi, high threshold 140 psi, recovery below 135 psi. Synthetic vibration and suction units/ranges live in the registry. These are demo labels, **not engineering operating limits or maintenance guidance**.
- One compressor transitions from normal to high pressure, remains high, and recovers. A second stays normal for comparison. Correlated changes are illustrative, not a fault diagnosis.
- One shared generator supports finite fixture output, paced Kafka publishing and approved custom-endpoint publishing. A notebook wrapper imports/packages the same builder; it does not reimplement it.
- Separate bounded live and historical-replay profiles. Never allocate hundreds of millions of records in memory. Use chunked generation, bounded queues, retry evidence, and explicit abort/error reporting.

**Duplicate semantics:** the provided schema has no authoritative event ID. A canonical fingerprint over source/unit/tag/event-time/source-add-time/value is only a documented duplicate heuristic; exclude Fabric receipt and processing timestamps. Preserve source value representation consistently when canonicalizing. Real repeated readings or corrections can collide or legitimately differ. The fixture knows which records were intentionally replayed; production deduplication requires a source event ID or an agreed identity/correction policy.

Preserve every raw row. Deduplicate only curated reads for this demo. Select latest state by **event time**, not arrival time, with an explicit deterministic tie-break rule for equal timestamps; surface conflicting same-key readings rather than invent a correction precedence. Bounded lookbacks must state their limits: neither the duplicate query nor disorder diagnostics proves global correctness over all history.

### 4.4 Eventhouse model and reusable KQL

Keep the model narrow: raw payload, typed telemetry, validation diagnostics, small reference tables, and curated functions. Do not port the insurance project's 26-table fan-out.

Normalize source fields with a tested function/update policy and preserve raw payloads for failures. Keep ingestion-time normalization free of cross-table joins that could break streaming-ingestion/update-policy compatibility. Use small tag/asset lookups in curated functions; validate target restrictions before selecting a more elaborate update policy. Each raw row must be attributable to accepted data or an explicit rejection reason.

Suggested functions, with documented output columns, units, and observation windows:

| Function | Purpose / output |
|---|---|
| `OperationalMeasurements(startUtc, endUtc, siteId)` | Bounded normalized, mapped, deduplicated readings; asset, measurement, unit, event time, receipt time, quality |
| `LatestCompressorMeasurements(asOfUtc, freshness)` | Latest per measurement, event-time selection, observation age and stale state |
| `CompressorHistory(assetId, startUtc, endUtc)` | One asset's timestamped measurements; no mixed-unit aggregate |
| `PressureTrend(assetId, startUtc, endUtc, grain)` | Event-time bins with average/min/max/sample count and explicit unit |
| `AbnormalCompressorReadings(startUtc, endUtc)` | Configured synthetic threshold breaches and evidence, not ML diagnoses |
| `CompareCompressors(assetA, assetB, startUtc, endUtc)` | Same-measurement, same-unit window comparisons and freshness |
| `IngestionHealth(startUtc, endUtc)` | Counts, receipt freshness, latency percentiles, skew, invalid/unmapped counts |
| `DuplicateCandidates(startUtc, endUtc)` | Fingerprint/count and heuristic caveat |
| `ArrivalOrderDiagnostics(startUtc, endUtc)` | Late-arrival candidates by measurement; receipt timestamps are approximate |
| `SiteTelemetryInventory(siteId)` | Registry inventory plus observation coverage; distinguishes registered from observed assets |

Default live history: 15 minutes; trend bin: one minute; stale threshold: 60 seconds; fresh as-of time exposed in every answer. Explicit parameters permit historical replay without accidentally querying only `ago(15m)`.

Latest-state queries must retain last known registry measurements and mark them stale; do not make stopped compressors disappear by filtering old rows before evaluating freshness. Bound scans to a documented latest-state horizon and return "no observation in horizon" when appropriate. Only add a latest-state materialized view if profiling justifies it and its aggregation semantics pass late-event/tie tests.

Reusable scripts: schema/policies, normalization, curated functions/docstrings, reference data loading, operational query examples, data-quality diagnostics, platform monitoring, and read-only acceptance assertions. Each presenter query block must be independently runnable.

### 4.5 Operational ontology and binding design

| Entity | Stable key and important properties | Relationships |
|---|---|---|
| Site | `SiteId`, display name, synthetic flag, time zone | Site **contains** TankBattery |
| TankBattery | `BatteryId`, name, `SiteId` | TankBattery **contains** GasLiftSystem |
| GasLiftSystem | `SystemId`, name, `BatteryId` | GasLiftSystem **uses** Compressor |
| Compressor | Globally scoped `AssetId`, name, source/unit, site, equipment class | Compressor **hasComponent** Component; Compressor **hasMeasurement** Measurement |
| Component | `ComponentId`, parent asset, component type/name | Component **hasMeasurement** Measurement |
| Measurement | `MeasurementId`, full tag, source/unit key, engineering unit, display label, synthetic thresholds | Measurement **observedOn** Compressor, where useful for navigation |

Equipment is a shared domain classification/property for the P0 compressor model; use an Equipment base entity/inheritance only if the selected ontology experience supports it cleanly. Avoid redundant Equipment/Compressor instances representing the same physical object.

Time, numeric value and actual receipt time are time-series properties/observations, not a new graph entity per sample. Keep telemetry in Eventhouse. Map `Source + UnitNum + Name` to `MeasurementId`, `AssetId` and optional `ComponentId` in an explicit registry; normalize slash/whitespace rules before matching and reject ambiguous keys.

**Proposed binding:** small Lakehouse Delta tables provide primary instances and relationship key pairs. Eventhouse telemetry provides secondary time-series properties joined through stable measurement/asset keys with `RecordDateTimeUTC` as timestamp. Publish an entity/property/relationship-to-table/column binding manifest with source item IDs supplied by deployment configuration.

Relationship type definitions alone are insufficient: validate actual Site -> Battery -> System -> Compressor -> Component -> Measurement instances. For this fixture expect **2 + 2 + 4 + 4 + 12 = 24 containment/measurement edges**, with each measurement having exactly one owner; optional inverse/navigation edges are counted separately.

The updated October ontology overview permits more flexible relationships and optional graph materialization [S1], while detailed relationship guidance still describes source bindings [S2]. Use explicit key-pair tables as a portable, testable design, **not as a claim that all current ontology experiences require a dedicated join table**.

Validate the selected experience's primary/secondary binding support in a small spike. If it cannot bind directly as proposed, record the exact limitation and supported alternative; a diagram is not a deployed ontology. Graph execution/materialization is optional, not a P0 dependency. If used, refresh and measure its snapshot age independently; do not call graph snapshots real-time.

### 4.6 Copilot and Data Agent are distinct demonstrations

**KQL Copilot:** connect the queryset to the intended database; provide meaningful table/column/function docstrings and precise prompts. Copilot generates/refines KQL; the presenter inspects it and selects Run. It does not automatically run generated queries or author control commands [S3]. No ontology dependency is assumed for this surface.

Test these prompts before the demo:

1. What compressors are represented in the observed data at the synthetic site?
2. Show recent discharge-pressure measurements for Compressor 1, with time and psi.
3. Which assets exceeded the configured synthetic threshold in the last 15 minutes?
4. How did Compressor 1's discharge pressure change across one-minute bins?
5. Which measurements had the highest p95 event-to-Eventhouse receipt latency?

Include the site/asset key and relevant curated function in the saved prompt where necessary. Define "unusual" as the configured synthetic rule; do not let the model invent a statistical anomaly method.

**Fabric Data Agent:** create a named operational agent with the curated KQL database source and the ontology source supported in the selected experience [S5, S6]. KQL-backed NL2KQL and UDF use are documented. Ontology is not required for a direct-KQL agent; the combined demo must demonstrate its actual added context rather than claim every generated KQL query traversed the ontology.

Instructions must define aliases, asset identity, hierarchy, units, source versus receipt time, default windows, freshness, duplicate caveats and synthetic thresholds. Require answers to state asset/site, metric/unit, time window/as-of time, observed evidence, and uncertainty. Treat "Which compressor should I investigate?" as a human-review suggestion based on recent threshold breaches and freshness, never a safety/maintenance decision.

Ground on the inventory, latest, history, trend, abnormal, comparison and health functions above. Select approved tables/functions where the UI supports it; verify generated queries use that scope. If function discovery/selection differs in the target, expose the smallest supported curated schema and document the limitation. A source picker or prompt is not a substitute for data-plane permissions.

Agent test set: the five operational questions in the requirements, all five Copilot prompts, plus nonexistent asset, no data, stale data, unknown units, denied site, ambiguous "Compressor 1", and a request to change data. An ambiguous asset name should request disambiguation, not select a site arbitrarily. Use direct KQL fixture results as truth, not a canned answer string.

Current documentation identifies Data Agent as generally available [S5]; ontology remains preview [S1]. Do not carry forward older project assumptions that every agent feature is preview. Specific consumers, ontology variants and region/tenant combinations still require validation.

### 4.7 Optional focused Activator action

Prefer an Eventstream branch over pretending an arbitrary KQL function is an Activator source. For the small demo, publish/include supported enrichment in a derived stream for recognized discharge-pressure tags: asset key, event time, numeric value, psi, threshold and scenario state. Keep the original nine-field landing payload intact.

Rule: for each asset, a **fresh** reading **becomes greater than 140 psi**; send one test notification. Recovery below 135 psi provides a documented reset/hysteresis scenario where supported. Use the product's actual state/cooldown capabilities, verified in the target UI [S7]. Do not promise a specific cooldown control before testing.

If dynamic reference enrichment is unsupported, configure explicit synthetic tag filters/mapping for the four demo assets and generate the derived specification from the registry. Do not invent a general Eventstream join feature.

Test normal -> high -> sustained high -> duplicate -> old high -> recovery -> new high. Stale replay and duplicates must not cause repeated notices. If the chosen stream/rule cannot enforce freshness and suppression, keep Activator off until a supported solution is validated. Notifications go only to an approved test recipient. No PLC, compressor-control, emergency-response or real work-order action.

### 4.8 Platform integration and enterprise path

| Platform/scenario | Credible coexistence approach | Important boundary |
|---|---|---|
| Existing ADX, query federation | Keep ADX as owner and validate authorized cross-cluster/remote queries or direct ADX connections where supported | Querying remote data is not physical ingestion or OneLake publication; permissions/network/performance remain separate |
| Existing ADX, database shortcut/follower | Read-only database shortcut into Eventhouse; same-region source/shortcut per documentation [S9] | Similar to follower behavior; shared source storage, cache and synchronization lag. Not a OneLake shortcut, writable landing database, or automatic OneLake availability |
| Physical Eventhouse landing | Ingest the approved Kafka stream/backfill into local physical tables | Establish retention, data quality and ownership; enable OneLake only on eligible physical tables |
| OneLake | Enable one selected physical telemetry table; inspect Delta files and compare a completed time window [S8] | Batched availability, not per-event streaming. Retention follows KQL retention; not an independent permanent archive |
| Databricks | Read the exposed read-only Delta data using approved OneLake authentication/path or supported catalog federation [S10] | Confirm actual item/path/Delta compatibility and permissions. Do not write/optimize Eventhouse-managed Delta tables |
| Power BI | Native KQL-based operational reporting first; optionally validated Direct Lake/semantic model over OneLake | Choose based on required freshness and model/security. No automatic unified security across engines |
| Snowflake | Document coexistence through a separately validated supported connector, export/external-table or sharing design | No verified live Snowflake route in this assessment; do not claim universal zero-copy or direct Eventhouse-Delta compatibility |
| External analytical tools | Approved Kusto query endpoint/SDK or eligible OneLake read path | Each route needs its own authentication, freshness and authorization validation |

OneLake adaptive write delay is documented as up to three hours by default, or until adequately sized files form; `TargetLatencyInMinutes` currently permits 5 minutes to 3 hours [S8]. A demo may deliberately select five minutes for one table after considering small-file/capacity impact. Prewarm the view and show **measured** lag; never promise second-level OneLake freshness.

The retrieved OneLake guidance lists restrictions on applying table RLS while availability is enabled, as well as some destructive/schema operations [S8]. Keep the OneLake demo on a separately scoped, non-sensitive synthetic table and verify downstream authorization independently. Never claim KQL RLS automatically protects Delta readers. Recheck exact supported behavior before choosing production isolation.

#### Enterprise architecture decisions to document, not overbuild

- **Topology:** use one Eventhouse/database for the demo. For enterprise design, compare central ingestion with federated business-unit/region/site-group ownership. A logical asset hierarchy does not mandate one database/Eventhouse per asset.
- **Isolation:** separate workspaces/data stores for hard trust/residency boundaries. Folders, databases and Eventhouses sharing a capacity do not automatically provide independent capacity/noisy-neighbor isolation. Distinct capacities are a stronger workload isolation lever.
- **Organization:** group databases by ownership, policy and access needs; use stable `SiteId`/`AssetId` dimensions within boundaries. Avoid a table per tag or a high-cardinality database per measurement.
- **RBAC/RLS:** least-privilege producer, deployer, operator, presenter and viewer identities. Verify workspace/item/data permissions and any KQL RLS with actual user queries. Test each AI/OneLake route separately. Do not grant production viewers Contributor merely to simplify the demo.
- **Lifecycle:** proposed demo raw/typed retention 30 days and hot cache one day, configurable and approved before deployment. Cold retained Eventhouse data and hot cache serve different needs. Longer-term archive, if required, is a separately governed export/storage design, not assumed from OneLake availability.
- **Capacity/noisy neighbors:** evaluate ingestion, update-policy CPU, concurrent KQL/dashboard/AI load, OneLake batching, and backfill together. Set bounded scans/refreshes and a stop budget. No capacity SKU recommendation without measurements.
- **Backfill:** use a separate throttled bulk lane, preserving historical event time. Reconcile by chunk/watermark with resumable manifests; keep it out of alerts and live freshness calculations. Prioritize live telemetry while ramping history.
- **Governance:** catalog descriptions, owner/steward, sensitivity labels where applicable, lineage, source-contract versions, dimension changes, audit evidence and approved downstream sharing. Tag parsing is not a governance system.
- **Scale arithmetic:** 20M/day is about **231.5 records/second average**; 1B/day is about **11,574/second**, not a benchmark. At 500 serialized bytes/record those are about 10GB/day and 500GB/day before compression, replication and derived data. Measure actual bytes, burstiness, tag cardinality, partition skew, update amplification and query concurrency.
- **Partitioning:** Kafka keys should preserve ordering for a measurement/asset while avoiding hot partitions; broker offset order is not event-time order. Target partitions and rate require an actual broker/capacity experiment.
- **Observability:** platform and business dashboards remain distinct. Eventstream flow/backlog/errors, Eventhouse ingestion/query failures and throttling, capacity utilization, and supported workspace-monitoring logs describe the platform. Pressure, vibration, stale assets and unmapped tags describe operations.

Workspace monitoring needs explicit collection enablement and does not backfill prior activity [S11]. Inspect supported tables in the target; do not reuse internal Kuskus schemas or assume every workload logs every metric. Native Eventstream metrics/runtime diagnostics remain the fallback for unsupported monitoring-table coverage.

## 5. Recommended demo sequence

Target 15 minutes, with 3D outside the core timebox. Start the simulator and optional OneLake preparation before the audience joins.

| Step / time | Presenter shows | Customer question | Required component | Expected result | Live fallback |
|---|---|---|---|---|---|
| 1. Connect / 2 min | Kafka source, Eventstream flow, raw nine-field records and actual receipt time | Can our industrial telemetry arrive continuously? | Approved Kafka route, generator, Eventhouse | Increasing counts; realistic tags/values; source and receipt timestamps distinguished | Explicitly labeled endpoint replay or previously captured synthetic ingestion evidence; do not call it live Kafka |
| 2. Understand / 2 min | Latest state, one-minute pressure trend, comparison and a late/duplicate example | What is happening, and can I trust the reading? | Curated KQL, dashboard | High-pressure compressor identified; older arrival does not replace newest event-time state; duplicates visible | Execute frozen fixture queries with fixed as-of time; label results historical |
| 3. Contextualize / 2 min | Traverse actual site/battery/system/compressor/measurement instances, inspect tag/units and source binding | Which operational asset does this tag describe? | Ontology, registry, Lakehouse relationship rows | Selected compressor maps to the same measurements/values in Eventhouse | Binding manifest plus captured instance view; clearly not proof of a live ontology |
| 4a. Ask with Copilot / 1 min | Natural-language pressure request; generated query reviewed then Run | Must the operator start by writing KQL? | Paid supported capacity, queryset, Copilot | Correct bounded query with explicit units/window | Saved prompt and generated query/result from a dated rehearsal |
| 4b. Ask with Data Agent / 3 min | Which compressor merits review? What changed? Compare it with another | Can the answer use operational context and evidence? | Grounded agent, curated functions, ontology | Concise asset/site answer with metric, units, time and stated freshness; recommendation not diagnosis | Sanitized transcript plus direct KQL answer; identify which path failed |
| 5. Act / 1 min, optional | Inject fresh high pressure and show one approved test notice | Can observation become action? | Activator stream/rule/recipient | One threshold-transition notice; no flood from sustained/old/duplicate readings | Dated rule-test evidence or skip; never trigger an unapproved recipient |
| 6. Integrate / 2 min | OneLake completed-window read or architecture comparison | Can we keep ADX/Databricks/Snowflake/Power BI investments? | Documented coexistence design; optional prewarmed OneLake | Same physical data available to another engine with measured lag and boundaries | Architecture and saved read evidence; no false universal zero-copy claim |
| 7. Scale / 2 min | Ingestion health, capacity signals, topology and backfill decisions | Is there an enterprise path beyond this small demo? | Monitoring, sizing assumptions, architecture notes | Clear isolation, cost, access and lifecycle choices; no billion/day claim from a tiny run | Sanitized monitoring capture and explicitly hypothetical sizing worksheet |

Natural transitions: a changing tag becomes a trend; the trend becomes a named compressor; the named compressor becomes a grounded answer; the fresh condition becomes a notification; the same governed data becomes a reusable platform asset.

## 6. P0/P1/P2 implementation backlog

Effort is intentionally not estimated until the broker, target workspace and ontology experience are confirmed. Dependencies are task IDs, not merely list order. All implementation tasks depend on **G0**.

| ID / priority / phase | Objective | Files/directories | Dependencies | Technical approach | Expected output | Validation criteria |
|---|---|---|---|---|---|---|
| G0 / P0 / Review | Approve scope, target and reuse rights | This plan; future README decision record | None | Review proposed decisions; name workspace/capacity owner, broker, test recipient and repository destination | Recorded review decision; no deployment yet | Explicit plan approval before code/resource changes |
| G1 / P0 / Qualification | Establish product and tenant capability matrix | `docs/capabilities.md`, `config.example.json` | G0 | Verify Kafka protocol/auth/network, paid AI capacity/region, permissions, ontology experience/API, agent source picker and monitoring | Dated pass/block evidence per surface | No assumed capabilities or paid resource provisioning; unsupported P0 marked blocked |
| D1 / P0 / Contract | Define source, identity, registry and fixture truth | `contracts/telemetry.schema.json`, `data/assets.csv`, `data/measurements.csv`, `data/relationships.csv`, `tests/fixtures/scenario-manifest.json` | G0 | Explicit nine-field schema, stable keys, synthetic units/thresholds, fixed-time expected counts | Versioned contract and deterministic scenario | Unique keys; valid parentage; 12 tags mapped; invalid/skew/duplicate policy documented |
| D2 / P0 / Simulator | Adapt one existing generator and publisher | `simulator/telemetry.py`, `simulator/publish.py`, `scripts/Invoke-Simulation.ps1`, optional notebook wrapper | D1, G1 | Extract reviewed bounded transport/pacing code; change payload builder; Kafka primary and endpoint fallback share corpus | Finite and continuous modes, rate/seed/run summary, manifests | Deterministic fixture; bounded memory; failed sends explicit; secrets/config absent from output |
| F1 / P0 / Ingestion | Provision minimal target items and configure source | `scripts/Deploy-Demo.ps1`, `fabric/eventstream/definition.json`, config | G1, D1 | Parameterize existing item/definition/LRO patterns; supported connector; manual credential binding | Target-scoped Eventhouse/DB/Eventstream and connection checklist | Dry run; repeated deployment no duplicate items; wrong-target refusal; actual Kafka records reconcile |
| K1 / P0 / Analytics | Install schema, normalization, functions and examples | `kql/00-schema.kql` through `kql/05-data-quality.kql` | D1, F1 | Narrow model; event-time correctness; actual receipt; curated dimension lookups; docstrings | Independently runnable query package | Fixture counts, units, ties, duplicates, disorder, invalid/unmapped and stale cases pass |
| O1 / P0 / Context | Create actual operational ontology and bindings | `ontology/model.yaml`, `ontology/bindings.template.json`, `scripts/Deploy-Context.ps1` | D1, G1, K1 | Load small Delta/reference tables; compile only supported contract; bind relationship instances and Eventhouse properties | Browsable instance hierarchy with source bindings | 26 entity instances and 24 required edges; correct measurement ownership; live value/time matches KQL |
| V1 / P0 / Dashboard | Build concise live operational view | `fabric/dashboard/build-spec.md`, `fabric/dashboard/queries.kql` | K1 | Native dashboard, asset/site filters, pressure/history, freshness and comparison | Rehearsable operations dashboard | Filters select scoped assets; no mixed units; stale state visible; measured refresh |
| A1 / P0 / Copilot | Validate NL-to-KQL surface | `agent/copilot-prompts.md`, KQL docstrings | G1, K1 | Precise saved prompts; inspect generated query; manually execute | Five tested prompts and results | Five of five prompts produce correct bounded results; no automatic-execution claim |
| A2 / P0 / Data Agent | Ground domain-aware Q&A | `agent/instructions.md`, `agent/evaluation.json`, `scripts/Test-AgentAnswers.ps1` | G1, K1, O1 | Supported KQL and ontology sources; UDF guidance; caller identity; manual setup unless automation verified | Published/shared agent and scored evidence | 10/10 positive prompts on fixture; all negative/denied/ambiguous/stale/write cases correct |
| M1 / P0 / Monitoring | Separate platform and asset observability | `kql/06-monitoring.kql`, `docs/monitoring.md` | F1, K1, G1 | Enable native metrics/monitoring collection; inspect available schemas and permissions | Flow, failures, freshness, latency and capacity view | Stop/restart producer visibly changes freshness; ingestion failure evidence available; platform logs not mistaken for asset readings |
| I1 / P0 / Architecture | Document enterprise coexistence and scaling | `docs/architecture.md`, `docs/coexistence.md` | G1, D1 | Decision tables, bounds, retention/isolation/security review and sizing assumptions | Customer architecture discussion package | Covers all named platforms and enterprise topics; clearly separates physical/follower/remote access |
| R1 / P0 / Rehearsal | Package setup, acceptance and fallbacks | `README.md`, `docs/manual-fabric-steps.md`, `docs/demo-runbook.md`, `scripts/Test-Demo.ps1`, `tests/`, `evidence/README.md` | D2, F1, K1, O1, V1, A1, A2, M1, I1 | Exact fixture and live verification; dated sanitized evidence; safe start/stop and repeat instructions | Complete P0 rehearsal package | Section 10 checklist passes; 15-minute story rehearsed; fallbacks labeled; no unapproved external notifications |
| P1-A / P1 / Action | One safe pressure notification | `fabric/activator/rule-spec.json`, derived Eventstream definition, manual runbook | D2, F1, K1, G1 | Supported enriched stream, per-asset threshold transition, freshness/suppression | Tested notice, not plant control | Normal/high/hold/duplicate/old/recover/retrigger tests; approved recipient only |
| P1-L / P1 / Sharing | Verify OneLake and optional Databricks read | `integration/onelake-read.py`, `integration/databricks-read.py`, coexistence runbook | F1, K1, G1, I1 | One eligible physical table; read-only completed-window reconciliation | Matching cross-engine values and measured lag | Same count/aggregate over aligned window; read-only source; no RLS inheritance claim |
| P1-S / P1 / Scale | Controlled ramp and historical backfill experiment | `scripts/Invoke-LoadProfile.ps1`, simulator replay support, `docs/performance.md` | D2, K1, M1 | 250 events/sec initial qualification profile, stepped bursts, chunked backfill and concurrent reads under approved budget | Reproducible throughput/latency/resource evidence | Actual achieved rate, errors/retries, counts and capacity reported; stop on budget/throttle threshold; no inferred enterprise certification |
| P1-D / P1 / Automation | Expand only supported artifact automation | Existing deploy/context scripts; capability record | G1, R1 | Add accepted dashboard/agent/ontology definition contracts only after export/API spike | Less manual setup without invented APIs | Fresh target and redeploy tests; explicit blockers on unsupported steps |
| P2-X / P2 / Coexistence | Optional live ADX/Snowflake route | `integration/` and coexistence docs | I1, G1, relevant external permissions | One separately qualified connector/query route at a time | Verified supplemental scenario | Document auth, locality, latency and data movement; never imply all routes are zero-copy |
| P2-3D / P2 / Physical | Reuse existing spatial prototype | `docs/physical-stretch.md`; external projectllama scene/config only after separate approval | O1, K1, G1, reuse permission | Stable AssetId-to-scene binding; existing geometry; initially cached telemetry inspection | Small operator-selects-compressor scene | Correct identity, timestamp and stale label; live scalar adapter separately scoped; core demo works without 3D |

**Execution order:** G0 -> G1 and D1 -> D2/F1 -> K1 -> O1/V1/A1/M1 -> A2 -> R1. I1 can proceed after G1/D1. P1 tasks can proceed once their listed prerequisites pass; they do not delay core P0 rehearsal.

## 7. File-by-file changes

Only this plan is created now. The paths below are **proposed**, not existing deliverables. No neighboring repository will be edited automatically.

| Proposed file | Change and source of reuse | Priority / task |
|---|---|---|
| `README.md` | New oil-and-gas setup, prerequisites, deployment order, start/stop, validation and manual-step links | P0 R1 |
| `.gitignore` | Exclude local config/secrets, run corpora, environments and private evidence; allow synthetic fixture/manifest | P0 D2/F1 |
| `config.example.json` | Placeholders only: workspace/item locators, Kafka/topic settings, source mode, registry location and demo policies; no live defaults | P0 G1/F1 |
| `requirements.txt` | Minimal dependencies actually needed by selected publisher/runtime; derive from reviewed reuse, not wholesale copied environments | P0 D2 |
| `contracts/telemetry.schema.json` | Exact nine-field synthetic contract; negative-test variants separate | P0 D1 |
| `data/assets.csv` | 14 structural instances across five asset levels with stable IDs | P0 D1 |
| `data/measurements.csv` | 12 measurement mappings, source/unit/full tag, owning asset/component, engineering units and synthetic thresholds | P0 D1 |
| `data/relationships.csv` | 24 required parent/measurement key-pair rows; unique typed edges | P0 D1 |
| `simulator/telemetry.py` | Single pure builder for nominal, rising pressure, recovery, late, duplicate, malformed and unknown-tag scenarios | P0 D2 |
| `simulator/publish.py` | Adapt approved Allstate pacing/retry/auth/corpus patterns; Kafka and endpoint adapters use same builder | P0 D2 |
| `scripts/Invoke-Simulation.ps1` | Validated mode/rate/duration/seed inputs and explicit finite/continuous run handling | P0 D2 |
| `fabric/notebooks/SimulateOperations.py` | Optional thin Fabric wrapper/package import of simulator only if notebook execution is selected; otherwise omit | P0 D2, conditional |
| `fabric/eventstream/definition.json` | Validated parameterized main topology; derived alert branch added only for P1 | P0 F1; P1-A |
| `scripts/Deploy-Demo.ps1` | Adapt scoped item discovery, pagination, definitions, LRO polling, dry run and failure handling; never create capacity automatically | P0 F1 |
| `kql/00-schema.kql` | Raw/typed/diagnostic/reference schema, mappings, ingestion-time policy and approved retention/cache settings | P0 K1 |
| `kql/01-normalization.kql` | Validation/normalization function and compatible update policies, raw reconciliation, original timestamps | P0 K1 |
| `kql/02-reference-data.kql` | Idempotent small dimension load tied to manifest/version; no duplicate append on redeploy | P0 K1 |
| `kql/03-functions.kql` | Curated functions from section 4.4 with docstrings, bounded filters and typed output contracts | P0 K1 |
| `kql/04-demo-queries.kql` | Latest, history, trend, abnormal, windows and comparison; independently runnable, presenter-sized blocks | P0 K1 |
| `kql/05-data-quality.kql` | Latency/skew, heuristic duplicate, disorder, unmapped, invalid, stale and future-time examples | P0 K1 |
| `kql/06-monitoring.kql` | Actual target schemas/management commands; distinct platform and business sections | P0 M1 |
| `kql/07-validation.kql` | Read-only fixture/live assertions with expected versus actual outputs | P0 R1 |
| `ontology/model.yaml` | Domain model, stable keys, labels, property types, relationship semantics and provenance; adapt one portable model pattern | P0 O1 |
| `ontology/bindings.template.json` | Item/table/column/property/key/timestamp mappings; no fabricated API fields | P0 O1 |
| `scripts/Deploy-Context.ps1` | Reference Delta table load plus supported ontology create/update/verification, or explicit portal checkpoint if contract unavailable | P0 O1 |
| `fabric/dashboard/build-spec.md` | Native layout, filters, tile query references, freshness and refresh configuration | P0 V1 |
| `fabric/dashboard/queries.kql` | Thin calls to shared functions, not duplicate analytical logic | P0 V1 |
| `agent/copilot-prompts.md` | Five precise questions, expected query semantics, as-of/window and manual Run instructions | P0 A1 |
| `agent/instructions.md` | Oil-and-gas glossary, grounding, units/freshness/identity rules, synthetic disclaimer and no-action boundary | P0 A2 |
| `agent/evaluation.json` | Positive and negative questions plus expected output fields/fixture-derived criteria; not fabricated transcripts | P0 A2 |
| `scripts/Test-AgentAnswers.ps1` | Score captured actual answers/results; use live API only if supported and qualified, otherwise consume exported/manual evidence | P0 A2 |
| `tests/fixtures/scenario-manifest.json` | Fixed seed/as-of, row groups, expected counts, known duplicates and hash | P0 D1 |
| `tests/test_telemetry.py` | Builder/schema/units/determinism/negative-case tests | P0 D2 |
| `tests/Test-Deployment.ps1` | Mock/dry-run target checks, pagination/LRO/failure/idempotence tests | P0 F1/O1 |
| `scripts/Test-Demo.ps1` | Opt-in read-only live structure, counts, KQL, binding and freshness checks; aggregate pass/block/fail output | P0 R1 |
| `docs/capabilities.md` | Exact experience/version/date, doc URLs, support status and tenant evidence/blockers | P0 G1 |
| `docs/architecture.md` | Source/time/identity decisions, physical boundaries, sizing/isolation/retention and backfill | P0 I1 |
| `docs/coexistence.md` | ADX remote versus follower versus physical landing; OneLake, Databricks, Snowflake, BI boundaries | P0 I1 |
| `docs/manual-fabric-steps.md` | Numbered portal tasks, required roles, validation and named blockers | P0 R1 |
| `docs/monitoring.md` | Accessible metrics/log sources, enablement, schemas, platform/asset separation and troubleshooting | P0 M1 |
| `docs/demo-runbook.md` | Section 5 sequence, exact prompts, preflight, fallbacks and safe reset/stop | P0 R1 |
| `evidence/README.md` | Evidence format, timestamps, synthetic-only disclosure, sanitization and local/private capture policy; no fake screenshots | P0 R1 |
| `fabric/activator/rule-spec.json` | Desired rule/fields/recipient placeholders, explicitly a specification unless a supported deployable contract is verified | P1-A |
| `integration/onelake-read.py` | Read-only completed-window comparison using actual exposed Delta path | P1-L |
| `integration/databricks-read.py` | Optional approved authenticated Delta read; secret references only | P1-L |
| `scripts/Invoke-LoadProfile.ps1` | Bounded ramps/backfill using existing simulator/corpus, stop budget and evidence output | P1-S |
| `docs/performance.md` | Reproducible measured profiles, bytes/records/latency/concurrency/capacity, limitations | P1-S |
| `docs/physical-stretch.md` | Existing-scene linkage, identity/geometry permissions, cached versus live limitations and independent acceptance | P2-3D |

Avoid adding a package framework, shared multi-customer library, new web application, second ontology compiler or generic integration abstraction unless implementation uncovers a concrete need.

## 8. Fabric manual configuration required

Some steps may later be automated with a documented and accepted API; this plan does not assume that they already are.

| Manual/tenant step | Responsible role | Repository support | Proof required |
|---|---|---|---|
| Select workspace, existing capacity, region, naming and spend approval | Fabric/workspace/capacity admin | Config template and dry-run plan | Correct approved target; no accidental neighboring-project deployment |
| Verify Fabric/Copilot/Data Agent/ontology tenant settings and eligible user groups | Tenant/capacity admin | Capability checklist and official docs | Actual UI/source availability; approved geography/data processing. AI requires paid F2+/P1+ under retrieved docs; trial is insufficient for KQL Copilot [S3, S5] |
| Approve broker/topic/authentication and network route; bind connection credentials | Kafka owner and Fabric connection owner | Connector/topology template, publisher settings | Target connector consumes approved topic; auth/network failures visible |
| Assign producer, deployer, viewer/agent permissions and approved secret access | Identity/workspace/data owners | Permission matrix; no committed credentials | Least-privilege positive/negative tests with actual identities |
| Create or bind Lakehouse and verify reference tables | Fabric engineer | Registry loader/context script | Unique entity rows and relationship key pairs visible |
| Select ontology experience; create/import/bind model; validate instances and properties | Fabric engineer/domain owner | Portable model and binding manifest | Hierarchy instances, mapped tag, units and Eventhouse property/time match; graph opt-in only if needed |
| Create/connect KQL Queryset and dashboard; set scoped filters/refresh | Presenter/Fabric engineer | KQL files and build spec | Correct database, five Copilot prompts, fresh/stale dashboard states |
| Create Data Agent; add KQL and ontology sources, instructions/examples; publish/share | Agent owner | Instructions/evaluation/runbook | Expected sources actually selected; authorized and denied-user tests; answer evaluations |
| Enable monitoring item collection and native workload diagnostics | Workspace/monitoring admin | Monitoring runbook/queries | New activity appears; permissions/retention known; no assumed historical backfill |
| Optional Activator object, stream mapping, condition, suppression and approved recipient | Rule/connection owner | Rule specification and scenario | Safe test notice; duplicates/stale replays suppressed; rule stopped after test if unused |
| Optional OneLake table availability/latency and consumer authorization | Database/data owner | Eligibility/read/reconciliation instructions | Delta file/path available, measured lag, completed-window comparison, downstream access tests |
| Optional Databricks/ADX/Snowflake access and external tool setup | External platform owner | Coexistence runbook | Route-specific authentication, locality, supported format and movement evidence |
| Capture/review sanitized screenshots and transcripts, rehearse and stop unused processes/rules | Presenter | Demo runbook/evidence policy | Dated evidence labeled live versus recorded; no sensitive or misleading output |

Do not equate HTTP 202, an ontology shell, source-picker selection, or successful local tests with a completed live deployment. Poll operations, then verify actual tables/bindings/records/answers.

## 9. Risks, dependencies and validation strategy

### 9.1 Principal risks

| Risk/dependency | Impact | Mitigation / gate |
|---|---|---|
| No target or approved broker identified | Kafka/demo deployment cannot be verified | G1 blocks live claims; endpoint fallback labeled; do not invent target IDs |
| Updated ontology preview differs from reused contracts | Failed import/binding or misleading hierarchy | Qualify current experience; validate one entity/relationship/timeseries binding before full model; preserve manual path |
| Relationship schema mistaken for actual context | Impressive diagram with no traversable instances | Count and traverse actual key-pair instances; reconcile the selected asset and tag |
| AI capacity/region/tenant policy unavailable | P0 AI story incomplete | Check first; dated recorded fallback for meeting only; do not label full P0 ready |
| Nondeterministic agent answers or unsupported UDF scope | Wrong units/window/site or unsupported recommendations | Curated schema, fixture-derived truth, source/query inspection and negative evaluation |
| Cross-customer code/data leakage | Confidentiality or reuse-rights issue | Reuse approved code only; no private data/endpoints/recipients; review copied files before publication |
| No source event identity | False deduplication or correction handling | Label heuristic; retain raw; define production source-ID/correction requirement |
| Clock skew/late data/empty stream | Wrong latest state, misleading latency or false notices | UTC contract; future/skew flags; event-time selection; stale and no-data outputs; alerts exclude old replay |
| OneLake lag, read-only constraints and RLS limitations | Live integration stalls or permissions misunderstood | Prewarm; show measured lag; use eligible synthetic table; test consumers independently |
| Small demo mistaken for enterprise proof | Unsupported sizing/cost commitments | Separate 10/sec rehearsal, 250/sec qualification and later representative scale tests; report resource/concurrency evidence |
| Backfill competes with live queries/ingestion | Throttling or failed presentation | Separate rate limits/windows, stop budget, prioritize live flow and monitor |
| Notification route or scalar 3D adapter unqualified | Demo distraction/unsafe action | P1/P2 only; approved recipients; no plant control; omit rather than fabricate |
| Internal diagnostics inaccessible | Broken monitoring experience | Native public Fabric diagnostics; no dependency on internal health backend |

### 9.2 Concrete acceptance evidence

**Offline deterministic fixture, proposed fixed reference time:** 2026-10-20T12:00:00Z. Store that time in the manifest and pass it into queries; do not rely on the wall clock.

- 120 valid unique recognized readings, including 8 deliberately late-arriving readings and 10 synthetic high-pressure readings.
- Add 12 exact replay duplicates, 6 invalid records (3 malformed event timestamps, 3 nonnumeric values), 5 valid-but-unknown-tag records, and 4 recognized but future-dated records outside tolerance.
- Expected raw count **147**. Typed/parse-valid rows **141**; explicit parse-reject rows **6**. Quality diagnostics identify **5** unknown tags and **4** future-dated rows. The recognized, time-eligible set is **132** before heuristic dedup and **120** afterward. Anomaly assertions evaluate the eligible deduplicated set and expect **10** high readings.
- Quality groups are deliberately disjoint in this fixture. Unknown/future rows are retained for diagnosis, not silently dropped. Real-world rows can have multiple quality flags, so production flag counts need not sum to total rows.
- Registry acceptance: **26 entities** (14 structural plus 12 measurements), **24 required edges**, no orphan measurements, no ambiguous lookup keys. Test the same `UnitNum`/`Compressor 1` label at different sites to demonstrate scoped IDs.
- Test conflicting equal-event-time readings separately; report ambiguity and use the documented deterministic display tie-break without claiming source correction semantics.
- A stop/start freshness test returns stale/no-observation rather than zero, healthy, or a disappeared asset. Test no data, malformed path, negative apparent latency, future data and missing unit.

**Live core rehearsal profile:** 10 events/second for five minutes, no intentional quality injections, plus a separately identified scenario run. Reconcile **3,000 unique generated events** against the run manifest/target window; record retries and any duplicate raw rows rather than demanding exactly-once transport.

Proposed demo SLOs, not Microsoft guarantees: p95 event-to-query-visible latency <=10 seconds for this low-rate profile, dashboard reflects changed data within 30 seconds, and every operational/AI answer states its time window and units. Measure query-visible arrival by polling and record source clock/observer assumptions; ingestion timestamps alone are not proof of query visibility. A failed threshold triggers investigation and explicit reporting, not selective exclusion.

**AI:** five Copilot prompts plus five Data Agent operational prompts must match fixture-derived data, identity, units and windows. All negative cases must handle absence/staleness/denial/ambiguity correctly. Capture the actual generated query/results where available. Recommendations require evidence and a synthetic-only/human-review boundary.

**Integration:** compare a closed event-time window that is fully available in both engines; match counts, per-tag values/aggregates and maximum event time. Report the measured OneLake observation lag separately.

**Deployment:** local tests do not create resources. Explicit live opt-in checks target IDs, parentage, source table, mappings, function output shape, ontology bindings, real rows and permissions. Redeploy must not append duplicate registry rows or silently target a same-named neighboring item. No cleanup/reset of shared resources without explicit approval.

## 10. Demo readiness checklist

All implementation readiness items remain **unchecked**. This planning assessment is not a readiness certificate.

### Approval and environment

- [x] Plan reviewed; user approved P0/P1 implementation and explicitly excluded P2. Reuse only synthetic assets and reviewed patterns.
- [ ] Repository destination/version-control decision approved; target config uses placeholders until authorized.
- [ ] Workspace, paid AI-eligible capacity/region, identities, network and broker qualified.
- [ ] Current ontology experience/API and agent sources verified; P0 blockers explicitly closed.

### Data

- [ ] Single adapted generator/corpus available; synthetic labels and deterministic seed recorded.
- [ ] Nine-field schema/time semantics validated; units and authoritative keys documented.
- [ ] Kafka source receiving data in Eventstream and Eventhouse; fallback lane separately labeled.
- [ ] Fixture counts 147/141/6/132/120 and quality/anomaly expectations pass.
- [ ] Latest/history/trend/comparison/latency/duplicate/disorder queries tested.
- [ ] No-data/stale/future/invalid/unknown and same-name-across-sites cases tested.
- [ ] Live rate, 3,000-event reconciliation and query-visible latency evidence captured.

### Context

- [ ] Ontology created in the selected supported experience.
- [ ] 26 entity instances and 24 required relationship instances validated.
- [ ] Stable source/unit/tag mapping and ownership correct; no orphan or ambiguous measurement.
- [ ] Selected compressor's Eventhouse value, unit and event time match its bound context.
- [ ] Graph materialization/refresh, if used, labeled separately from live source freshness.

### AI

- [ ] KQL Queryset write access, data access, docstrings and Copilot tenant settings verified.
- [ ] Five Copilot scenarios tested; presenter reviews and manually runs generated KQL.
- [ ] Data Agent configured with actual supported KQL/ontology grounding and published permissions.
- [ ] Five operational agent questions and all negative/ambiguous/denied/stale/write cases pass.
- [ ] Answers state asset/site, units, time/window, evidence and limitations; no fabricated diagnosis.

### Operations

- [ ] Platform monitoring collection active; actual logs/metrics queries tested.
- [ ] Business freshness/pressure views separate from platform flow/capacity views.
- [ ] Producer stop/restart and ingestion/error diagnostics demonstrated.
- [ ] Activator transition/duplicate/old/recovery tests and approved recipient validated, if included.
- [ ] Unused simulator processes and Activator rules can be safely stopped.

### Integration and scale

- [ ] OneLake scenario validated on an eligible physical table, if included.
- [ ] Measured Delta availability lag and completed-window reconciliation recorded.
- [ ] KQL versus downstream permissions tested independently; no unsupported RLS inheritance.
- [ ] ADX federation/follower/physical ingestion boundaries and same-region prerequisite documented.
- [ ] Databricks, Snowflake, Power BI and external-tool coexistence routes honestly scoped.
- [ ] Central/federated topology, isolation, retention/cache, capacity, governance and backfill path documented.
- [ ] Any load results labeled with actual rate/bytes/concurrency/resources; no unsupported enterprise throughput claim.

### Presentation

- [ ] README includes repeatable setup, manual configuration, validation and start/stop instructions.
- [ ] Seven-stage sequence rehearsed in approximately 15 minutes.
- [ ] Sample questions and expected evidence documented.
- [ ] Dated synthetic-only fallback screenshots, transcripts and query results captured and sanitized.
- [ ] Live, recorded, simulated and hypothetical material visibly distinguished.
- [ ] Optional 3D uses existing assets with explicit cached/live limitations; core does not depend on it.

### Official capability sources

These are primary documentation sources retrieved for this plan, not proof of target-tenant enablement. Recheck at implementation time. Search-generated summaries were not treated as product contracts.

- **S1:** [Ontology overview (preview)](https://learn.microsoft.com/en-us/fabric/iq/ontology/overview) - updated experience, bindings, optional graph execution, old-experience retirement January 31, 2027.
- **S2:** [Bind ontology data](https://learn.microsoft.com/en-us/fabric/iq/ontology/how-to-bind-data) and [create relationship types](https://learn.microsoft.com/en-us/fabric/iq/ontology/how-to-create-relationship-types) - supported sources/types, source mappings and relationship instances.
- **S3:** [Copilot for writing KQL queries](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/copilot-writing-queries) - prerequisites, paid capacity, manual execution and no control-command generation.
- **S4:** [Copilot for RTI](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/copilot-real-time-intelligence) - querysets, dashboards, ADX support and metadata best practices.
- **S5:** [Fabric Data Agent concept](https://learn.microsoft.com/en-us/fabric/data-science/concept-data-agent) - GA status, prerequisites, KQL/UDF support and caller authorization.
- **S6:** [Create a Fabric Data Agent](https://learn.microsoft.com/en-us/fabric/data-science/how-to-create-data-agent) - current source types, user identity, configuration and governance.
- **S7:** [Fabric Activator introduction](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/data-activator/activator-introduction) - streams, per-object state, conditions and notification/action types.
- **S8:** [Eventhouse OneLake availability](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/event-house-onelake-availability) - physical table exposure, adaptive latency, read-only representation, retention and restrictions.
- **S9:** [Database shortcuts](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/database-shortcut) - ADX/KQL read-only follower-like semantics, source storage, synchronization and locality.
- **S10:** [OneLake and Azure Databricks](https://learn.microsoft.com/en-us/fabric/onelake/onelake-azure-databricks) - authentication/read approaches and links to catalog federation; qualify the actual Eventhouse-exposed path.
- **S11:** [Workspace monitoring overview](https://learn.microsoft.com/en-us/fabric/fundamentals/workspace-monitoring-overview) - opt-in collection, supported workload logs and no historical backfill.
- **S12:** [Copilot in Fabric overview](https://learn.microsoft.com/en-us/fabric/fundamentals/copilot-fabric-overview) - tenant/capacity policy and workload-specific scope.

**Review boundary:** approve or revise this plan before implementing any proposed files, copying reusable code, publishing a repository, configuring Fabric, or incurring infrastructure costs.
