# Deno 2.7.14 notice collection

This directory pins the inputs and policy for the Deno runtime shipped with
`v2.19.1-karon.2`. The collector emits a verified conservative superset because
the official rusty_v8 prebuilt library has no public object-to-native-component
link map.

Run `tools/collect-deno-third-party-notices.ps1 -Run` with all source, metadata,
vendor, crates.io archive, executable, SPDX, upstream fallback, native archive,
the local Git object repository containing the pinned rusty_v8 commit, and
scratch parameters. Source archives must match `inputs.json`; native archives
must match `native-components.json`; exceptional upstream license sources must
match `upstream-license-fallbacks.json`.

The official profile metadata command is:

```powershell
cargo metadata --locked --features=panic-trace --filter-platform x86_64-pc-windows-msvc --format-version 1
```

The conservative metadata command is:

```powershell
cargo metadata --locked --all-features --filter-platform x86_64-pc-windows-msvc --format-version 1
```

The source vendor command is:

```powershell
cargo vendor --locked --versioned-dirs
```

Each registry package preserves its exact `.crate` archive and Cargo checksum.
The collector reads `Cargo.toml.orig`, license, notice, and copyright bytes
directly from that checksum-pinned archive. The vendor tree and its generated
`.cargo-checksum.json` are only compared with the trusted archive member map.
When package files are absent, fully valid SPDX expressions resolve to canonical
text from pinned SPDX License List Data v3.28.0. Invalid or custom expressions
require an exact version-tied upstream commit license fallback.

SPDX v3.28.0 records annotated tag object
`779ef2e5dff6d4af389c53de5e97116ab0bb52e8` separately from peeled commit
`c4a7237ec8f4654e867546f9f409749300f1bf4c`. Native completeness is an exact
path and commit comparison against all 20 gitlinks in rusty_v8 tree
`6c92c73eeacce6956b194cdaba8cfb020f11a960`.

The embedded TypeScript 5.9.2 compiler source is bound to the exact Deno commit,
source length and SHA-256. Pinned `cli/build.rs` and `cli/tsc/mod.rs` establish
compression and runtime inclusion, and the notice contains Microsoft's literal
copyright plus the complete pinned Apache-2.0 text.

The historical `fxhash@0.2.1` declaration `Apache-2.0/MIT` is preserved
verbatim as a content-addressed SPDX 2.3 `LicenseRef`. Its extracted text binds
the exact crate and manifest hashes and includes the complete pinned canonical
Apache-2.0 and MIT texts without interpreting the slash as `OR` or `AND`.

Any unresolved expression, checksum mismatch, mutable source, native omission,
path collision, or graph mismatch produces `deno-collection-blockers.json` and
no notice/source bundle. Every input/output ancestor rejects Windows reparse
points. Output is built in a process-owned same-volume directory and finalized
with an atomic no-overwrite directory move. This task does not modify the release-wide
corresponding-source lock and does not establish an overall release PASS.
