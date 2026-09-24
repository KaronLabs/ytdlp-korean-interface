# v2.19.1-karon.2 GUI release evidence contract

This directory defines the manual evidence contract for the sealed Windows x64 candidate. It does not claim that the GUI matrix has been run or that the release passed.

The [manual GUI evidence guide](MANUAL-GUI-EVIDENCE-GUIDE.md) gives the operator case-by-case steps. Its `C:\Users\ceo` screenshot paths are examples; replace them with the current Windows account's path before running the commands.

## Fixed matrix

Exactly these six case IDs are accepted:

| Case ID | Language | DPI |
|---|---|---:|
| `ko-KR-100` | `ko-KR` | 100 |
| `ko-KR-150` | `ko-KR` | 150 |
| `ko-KR-200` | `ko-KR` | 200 |
| `en-US-100` | `en-US` | 100 |
| `en-US-150` | `en-US` | 150 |
| `en-US-200` | `en-US` | 200 |

Every case must bind to one identical `ytdlp-interface.exe` SHA-256. The verifier also resolves `ffprobe.exe` from that executable's directory and records its SHA-256 and length. When `candidate-manifest.json` is supplied, both binaries must match the manifest entries exactly.

## Required observations

Each case records actual observed booleans for:

- launch
- download type
- 1080p preset
- 720p preset
- best-quality preset
- expected resolution
- queue registration
- progress
- completion
- advanced-settings navigation
- no clipping

The recorder initializes every observation to `null`; it never presets PASS. It does not change Windows display scaling or application language. The operator must perform those changes explicitly before each run and record the values actually observed.

`ko-KR-100` and `en-US-200` require a completed video lifecycle. The lifecycle references only the downloaded media file plus the expected width and height. Operator-authored ffprobe JSON is prohibited. The verifier executes the sealed candidate's own `ffprobe.exe`, requires both video and audio streams, compares the probed dimensions, and writes canonical probe JSON into its controlled output directory.

Representative coverage across the six cases must also include:

- MP3 conversion with a valid MP3 artifact
- settings save and restart restore
- legacy-settings transition

The verifier probes every referenced MP3 with the sealed candidate's `ffprobe.exe`; a filename or operator assertion is not sufficient.

## Evidence files

Screenshots must be fully decodable PNG files at least 640x480. Their recorded SHA-256, byte length, width, height, and capture timestamp must match the actual file. Truncated images, header-only images, and 1x1 placeholders are rejected.

PNG processing is fail-closed. The only permitted ancillary chunks are `cHRM`, `gAMA`, `sBIT`, `sRGB`, `pHYs`, and `tRNS`. Text or metadata-bearing `tEXt`, `zTXt`, `iTXt`, and `eXIf` chunks and every other unlisted ancillary chunk are rejected. `IHDR` must be first, `PLTE` must precede `IDAT`, all `IDAT` chunks must be contiguous, and one terminal `IEND` must be the final byte sequence.

Decode-time resource limits are 32 MiB encoded bytes, 8192 pixels on either axis, 8,388,608 total pixels, and 16 MiB cumulative `IDAT` data. These limits are checked with overflow-safe arithmetic before full image decoding.

All referenced evidence files must be direct descendants of the evidence directory and form its exact file allowlist. Every relative path and component must already be Unicode Normalization Form C. Uniqueness and containment keys use NFC plus ordinal case-insensitive comparison. Any extra file, including an unknown binary, causes rejection. Candidate and evidence paths are rejected when any path component is a reparse point or junction.

Candidate, evidence, manifest, and output paths must be local filesystem paths. UNC, device, and extended UNC paths are rejected; remote evidence cannot satisfy the immutable local snapshot contract.

The verifier snapshots the candidate executable, candidate ffprobe, optional candidate manifest, and complete evidence tree into a process-private local directory. Validation, hashing, ffprobe execution, and output generation use only those snapshot bytes. Immediately before atomic publication, the original candidate files and complete evidence tree are re-enumerated and re-hashed. A new, removed, renamed, resized, or changed file aborts publication.

Decoded JSON strings are recursively checked for cookies, tokens, authorization values, signed URLs, and query-bearing URLs. Evidence must not contain secrets or expiring media URLs.

## Operator workflow

Initialize one case from the null template:

```powershell
./tools/record-gui-release-evidence.ps1 `
  -Action Initialize `
  -EvidenceRoot <evidence-directory> `
  -CandidateExePath <sealed-candidate>/ytdlp-interface.exe `
  -Language ko-KR `
  -DpiPercent 100
```

After explicitly selecting the required language and DPI, record each observed result and attach screenshots with the recorder's matching actions. Attach a required video lifecycle without supplying probe JSON:

```powershell
./tools/record-gui-release-evidence.ps1 `
  -Action AttachVideoLifecycle `
  -CasePath <evidence-directory>/cases/ko-KR-100.json `
  -EvidenceFilePath <downloaded-video> `
  -ExpectedWidth 1920 `
  -ExpectedHeight 1080 `
  -Result true
```

Run the verifier only after all six case files and their referenced evidence are complete:

```powershell
./tools/verify-gui-release-evidence.ps1 `
  -EvidenceRoot <evidence-directory> `
  -CandidateExePath <sealed-candidate>/ytdlp-interface.exe `
  -CandidateManifestPath <sealed-candidate>/candidate-manifest.json `
  -OutputDirectory <empty-parent>/gui-contract-output
```

## Verifier output contract for packaging

Output is created only after all six cases pass. The verifier writes to a unique partial directory and performs a no-overwrite atomic directory move. If another producer wins the race, its final directory is preserved and the loser removes only its own partial directory.

The [GUI validation output schema](gui-validation-output.schema.json) is the canonical machine-readable contract for both `gui-validation-summary.json` and `gui-validation-evidence-manifest.json`. It fixes numeric `schemaVersion` to `2`, `releaseVersion` to `v2.19.1-karon.2`, rejects additional properties, and defines the exact nested candidate, six cases, full-video lifecycle cases, representative checks, generated probes, and evidence-file records. The verifier validates both generated JSON documents against this tracked schema before publication. This README intentionally does not duplicate the field grammar.

The packaging gate must consume both files, require `status == "PASS"`, require the exact six cases, require byte-for-byte-equivalent candidate objects, and bind `candidate.executable` and `candidate.ffprobe` to the packaged files. If `candidate.manifest` is non-null, the packaging gate must also bind its hash and length and verify that its file table contains matching root entries for both binaries. Packaging integration is intentionally outside this change.

The verifier-generated probe files are outputs, not operator evidence. No other evidence-root exclusions exist.
