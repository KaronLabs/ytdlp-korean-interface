# 코드대법원 재심청구서

사건번호: `KSC-INFRA-2026-0916-QP-01`

피고인: `KaronLabs/ytdlp-korean-interface` Quality Presets 변경분

원심 심판대상: `e36fe2894a80021ac9b7218c73173552d90e0063`

비교기준: `baf39d25370e05a69814357cd2d0a5cb10696910`

청구일: `2026-09-16`

## 1. 청구 취지

피고인은 원심의 모든 지적을 일괄 부정하지 않습니다. 다음과 같이 공소별 처분을 구합니다.

1. 공소 #2 `Exact review target 독립 검토 불가`는 원심 기록과 최초로 문서화된 pre-push 관찰에 부합합니다. 다만 그 관찰에는 원심 제출 시각과 기계적으로 결속된 별도 타임스탬프가 없습니다. 현재는 exact target 공개 조치와 독립 재검증으로 결함이 치유됐으므로 현재 상태에 대한 공소를 기각해 주십시오.
2. `실제 online YouTube path`를 required validation으로 묶은 부분은 원 명세의 `required: false`와 충돌하므로 해당 부분을 증거 오류로 기각해 주십시오.
3. `30 changed files / 8 commits`는 로컬 작성자 진술을 넘어 독립 Git 검사와 GitHub compare API로 확인됐으므로 UNVERIFIED 상태를 해제해 주십시오.
4. exact target CI identity 부재는 새 run `35031230121`로 시정됐음을 인정해 주십시오. 단, 이 run은 provenance contract만 검증하므로 품질 기능 전체 CI PASS로 확대하지 마십시오.
5. GUI/lifecycle, 여섯 locale/DPI 조합, public-binary license gate 미완료는 정당한 공소로 인정합니다. 특히 license gate는 독립 검토 결과 `NOT_VERIFIED`가 아니라 `FAIL`로 강화 정정합니다.
6. 본 재심은 30-file 구현의 새로운 의미적 코드 리뷰를 수행하지 않았으며 무결점 주장을 하지 않습니다. 원심이 구체적인 기능 코드 결함을 제시하지 않았으므로 추측성 변경은 하지 않고, 남은 심리를 위 세 required gate로 한정해 주십시오.

요청 처분: `원심 일부 취소, 공소 범위 축소, 잔존 required gates에 대한 계속심리`

피고인 상태: `partial_success`

독립 판결 요청: `PENDING`

## 2. 공소별 답변

### 공소 #1: Required 검증 미완료

판정: `부분 인정`

인정 범위:

- 최종 후보 GUI/lifecycle: `NOT_VERIFIED`
- 한국어·영어 × 100%·150%·200%: `NOT_VERIFIED`
- public-binary third-party license gate: `FAIL`
- 공개 배포: 위 gate가 열려 있어 의도적으로 `HOLD`

반박 범위:

- 온라인 YouTube는 원심 명세에서 `required: false`입니다.
- 원심의 “required라면 실제 online YouTube path를 완료해야 한다”는 일반론은 맞지만, 본 사건의 해당 criterion은 required가 아닙니다.
- 따라서 온라인 미실행을 required completion failure에 합산한 부분은 원 명세와 배치됩니다.

원시 명세 항목:

```text
criterion: Current online YouTube extraction produces the intended high-quality result with the candidate runtime.
required: false
result: NOT_VERIFIED
verification: Online integration was not executed.
```

독립 재검증:

```text
Claim 3 verdict: FAIL
The spec marks current online YouTube extraction required:false.
The packaging report's required IDs contain no online-YouTube check.
```

결론: GUI/DPI/license 미완료 공소는 유지하되, 온라인 YouTube 부분은 기각해야 합니다.

### 공소 #2: Exact review target 독립 검토 불가

판정: `최초 문서화된 pre-push 관찰에서 부재, 현재 시정 완료`

시간적 한계:

