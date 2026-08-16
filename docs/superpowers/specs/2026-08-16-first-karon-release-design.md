# First KaronLabs Release Factory Design

## Status

Approved direction for producing the first binary release of `KaronLabs/ytdlp-korean-interface`.

Target release:

- tag: `v2.19.1-karon.1`
- title: `ytdlp-korean-interface v2.19.1-karon.1`
- platform: Windows x64
- direct upstream baseline: `ErrorFlynn/ytdlp-interface v2.19.1`
- upstream baseline commit: `2173316ebb5e50af49a2a4e939693fa8c3a3459c`

## Goal

Create one reproducible, evidence-backed Windows x64 GitHub Release that is built from a clean canonical KaronLabs commit, passes the repository's existing candidate-seal and localhost smoke checks, is packaged with deterministic provenance metadata and SHA-256 checksums, and is published only after every pre-publication gate succeeds.

The release must be useful to a normal user: download one ZIP, extract it, and run `ytdlp-interface.exe` without building the C++ project.

## Non-goals

This first release does not attempt to:

- publish x86 or Windows 7 variants;
- redesign the existing candidate build system;
- claim machine-proven GUI interaction on a headless GitHub runner;
- create or import a long-lived signing private key into GitHub Actions;
- enable repository-wide immutable-release settings as part of the same change;
- replace the existing provenance documents or candidate manifest format.

## Release safety invariants

1. Build, candidate seal, smoke, package inventory, and ZIP checksum all complete before any public release is created.
2. A failed pre-publication gate creates no release and no release tag.
3. The release factory refuses to overwrite an existing `v2.19.1-karon.1` tag or release.
4. The release binds to one exact 40-character KaronLabs commit SHA; mutable `HEAD` is not used as the release identity after the workflow starts.
5. The upstream parent runtime archive is accepted only after its published SHA-256 matches the pinned value for ErrorFlynn `v2.19.1` x64.
6. The build continues to use the existing clean-source attestation, dependency-archive SHA, linker-input hashes, toolchain identities, and candidate manifest seal.
7. The final ZIP receives a separate release-level manifest because adding release documentation beside the sealed candidate payload must not be misrepresented as part of the original candidate seal.
8. The release notes distinguish KaronLabs work from ErrorFlynn and `yt-dlp` upstream work.

## Architecture

The release factory is a Windows GitHub Actions workflow plus focused PowerShell release helpers. It reuses repository-native build and smoke tooling instead of duplicating those controls.

```text
release request commit
        ↓
Windows 2022 GitHub runner
        ↓
pin GITHUB_SHA + verify tag/release absent
        ↓
fetch ErrorFlynn v2.19.1 x64 runtime archive
        ↓
verify pinned upstream archive SHA-256
        ↓
extract isolated parent runtime
        ↓
UpdateYtDlp on parent copy
        ↓
official nightly yt-dlp provenance + rollback identity
        ↓
existing build-candidate.ps1
        ↓
sealed candidate + candidate-manifest.json
        ↓
existing smoke-localhost.ps1
        ↓
artifact-only localhost MP3 smoke
        ↓
release package assembly
        ↓
release-manifest.json + ZIP + SHA256SUMS.txt
        ↓
final verification
        ↓
create GitHub Release v2.19.1-karon.1
```

## Trigger model

The workflow supports `workflow_dispatch` for future maintainers, but the first release is started by a source-controlled one-time request file so the release can be launched by the same reviewed commit that introduces the factory without requiring a separate API dispatch capability.

The initial request record is:

`release/requests/v2.19.1-karon.1.json`

The workflow's `push` trigger is path-scoped to that request record. Future ordinary commits therefore do not republish a release.

The request contains only fixed public release metadata such as tag, upstream version, platform, and expected upstream archive SHA-256. It contains no credentials.

## Source revision binding

At workflow start:

- `GITHUB_SHA` must match `^[0-9a-f]{40}$`;
- checkout uses that exact revision;
- the workflow verifies that the checked-out commit equals `GITHUB_SHA`;
- the working tree must be clean before the build;
- all release manifests record this exact source SHA.

If a release or tag named `v2.19.1-karon.1` already exists, the workflow fails before building or publishing anything.

## Parent runtime bootstrap

The existing candidate builder expects a preserved parent runtime containing the normal runtime payload and a verified `yt-dlp-provenance.json` for the official nightly channel.

The release factory therefore creates an isolated parent runtime as follows:

1. Download ErrorFlynn's normal Windows x64 `ytdlp-interface.7z` asset for upstream `v2.19.1`.
2. Verify the archive against the pinned SHA-256:
   `53b54e3c5c753e8cb2a8b9638c69c95c1449c8185c3145a9f0b06a2000b3702e`.
