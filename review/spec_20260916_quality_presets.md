# Code Supreme Court Review Spec

meta:
  created_at: 2026-09-16T07:16:45.8785403+09:00
  review_mode: standard
  review_target:
    branch: codex/quality-presets-20260916
    commit: e36fe2894a80021ac9b7218c73173552d90e0063
    working_tree_at_evidence_collection: clean
  comparison_base: baf39d25370e05a69814357cd2d0a5cb10696910
  alternative_comparison_evidence:
    status: available
    items:
      - `git merge-base baf39d25370e05a69814357cd2d0a5cb10696910 HEAD` returned the comparison base itself.
      - `git diff --stat baf39d25370e05a69814357cd2d0a5cb10696910..e36fe2894a80021ac9b7218c73173552d90e0063` reported 30 files, 2,796 insertions, and 41 deletions.
      - The target consists of eight scoped commits from `4808866` through `e36fe28`.
      - `origin` was observed as `git@github.com:KaronLabs/ytdlp-korean-interface.git`; this branch has not been pushed or released by this work.
  feedback_source:
    - User report that the interface appeared to download only 360p despite higher-resolution formats being available.
    - User-approved quality-preset implementation plan: basic video/audio modes, 1080p/720p/best presets, advanced-mode isolation, per-item policy, preflight revalidation, output inspection, independent verification, and gated release.
    - Independent application reviews `application-review.md`, `application-review-2.md`, and `application-review-3.md`.
  scope:
    - Implement a Korean-facing basic download flow with video, MP3 audio, and advanced modes.
    - Add maximum 1080p, maximum 720p, and current-best quality policies.
    - Keep basic-mode options isolated from external yt-dlp configuration and custom arguments.
    - Persist policy per queue item, invalidate stale analyses, pin the verified format IDs, and inspect the final output.
    - Add focused native/fixture tests, candidate-build support, and a gated `v2.19.1-karon.2` packaging path.
    - Build and validate a local release candidate without publishing it.
  changed_files: 30
  reviewer_access_assumption:
    - Reviewer can access the local worktree at `E:/03_AllWork/ytdlp-korean-interface/.worktrees/quality-presets`.
    - Reviewer can access retained local validation reports under `E:/03_AllWork/ytdlp-korean-interface/.quality-presets-work`.
    - Reviewer cannot assume a pushed branch, pull request, exact-SHA CI run, or public `karon.2` release exists.
    - Reviewer should independently run or inspect the remaining GUI, locale/DPI, online, and release gates.
  constitution_documents:
    status: present
    paths:
      - E:/03_AllWork/ytdlp-korean-interface/AGENTS.md
      - E:/03_AllWork/ytdlp-korean-interface/.worktrees/quality-presets/README.md
      - E:/03_AllWork/ytdlp-korean-interface/.worktrees/quality-presets/docs/superpowers/plans/2026-09-16-quality-presets.md
    applicability:
      - `AGENTS.md` governs respectful Korean communication, narrow changes, goal-oriented verification, implementation/review separation, and the project response format.
      - `README.md` defines the user-facing project and candidate-release claims.
      - The quality-preset plan defines this feature's behavior and release acceptance gates.
      - No `SECURITY.md` was found at the checked worktree path.

summary:
  - Added a versioned download-policy model with basic video, basic MP3 audio, and advanced modes.
  - Fresh settings default to basic video at maximum 1080p; 720p and current-best presets are available without requiring manual format IDs.
  - Basic mode generates isolated yt-dlp arguments, analyzes the actual selected streams, rejects invalid or over-cap selections, and pins literal format IDs before download.
  - Queue items retain their own policy and analysis generation; final output is verified with ffprobe before being reported complete.
  - Focused policy, fixture-engine, production-object, MP3, candidate-build, and static-review checks passed in their stated scopes.
  - The final executable's actual GUI/lifecycle path, six locale/DPI cases, online YouTube integration, complete third-party notice review, and public release remain unverified or unexecuted.
  - No public source push, tag, GitHub release, or public ZIP was produced; publication remains on HOLD.

