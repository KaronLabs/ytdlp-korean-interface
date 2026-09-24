# v2.19.1-karon.2 GUI 수동 검증 증거 안내서

이 안내서는 실제로 관찰한 결과만 기록하기 위한 문서입니다. 이 문서만으로 검증 PASS를
선언하거나 ZIP·태그를 만들거나 GitHub Release를 게시할 수는 없습니다.

## 변경하면 안 되는 기준값

기능 구현 대상 커밋:

```text
32f03f99d1339aa5f8fd37a1f6a1904b6dad5a28
```

봉인된 실행 파일의 SHA-256:

```text
BEBADE61F980CADA9D338A4C32DF77E0122C18BBF07E4E95E4F056C93008F6CA
```

봉인된 후보 파일을 수정하지 마세요. 각 사례에서는 별도의 임시 실행용 복사본을 사용합니다.
설정과 출력 상태만 애플리케이션을 통해 변경할 수 있습니다. 어느 복사본에서든
`ytdlp-interface.exe`, `ffprobe.exe`, `candidate-manifest.json`을 수정하지 마세요.

## PowerShell 최초 설정

PowerShell을 열고 아래 값을 한 번 설정하세요. 증거 폴더에는 기록 스크립트가 만든 파일만
있어야 합니다. 이 안내서, 개인 메모, 무관한 파일을 증거 폴더에 넣지 마세요.

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

시작 전에 봉인된 EXE의 해시를 확인하세요. 파일 식별 확인일 뿐이며 후보 파일을
수정해서는 안 됩니다.

```powershell
(Get-FileHash (Join-Path $SealedRoot 'ytdlp-interface.exe') -Algorithm SHA256).Hash
```

출력값은 위에 적힌 고정 SHA-256과 일치해야 합니다.

## 모든 사례에 적용할 규칙

1. `$SealedRoot`에서 새 임시 실행용 복사본을 만드세요. 언어·출력·기존 설정이 다른
   사례에 영향을 주지 않도록 사례마다 별도 복사본을 사용하세요.
2. 앱을 실행하기 전에 Windows 화면 배율을 해당 사례의 DPI로 설정하세요. 환경을
   기록하기 전에는 앱 언어도 해당 사례에 맞게 선택하세요.
3. 결과를 기록하기 전에 사례를 초기화하세요. 기록 스크립트는 모든 필수 관찰값을
   `null`로 만들며, PASS를 미리 입력하지 않습니다.
4. 해당 동작을 직접 확인한 뒤에만 `true`를 기록하세요. 동작이 없거나, 화면이
   잘리거나, 사용하기 어렵거나, 결과가 틀리면 `false`를 기록하고 스크린샷을
   보존하세요. 그 사례를 마무리한 다음 배포를 중단하고 결함을 조사하세요.
5. 사례마다 고유한 PNG 스크린샷이 최소 1장 필요합니다. 크기는 640x480 이상이어야
   합니다. 다른 사례의 스크린샷을 재사용하지 마세요. 쿠키·서명된 URL·토큰·쿼리
   문자열이 포함된 URL이 화면에 보이지 않게 하세요.
6. 여섯 사례 파일은 모두 동일한 EXE SHA와 연결되어야 합니다. 검증 스크립트에는
   `ytdlp-interface.exe`, `ffprobe.exe`, `candidate-manifest.json`이 봉인 후보와
   바이트 단위로 동일한, 수정하지 않은 실행용 복사본 하나를 사용하세요.
7. 검증 스크립트가 PASS를 반환하기 전에는 최종 ZIP을 만들지 마세요.

## 사례별 추가 증거

| 사례 | 필수 환경 | 추가로 필요한 증거 |
|---|---|---|
| `ko-KR-100` | 한국어, 100% | 실제 미디어 파일을 포함한 1080p 영상 다운로드 전체 과정, MP3 변환 결과물 |
| `ko-KR-150` | 한국어, 150% | 설정 저장·앱 완전 종료 후 재시작·복원된 설정의 스크린샷 |
| `ko-KR-200` | 한국어, 200% | 실제 이전 버전 설정에서 전환한 화면의 스크린샷 |
| `en-US-100` | 영어, 100% | 기본 GUI와 다운로드 흐름 |
| `en-US-150` | 영어, 150% | 기본 GUI와 다운로드 흐름 |
| `en-US-200` | 영어, 200% | 실제 미디어 파일을 포함한 1080p 영상 다운로드 전체 과정 |

## 사례 하나 시작하기

각 사례에서 `$CaseId`, `$Language`, `$Dpi`를 해당 표의 값으로 바꾸세요. 아래
예시는 `ko-KR-100`을 시작합니다.

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

그다음 Windows 화면 배율을 해당 값으로 설정하고 `$CandidateExe`를 실행하세요.
앱의 설정 화면에서 도구 경로는 `$RunRoot`를, 다운로드 폴더는 `$RunRoot` 아래의
폴더를 가리키도록 설정하세요. 출력 위치를 봉인 후보나 `$EvidenceRoot`로 지정하지 마세요.

