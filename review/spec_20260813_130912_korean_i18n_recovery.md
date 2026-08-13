# 제7갱도 코드대법원 검증 명세서 — Korean i18n source recovery

## meta

- created_at: 2026-08-13T13:09:12Z
- review_target: commit `b28e0bc43e70e27cc5d50b89b08aa23b259cf26b` on branch `codex/korean-i18n-recovery`, plus the separately preserved parent runtime at `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface`
- comparison_base: official upstream v2.19.1 source commit `2173316ebb5e50af49a2a4e939693fa8c3a3459c`
- feedback_source: user instructions in the current task; independent subagent reviews for Tasks 1–7; actual MSVC/PowerShell/runtime failures observed during implementation
- scope: 19 commits from comparison base through `b28e0bc`; source recovery, i18n migration, state persistence, runtime maintenance, candidate build, and smoke-test tooling
- changed_files_or_diff: `git diff --name-status 2173316ebb5e50af49a2a4e939693fa8c3a3459c..b28e0bc43e70e27cc5d50b89b08aa23b259cf26b`; 23 added files and 31 modified files
- reviewer_access_assumption: reviewer has read access to this repository, its Git history, the parent runtime directory, and the candidate directory listed below; reviewer does not have access to prior chat state unless this spec and cited runtime paths are supplied
- evidence_package:
  - spec_file_path: `review/spec_20260813_130912_korean_i18n_recovery.md`
  - spec_file_content_available: true
  - changed_files_or_diff: available from Git comparison above; exact file inventory is included in this document
  - test_commands: included under `tests` and `evidence_quotes`
  - test_outputs: included as timestamped excerpts; full reruns are possible from the repository
  - evidence_timestamps: 2026-08-13T12:51:47Z through 2026-08-13T13:09:01Z for final candidate and final reruns; earlier implementation commits contain their author timestamps
  - relevant_runtime_outputs: candidate manifest, candidate executable, MP3 pipeline output, parent `yt-dlp-provenance.json`, repaired settings, and backup files
  - known_missing_items: GUI-internal URL entry/info lookup/download click was not completed; GitHub push was not completed; full-base `git diff --check` reports CRLF-added lines as trailing whitespace

## summary

The official v2.19.1 C++ source was recovered into a separate Git repository and the Korean binary behavior was reimplemented at source level. The implementation adds a validated `i18n.hpp/.cpp` localization core, a 524-entry `ko-KR.json` catalog with English fallbacks at every call site, persisted language and queue-state tokens independent of visible captions, transactional runtime maintenance, reproducible Windows dependency/product builds, and isolated localhost smoke tooling. The parent runtime settings were repaired to the current user's Downloads directory and its `yt-dlp.exe` was replaced with a hash- and version-verified official nightly while preserving backups.

The final Windows Release x64 candidate built successfully and its direct localhost download-to-MP3 path was verified. The candidate GUI process was launched and remained alive, but GUI controls were not driven because Computer Use rejected the WSL workspace URI before input. No GUI success was asserted. The branch was committed locally but was not pushed because Git credentials were unavailable to WSL Git and Windows Git waited on an authentication UI.

## rationale

- Source-level localization replaces one-off EXE patching with reviewable and rebuildable code.
- English fallbacks remain in source so missing, invalid, or unavailable catalogs preserve upstream-observable text instead of blanking the UI.
- Stable enums/tokens and menu/list indices replace logic that previously inferred state from displayed captions; this prevents Korean text from changing control flow.
- Runtime maintenance verifies official nightly provenance, SHA-256, and reported version before transactional replacement; backups and rollback protect the existing portable installation.
- Candidate builds occur outside the parent runtime and verify inputs, dependency archive hash and safe entries, required toolchain, resulting product version, and candidate file hashes.
- The dependency archive contains source, not prebuilt libraries; therefore bit7z, Nana, libpng, and libjpeg-turbo are built as v143 Release x64 before the product link.
- ATL was removed because one `CComPtr<ITaskbarList3>` forced an otherwise unnecessary ATL installation. Equivalent Win32 COM construction and explicit `Release()` retain taskbar behavior.

