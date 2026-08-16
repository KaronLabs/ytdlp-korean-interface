# Provenance

This document records the chain of origin for `KaronLabs/ytdlp-korean-interface` and provides a repeatable way to verify that history.

It is **provenance documentation, not an additional software license**. Reuse rights remain governed by the MIT License in [`LICENSE`](LICENSE).

## Canonical identifiers

| Role | Value |
| --- | --- |
| Canonical repository | `KaronLabs/ytdlp-korean-interface` |
| Canonical URL | `https://github.com/KaronLabs/ytdlp-korean-interface` |
| Direct upstream | `ErrorFlynn/ytdlp-interface` |
| Direct upstream URL | `https://github.com/ErrorFlynn/ytdlp-interface` |
| Upstream baseline tag | `v2.19.1` |
| Upstream baseline commit | `2173316ebb5e50af49a2a4e939693fa8c3a3459c` |
| Software license | MIT |
| Current canonical release | `v2.19.1-karon.1` |
| Canonical release URL | `https://github.com/KaronLabs/ytdlp-korean-interface/releases/tag/v2.19.1-karon.1` |
| Release source commit | `c053c1edf5508b05beac1da27ddfcdbefd1bc2bd` |
| Windows x64 ZIP SHA-256 | `271664db6378be9ffe513b62f91cf90b849ab13bb9532a45096cee72bdaf9cc2` |

## Lineage

```text
yt-dlp
  ↓ download/site-extraction engine
ErrorFlynn/ytdlp-interface v2.19.1
  ↓ direct Windows GUI upstream
KaronLabs/ytdlp-korean-interface
  ↓ Korean recovery / hardening / verification repository history
v2.19.1-karon.1
```

### `yt-dlp`

`yt-dlp` supplies the underlying media extraction and download engine used by the GUI. KaronLabs does not claim authorship of `yt-dlp`.

### `ErrorFlynn/ytdlp-interface`

`ErrorFlynn/ytdlp-interface` is the direct Windows C++ GUI upstream for this repository. The recovery baseline is upstream tag `v2.19.1`, commit:

```text
2173316ebb5e50af49a2a4e939693fa8c3a3459c
```

The existing upstream MIT copyright notice remains in [`LICENSE`](LICENSE):

```text
Copyright (c) 2021 ErrorFlynn
```

KaronLabs does **not** claim sole authorship of unchanged upstream code.

### `KaronLabs/ytdlp-korean-interface`

The canonical repository for the Korean recovery and associated hardening history is:

```text
https://github.com/KaronLabs/ytdlp-korean-interface
```

The repository history documents KaronLabs-specific recovery, modification, test, maintenance, verification, and release work layered on the upstream baseline.

## First canonical KaronLabs release

The first published KaronLabs binary release is:

```text
Tag: v2.19.1-karon.1
Release: https://github.com/KaronLabs/ytdlp-korean-interface/releases/tag/v2.19.1-karon.1
Source commit: c053c1edf5508b05beac1da27ddfcdbefd1bc2bd
Platform: Windows x64
ZIP: ytdlp-korean-interface-v2.19.1-karon.1-win-x64.zip
ZIP SHA-256: 271664db6378be9ffe513b62f91cf90b849ab13bb9532a45096cee72bdaf9cc2
```

The release was built and published by the source-controlled GitHub Actions release factory only after repository contracts, the Release/x64 candidate build, candidate-manifest seal, localhost artifact/runtime MP3 smoke, final release-package inventory, ZIP validation, and `SHA256SUMS.txt` verification succeeded.

The publication step then downloaded the public ZIP and checksum asset again and verified that the downloaded ZIP bytes matched the already-validated local release payload before the workflow completed successfully.

The bundled `yt-dlp.exe` is an official `yt-dlp/yt-dlp-nightly-builds` nightly selected during that release build. Its exact nightly tag and SHA-256 are recorded inside the release package's `release-manifest.json` rather than treated as a permanently floating dependency.

## What the KaronLabs repository history adds

The recorded KaronLabs-specific repository work includes, at minimum:

- recovery of the Korean UI behavior into maintainable C++ source;
- the `ko-KR` localization catalog and loading/fallback behavior;
- UTF-8, schema, placeholder, and Nana-markup validation around translations;
- separation of localized presentation strings from stable internal state tokens;
- queue/state/subtitle regression coverage related to that separation;
- settings-repair tooling for known stale Windows download paths;
- verified `yt-dlp` runtime-update and rollback tooling;
- candidate manifests and runtime provenance records;
- localhost end-to-end download / MP3 / FFmpeg / FFprobe smoke testing;
- review/evidence material used to validate the recovery and hardening work;
- provenance-hardening documentation and deterministic provenance contract tests;
- a verification-first Windows x64 release factory and release-level package manifest.

This list describes repository history and project scope. It is deliberately **not** a claim that every line in the repository was authored from scratch by KaronLabs.

## AI-assisted development disclosure

The recovery and hardening work in this repository has been developed with extensive AI assistance. Provenance here records **which repository history contains which changes and when**, rather than pretending that every line has a simple single-human authorship story.

That distinction is intentional: the anti-laundering mechanism is the verifiable Git history, upstream baseline, diffs, tests, release records, artifact hashes, and package manifests—not an exaggerated authorship claim of our own.

## Evidence map

Useful primary-source records already present in this repository include:

### Design and implementation records

