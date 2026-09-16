[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Join-Path $PSScriptRoot '..'),
    [string] $CandidateDirectory,
    [string] $LockPath = (Join-Path $PSScriptRoot '..\release\dependencies\v2.19.1-karon.2.lock.json'),
    [string] $CorrespondingSourcesPath,
    [string] $SpdxPath,
    [string] $OutputDirectory,
    [switch] $PlanOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:KaronPackageTag = 'v2.19.1-karon.2'
$script:KaronPackageBinaryName = 'ytdlp-korean-interface-v2.19.1-karon.2-win-x64.zip'
$script:KaronPackageSourcesName = 'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources.zip'
$script:KaronPackageSpdxName = 'ytdlp-korean-interface-v2.19.1-karon.2.spdx.json'
$script:KaronPackageSumsName = 'SHA256SUMS.txt'
$script:KaronPackageLicensePrefix = 'release/licenses/v2.19.1-karon.2/'

function Test-KaronPackageProperty {
    param([Parameter(Mandatory)] [object] $Value, [Parameter(Mandatory)] [string] $Name)
    $null -ne $Value.PSObject.Properties[$Name]
}

function Assert-KaronPackageJsonKeys {
    param([Parameter(Mandatory)] [Text.Json.JsonElement] $Element)

    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw 'package_json_duplicate_key' }
            Assert-KaronPackageJsonKeys -Element $property.Value
        }
    }
    elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-KaronPackageJsonKeys -Element $item }
    }
}

function Read-KaronPackageJson {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $ErrorId)

    try {
        $raw = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
        $document = [Text.Json.JsonDocument]::Parse($raw)
        try { Assert-KaronPackageJsonKeys -Element $document.RootElement }
        finally { $document.Dispose() }
        $raw | ConvertFrom-Json -Depth 64
    }
    catch { throw "$ErrorId`: $($_.Exception.Message)" }
}

function Get-KaronPackageSha256 {
    param([Parameter(Mandatory)] [string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-KaronPackageRelativePath {
    param([string] $Path, [Parameter(Mandatory)] [string] $ErrorId)

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\\:\x00-\x1f<>"|?*]' -or
        $Path.StartsWith('/') -or [IO.Path]::IsPathRooted($Path)) { throw $ErrorId }
    foreach ($part in $Path.Split('/')) {
        if ([string]::IsNullOrWhiteSpace($part) -or $part -eq '.' -or $part -eq '..') { throw $ErrorId }
    }
}

function Get-KaronPackageChildPath {
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string] $RelativePath,
        [Parameter(Mandatory)] [string] $ErrorId
    )

    Assert-KaronPackageRelativePath -Path $RelativePath -ErrorId $ErrorId
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $child = [IO.Path]::GetFullPath((Join-Path $rootPath ($RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))))
    $prefix = $rootPath + [IO.Path]::DirectorySeparatorChar
    if (-not $child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw $ErrorId }
    $child
}

function Get-KaronPackageSafeInventory {
    param([Parameter(Mandatory)] [string] $Root, [Parameter(Mandatory)] [string] $ErrorPrefix)

    $rootPath = [IO.Path]::GetFullPath($Root)
    if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { throw ($ErrorPrefix + '_root_missing') }
    $rootItem = Get-Item -LiteralPath $rootPath -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ($ErrorPrefix + '_reparse_point') }

    $byPath = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($rootPath)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ($ErrorPrefix + '_reparse_point') }
            if ($item.PSIsContainer) {
                $pending.Push($item.FullName)
                continue
            }
            $relative = [IO.Path]::GetRelativePath($rootPath, $item.FullName).Replace('\', '/')
            Assert-KaronPackageRelativePath -Path $relative -ErrorId ($ErrorPrefix + '_path_invalid')
            $entry = [pscustomobject]@{
                RelativePath = $relative
                FullPath = [IO.Path]::GetFullPath($item.FullName)
                Length = [long]$item.Length
            }
            if (-not $byPath.TryAdd($relative, $entry)) { throw ($ErrorPrefix + '_path_collision') }
            if ([string]$byPath[$relative].RelativePath -cne $relative) { throw ($ErrorPrefix + '_path_collision') }
        }
    }
    $byPath
}

