#!/usr/bin/env python3
"""Evidence gate for depth release claims. Empty/synthetic evidence never passes.

Artifacts stay local (consented photo sets must not be committed by default).
This checks evidence integrity and declared measurements, not aesthetic quality.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

CATEGORIES = {"backlight", "night", "hair", "glasses", "hands", "pets", "glass", "plants", "foreground", "multiple-subjects", "motion"}


def artifact(root, record):
    if not isinstance(record, dict):
        raise ValueError("Artifact record must contain path and sha256")
    relative = Path(record.get("path", ""))
    if relative.is_absolute() or ".." in relative.parts or not relative.parts:
        raise ValueError("Artifact path must stay within the evidence directory")
    path = root / relative
    if any(p.is_symlink() for p in [path, *path.parents] if p != root.parent):
        raise ValueError("Symlink evidence is not accepted")
    if not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError("Evidence artifact is missing or outside the evidence directory")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            digest.update(chunk)
    if digest.hexdigest() != record.get("sha256"):
        raise ValueError("Evidence artifact hash mismatch")
    return path


def percentile(values, p):
    if not values or any(not isinstance(x, (int, float)) or isinstance(x, bool) or not math.isfinite(x) or x < 0 for x in values):
        raise ValueError("Timings must be finite, non-negative raw samples")
    return sorted(values)[max(0, math.ceil(len(values) * p) - 1)]


def evaluate(data, root):
    if data.get("version") != 1:
        raise ValueError("Unsupported depth acceptance manifest")
    pending = []
    scenes = data.get("scenes", [])
    if len(scenes) < 100:
        pending.append("At least 100 consented real capture scenes required")
    seen, categories = set(), set()
    for scene in scenes:
        if not scene.get("id") or scene["id"] in seen:
            raise ValueError("Scene IDs must be unique")
        seen.add(scene["id"])
        if scene.get("consented") is not True or scene.get("kind") != "real-capture":
            pending.append("Real capture consent missing: " + scene["id"])
        categories.update(scene.get("categories", []))
        for key in ["original", "photop", "competitor", "review"]:
            artifact(root, scene.get(key))
    if CATEGORIES - categories:
        pending.append("Missing scene categories: " + ", ".join(sorted(CATEGORIES - categories)))
    runs = data.get("deviceRuns", [])
    required_tiers = {"minimum-supported", "midrange", "lidar-pro"}
    if required_tiers - {r.get("tier") for r in runs}:
        pending.append("Physical device runs required for minimum-supported, midrange and lidar-pro")
    metrics = []
    for run in runs:
        trace_path = artifact(root, run.get("trace"))
        if trace_path.stat().st_size > 16 * 1024 * 1024:
            raise ValueError("Device trace exceeds 16MiB")
        trace = json.loads(trace_path.read_text())
        if run.get("physicalDevice") is not True or not run.get("model") or not run.get("os"):
            pending.append("Physical device identity missing")
        seconds = trace.get("durationSeconds", 0)
        if not isinstance(seconds, (int, float)) or not math.isfinite(seconds) or seconds < 600:
            pending.append("Continuous physical capture/preview trace must cover at least 10 minutes")
        samples = trace.get("previewLatencyMilliseconds", [])
        p95 = percentile(samples, 0.95)
        metrics.append({"model": run.get("model"), "previewLatencyP95Milliseconds": p95})
        if len(samples) < 300 or p95 > 150:
            pending.append("Preview p95 target (150ms, >=300 samples) not met")
        if run.get("thermalFallbackVerified") is not True or run.get("originalIntegrityVerified") is not True or run.get("cancelRecoveryVerified") is not True:
            pending.append("Thermal, original-integrity and cancellation checks required")
    reviews = data.get("blindReviews", [])
    reviewers = set()
    reviewed = set()
    for review in reviews:
        artifact(root, review.get("ballot"))
        if review.get("blinded") is not True or not review.get("reviewer"):
            pending.append("Independent blinded review required")
        reviewers.add(review.get("reviewer"))
        ids = set(review.get("sceneIDs", []))
        if ids - seen:
            raise ValueError("Blind review references unknown scenes")
        reviewed.update(ids)
    if len(reviewers) < 3 or reviewed != seen or not seen:
        pending.append("At least three reviewers and coverage of every real scene required")
    approval = data.get("qualityApproval")
    if not approval:
        pending.append("Human review of edge leakage, face detail, ghosting and competitor comparison required")
    else:
        artifact(root, approval)
        if approval.get("accepted") is not True:
            pending.append("Human quality acceptance is pending")
    legal = data.get("legalReview")
    if not legal:
        pending.append("Final distribution rights review required")
    else:
        artifact(root, legal)
        if legal.get("accepted") is not True:
            pending.append("Distribution rights review is pending")
    return {"eligible": not pending, "pending": pending, "sceneCount": len(seen), "deviceMetrics": metrics,
            "scope": "Evidence gate only; does not establish industry-leading quality or validate iOS SDK compatibility"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--validate-only", action="store_true", help="Validate structure/integrity; pending acceptance is reported, not treated as CI failure")
    args = parser.parse_args()
    try:
        result = evaluate(json.loads(args.manifest.read_text()), args.manifest.parent)
    except (ValueError, OSError, TypeError, KeyError) as error:
        parser.exit(1, str(error) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["eligible"] or args.validate_only else 2


if __name__ == "__main__":
    raise SystemExit(main())
