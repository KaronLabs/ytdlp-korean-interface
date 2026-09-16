# FFmpeg corresponding-source status

This directory records supply-chain evidence for the FFmpeg runtime used by
`v2.19.1-karon.2`. It is not an overall release or license PASS.

The binary archive and both shipped executables match the reviewed SHA-256
values. The observed build is static LGPL with `--enable-version3`; neither
`--enable-gpl` nor `--enable-nonfree` is present.

The producing workflow is BtbN/FFmpeg-Builds run `34967781095` at builder
commit `3e6685eda92f9288c15ac320139622dcedca09a4`. The exact source download-cache
artifact is `10396032837`. Its artifact digest is
`sha256:89219a2bad8686b27a2b10907c290fe1ec87088e86869a0c6433d96c6a5832c8`;
the downloaded inner `cache.tar.gz` is 2,166,213,260 bytes with SHA-256
`F5859AA90C962360FAA4593BFED1618D94C1190CEF720303D996693EEBA7B189`.
It contains 122 canonical source archives.

Closure remains fail-closed. The cache archives have not yet been mapped to
the complete enabled direct and transitive static link set with independently
audited license expressions, license text paths, local patches, and inline
recipe transforms. The release has no source asset, the Actions source-cache
artifact requires authenticated access and expires on 2026-09-29, and the
public job-log endpoint returned HTTP 403 for job `104378764705`.

Accordingly, the collector validates and records the official binary evidence
and caches the two independently closed source inputs (FFmpeg and the complete
BtbN scripts), then exits with `ffmpeg_source_closure_incomplete`. It does not
create a corresponding-source bundle until the manifest is complete.
