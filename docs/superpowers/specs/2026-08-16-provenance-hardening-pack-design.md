# Provenance Hardening Pack Design

## Status

Approved design for `KaronLabs/ytdlp-korean-interface`.

## Goal

Keep the project genuinely open source under the existing MIT terms while making false-origin claims, authorship laundering, and misleading “I built this from scratch” presentations materially harder to sustain.

The project should remain easy to fork, modify, teach with, package, and use commercially. The hardening work must not convert the repository into a source-available project or add new restrictions that conflict with the upstream MIT license.

The design instead makes origin and contribution history explicit, redundant, machine-readable, release-bound, and easy to verify.

## Threat Model

### In scope

The hardening targets people or organizations that reuse this repository and then make materially misleading claims such as:

- claiming to be the original author of `ytdlp-korean-interface`;
- claiming to have built the project from scratch when it is derived from this repository;
- deleting or obscuring the relationship between `ErrorFlynn/ytdlp-interface`, KaronLabs, and the derivative work;
- presenting a fork, course, product, or demonstration as an official KaronLabs offering without authorization;
- presenting KaronLabs-specific recovery, localization, validation, runtime-maintenance, or evidence work as independently created work without disclosing the KaronLabs source;
- changing cosmetic details, README text, variable names, or repository branding while relying substantially on the same implementation and then attempting to erase provenance.

### Out of scope

The project explicitly does not attempt to prevent:

- lawful forks;
- lawful modifications;
- commercial use;
- paid courses that accurately disclose the project's origin;
- redistribution under the MIT terms;
- independent reimplementations that do not copy protected expression;
- criticism, comparison, review, or teaching about the project.

The system is not intended to make false claims technically impossible. It is intended to make those claims easy to challenge with primary-source evidence.

## Design Principles

1. **Preserve MIT freedom.** Do not add use restrictions to `LICENSE`.
2. **Respect upstream authorship.** ErrorFlynn's original copyright and upstream role stay explicit.
3. **Claim only documented KaronLabs work.** KaronLabs provenance applies to repository-specific recovery, modifications, testing, and maintenance history, not unchanged upstream code.
4. **Avoid unnecessary copyright overclaims.** Provenance hardening does not depend on asserting copyright over every KaronLabs-specific line, particularly where AI-assisted generation may complicate authorship analysis.
5. **Use redundant evidence.** Human-readable documents, machine-readable metadata, Git history, release metadata, and checksums should all tell the same story.
6. **Prefer verifiable facts over threatening language.** The repository should look professional, not litigious.
7. **Separate license, provenance, and branding.** A right to use MIT-licensed code is not the same thing as a factual basis to claim original authorship or official KaronLabs endorsement.
8. **Keep maintenance cheap.** The provenance system must be simple enough that future versions can update it consistently.

## Current Baseline

Direct upstream:

- Repository: `ErrorFlynn/ytdlp-interface`
- Baseline tag: `v2.19.1`
- Baseline commit: `2173316ebb5e50af49a2a4e939693fa8c3a3459c`

KaronLabs repository:

- Repository: `KaronLabs/ytdlp-korean-interface`
- Primary branch: `main`
- Existing license: MIT
- Existing upstream copyright notice: `Copyright (c) 2021 ErrorFlynn`

KaronLabs-specific repository work includes, at minimum, the documented Korean source recovery and associated hardening work, including:

- `ko-KR` localization recovery and catalog handling;
- English fallback behavior;
- UTF-8, schema, placeholder, and Nana-markup validation;
- separation of translated presentation strings from internal state tokens;
- related queue/state/subtitle regression coverage;
- settings-repair tooling;
- verified `yt-dlp` runtime update and rollback tooling;
- candidate manifests and provenance records;
- localhost end-to-end smoke testing;
- review/evidence infrastructure used to validate recovery work.

The exact file-by-file boundary may evolve. The provenance documents therefore describe the KaronLabs work by repository history, diffs, design records, tests, and canonical commits rather than pretending every line in the repository was authored by KaronLabs.

## Architecture

The Provenance Hardening Pack consists of five repository-level records, one response guide, and a release discipline.

```text
LICENSE
  └─ legal permission and warranty terms

NOTICE
  └─ concise upstream and KaronLabs provenance notice

PROVENANCE.md
  └─ factual lineage, baseline SHAs, canonical repository, and verification model

ATTRIBUTION.md
  └─ accurate ways to describe reuse and examples of misleading origin claims

CITATION.cff
  └─ machine-readable repository citation metadata

README.md
  └─ short public-facing reuse and provenance summary linking to the above

docs/provenance-dispute-response.md
  └─ evidence-first response procedure for disputed origin claims

Git tags / GitHub Releases
  └─ canonical version checkpoints tied to commit SHAs and artifact hashes
```

