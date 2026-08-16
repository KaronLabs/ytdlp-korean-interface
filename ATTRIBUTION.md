# Reuse & Attribution Guide

This document explains how to describe reuse of `KaronLabs/ytdlp-korean-interface` accurately.

Canonical repository: `KaronLabs/ytdlp-korean-interface`  
Direct upstream: `ErrorFlynn/ytdlp-interface`

This is provenance and attribution guidance. It is **not an additional software-license restriction** and it is not legal advice. The actual software license is the [MIT License](LICENSE).

## Reuse is welcome

The MIT License remains the governing software license. Subject to its terms, lawful reuse includes:

- forks;
- modifications;
- redistribution;
- commercial use;
- paid teaching and paid courses;
- internal company use;
- packaging the software with another product;
- publishing your own derivative version.

In other words: the purpose of these provenance records is **not** to stop people from using the code.

> 코드는 가져가셔도 됩니다. 족보까지 새로 쓰지는 말아주세요.

## Accurate ways to describe a derivative

These are examples of clear, accurate descriptions:

- “Based on `KaronLabs/ytdlp-korean-interface`.”
- “Forked from `KaronLabs/ytdlp-korean-interface` and modified for this course.”
- “Uses the Korean localization recovery from `KaronLabs/ytdlp-korean-interface` as a base.”
- “Commercial product based in part on `KaronLabs/ytdlp-korean-interface`.”
- “Derived from `ErrorFlynn/ytdlp-interface` through the KaronLabs Korean recovery project.”
- “We modified the KaronLabs fork for our own workflow.”

You do not need to pretend your derivative is unoriginal. Derivative work can contain substantial new work of its own. The useful thing is simply to keep the lineage accurate.

## Examples of misleading origin claims

The following statements would conflict with the recorded repository history when made about a derivative that substantially reuses this repository:

- “I created `ytdlp-korean-interface` from scratch.”
- “This is entirely my original implementation,” when substantial source was copied from this repository.
- “KaronLabs had no role in these Korean recovery changes,” when the implementation follows the KaronLabs repository history.
- presenting a fork as an official KaronLabs release when KaronLabs did not publish it;
- presenting a third-party paid course as an official KaronLabs course without authorization;
- removing visible branding and then claiming that the underlying recovery/hardening implementation was independently created, when source correspondence shows otherwise.

This document does **not** declare that every misleading statement is automatically a violation of the MIT License. License compliance, copyright, authorship, endorsement, trademark, consumer-protection rules, platform policy, and other legal questions are separate issues that depend on the facts and jurisdiction.

The narrower claim made here is factual: Git history, upstream ancestry, source diffs, tests, design records, and release metadata can be used to check whether an origin claim matches the recorded history.

## Upstream attribution matters too

KaronLabs is itself building on prior open-source work.

The direct GUI upstream is:

- `ErrorFlynn/ytdlp-interface`
- baseline tag `v2.19.1`
- baseline commit `2173316ebb5e50af49a2a4e939693fa8c3a3459c`

The underlying media extraction/download engine is `yt-dlp`.

KaronLabs does not claim sole authorship of unchanged upstream code. Accurate provenance should preserve the upstream layer, the KaronLabs repository-specific layer, and any later third-party layer.

## Official-status and branding boundary

Permission to use MIT-licensed source code does not by itself establish that a third party is:

- KaronLabs;
- endorsed by KaronLabs;
- an official KaronLabs distributor;
- an official KaronLabs course provider;
- publishing an official KaronLabs release.

A derivative should use its own identity unless it is actually authorized to present itself as an official KaronLabs offering.

This clarification is about identity and provenance. It is not a hidden restriction on forks, modifications, commercial use, or paid teaching.

## What to preserve when redistributing

Follow the actual requirements in [`LICENSE`](LICENSE), including preservation of the copyright and permission notice in copies or substantial portions of the Software.

For clearer provenance, we also encourage derivatives to retain or link to:

- [`NOTICE`](NOTICE)
- [`PROVENANCE.md`](PROVENANCE.md)
- this `ATTRIBUTION.md`

That recommendation does not replace or expand the MIT License terms.

## If origin is disputed

Use primary-source evidence rather than arguments about branding or screenshots alone.

Start with:

1. the direct upstream baseline;
2. the relevant KaronLabs commit or release;
3. source correspondence and commit ancestry;
4. the smallest sufficient set of tests, design records, or artifact hashes.

The evidence-first procedure is documented in [`docs/provenance-dispute-response.md`](docs/provenance-dispute-response.md).

## Summary

**Allowed:** reuse it, fork it, modify it, sell a derivative, teach with it, build something better on top of it.

**Keep accurate:** where the code and repository-specific recovery work came from.

Open source works better when people can freely build on previous work without having to rewrite history to make their own contribution look valuable.
