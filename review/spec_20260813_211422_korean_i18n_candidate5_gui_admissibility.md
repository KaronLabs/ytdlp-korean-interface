# Candidate 5 GUI admissibility correction — append-only v3

사건 식별자: `2026-C5-GUI-20260813T211422Z`  
상태: `partial_success` 입력, 독립 검토 판정 `GUILTY`, `NOT GUILTY` 자격 `false`.

이 문서는 기존 candidate-5 v1/v2 index/spec/audit를 덮어쓰지 않는 append-only successor입니다. 새 독립 검토가 발견한 실행 사본 seal 불일치와 새 테스트 raw log를 결박합니다. 이전 v2의 PowerShell JSON parse 경고는 독립 검토의 strict UTF-8/Python 표준 JSON parse 결과로 정정합니다. 즉, ledger의 12개 raw record는 parseable로 취급하되, 그 사실이 GUI causal admissibility를 회복시키지는 않습니다.

## 1. 필수 입력 슬롯

- `review_target`: sealed candidate root `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-5\candidate-55e66fa7d6004a0c84bce001c97d2c4d`; manifest SHA `0DBB42E55AC3E400A758D38CE996321775FA2E3215E2B1AACFA6C1592062F68E`; source commit `6fe72b7f2b5240c272f4e4e6244a07c76695645b`, tree SHA `07D5889D48E55B866698777D5EBD22DDFF7DE8F4E8CABB7C4451B5CFA53D7A27`, dirty `false`.
- `comparison_base`: `2173316ebb5e50af49a2a4e939693fa8c3a3459c..6fe72b7f2b5240c272f4e4e6244a07c76695645b`; command `git diff --name-status 2173316ebb5e50af49a2a4e939693fa8c3a3459c..6fe72b7f2b5240c272f4e4e6244a07c76695645b`; counts 104 total / 75 added / 29 modified / 0 deleted / 0 renamed.
- `reviewer_access_assumption`: 다른 세션/모델이 이 spec, v3 index/audit, independent review, candidate root, GUI execution-copy root, raw logs, smoke artifacts, constitution files와 absolute screenshot paths를 직접 읽을 수 있어야 합니다. 이전 chat summary는 증거가 아닙니다.
- `meta.changed_files_or_diff`: comparison patch `comparison-base-to-final-20260814T193500Z.patch`, SHA `0A683E31236CF28513B90C65F278ADDDF4AFC2324506B91E929EC77025B3E2AF`; source-only check `diff-check-source-final-20260814T194000Z.log`, SHA `826A225B81E70E3DD792CD8D4983AC735B453DF6DA16ECA4505E42AEBA225F82`, exit 0; full check SHA `6A470CFA4ECAB42D69ACF4EE441FC517EDE6564BCA1DC0CBE1AA9C31667C2793`, exit 2 with old review-evidence whitespace diagnostics.
- `meta.evidence_package`: this spec, v3 index/audit, v2 index/spec/audit, candidate manifest and seal rechecks, build/test/smoke raw outputs, candidate-bound GUI ledger/screenshots, independent review, execution-copy mismatch, constitution hashes, diff/inventory records, and threat model.

## 2. Constitution and threat model

Applicable paths and hashes:

| path | bytes | SHA-256 |
|---|---:|---|
| `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\AGENTS.md` | 10453 | `4E22E0747C79B2AD9F17F08FE7F083035F3F37C6765DD02E9AAD029DAE2BA322` |
| `C:\Users\ceo\OneDrive\Desktop\01_AllWork\AGENTS.md` | 9613 | `50407D74E8897E2D4F7413ED089AAFDAD2C7658365804755164141C40A63A66C` |

GEMINI.md/CLAUDE.md는 repository와 명시된 부모에서 발견되지 않아 경로를 추정하지 않았습니다. Threat boundaries는 `network`, `proxy`, `file_io`, `process_exec`, `deserialize`, 환경/tool discovery, local runtime replacement입니다. 후보 manifest는 pre/post direct hash 검증 뒤 trusted이고, GUI execution copy는 아래 mismatch 때문에 untrusted입니다. 네트워크 metadata, stale settings, translated captions, arbitrary fixture output, cross-candidate GUI state, child success without direct exit code도 untrusted입니다. auth/secret/token/proxy credential/permission/eval/SQL/environment-secret boundary 확장은 없습니다.

## 3. Candidate seal/build/smoke evidence

