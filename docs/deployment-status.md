# Deployment status

Observed October 21, 2026, UTC. **P0/P1 only; P2 excluded.**

## Target and readiness

- Workspace: `21733624-95b6-4740-b892-d29ff7889aa4`.
- Folder: `Dev/Matthieu/OilandGas`, ID `975ffc5a-edee-4558-a62d-3a2bfe72110c`.
- All eleven primary items were verified in this folder by `Test-Demo.ps1`
  at `2026-10-21T08:35:53Z`; 21 scoped items include ten generated companions.
  Service-generated GraphModel/Lakehouse/SQL endpoint companions are also present
  in the folder, including backing items from earlier failed ontology imports.
  The complete scoped inventory is retained in acceptance evidence; none was
  silently deleted.
- Capacity assignment and West Central US region were observed, but the assigned
  capacity was not in the caller's accessible capacity list; no SKU is asserted.
- **Not ready for an end-to-end live Kafka/ontology/AI/notification demonstration.**
  The analytical core, native graph traversal, KQL agent answers and OneLake
  reads are verified; gates below remain open.

## Deployed inventory

| Item | Type | ID | Verified state |
|---|---|---|---|
| OilGasEventhouse | Eventhouse | `373dfd01-aaf5-483b-948b-db082b3a2e2d` | Created; database parent verified |
| OilGasOperationsDB | KQLDatabase | `9c562b46-9eaa-48b0-a1e9-19ccae2c272d` | Tables, policies, functions and fixture queries execute |
| OilGasTelemetryStream | Eventstream | `6df5df38-9866-43eb-8e12-251c90fd11cd` | Custom source Running; direct-ingestion destination Warning; zero accepted publishes |
| OilGasReference | Lakehouse | `8c85629d-eecd-4c9f-b005-b19ea610a08d` | 13 Delta tables registered and their contents read back |
| OilGasOperationsDashboard | KQLDashboard | `18f4d9bb-db7d-4186-9126-8306d49a1d90` | Definition accepted; browser rendering not validated |
| OilGasOperationalQueries | KQLQueryset | `fc9f4ecb-ce2a-4689-b9cf-69fd7cef5fc2` | Six tabs accepted; Copilot interaction not validated |
| OilGasLoadReference | Notebook | `3f768b78-766c-433e-a7f5-92459045f01b` | Optional Spark loader; attempted run failed; direct Delta loader succeeded |
| OilGasOperationalOntology | Ontology | `75a895c2-503c-4d13-8886-a2899cf83694` | Native backing graph counts/path and compound-key KQL join verified; time-series UI untested |
| OilGasOperationsAgent | DataAgent | `9d79ef9f-ec96-48e2-ad90-ea7b5587a368` | Published with existing permissions; KQL answers verified; context CSV formatting fails strict acceptance |
| OilGasPublishTelemetry | Python Notebook | `0513644a-29dc-47e8-b2b1-d10f84571b4d` | Finite shared publisher on Jupyter; actual send returned HTTP 401; terminal job |
| OilGasPressureAlert | Reflex | `472fc9fd-8084-4219-833f-310a10067f7b` | Stopped KQL source, scoped object/attributes; no rule/action/recipient |

No external infrastructure or P2 item was created. No notification recipient
or delivery connection was supplied/approved. No
notifications, equipment actions, permission changes or capacity resizing occurred.

## Measured acceptance

The 147 input records were ingested **directly using inline KQL ingestion**.
They did not pass through Kafka or Eventstream. All 15 assertions in
`kql/07-fixture-assertions.kql` passed against the actual database:

