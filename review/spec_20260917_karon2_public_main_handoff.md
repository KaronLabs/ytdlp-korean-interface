# Code Supreme Court Review Spec

meta:
  created_at: 2026-09-17 (Asia/Seoul)
  review_mode: high_risk
  review_target: d4c55f907011d4e9db3fea4380cc886830845af8
  comparison_base: baf39d25370e05a69814357cd2d0a5cb10696910
  alternative_comparison_evidence:
    status: available
    items:
      - `git merge-base baf39d25370e05a69814357cd2d0a5cb10696910 d4c55f907011d4e9db3fea4380cc886830845af8` returned the comparison base.
      - `git rev-list --count baf39d25370e05a69814357cd2d0a5cb10696910..d4c55f907011d4e9db3fea4380cc886830845af8` returned 65.
      - `git diff --stat` reported 822 files changed, 287363 insertions, and 248 deletions.
      - `git diff --name-status` reported 799 added files, 23 modified files, and no deleted files.
      - The authenticated SSH push reported `baf39d2..d4c55f9  HEAD -> main`.
      - The post-push `git ls-remote origin refs/heads/main` result was exactly `d4c55f907011d4e9db3fea4380cc886830845af8`.
  feedback_source:
    - User report that the interface appeared to download only low-quality video despite higher-quality streams being available.
    - User-approved quality preset, GUI, dependency-license, and `v2.19.1-karon.2` release plan.
    - Prior Code Supreme Court findings concerning exact-target availability, incomplete GUI validation, and incomplete binary-distribution license review.
    - User instruction that this session perform TDD implementation only and leave independent validation to another session.
    - User instruction that the reviewer can access GitHub only.
  scope:
    - Add versioned per-item video/audio/advanced download policies and 1080p, 720p, and best-quality presets.
    - Integrate policy preview, format pinning, queue persistence, start-time reinspection, and final-output inspection into the Windows GUI.
    - Migrate and pin redistributable archive/runtime dependencies for the intended `v2.19.1-karon.2` package.
    - Add third-party notices, source-closure material, SPDX inputs, GUI evidence contracts, candidate construction, packaging, and publication tooling.
    - Harden candidate provenance and release-license locking against encoding ambiguity, time-of-check/time-of-use replacement, wrapper substitution, and Windows case-fold collisions.
    - Publish the exact source target to public `origin/main` by a normal fast-forward SSH push.
    - Exclude independent GUI adjudication, final ZIP adjudication, tag creation, and GitHub Release publication from this implementation session.
  changed_files:
    total: 822
    added: 799
    modified: 23
    deleted: 0
    top_level_counts:
      release: 755
      tests: 22
      tools: 18
      ytdlp-interface: 17
      docs: 3
      review: 3
      locales: 1
      README.md: 1
      THIRD-PARTY-NOTICES.txt: 1
      ytdlp-interface dependencies.7z: 1
    full_inventory: https://github.com/KaronLabs/ytdlp-korean-interface/compare/baf39d25370e05a69814357cd2d0a5cb10696910...d4c55f907011d4e9db3fea4380cc886830845af8
  reviewer_access_assumption:
    - The reviewer can access only the public GitHub repository, commit, compare view, and GitHub Actions visible there.
    - The reviewer cannot rely on local `E:` drive artifacts, implementation-agent consoles, private temporary fixtures, or this session's in-memory state.
    - Exact target: https://github.com/KaronLabs/ytdlp-korean-interface/commit/d4c55f907011d4e9db3fea4380cc886830845af8
    - Exact comparison: https://github.com/KaronLabs/ytdlp-korean-interface/compare/baf39d25370e05a69814357cd2d0a5cb10696910...d4c55f907011d4e9db3fea4380cc886830845af8
    - This spec is an administrative follow-up file outside the functional review target. Its publication must not change `review_target`.
  constitution_documents:
    status: present
    paths:
      - E:/03_AllWork/ytdlp-korean-interface/AGENTS.md
      - E:/03_AllWork/ytdlp-korean-interface/.worktrees/karon2-release-rebuilt/README.md
      - E:/03_AllWork/ytdlp-korean-interface/.worktrees/karon2-release-rebuilt/docs/superpowers/plans/2026-09-16-quality-presets.md
      - E:/03_AllWork/ytdlp-korean-interface/.worktrees/karon2-release-rebuilt/docs/superpowers/plans/2026-09-16-deno-third-party-notices.md
      - E:/03_AllWork/ytdlp-korean-interface/.worktrees/karon2-release-rebuilt/review/spec_20260916_quality_presets.md
      - E:/03_AllWork/ytdlp-korean-interface/.worktrees/karon2-release-rebuilt/review/spec_20260916_quality_presets_retrial.md
    applicability:
      - Project instructions require narrow changes, explicit TDD boundaries, implementation/review separation, truthful status, and no force push.
      - The quality plan defines the preset behavior, queue semantics, GUI/DPI matrix, final-output inspection, and release gates.
      - The Deno plan and release metadata define third-party notice and corresponding-source expectations.
      - Earlier review specs are historical statements for earlier targets and are not treated as proof for this target.

