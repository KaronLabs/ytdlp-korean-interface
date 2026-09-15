#!/usr/bin/env python3
"""Offline media fixture. Engine checks are NOT application GUI acceptance."""
import argparse
import contextlib
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import zipfile


PLUGIN = r'''from yt_dlp.extractor.common import InfoExtractor

class QualityFixtureIE(InfoExtractor):
    IE_NAME = 'quality-fixture'
    _VALID_URL = r'http://127\.0\.0\.1:\d+/quality/(?P<id>[a-z0-9-]+)$'

    def _real_extract(self, url):
        info = self._download_json(url, self._match_id(url))
        warning = info.pop('_fixture_warning', None)
        if warning:
            self.report_warning(warning)
        return info
'''


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def run(args, root, label, env=None, expect=0):
    started = time.time()
    result = subprocess.run([str(a) for a in args], cwd=root, env=env,
                            capture_output=True, text=True, encoding='utf-8',
                            errors='replace', timeout=120)
    log = {'argv': [str(a) for a in args], 'cwd': str(root),
           'started_unix': started, 'duration': time.time() - started,
           'returncode': result.returncode, 'stdout': result.stdout,
           'stderr': result.stderr}
    write_json(Path(root) / (label + '.command.json'), log)
    if expect is not None and result.returncode != expect:
        raise RuntimeError(f'{label}: exit {result.returncode}: {result.stderr[-1600:]}')
    return result


def install_plugin(runtime):
    path = runtime / 'yt-dlp-plugins/quality_fixture/yt_dlp_plugins/extractor/quality_fixture.py'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(PLUGIN, encoding='utf-8')


def safe_extract(archive, destination):
    """Reject traversal, links, duplicate paths and Windows alternate streams."""
    seen = set()
    with zipfile.ZipFile(archive) as zipped:
        for entry in zipped.infolist():
            normalized = entry.filename.replace('\\', '/')
            path = Path(normalized)
            if (path.is_absolute() or '..' in path.parts or ':' in normalized
                    or (entry.external_attr >> 16) & 0o170000 == 0o120000):
                raise ValueError('unsafe ZIP entry: ' + entry.filename)
            key = normalized.casefold().rstrip('/')
            if key in seen:
                raise ValueError('duplicate ZIP entry: ' + entry.filename)
            seen.add(key)
        zipped.extractall(destination)


