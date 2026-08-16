[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$factoryPath = Join-Path $PSScriptRoot 'release-factory.ps1'
if (-not (Test-Path -LiteralPath $factoryPath -PathType Leaf)) { throw 'release_factory_missing' }
. $factoryPath

function Get-UpstreamReleaseAssetUrl {
    $config = Get-FirstReleaseConfiguration
    return 'https://github.com/' + $config.UpstreamRepository + '/releases/download/' + $config.UpstreamTag + '/' + $config.UpstreamAssetName
}

function Get-TrustedReleaseSevenZip {
    $candidates = @(
        (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
        $(if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) { Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe' })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and (Test-Path -LiteralPath $_ -PathType Leaf) }
    $sevenZip = $candidates | Select-Object -First 1
    if ($null -eq $sevenZip) { throw 'release_sevenzip_missing' }
    return [IO.Path]::GetFullPath($sevenZip)
}

function Invoke-ReleaseNative {
    param(
        [Parameter(Mandatory = $true)] [string] $FilePath,
        [Parameter(Mandatory = $true)] [string[]] $Arguments,
        [Parameter(Mandatory = $true)] [string] $FailureCode,
        [string] $WorkingDirectory
    )
    $old = Get-Location
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) { Set-Location -LiteralPath $WorkingDirectory }
        $output = @(& $FilePath @Arguments 2>&1)
        if ($LASTEXITCODE -ne 0) { throw ($FailureCode + ': ' + (($output | Out-String).Trim())) }
        return $output
    }
    finally { Set-Location -LiteralPath $old }
}

function Test-ReleasePathContained {
    param([Parameter(Mandatory = $true)] [string] $Root, [Parameter(Mandatory = $true)] [string] $Path)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $pathFull = [IO.Path]::GetFullPath($Path)
    return $pathFull.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Initialize-ReleaseParentSettings {
    param([Parameter(Mandatory = $true)] [string] $ParentRuntime)
    if (-not (Test-Path -LiteralPath $ParentRuntime -PathType Container)) { throw 'release_parent_runtime_missing' }
    $parent = [IO.Path]::GetFullPath($ParentRuntime)
    if (-not (Test-UpstreamRuntimeComplete -RuntimeRoot $parent)) { throw 'release_parent_runtime_incomplete' }
    $settingsPath = Join-Path $parent 'ytdlp-interface.json'
    if (Test-Path -LiteralPath $settingsPath) { throw 'release_parent_settings_unexpected' }

    $settings = [ordered]@{
        language = 'ko-KR'
        ytdlp_path = '.\yt-dlp.exe'
        outpath = '.'
        fmt1 = ''
        fmt2 = ''
        ratelim = 0
        ratelim_unit = 1
        unfinished_queue_items = @()
        unfinished_queue_states = @()
    }
    $json = $settings | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($settingsPath, $json, [Text.UTF8Encoding]::new($false))
    try { $written = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'release_parent_settings_invalid' }
    if ([string]$written.language -cne 'ko-KR' -or [string]$written.ytdlp_path -cne '.\yt-dlp.exe' -or
        [string]$written.outpath -cne '.' -or [int]$written.ratelim -ne 0 -or [int]$written.ratelim_unit -ne 1 -or
        @($written.unfinished_queue_items).Count -ne 0 -or @($written.unfinished_queue_states).Count -ne 0) {
        throw 'release_parent_settings_invalid'
    }
    return $settingsPath
}

function Initialize-CiNightlyParentRuntime {
    param(
        [Parameter(Mandatory = $true)] [string] $SourceRoot,
        [Parameter(Mandatory = $true)] [string] $ParentRuntime
    )
    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) { throw 'release_source_missing' }
    if (-not (Test-Path -LiteralPath $ParentRuntime -PathType Container)) { throw 'release_parent_runtime_missing' }
    $parent = [IO.Path]::GetFullPath($ParentRuntime)
    if (-not (Test-UpstreamRuntimeComplete -RuntimeRoot $parent)) { throw 'release_parent_runtime_incomplete' }
    $target = Join-Path $parent 'yt-dlp.exe'
    $modulePath = Join-Path ([IO.Path]::GetFullPath($SourceRoot)) 'tools\runtime-maintenance.psm1'
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw 'release_runtime_module_missing' }

    $module = Import-Module -Name $modulePath -Force -PassThru
    try {
        $transaction = & $module {
            param($TargetPath)
            $resolvedTargetPath = Resolve-CanonicalYtDlpTargetPath $TargetPath
            $metadataStagingPath = New-SiblingPath $resolvedTargetPath 'release-metadata'
            [IO.Directory]::CreateDirectory($metadataStagingPath) | Out-Null
            try {
                $official = Get-OfficialNightlyAsset $metadataStagingPath
                $result = Invoke-YtDlpTransaction -TargetPath $resolvedTargetPath -AssetPath $official.AssetPath -ReleaseTag $official.ReleaseTag -ExpectedSha256 $official.ExpectedSha256 -Confirm:$false
                return [pscustomobject]@{
                    ReleaseTag = $official.ReleaseTag
                    ExpectedSha256 = $official.ExpectedSha256
                    Updated = [bool]$result.Updated
                }
            }
            finally {
                if (Test-Path -LiteralPath $metadataStagingPath) { Remove-Item -LiteralPath $metadataStagingPath -Recurse -Force -ErrorAction SilentlyContinue }
            }
        } $target
    }
    finally { Remove-Module $module -Force -ErrorAction SilentlyContinue }

    if ($null -eq $transaction -or -not [bool]$transaction.Updated -or
        [string]::IsNullOrWhiteSpace([string]$transaction.ReleaseTag) -or
        -not (Test-HexDigest -Value ([string]$transaction.ExpectedSha256) -Length 64)) {
        throw 'release_nightly_transaction_invalid'
    }

    $buildScript = Join-Path ([IO.Path]::GetFullPath($SourceRoot)) 'tools\build-candidate.ps1'
    $verified = & {
        param($ScriptPath, $RuntimePath)
        . $ScriptPath
        Get-VerifiedParentRuntime -ParentRuntime $RuntimePath
    } $buildScript $parent

    if ($null -eq $verified -or [string]$verified.Path -cne $parent -or
        [string]$verified.YtDlpVersion -cne [string]$transaction.ReleaseTag -or
        ([string]$verified.YtDlpHash).ToLowerInvariant() -cne ([string]$transaction.ExpectedSha256).ToLowerInvariant()) {
        throw 'release_parent_provenance_invalid'
    }
    return $verified
}

function New-VerifiedUpstreamParentRuntime {
    param(
        [Parameter(Mandatory = $true)] [string] $SourceRoot,
        [Parameter(Mandatory = $true)] [string] $WorkspaceRoot
    )
    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) { throw 'release_source_missing' }
    $workspace = [IO.Path]::GetFullPath($WorkspaceRoot)
    if (Test-Path -LiteralPath $workspace) {
        if (@(Get-ChildItem -LiteralPath $workspace -Force).Count -ne 0) { throw 'release_workspace_not_empty' }
    } else { [IO.Directory]::CreateDirectory($workspace) | Out-Null }

    $config = Get-FirstReleaseConfiguration
    $archive = Join-Path $workspace $config.UpstreamAssetName
    $extractRoot = Join-Path $workspace 'upstream-extracted'
    [IO.Directory]::CreateDirectory($extractRoot) | Out-Null
    $previousProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri (Get-UpstreamReleaseAssetUrl) -OutFile $archive
        Assert-UpstreamArchiveHash -ArchivePath $archive | Out-Null
        $sevenZip = Get-TrustedReleaseSevenZip
        Invoke-ReleaseNative -FilePath $sevenZip -Arguments @('x', $archive, ('-o' + $extractRoot), '-y') -FailureCode 'upstream_extract_failed' | Out-Null
        $parent = Resolve-UpstreamRuntimeRoot -ExtractedRoot $extractRoot
        $settingsPath = Initialize-ReleaseParentSettings -ParentRuntime $parent
        $verified = Initialize-CiNightlyParentRuntime -SourceRoot $SourceRoot -ParentRuntime $parent
        return [pscustomobject]@{
            ParentRuntime = $parent
            UpstreamArchivePath = $archive
            UpstreamArchiveSha256 = $config.UpstreamArchiveSha256.ToLowerInvariant()
            SettingsPath = $settingsPath
            YtDlpTag = [string]$verified.YtDlpVersion
            YtDlpSha256 = ([string]$verified.YtDlpHash).ToLowerInvariant()
            YtDlpProvenancePath = Join-Path $parent 'yt-dlp-provenance.json'
        }
    }
    finally { $ProgressPreference = $previousProgress }
}

