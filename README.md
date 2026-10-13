# ytdlp-korean-interface

**명령어 대신 클릭으로. 한국어로 사용하는 Windows용 영상·음악 다운로더.**

yt-dlp를 한국어 화면에서 사용할 수 있도록 만든 Windows용 GUI입니다.
영상 주소를 넣고 화질을 고르면 다운로드와 필요한 영상·음성 병합을 처리합니다.

## 다운로드

### [Windows x64 실행용 ZIP 다운로드 — 약 188MB](https://github.com/KaronLabs/ytdlp-korean-interface/releases/download/v2.19.1-karon.2/ytdlp-korean-interface-v2.19.1-karon.2-win-x64.zip)

**Download for Windows (x64)** · 현재 공개 버전: **`v2.19.1-karon.2`**

**일반 사용자는 이 ZIP 하나만 받으시면 됩니다.**

파일 이름: `ytdlp-korean-interface-v2.19.1-karon.2-win-x64.zip`

[릴리즈 안내 및 SHA-256 확인](https://github.com/KaronLabs/ytdlp-korean-interface/releases/tag/v2.19.1-karon.2)

> `corresponding-sources`, `SPDX`, GitHub의 **Source code (zip)** 및 **Code → Download ZIP**은 실행용이 아닙니다.
> 소스 묶음까지 받으실 필요는 없습니다. 프로그램 대신 개발 창고를 받게 됩니다.

## 처음 사용하는 방법

1. 위 **Windows x64 실행용 ZIP**을 다운로드합니다.
2. ZIP **전체를 한 폴더에 압축 해제**합니다. 압축 파일 안에서 바로 실행하지 마세요.
3. 폴더 안의 **`ytdlp-interface.exe`**를 실행합니다.
4. 다운로드할 영상 주소를 입력합니다.
5. 다운로드 종류와 화질, 저장 위치를 선택합니다. 처음이라면 **동영상 / 최대 1080p**부터 사용해 보세요.
6. **다운로드 예정 화질**을 확인한 뒤 다운로드를 시작합니다. 완료된 파일은 선택한 저장 위치에서 확인합니다.

FFmpeg·ffprobe·Deno 등 실행에 필요한 구성요소가 함께 들어 있습니다.
**EXE만 따로 옮기지 말고 압축을 푼 폴더 전체를 유지해 주세요.**

## 주요 기능

| 기능 | 이렇게 사용합니다 |
| --- | --- |
| 한국어 인터페이스 | 메뉴와 설정을 한국어로 사용합니다. 영어도 지원합니다. |
| 간단한 화질 선택 | 최대 1080p, 최대 720p, 최고 화질 중 선택합니다. |
| 음악만 저장 | 오디오 모드에서 MP3로 변환합니다. |
| 영상·음성 병합 | 따로 제공되는 영상과 음성을 동봉된 FFmpeg로 합칩니다. |
| 다운로드 대기열 | 여러 작업을 등록하고 작업별 다운로드 정책을 유지합니다. |
| 고급 설정 | 형식 직접 선택, 사용자 지정 인수, 외부 yt-dlp 설정 등 기존 기능을 사용합니다. |

## 어떤 화질을 고르면 되나요?

| 선택 | 추천 상황 | 동작 |
| --- | --- | --- |
| **최대 1080p** | 처음 사용하거나 일반적인 영상 감상 | 현재 접근 가능한 형식에서 1080p 이하의 영상과 음성을 선택합니다. 신규 사용자 기본값입니다. |
| **최대 720p** | 파일 용량을 줄이고 싶을 때 | 현재 접근 가능한 형식에서 720p 이하의 영상과 음성을 선택합니다. |
| **최고 화질** | 해상도 상한 없이 받고 싶을 때 | 현재 접근 가능한 형식 중 최고 화질을 선택합니다. 파일이 커질 수 있습니다. |
| **오디오 / MP3** | 음악이나 강의의 소리만 필요할 때 | 영상을 저장하는 대신 음성을 MP3로 변환합니다. |
| **고급** | 형식과 옵션을 직접 지정하고 싶을 때 | 기존 수동 선택과 사용자 지정 설정을 사용합니다. |

**1080p가 없는 영상이 1080p로 만들어지는 것은 아닙니다.**
원하는 해상도보다 낮은 형식만 확인되면 그에 맞는 예정 화질이 표시됩니다.
상한을 초과하는 형식이나 필요한 음성을 확인할 수 없는 경우에는 안내를 확인하고 선택을 바꿔 주세요.
화질 숫자는 가로·세로 중 작은 변을 기준으로 하며, 해상도를 높이기 위한 자동 재인코딩은 하지 않습니다.

기본 모드는 화면에서 선택한 설정을 사용하며, 사용자 지정 인수와 외부 yt-dlp 설정은 적용하지 않습니다.
기존 사용자 설정은 고급 모드로 보존됩니다. 기본 프리셋을 사용하려면 직접 기본 모드로 전환해 주세요.

## 자주 묻는 질문

### 파일이 많은데 무엇을 받아야 하나요?

이름이 **`-win-x64.zip`**으로 끝나는 파일만 받으시면 됩니다.
대응 소스는 개발·재배포용이고, SPDX는 구성요소와 라이선스 정보입니다. 일반적인 실행에는 필요하지 않습니다.

### 형식 목록에 360p만 보이는 것 같은데요?

영상과 음성이 **한 파일로 합쳐진 형식**에는 낮은 해상도만 있을 수 있습니다.
더 높은 화질이 **영상 전용 형식**으로 따로 제공되는 경우도 있습니다.
목록의 첫 줄만 보고 최대 화질로 생각하지 마시고, 기본 모드에서 프리셋을 선택한 뒤 **다운로드 예정 화질**을 확인해 주세요.

원하는 화질이 조회되지 않는 이유는 영상 자체의 제공 형식, 접근 권한, 사이트 변경 등으로 달라질 수 있습니다.
항상 1080p 이상을 보장하지는 않습니다.

### MP4가 아니라 WebM이나 MKV가 저장됐어요.

정상일 수 있습니다. 화질을 낮춰 MP4에 맞추는 대신, 선택한 영상·음성 코덱에 적합한 저장 형식을 사용합니다.
MP4만 항상 생성되는 것은 아니며, 모든 재생기에서 같은 코덱을 지원하는 것도 아닙니다.

### 다운로드가 100%인데 아직 처리 중이에요.

영상·음성 병합, MP3 변환 또는 최종 파일 확인이 남아 있을 수 있습니다.
특히 긴 영상의 오디오 변환은 시간이 걸립니다. 출력 로그의 진행 상태를 확인해 주세요.

### EXE만 바탕화면으로 옮겨도 되나요?

실행에 필요한 다른 파일을 찾지 못할 수 있습니다. **폴더 전체를 유지하고 EXE의 바로가기를 만드시는 편이 좋습니다.**

### 특정 사이트나 영상에서 다운로드가 실패해요.

사이트 변경, 네트워크, 로그인·접근 제한 등 여러 원인이 있을 수 있습니다.
오류가 나면 주소와 선택한 모드, 출력 로그의 오류 내용을 확인해 주세요.
문제를 제보할 때 쿠키·인증 정보·개인 경로 등 민감한 내용은 지워 주세요.

[문제 제보하기](https://github.com/KaronLabs/ytdlp-korean-interface/issues)

## 이 프로젝트는 무엇인가요?

세 프로젝트의 역할은 다음과 같습니다.

| 프로젝트 | 역할 |
| --- | --- |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | 사이트 분석과 미디어 다운로드를 담당하는 엔진 |
| [ErrorFlynn/ytdlp-interface](https://github.com/ErrorFlynn/ytdlp-interface) | yt-dlp를 화면에서 조작하는 Windows GUI. 이 저장소의 직접적인 upstream |
| **KaronLabs/ytdlp-korean-interface** | `ytdlp-interface v2.19.1`을 기반으로 한국어 UI와 화질 선택, 설정·대기열 흐름을 개선한 파생 프로젝트 |

**yt-dlp 엔진을 새로 만든 프로젝트가 아니며, yt-dlp 또는 ErrorFlynn의 공식 배포판도 아닙니다.**
원본 개발자와 기여자들의 작업을 바탕으로 유지보수합니다.

## 알아두실 점

- 배포 대상은 **Windows x64**입니다. macOS·Linux용 GUI는 제공하지 않습니다.
- 한국어(`ko-KR`)와 영어(`en-US`)를 지원합니다.
- 새 기본 화질 프리셋은 개별 영상과 대기열 작업에 적용합니다. **재생목록과 라이브**는 기존 고급 기능으로 이용해 주세요.
- 이용할 권한이 있는 콘텐츠에 사용해 주세요.
- 이번 릴리즈는 자동 계약 테스트와 배포 자산의 다운로드 일치 확인을 완료했습니다.
- **한국어·영어 및 100%·150%·200% 배율의 GUI 전체 수동검증은 소유자 결정으로 생략했습니다(`WAIVED_BY_OWNER`).** 전체 GUI 검증 완료를 의미하지 않습니다.

## 라이선스와 개발 정보

**애플리케이션 소스는 MIT License**입니다. [LICENSE](LICENSE)를 확인해 주세요.

함께 배포되는 제3자 구성요소에는 각각의 라이선스가 적용됩니다.
이번 릴리즈의 PyInstaller 기반 `yt-dlp.exe` 결합 실행 파일은 **GPL-3.0-or-later**이며, yt-dlp 원본 소스는 Unlicense입니다.
실행용 ZIP 전체에 MIT만 적용되는 것으로 보시면 안 됩니다.

[제3자 구성요소 고지](THIRD-PARTY-NOTICES.txt) · [현재 릴리즈와 대응 소스](https://github.com/KaronLabs/ytdlp-korean-interface/releases/tag/v2.19.1-karon.2)

대응 소스가 필요한 개발·재배포 사용자는 릴리즈의 `corresponding-sources.zip.part0001`부터 모든 분할 파일과 `.restore.ps1`, `.restore.txt`, `.transport.json`을 함께 받으신 뒤, 동봉된 복원 안내를 따라 주세요.

<details>
<summary>개발·기여 및 프로젝트 기록</summary>

### 원본과 기여 기록

- [NOTICE](NOTICE): 원본 프로젝트와 계보 안내
- [PROVENANCE.md](PROVENANCE.md): upstream 기준선과 프로젝트 이력
- [ATTRIBUTION.md](ATTRIBUTION.md): 기여 표기 안내
- [CITATION.cff](CITATION.cff): 인용 메타데이터
- [원산지 기록 정정 절차](docs/provenance-dispute-response.md)

### 개발과 검증

Visual Studio 솔루션은 `ytdlp-interface/ytdlp-interface.sln`이며, 빌드 대상은 **Release / x64**입니다.
의존성 구성은 [직접 upstream의 안내](https://github.com/ErrorFlynn/ytdlp-interface)와 저장소의 빌드 도구를 참고하세요.

- [설정 복구 및 yt-dlp 유지보수 도구](docs/runtime-maintenance.md)
- [화질 프리셋 설계와 구현 범위](docs/superpowers/plans/2026-09-16-quality-presets.md)
- [현재 릴리즈 상세 안내](release/notes/v2.19.1-karon.2.md)
- [GUI 수동검증 안내](release/validation/v2.19.1-karon.2/MANUAL-GUI-EVIDENCE-GUIDE.md)
- [자동 검증 워크플로](https://github.com/KaronLabs/ytdlp-korean-interface/actions)

저장소 계약 테스트:

```bash
python tests/run_contract_tests.py
```

Native C++ 테스트는 `tests/native/`, PowerShell 테스트는 `tests/powershell/`에 있습니다.

### 이전 버전

- [v2.19.1-karon.1](https://github.com/KaronLabs/ytdlp-korean-interface/releases/tag/v2.19.1-karon.1): 최초 KaronLabs 공개 릴리즈. 현재 다운로드는 위의 `karon.2`를 사용해 주세요.

</details>
