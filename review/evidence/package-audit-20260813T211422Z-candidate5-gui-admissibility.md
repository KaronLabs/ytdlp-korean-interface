# Candidate 5 GUI admissibility package audit — append-only v3

## 사건 스냅샷

- 신고 status: `partial_success`.
- 독립 final verdict: `GUILTY`; `NOT GUILTY` eligible `false`.
- Candidate manifest: `0DBB42E55AC3E400A758D38CE996321775FA2E3215E2B1AACFA6C1592062F68E`.
- New spec: `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\review\spec_20260813_211422_korean_i18n_candidate5_gui_admissibility.md`, SHA `98AA5740220038580C7432E8ACAC658F3A985EF1A4EDA331190A86D27ECB4FE7`.
- New index: `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\review\evidence\final-index-20260813T211422Z-candidate5-gui-admissibility.json`, SHA `742AF6893BA24DA750F4757A6183C0678C73EDE8EEC52E0C7B963B85F1AD01FB`.
- Existing v1/v2 index/spec/audit and F526 invalidation records are preserved; this v3 only appends new files.

## 결정적 GUI inadmissibility

GUI ledger `gui-candidate5-20260814T205700Z-ledger.jsonl` is 16,462 bytes, 12 lines, mtime `2026-08-13T21:07:28.4063639Z`, SHA `819DEC76114254273F2252E8DF1D02F6F4EF4D81D271723E7BB86643929371EA`. Independent review parsed the 12 records as strict UTF-8 JSON and recomputed 15 referenced JPEG hashes; line 5’s placeholder is corrected only by additive line 12. All records carry candidate manifest SHA `0DBB…F68E`, but the GUI process path is a distinct execution copy:

`C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-gui-candidate5-20260814T000002Z\ytdlp-interface.exe`

The independent review file `independent-review-candidate5-gui-20260813T211049Z.md` (7,685 bytes, SHA `CA0D2D4698EA3FA71BE4DEE93644DD437849EDFF4803C82D67C37021721E1C3E`) proves the execution-copy mismatch:

| payload | manifest | execution copy |
|---|---|---|
| `ytdlp-interface.json` | 12,531 bytes; `9D52BD66A45FDA25E257A9D89184C27896A44484412F2B32CD37E99FE3DB9F05` | 8,404 bytes; `6C9FE18BCB17588FF8938385050394E8D839851D39108EFB716F2689BED1008C` |

The other seven payloads match, but one mismatch is sufficient. Therefore `inadmissible_for_sealed_candidate_causality=true`: GUI screenshots may be retained as diagnostic observations of an unsealed copy, but they cannot prove sealed-candidate behavior, GUI-to-artifact causality, or innocence. All captures also report `externalOverlayPresent=true`.

The prior v2 note saying PowerShell `ConvertFrom-Json` rejected lines 3/7/10 is superseded by the independent strict UTF-8/Python parse result. This correction changes parseability only; it does not change the decisive execution-copy mismatch.

## New raw test evidence

`tests-candidate5-20260814T211500Z.raw.log` is 2,507 bytes, mtime `2026-08-13T21:11:39.0035238Z`, SHA `9EEA86591AD94EC2E6A971EF2A751705FDA824AE5568D3CF23C1653A032149EC`. The command and output are:

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

The stream includes UTF-16/NUL-rendered sections; raw bytes and SHA remain the evidence object. Passing tests do not repair the GUI seal mismatch.

## Candidate, build, smoke and diff checks

- Candidate root is dirty false, source commit `6fe72b7f2b5240c272f4e4e6244a07c76695645b`, tree `07D5889D48E55B866698777D5EBD22DDFF7DE8F4E8CABB7C4451B5CFA53D7A27`, manifest 31,011 bytes SHA `0DBB…F68E`.
- Build raw SHA `455AD0C6F2F65BFB8D4F794188738D75F240F31D5CC2DA449175552A7887A3CF`, status SHA `AE865F82D6C08E1883AF5510DDE4EB98C575468F9647896BA4F142677E61CB27`, exit 0.
- Pre-smoke recheck SHA `E504021F7ADFE10636481DBE9AC947BE2AE31B96073DBE160825BFF6B69FA3E5`, 8/8 matched. Post-smoke raw SHA `9525E97D9BEDB4DDDE17C1E4E8771627CD4C07C20BA29659754B32C46C7D37`, exit 0, `Assert-CandidateManifestSeal PASS`.
- Smoke manifest SHA `F362C55FB7D2B68C8C2749058FF5BC38CB893ED0C467ADAEE4DD5B961D89BE57`, succeeded, artifact-only, candidate bound, `guiInteractionProven=false`, `operatorAttested=false`, cleanup true. MP3 SHA `188ACFB52B9592FB2EADEED48B4BFD07BE1FE698B1A9AC8B144974AB5AB7D9D5`, ffprobe SHA `312A974BFE98206258E69671AE8F50CDAA44C2C1BD1D55BB944A4F5C0ECCC41`, duration 2.020136, no `.part`.
- Comparison patch SHA `0A683E31236CF28513B90C65F278ADDDF4AFC2324506B91E929EC77025B3E2AF`; source-only diff check SHA `826A225B81E70E3DD792CD8D4983AC735B453DF6DA16ECA4505E42AEBA225F82`, exit 0; full review-evidence check SHA `6A470CFA4ECAB42D69ACF4EE441FC517EDE6564BCA1DC0CBE1AA9C31667C2793`, exit 2 due older whitespace diagnostics.

## Required package slots and open gates

Present: spec content, changed-files/diff, constitution hashes (`AGENTS.md` repo SHA `4E22E0747C79B2AD9F17F08FE7F083035F3F37C6765DD02E9AAD029DAE2BA322`, parent SHA `50407D74E8897E2D4F7413ED089AAFDAD2C7658365804755164141C40A63A66C`), candidate build/seal, fresh test raw, artifact smoke, threat model, GUI ledger/screenshot hashes, independent review, and exact mismatch output.

Open or failed: sealed-candidate GUI admissibility, GUI-to-artifact causal chain, manual DPI 100/150/200, playlist causal success, subtitle causal success (only 0/0), overlay-free capture, post-capture untracked inventory, and any claim that the artifact-only smoke was produced by the GUI. The stale inventory `untracked-inventory-final-20260814T193500Z.json` SHA `022409B6CF3D2E4617D0EA85CE2C088F5762D44625F0AA56E880C009AF3DB7D3` predates the GUI capture.

## Final audit conclusion

The sealed candidate itself passes build, pre/post manifest recheck, tests and artifact-only smoke. The GUI evidence is real but inadmissible for sealed-candidate causal proof because the exact process copy mutated a declared settings payload. Independent review therefore correctly records `GUILTY`; current submission cannot receive `NOT GUILTY` or a success sticker. A future cure requires a new sealed execution copy, pre/post recheck of that exact process directory, overlay-free fresh GUI download with MP3/FFprobe/settings/no-part binding, playlist/subtitle success, manual DPI 100/150/200 captures, post-capture inventory, and a new independent verdict.