function Invoke-ReleaseCandidateBuild {
    param(
        [Parameter(Mandatory = $true)] [string] $SourceRoot,
        [Parameter(Mandatory = $true)] [string] $ParentRuntime,
        [Parameter(Mandatory = $true)] [string] $CandidateBase
    )
    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) { throw 'release_source_missing' }
    if (-not (Test-Path -LiteralPath $ParentRuntime -PathType Container)) { throw 'release_parent_runtime_missing' }
    $source = [IO.Path]::GetFullPath($SourceRoot)
    $parent = [IO.Path]::GetFullPath($ParentRuntime)
    $candidateBaseFull = [IO.Path]::GetFullPath($CandidateBase)
    [IO.Directory]::CreateDirectory($candidateBaseFull) | Out-Null
    if (Test-ReleasePathContained -Root $parent -Path $candidateBaseFull -or Test-ReleasePathContained -Root $candidateBaseFull -Path $parent -or $parent -ceq $candidateBaseFull) {
        throw 'release_candidate_parent_overlap'
    }
    $buildScript = Join-Path $source 'tools\build-candidate.ps1'
    $results = @(& {
        param($ScriptPath, $Source, $Parent, $Base)
        . $ScriptPath
        Invoke-BuildCandidate -SourceRoot $Source -ParentRuntime $Parent -CandidateBase $Base -DependencyArchiveDirectory $Source
    } $buildScript $source $parent $candidateBaseFull)
    $built = $results | Where-Object { $null -ne $_.PSObject.Properties['CandidateRoot'] -and $null -ne $_.PSObject.Properties['ManifestPath'] } | Select-Object -Last 1
    if ($null -eq $built) { throw 'release_candidate_build_result_missing' }
    $candidate = [IO.Path]::GetFullPath([string]$built.CandidateRoot)
    $manifestPath = [IO.Path]::GetFullPath([string]$built.ManifestPath)
    if (-not (Test-ReleasePathContained -Root $candidateBaseFull -Path $candidate) -or
        -not (Test-ReleasePathContained -Root $candidate -Path $manifestPath) -or
        -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'release_candidate_build_result_invalid' }
    $manifestSha = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $candidateModule = Import-Module -Name (Join-Path $source 'tools\candidate-manifest.psm1') -Force -PassThru
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        & $candidateModule { param($Root,$Value) Assert-CandidateManifestSeal -CandidateRoot $Root -Manifest $Value } $candidate $manifest | Out-Null
    }
    finally { Remove-Module $candidateModule -Force -ErrorAction SilentlyContinue }
    return [pscustomobject]@{ CandidateRoot = $candidate; ManifestPath = $manifestPath; ManifestSha256 = $manifestSha }
}

