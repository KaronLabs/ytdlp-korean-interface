# Candidate 5 GUI package audit — append-only 2026-08-13T21:11:04Z

## 판정 스냅샷

- 신고 상태: `partial_success` (자동 무죄 아님)
- review target: candidate-5 manifest SHA `0DBB42E55AC3E400A758D38CE996321775FA2E3215E2B1AACFA6C1592062F68E`
- source: commit `6fe72b7f2b5240c272f4e4e6244a07c76695645b`, dirty `false`, tree `07D5889D48E55B866698777D5EBD22DDFF7DE8F4E8CABB7C4451B5CFA53D7A27`
- 새 spec: `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\review\spec_20260813_210934_korean_i18n_candidate5_gui.md`, 12,569 bytes, SHA `0021D6D4A04D8FF1A748776C6B16ADA98A3FC28E47E61CD0F6A738F19663094A`
- 새 index: `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\review\evidence\final-index-20260813T211104Z-candidate5-gui.json`, 21,724 bytes, SHA `4C178E2194588C4CCFE669151F3D69F935B69FBD0D8552902B606188659A27F8`

기존 `final-index-20260813T204749Z-0DBB.json`, `spec_20260813_204749_korean_i18n_candidate5.md`, `package-audit-20260813T204749Z-0DBB.md` 및 F526 invalidation evidence는 변경하지 않았습니다. 새 파일은 모두 append-only 추가입니다.

## 필수 입력 슬롯 감사

| 슬롯 | 상태 | 물적 증거 |
|---|---|---|
| `meta.changed_files_or_diff` | present | comparison patch SHA `0A683E31236CF28513B90C65F278ADDDF4AFC2324506B91E929EC77025B3E2AF`; exact git command/counts 104 = 75 added + 29 modified |
| `meta.reviewer_access_assumption` | present | 새 index와 spec에 다른 세션/모델의 절대 경로·hash 직접 접근 가정 기재 |
| `meta.evidence_package` | partial | spec/index, constitution, build/recheck, smoke, tests, GUI ledger/screenshots, threat model 포함; open gates는 아래 참조 |
| `review_target` | present | candidate root, source commit/tree, manifest SHA `0DBB…F68E` |
| `comparison_base` | present | base `2173316e…`, head `6fe72b7…`, patch + source-only/full diff logs |
| tests/evidence quotes | present | native/contract/PowerShell logs, candidate seal raw, smoke raw, ffprobe, GUI ledger quote |
| relevant runtime outputs | partial | artifact smoke는 성공했으나 `mode=artifact-only`, `guiInteractionProven=false` |

## Candidate/build/recheck 증거

- Build raw `build-candidate-5-20260813T203735Z.raw.log` SHA `455AD0C6F2F65BFB8D4F794188738D75F240F31D5CC2DA449175552A7887A3CF`, exit 0; status SHA `AE865F82D6C08E1883AF5510DDE4EB98C575468F9647896BA4F142677E61CB27`, exit 0.
- Pre-smoke recheck `candidate-5-recheck-20260813T2042Z.json` SHA `E504021F7ADFE10636481DBE9AC947BE2AE31B96073DBE160825BFF6B69FA3E5`, 8 entries, allMatched true.
- Post-smoke recheck raw `candidate-5-recheck-20260813T2047Z.raw.log` SHA `9525E97D9BEDB4DDDE17C1E4E8771627CD4C07C20BA29659754B32C46C7D37`, exit 0; quote `Assert-CandidateManifestSeal PASS; all declared payload hashes and lengths matched; EXIT_CODE=0` at `2026-08-13T20:46:49.0916544Z`.
- Smoke manifest `C:\Users\ceo\Downloads\ytdlp-interface-smoke-evidence\runs\add8b0130fdd43f2bd020e924ea1e59f.json` SHA `F362C55FB7D2B68C8C2749058FF5BC38CB893ED0C467ADAEE4DD5B961D89BE57`, `succeeded=true`, candidate bound `0DBB…F68E`, artifact-only. MP3 SHA `188ACFB52B9592FB2EADEED48B4BFD07BE1FE698B1A9AC8B144974AB5AB7D9D5`; ffprobe SHA `312A974BFE98206258E69671AE8F50CDAA44C2C1BD1D55BB944A4F5C0ECCC41`, output `codec_name=mp3; duration=2.020136`; no-part true; cleanup true.
- The first smoke attempt (raw SHA `00F211819AE3374F07751C3E2DD7FD629C368C7666C41C80D1012DE982DD3965`, exit 1) remains retained, so failed evidence is not concealed.