function Assert-KaronPackageStatusContract {
    param([Parameter(Mandatory)] [object] $Lock)

    if ($Lock.schemaVersion -cne 'karon-license-lock/v2' -or
        $Lock.release.tag -cne $script:KaronPackageTag -or
        $Lock.release.platform -cne 'win-x64') { throw 'package_lock_invalid' }
    if (-not (Test-KaronPackageProperty $Lock.release 'verificationStatus') -or
        $Lock.release.verificationStatus -cne 'verified') { throw 'package_release_not_verified' }
    if (-not (Test-KaronPackageProperty $Lock.release 'blockers') -or @($Lock.release.blockers).Count -ne 0) {
        throw 'package_release_blocked'
    }
    if (@($Lock.components).Count -eq 0) { throw 'package_components_missing' }

    foreach ($component in @($Lock.components)) {
        if (-not (Test-KaronPackageProperty $component 'verificationStatus') -or
            $component.verificationStatus -cne 'verified') { throw 'package_component_not_verified' }
        if (-not (Test-KaronPackageProperty $component 'blockers') -or @($component.blockers).Count -ne 0) {
            throw 'package_component_blocked'
        }
        if (@($component.noticeFiles).Count -eq 0 -or @($component.sourceArchives).Count -eq 0) {
            throw 'package_component_evidence_missing'
        }
        foreach ($archive in @($component.sourceArchives)) {
            if (-not (Test-KaronPackageProperty $archive 'verificationStatus') -or
                $archive.verificationStatus -cne 'verified') { throw 'package_source_not_verified' }
            if (-not (Test-KaronPackageProperty $archive 'blockers') -or @($archive.blockers).Count -ne 0) {
                throw 'package_source_blocked'
            }
            if ([string]$archive.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'package_source_hash_invalid' }
        }
    }
}

function Get-KaronPackageCandidateEntries {
    param(
        [Parameter(Mandatory)] [object] $Lock,
        [Parameter(Mandatory)] [string] $CandidateRoot
    )

    $actual = Get-KaronPackageSafeInventory -Root $CandidateRoot -ErrorPrefix 'package_candidate'
    $locked = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($Lock.release.candidateFiles)) {
        $relative = [string]$entry.path
        Assert-KaronPackageRelativePath -Path $relative -ErrorId 'package_candidate_path_invalid'
        if ([string]$entry.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'package_candidate_hash_invalid' }
        if (-not $locked.TryAdd($relative, $entry)) { throw 'package_candidate_path_collision' }
        if ([string]$locked[$relative].path -cne $relative) { throw 'package_candidate_path_collision' }
    }
    if ($locked.Count -eq 0 -or -not $locked.ContainsKey('candidate-manifest.json')) {
        throw 'package_candidate_manifest_missing'
    }
    if ($actual.Count -ne $locked.Count) { throw 'package_candidate_inventory_mismatch' }

    foreach ($relative in $locked.Keys) {
        if (-not $actual.ContainsKey($relative) -or [string]$actual[$relative].RelativePath -cne [string]$locked[$relative].path) {
            throw 'package_candidate_inventory_mismatch'
        }
        if ((Get-KaronPackageSha256 $actual[$relative].FullPath) -cne ([string]$locked[$relative].sha256).ToLowerInvariant()) {
            throw "package_candidate_hash_mismatch: $relative"
        }
    }

    $manifestPath = $actual['candidate-manifest.json'].FullPath
    $manifest = Read-KaronPackageJson -Path $manifestPath -ErrorId 'package_candidate_manifest_invalid'
    if ($manifest.schemaVersion -ne 1 -or -not (Test-KaronPackageProperty $manifest 'files')) {
        throw 'package_candidate_manifest_invalid'
    }
    $manifestFiles = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($manifest.files)) {
        $relative = [string]$entry.path
        Assert-KaronPackageRelativePath -Path $relative -ErrorId 'package_candidate_manifest_inventory_mismatch'
        $length = 0L
        if ($relative -ieq 'candidate-manifest.json' -or [string]$entry.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
            -not [long]::TryParse([string]$entry.length, [ref]$length) -or $length -lt 0) {
            throw 'package_candidate_manifest_inventory_mismatch'
        }
        if (-not $manifestFiles.TryAdd($relative, $entry)) { throw 'package_candidate_manifest_path_collision' }
        if ([string]$manifestFiles[$relative].path -cne $relative) { throw 'package_candidate_manifest_path_collision' }
    }
    if ($manifestFiles.Count -ne ($locked.Count - 1)) { throw 'package_candidate_manifest_inventory_mismatch' }
    foreach ($relative in $locked.Keys) {
        if ($relative -ieq 'candidate-manifest.json') { continue }
        if (-not $manifestFiles.ContainsKey($relative) -or [string]$manifestFiles[$relative].path -cne [string]$locked[$relative].path) {
            throw 'package_candidate_manifest_inventory_mismatch'
        }
        if ([string]$manifestFiles[$relative].sha256 -cne ([string]$locked[$relative].sha256).ToLowerInvariant()) {
            throw "package_candidate_manifest_hash_mismatch: $relative"
        }
        if ([long]$manifestFiles[$relative].length -ne [long]$actual[$relative].Length) {
            throw "package_candidate_manifest_length_mismatch: $relative"
        }
    }

    $entries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($relative in $locked.Keys) {
        $value = [pscustomobject]@{
            EntryName = [string]$locked[$relative].path
            SourcePath = [string]$actual[$relative].FullPath
            Sha256 = (Get-KaronPackageSha256 $actual[$relative].FullPath)
            Length = [long]$actual[$relative].Length
        }
        if (-not $entries.TryAdd($value.EntryName, $value)) { throw 'package_output_path_collision' }
    }
    $entries
}