function Invoke-ReleaseArtifactSmoke {
    param(
        [Parameter(Mandatory = $true)] [string] $SourceRoot,
        [Parameter(Mandatory = $true)] [string] $CandidateRoot,
        [Parameter(Mandatory = $true)] [string] $ParentRuntime,
        [Parameter(Mandatory = $true)] [string] $CandidateManifestSha256,
        [Parameter(Mandatory = $true)] [string] $DownloadsPath
    )
    if (-not (Test-HexDigest -Value $CandidateManifestSha256 -Length 64)) { throw 'release_candidate_manifest_invalid' }
    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) { throw 'release_source_missing' }
    if (-not (Test-Path -LiteralPath $CandidateRoot -PathType Container)) { throw 'release_candidate_missing' }
    if (-not (Test-Path -LiteralPath $ParentRuntime -PathType Container)) { throw 'release_parent_runtime_missing' }
    $downloads = [IO.Path]::GetFullPath($DownloadsPath)
    [IO.Directory]::CreateDirectory($downloads) | Out-Null
    $evidenceRoot = Join-Path $downloads 'ytdlp-interface-smoke-evidence'
    $runsRoot = Join-Path $evidenceRoot 'runs'
    $before = @()
    if (Test-Path -LiteralPath $runsRoot -PathType Container) { $before = @(Get-ChildItem -LiteralPath $runsRoot -File -Filter '*.json' | ForEach-Object { $_.Name }) }

    $automation = {
        param($url, $executionCandidate, $outputDirectory, $guiPid)
        $ytDlp = Join-Path $executionCandidate 'yt-dlp.exe'
        $template = Join-Path $outputDirectory 'smoke.%(ext)s'
        & $ytDlp --ignore-config --no-playlist --ffmpeg-location $executionCandidate -x --audio-format mp3 -o $template $url
        if ($LASTEXITCODE -ne 0) { throw 'release_smoke_download_failed' }
        return [pscustomobject]@{ Completed = $true; GuiProcessId = $guiPid; Url = $url; OutputDirectory = $outputDirectory }
    }

    $smokeScript = Join-Path ([IO.Path]::GetFullPath($SourceRoot)) 'tools\smoke-localhost.ps1'
    & $smokeScript -Run -CandidateRoot ([IO.Path]::GetFullPath($CandidateRoot)) -ParentRuntime ([IO.Path]::GetFullPath($ParentRuntime)) -DownloadsPath $downloads -ExpectedCandidateManifestSha256 $CandidateManifestSha256 -AutomationCommand $automation | Out-Null

    if (-not (Test-Path -LiteralPath $runsRoot -PathType Container)) { throw 'release_smoke_evidence_missing' }
    $after = @(Get-ChildItem -LiteralPath $runsRoot -File -Filter '*.json')
    $new = @($after | Where-Object { $before -notcontains $_.Name })
    if ($new.Count -ne 1) { throw 'release_smoke_evidence_ambiguous' }
    $evidencePath = $new[0].FullName
    try { $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'release_smoke_evidence_invalid' }
    if (-not [bool]$evidence.succeeded -or [string]$evidence.reasonCode -cne 'ok' -or [string]$evidence.mode -cne 'artifact-only' -or
        ([string]$evidence.candidateManifestSha256).ToLowerInvariant() -cne $CandidateManifestSha256.ToLowerInvariant() -or
        -not [bool]$evidence.proof.artifactValidated -or [bool]$evidence.proof.guiInteractionProven -or
        -not [bool]$evidence.cleanupSucceeded -or [string]$evidence.output.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
        [long]$evidence.output.length -le 0 -or [double]$evidence.output.duration -le 0 -or -not [bool]$evidence.output.noPartFiles) {
        throw 'release_smoke_evidence_invalid'
    }
    return [pscustomobject]@{
        EvidencePath = $evidencePath
        EvidenceSha256 = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
        RunId = [string]$evidence.runId
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Write-Output 'Release orchestrator library loaded. No build or release action is performed without an explicit caller.'
}
