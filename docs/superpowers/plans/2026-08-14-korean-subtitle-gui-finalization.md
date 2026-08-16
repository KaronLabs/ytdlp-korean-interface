# Korean Subtitle GUI Finalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make valid yt-dlp subtitle metadata usable in every Korean GUI subtitle count and selection path, then produce a fresh independently reviewable evidence package.

**Architecture:** Keep subtitle recognition in one small, pure JSON predicate/display helper shared by the queue menu, asynchronous menu refresh, and subtitle dialog. A subtitle language is valid when its first subformat contains a download source (`url` or `data`); `name` is optional and the language key is the display fallback. GUI evidence, DPI evidence, and package sealing remain separate proof layers bound to one candidate manifest SHA.

**Tech Stack:** C++17, nlohmann::json, MSVC/v143 native tests, PowerShell 5.1, Python unittest, Computer Use, Git SHA-256 manifests.

## Global Constraints

- Preserve `review/spec_20260813_130912_korean_i18n_recovery.md`; all new review material is append-only.
- Do not modify the sealed candidate tree or preserved parent runtime.
- Exclude `live_chat`; do not infer GUI causality from artifact-only or operator-only smoke results.
- Use only `127.0.0.1` synthetic fixtures for runtime evidence.
- Every production behavior change follows RED → GREEN → REFACTOR with raw command, output, UTC, exit code, and transcript hash retained.
- Windows display scaling is changed only manually by the user; Computer Use must not automate it.

---

### Task 1: Name-less subtitle contract

**Files:**
- Create or modify the smallest existing shared subtitle contract header used by the GUI and native test target.
- Modify: `ytdlp-interface/queue.cpp:567-579`
- Modify: `ytdlp-interface/gui.cpp:1864-1882`
- Modify: `ytdlp-interface/forms/form_subs.cpp:139-170`
- Test: existing native test source/project and a deterministic subtitle regression fixture.

**Interfaces:**
- `subtitle_entry_available(const nlohmann::json&) -> bool`: true only for a nonempty subformat array whose first object contains `url` or `data`.
- `subtitle_display_name(std::string_view language, const nlohmann::json&) -> std::string`: returns nonempty string `name` when present, otherwise the language key.

- [ ] **Step 1: Write the failing test**

  Add a fixture with `{"en":[{"url":"http://127.0.0.1/sub.vtt","ext":"vtt","protocol":"m3u8_native"}]}` and assert it is available, counted once, and displayed as `en`; assert a `name`-only entry is not treated as downloadable.

- [ ] **Step 2: Run the focused test and verify RED**

  Run the existing native test command from the repository’s test runner. Expected: the new name-less subtitle assertion fails because the current consumers require `front().contains("name")`.

- [ ] **Step 3: Implement the minimal shared predicate and fallback**

  Replace all three `front().contains("name")` gates with the shared predicate, preserve `live_chat` exclusion, and use the language key when `name` is absent. Do not alter download command construction or unrelated metadata handling.

- [ ] **Step 4: Run GREEN verification**

  Run the focused native regression, `RECOVERED_CATALOG=locales/ko-KR.json python3 tests/run_contract_tests.py`, and `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run_powershell_tests.ps1`. Expected: all exit 0 and the subtitle fixture reports one available language.

- [ ] **Step 5: Rebuild a fresh clean candidate**

  Build from the reviewed commit with `source.dirty=false`, recompute the complete candidate manifest, and preserve build stdout/stderr/exit/timestamps outside the candidate root.

### Task 2: Computer Use GUI proof

**Files:**
- Create: external run-unique JSONL ledger and screenshots under `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\`.
- Create: new append-only `review/spec_<timestamp>_korean_i18n_gui_finalization.md`.

- [ ] **Step 1: Select exactly one returned candidate window**

  Initialize `@oai/sky`, call `list_apps()`/`list_windows()`, and bind the fresh execution copy and candidate manifest SHA. Never guess a window handle.

- [ ] **Step 2: Capture every required GUI state**

  Record preObservation, one action, postObservation, visibleResult, UTC, window id/title, screenshot path/length/SHA for startup, URL, metadata, MP3 format, playlist, subtitle, sections, message box, queue/output, settings, and normal close.

- [ ] **Step 3: Preserve output artifacts before cleanup**

  Retain the final MP3 bytes, settings JSON bytes, raw FFprobe output, and no-`.part` listing outside the disposable smoke workspace, each with length/SHA/UTC.

### Task 3: DPI and independent package gate

**Files:**
- Create: append-only DPI observation log and final evidence index/spec.
- Create: independent reviewer attestation from a different session/model.

- [ ] **Step 1: User manually selects 100%, 150%, and 200%**

  At each tier, restart or reobserve the same fresh candidate and capture measured window DPI: 96, 144, and 192 respectively.

- [ ] **Step 2: Seal the complete package**

  Include exact binary diff, untracked inventory, `git status --porcelain=v1`, constitution paths, every raw log command/output/timestamp/exit, candidate/smoke/artifact hashes, and the same candidate manifest SHA across all GUI evidence.

- [ ] **Step 3: Obtain independent verdict**

  A different model/session reviews the complete append-only package and records `NOT GUILTY` only if every mandatory slot is present and evidence-backed.