| Assertion | Expected and observed |
|---|---:|
| Raw rows / parse-valid / invalid | 147 / 141 / 6 |
| Eligible before dedup / deduplicated | 132 / 120 |
| Unknown tags / future events | 5 / 4 |
| Synthetic threshold exceedances | 10 |
| Registry/latest coverage / fresh at explicit fixture as-of with 15-minute tolerance | 12 / 12 |
| Missing observations after a two-day gap remain stale, not normal | 12 |
| SITE-A measurement coverage | 6 |
| Separate metric/unit pairs | 3 |
| Actual raw receipt timestamps populated | 147 |
| Python versus KQL fingerprint parity | Exact match |

The generator fixture also includes eight late arrivals and 12 exact replay rows.
Local automated tests cover those counts, deterministic generation, equal-time
conflict fingerprints, invalids, sender bounds/retries and sanitized failures.
**35 Python tests passed** in the optional Fabric environment. All **19
PowerShell scripts parsed**, eight deployment/ingestion `-WhatIf` paths passed, six
ingestion-mode regression cases and 29 agent-output cases passed, and local
README/plan/runbook links resolved. All five historical demo query blocks
executed (12, 10, 39, 2 and 6 rows respectively); the prospective Activator feed
returned zero rows for stale historical data, as intended.
The full live KQL equal-time-conflict latest-selection scenario has not been
injected; that behavior is not represented as separately runtime-certified.

Telemetry fixture SHA-256:
`4123ef1f5e24226a617faca6828d091d8b6b456069094e8f7da848443877a3a9`.

### Direct Eventhouse samples

The user requested a separate direct Eventhouse route.
`Invoke-DirectIngestion.ps1` reuses the shared generator and the existing
`TelemetryJson` mapping. It appends bounded inline micro-batches, verifies raw
receipt using acknowledged extent IDs, and records each run without secrets.
It does not alter either Eventstream or its networking.

At `2026-10-21T08:53:39Z`, the live smoke test acknowledged and independently
verified **12 new raw rows**. A subsequent actual KQL query confirmed **12
normalized receipts**, total raw/typed counts of **159/159**, and **12 fresh
measurements at that query time**. Freshness is time-dependent, not permanent.
The first local generation attempt rejected seven-digit fractional timestamps;
the helper now supplies the generator's six-digit precision, with a regression
check. Its failed, zero-ingestion evidence is preserved.

The original 147-row proof above is historical, not the current table size.
Do not rerun exact fixture/OneLake counts after these additions. Direct inline
ingestion is for small demonstrations/prototyping, not production throughput,
the streaming ingestion API or Eventstream preview.

The requested three-hour volume load **completed successfully**.
The detached direct-ingestion run started at `2026-10-21T09:02:42.5978221Z`
and finished at `2026-10-21T12:02:42.6783252Z`
(05:02:42 Pacific daylight time), with a measured duration of **10,800.034 seconds**.
It completed **1,080 batches of 100 rows**, ten seconds apart, using the shared
normal/high/recovery generator. Final independent KQL checks verified:

| Three-hour run check | Observed |
|---|---:|
| New raw rows | 108,000 |
| New normalized rows | 108,000 |
| Distinct normalized fingerprints | 108,000 |
| Parse errors in this run | 0 |
| Database raw / normalized total, including earlier data | 108,187 / 108,187 |

The process exited with code zero, stopped automatically and removed its
temporary generator directory. No loader remains running. Runtime evidence is
recorded in
`local-only/direct-ingestion-evidence-f51c7992e2a240d0b520c1fdc2b5ac39.json`;
the independent final proof is
`local-only/direct-load-final-verification-f51c7992e2a240d0b520c1fdc2b5ac39.json`.
The command ID was `oilgas-direct-3h-volume`.
This is direct Eventhouse proof, not Eventstream/Kafka or notification proof.
Do not reload the fixture or run original exact-count assertions against this
larger database. Current observations naturally become stale after the load ends.

### Reference OneLake read

Direct materialization uploaded Parquet before committing Delta logs and read
the committed tables back through OneLake and delta-rs. Exact contents matched
the generated snapshot. Subsequent runs verified without overwriting:

