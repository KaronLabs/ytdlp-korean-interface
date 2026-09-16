# FFmpeg corresponding-source evidence

This directory closes the corresponding-source inputs for the exact BtbN
ffmpeg-n9.0.1-30-g9258bacca5-win64-lgpl-9.0.zip binary as a verified
conservative superset. It is supply-chain evidence for this FFmpeg component,
not an overall release-validation verdict.

The collector verifies and bundles the full FFmpeg and BtbN checkouts, all 122
exact BtbN source-cache archives, all 270 Rav1e crates, and 12 exact
crosstool-NG/GCC/MinGW toolchain sources including GCC 16.2.0 libgomp.

All discovered license, copying, copyright, and notice text is represented by a
deterministic content-derived LicenseRef and embedded as exact bytes. The 19
source-cache archives containing git submodule trees are explicitly marked
conservative-superset. Retained evidence includes authenticated Actions logs,
release metadata, evaluated recipes, BtbN patches, crosstool checksums, and the
authenticated GHCR cleanup failure.

The official job log prints n9.0.1-30-g9258bacca5. Its unique abbreviated commit
is tied to the full upstream commit by the retained GitHub commit metadata and
the hash-pinned full-commit FFmpeg source archive.

The collector rejects GPL/nonfree configuration, unknown enabled libraries,
mutable source URLs, SHA mismatches, missing recipe/patch/license data,
case-colliding paths or components, missing toolchain sources, and incomplete
nested-tree closure. NOASSERTION is not used.
