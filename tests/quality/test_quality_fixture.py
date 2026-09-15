"""Tests for fixture integrity, not an imitation of production policy."""
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
import urllib.error
import urllib.request
import zipfile

MODULE = Path(__file__).resolve().parents[2] / 'tools/quality-fixture.py'
spec = importlib.util.spec_from_file_location('quality_fixture', MODULE)
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class FixtureTests(unittest.TestCase):
    def test_mixed_contains_real_competing_stream_classes(self):
        formats = fixture.case_info('mixed', 'http://127.0.0.1:1234')['formats']
        self.assertEqual(['muxed360', 'v720', 'v1080', 'audio'], [f['format_id'] for f in formats])
        self.assertEqual('aac', formats[0]['acodec'])
        self.assertEqual('none', formats[1]['acodec'])
        self.assertEqual('none', formats[3]['vcodec'])

    def test_portrait_exposes_short_edge_1080(self):
        video = fixture.case_info('portrait', '')['formats'][0]
        self.assertEqual((1080, 1920), (video['width'], video['height']))

    def test_above_cap_has_no_hidden_low_resolution_fallback(self):
        formats = fixture.case_info('above-cap', '')['formats']
        self.assertEqual([2160], [min(f['width'], f['height']) for f in formats if f['vcodec'] != 'none'])

    def test_missing_dimensions_and_streams_are_distinct(self):
        unknown = fixture.case_info('unknown-dimensions', '')['formats'][0]
        self.assertIsNone(unknown['width'])
        self.assertIsNone(unknown['height'])
        self.assertTrue(all(f['acodec'] == 'none' for f in fixture.case_info('missing-audio', '')['formats']))
        self.assertTrue(all(f['vcodec'] == 'none' for f in fixture.case_info('audio-only', '')['formats']))

    def test_changed_and_unavailable_remove_previously_pinned_id(self):
        for case, state in [('changed', 'changed'), ('unavailable', 'missing')]:
            before = fixture.case_info(case, '')['formats']
            after = fixture.case_info(case, '', state)['formats']
            self.assertIn('v1080', [f['format_id'] for f in before])
            self.assertNotIn('v1080', [f['format_id'] for f in after])
            self.assertIn('v720', [f['format_id'] for f in after])

    def test_playlist_has_distinct_urls_and_live_explicit_marker(self):
        playlist = fixture.case_info('playlist', 'http://127.0.0.1:1234')
        self.assertEqual('_type', next(iter(playlist)))
        self.assertEqual(2, len({e['url'] for e in playlist['entries']}))
        self.assertTrue(fixture.case_info('live', '')['is_live'])

    def test_output_oracle_rejects_missing_audio_wrong_size_and_wrong_codec(self):
        base = {'streams': [{'codec_type': 'video', 'width': 1920, 'height': 1080,
                             'codec_name': 'vp9'}, {'codec_type': 'audio'}],
                'format': {'duration': '1'}}
        fixture.assert_media(base, (1920, 1080), 'vp9')
        with self.assertRaises(AssertionError):
            fixture.assert_media(base, (1280, 720), 'vp9')
        with self.assertRaises(AssertionError):
            fixture.assert_media(base, (1920, 1080), 'h264')
        base['streams'].pop()
        with self.assertRaises(AssertionError):
            fixture.assert_media(base, (1920, 1080), 'vp9')

    def test_zip_traversal_and_duplicates_rejected(self):
        for names in [('../escape',), ('C:/escape',), ('a:stream',), ('A.exe', 'a.exe')]:
            archive = io.BytesIO()
            with zipfile.ZipFile(archive, 'w') as zipped:
                for name in names:
                    zipped.writestr(name, b'x')
            archive.seek(0)
            with tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(ValueError):
                    fixture.safe_extract(archive, Path(directory))

    def test_http_only_serves_fixture_routes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture.write_json(root / 'states.json', {})
            (root / 'private.txt').write_text('not media')
            with fixture.server(root) as base:
                with urllib.request.urlopen(base + '/quality/mixed') as response:
                    self.assertEqual('mixed', json.load(response)['id'])
                with self.assertRaises(urllib.error.HTTPError) as error:
                    urllib.request.urlopen(base + '/private.txt')
                self.assertEqual(404, error.exception.code)


if __name__ == '__main__':
    unittest.main(verbosity=2)
