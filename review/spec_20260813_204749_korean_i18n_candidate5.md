# Korean i18n recovery — candidate-5 append-only review package

Capture time: `2026-08-13T20:47:49.6434635Z`.

This is a new append-only package for successor candidate 5. It does not
overwrite the F526 package or its invalidation review. Candidate root:
`C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-5\candidate-55e66fa7d6004a0c84bce001c97d2c4d`.

## Required metadata

- `review_target`: source commit `6fe72b7f2b5240c272f4e4e6244a07c76695645b`, branch `codex/korean-i18n-recovery`, `source_dirty=false`, tree SHA `07D5889D48E55B866698777D5EBD22DDFF7DE8F4E8CABB7C4451B5CFA53D7A27`, candidate manifest SHA `0DBB42E55AC3E400A758D38CE996321775FA2E3215E2B1AACFA6C1592062F68E`.
- `comparison_base`: `2173316ebb5e50af49a2a4e939693fa8c3a3459c`; exact command and 104-path counts are in `review/evidence/final-index-20260813T204749Z-0DBB.json`.
- `changed_files_or_diff`: binary patch `review/evidence/comparison-base-to-final-20260814T193500Z.patch`, SHA-256 `0A683E31236CF28513B90C65F278ADDDF4AFC2324506B91E929EC77025B3E2AF`; source-only diff-check exit 0; full diff-check exit 2 due older review-evidence whitespace diagnostics.
- `reviewer_access_assumption`: another session/model can read this spec, its JSON index, Git history, applicable constitutions, candidate-5 root, smoke run/artifacts, and all cited absolute paths without prior chat state.
- `meta.evidence_package`: `review/evidence/final-index-20260813T204749Z-0DBB.json`.
- `reviewer_required`: `different_session_or_model`.
- `review_package`: `partial`.
- `status`: `partial_success`.

## Constitution and threat model

Applicable constitution files are:

- `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\AGENTS.md`, 10,453 bytes, SHA-256 `4E22E0747C79B2AD9F17F08FE7F083035F3F37C6765DD02E9AAD029DAE2BA322`.
- `C:\Users\ceo\OneDrive\Desktop\01_AllWork\AGENTS.md`, 9,613 bytes, SHA-256 `50407D74E8897E2D4F7413ED089AAFDAD2C7658365804755164141C40A63A66C`.

No `GEMINI.md` or `CLAUDE.md` was found in the repository or stated parent
path; no unsubmitted constitution path is inferred.

The threat boundary covers network/proxy, file I/O, process execution,
deserialization, environment/tool discovery, and local runtime replacement.
Trusted inputs are the comparison-base Git object, reviewed dependency SHA,
validated catalog, and candidate-5 files only after pre/post manifest seal
rechecks. Untrusted inputs include release metadata before hash/version
validation, archive entries before traversal checks, stale paths, translated
captions used as state, arbitrary fixture output, and GUI evidence from a
different candidate. The change expands no auth, secret, token, proxy
credential, permission, eval, SQL, or environment-secret boundary.

## Candidate build and seal evidence

The candidate manifest is 31,011 bytes, mtime
`2026-08-13T20:41:32.9598094Z`, SHA-256
`0DBB42E55AC3E400A758D38CE996321775FA2E3215E2B1AACFA6C1592062F68E`.
It binds commit `6fe72b7...`, `dirty=false`, tree SHA above, and 125 tracked
files.

Build raw log:
`C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\build-candidate-5-20260813T203735Z.raw.log`, 1,222 bytes, SHA-256
`455AD0C6F2F65BFB8D4F794188738D75F240F31D5CC2DA449175552A7887A3CF`, exit 0.
Status JSON SHA-256 is
`AE865F82D6C08E1883AF5510DDE4EB98C575468F9647896BA4F142677E61CB27`.

Pre-smoke recheck JSON SHA-256
`E504021F7ADFE10636481DBE9AC947BE2AE31B96073DBE160825BFF6B69FA3E5` reports
8 entries and `allMatched=true` at `2026-08-13T20:41:53.3031413Z`.
Post-smoke Windows PowerShell 5.1-compatible recheck script SHA-256
`08F5CCDACEDA5D5AFA32BC17D7CB83A4DD2AD90ADB1CF6B2E11DA65BDD73E302` and raw
log SHA-256 `9525E97D9BEDB4DDDE17C1E4E8771627CD4C07C20BA29659754B32C46C7D37`.
The raw output states `ENTRY_COUNT=8`, `ALL_MATCHED=True`,
`Assert-CandidateManifestSeal PASS`, and `EXIT_CODE=0` at
`2026-08-13T20:46:49.0916544Z`.

