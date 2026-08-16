# Candidate 5 Korean i18n recovery review specification — GUI evidence append-only v2

사건 식별자: `2026-C5-GUI-20260813T210934Z`

이 문서는 후보 5(`candidate-55e66fa7d6004a0c84bce001c97d2c4d`)에만 결박된 새 append-only 검증 패키지입니다. 기존 후보 5 index/spec/audit와 F526 산출물은 덮어쓰지 않으며, F526 GUI 자료는 후보 5 증거로 재사용하지 않습니다. 신고 상태는 `partial_success`입니다. 이 문서 자체는 작성자 진술이 아니라 아래의 절대 경로, 명령, 원시 출력, SHA-256으로 재현 가능한 검증 지시서입니다.

## 1. 입력 슬롯과 판정 경계

- `review_target`: 후보 5 manifest SHA `0DBB42E55AC3E400A758D38CE996321775FA2E3215E2B1AACFA6C1592062F68E`, source commit `6fe72b7f2b5240c272f4e4e6244a07c76695645b`, tree SHA `07D5889D48E55B866698777D5EBD22DDFF7DE8F4E8CABB7C4451B5CFA53D7A27`, dirty `false`.
- `comparison_base`: `2173316ebb5e50af49a2a4e939693fa8c3a3459c..6fe72b7f2b5240c272f4e4e6244a07c76695645b`; exact command is `git diff --name-status 2173316ebb5e50af49a2a4e939693fa8c3a3459c..6fe72b7f2b5240c272f4e4e6244a07c76695645b`; 104 files (75 added, 29 modified, 0 deleted, 0 renamed).
- `reviewer_access_assumption`: 다른 세션/모델은 이 spec, 새 index/audit, Git history, 적용 가능한 AGENTS.md, 후보 5 root, 모든 raw log와 GUI 파일을 직접 읽을 수 있어야 하며 이전 채팅 상태를 신뢰하지 않습니다.
- `meta.evidence_package`: 아래의 spec 전문, diff/변경 목록, 테스트 로그와 evidence quotes, runtime artifact와 GUI ledger를 함께 읽는 것을 전제로 합니다.
- `reviewer_required`: `different_session_or_model`; 이 문서에는 독립 최종 verdict를 사칭하지 않습니다.

## 2. 헌법 문서와 diff 증거

적용 가능한 헌법은 다음 두 파일입니다.

| 경로 | bytes | SHA-256 |
|---|---:|---|
| `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\AGENTS.md` | 10453 | `4E22E0747C79B2AD9F17F08FE7F083035F3F37C6765DD02E9AAD029DAE2BA322` |
| `C:\Users\ceo\OneDrive\Desktop\01_AllWork\AGENTS.md` | 9613 | `50407D74E8897E2D4F7413ED089AAFDAD2C7658365804755164141C40A63A66C` |

저장된 비교 patch는 `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\review\evidence\comparison-base-to-final-20260814T193500Z.patch` (2,750,358 bytes, SHA `0A683E31236CF28513B90C65F278ADDDF4AFC2324506B91E929EC77025B3E2AF`)입니다. source-only diff check는 `diff-check-source-final-20260814T194000Z.log` (SHA `826A225B81E70E3DD792CD8D4983AC735B453DF6DA16ECA4505E42AEBA225F82`, exit 0)입니다. 전체 diff check `diff-check-final-20260814T194000Z.log` (SHA `6A470CFA4ECAB42D69ACF4EE441FC517EDE6564BCA1DC0CBE1AA9C31667C2793`)는 과거 review evidence patch whitespace 진단으로 exit 2였으므로 성공으로 둔갑시키지 않습니다. 기존 untracked inventory `untracked-inventory-final-20260814T193500Z.json` (SHA `022409B6CF3D2E4617D0EA85CE2C088F5762D44625F0AA56E880C009AF3DB7D3`)는 후보 5 GUI 캡처보다 이르므로 사후 inventory 슬롯을 충족하지 못합니다.

GEMINI.md/CLAUDE.md는 저장소와 명시된 부모 경로에서 발견되지 않았습니다. 제출되지 않은 헌법 경로는 추정하지 않습니다.

## 3. 후보 5 build·seal·artifact smoke

