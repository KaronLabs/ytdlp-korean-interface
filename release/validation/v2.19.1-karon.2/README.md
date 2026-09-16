# GUI release evidence contract for v2.19.1-karon.2

This directory defines the manual GUI evidence gate. It does not contain final
evidence and does not claim that the six-case matrix passed.

## Required cases

Run the same sealed `ytdlp-interface.exe` bytes in this exact matrix:

| Case ID | Language | Windows scale |
|---|---|---:|
| `ko-KR-100` | `ko-KR` | 100% |
| `ko-KR-150` | `ko-KR` | 150% |
| `ko-KR-200` | `ko-KR` | 200% |
| `en-US-100` | `en-US` | 100% |
| `en-US-150` | `en-US` | 150% |
| `en-US-200` | `en-US` | 200% |

The recorder never changes Windows DPI or language. Before each run, the
operator must explicitly set the requested scale and application language,
sign out or restart the application when Windows requires it, visually confirm
the effective values, and then record those observed values.

## Operator flow

Use a new evidence directory and the final sealed candidate path. `Initialize`
records the candidate SHA and creates only null observations. It does not set a
PASS value.

```powershell
pwsh -NoProfile -File tools/record-gui-release-evidence.ps1 `
  -Action Initialize `
  -EvidenceRoot C:\release-evidence\gui `
  -CandidateExePath C:\sealed-candidate\ytdlp-interface.exe `
  -Language ko-KR `
  -DpiPercent 100
```

After manually applying and observing the environment:

```powershell
pwsh -NoProfile -File tools/record-gui-release-evidence.ps1 `
  -Action RecordEnvironment `
  -CasePath C:\release-evidence\gui\cases\ko-KR-100.json `
  -ObservedLanguage ko-KR `
  -ObservedDpiPercent 100
```

Record every observation separately. Use `-Result false` when the observed
behavior failed. Never enter `true` merely to complete the form.

```powershell
pwsh -NoProfile -File tools/record-gui-release-evidence.ps1 `
  -Action RecordObservation `
  -CasePath C:\release-evidence\gui\cases\ko-KR-100.json `
  -Observation launch `
  -Result true
```

Capture screenshots with Computer Use or an operator-controlled local capture
tool, then attach each PNG. The recorder copies it into the evidence root and
records its byte hash, dimensions, length, and current UTC capture time.

```powershell
pwsh -NoProfile -File tools/record-gui-release-evidence.ps1 `
  -Action AddScreenshot `
  -CasePath C:\release-evidence\gui\cases\ko-KR-100.json `
  -EvidenceFilePath C:\captures\ko100-main.png `
  -Label main
```

For `ko-KR-100` and `en-US-200`, create ffprobe JSON from the actual completed
video and attach both files:

```powershell
& C:\sealed-candidate\ffprobe.exe -v error -show_streams -of json `
  C:\test-output\video.mp4 | Set-Content -Encoding utf8NoBOM C:\captures\video.ffprobe.json

pwsh -NoProfile -File tools/record-gui-release-evidence.ps1 `
  -Action AttachVideoLifecycle `
  -CasePath C:\release-evidence\gui\cases\ko-KR-100.json `
  -EvidenceFilePath C:\test-output\video.mp4 `
  -FfprobeJsonPath C:\captures\video.ffprobe.json `
  -ExpectedWidth 1920 `
  -ExpectedHeight 1080 `
  -Result true
```

Use `RecordMp3`, `RecordSettingsRestore`, and `RecordLegacyTransition` in at
least one representative case each. Settings and legacy checks must reference
a screenshot already attached to that same case. Finally run `Finalize` after
all observations and evidence were recorded.

## Secret hygiene

Do not record cookies, authorization headers, bearer tokens, signed media URLs,
proxy credentials, or URLs containing query strings. The verifier rejects
secret-like text in every JSON, log, text, Markdown, CSV, XML, and YAML evidence
file. Use a neutral local test identifier in notes instead of a media URL.

## Final verification

Run this only against the final sealed candidate and completed six-case
evidence directory:

```powershell
pwsh -NoProfile -File tools/verify-gui-release-evidence.ps1 `
  -EvidenceRoot C:\release-evidence\gui `
  -CandidateExePath C:\sealed-candidate\ytdlp-interface.exe `
  -OutputDirectory C:\release-evidence\sealed
```

Success creates one atomic directory named
`gui-validation-v2.19.1-karon.2` containing:

- `gui-validation-summary.json`
- `gui-validation-evidence-manifest.json`

If any gate fails, neither file is emitted. A competing producer's final
directory is never overwritten or deleted.