rationale:
  - The prior interface exposed low-level formats in a way that could make a muxed 360p option look like the only practical video choice even when separate 720p/1080p video and audio streams existed.
  - The implementation makes the common case explicit: users select a mode and quality ceiling, while yt-dlp still performs format selection and FFmpeg performs normal merge/post-processing.
  - `res:N` is treated as a preference rather than a proof of a hard ceiling. The selected metadata is inspected and an over-cap or unknown bounded result is blocked instead of silently accepted.
  - Analysis and execution share one policy, and execution uses the analyzed literal format IDs. This prevents a later fallback from quietly changing the promised quality.
  - Basic mode uses `--ignore-config` so unrelated user configuration or custom `-f` arguments cannot override the visible preset. Existing custom behavior is retained in advanced mode.
  - The trade-off is additional analysis and ffprobe work before a basic-mode job can be marked complete. This favors truthful output over a misleading early success state.
  - Playlist and live inputs, automatic video re-encoding, a new dependency installer, and a broader queue redesign were intentionally excluded.
  - Release evidence and packaging machinery already requested by the approved plan were retained, but this spec creates no new sealing, SBOM, or attestation procedure.

changes:
  - path: README.md
    status: modified
    change: Added the candidate quality-preset behavior, verification boundary, and release status information.
    reason: Describe the new user flow without presenting the unshipped candidate as a public release.
  - path: docs/superpowers/plans/2026-09-16-quality-presets.md
    status: added
    change: Recorded the selected scope, behavior, and public-release acceptance gates.
    reason: Preserve the implementation contract reviewed by separate agents.
  - path: locales/ko-KR.json
    status: modified
    change: Added Korean strings for mode/quality controls, stages, warnings, and failure states.
    reason: Make the new flow understandable without exposing raw format semantics.
  - path: release/notes/v2.19.1-karon.2.md
    status: added
    change: Drafted candidate release notes for the quality-preset change.
    reason: Prepare release communication while retaining candidate status.
  - path: release/requests/v2.19.1-karon.2.json
    status: added
    change: Added the gated local release request metadata.
    reason: Bind any future package to the intended repository, upstream baseline, platform, and source.
  - path: tests/native/quality_policy_tests.cpp
    status: added
    change: Added native tests for policy serialization, arguments, selection/output inspection, boundaries, aliases, and queue-related policy behavior.
    reason: Exercise the production policy logic without GUI dependencies.
  - path: tests/native/quality_policy_tests.vcxproj
    status: added
    change: Added a Windows project for the native policy test executable.
    reason: Build the focused tests with the project's Windows toolchain.
  - path: tests/quality/README.md
    status: added
    change: Documented the fixture scenarios, evidence meaning, and non-GUI limitations.
    reason: Prevent engine-only evidence from being misreported as GUI acceptance.
  - path: tests/quality/reproduce_selector_alias.py
    status: added
    change: Added a focused reproduction for yt-dlp selector-alias behavior.
    reason: Guard literal format-ID pinning from selector aliases and extension selectors.
  - path: tests/quality/test_quality_fixture.py
    status: added
    change: Added fixture contract tests for generated media and extractor behavior.
    reason: Validate the deterministic offline quality scenarios.
  - path: tools/build-candidate.ps1
    status: modified
    change: Added `PROCESSOR_ARCHITECTURE=AMD64` to the isolated x64 build environment and its attestation record.
    reason: Prevent libjpeg-turbo/CMake from observing an empty or inherited non-x64 architecture in hermetic builds.
  - path: tools/build-quality-development.ps1
    status: added
    change: Added an explicitly unsealed development-build helper.
    reason: Support rapid local application builds without confusing them with release candidates.
  - path: tools/package-quality-release.ps1
    status: added
    change: Added a gated packager that requires exact source/candidate inputs, independent validation records, minimal shipping settings, and third-party notices.
    reason: Refuse a public package while required quality and release gates remain incomplete.
  - path: tools/quality-fixture.py
    status: added
    change: Added a deterministic local yt-dlp extractor/HTTP fixture for mixed, capped, portrait, codec, and config-isolation cases.
    reason: Test real yt-dlp and FFmpeg selection/merge behavior without relying on YouTube availability.
  - path: tools/test-quality-policy.ps1
    status: added
    change: Added the focused native policy build/test runner.
    reason: Provide one command for direct policy regression checks.
  - path: ytdlp-interface/download_policy.hpp
    status: added
    change: Added the policy model, JSON serialization, yt-dlp argument generation, selected-stream inspection, output inspection, literal-ID validation, and selection comparison.
    reason: Keep the visible preset, analysis, execution, and completion rules in one production policy.
  - path: ytdlp-interface/forms/form_formats.cpp
    status: modified
    change: Connected manual-format reset to the recommended policy and prevented unsafe format-dialog entry while analysis/download state is active.
    reason: Make the existing automatic-selection action restore the new preset state.
  - path: ytdlp-interface/forms/form_loading.cpp
    status: modified
    change: Preserved basic-policy items and their errors in the existing large-queue retention path.
    reason: Avoid losing new per-item state when restoring larger queues.
  - path: ytdlp-interface/gui.cpp
    status: modified
    change: Integrated policy loading/saving, queue policy persistence, and unified completion handling.
    reason: Keep fresh defaults and legacy advanced behavior distinct across sessions.
  - path: ytdlp-interface/gui.hpp
    status: modified
    change: Declared quality widgets, policy helpers, analysis generations, item mailboxes, and preflight/output methods.
    reason: Attach the new flow to the existing GUI lifecycle.
  - path: ytdlp-interface/gui_bottom.cpp
    status: modified
    change: Routed basic-mode execution through policy preflight and verified completion.
    reason: Prevent the download button from bypassing the analyzed policy.
  - path: ytdlp-interface/gui_bottoms.cpp
    status: modified
    change: Added basic-mode completion participation to the global completion guard.
    reason: Avoid premature close or power actions while basic jobs are still active.
  - path: ytdlp-interface/gui_make.cpp
    status: modified
    change: Added mode, quality, analysis, settings, and result-summary controls to the main window.
    reason: Put the common quality decision next to the download action.
  - path: ytdlp-interface/gui_quality.cpp
    status: added
    change: Implemented basic analysis, generation invalidation, preflight revalidation, literal-ID pinning, process mailbox handling, receipt parsing, ffprobe verification, stages, and localized status rendering.
    reason: Provide the end-to-end preset behavior while reusing the existing process and queue architecture.
  - path: ytdlp-interface/queue.cpp
    status: modified
    change: Stored/restored item policy and actual per-item output options independently of metadata availability.
    reason: Prevent global setting changes or missing cached metadata from mutating queued jobs.
  - path: ytdlp-interface/types.cpp
    status: modified
    change: Initialized and serialized the new per-item quality state.
    reason: Make policy state part of the queue item's existing lifecycle.
  - path: ytdlp-interface/types.hpp
    status: modified
    change: Added per-item policy/analysis fields.
    reason: Carry the selected behavior with each job.
  - path: ytdlp-interface/util.cpp
    status: modified
    change: Captured child-process exit codes for the new verification flow.
    reason: Distinguish successful output from failed yt-dlp/FFmpeg/ffprobe execution.
  - path: ytdlp-interface/util.hpp
    status: modified
    change: Exposed optional process-exit-code output in the existing process helper contract.
    reason: Let quality preflight and inspection fail closed on tool errors.
  - path: ytdlp-interface/ytdlp-interface.vcxproj
    status: modified
    change: Added the new policy header and GUI implementation to the application build.
    reason: Compile and link the feature into the Windows executable.

