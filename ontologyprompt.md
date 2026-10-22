Create a new oil-and-gas operational ontology for a synthetic compressor monitoring demo. Do not modify or replace the existing OilGasOperationalOntology.

PURPOSE
Help users understand which site, battery, gas-lift system, compressor, component and measurement a telemetry reading belongs to. Support pressure history, asset comparisons, freshness checks and navigation from a site to its measurements. This is decision support, not equipment diagnosis or control.

TARGET
Eventhouse: OilGasEventhouse
KQL database: OilGasOperationsDB
KQL database item ID: 9c562b46-9eaa-48b0-a1e9-19ccae2c272d
Reference Lakehouse: OilGasReference

ENTITY TYPES
Create six entity types:

1. Site: synthetic production site.
2. Battery: tank battery belonging to a site.
3. System: gas-lift system belonging to a battery.
4. Compressor: compressor belonging to a system.
5. Component: compressor component, such as Throw 3.
6. Measurement: registered pressure or vibration tag; not an individual event.

STATIC SOURCE SCHEMAS
The KQL database contains:

AssetRegistry
- EntityId:string
- EntityType:string
- DisplayName:string
- ParentId:string
- SiteId:string
- AssetId:string

For Site, Battery, System, Compressor and Component, select the corresponding EntityType. Use EntityId as the unique entity key and DisplayName as the display label. Keep ParentId, SiteId and AssetId as contextual properties. Do not use AssetId as the unique key for every entity type.

MeasurementRegistry
- MeasurementId:string
- AssetId:string
- ComponentId:string
- SiteId:string
- Source:string
- UnitNum:string
- Name:string
- DisplayName:string
- EngineeringUnit:string
- Metric:string
- HighThreshold:real
- RecoveryThreshold:real

Use MeasurementId as the Measurement entity key. Here AssetId identifies the owning compressor; ComponentId identifies an optional component. Preserve both. DisplayName is a measurement label, not the compressor name.

AssetRelationships
- Relationship:string
- SourceId:string
- TargetId:string

If this experience cannot use filtered KQL tables for static bindings, use the existing per-entity reference tables in OilGasReference: Site, Battery, System, Compressor, Component and Measurement. Inspect their actual schemas before mapping. Do not invent a supported binding or silently substitute a new data source.

RELATIONSHIPS
Create these directed, one-to-many relationship types:
- Site contains Battery
- Battery contains System
- System contains Compressor
- Compressor contains Component
- Component contains Measurement
- Compressor has Measurement

Use registered relationship rows and matching IDs, not display labels or guessed name parsing. Component-linked measurements must retain their component relationship. Direct compressor measurement relationships must follow the actual registry/edge rows; do not create extra edges merely because a compressor ID is also available.

The Lakehouse also has existing per-relationship Edge_* tables if separate relationship sources are required. Inspect them and use SourceId and TargetId.

KQL TIME-SERIES BINDING
Bind Measurement time-series properties to the physical Telemetry table in OilGasOperationsDB.

Relevant actual columns:
- Source:string
- UnitNum:string
- Name:string
- EventTime:datetime
- NumericValue:real
- EventhouseIngestedAt:datetime
- Fingerprint:string
- ParseError:string
- Value:string

Contextualize each Measurement using ALL THREE equality matches:
Measurement.Source = Telemetry.Source
Measurement.UnitNum = Telemetry.UnitNum
Measurement.Name = Telemetry.Name

Telemetry does not contain MeasurementId, AssetId, SiteId or EngineeringUnit. Do not invent these columns in a physical-table binding. Obtain identity and units from MeasurementRegistry.

Use EventTime as the observation timestamp and NumericValue as the numeric time-series value. Keep EventhouseIngestedAt separate as the receipt timestamp. Value is original text; do not treat it as the typed numeric property. Exclude parse failures from numeric analysis while retaining the original raw records for inspection.

Do not create one Measurement entity per telemetry row or treat Fingerprint as a stable measurement identity.

SEMANTICS
- DischargePressure and SuctionPressure use psi.
- Vibration uses mm/s.
- Never aggregate incompatible metrics or units together.
- Source + UnitNum + full Name identifies a tag; UnitNum alone is not unique.
- Compressor 1 exists at multiple sites. Resolve ambiguity by SiteId and globally scoped compressor ID.
- A reading older than 60 seconds relative to the query's explicit UTC as-of time is stale. Exactly 60 seconds is not stale. Missing and stale are not healthy or zero.
- Thresholds are synthetic demo metadata, not approved operating limits.
- Do not infer current equipment conditions from historical data.

VALIDATION
Expected reference inventory:
2 Sites, 2 Batteries, 2 Systems, 4 Compressors, 4 Components and 12 Measurements; 24 registered relationships.

Validate this path against real bindings:
SITE-A -> BAT-A -> SYS-A -> CMP-A1 -> THR-A1 -> MSR-A1-DP

MSR-A1-DP must resolve to discharge pressure in psi using its exact registered Source, UnitNum and Name. Verify that SITE-B's Compressor 1 remains a different entity.

DELIVERY
Create the entity types, properties and relationships supported by this experience. Configure bindings only where the selected source and current experience actually support them. Do not change source tables, permissions or the existing ontology.

Finish with a concise checklist showing:
1. What was created.
2. Exact entity keys and relationship mappings.
3. Exact static and KQL time-series source mappings.
4. Validation results actually executed.
5. Any remaining manual configuration or unsupported binding capabilities.

Distinguish a generated model from a bound and runtime-validated ontology. Do not claim success for bindings or queries that were not executed.