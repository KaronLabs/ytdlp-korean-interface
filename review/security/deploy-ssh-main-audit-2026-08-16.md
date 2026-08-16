# SSH Main Deployment Security Audit — 2026-08-16

## Scope

Reviewed the repository-local deployment boundary for `KaronLabs/ytdlp-korean-interface`:

- `tools/deploy-ssh-main.ps1`
- `docs/karonlabs-github-deploy-manual-korean-interface.md`
- surrounding Git configuration assumptions relevant to that script

The review focused on deployment integrity, unintended source disclosure, staging isolation, SSH identity confusion, and false-success conditions.

No repository-wide `SECURITY.md` was present at scan time, so the deployment rules documented in the SSH manual were treated as the scoped security policy.

## Threat model

This is an administrative deployment script, not a remotely reachable service endpoint.

The realistic threats in scope were therefore:

- operator error;
- stale or locally contaminated Git configuration;
- an unintended GitHub SSH identity;
- accidental staging of unrelated files;
- an invocation that weakens the documented fixed-destination policy;
- a local ref changing between verification and push;
- a native Git failure being mistaken for a successful deployment.

No Critical or High severity remotely exploitable vulnerability was identified in this scoped review.

## Findings and remediation

### 1. Caller-overridable deployment destination and branch — Medium

**Before:** `RemoteName`, `ExpectedRemote`, and `Branch` were caller-controlled parameters even though the deployment policy defined `origin`, the KaronLabs SSH URL, and `main` as fixed values.

**Risk:** an invocation could intentionally or accidentally weaken the policy and target a different repository or branch.

**Fix:** policy-critical destination values are now internal constants. The script no longer exposes parameters that can change the canonical repository or deployment branch.

### 2. Non-main local branch could be pushed into remote main — Medium

**Before:** the script used `HEAD:refs/heads/main` without requiring the current local branch to be `main`.

**Risk:** a clean feature/test branch could be promoted directly to production `main` by mistake.

**Fix:** the script requires the current symbolic branch to be exactly `main` before any deployment work continues.

### 3. `remote.origin.pushurl` could bypass fetch-URL validation — Medium

**Before:** the script checked `git remote get-url origin` but then pushed through the `origin` alias. Git permits a separate push URL.

**Risk:** a locally configured `remote.origin.pushurl` could send source to a different repository even though the fetch URL passed validation. A post-push SHA check would discover inconsistency only after source had already been transmitted.

**Fix:** both fetch and effective push URLs are validated. Actual `ls-remote` and `push` operations use the canonical KaronLabs SSH URL directly rather than trusting the alias for network destination selection.

### 4. Existing staged files could be mixed into a `StagePaths` commit — Medium

**Before:** `git add -- <StagePaths>` was followed by `git commit`, but the index was not required to be clean first.

**Risk:** unrelated staged files, including sensitive local material, could be committed and deployed together with the intended paths.

**Fix:** `StagePaths` mode requires an empty index before staging, verifies the staged set after `git add`, and requires the index to be clean after commit.

### 5. Git pathspec magic could broaden `StagePaths` — Medium

**Before:** caller-supplied `StagePaths` were sent to Git as pathspecs.

**Risk:** values such as `:(glob)**` could select substantially more content than the operator intended.

**Fix:** `StagePaths` now accepts repository-relative explicit file paths only, rejects pathspec magic, absolute/out-of-repository paths, `.git` metadata, and directories, and passes normalized targets to Git using literal pathspecs.

### 6. Native Git failure / mutable-source ambiguity — Low to Medium

**Before:** important native Git commands did not consistently enforce their process exit code, and push used mutable `HEAD` rather than the SHA already recorded by the script.

**Risk:** a failed command could continue farther than intended, and a local ref change between verification and push could make the pushed source differ from the commit that had been recorded.

**Fix:** important Git commands now fail closed on non-zero exit. The script resolves and validates `HEAD^{commit}` as a 40-character SHA and pushes that exact SHA to the canonical URL. `PUSH_OK` is emitted only after the remote SHA is read back and exactly matches the verified local SHA.

### 7. SSH authentication accepted any GitHub account — Low

**Before:** the script only looked for GitHub's generic `successfully authenticated` message.

**Risk:** a wrong local key/account could pass the preflight identity check.

**Fix:** the SSH preflight now requires the authenticated GitHub login to be `KaronLabs`. The manual also recommends `IdentitiesOnly yes` with an explicit key.

## Preserved behavior

The hardening intentionally preserves the legitimate deployment model:

- SSH deployment to `KaronLabs/ytdlp-korean-interface`;
- `main` as the deployment branch;
- clean-tree deployments;
- explicit `StagePaths` + `CommitMessage` deployments;
- approved first-`main` bootstrap via `-AllowMainBootstrap`;
- pre-/post-push SHA verification;
- no force push path.

## Regression coverage

Added:

- `tests/powershell/deploy-ssh-main-security.Tests.ps1`
- `.github/workflows/deploy-ssh-security.yml`

The Windows regression suite checks:

1. policy-critical destination cannot be overridden;
2. non-main local branch is rejected;
3. mismatched push URL is rejected before push;
4. pre-staged unrelated files are rejected;
5. pathspec magic is rejected;
6. failed `git push` cannot report success;
7. successful push is bound to the canonical URL and exact verified SHA, not `HEAD`;
8. the SSH identity must be the expected `KaronLabs` login.

Final verification on `main` after the script and manual changes:

- GitHub Actions workflow: `Deploy SSH security contract`
- run id: `31949833689`
- head commit: `df3547305beeb8c61df68b31a51e50cafd6c266a`
- result: `success`
- security regression tests: `8/8 passed`

## Residual risk

This hardening does not protect a workstation that is already fully compromised. A local attacker with sufficient control could replace `git`, `ssh`, the script itself, the SSH key, or the repository contents.

The intended security boundary is narrower: prevent common deployment mistakes and fail closed when local Git/SSH state conflicts with the documented KaronLabs deployment policy.
