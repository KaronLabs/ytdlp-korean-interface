# v2.19.1-karon.2 manual GUI evidence guide

This guide records only observed results. It does not authorize a PASS claim,
ZIP creation, tag creation, or GitHub Release publication.

## Fixed identities

Functional target:

```text
32f03f99d1339aa5f8fd37a1f6a1904b6dad5a28
```

Sealed executable SHA-256:

```text
BEBADE61F980CADA9D338A4C32DF77E0122C18BBF07E4E95E4F056C93008F6CA
```

Do not modify the sealed candidate. Each case uses a disposable execution copy.
Only its settings/output state may change through the application. Do not edit
`ytdlp-interface.exe`, `ffprobe.exe`, or `candidate-manifest.json` in any copy.

## One-time PowerShell setup

Open PowerShell and define these values exactly once. The evidence root must
contain only files created by the recorder. Do not store this guide, notes, or
unrelated files inside it.

```powershell
$ValidationRoot = 'E:\03_AllWork\ytdlp-korean-interface\.validation\karon2-d4c55f9-20260918-01'
$SourceRoot = Join-Path $ValidationRoot 'source-32f03f9'
$Tools = Join-Path $SourceRoot 'tools'
$Recorder = Join-Path $Tools 'record-gui-release-evidence.ps1'
$Verifier = Join-Path $Tools 'verify-gui-release-evidence.ps1'
$SealedRoot = Join-Path $ValidationRoot 'candidates\candidate-2bc0f512653d48d4854d8961da2e1f3e'
$EvidenceRoot = Join-Path $ValidationRoot 'gui-evidence\manual-20260918'
$RuntimeParent = Join-Path $ValidationRoot 'gui-runtime\manual-20260918'
$VerifierOutput = Join-Path $ValidationRoot 'gui-output\manual-20260918'
```

Before beginning, confirm the sealed EXE hash. This is an identity check only;
do not modify the candidate.

```powershell
(Get-FileHash (Join-Path $SealedRoot 'ytdlp-interface.exe') -Algorithm SHA256).Hash
```

Expected output is the fixed SHA-256 shown above.

## Rules for every case

1. Create a new disposable runtime copy from `$SealedRoot`. Use a distinct copy
   for every case so language, output, and legacy settings do not bleed across
   cases.
2. Set Windows display scaling to the case DPI before launching the app. Select
   the required application language before recording the environment.
3. Initialize the case before recording any result. The recorder creates every
   required observation as `null`; it never pre-fills PASS.
4. Record `true` only after directly observing the stated behavior. If it is
   absent, clipped, unusable, or incorrect, record `false`, retain a screenshot,
   finalize the case, and stop the release path for defect triage.
5. Every case needs at least one unique PNG screenshot. Use PNG files at least
   640x480. Do not reuse the same screenshot in another case. Keep captures free
   of cookies, signed URLs, tokens, or query-bearing URLs.
6. All six case files must bind to the same EXE SHA. The verifier is run against
   one unmodified runtime copy whose `ytdlp-interface.exe`, `ffprobe.exe`, and
   `candidate-manifest.json` are byte-identical to the sealed candidate.
7. Do not create a final ZIP until the verifier returns PASS.

## Per-case assignment

| Case | Required environment | Extra required evidence |
|---|---|---|
| `ko-KR-100` | Korean, 100% | Completed 1080p video lifecycle with actual media artifact; MP3 conversion artifact |
| `ko-KR-150` | Korean, 150% | Settings save, full restart, and restored-setting screenshot |
| `ko-KR-200` | Korean, 200% | Actual legacy-settings transition screenshot |
| `en-US-100` | English, 100% | Standard GUI and download flow |
| `en-US-150` | English, 150% | Standard GUI and download flow |
| `en-US-200` | English, 200% | Completed 1080p video lifecycle with actual media artifact |

## Start one case

For each row, replace `$CaseId`, `$Language`, and `$Dpi` with its values. This
example starts `ko-KR-100`.

```powershell
$CaseId = 'ko-KR-100'
$Language = 'ko-KR'
$Dpi = 100
$RunRoot = Join-Path $RuntimeParent $CaseId
New-Item -ItemType Directory -Force -Path $RuntimeParent | Out-Null
Copy-Item -LiteralPath $SealedRoot -Destination $RunRoot -Recurse
$CandidateExe = Join-Path $RunRoot 'ytdlp-interface.exe'
$CandidateManifest = Join-Path $RunRoot 'candidate-manifest.json'
$CasePath = Join-Path $EvidenceRoot "cases\$CaseId.json"

& $Recorder -Action Initialize -EvidenceRoot $EvidenceRoot -CandidateExePath $CandidateExe -Language $Language -DpiPercent $Dpi
```

