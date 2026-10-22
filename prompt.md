# ExxonMobil Fabric RTI Demo — GitHub Copilot Plan Mode

## Objective

Create a detailed implementation plan for an **ExxonMobil Fabric Real-Time Intelligence demo**.

Do **not** start implementing yet.

First:
1. Inspect the plan.
2. Identify gaps against the demo requirements below.
3. Propose the architecture and implementation approach.
4. Produce a prioritized file-by-file implementation plan.
5. Clearly identify anything requiring manual configuration in Microsoft Fabric rather than code in this repository.

The demo should tell an end-to-end story:

**Oil & gas operational telemetry → Fabric RTI / Eventhouse → contextualized operational model / ontology → Copilot and Data Agents → operational intelligence and actions**

The objective is to demonstrate why Fabric RTI provides value beyond simply running another time-series database.

---

# 1. Customer Context

ExxonMobil is evaluating Fabric RTI as a potential enterprise platform for operational time-series data.

Their current environment includes technologies such as:

- Azure Data Explorer
- Databricks
- Snowflake
- Kafka / Confluent
- PI Historian
- PHD Historian
- OPC UA
- MQTT / Sparkplug B
- SCADA and industrial systems

The current POC starts with a Kafka source feeding Fabric Eventhouse.

The initial stream is approximately **20 million records/day**, with a historical/backfill load in the hundreds of millions of records.

The broader architecture could eventually involve sources producing **billions of data points per day**, so the demo architecture should not make assumptions that only work for a small demo dataset.

---

# 2. Use the ExxonMobil Data Shape

The actual sample shared by the team follows approximately this structure:

```text
RecordDateTime
RecordDateTimeUTC
UnitNum
Source
Name
Value
RecordAdded
ProcessedDate
IngestionTime
```

Example semantic meaning of `Name`:

```text
Badlands_21x_13/
Tank_Battery/
Gas_Lift/
Compressors/
Compressor_1/
Performance/
Throw_3/
DisplayedDiscPress
```

The demo should therefore model realistic production operations telemetry rather than generic IoT devices.

Important domain concepts should include where appropriate:

- Site / field
- Tank battery
- Gas lift
- Compressor
- Equipment
- Measurement / tag
- Timestamp
- Value
- Source system

Do not fabricate ExxonMobil confidential data.

Use synthetic values where real values are unavailable, while keeping the schema and domain realistic.

---

# 3. Demo Story

The demo should progressively answer:

> We already have ADX and other data platforms. What additional value do we get from Fabric RTI and the broader Fabric platform?

Design the experience as a progression rather than a collection of disconnected demos.

## Stage A — Real-Time Telemetry

Show operational telemetry arriving continuously.

Demonstrate:

- streaming events
- timestamps
- asset/tag names
- measurements
- ingestion timestamps
- realistic changing values

If one of my github repo or my C:\Work folder already contains a simulator, generator, Kafka publisher, Eventstream integration, or Eventhouse integration, reuse it rather than creating a parallel implementation.

Also consider how the demo can illustrate:

- near-real-time ingestion
- out-of-order events
- duplicate events
- event-time versus ingestion-time
- simple transformations/enrichment

---

# 4. Eventhouse / KQL

Determine what queries or artifacts are needed to show how telemetry becomes useful operational information.

Plan examples such as:

- latest compressor measurements
- telemetry history for a specific asset
- pressure/value trend
- abnormal readings
- aggregation over time windows
- comparison between assets
- ingestion latency
- duplicate detection
- out-of-order event handling

Keep queries simple enough to explain live.

Identify which KQL queries should become reusable demo scripts/files in the repository.

---

# 5. Operational Ontology / Context

This is a major differentiator in the demo.

Transform raw tag-based telemetry into a business/operational model.

For example:

```text
Field / Site
   ↓
Tank Battery
   ↓
Gas Lift System
   ↓
Compressor
   ↓
Component
   ↓
Measurement
   ↓
Real-Time Telemetry
```

