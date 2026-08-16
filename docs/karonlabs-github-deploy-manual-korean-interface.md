# KaronLabs `ytdlp-korean-interface` 배포(SSH) 매뉴얼

이 문서는 `E:\03_AllWork\ytdlp-korean-interface\src` 기준으로
`KaronLabs/ytdlp-korean-interface`에 SSH 방식으로 안전하게 푸시하는 절차입니다.

## 0. 전제

- 배포 대상 저장소: `https://github.com/KaronLabs/ytdlp-korean-interface`
- SSH 원격: `git@github.com:KaronLabs/ytdlp-korean-interface.git`
- 배포 브랜치: `main`
- 강제 푸시 금지

## 1) GitHub 인증 확인

```powershell
ssh -T git@github.com
```

성공 응답은 보통 `Hi <user>! You've successfully authenticated...` 형태입니다.

## 2) 배포 루트 고정

```powershell
Set-Location -LiteralPath "E:\03_AllWork\ytdlp-korean-interface\src"
git rev-parse --show-toplevel
```

`src`가 출력되지 않으면 저장소 루트가 잘못 지정된 상태이므로 중단하세요.

## 3) origin 원격을 배포 저장소로 정렬

```powershell
git remote -v
git remote set-url origin git@github.com:KaronLabs/ytdlp-korean-interface.git
git remote -v
```

원격이 `KaronLabs/ytdlp-korean-interface`가 아니면 `origin`을 수정하고 재확인하세요.

## 4) 푸시 게이트(반드시 통과)

- `git status --short`가 비어 있어야 합니다.  
  - 또는 `-StagePaths` + `-CommitMessage`를 지정해 해당 파일만 커밋하는 방식을 사용해도 됩니다.
- 푸시 대상은 `main`입니다.
- `git push --force` 또는 강제우회 옵션을 사용하지 않습니다.

```powershell
$repoRoot = (git rev-parse --show-toplevel).Trim()
if ($repoRoot -notlike '*\ytdlp-korean-interface\src') { throw 'Repository root must be ...\\ytdlp-korean-interface\\src' }

git status --short
$remoteBefore = ((git ls-remote origin refs/heads/main) -split '\s+')[0]
if ([string]::IsNullOrWhiteSpace($remoteBefore)) { throw 'Could not read remote main SHA.' }
Write-Output "REMOTE_BEFORE=$remoteBefore"
```

## 5) 변경 커밋(선택, 권장)

이 단계는 변경이 있을 때만 수행합니다.

```powershell
git add -- README.md
git commit -m "release: update ..."
```

`git add -A`/`git add .` 대신 변경 파일을 명시적으로 지정하세요.

## 6) SHA 보호 푸시 + 검증

```powershell
$sha = (git rev-parse HEAD).Trim()
$remoteNow = ((git ls-remote origin refs/heads/main) -split '\s+')[0]
if ($remoteNow -ne $remoteBefore) { throw "원격이 변경됨: $remoteBefore -> $remoteNow" }

git push origin HEAD:refs/heads/main

$remoteAfter = ((git ls-remote origin refs/heads/main) -split '\s+')[0]
if ($remoteAfter -ne $sha) { throw "원격 SHA 불일치: expected=$sha actual=$remoteAfter" }
Write-Output "PUSH_OK=$sha"
```

### 최초 main 브랜치 부트스트랩

원격 `main`이 아직 없는 상태에서 첫 배포를 할 때는 다음 명령으로 시작하세요.

```powershell
& 'E:\03_AllWork\ytdlp-korean-interface\src\tools\deploy-ssh-main.ps1' -AllowMainBootstrap
```

`-AllowMainBootstrap` 옵션은 사전 승인된 첫 푸시에서만 사용하고, 사용 로그를 남겨야 합니다.

## 7) 스크립트 사용(권장)

검증 규칙을 반복 실수 없이 사용하려면 함께 제공되는 배포 스크립트를 사용하세요.

```powershell
& 'E:\03_AllWork\ytdlp-korean-interface\src\tools\deploy-ssh-main.ps1'
```

배포를 더 강하게 운영하려면 다음을 추가하세요.

- 푸시 전후 `git log -1 --oneline` 확인
- GitHub Actions 결과 확인 후 Cloudflare 배포
- 릴리스 태그 정책 적용
