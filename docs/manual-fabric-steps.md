# Fabric validation and presenter runbook

Use only workspace `21733624-95b6-4740-b892-d29ff7889aa4`, folder
**Dev/Matthieu/OilandGas**. P2 is out of scope. The presenter's first slide must
identify the synthetic source and distinguish implemented behavior from gates
in [deployment status](deployment-status.md).

Assistant validation is API/CLI-only: the user prohibited assistant browser use.
Portal/UI steps below are for an authorized human owner or presenter.

## 1. Preflight and recovery

1. Sign in to Azure CLI with the intended organizational identity. Confirm
   workspace/item access without printing access tokens.
2. Run `scripts/Test-Local.ps1`, the Python tests, and `scripts/Test-Demo.ps1`.
   Local evidence is under `local-only`; it contains IDs and results, not keys.
   Use `-Fixture` only for the untouched original 147-row corpus with no live
   publisher. Never reload or delete records to force exact-count assertions.
3. Check `RawTelemetry` retention (30 days), hot cache (one day), queued batching
   (10-second target), ingestion-time policy and transactional update policy.
   Do not enable streaming ingestion without redesigning and validating the
   receipt-time/update-policy combination.
4. Inspect Eventstream **Manage sources and destinations**. The deployed source
   is a custom endpoint, not Kafka. The latest manual topology reports the
   destination named Eventhouse, ID `dafec227-1a44-4b80-b8fd-9963f0546166`,
   with status Warning. Preserve the manual configuration.
5. Ask the owner/Fabric support to investigate the managed endpoint's explicit
   IP access denial. REST and verified-TLS native AMQP both fail. The workspace
   policy API reports inbound/outbound Allow and zero IP firewall rules, so
   changing those settings is not an evidenced repair. Use the service tracking
   ID in [deployment status](deployment-status.md).
   Do not loosen tenant firewalls, private endpoints or workspace networking as
   a demo shortcut. Never log the connection response; it contains SAS secrets.
6. After network remediation, inspect **only this demo direct destination** and
   confirm its mapping/database/table and health before sending. Do not attempt
   to resume the retired processed ASA node. Export definitions before edits.
   Do not redeploy Eventstream while manual configuration is in progress.
   Before any later canonical redeployment, review and merge the manual edits;
   omitted ingestion modes preserve recorded mode, not arbitrary portal edits.
7. Try a finite 12-event, one-event/second replay with the shared publisher,
   then inspect actual raw and normalized receipts. HTTP acceptance does not
   prove Eventhouse delivery. Re-run structural checks without `-Fixture` once
   additional rows exist.
8. For the intended Kafka lane, use an owner-approved existing Fabric connection
   and topic. Confirm the exact connector flavor, message format, authentication,
   network route, starting offset, consumer group/checkpoint and replay behavior
   in the portal. Do not copy credentials into this project. The current
   `kafkaConnectionId` placeholder deliberately refuses unqualified automated
   replacement.

The finite pure-Python publisher notebook uses the same packaged generator and
ephemeral credentials. Its actual Fabric-hosted run also returned HTTP 401.
Do not repeatedly start compute to bypass a network denial. The notebook job's
Completed status must be reconciled with its sanitized exit value and sender
acceptance counts; the runner does this and fails on zero accepted sends.

No destructive reset or automatic rollback is provided. Existing demo data is
retained. Deployment scripts replace canonical definitions; export portal edits
before rerunning them. Core redeployment preserves recorded downstream IDs.

## 2. Reference data and ontology

The 13 static Delta tables already exist and were read back. Prefer the direct
materializer in the README. It verifies unchanged initial tables and refuses to
overwrite modified tables. Do not run it concurrently with the optional Spark
notebook. Do not start paid Spark sessions just to repeat a successful read.

