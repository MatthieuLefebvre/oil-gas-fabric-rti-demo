"""Materialize the generated synthetic reference snapshot as initial Delta tables."""

from __future__ import annotations

import argparse
import json
import tempfile
import uuid
from pathlib import Path
from urllib.parse import urlsplit

import pyarrow as pa
from azure.core.exceptions import ResourceExistsError, ResourceNotFoundError
from azure.identity import AzureCliCredential
from azure.storage.filedatalake import DataLakeServiceClient, FileSystemClient
from deltalake import DeltaTable, write_deltalake

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = "21733624-95b6-4740-b892-d29ff7889aa4"
LAKEHOUSE = "8c85629d-eecd-4c9f-b005-b19ea610a08d"


def verify_table(filesystem: FileSystemClient, remote: str, local: Path, expected: list[dict]) -> None:
    log_name = "_delta_log/00000000000000000000.json"
    versions = [
        entry.name.rsplit("/", 1)[-1]
        for entry in filesystem.get_paths(path=f"{remote}/_delta_log", recursive=False)
        if entry.name.endswith(".json")
    ]
    if versions != ["00000000000000000000.json"]:
        raise RuntimeError(f"{remote} is not an unchanged initial synthetic table; refusing to overwrite")
    log = filesystem.get_file_client(f"{remote}/{log_name}").download_file().readall()
    (local / "_delta_log").mkdir(parents=True)
    (local / log_name).write_bytes(log)
    for line in log.decode("utf-8").splitlines():
        action = json.loads(line)
        if "add" in action:
            name = action["add"]["path"]
            if Path(name).name != name or "\\" in name:
                raise ValueError("Unexpected path in initial synthetic Delta commit")
            data = filesystem.get_file_client(f"{remote}/{name}").download_file().readall()
            (local / name).write_bytes(data)
    actual = DeltaTable(local).to_pyarrow_table().to_pylist()
    canonical = lambda rows: sorted(json.dumps(row, sort_keys=True) for row in rows)
    if canonical(actual) != canonical(expected):
        raise RuntimeError(f"OneLake contents differ from the synthetic snapshot: {remote}")


def materialize(tables_path: str) -> dict[str, int]:
    parsed = urlsplit(tables_path)
    if parsed.scheme != "https" or parsed.hostname not in {
        "msit-onelake.dfs.fabric.microsoft.com",
        "msit-westcentralus-onelake.dfs.fabric.microsoft.com",
    } or parsed.path != f"/{WORKSPACE}/{LAKEHOUSE}/Tables":
        raise ValueError("Only the approved OilGasReference Tables endpoint is allowed")
    tables = json.loads((ROOT / "local-only" / "reference-tables.json").read_text(encoding="utf-8-sig"))
    counts: dict[str, int] = {}
    with AzureCliCredential() as credential, DataLakeServiceClient(
        account_url=f"https://{parsed.hostname}", credential=credential
    ) as service, tempfile.TemporaryDirectory(prefix="oilgas-delta-") as temporary:
        filesystem = service.get_file_system_client(WORKSPACE)
        for name, rows in tables.items():
            if not name.replace("_", "").isalnum() or not rows:
                raise ValueError(f"Invalid or empty synthetic table: {name}")
            remote = f"{LAKEHOUSE}/Tables/{name}"
            commit = filesystem.get_file_client(remote + "/_delta_log/00000000000000000000.json")
            try:
                commit.get_file_properties()
            except ResourceNotFoundError:
                pass
            else:
                verify_table(filesystem, remote, Path(temporary) / f"verify_{name}", rows)
                counts[name] = len(rows)
                print(f"{name}: existing committed data verified, {len(rows)} rows; no overwrite")
                continue
            table = pa.Table.from_pylist(rows, schema=pa.schema([
                pa.field(key, pa.string()) for key in rows[0]
            ]))
            directory = Path(temporary) / name
            write_deltalake(directory, table)
            for relative_directory in (remote, remote + "/_delta_log"):
                try:
                    filesystem.get_directory_client(relative_directory).create_directory()
                except ResourceExistsError:
                    pass
            # Upload data before the transaction log so readers never see a partial commit.
            files = sorted(directory.rglob("*"), key=lambda p: "_delta_log" in p.parts)
            for path in files:
                if path.is_file():
                    relative = path.relative_to(directory).as_posix()
                    staging = filesystem.get_file_client(f"{remote}/._upload_{uuid.uuid4().hex}")
                    staging.create_file()
                    data = path.read_bytes()
                    staging.append_data(data, offset=0, length=len(data))
                    staging.flush_data(len(data))
                    staging.rename_file(f"{WORKSPACE}/{remote}/{relative}")
            verify_table(filesystem, remote, Path(temporary) / f"verify_{name}", rows)
            counts[name] = table.num_rows
            print(f"{name}: committed {table.num_rows} synthetic rows")
    return counts


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tables-path", required=True)
    args = parser.parse_args()
    counts = materialize(args.tables_path)
    (ROOT / "local-only" / "reference-delta-evidence.json").write_text(
        json.dumps(counts, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