- 독립 검증자의 최초 pre-push 원격 조회에는 별도 wall-clock timestamp가 없습니다.
- 따라서 ref 부재를 원심 제출의 정확한 순간과 기계적으로 결속하지 않습니다.
- 다만 원심 명세의 local-only 신고와 최초 문서화된 pre-push 관찰은 서로 일치합니다.

시정 조치:

- force push 없이 새 검토 전용 ref를 생성했습니다.
- `main`은 변경하지 않았습니다.
- 공개 ZIP, tag, release도 생성하지 않았습니다.

실행 전 원격:

```text
refs/heads/review/quality-presets-e36fe28: absent
refs/heads/main: baf39d25370e05a69814357cd2d0a5cb10696910
```

SSH 인증:

```text
Hi KaronLabs! You've successfully authenticated, but GitHub does not provide shell access.
ssh exit: 1
```

push 결과:

```text
PushExit: 0
[new branch] e36fe2894a80021ac9b7218c73173552d90e0063 -> review/quality-presets-e36fe28
```

push 후 원격:

```text
e36fe2894a80021ac9b7218c73173552d90e0063 refs/heads/review/quality-presets-e36fe28
```

독립 검증자의 별도 조회:

```powershell
git -C E:/03_AllWork/ytdlp-korean-interface/.worktrees/quality-presets ls-remote --heads origin refs/heads/review/quality-presets-e36fe28
```

```text
e36fe2894a80021ac9b7218c73173552d90e0063 refs/heads/review/quality-presets-e36fe28
```

공개 검토 주소:

- Commit: https://github.com/KaronLabs/ytdlp-korean-interface/commit/e36fe2894a80021ac9b7218c73173552d90e0063
- Review branch: https://github.com/KaronLabs/ytdlp-korean-interface/tree/review/quality-presets-e36fe28
- Compare: https://github.com/KaronLabs/ytdlp-korean-interface/compare/baf39d25370e05a69814357cd2d0a5cb10696910...e36fe2894a80021ac9b7218c73173552d90e0063

결론: “현재 exact target을 독립 취득할 수 없다”는 공소는 더 이상 사실이 아닙니다.

### 공소 #3: Target SHA validation 결속 부족

판정: `부분 시정`

GitHub commit API 결과:

```json
{
  "sha": "e36fe2894a80021ac9b7218c73173552d90e0063",
  "html_url": "https://github.com/KaronLabs/ytdlp-korean-interface/commit/e36fe2894a80021ac9b7218c73173552d90e0063"
}
```

GitHub compare API 결과:

```json
{
  "status": "ahead",
  "ahead_by": 8,
  "total_commits": 8,
  "changed_files": 30
}
```

exact-target CI 결과:

```json
{
  "name": "Provenance contract",
  "headSha": "e36fe2894a80021ac9b7218c73173552d90e0063",
  "status": "completed",
  "conclusion": "success",
  "run": "https://github.com/KaronLabs/ytdlp-korean-interface/actions/runs/35031230121",
  "covered_job": "provenance-contract"
}
```

제한:

- 이 CI는 provenance contract만 검증합니다.
- native quality, Windows full build, engine fixture, GUI, DPI, license를 CI가 검증했다고 주장하지 않습니다.
- 기존 로컬 자동화 증거는 source-binding과 candidate report가 exact target을 기록하지만, GUI PASS 증거가 아닙니다.

결론: target identity와 30-file diff의 결속은 시정됐습니다. 전체 feature CI 부족은 남아 있습니다.

## 3. 정당한 공소에 대한 수정 및 안전조치

### GUI/lifecycle

동일 후보 복사본을 Computer Use로 다시 실행했습니다.

확인된 창:

```text
app: process:E:\03_AllWork\ytdlp-korean-interface\.quality-presets-work\final-B-e36fe28\manual-runtime\ytdlp-interface.exe
title: ytdlp-interface v2.19.1-karon.2
```

화면 캡처 실패:

```text
SetIsBorderRequired failed: 해당 인터페이스를 지원하지 않습니다. (0x80004002)
```