Then set Windows display scale to the required value, start `$CandidateExe`,
and use the application's Settings UI to point its tool paths at `$RunRoot` and
its download folder at a directory under `$RunRoot`. Do not point outputs at the
sealed candidate or at `$EvidenceRoot`.

Once the actual application language and Windows scale are visible, record the
environment:

```powershell
& $Recorder -Action RecordEnvironment -CasePath $CasePath -ObservedLanguage $Language -ObservedDpiPercent $Dpi
```

## Eleven required observations, in order

After every direct observation, run the corresponding command. Replace the
value after `-Result` with the actual result, `true` or `false`. Do not run a
command before observing the condition.

1. `launch`: Main window appears, receives focus, and the URL field accepts a
   short test value. This is the contract's focus/input observation.
2. `downloadType`: Verify Video and Audio modes can each be selected; return to
   Video for the video-quality checks.
3. `quality1080p`: Select the maximum 1080p preset and verify it visibly stays
   selected.
4. `quality720p`: Select the maximum 720p preset and verify it visibly stays
   selected.
5. `qualityBest`: Select the best-quality preset and verify it visibly stays
   selected.
6. `expectedResolution`: Return to 1080p, analyze a single public video with
   available 1080p video and audio, and verify that selected or expected
   dimensions plus audio presence are shown near the download controls.
7. `queueRegistration`: Add the analyzed item through the real GUI control and
   verify the item appears in the queue.
8. `progress`: Start the queued item through the real GUI and observe active
   progress, not merely a queued state.
9. `completion`: Observe the application's completed state only after it reports
   completion. For the two lifecycle cases, this must match the actual artifact.
10. `advancedNavigation`: Open the advanced settings or format-selection flow
    and verify it is reachable; return without changing the current case's
    evidence by hand.
11. `noClipping`: Inspect every visible label, selection, expected-result text,
    queue/status area, and relevant button at that DPI. Any text or control
    clipping is `false`.

Use this exact command shape after each observation:

```powershell
& $Recorder -Action RecordObservation -CasePath $CasePath -Observation 'launch' -Result true
& $Recorder -Action RecordObservation -CasePath $CasePath -Observation 'downloadType' -Result true
& $Recorder -Action RecordObservation -CasePath $CasePath -Observation 'quality1080p' -Result true
& $Recorder -Action RecordObservation -CasePath $CasePath -Observation 'quality720p' -Result true
& $Recorder -Action RecordObservation -CasePath $CasePath -Observation 'qualityBest' -Result true
& $Recorder -Action RecordObservation -CasePath $CasePath -Observation 'expectedResolution' -Result true
& $Recorder -Action RecordObservation -CasePath $CasePath -Observation 'queueRegistration' -Result true
& $Recorder -Action RecordObservation -CasePath $CasePath -Observation 'progress' -Result true
& $Recorder -Action RecordObservation -CasePath $CasePath -Observation 'completion' -Result true
& $Recorder -Action RecordObservation -CasePath $CasePath -Observation 'advancedNavigation' -Result true
& $Recorder -Action RecordObservation -CasePath $CasePath -Observation 'noClipping' -Result true
```

The displayed `true` values are command syntax examples only. Replace any value
that was not actually observed with `false`; do not continue toward release in
that case.

## Screenshot recording

Capture a PNG after meaningful states. A useful minimum is one full-window
capture after the 1080p expected-result display and one after completion or
advanced navigation. Save the source PNG outside `$EvidenceRoot`, then attach it.

```powershell
$Capture = 'C:\Users\ceo\Pictures\ko-KR-100-1080p.png'
& $Recorder -Action AddScreenshot -CasePath $CasePath -EvidenceFilePath $Capture -Label '1080p-result'
$ResolutionScreenshot = "screenshots/$CaseId-1080p-result.png"
```

The recorder copies the image to the evidence root and records its actual hash,
length, dimensions, and timestamp. Never edit the copied file afterward.

## Required completed video lifecycles

For `ko-KR-100` and `en-US-200`, use a real completed video download that has
both a video and an audio stream. The selected output must be `.mp4`, `.mkv`, or
`.webm`. The expected dimensions must be the dimensions displayed and actually
downloaded. The verifier requires the smaller dimension to equal 1080.

For a 1920x1080 result:

