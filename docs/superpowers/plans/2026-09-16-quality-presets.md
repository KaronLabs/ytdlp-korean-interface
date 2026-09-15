# Quality presets implementation plan

## Authority and baseline

User-approved plan from the current conversation, 2026-09-16. Baseline origin/main: baf39d25370e05a69814357cd2d0a5cb10696910. Original checkout at src is preserved. Implement in this isolated worktree; no force push. Implementation and independent validation have separate owners.

## Required behavior

1. New users default to video, maximum 1080p, automatic audio, automatic compatible container. Choices: 1080p, 720p, best; audio mode uses existing MP3 capability. Advanced selection is separate from resolution.
2. Existing settings without the new policy migrate to advanced unchanged. Keep existing custom arguments and presets; offer an explicit return to recommended basic settings. Remembered fmt1/fmt2 are not proof of active manual selection.
3. Persist a versioned policy globally and per queue item. Existing items do not inherit subsequent global changes. Active jobs freeze settings. Missing/invalid legacy item policy restores advanced. Preserve duplicate-URL and playlist behavior.
4. Basic mode ignores external yt-dlp configuration and custom arguments. Explicit GUI path/name/cookies/proxy/tool settings still apply. Advanced retains legacy behavior. Probe and download derive from the same effective settings. Basic video must never inherit audio extraction or codec/container-first sorting.
5. yt-dlp owns ranking. Start from bv*+ba/b for video and res:1080 or res:720. Validate selected streams: min(width,height) <= cap, known dimensions for bounded modes, video and audio present. Best permits unknown dimensions with an honest label. No upscaling/reencoding or codec-driven resolution downgrade. Container is automatic.
6. Use the existing async info flow. Invalidate preview on policy/URL change; reject stale generations. Re-resolve immediately before download. Pin the returned format ID(s) for that item. Changed resolution/audio versus the displayed preview suspends the item with an explanation. No automatic fallback from unavailable IDs; ordinary network retries remain allowed.
7. First release covers individual videos and existing queue, including portrait clips. Playlist/live input routes explicitly to existing advanced behavior; never imply basic presets apply or reuse one video's ID for a whole list.
8. Display target versus selected resolution, audio presence and automatic container near download controls. Say current available formats, not original/source maximum. Show extraction warnings. Advanced categories: video+audio, video only, audio only. Reuse existing automatic-selection button.
9. Check executable FFmpeg when needed, ffprobe for final output. Deno/YouTube warnings are contextual, not a blanket dependency for all sites. Link errors to existing settings/updater. No new installer.
10. Stage UI: analyze, download, postprocess, inspect file, done. Do not infer completion from 100%. Obtain the actual final path and inspect output streams. Preserve output if verification fails; no automatic deletion or redownload. Keep existing non-basic semantics.
11. Korean and English strings and keyboard/DPI-safe layout. Do not rework unrelated GUI or queue code.

## Independent acceptance

Offline fixture must expose muxed 360p, separate 720p/1080p video and audio. Real yt-dlp and FFmpeg must produce capped video with audio. Additional cases: only 360p; only 2160p (blocked by 1080 cap); portrait; missing dimensions/audio; VP9/AV1 preserved; external -f best/-x ignored in basic; legacy migration; queue restore and settings isolation; stale response; changed selection; missing/broken FFmpeg; postprocess/probe failure; playlist/live boundary. Keep existing MP3 smoke intact. Verify UI at 100/150/200 percent and both locales where tooling permits; never claim unexecuted checks.

## Work packages

- A: Application implementation. Own C++ application sources and locale catalogs only. Do not run tests or self-verify; validation has a separate owner. Add a GUI-independent policy header with selection/result inspection so native tests can exercise real production behavior. Send its API to the controller early.
- B: Independent validation preparation. Own new tests and dedicated quality smoke tools only. Establish baseline and fixtures, then test A after its ready signal. Do not edit application sources. Record commands, return codes, failures and evidence honestly.
- C: Controller. Own plan, README/release notes and ledger. Preserve original checkout/runtime; coordinate independent reviewer, build and publish gates.

## Build and release

Reuse build-candidate.ps1 and candidate manifest. Runtime input is the existing deployed directory under E:/Util/ytdlp-korean-interface-v2.19.1-karon.1-win-x64 (2)/ytdlp-korean-interface-v2.19.1-karon.1-win-x64. Use v2.19.1-karon.2 as the next candidate tag only after confirming it is unused. Keep app baseline version semantics if required by upstream updater; display downstream release identity without enabling upstream overwrite.

Review source independently, repair blockers, make scoped commits, build a clean exact commit, validate the packaged bytes with fresh and legacy settings, preserve previous release. Record engine/runtime versions and hashes. Read remote main SHA again immediately before non-force HEAD:refs/heads/main and compare after. Publish only a reviewed and tested ZIP; if required validation is unavailable, retain candidate and report the exact remaining gate, not success.
