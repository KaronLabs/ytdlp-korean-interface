# Conservative release and workspace cleanup

## Boundaries

- Keep the frozen application candidate, its manifest, and earlier sealed
  candidates unchanged. Keep the active GUI runtime and user settings.
- Keep the existing 407-input FFmpeg source closure. A directory named
  `cache` is not automatically disposable: it can contain required sources.
- Do not rewrite Git history, force-push, or ignore all ZIP, DLL, or LIB files.
- Keep the owner GUI waiver as `WAIVED_BY_OWNER`, never as `PASS`.

## Git and local cleanup

The repository root `.gitignore` excludes `.scratch`, `.validation`, `build`,
and `out`. Existing ignore rules remain in place. Ignoring a tracked path does
not untrack it; only explicitly identified disposable tracked paths may be
removed from the index while retaining their local files.

Delete only individually identified, untracked, unused generated build files
or disposable outputs. Resolve every deletion target within the workspace;
reject reparse points and paths used by active applications or builds. Do not
recursively remove `.scratch`, `.validation`, or a worktree. Keep uncertain
items until their source, release, and recovery references are resolved.

## Source ZIP candidate

Preserve the original FFmpeg source ZIP. An optimized candidate may copy all
entries without modifying their payload bytes, names, timestamps, or external
attributes. Keep existing source archives stored without another compression
pass and compress only the surrounding metadata. Do not remove Git metadata,
generated files, patches, or licenses from nested source archives without
establishing that their builds do not require them.

The accompanying `source-bindings.json` records the original container and
the replacement generated-source archive identity. Its archive fragment uses
the existing `generated-source-closure` contract and remains `NOT_VERIFIED`.
It is not a verified license lock or authority to publish a release.

After independent entry-by-entry verification, use the candidate archive
fragment in the candidate-aligned staging license template and supply that
same archive to `build-release-license-lock.ps1` via
`-FfmpegSourcesArchivePath`. Preserve the origin archive and build metadata.
The existing lock builder must establish the new producer/archive binding;
do not manually change verification status or bypass source inventory checks.

## Handoff and measurements

## User downloads and source transport

Normal users download only the `*-win-x64.zip` portable runtime package,
extract the entire directory, and start `ytdlp-interface.exe`. The runtime
package includes the required engines, resources, and third-party notices,
not development caches or corresponding-source archives. Its final size
must be measured from the packaged runtime, not from the source collection.

Corresponding sources are separate development and redistribution material.
They are not required to run the portable application. GitHub's automatic
`Source code (zip)` download is the application repository snapshot; it is
not a substitute for the complete dependency corresponding-source bundle.

GitHub requires each release asset to be smaller than 2 GiB. A larger source
container can therefore be transported as numbered binary parts of at most
1 GiB. Restore all parts in their recorded order to recover the original
ZIP before extracting it. Include restoration instructions, the original
container hash, and each part's length and hash. Keep both the original
source ZIP and the frozen application candidate unchanged.

Preparing parts is not license verification or release approval. Do not
upload them or publish the runtime until the non-waived release gates pass.
The existing four-asset publisher does not accept an expanded split-source
inventory; its receipt, checksum, and asset-inventory contract must explicitly
support the final transport layout before that layout is published. Do not
bypass the publisher or replace source identities with part hashes.

Reference: https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases

## Handoff and measurements

The independent verifier checks the ignore rules, protected paths, every
source entry, candidate identity, final runtime behavior, and license gates.
Report deleted local bytes, tracked-content changes, source-ZIP reduction,
and temporary additional disk usage separately. Do not claim that source
ZIP creation, source push, or assembly checks establish release approval.

Commit cleanup rules and documentation separately when appropriate, then
push only after the agreed independent checks. Do not publish a tag or
release while non-waived gates remain open.