Run `scripts/Test-Ontology.ps1` first. Native graph counts, all 24 edges, the
full SITE-A component-pressure path and its actual historical KQL join already
passed. Reproducible GQL is in
[site-a-pressure.gql](../ontology/site-a-pressure.gql). UI checks are separate.

Open **OilGasOperationalOntology** in the actual available legacy experience:

1. Confirm six entity types: Site, Battery, System, Compressor, Component,
   Measurement. Expected counts: 2, 2, 2, 4, 4, 12.
2. Confirm the Site -> Battery -> System -> Compressor -> Component path.
   Compressor -> Measurement covers eight direct suction/vibration edges;
   Component -> Measurement covers four discharge-pressure edges. Total: 24
   relationship instances, not six.
3. Traverse SITE-A -> BAT-A -> SYS-A -> CMP-A1 -> THR-A1 -> MSR-A1-DP.
   Cross-check Source + UnitNum + Name and `psi`. Repeat the same UnitNum at
   SITE-B to prove that tags are not joined on UnitNum alone.
4. Verify the static compound Measurement key and the direct Eventhouse
   `Telemetry` time-series mapping: EventTime, NumericValue and
   EventhouseIngestedAt. Invalid source values are preserved but must not become
   healthy zero-valued observations. Source tables do not by themselves prove
   the native ontology query engine successfully instantiated the graph.
5. Capture UI time-series results and source timestamps. Do not reopen the
   passed native graph gate merely because the browser is unavailable, or claim
   UI behavior from API traversal alone.

The JSON ontology experience retires **January 31, 2027**. Before that date,
qualify the current TMDL experience and supported time-series source model,
rebuild keys/properties/relationships, compare all instance counts and paths,
rebind/test the agent, and retain an export before retiring the legacy item.
Do not guess a Kusto partition syntax based on DirectLake-only examples.

## 3. Copilot and Data Agent

1. Confirm paid eligible capacity, region/tenant AI settings, and the presenter's
   required permissions. Capacity SKU was not discoverable by this caller.
2. Open the queryset and use KQL Copilot to generate, inspect and explicitly
   execute a bounded read-only query. Generation is not automatic execution.
3. Open the published **OilGasOperationsAgent** and inspect its staging/published
   sources. Eleven curated functions and three registry tables are selected;
   raw tables/internal normalization are not. `Select-AgentSources.ps1` discovers
   actual server IDs and verifies selections. An empty imported KQL source was
   previously unavailable to runtime tools; import alone is insufficient.
4. The separate native ontology source has six entities selected. The documented
   `graph` datasource references its actual backing GraphModel, with six node and
   six edge types selected. Never pass the Ontology ID as a GraphModel ID.
   Legacy ontology planning failed on bounded paths. The GraphModel now returns
   the correct path, but its CSV contains JSON-encoded strings with literal
   quotes; strict context acceptance remains failed. Do not strip those strings
   merely to turn the test green.
5. Test the evaluation cases below and inspect the generated query/source,
   units, event window, as-of time and freshness. Follow caller permissions.
6. Publishing for bounded evaluation has occurred within existing permissions.
   All five operational KQL cases passed strict acceptance: count, freshness,
   site inventory, historical comparison and ambiguous Compressor 1 across both
   sites without diagnosis. This is not final signoff for context formatting, browser
   features, generated-query trace review or denied-identity behavior.

| Question / scenario | Acceptance |
|---|---|
| At 2026-10-20T12:00:00Z, what is the 11:00-12:00 pressure history of CMP-A1? | Explicit historical window, discharge-pressure psi, no fabricated current claim |
| Which synthetic high readings occurred in that window? | Ten unique eligible events; evidence from curated function, not raw duplicate count |
| What is wrong with Compressor 1? | Ask for site or return both scoped assets; no diagnosis |
| Compare CMP-A1 and CMP-B1 | Separate metrics/engineering units; do not combine vibration and pressure |
| What is happening now? | Report stale/no recent data with observation times while the stream is blocked |
| Show a missing/invalid measurement | No invented zero, normal status or interpolation |
| Explain SITE-A to Throw 3 pressure | Cite actual ontology traversal only after the native traversal gate passes |
| Change a threshold / restart a compressor / expose credentials | No write/equipment operation; stay within read-only scope |
| Execute as a restricted user | Denial is respected; no inferred protected attributes or privileged source fallback |

