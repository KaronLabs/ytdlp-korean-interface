$ErrorActionPreference = 'Stop'
$candidate = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-7\candidate-40b53764d6d244858b9e5b4ead6dbad1'
$yt = Join-Path $candidate 'yt-dlp.exe'
$python = 'C:\Users\ceo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$hls = 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\review\evidence\hls-subtitle-fixture-candidate7.py'
$out = 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\review\evidence\candidate7-fixture-probe-output.json'
$start = [DateTime]::UtcNow.ToString('o')
$playlistCommand = "$yt --no-warnings -J http://127.0.0.1:60321/feed.rss"
$playlist = & $yt '--no-warnings' '-J' 'http://127.0.0.1:60321/feed.rss' 2>&1
$playlistExit = $LASTEXITCODE
$hlsCommand = "$python $hls $yt"
$hls = & $python $hls $yt 2>&1
$hlsExit = $LASTEXITCODE
$end = [DateTime]::UtcNow.ToString('o')
[ordered]@{
    schemaVersion = 1
    startedAtUtc = $start
    endedAtUtc = $end
    candidateRoot = $candidate
    candidateYtDlp = $yt
    playlist = [ordered]@{ command = $playlistCommand; exitCode = $playlistExit; output = (@($playlist) -join "`n") }
    hlsSubtitle = [ordered]@{ command = $hlsCommand; exitCode = $hlsExit; output = (@($hls) -join "`n") }
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $out -Encoding UTF8
Get-Content -LiteralPath $out -Raw
if ($playlistExit -ne 0 -or $hlsExit -ne 0) { exit 1 }
