$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $RepositoryRoot 'tools\release-factory.ps1')
. (Join-Path $RepositoryRoot 'tools\release-orchestrator.ps1')
$script:Failures = 0
$script:Tests = 0

function Assert-True { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw $Message } }
function Assert-Equal { param($Expected,$Actual,[string]$Message='values differ') if ($Expected -cne $Actual) { throw "$Message expected='$Expected' actual='$Actual'" } }
function Invoke-Test { param([string]$Name,[scriptblock]$Body) $script:Tests++; try { & $Body; Write-Host "PASS: $Name" } catch { $script:Failures++; Write-Host "FAIL: $Name"; Write-Host $_ } }
function New-TempDirectory { $p=Join-Path ([IO.Path]::GetTempPath()) ('karon-upstream-layout-'+[Guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Force -Path $p|Out-Null; $p }

function New-ObservedUpstreamRuntime {
    param([Parameter(Mandatory=$true)][string]$Root)
    foreach ($name in @('ytdlp-interface.exe','yt-dlp.exe','ffmpeg.exe','ffprobe.exe','deno.exe','7z.dll')) {
        [IO.File]::WriteAllText((Join-Path $Root $name), "fixture-$name", [Text.UTF8Encoding]::new($false))
    }
}

Invoke-Test 'observed ErrorFlynn v2.19.1 x64 layout is accepted without settings file' {
    $root=New-TempDirectory
    try {
        New-ObservedUpstreamRuntime -Root $root
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'ytdlp-interface.json'))) 'fixture unexpectedly contains settings'
        $resolved=Resolve-UpstreamRuntimeRoot -ExtractedRoot $root
        Assert-Equal ([IO.Path]::GetFullPath($root)) ([IO.Path]::GetFullPath($resolved)) 'flat upstream runtime root was not resolved'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

Invoke-Test 'release bootstrap creates deterministic portable Korean settings when upstream omits them' {
    $root=New-TempDirectory
    try {
        New-ObservedUpstreamRuntime -Root $root
        $settingsPath=Initialize-ReleaseParentSettings -ParentRuntime $root
        Assert-Equal (Join-Path ([IO.Path]::GetFullPath($root)) 'ytdlp-interface.json') ([IO.Path]::GetFullPath($settingsPath))
        $settings=Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $names=@($settings.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
        $expected=@('fmt1','fmt2','language','outpath','ratelim','ratelim_unit','unfinished_queue_items','unfinished_queue_states','ytdlp_path') | Sort-Object
        Assert-Equal $expected.Count $names.Count 'unexpected release settings field count'
        for($i=0;$i -lt $expected.Count;$i++){ Assert-Equal $expected[$i] $names[$i] 'unexpected release settings field' }
        Assert-Equal 'ko-KR' ([string]$settings.language)
        Assert-Equal '.\yt-dlp.exe' ([string]$settings.ytdlp_path)
        Assert-Equal '.' ([string]$settings.outpath)
        Assert-Equal '' ([string]$settings.fmt1)
        Assert-Equal '' ([string]$settings.fmt2)
        Assert-Equal 0 ([int]$settings.ratelim)
        Assert-Equal 1 ([int]$settings.ratelim_unit)
        Assert-True (@($settings.unfinished_queue_items).Count -eq 0) 'queue items must start empty'
        Assert-True (@($settings.unfinished_queue_states).Count -eq 0) 'queue states must start empty'
        Assert-True (-not ([string]$settings.outpath -match '^[A-Za-z]:\\')) 'release settings must not contain machine-specific absolute output path'
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($script:Failures -gt 0) { throw "$($script:Failures) of $($script:Tests) upstream layout tests failed." }
Write-Host "All $($script:Tests) upstream layout tests passed."
exit 0
