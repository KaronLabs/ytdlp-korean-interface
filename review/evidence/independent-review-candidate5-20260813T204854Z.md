# Independent final review -- candidate 5 / 0DBB

Capture: `2026-08-13T20:48:54Z`.  This is an append-only, read-only audit by
the separately dispatched reviewer task `/root/independent_candidate5`.  It did
not modify source, the candidate directory, the smoke workspace, or prior
evidence.

## Judicial verdict

**GUILTY.  `NOT GUILTY` is ineligible.**

Candidate 5 is correctly sealed both before and after the retained smoke, and
the successful smoke artifacts are present and hash-consistent.  Those facts
do not satisfy the strict GUI/DPI/package protocol: the candidate has no
candidate-5-bound GUI causal ledger or screenshots, no manual 100/150/200%
DPI observations, and no post-capture package inventory.  The final index
itself truthfully declares `status=partial_success`,
`reviewer_verdict=pending`, and `not_guilty_eligible=false`.

## Identity, build, and seal

| item | independently observed result |
|---|---|
| candidate root | `C:\\Users\\ceo\\AppData\\Local\\Temp\\ytdlp-interface-final-candidates-5\\candidate-55e66fa7d6004a0c84bce001c97d2c4d` |
| candidate manifest | 31,011 bytes; SHA-256 `0DBB42E55AC3E400A758D38CE996321775FA2E3215E2B1AACFA6C1592062F68E` |
| source attestation | commit `6fe72b7f2b5240c272f4e4e6244a07c76695645b`; `dirty=false`; tree SHA `07D5889D48E55B866698777D5EBD22DDFF7DE8F4E8CABB7C4451B5CFA53D7A27` |
| build | `build-candidate-5-20260813T203735Z.status.json` exists, hashes to `AE865F82D6C08E1883AF5510DDE4EB98C575468F9647896BA4F142677E61CB27`, and records `exitCode=0`; paired raw log hashes to `455AD0C6F2F65BFB8D4F794188738D75F240F31D5CC2DA449175552A7887A3CF` |
| pre-smoke seal | JSON recheck exists, SHA-256 `E504021F7ADFE10636481DBE9AC947BE2AE31B96073DBE160825BFF6B69FA3E5`; 8 entries and `allMatched=true` |
| post-smoke seal | raw recheck exists, SHA-256 `9525E97D9BEDB4DDDE17C1E4E8771627CD4C07C20BA29659754B32C46C7D37E5`; it records `ENTRY_COUNT=8`, `ALL_MATCHED=True`, validator PASS, and `EXIT_CODE=0` |
| fresh reviewer recheck | at `2026-08-13T20:48:29.5676969Z`, all 8 manifest payloads had matching length and SHA-256; no expected payload was missing and no unexpected payload existed other than `candidate-manifest.json` |

The fresh review therefore confirms that the sealed candidate remained
`allMatched=true` after smoke and remains so at review time.  This directly
distinguishes candidate 5 from the invalidated F526 candidate; F526 GUI
evidence was not accepted as evidence for 0DBB.

## Smoke run `add8b0130fdd43f2bd020e924ea1e59f`

The retained smoke manifest exists at
`C:\\Users\\ceo\\Downloads\\ytdlp-interface-smoke-evidence\\runs\\add8b0130fdd43f2bd020e924ea1e59f.json`;
it is 1,766 bytes with the required SHA-256
`F362C55FB7D2B68C8C2749058FF5BC38CB893ED0C467ADAEE4DD5B961D89BE57`.
It records `succeeded=true`, `reasonCode=ok`, `mode=artifact-only`, and the
same 0DBB candidate-manifest SHA.

- The retained MP3 exists (9,328 bytes; SHA-256
  `188ACFB52B9592FB2EADEED48B4BFD07BE1FE698B1A9AC8B144974AB5AB7D9D5`).
  Running the candidate's `ffprobe.exe` read-only against it returned
  `codec_name=mp3` and `duration=2.020136`.
- Retained settings JSON exists (12,595 bytes; SHA-256
  `817FE80902CAFA58EE802E568D249094C6FA40D6FC99F11F915933E201B7292D`) and
  parsed successfully.  The retained FFprobe text exists (33 bytes; SHA-256
  `312A974BFE98206258E69671AE8F50CDAA44C2C1BD1D55BB944A4F5C0ECCC41A`).
  A current recursive check found zero `.part` files in that retained artifact
  directory.
- The candidate-5 wrapper status and log hash to
  `43A6915C22C9CD0EAA8FB9230309B9F136EEA808EB41ABDA6DE323CFFDDBE887` and
  `FAD277F43EB76698DCE4994E5EF73561C0DF907FC99F599F3549FC99B245FAB1`;
  both record exit code 0 / a valid `ok` result.

The manifest simultaneously records `guiInteractionProven=false` and
`operatorAttested=false`.  It is valid downstream artifact evidence, not GUI
causality evidence.

## Strict-protocol audit

| gate | result | evidence / consequence |
|---|---|---|
| GUI causality | **FAIL** | `final-index-20260813T204749Z-0DBB.json` explicitly says `missing_for_candidate_5`; no 0DBB-bound GUI action/refresh ledger or screenshots were supplied. F526 material is excluded after its mutation. |
| manual DPI 100%, 150%, 200% | **FAIL** | No three manual scale observations, measured DPI values, or candidate-5-bound screenshots exist. |
| reviewer separation | **PARTIAL** | This document is the required separately dispatched review task, but the frozen index predates it and records `reviewer_verdict=pending`; it has no independently auditable implementation-author session/model identity. This review cannot cure the failed GUI/DPI/inventory gates. |
| candidate payload inventory | **PASS** | Fresh recheck found exactly the 8 manifest payloads, with matching lengths and SHA-256 values. |
| final-package inventory | **FAIL** | The cited untracked inventory (`022409B6CF3D2E4617D0EA85CE2C088F5762D44625F0AA56E880C009AF3DB7D3`) predates candidate-5 files; no post-capture inventory binds the complete final evidence set. |
| constitution | **PASS** | Applicable repository and inherited `AGENTS.md` files independently hash to `4E22E0747C79B2AD9F17F08FE7F083035F3F37C6765DD02E9AAD029DAE2BA322` and `50407D74E8897E2D4F7413ED089AAFDAD2C7658365804755164141C40A63A66C`. |
| evidence index | **PASS, limited** | `final-index-20260813T204749Z-0DBB.json` exists (13,669 bytes; SHA-256 `9D90305ECAE39B9820543447E63BF208D03E749934BA598B96543196C474EFB4`) and its sampled build, pre/post seal, smoke, artifact, settings, FFprobe, and constitution references re-hash exactly. Its stated scope is correctly `partial_success`. |

## Required cure

Keep this sealed candidate unchanged, then capture a candidate-5-bound,
overlay-free GUI action/refresh ledger for the complete flow; have the operator
manually set and record 100%, 150%, and 200% Display Scale with corresponding
evidence; create a post-capture inventory binding every final artifact; and
freeze a successor index that names this independent reviewer verdict.  Only
after all of those gates have concrete, candidate-bound evidence may a new
review consider `NOT GUILTY`.
