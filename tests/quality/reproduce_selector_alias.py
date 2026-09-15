"""Demonstrate why reserved yt-dlp selectors are not literal format IDs."""
import argparse
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('fixture', Path(__file__).resolve().parents[2] / 'tools/quality-fixture.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, required=True)
parser.add_argument('--helper', type=Path, required=True)
args = parser.parse_args()
root = args.root.resolve()
evidence = root / 'selector-alias-reproduction'
evidence.mkdir()
results = []
with fixture.server(root) as base:
    for alias in ('w', 'wa', 'wv', 'worstvideo', 'worstaudio'):
        request = evidence / (alias + '.request.json')
        fixture.write_json(request, {'operation': 'arguments', 'pinned_ids': alias})
        produced = fixture.run([args.helper, '--request', request], evidence, alias + '-helper')
        argv = json.loads(produced.stdout)
        output = fixture.run([root / 'runtime/yt-dlp.exe', *argv, '--skip-download', '-J',
                              '--no-cache-dir', '--proxy', '', base + '/quality/mixed'],
                             evidence, alias + '-engine', fixture.isolated_env(root))
        actual = json.loads(output.stdout)['format_id']
        assert actual != alias, 'fixture unexpectedly contains reserved alias as literal ID'
        results.append({'supplied_pin': alias, 'actual_selected_id': actual,
                        'helper_accepted_reserved_selector': True})
fixture.write_json(evidence / 'result.json', {'finding': 'RESERVED_SELECTOR_ACCEPTED_AS_PIN',
                                            'results': results})
print(json.dumps(results, indent=2))
