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
    derived = manifest["derivation"]
    if derived["sourceSpecificationSHA256"] != "7d128934363e8f5771ff4ac1f90f2ea4fedc9b5e99c28e075199aee02381ef9c" or derived["derivedSpecificationSHA256"] != "2b53c9007612dbfff8606de547ee180287700ea1c0b3c109e592d94fbae8d15a":
        raise ValueError("Changed decoder output adaptation")
    script = Path(__file__).resolve().parent / "derive_experimental_photo_head.py"
    if derived["script"] != "scripts/derive_experimental_photo_head.py" or hashlib.sha256(script.read_bytes()).hexdigest() != derived["scriptSHA256"]:
        raise ValueError("Changed decoder derivation script")
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


def check_portrait():
    repository = Path(__file__).resolve().parents[1]
    root = repository / "assets/experimental-matte/ExperimentalPortraitMatte"
    record = json.loads((repository / "third-party/MatAnyone2Kit/provenance.json").read_text())
    if record["schemaVersion"] != 1 or record["revision"] != "d85a029870b5149af6aa122cbc13c90db11e5b35":
        raise ValueError("Portrait model requires a new provenance audit")
    if record["codeLicense"] != "GPL-3.0" or record["weightsLicense"] != "NTU S-Lab License 1.0":
        raise ValueError("Changed portrait rights records")
    actual = {str(path.relative_to(root)) for path in root.rglob("*") if path.is_file()}
    if len(record["files"]) != 35 or actual != {entry["path"] for entry in record["files"]}:
        raise ValueError("Changed portrait resource inventory")
    for entry in record["files"]:
        path = root / entry["path"]
        if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError("Unsafe portrait resource")
        data = path.read_bytes()
        if len(data) != entry["bytes"] or hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise ValueError("Changed portrait resource: " + entry["path"])
    expected = {f"ios/PhotoP/External/MatAnyone2/{name}.swift" for name in ["MatAnyoneCoreML", "MatAnyoneCoreMLEngine", "MemoryBank"]}
    if len(record["sourceFiles"]) != 3 or {entry["file"] for entry in record["sourceFiles"]} != expected:
        raise ValueError("Changed portrait source scope")
    for entry in record["sourceFiles"]:
        if hashlib.sha256((repository / entry["file"]).read_bytes()).hexdigest() != entry["adaptedFileSHA256"]:
            raise ValueError("Portrait adapter changes require a provenance update")
    fingerprint = hashlib.sha256(json.dumps(record["files"], sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    if fingerprint != record["resourceFingerprint"]:
        raise ValueError("Changed portrait fingerprint")
    print("Experimental MatAnyone2 photo: 35 resource and 3 adapted-source hashes intact")


if __name__ == "__main__":
    check()
    check_portrait()