## threat_model

### trust_boundary

This change touches network, file I/O, process execution, deserialization, environment/tool discovery, and local runtime replacement boundaries.

### trusted

- Git object `2173316ebb5e50af49a2a4e939693fa8c3a3459c` as the official v2.19.1 comparison base.
- Source-controlled `tools/dependency-archives.json` and its expected SHA-256 for the reviewed dependency archive.
- Parent `yt-dlp-provenance.json` only after repository/channel/tag fields, binary SHA-256, and `yt-dlp --version` all agree.
- Visual Studio installation returned by `vswhere` only when the v143 x86/x64 tool component and MSBuild/toolset paths exist.
- Candidate-local executables only after file existence, version execution, and manifest hashing.
- Catalog JSON only after schema, locale, string type, key validity, markup, and fallback constraints pass.

### untrusted

- Network downloads and GitHub release metadata before repository/channel/hash/version verification.
- Dependency archive entries before expected-root, absolute-path, and traversal checks.
- Existing settings paths that reference another user's profile or stale portable locations.
- Human-visible translated captions as program state.
- Arbitrary public PowerShell fixture seams; internal transaction helpers are module-private.
- Windows `python.exe` application aliases until an actual `--version` process succeeds.
- Child process success until the direct process handle exits and its exit code is read.

### boundary_change

- Added a JSON localization file boundary with validation and an English fallback boundary.
- Added an official-nightly provenance/hash/version boundary around `yt-dlp.exe` replacement.
- Added archive hash and safe-entry boundaries before dependency extraction.
- Added isolated candidate and smoke workspaces that may not overlap the preserved parent runtime.
- Removed the ATL runtime/build dependency boundary for taskbar COM and replaced it with direct Win32 COM lifetime management.
- Did not expand authentication or secret access; Git push authentication remained outside automated control.

### blocked_scenarios

- Invalid localization keys, malformed named markup, duplicate/missing catalog entries, and empty English fallbacks.
- Korean captions changing queue state, startup behavior, menu identity, or async item matching.
- Stale paths writing downloads into a former user's profile.
- Unverified or mismatched `yt-dlp.exe` replacing the preserved runtime.
- Archive traversal, unexpected dependency roots, parent/candidate overlap, stale MP3 false positives, and automation markers unrelated to the actual GUI PID/URL/output.
- MSBuild success being inferred from shell-global `$LASTEXITCODE`; direct child exit codes are used.
- Cleanup failures suppressing sanitized smoke failure evidence.

### new_scenarios

- A catalog can now be altered independently of the executable; validation mitigates but does not cryptographically sign it.
- Candidate builds execute four third-party source builds and CMake/MSBuild from reviewed local inputs; compromised local toolchains remain out of scope.
- Direct raw COM lifetime management is more explicit but depends on every future ownership path preserving `Release()` and null reset.
- Runtime maintenance changes local executable files when explicitly invoked with its action switch; backup storage consumes additional disk space.

## before_after

| Area | Before | After |
|---|---|---|
| Source ownership | Current Korean behavior existed only in a preserved EXE; maintainable Korean source was unavailable | Official v2.19.1 source exists in Git with source-level Korean behavior |
| Localization | English literals compiled directly into controls | `i18n::tr(key, English fallback)` plus validated `locales/ko-KR.json` |
| Missing catalog | No catalog model | English fallback remains visible; unsupported language normalizes to `en-US` |
| Control state | Several queue/menu branches depended on visible captions or overloaded positions | Stable enum tokens, category/item pairs, explicit menu positions, and persisted sidecars/settings |
| Settings path | Stale output path could reference a former user | Only stale paths repaired to `C:\Users\ceo\Downloads`; unrelated fresh presets preserved |
| yt-dlp | Older preserved executable without the new transaction proof | Official nightly `2026.08.04.234419`, verified by provenance, hash, and version; original backed up |
| Windows build | Product build assumed four prebuilt `.lib` files and ATL | Reviewed dependency sources build as v143 Release x64; product uses direct Win32 COM |
| Smoke evidence | Could pass on stale MP3 or lose evidence during cleanup error | Fresh owned workspace, PID/URL/output marker, stable failure codes, sanitized evidence, bounded cleanup wait |
| Distribution | Local source state only | Local branch and commits exist; remote push remains incomplete |

