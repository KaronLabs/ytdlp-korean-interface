# Independent quality acceptance

These tests call the real `download_policy.hpp`. The Python fixture does not
reimplement application policy. A successful fixture command is not GUI acceptance.

## Baseline / fixture preparation

```powershell
python -m unittest discover -s tests/quality -p 'test_*.py' -v
python tools/quality-fixture.py prepare --root E:/quality-fixture --runtime E:/isolated-parent
python tools/quality-fixture.py check --root E:/quality-fixture
```

Use a NEW fixture root. Only yt-dlp, FFmpeg and ffprobe are copied from a runtime
directory. No source config is read or changed. Media consists of real 1-second,
4-fps test patterns and 48-kHz sine audio. Files include H.264 360/720/1080/2160,
1080x1920 portrait, VP9 1080, AV1 1080, AAC audio and muxed H.264/AAC 360.

Engine checks prove seven actual output shapes and two config-discovery cases.
The above-cap engine check deliberately expects 2160: resolution sorting is a
preference, and only production inspection can impose the hard short-edge cap.

## Real production helper + engine

Run only after the controller authorizes production validation:

```powershell
./tools/test-quality-policy.ps1 -EvidenceRoot E:/quality-helper-run -ImplementationReady
python tools/quality-fixture.py policy-check --root E:/quality-fixture --helper E:/quality-helper-run/bin/quality_policy_tests.exe --implementation-ready
```

The native executable runs behavioral assertions and exposes a JSON bridge to
the same compiled production functions. The engine runner obtains arguments
from that bridge, probes twice, compares selection using `same_selection`, pins
the newly resolved IDs, downloads real media, and checks real ffprobe JSON with
`inspect_output`. Output dimensions/codecs/audio are also checked independently.

Covered: fresh policy defaults; policy serialization/invalid legacy policy;
1080/720/best; portrait; missing dimensions/audio/video; requested-download
nesting; multi-video/playlist/live boundary; injection-safe literal format IDs;
changed preview characteristics; actual missing pinned ID without fallback;
external portable `-f best -x` config; VP9/AV1; MP3 and cover-art handling;
malformed probe data and above-cap final streams.

Not established by the helper tests: settings-file migration, GUI option
assembly/custom-argument suppression, per-item queue persistence/active snapshot,
URL generation rejection, FFmpeg executable validation in GUI, final stage
transitions, file preservation on verification failure, locale/DPI layout.

## Exact candidate ZIP / real GUI handoff

```powershell
python tools/quality-fixture.py prepare --root E:/quality-exact-zip --candidate-zip E:/candidate.zip
python tools/quality-fixture.py serve --root E:/quality-exact-zip
```

Preparation records ZIP SHA256 and every candidate file hash before adding the
loopback extractor fixture. It copies the entire candidate to `runtime`; the
ZIP is not changed. Executable bytes are unmodified. The fixture plugin is the
only engine instrumentation and is automatically discovered beside yt-dlp.
The running server writes concrete URLs and its PID to `server.json`.

Before opening the copied GUI, use the candidate's supported settings schema to
point tool paths and outputs exclusively inside this fixture. Do not launch a
candidate carrying legacy absolute original-runtime paths. Controller/A must
provide the confirmed config keys. Fresh/legacy settings are separate runs.

Actual GUI acceptance requires selecting a preset and entering the printed
`mixed` URL in the real application, observing preview, then activating its real
download control. Retain screenshots or operator attestation, actual GUI PID,
child yt-dlp invocation, HTTP requests, final file path and ffprobe results.
Starting a GUI process followed by a test-script CLI download is insufficient.

The server supports all cases listed in `server.json`. For change/disappearance,
after the first GUI preview and before Download, update this fixture's
`states.json` to `{"changed":"changed","unavailable":"missing"}`.
Restore `{}` before another independent case. This removes the old format ID and
changes resolution through the same URL. A playlist has two distinct entry URLs.

Automated GUI limitation as of initial preparation: controller's Windows capture
failed with `0x80004002`; accessibility exposed titlebar only. This validation
session exposes no Windows node_repl API. Browser-only cua_repl cannot operate a
native Nana application. Supported remaining route is operator-guided real GUI
input with separately labeled attestation, or repaired native Computer Use.
Neither has been executed by this test package yet.

## Evidence

Every subprocess has a `*.command.json` containing exact argv, cwd, timestamp,
return code, stdout and stderr. `identity.json` binds executable hashes/versions;
`media-manifest.json` binds actual fixture bytes/probes. Helper builds record
header SHA before/after and executable SHA. Each production engine run writes to
a new timestamped directory. `result.json` and engine results explicitly set
`gui_acceptance: false`. Failed runs retain all diagnostics and media.

Existing `smoke-localhost.ps1`, release factory and build scripts are unchanged.
