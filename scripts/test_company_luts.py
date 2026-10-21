import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from check_company_luts import validate


class CompanyLUTTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        data = b'LUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n'
        (self.root / 'test.cube').write_bytes(data)
        revision = '1' * 40
        self.entry = dict(id='test', file='test.cube', official=False, rightsStatus='unverified', license=None,
                          commercialUseAllowed=None, redistributionAllowed=None, sourceRevision=revision,
                          source=f'https://github.com/test/luts/blob/{revision}/test.cube', nativeInput='srgb-assumed',
                          nativeOutput='srgb-assumed', role='creative', previewColors=[[0, 0, 0]] * 12,
                          sha256=hashlib.sha256(data).hexdigest(),
                          gitBlobSHA=hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest())
        self.write(self.entry)

    def write(self, entry):
        (self.root / 'manifest.json').write_text(json.dumps(dict(schemaVersion=1, assets=[entry])))

    def test_unverified_rights_do_not_block_integrity_validation(self):
        self.assertEqual(len(validate(self.root)), 1)

    def test_changed_original_bytes_are_rejected(self):
        with (self.root / 'test.cube').open('ab') as f: f.write(b'# changed')
        with self.assertRaisesRegex(ValueError, 'SHA256'): validate(self.root)

    def test_path_escape_profile_and_false_official_claim_are_rejected(self):
        for key, value in [('file', '../test.cube'), ('nativeOutput', 'camera-log'), ('official', True), ('redistributionAllowed', True)]:
            entry = copy.deepcopy(self.entry); entry[key] = value; self.write(entry)
            with self.assertRaises(ValueError): validate(self.root)

    def test_unregistered_asset_is_rejected(self):
        (self.root / 'extra.cube').write_bytes((self.root / 'test.cube').read_bytes())
        with self.assertRaisesRegex(ValueError, 'unregistered'): validate(self.root)