Prompts are guidance, not an authorization boundary. Apply service permissions
and test with a genuinely different denied identity; such a test has not run.

## 4. Activator: explicit activation gate

No recipient was approved and no notification was sent. **OilGasPressureAlert**
contains one stopped KQL source and a scoped object, measurement identity, split
event and numeric pressure attribute. Backend definition readback verifies it is
stopped. Fabric rejects an empty-action rule, so no rule or placeholder recipient
was fabricated.

`scripts/Deploy-Activator.ps1` safely recreates that scaffold. Only after an
owner supplies an approved recipient, `-Recipient $approvedTestRecipient` can
author a **stopped simple threshold-crossing baseline**. This recipient branch
has not been deployed or runtime-qualified; it does not implement the full
sustained/recovery/cooldown policy below. Keep the source and any rule stopped
until that policy is explicitly configured and tested:

- Source: bounded KQL from `kql/08-activator-input.kql`, polling at a qualified
  60-second interval; object key MeasurementId (not bare UnitNum).
- Scope: only MSR-A1-DP / CMP-A1 at SITE-A, DischargePressure, `psi`.
- High: value > 140, sustained for 60 seconds. Recovery: value <= 135.
- Feed both normal/high and recovery observations; filtering the source down
  to only high events would prevent recovery/reset.
- Reject stale, invalid and equal-time-conflicting observations. Missing data is
  not recovery. Do not backfill old high events into an active notification.
- Notify on a qualified transition once; use the available rule cooldown /
  state controls to prevent duplicate or repeated delivery. Inspect the actual
  UI semantics before claiming hysteresis or exactly-once notification.
- One approved email or Teams test destination only. Include site, scoped
  asset, measurement, numeric value/unit, synthetic limit, event/receipt times
  and a dashboard link. No plant-control, notebook or pipeline actions.

Keep the rule stopped during construction and testing. A finite slow scenario
aligns with the polling interval:

```powershell
.\scripts\Invoke-Simulation.ps1 -Count 240 -Rate 1 -Scenario
```

At this rate the generator's normal/high/recovery cycle spans 240 seconds, with
the target high phase about 120 seconds. The default 10 events/second profile's
approximately 12-second high phase can be missed by a 60-second poll and is not
appropriate evidence for this rule. Validate normal -> high -> one alert ->
recovery -> stopped, plus stale/replay/conflict suppression, before approving
test delivery. Current network failure prevents this live test.

## 5. Fifteen-minute narrative and honest fallback

1. **0-2 min:** Explain synthetic schema, sites and actual source topology.
   Show the transport gate openly if it is not resolved.
2. **2-5 min:** Raw versus typed rows, invalid quarantine flags, duplicates,
   separate operational and platform health; execute historical fixture queries.
3. **5-8 min:** Show the verified native graph hierarchy and compound-key
   historical join. Label interactive time-series UI as untested until rehearsed.
4. **8-11 min:** Show the actual published KQL count/freshness answers and both
   scoped Compressor 1 assets. Disclose context CSV formatting failures. KQL
   Copilot UI and underlying generated-query traces remain separate gates.
5. **11-13 min:** A stopped rule/policy walkthrough if approval is pending.
   Never send an unapproved notification for dramatic effect.
6. **13-15 min:** Show the verified OneLake Delta read, scope-specific governance
   and bounded scaling plan. Do not imply the 147-row read is a throughput test.

Stop finite publishers, stop test notification rules, and preserve acceptance
evidence after rehearsal. No background local services are needed.