function Add-KaronPackageNoticeEntries {
    param(
        [Parameter(Mandatory)] [Collections.Generic.Dictionary[string, object]] $Entries,
        [Parameter(Mandatory)] [object] $Lock,
        [Parameter(Mandatory)] [string] $SourceRoot
    )

    $rootNotice = [IO.Path]::GetFullPath((Join-Path $SourceRoot 'THIRD-PARTY-NOTICES.txt'))
    if (-not (Test-Path -LiteralPath $rootNotice -PathType Leaf)) { throw 'package_root_notice_missing' }
    $rootNoticeItem = Get-Item -LiteralPath $rootNotice -Force
    if (($rootNoticeItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $rootNoticeItem.Length -le 0) {
        throw 'package_root_notice_invalid'
    }
    $noticeEntry = [pscustomobject]@{
        EntryName = 'THIRD-PARTY-NOTICES.txt'
        SourcePath = $rootNotice
        Sha256 = Get-KaronPackageSha256 $rootNotice
        Length = [long]$rootNoticeItem.Length
    }
    if (-not $Entries.TryAdd($noticeEntry.EntryName, $noticeEntry)) { throw 'package_output_path_collision' }

    $expected = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($component in @($Lock.components)) {
        foreach ($notice in @($component.noticeFiles)) {
            $relative = [string]$notice.path
            Assert-KaronPackageRelativePath -Path $relative -ErrorId 'package_license_path_invalid'
            if (-not $relative.StartsWith($script:KaronPackageLicensePrefix, [StringComparison]::Ordinal)) {
                throw 'package_license_path_invalid'
            }
            if ([string]$notice.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'package_license_hash_invalid' }
            if (-not $expected.TryAdd($relative, $notice)) { throw 'package_license_path_collision' }
            if ([string]$expected[$relative].path -cne $relative) { throw 'package_license_path_collision' }
        }
    }

    $licenseRoot = Join-Path $SourceRoot 'release\licenses\v2.19.1-karon.2'
    $actual = Get-KaronPackageSafeInventory -Root $licenseRoot -ErrorPrefix 'package_license'
    if ($actual.Count -ne $expected.Count) { throw 'package_license_inventory_mismatch' }
    foreach ($relative in $expected.Keys) {
        $corpusRelative = $relative.Substring($script:KaronPackageLicensePrefix.Length)
        if (-not $actual.ContainsKey($corpusRelative) -or [string]$actual[$corpusRelative].RelativePath -cne $corpusRelative) {
            throw 'package_license_inventory_mismatch'
        }
        $actualHash = Get-KaronPackageSha256 $actual[$corpusRelative].FullPath
        if ($actualHash -cne ([string]$expected[$relative].sha256).ToLowerInvariant()) {
            throw "package_license_hash_mismatch: $relative"
        }
        $value = [pscustomobject]@{
            EntryName = $relative
            SourcePath = [string]$actual[$corpusRelative].FullPath
            Sha256 = $actualHash
            Length = [long]$actual[$corpusRelative].Length
        }
        if (-not $Entries.TryAdd($relative, $value)) { throw 'package_output_path_collision' }
    }
}

function Get-KaronPackageSortedNames {
    param([Parameter(Mandatory)] [Collections.Generic.Dictionary[string, object]] $Entries)
    $names = [string[]]@($Entries.Keys)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    $names
}

function Get-KaronPackageStreamSha256 {
    param([Parameter(Mandatory)] [IO.Stream] $Stream)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { [Convert]::ToHexString($hasher.ComputeHash($Stream)).ToLowerInvariant() }
    finally { $hasher.Dispose() }
}

function New-KaronPackageBinaryZipPartial {
    param(
        [Parameter(Mandatory)] [Collections.Generic.Dictionary[string, object]] $Entries,
        [Parameter(Mandatory)] [string] $PartialPath
    )

    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::Open($PartialPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($name in @(Get-KaronPackageSortedNames $Entries)) {
                $input = $Entries[$name]
                $entry = $zip.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $inputStream = [IO.File]::OpenRead($input.SourcePath)
                $outputStream = $entry.Open()
                try { $inputStream.CopyTo($outputStream) }
                finally { $outputStream.Dispose(); $inputStream.Dispose() }
            }
        }
        finally { $zip.Dispose() }
    }
    finally { $stream.Dispose() }

    $readStream = [IO.File]::OpenRead($PartialPath)
    try {
        $zip = [IO.Compression.ZipArchive]::new($readStream, [IO.Compression.ZipArchiveMode]::Read, $true)
        try {
            $expectedNames = @(Get-KaronPackageSortedNames $Entries)
            $actualNames = @($zip.Entries | ForEach-Object FullName)
            if (($actualNames -join "`n") -cne ($expectedNames -join "`n")) { throw 'package_zip_inventory_mismatch' }
            for ($index = 0; $index -lt $zip.Entries.Count; $index++) {
                $entry = $zip.Entries[$index]
                $expected = $Entries[$entry.FullName]
                if ([long]$entry.Length -ne [long]$expected.Length) { throw 'package_zip_length_mismatch' }
                $entryStream = $entry.Open()
                try { $hash = Get-KaronPackageStreamSha256 $entryStream }
                finally { $entryStream.Dispose() }
                if ($hash -cne [string]$expected.Sha256) { throw 'package_zip_hash_mismatch' }
            }
        }
        finally { $zip.Dispose() }
    }
    finally { $readStream.Dispose() }
}