## diffs

Comparison command:

`git diff --name-status 2173316ebb5e50af49a2a4e939693fa8c3a3459c..b28e0bc43e70e27cc5d50b89b08aa23b259cf26b`

Functional diff groups:

- Localization core/catalog/tests: new `i18n.*`, `locales/ko-KR.json`, contract/native tests, and project integration.
- UI migration: form, GUI, queue, outbox, log, widgets, resource, and types call sites converted to key/fallback lookup.
- Stable state: new `settings_json.hpp` and `state_tokens.hpp`; queue state, scheduled-live, playlist identity, and language persistence.
- Runtime safety: new `runtime-maintenance.psm1/.ps1`, provenance/path repair tests, documentation.
- Reproducible build/smoke: new candidate build, dependency manifest, localhost smoke scripts/tests/docs.
- Final compiler fixes: explicit `::widgets`, Nana combox reference API, Title string API, raw taskbar COM, v143 dependency builds, direct-child process waiting, and Python runtime verification.

## files

### added

- `.gitignore` — generated dependency/build/candidate/evidence artifacts excluded; impact medium.
- `docs/runtime-maintenance.md` — safe runtime repair/update usage; impact low.
- `docs/superpowers/plans/2026-08-13-korean-i18n-recovery.md` — implementation plan; impact low.
- `docs/superpowers/specs/2026-08-13-korean-i18n-recovery-design.md` — approved design; impact low.
- `docs/windows-smoke.md` — candidate and smoke procedure; impact medium.
- `locales/ko-KR.json` — 524 Korean strings; impact high.
- `tests/contract/test_recovery_contract.py` — catalog, migration, state, build, and entrypoint contracts; impact high.
- `tests/fixtures/catalog_valid.json` — valid catalog fixture; impact low.
- `tests/native/i18n_tests.cpp`, `state_token_tests.cpp`, `test_main.cpp`, `i18n_tests.vcxproj` — native localization/state verification; impact high.
- `tests/powershell/runtime-maintenance.Tests.ps1`, `smoke-localhost.Tests.ps1` — Windows safety/build/smoke fixtures; impact high.
- `tests/run_contract_tests.py`, `tests/run_powershell_tests.ps1` — deterministic test runners; impact medium.
- `tools/build-candidate.ps1` — verified dependency/product build and isolated candidate assembly; impact high.
- `tools/dependency-archives.json` — reviewed archive name/hash/root policy; impact high.
- `tools/runtime-maintenance.ps1`, `runtime-maintenance.psm1` — transactional settings/yt-dlp maintenance; impact high.
- `tools/smoke-localhost.ps1` — localhost GUI/product smoke harness and evidence handling; impact high.
- `ytdlp-interface/i18n.cpp`, `i18n.hpp` — validated runtime localization implementation/API; impact high.
- `ytdlp-interface/settings_json.hpp`, `state_tokens.hpp` — language and stable queue state serialization; impact high.

### modified

