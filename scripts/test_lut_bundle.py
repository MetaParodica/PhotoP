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
        (self.root / 'LICENSE.txt').write_bytes(b'fixture license')
        self.asset = dict(file='test.cube', redistributionAllowed=True, commercialUseAllowed=True,
                          license='test-only', source='fixture', creator='fixture', requiredCredit='fixture',
                          licenseFile='LICENSE.txt', licenseSHA256=hashlib.sha256(b'fixture license').hexdigest(), profileBasis='declared',  inputProfile='sRGB', outputProfile='sRGB',
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

    def test_missing_credit(self):
        self.asset['requiredCredit'] = ''
        self.write([self.asset])
        with self.assertRaises(ValueError): validate(self.root)

    def test_missing_or_changed_license(self):
        self.write([self.asset])
        (self.root / 'LICENSE.txt').write_bytes(b'changed')
        with self.assertRaises(ValueError): validate(self.root)
        (self.root / 'LICENSE.txt').unlink()
        with self.assertRaises(ValueError): validate(self.root)

    def test_license_path_escape(self):
        self.asset['licenseFile'] = '../outside.txt'
        self.write([self.asset])
        with self.assertRaises(ValueError): validate(self.root)

    def test_assumed_profile_requires_confirmation(self):
        self.asset['profileBasis'] = 'assumed-sRGB'
        self.write([self.asset])
        with self.assertRaises(ValueError): validate(self.root)
        self.asset['requiresSRGBConfirmation'] = True
        self.write([self.asset])
        self.assertEqual(validate(self.root), 1)


if __name__ == '__main__': unittest.main()
