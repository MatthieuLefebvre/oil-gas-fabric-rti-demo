"""Read back this demo's Eventhouse Delta export without Spark or source writes."""

from __future__ import annotations

import json
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from azure.identity import AzureCliCredential
from azure.storage.filedatalake import DataLakeServiceClient
from deltalake import DeltaTable

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = "21733624-95b6-4740-b892-d29ff7889aa4"
TABLE = "9c562b46-9eaa-48b0-a1e9-19ccae2c272d/Tables/Telemetry"


def main() -> None:
    with AzureCliCredential() as credential, DataLakeServiceClient(
        "https://msit-onelake.dfs.fabric.microsoft.com", credential=credential
    ) as service, tempfile.TemporaryDirectory(prefix="oilgas-onelake-read-") as temporary:
        filesystem = service.get_file_system_client(WORKSPACE)
        local = Path(temporary)
        total = 0
        for entry in filesystem.get_paths(path=TABLE, recursive=True):
            if entry.is_directory:
                continue
            relative = entry.name.removeprefix(TABLE + "/")
            if not entry.name.startswith(TABLE + "/") or ".." in relative or "\\" in relative:
                raise ValueError("Unexpected OneLake file path")
            if not (relative.endswith(".parquet") or relative.startswith("_delta_log/")):
                continue
            total += entry.content_length or 0
            if total > 10 * 1024 * 1024:
                raise RuntimeError("Demo verification is limited to a 10 MiB Delta snapshot")
            target = local / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(filesystem.get_file_client(entry.name).download_file().readall())
        table = DeltaTable(local).to_pyarrow_table()
        fixture = json.loads((ROOT / "tests" / "fixtures" / "scenario-manifest.json").read_text())
        if table.num_rows != fixture["Count"]:
            raise RuntimeError(f"Expected fixed-corpus {fixture['Count']} rows; OneLake has {table.num_rows}")
        values = table.column("EventTime").to_pylist()
        times = [value for value in values if value is not None]
        evidence = {
            "observedAtUtc": datetime.now(timezone.utc).isoformat(),
            "workspaceId": WORKSPACE,
            "tablePath": TABLE,
            "deltaVersion": DeltaTable(local).version(),
            "rows": table.num_rows,
            "eventTimeMin": min(times).isoformat(),
            "eventTimeMax": max(times).isoformat(),
            "downloadedBytes": total,
            "scope": "Read-only fixed synthetic corpus; not Kafka/Eventstream ingestion evidence",
        }
        (ROOT / "local-only" / "onelake-evidence.json").write_text(
            json.dumps(evidence, indent=2) + "\n", encoding="utf-8"
        )
        print(json.dumps(evidence, indent=2))


if __name__ == "__main__":
    main()
