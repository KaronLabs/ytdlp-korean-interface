# Korean i18n Source Recovery Design

## Context

The existing `ytdlp-interface` directory is a Windows x64 deployment assembled from ytdlp-interface v2.19.1 and contains a customized Korean executable, a 524-entry `locales/ko-KR.json` catalog, yt-dlp, FFmpeg, FFprobe, Deno, and settings. It contains no recoverable source history.

This repository is an isolated clone of upstream tag `v2.19.1` at commit `2173316ebb5e50af49a2a4e939693fa8c3a3459c`. The deployed executable is evidence of desired behavior, not a source artifact that can be reproduced byte-for-byte.

## Goals

1. Reconstruct the observable Korean localization behavior as maintainable C++ source.
2. Keep English strings as a compiled fallback and load Korean strings from `locales/ko-KR.json`.
3. Prevent translated presentation text from changing internal state or control flow.
4. Establish automated coverage before modifying localization behavior.
5. Update the deployed yt-dlp nightly safely with provenance, verification, backup, and rollback.
6. Replace stale download paths with the current Windows user's Known Folder Downloads path.
7. Verify the Windows GUI, metadata lookup, download, MP3 extraction, and FFmpeg output end to end using locally generated media served from localhost.

## Non-goals

- Byte-for-byte reproduction of the existing Korean executable.
- Refactoring unrelated upstream code.
- Adding languages other than `en-US` and `ko-KR`.
- Replacing Nana, bit7z, libpng, libjpeg-turbo, nlohmann/json, or the upstream updater architecture.
- Running smoke tests against YouTube or another external media service.
- Automatically deleting failed smoke-test evidence.
- Changing the user's cookie, proxy, SponsorBlock, format, or download-concurrency preferences.

## Repository and Artifact Boundaries

- The parent deployment directory remains a preserved runtime baseline.
- This `src` directory is the only Git repository and the only location for source changes.
- Upstream source remains under `ytdlp-interface/` as provided by v2.19.1.
- Dependency source trees are extracted beside `ytdlp-interface/` so existing Visual Studio relative paths remain valid.
- Build and smoke-test outputs never overwrite the preserved deployment until all automated and Windows tests pass.
- Runtime replacement operations create a versioned backup and provenance manifest first.

## Selected Approach

Introduce a small localization component with these source-level interfaces:

```cpp
namespace i18n
{
    struct load_result
    {
        bool catalog_loaded;
        std::vector<std::string> diagnostics;
    };

    load_result load_catalog(const std::filesystem::path& catalog_path);
    std::string tr(std::string_view key, std::string_view english_fallback);
    std::string active_locale();
    void reset_for_tests();
}
```

`tr(key, english_fallback)` is the only UI translation lookup surface. English remains at each call site, which makes fallback explicit and lets code review verify meaning without opening a second file.

The component owns catalog parsing and validation but does not own GUI widgets, settings persistence, downloads, or update operations.

## Localization Catalog Contract

The catalog has this root shape:

```json
{
  "locale": "ko-KR",
  "schemaVersion": 1,
  "strings": {
    "main.start_download": "다운로드 시작"
  }
}
```

The complete catalog is rejected and English is used when:

- the file cannot be opened;
- the JSON is malformed;
- the root is not an object;
- `locale` is not `ko-KR`;
- `schemaVersion` is not integer `1`;
- `strings` is not an object.

An individual entry is rejected and its English call-site fallback is used when:

- the value is not a string;
- the value is empty;
- the string is invalid UTF-8;
- its placeholder multiset differs from the English fallback;
- Nana markup is malformed or unbalanced.

Placeholders are named tokens such as `{title}`, `{url}`, and `{item_number}`. Repeated placeholders retain multiplicity, so `{x} {x}` does not match `{x}`.

Supported Nana markup validation covers the syntax already present in the recovered catalog, including opening tags with attributes, closing tags, and the shorthand closing tag `</>`. Validation does not interpret visual style; it only prevents malformed translated markup from reaching Nana.

Diagnostics are written to `localization.log` beside the active settings file. Diagnostics contain the locale key and reason but never media URLs, cookies, proxy credentials, browser profiles, or download paths.

## Startup and Settings Flow

