[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Join-Path $PSScriptRoot '..'),
    [string] $CandidateDirectory,
    [string] $LockPath = (Join-Path $PSScriptRoot '..\release\dependencies\v2.19.1-karon.2.lock.json'),
    [string] $CorrespondingSourcesPath,
    [string] $SpdxPath,
    [string] $GuiValidationSummaryPath,
    [string] $GuiValidationEvidenceManifestPath,
    [string] $OutputDirectory,
    [string] $ReceiptPath,
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
$script:KaronPackageCliGuiSummaryPath = $GuiValidationSummaryPath
$script:KaronPackageCliGuiManifestPath = $GuiValidationEvidenceManifestPath
$script:KaronPackageCliReceiptPath = $ReceiptPath
$script:KaronPackageGuiCases = @(
    [pscustomobject]@{ Id = 'gui-en-US-100'; Language = 'en-US'; Dpi = 100 },
    [pscustomobject]@{ Id = 'gui-en-US-150'; Language = 'en-US'; Dpi = 150 },
    [pscustomobject]@{ Id = 'gui-en-US-200'; Language = 'en-US'; Dpi = 200 },
    [pscustomobject]@{ Id = 'gui-ko-KR-100'; Language = 'ko-KR'; Dpi = 100 },
    [pscustomobject]@{ Id = 'gui-ko-KR-150'; Language = 'ko-KR'; Dpi = 150 },
    [pscustomobject]@{ Id = 'gui-ko-KR-200'; Language = 'ko-KR'; Dpi = 200 }
)

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

function Get-KaronPackageRawProperty {
    param(
        [Parameter(Mandatory)] [Text.Json.JsonElement] $Element,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $ErrorId
    )
    if ($Element.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw $ErrorId }
    $matches = @($Element.EnumerateObject() | Where-Object { $_.Name -ceq $Name })
    if ($matches.Count -ne 1) { throw $ErrorId }
    $matches[0].Value.Clone()
}

function Assert-KaronPackageRawExactKeys {
    param(
        [Parameter(Mandatory)] [Text.Json.JsonElement] $Element,
        [Parameter(Mandatory)] [string[]] $Names,
        [Parameter(Mandatory)] [string] $ErrorId
    )
    if ($Element.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw $ErrorId }
    $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($name in $Names) { [void]$expected.Add($name) }
    $actual = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($property in $Element.EnumerateObject()) {
        if (-not $actual.Add($property.Name) -or -not $expected.Contains($property.Name)) { throw $ErrorId }
    }
    if ($actual.Count -ne $expected.Count) { throw $ErrorId }
}

function Get-KaronPackageRawString {
    param([Text.Json.JsonElement] $Element, [string] $ErrorId)
    if ($Element.ValueKind -ne [Text.Json.JsonValueKind]::String) { throw $ErrorId }
    $Element.GetString()
}

function Get-KaronPackageRawInt64 {
    param([Text.Json.JsonElement] $Element, [string] $ErrorId)
    if ($Element.ValueKind -ne [Text.Json.JsonValueKind]::Number) { throw $ErrorId }
    [long]$value = 0
    if (-not $Element.TryGetInt64([ref]$value)) { throw $ErrorId }
    $value
}

function Get-KaronPackageRawArray {
    param([Text.Json.JsonElement] $Element, [string] $ErrorId)
    if ($Element.ValueKind -ne [Text.Json.JsonValueKind]::Array) { throw $ErrorId }
    @($Element.EnumerateArray() | ForEach-Object { $_.Clone() })
}

function Assert-KaronPackageRawStatus {
    param(
        [Text.Json.JsonElement] $Element,
        [string] $StatusName,
        [string] $ErrorId
    )
    if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $Element $StatusName $ErrorId) $ErrorId) -cne 'verified') {
        throw $ErrorId
    }
    if (@(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $Element 'blockers' $ErrorId) $ErrorId).Count -ne 0) {
        throw $ErrorId
    }
}

function ConvertFrom-KaronPackageJsonStrict {
    param([string] $Text, [string] $ErrorId)
    try {
        $document = [Text.Json.JsonDocument]::Parse($Text)
        Assert-KaronPackageJsonKeys -Element $document.RootElement
        $raw = $document.RootElement.Clone()
        $document.Dispose()
        [pscustomobject]@{ Raw = $raw; Value = ($Text | ConvertFrom-Json -Depth 64) }
    }
    catch { throw $ErrorId }
}