def prepare(args):
    root = args.root.resolve()
    root.mkdir(parents=True, exist_ok=False)
    runtime = root / 'runtime'
    identity = {}
    if args.candidate_zip:
        archive = args.candidate_zip.resolve()
        identity['zip_sha256'] = sha256(archive)
        identity['zip_path'] = str(archive)
        safe_extract(archive, root / 'unpacked')
        apps = list((root / 'unpacked').rglob('ytdlp-interface.exe'))
        if len(apps) != 1:
            raise ValueError('ZIP must contain exactly one ytdlp-interface.exe')
        shutil.copytree(apps[0].parent, runtime)
    else:
        runtime.mkdir()
        for name in ('yt-dlp.exe', 'ffmpeg.exe', 'ffprobe.exe'):
            shutil.copy2(args.runtime / name, runtime / name)
        identity['runtime_source'] = str(args.runtime.resolve())
    identity['files_before_instrumentation'] = {
        str(p.relative_to(runtime)): sha256(p) for p in runtime.rglob('*') if p.is_file()}
    install_plugin(runtime)
    # Every config written here belongs to this fixture copy, never the original.
    for name in ('profile', 'appdata', 'localappdata', 'home', 'media', 'outputs'):
        (root / name).mkdir()
    write_json(root / 'states.json', {})
    env = isolated_env(root)
    for name in ('yt-dlp', 'ffmpeg', 'ffprobe'):
        flag = '--version' if name == 'yt-dlp' else '-version'
        result = run([runtime / (name + '.exe'), flag], root, name + '-version', env)
        identity[name + '_version'] = result.stdout.splitlines()[0]
    write_json(root / 'identity.json', identity)
    ffmpeg = runtime / 'ffmpeg.exe'
    media = root / 'media'
    sizes = {'v360': (640, 360), 'v720': (1280, 720), 'v1080': (1920, 1080),
             'v2160': (3840, 2160), 'portrait': (1080, 1920),
             'vp9': (1920, 1080), 'av1': (1920, 1080)}
    for name, (width, height) in sizes.items():
        codec = ['-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '20']
        ext = 'mp4'
        if name == 'vp9':
            codec = ['-c:v', 'libvpx-vp9', '-deadline', 'realtime', '-cpu-used', '8', '-crf', '24', '-b:v', '0']
            ext = 'webm'
        elif name == 'av1':
            codec = ['-c:v', 'libaom-av1', '-cpu-used', '8', '-crf', '28', '-b:v', '0']
            ext = 'webm'
        run([ffmpeg, '-hide_banner', '-nostdin', '-y', '-f', 'lavfi', '-i',
             f'testsrc2=size={width}x{height}:rate=4', '-t', '1', '-an',
             *codec, '-threads', '2', '-pix_fmt', 'yuv420p', media / f'{name}.{ext}'],
            root, 'generate-' + name, env)
    run([ffmpeg, '-hide_banner', '-nostdin', '-y', '-f', 'lavfi', '-i',
         'sine=frequency=997:sample_rate=48000', '-t', '1', '-c:a', 'aac',
         '-b:a', '128k', media / 'audio.m4a'], root, 'generate-audio', env)
    run([ffmpeg, '-hide_banner', '-nostdin', '-y', '-i', media / 'v360.mp4',
         '-i', media / 'audio.m4a', '-map', '0:v:0', '-map', '1:a:0', '-c', 'copy',
         '-shortest', media / 'muxed360.mp4'], root, 'generate-muxed360', env)
    probes = {}
    for path in sorted(media.iterdir()):
        result = run([runtime / 'ffprobe.exe', '-v', 'error', '-show_streams',
                      '-show_format', '-of', 'json', path], root, 'probe-' + path.stem, env)
        probes[path.name] = {'sha256': sha256(path), 'probe': json.loads(result.stdout)}
    write_json(root / 'media-manifest.json', probes)
    print(json.dumps({'prepared': str(root), 'identity': identity}, indent=2))


def isolated_env(root):
    env = os.environ.copy()
    env.update({'USERPROFILE': str(root / 'profile'), 'APPDATA': str(root / 'appdata'),
                'LOCALAPPDATA': str(root / 'localappdata'), 'HOME': str(root / 'home'),
                'XDG_CONFIG_HOME': str(root / 'home'), 'NO_PROXY': '127.0.0.1,localhost'})
    return env


CASES = ('mixed', 'only360', 'above-cap', 'portrait', 'unknown-dimensions',
         'missing-audio', 'audio-only', 'vp9', 'av1', 'playlist', 'live',
         'changed', 'unavailable', 'warning')


def case_info(case, base, state=None):
    def video(name, width, height, codec='h264', audio=False):
        ext = 'webm' if codec in ('vp9', 'av1') else 'mp4'
        return {'format_id': name, 'url': f'{base}/media/{name}.{ext}',
                'ext': ext, 'width': width, 'height': height, 'fps': 4,
                'vcodec': codec, 'acodec': 'aac' if audio else 'none', 'protocol': 'http'}
    audio = {'format_id': 'audio', 'url': base + '/media/audio.m4a', 'ext': 'm4a',
             'vcodec': 'none', 'acodec': 'aac', 'abr': 128, 'protocol': 'http'}
    muxed = video('muxed360', 640, 360, audio=True)
    v720, v1080 = video('v720', 1280, 720), video('v1080', 1920, 1080)
    variants = {'mixed': [muxed, v720, v1080, audio], 'only360': [muxed],
                'above-cap': [video('v2160', 3840, 2160), audio],
                'portrait': [video('portrait', 1080, 1920), audio],
                'unknown-dimensions': [video('v1080', None, None), audio],
                'missing-audio': [v1080], 'audio-only': [audio],
                'vp9': [muxed, video('vp9', 1920, 1080, 'vp9'), audio],
                'av1': [muxed, video('av1', 1920, 1080, 'av1'), audio],
                'changed': [v720, audio] if state == 'changed' else [v1080, audio],
                'unavailable': [v720, audio] if state == 'missing' else [v1080, audio],
                'live': [muxed], 'warning': [muxed]}
    if case == 'playlist':
        return {'_type': 'playlist', 'id': 'fixture-playlist', 'title': 'Two distinct videos',
                'entries': [{'_type': 'url', 'url': base + '/quality/' + name}
                            for name in ('mixed', 'only360')]}
    info = {'id': case, 'title': 'Quality fixture ' + case, 'duration': 1,
            'webpage_url': base + '/quality/' + case, 'formats': variants[case]}
    if case == 'live':
        info.update(is_live=True, live_status='is_live')
    if case == 'warning':
        info['_fixture_warning'] = 'Fixture extraction warning: formats may be incomplete'
    return info


@contextlib.contextmanager
def server(root, port=0):
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=str(root), **kwargs)

        def log_message(self, fmt, *args):
            with (root / 'http-requests.log').open('a', encoding='utf-8') as log:
                log.write(f'{time.time():.6f} {fmt % args}\n')

        def do_GET(self):
            path = urllib.parse.urlsplit(self.path).path
            if path.startswith('/quality/'):
                case = path.removeprefix('/quality/')
                if case not in CASES:
                    self.send_error(404)
                    return
                states = json.loads((root / 'states.json').read_text(encoding='utf-8'))
                body = json.dumps(case_info(case, f'http://127.0.0.1:{self.server.server_port}',
                                            states.get(case))).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif path.startswith('/media/') and Path(path).name == path.removeprefix('/media/'):
                super().do_GET()
            else:
                self.send_error(404)
    service = http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler)
    worker = threading.Thread(target=service.serve_forever, daemon=True)
    worker.start()
    try:
        yield f'http://127.0.0.1:{service.server_port}'
    finally:
        service.shutdown()
        service.server_close()
        worker.join(timeout=5)