- `ytdlp-interface/forms/form_changes.cpp`, `form_colors.cpp`, `form_formats.cpp`, `form_input.cpp`, `form_json.cpp`, `form_loading.cpp`, `form_playlist.cpp`, `form_sections.cpp`, `form_settings.cpp`, `form_subs.cpp`, `form_suspend.cpp` — localized visible UI; settings adds language selection; compiler ambiguity/API fixes; impact high.
- `ytdlp-interface/gui.cpp`, `gui.hpp`, `gui_bottom.cpp`, `gui_bottoms.cpp`, `gui_make.cpp` — localized main UI, stable behavioral state/menu identity, queue persistence, taskbar COM lifetime; impact high.
- `ytdlp-interface/log.cpp`, `main.cpp`, `msgbox.hpp`, `outbox.cpp`, `queue.cpp` — localized diagnostics/messages/queue actions and shared localized button/accessor use; impact high.
- `ytdlp-interface/types.cpp`, `types.hpp`, `util.cpp`, `widgets.cpp`, `widgets.hpp` — state/settings/localized widget support; impact medium.
- `ytdlp-interface/ytdlp-interface.rc` — Korean file description/version resource; impact medium.
- `ytdlp-interface/ytdlp-interface.sln`, `ytdlp-interface.vcxproj` — i18n/native tests, sources/catalog, UTF-8 compilation, build integration; impact high.

### deleted

- none.

## implementation

- `i18n::load_catalog` parses UTF-8 JSON, validates locale/schema/string entries, and publishes a catalog only after validation. `i18n::tr` returns the catalog value for a known key and the supplied English fallback otherwise. Named placeholders are formatted without interpreting display strings as state.
- Startup normalizes the persisted language to `ko-KR` or `en-US`, preloads the catalog before GUI construction, and persists settings through a separate JSON adapter. Queue item states serialize stable tokens, not localized text.
- Menu and list identity use explicit Nana indices and `index_pair` category/item identity. Scheduled-live and playlist metadata are serialized so a restart does not re-enable actions based on a translated title.
- Runtime repair changes only stale path values; fresh unrelated presets remain unchanged. `UpdateYtDlp` obtains official nightly metadata, verifies asset SHA-256 and version, uses `ShouldProcess`, replaces transactionally, writes provenance, and rolls back on failure. Test-only injection remains inside a non-exported module function.
- Candidate build verifies parent provenance/runtime versions, archive SHA-256 and entries, extracts only expected roots, locates v143/MSBuild/CMake, builds four Release x64 libraries, builds the product, checks `2.19.1.0`, copies required runtime/catalog/settings files into an isolated candidate, and writes hashes/versions to a manifest.
- Process invocation quotes Windows arguments, captures stdout/stderr to temporary files, binds the direct child handle, waits for the direct child (not long-lived compiler descendants), refreshes the process object, and rejects nonzero exit codes.
- Smoke tooling creates a fresh candidate-owned workspace, generates a two-second synthetic media file, binds a server to `127.0.0.1`, launches the candidate GUI, requires either an exact automation marker or operator confirmation, validates fresh MP3/codec/duration/no `.part`, bounds cleanup waits, and always writes sanitized evidence even if cleanup fails.
- Taskbar progress uses `ITaskbarList3*`; `CoCreateInstance(... IID_PPV_ARGS(&i_taskbar))` establishes ownership, and all destruction/failed initialization paths call `Release()` and null the pointer.

## impact

