# KaronLabs `ytdlp-korean-interface` 배포(SSH) 매뉴얼

이 문서는 `E:\03_AllWork\ytdlp-korean-interface\src` 기준으로  
`KaronLabs/ytdlp-korean-interface`의 `main`에 SSH 방식으로 안전하게 배포하기 위한 규칙입니다.

실제 변경 배포의 기준 구현은 [`tools/deploy-ssh-main.ps1`](../tools/deploy-ssh-main.ps1)입니다.  
수동 명령은 상태 확인과 복구용으로만 사용하고, 정상 배포에서는 스크립트를 사용합니다.

## 0. 보안 원칙 — 고정값은 고정값으로 둡니다

아래 값은 운영자 입력으로 바꾸지 않습니다.

- canonical repository: `https://github.com/KaronLabs/ytdlp-korean-interface`
- canonical SSH URL: `git@github.com:KaronLabs/ytdlp-korean-interface.git`
- remote name: `origin`
- deployment branch: `main`
- expected GitHub SSH login: `KaronLabs`
- `git push --force`, `--force-with-lease` 및 기타 강제 우회 금지
- `main` 이외의 현재 브랜치에서는 배포 금지
- push 전·직전·후 원격 SHA 확인
- 실제 push source는 mutable `HEAD`가 아니라 검증된 40자리 commit SHA
- 기존 staged 변경과 배포 대상 파일 혼합 금지
- `StagePaths`는 저장소 내부의 명시적 파일 경로만 허용; glob/pathspec magic/디렉터리 금지
- Git/SSH 검증 실패 시 fail closed

즉 이 스크립트는 "대충 맞는 원격으로 HEAD를 밀기"가 아니라, **검증한 커밋 하나를 검증한 목적지 하나에만 보내는 것**을 목표로 합니다.

## 1. 로컬 SSH 키 고정

권장 설정 위치:

`C:\Users\Administrator\.ssh\config`

```sshconfig
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/new-api-key
  IdentitiesOnly yes
```

`IdentitiesOnly yes`를 사용하면 ssh-agent에 여러 키가 올라가 있을 때 엉뚱한 GitHub 계정으로 인증되는 가능성을 줄일 수 있습니다.

> 이 설정은 작업자 로컬 환경용입니다. `.ssh/config`와 private key는 저장소에 커밋하지 않습니다.

## 2. 작업 루트 확인

```powershell
Set-Location -LiteralPath "E:\03_AllWork\ytdlp-korean-interface\src"
git rev-parse --show-toplevel
```

출력이 `...\ytdlp-korean-interface\src`가 아니면 배포를 중단합니다.

배포 스크립트도 이 경계를 자체 검증합니다.

## 3. GitHub SSH 계정 확인

```powershell
ssh -T git@github.com
```

이 저장소 배포에서는 단순히 `successfully authenticated` 문자열만 보이면 충분하지 않습니다.

정상 계정은 다음과 같이 **`KaronLabs`**로 식별되어야 합니다.

```text
Hi KaronLabs! You've successfully authenticated...
```

다른 GitHub login이 보이면 키 선택 또는 `~/.ssh/config`부터 수정합니다.  
`deploy-ssh-main.ps1`도 `KaronLabs`가 아닌 인증 결과를 거부합니다.

> GitHub의 `ssh -T`는 인증 성공 시에도 shell access를 제공하지 않는다는 이유로 일반적인 0이 아닌 종료 코드를 사용할 수 있습니다. 이 스크립트는 GitHub의 인증 메시지와 login을 검증합니다.

## 4. `origin` fetch/push URL 모두 확인

Git은 fetch URL과 push URL을 별도로 가질 수 있습니다.  
따라서 `git remote get-url origin` 하나만 확인하면 충분하지 않습니다.

```powershell
git -C E:\03_AllWork\ytdlp-korean-interface\src remote get-url --all origin
git -C E:\03_AllWork\ytdlp-korean-interface\src remote get-url --push --all origin
```