function Assert-KaronPackageLockRawContract {
    param(
        [Parameter(Mandatory)] [Text.Json.JsonElement] $Root,
        [Parameter(Mandatory)] [bool] $RequireReceiptInputs,
        [Parameter(Mandatory)] [string] $ErrorId
    )
    if ($Root.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw $ErrorId }
    $release = Get-KaronPackageRawProperty $Root 'release' $ErrorId
    Assert-KaronPackageRawStatus $release 'verificationStatus' $ErrorId
    if ((Get-KaronPackageRawProperty $release 'candidateFiles' $ErrorId).ValueKind -ne [Text.Json.JsonValueKind]::Array) { throw $ErrorId }
    foreach ($candidate in Get-KaronPackageRawArray (Get-KaronPackageRawProperty $release 'candidateFiles' $ErrorId) $ErrorId) {
        if ($candidate.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw $ErrorId }
    }
    $metadata = Get-KaronPackageRawProperty $release 'metadataPackage' $ErrorId
    if ($metadata.ValueKind -ne [Text.Json.JsonValueKind]::Object -or
        (Get-KaronPackageRawString (Get-KaronPackageRawProperty $metadata 'sourceCommit' $ErrorId) $ErrorId) -notmatch '^[a-fA-F0-9]{40}$') {
        throw $ErrorId
    }
    $components = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $Root 'components' $ErrorId) $ErrorId)
    if ($components.Count -eq 0) { throw $ErrorId }
    foreach ($component in $components) {
        if ($component.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw $ErrorId }
        Assert-KaronPackageRawStatus $component 'verificationStatus' $ErrorId
        foreach ($arrayName in @('noticeFiles', 'sourceArchives')) {
            foreach ($item in Get-KaronPackageRawArray (Get-KaronPackageRawProperty $component $arrayName $ErrorId) $ErrorId) {
                if ($item.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw $ErrorId }
                if ($arrayName -ceq 'sourceArchives') { Assert-KaronPackageRawStatus $item 'verificationStatus' $ErrorId }
            }
        }
    }
    if ($RequireReceiptInputs) {
        $inputs = Get-KaronPackageRawProperty $release 'receiptInputs' $ErrorId
        Assert-KaronPackageRawExactKeys $inputs @(
            'candidateManifest', 'correspondingSources', 'spdx', 'rootThirdPartyNotices',
            'guiValidationSummary', 'guiValidationEvidenceManifest', 'releaseNotes'
        ) $ErrorId
        foreach ($name in @(
            'candidateManifest', 'correspondingSources', 'spdx', 'rootThirdPartyNotices',
            'guiValidationSummary', 'guiValidationEvidenceManifest'
        )) {
            $record = Get-KaronPackageRawProperty $inputs $name $ErrorId
            Assert-KaronPackageRawExactKeys $record @('fileName', 'length', 'sha256') $ErrorId
            [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $record 'fileName' $ErrorId) $ErrorId)
            if ((Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $record 'length' $ErrorId) $ErrorId) -le 0) { throw $ErrorId }
            if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $record 'sha256' $ErrorId) $ErrorId) -notmatch '^[a-fA-F0-9]{64}$') { throw $ErrorId }
        }
        $notes = Get-KaronPackageRawProperty $inputs 'releaseNotes' $ErrorId
        Assert-KaronPackageRawExactKeys $notes @('path', 'length', 'sha256') $ErrorId
        [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $notes 'path' $ErrorId) $ErrorId)
        if ((Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $notes 'length' $ErrorId) $ErrorId) -le 0 -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $notes 'sha256' $ErrorId) $ErrorId) -notmatch '^[a-fA-F0-9]{64}$') {
            throw $ErrorId
        }
    }
}

function Read-KaronPackageStrictLock {
    param([string] $Path)
    $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
    $json = ConvertFrom-KaronPackageJsonStrict $text 'package_lock_invalid'
    Assert-KaronPackageLockRawContract $json.Raw $true 'package_lock_type_invalid'
    $json.Value
}

function Get-KaronPackageBoundRecord {
    param([object] $Lock, [string] $Name, [string] $NameField = 'fileName')
    if (-not (Test-KaronPackageProperty $Lock.release 'receiptInputs') -or
        -not (Test-KaronPackageProperty $Lock.release.receiptInputs $Name)) { throw 'package_receipt_input_missing' }
    $record = $Lock.release.receiptInputs.$Name
    if (-not (Test-KaronPackageProperty $record $NameField) -or -not (Test-KaronPackageProperty $record 'length') -or
        -not (Test-KaronPackageProperty $record 'sha256') -or [long]$record.length -le 0 -or
        [string]$record.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'package_receipt_input_invalid' }
    [pscustomobject]@{
        Name = [string]$record.$NameField
        Length = [long]$record.length
        Sha256 = ([string]$record.sha256).ToLowerInvariant()
    }
}

function Assert-KaronPackageBoundFile {
    param([object] $Record, [string] $Path, [string] $ExpectedName, [string] $ErrorId)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw $ErrorId }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -ne $Record.Length -or
        $Record.Name -cne $ExpectedName -or (Get-KaronPackageSha256 $Path) -cne $Record.Sha256) { throw $ErrorId }
}

