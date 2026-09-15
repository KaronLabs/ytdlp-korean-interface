#requires -Version 7.4
<#
.SYNOPSIS
Packages an independently validated, already sanitized karon.2 candidate.
.DESCRIPTION
No build, runtime execution, download, upload, Git mutation, or candidate repair.
All inputs are mandatory with -Run. OutputRoot must already exist. The package
directory must be new; failures leave incomplete output for independent review.
Evidence uses quality-release-validation/v1. Raw evidence stays outside the ZIP.
The app owner supplies ShippingSettingsPath BEFORE candidate sealing. The evidence
binds its bytes, explicit versioned policy, production API source, and runtime test.
Do not use the first-release factory/archive for this release.
#>
[CmdletBinding()]
param(
    [string] $SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [string] $SourceSha,
    [string] $CandidateRoot,
    [string] $CandidateManifestSha256,
    [string] $EvidencePath,
    [string] $EvidenceSha256,
    [string] $ShippingSettingsPath,
    [string] $LicenseRoot,
    [string] $OutputRoot,
    [switch] $Run
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-QualityRelativePath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\\:\x00-\x1f<>"|?*]' -or $Path.StartsWith('/')) {
        throw 'quality_path_invalid'
    }
    foreach ($part in $Path.Split('/')) {
        if ($part -in @('', '.', '..') -or $part -match '[. ]$|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)') {
            throw 'quality_path_invalid'
        }
    }
}