| Tables | Rows |
|---|---|
| Site / Battery / System | 2 / 2 / 2 |
| Compressor / Component / Measurement | 4 / 4 / 12 |
| Relationship | 24 |
| Edge_Site_Battery / Edge_Battery_System / Edge_System_Compressor | 2 / 2 / 4 |
| Edge_Compressor_Component / Edge_Component_Measurement / Edge_Compressor_Measurement | 4 / 4 / 8 |

These are source-table/edge proofs, independently checked by native graph queries below.
The native ontology export was also read back: 27 parts, six entity definitions,
six relationship definitions, six contextualizations and the expected Eventhouse
Telemetry time-series source. Definition readback alone does not prove traversal.
Non-schema Lakehouse bindings omit `sourceSchema`; the Measurement entity has
the compound telemetry key Source + UnitNum + Name. Component ownership is
retained separately from the normalized compressor AssetId.

### Native graph and published agent

The actual ontology backing GraphModel is
`8a353ad0-08b4-467f-968a-bfe47b7b66ee`. The supported beta GQL API verified
Site/Battery/System/Compressor/Component/Measurement counts of **2/2/2/4/4/12**,
**24 relationships**, and this full native path:

`SITE-A -> BAT-A -> SYS-A -> CMP-A1 -> THR-A1 -> MSR-A1-DP`.

Its Source + UnitNum + Name matched exactly one historical KQL pressure
measurement in `psi`. The shared reproducible query is
[site-a-pressure.gql](../ontology/site-a-pressure.gql). This is an actual graph
query, not a registry-table fallback. Native time-series UI remains untested.

The published agent has eleven curated functions and three registry tables
selected; raw tables/internal normalization are unselected. Six legacy ontology
entities and six node/six edge types from the actual GraphModel are configured.
The schema-supported `graph` datasource points to the GraphModel, never the
Ontology item ID.

Measured published MCP conversations:

- Historical 11:00-12:00 UTC count: **10 readings (unit: psi)**, exact requested UTC
  observation window; strict CSV acceptance passed.
- At `2026-10-21T07:48:29Z`: **0 fresh, 12 stale, 0 missing**, all twelve
  measurement IDs, appropriate units and old event times; strict acceptance passed.
- Ambiguous "Compressor 1": returned both CMP-A1/SITE-A and CMP-B1/SITE-B,
  explicitly stale and not a diagnosis; the latest strict evaluation passed.
- Site inventory: six scoped measurements for CMP-A1/A2 in SITE-A, with correct
  metric/unit and actual query as-of metadata; strict acceptance passed.
- Historical comparison: six rows matched independent KQL ground truth for
  averages/minima/maxima rounded to three decimals, samples, units, latest
  timestamps and the requested UTC window; strict acceptance passed.
- Legacy ontology-tool traversal produced planner path-limit errors, including
  on bounded subpaths. Earlier correct answers are preserved but do not override
  these failures.
- The GraphModel source retrieved the correct full path after a verified GQL
  few-shot. Its returned CSV nevertheless JSON-encodes every string scalar,
  leaving literal quote characters in IDs/units. **GraphPath acceptance fails**;
  neither prompt guidance nor an exact-query diagnostic removed this encoding.
  The latest published version was retested at `2026-10-21T08:37:57Z` and still
  fails. Native GQL returns both raw properties and explicit string casts as
  `gqlType: STRING`, `jsonType: string`, with the correct unquoted value.
  This is not repaired by changing the registry or trimming agent output.
  The evaluator deliberately does not strip it into a success.

RPC completion, semantic acceptance and source configuration are distinct.
The MCP response exposes resource/deep links, not underlying generated-query
traces. Denied-identity testing, KQL Copilot and browser rendering remain untested.

### Eventhouse OneLake read

At `2026-10-21T07:27:34Z`, the independent reader reopened:

`9c562b46-9eaa-48b0-a1e9-19ccae2c272d/Tables/Telemetry`