1. Resolve the settings path using existing upstream behavior.
2. Load settings without changing unrelated values.
3. Read `language`; accept `en-US` and `ko-KR`, otherwise select `en-US` and log the reason.
4. For `ko-KR`, load `<application-directory>/locales/ko-KR.json` before constructing GUI widgets.
5. If loading fails, continue in English rather than preventing startup.
6. A language change is persisted and takes effect on the next process start, matching the current executable's observable restart-required behavior.

The default for a fresh configuration remains English. The recovered deployment configuration continues using `ko-KR`.

## Presentation and Internal-State Separation

Before translating a call site, any string used as both visible text and a control token is split. At minimum, coverage must protect these upstream couplings:

- queue completion state currently compared with `"done"`;
- view switching currently inferred from a caption containing `"queue"`;
- format classification currently compared with `"Audio only"` and `"Video only"`.

Internal values become enums, booleans, or stable nonlocalized constants. Only widget captions and user-facing messages use `i18n::tr`.

The migration is surgical: no unrelated widgets, queue data structures, process management, or downloader argument logic are redesigned.

## Translation Migration Perimeter

The 524 recovered keys are the baseline. Migration covers the user-visible strings in:

- `main.cpp`;
- `gui.cpp`, `gui_make.cpp`, `gui_bottom.cpp`, and `gui_bottoms.cpp`;
- `queue.cpp` and `outbox.cpp`;
- `msgbox.hpp` and message-box construction sites;
- all existing files under `ytdlp-interface/forms/`;
- Windows version-resource description text in `ytdlp-interface.rc`.

Every catalog key must be referenced by source or explicitly classified as runtime-only metadata. Every migrated call site must have a nonempty English fallback.

## Test Coverage Perimeter

### Tier 1: Native deterministic tests

A non-GUI native test target exercises real localization code without creating a window. Red-Green-Refactor is mandatory for each behavior.

Required tests:

- valid Korean catalog loads;
- missing file falls back to English;
- malformed JSON rejects the catalog;
- wrong locale, schema version, or strings type rejects the catalog;
- missing key returns its English fallback;
- non-string and empty entries fall back individually;
- placeholder equality accepts reordered identical multisets;
- placeholder loss, addition, or multiplicity mismatch rejects the entry;
- balanced Nana markup is accepted;
- malformed, mismatched, and unclosed markup is rejected;
- invalid UTF-8 is rejected;
- diagnostics identify the key and reason without leaking sensitive settings;
- loading or resetting the catalog does not retain stale entries;
- internal queue/view/format decisions are unchanged when Korean labels differ from English.

### Tier 2: Repository contract tests

Deterministic scripts validate:

- `ko-KR.json` parses as JSON;
- exactly 524 recovered baseline keys exist during the initial recovery;
- there are no empty values;
- source references and catalog keys have no unexplained missing or extra entries;
- placeholder and markup invariants hold across all call sites;
- all runtime executables and smoke-test output paths remain outside tracked source.

The exact 524-key assertion is a recovery baseline, not a permanent ceiling. A later upstream feature may increase the count in the same commit that adds its English call site and Korean translation.

### Tier 3: Build verification

Build the v2.19.1 solution as Release x64 with the upstream v143 toolset and required static dependencies. A successful build must produce a Windows GUI executable whose product version remains `2.19.1.0`. Debug or x86 builds are optional unless a changed project setting affects them.

### Tier 4: Windows GUI smoke test

The smoke test runs only after deterministic tests and the Release x64 build pass. It uses a temporary copy of the runtime bundle and never the preserved baseline in place.

It verifies:

- Korean main window starts without a localization error;
- Settings, format selection, playlist/subtitle/sections dialogs, queue view, output view, and message boxes render translated labels;
- switching views and selecting audio/video formats still follows internal state rather than translated captions;
- 100%, 150%, and 200% DPI visual inspection detects clipping in changed layouts;
- closing the GUI saves valid JSON.

### Tier 5: Localhost end-to-end media smoke

