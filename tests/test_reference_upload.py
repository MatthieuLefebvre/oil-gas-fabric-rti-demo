import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

AVAILABLE = importlib.util.find_spec("deltalake") is not None
if AVAILABLE:
    import pyarrow as pa
    from deltalake import write_deltalake
    from scripts.materialize_reference import materialize, verify_table


@unittest.skipUnless(AVAILABLE, "Optional requirements-fabric.txt environment required")
class ReferenceUploadTests(unittest.TestCase):
    def test_unapproved_destinations_rejected_before_authentication(self):
        for url in (
            "https://example.com/21733624-95b6-4740-b892-d29ff7889aa4/Tables",
            "https://msit-onelake.dfs.fabric.microsoft.com/other/Tables",
            "http://msit-onelake.dfs.fabric.microsoft.com/",
        ):
            with self.subTest(url=url), self.assertRaises(ValueError):
                materialize(url)

    def make_filesystem(self, source):
        filesystem = Mock()
        filesystem.get_paths.return_value = [
            SimpleNamespace(name="remote/_delta_log/00000000000000000000.json")
        ]
        filesystem.get_file_client.side_effect = lambda name: SimpleNamespace(
            download_file=lambda: SimpleNamespace(readall=lambda: (source / name.removeprefix("remote/")).read_bytes())
        )
        return filesystem

    def test_committed_delta_roundtrip_and_content_mismatch(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            expected = [{"Id": "A"}, {"Id": "B"}]
            write_deltalake(root / "source", pa.Table.from_pylist(expected))
            filesystem = self.make_filesystem(root / "source")
            verify_table(filesystem, "remote", root / "verified", expected)
            with self.assertRaisesRegex(RuntimeError, "contents differ"):
                verify_table(filesystem, "remote", root / "mismatch", [{"Id": "C"}])

    def test_modified_delta_versions_are_not_treated_as_initial_snapshot(self):
        filesystem = Mock()
        filesystem.get_paths.return_value = [
            SimpleNamespace(name="remote/_delta_log/00000000000000000001.json")
        ]
        with self.assertRaisesRegex(RuntimeError, "unchanged initial"):
            verify_table(filesystem, "remote", Path("unused"), [])
        filesystem.get_file_client.assert_not_called()

    def test_unsafe_committed_paths_rejected(self):
        filesystem = self.make_filesystem(Path("unused"))
        filesystem.get_file_client.side_effect = None
        filesystem.get_file_client.return_value.download_file.return_value.readall.return_value = (
            json.dumps({"add": {"path": "../outside.parquet"}}).encode()
        )
        with tempfile.TemporaryDirectory() as temp, self.assertRaisesRegex(ValueError, "Unexpected path"):
            verify_table(filesystem, "remote", Path(temp) / "verify", [])


if __name__ == "__main__":
    unittest.main()