function Get-KaronPackageGitBlobSha1 {
    param([string] $Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $header = [Text.Encoding]::UTF8.GetBytes(('blob {0}' -f $bytes.Length) + [char]0)
    $input = [byte[]]::new($header.Length + $bytes.Length)
    [Buffer]::BlockCopy($header, 0, $input, 0, $header.Length)
    [Buffer]::BlockCopy($bytes, 0, $input, $header.Length, $bytes.Length)
    $algorithm = [Security.Cryptography.SHA1]::Create()
    try { [Convert]::ToHexString($algorithm.ComputeHash($input)).ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Assert-KaronPackageGuiContract {
    param(
        [object] $Lock,
        [string] $SummaryPath,
        [string] $ManifestPath,
        [Collections.Generic.Dictionary[string, object]] $CandidateEntries
    )
    $summaryRecord = Get-KaronPackageBoundRecord $Lock 'guiValidationSummary'
    $manifestRecord = Get-KaronPackageBoundRecord $Lock 'guiValidationEvidenceManifest'
    Assert-KaronPackageBoundFile $summaryRecord $SummaryPath 'gui-validation-summary.json' 'package_gui_summary_mismatch'
    Assert-KaronPackageBoundFile $manifestRecord $ManifestPath 'gui-validation-evidence-manifest.json' 'package_gui_manifest_mismatch'
    if (-not $CandidateEntries.ContainsKey('ytdlp-interface.exe') -or -not $CandidateEntries.ContainsKey('ffprobe.exe')) {
        throw 'package_candidate_runtime_missing'
    }
    $summary = ConvertFrom-KaronPackageJsonStrict ([IO.File]::ReadAllText($SummaryPath, [Text.UTF8Encoding]::new($false, $true))) 'package_gui_summary_invalid'
    $manifest = ConvertFrom-KaronPackageJsonStrict ([IO.File]::ReadAllText($ManifestPath, [Text.UTF8Encoding]::new($false, $true))) 'package_gui_manifest_invalid'
    Assert-KaronPackageRawExactKeys $summary.Raw @('schemaVersion', 'tag', 'status', 'blockers', 'candidate', 'cases') 'package_gui_summary_invalid'
    Assert-KaronPackageRawExactKeys $manifest.Raw @('schemaVersion', 'tag', 'status', 'blockers', 'candidate', 'cases') 'package_gui_manifest_invalid'
    if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $summary.Raw 'schemaVersion' 'package_gui_summary_invalid') 'package_gui_summary_invalid') -cne 'karon-gui-validation-summary/v1' -or
        (Get-KaronPackageRawString (Get-KaronPackageRawProperty $manifest.Raw 'schemaVersion' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid') -cne 'karon-gui-validation-evidence-manifest/v1') {
        throw 'package_gui_schema_invalid'
    }
    foreach ($item in @(
        [pscustomobject]@{ Raw = $summary.Raw; ErrorId = 'package_gui_summary_invalid' },
        [pscustomobject]@{ Raw = $manifest.Raw; ErrorId = 'package_gui_manifest_invalid' }
    )) {
        if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $item.Raw 'tag' $item.ErrorId) $item.ErrorId) -cne $script:KaronPackageTag) {
            throw $item.ErrorId
        }
        Assert-KaronPackageRawStatus $item.Raw 'status' $item.ErrorId
        $candidate = Get-KaronPackageRawProperty $item.Raw 'candidate' $item.ErrorId
        Assert-KaronPackageRawExactKeys $candidate @('fileName', 'length', 'sha256') $item.ErrorId
        $fileName = Get-KaronPackageRawString (Get-KaronPackageRawProperty $candidate 'fileName' $item.ErrorId) $item.ErrorId
        $length = Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $candidate 'length' $item.ErrorId) $item.ErrorId
        $sha256 = Get-KaronPackageRawString (Get-KaronPackageRawProperty $candidate 'sha256' $item.ErrorId) $item.ErrorId
        if ($fileName -cne 'ytdlp-interface.exe' -or $length -ne $CandidateEntries['ytdlp-interface.exe'].Length -or
            $sha256.ToLowerInvariant() -cne $CandidateEntries['ytdlp-interface.exe'].Sha256) { throw 'package_gui_candidate_mismatch' }
    }
    $summaryCases = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $summary.Raw 'cases' 'package_gui_summary_invalid') 'package_gui_summary_invalid')
    $manifestCases = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $manifest.Raw 'cases' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid')
    if ($summaryCases.Count -ne 6 -or $manifestCases.Count -ne 6) { throw 'package_gui_case_inventory_invalid' }
    $evidenceRoot = Split-Path -Parent ([IO.Path]::GetFullPath($ManifestPath))
    $seenArtifacts = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    for ($index = 0; $index -lt 6; $index++) {
        $expected = $script:KaronPackageGuiCases[$index]
        $summaryCase = $summaryCases[$index]
        Assert-KaronPackageRawExactKeys $summaryCase @('id', 'language', 'dpiPercent', 'status', 'evidenceId') 'package_gui_summary_invalid'
        if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $summaryCase 'id' 'package_gui_summary_invalid') 'package_gui_summary_invalid') -cne $expected.Id -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $summaryCase 'language' 'package_gui_summary_invalid') 'package_gui_summary_invalid') -cne $expected.Language -or
            (Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $summaryCase 'dpiPercent' 'package_gui_summary_invalid') 'package_gui_summary_invalid') -ne $expected.Dpi -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $summaryCase 'status' 'package_gui_summary_invalid') 'package_gui_summary_invalid') -cne 'verified' -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $summaryCase 'evidenceId' 'package_gui_summary_invalid') 'package_gui_summary_invalid') -cne $expected.Id) {
            throw 'package_gui_case_inventory_invalid'
        }
        $manifestCase = $manifestCases[$index]
        Assert-KaronPackageRawExactKeys $manifestCase @('id', 'status', 'artifacts') 'package_gui_manifest_invalid'
        if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $manifestCase 'id' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid') -cne $expected.Id -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $manifestCase 'status' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid') -cne 'verified') {
            throw 'package_gui_case_inventory_invalid'
        }
        $artifacts = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $manifestCase 'artifacts' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid')
        if ($artifacts.Count -eq 0) { throw 'package_gui_evidence_missing' }
        foreach ($artifact in $artifacts) {
            Assert-KaronPackageRawExactKeys $artifact @('path', 'length', 'sha256') 'package_gui_manifest_invalid'
            $relative = Get-KaronPackageRawString (Get-KaronPackageRawProperty $artifact 'path' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid'
            Assert-KaronPackageRelativePath $relative 'package_gui_manifest_invalid'
            if (-not $seenArtifacts.Add($relative)) { throw 'package_gui_manifest_invalid' }
            $record = [pscustomobject]@{
                Name = $relative
                Length = Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $artifact 'length' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid'
                Sha256 = (Get-KaronPackageRawString (Get-KaronPackageRawProperty $artifact 'sha256' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid').ToLowerInvariant()
            }
            $artifactPath = Get-KaronPackageChildPath $evidenceRoot $relative 'package_gui_manifest_invalid'
            Assert-KaronPackageBoundFile $record $artifactPath $relative 'package_gui_evidence_mismatch'
        }
    }
}

function Assert-KaronPackageSourcesContract {
    param([object] $Lock, [string] $Path, [string] $RootNoticePath)
    $bound = Get-KaronPackageBoundRecord $Lock 'correspondingSources'
    Assert-KaronPackageBoundFile $bound $Path $script:KaronPackageSourcesName 'package_sources_lock_mismatch'
    Add-Type -AssemblyName System.IO.Compression
    $prefix = 'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources/'
    try {
        $stream = [IO.File]::OpenRead($Path)
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $false)
    }
    catch { throw 'package_sources_zip_invalid' }
    try {
        $entries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $zip.Entries) {
            Assert-KaronPackageRelativePath $entry.FullName 'package_sources_structure_invalid'
            if (-not $entry.FullName.StartsWith($prefix, [StringComparison]::Ordinal) -or $entry.Length -le 0 -or
                -not $entries.TryAdd($entry.FullName, $entry)) { throw 'package_sources_structure_invalid' }
        }
        $innerLockName = $prefix + 'release/dependencies/v2.19.1-karon.2.lock.json'
        $innerNoticeName = $prefix + 'THIRD-PARTY-NOTICES.txt'
        if (-not $entries.ContainsKey($innerLockName) -or -not $entries.ContainsKey($innerNoticeName)) { throw 'package_sources_manifest_missing' }
        $reader = [IO.StreamReader]::new($entries[$innerLockName].Open(), [Text.UTF8Encoding]::new($false, $true))
        try { $innerJson = ConvertFrom-KaronPackageJsonStrict $reader.ReadToEnd() 'package_sources_manifest_invalid' }
        finally { $reader.Dispose() }
        Assert-KaronPackageLockRawContract $innerJson.Raw $false 'package_sources_manifest_invalid'
        $inner = $innerJson.Value
        if ([string]$inner.release.metadataPackage.sourceCommit -cne [string]$Lock.release.metadataPackage.sourceCommit -or
            @($inner.release.candidateFiles).Count -ne @($Lock.release.candidateFiles).Count -or
            @($inner.components).Count -ne @($Lock.components).Count) { throw 'package_sources_manifest_mismatch' }
        $expected = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
        $expected.Add($innerLockName, '')
        $expected.Add($innerNoticeName, (Get-KaronPackageSha256 $RootNoticePath))
        foreach ($component in @($inner.components)) {
            foreach ($notice in @($component.noticeFiles)) { $expected.Add($prefix + [string]$notice.path, ([string]$notice.sha256).ToLowerInvariant()) }
            foreach ($archive in @($component.sourceArchives)) {
                $expected.Add($prefix + 'sources/' + [string]$component.id + '/' + [string]$archive.fileName, ([string]$archive.sha256).ToLowerInvariant())
            }
        }
        if ($entries.Count -ne $expected.Count) { throw 'package_sources_structure_invalid' }
        foreach ($name in $entries.Keys) {
            if (-not $expected.ContainsKey($name)) { throw 'package_sources_structure_invalid' }
            if ($name -ceq $innerLockName) { continue }
            $entryStream = $entries[$name].Open()
            try { $hash = Get-KaronPackageStreamSha256 $entryStream }
            finally { $entryStream.Dispose() }
            if ($hash -cne $expected[$name]) { throw 'package_sources_entry_hash_mismatch' }
        }
    }
    finally {
        $zip.Dispose()
        $stream.Dispose()
    }
}