under this workspace in OneLake. Result: **147 rows, Delta version 1**, 23,627
downloaded bytes; event-time range `2026-10-20T11:50:00Z` through
`2026-10-20T12:02:03Z`. The latter includes deliberately future-dated fixture rows.
Availability is configured with a five-minute target, not a measured live
latency SLA. The backfill toggle affected only this synthetic table's mirroring
policy, not the Eventhouse source rows.

### Local load preparation

A bounded 3,000-row, 1,127,000-byte synthetic corpus was generated with an
intended 100 events/second event-time profile, using the same generator.
SHA-256 `54880f29c3f4d2cdb2f490a658fb88444040ff68cb472adeee8be11c0a184887`.
This was **file generation, not a 100 events/second ingestion benchmark**.

## Validated deviations from the original design

1. **Value is a numeric string on the wire.** This preserves one Eventstream
   type across normal and deliberately invalid samples; NumericValue is parsed
   explicitly in KQL. Original text remains available.
2. **Queued ingestion rather than streaming ingestion on RawTelemetry.** Fabric
   rejected `ingestion_time()` inside a transactional update policy with
   streaming ingestion enabled. Disabling streaming and configuring a 10-second
   ingestion batching target preserves actual raw receipt and transactional
   normalization. End-to-end latency at or below ten seconds is not certified.
3. **Legacy JSON ontology.** Its documented direct Kusto time-series contract
   was accepted. That experience retires January 31, 2027; migration to the
   current TMDL experience is a release gate, not a perpetual supported design.
   No undocumented TMDL Kusto binding has been invented.
4. **Published KQL plus preview context sources.** Native ontology uses the
   tenant-supported separate ontology part, not an invented generic enum.
   The documented generic `graph` source uses the actual backing GraphModel.
   KQL conversations pass; legacy planner and GraphModel scalar-encoding failures
   keep full context-answer acceptance open.
5. **Direct Delta materialization instead of Spark.** The notebook job
   `5fcac1d1-580a-4d19-b60f-c2f2c2f6a642` ended Failed with
   `System_Cancelled_Session_Statements_Failed`; the isolated OneLake uploader
   subsequently materialized and verified all 13 tables successfully.
6. **Direct-ingestion Eventstream destination.** Replaced the failed processed
   ASA node with a fresh documented direct-ingestion node. Its status is Warning;
   transport remains blocked. Both deployment entry points preserve the recorded
   mode unless explicitly overridden, preventing accidental processed-mode regression.
7. **Safe Activator scaffold instead of an unapproved rule.** Fabric rejected a
   rule with an empty action step. No placeholder recipient was invented. The
   source/object/identity/pressure attributes are deployed stopped. An explicitly
   supplied recipient can author a stopped threshold baseline, but sustained
   duration, recovery, cooldown and delivery remain unqualified.

## AMQP connection diagnostic

The selected Running source `964f865d-69ac-4c16-99bd-d928c9d2b611` matches
the user-supplied endpoint host, entity path and SAS policy name. The pasted
secret was not persisted or compared byte-for-byte; probes fetched the current
primary connection string from Fabric and held it only in process memory.

The official Azure Event Hubs SDK 5.15.1 failed before sending an event.
Its native uAMQP 1.6.11 implementation on port 5671, with certificate verification
enabled, returned the explicit service response:

> Status code: 401. Ip has been prevented to connect to the endpoint.

Service timestamp: `2026-10-21T08:32:29`. Tracking ID:
`2274cee5-7a5d-4537-b0bd-23675600069a_G1`.
Zero events were accepted and no sustained publisher was started.
The `verify_none` URI option was not used. No browser, networking changes,
permission changes or Eventstream redeployment were used.

