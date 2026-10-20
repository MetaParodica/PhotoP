import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from check_lut_bundle import validate


class LUTBundleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.data = b'TITLE "test"\n'
        (self.root / 'test.cube').write_bytes(self.data)
        self.asset = dict(file='test.cube', redistributionAllowed=True, commercialUseAllowed=True,
                          license='test-only', source='fixture', inputProfile='sRGB', outputProfile='sRGB',
                          sha256=hashlib.sha256(self.data).hexdigest())

    def write(self, assets):
        (self.root / 'manifest.json').write_text(json.dumps(dict(schemaVersion=1, assets=assets)))

    def test_valid_asset(self):
        self.write([self.asset])
        self.assertEqual(validate(self.root), 1)

    def test_unregistered_file(self):
        self.write([])
        with self.assertRaises(ValueError): validate(self.root)

    def test_unclear_redistribution(self):
        self.asset['redistributionAllowed'] = None
        self.write([self.asset])
        with self.assertRaises(ValueError): validate(self.root)

    def test_research_only_asset(self):
        self.asset['commercialUseAllowed'] = False
        self.write([self.asset])
        with self.assertRaises(ValueError): validate(self.root)

    def test_changed_bytes(self):
        self.write([self.asset])
        (self.root / 'test.cube').write_bytes(b'changed')
        with self.assertRaises(ValueError): validate(self.root)

    def test_path_escape(self):
        self.asset['file'] = '../outside.cube'
        self.write([self.asset])
        with self.assertRaises(ValueError): validate(self.root)

    def test_missing_color_profile(self):
        self.asset['inputProfile'] = ''
        self.write([self.asset])
        with self.assertRaises(ValueError): validate(self.root)


if __name__ == '__main__': unittest.main()