## GUI evidence audit

Ledger absolute path: `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\review\evidence\gui-candidate5-20260814T205700Z-ledger.jsonl`.

- bytes 16,462; mtime UTC `2026-08-13T21:07:28.4063639Z`; SHA `819DEC76114254273F2252E8DF1D02F6F4EF4D81D271723E7BB86643929371EA`; 12 physical lines.
- Independent parse result: 9 valid JSON lines, invalid lines 3/7/10. Invalidity is caused by unescaped internal quotes in `visibleResult.menuItems`, `visibleResult.sections`, and `visibleResult.logContains`. The raw ledger hash is valid evidence of the submitted bytes, but those records cannot be treated as machine-parseable structured evidence.
- Candidate binding: all 12 raw records contain manifest SHA `0DBB42E55AC3E400A758D38CE996321775FA2E3215E2B1AACFA6C1592062F68E`.
- Captured states include Korean startup, URL queue, queue context menu (`구간 다운로드`, `형식 선택`, `자막 선택(0/0)`), queue action result, metadata row with info `---`, format child, yt-dlp settings child, sections dialog, Korean equal-start/end validation message, output view with MP3 log mention, negative playlist attempt, and corrected metadata binding.
- Every screenshot reports `externalOverlayPresent=true`; startup has null preObservation. The corrected metadata event is additive and does not erase the earlier metadata line.
- The index records bytes, UTC mtime, and SHA for all 16 screenshot files found by the directory scan. The visual set is candidate-bound but does not prove GUI causality for the artifact smoke.

## Open gates (not silently waived)

1. Manual display DPI captures at 100%, 150%, and 200% are missing.
2. Playlist causal success is missing; the captured `feed.rss` result is negative because an existing queue item blocked it.
3. Subtitle causal success is missing; the only observed selector reports `0/0`.
4. GUI-to-artifact causal binding is missing because smoke declares `mode=artifact-only` and `guiInteractionProven=false`.
5. Three ledger lines are invalid JSON and require a future corrected append-only capture or explicit raw-line adjudication.
6. Post-capture untracked inventory is missing; `untracked-inventory-final-20260814T193500Z.json` SHA `022409B6CF3D2E4617D0EA85CE2C088F5762D44625F0AA56E880C009AF3DB7D3` predates the GUI files.
7. Independent different-session/model final verdict is pending.

## Constitution and threat model

Applicable constitution hashes are repo `AGENTS.md` SHA `4E22E0747C79B2AD9F17F08FE7F083035F3F37C6765DD02E9AAD029DAE2BA322` (10,453 bytes) and parent `AGENTS.md` SHA `50407D74E8897E2D4F7413ED089AAFDAD2C7658365804755164141C40A63A66C` (9,613 bytes). GEMINI/CLAUDE paths were not found and were not inferred. Threat boundaries are network, proxy, file I/O, process execution, deserialization, environment/tool discovery, and local runtime replacement. The candidate seal and direct artifact hashes are trusted checks; network metadata, stale settings, translated captions, arbitrary fixture output, cross-candidate GUI records, and child success without direct exit code remain untrusted. No auth/secret/token/proxy-credential/permission/eval/SQL/environment-secret boundary is expanded.

## Conclusion for the next court session

The package is materially stronger than the prior candidate-5 package because it supplies a candidate-bound GUI ledger and screenshot hash inventory, but it remains `partial_success`. A different session/model must issue the final verdict. The correct conservative reading is: build, candidate seal, unit/contract/runtime logs, and artifact smoke are evidenced; GUI localization states are partially evidenced; DPI, playlist/subtitle causal paths, GUI causality, post-capture inventory, parseability of three ledger lines, and independent review remain open. No NOT GUILTY claim is authorized by this artifact alone.