- API: internal C++ localization/settings/state APIs added; no public network API.
- UI: Korean catalog covers 524 visible messages/labels; English fallback remains; Interface settings adds English/Korean selection and restart notice.
- DB / 스키마: none.
- 설정 / 환경변수: settings gains normalized `language` and stable queue-state data; build uses installed Program Files tools and an optional explicit Python path; no secret environment variables.
- 배포 / 인프라: isolated candidate assembly and manifest added; parent runtime is not overwritten by candidate build.
- 성능: startup performs one catalog parse; translation lookup is average O(1). Dependency builds add first-build time but are incremental thereafter.
- 보안: archive traversal/hash checks, binary provenance/version/hash verification, path containment, transactional replacement, and module-private test seams added. No authentication automation added.
- 의존성: official v2.19.1 dependencies remain bit7z, Nana, libpng, libjpeg-turbo, nlohmann/json; build requires VS Build Tools v143, CMake, and trusted Program Files 7-Zip.
- 라이선스 / third-party: no third-party source licenses changed; existing dependency sources are built locally. License compatibility was not independently re-audited.
- 접근성 (a11y): no deliberate accessibility API changes; Korean labels may improve readability but full screen-reader testing was not run.
- 국제화 (i18n): high impact; Korean external catalog plus English source fallback; only `ko-KR` and `en-US` are supported.
- 데이터 보존 / 삭제 (GDPR 등): local settings/executable backups are retained; candidate/smoke temporary data is local. No personal data is transmitted by the localhost smoke.
- 컴플라이언스 (도메인별): none identified; downloader use remains subject to user/site/legal obligations outside this code change.
- 로깅 / 모니터링: smoke success/failure evidence and candidate manifest added; evidence excludes full paths except workspace identifier and manifest paths inside candidate.
- 회귀 위험: medium because 31 existing product source files changed and GUI click smoke is incomplete; mitigated by 524-key parity, state contracts, native tests, actual Release build, and direct pipeline smoke.
- 하위호환성: legacy queue text is mapped to stable tokens; unsupported/missing language falls back to English; existing settings without language remain usable.

## tests

### automated

- `RECOVERED_CATALOG=locales/ko-KR.json python3 tests/run_contract_tests.py` — run at 2026-08-13T13:08:18Z; 20 tests passed.
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run_powershell_tests.ps1` — run at 2026-08-13T13:09:01Z; runtime-maintenance and smoke-localhost suites passed.
- `ytdlp-interface/x64/Release/i18n_tests.exe` — run at 2026-08-13T13:08:39Z; exit code 0.
- `tools/build-candidate.ps1 -Run ...` — run during implementation; Windows Release x64 dependency and product build returned exit 0 and produced candidate manifest at 2026-08-13T12:51:47.3133181Z.
- Candidate direct pipeline: localhost yt-dlp extraction to MP3 followed by candidate ffprobe; output `codec_name=mp3`, `duration=2.020136`, no `.part`; rechecked 2026-08-13T13:08:37Z.
- `git diff --check 2173316e..HEAD` — run 2026-08-13T13:08:12Z; nonzero because CRLF lines in added `locales/ko-KR.json` are reported as trailing whitespace. This is not reported as passed.

### manual

- Candidate GUI launch: smoke harness launched `ytdlp-interface.exe`, waited one second, refreshed the process, and did not report `gui_start_failed`; operator prompt was reached with URL `http://127.0.0.1:51273/input.mp4`.
- GUI control interaction: not completed. Computer Use initialization failed before any input because its Node bridge rejected `file:///mnt/c/...` as a local file URI. The operator path was explicitly answered `NO`, producing `operator_not_confirmed`; no false success marker exists.
- Parent runtime repair/update: executed earlier in the task. Existing settings and yt-dlp were backed up; current output path and nightly provenance/hash/version were inspected. Exact backup filenames and hashes are available in the parent directory and prior task reports, but a fresh mutation was not repeated for this spec.
- GitHub push: not completed. WSL Git returned `fatal: could not read Username for 'https://github.com': No such device or address`; Windows Git was interrupted after waiting on authentication UI.

### repro

