"""Release identity, channel handling and allowlisted packaging checks."""
from pathlib import Path
from contextlib import redirect_stdout
from tempfile import TemporaryDirectory
from unittest.mock import patch
from zipfile import ZipFile
import hashlib,importlib.util,io,shutil,unittest

REPO=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('qp_release_builder',REPO/'tools/build_release.py')
B=importlib.util.module_from_spec(spec);spec.loader.exec_module(B)

class ReleaseBuilderTests(unittest.TestCase):
    def setUp(self):
        self.tmp=TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.source=self.root/'QuestPartners'
        shutil.copytree(REPO/'QuestPartners',self.source)
    def version(self,version):
        for n in ('Core.lua','QuestPartners.toc'):
            p=self.source/n;p.write_bytes(p.read_bytes().replace(b'0.6.0',version.encode(),1))
    def build(self,channel=None):
        with patch.object(B,'ROOT',self.root),redirect_stdout(io.StringIO()):
            return B.build(self.source,channel=channel)
    def test_stable_defaults_to_release(self):
        r=self.build();self.assertEqual(r['planned_file_type'],'Release')
        self.assertEqual(r['filename'],'QuestPartners-0.6.0-forever.zip')
        self.assertEqual(r['curseforge_project_id'],1811599)
    def test_test9_defaults_to_alpha(self):
        self.version('0.6.0-test9');r=self.build()
        self.assertEqual(r['planned_file_type'],'Alpha');self.assertTrue(r['filename'].endswith('-forever-alpha.zip'))
    def test_beta_suffix_is_detected(self):
        self.version('0.6.1-beta.1');self.assertEqual(self.build()['planned_file_type'],'Beta')
    def test_explicit_channel_is_honoured(self):
        self.assertEqual(self.build('alpha')['planned_file_type'],'Alpha')
    def test_release_rejects_prerelease_version(self):
        self.version('0.6.0-test9')
        with self.assertRaisesRegex(ValueError,'prerelease'):self.build('release')
        self.assertFalse((self.root/'upload').exists())
    def test_invalid_channel_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'channel'):self.build('unknown')
    def test_mismatched_versions_are_rejected(self):
        p=self.source/'QuestPartners.toc';p.write_bytes(p.read_bytes().replace(b'0.6.0',b'0.6.1'))
        with self.assertRaisesRegex(ValueError,'versions differ'):self.build()
    def test_reproducible_allowlist_and_checksum(self):
        (self.source/'private-settings.txt').write_text('fixture only')
        first=self.build();path=self.root/'upload'/first['filename'];before=path.read_bytes()
        second=self.build();self.assertEqual(before,path.read_bytes())
        self.assertEqual(first['sha256'],hashlib.sha256(before).hexdigest())
        self.assertEqual(first['sha256'],second['sha256'])
        with ZipFile(path) as z:
            self.assertEqual(set(z.namelist()),{'QuestPartners/'+n for n in B.FILES})
            self.assertEqual(len(z.namelist()),10)
            self.assertIsNone(z.testzip())