No single document is treated as the source of truth in isolation. The records are designed to cross-reference one another.

## Component Design

### 1. `LICENSE`

The existing MIT license remains intact.

Do not rewrite the upstream license into a custom license and do not add field-of-use, commercial-use, course-use, attribution-beyond-MIT, or no-resale restrictions.

Reason: the project's stated goal is open reuse with strong provenance, not tighter code-use control.

Do not delete or replace ErrorFlynn's existing notice as part of this hardening pass.

### 2. `NOTICE`

`NOTICE` is the compact redistribution-facing provenance record.

It will contain:

- the direct upstream project and canonical URL;
- the baseline upstream version and commit;
- ErrorFlynn's existing copyright notice as found in `LICENSE`;
- a KaronLabs repository-provenance notice for the Korean recovery and hardening work;
- a short summary of that work;
- a statement that the repository remains MIT-licensed;
- a statement that `NOTICE` documents lineage and does not add a new software-license restriction.

Preferred KaronLabs provenance wording:

`KaronLabs-specific Korean recovery, hardening, testing, and maintenance history is documented in this repository from 2026 onward. See PROVENANCE.md for scope, lineage, and verification references.`

This deliberately avoids claiming KaronLabs sole authorship of unchanged upstream code or relying on a broad copyright assertion as the anti-laundering mechanism.

### 3. `PROVENANCE.md`

`PROVENANCE.md` is the main human-readable chain-of-origin record.

It will include:

#### Canonical lineage

```text
yt-dlp
  ↓ download engine
ErrorFlynn/ytdlp-interface v2.19.1
  ↓ direct GUI upstream
KaronLabs/ytdlp-korean-interface
  ↓ Korean recovery and hardening repository history
canonical KaronLabs releases
```

#### Canonical identifiers

- upstream repository URL;
- upstream tag `v2.19.1`;
- upstream commit `2173316ebb5e50af49a2a4e939693fa8c3a3459c`;
- KaronLabs repository URL;
- canonical default branch;
- canonical provenance-document location.

#### KaronLabs modification scope

A concise list of the recovery, i18n, state separation, runtime-maintenance, and verification work that distinguishes the repository from upstream.

#### Evidence map

References to the existing design, test, and evidence locations, including:

- `docs/superpowers/specs/2026-08-13-korean-i18n-recovery-design.md`;
- `tests/contract/`;
- `tests/native/`;
- `tests/powershell/`;
- `tools/runtime-maintenance.psm1`;
- `tools/smoke-localhost.ps1`;
- `review/evidence/`.

#### Verification rule

A reader should verify origin in this order:

1. identify the commit or release being used;
2. compare it with the canonical KaronLabs Git history;
3. inspect `PROVENANCE.md` and `NOTICE` from that commit;
4. for releases, verify the release tag, source commit, and artifact checksum;
5. compare derivative source against the canonical repository when origin is disputed.

#### Historical-boundary statement

The document will explicitly distinguish:

- upstream work by ErrorFlynn and upstream contributors;
- KaronLabs-specific repository recovery/modification history;
- later third-party forks and modifications.

This prevents the anti-laundering system itself from overclaiming ownership.

### 4. `ATTRIBUTION.md`

`ATTRIBUTION.md` explains how to describe reuse accurately.

It is guidance and factual provenance documentation, not an additional software-license restriction and not legal advice.

The document will state that the MIT license permits reuse, modification, redistribution, sublicensing, and commercial use subject to its terms.

#### Accurate examples

Examples treated as accurate include:

- “Based on KaronLabs/ytdlp-korean-interface.”
- “Forked from KaronLabs/ytdlp-korean-interface and modified for this course.”
- “Uses the KaronLabs Korean localization recovery as a base.”
- “Commercial product based in part on KaronLabs/ytdlp-korean-interface.”
- “Derived from ErrorFlynn/ytdlp-interface through the KaronLabs Korean fork.”

#### Misleading examples

The document will identify examples that conflict with the recorded repository history, such as:

- “I created ytdlp-korean-interface from scratch,” when the work is derived from this repository;
- “This is entirely my original implementation,” when substantial source is copied from this repository;
- “KaronLabs had no role in these Korean recovery changes,” when the implementation tracks the KaronLabs repository history;
- presenting a derivative as an official KaronLabs release or official KaronLabs course without authorization.

The language must avoid claiming that every misleading statement is automatically a license violation. It will instead say that such claims are inconsistent with the repository's documented provenance and may raise separate legal or platform-policy questions depending on jurisdiction and facts.

