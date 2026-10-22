# Coexistence and governance

## Verified and prospective routes

| Route | Semantics and status |
|---|---|
| Synthetic fixture -> Eventhouse | Physical inline ingestion performed. Retained raw plus typed table; not Kafka/Eventstream proof. |
| Shared synthetic generator -> direct Eventhouse micro-batches | User-approved three-hour demo-volume load completed through Entra/KQL inline ingestion: 108,000 raw rows, 108,000 normalized rows, 108,000 distinct fingerprints and zero parse errors independently verified. Not production throughput, Kafka or Eventstream proof. |
| Kafka -> Eventstream -> Eventhouse | Intended production-like lane; not configured/qualified. Broker auth, topic, connector, offsets and network route remain gates. |
| Custom endpoint -> Eventstream -> Eventhouse | Destination Warning; local/Fabric-hosted REST and verified-TLS native AMQP rejected with 401 and explicit IP denial; zero accepted events. Workspace policy Allow/Allow and zero firewall rules do not explain the managed endpoint restriction. |
| Eventhouse -> OneLake | Physical Telemetry Delta availability enabled; 147 rows read back at version 1. Batched availability, five-minute configured target, not a real-time zero-latency view. |
| OneLake reference Lakehouse -> ontology | Static sources materialized; native backing graph verifies six entity counts, 24 edges and the complete component-pressure path. |
| Eventhouse -> ontology | Direct Measurement time-series binding configured; actual graph-to-KQL compound-key join passed. Time-series UI and retiring-JSON migration remain gates. |
| KQL -> Data Agent | Published; eleven functions/three registries selected. All five operational cases passed strict acceptance: historical count, current staleness, site inventory, historical comparison and ambiguity across both scoped assets. |
| Ontology-backed GraphModel -> Data Agent | Actual GraphModel selected using documented graph datasource. Path values returned, but extra JSON quoting in CSV fails strict acceptance; legacy ontology planner also fails bounded paths. |
| OneLake -> Databricks / Power BI | Prospective read using the supported identity/connector and eligible endpoint; no Databricks job or downstream report was created/tested. |
| Existing ADX -> Fabric | Decide explicitly between remote query, permitted cross-cluster/follower patterns, or physical ingestion. An ADX shortcut/follower is not automatically an Eventhouse OneLake Delta copy. No live ADX route implemented (P2 excluded). |
| Snowflake -> Fabric | Documentation-only coexistence discussion. No connector, replication, shortcut or zero-copy integration is claimed (P2 excluded). |

OneLake availability follows source retention and is read-only from the consumer
perspective; it is not an independent archive with arbitrary retention. Do not
write into the Eventhouse-managed Delta export. No external-table implementation
was substituted for the physical Telemetry table.

## Identity and data controls

- Target-folder ancestry and fixed workspace/folder IDs are checked by scripts.
  No other customer workspace, project or demo dataset is modified.
- Credentials come from authenticated Azure CLI or transient environment
  variables. Never persist Fabric tokens, SAS keys, Kafka secrets or inherited
  recipients. Generated local state is excluded by `.gitignore`.
- Synthetic source identity uses Source + UnitNum + full Name; SiteId and
  globally scoped AssetId disambiguate repeated local compressor numbers.
- A fingerprint is a heuristic for exact source-field replay. It is not an
  authoritative event ID, exactly-once processing, or correction precedence.
- KQL functions separate metrics/units, stale/missing readings, parse failures,
  unknown tags, future events, equal-time conflicts and negative apparent
  latency. Ingestion time is approximate receipt, not a total arrival order.
- Prompts are not access control. Apply least privilege at each Fabric and
  OneLake surface; verify a denied identity before claiming enforcement.
- KQL row-level policies are not automatically inherited by OneLake consumers.
  This demo enabled availability only for a synthetic physical table. Any
  customer rollout needs explicit downstream authorization and exposure review.
- No RLS/OLS/access-role rollout, real customer data, plant integration,
  notifications, external infrastructure or broad workspace changes occurred.
- The Activator source/object scaffold is stopped and contains no action,
  recipient or rule. Publishing the agent did not change its permissions.

## Documentation sources

- [Eventhouse OneLake availability](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/event-house-onelake-availability)
- [Mirroring policy](https://learn.microsoft.com/en-us/kusto/management/mirroring-policy?view=microsoft-fabric)
- [Mirroring policy commands](https://learn.microsoft.com/en-us/kusto/management/alter-merge-mirroring-policy-command?view=microsoft-fabric)
- [Ontology definition](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/ontology-definition)
- [Retiring JSON ontology definition](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/ontology-old-definition)
- [Data Agent definition](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/data-agent-definition)
- [Data Agent datasource schema](https://developer.microsoft.com/json-schemas/fabric/item/dataAgent/definition/dataSource/1.0.0/schema.json)
- [Native graph GQL query API](https://learn.microsoft.com/en-us/fabric/graph/gql-query-api)
- [Activator definition](https://learn.microsoft.com/en-us/rest/api/fabric/articles/item-management/definitions/reflex-definition)

Documentation availability is not evidence that the tenant's runtime feature,
permissions or downstream identity behavior has passed acceptance.