- Full candidate build: follow `docs/windows-smoke.md`, using the reviewed dependency archive directory. Expected result is a new `candidate-*` directory and `candidate-manifest.json`.
- Contract repro: run `RECOVERED_CATALOG=locales/ko-KR.json python3 tests/run_contract_tests.py` from repository root.
- Windows fixture repro: run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run_powershell_tests.ps1` from repository root.
- Remaining GUI repro: run `tools/smoke-localhost.ps1 -Run -OperatorGuided` with the candidate, preserved parent, and a verified Python executable; enter the supplied localhost URL in the candidate GUI, request info, select MP3 conversion, download, then type `YES` only after observing completion.

## evidence_quotes

### E1 — contract suite

- command: `RECOVERED_CATALOG=locales/ko-KR.json python3 tests/run_contract_tests.py`
- output: excerpt (suite tail):
  ```text
  test_task_7_settings_uses_title_and_combox_value_apis ... ok
  test_windows_process_runner_waits_for_direct_child_not_process_tree ... ok
  Ran 20 tests in 6.176s
  OK
  ```
- timestamp: 2026-08-13T13:08:18Z
- evidence_type: automated

### E2 — Windows PowerShell fixtures

- command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run_powershell_tests.ps1`
- output: excerpt:
  ```text
  START runtime-maintenance.Tests.ps1
  runtime-maintenance tests passed
  PASS runtime-maintenance.Tests.ps1
  START smoke-localhost.Tests.ps1
  smoke-localhost fixture tests passed.
  PASS smoke-localhost.Tests.ps1
  ```
- timestamp: 2026-08-13T13:09:01Z
- evidence_type: automated

### E3 — native i18n/state executable

- command: `ytdlp-interface/x64/Release/i18n_tests.exe; echo exit_code=$?`
- output:
  ```text
  exit_code=0
  2026-08-13T13:08:39Z
  ```
- timestamp: 2026-08-13T13:08:39Z
- evidence_type: automated

### E4 — Release candidate manifest

- command: parse `candidate-c7f414cb5f664df4abbdca0e94979594/candidate-manifest.json`
- output: excerpt:
  ```text
  createdAtUtc: 2026-08-13T12:51:47.3133181Z
  product version: 2.19.1.0
  yt-dlp version: 2026.08.04.234419
  ytdlp-interface.exe sha256: F58562956A36B601AD9DBAF22D3B65E5797006F6FFF70A0897A94B1776162B25
  locales\ko-KR.json sha256: 8EE947DBF4713CF2CDD06081C3EE2AC4A24FFCB3FA261A626E7AEB2F505674FA
  ```
- timestamp: manifest 2026-08-13T12:51:47.3133181Z; inspected 2026-08-13T13:08:12Z
- evidence_type: runtime

### E5 — direct localhost download and MP3 postprocessing

- command: candidate `yt-dlp.exe --ffmpeg-location <candidate> -x --audio-format mp3 ... http://127.0.0.1:51275/input.mp4`, then candidate `ffprobe.exe -show_entries stream=codec_name -show_entries format=duration ... output.mp3`
- output: excerpt:
  ```text
  [generic] Extracting URL: http://127.0.0.1:51275/input.mp4
  [download] 100% of 18.35KiB
  [ExtractAudio] Destination: ...\pipeline-smoke\output.mp3
  codec_name=mp3
  duration=2.020136
  exit_code=0
  ```
- timestamp: pipeline execution 2026-08-13T12:57:13Z; ffprobe recheck 2026-08-13T13:08:37Z
- evidence_type: runtime

### E6 — GUI smoke incomplete evidence

- command: `powershell.exe ... tools/smoke-localhost.ps1 -Run -OperatorGuided -PythonPath <verified-python> -CandidateRoot <candidate> -ParentRuntime <parent>`
- output: excerpt:
  ```text
  Observe the candidate GUI and complete MP3 download for http://127.0.0.1:51273/input.mp4.
  Type YES after verifying completion: NO
  operator_not_confirmed
  FullyQualifiedErrorId : operator_not_confirmed
  ```
- timestamp: 2026-08-13T12:55Z (minute precision from execution sequence; exact second unavailable)
- evidence_type: manual

### E7 — full comparison whitespace check failure

