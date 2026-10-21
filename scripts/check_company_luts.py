"""Integrity/profile checks for the separately tracked, rights-unverified LUT collection.

Unknown rights are recorded, not treated as an approval or an exclusion gate.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re


def validate(root):
    root = Path(root).resolve()
    manifest = json.loads((root / 'manifest.json').read_text())
    if manifest.get('schemaVersion') != 1:
        raise ValueError('unsupported manifest')
    files, identifiers = set(), set()
    for item in manifest['assets']:
        path = Path(item['file'])
        file = root / path
        if path.is_absolute() or '..' in path.parts or root not in file.resolve().parents or file.is_symlink():
            raise ValueError('unsafe LUT path')
        if item['id'] in identifiers or item['file'] in files:
            raise ValueError('duplicate LUT')
        identifiers.add(item['id']); files.add(item['file'])
        if item['official'] is not False or item['rightsStatus'] != 'unverified':
            raise ValueError('this mirror collection must not claim official or verified status')
        if any(item.get(k) is not None for k in ('license', 'commercialUseAllowed', 'redistributionAllowed')):
            raise ValueError('unverified rights must remain unknown')
        revision = item['sourceRevision']
        if not re.fullmatch('[0-9a-f]{40}', revision) or f'/blob/{revision}/' not in item['source']:
            raise ValueError('source must be pinned')
        profiles = (item['nativeInput'], item['nativeOutput'])
        if profiles not in {('vlog-vgamut', 'rec709-gamma24-assumed'), ('vlog-vgamut', 'wdr-unverified'), ('srgb-assumed', 'srgb-assumed')}:
            raise ValueError('unsupported profile declaration')
        if item['role'] not in ('creative', 'technical'):
            raise ValueError('missing role')
        patches = item['previewColors']
        if len(patches) != 12 or any(len(p) != 3 or any(not math.isfinite(v) or not 0 <= v <= 1 for v in p) for p in patches):
            raise ValueError('invalid preview patches')
        data = file.read_bytes()
        if len(data) > 32 * 1024 * 1024 or hashlib.sha256(data).hexdigest() != item['sha256']:
            raise ValueError('LUT SHA256 mismatch')
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if blob != item['gitBlobSHA']:
            raise ValueError('source Git blob mismatch')
        size, count = None, 0
        for raw in data.decode('utf-8').splitlines():
            line = raw.split('#', 1)[0].strip()
            if not line or line.startswith('TITLE '):
                continue
            if line.startswith('LUT_3D_SIZE '):
                if size is not None:
                    raise ValueError('duplicate LUT size')
                size = int(line.split()[1])
                if not 2 <= size <= 65:
                    raise ValueError('unsupported LUT size')
            elif line.startswith(('DOMAIN_MIN ', 'DOMAIN_MAX ')):
                if len(line.split()) != 4:
                    raise ValueError('invalid domain')
            else:
                values = [float(x) for x in line.split()]
                if size is None or len(values) != 3 or not all(math.isfinite(x) for x in values):
                    raise ValueError('invalid cube rows')
                count += 1
        if size is None or count != size ** 3:
            raise ValueError('cube size/count mismatch')
    actual = {str(p.relative_to(root)) for p in root.rglob('*.cube')}
    if files != actual:
        raise ValueError('unregistered or missing LUT file')
    return manifest['assets']


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--bundle', type=Path, default=Path(__file__).resolve().parents[1] / 'assets/company-luts')
    args = parser.parse_args()
    entries = validate(args.bundle)
    print(f'{len(entries)} external LUT files intact; rights unverified (recorded, not approved)')
