# Review Spec: manual GUI evidence handoff for karon.2

> Publication note: this spec records the pre-publication review state. A byte-identical copy of the reviewed guide is staged for publication at `release/validation/v2.19.1-karon.2/MANUAL-GUI-EVIDENCE-GUIDE.md`; the guide's SHA-256 remains the review identity. The independent document verdict does not imply GUI validation PASS.

## meta

- case: `KARON2-MANUAL-GUI-EVIDENCE-20260924`
- review_mode: `standard`
- review_target: local, untracked `E:\03_AllWork\ytdlp-korean-interface\.validation\karon2-d4c55f9-20260918-01\MANUAL-GUI-EVIDENCE-GUIDE.md`
- review_target_sha256: `4A698685EA410BEC62579748BCD96F529F52A6B855669FAC108E3B969C27EE9F`
- review_target_size_bytes: `13123`
- comparison_base: not applicable; the guide is a newly created file outside Git, not a commit diff
- repository_context_head: `f8d3648bdb65dba9a68c925e8980f92136738d94`
- functional_target_unchanged: `32f03f99d1339aa5f8fd37a1f6a1904b6dad5a28`
- sealed_candidate_exe_sha256: `BEBADE61F980CADA9D338A4C32DF77E0122C18BBF07E4E95E4F056C93008F6CA`
- feedback_source: user direction to stop native Computer Use recovery and use the repository's manual GUI evidence contract
- reviewer_access_assumption: a GitHub-only reviewer cannot retrieve the local guide until it is attached or published; this spec does not claim otherwise
- constitution: user-supplied project `AGENTS.md` instructions and `release/validation/v2.19.1-karon.2/README.md`
- changed_files: 1 reviewed guide; this administrative Review Spec is excluded from that count

## summary

The reviewed change is a local operator guide for manually collecting GUI release evidence. It does not change the application, sealed candidate EXE, validation scripts, or release package. The guide describes six language/DPI cases, real observations and artifacts, representative feature coverage, and the existing record/verify commands. No GUI case has been recorded or passed by this change.

## rationale

Native application automation was stopped at the user's direction because its failure was classified as an automation-infrastructure limitation, not an application defect. The guide gives the Windows operator a repeatable path to collect actual observations under the repository's existing manual evidence contract. It must not substitute instructions for completed evidence.

## changes

| Path | Type | Purpose |
|---|---|---|
| `E:\03_AllWork\ytdlp-korean-interface\.validation\karon2-d4c55f9-20260918-01\MANUAL-GUI-EVIDENCE-GUIDE.md` | Added outside Git | Step-by-step manual GUI evidence collection and release HOLD criteria |

The guide is not committed or pushed. The existing functional target and sealed candidate remain the reference artifacts. This Review Spec documents the guide; it is not itself a GUI validation result.

## implementation

- Workflow: select one of `ko-KR-100`, `ko-KR-150`, `ko-KR-200`, `en-US-100`, `en-US-150`, `en-US-200`; operate the same sealed candidate; capture what was actually seen; record each completed step using `tools/record-gui-release-evidence.ps1`.
- Representative coverage: completed video lifecycle with downloaded media at `ko-KR-100` and `en-US-200`; MP3 conversion, settings save/restart restore, and legacy-settings transition across the full set.
- Evidence flow: operator observations and screenshots/media artifacts -> repository recorder -> `tools/verify-gui-release-evidence.ps1` -> `gui-validation-summary.json` and `gui-validation-evidence-manifest.json` only after all required evidence exists.
- State boundary: examples in the guide are not prefilled PASS records. An observed result may be recorded only after the corresponding user action and artifact inspection.
- Interfaces and persistence: no application API, GUI code, settings format, or queue-policy change. Evidence files will be produced by the existing tools when the manual workflow is run.

## impact