```powershell
$VideoOutput = 'C:\actual-downloads\example-1080p.mp4'
& $Recorder -Action AttachVideoLifecycle -CasePath $CasePath -EvidenceFilePath $VideoOutput -ExpectedWidth 1920 -ExpectedHeight 1080 -Result true
```

Do not provide operator-authored ffprobe JSON. The verifier runs the sealed
candidate's `ffprobe.exe` against the copied artifact and generates canonical
probe evidence itself.

## Representative coverage

### MP3 conversion: `ko-KR-100`

After the video lifecycle, select Audio mode in the real GUI, complete one MP3
conversion, and record the actual `.mp3` output.

```powershell
$Mp3Output = 'C:\actual-downloads\example.mp3'
& $Recorder -Action RecordMp3 -CasePath $CasePath -EvidenceFilePath $Mp3Output -Result true
```

The verifier requires an MP3 container, an MP3 audio stream, and no normal video
stream. A filename alone is insufficient.

### Settings save and restart restore: `ko-KR-150`

1. Change one safe, visible application setting in the disposable runtime copy,
   such as the download directory or selected language.
2. Save through the application UI and exit the application normally.
3. Relaunch the same `$RunRoot\ytdlp-interface.exe`.
4. Confirm the exact changed setting is restored.
5. Capture a full PNG showing the restored value, attach it, then record the
   representative check using the returned screenshot path.

```powershell
$Capture = 'C:\Users\ceo\Pictures\ko-KR-150-settings-restored.png'
& $Recorder -Action AddScreenshot -CasePath $CasePath -EvidenceFilePath $Capture -Label 'settings-restored'
$RestoreScreenshot = "screenshots/$CaseId-settings-restored.png"
& $Recorder -Action RecordSettingsRestore -CasePath $CasePath -ScreenshotReferencePath $RestoreScreenshot -Result true
```

### Legacy-settings transition: `ko-KR-200`

Use an actual pre-karon.2 `ytdlp-interface.json` from a previous installation.
Back it up first and copy it only into the disposable `$RunRoot`; never place it
into `$SealedRoot` and do not hand-author guessed legacy JSON keys.

1. Launch the disposable copy with the real legacy file.
2. Verify the application keeps existing settings/custom behavior in Advanced
   mode rather than silently applying the new recommended basic policy.
3. Use the visible action that returns to recommended basic settings.
4. Confirm the transition is explicit and capture a full PNG showing the result.
5. Attach the capture and record the representative check.

```powershell
$Capture = 'C:\Users\ceo\Pictures\ko-KR-200-legacy-transition.png'
& $Recorder -Action AddScreenshot -CasePath $CasePath -EvidenceFilePath $Capture -Label 'legacy-transition'
$LegacyScreenshot = "screenshots/$CaseId-legacy-transition.png"
& $Recorder -Action RecordLegacyTransition -CasePath $CasePath -ScreenshotReferencePath $LegacyScreenshot -Result true
```

If no authentic legacy settings file exists, record no PASS for this check. Stop
and report the missing evidence input before verifier execution.

## Finalize all six cases

Only after each case has its environment, all eleven observed values, screenshots,
and its assigned representative evidence, finalize it:

```powershell
& $Recorder -Action Finalize -CasePath $CasePath
```

Repeat with these case variables:

```text
ko-KR-100 / ko-KR / 100
ko-KR-150 / ko-KR / 150
ko-KR-200 / ko-KR / 200
en-US-100 / en-US / 100
en-US-150 / en-US / 150
en-US-200 / en-US / 200
```

## Verify only after all evidence is complete

Choose one untouched runtime copy as `$VerifierRunRoot`; its EXE, ffprobe, and
manifest must remain byte-identical to the sealed candidate. Then run:

```powershell
$VerifierRunRoot = Join-Path $RuntimeParent 'en-US-200'
& $Verifier `
  -EvidenceRoot $EvidenceRoot `
  -CandidateExePath (Join-Path $VerifierRunRoot 'ytdlp-interface.exe') `
  -CandidateManifestPath (Join-Path $VerifierRunRoot 'candidate-manifest.json') `
  -OutputDirectory $VerifierOutput
```

PASS creates exactly this output directory:

```text
<VerifierOutput>\gui-validation-v2.19.1-karon.2\
```

It contains `gui-validation-summary.json` and
`gui-validation-evidence-manifest.json`. Only after this command succeeds may
the release sequence continue to final ZIP, license adjudication, exact-target
CI, and the release gate.
