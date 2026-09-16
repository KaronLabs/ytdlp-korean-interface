# Deno 2.7.14 notice collection

This directory pins the inputs and policy for the Deno runtime shipped with
`v2.19.1-karon.2`. The collector emits a verified conservative superset because
the official rusty_v8 prebuilt library has no public object-to-native-component
link map.

Run `tools/collect-deno-third-party-notices.ps1 -Run` with all source, metadata,
vendor, executable, native archive, and scratch parameters. The source archives
must match `inputs.json`; native archives must match `native-components.json`.

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

Any missing crate license file, checksum mismatch, mutable source, native
omission, path collision, or graph mismatch produces
`deno-collection-blockers.json` and no notice/source bundle. This task does not
modify the release-wide corresponding-source lock and does not establish an
overall release PASS.