function Assert-KaronPackageSpdxContract {
    param([object] $Lock, [string] $Path)
    $bound = Get-KaronPackageBoundRecord $Lock 'spdx'
    Assert-KaronPackageBoundFile $bound $Path $script:KaronPackageSpdxName 'package_spdx_lock_mismatch'
    $json = ConvertFrom-KaronPackageJsonStrict ([IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))) 'package_spdx_invalid'
    foreach ($contract in @(
        [pscustomobject]@{ Name = 'spdxVersion'; Value = 'SPDX-2.3' },
        [pscustomobject]@{ Name = 'dataLicense'; Value = 'CC0-1.0' },
        [pscustomobject]@{ Name = 'SPDXID'; Value = 'SPDXRef-DOCUMENT' },
        [pscustomobject]@{ Name = 'name'; Value = 'ytdlp-korean-interface-v2.19.1-karon.2-win-x64' }
    )) {
        if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $json.Raw $contract.Name 'package_spdx_invalid') 'package_spdx_invalid') -cne $contract.Value) {
            throw 'package_spdx_identity_invalid'
        }
    }
    $namespace = Get-KaronPackageRawString (Get-KaronPackageRawProperty $json.Raw 'documentNamespace' 'package_spdx_invalid') 'package_spdx_invalid'
    if ($namespace -notmatch '^https://github\.com/KaronLabs/ytdlp-korean-interface/spdx/v2\.19\.1-karon\.2/[a-fA-F0-9]{64}$') {
        throw 'package_spdx_identity_invalid'
    }
    $expectedPackages = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($component in @($Lock.components)) {
        $expectedPackages.Add('SPDXRef-Package-' + [string]$component.id, [pscustomobject]@{ Name = [string]$component.name; Version = [string]$component.version })
    }
    $metadata = $Lock.release.metadataPackage
    $expectedPackages.Add('SPDXRef-Package-' + [string]$metadata.id, [pscustomobject]@{ Name = [string]$metadata.name; Version = [string]$metadata.version })
    $packages = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $json.Raw 'packages' 'package_spdx_invalid') 'package_spdx_invalid')
    if ($packages.Count -ne $expectedPackages.Count) { throw 'package_spdx_package_inventory_invalid' }
    $seenPackages = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($package in $packages) {
        $id = Get-KaronPackageRawString (Get-KaronPackageRawProperty $package 'SPDXID' 'package_spdx_invalid') 'package_spdx_invalid'
        $name = Get-KaronPackageRawString (Get-KaronPackageRawProperty $package 'name' 'package_spdx_invalid') 'package_spdx_invalid'
        $version = Get-KaronPackageRawString (Get-KaronPackageRawProperty $package 'versionInfo' 'package_spdx_invalid') 'package_spdx_invalid'
        if (-not $seenPackages.Add($id) -or -not $expectedPackages.ContainsKey($id) -or
            $expectedPackages[$id].Name -cne $name -or $expectedPackages[$id].Version -cne $version) { throw 'package_spdx_package_inventory_invalid' }
    }
    $described = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($item in Get-KaronPackageRawArray (Get-KaronPackageRawProperty $json.Raw 'documentDescribes' 'package_spdx_invalid') 'package_spdx_invalid') {
        if (-not $described.Add((Get-KaronPackageRawString $item 'package_spdx_invalid'))) { throw 'package_spdx_package_inventory_invalid' }
    }
    if ($described.Count -ne $expectedPackages.Count) { throw 'package_spdx_package_inventory_invalid' }
    foreach ($id in $expectedPackages.Keys) {
        if (-not $described.Contains($id)) { throw 'package_spdx_package_inventory_invalid' }
    }
    $expectedFiles = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in @($Lock.release.candidateFiles)) { $expectedFiles.Add([string]$candidate.path, ([string]$candidate.sha256).ToLowerInvariant()) }
    $files = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $json.Raw 'files' 'package_spdx_invalid') 'package_spdx_invalid')
    if ($files.Count -ne $expectedFiles.Count) { throw 'package_spdx_file_inventory_invalid' }
    $seenFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $files) {
        $name = Get-KaronPackageRawString (Get-KaronPackageRawProperty $file 'fileName' 'package_spdx_invalid') 'package_spdx_invalid'
        if (-not $name.StartsWith('./', [StringComparison]::Ordinal)) { throw 'package_spdx_file_inventory_invalid' }
        $relative = $name.Substring(2)
        if (-not $seenFiles.Add($relative) -or -not $expectedFiles.ContainsKey($relative)) { throw 'package_spdx_file_inventory_invalid' }
        $hashes = @()
        foreach ($checksum in Get-KaronPackageRawArray (Get-KaronPackageRawProperty $file 'checksums' 'package_spdx_invalid') 'package_spdx_invalid') {
            if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $checksum 'algorithm' 'package_spdx_invalid') 'package_spdx_invalid') -ceq 'SHA256') {
                $hashes += Get-KaronPackageRawString (Get-KaronPackageRawProperty $checksum 'checksumValue' 'package_spdx_invalid') 'package_spdx_invalid'
            }
        }
        if ($hashes.Count -ne 1 -or $hashes[0].ToLowerInvariant() -cne $expectedFiles[$relative]) { throw 'package_spdx_file_hash_mismatch' }
    }
}

