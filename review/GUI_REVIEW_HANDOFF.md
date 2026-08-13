# Korean i18n GUI independent-review handoff

Use this file in a **new Codex task/session**. The reviewer must be a different
session or model from the implementation author.

## Fixed inputs

- Final package index: `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\review\spec_20260813_154600_korean_i18n_recovery_final_index.md`
- Candidate root: `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-candidates\candidate-dc08eec8638f433b835ce6a5520499b1`
- Candidate manifest SHA-256: `1070737848C63B7477BE2C053D21E48865BEF6E0807297D5BB1A69457846535E`
- Parent runtime: `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface`
- Python: `C:\Users\ceo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe`
- Existing artifact-only MP3 SHA-256: `188ACFB52B9592FB2EADEED48B4BFD07BE1FE698B1A9AC8B144974AB5AB7D9D5`

## Mandatory first gate

Read the bundled `computer-use` skill completely, including `guidance.md`,
`api.md`, and `confirmations.md`. Reset the Node REPL, import `@oai/sky`, and
call `sky.list_apps()` without performing any input.

- If it returns apps, continue.
- If it returns `EPERM ... lstat 'C:\Users\ceo\AppData\Local\OpenAI\Codex'`,
  stop. Record the exact error and do not use PowerShell UI Automation, ACL
  changes, security-setting changes, or guessed window handles.

## Candidate integrity gate

Before launching the candidate, recalculate `candidate-manifest.json` SHA-256
and verify every manifest-listed file's length and SHA-256. Stop on any
mismatch. Record command, UTC start/completion, output, and exit code.

## Supervised GUI action ledger

Launch the candidate by the explicit executable path using Computer Use. After
each step below, capture a fresh window state. Never reuse element indexes,
coordinates, or screenshot IDs after state changes.

1. Select exactly one returned candidate window.
2. Capture the initial main window and verify Korean text is present without a
   localization-error dialog.
3. Verify the main controls and each required translated dialog/page: format,
   playlist, subtitle, sections, queue/output, settings, and message boxes.
4. Verify behavior does not depend on visible translated captions when changing
   views or queue states.
5. In settings, verify the Korean language selection persists and that closing
   the application leaves valid JSON.
6. Run the complete localhost flow: focus the URL field, enter the supplied
   `http://127.0.0.1:<port>/input.mp4` URL, request information, observe metadata,
   select MP3, initiate download, and observe completion.
7. Verify a fresh non-empty MP3 exists, no `.part` remains, FFprobe reports an
   MP3 codec and positive duration, and the output is contained by the unique
   Downloads smoke workspace.
8. Record 100%, 150%, and 200% DPI observations. Display-scaling changes are
   manual/user actions; Computer Use must not alter Windows display settings.

Every ledger entry must contain UTC timestamp, action, pre-observation identity,
post-observation identity, selected window id/title, visible result, and the
candidate-manifest SHA-256. Screenshots/accessibility records must be actual
current-run outputs, not written summaries.

## Required final artifacts

- Computer Use initialization transcript
- Candidate integrity transcript
- GUI action/refresh ledger
- Screenshot/accessibility evidence for each required state
- Operator-guided smoke manifest with `succeeded=true` and
  `mode=operator-guided`
- Fresh MP3 body, SHA-256, size, FFprobe output, and no-`.part` check
- Valid settings JSON after close
- DPI observations
- Different-session/model reviewer identity and final judicial verdict

Do not issue `NOT GUILTY` unless every item above is present and independently
bound to the same candidate manifest SHA-256.

## Copy/paste prompt for the new task

> Independently review the Korean i18n recovery using
> `C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\review\GUI_REVIEW_HANDOFF.md`.
> Use the computer-use skill. Begin with a fresh read-only `sky.list_apps()`.
> Follow the handoff exactly, preserve actual action/refresh evidence, and issue
> NOT GUILTY only if every stated gate passes. Do not rely on the previous task's
> prose or artifact-only smoke as GUI evidence.