두 결과 모두 정확히 하나의 URL만 보여야 하며 값은 모두 아래와 같아야 합니다.

```text
git@github.com:KaronLabs/ytdlp-korean-interface.git
```

fetch URL 보정:

```powershell
git -C E:\03_AllWork\ytdlp-korean-interface\src remote set-url origin git@github.com:KaronLabs/ytdlp-korean-interface.git
```

별도 `pushurl`이 잘못 설정되어 있다면 제거한 뒤 다시 확인합니다.

```powershell
git -C E:\03_AllWork\ytdlp-korean-interface\src config --unset-all remote.origin.pushurl
```

`pushurl`이 원래 없었다면 위 명령은 "없음" 상태를 반환할 수 있습니다. 이후 반드시 두 `get-url` 명령으로 최종 상태를 다시 확인하세요.

배포 스크립트는 fetch URL과 effective push URL을 둘 다 검증하며, 실제 네트워크 push 역시 remote alias 대신 canonical SSH URL을 직접 사용합니다.

## 5. 현재 브랜치와 작업 상태 확인

```powershell
git -C E:\03_AllWork\ytdlp-korean-interface\src rev-parse --abbrev-ref HEAD
git -C E:\03_AllWork\ytdlp-korean-interface\src status --short
git -C E:\03_AllWork\ytdlp-korean-interface\src diff --cached --name-only
```

기본 배포 조건:

- 현재 브랜치가 정확히 `main`
- 일반 배포는 working tree가 clean
- `StagePaths` 모드는 시작 시 Git index가 clean

**`main`이 아닌 브랜치의 `HEAD`를 `main`으로 밀어 넣는 방식은 금지합니다.**  
먼저 의도한 변경을 `main`에 반영한 뒤 배포하세요.

## 6. 권장 배포 — 이미 커밋된 clean `main`

```powershell
& 'E:\03_AllWork\ytdlp-korean-interface\src\tools\deploy-ssh-main.ps1'
```

실제 push 전에 동작만 확인하려면:

```powershell
& 'E:\03_AllWork\ytdlp-korean-interface\src\tools\deploy-ssh-main.ps1' -WhatIf
```

`-WhatIf`에서는 push를 수행하지 않으며 `PUSH_OK` 대신 skip 상태로 종료합니다.

## 7. 특정 파일만 스테이징·커밋 후 배포

배포 스크립트가 명시된 파일만 literal pathspec으로 stage하도록 할 수 있습니다.

README만 수정한 경우:

```powershell
& 'E:\03_AllWork\ytdlp-korean-interface\src\tools\deploy-ssh-main.ps1' `
  -StagePaths @('README.md') `
  -CommitMessage 'docs: update README'
```

배포 문서만 수정한 경우:

```powershell
& 'E:\03_AllWork\ytdlp-korean-interface\src\tools\deploy-ssh-main.ps1' `
  -StagePaths @('docs/karonlabs-github-deploy-manual-korean-interface.md') `
  -CommitMessage 'docs: harden SSH deployment procedure'
```

### `StagePaths` 규칙

- 실행 전 이미 staged된 파일이 있으면 중단
- repository-relative file path만 허용
- `:(glob)**` 같은 Git pathspec magic 거부
- absolute path 거부
- 저장소 밖으로 빠져나가는 `..` 경로 거부
- `.git` metadata 경로 거부
- 디렉터리 자체를 대상으로 하는 broad staging 거부
- `git add` 후 예상하지 않은 staged path가 나타나면 중단
- commit 실패 시 중단

따라서 "README 하나 올리려다가 어제 올려둔 비밀파일까지 같이 커밋" 같은 사고를 막는 데 초점을 둡니다.

## 8. SHA / 동시 푸시 게이트

진단 목적으로 현재 값을 직접 확인할 수 있습니다.