The SDK diagnostic dependencies are recorded in
[requirements-eventhubs.txt](../requirements-eventhubs.txt); this does not add
an AMQP transport to the shared REST/Kafka/stdout publisher.
Nonsecret probe evidence is retained in `local-only/amqp-evidence.json`.
The workspace/network owner must review the applicable inbound network policy
and approve a permitted publishing path. Do not disable security controls to
work around the rejection. Rotate the connection key exposed in chat after
the demonstration, using the owner's approved procedure.

Read-only calls to the documented workspace network policy and inbound firewall
APIs subsequently returned **inbound Allow, outbound Allow, zero firewall rules**.
These workspace settings do not explain the managed endpoint's denial. Do not
change them speculatively or widen access. The owner/Fabric support investigation
must identify the effective managed-endpoint or inherited restriction, using the
tracking ID above; its exact configuration is not established by these APIs.

The user subsequently created **EVstream**, item
`27f52415-5e67-4402-92d3-ae6d5a18acf6`, in the approved folder. Its Running
`telemtrysourceendpoint`, ID `9b7aa6be-a850-4c68-91eb-cb72086e86db`, matches
the newly supplied endpoint/policy. A fresh-primary-key native AMQP probe with
verified TLS also failed with an explicit IP access denial and zero accepted
events. Both primary/secondary credential slots identify this same single
source; they are not separate sources. No sustained sender was started and
the manually authored stream was not changed. Evidence is retained in
`local-only/new-eventstream-amqp-evidence.json`.

## Open gates and owners

| Gate | Evidence / next action |
|---|---|
| Eventstream publishing | REST and verified-TLS native AMQP both returned HTTP/status 401 with an explicit IP access denial. The source host/entity/policy match. Workspace policy reads Allow/Allow with zero firewall rules, so those settings do not explain it. Zero accepted events; no active publisher. Owner/Fabric support must identify the effective managed-endpoint restriction; no networking controls were changed. |
| Eventstream destination | Latest read-only topology after manual edits reports Eventhouse (`dafec227-1a44-4b80-b8fd-9963f0546166`), Warning. Preserve the manual configuration and confirm receipt/health after owner remediation; do not redeploy the retired ASA node. |
| External Kafka | No existing Fabric connection/topic supplied; custom endpoint is not Kafka proof. Qualify the intended connector, schema and offset/replay behavior before replacing the fallback. |
| Ontology UI and migration | Native counts/path and historical graph-to-KQL join passed. Verify the interactive time-series UI; migrate the retiring JSON experience before January 31, 2027. |
| AI | All five published operational KQL cases passed strict acceptance. Fabric owner/support must qualify legacy ontology planning and correct GraphModel scalar serialization; strict context acceptance stays false. Generated-query traces and genuinely denied-user behavior remain separate gates; browser-based checks are prohibited by the user. |
| Activator | Stopped scaffold exists with no rule or delivery action. Obtain an approved test recipient, author/qualify sustained high/recovery/cooldown behavior, then explicitly approve delivery. No recipient can be inferred. |
| Live load and latency | Publisher works locally, but transport rejects the network. Run the bounded staged profile only after ingestion works; collect destination receipts, quality, latency, query times and cost. |
| Dashboard and presenter rehearsal | The user explicitly prohibited assistant browser use for security reasons. Automated checks remain API/CLI-only; human owner/presenter UI validation is separate. Rendering, Copilot UI, ontology time-series UI and the complete 15-minute narrative remain unverified; native graph traversal itself passed. |

See [manual steps](manual-fabric-steps.md) and [load qualification](load-testing.md).
Raw machine evidence is retained in ignored `local-only/deployment.json`,
`acceptance.json`, `reference-delta-evidence.json`, `onelake-evidence.json`,
`ontology-evidence.json`, `agent-selection.json`, agent evaluation files and
terminal notebook job evidence. The notebook scheduler's Completed state did
not mean successful publishing: its exit value reported Failed/HTTP 401 and
the parent runner correctly raised an error. No publisher job remains running.
Do not distribute tokens, connection strings or endpoint access keys.
