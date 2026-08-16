# Provenance Dispute Response

This procedure is for situations where a third party appears to reuse `KaronLabs/ytdlp-korean-interface` while making a disputed origin, authorship, or official-status claim.

The goal is **correction of the record using evidence**, not retaliation.

This document is not legal advice. If a dispute becomes legally significant, obtain advice appropriate to the relevant jurisdiction.

## Principles

1. Preserve evidence before contacting anyone.
2. Separate upstream `ErrorFlynn/ytdlp-interface` material from KaronLabs-specific repository history.
3. Distinguish lawful MIT reuse from a disputed origin claim.
4. Prefer hashes, source correspondence, commit history, and archived statements over assumptions.
5. Request the narrowest reasonable correction first.
6. Use a platform policy process only when the facts actually fit that policy.
7. Do not use harassment, threats, mass-reporting campaigns, or doxxing.

## Step 1 — Preserve the disputed claim

Before a post, repository, course page, video description, or download is edited, preserve the relevant public material.

Record:

- URL;
- visible account or publisher name;
- date and time observed;
- exact wording of the disputed claim;
- screenshots where useful;
- repository commit/tag if available;
- downloadable artifact filename if available.

Do not collect unrelated private information.

## Step 2 — Preserve the technical artifact

When reasonably and lawfully available, preserve the exact technical object being compared.

Examples:

- Git commit SHA;
- source archive;
- binary installer or ZIP;
- course sample repository;
- public code snippet.

Calculate a cryptographic hash such as SHA-256 for downloaded artifacts so the evidence refers to a specific byte sequence.

Example record:

```text
Artifact: example-ytdlp-course.zip
SHA-256: <calculated value>
Observed from: <public URL>
Observed at: <timestamp>
```

Do not execute an untrusted binary merely to prove provenance when static source or hash evidence is sufficient.

## Step 3 — Resolve the canonical upstream boundary

The direct GUI upstream for this repository is:

```text
ErrorFlynn/ytdlp-interface
v2.19.1
2173316ebb5e50af49a2a4e939693fa8c3a3459c
```

First determine which matching material belongs to upstream. Do not incorrectly attribute ErrorFlynn's work to KaronLabs merely because it also appears in the KaronLabs repository.

The underlying `yt-dlp` project is another separate upstream layer.

## Step 4 — Resolve the relevant KaronLabs history

Canonical repository:

```text
KaronLabs/ytdlp-korean-interface
```

Use the earliest relevant canonical commits, source diffs, design records, tests, and—once available—release records.

Useful repository evidence can include:

- [`PROVENANCE.md`](../PROVENANCE.md)
- [`NOTICE`](../NOTICE)
- [`ATTRIBUTION.md`](../ATTRIBUTION.md)
- Git commit ancestry and timestamps
- `docs/superpowers/specs/`
- `tests/contract/`
- `tests/native/`
- `tests/powershell/`
- `tools/`
- `review/evidence/`

Prefer a small, understandable proof over an enormous evidence dump.

## Step 5 — Compare concrete correspondence

Strong provenance evidence is based on specific correspondence, for example:

- substantially identical implementation logic;
- the same unusual localization keys or fallback structure;
- the same state-token separation;
- copied tests or fixtures;
- matching runtime-maintenance transaction logic;
- matching documentation language;
- matching manifests or evidence structures;
- Git ancestry or a visible fork relationship.

Feature similarity alone is not enough. Two projects can independently implement the same idea.

Do not publicly accuse a party of copying merely because its UI or feature list looks similar.

## Step 6 — Classify the actual problem

Ask what is actually disputed.

### Case A — Lawful reuse with accurate provenance

Example:

> “This course uses a modified version of KaronLabs/ytdlp-korean-interface.”

No provenance dispute exists. Paid teaching, forks, modifications, redistribution, and commercial use are not prohibited merely because money is involved.

### Case B — Missing required MIT notice

Compare the redistribution against [`LICENSE`](../LICENSE) and the actual MIT notice requirement.

Treat this as a license-compliance question, not automatically as an authorship dispute.

### Case C — Misleading origin claim

Example:

> “I built this entire implementation from scratch,”

while concrete source correspondence shows substantial derivation from the KaronLabs repository.

This is the primary use case for this procedure.

### Case D — False official-status claim

Example:

> “Official KaronLabs course”

without authorization.

This is an identity/endorsement issue distinct from ordinary MIT source reuse.

## Step 7 — Request a narrow factual correction

When reasonable, contact the publisher privately before escalating.

A useful correction request should include:

- the exact statement believed to be inaccurate;
- the canonical repository URL;
- the relevant upstream/KaronLabs distinction;
- one or two concrete evidence references;
- the specific correction requested.

Example structure:

> Your material appears to reuse `KaronLabs/ytdlp-korean-interface`, which is itself based on `ErrorFlynn/ytdlp-interface`. Reuse is welcome under the MIT License. The concern is only the statement that this implementation was created entirely from scratch. The corresponding implementation is present in the earlier canonical repository history at `<commit>`. Please correct the origin statement to disclose the project it was derived from.

Do not demand removal of lawful reuse when a provenance correction is sufficient.

## Step 8 — Escalate only against a matching platform policy

If a publisher refuses correction and escalation is appropriate, identify the exact platform policy that applies before filing anything.

Possible categories may include, depending on the facts and platform:

- copyright/license compliance;
- impersonation;
- misleading commercial representation;
- trademark or brand impersonation;
- academic or marketplace integrity policies.

A platform complaint should accurately state what the evidence proves. Do not convert an origin disagreement into a broader accusation unsupported by the record.

## Step 9 — Keep public statements factual

If a public clarification becomes necessary, publish the smallest sufficient factual record:

- canonical upstream;
- canonical KaronLabs commit/release;
- disputed statement;
- relevant source correspondence;
- requested correction.

Avoid speculation about motives.

Avoid personal attacks, harassment, dogpiling, threats, and doxxing.

The objective is to make the history checkable, not to manufacture a public punishment campaign.

## Recommended evidence packet

For most disputes, the following is enough:

```text
1. Archived disputed claim
2. URL + timestamp
3. Derivative commit or artifact SHA-256
4. ErrorFlynn upstream baseline SHA
5. Relevant earlier KaronLabs commit SHA
6. Small source diff / correspondence excerpt
7. PROVENANCE.md
8. Copy of the correction request and response
```

Only add more evidence if the dispute actually requires it.

## What not to do

Do not:

- fabricate timestamps or provenance;
- rewrite old public history to create retroactive evidence;
- claim KaronLabs authored unchanged ErrorFlynn or `yt-dlp` code;
- assume every similar implementation is copied;
- mass-report without checking the applicable platform policy;
- encourage harassment;
- publish private personal information;
- engage in doxxing;
- threaten legal action you are not prepared or entitled to pursue.

## Summary

The repository stays open.

The response model is equally simple:

```text
preserve → hash → compare → separate upstream → request correction → policy-based escalation if justified
```

The strongest anti-laundering tool is a clean, boring, checkable historical record.
