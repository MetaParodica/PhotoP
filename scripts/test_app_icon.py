"""Checks production icon resources without a third-party imaging dependency."""
import hashlib
import json
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / 'ios/PhotoP/Assets.xcassets/AppIcon.appiconset'


class AppIconTests(unittest.TestCase):
    def test_every_iphone_slot_has_correct_opaque_png_dimensions(self):
        entries = json.loads((ICONS / 'Contents.json').read_text())['images']
        self.assertEqual(len(entries), 9)
        for entry in entries:
            image = ICONS / entry['filename']
            self.assertEqual(image.parent, ICONS)
            data = image.read_bytes()
            self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
            self.assertEqual(data[12:16], b'IHDR')
            width, height, depth, color = struct.unpack('>IIBB', data[16:26])
            expected = int(entry['size'].split('x')[0]) * int(entry['scale'][0])
            self.assertEqual((width, height), (expected, expected))
            self.assertEqual((depth, color), (8, 2), 'App Store icon must not contain alpha')
        slots = {(e['size'], e['scale']) for e in entries if e['idiom'] == 'iphone'}
        self.assertEqual(slots, {(f'{p}x{p}', f'{s}x') for p in (20, 29, 40, 60) for s in (2, 3)})

    def test_marketing_icon_matches_recorded_user_image_conversion(self):
        record = json.loads((ROOT / 'assets/app-icon-source.json').read_text())
        self.assertEqual(hashlib.sha256((ICONS / 'Icon-1024.png').read_bytes()).hexdigest(), record['icon1024SHA256'])
        self.assertEqual(len(record['sourceSHA256']), 64)


if __name__ == '__main__':
    unittest.main()
