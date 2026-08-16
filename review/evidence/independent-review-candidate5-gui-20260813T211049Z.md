# Independent GUI evidence review -- candidate 5 / 0DBB

Capture: `2026-08-13T21:10:49Z`.  This is a new append-only, read-only
review by separately dispatched task `/root/independent_candidate5`; the prior
candidate-5 review remains unmodified.  Source, both candidate roots, smoke
artifacts, screenshots, and prior evidence were not changed.

## Judicial verdict

**GUILTY.  `NOT GUILTY` remains ineligible.**

The new ledger establishes that several real GUI states were observed, and its
referenced JPEGs are overwhelmingly hash-consistent.  It nevertheless cannot
prove execution of the sealed candidate: the process named by every ledger
event ran from a distinct GUI execution copy whose own 0DBB manifest does not
match its `ytdlp-interface.json`.  Independently of that decisive failure,
all observations contain an external overlay, playlist and subtitle success
are explicitly absent, manual DPI evidence is absent, and the final package
index/inventory/reviewer-separation record is still incomplete.

## Ledger and screenshot integrity

| item | independently observed result |
|---|---|
| ledger | `gui-candidate5-20260814T205700Z-ledger.jsonl`; 16,462 bytes; 12 UTF-8 JSONL records; SHA-256 `819DEC76114254273F2252E8DF1D02F6F4EF4D81D271723E7BB86643929371EA` |
| candidate binding stated in ledger | all 12 records name `0DBB42E55AC3E400A758D38CE996321775FA2E3215E2B1AACFA6C1592062F68E` |
| screenshot references | 16 distinct referenced JPEGs; 15 referenced hashes recompute exactly. The remaining reference is the explicit line-5 placeholder `UNRECORDED_PREVIOUS_SCREENSHOT`, not a hash. |
| correction | line 12 is a valid append-only correction for the line-5 pre-image; it gives `queue-action-started.jpg` SHA `876CEF678A21F01129B6E8970AA2565997E53E66EB9C0DE89C036803754437AE`, which recomputes exactly. Line 5 remains an invalid strict-proof record and only line 12 may supply the corrected binding. |
| overlay | all 12 records set `externalOverlayPresent=true`; direct visual inspection confirms the Codex evidence/chat overlay covers a material upper-center region in format, settings, sections, message-box, output, queue-context, and playlist screenshots. |

The ledger is valid JSON when decoded as strict UTF-8 and parsed using the
Python standard JSON parser.  A PowerShell `ConvertFrom-Json` failure for lines
3, 7, and 10 was an encoding-path false negative and is not counted as an
artifact defect.

## Decisive candidate-causality failure

The sealed candidate root remains healthy at review time: the original
candidate manifest hashes to `0DBB...F68E`, and all eight declared payloads
still match their specified SHA-256 and length (`allMatched=true`).  Its
post-smoke retained recheck also records eight matching entries and `EXIT_CODE=0`.

The GUI ledger, however, identifies every window as process
`C:\\Users\\ceo\\AppData\\Local\\Temp\\ytdlp-interface-final-gui-candidate5-20260814T000002Z\\ytdlp-interface.exe`,
not the sealed candidate root.  That execution-copy directory contains an
identical-hash manifest (`0DBB...F68E`) but fails its own manifest recheck:

| execution-copy payload | manifest requirement | independently observed |
|---|---|---|
| `ytdlp-interface.json` | 12,531 bytes; `9D52BD66A45FDA25E257A9D89184C27896A44484412F2B32CD37E99FE3DB9F05` | 8,404 bytes; `6C9FE18BCB17588FF8938385050394E8D839851D39108EFB716F2689BED1008C` |

The other seven declared payloads match, but one mismatch is sufficient.  The
execution-copy settings JSON is syntactically valid, which does not cure the
seal mismatch.  Consequently, the visual observations are not admissible as
strict candidate-5 GUI causality proof.

## Event-by-event evidentiary classification

| ledger event(s) | classification | exact limitation |
|---|---|---|
| startup and URL entry | observed UI state only | Korean main window and loopback URL/queued row are visible, but the execution copy is unsealed and overlay-covered. |
| queue context menu | observed UI state only | The menu is visibly Korean and exposes subtitle selection, but reports `0/0`; no subtitle track, dialog, selection, or download result is proven. |
| queue-action result; metadata outcome; corrected binding | negative/diagnostic evidence | The clicked coordinate cleared the queue; subsequent row is `완료` with `info=---`, `metadataDialogVisible=false`, and `metadataSuccess=false`. It is not a successful metadata causal chain. |
| format dialog | observed UI state only | Korean format dialog is visible, but `mp4 - unknown *` is not a format-selection/download proof and the screenshot has the external overlay. |
| settings | observed UI state only | Korean settings navigation and yt-dlp panel are visible; no language change/persistence-after-close or sealed execution proof is captured. |
| sections dialog and input-error message box | observed UI state only | Korean sections UI and the equal-bound validation message are visible. They do not prove an end-to-end sections download and are overlay-covered. |
| output view | non-closing diagnostic evidence | The image shows GUI output mentioning MP3 and an already-downloaded file. It does not prove a fresh GUI-produced artifact; the separately retained `add8...59f` smoke is expressly `artifact-only`. |
| playlist availability result | negative evidence | It states that the URL is already in the queue; `newPlaylistRowVisible=false`, `playlistDialogVisible=false`, and `metadataFetched=false`. No playlist flow is proven. |

## Remaining strict-protocol gaps

1. **Candidate GUI causality — fail.** The actual GUI process copy is
   manifest-mismatched as above.  Candidate-root seal success does not transfer
   to an unsealed copy.
2. **Overlay-free proof — fail.** All 12 ledger states explicitly contain the
   external overlay, and direct image review confirms it.
3. **Subtitle and playlist — fail.** Subtitle is only `0/0`; playlist outcome
   is expressly negative.  Neither required interaction succeeds.
4. **Manual 100%, 150%, and 200% DPI — fail.** No display-scale observations,
   measured DPI, or corresponding screenshots were supplied.
5. **End-to-end GUI download — fail.** There is no candidate-5-sealed GUI
   chain from URL through metadata/format selection to a fresh contained MP3,
   FFprobe result, no-`.part` check, and persisted settings.  The supplied
   `F362C55FB7D2B68C8C2749058FF5BC38CB893ED0C467ADAEE4DD5B961D89BE57`
   smoke manifest remains valid, but declares `mode=artifact-only`,
   `guiInteractionProven=false`, and `operatorAttested=false`.
6. **Package inventory and independent-review binding — fail.** No frozen
   successor index references this new ledger; the last candidate-5 index
   predates it.  No post-capture untracked inventory binds this ledger,
   screenshots, this review, and all earlier evidence.  The ledger records no
   collection-author session/model or Computer Use initialization transcript;
   it therefore cannot independently establish reviewer separation.  This
   separately dispatched review does not repair the other failed gates.

## Required cure before another verdict

Make a new sealed execution copy and perform a pre-launch and post-GUI
eight-payload manifest recheck against that exact process directory.  Capture
an overlay-free current-run ledger that reaches a fresh GUI download and binds
its MP3, FFprobe, settings-after-close, and no-`.part` state.  Exercise an
available subtitle track and a playlist flow, record operator-manual 100/150/
200% DPI evidence, then freeze a post-capture inventory/index naming the
collector and a different-session/model reviewer.  Only that complete package
could be reconsidered for `NOT GUILTY`.