- `docs/superpowers/specs/2026-08-13-korean-i18n-recovery-design.md`
- `docs/superpowers/specs/2026-08-16-provenance-hardening-pack-design.md`
- `docs/superpowers/specs/2026-08-16-first-karon-release-design.md`
- `docs/superpowers/plans/2026-08-16-provenance-hardening-pack.md`
- `docs/superpowers/plans/2026-08-17-first-karon-release.md`

### Deterministic tests

- `tests/contract/`
- `tests/native/`
- `tests/powershell/`

### Runtime, build, and release tooling

- `tools/runtime-maintenance.psm1`
- `tools/build-candidate.ps1`
- `tools/candidate-manifest.psm1`
- `tools/smoke-localhost.ps1`
- `tools/release-factory.ps1`
- `tools/release-orchestrator.ps1`
- `tools/release-archive.ps1`

### Review evidence

- `review/evidence/`
- `review/security/`

The evidence directory is intentionally richer than what should normally be needed in a provenance dispute. A compact proof should usually prefer the smallest sufficient set: canonical upstream commit, canonical KaronLabs commit, source diff, release tag, artifact hash, and release manifest.

## Verification procedure

When the origin of a derivative repository, binary, course sample, or product is disputed, verify in this order.

### 1. Identify the artifact being discussed

Record the exact repository URL, commit, tag, binary filename, course material, or source sample. Avoid comparing vague screenshots when exact source or artifact identifiers are available.

### 2. Resolve the direct upstream baseline

Compare against:

```text
ErrorFlynn/ytdlp-interface
v2.19.1
2173316ebb5e50af49a2a4e939693fa8c3a3459c
```

This separates upstream material from later KaronLabs-specific repository work.

### 3. Resolve the relevant KaronLabs commit

Use the Git history of:

```text
KaronLabs/ytdlp-korean-interface
```

Inspect commit parentage, timestamps, source diffs, design records, and tests rather than relying only on README wording or repository branding.

For the first canonical binary release, the release tag resolves to:

```text
v2.19.1-karon.1
c053c1edf5508b05beac1da27ddfcdbefd1bc2bd
```

### 4. Compare source correspondence

Look for concrete correspondence such as:

- substantially identical source structure or logic;
- distinctive recovery/hardening behavior;
- matching translation keys and fallback design;
- matching tests, fixtures, tooling, or documentation;
- copied comments, strings, manifests, or evidence structures;
- commit ancestry or fork relationships when available.

Feature similarity by itself is not proof of copying. Independent implementations should not be treated as derivatives without concrete evidence.

### 5. Verify canonical release metadata

For `v2.19.1-karon.1`, verify:

- release tag `v2.19.1-karon.1`;
- source commit `c053c1edf5508b05beac1da27ddfcdbefd1bc2bd`;
- direct upstream tag `v2.19.1` and commit `2173316ebb5e50af49a2a4e939693fa8c3a3459c`;
- Windows x64 ZIP filename;
- ZIP SHA-256 against `SHA256SUMS.txt`;
- `release-manifest.json` inside the extracted package;
- `candidate-manifest.json` for the sealed build candidate provenance.

The public release page is:

```text
https://github.com/KaronLabs/ytdlp-korean-interface/releases/tag/v2.19.1-karon.1
```

## Canonical release discipline

The first real KaronLabs release on this upstream baseline is:

```text
v2.19.1-karon.1
```

Later KaronLabs releases on the same upstream baseline increment only the Karon suffix:

```text
v2.19.1-karon.2
v2.19.1-karon.3
```

If the direct upstream baseline changes, the version prefix changes with it.

### Signing

Future canonical release tags should be signed with a GitHub-supported verified signing identity where practical.

The first `v2.19.1-karon.1` tag was created by the release workflow and is not represented here as a user-signed cryptographic tag. Existing public history should not be rewritten merely to manufacture retroactive signatures.

### Immutable releases

`v2.19.1-karon.1` is currently recorded as a normal published GitHub Release, not an immutable Release.

If GitHub immutable releases are enabled later, use them prospectively after release contents are complete. Release immutability supplements Git history and checksums; it does not replace them.

## Historical boundaries

For provenance purposes, keep these categories separate:

1. **Upstream work** — work from `ErrorFlynn/ytdlp-interface` and its contributors, plus the separate `yt-dlp` project and its contributors.
2. **KaronLabs repository history** — Korean recovery, hardening, tests, maintenance tooling, evidence, release tooling, and later KaronLabs-specific modifications recorded in this repository.
3. **Third-party derivatives** — forks, products, courses, packages, or modifications created later by other parties.

A truthful derivative can freely acknowledge all three layers. Nothing in this provenance system is intended to stop that lawful reuse.

## If a fork removes these provenance files

A fork can technically delete `NOTICE`, `PROVENANCE.md`, `ATTRIBUTION.md`, or `CITATION.cff`. Deleting those files does not rewrite the canonical Git history or already-published release metadata that existed before the fork.

The MIT License separately governs which copyright and permission notices must be retained in copies or substantial portions of the Software. See [`LICENSE`](LICENSE) for the actual license text.

## Related documents

- [`NOTICE`](NOTICE) — compact lineage notice
- [`ATTRIBUTION.md`](ATTRIBUTION.md) — accurate ways to describe reuse
- [`CITATION.cff`](CITATION.cff) — machine-readable citation metadata
- [`docs/provenance-dispute-response.md`](docs/provenance-dispute-response.md) — evidence-first response procedure

The operating principle is simple: **keep the code open, keep the history checkable.**