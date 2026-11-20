"""Verify pinned experimental photo models; this does not run Core ML."""
import hashlib
import json
from pathlib import Path

ARCHIVE = "9c35c1b6667a0dd80b093bbc20747628f304133ad2a531de049307beb3ae1401"
PACKAGES = {"ExperimentalPhotoEncoder.mlpackage", "ExperimentalPhotoInitializer.mlpackage"}
SUFFIXES = {"Manifest.json", "Data/com.apple.CoreML/model.mlmodel", "Data/com.apple.CoreML/weights/weight.bin"}


def check(root=None):
    root = (root or Path(__file__).resolve().parents[1] / "assets/experimental-depth").resolve()
    manifest = json.loads((root / "ExperimentalDepthLegal/manifest.json").read_text())
    if manifest["schemaVersion"] != 1 or manifest["archiveSHA256"] != ARCHIVE or manifest["license"] != "Apache-2.0":
        raise ValueError("Experimental model requires a new provenance audit")
    expected = {f"{package}/{suffix}" for package in PACKAGES for suffix in SUFFIXES}
    records = manifest["files"]
    if len(records) != 6 or {entry["path"] for entry in records} != expected:
        raise ValueError("Unexpected model files")
    legal = manifest["legalFiles"]
    if {entry["path"] for entry in legal} != {"ExperimentalDepthLegal/LICENSE", "ExperimentalDepthLegal/NOTICE"} or len(legal) != 2:
        raise ValueError("Missing license or notice")
    for entry in records + legal:
        path = root / entry["path"]
        if path.is_symlink() or not path.resolve().is_relative_to(root):
            raise ValueError("Unsafe model path")
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != entry["sha256"] or len(data) != entry.get("bytes", len(data)):
            raise ValueError("Changed pinned file: " + entry["path"])
    print("Experimental EdgeTAM photo: 6 pinned model files and 2 rights records intact")


if __name__ == "__main__":
    check()