```powershell
$repo = 'E:\03_AllWork\ytdlp-korean-interface\src'
$canonical = 'git@github.com:KaronLabs/ytdlp-korean-interface.git'

git -C $repo rev-parse --verify 'HEAD^{commit}'
git -C $repo ls-remote $canonical refs/heads/main
```

실제 배포 스크립트는 다음 순서로 처리합니다.

1. 원격 `main` SHA를 canonical URL에서 읽음
2. 로컬 `HEAD^{commit}`을 정확한 40자리 commit SHA로 확정
3. push 직전에 원격 SHA를 다시 읽어 동시 변경 감지
4. 정확한 commit SHA를 canonical SSH URL의 `refs/heads/main`으로 push
5. push command의 native exit code 확인
6. 원격 SHA를 다시 읽어 로컬 commit SHA와 완전 일치 확인
7. 모든 검증이 통과한 경우에만 `PUSH_OK=<sha>` 출력

정상 구현은 다음과 같은 **exact commit refspec**을 사용하며 mutable `HEAD`를 source로 사용하지 않습니다.

```text
<40-char-commit-sha>:refs/heads/main
```

> 수동 `git push origin HEAD:refs/heads/main`은 이 매뉴얼의 정상 배포 절차가 아닙니다.

## 9. 최초 `main` 부트스트랩

원격 `main`이 실제로 존재하지 않는 승인된 최초 배포만 다음 플래그를 사용합니다.

```powershell
& 'E:\03_AllWork\ytdlp-korean-interface\src\tools\deploy-ssh-main.ps1' -AllowMainBootstrap
```

평상시 원격 SHA를 읽지 못했다고 이 플래그로 우회하면 안 됩니다.  
네트워크/인증/Git 오류는 bootstrap으로 취급하지 않고 실패해야 합니다.

## 10. 스크립트가 강제하는 배포 보안 경계

`tools/deploy-ssh-main.ps1`는 현재 다음을 강제합니다.

- canonical repository / SSH URL / `origin` / `main`을 코드 내부 고정값으로 사용
- caller가 배포 대상 remote 또는 branch를 바꾸는 parameter 제공하지 않음
- 작업 루트 검증
- 현재 브랜치 `main` 검증
- GitHub SSH login `KaronLabs` 검증
- fetch URL과 push URL 모두 canonical URL인지 검증
- 별도 악성/오염 `remote.origin.pushurl` 거부
- clean working tree 또는 격리된 `StagePaths` 흐름
- 기존 staged 변경 혼입 차단
- StagePaths literal file isolation
- 모든 중요한 native Git command의 exit code 검사
- push 전/직전/후 원격 SHA 확인
- 검증된 exact commit SHA를 canonical URL에 직접 push
- push 후 remote SHA가 정확히 local SHA인지 확인
- `-AllowMainBootstrap` 없이는 빈 remote `main` 허용하지 않음
- force push 경로 제공하지 않음

## 11. 자동 보안 회귀 테스트

배포 경계는 GitHub Actions의 `Deploy SSH security contract` 워크플로에서 Windows PowerShell로 회귀 테스트합니다.

검증 항목에는 다음이 포함됩니다.

- caller가 remote/branch 정책을 바꾸려는 시도 거부
- non-main branch 배포 거부
- 별도/mismatched push URL 거부
- pre-staged unrelated file 혼입 거부
- Git pathspec magic 거부
- failed `git push`를 성공으로 오인하지 않음
- exact verified SHA + canonical URL push
- 잘못된 GitHub SSH login 거부

이 테스트는 실제 외부 저장소로 push하지 않고 Git/SSH 경계를 모킹하여 fail-closed 동작을 검증합니다.

---

요약하면:

> **`main` + KaronLabs SSH identity + canonical URL + clean index + exact commit SHA`가 모두 맞을 때만 push합니다.**

유튜브 다운로더 하나 배포하는데 경비실이 조금 진지해졌지만, 잘못된 저장소에 소스가 날아가거나 엉뚱한 staged 파일이 같이 출국하는 것보다는 낫습니다.