function Test-QualityWithin {
    param([string] $Root, [string] $Path)
    return $Path.Equals($Root, [StringComparison]::OrdinalIgnoreCase) -or
        $Path.StartsWith($Root.TrimEnd('\', '/') + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Get-QualityPath {
    param([string] $Path, [ValidateSet('File', 'Directory')] [string] $Kind)
    if ($Path -notmatch '^[A-Za-z]:[\\/]' -or $Path.Substring(2) -match ':|[\x00-\x1f]' -or $Path -match '[*?]') {
        throw 'quality_absolute_local_path_required'
    }
    $full = [IO.Path]::GetFullPath($Path)
    $item = Get-Item -LiteralPath $full -Force
    if (($Kind -eq 'Directory') -ne [bool]$item.PSIsContainer) { throw 'quality_path_type_invalid' }
    $cursor = $full
    while ($null -ne $cursor) {
        $ancestor = Get-Item -LiteralPath $cursor -Force
        if (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'quality_reparse_point_rejected' }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
        if ($cursor -eq '') { $cursor = $null }
    }
    return $full.TrimEnd('\', '/')
}

function Get-QualityChild {
    param([string] $Root, [string] $Relative)
    Assert-QualityRelativePath $Relative
    $path = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not (Test-QualityWithin $Root $path)) { throw 'quality_path_escape' }
    return Get-QualityPath $path File
}

function Get-QualityHash {
    param([string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-QualityHash {
    param([string] $Path, [string] $Sha256)
    if ($Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or (Get-QualityHash $Path) -cne $Sha256.ToLowerInvariant()) {
        throw 'quality_input_hash_mismatch'
    }
}

function Assert-QualityJsonKeys {
    param([System.Text.Json.JsonElement] $Element)
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw 'quality_duplicate_json_key' }
            Assert-QualityJsonKeys $property.Value
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($elementValue in $Element.EnumerateArray()) { Assert-QualityJsonKeys $elementValue }
    }
}

function Read-QualityJson {
    param([string] $Path)
    $raw = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
    $document = [System.Text.Json.JsonDocument]::Parse($raw)
    try {
        if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw 'quality_json_object_required' }
        Assert-QualityJsonKeys $document.RootElement
        $value = ConvertFrom-Json -InputObject $raw -Depth 64
        if ($null -ne $value.PSObject.Properties['schemaVersion'] -and
            $value.schemaVersion -ceq 'quality-release-validation/v1') {
            # PowerShell 7.4 converts ISO dates automatically. Keep the evidence's
            # original offsets instead of casting the resulting DateTime to text.
            $index = 0
            foreach ($check in $document.RootElement.GetProperty('checks').EnumerateArray()) {
                foreach ($name in @('startedAtUtc', 'finishedAtUtc')) {
                    $timestamp = $check.GetProperty($name)
                    if ($timestamp.ValueKind -ne [System.Text.Json.JsonValueKind]::String) { throw 'quality_evidence_time_invalid' }
                    $value.checks[$index].$name = $timestamp.GetString()
                }
                $index++
            }
        }
    }
    finally { $document.Dispose() }
    return $value
}

function Get-QualityTreeFiles {
    param([string] $Root)
    foreach ($item in Get-ChildItem -LiteralPath $Root -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'quality_reparse_point_rejected' }
        if ($item.PSIsContainer) { Get-QualityTreeFiles $item.FullName }
        else { $item }
    }
}

function Invoke-QualityGit {
    param([string] $Root, [string[]] $Arguments)
    $lines = @(& git.exe --no-optional-locks -c core.quotepath=false -C $Root @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'quality_source_git_read_failed' }
    return $lines
}

function Assert-QualitySource {
    param([string] $Root, [string] $Sha, [object] $Attestation)
    if ($Sha -notmatch '^[a-fA-F0-9]{40}$') { throw 'quality_source_sha_required' }
    $head = (@(Invoke-QualityGit $Root @('rev-parse', '--verify', 'HEAD')) -join '').Trim()
    if ($head -cne $Sha.ToLowerInvariant() -or $head -cne ([string]$Attestation.commit).ToLowerInvariant()) {
        throw 'quality_source_head_mismatch'
    }
    if (@(Invoke-QualityGit $Root @('status', '--porcelain=v1', '--untracked-files=all')).Count -ne 0) {
        throw 'quality_source_worktree_dirty'
    }
    if ($Attestation.dirty -isnot [bool] -or $Attestation.dirty) { throw 'quality_source_attestation_dirty' }
    $tracked = @(Invoke-QualityGit $Root @('ls-files', '--cached') | Sort-Object -Unique)
    $records = foreach ($relative in $tracked) {
        $path = Get-QualityChild $Root ([string]$relative)
        ([string]$relative) + "`0" + (Get-Item -LiteralPath $path).Length + "`0" + (Get-QualityHash $path).ToUpperInvariant()
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($records -join "`n"))
    $digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    if ($tracked.Count -eq 0 -or $tracked.Count -ne $Attestation.trackedFileCount -or
        $digest -cne ([string]$Attestation.treeSha256).ToUpperInvariant()) { throw 'quality_source_tree_mismatch' }
    return $tracked
}

function Get-QualityRequiredChecks {
    @('source-review', 'production-policy-tests', 'offline-media', 'only-360p', 'only-2160p-blocked',
        'portrait', 'missing-dimensions', 'missing-audio', 'vp9-av1', 'external-config-isolation',
        'fresh-basic1080', 'legacy-settings', 'queue-restore-isolation', 'stale-preview', 'changed-selection',
        'missing-broken-ffmpeg', 'postprocess-probe-failure', 'playlist-live-boundary', 'mp3-smoke',
        'runtime-provenance', 'shipping-privacy', 'third-party-licenses',
        'gui-ko-KR-100', 'gui-ko-KR-150', 'gui-ko-KR-200', 'gui-en-US-100', 'gui-en-US-150', 'gui-en-US-200')
}

function Write-QualityNewText {
    param([string] $Path, [string] $Text)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
        $stream.Write($bytes, 0, $bytes.Length)
    }
    finally { $stream.Dispose() }
}