implementation:
  core_logic:
    - `download_policy::policy` stores schema version 1, mode, and quality.
    - Basic video arguments use `--ignore-config --no-playlist -f bv*+ba/b --format-sort-force -S res:N`; basic audio uses `ba/b -x --audio-format mp3 --audio-quality 0`.
    - Selected metadata is scanned once for literal format IDs, video/audio presence, dimensions, and playlist/live boundaries. Bounded modes require known dimensions and reject `min(width,height)` above the selected cap.
    - Execution preflight repeats the analysis policy and compares the visible selection before pinning the exact format IDs.
    - Final output is accepted only after a single reported final path is parsed and ffprobe confirms the required streams, dimensions, and MP3 codec where applicable.
    - Stream inspection is O(s) time and O(1) auxiliary state for `s` selected or output streams. Queue persistence remains O(q) for `q` queue items.
  data_flow:
    - User mode/quality selection -> versioned policy -> analysis arguments -> yt-dlp metadata -> policy inspection -> displayed planned result.
    - Download request -> generation/state recheck -> same-policy preflight -> literal format-ID pin -> yt-dlp/FFmpeg -> `after_move` JSON receipt -> ffprobe -> verified completion or preserved-file error.
    - Worker output -> per-item mailbox under mutex -> GUI-thread publication, avoiding worker access to mutable GUI containers.
  state_transition:
    - pending analysis -> analyzing -> ready with verified selection -> download -> post-process -> inspect -> done.
    - URL/mode/quality changes invalidate prior generations and return the item to analysis-required state.
    - Changed preflight selection, missing tools, invalid metadata, invalid literal IDs, download failure, ambiguous receipt, or probe mismatch transitions to paused/error without silent quality downgrade.
    - Stop-all and skipped-row intent are rechecked before deferred starts; auto-advance remains suppressed when stopped.
  edge_conditions:
    - Playlist, multi-video, live, upcoming, and post-live metadata require advanced mode.
    - 1080p/720p are ceilings checked on the smaller dimension so portrait media is handled consistently.
    - Lower-than-target media is allowed and reported at its actual dimensions.
    - Above-cap and unknown-dimension bounded selections are rejected; current-best may proceed without a numeric ceiling but is not described as the source original.
    - Selector aliases, extension selectors, and non-literal IDs cannot be pinned as if they were exact format IDs.
    - Attached cover art is ignored when evaluating whether MP3 output unexpectedly contains video.
  error_handling:
    - External/custom config is excluded only in basic mode; legacy custom behavior remains available in advanced mode.
    - Tool execution failures use captured exit codes and localized messages.
    - Final files are preserved on receipt or inspection failure; the app does not automatically delete or redownload them.
    - Stale asynchronous responses are discarded by generation rather than overwriting newer selections.
  I/O:
    - Reads/writes the existing JSON settings and queue cache with the new policy fields.
    - Launches local `yt-dlp.exe`, `ffmpeg.exe`, and `ffprobe.exe` through the existing process boundary.
    - Reads yt-dlp JSON metadata and `after_move` receipt output; reads ffprobe JSON stream metadata.
    - Writes media only to the selected output location through yt-dlp/FFmpeg. No database is used.
  API_contract:
    - External public API: none.
    - Internal policy API: `serialize`, `deserialize`, `arguments`, `inspect_selected`, `inspect_output`, `same_selection`, `is_basic`, and `resolution_cap`.
    - Process helper gains optional exit-code capture while retaining existing callers.
  DB_contract: none
  persistence:
    - Root setting key: `download_policy` with `version`, `mode`, and `quality`.
    - Queue policy state is stored per item rather than inferred from remembered `fmt1`/`fmt2` values.
    - Missing or invalid policy in an existing profile resolves to advanced mode, preserving legacy behavior.
    - Fresh shipping settings contain only language, relative yt-dlp path, relative FFmpeg path, and basic-video/1080p policy.

