import copy
import json
from pathlib import Path
import unittest
from check_depth_model import validate_manifest


class DepthModelManifestTests(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads((Path(__file__).resolve().parents[1] / "assets/depth-model/legal/manifest.json").read_text())

    def test_pinned_contract(self):
        validate_manifest(self.manifest)

    def test_unsafe_or_duplicate_paths_rejected(self):
        for value in ["../weight.bin", "/tmp/weight.bin", self.manifest["files"][0]["path"]]:
            changed = copy.deepcopy(self.manifest)
            changed["files"][1]["path"] = value
            with self.assertRaises(ValueError):
                validate_manifest(changed)

    def test_unreviewed_revision_or_license_rejected(self):
        for key, value in [("revision", "main"), ("license", "CC-BY-NC-4.0")]:
            changed = copy.deepcopy(self.manifest)
            changed[key] = value
            with self.assertRaises(ValueError):
                validate_manifest(changed)

    def test_changed_io_rejected(self):
        changed = copy.deepcopy(self.manifest)
        changed["input"]["width"] = 512
        with self.assertRaises(ValueError):
            validate_manifest(changed)
