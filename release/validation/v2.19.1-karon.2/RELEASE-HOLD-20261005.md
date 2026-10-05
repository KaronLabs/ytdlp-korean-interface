# v2.19.1-karon.2 release hold

## Owner-approved scope

The owner waived the remaining manual GUI matrix and representative manual
checks. Their status is `WAIVED_BY_OWNER`, not `PASS`. The candidate-bound
waiver is `gui-validation-waiver.json`. Automated tests, source/license
verification, final-package checks, and exact-target CI are not waived.

## Frozen application candidate

- Application source: `b80f594a2b6673d28e00e705659c39b0c4bed647`.
- Application tree: `541a9bef018b4b266ba0ca8469ecb2868ef1e6df`.
- Candidate manifest SHA-256: `986754c3b2467c12127b7497434c0b3caad5fa6aef13406e2aaefb6b8040163d`.
- Application EXE SHA-256: `1e23c9e0962f0ea8f78dca8f0b832c9706ce4aedc1ff7b8703e6b806e0542fd4`.

The packaging/tools commit is separate from this application source commit.
The earlier sealed candidate and the karon.1 release have not been replaced.

## Independent licensing findings: NOT_VERIFIED

1. The pinned Windows yt-dlp executable is a GPLv3+ combined distribution,
   whereas the yt-dlp project source itself is Unlicense. The collected source
   inventory binds the project source ZIP, official executable, and checksums,
   but does not yet bind the exact bundled dependency versions and their
   corresponding source/build materials. The preserved third-party notice is
   not by itself proof that this redistribution supplies corresponding source.
   See the [pinned official licensing statement](https://github.com/yt-dlp/yt-dlp/blob/bbc809a1161d3bfca51fa36f59dda35556ee85a0/README.md#licensing).
2. Deno's collected notice includes SPDX canonical fallback text with generic
   copyright placeholders. Original or applicable shared copyright notices
   must be traced to their actual included locations. This is an unverified
   attribution question, not a finding that every fallback violates a license.
   See the [pinned Deno license](https://github.com/denoland/deno/blob/2d674b25625bcc367853d00fe86f6e84390f88cb/LICENSE.md).
3. Modified static-library source trees and build materials exist in the
   candidate-bound dependency archive inside the non-runtime evidence bundle.
   They must remain in the public corresponding-source assets, with extraction
   instructions; replacing them with upstream-only ZIPs is insufficient.

Application MIT licensing is distinct from each third-party component's terms.
This limited technical assessment is not legal advice or final-package approval.

### Bounded follow-up findings

- The exact yt-dlp upstream Windows x64 build is traceable to
  [run 33341826683, job 99338791679](https://github.com/yt-dlp/yt-dlp/actions/runs/33341826683/job/99338791679).
  Its pinned requirements describe build inputs, not automatically every module
  embedded in the executable. Corresponding-source collection remains open.
- A direct inspection of the supplied Deno source closure found original Deno
  copyright headers and the shared MIT license for `serde_v8 0.309.0`.
  `deno_core_icudata 0.77.0` identifies the Deno authors and MIT; the closure also
  contains the separate Unicode license for native ICU. These two placeholder
  examples do not establish missing original notices. Exact ICU data/source
  binding and final-package coverage remain unverified.
- Do not treat the fallback placeholder count as a license-violation count or
  use it to require an unsupported blanket license rewrite.

## Source-asset size: owner decision required

The actual FFmpeg source closure ZIP is `2,528,152,976` bytes before adding
Deno and application sources. GitHub requires each release asset to be smaller
than 2 GiB. See the [official release-asset limit](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases#storage-and-bandwidth-quotas).

The approved four-asset layout therefore cannot be published unchanged with
the current complete source closures. Permission to publish recoverable source
parts has been requested. No source has been removed to fit the limit, and no
permission has been presumed from a preselected option.

## Remaining release gates

- Producer-adapter contracts and the actual production assembly path require
  independent verification. Collection success is not license approval.
- CI must succeed on the exact final packaging commit. An earlier commit's run
  is not automatically applicable to a later commit.
- The final portable ZIP and corresponding-source assets have not been
  generated or approved. Final file-by-file license/source checks remain open.
- No karon.2 tag, draft release, or stable binary release has been created by
  this work. HOLD remains until all non-waived gates pass.

Do not treat passing synthetic contracts, a source push, or a verified assembly
format as authorization to bypass the independent license/publication gates.
