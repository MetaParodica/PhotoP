import hashlib
import tempfile
import unittest
from pathlib import Path

from check_depth_acceptance import artifact, evaluate, percentile


class DepthAcceptanceTests(unittest.TestCase):
    def test_empty_evidence_cannot_become_release_acceptance(self):
        result = evaluate({"version": 1}, Path("."))
        self.assertFalse(result["eligible"])
        self.assertGreaterEqual(len(result["pending"]), 5)

    def test_artifact_hash_and_path_integrity(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "trace.json").write_bytes(b"trace")
            record = {"path": "trace.json", "sha256": hashlib.sha256(b"trace").hexdigest()}
            self.assertEqual(artifact(root, record), root / "trace.json")
            for bad in [dict(record, sha256="0" * 64), dict(record, path="../trace.json"), dict(record, path="/trace.json")]:
                with self.assertRaises(ValueError):
                    artifact(root, bad)
            (root / "alias").symlink_to(root / "trace.json")
            with self.assertRaises(ValueError):
                artifact(root, dict(record, path="alias"))

    def test_p95_uses_tail_and_rejects_invalid_timings(self):
        self.assertEqual(percentile(list(range(1, 101)), 0.95), 95)
        for invalid in [[], [float("nan")], [float("inf")], [-1], [True]]:
            with self.assertRaises(ValueError):
                percentile(invalid, 0.95)

    def test_synthetic_claim_and_duplicate_scenes_fail_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); (root / "image").write_bytes(b"fixture")
            record = {"path": "image", "sha256": hashlib.sha256(b"fixture").hexdigest()}
            scene = dict(id="synthetic", kind="synthetic", consented=True, original=record, photop=record, competitor=record, review=record)
            result = evaluate({"version": 1, "scenes": [scene]}, root)
            self.assertFalse(result["eligible"])
            with self.assertRaises(ValueError):
                evaluate({"version": 1, "scenes": [scene, scene]}, root)
