# FFmpeg corresponding-source evidence

This directory records supply-chain evidence for the exact BtbN asset
ffmpeg-n9.0.1-30-g9258bacca5-win64-lgpl-9.0.zip. It is not an overall release
validation or license-compliance PASS.

## Exact binary and builder

- Release tag: autobuild-2026-09-15-13-18
- Archive SHA-256: 39697D69681A09BD55A0F0224360A9A4285BC12127DF807D7242592B0E144A7B
- ffmpeg.exe SHA-256: 41482EABC1A33F9D1E4334CA32EC9259AA34A3EC2493FCC9F214BFE54301CE38
- ffprobe.exe SHA-256: 376F55EB141C3B0D8790B64967B8CBF1737D76BEBE0820189356C71CC884B395
- FFmpeg source input: 9258bacca50d7ca28bcb6d797e8952123e35105b
- BtbN scripts: 3e6685eda92f9288c15ac320139622dcedca09a4
- Actions run: 34967781095
- Target-image job: 104378764705
- Binary-build job: 104384912273

Authenticated full logs are retained under evidence/. Their SHA-256 values are
FFB2BEC78A50C9DD9203F6EBD4C8EF916B9D8D8A9321E935811652C7F96339BC and
CAA811263C2165348FA337DC6377C4BDFEC61AC7E7D9838EDAF391EB539F5348.
The initial GitHub CLI calls were rejected by the CLI escape-sequence guard.
The exact stderr is retained; successful calls used the
--allow-escape-sequences option.

## Retained graph

The official target-image log references 85 of the 122 canonical source-cache
archives. component-graph.json records their archive SHA-256, upstream
revision, exact recipe SHA-256, evaluated dependencies and configure output,
patches, inline transforms, and license-text members. Rav1e's Cargo.lock adds
270 checksum-verified crates.io source archives in rav1e-crates.json.
The collector verifies 358 source records: three direct source sets, 85 BtbN
cache archives, and 270 Rav1e crates.

The actual configuration contains --enable-version3 and static pkg-config
flags, and contains neither --enable-gpl nor --enable-nonfree.

## Fail-closed result

Closure remains incomplete. No deterministic component source bundle was
created.

The target image is pinned to
ghcr.io/btbn/ffmpeg-builds/base-win64@sha256:f0d05267fd9d4538c73926ebf50e7edfe962c361f487c6c8302469d6616963be,
but the retained cache does not provide the exact source-package set for its
GCC/libgomp and other toolchain binaries. The FFmpeg link input includes
-lgomp, so this gap cannot be ignored.

Nineteen stage archives contain git submodules or nested source trees. Their
bytes and discovered license files are retained, but an exact per-linked
subcomponent commit, applicability, and license-expression graph is not yet
complete for every nested tree.

The binary-build log records the release/9.0 clone and packaged name
n9.0.1-30-g9258bacca5, but does not print the checkout as a full 40-character
git rev-parse.

The collector validates all available non-blocked evidence before returning
ffmpeg_source_closure_incomplete. It must not emit a bundle until every
manifest.json unresolved item is closed.
