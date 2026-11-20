#!/usr/bin/env python3
"""Integrity/coverage gate for REAL video-depth quality evidence (not aesthetics)."""
import argparse
import json
import math
from pathlib import Path
from check_depth_acceptance import artifact

CATEGORIES = {"still-person", "walking", "fast-subject", "camera-pan", "camera-dolly",
              "foreground-entry", "occlusion-return", "subject-crossing", "backlit-hair", "night-lights"}


def evaluate(data, root):
    if data.get("version") != 1:
        raise ValueError("Unsupported video depth evidence format")
    pending, categories, seen = [], set(), set()
    for scene in data.get("scenes", []):
        if not scene.get("id") or scene["id"] in seen:
            raise ValueError("Scene IDs must be unique")
        seen.add(scene["id"])
        if scene.get("kind") != "real-capture" or scene.get("consented") is not True:
            pending.append("Real capture/consent missing: " + scene["id"])
        categories.update(scene.get("categories", []))
        for key in ["original", "baseline", "candidate", "blindReview"]:
            artifact(root, scene.get(key))
        measurements = artifact(root, scene.get("measurements"))
        if measurements.stat().st_size > 16 * 1024 * 1024:
            raise ValueError("Video measurement file too large")
        metrics = json.loads(measurements.read_text())
        pts = metrics.get("ptsSeconds", [])
        if len(pts) < 30 or any(not isinstance(t, (int, float)) or isinstance(t, bool) or not math.isfinite(t) or t < 0 for t in pts) or any(a >= b for a, b in zip(pts, pts[1:])):
            raise ValueError("At least 30 strictly increasing real frame timestamps required")
        for key in ["depthJitterBefore", "depthJitterAfter", "boundaryJitterPixels", "targetLossFrames", "fallbackFrames"]:
            value = metrics.get(key)
            if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value) or value < 0:
                raise ValueError("Finite nonnegative measurement required: " + key)
        for key in ["targetLossFrames", "fallbackFrames"]:
            if int(metrics[key]) != metrics[key] or metrics[key] > len(pts):
                raise ValueError("Frame counts must be integral and bounded")
        for key in ["ptsPreserved", "audioPreserved", "orientationPreserved", "originalHashPreserved"]:
            if metrics.get(key) is not True:
                pending.append("Preservation check missing: " + key)
        if metrics["depthJitterAfter"] > metrics["depthJitterBefore"]:
            pending.append("Temporal jitter regressed: " + scene["id"])
        if scene.get("humanAccepted") is not True:
            pending.append("Human boundary/target/ghosting acceptance pending: " + scene["id"])
    if len(seen) < 10:
        pending.append("At least 10 real video scenes required")
    if CATEGORIES - categories:
        pending.append("Missing video categories: " + ", ".join(sorted(CATEGORIES - categories)))
    return {"accepted": not pending, "realEvidenceRecords": len(seen), "pending": pending,
            "note": "This validates evidence integrity; human visual review remains required."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    try:
        report = evaluate(json.loads(args.manifest.read_text()), args.manifest.parent)
    except (ValueError, OSError, TypeError) as error:
        print(json.dumps({"accepted": False, "error": str(error)})); return 1
    print(json.dumps(report, indent=2))
    return 0 if report["accepted"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
