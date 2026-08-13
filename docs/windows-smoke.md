# Windows candidate build and localhost smoke

These PowerShell 5.1 tools assemble and exercise an isolated candidate. They
never replace files in the preserved parent runtime directory.

## Fixture tests

Run the dependency-free PowerShell fixtures from Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run_powershell_tests.ps1
```

The smoke fixtures use temporary files and fake processes. They cover unique,
contained candidate roots; explicit `127.0.0.1` URLs; process cleanup; nonempty
final MP3 output; MP3 codec and positive duration probe output; `.part`
rejection; retained failure evidence; and success-only workspace cleanup.

## Candidate build

`tools/build-candidate.ps1` is inert until `-Run` is supplied. It locates
`vswhere.exe`, MSBuild, and the v143 C++ toolset; builds `Release|x64`; checks
the `2.19.1.0` product version and Korean catalog; then creates a GUID-named
candidate under `src/candidate-runtime`. The candidate receives copies of the
new GUI, parent runtime executables, catalog, and a repaired *copy* of
`ytdlp-interface.json`. `candidate-manifest.json` records SHA-256 values, file
sizes, and executable version output.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build-candidate.ps1 -Run
```

The script accepts reviewed local `bit7z.zip`, `nana.zip`, `libpng.zip`, and
`libjpeg-turbo-3.1.2.zip` through `-DependencyArchiveDirectory` and extracts
only missing dependency roots beside the solution. It never installs build tools
or fetches dependencies; a missing prerequisite stops before candidate assembly.

## Localhost MP3 smoke

The smoke script is inert until `-Run`. It creates a two-second sine-wave MP4
with the candidate FFmpeg, serves it through Python's HTTP server bound only to
`127.0.0.1`, and launches the candidate GUI. No external media, cookies,
browser profiles, proxies, or user download archives are used.

For deterministic automation, provide a script block which accepts the URL,
candidate root, and output directory and drives the reviewed GUI automation.
For a supervised smoke, use `-OperatorGuided` and complete the displayed MP3
flow manually. Both paths require a contained final `.mp3`, no `.part` files,
`ffprobe` codec `mp3`, and positive duration.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/smoke-localhost.ps1 -Run -CandidateRoot <candidate> -OperatorGuided
```

Each run writes a sanitized result or failure manifest beneath the candidate's
`smoke-evidence` directory. Successful temporary workspaces are removed;
failed workspaces and server logs remain for inspection. The operator must
separately record Korean startup, dialogs, queue/output, format-category, and
100/150/200 DPI visual gates when automation cannot prove them.