def assert_media(probe, dimensions, codec=None):
    streams = probe['streams']
    videos = [s for s in streams if s['codec_type'] == 'video']
    audios = [s for s in streams if s['codec_type'] == 'audio']
    assert len(videos) == 1 and audios, 'output must contain video AND audio'
    assert (videos[0]['width'], videos[0]['height']) == dimensions, videos
    if codec:
        assert videos[0]['codec_name'] == codec, videos
    assert float(probe['format']['duration']) > 0


def check(args):
    root = args.root.resolve()
    runtime = root / 'runtime'
    env = isolated_env(root)
    checks = [('mixed', 1080, (1920, 1080), 'h264'), ('mixed', 720, (1280, 720), 'h264'),
              ('only360', 1080, (640, 360), 'h264'), ('portrait', 1080, (1080, 1920), 'h264'),
              ('above-cap', 1080, (3840, 2160), 'h264'),
              ('vp9', 1080, (1920, 1080), 'vp9'), ('av1', 1080, (1920, 1080), 'av1')]
    results = []
    with server(root) as base:
        for case, cap, dimensions, codec in checks:
            label = f'engine-{case}-{cap}'
            final = root / (label + '.final.txt')
            cmd = [runtime / 'yt-dlp.exe', '--ignore-config', '--no-cache-dir',
                   '--no-colors', '--proxy', '', '--ffmpeg-location', runtime,
                   '-f', 'bv*+ba/b', '-S', f'res:{cap}', '--write-info-json',
                   '--print-to-file', 'after_move:filepath', final,
                   '-o', root / 'outputs' / (label + '.%(ext)s'), base + '/quality/' + case]
            run(cmd, root, label, env)
            output = Path(final.read_text(encoding='utf-8').strip().splitlines()[-1])
            probe = json.loads(run([runtime / 'ffprobe.exe', '-v', 'error', '-show_streams',
                                   '-show_format', '-of', 'json', output], root, label + '-probe', env).stdout)
            assert_media(probe, dimensions, codec)
            results.append({'case': case, 'cap': cap, 'path': str(output),
                            'sha256': sha256(output), 'video_codec': codec,
                            'dimensions': dimensions, 'audio_present': True,
                            'meaning': 'sorting is NOT a hard cap; production must reject' if case == 'above-cap'
                                       else 'fixture engine check only'})
        # Poison the fixture portable config, then prove ignored vs read behavior.
        config = runtime / 'yt-dlp.conf'
        if config.exists():
            raise RuntimeError('refusing to overwrite candidate config')
        config.write_text('-f best\n-x\n--audio-format mp3\n', encoding='utf-8')
        try:
            for ignored, expected in ((False, 'muxed360'), (True, 'v1080+audio')):
                label = 'config-' + ('ignored' if ignored else 'honored')
                cmd = [runtime / 'yt-dlp.exe', '--no-cache-dir', '--proxy', '', '-j',
                       '--skip-download', base + '/quality/mixed']
                if ignored:
                    cmd[1:1] = ['--ignore-config', '-f', 'bv*+ba/b', '-S', 'res:1080']
                info = json.loads(run(cmd, root, label, env).stdout)
                assert info['format_id'] == expected, info['format_id']
                results.append({'case': label, 'format_id': info['format_id'],
                                'meaning': 'engine config behavior only; application injection pending'})
        finally:
            config.unlink()
        for case in ('unknown-dimensions', 'missing-audio', 'audio-only', 'live', 'playlist', 'warning'):
            # Unprocessed dump retains absent metadata, allowing native helper input.
            info = case_info(case, base)
            write_json(root / ('input-' + case + '.json'), info)
        for case in ('changed', 'unavailable'):
            write_json(root / ('input-' + case + '-before.json'), case_info(case, base))
            write_json(root / ('input-' + case + '-after.json'),
                       case_info(case, base, 'changed' if case == 'changed' else 'missing'))
    write_json(root / 'engine-results.json', {'tier': 'FIXTURE_ENGINE_ONLY',
                                             'gui_acceptance': False, 'results': results})
    print(json.dumps({'tier': 'FIXTURE_ENGINE_ONLY', 'passed': len(results),
                      'gui_acceptance': False, 'results': str(root / 'engine-results.json')}))