- Candidate manifest: `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-5\candidate-55e66fa7d6004a0c84bce001c97d2c4d\candidate-manifest.json`, 31,011 bytes, SHA `0DBB42E55AC3E400A758D38CE996321775FA2E3215E2B1AACFA6C1592062F68E`, mtime `2026-08-13T20:41:32.9598094Z`.
- Build raw `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\build-candidate-5-20260813T203735Z.raw.log`, SHA `455AD0C6F2F65BFB8D4F794188738D75F240F31D5CC2DA449175552A7887A3CF`, exit 0; status SHA `AE865F82D6C08E1883AF5510DDE4EB98C575468F9647896BA4F142677E61CB27`, exit 0.
- Pre-smoke recheck `candidate-5-recheck-20260813T2042Z.json`, SHA `E504021F7ADFE10636481DBE9AC947BE2AE31B96073DBE160825BFF6B69FA3E5`, 8 entries, all matched. Post-smoke raw `candidate-5-recheck-20260813T2047Z.raw.log`, SHA `9525E97D9BEDB4DDDE17C1E4E8771627CD4C07C20BA29659754B32C46C7D37`, exit 0; quote `Assert-CandidateManifestSeal PASS; all declared payload hashes and lengths matched; EXIT_CODE=0` at `2026-08-13T20:46:49.0916544Z`.
- Artifact smoke manifest `C:\Users\ceo\Downloads\ytdlp-interface-smoke-evidence\runs\add8b0130fdd43f2bd020e924ea1e59f.json`, SHA `F362C55FB7D2B68C8C2749058FF5BC38CB893ED0C467ADAEE4DD5B961D89BE57`, `succeeded=true`, `mode=artifact-only`, candidate bound `0DBB...F68E`, `guiInteractionProven=false`, `operatorAttested=false`, cleanup true. MP3 SHA `188ACFB52B9592FB2EADEED48B4BFD07BE1FE698B1A9AC8B144974AB5AB7D9D5`; ffprobe SHA `312A974BFE98206258E69671AE8F50CDAA44C2C1BD1D55BB944A4F5C0ECCC41`, `codec_name=mp3; duration=2.020136`; no part files.
- Successful smoke raw SHA `FAD277F43EB76698DCE4994E5EF73561C0DF907FC99F599F3549FC99B245FAB1`, exit 0, quote `Valid=true; ReasonCode=ok; Duration=2.020136`; retained first failed attempt SHA `00F211819AE3374F07751C3E2DD7FD629C368C7666C41C80D1012DE982DD3965`, exit 1.

## 4. New test raw evidence

`C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\review\evidence\tests-candidate5-20260814T211500Z.raw.log` is 2,507 bytes, mtime `2026-08-13T21:11:39.0035238Z`, SHA `9EEA86591AD94EC2E6A971EF2A751705FDA824AE5568D3CF23C1653A032149EC`. It records:

```
START_UTC=2026-08-13T21:11:26.7837143Z
COMMAND=powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\tests\run_powershell_tests.ps1
runtime-maintenance tests passed
PASS runtime-maintenance.Tests.ps1
smoke-localhost fixture tests passed.
PASS smoke-localhost.Tests.ps1
END_UTC=2026-08-13T21:11:38.9981675Z
EXIT_CODE=0
```

The raw stream contains UTF-16/NUL-rendered portions; the SHA and command/output/timestamps above are retained as the evidence object. This test result does not cure GUI execution-copy seal failure.

## 5. GUI ledger and decisive admissibility ruling

Ledger path `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\review\evidence\gui-candidate5-20260814T205700Z-ledger.jsonl`: 16,462 bytes, 12 records, mtime `2026-08-13T21:07:28.4063639Z`, SHA `819DEC76114254273F2252E8DF1D02F6F4EF4D81D271723E7BB86643929371EA`. The independent review parsed all 12 records as strict UTF-8 JSON and independently recomputed 15 referenced JPEG hashes; line 5’s `UNRECORDED_PREVIOUS_SCREENSHOT` placeholder is corrected only by additive line 12, whose `queue-action-started.jpg` SHA is `876CEF678A21F01129B6E8970AA2565997E53E66EB9C0DE89C036803754437AE`. All records state candidate manifest SHA `0DBB...F68E`; all state `externalOverlayPresent=true`.

**GUI admissibility:** `inadmissible_for_sealed_candidate_causality=true`. The ledger’s process path is `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-gui-candidate5-20260814T000002Z\ytdlp-interface.exe`, an execution copy distinct from the sealed candidate root. Independent review `independent-review-candidate5-gui-20260813T211049Z.md` (7,685 bytes, mtime `2026-08-13T21:11:17.4576047Z`, SHA `CA0D2D4698EA3FA71BE4DEE93644DD437849EDFF4803C82D67C37021721E1C3E`) records the decisive mismatch:

| payload | sealed manifest requirement | execution copy observed |
|---|---|---|
| `ytdlp-interface.json` | 12,531 bytes; SHA `9D52BD66A45FDA25E257A9D89184C27896A44484412F2B32CD37E99FE3DB9F05` | 8,404 bytes; SHA `6C9FE18BCB17588FF8938385050394E8D839851D39108EFB716F2689BED1008C` |

The other seven declared payloads match, but one mismatch is sufficient to reject the GUI run as strict candidate-5 execution evidence. The execution-copy candidate manifest itself hashes to `0DBB...F68E`, but that does not transfer seal validity to its mutated payload. GUI images remain admissible only as diagnostic observations of an unsealed copy, not as proof of candidate behavior, artifact causality, or NOT GUILTY.

The independent review also classifies playlist and subtitle paths as negative/unproven (`playlist` blocked by existing queue; subtitle `0/0`), reports overlay in material upper-center regions, and finds no manual 100/150/200 DPI evidence, no fresh sealed GUI-to-MP3 chain, and no post-capture inventory.

## 6. Risks, open slots, and finality

1. GUI causal proof: failed / inadmissible due execution-copy settings mismatch.
2. Artifact smoke: successful but artifact-only; GUI causality absent.
3. Manual DPI 100%, 150%, 200%: missing.
4. Playlist causal success: missing; captured path is negative.
5. Subtitle causal success: missing; only `0/0` observed.
6. Overlay-free capture: missing; all 12 records report overlay present.
7. Post-capture untracked inventory: missing; old inventory predates GUI capture.
8. Independent reviewer: now present; independent verdict is GUILTY and NOT GUILTY remains ineligible.
9. Append-only recheck: any cure must use a new sealed execution copy, new ledger, new inventory and new spec; v1/v2 files remain frozen.

The package therefore remains `partial_success` as the submitted status, but the independent final verdict for the current submission is `GUILTY` on GUI causality/verification grounds. No success or NOT GUILTY claim is supported.