impact:
  UI: Main window gains explicit video/audio/advanced selection, 1080p/720p/best quality choices, analysis action, planned-result text, and staged completion status.
  API: No public API change; internal process helper and policy functions are extended.
  DB: none
  configuration: Adds versioned global and per-item policy state; basic mode ignores external yt-dlp configuration and arbitrary custom arguments.
  deployment: A local `karon.2` candidate and gated packager exist, but no source push, tag, release, or public ZIP occurred.
  security: Reuses the existing local subprocess boundary. Basic-mode argument tokens are app-generated and literal format IDs are validated before pinning. No auth, permission, secret, or public network boundary was added.
  performance: Adds one preflight metadata check and one ffprobe inspection per basic job. Policy/stream work is linear in queue/stream count; no automatic video re-encoding was added.
  dependencies: Uses the existing yt-dlp, FFmpeg, ffprobe, Deno, 7-Zip, and native build dependencies. No new runtime dependency is introduced.
  a11y: Keyboard/DPI behavior was not independently verified; risk remains.
  i18n: Adds Korean strings with English fallbacks in code; six locale/DPI runtime cases remain unexecuted.
  backward_compatibility: Existing profiles without a valid versioned policy remain in advanced mode; remembered custom arguments and manual-format behavior are not deleted.
  data_retention: Queue policy is retained per item; files produced before a verification failure are preserved.
  logging_monitoring: Adds visible stage/error output and retained local validation records; no remote telemetry or monitoring is added.

