# Korean i18n recovery — candidate 22A481 append-only package

This spec is an append-only package snapshot created at
`2026-08-13T19:57:21.9374706Z`. It is bound to candidate manifest SHA
`22A481CD04F3C90D5FD7717C8085B49D7667F0245906F1B58E9EB330AFA36F6C` and
source commit `6fe72b7f2b5240c272f4e4e6244a07c76695645b`. It supersedes no
earlier file and makes no retrospective change to the original submission.

## Required metadata

- `review_target`: source commit `6fe72b7f2b5240c272f4e4e6244a07c76695645b`, branch `codex/korean-i18n-recovery`, `source.dirty=false`, tree SHA `53AD3690BEACCF9A3C4C9F9CE2D27DA199EAD42849F686FFFEF14F5DA28F4B15`.
- `comparison_base`: `2173316ebb5e50af49a2a4e939693fa8c3a3459c`.
- `changed_files_or_diff`: `git diff --name-status 2173316ebb5e50af49a2e939693fa8c3a3459c..6fe72b7f2b5240c272f4e4e6244a07c76695645b` (104 paths: 75 added, 29 modified, 0 deleted, 0 renamed); binary patch `review/evidence/comparison-base-to-final-20260814T193500Z.patch`, 2,750,358 bytes, SHA-256 `0A683E31236CF28513B90C65F278ADDDF4AFC2324506B91E929EC77025B3E2AF`.
- `reviewer_access_assumption`: a different session/model can read this spec, the companion JSON index, repository Git history, applicable constitution files, candidate root, and all absolute evidence paths; no prior chat state is required.
- `reviewer_required`: `different_session_or_model`.
- `evidence_package`: complete inventory/index is `review/evidence/final-index-20260813T195721Z-22A481.json`; the exact-hash audit is `review/evidence/package-audit-20260813T195721Z.md`.
- `review_package`: `partial`; required slots are present as named fields, but GUI/DPI/smoke/independent-verdict gates remain open.
- `status`: `partial_success`.

## Constitution documents

The repository constitution is
`C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\AGENTS.md`
(10,453 bytes, SHA-256
`4E22E0747C79B2AD9F17F08FE7F083035F3F37C6765DD02E9AAD029DAE2BA322`). Its
inherited parent is
`C:\Users\ceo\OneDrive\Desktop\01_AllWork\AGENTS.md` (9,613 bytes, SHA-256
`50407D74E8897E2D4F7413ED089AAFDAD2C7658365804755164141C40A63A66C`). No
`GEMINI.md` or `CLAUDE.md` was found in those stated paths; no unsubmitted
constitution path is inferred.

## Evidence quotes

The following are raw outputs, not author summaries:

- `review/evidence/native-final-20260814T194000Z.log`: `BUILD_EXIT=0`, `TEST_EXIT=0`; SHA-256 `DB10640B6DA697AD57A0AC4D7BDE9ACC2264632A01620F94AD00726AE021E742`; end `2026-08-13T19:36:31.9982868Z`.
- `review/evidence/contract-final-20260814T194000Z.log`: `Ran 20 tests in 8.161s`, `OK`, `EXIT_CODE=0`; SHA-256 `7D7C1762CA8B9F2B5419CD89B92144FE0F463451C200F36D7E7A9DC120403950`; end `2026-08-13T19:36:47.4796649Z`.
- `review/evidence/powershell-final-20260814T194000Z.log`: `runtime-maintenance tests passed`, `smoke-localhost fixture tests passed`, `EXIT_CODE=0`; SHA-256 `711CFFF45BBED6A07BA6C00EE23B1C2E1E0697121523E43055A9493A49FCEA01`; end `2026-08-13T19:37:09.7837257Z`.
- `review/evidence/build-candidate-final-20260814T193500Z.log`: candidate root returned and `EXIT_CODE=0`; SHA-256 `07E2023621F0CC63DA4A43CDBEC82BB70C88F3F9C7927D754C2CD905BC345D05`; end `2026-08-13T19:33:35.3862005Z`.
- `review/evidence/candidate-recheck-final-20260814T193500Z.json`: 8/8 manifest entries match; `allMatched=true`; SHA-256 `A42CE7F675921CA44F7A383AF0324A3142B409EA46FDC61ED5A910B21A01EFCF`; checked `2026-08-13T19:36:08.5142934Z`.

## Threat model

The change crosses network, proxy, file-I/O, process-execution,
deserialization, environment/tool discovery, and local runtime-replacement
boundaries. Trusted inputs are the comparison-base Git object, reviewed
dependency archive hash, validated catalog, and candidate binaries only after
manifest/hash/version recheck. Untrusted inputs include network metadata before
hash/version verification, archive entries before traversal checks, stale
settings paths, translated captions used as program state, arbitrary fixture
output, and child success before direct exit-code inspection. The subtitle
fallback change does not expand auth, secret, token, proxy-credential, or
permission access; localhost fixtures remain isolated.

## Risks and handling

1. **High — GUI causal matrix incomplete.** The current ledger has three
   candidate-bound records at capture; startup is visible, but metadata/format,
   settings, playlist, subtitle, sections, output, message-box, and complete
   URL→MP3 flow are not proven. `handling=accepted_unresolved`.
2. **High — DPI tiers absent.** No current-candidate 100%, 150%, and 200%
   observations are bound to this package. `handling=accepted_unresolved`.
3. **High — candidate-bound operator smoke absent.** Existing 78E1/090160
   artifacts are excluded; new MP3/settings/FFprobe/no-part outputs bound to
   22A481 are required. `handling=plan`.
4. **High — independent verdict pending.** The old `gpt-5.6-terra` review is
   bound to an earlier candidate and cannot serve as this package's final
   reviewer. `handling=plan`.
5. **Medium — full diff-check exit 2.** The source-only check exits 0; the
   full check reports whitespace in old review evidence. `handling=safeguard`.
6. **Medium — external overlay and ledger inconsistency.** The first GUI
   record says overlay false, later records say overlay true. Treat current
   screenshots as overlay-present unless a later independent ledger proves
   otherwise. `handling=safeguard`.

## Disposition

This is an honest `partial_success` evidence package. The native, contract,
PowerShell, candidate-seal, and source-only diff gates are evidenced. The GUI,
DPI, candidate-bound artifact smoke, and different-session/model review gates
are not. Consequently this package must not be labeled `success` or
`NOT GUILTY`; it is a handoff for a later append-only package after those gates
are actually executed.

