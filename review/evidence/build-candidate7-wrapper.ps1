$ErrorActionPreference = 'Stop'
$clean = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-clean-7f01bff'
$base = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-7'
$log = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\build-candidate-7-20260814T000000Z.raw.log'
$status = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-evidence\build-candidate-7-20260814T000000Z.status.json'
$build = Join-Path $clean 'tools\build-candidate.ps1'
$args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$build,'-Run','-SourceRoot',$clean,'-ParentRuntime','C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface','-CandidateBase',$base,'-DependencyArchiveDirectory',$clean)
$start = [DateTime]::UtcNow.ToString('o')
$cmd = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File ' + $build + ' -Run -SourceRoot ' + $clean + ' -ParentRuntime C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface -CandidateBase ' + $base + ' -DependencyArchiveDirectory ' + $clean
$head = (git -C $clean rev-parse HEAD | Out-String).Trim()
$sourceStatus = (git -C $clean status --porcelain | Out-String).Trim()
@("START_UTC=$start", "COMMAND=$cmd", "SOURCE_HEAD=$head", "SOURCE_STATUS=$sourceStatus", 'CHILD_STDOUT_STDERR_BEGIN') | Set-Content -LiteralPath $log -Encoding utf8
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' @args 2>&1 | Tee-Object -FilePath $log -Append
$exit = $LASTEXITCODE
$end = [DateTime]::UtcNow.ToString('o')
Add-Content -LiteralPath $log -Value @('CHILD_STDOUT_STDERR_END', "END_UTC=$end", "EXIT_CODE=$exit")
[pscustomobject]@{ startUtc = $start; endUtc = $end; exitCode = $exit; command = $cmd; candidateBase = $base; log = $log } | ConvertTo-Json | Set-Content -LiteralPath $status -Encoding utf8
if ($exit -ne 0) { exit $exit }
