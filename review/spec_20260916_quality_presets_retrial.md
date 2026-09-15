# Code Supreme Court Review Spec: Retrial

meta:
  created_at: 2026-09-16T07:36:02.8424159+09:00
  review_mode: standard
  review_target: e36fe2894a80021ac9b7218c73173552d90e0063
  comparison_base: baf39d25370e05a69814357cd2d0a5cb10696910
  alternative_comparison_evidence:
    status: available
    items:
      - `refs/heads/review/quality-presets-e36fe28` advertises the exact target through `origin`.
      - GitHub's commit API returns the exact target and its public commit URL.
      - GitHub's compare API reports `ahead_by=8`, `total_commits=8`, and `changed_files=30` for the exact base-to-target range.
      - GitHub Actions run `35031230121` is bound to the exact target SHA and completed successfully, but covers only the provenance contract.
  feedback_source:
    - Code Supreme Court case `KSC-INFRA-2026-0916-QP-01`, verdict `GUILTY / REVISE / 26`.
    - Original filing `review/spec_20260916_quality_presets.md`.
    - Independent retrial target review and independent public-binary license review.
  scope:
    - Preserve the functional review target unchanged.
    - Cure external target availability and bind newly available CI identity to the target.
    - Re-adjudicate the court's required-validation claims against the filed specification.
    - Record the independent license gate as FAIL rather than NOT_VERIFIED.
    - Retain GUI, locale/DPI, and publication gates as unresolved without manufacturing PASS evidence.
  changed_files: 30 functional target files; retrial documents are administrative material outside the target
  reviewer_access_assumption:
    - Public target: `https://github.com/KaronLabs/ytdlp-korean-interface/commit/e36fe2894a80021ac9b7218c73173552d90e0063`.
    - Public review ref: `refs/heads/review/quality-presets-e36fe28`.
    - Public compare: `baf39d25370e05a69814357cd2d0a5cb10696910...e36fe2894a80021ac9b7218c73173552d90e0063`.
    - Exact-target CI: `https://github.com/KaronLabs/ytdlp-korean-interface/actions/runs/35031230121`.
    - Local raw reports remain available under `E:/03_AllWork/ytdlp-korean-interface/.quality-presets-work/retrial` for a reviewer on this host.
  constitution_documents:
    status: present
    paths:
      - E:/03_AllWork/ytdlp-korean-interface/AGENTS.md
      - E:/03_AllWork/ytdlp-korean-interface/.worktrees/quality-presets/README.md
      - E:/03_AllWork/ytdlp-korean-interface/.worktrees/quality-presets/docs/superpowers/plans/2026-09-16-quality-presets.md
      - E:/03_AllWork/ytdlp-korean-interface/.worktrees/quality-presets/review/spec_20260916_quality_presets.md
    applicability:
      - Project instructions require narrow changes, implementation/review separation, and truthful verification status.
      - The approved quality plan defines GUI/DPI and release gates; it treats online YouTube as a separate optional integration check.
      - The original filing is preserved as the historical statement submitted before the first verdict.

summary:
  - No functional source code changed after target `e36fe28`.
  - The exact target is now publicly obtainable from a dedicated review branch, curing the first filing's external-access defect.
  - GitHub independently exposes the exact eight-commit, 30-file comparison and an exact-target provenance CI run.
  - The court's statement that online YouTube was an unfinished required criterion is contradicted by the original specification, where it is explicitly `required: false`.
  - Required GUI/lifecycle and six locale/DPI cases remain NOT_VERIFIED because the supported Windows capture/input path failed again.
  - Independent license review returned FAIL for public binary distribution; public packaging and release remain on HOLD.
  - Overall implementation status remains `partial_success`; this filing requests only evidence-corrected retrial, not a false full acquittal.