## Tests and artifact smoke

The source-level native, contract, and PowerShell logs are retained with exact
hashes in the JSON index. The candidate-5 artifact smoke is separate from GUI
causality:

- Run manifest `add8b0130fdd43f2bd020e924ea1e59f`, SHA-256 `F362C55FB7D2B68C8C2749058FF5BC38CB893ED0C467ADAEE4DD5B961D89BE57`, completed `2026-08-13T20:46:32.3907330Z`.
- It binds `candidateManifestSha256=0DBB42...F68E`, `succeeded=true`, `artifactValidated=true`, `cleanupSucceeded=true`, `guiInteractionProven=false`, `operatorAttested=false`.
- MP3 output: 9,328 bytes, SHA-256 `188ACFB52B9592FB2EADEED48B4BFD07BE1FE698B1A9AC8B144974AB5AB7D9D5`.
- Settings overlay: 12,595 bytes, SHA-256 `817FE80902CAFA58EE802E568D249094C6FA40D6FC99F11F915933E201B7292D`.
- FFprobe: 33 bytes, SHA-256 `312A974BFE98206258E69671AE8F50CDAA44C2C1BD1D55BB944A4F5C0ECCC41`, output `codec_name=mp3` and `duration=2.020136`.
- `noPartFiles=true`, duration `2.020136`, cleanup succeeded.
- Raw smoke log SHA-256 `FAD277F43EB76698DCE4994E5EF73561C0DF907FC99F599F3549FC99B245FAB1`, status SHA-256 `43A6915C22C9CD0EAA8FB9230309B9F136EEA808EB41ABDA6DE323CFFDDBE887`, both exit 0.

The first candidate-5 smoke attempt is retained as a failure: it reached
`Valid=true` but failed copying a missing transient path, with log SHA
`00F211819AE3374F07751C3E2DD7FD629C368C7666C41C80D1012DE982DD3965` and
status SHA `B486DF24CE6E15FD055D3E2028561F134C23EF95F528C87D662D0A318FD6FC0B`.
The second run is the successful run cited above; neither failure is hidden.

## GUI and DPI gates

No candidate-5-bound GUI ledger or screenshot set was supplied. The F526 GUI
ledger is excluded because independent review found that F526 was later
mutated (`ytdlp-interface.json` no longer matched its sealed manifest). Thus
candidate-5 has no accepted GUI causal evidence at this snapshot.

Manual Windows display-scale observations at 100%, 150%, and 200% are also
absent. No agent changed Windows display settings. The prior observed 120
logical DPI/125% state cannot prove the requested three tiers.

## Prior F526 invalidation

The prior candidate is preserved as a negative exhibit, not reused as evidence:

- F526 manifest SHA `F5263136E613A81A58B998D00A46732ED793234D6CE127E6FD5C2934DD428057`.
- Independent review path `review/evidence/independent-review-F5263136-20260814T205500Z.md`, SHA-256 `4050CBF8CC3D47817BBDD7DC93DD09A73387B615772772B47F05AFA313B39FF2`.
- Its post-run `ytdlp-interface.json` was 8,478 bytes/SHA
  `3A113AE7CA3AB37219834906D226B60CE595764987549DAA6A3E021F4F80C30C`, while
  the F526 manifest required 12,531 bytes/SHA
  `9D52BD66A45FDA25E257A9D89184C27896A44484412F2B32CD37E99FE3DB9F05`.

Candidate-5 was freshly built and independently rechecked after that
invalidation; no F526 artifact is silently promoted into candidate-5 proof.

## Risks and disposition

1. **High — GUI evidence absent for candidate-5.** `handling=accepted_unresolved`.
2. **High — DPI 100/150/200 absent.** `handling=accepted_unresolved`.
3. **High — independent different-session/model verdict pending.** `handling=plan`.
4. **High — artifact smoke is not GUI causality.** The manifest explicitly says
   `guiInteractionProven=false` and `operatorAttested=false`; `handling=safeguard`.
5. **High — prior F526 mutation.** Preserved as negative evidence; candidate-5
   pre/post seal rechecks are required; `handling=safeguard`.
6. **Medium — post-capture untracked inventory absent.** Existing inventory
   predates candidate-5 evidence; `handling=plan`.
7. **Medium — full diff-check exit 2.** Source-only check exits 0; `handling=safeguard`.

## Final status

This package is an honest `partial_success`. Candidate-5 build, pre/post
manifest seals, source tests, and artifact smoke are materially evidenced.
Candidate-5 GUI, manual DPI tiers, and independent final review remain open.
Accordingly this append-only revision does not claim `success` or
`NOT GUILTY`.

