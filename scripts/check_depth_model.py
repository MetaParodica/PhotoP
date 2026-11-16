"""Verify raw Core ML model and rights records, not runtime inference."""
import argparse
import hashlib
import json
from pathlib import Path


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def validate_manifest(manifest):
    if manifest.get("schema_version") != 1 or manifest.get("license") != "Apache-2.0":
        raise ValueError("Unsupported model/license record")
    if manifest.get("revision") != "cfef6f6f2a70783dedc0bfae40cecbc2052285d3":
        raise ValueError("Model revision requires a new audit")
    files = manifest.get("files", [])
    expected = {
        "DepthAnythingV2SmallF16.mlpackage/Manifest.json",
        "DepthAnythingV2SmallF16.mlpackage/Data/com.apple.CoreML/model.mlmodel",
        "DepthAnythingV2SmallF16.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
    }
    if len(files) != 3 or {item.get("path") for item in files} != expected:
        raise ValueError("Unexpected or unsafe model paths")
    for item in files:
        if not isinstance(item.get("bytes"), int) or item["bytes"] <= 0:
            raise ValueError("Missing byte count")
        value = item.get("sha256", "")
        if len(value) != 64 or any(c not in "0123456789abcdef" for c in value):
            raise ValueError("Invalid SHA-256")
    if (manifest["input"]["width"], manifest["input"]["height"], manifest["input"]["name"]) != (518, 392, "image"):
        raise ValueError("Changed input contract")
    if manifest["output"]["type"] != "GRAYSCALE_FLOAT16 image" or manifest["output"]["name"] != "depth":
        raise ValueError("Changed output contract")


def check(root):
    root = root.resolve()
    manifest = json.loads((root / "legal/manifest.json").read_text())
    validate_manifest(manifest)
    for item in manifest["files"]:
        path = root / item["path"]
        if path.is_symlink() or not path.resolve().is_relative_to(root):
            raise ValueError("Model path escapes package")
        if path.stat().st_size != item["bytes"] or digest(path) != item["sha256"]:
            raise ValueError("Model bytes changed: " + item["path"])
    if digest(root / "legal/LICENSE") != manifest["license_sha256"]:
        raise ValueError("Changed license")
    if not (root / "legal/NOTICE.txt").is_file():
        raise ValueError("Missing attribution")
    print("Depth Anything V2 Small FP16: pinned model, 3 files and Apache-2.0 notice intact")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1] / "assets/depth-model")
    check(parser.parse_args().root)