- Candidate manifest: `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-5\candidate-55e66fa7d6004a0c84bce001c97d2c4d\candidate-manifest.json`, 31,011 bytes, mtime `2026-08-13T20:41:32.9598094Z`, SHA `0DBB42E55AC3E400A758D38CE996321775FA2E3215E2B1AACFA6C1592062F68E`.
- Build raw: `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\build-candidate-5-20260813T203735Z.raw.log`, SHA `455AD0C6F2F65BFB8D4F794188738D75F240F31D5CC2DA449175552A7887A3CF`, exit 0. Status JSON SHA `AE865F82D6C08E1883AF5510DDE4EB98C575468F9647896BA4F142677E61CB27`, exit 0. Raw quote: `SOURCE_HEAD=6fe72b7f2b5240c272f4e4e6244a07c76695645b; SOURCE_STATUS=; EXIT_CODE=0`.
- Pre-smoke recheck JSON `candidate-5-recheck-20260813T2042Z.json`, SHA `E504021F7ADFE10636481DBE9AC947BE2AE31B96073DBE160825BFF6B69FA3E5`, entry count 8, allMatched true.
- Post-smoke recheck raw `candidate-5-recheck-20260813T2047Z.raw.log`, SHA `9525E97D9BEDB4DDDE17C1E4E8771627CD4C07C20BA29659754B32C46C7D37`, exit 0. Script SHA `08F5CCDACEDA5D5AFA32BC17D7CB83A4DD2AD90ADB1CF6B2E11DA65BDD73E302`. Raw quote at `2026-08-13T20:46:49.0916544Z`: `MANIFEST_SHA256=0DBB42...; ENTRY_COUNT=8; ALL_MATCHED=True; Assert-CandidateManifestSeal PASS; EXIT_CODE=0`.
- Artifact smoke run `add8b0130fdd43f2bd020e924ea1e59f` manifest `C:\Users\ceo\Downloads\ytdlp-interface-smoke-evidence\runs\add8b0130fdd43f2bd020e924ea1e59f.json`, 1,766 bytes, SHA `F362C55FB7D2B68C8C2749058FF5BC38CB893ED0C467ADAEE4DD5B961D89BE57`, completed `2026-08-13T20:46:32.3907330Z`, `succeeded=true`, `mode=artifact-only`, bound manifest `0DBB...F68E`, `guiInteractionProven=false`, `operatorAttested=false`, cleanup true.
- Artifact outputs: `output.mp3` 9,328 bytes SHA `188ACFB52B9592FB2EADEED48B4BFD07BE1FE698B1A9AC8B144974AB5AB7D9D5`; settings JSON 12,595 bytes SHA `817FE80902CAFA58EE802E568D249094C6FA40D6FC99F11F915933E201B7292D`; ffprobe 33 bytes SHA `312A974BFE98206258E69671AE8F50CDAA44C2C1BD1D55BB944A4F5C0ECCC41`, output `codec_name=mp3; duration=2.020136`; no part files.
- Smoke raw `artifact-smoke-candidate5-20260813T205500Z.log` SHA `FAD277F43EB76698DCE4994E5EF73561C0DF907FC99F599F3549FC99B245FAB1`, exit 0, quote `Valid=true; ReasonCode=ok; Duration=2.020136`. The first transient failed attempt remains retained (`artifact-smoke-candidate5-20260813T205000Z.log`, SHA `00F211819AE3374F07751C3E2DD7FD629C368C7666C41C80D1012DE982DD3965`, exit 1) and is not hidden.

## 4. GUI ledger audit (candidate-bound)

Ledger: `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\review\evidence\gui-candidate5-20260814T205700Z-ledger.jsonl`; 16,462 bytes; mtime `2026-08-13T21:07:28.4063639Z`; SHA `819DEC76114254273F2252E8DF1D02F6F4EF4D81D271723E7BB86643929371EA`; 12 physical lines. Every line carries candidate manifest SHA `0DBB42...F68E`.

Independent `ConvertFrom-Json` parsing found 9 valid lines and 3 invalid lines (3, 7, 10). Lines 3, 7 and 10 contain unescaped double quotes inside `visibleResult.menuItems`, `visibleResult.sections`, and `visibleResult.logContains`; therefore the ledger hash and raw text are evidence, but those three records are not machine-parseable JSON evidence. The corrected line 12 is retained as an additional `metadata-outcome-corrected-binding` record and does not erase line 5.

Candidate-bound event claims (all screenshots report `externalOverlayPresent=true`):

1. `startup` at `2026-08-13T20:55:58.662Z`: Korean main window visible; post `...-startup.jpg` SHA `EBEA2C96...91E57`; initial `preObservation` is null.
2. `url-entry` at `20:57:59.255Z`: `http://127.0.0.1:60321/input.mp4` visible and queue row entered; post `...-url-entry.jpg` SHA `02AC02FF...E70CA`.
3. `queue-context-menu` at `20:58:46.698Z`: Korean context menu visible; `구간 다운로드`, `형식 선택`, `자막 선택(0/0)` observed; post `...-queue-context.jpg` SHA `9573E5F9...CEE25`; record is one of the invalid JSON lines.
4. `queue-action-result` at `20:59:02.613Z`: queue cleared; no metadata success claimed; post `...-queue-action-result.jpg` SHA `68023F5B...25F6E`.
5. `metadata-outcome` at `20:59:38.248Z`: row says completed/완료 but info remains `---`; post `...-metadata-outcome.jpg` SHA `8B0DCC26...A8ACE`.
6. `format-dialog` at `21:00:04.850Z`: localized format child with mp4 row; post `...-format-dialog.jpg` SHA `D9F1B164...593BCB`.
7. `settings-ytdlp` at `21:00:41.982Z`: Korean settings child and yt-dlp section visible; post `...-settings-ytdlp.jpg` SHA `AD04525D...D6319C`; record is one of the invalid JSON lines.
8. `sections-dialog` at `21:02:47.020Z`: sections dialog visible; post `...-sections-dialog.jpg` SHA `2D9C14EC...161D4F`.
9. `localized-message-box` at `21:04:43.425Z`: Korean validation message “시작과 종료 시점이 같습니다”; post `...-message-box.jpg` SHA `75AF4535...2A0FD9`.
10. `output-view` at `21:05:33.308Z`: Korean GUI output log visibly mentions MP3 extraction/download; post `...-output-view.jpg` SHA `5A166B1D...2557A6`; record is one of the invalid JSON lines.
11. `playlist-availability-result` at `21:06:56.547Z`: `feed.rss` attempt was blocked by the existing queue row; no playlist success is claimed; post `...-playlist-input-result.jpg` SHA `B04586CC...B1BF3B`.
12. `metadata-outcome-corrected-binding` at `21:07:28.415Z`: rebinds the metadata screenshot to its actual SHA `8B0DCC26...A8ACE`; it does not add metadata contents beyond `---`.

