# 재심청구서: KSC-INFRA-2026-0925-KARON2-REMOTE-MAIN-01

- 작성일: 2026-09-25
- 재심 대상: `e5c40d3b4a0d4a4f7fc364ff39af53f852a10640`
- 원심 대상: `bcd91dac8a04857d4d08a86461fc005e156fa8bd`
- 기능 소스: `32f03f99d1339aa5f8fd37a1f6a1904b6dad5a28` (변경 없음)
- 범위: CI trigger/계약 추가와 원심 공소의 사실관계 재정리
- 신청 상태: `partial_success`; 독립 판정: `PENDING`

## 공소별 답변

### 1. GUI/runtime 검증 미완료: 인정, 출시 보류

실제 6개 GUI 조합과 두 건의 완료 영상, MP3, 설정 복원, 기존 설정 전환 결과는 이 세션에서 생성하지 않았습니다. 형님이 Windows에서 sealed 후보를 직접 조작해 주시는 기존 수동 증거 계약을 유지합니다. `gui-validation-summary.json`의 PASS, 최종 ZIP, 태그, Release를 주장하지 않습니다. 후보 EXE와 기능 소스도 수정하지 않았습니다.

### 2. exact-target CI 부재: 시정 작업 제출, 결과 미판정

원심 SHA `bcd91dac...`의 run 0건은 반박하지 않습니다. 기존 `release-factory-contract.yml`은 `karon.2` 주요 경로를 push filter에서 누락했습니다. 별도 `.github/workflows/karon2-quality-contract.yml`을 추가하고 원격 `main`에 `e5c40d3...`으로 게시했습니다. 새 workflow는 `main` push, PR, 수동 실행에 대응하며 Karon.2 소스·테스트·릴리스 입력 경로 변경 시 Windows 2022에서 다음 기존 테스트 진입점을 실행하도록 정의합니다.

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/test-quality-policy.ps1
python -m unittest discover -s tests/quality -p 'test_*.py'
tests/powershell/gui-release-evidence-contract.Tests.ps1
tests/powershell/release-license-lock.Tests.ps1
tests/powershell/release-publication-contract.Tests.ps1
```

이것은 CI **설정 변경**의 증거이지 CI 성공 증거가 아닙니다. 이 세션에서는 새 workflow의 run ID, 각 job 결과, exact head SHA를 독립 검증하지 않았습니다. 재판부가 `head_sha=e5c40d3...`의 모든 required job을 확인하기 전까지 `CI: NOT_VERIFIED`입니다. GitHub의 path filter는 push의 변경 파일에 적용되고 수동 실행은 `workflow_dispatch`로 별도 시작할 수 있습니다: <https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax>.

### 3. application source/license identity: 불일치 인정, 단순 SHA 치환 처방은 반박

tracked lock의 application source와 sealed 후보의 source가 다른 것은 사실입니다. 다만 tracked lock은 **목표 의존성 조합을 기술한 미검증 템플릿**이고, `release/licenses/v2.19.1-karon.2/application/SOURCE-STATUS.txt`는 현재 sealed 후보가 목표 후보가 아니라고 이미 명시합니다. 실제 입력을 읽은 원시 출력은 다음과 같습니다.

```text
candidate-manifest.json:
  applicationSourceCommit = 32f03f99d1339aa5f8fd37a1f6a1904b6dad5a28
  applicationSourceTree   = 14995ebe0132bfc3b78e7b774f924c16c29a1e0f
  7z.dll SHA-256          = 1A482E7ED19B1C7A547558E6E728CC4E4215AA9A98846702DBD8C1E22419C6E0
  yt-dlp.exe SHA-256      = A3A504C66E91F6474CEF0BE83B16AEDFB7B42B9400A962242D0D433E98F67A70
  ytdlp-interface.exe     = BEBADE61F980CADA9D338A4C32DF77E0122C18BBF07E4E95E4F056C93008F6CA

tracked license lock:
  application.sourceCommit = 8f776b34cf9e644accb9f5e1230dd7e1b24d3def
  application.sourceArchive = karon-8f776b34.zip
  7zip target version = 26.01; candidate 7z.dll SHA-256 = null
  yt-dlp target version = 2026.08.04.234419
  yt-dlp.exe SHA-256 = e78500d301b5de3a9280a418f6dd45604c4d85b718b0a2447c1b0aa9699e2689
  release.verificationStatus = NOT_VERIFIED
```

따라서 `8f776...`만 `32f03...`으로 바꾸면 application source 필드 하나는 맞더라도 7-Zip과 yt-dlp 바이너리 결속이 틀립니다. 실제 대응 소스 ZIP의 파일명·길이·SHA, 비런타임 source manifest/inventory, 구성요소별 고지도 재생성해야 합니다. `build-release-license-lock.ps1`가 불일치를 거부하는 동작은 정상적인 fail-closed 게이트입니다. `release/dependencies/v2.19.1-karon.2.lock.json`, `THIRD-PARTY-NOTICES.txt`, 후보 manifest를 임의 수정하지 않았습니다.

현재 승인된 정책인 '클린 의존성을 포함한 최종 휴대용 ZIP'과 '기존 sealed 후보 바이트 유지'를 동시에 만족하는 최종 패키지 후보는 아직 제시되지 않았습니다. 새 후보가 필요하면 기존 sealed 후보를 덮어쓰지 말고 별도 후보로 생성한 다음, **그 새 EXE/런타임 조합에 대해 GUI와 라이선스 검증을 다시 결속**해야 합니다. 어느 경로도 완료되기 전에는 final ZIP을 생성하지 않습니다.

## 이번 변경과 남은 게이트

변경 파일: `.github/workflows/karon2-quality-contract.yml` 하나. 원심 기능 C++ 코드, GUI 가이드, 기존 CI, 후보 EXE, lock, notice는 그대로입니다.

| 게이트 | 현재 상태 | 판정에 필요한 다음 증거 |
| --- | --- | --- |
| GUI 6종 및 실제 영상/MP3/설정 | `NOT_RUN` | 형님의 실제 관찰값, PNG·미디어·검증기 PASS |
| 새 exact-target CI | `NOT_VERIFIED` | `e5c40d3...`의 run URL, head SHA, required jobs 성공 |
| 후보와 대응 소스/라이선스 결속 | `FAIL-CLOSED` | 최종 의존성 정책과 일치하는 후보·source archive·고지·lock 검증 |
| 최종 ZIP/공개 릴리스 | `HOLD` | 앞선 게이트 통과 후 ZIP 자체 판정 |

재판부에는 공소 #2의 구조적 누락을 시정한 코드 변경을 심리하되, 아직 없는 GUI·CI·라이선스 PASS를 승인 근거로 취급하지 않기를 요청합니다. 원심의 825-file provenance 및 한국어 가이드 PASS 판정은 다투지 않습니다.