function Move-KaronPackageOwnedArtifact {
    param(
        [Parameter(Mandatory)] [string] $PartialPath,
        [Parameter(Mandatory)] [string] $FinalPath
    )

    try { [IO.File]::Move($PartialPath, $FinalPath, $false) }
    catch {
        if (Test-Path -LiteralPath $PartialPath) { Remove-Item -LiteralPath $PartialPath -Force }
        throw "package_output_race: $FinalPath"
    }
    finally {
        if (Test-Path -LiteralPath $PartialPath) { Remove-Item -LiteralPath $PartialPath -Force }
    }
}

function Copy-KaronPackageArtifactAtomic {
    param(
        [Parameter(Mandatory)] [string] $SourcePath,
        [Parameter(Mandatory)] [string] $FinalPath,
        [Parameter(Mandatory)] [string] $ExpectedSha256
    )

    if ([IO.Path]::GetFullPath($SourcePath).Equals([IO.Path]::GetFullPath($FinalPath), [StringComparison]::OrdinalIgnoreCase)) {
        if ((Get-KaronPackageSha256 $FinalPath) -cne $ExpectedSha256) { throw 'package_generated_asset_hash_mismatch' }
        return
    }
    $partial = "$FinalPath.$PID.$([Guid]::NewGuid().ToString('N')).partial"
    try {
        [IO.File]::Copy($SourcePath, $partial, $false)
        if ((Get-KaronPackageSha256 $partial) -cne $ExpectedSha256) { throw 'package_generated_asset_hash_mismatch' }
        Move-KaronPackageOwnedArtifact -PartialPath $partial -FinalPath $FinalPath
    }
    finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    }
}