### 5. `CITATION.cff`

The repository will add Citation File Format metadata so GitHub and compatible tools can expose a canonical repository citation.

The metadata will identify:

- title: `ytdlp-korean-interface`;
- repository URL;
- MIT license;
- KaronLabs as the maintainer/project identity for this derivative repository;
- the direct upstream relationship in the citation message;
- a canonical version only once a KaronLabs release actually exists.

The file must not represent KaronLabs as the sole author of `ErrorFlynn/ytdlp-interface`.

Until a KaronLabs release exists, omit a fabricated release version rather than invent one.

### 6. `README.md`

Add a short `Reuse & Attribution` section rather than turning the README into a legal document.

The section should communicate:

- forks, modifications, commercial use, and teaching are welcome under MIT;
- direct upstream is ErrorFlynn/ytdlp-interface;
- KaronLabs-specific repository changes have a documented provenance trail;
- users should preserve notices required by the MIT license;
- readers can use `NOTICE`, `PROVENANCE.md`, and `ATTRIBUTION.md` for detailed lineage.

Preferred KaronLabs-style line:

> 코드는 가져가셔도 됩니다. 족보까지 새로 쓰지는 말아주세요.

The joke is flavor; the factual sentences immediately around it must remain precise.

### 7. `docs/provenance-dispute-response.md`

This file is included in the first hardening pass.

It defines a factual, evidence-first response sequence for disputed origin claims:

1. archive the disputed public claim and its URL/date;
2. identify the derivative repository, binary, course material, or source sample;
3. preserve relevant hashes and screenshots;
4. compare against canonical KaronLabs commits/releases;
5. identify KaronLabs-derived portions and upstream portions separately;
6. contact the publisher privately first when reasonable;
7. request correction of the authorship/origin statement rather than removal of lawful MIT reuse;
8. escalate to a platform complaint only when supported by the platform's applicable policy and evidence;
9. avoid public accusations that go beyond verified facts.

The response guide must not automate harassment, mass reporting, doxxing, brigading, or retaliation.

## Release Provenance Discipline

### Canonical version naming

The first KaronLabs binary/source release should use:

`v2.19.1-karon.1`

Subsequent Karon releases based on the same upstream baseline increment the Karon suffix:

- `v2.19.1-karon.2`
- `v2.19.1-karon.3`

If the direct upstream baseline changes, the prefix changes with it.

### Release record

Each KaronLabs release must record:

- release tag;
- exact source commit SHA;
- direct upstream repository;
- direct upstream baseline tag and commit SHA;
- artifact filename;
- artifact SHA-256;
- build architecture;
- concise KaronLabs change summary;
- link to `PROVENANCE.md` at the released commit.

### Signing

Future canonical release tags should be cryptographically signed using a GitHub-supported verified signing method where practical.

The implementation phase must not invent or silently generate a signing identity for the user. If no signing key or SSH signing configuration exists, repository documents and release discipline can still be implemented, while key setup remains an explicit operator step.

### Immutable releases

If the repository/account supports GitHub immutable releases, canonical KaronLabs releases should use that feature after release contents are final.

Immutability is a release-integrity control, not a substitute for Git history or the provenance documents.

## Branding Boundary

The Provenance Hardening Pack distinguishes source-code rights from official-brand claims.

The repository will state that MIT permission to use the code does not itself establish:

- KaronLabs endorsement;
- official KaronLabs status;
- authorization to impersonate KaronLabs;
- authorization to describe a third-party course or product as published by KaronLabs.

This statement will be framed as an identity/endorsement clarification, not as a hidden restriction on use of the software.

If KaronLabs later registers trademarks or adopts a formal trademark policy, that policy can be added separately without rewriting the MIT software license.

## Evidence Strategy

The existing repository already contains unusually rich evidence. The hardening work should organize references to that evidence rather than manufacture artificial “proof” files.

Useful evidence includes:

- Git commit timestamps and parent relationships;
- design documents created during recovery;
- test source and test logs;
- candidate manifests;
- comparison patches;
- GUI screenshots;
- runtime provenance manifests;
- release tags and checksums once releases begin.

A later provenance dispute should rely on the smallest sufficient evidence set. Publishing hundreds of evidence files in an argument is less effective than showing a canonical commit, upstream baseline, diff, and release hash.

## Data Flow

### Normal reuse

```text
User finds repository
  ↓
README explains lineage
  ↓
LICENSE grants MIT rights
  ↓
NOTICE preserves concise provenance
  ↓
PROVENANCE gives detailed chain of origin
  ↓
ATTRIBUTION gives accurate description examples
  ↓
CITATION.cff exposes machine-readable citation
```

