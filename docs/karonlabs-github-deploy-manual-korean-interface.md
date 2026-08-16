# KaronLabs `ytdlp-korean-interface` 배포(SSH) 매뉴얼

이 문서는 `E:\03_AllWork\ytdlp-korean-interface\src` 기준으로  
`KaronLabs/ytdlp-korean-interface`에 SSH 방식으로 안전하게 푸시하기 위한 규칙입니다.

## 0. 원칙(필수 준수)

- 배포 대상: `https://github.com/KaronLabs/ytdlp-korean-interface`
- 원격 URL: `git@github.com:KaronLabs/ytdlp-korean-interface.git`
- 배포 브랜치: `main` 고정
- `git push --force` / 강제 우회 금지
- 푸시 전·후 원격 SHA 비교(동시 푸시 감지)
- 작업 트리와 스테이징 범위 분리, 무관 파일 혼합 금지

> 로컬 SSH 키 정책(권장):  
> `C:\Users\Administrator\.ssh\config`의 `Host github.com`에 사용할 키를 고정해 두면
> 호스트별 키 충돌로 인한 인증 실패를 줄일 수 있습니다.

```
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/new-api-key
```

⚠️ 위 설정은 작업자 로컬 환경용입니다. `.ssh/config` 자체를 이 저장소에 커밋하지 않습니다.

## 1) 작업 루트 고정

```powershell
Set-Location -LiteralPath "E:\03_AllWork\ytdlp-korean-interface\src"
git rev-parse --show-toplevel
```

`...\\ytdlp-korean-interface\\src`가 아니라면 중단하고 경로를 수정하세요.

## 2) GitHub 인증 확인

```powershell
ssh -T git@github.com
```

성공 응답은 보통 `Hi <user>! You've successfully authenticated...` 형태입니다.

## 3) origin 정합성 확인/보정

```powershell
git -C E:\03_AllWork\ytdlp-korean-interface\src remote -v
git -C E:\03_AllWork\ytdlp-korean-interface\src remote set-url origin git@github.com:KaronLabs/ytdlp-korean-interface.git
git -C E:\03_AllWork\ytdlp-korean-interface\src remote get-url origin
```

최종 출력이 `git@github.com:KaronLabs/ytdlp-korean-interface.git`인지 확인하세요.
다르면 중단 후 재설정합니다.

## 4) 배포 전 상태 점검

```powershell
git -C E:\03_AllWork\ytdlp-korean-interface\src status --short
git -C E:\03_AllWork\ytdlp-korean-interface\src rev-parse --abbrev-ref HEAD
```

- `status --short`는 빈 값이어야 기본 게이트 통과입니다.
- `main` 외 브랜치에서 푸시할 예정이라면 먼저 `main`으로 이동하거나 정책상 `HEAD:refs/heads/main`로 강제 동기화를 다시 검토하세요.

## 5) 변경 커밋(스코프 분리)

무관 파일은 섞지 않습니다.

```powershell
git -C E:\03_AllWork\ytdlp-korean-interface\src add -- README.md
git -C E:\03_AllWork\ytdlp-korean-interface\src commit -m "docs: localize README and document upstream diff"
```

예시: 배포 문서만 수정한 경우

```powershell
git -C E:\03_AllWork\ytdlp-korean-interface\src add -- docs/karonlabs-github-deploy-manual-korean-interface.md
git -C E:\03_AllWork\ytdlp-korean-interface\src commit -m "docs: align SSH deploy flow for main branch and remote SHA checks"
```

## 6) 푸시 SHA 게이트

```powershell
$branch = "main"
$remoteBefore = ((git -C E:\03_AllWork\ytdlp-korean-interface\src ls-remote origin ("refs/heads/$branch")) | Out-String).Trim()
Write-Output "REMOTE_BEFORE=$remoteBefore"

$localSha = ((git -C E:\03_AllWork\ytdlp-korean-interface\src rev-parse HEAD) | Out-String).Trim()
Write-Output "LOCAL_SHA=$localSha"

git -C E:\03_AllWork\ytdlp-korean-interface\src push origin HEAD:refs/heads/main

$remoteAfterRaw = ((git -C E:\03_AllWork\ytdlp-korean-interface\src ls-remote origin ("refs/heads/$branch")) | Out-String).Trim()
$remoteAfter = if ([string]::IsNullOrWhiteSpace($remoteAfterRaw)) { "" } else { ($remoteAfterRaw -split '\s+')[0] }
Write-Output "REMOTE_AFTER=$remoteAfter"

if ([string]::IsNullOrWhiteSpace($remoteAfter)) { throw "원격 SHA 조회 실패" }
if ($remoteAfter -ne $localSha) { throw "원격 SHA 불일치: expected=$localSha actual=$remoteAfter" }

# 원격 변경 감지(동시 푸시)
if (-not [string]::IsNullOrWhiteSpace($remoteBefore)) {
  $remoteBeforeSha = ($remoteBefore -split '\s+')[0]
  if ($remoteBeforeSha -ne $remoteAfter) {
    Write-Output "WARN: remote-before/after changed by third-party push in flow."
  }
}
```

> 권고: 실제 운영에서는 `git ls-remote` 결과에서 해시 부분만 추출해 비교하면 경고 정확도가 높아집니다.

## 7) 최초 main 부트스트랩(선택)

원격 `main`이 존재하지 않는 초기 상태는 아래 명령만 허용합니다.

```powershell
& 'E:\03_AllWork\ytdlp-korean-interface\src\tools\deploy-ssh-main.ps1' -AllowMainBootstrap
```

이 플래그는 승인된 최초 배포에서만 사용합니다.

## 8) 스크립트 추천 플로우

반복 실행을 줄이려면 아래 스크립트 사용을 권장합니다.

```powershell
& 'E:\03_AllWork\ytdlp-korean-interface\src\tools\deploy-ssh-main.ps1'
```

`deploy-ssh-main.ps1`는 다음을 강제합니다.

- origin URL 검증 (`git@github.com:KaronLabs/ytdlp-korean-interface.git`)
- working tree 정합성 또는 명시 StagePaths 검증
- 푸시 전 원격 SHA 보관, 푸시 후 동일 SHA 확인
- `main` 브랜치 강제 푸시 (`HEAD:refs/heads/main`)
- `-AllowMainBootstrap` 없이는 빈 `main` 허용하지 않음
- `--force` 사용 차단