summary:
  - The target adds a basic video/audio policy model with 1080p, 720p, and best presets while retaining an explicit advanced mode for legacy/custom behavior.
  - The GUI now derives analysis and download arguments from the same policy, previews selected streams, pins literal format IDs, freezes policy per queue item, and checks the final file with ffprobe before normal completion.
  - The target also adds the build, dependency, license, source-closure, GUI-evidence, packaging, and publication contracts intended for `v2.19.1-karon.2`.
  - Candidate provenance was hardened to capture exact Git source identity, decode NUL-delimited Git tree paths as strict UTF-8, and resist source replacement between inspection and materialization.
  - The release-license lock was hardened to bind the actual source wrapper and raw archive, retain file handles or immutable snapshots through inspection, and reject ordinal or case-insensitive duplicate archive paths.
  - All 65 commits in the target range are now publicly accessible on GitHub `main` at exact SHA `d4c55f9...`.
  - No tag, public executable ZIP, corresponding-source ZIP, SPDX asset, or GitHub Release was created by this session.
  - Exact-target independent GUI, final-package license, and CI validation remain incomplete, so this submission is `partial_success` rather than a completion claim.

rationale:
  - The original GUI exposed raw formats in a way that could make users believe only the first combined 360p entry was usable even when separate high-resolution video and audio streams were available.
  - A preset must control the effective yt-dlp invocation, not merely decorate the GUI. Basic mode therefore ignores external yt-dlp configuration and arbitrary custom arguments, while advanced mode preserves existing expert behavior.
  - `res:N` is a preference rather than a complete upper-bound proof. The implementation therefore inspects yt-dlp's selected metadata, applies the smaller-dimension cap used for portrait and landscape media, and rejects unknown or over-cap results instead of silently downloading a larger or lower-confidence selection.
  - Queue items carry their own versioned policy so a later global setting change cannot alter already-enqueued work. Invalid or absent legacy policy data falls back to advanced mode instead of silently applying new defaults.
  - Automatic video re-encoding was intentionally excluded. The design prioritizes selected quality and lets yt-dlp/FFmpeg choose a suitable output container.
  - Public binary distribution requires more than an application MIT license. The target adds component notices, pinned dependency identities, source-closure material, and a lock step that connects inspected bytes to packaging inputs.
  - The archive and candidate tools process mutable filesystem inputs. Hash-then-reopen designs allow replacement races; the final implementation holds readable handles or immutable snapshots and validates Windows case-fold uniqueness before publication.
  - The public source push was required because the appointed reviewer can access GitHub only. A normal fast-forward push was used; history rewriting, tag creation, and release publication were intentionally excluded.
  - This session did not repeat independent validation. Focused TDD execution reported by implementation agents is disclosed as witness evidence, not converted into exact-target CI or independent runtime proof.

