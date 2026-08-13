# Korean i18n Recovery Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

Goal: Recover the observed Korean localization as tested C++ source, repair runtime security and download paths transactionally, and prove the candidate with deterministic and Windows localhost smoke tests.

Architecture: Add a GUI-independent i18n component with compiled English call-site fallbacks and a validated external Korean catalog. Separate internal control tokens from visible captions before migrating strings. Keep runtime maintenance and smoke orchestration in bounded PowerShell tools so the preserved deployment is never modified without verification and rollback.

Tech Stack: C++20, nlohmann/json, Nana C++ GUI, Visual Studio/MSBuild v143, Python 3 standard-library contract tests, PowerShell 5.1, yt-dlp nightly, FFmpeg/FFprobe.

## Global Constraints

- Base source is upstream tag v2.19.1 at commit 2173316ebb5e50af49a2a4e939693fa8c3a3459c.
- The parent deployment directory is preserved until all candidate tests pass.
- English is compiled at each i18n::tr(key, english_fallback) call site.
- Only en-US and ko-KR are supported.
- Catalog schema is locale ko-KR, integer schemaVersion 1, and object strings.
- Initial recovery baseline is exactly 524 Korean keys, no empty values, and no unexplained source/catalog drift.
- Translation cannot control queue state, view state, format category, updater state, or any other behavior.
- Every production behavior follows Red-Green-Refactor; configuration-only copies are verified by contract tests.
- yt-dlp remains on the official nightly channel and is replaced only after SHA-256 and version verification with rollback available.
- Download paths resolve through FOLDERID_Downloads; unrelated settings remain unchanged.
- Network smoke uses only a two-second synthetic file served from 127.0.0.1.
- No cookies, browser profiles, proxies, external media services, or user download archives are used by tests.

---

### Task 1: Deterministic Recovery Test Perimeter

Files:
- Create: tests/contract/test_recovery_contract.py
- Create: tests/fixtures/catalog_valid.json
- Create: tests/run_contract_tests.py
- Modify: .gitignore

Interfaces:
- Consumes upstream source and RECOVERED_CATALOG.
- Produces python3 tests/run_contract_tests.py, the zero-dependency deterministic gate.

- [ ] Step 1: Write failing repository-contract tests.

Use unittest cases named test_i18n_source_and_header_exist, test_recovered_catalog_has_524_nonempty_string_entries, test_every_catalog_key_has_a_source_reference, test_every_tr_call_has_a_nonempty_english_fallback, and test_runtime_artifacts_are_ignored. The initial run must fail because the i18n source and repository catalog do not exist.

- [ ] Step 2: Verify RED.

Run RECOVERED_CATALOG=../locales/ko-KR.json python3 tests/run_contract_tests.py. Expect failures on missing i18n source and migration contracts, while the external catalog assertion passes.

- [ ] Step 3: Add only the runner, fixture, and ignore boundaries.

The runner discovers test_*.py below tests/contract. Ignore .superpowers, dependency extraction trees, Visual Studio output, candidate runtime, smoke evidence, backups, and provenance staging without ignoring source or docs.

- [ ] Step 4: Re-run and record exact expected RED failures. Syntax and import errors are not acceptable RED evidence.

- [ ] Step 5: Commit with message test: establish i18n recovery perimeter.

### Task 2: Localization Core Red-Green-Refactor

Files:
- Create: ytdlp-interface/i18n.hpp
- Create: ytdlp-interface/i18n.cpp
- Create: tests/native/i18n_tests.cpp
- Create: tests/native/i18n_tests.vcxproj
- Create: tests/native/test_main.cpp
- Modify: ytdlp-interface/ytdlp-interface.sln
- Modify: ytdlp-interface/ytdlp-interface.vcxproj
- Modify: tests/contract/test_recovery_contract.py

Interfaces produced:
- i18n::load_result with catalog_loaded and diagnostics.
- load_catalog(path), tr(key, english_fallback), active_locale(), and reset_for_tests().

- [ ] Step 1: Write one failing native test per behavior.

Cover valid load; missing file; malformed root/schema/locale/strings; missing key; non-string and empty entries; invalid UTF-8; placeholder multiset equality and mismatch; balanced and malformed Nana markup; diagnostic key/reason; reset removing stale state.

- [ ] Step 2: Verify RED.

When MSBuild exists, build tests/native/i18n_tests.vcxproj Debug x64 and require failure because the API is missing. Without MSBuild, contract tests must fail on the same declarations and native execution is recorded as unavailable.

- [ ] Step 3: Implement minimal parsing and fallback.

Use json.hpp, unordered_map, strict root validation, UTF-8 validation, placeholder multiset comparison, and a stack-based Nana markup validator. Do not depend on GUI classes.

- [ ] Step 4: Verify GREEN with the native executable when available and always with python3 tests/run_contract_tests.py.

- [ ] Step 5: Refactor private validation helpers only while all tests remain green.

- [ ] Step 6: Commit with message feat: add validated localization core.

### Task 3: Startup Integration and Internal Token Separation

Files:
- Modify: ytdlp-interface/types.hpp and types.cpp
- Modify: ytdlp-interface/main.cpp
- Modify: ytdlp-interface/gui.hpp, gui.cpp, and gui_make.cpp
- Modify: ytdlp-interface/outbox.cpp and queue.cpp
- Modify: ytdlp-interface/forms/form_formats.cpp, form_loading.cpp, and form_settings.cpp
- Modify: contract and native tests

Interfaces:
- settings language field accepts en-US or ko-KR.
- Queue completion/error, main view, format category, and updater action never depend on captions.

- [ ] Step 1: Write failing settings and token-independence tests.

Assert default en-US, persisted ko-KR, invalid value fallback, and no behavioral branches on visible done, queue, Audio only, Video only, Update, or Cancel captions.