rationale:
  - The first filing stated that the target was local-only, and the first documented independent pre-push observation found no advertised review ref. That absence observation has no separate wall-clock timestamp tying it mechanically to the exact filing instant. The current state is unambiguous: a plain, non-force push to a dedicated review ref fixes the review-material defect without changing `main` or publishing a binary.
  - The same push triggered an exact-target provenance workflow. It proves target identity and that contract only; it is not reused as evidence for GUI or quality behavior.
  - The court grouped online YouTube with required unfinished work, but the filed criterion is optional and the retained validation calls it intentionally omitted optional scope. That portion requires rebuttal rather than implementation.
  - GUI verification was retried with the supported Computer Use runtime. The target window launched, but screenshot capture again failed with `0x80004002`; the accessibility tree exposed only the title bar, and input geometry was unavailable. No blind interaction or custom Win32 bypass was used.
  - License integrity evidence was not enough to prove distribution compliance. The independent reviewer identified affirmative FFmpeg/ffprobe, Deno, and bit7z failures plus unresolved exact-binding gaps, so the gate is now recorded as FAIL.
  - The only source-side action is administrative review documentation. This retrial performed no new semantic review of the 30-file implementation and makes no defect-free claim. The verdict supplied no concrete functional defect to remediate, so speculative code changes are outside this retrial's scope.

changes:
  - path: refs/heads/review/quality-presets-e36fe28
    status: added
    change: Public review ref now points exactly to `e36fe2894a80021ac9b7218c73173552d90e0063`.
    reason: Make the exact target and base-to-target diff independently obtainable without moving `main`.
  - path: review/spec_20260916_quality_presets_retrial.md
    status: added
    change: Records post-verdict evidence, corrected acceptance results, and remaining blockers.
    reason: The spec lifecycle requires a new filing after a verdict and material review-state change.
  - path: review/retrial_petition_20260916_quality_presets.md
    status: added
    change: Separates rebutted, cured, and admitted counts with raw commands and public links.
    reason: Request a retrial without rewriting the historical first filing.

implementation:
  core_logic: none; review-material remediation only
  data_flow: local exact commit -> plain SSH push -> dedicated public review ref -> GitHub commit/compare API -> independent reviewer
  state_transition:
    - exact target unavailable -> exact target advertised at dedicated review ref
    - target CI unavailable -> exact-target provenance contract completed successfully
    - license gate NOT_VERIFIED -> FAIL after independent component review
    - GUI/DPI NOT_VERIFIED -> remains NOT_VERIFIED after reproducible Computer Use failure
  edge_conditions:
    - `main` remains at `baf39d25370e05a69814357cd2d0a5cb10696910`.
    - No force push, tag, release, or public ZIP was created.
    - The passed CI job covers provenance only.
    - Online YouTube remains optional and unexecuted.
  error_handling:
    - Push aborted unless origin, local HEAD, SSH authentication, ref absence, and post-push SHA matched expected values.
    - Computer Use stopped after the documented recovery retry and did not use stale coordinates or blind input.
    - The verifier-owned candidate process was stopped by its exact executable path after UI cleanup input failed.
  I/O:
    - One new Git remote branch ref was created.
    - Review Markdown files are added locally for the retrial filing.
    - No media, user settings, release asset, or `main` branch content was changed by the retrial remediation.
  API_contract: none
  DB_contract: none
  persistence: Git review ref and review documents only

impact:
  UI: no functional change; GUI acceptance remains unverified
  API: none
  DB: none
  configuration: none
  deployment: review branch published; production/source `main` deployment and binary release not performed
  security: plain SSH push used; no secret material was read or recorded
  performance: none
  dependencies: none
  a11y: unchanged and unverified in the final candidate
  i18n: unchanged; six locale/DPI runtime cases remain unverified
  backward_compatibility: none
  data_retention: original filing and independent reports preserved
  logging_monitoring: exact raw Git/GitHub/Computer Use results recorded in the petition

threat_model:
  required: false
  trusted: local Git object database and authenticated GitHub origin
  untrusted: public review consumers and external site state
  boundary_change: no application trust-boundary change; only a public review ref was added
  risk_scenarios: accidental main movement or publishing a non-target ref
  mitigation: exact origin/HEAD/ref gates, plain non-force push, and post-push `ls-remote` equality
  accepted_gaps: public review ref retention depends on future repository administration

