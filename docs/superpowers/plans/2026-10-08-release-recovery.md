# Karon.2 Release Pipeline Recovery Plan

> For agentic workers: use superpowers:subagent-driven-development with implementation and verification assigned to different agents.

**Goal:** Repair the failed release pipeline without replacing the sealed application candidate or bypassing final release checks.

**Architecture:** Source/license assembly may construct intermediate artifacts while remaining unapproved. Final approval requires the generated artifacts, exact candidate bindings, independent checks, and exact-target CI. Source transport preserves the complete archive identity across ordered split assets.

**Tech Stack:** PowerShell Core, Pester, GitHub Actions, GitHub CLI.

**Spec:** User-approved GUI-waived v2.19.1-karon.2 release plan and independent source-license adjudication from 2026-10-08.

## Global Constraints

- Preserve application source b80f594a2b6673d28e00e705659c39b0c4bed647 and the existing candidate executable.
- GUI status stays WAIVED_BY_OWNER, not PASS. Automated and license checks are not waived.
- Preserve original corresponding sources and authentic license text bytes.
- Do not publish a tag or release while final gates fail.
- Explicit staging only; no force push or unrelated edits.

## Task 1: Recover source/license artifact construction

**Files:** tools/build-corresponding-sources.ps1, tools/generate-release-spdx.ps1, tools/build-release-license-lock.ps1 and directly related PowerShell tests.

- [ ] Add tests for unapproved-but-bound intermediate assembly, retained upstream TODO text, original notice bytes, and rejected incomplete or mismatched bindings.
- [ ] Independent verifier records RED before production edits.
- [ ] Implement only the proven generation-cycle and notice-consumption fixes.
- [ ] Independent verifier runs targeted tests and real source/SPDX generation. Intermediate generation must not grant final approval.

## Task 2: Repair split source publication contract

**Files:** tools/source-release-transport.ps1, tools/publish-quality-release.ps1, tools/package-quality-release.ps1, tests/powershell/release-publication-contract.Tests.ps1.

- [ ] Recover the two exact failures from release factory run 37743363229; preserve their names and causes.
- [ ] Add any missing regression test before production edits; existing failed CI supplies RED for existing cases.
- [ ] Apply the smallest implementation fix without weakening restored whole-source checks or draft-first publication.
- [ ] Independent verifier runs publication contracts, including tampered, reordered, missing and extra assets.

## Task 3: Integrate only independently passing changes

- [ ] Commit source/license and transport changes separately with explicit path lists.
- [ ] Use SSH fast-forward push to origin main after remote SHA checks.
- [ ] Require CI runs whose headSha equals the new source commit; never inherit old success.
- [ ] Resolve remaining current producer metadata and packaging identity only from actual artifacts.
- [ ] Create final runtime ZIP only after the non-waived gates pass; report its actual size separately from corresponding sources.
- [ ] Publish validated assets draft-first, confirm downloaded assets, then update the README download link.

## Current Baseline

Remote source before recovery: 20f74da1fe1b807e83c22510beaea01d64468d40.
Release factory run 37743363229: publication contracts 139 passed, 2 failed.
Quality run 37743363143: GUI waiver contracts 33 passed; legacy license-lock contracts 22 passed, 4 failed.
Independent source/license checks: 117 scoped tests passed; final source/SPDX construction blocked. Release remains HOLD.