acceptance_criteria:
  - criterion: Exact review target is identifiable and contains only the eight scoped quality-preset commits after the selected base.
    required: true
    source: Code Supreme Court input/provenance contract.
    result: PASS
    verification: Git reported merge-base `baf39d2`, target `e36fe28`, clean status, and 30 changed files in the scoped diff.
  - criterion: Fresh users receive basic video, maximum 1080p, and automatic audio/container behavior.
    required: true
    source: User-approved implementation plan.
    result: PASS
    verification: Candidate shipping settings and actual settings loader tests verified version 1, mode `video`, quality `1080p`, and relative tool paths.
  - criterion: Basic 1080p/720p policies select video plus audio, enforce the ceiling, support portrait media, and truthfully allow lower-only media.
    required: true
    source: User-approved implementation plan.
    result: PASS
    verification: Native policy checks and real offline yt-dlp/FFmpeg fixtures covered mixed 1080p, 720p, only-360p, portrait, over-cap rejection, VP9, and AV1 cases.
  - criterion: Basic mode is not overridden by external yt-dlp config or arbitrary custom arguments; advanced mode preserves legacy custom behavior.
    required: true
    source: User-approved implementation plan.
    result: PASS
    verification: Engine config-honored/config-ignored cases and actual production-object settings tests passed for fresh basic and legacy advanced profiles.
  - criterion: Analysis and execution remain aligned, stale responses cannot overwrite current choices, and exact verified format IDs are pinned without silent fallback.
    required: true
    source: User-approved implementation plan and independent F1-F8 review findings.
    result: PASS
    verification: Final native helper reported 116/116 assertions; independent static reviews closed F1-F8 and R1 in their stated scopes.
  - criterion: Each queue item retains its own policy/output options across save/restore and global policy changes.
    required: true
    source: User-approved implementation plan.
    result: PASS
    verification: Native policy/persistence assertions and actual loader tests passed, including fresh and legacy settings. No claim is made that a 51-row queue was exercised through the final GUI.
  - criterion: A downloaded basic-mode result is marked complete only after final-path receipt and ffprobe stream verification; failed inspection preserves the file.
    required: true
    source: User-approved implementation plan.
    result: PASS
    verification: Production helper plus real engine checks passed 17/17; actual production-object process/receipt harness passed 35/35 and produced a 1920x1080 file with audio and a Korean filename.
  - criterion: Existing MP3 behavior remains functional.
    required: true
    source: Regression requirement from the existing application.
    result: PASS
    verification: Existing MP3 smoke created, probed, and cleaned a real MP3 artifact. This is artifact/CLI proof, not a GUI-click proof.
  - criterion: The exact target source builds into a sealed Windows x64 candidate with the intended minimal settings and dependency inventory.
    required: true
    source: User-approved candidate-build and release plan.
    result: PASS
    verification: Independent candidate build completed with exit code 0; source SHA `e36fe28`, executable hash `90ED...932E`, and candidate manifest hash `6E69...B6B1` were recorded. This criterion concerns the local candidate, not public release readiness.
  - criterion: The final candidate's actual GUI can complete the core video, MP3, advanced, stop, skip, queue, and completion lifecycle without regression.
    required: true
    source: UI interaction test expectation and user-approved independent verification plan.
    result: NOT_VERIFIED
    verification: Computer Use could enumerate/activate the window, but capture failed with `0x80004002` and coordinate input geometry was unavailable. Blind clicks were not used.
  - criterion: Korean/English UI at 100%, 150%, and 200% scaling keeps the mode, quality, result, and download controls visible and operable.
    required: true
    source: User-approved six-case GUI acceptance matrix.
    result: NOT_VERIFIED
    verification: All six runtime GUI/DPI cases were not run because the supported Windows automation path could not capture or address the Nana controls.
  - criterion: Current online YouTube extraction produces the intended high-quality result with the candidate runtime.
    required: false
    source: User-approved plan separates online integration from deterministic offline acceptance.
    result: NOT_VERIFIED
    verification: Online integration was not executed.
  - criterion: Third-party notices and distributable-source obligations are complete for the final public ZIP.
    required: true
    source: Gated packaging/release plan.
    result: NOT_VERIFIED
    verification: Notice inputs were collected for named components, but full FFmpeg/Deno transitive obligations and exact binary/source correspondence remain incomplete.
  - criterion: Source and verified ZIP are pushed/published to `KaronLabs/ytdlp-korean-interface` only after all required gates pass.
    required: true
    source: User-approved SSH deployment and release plan.
    result: NOT_VERIFIED
    verification: Publication was deliberately held; no push, tag, GitHub release, or public ZIP was performed.