acceptance_criteria:
  - criterion: Exact target is publicly obtainable and resolves to the submitted SHA.
    required: true
    source: Court rehabilitation order 1.
    result: PASS
    verification: Independent `git ls-remote --heads origin refs/heads/review/quality-presets-e36fe28` returned exactly `e36fe2894a80021ac9b7218c73173552d90e0063`.
  - criterion: Base-to-target provenance exposes the reported 30 files and eight commits.
    required: true
    source: Court procedures A and B.
    result: PASS
    verification: Local Git, independent reviewer Git, and GitHub compare API all reported 30 files and eight commits.
  - criterion: Available CI evidence is bound to the exact target and not overstated.
    required: true
    source: Court rehabilitation order 3 and procedure D.
    result: PASS
    verification: Run `35031230121` has `headSha=e36fe28...`, conclusion `success`, and one covered job `provenance-contract`; all quality/GUI checks remain listed as uncovered by CI.
  - criterion: Existing exact-target automated and object/engine evidence remains accurately scoped.
    required: true
    source: Original filing and retained independent validation.
    result: PASS
    verification: Target-bound source/candidate reports retain native 116/116, engine 9/9, production/engine 17/17, production-object 35/35, MP3 artifact smoke, and sealed x64 candidate build in their stated non-GUI scopes.
  - criterion: Final candidate GUI/lifecycle flow is independently executed.
    required: true
    source: Approved quality plan and UI interaction expectation.
    result: NOT_VERIFIED
    verification: Retry reproduced `SetIsBorderRequired ... 0x80004002`; accessibility exposed only title-bar controls and click input reported `coordinate input geometry is unavailable`.
  - criterion: Korean and English UI pass 100%, 150%, and 200% scaling.
    required: true
    source: Approved six-case GUI matrix.
    result: NOT_VERIFIED
    verification: No case could be executed through the supported Computer Use path.
  - criterion: Current online YouTube integration is checked.
    required: false
    source: Original filing and validation plan.
    result: NOT_VERIFIED
    verification: Not executed; this optional omission does not convert required acceptance to failure.
  - criterion: Public-binary third-party licensing is complete for the exact candidate.
    required: true
    source: Approved release gate.
    result: FAIL
    verification: Independent review found FFmpeg/ffprobe corresponding-source and transitive gaps, missing Deno/V8 notices and exact provenance, unresolved bit7z GPL static-link distribution posture, and several final linker-input/SBOM binding gaps.
  - criterion: Public source main and binary release occur only after required gates pass.
    required: true
    source: Approved deployment plan.
    result: NOT_VERIFIED
    verification: Correct safeguard behavior occurred: `main` and public release were not changed while GUI and license gates remain open.

