import base64
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = "21733624-95b6-4740-b892-d29ff7889aa4"


class DefinitionTests(unittest.TestCase):
    def test_activator_scaffold_is_stopped_and_fully_scoped(self):
        entities = json.loads((ROOT / "fabric" / "activator" / "ReflexEntities.json").read_text(encoding="utf-8-sig"))
        ids = {entity["uniqueIdentifier"] for entity in entities}
        self.assertEqual(len(ids), len(entities))
        sources = [entity["payload"] for entity in entities if entity["type"] == "kqlSource-v1"]
        self.assertEqual(len(sources), 1)
        self.assertTrue(sources[0]["runSettings"]["isStopped"])
        self.assertEqual(sources[0]["eventhouseItem"]["workspaceId"], WORKSPACE)
        self.assertEqual(sources[0]["eventhouseItem"]["itemId"], "9c562b46-9eaa-48b0-a1e9-19ccae2c272d")
        query = sources[0]["query"]["queryString"]
        for guard in ("MSR-A1-DP", "SITE-A", "CMP-A1", "psi", "not(IsStale)", "ConflictCount <= 1"):
            self.assertIn(guard, query)
        templates = {}
        for entity in entities:
            payload = entity["payload"]
            for parent in ("parentContainer", "parentObject"):
                if parent in payload:
                    self.assertIn(payload[parent]["targetUniqueIdentifier"], ids)
            definition = payload.get("definition", {})
            if definition.get("type") == "Rule":
                self.assertFalse(definition["settings"]["shouldRun"])
                self.assertFalse(definition["settings"]["shouldApplyRuleOnUpdate"])
            if "instance" not in definition:
                continue
            instance = json.loads(definition["instance"])
            templates[instance["templateId"]] = instance
            def verify_arguments(arguments):
                for argument in arguments:
                    if argument["name"] == "entityId":
                        self.assertIn(argument["value"], ids)
                    verify_arguments(argument.get("arguments", []))
            for step in instance["steps"]:
                for row in step["rows"]:
                    verify_arguments(row["arguments"])
        for template in ("SourceEvent", "IdentityPartAttribute", "IdentityTupleAttribute", "SplitEvent", "BasicEventAttribute"):
            self.assertIn(template, templates)
        self.assertNotIn("AttributeTrigger", templates)
        serialized = json.dumps(entities)
        for action in ("TeamsMessage", "EmailMessage", "recipients", "sentTo"):
            self.assertNotIn(action, serialized)

    def test_eventstream_has_exact_wire_fields_and_approved_target(self):
        definition = json.loads((ROOT / "fabric" / "eventstream" / "definition.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(definition["sources"][0]["type"], "CustomEndpoint")
        destination = definition["destinations"][0]
        self.assertEqual(destination["properties"]["workspaceId"], WORKSPACE)
        self.assertEqual(destination["properties"]["tableName"], "RawTelemetry")
        fields = [
            "RecordDateTime", "RecordDateTimeUTC", "UnitNum", "Source", "Name",
            "Value", "RecordAdded", "ProcessedDate", "IngestionTime",
        ]
        if destination["properties"]["dataIngestionMode"] == "ProcessedIngestion":
            columns = destination["inputSchemas"][0]["schema"]["columns"]
            self.assertEqual([c["name"] for c in columns], fields)
            self.assertTrue(all(c["type"] == "Nvarchar(max)" for c in columns))
        else:
            self.assertEqual(destination["properties"]["dataIngestionMode"], "DirectIngestion")
            self.assertEqual(destination["properties"]["connectionName"], "OilGasDirectConnection")
            self.assertEqual(destination["properties"]["mappingRuleName"], "TelemetryJson")
            self.assertNotIn("inputSchemas", destination)
            schema = (ROOT / "kql" / "00-schema.kql").read_text()
            for name in fields:
                self.assertIn(name, schema)

    def test_dashboard_queries_and_tiles_are_consistently_wired(self):
        dashboard = json.loads((ROOT / "fabric" / "dashboard" / "RealTimeDashboard.json").read_text(encoding="utf-8-sig"))
        self.assertEqual(dashboard["dataSources"][0]["workspace"], WORKSPACE)
        self.assertEqual(len(dashboard["queries"]), 6)
        self.assertEqual(len(dashboard["tiles"]), 6)
        queries = {q["id"] for q in dashboard["queries"]}
        self.assertEqual(len(queries), 6)
        for tile in dashboard["tiles"]:
            self.assertIn(tile["queryRef"]["queryId"], queries)
            self.assertEqual(tile["visualType"], "table")

    def test_ontology_entity_keys_and_complete_relationship_contexts(self):
        package = json.loads((ROOT / "ontology" / "definition.json").read_text(encoding="utf-8-sig"))
        parts = {
            p["path"]: json.loads(base64.b64decode(p["payload"]))
            for p in package["definition"]["parts"] if p["path"] != ".platform"
        }
        entities = [v for k, v in parts.items() if k.startswith("EntityTypes/") and k.endswith("/definition.json")]
        self.assertEqual({entity["name"] for entity in entities}, {
            "Site", "Battery", "System", "Compressor", "Component", "Measurement",
        })
        for entity in entities:
            self.assertIsInstance(entity["entityIdParts"], list)
            self.assertEqual(len(entity["entityIdParts"]), 3 if entity["name"] == "Measurement" else 1)
        contexts = [v for k, v in parts.items() if "/Contextualizations/" in k]
        self.assertEqual(len(contexts), 6)
        for context in contexts:
            source = context["dataBindingTable"]
            self.assertEqual(next(iter(source)), "sourceType")
            self.assertEqual(source["workspaceId"], WORKSPACE)
            self.assertNotIn("sourceSchema", source)
            expected = 3 if source["sourceTableName"].endswith("_Measurement") else 1
            self.assertEqual(len(context["targetKeyRefBindings"]), expected)
        bindings = [v["dataBindingConfiguration"] for k, v in parts.items() if "/DataBindings/" in k]
        self.assertEqual(len(bindings), 7)
        for binding in bindings:
            self.assertEqual(next(iter(binding)), "dataBindingType")
            self.assertEqual(next(iter(binding["sourceTableProperties"])), "sourceType")
        timeseries = [binding for binding in bindings if binding["dataBindingType"] == "TimeSeries"]
        self.assertEqual(len(timeseries), 1)
        self.assertEqual(timeseries[0]["sourceTableProperties"]["sourceTableName"], "Telemetry")


if __name__ == "__main__":
    unittest.main()