changes:
  - path: ytdlp-interface/download_policy.hpp
    status: added
    change: Defines the versioned basic-video, basic-audio, and advanced policy; 1080p, 720p, and best presets; argument construction; selected-stream inspection; output inspection; literal format-ID restrictions; and selection-equivalence checks.
    reason: Centralize quality behavior so analysis, queueing, execution, and final verification use one policy contract.
  - path: ytdlp-interface/gui_quality.cpp
    status: added
    change: Implements policy-aware command construction, metadata analysis, generation-safe preview handling, dependency checks, queue policy capture, download execution, output-path receipts, ffprobe inspection, and user-facing error/status text.
    reason: Connect the policy contract to the actual Windows GUI lifecycle instead of adding non-functional preset labels.
  - path: ytdlp-interface/forms/*.cpp, ytdlp-interface/gui*.cpp, ytdlp-interface/gui.hpp, ytdlp-interface/queue.cpp, ytdlp-interface/types.*, ytdlp-interface/util.*, ytdlp-interface/ytdlp-interface.*
    status: modified
    change: Wires mode and quality controls into existing forms, persists policy state, stores per-item policy in the queue, exposes status and expected output, updates version identity, and builds the new implementation unit.
    reason: Integrate the new policy without replacing unrelated GUI architecture.
  - path: locales/ko-KR.json
    status: modified
    change: Adds Korean labels and diagnostics for download mode, quality presets, analysis, dependency errors, policy boundaries, and verified completion states.
    reason: Keep the new primary workflow understandable in the Korean interface.
  - path: tools/build-candidate.ps1
    status: modified
    change: Captures source commit/tree identity, materializes the captured tree, normalizes native Git failures, supports Windows PowerShell, and decodes NUL-delimited Git tree inventory as strict UTF-8 without globally changing console encoding.
    reason: Ensure a candidate is built from the source identity that was inspected and preserve non-ASCII path identity across Windows shells.
  - path: tools/build-release-license-lock.ps1
    status: added
    change: Integrates verified component/source/license inputs into a release lock while retaining or snapshotting inspected bytes, binding the 7-Zip wrapper to its raw corresponding source, and rejecting case-fold path collisions.
    reason: Prevent mutable-input substitution and ambiguous Windows archive identities from passing a release gate.
  - path: tools/build-sevenzip-no-rar.ps1, tools/build-sevenzip-source-wrapper.ps1
    status: added
    change: Builds a 7-Zip runtime without RAR handlers and creates the deterministic corresponding-source wrapper consumed by the release lock.
    reason: Match runtime scope to ZIP/7z extraction needs and connect redistributed bytes to source material.
  - path: tools/collect-*.ps1, tools/build-corresponding-sources.ps1, tools/generate-release-spdx.ps1
    status: added
    change: Collects FFmpeg, Deno, and non-runtime component provenance/notices and constructs corresponding-source and SPDX inputs.
    reason: Make third-party distribution inputs explicit rather than describing the whole portable package as MIT.
  - path: tools/package-quality-release.ps1, tools/publish-quality-release.ps1, tools/candidate-manifest.psm1
    status: added_or_modified
    change: Defines candidate inventory, exact release asset names, package gates, draft-first GitHub publication, asset identity checks, and failure sanitization.
    reason: Keep package construction and public publication tied to a known candidate instead of rebuilding or substituting assets after validation.
  - path: tools/record-gui-release-evidence.ps1, tools/verify-gui-release-evidence.ps1, release/validation/v2.19.1-karon.2/*
    status: added
    change: Defines structured GUI case records and validation contracts for the required language/DPI matrix.
    reason: Give the independent validation session a deterministic input/output contract without declaring the cases passed.
  - path: tests/native/*, tests/quality/*, tests/powershell/*
    status: added_or_modified
    change: Adds policy, selector, media-fixture, candidate provenance, dependency archive, license bundle, GUI evidence, source collection, release lock, packaging, and publication regression tests.
    reason: Establish the TDD perimeter around failure modes introduced or discovered by the implementation.
  - path: release/dependencies/*, release/licenses/*, release/runtime/*, release/evidence/*
    status: added
    change: Adds pinned dependency metadata, component licenses, FFmpeg/Deno/7-Zip source-closure records, and generated or collected license-corpus material. This group contains most of the 755 changed `release/` paths.
    reason: Supply the intended portable release with explicit component and corresponding-source records; inclusion in Git is not itself a legal-compliance verdict.
  - path: ytdlp-interface dependencies.7z
    status: modified
    change: Replaces the prior dependency archive with the archive used by the bit7z 4.1 candidate contract.
    reason: Align candidate linkage inputs with the pinned archive dependency plan.
  - path: README.md, THIRD-PARTY-NOTICES.txt, release/notes/v2.19.1-karon.2.md, release/requests/v2.19.1-karon.2.json
    status: added_or_modified
    change: Documents the Korean GUI fork, preset behavior, third-party licensing boundary, intended release assets, unsigned-binary status, and release request contract.
    reason: State user-visible behavior and distribution facts without claiming a release that has not occurred.
  - path: docs/superpowers/*, review/spec_20260916_quality_presets*.md, review/retrial_petition_20260916_quality_presets.md
    status: added
    change: Preserves design, implementation, and prior court-review history.
    reason: Retain the decision trail while treating earlier target claims as historical rather than current proof.

implementation:
  core_logic:
    - `download_policy::policy` serializes version, mode, and quality. Unsupported, malformed, or absent policy data resolves conservatively to advanced mode.
    - Basic video builds `--ignore-config --no-playlist -f bv*+ba/b --format-sort-force -S res:<cap>` or `res` for best. Basic audio uses `ba/b -x --audio-format mp3 --audio-quality 0`.
    - A pinned selection is accepted only when every `+`-separated token is a literal format ID rather than a selector alias, extension alias, wildcard, or aggregate selector.
    - Playlist, multi-video, live, upcoming, and post-live metadata is rejected from basic mode and routed to advanced behavior.
    - Selected metadata must contain required audio/video streams. Capped video requires known dimensions, and the smaller of width/height must not exceed the selected cap.
    - Final ffprobe metadata must match the selected mode, cap, stream presence, and audio codec rules. Attached pictures are not counted as video streams.
    - Candidate source provenance captures commit/tree identity and uses strict UTF-8 for Git's NUL-delimited path inventory.
    - Release-license locking inspects the bytes actually supplied to packaging, binds wrapper and raw source identities, and rejects ordinal and ordinal-ignore-case duplicate paths.
  data_flow:
    - GUI URL plus captured policy/settings -> yt-dlp simulation metadata -> inspected selected streams -> literal pinned format IDs -> queue item with immutable policy snapshot -> start-time reinspection -> yt-dlp download/postprocessing -> final-path receipt -> ffprobe JSON -> completed or preserved-error state.
    - Git commit/tree plus pinned dependencies and source archives -> candidate/source inventories -> component evidence and release-license lock -> package inputs -> intended four-asset publication contract.
    - Local integration target -> pre-push remote SHA gate -> normal SSH fast-forward push -> public GitHub exact commit and compare view.
  state_transition:
    - Legacy or malformed policy -> advanced mode.
    - Basic policy changed or URL changed -> previous analysis invalidated -> new analysis generation pending.
    - Analysis valid -> expected resolution/audio displayed -> literal formats pinned for that item.
    - Analysis invalid, over cap, dimensions unknown, missing audio/video, or boundary input -> blocked with an explicit diagnostic.
    - Queue insertion -> policy and selected metadata frozen for that item.
    - Start-time selection differs from preview -> item paused rather than silently downgraded.
    - Download/postprocessing success -> final path parsed -> ffprobe inspection -> completed only when output matches policy.
    - Final inspection failure -> file preserved and item marked with a result-verification error.
    - Mutable release input -> readable handle or snapshot retained -> inspected identity written to lock -> publication allowed only through subsequent gates.
  edge_conditions:
    - Portrait video uses the smaller dimension for the 720/1080 cap.
    - Unknown video dimensions do not pass capped presets.
    - Best quality has no numeric resolution cap but still requires the expected streams.
    - A video-only selection cannot be displayed as audio-included.
    - Basic audio output must be MP3 and must not contain a normal video stream.
    - A single format ID is scoped to the analyzed item and is not reused for playlists or unrelated URLs.
    - Late asynchronous analysis cannot replace a newer URL/policy generation.
    - Git paths are decoded as UTF-8 locally for the inventory operation; global console encoding is not mutated.
    - Archive entries colliding only under Windows case folding are rejected.
    - Hash-then-swap of raw archives, wrappers, or supplied evidence cannot silently substitute later bytes in the final lock path.
  error_handling:
    - Policy and metadata parse failures fail closed to advanced mode or a blocked item.
    - Missing or non-executable FFmpeg/ffprobe receives a specific user-facing error and does not produce a verified-complete result.
    - Ambiguous or missing final-path receipts preserve downloaded files and report an inspection failure.
    - Candidate Git failures are normalized to controlled source-input errors instead of leaking uncontrolled native output.
    - Publication transport failures are sanitized, and credential-helper output is suppressed from reported errors.
    - Source/archive identity mismatches and duplicate paths stop lock/package generation.
  I/O:
    - Executes yt-dlp, FFmpeg, and ffprobe using quoted Windows process arguments.
    - Reads and writes queue/config policy JSON, temporary metadata/receipt data, component evidence JSON, lock JSON, package ZIPs, and intended GitHub Release assets.
    - Reads Git objects and dependency/source archives; the public action performed in this session was a Git SSH push only.
  API_contract: No application network API was added. The release publisher uses GitHub release/asset interfaces under an exact repository, tag, candidate, and asset-name contract.
  DB_contract: none
  persistence:
    - Policy JSON stores `version`, `mode`, and `quality`.
    - Each queue item stores its own policy and selected-result state.
    - Existing custom arguments and manual format history are retained for advanced mode.
    - Release lock, notices, source inventories, and request files persist build/release inputs; they do not prove final public asset compliance until independently checked.

impact:
  UI: Adds basic video/audio selection, 1080p/720p/best controls, expected-result text, explicit analysis/blocking states, and advanced-mode routing.
  API: No public application API change. GitHub release automation code is added but was not executed for a release.
  DB: none
  configuration: Adds versioned download policy persistence; legacy settings conservatively remain advanced rather than being overwritten.
  deployment: Source `main` now contains the implementation at `d4c55f9...`; no release tag or binary assets exist from this session.
  security: Reduces command selector ambiguity, external-config override, archive substitution, path-collision, candidate source TOCTOU, publication identity, and credential-output risks. Independent security adjudication is still pending.
  performance: Adds metadata simulation before queue/download, start-time reinspection, and ffprobe after download. These are bounded external-process costs per basic-mode item; no benchmark was run.
  dependencies: Moves archive integration toward bit7z 4.1 and a no-RAR 7-Zip runtime; adds pinned FFmpeg, Deno, source-closure, and notice contracts for the intended package.
  a11y: New controls and labels exist, but keyboard/accessibility and 100/150/200 percent DPI behavior were not independently executed for this target.
  i18n: Korean text was added. The complete Korean/English six-case GUI matrix remains unverified.
  backward_compatibility: Legacy policy absence falls back to advanced mode and existing custom settings are retained. Runtime migration behavior still requires independent GUI validation.
  data_retention: Downloaded files are preserved when final inspection fails. Existing `karon.1` release content was not changed.
  logging_monitoring: Adds explicit policy/inspection diagnostics and structured release evidence inputs. No production telemetry service was added.

threat_model:
  required: true
  trusted:
    - The exact local Git commit and tree captured before candidate materialization.
    - Explicitly pinned component identities after they are independently verified.
    - The authenticated `git@github.com:KaronLabs/ytdlp-korean-interface.git` origin.
  untrusted:
    - User URLs and extractor metadata.
    - Format IDs and aliases returned by external extractors.
    - Mutable local dependency, runtime, wrapper, source, notice, and evidence files.
    - Archive entry names, including Windows case-fold aliases and path traversal forms.
    - External yt-dlp configuration and arbitrary custom arguments when operating in basic mode.
    - GitHub transport/API responses and release asset state until identity checks complete.
  boundary_change:
    - The GUI now converts external metadata into pinned command arguments and completion decisions.
    - New tooling converts local Git/archive/license inputs into candidate and intended public-release artifacts.
    - New publication tooling can create external GitHub release state when explicitly run in a later session.
  risk_scenarios:
    - A selector alias is mistaken for a literal format ID and changes the effective download selection.
    - External configuration silently re-enables MP3 extraction or low-quality format selection in basic video mode.
    - Metadata changes between preview and execution and silently downgrades or changes streams.
    - A dependency/source archive is replaced after hashing but before inspection or packaging.
    - Two archive entries differ ordinally but collide on Windows, allowing ambiguous extraction or evidence matching.
    - A source wrapper is valid by itself but refers to a different raw corresponding-source archive.
    - A candidate is built from a working tree different from the captured Git commit/tree.
    - A publisher uploads the wrong bytes, wrong asset set, or assets associated with the wrong source identity.
    - Error output discloses credential-helper or transport-secret material.
  mitigation:
    - Use `--ignore-config`, explicit basic-mode arguments, strict literal format-ID validation, and per-item policy snapshots.
    - Reinspect immediately before execution and block changed selections.
    - Verify the final output with ffprobe and preserve mismatching files without false completion.
    - Capture commit/tree identity and decode Git inventory as strict UTF-8.
    - Retain readable handles or immutable snapshots through archive/evidence inspection and lock publication.
    - Require ordinal and ordinal-ignore-case path uniqueness and explicit wrapper-to-source binding.
    - Enforce exact candidate, tag, repository, asset-name, length, and hash contracts in package/publication tools.
    - Sanitize publication failures and suppress credential-helper output.
    - Keep release publication on hold until an independent session verifies GUI, package, licensing, and exact-target CI.
  accepted_gaps:
    - Independent GUI lifecycle and DPI validation has not been run for this target.
    - Final portable ZIP and corresponding-source assets have not been produced and independently classified.
    - Exact-target CI status was not checked by this implementation session.
    - The intended executable remains unsigned unless a later release process adds Authenticode signing.

deployment_or_rollback:
  deployment_plan:
    - Completed scope: normal fast-forward SSH push of source target `d4c55f9...` to public `origin/main`.
    - Deferred scope: independent target validation, final candidate build, final portable ZIP inspection, annotated `v2.19.1-karon.2` tag, and four GitHub Release assets.
    - This spec may be published in a later administrative commit while retaining `d4c55f9...` as the functional review target.
  rollback_procedure:
    - Do not force-push or rewrite public `main`.
    - If independent review rejects the source target, create explicit revert commit(s) for the rejected target range or apply narrowly scoped corrective commits.
    - Do not create the release tag or assets while required gates remain unresolved.
    - Existing `v2.19.1-karon.1` remains the prior public release and must not be replaced.
  last_known_good_commit: baf39d25370e05a69814357cd2d0a5cb10696910

acceptance_criteria:
  - criterion: The exact implementation target is publicly obtainable by the GitHub-only reviewer.
    required: true
    source: User instruction and prior court target-availability finding.
    result: PASS
    verification: Authenticated push output was `baf39d2..d4c55f9  HEAD -> main`; post-push `ls-remote` returned the exact target for `refs/heads/main`.
  - criterion: The submitted comparison range and changed-file count are derived from Git rather than a stale summary.
    required: true
    source: Review protocol provenance rule.
    result: PASS
    verification: Git reported 65 commits and 822 files: 799 added, 23 modified, 0 deleted.
  - criterion: Basic video and audio policies, 1080p/720p/best presets, legacy advanced fallback, and per-item queue persistence are implemented in the target.
    required: true
    source: User-approved quality-preset implementation plan.
    result: PASS
    verification: Exact-target Git diff contains the policy model, GUI integration, queue persistence, native tests, and fixture tests. This is implementation evidence, not independent runtime adjudication.
  - criterion: Basic mode prevents external config/custom options from silently overriding the selected mode and quality.
    required: true
    source: User-approved conflict-isolation rule.
    result: PASS
    verification: The policy argument contract adds `--ignore-config` and generates basic-mode selection/extraction options centrally; advanced mode retains custom behavior.
  - criterion: Preview, start-time selection, and final output are checked without silent quality-policy changes.
    required: true
    source: User-approved analysis/execution consistency and completion rules.
    result: NOT_VERIFIED
    verification: Implementation and tests exist, but this session did not independently run the exact target through the complete GUI lifecycle.
  - criterion: Candidate provenance handles Windows PowerShell, strict UTF-8 Git paths, and source TOCTOU cases.
    required: true
    source: TDD implementation scope following candidate-provenance review findings.
    result: PASS
    verification: Implementation-agent runs reported candidate provenance 12/12 under Windows PowerShell 5.1 and pwsh, release factory 9/9, and the related publication implementation suite 99/99 at the source implementation commits. No exact-target CI inference is made.
  - criterion: Release-license locking rejects wrapper/source substitution, raw archive swap, wrapper swap, and case-fold collisions.
    required: true
    source: TDD implementation scope following release-lock review findings.
    result: PASS
    verification: RED reproduced four fail-open paths at 11/15; GREEN was reported as 15/15, wrapper-focused 5/5, and publication implementation suite 98/98 at the source implementation commits. No independent exact-target verdict is claimed.
  - criterion: Korean and English GUI behavior passes at 100%, 150%, and 200% scaling on the same exact executable.
    required: true
    source: User-approved GUI six-case matrix.
    result: NOT_VERIFIED
    verification: Not executed in this TDD implementation session.
  - criterion: A final `v2.19.1-karon.2` portable ZIP has zero unclassified files, zero unverified components, no prohibited FFmpeg configuration, and complete source/license bindings.
    required: true
    source: User-approved public binary license gate.
    result: NOT_VERIFIED
    verification: Tooling and repository material were implemented, but no final ZIP was built and independently adjudicated in this session.
  - criterion: Required CI jobs are successful for exact target `d4c55f9...`.
    required: true
    source: Code Supreme Court exact-target validation requirement.
    result: NOT_VERIFIED
    verification: CI was not queried or treated as evidence by this implementation session.
  - criterion: Public tag and release assets are created only after all blocking gates pass.
    required: true
    source: User-approved deployment order.
    result: PASS
    verification: No tag or GitHub Release asset was created while GUI, final-package license, and exact-target CI gates remain unresolved.
  - criterion: Current online YouTube behavior is checked separately from deterministic local fixtures.
    required: false
    source: User-approved optional online smoke rule.
    result: NOT_VERIFIED
    verification: Not executed; this optional omission is not promoted to a required failure.

validation:
  automated:
    - command: `git -c core.autocrlf=false -C <repo> rev-parse HEAD; git status --porcelain=v1 -uall; git remote get-url origin; git ls-remote origin refs/heads/main`
      result: PASS
      summary: Before publication, local HEAD was `d4c55f9...`, the worktree was clean, origin was the requested SSH repository, and remote main was `baf39d2...`.
      reason: Establish the exact source and remote preconditions for the requested public handoff.
    - command: `git -c core.autocrlf=false -C <repo> fetch --no-tags origin refs/heads/main:refs/remotes/origin/main; git merge-base --is-ancestor baf39d2... d4c55f9...`
      result: PASS
      summary: The fetched remote SHA matched the preflight SHA and the target was a descendant suitable for normal fast-forward publication.
      reason: Prevent a force push, divergent update, or stale remote assumption.
    - command: `git -c core.autocrlf=false -C <repo> push origin HEAD:refs/heads/main`
      result: PASS
      summary: Git reported `baf39d2..d4c55f9  HEAD -> main`.
      reason: Make the exact implementation target accessible to the GitHub-only reviewer.
    - command: `git -c core.autocrlf=false -C <repo> ls-remote origin refs/heads/main`
      result: PASS
      summary: Post-push remote main equaled `d4c55f907011d4e9db3fea4380cc886830845af8`; the local worktree remained clean.
      reason: Detect a failed or competing remote update after publication.
    - command: `git diff --name-status/--stat and git rev-list for baf39d2...d4c55f9`
      result: PASS
      summary: Git reported 65 commits, 822 changed files, 799 additions, 23 modifications, no deletions, 287363 inserted lines, and 248 deleted lines.
      reason: Bind the court summary to the authoritative Git range.
    - command: `implementation-agent focused Pester/native invocations for candidate provenance and release-license lock (exact shell transcript unavailable to the GitHub-only reviewer)`
      result: PASS
      summary: Reported GREEN results were candidate provenance 12/12 on both Windows PowerShell 5.1 and pwsh, release factory 9/9, candidate-related publication 99/99, release lock 15/15, source wrapper 5/5, and lock-related publication 98/98.
      reason: Disclose the TDD implementation evidence while explicitly withholding exact-target CI or independent-verification status.
  manual:
    - procedure: Operate the exact target through basic video 1080p, 720p, best, MP3, advanced mode, queue persistence, changed-selection blocking, completion, and preserved-error paths.
      result: NOT_RUN
      observed_result: none
      reason: The user assigned independent GUI validation to another session.
      artifact: none
    - procedure: Inspect Korean and English layouts at 100%, 150%, and 200% DPI using one exact executable SHA.
      result: NOT_RUN
      observed_result: none
      reason: The user assigned the six-case GUI matrix to another session.
      artifact: none
    - procedure: Independently classify every file in the final portable ZIP and verify licenses, notices, exact source, and build closure.
      result: NOT_RUN
      observed_result: No final ZIP was created by this implementation session.
      reason: License adjudication and final artifact validation belong to the separate validation session.
      artifact: none
  ci:
    result: NOT_RUN
    target_sha: d4c55f907011d4e9db3fea4380cc886830845af8
    run: unavailable
    covered_checks: none established by this filing
    uncovered_checks: exact-target build, native policy, PowerShell contracts, GUI lifecycle, language/DPI matrix, final package/license gate, and publication contract
    summary: This implementation session did not query GitHub Actions and does not reuse CI from another SHA.

risks:
  - description: Exact-target GUI lifecycle and the six language/DPI combinations are not independently verified.
    severity: high
    handling: fix_before_merge
    reason: Unit, fixture, and contract tests do not prove Nana event wiring, layout, persisted migration, or final user-visible completion behavior.
  - description: No final portable ZIP has passed independent file-by-file license and corresponding-source adjudication.
    severity: high
    handling: fix_before_merge
    reason: Repository notices and lock tooling do not by themselves prove that the exact distributed bytes satisfy all component obligations.
  - description: Exact-target public CI evidence is not established in this filing.
    severity: medium
    handling: follow_up
    reason: Implementation-agent test reports are not a substitute for a GitHub-visible run bound to `d4c55f9...`.
  - description: The 822-file range includes a large generated/collected FFmpeg license corpus, increasing review cost and the chance of unnoticed inventory mismatch.
    severity: medium
    handling: safeguard
    reason: The authoritative Git inventory must be compared by exact members, not accepted from counts alone.
  - description: The intended executable is not Authenticode-signed.
    severity: low
    handling: accepted
    reason: The approved scope permits an unsigned release if that fact and final hashes are disclosed; no binary release has occurred yet.
  - description: Online YouTube extractor behavior remains unverified.
    severity: medium
    handling: follow_up
    reason: Site behavior can differ from deterministic fixtures, but the approved contract treats this smoke as optional and non-blocking when external conditions prevent execution.

request:
  allowed_verdicts:
    - NOT GUILTY
    - GUILTY
    - DEATH
  review_focus:
    - Independently fetch exact target `d4c55f9...` and compare it with `baf39d2...`; confirm 65 commits and the exact 822-member file inventory.
    - Review the effective basic-mode command, literal format pinning, resolution-cap semantics, queue policy persistence, start-time reinspection, and ffprobe completion gate.
    - Re-run the focused candidate provenance and release-license-lock suites on the exact target rather than accepting implementation-agent totals alone.
    - Run the exact-target GUI lifecycle and Korean/English 100/150/200 percent matrix using one recorded executable identity.
    - Build and independently classify the final portable ZIP, corresponding-source ZIP, SPDX JSON, and checksum list before authorizing a tag or GitHub Release.
    - Check GitHub Actions only where the workflow head SHA equals `d4c55f9...`; do not inherit success from earlier targets.
    - Treat the absence of a public `karon.2` binary release as the intended safeguard while blocking gates remain open.

brief:
  - 잘된 점: 화질 선택을 GUI 장식이 아니라 분석·대기열·실행·결과 검사까지 이어지는 단일 정책으로 구현했고, GitHub-only 검토가 가능하도록 exact target을 fast-forward 공개했습니다.
  - 애매한 점: 구현 단계의 focused GREEN 결과는 존재하지만 GitHub-only 검증자가 재현할 exact-target CI와 최종 GUI/ZIP 증거는 아직 없습니다.
  - 어려웠던 점: Windows의 UTF-8 경로, case-fold 충돌, hash-then-swap, source-wrapper 결속처럼 서로 다른 계층의 동일성 문제를 한 릴리스 계약으로 수렴시켜야 했습니다.

status:
  partial_success

review_verdict:
  PENDING