validation:
  automated:
    - command: `E:/03_AllWork/ytdlp-korean-interface/.quality-presets-work/final-B-e36fe28/helper/bin/quality_policy_tests.exe --implementation-ready`
      result: PASS
      summary: Final native production policy helper passed 116/116 assertions.
      reason: Directly exercises serialization, argument construction, selection/output validation, aliases, boundaries, persistence, and lifecycle contracts.
    - command: `& E:/03_AllWork/ytdlp-korean-interface/.quality-presets-work/final-B-e36fe28/run.ps1`
      result: PASS
      summary: Five retained stages passed: native helper, MP3 smoke, fixture preparation, real fixture engine, and production/engine integration. Original candidate files remained unchanged and no owned runtime process remained.
      reason: Rechecks the exact candidate-adjacent helper/engine behavior and media artifacts.
    - command: `E:/03_AllWork/ytdlp-korean-interface/.quality-presets-work/loader-process-B01/bin-receipt-02/acceptance.exe E:/03_AllWork/ytdlp-korean-interface/.quality-presets-work/gui-dev-B04/runtime http://127.0.0.1:9106/quality/mixed`
      result: PASS
      summary: Actual production-object settings/process/receipt harness exited 0 with 35/35 assertions, including a 1920x1080 video with audio and Korean filename.
      reason: Exercises compiled production objects and real yt-dlp/FFmpeg/ffprobe integration without claiming final GUI-path acceptance.
    - command: `tools/build-candidate.ps1 -Run` with the pinned source, isolated parent runtime, dependency archive, and fresh candidate base recorded in the independent build report.
      result: PASS
      summary: Independent Windows x64 candidate build and candidate inventory/settings checks passed; runner exit code 0.
      reason: Proves the exact source can produce the retained candidate after the two-line architecture-environment correction.
    - command: Independent architecture-focused PowerShell harness retained under `.quality-presets-work/architecture-review-20260915T211215Z`.
      result: PASS
      summary: 50 focused assertions passed for empty, x86, and ARM64 inherited environments; child builds observed `PreferredToolArchitecture=x64` and `PROCESSOR_ARCHITECTURE=AMD64`.
      reason: Reproduces and closes the hermetic CMake/libjpeg-turbo architecture failure without changing build arguments.
  manual:
    - procedure: Independent static review of the application integration, followed by focused R1 closure.
      result: PASS
      observed_result: F1-F8 were reported addressed; R1's inaccessible helper call was replaced by the existing localization API. The final review explicitly limits itself to static scope.
      reason: Separate reviewers examined implementation defects without implementing production code.
      artifact: E:/03_AllWork/ytdlp-korean-interface/.quality-presets-work/application-review-3.md
    - procedure: Launch and operate the exact candidate through the core GUI lifecycle using the supported Computer Use path.
      result: NOT_RUN
      observed_result: Window discovery/activation succeeded, but screen capture failed with `SetIsBorderRequired / 0x80004002`; coordinate input geometry was unavailable and Nana inner controls were not exposed through UI Automation.
      reason: Supported UI observation/input was unavailable; blind interaction and custom Win32/GDI bypasses were not used.
      artifact: E:/03_AllWork/ytdlp-korean-interface/.quality-presets-work/gui-dev-B04/sky-observation.json
    - procedure: Exercise Korean and English UI at 100%, 150%, and 200% scaling.
      result: NOT_RUN
      observed_result: No locale/DPI case was executed.
      reason: Same Computer Use capture/input blocker as the core GUI flow.
      artifact: none
    - procedure: Run a current online YouTube integration check with the candidate runtime.
      result: NOT_RUN
      observed_result: none
      reason: Deterministic offline validation completed; optional online validation was not started.
      artifact: none
    - procedure: Complete third-party distribution notice/source review for the final ZIP.
      result: NOT_RUN
      observed_result: Component notices were prepared, but complete legal/distribution clearance was not claimed.
      reason: FFmpeg/Deno transitive notices and some exact binary/source correspondences remain unresolved.
      artifact: E:/03_AllWork/ytdlp-korean-interface/.quality-presets-work/licenses-report.md
  ci:
    result: NOT_RUN
    target_sha: e36fe2894a80021ac9b7218c73173552d90e0063
    run: unavailable
    covered_checks: none
    uncovered_checks: All exact-target CI checks; no CI URL or run ID was verified for this local branch.
    summary: Local focused/build/integration evidence exists, but it must not be presented as exact-SHA GitHub Actions success.

