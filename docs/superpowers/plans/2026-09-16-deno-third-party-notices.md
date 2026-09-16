# Deno 2.7.14 Third-Party Notice and Source Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce fail-closed, reproducible Deno 2.7.14 notice and source evidence without claiming an overall release PASS.

**Architecture:** A PowerShell entrypoint validates pinned manifests and the official executable, compares Cargo metadata and Cargo.lock/vendor state, validates the complete pinned native source corpus, then creates deterministic notice, component, inventory, and ZIP artifacts only after every gate passes. Upstream license-file omissions create a blocker artifact and no success bundle.

**Tech Stack:** PowerShell 7.4+, Pester, Cargo metadata/vendor, Git, SHA-256, .NET ZipArchive.

**Spec:** `docs/superpowers/specs/2026-09-16-deno-third-party-notices-design.md`

## Global Constraints

- Work only in `.worktrees/task-7-deno-notices` based on `5861a248918f1757d381fc498b9c482b36c0a2e8`.
- Do not push, publish, modify Task 3 lock, or claim overall release PASS.
- Treat the public closure as a verified conservative superset, not an exact linked set.
- Reject missing license files, checksum mismatches, mutable sources, NOASSERTION, native omissions, path collisions, and target mismatch.

---

### Task 1: RED contracts

**Files:**
- Create: `tests/powershell/collect-deno-third-party-notices.Tests.ps1`

**Interfaces:**
- Consumes: no production collector.
- Produces: seven executable failure and positive identity contracts.

- [ ] Write tests for every required rejection and the exact official positive source.
- [ ] Run Pester and retain a non-zero RED result with `TotalCount > 0`.

### Task 2: Collector and pinned manifests

**Files:**
- Create: `tools/collect-deno-third-party-notices.ps1`
- Create: `release/runtime/v2.19.1-karon.2/deno/inputs.json`
- Create: `release/runtime/v2.19.1-karon.2/deno/native-components.json`
- Create: `release/runtime/v2.19.1-karon.2/deno/THIRD-PARTY-NOTICES.template.txt`
- Create: `release/runtime/v2.19.1-karon.2/deno/README.md`

**Interfaces:**
- Consumes: pinned source archives, native archives, Cargo.lock/vendor, Cargo metadata, and official deno.exe.
- Produces: notice text, component manifest, source inventory, deterministic source ZIP, or a deterministic blocker report.

- [ ] Implement the minimum validation functions required by the RED contracts.
- [ ] Implement full collection with validation before artifact publication.
- [ ] Run the collector against the exact official inputs.
- [ ] Run Pester and require zero failures with `TotalCount > 0`.

### Task 3: Commit evidence tooling

**Files:**
- Modify: only files listed in Tasks 1 and 2.

**Interfaces:**
- Consumes: completed implementation and fresh test/collection outputs.
- Produces: local commit `build: collect deno third-party notices`.

- [ ] Stage only the listed paths.
- [ ] Commit locally without push or publication.