1. Generate a two-second synthetic MP4 with the bundled FFmpeg using a test tone and a generated color frame.
2. Serve it from `127.0.0.1` with a temporary local HTTP server.
3. Use a unique smoke root beneath the current user's Downloads Known Folder.
4. Add the localhost URL through the GUI and wait for metadata resolution.
5. Download with MP3 conversion enabled.
6. Read the final path and verify it is contained by the smoke root.
7. Use FFprobe JSON to assert at least one audio stream, codec `mp3`, duration greater than zero, and a nonempty final file.
8. Assert no `.part` or temporary media remains.

Successful runs remove only their unique smoke root. Failed runs preserve their isolated artifacts and sanitized logs for diagnosis.

## yt-dlp Update Design

The selected channel remains `nightly`. Update work is separate from the i18n implementation and follows this transaction:

1. Ensure the GUI and its yt-dlp child processes are stopped.
2. Query the official `yt-dlp/yt-dlp-nightly-builds` latest release.
3. Download `yt-dlp.exe` and the official SHA-256 sums into a unique staging directory.
4. Verify the asset hash against the official sums before touching the deployment.
5. Run staged `yt-dlp.exe --version` and require the reported version to equal the selected release tag.
6. Copy the existing executable to a versioned backup.
7. Replace the executable using a same-volume atomic rename where Windows permits it.
8. Re-run `--version` from the deployed location.
9. Write a provenance manifest containing channel, tag, asset name, SHA-256, source repository, installation time, previous version, and backup path.
10. On any post-replacement failure, restore the backup and verify its version.

At least the last verified backup remains until the complete Windows smoke test passes. Update scripts do not accept arbitrary repository URLs.

## Download Path Repair

The current user's Downloads directory is resolved with `SHGetKnownFolderPath(FOLDERID_Downloads)`, not by concatenating `%USERPROFILE%`.

Path repair modifies only:

- the active `outpath`;
- `outpaths`, removing stale `C:\Users\Administrator\...` and nonexistent `D:\...` entries and adding the resolved current Downloads path;
- each saved preset's corresponding `outpath` and `outpaths` values when they equal one of those known stale paths.

All other settings and preset fields are preserved byte-for-byte where JSON serialization permits. The original settings file is copied to a timestamped backup before replacement. The repaired JSON is written to a sibling temporary file, parsed again, then atomically renamed.

## Error Handling and Rollback

- Localization errors degrade to English and never abort startup.
- Build failures leave the deployment untouched.
- Settings repair failures leave the original settings file and backup intact.
- Update failures before replacement remove only staging artifacts.
- Update failures after replacement restore and verify the previous binary.
- GUI or media smoke failures keep the candidate runtime, smoke root, version inventory, sanitized commands, and logs separate from the preserved baseline.
- No rollback operation deletes an unverified file unless a verified replacement or backup exists.

## Implementation Sequence

1. Establish native and repository-level test targets.
2. TDD the localization parser, validation, fallback, and diagnostics.
3. TDD the internal-token separation regressions.
4. Migrate UI strings in bounded groups, running the full deterministic suite after each group.
5. Add the recovered catalog and key-coverage test.
6. Build Release x64 and fix only localization-related compiler or linker failures.
7. Implement and test settings repair as a transaction.
8. Implement and test the verified yt-dlp update transaction.
9. Assemble a candidate runtime copy.
10. Run Windows GUI and localhost end-to-end smoke tests.
11. Promote the candidate only after all gates pass and retain rollback artifacts until user acceptance.

## Acceptance Criteria

- The independent Git repository retains upstream v2.19.1 ancestry and the recovery work is on a feature branch.
- Deterministic tests demonstrate Red-Green-Refactor evidence for every new localization behavior.
- All deterministic tests pass with no warnings attributable to the recovery.
- The recovered catalog has 524 baseline keys, no empty values, no unexplained key drift, and valid placeholders and markup.
- Release x64 builds with product version `2.19.1.0`.
- The Korean UI starts and all migrated screens fall back safely to English when the catalog is absent or invalid.
- Translation changes cannot alter queue state, view switching, or format classification.
- yt-dlp is installed from the official nightly channel with verified SHA-256, provenance, backup, and tested rollback.
- Active and preset download paths use the current user's Downloads Known Folder and preserve unrelated settings.
- The localhost smoke test completes metadata lookup, download, MP3 extraction, and FFprobe validation inside its isolated run root.
- The preserved deployment can be restored without source rebuild or network access.