function New-QualityZip {
    param([string] $Path, [string] $PackageRoot, [string] $PackageName, [object[]] $Inventory)
    $output = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $archive = [IO.Compression.ZipArchive]::new($output, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($record in $Inventory) {
                $inputPath = Get-QualityChild $PackageRoot $record.path
                $entry = $archive.CreateEntry(($PackageName + '/' + $record.path), [IO.Compression.CompressionLevel]::Optimal)
                $inputStream = [IO.File]::Open($inputPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                try {
                    $entryStream = $entry.Open()
                    try { $inputStream.CopyTo($entryStream) }
                    finally { $entryStream.Dispose() }
                }
                finally { $inputStream.Dispose() }
            }
        }
        finally { $archive.Dispose() }
        $output.Position = 0
        $archive = [IO.Compression.ZipArchive]::new($output, [IO.Compression.ZipArchiveMode]::Read, $true)
        try {
            $expected = @{}
            foreach ($record in $Inventory) { $expected.Add(($PackageName + '/' + $record.path), $record) }
            $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($entry in $archive.Entries) {
                Assert-QualityRelativePath $entry.FullName
                if (-not $seen.Add($entry.FullName) -or -not $expected.ContainsKey($entry.FullName)) { throw 'quality_zip_inventory_mismatch' }
                $record = $expected[$entry.FullName]
                if ($entry.FullName -cne ($PackageName + '/' + $record.path) -or $entry.Length -ne $record.length) { throw 'quality_zip_inventory_mismatch' }
                $entryStream = $entry.Open()
                try { $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($entryStream)).ToLowerInvariant() }
                finally { $entryStream.Dispose() }
                if ($hash -cne $record.sha256) { throw 'quality_zip_hash_mismatch' }
            }
            if ($seen.Count -ne $expected.Count) { throw 'quality_zip_inventory_mismatch' }
        }
        finally { $archive.Dispose() }
        $output.Position = 0
        return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($output)).ToLowerInvariant()
    }
    finally { $output.Dispose() }
}