3. Extract with the runner's trusted Program Files 7-Zip.
4. Resolve exactly one runtime directory containing the required product/runtime files; ambiguous or incomplete extraction fails closed.
5. Run the repository's existing `UpdateYtDlp` against the isolated parent `yt-dlp.exe`.
6. Require the resulting `yt-dlp-provenance.json`, backup identity, current executable hash, and version to pass the checks already enforced by `build-candidate.ps1`.

The release uses the official `yt-dlp/yt-dlp-nightly-builds` latest nightly selected by the existing updater at release-build time. The exact selected tag and executable hash are captured in the candidate manifest; the release does not claim a timeless or floating yt-dlp version.

## Candidate build

The factory calls the existing `tools/build-candidate.ps1 -Run` using:

- the exact checked-out KaronLabs source revision;
- the isolated verified parent runtime;
- the source-controlled `ytdlp-interface dependencies.7z` as the reviewed dependency archive input;
- an isolated candidate output directory.

Existing controls remain authoritative:

- clean source revision requirement;
- exact tracked-input tree digest;
- dependency archive SHA-256;
- trusted 7-Zip inspection;
- Visual Studio v143 / Release / x64 build;
- linker library hashes before and after product link;
- toolchain identity attestation;
- product version `2.19.1.0`;
- required runtime payload;
- Korean catalog presence;
- candidate manifest exact inventory seal.

No second ad-hoc build path is introduced.

## Smoke gate

The headless release gate uses the existing `tools/smoke-localhost.ps1` in `artifact-only` mode.

The smoke still launches `ytdlp-interface.exe` and requires it to remain running, but the GitHub runner does not claim proof that UI controls were clicked. The automation command performs the deterministic media operation using the candidate's own `yt-dlp.exe` and FFmpeg against the smoke script's `127.0.0.1` URL, writes the result into the smoke output directory, and returns the marker bound to the exact GUI PID, URL, and output directory.

The existing smoke code then independently requires:

- sealed candidate copied to the execution workspace;
- candidate GUI process successfully started;
- `127.0.0.1`-only fixture URL;
- newly generated output after smoke start;
- nonempty MP3;
- no `.part` files;
- FFprobe reports `codec_name=mp3`;
- positive duration;
- successful process cleanup;
- retained evidence and hashes.

The release notes describe this accurately as an automated artifact/runtime smoke. Prior manual GUI evidence remains separate; this workflow does not upgrade `guiInteractionProven` from false to true.

## Public package layout

The release asset is:

`ytdlp-korean-interface-v2.19.1-karon.1-win-x64.zip`

The extracted directory is intentionally simple for end users:

```text
ytdlp-korean-interface-v2.19.1-karon.1-win-x64/
├─ ytdlp-interface.exe
├─ yt-dlp.exe
├─ ffmpeg.exe
├─ ffprobe.exe
├─ deno.exe
├─ 7z.dll
├─ ytdlp-interface.json
├─ locales/
│  └─ ko-KR.json
├─ candidate-manifest.json
├─ LICENSE
├─ NOTICE
├─ PROVENANCE.md
└─ release-manifest.json
```

The candidate payload is copied without mutation from the smoke-approved sealed candidate. `LICENSE`, `NOTICE`, and `PROVENANCE.md` are then copied from the exact release source revision.

Because those additional release documents are outside the original candidate inventory contract, `release-manifest.json` is the authoritative final-package inventory.

## Release manifest

`release-manifest.json` uses a small release-specific schema and records at least:

- schema version;
- release tag;
- source repository;
- exact KaronLabs source commit SHA;
- direct upstream repository, tag, and baseline commit;
- upstream runtime archive filename and SHA-256;
- candidate-manifest SHA-256;
- selected yt-dlp nightly tag and SHA-256, copied from verified candidate metadata;
- smoke evidence result/digest references available to the workflow;
- final package file inventory excluding `release-manifest.json` itself, with relative path, byte length, and SHA-256;
- creation timestamp.

After writing the manifest, the factory reparses it and re-hashes every listed file. Any missing, extra, duplicate, traversing, absolute, or hash-mismatched entry fails the package gate.

## ZIP and checksum

The complete package directory is archived as:

`ytdlp-korean-interface-v2.19.1-karon.1-win-x64.zip`

The workflow then computes the ZIP's SHA-256 and writes:

`SHA256SUMS.txt`

with exactly one canonical line for the public ZIP asset.

The ZIP is reopened/listed before publication. The archive must contain exactly one expected top-level release directory and no path traversal, absolute paths, symlinks/reparse artifacts, build directories, source tree, `.git`, secrets, or temporary smoke files.