- command: `git diff --check 2173316ebb5e50af49a2a4e939693fa8c3a3459c..HEAD`
- output: excerpt:
  ```text
  locales/ko-KR.json:1: trailing whitespace.
  locales/ko-KR.json:2: trailing whitespace.
  locales/ko-KR.json:537: trailing whitespace.
  locales/ko-KR.json:538: trailing whitespace.
  ```
- timestamp: 2026-08-13T13:08:12Z
- evidence_type: automated

### E8 — Git push failure

- command: `git push -u origin codex/korean-i18n-recovery`
- output:
  ```text
  fatal: could not read Username for 'https://github.com': No such device or address
  ```
- timestamp: 2026-08-13T13:02Z (minute precision from execution sequence; exact second unavailable)
- evidence_type: runtime

## risks

- description: GUI-internal URL entry, information lookup, MP3 option selection, and download click were not completed in this session. Candidate startup and the downstream localhost/yt-dlp/FFmpeg path were verified separately, but their GUI integration remains unproven.
  - severity: high
  - handling: plan — run the operator-guided smoke from a different session/model with functioning Computer Use, and require `success.json`, fresh MP3, ffprobe MP3/duration, and no `.part` before approval.
- description: The completed branch has not been pushed to GitHub; loss of the local repository would lose the new commits.
  - severity: medium
  - handling: safeguard — local Git objects and working tree are intact; authenticate Git Credential Manager or CLI and push `codex/korean-i18n-recovery` without force.
- description: Full-base `git diff --check` is nonzero because added CRLF catalog lines are classified as trailing whitespace. Prior working-tree-only checks were green because there was no unstaged diff; they do not prove the complete branch diff is whitespace-clean.
  - severity: low
  - handling: accepted_unresolved — JSON parses and all 524 contract checks pass. A future separate commit may normalize catalog line endings after reviewer agreement; this spec does not modify committed source.
- description: No independent license/third-party provenance audit was performed for the dependency source archive beyond its reviewed manifest SHA-256 and expected roots.
  - severity: medium
  - handling: plan — reviewer should compare dependency versions/licenses to official sources before redistributing binaries.
- description: Parent runtime backups and candidate artifacts are intentionally outside Git and may be cleaned by external temp/storage policies.
  - severity: medium
  - handling: safeguard — candidate manifest contains hashes; preserve candidate and parent backups in an off-host package if long-term retention is required.
- description: This saved spec alone is not a sufficient review package if the verifier cannot access the repository diff, runtime candidate, and quoted test outputs.
  - severity: high
  - handling: safeguard — transmit this file's full content together with the Git comparison, test output excerpts, candidate manifest, and relevant runtime paths.

## request

The different-session/model reviewer shall:

1. Review every change in `2173316e..b28e0bc`, prioritizing i18n fallback correctness, caption-independent control flow, serialization compatibility, PowerShell trust boundaries, raw COM ownership, and candidate containment.
2. Re-run the 20 contract tests, Windows PowerShell suites, native Release tests, and a fresh Release x64 candidate build.
3. Complete the missing GUI smoke from URL entry through information lookup, MP3 download, FFmpeg postprocessing, and evidence verification.
4. Inspect dependency licenses/provenance if the candidate will be redistributed.
5. Return APPROVED only if the GUI smoke is green and no high/critical code finding remains; otherwise return concrete file/line findings and preserve failure evidence.

## brief

- 잘된 점: official v2.19.1에서 재현 가능한 source-level i18n, stable state, verified runtime maintenance, and actual Release candidate/data pipeline were established with TDD and independent reviews.
- 애매한 점: GUI process startup is proven, but GUI control integration is not; direct pipeline success must not be substituted for GUI smoke success.
- 어려웠던 점: WSL/Windows bridge instability, missing ATL, MSVC-only compile errors, source-only dependency archive, `mspdbsrv` process-tree waiting, Python app alias, and Computer Use URI rejection required separate evidence-driven fixes or explicit unresolved reporting.

## status

partial_success