The full index lists each pre/post screenshot path, bytes, mtime, and SHA. The screenshot set is candidate-bound by event metadata but is not a proof that the artifact smoke was caused by the GUI: the smoke manifest explicitly says `mode=artifact-only` and `guiInteractionProven=false`.

## 5. Tests and evidence quotes

- Native log `native-final-20260814T194000Z.log`, SHA `DB10640B6DA697AD57A0AC4D7BDE9ACC2264632A01620F94AD00726AE021E742`, quote `BUILD_EXIT=0; TEST_EXIT=0`.
- Contract log `contract-final-20260814T194000Z.log`, SHA `7D7C1762CA8B9F2B5419CD89B92144FE0F463451C200F36D7E7A9DC120403950`, quote `Ran 20 tests in 8.161s; OK; EXIT_CODE=0`.
- PowerShell log `powershell-final-20260814T194000Z.log`, SHA `711CFFF45BBED6A07BA6C00EE23B1C2E1E0697121523E43055A9493A49FCEA01`, quote `runtime-maintenance tests passed; smoke-localhost fixture tests passed; EXIT_CODE=0`.
- GUI evidence quote: ledger line 9 raw record at `2026-08-13T21:04:43.425Z` binds the localized validation message screenshot SHA `75AF4535E0C21E0C82ADF280BD2F4DC2E26C4171626AE96F8A5FB786D02A0FD9`.
- Artifact evidence quote: smoke raw at `2026-08-13T20:46:32.5435154Z` says `Valid=true; ReasonCode=ok; Duration=2.020136`; ffprobe says `codec_name=mp3; duration=2.020136`.

## 6. Threat model

Trust boundaries are `network`, `proxy`, `file_io`, `process_exec`, `deserialize`, environment/tool discovery, and local runtime replacement. Trusted only after direct checks: comparison-base Git object, dependency archive SHA, validated catalog, candidate after pre/post seal recheck, and artifacts after direct SHA/FFprobe checks. Untrusted inputs include network metadata before verification, archive entries before traversal checks, stale settings paths, translated captions as state, arbitrary fixture output, GUI evidence from another candidate, and child success without direct exit code. The change expands no auth/secret/token/proxy-credential/permission/eval/SQL/environment-secret boundary; localhost smoke is isolated. GUI overlay visibility and lack of manual DPI coverage remain operational review risks, not silently waived security assumptions.

## 7. Open gates and declared risks

The package remains `partial_success` and `not_guilty_eligible=false` until all of the following are independently closed:

1. Manual DPI observations at 100%, 150%, and 200% are absent.
2. Playlist causal success is absent; the captured result is explicitly negative because an existing queue row blocked `feed.rss`.
3. Subtitle causal success is absent; the context menu reports `자막 선택(0/0)`.
4. GUI-to-artifact causal binding is absent; artifact smoke is artifact-only and reports `guiInteractionProven=false`.
5. Three ledger records are not valid JSON due unescaped internal quotes; raw hashes are preserved but parser-based re-review must account for this.
6. Post-capture untracked-file inventory is absent; the existing inventory predates these GUI files.
7. Different-session/model final verdict is pending.
8. Codex overlay is visible in all GUI captures (`externalOverlayPresent=true`), limiting unobscured visual claims.

Risk handling is explicit: GUI/DPI/causal/inventory/reviewer gaps are `accepted_unresolved` or `plan`; the artifact smoke and candidate recheck are safeguards; the earlier F526 mutation is retained as a separate invalidated candidate and no evidence is cross-bound.

## 8. Required independent recheck

The next reviewer must read this spec and the new index/audit, recalculate the ledger and screenshot hashes, parse each JSONL line (recording the 3 invalid lines), execute the candidate-5 post-smoke recheck or inspect its raw output, verify the smoke manifest's candidate SHA and `guiInteractionProven=false`, and issue a fresh verdict in a new append-only spec. A `success` or `NOT GUILTY` claim before closing the seven gates above is not supported by this package.