## Release notes

The release notes identify:

- this as KaronLabs `v2.19.1-karon.1`;
- direct upstream `ErrorFlynn/ytdlp-interface v2.19.1`;
- Korean localization recovery and i18n hardening;
- state-token separation;
- runtime maintenance/rollback and evidence hardening;
- automated Windows x64 build and artifact smoke status;
- exact source commit SHA;
- verification instructions using `SHA256SUMS.txt` and `release-manifest.json`;
- the fact that the bundled yt-dlp is the exact official nightly recorded in the manifest, not a permanently fixed future version.

Tone stays concise and professional with one small KaronLabs line: `작은 일이었는데 작지 않게 됐습니다.`

## Publication transaction

Publication is the final phase only.

Before publication the workflow verifies again that the target tag and release do not already exist.

Preferred transaction:

1. prepare a GitHub draft release targeting the exact source SHA;
2. upload the already-verified ZIP and `SHA256SUMS.txt` to the draft;
3. verify the draft asset names and local hashes against the intended release inputs;
4. publish the draft as the non-prerelease latest release;
5. fetch the published release and verify tag, target identity where exposed, asset names, asset sizes/digests where exposed, and published status.

If GitHub's draft behavior or CLI version would create a public tag earlier than expected, the implementation must use an equivalent API/CLI sequence with explicit cleanup on a failed publication attempt. Cleanup is allowed only for objects created by the current workflow after proving that no tag/release existed at workflow start. Pre-existing release objects are never modified or deleted.

A network failure after GitHub has accepted a publication request is treated as an uncertain publication state: the workflow re-reads GitHub state before deciding whether cleanup is safe. It never blindly creates a second release with the same tag.

## GitHub permissions

The release workflow uses the repository-scoped `GITHUB_TOKEN` with minimum required permissions:

```yaml
permissions:
  contents: write
```

No long-lived PAT, SSH private key, or signing private key is stored for the factory.

## Signing and immutability

This first automated release does not pretend to be cryptographically user-signed when no KaronLabs signing key has been configured in the runner.

The provenance value comes from:

- exact GitHub repository history;
- exact source SHA;
- candidate attestation;
- release manifest;
- SHA-256 checksum;
- GitHub release metadata.

A future operator may add a verified signed tag and/or enable GitHub immutable releases as a separate hardening step. Existing public history is not rewritten merely to manufacture retroactive signing evidence.

## Tests

Implementation adds focused tests before release publication is attempted.

### Static/contract tests

Verify:

- fixed tag and asset naming;
- release request pins the expected upstream archive hash;
- workflow permissions are only what publication requires;
- workflow does not publish before build/smoke/package verification steps;
- package manifest rejects path traversal and unexpected files;
- SHA256SUMS contains the public ZIP only;
- release script refuses pre-existing tag/release state;
- exact source SHA is used throughout metadata.

### Existing suites

Run the existing relevant repository checks, including:

- Python contract tests;
- PowerShell tests;
- deploy SSH security regression workflow;
- provenance contract workflow.

### Release dry-run

Before any public release object is created, the factory completes through build, candidate seal, smoke, package, release manifest, ZIP, and SHA-256 validation.

Publication code runs only after that dry-run-equivalent phase has succeeded in the same workflow execution.

## Failure behavior

Any of the following prevents publication:

- source revision mismatch or dirty tree;
- pre-existing target tag/release;
- upstream archive download/hash mismatch;
- parent runtime/provenance failure;
- dependency/toolchain/build failure;
- candidate seal failure;
- GUI startup failure;
- artifact smoke failure;
- package inventory mismatch;
- ZIP validation failure;
- checksum mismatch;
- GitHub publication verification failure.

Temporary build, parent-runtime, and smoke directories are runner-local and disposable. Diagnostic logs may be uploaded as workflow artifacts on failure, but failed candidates are never attached to a GitHub Release.

## Success criteria

The work is complete only when all of the following are true:

1. `v2.19.1-karon.1` exists as a published, non-prerelease GitHub Release.
2. The release is bound to the intended exact KaronLabs source revision.
3. The release contains exactly the intended public assets: Windows x64 ZIP and `SHA256SUMS.txt`.
4. The Windows x64 ZIP contains the runtime payload and required provenance/license documents.
5. `release-manifest.json` validates the extracted release package.
6. `SHA256SUMS.txt` matches the published ZIP bytes.
7. The same workflow run shows successful build, candidate seal, artifact smoke, package validation, and publication verification.
8. No failed candidate or unrelated build artifact is published.

The operating rule is simple: **build everything, prove everything, then publish once.**