### Provenance dispute

```text
Questionable origin claim
  ↓
Identify claimed artifact/source
  ↓
Resolve canonical KaronLabs commit/release
  ↓
Compare Git history / source / hashes
  ↓
Use NOTICE + PROVENANCE as lineage map
  ↓
Follow docs/provenance-dispute-response.md
  ↓
Produce narrow factual correction request
```

## Error Handling and Edge Cases

### No KaronLabs binary release exists yet

Do not fabricate one. `CITATION.cff` and `PROVENANCE.md` will say the canonical source repository is the current authority until the first KaronLabs release is created.

### Existing unsigned commits

Do not rewrite public history merely to make old commits signed. Signed history begins prospectively.

### Existing upstream MIT copyright

Do not delete or replace ErrorFlynn's notice. KaronLabs provenance is additive and scoped to repository-specific changes and history.

### AI-assisted implementation history

Do not make the anti-laundering system depend on a sweeping copyright claim over AI-assisted output. The primary evidence is repository lineage, concrete diffs, selection/integration history, tests, design records, release metadata, and canonical Git history.

### Third-party contributions

If external contributors later submit substantial changes, provenance language should identify project contributors where appropriate. Git history remains the detailed contribution record.

### Fork removes provenance files

The system cannot prevent deletion. The canonical repository and earlier signed/immutable releases remain evidence of the prior history.

### Independent implementation looks similar

Do not assume copying based on feature similarity alone. Provenance claims should rely on source correspondence, commit history, distinctive implementation, copied text/assets, or other concrete evidence.

## Testing and Validation

The implementation must include deterministic checks that prevent provenance files from silently drifting apart.

At minimum, add a repository-level test that verifies:

- `NOTICE` exists;
- `PROVENANCE.md` exists;
- `ATTRIBUTION.md` exists;
- `CITATION.cff` exists;
- `docs/provenance-dispute-response.md` exists;
- the provenance records reference the canonical repository name `KaronLabs/ytdlp-korean-interface` where appropriate;
- `PROVENANCE.md` contains upstream baseline `v2.19.1`;
- `PROVENANCE.md` contains upstream commit `2173316ebb5e50af49a2a4e939693fa8c3a3459c`;
- `NOTICE` names ErrorFlynn and explicitly states that it does not add a new license restriction;
- `LICENSE` still contains the existing ErrorFlynn MIT notice;
- the README links to the provenance documents;
- no provenance document claims KaronLabs authored the entire upstream project;
- `CITATION.cff` has the required Citation File Format fields and is structurally parseable using the existing test environment.

If a new YAML dependency would be required only for this test, prefer a small deterministic structural validation rather than adding a dependency solely for `CITATION.cff`.

The test suite should also include negative assertions for accidental language such as:

- `KaronLabs created ytdlp-interface`;
- `original author of ytdlp-interface: KaronLabs`;
- any statement that changes the MIT grant into a no-commercial-use, no-course-use, or no-resale restriction.

## Acceptance Criteria

The Provenance Hardening Pack is complete when:

1. the existing MIT software freedom remains unchanged;
2. upstream ErrorFlynn attribution remains intact;
3. KaronLabs-specific repository recovery/modification history is clearly identified without overclaiming upstream authorship;
4. `NOTICE`, `PROVENANCE.md`, `ATTRIBUTION.md`, `CITATION.cff`, and `docs/provenance-dispute-response.md` exist and agree on repository lineage;
5. the README contains a short reuse/provenance section linking to those records;
6. deterministic tests catch removal or material drift of the provenance records;
7. release naming and release-metadata rules are documented for `v2.19.1-karon.N`;
8. future signing is documented as prospective and no old history is rewritten;
9. no file claims that lawful MIT commercial reuse, teaching, or resale is prohibited;
10. a third party can answer “where did this code come from?” using the repository alone without relying on oral history.

## Implementation Boundary

The first implementation pass should modify only repository metadata, documentation, and deterministic provenance tests.

It should not:

- alter downloader behavior;
- alter localization behavior;
- alter runtime update behavior;
- rewrite historical commits;
- create a fake KaronLabs release;
- create or upload cryptographic private keys;
- change the software license away from MIT.

A later release task can create the first canonical KaronLabs release after a reviewed binary artifact exists.

## Maintainer Summary

The intended posture is simple:

> Fork it. Modify it. Sell it. Teach it. Improve it.
>
> Keep the MIT requirements intact, describe where it came from accurately, and do not turn a derivative work into a fake origin story.

Or, in the repository's less formal voice:

> 코드는 가져가셔도 됩니다. 족보까지 새로 쓰지는 말아주세요.
