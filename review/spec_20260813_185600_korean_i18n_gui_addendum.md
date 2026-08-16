# Korean i18n GUI evidence addendum (append-only)

## Meta

- `created_at_utc`: `2026-08-13T18:55:42Z`
- `review_target`: candidate execution copy derived from source commit `366dc65539bec11edf8159d05b470e0beeddee6b`
- `candidate_manifest_sha256`: `78E1AF2D6FBB5BC2300A7C0FE307A28AA6CA4A04160A8D8ECEAABF371205474D`
- `reviewer_required`: `different_session_or_model`
- `status`: `partial_success`
- `disposition`: additional GUI observations are recorded; NOT GUILTY is not claimed because DPI tiers, playlist/subtitle metadata flows, and an independent final verdict remain open.

## Computer Use evidence

The following observations were made against the returned candidate window, not a guessed handle. Each event includes UTC time, candidate binding, window identity, pre/post screenshot paths, and visible result in the external JSONL ledger:

- ledger: `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\gui-run-20260814T20260813T184753Z-missing-gates\gui-observation-addendum.jsonl`
- ledger SHA-256 at capture: `C5C77E58E7362A0E81EFF430B84E755D3FBEEE28ECAECD43939005922C7F7D34`
- `queue_context_menu_observed` at `2026-08-13T18:55:05.469Z`: right-click on queue row #2 showed Korean context-menu entries including `구간 다운로드` and `자막 선택(0/0)`. Playlist/subtitle metadata was empty in this local direct-media row; no playlist dialog was fabricated.
- `sections_dialog_observed` at `2026-08-13T18:55:05.471Z`: selecting `구간 다운로드` opened the Korean media-sections dialog. Screenshot SHA-256: `EFA75F2D729847BEE0D6AE720ABB1BB3961460AD2F38957A14F41821F8A9B7C7`.
- `localized_validation_message_observed` at `2026-08-13T18:55:05.472Z`: entering `start=1,end=1` and selecting `목록에 추가` opened the Korean `입력 오류` dialog with `시작과 종료 시점이 같습니다`. Screenshot SHA-256: `93E18247B7FBEB3CFD8193525EE2D6977C0B067B62BD84DADA418A82643B4E07`.

The screenshots contain a Codex desktop toast over part of the application. This is recorded as `externalOverlayPresent=true`; the captures are admissible as observations of the visible controls but are not claimed to be unobstructed visual proof.

## DPI boundary

The retained raw observation log `C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\dpi-observed-20260813T183000Z.log` (SHA-256 `9E5DDBB9229EC3C42C94EAE275A6404FA349E2FA50094F06AA0F695AED4EC880`) reports `PixelsPerXLogicalInch=120` and `PixelsPerYLogicalInch=120` for both monitors. Per Microsoft's DPI table, 120 logical DPI is 125%; it is not the 100% tier. No automatic display-scaling action was taken. The required 100% (96), 150% (144), and 200% (192) observations remain pending user-manual Windows Display Scale changes.

## Remaining mandatory slots

1. Obtain fresh Computer Use observations for playlist and subtitle dialogs using metadata that actually contains playlist entries/subtitles; disabled menu items must be recorded as disabled rather than inferred as supported.
2. Preserve `preObservation`, `postObservation`, and `visibleResult` for every candidate-bound GUI event in the final ledger, not only this addendum.
3. After the user manually sets Windows Display Scale to 100%, 150%, and 200% in turn, observe the same candidate and record each fresh screenshot plus measured DPI.
4. Run a new different-session/model review over the complete append-only package and bind its verdict to the same candidate SHA.

## Provisional order

The sections and localized validation-message paths are now directly observed and hash-bound. They do not cure the unobserved playlist/subtitle metadata paths, missing DPI tiers, or pending independent verdict; therefore the submission remains `partial_success`.