function Write-KaronPackageAtomicJson {
    param([string] $Path, [object] $Value)
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent) }
    $parentItem = Get-Item -LiteralPath $parent -Force
    if (-not $parentItem.PSIsContainer -or ($parentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'package_receipt_location_invalid'
    }
    $partial = $Path + '.' + $PID + '.' + [Guid]::NewGuid().ToString('N') + '.partial'
    try {
        [IO.File]::WriteAllText($partial, (($Value | ConvertTo-Json -Depth 64) + [char]10), [Text.UTF8Encoding]::new($false))
        Move-KaronPackageOwnedArtifact $partial $Path
    }
    finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    }
}

function New-KaronPackageLocalRecord {
    param([string] $Path, [string] $FileName)
    $item = Get-Item -LiteralPath $Path
    [ordered]@{ localPath = [IO.Path]::GetFullPath($Path); fileName = $FileName; length = [long]$item.Length; sha256 = Get-KaronPackageSha256 $Path }
}

function Get-KaronPackagePublicInventory {
    param([string] $AssetDirectory)
    $names = @($script:KaronPackageBinaryName, $script:KaronPackageSourcesName, $script:KaronPackageSpdxName, $script:KaronPackageSumsName)
    $files = @(Get-ChildItem -LiteralPath $AssetDirectory -File -Force)
    if ($files.Count -ne 4) { throw 'package_final_inventory_invalid' }
    $result = @()
    foreach ($name in $names) {
        $path = Join-Path $AssetDirectory $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'package_final_inventory_invalid' }
        $item = Get-Item -LiteralPath $path
        $result += [ordered]@{ fileName = $name; length = [long]$item.Length; sha256 = Get-KaronPackageSha256 $path }
    }
    $result
}