실제 앱 언어와 Windows 화면 배율을 확인한 뒤 환경을 기록하세요.

```powershell
& $Recorder -Action RecordEnvironment -CasePath $CasePath -ObservedLanguage $Language -ObservedDpiPercent $Dpi
```

## 순서대로 확인할 필수 관찰 항목 11개

각 항목을 직접 확인한 직후 해당 명령을 실행하세요. `-Result` 뒤의 값은 실제 결과에
따라 `true` 또는 `false`로 바꾸세요. 확인하기 전에 명령부터 실행하지 마세요.

1. `launch`: 기본 창이 나타나고 입력 초점을 받을 수 있으며 URL 칸에 짧은 시험
   값을 입력할 수 있는지 확인하세요. 이는 창 초점·입력 동작 확인 항목입니다.
2. `downloadType`: 동영상과 오디오 모드를 각각 선택할 수 있는지 확인한 뒤,
   화질 확인을 위해 동영상 모드로 돌아오세요.
3. `quality1080p`: 최대 1080p 프리셋을 선택하고 선택 상태가 화면에 유지되는지
   확인하세요.
4. `quality720p`: 최대 720p 프리셋을 선택하고 선택 상태가 화면에 유지되는지
   확인하세요.
5. `qualityBest`: 최고 화질 프리셋을 선택하고 선택 상태가 화면에 유지되는지
   확인하세요.
6. `expectedResolution`: 다시 1080p를 선택하세요. 1080p 영상과 음성이 제공되는
   공개 단일 영상을 분석한 뒤, 다운로드 조작부 근처에 선택 또는 예상 해상도와
   음성 포함 여부가 표시되는지 확인하세요.
7. `queueRegistration`: 실제 GUI 조작으로 분석한 항목을 추가하고 대기열에
   나타나는지 확인하세요.
8. `progress`: 실제 GUI에서 대기 중인 항목을 시작하고, 대기 상태만 표시되는 것이
   아니라 다운로드 진행 상태가 나타나는지 확인하세요.
9. `completion`: 앱이 완료를 보고한 뒤 완료 상태를 확인하세요. 실제 영상 결과물이
   필수인 두 사례에서는 완료 표시와 해당 파일이 일치해야 합니다.
10. `advancedNavigation`: 고급 설정 또는 형식 선택 화면이 열리는지 확인하세요.
    현재 사례의 증거를 수동으로 바꾸지 말고 이전 화면으로 돌아오세요.
11. `noClipping`: 해당 DPI에서 보이는 문구·선택 항목·예상 결과·대기열과 상태
    영역·관련 버튼을 확인하세요. 글자나 조작부가 하나라도 잘리면 `false`입니다.

각 항목을 확인한 뒤 아래 형태의 명령을 사용하세요.

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

아래 명령의 `true`는 문법 예시일 뿐입니다. 실제로 확인하지 못한 항목은
`false`로 기록하고, 그 경우 배포 단계로 진행하지 마세요.

## 스크린샷 기록

의미 있는 상태가 나타난 뒤 PNG로 캡처하세요. 최소한 1080p 예상 결과가 표시된
화면 한 장과 완료 또는 고급 설정 화면 한 장을 전체 창으로 찍는 것이 좋습니다.
원본 PNG를 `$EvidenceRoot` 밖에 저장한 다음 기록 스크립트로 첨부하세요.

```powershell
$Capture = 'C:\Users\ceo\Pictures\ko-KR-100-1080p.png'
& $Recorder -Action AddScreenshot -CasePath $CasePath -EvidenceFilePath $Capture -Label '1080p-result'
$ResolutionScreenshot = "screenshots/$CaseId-1080p-result.png"
```

기록 스크립트는 이미지를 증거 폴더로 복사하고 실제 해시·크기·가로세로 길이·
촬영 시각을 기록합니다. 복사된 파일은 이후 수정하지 마세요.

## 실제 완료 영상이 필요한 사례

`ko-KR-100`과 `en-US-200`에서는 영상과 음성 스트림이 모두 들어 있는 실제 완료
다운로드 파일을 사용하세요. 출력 형식은 `.mp4`, `.mkv`, `.webm` 중 하나여야
합니다. 예상 가로세로 길이는 화면에 표시된 값이면서 실제 다운로드 결과와도
일치해야 합니다. 검증 스크립트는 가로세로 중 짧은 변이 1080인지 확인합니다.

1920x1080 결과의 예시:

```powershell
$VideoOutput = 'C:\actual-downloads\example-1080p.mp4'
& $Recorder -Action AttachVideoLifecycle -CasePath $CasePath -EvidenceFilePath $VideoOutput -ExpectedWidth 1920 -ExpectedHeight 1080 -Result true
```

검증자가 직접 작성한 ffprobe JSON은 제출하지 마세요. 검증 스크립트가 봉인
후보의 `ffprobe.exe`로 복사된 결과물을 검사하고 표준 검사 증거를 생성합니다.

## 대표 기능 확인

### MP3 변환: `ko-KR-100`

영상 다운로드 확인을 마친 뒤 실제 GUI에서 오디오 모드를 선택하고 MP3 변환을
완료하세요. 만들어진 `.mp3` 파일을 기록하세요.

