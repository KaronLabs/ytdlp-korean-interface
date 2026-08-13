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
`ytdlp-interface.json`. `candidate-manifest.json` records candidate SHA-256
values, sizes, executable version output, and an attestation block binding the
clean Git revision plus an exact tracked-input tree digest, reviewed dependency
archive hash, actual linker library hashes, MSBuild/CMake/MSVC compiler/linker/
resource-compiler and Windows SDK identities, and normalized build commands,
working directory, effective properties, and relevant architecture environment.
Ignored files and prior build outputs are never copied into the isolated source.
`Directory.Build.*` imports are disabled and `UserRootDir` is redirected to an
empty run-private directory, preventing external user props from changing the
sealed build. The same values, including fixed MSVC toolset and Windows SDK
versions, are injected into CMake's generated Visual Studio projects through
`CMAKE_VS_GLOBALS`, as well as into their subsequent MSBuild invocation.
Dependency library hashes are captured before product linking and
must remain unchanged afterward. Before copying, the parent runtime's
`yt-dlp-provenance.json` must identify the official nightly repository/channel,
match the parent executable hash and `--version` tag, and FFmpeg/FFprobe/Deno
must each exit successfully with version output.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/build-candidate.ps1 -Run -DependencyArchiveDirectory <src>
```

The script requires the reviewed `ytdlp-interface dependencies.7z` through
`-DependencyArchiveDirectory`, whose SHA-256 is pinned in
`tools/dependency-archives.json`. It requires a trusted Program Files 7-Zip,
verifies its hash and lists entries even when dependency roots already exist,
rejects traversal/absolute/unexpected paths, and extracts into unique staging
only when a dependency root is missing.
It never installs build tools or fetches dependencies; a missing prerequisite
stops before candidate assembly.

The candidate manifest uses schema version 1. After it is written, the shared
producer/consumer seal validator requires every attestation field and verifies
that its file inventory is the exact candidate payload set: missing, changed,
duplicate, traversing, or extra unmanifested files invalidate the candidate.
Linker inputs, toolchain identities, and configure/build/product command steps
are likewise exact unique sets; missing, duplicate, or extra entries invalidate
the attestation. Command names alone are insufficient: each step must use the
expected MSBuild/CMake executable and required Release/x64 solution,
configure, build, generator, architecture, toolset, and target arguments. The
libjpeg-turbo configure step must contain exactly one `CMAKE_VS_GLOBALS` value
binding every hermetic Visual Studio global described above. Validation uses
the canonical normalized argv for every step: exactly one expected
solution/project or source/build directory, the fixed switch/property set, and
no additional solution, project, directory, or unknown argument.
The localhost smoke applies the same validator before copying any payload file.

## Localhost MP3 smoke

The smoke script is inert until `-Run`. It creates a two-second tone-and-color MP4
with the candidate FFmpeg, serves it through Python's HTTP server bound only to
`127.0.0.1`, and launches the candidate GUI. No external media, cookies,
browser profiles, proxies, or user download archives are used.

Each run creates a unique root beneath the current user's Downloads Known
Folder, snapshots `candidate-manifest.json`, verifies its caller-pinned SHA-256,
rejects malformed metadata and duplicate paths, and copies only verified files
into an execution copy. It writes the output directory into that execution
copy's settings before the GUI starts. Because that settings override makes the
execution tree a derivative rather than the sealed base tree, evidence records a
`settings-overlay` attestation binding both the base manifest SHA-256 and the
executed settings SHA-256. The sealed candidate tree remains unchanged. For
deterministic automation, provide a script block
which accepts the URL, candidate root, output directory, and GUI PID, and
returns `{ Completed = $true; GuiProcessId = ...; Url = ...; OutputDirectory =
... }`. A marker not bound to the launched GUI, exact URL, and unique output is
rejected, but it is recorded as `artifact-only`: an arbitrary PowerShell marker
does not prove GUI interaction. For a supervised GUI smoke, use
`-OperatorGuided`, observe the GUI, and type `YES` after the MP3 flow. Both
paths require a newly-created contained final `.mp3`, no `.part` files,
`ffprobe` codec `mp3`, and positive duration. The server is polled at its exact
`127.0.0.1` URL before the GUI starts.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/smoke-localhost.ps1 -Run -CandidateRoot <candidate> -ParentRuntime <preserved-runtime> -ExpectedCandidateManifestSha256 <reviewed-sha256> -OperatorGuided
```

`-ExpectedCandidateManifestSha256` is required for a run; the smoke refuses to
self-authorize the candidate by calculating its own expected digest.

Each run creates exactly one sanitized append-only manifest beneath
`Downloads\ytdlp-interface-smoke-evidence\runs\<run-id>.json`, outside the
sealed candidate. It records the mode, stable result code, cleanup outcome,
candidate-manifest SHA-256, derivative execution attestation, and separate
`artifactValidated`, `guiInteractionProven`, and `operatorAttested` proof
claims. `artifact-only` can never claim GUI interaction or operator proof. An
operator-guided confirmation records operator attestation but still does not
claim machine-proven GUI interaction.

After the GUI and server have stopped, and before successful workspace
deletion, the run copies the final MP3 bytes, executed settings bytes, and raw
FFprobe output into
`Downloads\ytdlp-interface-smoke-evidence\artifacts\<run-id>`. The manifest records
their evidence-relative paths and binds the MP3 relative path, SHA-256, length,
duration, executed settings SHA-256, exact FFprobe-output SHA-256, and absence
of `.part` files. The retained copies are hash-verified before the manifest is
written. It does not publish absolute paths or the URL. Successful temporary
workspaces are removed only after evidence is persisted; failed workspaces and
their detailed local server logs remain for inspection. Cleanup failure is
terminal `process_cleanup_timeout`, records
`cleanupSucceeded=false`, retains the workspace, and is surfaced even when the
smoke had already failed. The operator must
separately record Korean startup, dialogs, queue/output, format-category, and
100/150/200 DPI visual gates when automation cannot prove them.