스크린샷 없는 접근성 트리:

```text
Window: ytdlp-interface v2.19.1-karon.2
title bar only: system menu, minimize, maximize, close
```

입력 실패:

```text
coordinate input geometry is unavailable
```

조치:

- 이전 좌표나 blind click을 사용하지 않았습니다.
- custom Win32/GDI 우회 도구를 만들지 않았습니다.
- 검증용 후보 프로세스만 exact executable path로 종료했고 기존 `karon.1` 사용자 프로세스는 건드리지 않았습니다.
- 결과는 계속 `NOT_VERIFIED`입니다.

### Public-binary license gate

독립 검증자 판정: `FAIL`

확인된 주요 blocking items:

- FFmpeg/ffprobe: exact corresponding source, build/configuration material, static external libraries의 source/notice가 불완전합니다.
- Deno: embedded V8 notice 및 complete third-party dependency notice set과 exact binary/source binding이 불완전합니다.
- bit7z: GPL-2.0-or-later static dependency의 exact snapshot, final linkage, combined executable 배포 조건, corresponding source가 닫히지 않았습니다.
- 7-Zip, Nana, libpng, libjpeg-turbo, zlib: final candidate와 exact linker-input/source를 묶는 증거가 불완전합니다.
- 현재 11-label 목록은 minimum coverage이지 완전한 transitive inventory가 아닙니다.

수정:

- 재심 명세에서 license criterion을 `NOT_VERIFIED`에서 `FAIL`로 정정했습니다.
- public packaging/release HOLD를 유지했습니다.
- hash/inventory 일치만으로 semantic license compliance PASS를 주장하지 않습니다.

## 4. 변경하지 않은 것

- 기능 코드
- review target `e36fe28`
- `main` branch
- 기존 공개 `karon.1` release
- 사용자의 기존 실행 프로그램과 설정
- public `karon.2` ZIP/tag/release

본 재심은 구현의 새로운 의미적 코드 리뷰를 수행하지 않았으므로 “코드 결함이 없다”고 주장하지 않습니다. 원심이 수정할 구체적인 코드 결함을 특정하지 않았기 때문에, 재판 대응만을 위한 추측성 코드 변경은 하지 않았습니다.

## 5. 재심 증거 목록

1. 원심 명세: `review/spec_20260916_quality_presets.md`
2. 재심 명세: `review/spec_20260916_quality_presets_retrial.md`
3. 독립 target 검토: `E:/03_AllWork/ytdlp-korean-interface/.quality-presets-work/retrial/independent-target-review.md`
4. 독립 license 검토: `E:/03_AllWork/ytdlp-korean-interface/.quality-presets-work/retrial/independent-license-review.md`
5. 공개 exact target commit: `https://github.com/KaronLabs/ytdlp-korean-interface/commit/e36fe2894a80021ac9b7218c73173552d90e0063`
6. 공개 base-to-target compare: `https://github.com/KaronLabs/ytdlp-korean-interface/compare/baf39d25370e05a69814357cd2d0a5cb10696910...e36fe2894a80021ac9b7218c73173552d90e0063`
7. exact-target CI: `https://github.com/KaronLabs/ytdlp-korean-interface/actions/runs/35031230121`

## 6. 최종 진술

피고인은 전면 무죄를 주장하지 않습니다.

- exact target 접근 불가: 시정 완료
- 30 files / 8 commits 미검증: 시정 완료
- target CI identity 부재: provenance 범위에서 시정 완료
- online YouTube required 판시: 원 명세와 불일치하므로 반박
- GUI/lifecycle 및 locale/DPI: 정당한 미검증, 계속심리 요청
- public-binary license: 정당한 FAIL, 공개 배포 금지 유지

따라서 원심의 포괄적 `GUILTY / REVISE`를 그대로 유지하기보다, 치유된 공소와 증거 오류를 기각하고 잔존 required gates만 분리 심리해 주시기 바랍니다.

status: `partial_success`

review_verdict: `PENDING`
