# Runtime maintenance

`tools/runtime-maintenance.psm1` is the PowerShell 5.1 module and exports only `RepairSettings` and `UpdateYtDlp`. `tools/runtime-maintenance.ps1` is a safe compatibility loader that imports that module; loading either file performs no repair or update.

## Settings repair

`RepairSettings -SettingsPath <copy-of-settings.json> -WhatIf` parses the file before taking action. Without `-WhatIf`, it backs up the settings file, resolves `FOLDERID_Downloads` through `SHGetKnownFolderPath`, repairs only stale `outpath`/`outpaths` values under the root and each preset, serializes to a sibling temporary file, reparses it, then uses `File.Replace`. Malformed input is never replaced. A failed replacement verification restores the backup.

The stale prefixes are deliberately narrow: `D:\Luna-Youtube-Downloader` and `C:\Users\Administrator`. All other settings fields and preset fields are retained.

## yt-dlp nightly update

`UpdateYtDlp -TargetPath <candidate\yt-dlp.exe> -WhatIf` must be run from an unelevated PowerShell process. It accepts only the canonical `yt-dlp.exe` target leaf and derives its release metadata, asset, checksum, and version from `yt-dlp/yt-dlp-nightly-builds`. In normal use it downloads `yt-dlp.exe` plus `SHA2-256SUMS`, checks SHA-256, checks `--version` against the release tag, records the prior version and SHA-256, backs up the target, replaces it from sibling staging, verifies again, and atomically records `yt-dlp-provenance.json` beside the target.

The public updater has no caller-controlled asset, checksum, tag, or version-reader overrides. Fixture tests use the internal transaction directly. `-WhatIf` runs release validation but never recovers a pending transaction, backs up or replaces the executable, writes or restores provenance, or deletes a transaction journal.

Before replacement, the updater atomically writes a sibling transaction journal containing the prior executable identity and provenance preimage. On the next confirmed update attempt, it requires a typed, complete journal whose backup is an absolute, canonical updater backup in the target directory and is not a link or reparse point. A journal that says provenance did not exist must carry an empty preimage. When provenance existed, its decoded official repository, nightly channel, asset, tag, and SHA-256 must bind the journal's prior version and hash; the journal cannot establish executable trust merely by repeating its own values.

Recovery never executes a journal backup. The official prior provenance already binds the byte identity by SHA-256 and the recorded release tag; launching the backup would add code-execution surface without adding authenticity. Recovery holds the source against write/delete while copying it once to a private sibling snapshot. During creation it opens an overlapping read bridge before closing the writer, then opens the final read/no-write/no-delete handle before closing the bridge. Thus a handle continuously pins the same snapshot identity from creation through stream hashing and restoration; the pathname cannot be swapped underneath those operations. Recovery verifies the executable plus the exact provenance existence and bytes before deleting the journal.

Normal installation likewise rechecks the deployed executable SHA-256 and exact serialized provenance bytes before deleting the journal. Catch rollback first creates the same continuously pinned snapshot of the generated backup and verifies its previous SHA-256 before changing the target; a replaced or mutated backup is rejected and the journal remains. A valid residual journal is recovered before any network operation begins. The script intentionally does not target the preserved parent deployment; run it against a reviewed candidate copy only.

## Tests

The tests do not require Pester and only create temporary fixture directories:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run_powershell_tests.ps1
```
