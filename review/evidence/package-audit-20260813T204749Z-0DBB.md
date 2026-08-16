# Candidate-5 package audit (append-only)

Capture: `2026-08-13T20:47:49.6434635Z`.

Candidate-5 manifest `0DBB42E55AC3E400A758D38CE996321775FA2E3215E2B1AACFA6C1592062F68E`
binds clean source commit `6fe72b7f2b5240c272f4e4e6244a07c76695645b`, tree
`07D5889D48E55B866698777D5EBD22DDFF7DE8F4E8CABB7C4451B5CFA53D7A27`, and 125
tracked files. Build exit is 0; pre-smoke and post-smoke 8-entry seal checks
both report all matched. The successful artifact smoke manifest
`F362C55FB7D2B68C8C2749058FF5BC38CB893ED0C467ADAEE4DD5B961D89BE57` binds the
same candidate and records MP3 SHA `188ACF...7D9D5`, settings SHA
`817FE8...B7292D`, FFprobe SHA `312A97...CCC41`, duration 2.020136, and no
`.part` files.

The candidate-5 raw build/recheck/smoke evidence is enumerated in
`final-index-20260813T204749Z-0DBB.json`. Source native/contract/PowerShell
logs, constitution hashes, comparison patch, and threat model are also bound
there. A prior smoke failure and the prior F526 mutation are retained rather
than hidden.

The following required gates remain unproven:

- candidate-5-bound GUI action/refresh ledger and screenshots;
- manual 100%, 150%, and 200% DPI observations;
- different-session-or-model verdict over this exact frozen package;
- post-capture untracked inventory.

The artifact smoke's own flags are `guiInteractionProven=false` and
`operatorAttested=false`; it cannot be treated as GUI proof. F526 GUI evidence
is excluded because its candidate was later mutated and independently failed
seal validation. The correct status is `partial_success`, not `success` or
`NOT GUILTY`.