- [ ] Step 2: Verify RED with python3 tests/run_contract_tests.py.

- [ ] Step 3: Implement minimal startup loading.

Load settings, validate language, load locales/ko-KR.json before GUI construction, and append sanitized diagnostics to localization.log. Catalog failure continues in English.

- [ ] Step 4: Replace caption-driven branches with enums, booleans, or stable internal constants following existing style. Do not redesign queues or downloader arguments.

- [ ] Step 5: Verify GREEN with contract and native suites plus a source search for prohibited caption comparisons.

- [ ] Step 6: Commit with message refactor: separate localized labels from control state.

### Task 4: Recover the 524-Key Korean UI Catalog

Files:
- Create: locales/ko-KR.json
- Modify: main, gui, gui_make, gui_bottom, gui_bottoms, queue, outbox, msgbox, all forms cpp files, resource script, project file, and contract tests.

Interfaces:
- Every recovered key is referenced by i18n::tr with a nonempty English fallback.
- The project copies locales/ko-KR.json beside candidate executables.

- [ ] Step 1: Add failing parity tests.

Parse real tr calls and assert 524 unique keys, no missing/extra keys, nonempty English fallbacks, placeholder multiset equality, and valid Nana markup. Failures list individual keys.

- [ ] Step 2: Verify RED.

- [ ] Step 3: Copy the parent catalog and change the lone English none in Korean format-sorting help to 없음 while preserving all keys and placeholders.

- [ ] Step 4: Migrate visible strings in bounded groups: startup/errors; main/queue/output; dialogs; settings/updater; message-box controls. Run contract tests after each group.

- [ ] Step 5: Configure the Visual Studio project to copy the catalog to the output locales directory.

- [ ] Step 6: Verify catalog=524, source=524, missing=0, extra=0, empty=0, placeholder mismatches=0, markup failures=0.

- [ ] Step 7: Commit with message feat: recover complete Korean interface catalog.

### Task 5: Transactional Settings Repair and Verified yt-dlp Update

Files:
- Create: tools/runtime-maintenance.ps1
- Create: tests/powershell/runtime-maintenance.Tests.ps1
- Create: tests/run_powershell_tests.ps1
- Create: docs/runtime-maintenance.md

Interfaces:
- RepairSettings resolves FOLDERID_Downloads, backs up, rewrites only stale path fields, reparses, and atomically replaces.
- UpdateYtDlp accepts only the official nightly repository, verifies SHA-256 and version, backs up, replaces, verifies, writes provenance, and rolls back.
- WhatIf validates without replacement.

- [ ] Step 1: Write failing PowerShell tests.

Prove unrelated JSON fields and presets survive; only known stale paths change; malformed settings remain untouched; hash/version mismatch blocks replacement; successful replacement writes provenance; simulated post-replacement failure restores backup.

- [ ] Step 2: Verify RED with powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run_powershell_tests.ps1.

- [ ] Step 3: Implement minimal transactional functions using .NET IO, SHA256, the official nightly endpoint, Known Folder lookup, sibling temp files, and sanitized provenance. Reject alternate repositories.

- [ ] Step 4: Verify GREEN and WhatIf safety against copied fixtures. Parent deployment hashes must remain unchanged.

- [ ] Step 5: Apply only after tests pass: record hashes, back up settings/runtime, repair paths, update yt-dlp, verify deployed version/hash/provenance, and retain rollback.

- [ ] Step 6: Commit source tools and docs with message feat: add transactional runtime maintenance. Never commit runtime binaries or user settings.

### Task 6: Release Build, Candidate Assembly, and Windows Smoke

Files:
- Create: tools/build-candidate.ps1
- Create: tools/smoke-localhost.ps1
- Create: tests/powershell/smoke-localhost.Tests.ps1
- Create: docs/windows-smoke.md

Interfaces:
- build-candidate builds Release x64 and assembles a unique candidate directory.
- smoke-localhost generates two-second media, serves only 127.0.0.1, validates the GUI/MP3 flow, and emits a result manifest.

- [ ] Step 1: Write failing smoke-orchestrator tests.

Cover path containment, unique roots, localhost-only URLs, process cleanup, final MP3 checks, part-file rejection, failure evidence retention, and success-only cleanup with fake process outputs.

- [ ] Step 2: Verify RED.

- [ ] Step 3: Extract official dependencies beside the solution. Locate Build Tools with vswhere; if absent, install the Microsoft C++ workload from an approved source and verify MSBuild plus v143.

- [ ] Step 4: Build ytdlp-interface.sln Release x64 and require exit zero, product version 2.19.1.0, and the copied catalog.

- [ ] Step 5: Assemble a candidate with the new GUI, verified yt-dlp, FFmpeg, FFprobe, Deno, 7z DLL, catalog, and repaired settings copy. Verify hashes and versions before launch.

- [ ] Step 6: Run GUI smoke for Korean startup, principal dialogs, queue/output switching, format categories, and DPI 100/150/200 when supported. Record exact unexecuted visual gates otherwise.

- [ ] Step 7: Run localhost end-to-end smoke. Require contained final path, nonempty mp3, FFprobe codec mp3, positive duration, and no part file.

- [ ] Step 8: Run all contract, native, PowerShell, build, and smoke gates. Preserve sanitized failed evidence outside Git.

- [ ] Step 9: Commit tooling with message test: add Windows candidate and localhost smoke.

## Final Verification

Run contract tests, PowerShell tests, Release x64 rebuild, and localhost smoke. Then run git diff --check against upstream v2.19.1, inspect status and commit history, and provide the final reviewer with the plan, design, ledger, diff package, exact outputs, and any unexecuted visual gates.