function Assert-KaronPackageGeneratedAsset {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $ExpectedName,
        [Parameter(Mandatory)] [string] $ErrorId
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw $ErrorId }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Name -cne $ExpectedName -or $item.Length -le 0 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw $ErrorId }
    [pscustomobject]@{
        FullPath = [IO.Path]::GetFullPath($item.FullName)
        Sha256 = Get-KaronPackageSha256 $item.FullName
        Length = [long]$item.Length
    }
}

function Assert-KaronPackageOutputReady {
    param(
        [Parameter(Mandatory)] [string] $OutputRoot,
        [Parameter(Mandatory)] [string] $SourcesPath,
        [Parameter(Mandatory)] [string] $SpdxPath
    )

    if (-not (Test-Path -LiteralPath $OutputRoot)) { New-Item -ItemType Directory -Path $OutputRoot | Out-Null }
    $rootItem = Get-Item -LiteralPath $OutputRoot -Force
    if (-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'package_output_invalid'
    }

    $allowed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $sourcesFinal = [IO.Path]::GetFullPath((Join-Path $OutputRoot $script:KaronPackageSourcesName))
    $spdxFinal = [IO.Path]::GetFullPath((Join-Path $OutputRoot $script:KaronPackageSpdxName))
    if ([IO.Path]::GetFullPath($SourcesPath).Equals($sourcesFinal, [StringComparison]::OrdinalIgnoreCase)) { [void]$allowed.Add($sourcesFinal) }
    if ([IO.Path]::GetFullPath($SpdxPath).Equals($spdxFinal, [StringComparison]::OrdinalIgnoreCase)) { [void]$allowed.Add($spdxFinal) }

    foreach ($item in @(Get-ChildItem -LiteralPath $OutputRoot -Force)) {
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            -not $allowed.Contains([IO.Path]::GetFullPath($item.FullName))) { throw 'package_output_not_empty' }
    }
    foreach ($name in @($script:KaronPackageBinaryName, $script:KaronPackageSumsName)) {
        if (Test-Path -LiteralPath (Join-Path $OutputRoot $name)) { throw 'package_output_exists' }
    }
    if (-not $allowed.Contains($sourcesFinal) -and (Test-Path -LiteralPath $sourcesFinal)) { throw 'package_output_exists' }
    if (-not $allowed.Contains($spdxFinal) -and (Test-Path -LiteralPath $spdxFinal)) { throw 'package_output_exists' }
}

