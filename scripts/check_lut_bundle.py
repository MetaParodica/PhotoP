#!/usr/bin/env python3
"""Validate the explicit LUT bundle manifest; downloaded catalogs are separate."""
import argparse
import hashlib
import json
from pathlib import Path


def validate(root: Path) -> int:
    manifest = json.loads((root / 'manifest.json').read_text())
    if manifest.get('schemaVersion') != 1:
        raise ValueError('Unsupported manifest version')
    registered = set()
    for asset in manifest['assets']:
        relative = Path(asset['file'])
        path = (root / relative).resolve()
        if relative.is_absolute() or not path.is_relative_to(root.resolve()):
            raise ValueError('Asset path must stay inside the bundle')
        if str(relative) in registered:
            raise ValueError('Duplicate asset path')
        registered.add(str(relative))
        if asset.get('redistributionAllowed') is not True:
            raise ValueError('Bundled file lacks redistribution approval')
        if asset.get('commercialUseAllowed') is not True:
            raise ValueError('Commercial bundle includes a research-only LUT')
        if not asset.get('license') or not asset.get('source') or not asset.get('inputProfile') or not asset.get('outputProfile'):
            raise ValueError('Missing rights or color profile evidence')
        if not asset.get('requiredCredit') or not asset.get('creator') or not asset.get('profileBasis'):
            raise ValueError('Missing credit, creator or profile basis')
        if asset['profileBasis'] == 'assumed-sRGB' and asset.get('requiresSRGBConfirmation') is not True:
            raise ValueError('Assumed input requires explicit declaration')
        license_path = (root / asset.get('licenseFile', '')).resolve()
        if not license_path.is_relative_to(root.resolve()) or not license_path.is_file():
            raise ValueError('License file must stay inside the bundle')
        if hashlib.sha256(license_path.read_bytes()).hexdigest() != asset.get('licenseSHA256'):
            raise ValueError('License hash mismatch')
        if hashlib.sha256(path.read_bytes()).hexdigest() != asset['sha256']:
            raise ValueError('Asset hash mismatch')
    files = {str(p.relative_to(root)) for p in root.rglob('*')
             if p.is_file() and p.suffix.lower() in {'.cube', '.png', '.3dl', '.vlt'}}
    if files != registered:
        raise ValueError('Unregistered or missing bundled LUT files')
    return len(registered)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path)
    args = parser.parse_args()
    root = args.bundle or Path(__file__).resolve().parents[1] / 'assets' / 'luts' 
    print(f'Commercial LUT bundle: {validate(root)} approved assets')