Determine:

- which entities should exist
- entity properties
- relationships
- how telemetry maps to entities
- how the ontology references or binds to Eventhouse data
- what repository artifacts are needed
- what Fabric configuration must be performed manually

The goal is to move from:

**"Tag XYZ has value 115.6"**

to something closer to:

**"Compressor 1 at this production site currently has this operating condition."**

---

# 6. Copilot Experience

Plan a short Copilot demonstration showing that users can explore operational information without starting with KQL.

Potential questions should be grounded in capabilities actually available in the environment.

Examples to evaluate:

- What compressors are represented in this dataset?
- Show recent measurements for Compressor 1.
- Which assets have unusual values?
- How has discharge pressure changed recently?
- Which measurements have the highest ingestion latency?

Do not assume unsupported Copilot functionality.

Clearly identify what configuration and semantic context Copilot requires.

---

# 7. Data Agent

Plan how a Data Agent could provide a more domain-aware conversational experience over the operational data.

The desired experience is roughly:

**Natural-language operational question → contextual understanding → Eventhouse/KQL query → concise operational answer**

Evaluate questions such as:

- Which compressor should I investigate?
- What changed recently for Compressor 1?
- Are any assets showing abnormal telemetry?
- Compare the recent behavior of two compressors.
- What operational telemetry exists for a selected site?

Do not fabricate capabilities.

Identify explicitly:

- required Fabric artifacts
- instructions/prompts for the agent
- grounding data
- ontology dependencies
- queries/functions that should be exposed
- configuration that must happen outside the repository

---

# 8. Activator / Operational Actions

Evaluate whether Activator can strengthen the story.

Potential scenario:

```text
Telemetry
   ↓
Condition / rule
   ↓
Trigger
   ↓
Operational action or notification
```

For example, an abnormal compressor measurement could become an operational signal.

Keep this portion focused. It should demonstrate the transition from **observing data** to **acting on data**, rather than becoming a separate large demo.

Clearly separate what can be implemented in code from what requires Fabric configuration.

---

# 9. Fabric Platform Integration

The customer explicitly cares about coexistence with existing platforms.

The demo/architecture should therefore explain how RTI fits alongside:

- Databricks
- Snowflake
- ADX
- Power BI
- external analytical tools

Review whether the repository can demonstrate or document:

### OneLake availability

Show how Eventhouse data can become available through OneLake where technically appropriate.

### ADX coexistence

Explain where ADX federation, shortcuts, or follower scenarios fit versus physically landing data in Eventhouse.

Do not claim that data exposed through an ADX follower automatically receives OneLake availability.

### Databricks

Where possible, show or document how another analytics platform can consume the resulting data without creating unnecessary ingestion pipelines.

Prioritize a credible architecture over trying to demonstrate every integration live.

---

# 10. Enterprise Architecture Considerations

Include an architecture section covering the issues ExxonMobil raised around operating this at enterprise scale.

Address at least conceptually:

- centralized vs. federated Eventhouse topology
- site/asset isolation
- Eventhouse/database organization
- noisy-neighbor considerations
- RBAC / RLS
- lifecycle and retention
- hot versus longer-term storage
- monitoring
- capacity considerations
- governance
- downstream data sharing

Do not over-engineer these capabilities into the demo unless the repository already supports them.

The purpose is to demonstrate that the demo has an enterprise architecture path.

---

# 11. Monitoring

Include Fabric monitoring/observability in the plan where relevant.

The user should be able to understand:

- whether data is flowing
- ingestion behavior
- Eventhouse activity
- operational telemetry for the Fabric workload

Clearly distinguish platform monitoring from business/asset monitoring.

---

# 12. Optional Stretch: Physical / 3D Operations

Treat the NVIDIA / Omniverse physical operations visualization as a **stretch goal**, not a dependency for the core demo.

If this repository already contains reusable 3D, digital twin, Omniverse, or physical-AI assets, explain how they could be connected to the ontology and real-time telemetry.

Potential experience:

```text
Fabric RTI telemetry
        ↓
Operational ontology
        ↓
Physical / 3D representation
        ↓
Operator selects asset
        ↓
Current telemetry + AI context
```

Do not build a new 3D application unless the existing repository makes this practical.

---

# 13. Demo Narrative

The final implementation should support a concise customer story:

### 1 — Connect
Operational telemetry streams into Fabric.

### 2 — Understand
Eventhouse provides real-time time-series analytics.

### 3 — Contextualize
Raw industrial tags become assets and relationships through an operational ontology.

### 4 — Ask
Copilot and Data Agents allow users to interact with operational information naturally.

### 5 — Act
Activator can turn relevant conditions into operational triggers and actions.

### 6 — Integrate
The same data can participate in the broader Fabric ecosystem and coexist with Databricks, ADX, Snowflake, Power BI, and other tools.

### 7 — Scale
The architecture provides a path from today's POC to a broader enterprise operational data platform.

---

# 14. Planning Tasks

Before changing any code, analyze the repository and produce:

## A. Current Repository Assessment

Identify:

- existing architecture
- existing applications
- telemetry simulators
- ingestion components
- KQL
- Fabric artifacts
- ontology assets
- AI / agent components
- visualization components
- documentation
- reusable demo assets

For each important component classify it:

**Reuse / Modify / Replace / Missing**

---

## B. Gap Analysis

Create a matrix:

| Demo requirement | Existing implementation | Gap | Recommended change | Priority |
|---|---|---|---|---|

Use these priorities:

- **P0** — required for the customer demo
- **P1** — strongly improves the story
- **P2** — optional/stretch

---

## C. Proposed Architecture

Describe the recommended end-to-end architecture.

Separate clearly:

### Repository components

Things we implement or maintain in GitHub.

### Microsoft Fabric components

Things configured in the Fabric environment.

### External dependencies

Kafka, ADX, Databricks, NVIDIA/Omniverse, etc.

Also show the major data flow.

---

## D. Demo Sequence

Design a live demo flow optimized for customer impact.

For each step include:

- what the presenter shows
- what question it answers
- required component
- expected result
- fallback if the component fails during the live demo

Keep the transition between steps natural.

---

## E. Implementation Plan

Provide a phased implementation plan.

For every task specify:

- priority
- objective
- files/directories affected
- dependencies
- technical approach
- expected output
- validation criteria

Prefer modifying existing components over adding redundant new components.

---

## F. Demo Readiness Checklist

Finish with a checklist covering:

### Data
- telemetry generator/data available
- schema validated
- Eventhouse receiving data
- queries tested

### Context
- ontology created
- relationships validated
- telemetry mapped correctly

### AI
- Copilot scenarios tested
- Data Agent configured
- demo questions tested

### Operations
- Activator scenario validated if included
- monitoring working

### Integration
- OneLake scenario validated where applicable
- coexistence story documented

### Presentation
- demo sequence rehearsable
- sample questions documented
- fallback screenshots/results available
- README includes setup instructions

---

# Working Principles

- Inspect before modifying.
- Reuse before rebuilding.
- Optimize for a convincing live customer demo, not a production implementation.
- Keep setup repeatable.
- Separate code changes from Fabric portal configuration.
- Do not fabricate Microsoft Fabric functionality.
- Do not fabricate ExxonMobil data.
- Prefer synthetic telemetry based on the shared schema where data is required.
- Keep the oil & gas domain visible throughout the experience.
- Keep the core demo reliable and treat advanced 3D/Omniverse functionality as optional.

## Final Plan Output

At the end of Plan Mode, provide:

1. **Executive summary**
2. **Repository assessment**
3. **Gap analysis**
4. **Target architecture**
5. **Recommended demo sequence**
6. **P0/P1/P2 implementation backlog**
7. **File-by-file changes**
8. **Fabric manual configuration required**
9. **Risks and dependencies**
10. **Demo readiness checklist**

Do not implement anything until the plan has been reviewed.