- User-visible application behavior: none.
- Release process: the guide makes the required manual GUI gate actionable, but does not satisfy the gate on its own.
- Source and binary provenance: no rebuild or change to the sealed EXE is authorized by this document.
- Reviewer access: the reviewed guide is currently local and outside Git. A reviewer restricted to GitHub needs the exact file and SHA supplied through an accessible channel before independently reviewing its contents.

## acceptance_criteria

| Criterion | required | result | Evidence or remaining work |
|---|---|---|---|
| Guide enumerates all six language/DPI cases with operator actions and observations | true | PASS | Reviewed guide contains the six cases and step-by-step instructions. |
| Guide requires completed video lifecycle and real downloaded-media evidence for `ko-KR-100` and `en-US-200` | true | PASS | The guide explicitly assigns both lifecycle cases and artifact capture. |
| Guide covers MP3 conversion, settings restart restore, and legacy-settings transition | true | PASS | These representative checks are assigned in the guide. |
| Guide prohibits prefilled PASS and keeps final ZIP behind GUI PASS | true | PASS | The guide states actual observations only and preserves the release HOLD. |
| All six GUI cases and representative checks have actual recorded PASS evidence | true | NOT_VERIFIED | No manual GUI evidence set was present at the last read-only check. |
| The two completed-video cases have downloaded files and result evidence | true | NOT_VERIFIED | The operator has not yet supplied media artifacts. |
| Repository verifier has generated a passing summary and evidence manifest | true | NOT_VERIFIED | `gui-validation-summary.json` and `gui-validation-evidence-manifest.json` were absent at the last check. |
| GitHub-only reviewer can retrieve the exact reviewed guide | true | NOT_VERIFIED | The guide is local and untracked; provide the file or publish it separately. |

## validation

- automated: no application tests or GUI verifier were run for this documentation-only change. A read-only SHA-256 check identified the guide as `4A698685EA410BEC62579748BCD96F529F52A6B855669FAC108E3B969C27EE9F`, 13,123 bytes; the sealed EXE still matched `BEBADE61F980CADA9D338A4C32DF77E0122C18BBF07E4E95E4F056C93008F6CA` at the last check.
- manual: guide text was inspected for the six cases, lifecycle instructions, representative checks, recorder usage, verifier usage, and HOLD wording. The application GUI was not operated in this review.
- ci: `NOT_RUN` for the local guide; existing CI on another commit is not evidence for this review target.
- release_state: the manual evidence directory, GUI summary, GUI evidence manifest, and final ZIP were absent at the last read-only check. Absence is not a PASS for the GUI gate.

## risks

| Severity | Risk | Handling |
|---|---|---|
| High | Required GUI validation remains incomplete; releasing now would bypass the user-mandated gate. | Keep final ZIP, license adjudication, exact-target CI, and release gate on HOLD until GUI contract PASS. |
| High | GitHub-only independent reviewer cannot inspect the local guide. | Provide the exact hashed guide through an accessible, non-rebuilding channel before requesting approval. |
| Medium | Example recorder commands could be copied with a passing result without observation. | Operator must execute each GUI step first and record only observed results and artifacts. |

No application defect is established by these risks. Licensing and final-package checks remain separate downstream gates and are not claimed complete here.

## request

Review the guide against the user's manual GUI evidence directions and the repository's existing evidence contract. Do not infer that a documented procedure is executed evidence. Confirm the reviewed guide's SHA and accessibility before judging its contents. If a GUI defect is found during operator testing, stop and report it rather than altering the sealed candidate.

## brief

One local guide was added to direct manual evidence collection. It covers six GUI combinations, two real video lifecycles, MP3/settings/legacy coverage, and the existing recorder/verifier. The GUI, license, CI, ZIP, and release gates remain unpassed. The guide is not yet available to a GitHub-only reviewer.

## status

`partial_success` - guidance prepared; required GUI evidence and reviewer access are not complete.

## review_verdict

`PENDING` - independent review by a different session or model is required.