function Invoke-QualityPackage {
    $source = Get-QualityPath $SourceRoot Directory
    $candidate = Get-QualityPath $CandidateRoot Directory
    $evidenceFile = Get-QualityPath $EvidencePath File
    $settingsFile = Get-QualityPath $ShippingSettingsPath File
    $licenses = Get-QualityPath $LicenseRoot Directory
    $output = Get-QualityPath $OutputRoot Directory
    foreach ($root in @($source, $candidate, $licenses)) {
        if ((Test-QualityWithin $root $output) -or (Test-QualityWithin $output $root)) { throw 'quality_output_input_overlap' }
    }
    if ((Test-QualityWithin $source $candidate) -or (Test-QualityWithin $candidate $source)) { throw 'quality_candidate_source_overlap' }
    $requestPath = Get-QualityChild $source 'release/requests/v2.19.1-karon.2.json'
    $request = Read-QualityJson $requestPath
    $expectedRequest = [ordered]@{
        schemaVersion = 1; tag = 'v2.19.1-karon.2'; platform = 'win-x64'
        upstreamRepository = 'ErrorFlynn/ytdlp-interface'; upstreamTag = 'v2.19.1'
        upstreamCommit = '2173316ebb5e50af49a2a4e939693fa8c3a3459c'; upstreamAsset = 'ytdlp-interface.7z'
        upstreamArchiveSha256 = '53b54e3c5c753e8cb2a8b9638c69c95c1449c8185c3145a9f0b06a2000b3702e'
        shippingPolicy = 'basic1080'; validationContract = 'quality-release-validation/v1'
    }
    if (@($request.PSObject.Properties).Count -ne $expectedRequest.Count) { throw 'quality_request_invalid' }
    foreach ($name in $expectedRequest.Keys) {
        if ($request.$name -cne $expectedRequest[$name]) { throw 'quality_request_invalid' }
    }

    $manifestPath = Get-QualityChild $candidate 'candidate-manifest.json'
    Assert-QualityHash $manifestPath $CandidateManifestSha256
    Assert-QualityHash $evidenceFile $EvidenceSha256
    $manifest = Read-QualityJson $manifestPath
    $evidence = Read-QualityJson $evidenceFile
    $tracked = @(Assert-QualitySource $source $SourceSha $manifest.attestation.source)
    foreach ($relative in @('tools/package-quality-release.ps1', 'tools/candidate-manifest.psm1', 'release/requests/v2.19.1-karon.2.json')) {
        if ($tracked -cnotcontains $relative) { throw 'quality_packaging_input_not_tracked' }
    }
    $ownScript = Get-QualityPath (Join-Path $PSScriptRoot 'package-quality-release.ps1') File
    Assert-QualityHash $ownScript (Get-QualityHash (Get-QualityChild $source 'tools/package-quality-release.ps1'))

    $candidateNames = @('7z.dll', 'deno.exe', 'ffmpeg.exe', 'ffprobe.exe', 'yt-dlp.exe', 'ytdlp-interface.exe',
        'ytdlp-interface.json', 'locales/ko-KR.json', 'candidate-manifest.json')
    $candidateFiles = @(Get-QualityTreeFiles $candidate)
    if ($candidateFiles.Count -ne $candidateNames.Count) { throw 'quality_candidate_inventory_rejected' }
    foreach ($file in $candidateFiles) {
        $relative = $file.FullName.Substring($candidate.Length + 1).Replace('\', '/')
        if ($candidateNames -cnotcontains $relative) { throw 'quality_candidate_inventory_rejected' }
    }
    Import-Module (Get-QualityChild $source 'tools/candidate-manifest.psm1') -Force
    Assert-CandidateManifestSeal -CandidateRoot $candidate -Manifest $manifest
    $manifestText = [IO.File]::ReadAllText($manifestPath)
    if ($manifestText -match '(?i)[/\\]+(?:Users|home|Documents and Settings)[/\\]+') { throw 'quality_candidate_manifest_private_path' }

    if ($evidence.schemaVersion -cne 'quality-release-validation/v1' -or $evidence.tag -cne $request.tag -or
        $evidence.sourceSha -cne $SourceSha.ToLowerInvariant() -or
        $evidence.candidateManifestSha256 -cne $CandidateManifestSha256.ToLowerInvariant() -or
        $evidence.reviewer.role -cne 'independent-validator' -or
        $evidence.reviewer.id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$' -or
        $evidence.implementerId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$' -or
        $evidence.reviewer.id -ieq $evidence.implementerId) { throw 'quality_independent_evidence_required' }
    $evidenceRoot = [IO.Path]::GetDirectoryName($evidenceFile)
    $pinnedInputs = [Collections.Generic.List[object]]::new()
    $pinnedInputs.Add(@{ path = $evidenceFile; sha256 = $EvidenceSha256 })
    $pinnedInputs.Add(@{ path = $manifestPath; sha256 = $CandidateManifestSha256 })
    $pinnedInputs.Add(@{ path = $requestPath; sha256 = (Get-QualityHash $requestPath) })
    $checkSummary = [Collections.Generic.List[object]]::new()
    $checkIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $requiredChecks = @(Get-QualityRequiredChecks)
    foreach ($check in $evidence.checks) {
        if (-not $checkIds.Add([string]$check.id) -or $requiredChecks -cnotcontains $check.id -or
            $check.status -cne 'pass' -or $check.executed -isnot [bool] -or -not $check.executed) { throw 'quality_required_check_not_passed' }
        $start = [DateTimeOffset]::Parse($check.startedAtUtc, [Globalization.CultureInfo]::InvariantCulture)
        $finish = [DateTimeOffset]::Parse($check.finishedAtUtc, [Globalization.CultureInfo]::InvariantCulture)
        if ($finish -lt $start -or $finish -gt [DateTimeOffset]::UtcNow -or $start.Offset -ne [TimeSpan]::Zero -or
            $finish.Offset -ne [TimeSpan]::Zero) { throw 'quality_evidence_time_invalid' }
        if ($check.method -ceq 'process') {
            if (($check.exitCode -isnot [long] -and $check.exitCode -isnot [int]) -or $check.exitCode -ne 0 -or
                [string]::IsNullOrWhiteSpace([string]$check.command)) { throw 'quality_process_evidence_invalid' }
        }
        elseif ($check.method -ceq 'manual' -and ($check.id -like 'gui-*' -or
            @('source-review', 'shipping-privacy', 'third-party-licenses') -ccontains $check.id)) {
            if ([string]::IsNullOrWhiteSpace([string]$check.procedure)) { throw 'quality_manual_evidence_invalid' }
        }
        else { throw 'quality_evidence_method_invalid' }
        $artifactHashes = [Collections.Generic.List[string]]::new()
        foreach ($artifact in $check.artifacts) {
            $artifactPath = Get-QualityChild $evidenceRoot ([string]$artifact.path)
            if ($artifact.length -le 0 -or (Get-Item -LiteralPath $artifactPath).Length -ne $artifact.length) { throw 'quality_evidence_artifact_invalid' }
            Assert-QualityHash $artifactPath ([string]$artifact.sha256)
            $pinnedInputs.Add(@{ path = $artifactPath; sha256 = $artifact.sha256 })
            $artifactHashes.Add(([string]$artifact.sha256).ToLowerInvariant())
        }
        if ($artifactHashes.Count -eq 0) { throw 'quality_raw_evidence_missing' }
        $checkSummary.Add([ordered]@{ id = $check.id; executed = $true; status = 'pass'; method = $check.method
            startedAtUtc = $start.ToString('o'); finishedAtUtc = $finish.ToString('o'); artifactSha256 = @($artifactHashes.ToArray()) })
    }
    if ($checkIds.Count -ne $requiredChecks.Count) { throw 'quality_required_evidence_missing' }

    $shipping = $evidence.shippingSettings
    if ($shipping.policyId -cne 'basic1080' -or $shipping.policyProperty -cne 'download_policy' -or
        $shipping.versionProperty -cne 'version') { throw 'quality_explicit_basic1080_policy_required' }
    Assert-QualityHash $settingsFile ([string]$shipping.sha256)
    Assert-QualityHash (Get-QualityChild $candidate 'ytdlp-interface.json') ([string]$shipping.sha256)
    $settings = Read-QualityJson $settingsFile
    if (@($settings.PSObject.Properties).Count -ne 4 -or $settings.language -cne 'ko-KR' -or
        $settings.ytdlp_path -cne '.\yt-dlp.exe' -or $settings.ffmpeg_path -cne '.\') {
        throw 'quality_shipping_settings_not_fresh'
    }
    foreach ($policy in @($shipping.policy, $settings.($shipping.policyProperty))) {
        if ($policy -isnot [pscustomobject] -or @($policy.PSObject.Properties).Count -ne 3 -or
            ($policy.version -isnot [int] -and $policy.version -isnot [long]) -or $policy.version -ne 1 -or
            $policy.mode -cne 'video' -or $policy.quality -cne '1080p') { throw 'quality_shipping_policy_mismatch' }
    }
    if ($tracked -cnotcontains $shipping.apiSource.path -or $shipping.apiSource.path -cne 'ytdlp-interface/download_policy.hpp') {
        throw 'quality_policy_api_source_required'
    }
    $apiPath = Get-QualityChild $source ([string]$shipping.apiSource.path)
    Assert-QualityHash $apiPath ([string]$shipping.apiSource.sha256)
    $pinnedInputs.Add(@{ path = $settingsFile; sha256 = $shipping.sha256 })
    $pinnedInputs.Add(@{ path = $apiPath; sha256 = $shipping.apiSource.sha256 })
    if ($evidence.engine.repository -cne 'yt-dlp/yt-dlp-nightly-builds' -or $evidence.engine.channel -cne 'nightly' -or
        $evidence.engine.tag -cne ([string]$manifest.versions.ytdlp).Trim()) { throw 'quality_engine_provenance_mismatch' }
    Assert-QualityHash (Get-QualityChild $candidate 'yt-dlp.exe') ([string]$evidence.engine.sha256)

    $copies = [Collections.Generic.List[object]]::new()
    foreach ($entry in $manifest.files) {
        $relative = ([string]$entry.path).Replace('\', '/')
        $copies.Add(@{ path = $relative; input = (Get-QualityChild $candidate $relative); sha256 = ([string]$entry.sha256).ToLowerInvariant(); length = [long]$entry.length })
    }
    $copies.Add(@{ path = 'candidate-manifest.json'; input = $manifestPath; sha256 = $CandidateManifestSha256.ToLowerInvariant(); length = (Get-Item -LiteralPath $manifestPath).Length })
    foreach ($relative in @('LICENSE', 'NOTICE', 'PROVENANCE.md')) {
        if ($tracked -cnotcontains $relative) { throw 'quality_attribution_not_tracked' }
        $path = Get-QualityChild $source $relative
        $copies.Add(@{ path = $relative; input = $path; sha256 = (Get-QualityHash $path); length = (Get-Item -LiteralPath $path).Length })
    }
    $components = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $licensePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $licenseSummary = [Collections.Generic.List[object]]::new()
    foreach ($license in $evidence.licenseFiles) {
        $path = Get-QualityChild $licenses ([string]$license.path)
        if (-not $licensePaths.Add([string]$license.path) -or $license.path -notmatch '(?i)(?:\.txt|\.md|(?:^|/)(?:LICENSE|COPYING|NOTICE))$' -or
            $license.length -le 0 -or (Get-Item -LiteralPath $path).Length -ne $license.length) { throw 'quality_license_invalid' }
        Assert-QualityHash $path ([string]$license.sha256)
        $licenseText = [IO.File]::ReadAllText($path, [Text.UTF8Encoding]::new($false, $true))
        if ([string]::IsNullOrWhiteSpace($licenseText) -or $licenseText.Contains([char]0)) { throw 'quality_license_text_required' }
        if (@($license.components).Count -eq 0) { throw 'quality_license_component_required' }
        foreach ($component in $license.components) {
            if ($component -notmatch '^[a-z0-9][a-z0-9.-]*$') { throw 'quality_license_component_invalid' }
            $null = $components.Add([string]$component)
        }
        $relative = 'THIRD-PARTY/' + $license.path
        $copies.Add(@{ path = $relative; input = $path; sha256 = ([string]$license.sha256).ToLowerInvariant(); length = [long]$license.length })
        $licenseSummary.Add([ordered]@{ path = $relative; sha256 = ([string]$license.sha256).ToLowerInvariant(); components = @($license.components) })
    }
    foreach ($component in @('yt-dlp', 'ffmpeg', 'ffprobe', 'deno', '7zip', 'bit7z', 'nana', 'libpng', 'libjpeg-turbo', 'nlohmann-json', 'zlib')) {
        if (-not $components.Contains($component)) { throw "quality_license_missing:$component" }
    }
    foreach ($inputRecord in $pinnedInputs) {
        if (Test-QualityWithin $output $inputRecord.path) { throw 'quality_output_input_overlap' }
    }
    $destinations = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($copy in $copies) {
        Assert-QualityRelativePath $copy.path
        if (-not $destinations.Add($copy.path)) { throw 'quality_duplicate_package_path' }
    }

    # All preconditions above are read-only. Every write below is under OutputRoot.
    $packageName = 'ytdlp-korean-interface-v2.19.1-karon.2-win-x64'
    $runRoot = Join-Path $output $packageName
    if (Test-Path -LiteralPath $runRoot) { throw 'quality_output_exists_use_new_output_root' }
    $null = New-Item -ItemType Directory -Path $runRoot -ErrorAction Stop
    $package = Join-Path $runRoot $packageName
    $null = New-Item -ItemType Directory -Path $package -ErrorAction Stop
    foreach ($copy in $copies) {
        $destination = [IO.Path]::GetFullPath((Join-Path $package $copy.path))
        if (-not (Test-QualityWithin $package $destination)) { throw 'quality_output_path_escape' }
        $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        $null = Get-QualityPath ([IO.Path]::GetDirectoryName($destination)) Directory
        [IO.File]::Copy($copy.input, $destination, $false)
        Assert-QualityHash $destination $copy.sha256
        if ((Get-Item -LiteralPath $destination).Length -ne $copy.length) { throw 'quality_copy_length_mismatch' }
    }
    $inventory = @($copies | Sort-Object { $_.path } | ForEach-Object {
        [ordered]@{ path = $_.path; sha256 = $_.sha256; length = $_.length }
    })
    $release = [ordered]@{
        schemaVersion = 1; tag = $request.tag; repository = 'KaronLabs/ytdlp-korean-interface'
        platform = $request.platform; sourceCommit = $SourceSha.ToLowerInvariant()
        sourceTreeSha256 = ([string]$manifest.attestation.source.treeSha256).ToLowerInvariant()
        requestSha256 = (Get-QualityHash $requestPath); packagerSha256 = (Get-QualityHash $ownScript)
        directUpstream = [ordered]@{ repository = $request.upstreamRepository; tag = $request.upstreamTag
            commit = $request.upstreamCommit; runtimeAsset = $request.upstreamAsset; runtimeArchiveSha256 = $request.upstreamArchiveSha256 }
        candidateManifestSha256 = $CandidateManifestSha256.ToLowerInvariant()
        ytDlp = [ordered]@{ repository = $evidence.engine.repository; channel = $evidence.engine.channel
            tag = $evidence.engine.tag; sha256 = ([string]$evidence.engine.sha256).ToLowerInvariant() }
        shippingSettings = [ordered]@{ policyId = 'basic1080'; sha256 = ([string]$shipping.sha256).ToLowerInvariant()
            policyProperty = $shipping.policyProperty; policy = $shipping.policy; sourceApiSha256 = $shipping.apiSource.sha256 }
        validation = [ordered]@{ contract = $evidence.schemaVersion; evidenceSha256 = $EvidenceSha256.ToLowerInvariant()
            reviewerId = $evidence.reviewer.id; guiInteractionProven = $true; checks = @($checkSummary.ToArray()) }
        thirdPartyLicenses = @($licenseSummary.ToArray()); files = $inventory
        createdAtUtc = [DateTime]::UtcNow.ToString('o')
    }
    $releaseText = ($release | ConvertTo-Json -Depth 48) + "`n"
    $releasePath = Join-Path $package 'release-manifest.json'
    Write-QualityNewText $releasePath $releaseText
    $releaseHash = Get-QualityHash $releasePath
    $zipInventory = @($inventory) + @([ordered]@{ path = 'release-manifest.json'; sha256 = $releaseHash; length = (Get-Item -LiteralPath $releasePath).Length })
    $zipName = $packageName + '.zip'
    $zipHash = New-QualityZip (Join-Path $runRoot $zipName) $package $packageName $zipInventory

    # No completion record if any pinned input/source/candidate changed mid-package.
    foreach ($inputRecord in $pinnedInputs) { Assert-QualityHash $inputRecord.path $inputRecord.sha256 }
    foreach ($copy in $copies) { Assert-QualityHash $copy.input $copy.sha256 }
    $null = Assert-QualitySource $source $SourceSha $manifest.attestation.source
    Assert-CandidateManifestSeal -CandidateRoot $candidate -Manifest $manifest
    Write-QualityNewText (Join-Path $runRoot 'release-manifest.json') $releaseText
    $sums = "$zipHash  $zipName`n$releaseHash  release-manifest.json`n"
    Write-QualityNewText (Join-Path $runRoot 'SHA256SUMS.txt') $sums
    $completion = [ordered]@{ schemaVersion = 1; tag = $request.tag; zipSha256 = $zipHash
        checksumFileSha256 = (Get-QualityHash (Join-Path $runRoot 'SHA256SUMS.txt'))
        zipInventoryAndHashesVerified = $true; uploaded = $false; createdAtUtc = [DateTime]::UtcNow.ToString('o') }
    Write-QualityNewText (Join-Path $runRoot 'packaging-complete.json') (($completion | ConvertTo-Json) + "`n")
    return [pscustomobject]@{ OutputDirectory = $runRoot; ZipPath = (Join-Path $runRoot $zipName)
        ZipSha256 = $zipHash; ManifestPath = (Join-Path $runRoot 'release-manifest.json'); Uploaded = $false }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $Run) { Write-Output 'No action taken. Supply all reviewed inputs and -Run to package karon.2.' }
    else { Invoke-QualityPackage }
}