function Assert-KaronReleaseReceipt {
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $AssetDirectory,
        [Parameter(Mandatory)] [string] $ReceiptPath
    )
    $repo = [IO.Path]::GetFullPath($RepositoryRoot)
    $assets = [IO.Path]::GetFullPath($AssetDirectory)
    $receipt = [IO.Path]::GetFullPath($ReceiptPath)
    if ([IO.Path]::GetFileName($receipt) -cne 'release-receipt.json' -or
        (Split-Path -Parent $receipt) -ieq $assets) { throw 'package_receipt_location_invalid' }
    $json = ConvertFrom-KaronPackageJsonStrict ([IO.File]::ReadAllText($receipt, [Text.UTF8Encoding]::new($false, $true))) 'package_receipt_invalid'
    Assert-KaronPackageRawExactKeys $json.Raw @(
        'schemaVersion', 'tag', 'platform', 'sourceCommit', 'candidateManifest', 'application', 'ffprobe',
        'guiValidationSummary', 'guiValidationEvidenceManifest', 'licenseLock', 'rootThirdPartyNotices',
        'correspondingSources', 'spdx', 'releaseNotes', 'guiCaseIds', 'publicAssets'
    ) 'package_receipt_invalid'
    if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $json.Raw 'schemaVersion' 'package_receipt_invalid') 'package_receipt_invalid') -cne 'karon-release-receipt/v1' -or
        (Get-KaronPackageRawString (Get-KaronPackageRawProperty $json.Raw 'tag' 'package_receipt_invalid') 'package_receipt_invalid') -cne $script:KaronPackageTag) {
        throw 'package_receipt_invalid'
    }
    $value = $json.Value
    $records = @('candidateManifest', 'application', 'ffprobe', 'guiValidationSummary', 'guiValidationEvidenceManifest', 'licenseLock', 'rootThirdPartyNotices', 'correspondingSources', 'spdx')
    foreach ($name in $records) {
        $rawRecord = Get-KaronPackageRawProperty $json.Raw $name 'package_receipt_invalid'
        Assert-KaronPackageRawExactKeys $rawRecord @('localPath', 'fileName', 'length', 'sha256') 'package_receipt_invalid'
        $record = [pscustomobject]@{ Name = [string]$value.$name.fileName; Length = [long]$value.$name.length; Sha256 = ([string]$value.$name.sha256).ToLowerInvariant() }
        Assert-KaronPackageBoundFile $record ([string]$value.$name.localPath) $record.Name 'package_receipt_tampered'
    }
    $notesRaw = Get-KaronPackageRawProperty $json.Raw 'releaseNotes' 'package_receipt_invalid'
    Assert-KaronPackageRawExactKeys $notesRaw @('repositoryPath', 'localPath', 'length', 'sha256', 'gitBlobSha1') 'package_receipt_invalid'
    $notesPath = [IO.Path]::GetFullPath((Join-Path $repo 'release\notes\v2.19.1-karon.2.md'))
    if ([string]$value.releaseNotes.repositoryPath -cne 'release/notes/v2.19.1-karon.2.md' -or
        [IO.Path]::GetFullPath([string]$value.releaseNotes.localPath) -cne $notesPath -or
        [long]$value.releaseNotes.length -ne (Get-Item -LiteralPath $notesPath).Length -or
        ([string]$value.releaseNotes.sha256).ToLowerInvariant() -cne (Get-KaronPackageSha256 $notesPath) -or
        ([string]$value.releaseNotes.gitBlobSha1).ToLowerInvariant() -cne (Get-KaronPackageGitBlobSha1 $notesPath)) {
        throw 'package_receipt_notes_mismatch'
    }
    $lockPath = [string]$value.licenseLock.localPath
    $lock = Read-KaronPackageStrictLock $lockPath
    Assert-KaronPackageStatusContract $lock
    if (([string]$lock.release.metadataPackage.sourceCommit).ToLowerInvariant() -cne ([string]$value.sourceCommit).ToLowerInvariant()) {
        throw 'package_receipt_source_mismatch'
    }
    $candidateRoot = Split-Path -Parent ([string]$value.candidateManifest.localPath)
    $candidateEntries = Get-KaronPackageCandidateEntries $lock $candidateRoot
    if ($candidateEntries['ytdlp-interface.exe'].Sha256 -cne ([string]$value.application.sha256).ToLowerInvariant() -or
        $candidateEntries['ffprobe.exe'].Sha256 -cne ([string]$value.ffprobe.sha256).ToLowerInvariant()) { throw 'package_receipt_candidate_mismatch' }
    Assert-KaronPackageGuiContract $lock ([string]$value.guiValidationSummary.localPath) ([string]$value.guiValidationEvidenceManifest.localPath) $candidateEntries
    Assert-KaronPackageSourcesContract $lock ([string]$value.correspondingSources.localPath) ([string]$value.rootThirdPartyNotices.localPath)
    Assert-KaronPackageSpdxContract $lock ([string]$value.spdx.localPath)
    $caseIds = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $json.Raw 'guiCaseIds' 'package_receipt_invalid') 'package_receipt_invalid')
    if ($caseIds.Count -ne 6) { throw 'package_receipt_gui_cases_invalid' }
    for ($index = 0; $index -lt 6; $index++) {
        if ((Get-KaronPackageRawString $caseIds[$index] 'package_receipt_invalid') -cne $script:KaronPackageGuiCases[$index].Id) {
            throw 'package_receipt_gui_cases_invalid'
        }
    }
    $public = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $json.Raw 'publicAssets' 'package_receipt_invalid') 'package_receipt_invalid')
    $actualPublic = Get-KaronPackagePublicInventory $assets
    if ($public.Count -ne 4) { throw 'package_receipt_assets_invalid' }
    for ($index = 0; $index -lt 4; $index++) {
        $record = $public[$index]
        Assert-KaronPackageRawExactKeys $record @('fileName', 'length', 'sha256') 'package_receipt_assets_invalid'
        if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $record 'fileName' 'package_receipt_assets_invalid') 'package_receipt_assets_invalid') -cne [string]$actualPublic[$index].fileName -or
            (Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $record 'length' 'package_receipt_assets_invalid') 'package_receipt_assets_invalid') -ne [long]$actualPublic[$index].length -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $record 'sha256' 'package_receipt_assets_invalid') 'package_receipt_assets_invalid').ToLowerInvariant() -cne [string]$actualPublic[$index].sha256) {
            throw 'package_receipt_assets_mismatch'
        }
    }
    [pscustomobject]@{
        SourceCommit = ([string]$value.sourceCommit).ToLowerInvariant()
        NotesPath = $notesPath
        NotesBlobSha1 = ([string]$value.releaseNotes.gitBlobSha1).ToLowerInvariant()
        ReceiptSha256 = Get-KaronPackageSha256 $receipt
        AssetPaths = @($actualPublic | ForEach-Object { Join-Path $assets $_.fileName })
    }
}

