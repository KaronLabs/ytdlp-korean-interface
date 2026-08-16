$ErrorActionPreference = 'Stop'
$clean = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-clean-d9f12d8'
$base = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-8'
$evidence = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence'
$log = Join-Path $evidence 'build-candidate-8-20260814T000000Z.raw.log'
$status = Join-Path $evidence 'build-candidate-8-20260814T000000Z.status.json'
$build = Join-Path $clean 'tools\build-candidate.ps1'
$powershell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $build, '-Run', '-SourceRoot', $clean, '-ParentRuntime', 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface', '-CandidateBase', $base, '-DependencyArchiveDirectory', $clean)
$command = $powershell + ' ' + (($args | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
$start = [DateTime]::UtcNow.ToString('o')
$head = (git -C $clean rev-parse HEAD | Out-String).Trim()
$sourceStatus = (git -C $clean status --porcelain | Out-String).Trim()
[IO.Directory]::CreateDirectory($evidence) | Out-Null
@("START_UTC=$start", "COMMAND=$command", "SOURCE_HEAD=$head", "SOURCE_STATUS=$sourceStatus", 'CHILD_STDOUT_STDERR_BEGIN') | Set-Content -LiteralPath $log -Encoding utf8
& $powershell @args 2>&1 | Tee-Object -FilePath $log -Append
$exit = $LASTEXITCODE
$end = [DateTime]::UtcNow.ToString('o')
Add-Content -LiteralPath $log -Value @('CHILD_STDOUT_STDERR_END', "END_UTC=$end", "EXIT_CODE=$exit")
$candidate = $null
$manifestSha256 = $null
if ($exit -eq 0) {
    $candidate = Get-ChildItem -LiteralPath $base -Directory | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($null -eq $candidate) { throw 'candidate_missing_after_successful_build' }
    $manifestSha256 = (Get-FileHash -LiteralPath (Join-Path $candidate.FullName 'candidate-manifest.json') -Algorithm SHA256).Hash
}
[pscustomobject]@{
    startUtc = $start; endUtc = $end; exitCode = $exit; command = $command
    cleanSourceRoot = $clean; sourceHead = $head; sourceStatus = $sourceStatus
    candidateBase = $base; candidateRoot = if ($null -eq $candidate) { $null } else { $candidate.FullName }
    candidateManifestSha256 = $manifestSha256; rawLog = $log
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $status -Encoding utf8
if ($exit -ne 0) { exit $exit }
