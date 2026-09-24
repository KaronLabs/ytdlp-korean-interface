# Code Supreme Court Review Spec: karon.2 remote-main change set

## meta

- created_at: `2026-09-25`, Asia/Seoul
- review_mode: `standard`
- review_target: public `origin/main` commit `bcd91dac8a04857d4d08a86461fc005e156fa8bd`
- comparison_base: `baf39d25370e05a69814357cd2d0a5cb10696910`
- alternative_comparison_evidence:
  - status: `available`
  - items: `git ls-remote origin refs/heads/main` returned the target SHA; local HEAD matched; `git merge-base --is-ancestor` confirmed the base and functional commit `32f03f99d1339aa5f8fd37a1f6a1904b6dad5a28` are ancestors of the target.
- feedback_source: user's 360p/quality-preset complaint, subsequent karon.2 implementation and release requests, manual GUI validation instructions, and request for a remote-Git-based court submission
- scope: the 72 non-merge commits and 825 changed files in `comparison_base..review_target`; source, tests, release preparation, notices, and the Korean manual guide; **not** a claim that a new executable Release was published
- changed_files: `825` (`release/` 756, `tests/` 22, `tools/` 18, `ytdlp-interface/` 17, `review/` 5, `docs/` 3, `locales/` 1, and three root-level files)
- changed_files_or_diff: [complete public comparison](https://github.com/KaronLabs/ytdlp-korean-interface/compare/baf39d25370e05a69814357cd2d0a5cb10696910...bcd91dac8a04857d4d08a86461fc005e156fa8bd); `git diff --name-status <base> <target>` is the authoritative complete path list rather than copying 825 names here
- reviewer_access_assumption: reviewer can fetch the public repository and this exact commit, but cannot be assumed to access the local E: drive, sealed candidate, downloaded media, manual screenshots, or private CI data; request those separately if needed
- constitution_documents:
  - status: `present`
  - paths: conversation-provided `AGENTS.md` instructions (no `AGENTS.md` file in the inspected worktree), tracked `README.md`, tracked `release/validation/v2.19.1-karon.2/README.md`
  - applicability: user-provided instructions govern this task; the project README describes public behavior; the release-validation README defines the six-case GUI evidence gate
- historical_candidate_reference: a prior session reported sealed candidate EXE SHA-256 `BEBADE61F980CADA9D338A4C32DF77E0122C18BBF07E4E95E4F056C93008F6CA`; its current bytes and relation to this remote target were **not reverified in this session**
- spec_lifecycle: this administrative spec is written after the review target and is excluded from its 825-file diff; a later spec-publication commit must not replace `review_target` in this document

## summary

The source range adds versioned per-item download policies with basic video, MP3 audio, and advanced modes, plus 1080p, 720p, and best-available presets.
The GUI adds controls and expected-result display; the basic path builds yt-dlp arguments, inspects the selected streams, rechecks before download, and inspects the final file with ffprobe.
Settings and queue serialization persist policies; existing settings without a valid policy restore in advanced mode.
The range also adds native/fixture tests, GUI evidence tools, release packaging gates, dependency/license material, and a Korean manual evidence guide.
The source is on public `main`. No final karon.2 ZIP, completed six-case GUI contract, or published executable Release is established by this submission.

## rationale

The original user-visible format picker could be read as if only its checked 360p/720p formats were downloadable. The new basic path is intended to make quality choice explicit without requiring manual format IDs. `res:N` is a yt-dlp preference, not a hard maximum, so the policy additionally inspects selected and final stream dimensions. Basic mode isolates external yt-dlp config and user arguments; advanced mode retains manual/custom behavior. The trade-off is a larger GUI/process/queue surface and a release dependency on real GUI and license checks. Playlist/live handling, automatic transcoding, and a new installer were intentionally excluded from the basic preset scope.

## changes

The table groups the complete diff by purpose. The public comparison above contains every path and exact patch.

| path/group | status | change | reason |
|---|---|---|---|
| `ytdlp-interface/download_policy.hpp`, `gui_quality.cpp`, 15 other `ytdlp-interface/` paths | added/modified | Versioned policy, format and output inspection, GUI controls, queue integration, settings serialization, candidate branding/About details | Implement the quality-preset workflow and existing-setting compatibility |
| `locales/ko-KR.json` | modified | Quality and release-notice translations | Expose the new UI in Korean |
| `tests/` (22 paths) | added/modified | Native policy assertions, quality fixtures, GUI evidence and release/license contract tests | Define failure-sensitive checks for the new behavior and packaging gates |
| `tools/` (18 paths) | added/modified | Quality fixture/build scripts, GUI recorder/verifier, candidate/package/publication and license-source tools | Prepare independent validation and a gated release path |
| `release/` (756 paths) | added | Dependency lock, notices, license/source material, GUI validation contract, release notes and extensive FFmpeg/Deno evidence corpus | Prepare redistributable candidate and corresponding-source review; not proof of final approval |
| `docs/` (3 paths), `review/` (5 paths) | added | Plans, review/handoff records, Korean manual GUI evidence guide's associated review record | Explain scope and independent review boundaries |
| `README.md`, `THIRD-PARTY-NOTICES.txt`, `ytdlp-interface dependencies.7z` | modified/added | Public instructions, bundled-component notices, archive-dependency update | Document and prepare distribution dependencies |

Relevant milestones in the range include `47c501c` (per-item policies), `637a6da` (GUI and verified results), `197bb5c` (bit7z migration), `093a5b3` (GUI evidence gate), `7d7867d` (packaging/publication contract), `32f03f9` (product version validation), and `bcd91da` (manual guide localization). Commit titles identify intent; runtime success is not inferred from titles.

## implementation

- core_logic: `download_policy.hpp` defines policy version 1. Fresh policy is basic video/1080p. Basic video constructs `--ignore-config --no-playlist -f bv*+ba/b --format-sort-force -S res:N` (or unbounded `res` for best). Basic audio adds MP3 extraction. Advanced mode adds no basic-policy arguments. Selected formats and ffprobe output must contain the required streams; capped video uses the smaller dimension and rejects unknown or above-cap dimensions.
- data_flow: GUI mode/quality choice -> policy stored on the item -> yt-dlp metadata selection inspection and preview -> pre-download re-resolution and literal format-ID pinning -> yt-dlp execution -> final-path receipt -> ffprobe inspection -> queue completion or paused/error state.
- state_transition: basic/advanced choice changes item generation; stale analysis is invalidated. Queue items carry their own policy. On startup an absent/invalid saved policy becomes advanced rather than silently enabling a new basic policy. Playlist/live boundaries route to advanced. A failed inspection is paused, not silently downgraded or automatically redownloaded.
- edge_conditions: tests in source cover portrait orientation, absent dimensions/audio/video, above-cap selection/output, format-selector aliases, playlist/live boundaries, changed preview characteristics, VP9/AV1, MP3 cover art, and malformed probe data. Their existence is confirmed; their pass status at this target was not measured here.
- error_handling: the basic path sets a visible notice/stage on extractor, dependency, selection, download, final-path, or probe failures and preserves existing files on inspection failure. This is a code-path description, not a runtime success claim.
- I/O: Windows GUI, yt-dlp and ffprobe subprocesses, application JSON settings/queue files, downloaded media, and local release/evidence files.
- API_contract: no newly asserted external network API; CLI arguments passed to yt-dlp and the internal JSON policy shape change.
- DB_contract: none.
- persistence: `download_policy` and `queue_download_policies` are serialized in settings/queue data; old data without a valid policy routes to advanced mode.

## impact

- UI: new mode, quality, analyze, recommended, and settings controls; preview/stage notices; manual format selection retained.
- API: none externally asserted.
- DB: none.
- configuration: versioned policy and per-queue-item persistence; basic mode ignores external yt-dlp config.
- deployment: public source is pushed; final executable ZIP/Release is not established.
- security: new basic-mode command assembly and literal format-ID handling extend the existing yt-dlp subprocess boundary; see threat model.
- performance: extra selection recheck and ffprobe inspection add work before completion; no measured latency claim.
- dependencies: release range prepares bit7z v4, 7-Zip without RAR handlers, FFmpeg, Deno, and notices/source material; final package contents are not independently adjudicated here.
- a11y: DPI layouts and navigation require the six-case manual check; no PASS claimed.
- i18n: Korean UI entries and Korean manual guide added; English/Korean runtime matrix still pending.
- backward_compatibility: old policy-less settings are designed to remain in advanced mode; runtime migration not rechecked here.
- data_retention: failed final-file inspection is designed to preserve the downloaded file.
- logging_monitoring: quality notices/stages and existing outbox process output are used; no new production telemetry claim.

## threat_model

- required: `true` (basic mode creates a new route from URL/selected format metadata into a subprocess command)
- trusted: application-controlled policy enum, selected local tool paths after validation
- untrusted: user URL, extractor metadata/format IDs, external configuration in advanced mode
- boundary_change: new basic-mode argument construction and pinned format IDs at the existing yt-dlp/ffprobe process boundary
- risk_scenarios: format-selector alias or shell metacharacter interpreted as an unintended selector/command; external config overriding displayed quality; malformed metadata producing a false preview or unsafe fallback
- mitigation: literal format-ID validation, argument quoting and `--` before URL in the code path, `--ignore-config` in basic mode, selected/final-stream inspection, and no automatic lower-quality retry
- accepted_gaps: these mitigations were inspected in source, not independently penetration-tested or proven in the six-case GUI runtime at this target

## acceptance_criteria

| criterion | required | source | result | verification |
|---|---|---|---|---|
| Public `main` contains the functional quality-preset commit and the Korean guide | true | user request | PASS | `git ls-remote` returned `bcd91da...`; local ancestry check included `32f03f99...`; [GitHub shows the guide-localization commit](https://github.com/KaronLabs/ytdlp-korean-interface/commit/bcd91dac8a04857d4d08a86461fc005e156fa8bd) |
| Versioned policy, basic/advanced split, and 1080p/720p/best controls exist in the target source | true | implementation plan | PASS | Target diff in `download_policy.hpp`, `gui_make.cpp`, `gui.cpp`, `types.cpp` |
| Real basic-video 1080p/720p/best and MP3 downloads produce the advertised streams and bounds | true | user quality complaint and implementation plan | NOT_VERIFIED | No current-session executable or media run |
| Settings migration and per-item queue policy survive save/restart and do not regress advanced/manual mode | true | implementation plan | NOT_VERIFIED | Static code inspected; GUI/settings/queue runtime not run here |
| All six ko-KR/en-US by 100/150/200 GUI cases pass, including two real video lifecycles and representative MP3/settings/legacy checks | true | user's manual GUI evidence instruction | NOT_VERIFIED | No completed verifier summary/manifest inspected here; screenshot of a manual-format picker is not this acceptance evidence |
| Final ZIP and corresponding sources pass independent license/package review before executable release | true | user's karon.2 release plan | NOT_VERIFIED | Source/license corpus and gates exist, but final ZIP/adjudication not established here |
| Exact-target required CI jobs pass | true | review protocol | NOT_VERIFIED | No run ID/job set at `bcd91da...` obtained; GitHub Actions listing alone is insufficient |
| New Korean guide preserves command IDs and manual-evidence semantics | true | guide-localization request | NOT_VERIFIED | Commit shows a one-file translation diff; no independent semantic review of the new bytes |

## validation

### automated

| command/check | result | summary | reason |
|---|---|---|---|
| `git ls-remote origin refs/heads/main` and local `git rev-parse HEAD` | PASS | Both returned `bcd91dac8a04857d4d08a86461fc005e156fa8bd` during this preparation | Remote target identity only, not functional validation |
| `git merge-base --is-ancestor <base> <target>`; target contains `32f03f99...` | PASS | Both ancestry checks returned true | Establishes comparison and inclusion of functional source |
| `git diff --name-only <base> <target>` | PASS | 825 changed files, grouped in meta; 72 non-merge commits | Establishes scope, not correctness |
| Native quality policy, Python fixture, PowerShell release/license tests | NOT_RUN | Test code and runner were inspected but not executed in this session | Implementation and independent validation remain separate |

### manual

| procedure | result | observed_result | reason |
|---|---|---|---|
| Six-case GUI matrix and actual media inspection | NOT_RUN | none in this session | User/operator manual evidence contract remains the release gate |
| Final ZIP extraction, license adjudication, online YouTube smoke | NOT_RUN | none in this session | No final executable release established |

### ci

- result: `NOT_RUN` (not established for this review target)
- target_sha: `bcd91dac8a04857d4d08a86461fc005e156fa8bd`
- run: `unavailable`; the public Actions page did not identify exact-target required job results, and the attempted public API lookup was inaccessible
- covered_checks: unavailable
- uncovered_checks: exact-target CI identity and required-job status remain unconfirmed
- summary: do not apply a base or other-commit CI result to this target

## risks

| description | severity | handling | reason |
|---|---|---|---|
| The main quality workflow is not yet proven on the sealed executable across the required six GUI cases | high | safeguard | Block final ZIP and executable release until actual GUI/media evidence passes; static source cannot prove behavior |
| Third-party license/source compliance and the exact final ZIP are not independently adjudicated | high | safeguard | Block executable release; tracked notices/lock material are preparation, not a legal or package PASS |
| Exact-target CI result is unavailable | medium | follow_up | Reviewer must inspect a run tied to `bcd91da...` or record that required CI is not available |
| Korean guide changed after the prior English-guide verdict | medium | follow_up | The old exact-byte approval does not approve the new translation; review command names and semantics independently |
| A GitHub source checkout or older public executable may not be the sealed candidate being tested | medium | safeguard | Bind runtime observations to the candidate executable identity; do not treat source push as a binary release |

## request

- allowed_verdicts: `NOT GUILTY`, `GUILTY`, `DEATH`
- review_focus: independently inspect the `base..target` functional diff and directly related tests; distinguish source presence from working GUI, and tracked license corpus from an approved final package. Assess the Korean guide's command/criterion equivalence. Do not mark release PASS without the separate GUI, license, exact-target CI, and final-ZIP gates.
- independent_reviewer: different session or model with public repository access; request local runtime artifacts only if deciding runtime acceptance

## brief

- 잘된 점: 원격 `main`, 조상 관계, 825-file scope, and key implementation paths are directly identifiable.
- 애매한 점: native/fixture test and CI outcomes at the exact target were not established in this session.
- 어려웠던 점: the large license corpus is a real part of the diff but should not obscure the smaller functional change or be mistaken for approval.

## status

`partial_success` - source and documentation are published, while required functional GUI, release license/package, exact-target CI, and translation-equivalence criteria remain `NOT_VERIFIED`.

## review_verdict

`PENDING` - only an independent reviewer may assign the verdict.
