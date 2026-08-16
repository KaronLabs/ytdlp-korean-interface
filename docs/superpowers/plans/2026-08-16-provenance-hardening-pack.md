# Provenance Hardening Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve unrestricted MIT reuse while making the repository's upstream lineage and KaronLabs-specific recovery/hardening history explicit, redundant, machine-readable, and easy to verify.

**Architecture:** Add a small provenance layer around the existing repository without changing runtime code or the MIT license. Human-readable lineage files, machine-readable citation metadata, README links, and deterministic contract tests must all agree on the canonical repository, direct upstream baseline, and the boundary between lawful reuse and misleading origin claims.

**Tech Stack:** Markdown, Citation File Format YAML, Python `unittest`, Git/GitHub repository history.

## Global Constraints

- Preserve the existing MIT `LICENSE` without adding field-of-use, commercial-use, paid-course, resale, or fork restrictions.
- Preserve ErrorFlynn's upstream copyright and direct-upstream role.
- Canonical repository: `KaronLabs/ytdlp-korean-interface`.
- Direct upstream: `ErrorFlynn/ytdlp-interface`.
- Upstream baseline tag: `v2.19.1`.
- Upstream baseline commit: `2173316ebb5e50af49a2a4e939693fa8c3a3459c`.
- KaronLabs provenance claims apply only to documented repository-specific recovery, modifications, testing, maintenance, and evidence history; do not claim sole authorship of unchanged upstream code.
- Do not turn provenance guidance into an additional software-license restriction.
- Do not fabricate a KaronLabs release version; no KaronLabs public release exists yet.
- Existing unsigned public commits remain unchanged; signing begins prospectively when an operator configures a signing identity.

---

### Task 1: Add a provenance contract test

**Files:**
- Create: `tests/contract/test_provenance_contract.py`
- Existing runner: `tests/run_contract_tests.py`

**Interfaces:**
- Consumes: repository root files and Markdown/CFF text.
- Produces: deterministic `unittest` failures when provenance records are missing or drift on canonical identifiers.

- [ ] **Step 1: Add tests before provenance files exist**

Create `tests/contract/test_provenance_contract.py` using only the Python standard library. It must assert:

```python
REQUIRED_FILES = [
    "NOTICE",
    "PROVENANCE.md",
    "ATTRIBUTION.md",
    "CITATION.cff",
    "docs/provenance-dispute-response.md",
]
```

Tests must require:

- every required file exists;
- `NOTICE`, `PROVENANCE.md`, `ATTRIBUTION.md`, and `CITATION.cff` identify `KaronLabs/ytdlp-korean-interface`;
- provenance documents identify `ErrorFlynn/ytdlp-interface`;
- `PROVENANCE.md` contains both `v2.19.1` and `2173316ebb5e50af49a2a4e939693fa8c3a3459c`;
- `ATTRIBUTION.md` explicitly says lawful forks, modifications, commercial use, and paid teaching remain allowed under MIT;
- `ATTRIBUTION.md` says it is guidance/provenance documentation rather than an additional software-license restriction;
- `CITATION.cff` contains `license: MIT` and does not invent `v2.19.1-karon.1` as a released version;
- `README.md` links to `NOTICE`, `PROVENANCE.md`, and `ATTRIBUTION.md`;
- the existing `LICENSE` still includes `Copyright (c) 2021 ErrorFlynn` and `Permission is hereby granted, free of charge`.

- [ ] **Step 2: Run the test and confirm the expected RED state**

Run:

```bash
python tests/run_contract_tests.py
```

Expected: provenance tests fail because the new provenance files do not yet exist.

- [ ] **Step 3: Commit the failing contract test**

Commit only `tests/contract/test_provenance_contract.py` with:

```text
test: define provenance hardening contract
```

---

### Task 2: Add the human-readable provenance records

**Files:**
- Create: `NOTICE`
- Create: `PROVENANCE.md`
- Create: `ATTRIBUTION.md`
- Create: `docs/provenance-dispute-response.md`

**Interfaces:**
- Consumes: approved design at `docs/superpowers/specs/2026-08-16-provenance-hardening-pack-design.md` and existing repository history.
- Produces: concise redistribution provenance, detailed lineage, accurate reuse language, and evidence-first dispute response procedure.

- [ ] **Step 1: Create `NOTICE`**

`NOTICE` must state:

- canonical KaronLabs repository;
- direct upstream URL and baseline tag/commit;
- ErrorFlynn copyright is retained in `LICENSE`;
- KaronLabs-specific Korean recovery/hardening/testing/maintenance history is documented from 2026 onward;
- the notice documents provenance and does not add a software-license restriction.

- [ ] **Step 2: Create `PROVENANCE.md`**

Include:

- lineage `yt-dlp -> ErrorFlynn/ytdlp-interface v2.19.1 -> KaronLabs/ytdlp-korean-interface`;
- exact upstream tag and commit;
- KaronLabs repository URL;
- KaronLabs-specific documented work scope;
- evidence map to design docs, contract/native/PowerShell tests, maintenance tooling, smoke tooling, and review evidence;
- verification procedure based on canonical commits, diffs, releases, and hashes;
- explicit boundary between upstream, KaronLabs repository history, and later third-party forks;
- future release naming discipline beginning with `v2.19.1-karon.1` only when an actual release is created;
- prospective signed-tag and immutable-release guidance without pretending those controls already exist.

- [ ] **Step 3: Create `ATTRIBUTION.md`**

State clearly:

- MIT reuse, modification, redistribution, commercial use, and paid teaching are welcome subject to the MIT license;
- accurate examples such as `Based on KaronLabs/ytdlp-korean-interface`;
- misleading examples such as claiming a derivative was created from scratch;
- the document is provenance guidance, not an additional software-license restriction or legal advice;
- permission to use MIT code does not itself imply official KaronLabs endorsement.

- [ ] **Step 4: Create `docs/provenance-dispute-response.md`**

Define the evidence-first sequence:

1. archive the public claim and date/URL;
2. identify the derivative artifact/source/course;
3. preserve hashes/screenshots;
4. resolve the canonical KaronLabs commit/release;
5. compare source/history while separating upstream material from KaronLabs-specific history;
6. request factual correction first when reasonable;
7. escalate only under an applicable platform policy and supported evidence;
8. avoid harassment, mass reporting, doxxing, or unsupported public accusations.

- [ ] **Step 5: Commit the human-readable records**

Commit the four files with:

```text
docs: add canonical provenance and attribution records
```

---

### Task 3: Add machine-readable citation metadata

**Files:**
- Create: `CITATION.cff`

**Interfaces:**
- Consumes: canonical repository and upstream facts from `PROVENANCE.md`.
- Produces: GitHub/compatible citation metadata without claiming KaronLabs authored unchanged upstream source.

- [ ] **Step 1: Create valid CFF metadata**

Use CFF 1.2.0 with:

```yaml
cff-version: 1.2.0
title: ytdlp-korean-interface
type: software
license: MIT
repository-code: https://github.com/KaronLabs/ytdlp-korean-interface
```

Identify KaronLabs as the repository/project maintainer identity, and use the message/abstract to disclose that this is a Korean recovery/hardening derivative of `ErrorFlynn/ytdlp-interface v2.19.1`. Do not include a `version` field until an actual KaronLabs release exists.

- [ ] **Step 2: Commit citation metadata**

Commit with:

```text
docs: add machine-readable repository citation
```

---

### Task 4: Connect provenance records from README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: `NOTICE`, `PROVENANCE.md`, `ATTRIBUTION.md`, `CITATION.cff`.
- Produces: a short public-facing `Reuse & Attribution` section.

- [ ] **Step 1: Add a concise README section before License**

The section must say:

- forks, modifications, commercial use, and teaching are welcome under MIT;
- direct upstream remains `ErrorFlynn/ytdlp-interface`;
- KaronLabs recovery/hardening history is documented through the provenance records;
- required MIT notices must be preserved according to the license;
- `NOTICE`, `PROVENANCE.md`, and `ATTRIBUTION.md` are linked.

Include the KaronLabs-style line:

> **코드는 가져가셔도 됩니다. 족보까지 새로 쓰지는 말아주세요.**

Immediately surround the joke with precise factual language so it cannot be mistaken for an additional license condition.

- [ ] **Step 2: Commit README update**

Commit with:

```text
docs: expose reuse and provenance guidance
```

---

### Task 5: Verify the hardening contract and repository boundary

**Files:**
- Test: `tests/contract/test_provenance_contract.py`
- Inspect: `LICENSE`, `NOTICE`, `PROVENANCE.md`, `ATTRIBUTION.md`, `CITATION.cff`, `README.md`, `docs/provenance-dispute-response.md`

**Interfaces:**
- Consumes: completed tasks 1-4.
- Produces: fresh test evidence and a checked provenance boundary.

- [ ] **Step 1: Run the full repository contract suite**

Run:

```bash
python tests/run_contract_tests.py
```

Expected: exit code `0`; provenance tests and existing recovery contract tests pass.

- [ ] **Step 2: Confirm no license mutation occurred**

Compare `LICENSE` against its pre-hardening blob and confirm the file still contains the original ErrorFlynn MIT notice unchanged.

- [ ] **Step 3: Check cross-document canonical identifiers**

Confirm all relevant records agree on:

```text
KaronLabs/ytdlp-korean-interface
ErrorFlynn/ytdlp-interface
v2.19.1
2173316ebb5e50af49a2a4e939693fa8c3a3459c
```

- [ ] **Step 4: Confirm release/signing language is prospective**

Confirm no document claims that `v2.19.1-karon.1`, signed tags, or immutable releases already exist.

- [ ] **Step 5: Record operator-only follow-up**

After implementation, report that cryptographic signing and immutable GitHub Releases require an operator signing identity and an actual release. Do not generate credentials or fabricate a release during this hardening pass.