def serve(args):
    root = args.root.resolve()
    with server(root, args.port) as base:
        urls = {case: base + '/quality/' + case for case in CASES}
        write_json(root / 'server.json', {'pid': os.getpid(), 'base': base, 'urls': urls})
        print(json.dumps(urls, indent=2), flush=True)
        threading.Event().wait()


def policy_check(args):
    """Call the compiled production header; never reimplement its policy here."""
    if not args.implementation_ready:
        raise RuntimeError('A-ready/controller authorization required')
    root = args.root.resolve()
    helper = args.helper.resolve()
    runtime = root / 'runtime'
    env = isolated_env(root)
    evidence = root / ('production-' + time.strftime('%Y%m%d-%H%M%S'))
    evidence.mkdir()
    results = []
    serial = 0

    def call(operation, policy, **fields):
        nonlocal serial
        serial += 1
        path = evidence / f'helper-{serial:03}.json'
        write_json(path, dict(operation=operation, policy=policy, **fields))
        return json.loads(run([helper, '--request', path], evidence,
                              f'helper-{serial:03}', env).stdout)

    def get_policy(quality='1080p', mode='video'):
        return {'version': 1, 'mode': mode, 'quality': quality}

    def probe_selection(base, case, policy, label):
        argv = call('arguments', policy)
        result = run([runtime / 'yt-dlp.exe', *argv, '--no-cache-dir', '--proxy', '',
                      '--ffmpeg-location', runtime, '--skip-download', '-J',
                      base + '/quality/' + case], evidence, label, env, expect=None)
        if result.returncode:
            return None, {'valid': False, 'error': 'engine_selection_failed'}
        metadata = json.loads(result.stdout)
        return metadata, call('selected', policy, metadata=metadata)

    with server(root) as base:
        for case, quality, dimensions, codec in [
                ('mixed', '1080p', (1920, 1080), 'h264'),
                ('mixed', '720p', (1280, 720), 'h264'),
                ('only360', '1080p', (640, 360), 'h264'),
                ('portrait', '1080p', (1080, 1920), 'h264'),
                ('vp9', '1080p', (1920, 1080), 'vp9'),
                ('av1', '1080p', (1920, 1080), 'av1')]:
            policy = get_policy(quality)
            label = case + '-' + quality
            metadata, selection = probe_selection(base, case, policy, label + '-preview')
            assert selection['valid'], selection
            # A second real extractor call models the required pre-download re-resolution.
            fresh, fresh_selection = probe_selection(base, case, policy, label + '-refresh')
            assert fresh_selection['valid'] and call('same', policy, before=metadata, after=fresh)
            argv = call('arguments', policy, pinned_ids=fresh_selection['format_ids'])
            final = evidence / (label + '-final.txt')
            run([runtime / 'yt-dlp.exe', *argv, '--verbose', '--no-cache-dir', '--proxy', '',
                 '--ffmpeg-location', runtime, '--print-to-file', 'after_move:filepath', final,
                 '-o', evidence / (label + '.%(ext)s'), base + '/quality/' + case],
                evidence, label + '-download', env)
            output = Path(final.read_text(encoding='utf-8').strip())
            actual = json.loads(run([runtime / 'ffprobe.exe', '-v', 'error', '-show_streams',
                                    '-show_format', '-of', 'json', output], evidence,
                                   label + '-ffprobe', env).stdout)
            assert_media(actual, dimensions, codec)
            verdict = call('output', policy, metadata=actual)
            assert verdict['valid'], verdict
            results.append({'case': label, 'selection': fresh_selection,
                            'output': verdict, 'sha256': sha256(output), 'path': str(output)})

        for case, reason in [('above-cap', 'resolution_exceeds_cap'),
                             ('unknown-dimensions', 'unknown_dimensions'),
                             ('missing-audio', 'missing_audio'), ('audio-only', 'missing_video'),
                             ('playlist', 'advanced_required'), ('live', 'advanced_required')]:
            policy = get_policy()
            metadata, result = probe_selection(base, case, policy, case + '-reject')
            assert not result['valid'], (case, result)
            if metadata is not None:
                assert result['error'] == reason, (case, result)
            results.append({'case': case, 'rejection': result,
                            'layer': 'production helper' if metadata is not None else 'engine'})
        metadata, result = probe_selection(base, 'unknown-dimensions', get_policy('best'), 'best-unknown')
        assert result['valid'] and not result['dimensions_known'], result
        results.append({'case': 'best-unknown', 'selection': result})

        # This tests the helper argument path with a real portable config, not a hand-coded ignore flag.
        config = runtime / 'yt-dlp.conf'
        if config.exists():
            raise RuntimeError('refusing to overwrite candidate config')
        config.write_text('-f best\n-x\n--audio-format mp3\n', encoding='utf-8')
        try:
            _, result = probe_selection(base, 'mixed', get_policy(), 'production-config-poison')
            assert result['valid'] and result['format_ids'] == 'v1080+audio', result
            argv = call('arguments', get_policy(), pinned_ids=result['format_ids'])
            final = evidence / 'config-final.txt'
            run([runtime / 'yt-dlp.exe', *argv, '--no-cache-dir', '--proxy', '',
                 '--ffmpeg-location', runtime, '--print-to-file', 'after_move:filepath', final,
                 '-o', evidence / 'config.%(ext)s', base + '/quality/mixed'], evidence, 'config-download', env)
            output = Path(final.read_text(encoding='utf-8').strip())
            actual = json.loads(run([runtime / 'ffprobe.exe', '-v', 'error', '-show_streams',
                                    '-show_format', '-of', 'json', output], evidence, 'config-probe', env).stdout)
            assert_media(actual, (1920, 1080), 'h264')
            assert call('output', get_policy(), metadata=actual)['valid']
            results.append({'case': 'external-config-isolation', 'selection': result,
                            'path': str(output), 'sha256': sha256(output)})
        finally:
            config.unlink()

        before, first = probe_selection(base, 'changed', get_policy(), 'change-before')
        write_json(root / 'states.json', {'changed': 'changed', 'unavailable': 'missing'})
        try:
            after, second = probe_selection(base, 'changed', get_policy(), 'change-after')
            assert first['valid'] and second['valid']
            assert not call('same', get_policy(), before=before, after=after)
            results.append({'case': 'changed-selection', 'before': first, 'after': second, 'same': False})
            argv = call('arguments', get_policy(), pinned_ids=first['format_ids'])
            unavailable = run([runtime / 'yt-dlp.exe', *argv, '--no-cache-dir', '--proxy', '',
                               '--ffmpeg-location', runtime, '-o', evidence / 'unavailable.%(ext)s',
                               base + '/quality/unavailable'], evidence, 'unavailable-pin', env, expect=None)
            assert unavailable.returncode != 0 and 'Requested format is not available' in unavailable.stderr
            assert not list(evidence.glob('unavailable.*')), 'unexpected fallback output'
            results.append({'case': 'unavailable-pin', 'returncode': unavailable.returncode, 'fallback': False})
        finally:
            write_json(root / 'states.json', {})

        # Dedicated new audio check; the old MP3 smoke is unchanged.
        policy = get_policy(mode='audio')
        _, selection = probe_selection(base, 'mixed', policy, 'mp3-selection')
        assert selection['valid']
        argv = call('arguments', policy, pinned_ids=selection['format_ids'])
        final = evidence / 'mp3-final.txt'
        run([runtime / 'yt-dlp.exe', *argv, '--no-cache-dir', '--proxy', '',
             '--ffmpeg-location', runtime, '--print-to-file', 'after_move:filepath', final,
             '-o', evidence / 'audio.%(ext)s', base + '/quality/mixed'], evidence, 'mp3-download', env)
        output = Path(final.read_text(encoding='utf-8').strip())
        actual = json.loads(run([runtime / 'ffprobe.exe', '-v', 'error', '-show_streams',
                                '-show_format', '-of', 'json', output], evidence, 'mp3-probe', env).stdout)
        verdict = call('output', policy, metadata=actual)
        assert verdict['valid'] and not verdict['video'], verdict
        results.append({'case': 'mp3', 'path': str(output), 'sha256': sha256(output), 'output': verdict})
    result = {'tier': 'PRODUCTION_HELPER_AND_ENGINE', 'gui_acceptance': False,
              'helper_sha256': sha256(helper), 'runtime_identity': json.loads((root / 'identity.json').read_text()),
              'results': results, 'passed': len(results)}
    write_json(evidence / 'result.json', result)
    print(json.dumps({'passed': len(results), 'tier': result['tier'], 'gui_acceptance': False,
                      'evidence': str(evidence)}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build = commands.add_parser('prepare')
    build.add_argument('--root', type=Path, required=True)
    source = build.add_mutually_exclusive_group(required=True)
    source.add_argument('--runtime', type=Path)
    source.add_argument('--candidate-zip', type=Path)
    for name in ('check', 'serve'):
        command = commands.add_parser(name)
        command.add_argument('--root', type=Path, required=True)
        if name == 'serve':
            command.add_argument('--port', type=int, default=0)
    integration = commands.add_parser('policy-check')
    integration.add_argument('--root', type=Path, required=True)
    integration.add_argument('--helper', type=Path, required=True)
    integration.add_argument('--implementation-ready', action='store_true')
    args = parser.parse_args()
    {'prepare': prepare, 'check': check, 'serve': serve, 'policy-check': policy_check}[args.command](args)


if __name__ == '__main__':
    main()