validation:
  automated:
    - command: `git ls-remote --heads origin refs/heads/review/quality-presets-e36fe28`
      result: PASS
      summary: Exact advertised SHA equals the review target.
      reason: Directly cures external Git target availability.
    - command: `gh api repos/KaronLabs/ytdlp-korean-interface/commits/e36fe2894a80021ac9b7218c73173552d90e0063`
      result: PASS
      summary: GitHub returned the exact SHA, public commit URL, and commit metadata.
      reason: Confirms the object is available through the repository API.
    - command: `gh api repos/KaronLabs/ytdlp-korean-interface/compare/baf39d25370e05a69814357cd2d0a5cb10696910...e36fe2894a80021ac9b7218c73173552d90e0063`
      result: PASS
      summary: `status=ahead`, `ahead_by=8`, `total_commits=8`, and `changed_files=30`.
      reason: Independently exposes the complete comparison range.
    - command: `gh run view 35031230121 --repo KaronLabs/ytdlp-korean-interface`
      result: PASS
      summary: Exact-target `Provenance contract` completed successfully; no broader coverage is claimed.
      reason: Binds available CI identity to the target SHA.
    - command: retained exact-target native/engine/process/candidate validation from the original filing
      result: PASS
      summary: Prior target-bound checks remain valid in their explicitly limited scopes; no duplicate test run was added for evidence volume.
      reason: The functional target did not change.
  manual:
    - procedure: Independent target/provenance retrial review.
      result: PASS
      observed_result: Reviewer independently confirmed current review ref, exact objects, 30 files, eight commits, required GUI/DPI/license gaps, and the optional status of online YouTube.
      reason: Separate reviewer adjudicated the court's factual claims.
      artifact: E:/03_AllWork/ytdlp-korean-interface/.quality-presets-work/retrial/independent-target-review.md
    - procedure: Independent public-binary license review.
      result: FAIL
      observed_result: Integrity of submitted notices passed, but semantic completeness and exact candidate distribution obligations did not.
      reason: Known FAIL and NOT_VERIFIED component rows block public packaging.
      artifact: E:/03_AllWork/ytdlp-korean-interface/.quality-presets-work/retrial/independent-license-review.md
    - procedure: Establish safe observation and input for the exact candidate using supported Computer Use.
      result: FAIL
      observed_result: The controller reports that the candidate window launched as `ytdlp-interface v2.19.1-karon.2`; capture failed with `0x80004002`, accessibility exposed only the title bar, and geometry-backed input failed.
      reason: The automation infrastructure attempt ran but could not provide a safe control surface. This is not a product-function failure verdict.
      artifact: controller-reported current raw tool output and prior sky observation record
    - procedure: Operate the exact candidate through the basic-video, MP3, advanced, stop/skip, queue, and completion lifecycle.
      result: NOT_RUN
      observed_result: No feature control was clicked or driven.
      reason: The preceding observation/input prerequisite failed, so blind interaction was not attempted.
      artifact: none
  ci:
    result: PASS
    target_sha: e36fe2894a80021ac9b7218c73173552d90e0063
    run: https://github.com/KaronLabs/ytdlp-korean-interface/actions/runs/35031230121
    covered_checks: Exact-target checkout and provenance contract passed.
    uncovered_checks: Native quality policy, Windows application build, fixture engine, GUI lifecycle, locale/DPI matrix, and public-binary license gate are not covered by this run.
    summary: This PASS applies only to the identified exact-target provenance CI run. Full quality/GUI/license CI was NOT_RUN and receives no PASS inference.

risks:
  - description: Exact final-candidate GUI/lifecycle behavior remains unverified.
    severity: high
    handling: fix_before_merge
    reason: Static/object/engine checks cannot prove actual Nana event wiring and user interaction.
  - description: Public-binary license gate has affirmative failures and unresolved exact-binding gaps.
    severity: high
    handling: fix_before_merge
    reason: The candidate must not be publicly packaged or released until complete corresponding-source, notice, GPL posture, and exact dependency binding are resolved.
  - description: Six locale/DPI combinations remain unexecuted.
    severity: medium
    handling: fix_before_merge
    reason: Control clipping or inaccessibility may remain.
  - description: Current online YouTube behavior is unverified.
    severity: medium
    handling: follow_up
    reason: Site behavior may differ from deterministic fixtures, but this check is optional in the filed acceptance contract.
  - description: Exact-target CI currently covers provenance only.
    severity: low
    handling: follow_up
    reason: Local exact-target evidence exists, but public CI does not yet reproduce the full quality test set.

request:
  allowed_verdicts:
    - NOT GUILTY
    - GUILTY
    - DEATH
  review_focus:
    - Dismiss the current-state target-unavailability count because the exact ref is now independently advertised.
    - Dismiss any count that treats online YouTube as required; the filed source marks it optional.
    - Confirm 30 files, eight commits, public target identity, and exact-target provenance CI.
    - Retain only GUI/lifecycle, six locale/DPI cases, and public-binary license compliance as blocking required gates.
    - Do not treat the absence of public release as misconduct while those gates are open; publication HOLD is the required safeguard.

brief:
  - 잘된 점: 공개 review ref와 exact-target CI identity로 독립 취득 결함을 시정했고, 별도 검증자가 30 files·8 commits와 온라인 optional 판정을 재확인했습니다.
  - 애매한 점: GUI 자동화 실패는 제품 실패가 아니라 검증 인프라 실패지만, 실제 사용자 흐름 PASS를 대신할 수 없습니다.
  - 어려웠던 점: 라이선스 파일의 해시 일치는 배포 준수와 동일하지 않았으며, 독립 검토 결과 실제 FAIL 항목이 확인됐습니다.

status:
  partial_success

review_verdict:
  PENDING
