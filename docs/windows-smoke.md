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
`vswhere.exe`, MSBuild, CMake, and the v143 C++ toolset; builds the four
source dependencies for `Release|x64` first, verifies the exact linker inputs
(`bit7z64.lib`, `nana_v143_Release_x64.lib`, `libpng.lib`, and
`turbojpeg-static.lib`), then builds the product. It checks the `2.19.1.0`
product version and Korean catalog; then creates a GUID-named
candidate under a GUID-named directory outside the preserved parent runtime. The candidate receives copies of the
new GUI, parent runtime executables, catalog, and a repaired *copy* of
`ytdlp-interface.json`. `candidate-manifest.json` records SHA-256 values, file
sizes, and executable version output. Before copying, the parent runtime's
`yt-dlp-provenance.json` must identify the official nightly repository/channel,
match the parent executable hash and `--version` tag, and FFmpeg/FFprobe/Deno
must each exit successfully with version output.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build-candidate.ps1 -Run -DependencyArchiveDirectory <src>
```

The script accepts only the reviewed `ytdlp-interface dependencies.7z` through
`-DependencyArchiveDirectory`, whose SHA-256 is pinned in
`tools/dependency-archives.json`. It requires a trusted Program Files 7-Zip,
lists entries before extraction, rejects traversal/absolute/unexpected paths,
and extracts into unique staging before moving only missing dependency roots.
It never installs build tools or fetches dependencies; a missing prerequisite
stops before candidate assembly.

## Localhost MP3 smoke

The smoke script is inert until `-Run`. It creates a two-second sine-wave MP4
with the candidate FFmpeg, serves it through Python's HTTP server bound only to
`127.0.0.1`, and launches the candidate GUI. No external media, cookies,
browser profiles, proxies, or user download archives are used.

For deterministic automation, provide a script block which accepts the URL,
candidate root, output directory, and GUI PID, drives the reviewed GUI
automation, and returns `{ Completed = $true; GuiProcessId = ...; Url = ...;
OutputDirectory = ... }`. A marker not bound to the launched GUI, exact URL,
and unique workspace output is rejected. For a supervised smoke, use
`-OperatorGuided`, observe the GUI, and type `YES` after the MP3 flow. Both
paths require a newly-created contained final `.mp3`, no `.part` files,
`ffprobe` codec `mp3`, and positive duration. The server is polled at its exact
`127.0.0.1` URL before the GUI starts.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/smoke-localhost.ps1 -Run -CandidateRoot <candidate> -OperatorGuided
```

Each run writes a sanitized result or failure manifest beneath the candidate's
`smoke-evidence` directory: only workspace ID and a stable reason code are
published. Successful temporary workspaces are removed; failed workspaces and
their detailed local server logs remain for inspection. The operator must
separately record Korean startup, dialogs, queue/output, format-category, and
100/150/200 DPI visual gates when automation cannot prove them.
