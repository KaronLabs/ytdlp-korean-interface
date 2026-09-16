# Deno 2.7.14 Third-Party Notice and Source Closure Design

## Scope

Collect reproducible license and source evidence for the Deno 2.7.14 Windows
x86_64 runtime shipped with `v2.19.1-karon.2`. This work does not establish an
overall release PASS and does not modify the release-wide corresponding-source
lock.

## Identity

The collector binds all output to the official executable SHA-256
`b6e83993f1f1ab97075a77043de61118966d719b5450bc631251d47c3a34230b`,
Deno source commit `2d674b25625bcc367853d00fe86f6e84390f88cb`, rusty_v8
`v147.4.0`, and V8 commit `708fc9b76e540c03e9a7c5e1d4f768b279517589`.

## Closure model

The pinned Deno workflow builds release binaries with Cargo `--locked`, default
features, and `panic-trace`. The workspace selects rusty_v8 with default
features disabled and `simdutf` enabled. Public evidence does not expose an
object-to-component linker map for the published rusty_v8 static library, so
the output classification is `verified-conservative-superset`, never an exact
linked set.

The conservative set contains every registry package in the pinned Cargo.lock,
every workspace package returned by Cargo metadata, the pinned Deno, rusty_v8,
and V8 source archives, every pinned rusty_v8 submodule archive, and every
license-like file found in those verified sources. Each component records its
inclusion reason.

## Fail-closed rules

Collection rejects checksum mismatches, missing or ambiguous license metadata,
license-file-less crates, NOASSERTION, mutable or unpinned Git sources, missing
required native components, case-insensitive path collisions, and target graph
inconsistency. Validation finishes before notice or source-bundle publication.
On failure, a blocker report is written without a notice ZIP.

## Deterministic outputs

Successful output uses sorted normalized paths, UTF-8 without BOM, LF line
endings, fixed ZIP timestamps, SHA-256 inventories, and component records that
include source/checksum/license/license-file hashes. Tool versions and hashes of
the pinned workflow, lock files, source archives, static library, and executable
are recorded.
