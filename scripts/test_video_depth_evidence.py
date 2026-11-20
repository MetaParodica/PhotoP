import json
import tempfile
import unittest
from pathlib import Path
from check_video_depth_evidence import evaluate, CATEGORIES
from hashlib import sha256


class VideoDepthEvidenceTests(unittest.TestCase):
    def test_empty_real_evidence_never_passes(self):
        result = evaluate({"version": 1, "scenes": []}, Path("."))
        self.assertFalse(result["accepted"])
        self.assertEqual(result["realEvidenceRecords"], 0)

    def test_synthetic_forged_timing_and_escape_cannot_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "sample").write_bytes(b"test fixture only, not a quality evaluation")
            sample = {"path": "sample", "sha256": sha256((root / "sample").read_bytes()).hexdigest()}
            metrics = {"ptsSeconds": [i/30 for i in range(30)], "depthJitterBefore": 0.1, "depthJitterAfter": 0.05,
                       "boundaryJitterPixels": 1.2, "targetLossFrames": 0, "fallbackFrames": 0,
                       "ptsPreserved": True, "audioPreserved": True, "orientationPreserved": True, "originalHashPreserved": True}
            (root / "metrics").write_text(json.dumps(metrics))
            measure = {"path": "metrics", "sha256": sha256((root / "metrics").read_bytes()).hexdigest()}
            scene = dict(id="fixture", kind="synthetic", consented=True, categories=sorted(CATEGORIES),
                         original=sample, baseline=sample, candidate=sample, blindReview=sample, measurements=measure, humanAccepted=True)
            self.assertFalse(evaluate({"version": 1, "scenes": [scene]},root)["accepted"])
            metrics["ptsSeconds"][3] = -1
            (root / "metrics").write_text(json.dumps(metrics))
            measure["sha256"] = sha256((root / "metrics").read_bytes()).hexdigest()
            with self.assertRaises(ValueError): evaluate({"version": 1, "scenes": [scene]},root)
            scene["original"] = {"path": "../escape", "sha256": "0"*64}
            with self.assertRaises(ValueError): evaluate({"version": 1, "scenes": [scene]},root)