function Invoke-QualityReleasePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $CandidateDirectory,
        [Parameter(Mandatory)] [string] $LockPath,
        [Parameter(Mandatory)] [string] $CorrespondingSourcesPath,
        [Parameter(Mandatory)] [string] $SpdxPath,
        [Parameter(Mandatory)] [string] $OutputDirectory,
        [switch] $PlanOnly
    )

    $sourceRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    $candidateRoot = [IO.Path]::GetFullPath($CandidateDirectory)
    $outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
    if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container) -or
        -not (Test-Path -LiteralPath $candidateRoot -PathType Container) -or
        -not (Test-Path -LiteralPath $LockPath -PathType Leaf)) { throw 'package_input_missing' }

    $sources = Assert-KaronPackageGeneratedAsset -Path $CorrespondingSourcesPath -ExpectedName $script:KaronPackageSourcesName -ErrorId 'package_sources_invalid'
    $spdx = Assert-KaronPackageGeneratedAsset -Path $SpdxPath -ExpectedName $script:KaronPackageSpdxName -ErrorId 'package_spdx_invalid'
    $lock = Read-KaronPackageJson -Path $LockPath -ErrorId 'package_lock_invalid'
    Assert-KaronPackageStatusContract -Lock $lock
    $entries = Get-KaronPackageCandidateEntries -Lock $lock -CandidateRoot $candidateRoot
    Add-KaronPackageNoticeEntries -Entries $entries -Lock $lock -SourceRoot $sourceRoot
    Assert-KaronPackageOutputReady -OutputRoot $outputRoot -SourcesPath $sources.FullPath -SpdxPath $spdx.FullPath

    $binaryPath = Join-Path $outputRoot $script:KaronPackageBinaryName
    $sourcesFinal = Join-Path $outputRoot $script:KaronPackageSourcesName
    $spdxFinal = Join-Path $outputRoot $script:KaronPackageSpdxName
    $sumsPath = Join-Path $outputRoot $script:KaronPackageSumsName
    $assetPaths = @($binaryPath, $sourcesFinal, $spdxFinal, $sumsPath)
    if ($PlanOnly) {
        return [pscustomobject]@{ Mode = 'plan'; AssetPaths = $assetPaths; ZipEntries = @(Get-KaronPackageSortedNames $entries) }
    }

    $binaryPartial = "$binaryPath.$PID.$([Guid]::NewGuid().ToString('N')).partial"
    try {
        New-KaronPackageBinaryZipPartial -Entries $entries -PartialPath $binaryPartial
        Move-KaronPackageOwnedArtifact -PartialPath $binaryPartial -FinalPath $binaryPath
    }
    finally {
        if (Test-Path -LiteralPath $binaryPartial) { Remove-Item -LiteralPath $binaryPartial -Force }
    }

    Copy-KaronPackageArtifactAtomic -SourcePath $sources.FullPath -FinalPath $sourcesFinal -ExpectedSha256 $sources.Sha256
    Copy-KaronPackageArtifactAtomic -SourcePath $spdx.FullPath -FinalPath $spdxFinal -ExpectedSha256 $spdx.Sha256

    $lines = @(
        ((Get-KaronPackageSha256 $binaryPath) + '  ' + $script:KaronPackageBinaryName)
        ((Get-KaronPackageSha256 $sourcesFinal) + '  ' + $script:KaronPackageSourcesName)
        ((Get-KaronPackageSha256 $spdxFinal) + '  ' + $script:KaronPackageSpdxName)
    )
    $sumsPartial = "$sumsPath.$PID.$([Guid]::NewGuid().ToString('N')).partial"
    try {
        [IO.File]::WriteAllText($sumsPartial, (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
        Move-KaronPackageOwnedArtifact -PartialPath $sumsPartial -FinalPath $sumsPath
    }
    finally {
        if (Test-Path -LiteralPath $sumsPartial) { Remove-Item -LiteralPath $sumsPartial -Force }
    }

    $finalItems = @(Get-ChildItem -LiteralPath $outputRoot -Force)
    if ($finalItems.Count -ne 4 -or @($finalItems | Where-Object {
        $_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $_.Length -le 0
    }).Count -ne 0) { throw 'package_final_inventory_invalid' }
    $finalNames = [string[]]@($finalItems | ForEach-Object Name)
    $expectedNames = [string[]]@($script:KaronPackageBinaryName, $script:KaronPackageSourcesName, $script:KaronPackageSpdxName, $script:KaronPackageSumsName)
    [Array]::Sort($finalNames, [StringComparer]::Ordinal)
    [Array]::Sort($expectedNames, [StringComparer]::Ordinal)
    if (($finalNames -join "`n") -cne ($expectedNames -join "`n")) { throw 'package_final_inventory_invalid' }

    [pscustomobject]@{ Mode = 'packaged'; AssetPaths = $assetPaths; ZipEntries = @(Get-KaronPackageSortedNames $entries) }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-QualityReleasePackage `
        -RepositoryRoot $RepositoryRoot `
        -CandidateDirectory $CandidateDirectory `
        -LockPath $LockPath `
        -CorrespondingSourcesPath $CorrespondingSourcesPath `
        -SpdxPath $SpdxPath `
        -OutputDirectory $OutputDirectory `
        -PlanOnly:$PlanOnly
}
