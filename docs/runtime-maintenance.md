# Runtime maintenance

`tools/runtime-maintenance.psm1` is the PowerShell 5.1 module and exports only `RepairSettings` and `UpdateYtDlp`. `tools/runtime-maintenance.ps1` is a safe compatibility loader that imports that module; loading either file performs no repair or update.

## Settings repair

`RepairSettings -SettingsPath <copy-of-settings.json> -WhatIf` parses the file before taking action. Without `-WhatIf`, it backs up the settings file, resolves `FOLDERID_Downloads` through `SHGetKnownFolderPath`, repairs only stale `outpath`/`outpaths` values under the root and each preset, serializes to a sibling temporary file, reparses it, then uses `File.Replace`. Malformed input is never replaced. A failed replacement verification restores the backup.

The stale prefixes are deliberately narrow: `D:\Luna-Youtube-Downloader` and `C:\Users\Administrator`. All other settings fields and preset fields are retained.

## yt-dlp nightly update

`UpdateYtDlp -TargetPath <candidate\yt-dlp.exe> -WhatIf` accepts only the canonical `yt-dlp.exe` target leaf and derives its release metadata, asset, checksum, and version from `yt-dlp/yt-dlp-nightly-builds`. In normal use it downloads `yt-dlp.exe` plus `SHA2-256SUMS`, checks SHA-256, checks `--version` against the release tag, backs up the target, replaces it from sibling staging, verifies again, and records `yt-dlp-provenance.json` beside the target.

The public updater has no caller-controlled asset, checksum, tag, or version-reader overrides. Fixture tests use the internal transaction directly. `-WhatIf` runs validation but never backs up, replaces, or writes provenance.

If a post-replacement operation fails, the script restores the saved executable and verifies the rollback version. The script intentionally does not target the preserved parent deployment; run it against a reviewed candidate copy only.

## Tests

The tests do not require Pester and only create temporary fixture directories:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/run_powershell_tests.ps1
```
