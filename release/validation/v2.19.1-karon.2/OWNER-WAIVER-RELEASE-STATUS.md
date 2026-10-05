# v2.19.1-karon.2 release preparation status

## Owner decision

Manual GUI validation is `WAIVED_BY_OWNER`, not `PASS`. The owner requested:

> 남은 gui 확인 거ㅗㄴ너뛰고 릴리즈 까지 달려

The earlier `잘되네` report is a limited, unstructured user observation. The
waiver does not waive automated runtime tests, source integrity, licenses, CI,
or final-package checks. No screenshots, media results, or GUI PASS summaries
were manufactured. The waiver is limited to this release and the exact candidate
identified by `gui-validation-waiver.json` in this directory.

## Frozen application candidate

- Application source: `b80f594a2b6673d28e00e705659c39b0c4bed647`.
- Application tree: `541a9bef018b4b266ba0ca8469ecb2868ef1e6df`.
- EXE SHA-256: `1e23c9e0962f0ea8f78dca8f0b832c9706ce4aedc1ff7b8703e6b806e0542fd4`.
- Candidate manifest SHA-256: `986754c3b2467c12127b7497434c0b3caad5fa6aef13406e2aaefb6b8040163d`.
- Candidate manifest length: `21628` bytes.

The previous sealed candidate and karon.1 remain unchanged. Subsequent release
tool, fixture, and notice changes do not replace the application binary.

## Independent results completed on 2026-10-05

These are separate scopes, not a claim that the final ZIP is approved.

| Scope | Actual result |
| --- | --- |
| Native quality policy | 116 checks, zero failures |
| LGPL fixture unit tests | 10 passed |
| Actual fixture engine checks | 9 passed |
| Production helper policy checks | 17 passed |
| Additional Best runtime checks | 2 passed |
| GUI waiver contract | 31 passed |
| License/AssemblyOnly synthetic contract | 26 passed |
| Publication/v2-v3 receipt contract | 117 passed |
| Existing GUI evidence synthetic contract | 70 passed on the final full run |

Actual runtime artifacts include 1080p and 720p video with audio, Best at 2160p,
and MP3 audio. The 1080p policy rejects the same 2160p-only input. Disappearing
pinned formats fail without a silent lower-quality fallback. EXE and production
helper hashes were unchanged before and after runtime testing.

The H.264 fixture regression failed against the baseline as expected, then
passed with `libopenh264` instead of GPL-only `libx264`. Application code was
not changed to accommodate the fixture.

The initial GUI evidence contract run had one unexplained failure; a later
complete run passed all 70 tests and a separate positive verifier run exited
zero. This synthetic contract result is not an actual six-case Windows GUI
validation result.

## Open release gates

- Actual non-runtime source collection is closed for this candidate. Its
  completed evidence bundle and inventory are retained outside the repository.
- Production license assembly attempt 02 exited nonzero with
  `release_license_lock_source_archive_mismatch`. The producer and integrator
  schemas still require explicit adaptation. Synthetic fixture success does
  not resolve this production failure.
- Deno/FFmpeg generated source closures must not be labeled as upstream commit
  ZIP downloads. Their own bytes, sources, and producer records must remain
  distinguishable.
- FFmpeg's complete source ZIP is `2528152976` bytes, exceeding GitHub's
  per-asset limit of less than 2 GiB. Splitting sources changes the approved
  four-asset layout and is pending the owner's decision. No sources were
  removed to force the package under the limit.
- Exact final packaging-commit CI, complete source ZIP/SPDX generation,
  independent final license adjudication, and final runtime ZIP verification
  have not completed.

The stable tag and public binary Release must remain absent until these
non-waived gates pass. The tracked dependency template remains `NOT_VERIFIED`;
it is not a verified final release lock.