function Invoke-QualityReleasePackageCore {
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

function Invoke-QualityReleasePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $CandidateDirectory,
        [Parameter(Mandatory)] [string] $LockPath,
        [Parameter(Mandatory)] [string] $CorrespondingSourcesPath,
        [Parameter(Mandatory)] [string] $SpdxPath,
        [string] $GuiValidationSummaryPath = $script:KaronPackageCliGuiSummaryPath,
        [string] $GuiValidationEvidenceManifestPath = $script:KaronPackageCliGuiManifestPath,
        [Parameter(Mandatory)] [string] $OutputDirectory,
        [string] $ReceiptPath = $script:KaronPackageCliReceiptPath,
        [switch] $PlanOnly
    )
    if ([string]::IsNullOrWhiteSpace($GuiValidationSummaryPath) -or
        [string]::IsNullOrWhiteSpace($GuiValidationEvidenceManifestPath) -or
        [string]::IsNullOrWhiteSpace($ReceiptPath)) { throw 'package_evidence_input_missing' }
    $repo = [IO.Path]::GetFullPath($RepositoryRoot)
    $candidateRoot = [IO.Path]::GetFullPath($CandidateDirectory)
    $outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
    $receipt = [IO.Path]::GetFullPath($ReceiptPath)
    if ([IO.Path]::GetFileName($GuiValidationSummaryPath) -cne 'gui-validation-summary.json' -or
        [IO.Path]::GetFileName($GuiValidationEvidenceManifestPath) -cne 'gui-validation-evidence-manifest.json' -or
        [IO.Path]::GetFileName($receipt) -cne 'release-receipt.json' -or
        (Split-Path -Parent $receipt) -ieq $outputRoot) { throw 'package_evidence_input_invalid' }
    if (Test-Path -LiteralPath $receipt) { throw 'package_receipt_exists' }

    $lock = Read-KaronPackageStrictLock $LockPath
    Assert-KaronPackageStatusContract $lock
    $candidateEntries = Get-KaronPackageCandidateEntries $lock $candidateRoot
    $candidateManifestRecord = Get-KaronPackageBoundRecord $lock 'candidateManifest'
    Assert-KaronPackageBoundFile $candidateManifestRecord $candidateEntries['candidate-manifest.json'].SourcePath 'candidate-manifest.json' 'package_candidate_manifest_lock_mismatch'
    Assert-KaronPackageGuiContract $lock $GuiValidationSummaryPath $GuiValidationEvidenceManifestPath $candidateEntries
    $rootNoticePath = Join-Path $repo 'THIRD-PARTY-NOTICES.txt'
    $rootNoticeRecord = Get-KaronPackageBoundRecord $lock 'rootThirdPartyNotices'
    Assert-KaronPackageBoundFile $rootNoticeRecord $rootNoticePath 'THIRD-PARTY-NOTICES.txt' 'package_root_notice_lock_mismatch'
    Assert-KaronPackageSourcesContract $lock $CorrespondingSourcesPath $rootNoticePath
    Assert-KaronPackageSpdxContract $lock $SpdxPath
    $notesPath = [IO.Path]::GetFullPath((Join-Path $repo 'release\notes\v2.19.1-karon.2.md'))
    $notesRecord = Get-KaronPackageBoundRecord $lock 'releaseNotes' 'path'
    Assert-KaronPackageBoundFile $notesRecord $notesPath 'release/notes/v2.19.1-karon.2.md' 'package_release_notes_lock_mismatch'

    $coreResult = Invoke-QualityReleasePackageCore -RepositoryRoot $repo -CandidateDirectory $candidateRoot -LockPath $LockPath -CorrespondingSourcesPath $CorrespondingSourcesPath -SpdxPath $SpdxPath -OutputDirectory $outputRoot -PlanOnly:$PlanOnly
    if ($PlanOnly) {
        return [pscustomobject]@{
            Mode = 'plan'
            AssetPaths = @($coreResult.AssetPaths)
            ZipEntries = @($coreResult.ZipEntries)
            ReceiptPath = $receipt
            GuiCases = @($script:KaronPackageGuiCases | ForEach-Object Id)
        }
    }

    $sourcesFinal = Join-Path $outputRoot $script:KaronPackageSourcesName
    $spdxFinal = Join-Path $outputRoot $script:KaronPackageSpdxName
    $receiptValue = [ordered]@{
        schemaVersion = 'karon-release-receipt/v1'
        tag = $script:KaronPackageTag
        platform = 'win-x64'
        sourceCommit = ([string]$lock.release.metadataPackage.sourceCommit).ToLowerInvariant()
        candidateManifest = New-KaronPackageLocalRecord $candidateEntries['candidate-manifest.json'].SourcePath 'candidate-manifest.json'
        application = New-KaronPackageLocalRecord $candidateEntries['ytdlp-interface.exe'].SourcePath 'ytdlp-interface.exe'
        ffprobe = New-KaronPackageLocalRecord $candidateEntries['ffprobe.exe'].SourcePath 'ffprobe.exe'
        guiValidationSummary = New-KaronPackageLocalRecord $GuiValidationSummaryPath 'gui-validation-summary.json'
        guiValidationEvidenceManifest = New-KaronPackageLocalRecord $GuiValidationEvidenceManifestPath 'gui-validation-evidence-manifest.json'
        licenseLock = New-KaronPackageLocalRecord $LockPath ([IO.Path]::GetFileName($LockPath))
        rootThirdPartyNotices = New-KaronPackageLocalRecord $rootNoticePath 'THIRD-PARTY-NOTICES.txt'
        correspondingSources = New-KaronPackageLocalRecord $sourcesFinal $script:KaronPackageSourcesName
        spdx = New-KaronPackageLocalRecord $spdxFinal $script:KaronPackageSpdxName
        releaseNotes = [ordered]@{
            repositoryPath = 'release/notes/v2.19.1-karon.2.md'
            localPath = $notesPath
            length = [long](Get-Item -LiteralPath $notesPath).Length
            sha256 = Get-KaronPackageSha256 $notesPath
            gitBlobSha1 = Get-KaronPackageGitBlobSha1 $notesPath
        }
        guiCaseIds = @($script:KaronPackageGuiCases | ForEach-Object Id)
        publicAssets = @(Get-KaronPackagePublicInventory $outputRoot)
    }
    Write-KaronPackageAtomicJson $receipt $receiptValue
    $validated = Assert-KaronReleaseReceipt $repo $outputRoot $receipt
    [pscustomobject]@{
        Mode = 'packaged'
        AssetPaths = @($validated.AssetPaths)
        ZipEntries = @($coreResult.ZipEntries)
        ReceiptPath = $receipt
        ReceiptSha256 = $validated.ReceiptSha256
    }
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