```powershell
$Mp3Output = 'C:\actual-downloads\example.mp3'
& $Recorder -Action RecordMp3 -CasePath $CasePath -EvidenceFilePath $Mp3Output -Result true
```

검증 스크립트는 MP3 컨테이너와 MP3 음성 스트림이 있고 일반 영상 스트림은
없는지 확인합니다. 파일 이름만으로는 통과할 수 없습니다.

### 설정 저장 후 재시작·복원: `ko-KR-150`

1. 임시 실행용 복사본에서 다운로드 폴더나 선택 언어처럼 화면에서 확인 가능한
   안전한 설정 하나를 바꾸세요.
2. 앱 화면에서 설정을 저장하고 앱을 정상적으로 종료하세요.
3. 같은 `$RunRoot\ytdlp-interface.exe`를 다시 실행하세요.
4. 변경한 설정값이 정확히 복원되었는지 확인하세요.
5. 복원된 값이 보이도록 전체 화면 PNG를 찍어 첨부하고, 해당 스크린샷 경로로
   대표 기능 확인 결과를 기록하세요.

```powershell
$Capture = 'C:\Users\ceo\Pictures\ko-KR-150-settings-restored.png'
& $Recorder -Action AddScreenshot -CasePath $CasePath -EvidenceFilePath $Capture -Label 'settings-restored'
$RestoreScreenshot = "screenshots/$CaseId-settings-restored.png"
& $Recorder -Action RecordSettingsRestore -CasePath $CasePath -ScreenshotReferencePath $RestoreScreenshot -Result true
```

### 이전 버전 설정 전환: `ko-KR-200`

이전 설치본에서 실제로 사용한 karon.2 이전 버전의 `ytdlp-interface.json`을
사용하세요. 먼저 백업한 뒤 임시 `$RunRoot`에만 복사하세요. `$SealedRoot`에
넣거나 이전 JSON 키를 추측해서 직접 만들어서는 안 됩니다.

1. 실제 이전 버전 설정 파일이 들어 있는 임시 복사본을 실행하세요.
2. 앱이 새 권장 기본 정책을 몰래 적용하지 않고 기존 설정·사용자 지정 동작을
   고급 모드에 보존하는지 확인하세요.
3. 화면에서 권장 기본 설정으로 돌아가는 동작을 사용하세요.
4. 전환이 명시적으로 이루어졌는지 확인하고 결과가 보이는 전체 화면 PNG를
   찍으세요.
5. 캡처를 첨부하고 대표 기능 확인 결과를 기록하세요.

```powershell
$Capture = 'C:\Users\ceo\Pictures\ko-KR-200-legacy-transition.png'
& $Recorder -Action AddScreenshot -CasePath $CasePath -EvidenceFilePath $Capture -Label 'legacy-transition'
$LegacyScreenshot = "screenshots/$CaseId-legacy-transition.png"
& $Recorder -Action RecordLegacyTransition -CasePath $CasePath -ScreenshotReferencePath $LegacyScreenshot -Result true
```

실제 이전 버전 설정 파일이 없다면 이 항목을 PASS로 기록하지 마세요. 검증
스크립트를 실행하기 전에 중단하고 필요한 증거 입력이 없다고 보고하세요.

## 여섯 사례 마무리

각 사례의 환경, 11개 관찰 결과, 스크린샷, 해당 사례에 배정된 대표 증거가
모두 준비된 뒤에만 사례를 마무리하세요.

```powershell
& $Recorder -Action Finalize -CasePath $CasePath
```

다음 사례별 변수로 반복하세요.

```text
ko-KR-100 / ko-KR / 100
ko-KR-150 / ko-KR / 150
ko-KR-200 / ko-KR / 200
en-US-100 / en-US / 100
en-US-150 / en-US / 150
en-US-200 / en-US / 200
```

## 모든 증거가 완성된 뒤에만 검증

수정하지 않은 실행용 복사본 하나를 `$VerifierRunRoot`로 선택하세요. 그 안의
EXE·ffprobe·manifest는 봉인 후보와 바이트 단위로 동일해야 합니다. 그다음
아래 명령을 실행하세요.

```powershell
$VerifierRunRoot = Join-Path $RuntimeParent 'en-US-200'
& $Verifier `
  -EvidenceRoot $EvidenceRoot `
  -CandidateExePath (Join-Path $VerifierRunRoot 'ytdlp-interface.exe') `
  -CandidateManifestPath (Join-Path $VerifierRunRoot 'candidate-manifest.json') `
  -OutputDirectory $VerifierOutput
```

PASS하면 아래 출력 폴더가 생성됩니다.

```text
<VerifierOutput>\gui-validation-v2.19.1-karon.2\
```

이 폴더에는 `gui-validation-summary.json`과
`gui-validation-evidence-manifest.json`이 들어 있습니다. 이 명령이 성공한
뒤에만 최종 ZIP 제작, 라이선스 판정, 정확한 대상 커밋의 CI, 릴리스 게이트
순서로 진행할 수 있습니다.