risks:
  - description: The exact final executable has not been driven through the real GUI lifecycle, so wiring, event-order, stop/skip, queue, or close/power regressions may remain despite static and object-level tests.
    severity: high
    handling: fix_before_merge
    reason: This is a user-facing GUI feature and the required E2E path is still unverified.
  - description: Korean/English layout at 100%, 150%, and 200% scaling is unverified.
    severity: medium
    handling: fix_before_merge
    reason: Controls may clip or become inaccessible on common Windows scaling settings.
  - description: Current online YouTube/EJS behavior is unverified against the candidate runtime.
    severity: medium
    handling: follow_up
    reason: Offline fixtures prove policy/engine integration but cannot prove current site-specific extraction.
  - description: Complete third-party distribution obligations and exact correspondence for every shipped binary have not been independently cleared.
    severity: high
    handling: fix_before_merge
    reason: Public binary distribution should remain blocked until the release notice/source obligations are reviewed.
  - description: The 35/35 process/settings result links production objects from a development build, not user clicks through the sealed candidate GUI.
    severity: medium
    handling: safeguard
    reason: It is strong core-logic evidence but cannot substitute for final-artifact GUI acceptance.
  - description: No exact-target CI run is available.
    severity: low
    handling: follow_up
    reason: Local Windows evidence is substantial, but a pushed branch would still need exact-SHA CI status before ordinary merge/release claims.
  - description: The branch and review spec are local-only until an explicitly approved, gated source push occurs.
    severity: low
    handling: accepted
    reason: Reviewers without this workspace cannot inspect the target yet; this is intentional while publication gates are open.

request:
  allowed_verdicts:
    - NOT GUILTY
    - GUILTY
    - DEATH
  review_focus:
    - Confirm the 30-file `baf39d2..e36fe28` diff implements the stated policy without bypassing existing advanced behavior.
    - Independently execute the exact candidate's basic-video 1080p/720p, MP3, advanced, stop/skip, queue restore, and completion flows.
    - Execute Korean/English at 100%, 150%, and 200% scaling and record actual control visibility/operation.
    - Verify no silent quality downgrade occurs when the preflight selection changes or only over-cap/unknown bounded formats exist.
    - Review the unresolved third-party distribution obligations before authorizing a public ZIP.
    - Keep source publication, binary publication, and GitHub release judgment separate; do not infer any of them from the local candidate build.

brief:
  - 잘된 점: 화면 프리셋과 실제 yt-dlp 선택·실행·ffprobe 완료 판정을 하나의 버전 정책으로 연결했고, 실제 오프라인 엔진과 생산 객체 수준에서 고화질+오디오 결과를 검증했습니다.
  - 애매한 점: Computer Use 실패로 최종 실행 파일의 실제 GUI 사용자 흐름과 6개 언어/DPI 조건이 남아 있으며, 객체 수준 검증을 GUI 검증으로 승격할 수 없습니다.
  - 어려웠던 점: yt-dlp 정렬은 화질 상한 자체가 아니므로 선택 결과 재검사와 literal format-ID 고정이 필요했고, 격리 빌드에서는 CPU 아키텍처 환경을 명시해야 했습니다.

status:
  partial_success

review_verdict:
  PENDING
