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
$script:KaronPackageGuiSchemaRepositoryPath = 'release/validation/v2.19.1-karon.2/gui-validation-output.schema.json'
$script:KaronPackageCliGuiSummaryPath = $GuiValidationSummaryPath
$script:KaronPackageCliGuiManifestPath = $GuiValidationEvidenceManifestPath
$script:KaronPackageCliReceiptPath = $ReceiptPath
$script:KaronPackageGuiCases = @(
    [pscustomobject]@{ Id = 'ko-KR-100'; Language = 'ko-KR'; Dpi = 100 },
    [pscustomobject]@{ Id = 'ko-KR-150'; Language = 'ko-KR'; Dpi = 150 },
    [pscustomobject]@{ Id = 'ko-KR-200'; Language = 'ko-KR'; Dpi = 200 },
    [pscustomobject]@{ Id = 'en-US-100'; Language = 'en-US'; Dpi = 100 },
    [pscustomobject]@{ Id = 'en-US-150'; Language = 'en-US'; Dpi = 150 },
    [pscustomobject]@{ Id = 'en-US-200'; Language = 'en-US'; Dpi = 200 }
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

function Assert-KaronPackagePathChain {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $ErrorId = 'package_path_reparse_point'
    )
    try {
        $full = [IO.Path]::GetFullPath($Path)
        $root = [IO.Path]::GetPathRoot($full)
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) { throw $ErrorId }
        $current = $root
        $rootItem = Get-Item -LiteralPath $current -Force
        if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw $ErrorId }
        $relative = $full.Substring($root.Length).TrimStart([char[]]@('\', '/'))
        if (-not [string]::IsNullOrEmpty($relative)) {
            foreach ($part in $relative.Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries)) {
                $current = Join-Path $current $part
                if (-not (Test-Path -LiteralPath $current)) { break }
                $item = Get-Item -LiteralPath $current -Force
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw $ErrorId }
            }
        }
        $full
    }
    catch {
        if ($_.Exception.Message -ceq $ErrorId) { throw }
        throw $ErrorId
    }
}

function Invoke-KaronPackageGit {
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [string] $ErrorId
    )
    $output = @(& git -C $RepositoryRoot @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ($ErrorId + ': ' + (($output | Out-String).Trim())) }
    (($output | Out-String).Trim())
}

function Get-KaronPackageRepositoryHead {
    param([Parameter(Mandatory)] [string] $RepositoryRoot)
    $root = Assert-KaronPackagePathChain $RepositoryRoot
    $actualRoot = Invoke-KaronPackageGit $root @('rev-parse', '--show-toplevel') 'package_repository_invalid'
    if (-not [IO.Path]::GetFullPath($actualRoot).Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'package_repository_invalid'
    }
    $head = Invoke-KaronPackageGit $root @('rev-parse', '--verify', 'HEAD^{commit}') 'package_repository_head_invalid'
    if ($head -notmatch '^[a-fA-F0-9]{40}$') { throw 'package_repository_head_invalid' }
    $head.ToLowerInvariant()
}

function Get-KaronPackageTrackedFileRecord {
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $RepositoryPath,
        [Parameter(Mandatory)] [string] $FileName,
        [string] $ErrorId = 'package_tracked_blob_mismatch'
    )
    Assert-KaronPackageRelativePath $RepositoryPath 'package_tracked_path_invalid'
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $path = [IO.Path]::GetFullPath((Join-Path $root ($RepositoryPath.Replace('/', [IO.Path]::DirectorySeparatorChar))))
    [void](Assert-KaronPackagePathChain $path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw $ErrorId }
    $tree = Invoke-KaronPackageGit $root @('ls-tree', 'HEAD', '--', $RepositoryPath) $ErrorId
    $match = [regex]::Match($tree, '^(100644|100755)\s+blob\s+([a-fA-F0-9]{40})\s+(.+)$')
    if (-not $match.Success -or $match.Groups[3].Value -cne $RepositoryPath) { throw $ErrorId }
    $blob = Invoke-KaronPackageGit $root @('hash-object', ('--path=' + $RepositoryPath), $path) $ErrorId
    if ($blob -notmatch '^[a-fA-F0-9]{40}$') { throw $ErrorId }
    $blob = $blob.ToLowerInvariant()
    if ($blob -cne $match.Groups[2].Value.ToLowerInvariant()) { throw $ErrorId }
    $item = Get-Item -LiteralPath $path -Force
    [ordered]@{
        repositoryPath = $RepositoryPath
        localPath = $path
        fileName = $FileName
        length = [long]$item.Length
        sha256 = Get-KaronPackageSha256 $path
        gitBlobSha1 = $blob
    }
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

    $rootPath = Assert-KaronPackagePathChain $Root
    if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) { throw ($ErrorPrefix + '_root_missing') }
    $rootItem = Get-Item -LiteralPath $rootPath -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ($ErrorPrefix + '_reparse_point') }

    $byPath = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($rootPath)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            [void](Assert-KaronPackagePathChain $item.FullName)
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
    $manifestDocument = ConvertFrom-KaronPackageJsonStrict ([IO.File]::ReadAllText($manifestPath, [Text.UTF8Encoding]::new($false, $true))) 'package_candidate_manifest_invalid'
    $manifest = $manifestDocument.Value
    if ($manifest.schemaVersion -ne 1 -or -not (Test-KaronPackageProperty $manifest 'files')) {
        throw 'package_candidate_manifest_invalid'
    }
    $applicationSourceCommit = Get-KaronPackageRawString (Get-KaronPackageRawProperty $manifestDocument.Raw 'applicationSourceCommit' 'package_candidate_manifest_invalid') 'package_candidate_manifest_invalid'
    if ($applicationSourceCommit -notmatch '^[a-fA-F0-9]{40}$') { throw 'package_candidate_manifest_invalid' }
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
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    [void](Assert-KaronPackagePathChain $tempRoot)
    $snapshotRoot = Join-Path $tempRoot ('karon-package-snapshot-' + [Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $snapshotRoot)
    [void](Assert-KaronPackagePathChain $snapshotRoot)
    try {
        $sealedEntries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        $index = 0
        foreach ($name in @(Get-KaronPackageSortedNames $Entries)) {
            $source = $Entries[$name]
            $snapshotPath = Join-Path $snapshotRoot (('{0:d8}.bin' -f $index))
            [IO.File]::Copy([string]$source.SourcePath, $snapshotPath, $false)
            $snapshotItem = Get-Item -LiteralPath $snapshotPath -Force
            if ([long]$snapshotItem.Length -ne [long]$source.Length -or
                (Get-KaronPackageSha256 $snapshotPath) -cne [string]$source.Sha256 -or
                (Get-KaronPackageSha256 $source.SourcePath) -cne [string]$source.Sha256) {
                throw 'package_input_changed'
            }
            $sealedEntries.Add($name, [pscustomobject]@{
                EntryName = $name
                SourcePath = $snapshotPath
                Sha256 = [string]$source.Sha256
                Length = [long]$source.Length
            })
            $index++
        }

        $stream = [IO.File]::Open($PartialPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
            try {
                foreach ($name in @(Get-KaronPackageSortedNames $sealedEntries)) {
                    $input = $sealedEntries[$name]
                    $entry = $zip.CreateEntry($name, [IO.Compression.CompressionLevel]::Optimal)
                    $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                    $inputStream = [IO.File]::Open($input.SourcePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
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
                $expectedNames = @(Get-KaronPackageSortedNames $sealedEntries)
                $actualNames = @($zip.Entries | ForEach-Object FullName)
                if (($actualNames -join "`n") -cne ($expectedNames -join "`n")) { throw 'package_zip_inventory_mismatch' }
                for ($index = 0; $index -lt $zip.Entries.Count; $index++) {
                    $entry = $zip.Entries[$index]
                    $expected = $sealedEntries[$entry.FullName]
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
    finally {
        if (Test-Path -LiteralPath $snapshotRoot) {
            $full = [IO.Path]::GetFullPath($snapshotRoot)
            if ((Split-Path -Parent $full) -cne $tempRoot -or -not ([IO.Path]::GetFileName($full)).StartsWith('karon-package-snapshot-', [StringComparison]::Ordinal)) {
                throw 'package_snapshot_location_invalid'
            }
            Remove-Item -LiteralPath $full -Recurse -Force
        }
    }
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

    if ([string]::IsNullOrWhiteSpace($Path)) { throw $ErrorId }
    [void](Assert-KaronPackagePathChain $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw $ErrorId }
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

    [void](Assert-KaronPackagePathChain $OutputRoot)
    if (-not (Test-Path -LiteralPath $OutputRoot)) { New-Item -ItemType Directory -Path $OutputRoot | Out-Null }
    [void](Assert-KaronPackagePathChain $OutputRoot)
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

function Get-KaronPackageRawBoolean {
    param([Text.Json.JsonElement] $Element, [string] $ErrorId)
    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::True) { return $true }
    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::False) { return $false }
    throw $ErrorId
}

function Test-KaronPackageRawProperty {
    param([Text.Json.JsonElement] $Element, [string] $Name)
    if ($Element.ValueKind -ne [Text.Json.JsonValueKind]::Object) { return $false }
    @($Element.EnumerateObject() | Where-Object { $_.Name -ceq $Name }).Count -eq 1
}

function Write-KaronPackageCanonicalJsonElement {
    param(
        [Parameter(Mandatory)] [Text.Json.Utf8JsonWriter] $Writer,
        [Parameter(Mandatory)] [Text.Json.JsonElement] $Element,
        [Parameter(Mandatory)] [string] $Path
    )
    switch ($Element.ValueKind) {
        ([Text.Json.JsonValueKind]::Object) {
            $Writer.WriteStartObject()
            $names = [string[]]@($Element.EnumerateObject() | ForEach-Object Name)
            [Array]::Sort($names, [StringComparer]::Ordinal)
            foreach ($name in $names) {
                if ($Path -ceq '$.release' -and $name -ceq 'receiptInputs') { continue }
                $Writer.WritePropertyName($name)
                Write-KaronPackageCanonicalJsonElement $Writer (Get-KaronPackageRawProperty $Element $name 'package_lock_projection_invalid') ($Path + '.' + $name)
            }
            $Writer.WriteEndObject()
        }
        ([Text.Json.JsonValueKind]::Array) {
            $Writer.WriteStartArray()
            foreach ($item in $Element.EnumerateArray()) { Write-KaronPackageCanonicalJsonElement $Writer $item ($Path + '[]') }
            $Writer.WriteEndArray()
        }
        ([Text.Json.JsonValueKind]::String) { $Writer.WriteStringValue($Element.GetString()) }
        ([Text.Json.JsonValueKind]::Number) { $Writer.WriteRawValue($Element.GetRawText(), $true) }
        ([Text.Json.JsonValueKind]::True) { $Writer.WriteBooleanValue($true) }
        ([Text.Json.JsonValueKind]::False) { $Writer.WriteBooleanValue($false) }
        ([Text.Json.JsonValueKind]::Null) { $Writer.WriteNullValue() }
        default { throw 'package_lock_projection_invalid' }
    }
}

function Get-KaronPackageLockProjectionSha256 {
    param([Parameter(Mandatory)] [Text.Json.JsonElement] $Root)
    $stream = [IO.MemoryStream]::new()
    $writer = [Text.Json.Utf8JsonWriter]::new($stream, [Text.Json.JsonWriterOptions]@{ Indented = $false })
    try {
        Write-KaronPackageCanonicalJsonElement $writer $Root '$'
        $writer.Flush()
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream.ToArray())).ToLowerInvariant()
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
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
    if ($Root.ValueKind -ne [Text.Json.JsonValueKind]::Object -or
        (Get-KaronPackageRawString (Get-KaronPackageRawProperty $Root 'schemaVersion' $ErrorId) $ErrorId) -cne 'karon-license-lock/v2') { throw $ErrorId }
    $release = Get-KaronPackageRawProperty $Root 'release' $ErrorId
    if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $release 'tag' $ErrorId) $ErrorId) -cne $script:KaronPackageTag -or
        (Get-KaronPackageRawString (Get-KaronPackageRawProperty $release 'platform' $ErrorId) $ErrorId) -cne 'win-x64') { throw $ErrorId }
    Assert-KaronPackageRawStatus $release 'verificationStatus' $ErrorId
    if ((Get-KaronPackageRawProperty $release 'candidateFiles' $ErrorId).ValueKind -ne [Text.Json.JsonValueKind]::Array) { throw $ErrorId }
    foreach ($candidate in Get-KaronPackageRawArray (Get-KaronPackageRawProperty $release 'candidateFiles' $ErrorId) $ErrorId) {
        if ($candidate.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw $ErrorId }
        foreach ($name in @('path', 'sha256', 'package', 'licenseConcluded')) {
            [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $candidate $name $ErrorId) $ErrorId)
        }
    }
    $metadata = Get-KaronPackageRawProperty $release 'metadataPackage' $ErrorId
    foreach ($name in @('id', 'name', 'version', 'licenseExpression', 'licenseConcluded', 'sourceCommit', 'downloadLocation')) {
        [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $metadata $name $ErrorId) $ErrorId)
    }
    if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $metadata 'sourceCommit' $ErrorId) $ErrorId) -notmatch '^[a-fA-F0-9]{40}$') {
        throw $ErrorId
    }
    $components = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $Root 'components' $ErrorId) $ErrorId)
    if ($components.Count -eq 0) { throw $ErrorId }
    foreach ($component in $components) {
        if ($component.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw $ErrorId }
        Assert-KaronPackageRawStatus $component 'verificationStatus' $ErrorId
        foreach ($name in @('id', 'name', 'version', 'sourceRepository', 'sourceCommit', 'licenseExpression', 'buildRecipe', 'licenseConcluded')) {
            [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $component $name $ErrorId) $ErrorId)
        }
        [void](Get-KaronPackageRawBoolean (Get-KaronPackageRawProperty $component 'modified' $ErrorId) $ErrorId)
        [void](Get-KaronPackageRawBoolean (Get-KaronPackageRawProperty $component 'filesAnalyzed' $ErrorId) $ErrorId)
        foreach ($arrayName in @('noticeFiles', 'sourceArchives')) {
            foreach ($item in Get-KaronPackageRawArray (Get-KaronPackageRawProperty $component $arrayName $ErrorId) $ErrorId) {
                if ($item.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw $ErrorId }
                if ($arrayName -ceq 'noticeFiles') {
                    [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $item 'path' $ErrorId) $ErrorId)
                    [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $item 'sha256' $ErrorId) $ErrorId)
                }
                else {
                    Assert-KaronPackageRawStatus $item 'verificationStatus' $ErrorId
                    foreach ($name in @('fileName', 'commit', 'url', 'sha256')) {
                        [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $item $name $ErrorId) $ErrorId)
                    }
                    if ((Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $item 'length' $ErrorId) $ErrorId) -le 0) { throw $ErrorId }
                }
            }
        }
        if (Test-KaronPackageRawProperty $component 'staticLinkTarget') {
            [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $component 'staticLinkTarget' $ErrorId) $ErrorId)
        }
        if (Test-KaronPackageRawProperty $component 'licenseRefs') {
            foreach ($licenseRef in Get-KaronPackageRawArray (Get-KaronPackageRawProperty $component 'licenseRefs' $ErrorId) $ErrorId) {
                foreach ($name in @('licenseId', 'name', 'noticePath')) {
                    [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $licenseRef $name $ErrorId) $ErrorId)
                }
            }
        }
    }
    if ($RequireReceiptInputs) {
        $inputs = Get-KaronPackageRawProperty $release 'receiptInputs' $ErrorId
        Assert-KaronPackageRawExactKeys $inputs @(
            'candidateManifest', 'correspondingSources', 'spdx', 'rootThirdPartyNotices',
            'guiValidationSummary', 'guiValidationEvidenceManifest', 'guiValidationSchema', 'releaseNotes'
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
        $guiSchema = Get-KaronPackageRawProperty $inputs 'guiValidationSchema' $ErrorId
        Assert-KaronPackageRawExactKeys $guiSchema @('path', 'length', 'sha256') $ErrorId
        [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $guiSchema 'path' $ErrorId) $ErrorId)
        if ((Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $guiSchema 'length' $ErrorId) $ErrorId) -le 0 -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $guiSchema 'sha256' $ErrorId) $ErrorId) -notmatch '^[a-fA-F0-9]{64}$') {
            throw $ErrorId
        }
    }
}

function Read-KaronPackageStrictLockDocument {
    param([string] $Path)
    [void](Assert-KaronPackagePathChain $Path)
    $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
    $json = ConvertFrom-KaronPackageJsonStrict $text 'package_lock_invalid'
    Assert-KaronPackageLockRawContract $json.Raw $true 'package_lock_type_invalid'
    $json
}

function Read-KaronPackageStrictLock {
    param([string] $Path)
    (Read-KaronPackageStrictLockDocument $Path).Value
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
    [void](Assert-KaronPackagePathChain $Path)
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

function Get-KaronPackageApplicationProvenance {
    param(
        [Parameter(Mandatory)] [object] $Lock,
        [Parameter(Mandatory)] [Collections.Generic.Dictionary[string, object]] $CandidateEntries,
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $PackagingCommit
    )
    $manifest = ConvertFrom-KaronPackageJsonStrict ([IO.File]::ReadAllText($CandidateEntries['candidate-manifest.json'].SourcePath, [Text.UTF8Encoding]::new($false, $true))) 'package_candidate_manifest_invalid'
    $applicationSourceCommit = Get-KaronPackageRawString (Get-KaronPackageRawProperty $manifest.Raw 'applicationSourceCommit' 'package_candidate_manifest_invalid') 'package_candidate_manifest_invalid'
    if ($applicationSourceCommit -notmatch '^[a-fA-F0-9]{40}$' -or $PackagingCommit -notmatch '^[a-fA-F0-9]{40}$') { throw 'package_application_source_invalid' }
    $applicationSourceCommit = $applicationSourceCommit.ToLowerInvariant()
    $packaging = $PackagingCommit.ToLowerInvariant()
    $applicationComponents = @($Lock.components | Where-Object { [string]$_.id -ceq 'application' })
    if ($applicationComponents.Count -ne 1) { throw 'package_application_source_invalid' }
    $metadataCommit = ([string]$Lock.release.metadataPackage.sourceCommit).ToLowerInvariant()
    $componentCommit = ([string]$applicationComponents[0].sourceCommit).ToLowerInvariant()
    if ($metadataCommit -ceq $packaging -or $componentCommit -ceq $packaging -or $applicationSourceCommit -ceq $packaging) { throw 'package_provenance_self_reference' }
    if ($metadataCommit -cne $applicationSourceCommit -or $componentCommit -cne $applicationSourceCommit) { throw 'package_application_source_mismatch' }
    $resolved = @(& git -C $RepositoryRoot rev-parse --verify ($applicationSourceCommit + '^{commit}') 2>&1)
    if ($LASTEXITCODE -ne 0 -or (($resolved | Out-String).Trim()).ToLowerInvariant() -cne $applicationSourceCommit) { throw 'package_application_source_object_invalid' }
    $null = @(& git -C $RepositoryRoot merge-base --is-ancestor $applicationSourceCommit $packaging 2>&1)
    if ($LASTEXITCODE -eq 1) { throw 'package_application_source_not_ancestor' }
    if ($LASTEXITCODE -ne 0) { throw 'package_application_source_object_invalid' }
    $null = @(& git -C $RepositoryRoot diff --quiet --no-ext-diff --no-textconv $applicationSourceCommit $packaging -- . ':(exclude)release/**' 2>&1)
    if ($LASTEXITCODE -eq 1) { throw 'package_application_source_delta_invalid' }
    if ($LASTEXITCODE -ne 0) { throw 'package_application_source_object_invalid' }
    $treeOutput = @(& git -C $RepositoryRoot rev-parse --verify ($applicationSourceCommit + '^{tree}') 2>&1)
    $applicationSourceTree = (($treeOutput | Out-String).Trim()).ToLowerInvariant()
    if ($LASTEXITCODE -ne 0 -or $applicationSourceTree -notmatch '^[a-f0-9]{40}$') { throw 'package_application_source_object_invalid' }
    [pscustomobject]@{
        ApplicationSourceCommit = $applicationSourceCommit
        ApplicationSourceTree = $applicationSourceTree
        PackagingCommit = $packaging
    }
}

function Get-KaronPackageGuiSchemaContract {
    param([object] $Lock, [string] $RepositoryRoot)
    $record = Get-KaronPackageBoundRecord $Lock 'guiValidationSchema' 'path'
    if ($record.Name -cne $script:KaronPackageGuiSchemaRepositoryPath) { throw 'package_gui_schema_path_invalid' }
    $tracked = Get-KaronPackageTrackedFileRecord $RepositoryRoot $script:KaronPackageGuiSchemaRepositoryPath 'gui-validation-output.schema.json' 'package_gui_schema_untracked'
    if ($tracked.length -ne 11516L -or $tracked.sha256 -cne 'e49cc70253bd5dd4b4abd8ee00406f5dd8ed39434e309e3e3c74694b85c1b80e' -or
        $tracked.length -ne $record.Length -or $tracked.sha256 -cne $record.Sha256) { throw 'package_gui_schema_lock_mismatch' }
    $document = ConvertFrom-KaronPackageJsonStrict ([IO.File]::ReadAllText($tracked.localPath, [Text.UTF8Encoding]::new($false, $true))) 'package_gui_schema_invalid'
    $root = $document.Raw
    if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $root '$schema' 'package_gui_schema_invalid') 'package_gui_schema_invalid') -cne 'https://json-schema.org/draft/2020-12/schema' -or
        (Get-KaronPackageRawString (Get-KaronPackageRawProperty $root '$id' 'package_gui_schema_invalid') 'package_gui_schema_invalid') -cne 'https://github.com/KaronLabs/ytdlp-korean-interface/blob/v2.19.1-karon.2/release/validation/v2.19.1-karon.2/gui-validation-output.schema.json') {
        throw 'package_gui_schema_identity_invalid'
    }
    [pscustomobject]@{ Root = $root; Tracked = $tracked }
}

function Assert-KaronPackageGuiCandidateRecord {
    param([Text.Json.JsonElement] $Record, [string] $ExpectedName, [object] $CandidateEntry)
    Assert-KaronPackageRawExactKeys $Record @('fileName', 'sha256', 'length') 'package_gui_candidate_mismatch'
    if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $Record 'fileName' 'package_gui_candidate_mismatch') 'package_gui_candidate_mismatch') -cne $ExpectedName -or
        (Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $Record 'length' 'package_gui_candidate_mismatch') 'package_gui_candidate_mismatch') -ne $CandidateEntry.Length -or
        (Get-KaronPackageRawString (Get-KaronPackageRawProperty $Record 'sha256' 'package_gui_candidate_mismatch') 'package_gui_candidate_mismatch').ToLowerInvariant() -cne $CandidateEntry.Sha256) {
        throw 'package_gui_candidate_mismatch'
    }
}

function Assert-KaronPackageGuiContract {
    param(
        [object] $Lock,
        [string] $RepositoryRoot,
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
    $schema = Get-KaronPackageGuiSchemaContract $Lock $RepositoryRoot
    $summary = ConvertFrom-KaronPackageJsonStrict ([IO.File]::ReadAllText($SummaryPath, [Text.UTF8Encoding]::new($false, $true))) 'package_gui_summary_invalid'
    $manifest = ConvertFrom-KaronPackageJsonStrict ([IO.File]::ReadAllText($ManifestPath, [Text.UTF8Encoding]::new($false, $true))) 'package_gui_manifest_invalid'
    try {
        if (-not (Test-Json -LiteralPath $SummaryPath -SchemaFile $schema.Tracked.localPath -ErrorAction Stop)) { throw 'invalid' }
    }
    catch { throw 'package_gui_summary_schema_invalid' }
    try {
        if (-not (Test-Json -LiteralPath $ManifestPath -SchemaFile $schema.Tracked.localPath -ErrorAction Stop)) { throw 'invalid' }
    }
    catch { throw 'package_gui_manifest_schema_invalid' }
    $guiRoot = Split-Path -Parent ([IO.Path]::GetFullPath($ManifestPath))
    if ((Split-Path -Parent ([IO.Path]::GetFullPath($SummaryPath))) -cne $guiRoot) { throw 'package_gui_evidence_inventory_invalid' }
    $actualGuiFiles = Get-KaronPackageSafeInventory $guiRoot 'package_gui_evidence'
    $declaredGuiFiles = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$declaredGuiFiles.Add('gui-validation-summary.json', $true)
    [void]$declaredGuiFiles.Add('gui-validation-evidence-manifest.json', $true)
    $summaryCandidate = Get-KaronPackageRawProperty $summary.Raw 'candidate' 'package_gui_summary_invalid'
    $manifestCandidate = Get-KaronPackageRawProperty $manifest.Raw 'candidate' 'package_gui_manifest_invalid'
    if ($summaryCandidate.GetRawText() -cne $manifestCandidate.GetRawText()) { throw 'package_gui_candidate_mismatch' }
    Assert-KaronPackageGuiCandidateRecord (Get-KaronPackageRawProperty $summaryCandidate 'executable' 'package_gui_candidate_mismatch') 'ytdlp-interface.exe' $CandidateEntries['ytdlp-interface.exe']
    Assert-KaronPackageGuiCandidateRecord (Get-KaronPackageRawProperty $summaryCandidate 'ffprobe' 'package_gui_candidate_mismatch') 'ffprobe.exe' $CandidateEntries['ffprobe.exe']
    $candidateManifest = Get-KaronPackageRawProperty $summaryCandidate 'manifest' 'package_gui_candidate_mismatch'
    if ($candidateManifest.ValueKind -ne [Text.Json.JsonValueKind]::Null) {
        if (-not $CandidateEntries.ContainsKey('candidate-manifest.json')) { throw 'package_gui_candidate_mismatch' }
        Assert-KaronPackageGuiCandidateRecord $candidateManifest 'candidate-manifest.json' $CandidateEntries['candidate-manifest.json']
    }

    $manifestFiles = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $manifest.Raw 'evidenceFiles' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid')
    $evidence = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $manifestFiles) {
        Assert-KaronPackageRawExactKeys $file @('path', 'sha256', 'length') 'package_gui_manifest_invalid'
        $relative = Get-KaronPackageRawString (Get-KaronPackageRawProperty $file 'path' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid'
        Assert-KaronPackageRelativePath $relative 'package_gui_manifest_invalid'
        if (-not [string]::Equals($relative.Normalize([Text.NormalizationForm]::FormC), $relative, [StringComparison]::Ordinal) -or $evidence.ContainsKey($relative) -or
            -not $declaredGuiFiles.TryAdd($relative, $true)) { throw 'package_gui_manifest_invalid' }
        $record = [pscustomobject]@{
            Name = $relative
            Sha256 = (Get-KaronPackageRawString (Get-KaronPackageRawProperty $file 'sha256' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid').ToLowerInvariant()
            Length = Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $file 'length' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid'
        }
        Assert-KaronPackageBoundFile $record (Get-KaronPackageChildPath $guiRoot $relative 'package_gui_evidence_invalid') $relative 'package_gui_evidence_mismatch'
        $evidence.Add($relative, $record)
    }
    if ((Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $summary.Raw 'evidenceFileCount' 'package_gui_summary_invalid') 'package_gui_summary_invalid') -ne $evidence.Count) {
        throw 'package_gui_evidence_inventory_invalid'
    }
    $summaryCases = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $summary.Raw 'cases' 'package_gui_summary_invalid') 'package_gui_summary_invalid')
    if ($summaryCases.Count -ne 6) { throw 'package_gui_case_inventory_invalid' }
    for ($index = 0; $index -lt 6; $index++) {
        $expected = $script:KaronPackageGuiCases[$index]
        $summaryCase = $summaryCases[$index]
        Assert-KaronPackageRawExactKeys $summaryCase @('caseId', 'language', 'dpi', 'evidenceFile', 'evidenceSha256') 'package_gui_summary_invalid'
        $evidencePath = Get-KaronPackageRawString (Get-KaronPackageRawProperty $summaryCase 'evidenceFile' 'package_gui_summary_invalid') 'package_gui_summary_invalid'
        if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $summaryCase 'caseId' 'package_gui_summary_invalid') 'package_gui_summary_invalid') -cne $expected.Id -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $summaryCase 'language' 'package_gui_summary_invalid') 'package_gui_summary_invalid') -cne $expected.Language -or
            (Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $summaryCase 'dpi' 'package_gui_summary_invalid') 'package_gui_summary_invalid') -ne $expected.Dpi -or
            -not $evidence.ContainsKey($evidencePath) -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $summaryCase 'evidenceSha256' 'package_gui_summary_invalid') 'package_gui_summary_invalid').ToLowerInvariant() -cne $evidence[$evidencePath].Sha256) {
            throw 'package_gui_case_inventory_invalid'
        }
    }
    $lifecycle = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $summary.Raw 'fullVideoLifecycleCases' 'package_gui_summary_invalid') 'package_gui_summary_invalid')
    if ($lifecycle.Count -ne 2 -or (Get-KaronPackageRawString $lifecycle[0] 'package_gui_summary_invalid') -cne 'ko-KR-100' -or
        (Get-KaronPackageRawString $lifecycle[1] 'package_gui_summary_invalid') -cne 'en-US-200') { throw 'package_gui_lifecycle_invalid' }

    $representative = Get-KaronPackageRawProperty $summary.Raw 'representativeChecks' 'package_gui_summary_invalid'
    $representativeIds = @{}
    foreach ($name in @('mp3Conversion', 'settingsSaveRestartRestore', 'legacySettingsTransition')) {
        $ids = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $representative $name 'package_gui_summary_invalid') 'package_gui_summary_invalid')
        if ($ids.Count -eq 0) { throw 'package_gui_representative_invalid' }
        $representativeIds[$name] = @($ids | ForEach-Object { Get-KaronPackageRawString $_ 'package_gui_summary_invalid' })
    }

    $summaryProbes = Get-KaronPackageRawProperty $summary.Raw 'generatedProbes' 'package_gui_summary_invalid'
    $manifestProbes = Get-KaronPackageRawProperty $manifest.Raw 'generatedProbeFiles' 'package_gui_manifest_invalid'
    if ($summaryProbes.GetRawText() -cne $manifestProbes.GetRawText()) { throw 'package_gui_probe_inventory_invalid' }
    $seenProbes = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $videoCases = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $mp3Cases = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($probe in Get-KaronPackageRawArray $manifestProbes 'package_gui_manifest_invalid') {
        $caseId = Get-KaronPackageRawString (Get-KaronPackageRawProperty $probe 'caseId' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid'
        $kind = Get-KaronPackageRawString (Get-KaronPackageRawProperty $probe 'kind' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid'
        $sourcePath = Get-KaronPackageRawString (Get-KaronPackageRawProperty $probe 'sourceEvidencePath' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid'
        $relative = Get-KaronPackageRawString (Get-KaronPackageRawProperty $probe 'path' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid'
        Assert-KaronPackageRelativePath $sourcePath 'package_gui_manifest_invalid'
        Assert-KaronPackageRelativePath $relative 'package_gui_manifest_invalid'
        if (-not [string]::Equals($sourcePath.Normalize([Text.NormalizationForm]::FormC), $sourcePath, [StringComparison]::Ordinal) -or
            -not [string]::Equals($relative.Normalize([Text.NormalizationForm]::FormC), $relative, [StringComparison]::Ordinal) -or
            -not $evidence.ContainsKey($sourcePath) -or -not $seenProbes.Add($relative) -or
            -not $declaredGuiFiles.TryAdd($relative, $true)) { throw 'package_gui_probe_inventory_invalid' }
        $record = [pscustomobject]@{
            Name = $relative
            Length = Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $probe 'length' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid'
            Sha256 = (Get-KaronPackageRawString (Get-KaronPackageRawProperty $probe 'sha256' 'package_gui_manifest_invalid') 'package_gui_manifest_invalid').ToLowerInvariant()
        }
        Assert-KaronPackageBoundFile $record (Get-KaronPackageChildPath $guiRoot $relative 'package_gui_manifest_invalid') $relative 'package_gui_probe_mismatch'
        if ($kind -ceq 'video') { [void]$videoCases.Add($caseId) } else { [void]$mp3Cases.Add($caseId) }
    }
    if (-not $videoCases.Contains('ko-KR-100') -or -not $videoCases.Contains('en-US-200')) { throw 'package_gui_lifecycle_invalid' }
    $representativeValid = $false
    foreach ($caseId in $representativeIds.mp3Conversion) { if ($mp3Cases.Contains($caseId)) { $representativeValid = $true } }
    if (-not $representativeValid) { throw 'package_gui_representative_invalid' }
    if ($actualGuiFiles.Count -ne $declaredGuiFiles.Count) { throw 'package_gui_evidence_inventory_invalid' }
    foreach ($relative in $declaredGuiFiles.Keys) {
        if (-not $actualGuiFiles.ContainsKey($relative) -or [string]$actualGuiFiles[$relative].RelativePath -cne $relative) {
            throw 'package_gui_evidence_inventory_invalid'
        }
    }
    $schema.Tracked
}

function Assert-KaronPackageNestedSourceArchive {
    param([IO.Compression.ZipArchiveEntry] $Entry, [object] $Contract)
    if ($Contract.Name -notmatch '^[^/\\]+\.zip$' -or [long]$Entry.Length -ne [long]$Contract.Length) {
        throw 'package_source_archive_invalid'
    }
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    [void](Assert-KaronPackagePathChain $tempRoot)
    $tempPath = Join-Path $tempRoot ('karon-source-archive-' + [Guid]::NewGuid().ToString('N') + '.zip')
    try {
        $input = $Entry.Open()
        $output = [IO.File]::Open($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $input.CopyTo($output) }
        finally { $output.Dispose(); $input.Dispose() }
        [void](Assert-KaronPackagePathChain $tempPath)
        if ((Get-KaronPackageSha256 $tempPath) -cne $Contract.Sha256) { throw 'package_sources_entry_hash_mismatch' }
        try { $archive = [IO.Compression.ZipFile]::OpenRead($tempPath) }
        catch { throw 'package_source_archive_invalid' }
        try {
            $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            $fileCount = 0
            foreach ($nested in $archive.Entries) {
                $name = [string]$nested.FullName
                if ($name.Contains('\')) { throw 'package_source_archive_invalid' }
                $directory = $name.EndsWith('/', [StringComparison]::Ordinal)
                $checkName = if ($directory) { $name.TrimEnd('/') } else { $name }
                Assert-KaronPackageRelativePath $checkName 'package_source_archive_invalid'
                if (-not $paths.Add($checkName)) { throw 'package_source_archive_invalid' }
                $unixType = ($nested.ExternalAttributes -shr 16) -band 0xF000
                $dosAttributes = $nested.ExternalAttributes -band 0xFFFF
                if ($unixType -eq 0xA000 -or ($dosAttributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'package_source_archive_invalid'
                }
                if (-not $directory) { $fileCount++ }
            }
            if ($fileCount -eq 0) { throw 'package_source_archive_invalid' }
        }
        finally { $archive.Dispose() }
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force }
    }
}

function Assert-KaronPackageSourcesContract {
    param(
        [object] $Lock,
        [Text.Json.JsonElement] $OuterLockRaw,
        [string] $Path,
        [string] $RootNoticePath
    )
    $bound = Get-KaronPackageBoundRecord $Lock 'correspondingSources'
    Assert-KaronPackageBoundFile $bound $Path $script:KaronPackageSourcesName 'package_sources_lock_mismatch'
    Add-Type -AssemblyName System.IO.Compression
    $prefix = 'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources/'
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $false)
    }
    catch { throw 'package_sources_zip_invalid' }
    try {
        $entries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $zip.Entries) {
            Assert-KaronPackageRelativePath $entry.FullName 'package_sources_structure_invalid'
            if (-not $entry.FullName.StartsWith($prefix, [StringComparison]::Ordinal) -or $entry.Length -le 0 -or
                -not $entries.TryAdd($entry.FullName, $entry)) { throw 'package_sources_structure_invalid' }
            if ([string]$entries[$entry.FullName].FullName -cne $entry.FullName) { throw 'package_sources_structure_invalid' }
        }
        $innerLockName = $prefix + 'release/dependencies/v2.19.1-karon.2.lock.json'
        $innerNoticeName = $prefix + 'THIRD-PARTY-NOTICES.txt'
        if (-not $entries.ContainsKey($innerLockName) -or -not $entries.ContainsKey($innerNoticeName)) { throw 'package_sources_manifest_missing' }
        $reader = [IO.StreamReader]::new($entries[$innerLockName].Open(), [Text.UTF8Encoding]::new($false, $true))
        try { $innerJson = ConvertFrom-KaronPackageJsonStrict $reader.ReadToEnd() 'package_sources_manifest_invalid' }
        finally { $reader.Dispose() }
        Assert-KaronPackageLockRawContract $innerJson.Raw $false 'package_sources_manifest_invalid'
        if ((Get-KaronPackageLockProjectionSha256 $innerJson.Raw) -cne (Get-KaronPackageLockProjectionSha256 $OuterLockRaw)) {
            throw 'package_sources_manifest_mismatch'
        }
        $inner = $innerJson.Value
        $expected = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        $expected.Add($innerLockName, [pscustomobject]@{ Kind = 'lock'; Name = $innerLockName; Sha256 = ''; Length = [long]$entries[$innerLockName].Length })
        $expected.Add($innerNoticeName, [pscustomobject]@{ Kind = 'notice'; Name = $innerNoticeName; Sha256 = Get-KaronPackageSha256 $RootNoticePath; Length = [long](Get-Item $RootNoticePath).Length })
        foreach ($component in @($inner.components)) {
            foreach ($notice in @($component.noticeFiles)) {
                $name = $prefix + [string]$notice.path
                $expected.Add($name, [pscustomobject]@{ Kind = 'notice'; Name = $name; Sha256 = ([string]$notice.sha256).ToLowerInvariant(); Length = -1L })
            }
            foreach ($archive in @($component.sourceArchives)) {
                $name = $prefix + 'sources/' + [string]$component.id + '/' + [string]$archive.fileName
                $expected.Add($name, [pscustomobject]@{
                    Kind = 'archive'
                    Name = [string]$archive.fileName
                    Sha256 = ([string]$archive.sha256).ToLowerInvariant()
                    Length = [long]$archive.length
                })
            }
        }
        if ($entries.Count -ne $expected.Count) { throw 'package_sources_structure_invalid' }
        foreach ($name in $entries.Keys) {
            if (-not $expected.ContainsKey($name)) { throw 'package_sources_structure_invalid' }
            $contract = $expected[$name]
            if ($contract.Kind -ceq 'lock') { continue }
            if ($contract.Length -ge 0 -and [long]$entries[$name].Length -ne [long]$contract.Length) {
                throw 'package_sources_entry_length_mismatch'
            }
            if ($contract.Kind -ceq 'archive') {
                Assert-KaronPackageNestedSourceArchive $entries[$name] $contract
                continue
            }
            $entryStream = $entries[$name].Open()
            try { $hash = Get-KaronPackageStreamSha256 $entryStream }
            finally { $entryStream.Dispose() }
            if ($hash -cne $contract.Sha256) { throw 'package_sources_entry_hash_mismatch' }
        }
    }
    finally {
        $zip.Dispose()
        $stream.Dispose()
    }
}

function Get-KaronPackageSpdxFileId {
    param([string] $RelativePath)
    $digest = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($RelativePath))
    'SPDXRef-File-' + [Convert]::ToHexString($digest).ToLowerInvariant().Substring(0, 20)
}

function Assert-KaronPackageSpdxContract {
    param(
        [object] $Lock,
        [string] $Path,
        [string] $RepositoryRoot,
        [Collections.Generic.Dictionary[string, object]] $CandidateEntries
    )
    $bound = Get-KaronPackageBoundRecord $Lock 'spdx'
    Assert-KaronPackageBoundFile $bound $Path $script:KaronPackageSpdxName 'package_spdx_lock_mismatch'
    $json = ConvertFrom-KaronPackageJsonStrict ([IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))) 'package_spdx_invalid'
    $schema = Get-KaronPackageTrackedFileRecord $RepositoryRoot 'tests/powershell/fixtures/spdx-2.3-schema-aadf3b0b.json' 'spdx-2.3-schema-aadf3b0b.json' 'package_spdx_schema_untracked'
    if ($schema.length -ne 45312L -or $schema.sha256 -cne '239208b7ac287b3cf5d9a9af23f9d69863971102a5e1587a27a398b43490b89b') { throw 'package_spdx_schema_pin_mismatch' }
    try {
        if (-not (Test-Json -LiteralPath $Path -SchemaFile $schema.localPath -ErrorAction Stop)) { throw 'invalid' }
    }
    catch { throw 'package_spdx_schema_invalid' }
    $creationInfo = Get-KaronPackageRawProperty $json.Raw 'creationInfo' 'package_spdx_schema_invalid'
    [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $creationInfo 'created' 'package_spdx_schema_invalid') 'package_spdx_schema_invalid')
    foreach ($creator in Get-KaronPackageRawArray (Get-KaronPackageRawProperty $creationInfo 'creators' 'package_spdx_schema_invalid') 'package_spdx_schema_invalid') {
        [void](Get-KaronPackageRawString $creator 'package_spdx_schema_invalid')
    }
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
        $primary = @($component.sourceArchives | Where-Object { [string]$_.commit -ceq [string]$component.sourceCommit })
        if ($primary.Count -ne 1) { throw 'package_spdx_package_contract_mismatch' }
        $expectedPackages.Add('SPDXRef-Package-' + [string]$component.id, [pscustomobject]@{
            Name = [string]$component.name
            Version = [string]$component.version
            Declared = [string]$component.licenseExpression
            Concluded = [string]$component.licenseConcluded
            Download = [string]$primary[0].url
            FilesAnalyzed = [bool]$component.filesAnalyzed
        })
    }
    $metadata = $Lock.release.metadataPackage
    $expectedPackages.Add('SPDXRef-Package-' + [string]$metadata.id, [pscustomobject]@{
        Name = [string]$metadata.name
        Version = [string]$metadata.version
        Declared = [string]$metadata.licenseExpression
        Concluded = [string]$metadata.licenseConcluded
        Download = [string]$metadata.downloadLocation
        FilesAnalyzed = $true
    })
    $packages = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $json.Raw 'packages' 'package_spdx_invalid') 'package_spdx_invalid')
    if ($packages.Count -ne $expectedPackages.Count) { throw 'package_spdx_package_inventory_invalid' }
    $seenPackages = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($package in $packages) {
        [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $package 'copyrightText' 'package_spdx_schema_invalid') 'package_spdx_schema_invalid')
        $id = Get-KaronPackageRawString (Get-KaronPackageRawProperty $package 'SPDXID' 'package_spdx_invalid') 'package_spdx_invalid'
        if (-not $seenPackages.Add($id) -or -not $expectedPackages.ContainsKey($id)) { throw 'package_spdx_package_inventory_invalid' }
        $expected = $expectedPackages[$id]
        if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $package 'name' 'package_spdx_invalid') 'package_spdx_invalid') -cne $expected.Name -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $package 'versionInfo' 'package_spdx_invalid') 'package_spdx_invalid') -cne $expected.Version -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $package 'licenseDeclared' 'package_spdx_invalid') 'package_spdx_invalid') -cne $expected.Declared -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $package 'licenseConcluded' 'package_spdx_invalid') 'package_spdx_invalid') -cne $expected.Concluded -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $package 'downloadLocation' 'package_spdx_invalid') 'package_spdx_invalid') -cne $expected.Download -or
            (Get-KaronPackageRawBoolean (Get-KaronPackageRawProperty $package 'filesAnalyzed' 'package_spdx_invalid') 'package_spdx_invalid') -ne $expected.FilesAnalyzed) {
            throw 'package_spdx_package_contract_mismatch'
        }
    }
    $described = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($item in Get-KaronPackageRawArray (Get-KaronPackageRawProperty $json.Raw 'documentDescribes' 'package_spdx_invalid') 'package_spdx_invalid') {
        if (-not $described.Add((Get-KaronPackageRawString $item 'package_spdx_invalid'))) { throw 'package_spdx_package_inventory_invalid' }
    }
    if ($described.Count -ne $expectedPackages.Count) { throw 'package_spdx_package_inventory_invalid' }
    foreach ($id in $expectedPackages.Keys) { if (-not $described.Contains($id)) { throw 'package_spdx_package_inventory_invalid' } }

    $expectedFiles = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in @($Lock.release.candidateFiles)) {
        $relative = [string]$candidate.path
        if (-not $CandidateEntries.ContainsKey($relative)) { throw 'package_spdx_file_inventory_invalid' }
        $expectedFiles.Add($relative, [pscustomobject]@{
            Sha256 = ([string]$candidate.sha256).ToLowerInvariant()
            Sha1 = (Get-FileHash -LiteralPath $CandidateEntries[$relative].SourcePath -Algorithm SHA1).Hash.ToLowerInvariant()
            Package = 'SPDXRef-Package-' + [string]$candidate.package
            License = [string]$candidate.licenseConcluded
            SpdxId = Get-KaronPackageSpdxFileId $relative
        })
    }
    $files = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $json.Raw 'files' 'package_spdx_invalid') 'package_spdx_invalid')
    if ($files.Count -ne $expectedFiles.Count) { throw 'package_spdx_file_inventory_invalid' }
    $seenFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $files) {
        [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $file 'copyrightText' 'package_spdx_schema_invalid') 'package_spdx_schema_invalid')
        $name = Get-KaronPackageRawString (Get-KaronPackageRawProperty $file 'fileName' 'package_spdx_invalid') 'package_spdx_invalid'
        if (-not $name.StartsWith('./', [StringComparison]::Ordinal)) { throw 'package_spdx_file_inventory_invalid' }
        $relative = $name.Substring(2)
        if (-not $seenFiles.Add($relative) -or -not $expectedFiles.ContainsKey($relative)) { throw 'package_spdx_file_inventory_invalid' }
        $expected = $expectedFiles[$relative]
        if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $file 'SPDXID' 'package_spdx_invalid') 'package_spdx_invalid') -cne $expected.SpdxId -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $file 'licenseConcluded' 'package_spdx_invalid') 'package_spdx_invalid') -cne $expected.License) {
            throw 'package_spdx_file_contract_mismatch'
        }
        $hashes = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
        foreach ($checksum in Get-KaronPackageRawArray (Get-KaronPackageRawProperty $file 'checksums' 'package_spdx_invalid') 'package_spdx_invalid') {
            $algorithm = Get-KaronPackageRawString (Get-KaronPackageRawProperty $checksum 'algorithm' 'package_spdx_invalid') 'package_spdx_invalid'
            $value = Get-KaronPackageRawString (Get-KaronPackageRawProperty $checksum 'checksumValue' 'package_spdx_invalid') 'package_spdx_invalid'
            if (-not $hashes.TryAdd($algorithm, $value.ToLowerInvariant())) { throw 'package_spdx_file_hash_mismatch' }
        }
        if ($hashes.Count -ne 2 -or -not $hashes.ContainsKey('SHA1') -or -not $hashes.ContainsKey('SHA256') -or
            $hashes['SHA1'] -cne $expected.Sha1 -or $hashes['SHA256'] -cne $expected.Sha256) { throw 'package_spdx_file_hash_mismatch' }
    }

    $expectedRelationships = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($packageId in $expectedPackages.Keys) { [void]$expectedRelationships.Add('SPDXRef-DOCUMENT|DESCRIBES|' + $packageId) }
    foreach ($relative in $expectedFiles.Keys) {
        [void]$expectedRelationships.Add($expectedFiles[$relative].Package + '|CONTAINS|' + $expectedFiles[$relative].SpdxId)
    }
    foreach ($component in @($Lock.components | Where-Object { -not [bool]$_.filesAnalyzed })) {
        [void]$expectedRelationships.Add(('SPDXRef-Package-' + [string]$component.staticLinkTarget + '|STATIC_LINK|SPDXRef-Package-' + [string]$component.id))
    }
    $actualRelationships = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($relationship in Get-KaronPackageRawArray (Get-KaronPackageRawProperty $json.Raw 'relationships' 'package_spdx_invalid') 'package_spdx_invalid') {
        $key = (Get-KaronPackageRawString (Get-KaronPackageRawProperty $relationship 'spdxElementId' 'package_spdx_invalid') 'package_spdx_invalid') + '|' +
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $relationship 'relationshipType' 'package_spdx_invalid') 'package_spdx_invalid') + '|' +
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $relationship 'relatedSpdxElement' 'package_spdx_invalid') 'package_spdx_invalid')
        if (-not $actualRelationships.Add($key)) { throw 'package_spdx_relationship_invalid' }
    }
    if ($actualRelationships.Count -ne $expectedRelationships.Count) { throw 'package_spdx_relationship_invalid' }
    foreach ($key in $expectedRelationships) { if (-not $actualRelationships.Contains($key)) { throw 'package_spdx_relationship_invalid' } }

    $definitions = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $expressions = [Collections.Generic.List[string]]::new()
    $expressions.Add([string]$metadata.licenseExpression)
    $expressions.Add([string]$metadata.licenseConcluded)
    foreach ($candidate in @($Lock.release.candidateFiles)) { $expressions.Add([string]$candidate.licenseConcluded) }
    foreach ($component in @($Lock.components)) {
        $expressions.Add([string]$component.licenseExpression)
        $expressions.Add([string]$component.licenseConcluded)
        $componentLicenseRefs = if (Test-KaronPackageProperty $component 'licenseRefs') { @($component.licenseRefs) } else { @() }
        foreach ($definition in $componentLicenseRefs) {
            if (-not $definitions.TryAdd([string]$definition.licenseId, $definition)) { throw 'package_spdx_license_ref_invalid' }
        }
    }
    $usedRefs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($expression in $expressions) {
        foreach ($match in [regex]::Matches($expression, 'LicenseRef-[A-Za-z0-9.-]+')) { [void]$usedRefs.Add($match.Value) }
    }
    $extracted = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $json.Raw 'hasExtractedLicensingInfos' 'package_spdx_invalid') 'package_spdx_invalid')
    if ($extracted.Count -ne $usedRefs.Count) { throw 'package_spdx_license_ref_invalid' }
    $seenRefs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($item in $extracted) {
        $licenseId = Get-KaronPackageRawString (Get-KaronPackageRawProperty $item 'licenseId' 'package_spdx_invalid') 'package_spdx_invalid'
        if (-not $seenRefs.Add($licenseId) -or -not $usedRefs.Contains($licenseId) -or -not $definitions.ContainsKey($licenseId)) {
            throw 'package_spdx_license_ref_invalid'
        }
        $definition = $definitions[$licenseId]
        $notice = Get-KaronPackageTrackedFileRecord $RepositoryRoot ([string]$definition.noticePath) ([IO.Path]::GetFileName([string]$definition.noticePath)) 'package_spdx_license_ref_invalid'
        $expectedText = [IO.File]::ReadAllText($notice.localPath, [Text.UTF8Encoding]::new($false, $true))
        if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $item 'name' 'package_spdx_invalid') 'package_spdx_invalid') -cne [string]$definition.name -or
            (Get-KaronPackageRawString (Get-KaronPackageRawProperty $item 'extractedText' 'package_spdx_invalid') 'package_spdx_invalid') -cne $expectedText) {
            throw 'package_spdx_license_ref_invalid'
        }
    }
}

function Write-KaronPackageAtomicJson {
    param([string] $Path, [object] $Value)
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    [void](Assert-KaronPackagePathChain $parent)
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent) }
    [void](Assert-KaronPackagePathChain $parent)
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
    [void](Assert-KaronPackagePathChain $Path)
    $item = Get-Item -LiteralPath $Path
    [ordered]@{ localPath = [IO.Path]::GetFullPath($Path); fileName = $FileName; length = [long]$item.Length; sha256 = Get-KaronPackageSha256 $Path }
}

function Get-KaronPackagePublicInventory {
    param([string] $AssetDirectory)
    [void](Assert-KaronPackagePathChain $AssetDirectory)
    $names = @($script:KaronPackageBinaryName, $script:KaronPackageSourcesName, $script:KaronPackageSpdxName, $script:KaronPackageSumsName)
    $files = @(Get-ChildItem -LiteralPath $AssetDirectory -File -Force)
    if ($files.Count -ne 4) { throw 'package_final_inventory_invalid' }
    $result = @()
    foreach ($name in $names) {
        $path = Join-Path $AssetDirectory $name
        [void](Assert-KaronPackagePathChain $path)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'package_final_inventory_invalid' }
        $item = Get-Item -LiteralPath $path
        $result += [ordered]@{ fileName = $name; length = [long]$item.Length; sha256 = Get-KaronPackageSha256 $path }
    }
    $result
}

function New-KaronPackageByteSnapshots {
    param([Parameter(Mandatory)] [string[]] $Paths)
    $snapshots = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($pathValue in $Paths) {
        $path = Assert-KaronPackagePathChain $pathValue
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'package_snapshot_input_missing' }
        $item = Get-Item -LiteralPath $path -Force
        $record = [pscustomobject]@{ Path = $path; Length = [long]$item.Length; Sha256 = Get-KaronPackageSha256 $path }
        if (-not $snapshots.TryAdd($path, $record)) { continue }
    }
    $snapshots
}

function Assert-KaronPackageByteSnapshots {
    param([Parameter(Mandatory)] [Collections.Generic.Dictionary[string, object]] $Snapshots)
    foreach ($record in $Snapshots.Values) {
        [void](Assert-KaronPackagePathChain $record.Path)
        if (-not (Test-Path -LiteralPath $record.Path -PathType Leaf)) { throw 'package_input_changed' }
        $item = Get-Item -LiteralPath $record.Path -Force
        if ([long]$item.Length -ne [long]$record.Length -or (Get-KaronPackageSha256 $record.Path) -cne [string]$record.Sha256) {
            throw 'package_input_changed'
        }
    }
}

function Get-KaronPackageLicenseCorpusRecords {
    param([object] $Lock, [string] $RepositoryRoot)
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $declaredHashes = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($component in @($Lock.components)) {
        $componentPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($notice in @($component.noticeFiles)) {
            $path = [string]$notice.path
            $sha256 = ([string]$notice.sha256).ToLowerInvariant()
            if (-not $path.StartsWith($script:KaronPackageLicensePrefix, [StringComparison]::Ordinal) -or
                $sha256 -notmatch '^[a-f0-9]{64}$' -or -not $componentPaths.Add($path) -or
                -not $paths.Add($path) -or -not $declaredHashes.TryAdd($path, $sha256)) {
                throw 'package_license_inventory_mismatch'
            }
        }
        foreach ($licenseRef in $(if (Test-KaronPackageProperty $component 'licenseRefs') { @($component.licenseRefs) } else { @() })) {
            $noticePath = [string]$licenseRef.noticePath
            if (-not $noticePath.StartsWith($script:KaronPackageLicensePrefix, [StringComparison]::Ordinal) -or
                -not $componentPaths.Contains($noticePath)) { throw 'package_license_ref_notice_invalid' }
        }
    }
    $sorted = [string[]]@($paths)
    [Array]::Sort($sorted, [StringComparer]::Ordinal)
    @($sorted | ForEach-Object {
        $tracked = Get-KaronPackageTrackedFileRecord $RepositoryRoot $_ ([IO.Path]::GetFileName($_))
        if ($tracked.sha256 -cne $declaredHashes[$_]) { throw 'package_license_notice_hash_mismatch' }
        $tracked
    })
}

function Assert-KaronPackageReceiptTrackedRecord {
    param(
        [Text.Json.JsonElement] $Raw,
        [object] $Value,
        [string] $RepositoryRoot,
        [string] $RepositoryPath,
        [string] $FileName,
        [string] $ErrorId
    )
    Assert-KaronPackageRawExactKeys $Raw @('repositoryPath', 'localPath', 'fileName', 'length', 'sha256', 'gitBlobSha1') 'package_receipt_invalid'
    foreach ($name in @('repositoryPath', 'localPath', 'fileName', 'sha256', 'gitBlobSha1')) {
        [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $Raw $name 'package_receipt_invalid') 'package_receipt_invalid')
    }
    [void](Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $Raw 'length' 'package_receipt_invalid') 'package_receipt_invalid')
    $actual = Get-KaronPackageTrackedFileRecord $RepositoryRoot $RepositoryPath $FileName $ErrorId
    foreach ($name in @('repositoryPath', 'localPath', 'fileName', 'sha256', 'gitBlobSha1')) {
        if ([string]$Value.$name -cne [string]$actual[$name]) { throw $ErrorId }
    }
    if ([long]$Value.length -ne [long]$actual.length) { throw $ErrorId }
    $actual
}

function Assert-KaronReleaseReceipt {
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $AssetDirectory,
        [Parameter(Mandatory)] [string] $ReceiptPath
    )
    $repo = Assert-KaronPackagePathChain $RepositoryRoot
    $assets = Assert-KaronPackagePathChain $AssetDirectory
    $receipt = Assert-KaronPackagePathChain $ReceiptPath
    if ([IO.Path]::GetFileName($receipt) -cne 'release-receipt.json' -or
        (Split-Path -Parent $receipt) -ieq $assets -or -not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
        throw 'package_receipt_location_invalid'
    }
    $json = ConvertFrom-KaronPackageJsonStrict ([IO.File]::ReadAllText($receipt, [Text.UTF8Encoding]::new($false, $true))) 'package_receipt_invalid'
    Assert-KaronPackageRawExactKeys $json.Raw @(
        'schemaVersion', 'tag', 'platform', 'applicationSourceCommit', 'applicationSourceTree', 'packagingCommit', 'candidateManifest', 'application', 'ffprobe',
        'guiValidationSummary', 'guiValidationEvidenceManifest', 'guiValidationSchema', 'licenseLock', 'rootThirdPartyNotices',
        'licenseCorpus', 'correspondingSources', 'spdx', 'releaseNotes', 'guiCaseIds', 'publicAssets'
    ) 'package_receipt_invalid'
    if ((Get-KaronPackageRawString (Get-KaronPackageRawProperty $json.Raw 'schemaVersion' 'package_receipt_invalid') 'package_receipt_invalid') -cne 'karon-release-receipt/v2' -or
        (Get-KaronPackageRawString (Get-KaronPackageRawProperty $json.Raw 'tag' 'package_receipt_invalid') 'package_receipt_invalid') -cne $script:KaronPackageTag -or
        (Get-KaronPackageRawString (Get-KaronPackageRawProperty $json.Raw 'platform' 'package_receipt_invalid') 'package_receipt_invalid') -cne 'win-x64') {
        throw 'package_receipt_invalid'
    }
    $applicationSourceCommit = (Get-KaronPackageRawString (Get-KaronPackageRawProperty $json.Raw 'applicationSourceCommit' 'package_receipt_invalid') 'package_receipt_invalid').ToLowerInvariant()
    $applicationSourceTree = (Get-KaronPackageRawString (Get-KaronPackageRawProperty $json.Raw 'applicationSourceTree' 'package_receipt_invalid') 'package_receipt_invalid').ToLowerInvariant()
    $packagingCommit = (Get-KaronPackageRawString (Get-KaronPackageRawProperty $json.Raw 'packagingCommit' 'package_receipt_invalid') 'package_receipt_invalid').ToLowerInvariant()
    if ($applicationSourceCommit -notmatch '^[a-f0-9]{40}$' -or $applicationSourceTree -notmatch '^[a-f0-9]{40}$' -or
        $packagingCommit -notmatch '^[a-f0-9]{40}$') { throw 'package_receipt_invalid' }
    if ($applicationSourceCommit -ceq $packagingCommit) { throw 'package_receipt_provenance_confused' }
    if ($packagingCommit -cne (Get-KaronPackageRepositoryHead $repo)) { throw 'package_receipt_packaging_commit_mismatch' }
    $value = $json.Value
    foreach ($name in @('candidateManifest', 'application', 'ffprobe', 'guiValidationSummary', 'guiValidationEvidenceManifest', 'correspondingSources', 'spdx')) {
        $rawRecord = Get-KaronPackageRawProperty $json.Raw $name 'package_receipt_invalid'
        Assert-KaronPackageRawExactKeys $rawRecord @('localPath', 'fileName', 'length', 'sha256') 'package_receipt_invalid'
        foreach ($field in @('localPath', 'fileName', 'sha256')) {
            [void](Get-KaronPackageRawString (Get-KaronPackageRawProperty $rawRecord $field 'package_receipt_invalid') 'package_receipt_invalid')
        }
        $length = Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $rawRecord 'length' 'package_receipt_invalid') 'package_receipt_invalid'
        $record = [pscustomobject]@{ Name = [string]$value.$name.fileName; Length = $length; Sha256 = ([string]$value.$name.sha256).ToLowerInvariant() }
        Assert-KaronPackageBoundFile $record ([string]$value.$name.localPath) $record.Name 'package_receipt_tampered'
    }

    $lockRepositoryPath = 'release/dependencies/v2.19.1-karon.2.lock.json'
    [void](Assert-KaronPackageReceiptTrackedRecord (Get-KaronPackageRawProperty $json.Raw 'licenseLock' 'package_receipt_invalid') $value.licenseLock $repo $lockRepositoryPath 'v2.19.1-karon.2.lock.json' 'package_receipt_lock_mismatch')
    [void](Assert-KaronPackageReceiptTrackedRecord (Get-KaronPackageRawProperty $json.Raw 'rootThirdPartyNotices' 'package_receipt_invalid') $value.rootThirdPartyNotices $repo 'THIRD-PARTY-NOTICES.txt' 'THIRD-PARTY-NOTICES.txt' 'package_receipt_notice_mismatch')
    $notesPath = [IO.Path]::GetFullPath((Join-Path $repo 'release\notes\v2.19.1-karon.2.md'))
    $notesRecord = Assert-KaronPackageReceiptTrackedRecord (Get-KaronPackageRawProperty $json.Raw 'releaseNotes' 'package_receipt_invalid') $value.releaseNotes $repo 'release/notes/v2.19.1-karon.2.md' 'v2.19.1-karon.2.md' 'package_receipt_notes_mismatch'
    [void](Assert-KaronPackageReceiptTrackedRecord (Get-KaronPackageRawProperty $json.Raw 'guiValidationSchema' 'package_receipt_invalid') $value.guiValidationSchema $repo $script:KaronPackageGuiSchemaRepositoryPath 'gui-validation-output.schema.json' 'package_receipt_gui_schema_mismatch')

    $lockPath = [IO.Path]::GetFullPath((Join-Path $repo ($lockRepositoryPath.Replace('/', [IO.Path]::DirectorySeparatorChar))))
    $lockDocument = Read-KaronPackageStrictLockDocument $lockPath
    $lock = $lockDocument.Value
    Assert-KaronPackageStatusContract $lock
    $actualCorpus = @(Get-KaronPackageLicenseCorpusRecords $lock $repo)
    $receiptCorpus = @(Get-KaronPackageRawArray (Get-KaronPackageRawProperty $json.Raw 'licenseCorpus' 'package_receipt_invalid') 'package_receipt_invalid')
    if ($receiptCorpus.Count -ne $actualCorpus.Count) { throw 'package_receipt_license_corpus_mismatch' }
    for ($index = 0; $index -lt $actualCorpus.Count; $index++) {
        $path = [string]$actualCorpus[$index].repositoryPath
        [void](Assert-KaronPackageReceiptTrackedRecord $receiptCorpus[$index] $value.licenseCorpus[$index] $repo $path ([IO.Path]::GetFileName($path)) 'package_receipt_license_corpus_mismatch')
    }

    $candidateRoot = Split-Path -Parent ([string]$value.candidateManifest.localPath)
    $candidateEntries = Get-KaronPackageCandidateEntries $lock $candidateRoot
    $provenance = Get-KaronPackageApplicationProvenance $lock $candidateEntries $repo $packagingCommit
    if ($applicationSourceCommit -cne $provenance.ApplicationSourceCommit -or $applicationSourceTree -cne $provenance.ApplicationSourceTree) {
        throw 'package_receipt_application_source_mismatch'
    }
    if ($candidateEntries['ytdlp-interface.exe'].Sha256 -cne ([string]$value.application.sha256).ToLowerInvariant() -or
        $candidateEntries['ffprobe.exe'].Sha256 -cne ([string]$value.ffprobe.sha256).ToLowerInvariant()) { throw 'package_receipt_candidate_mismatch' }
    [void](Assert-KaronPackageGuiContract $lock $repo ([string]$value.guiValidationSummary.localPath) ([string]$value.guiValidationEvidenceManifest.localPath) $candidateEntries)
    Assert-KaronPackageSourcesContract $lock $lockDocument.Raw ([string]$value.correspondingSources.localPath) ([string]$value.rootThirdPartyNotices.localPath)
    Assert-KaronPackageSpdxContract $lock ([string]$value.spdx.localPath) $repo $candidateEntries

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
        ApplicationSourceCommit = $applicationSourceCommit
        ApplicationSourceTree = $applicationSourceTree
        PackagingCommit = $packagingCommit
        NotesPath = $notesPath
        NotesBlobSha1 = [string]$notesRecord.gitBlobSha1
        NotesBody = [IO.File]::ReadAllText($notesPath, [Text.UTF8Encoding]::new($false, $true))
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
    $repo = Assert-KaronPackagePathChain $RepositoryRoot
    $candidateRoot = Assert-KaronPackagePathChain $CandidateDirectory
    $outputRoot = Assert-KaronPackagePathChain $OutputDirectory
    $receipt = Assert-KaronPackagePathChain $ReceiptPath
    if ([IO.Path]::GetFileName($GuiValidationSummaryPath) -cne 'gui-validation-summary.json' -or
        [IO.Path]::GetFileName($GuiValidationEvidenceManifestPath) -cne 'gui-validation-evidence-manifest.json' -or
        [IO.Path]::GetFileName($receipt) -cne 'release-receipt.json' -or
        (Split-Path -Parent $receipt) -ieq $outputRoot) { throw 'package_evidence_input_invalid' }
    if (Test-Path -LiteralPath $receipt) { throw 'package_receipt_exists' }

    $expectedLockPath = [IO.Path]::GetFullPath((Join-Path $repo 'release\dependencies\v2.19.1-karon.2.lock.json'))
    $actualLockPath = Assert-KaronPackagePathChain $LockPath
    if (-not $actualLockPath.Equals($expectedLockPath, [StringComparison]::OrdinalIgnoreCase)) { throw 'package_lock_path_invalid' }
    $packagingCommit = Get-KaronPackageRepositoryHead $repo
    $lockTracked = Get-KaronPackageTrackedFileRecord $repo 'release/dependencies/v2.19.1-karon.2.lock.json' 'v2.19.1-karon.2.lock.json'
    $lockDocument = Read-KaronPackageStrictLockDocument $actualLockPath
    $lock = $lockDocument.Value
    Assert-KaronPackageStatusContract $lock
    $candidateEntries = Get-KaronPackageCandidateEntries $lock $candidateRoot
    $provenance = Get-KaronPackageApplicationProvenance $lock $candidateEntries $repo $packagingCommit
    $candidateManifestRecord = Get-KaronPackageBoundRecord $lock 'candidateManifest'
    Assert-KaronPackageBoundFile $candidateManifestRecord $candidateEntries['candidate-manifest.json'].SourcePath 'candidate-manifest.json' 'package_candidate_manifest_lock_mismatch'
    $guiSchemaTracked = Assert-KaronPackageGuiContract $lock $repo $GuiValidationSummaryPath $GuiValidationEvidenceManifestPath $candidateEntries
    $rootNoticePath = [IO.Path]::GetFullPath((Join-Path $repo 'THIRD-PARTY-NOTICES.txt'))
    $rootNoticeTracked = Get-KaronPackageTrackedFileRecord $repo 'THIRD-PARTY-NOTICES.txt' 'THIRD-PARTY-NOTICES.txt'
    $rootNoticeRecord = Get-KaronPackageBoundRecord $lock 'rootThirdPartyNotices'
    Assert-KaronPackageBoundFile $rootNoticeRecord $rootNoticePath 'THIRD-PARTY-NOTICES.txt' 'package_root_notice_lock_mismatch'
    $licenseCorpus = @(Get-KaronPackageLicenseCorpusRecords $lock $repo)
    Assert-KaronPackageSourcesContract $lock $lockDocument.Raw $CorrespondingSourcesPath $rootNoticePath
    Assert-KaronPackageSpdxContract $lock $SpdxPath $repo $candidateEntries
    $notesPath = [IO.Path]::GetFullPath((Join-Path $repo 'release\notes\v2.19.1-karon.2.md'))
    $notesTracked = Get-KaronPackageTrackedFileRecord $repo 'release/notes/v2.19.1-karon.2.md' 'v2.19.1-karon.2.md'
    $notesRecord = Get-KaronPackageBoundRecord $lock 'releaseNotes' 'path'
    Assert-KaronPackageBoundFile $notesRecord $notesPath 'release/notes/v2.19.1-karon.2.md' 'package_release_notes_lock_mismatch'

    $snapshotPaths = [Collections.Generic.List[string]]::new()
    foreach ($entry in $candidateEntries.Values) { $snapshotPaths.Add([string]$entry.SourcePath) }
    foreach ($record in $licenseCorpus) { $snapshotPaths.Add([string]$record.localPath) }
    foreach ($path in @($actualLockPath, $rootNoticePath, $CorrespondingSourcesPath, $SpdxPath, $GuiValidationSummaryPath, $GuiValidationEvidenceManifestPath, $guiSchemaTracked.localPath, $notesPath)) {
        $snapshotPaths.Add([string]$path)
    }
    $guiRoot = Split-Path -Parent ([IO.Path]::GetFullPath($GuiValidationEvidenceManifestPath))
    foreach ($entry in (Get-KaronPackageSafeInventory $guiRoot 'package_gui_snapshot').Values) { $snapshotPaths.Add([string]$entry.FullPath) }
    $inputSnapshots = New-KaronPackageByteSnapshots ([string[]]$snapshotPaths.ToArray())

    $coreResult = Invoke-QualityReleasePackageCore -RepositoryRoot $repo -CandidateDirectory $candidateRoot -LockPath $actualLockPath -CorrespondingSourcesPath $CorrespondingSourcesPath -SpdxPath $SpdxPath -OutputDirectory $outputRoot -PlanOnly:$PlanOnly
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
        schemaVersion = 'karon-release-receipt/v2'
        tag = $script:KaronPackageTag
        platform = 'win-x64'
        applicationSourceCommit = $provenance.ApplicationSourceCommit
        applicationSourceTree = $provenance.ApplicationSourceTree
        packagingCommit = $provenance.PackagingCommit
        candidateManifest = New-KaronPackageLocalRecord $candidateEntries['candidate-manifest.json'].SourcePath 'candidate-manifest.json'
        application = New-KaronPackageLocalRecord $candidateEntries['ytdlp-interface.exe'].SourcePath 'ytdlp-interface.exe'
        ffprobe = New-KaronPackageLocalRecord $candidateEntries['ffprobe.exe'].SourcePath 'ffprobe.exe'
        guiValidationSummary = New-KaronPackageLocalRecord $GuiValidationSummaryPath 'gui-validation-summary.json'
        guiValidationEvidenceManifest = New-KaronPackageLocalRecord $GuiValidationEvidenceManifestPath 'gui-validation-evidence-manifest.json'
        guiValidationSchema = $guiSchemaTracked
        licenseLock = $lockTracked
        rootThirdPartyNotices = $rootNoticeTracked
        licenseCorpus = $licenseCorpus
        correspondingSources = New-KaronPackageLocalRecord $sourcesFinal $script:KaronPackageSourcesName
        spdx = New-KaronPackageLocalRecord $spdxFinal $script:KaronPackageSpdxName
        releaseNotes = $notesTracked
        guiCaseIds = @($script:KaronPackageGuiCases | ForEach-Object Id)
        publicAssets = @(Get-KaronPackagePublicInventory $outputRoot)
    }
    Write-KaronPackageAtomicJson $receipt $receiptValue
    $validated = Assert-KaronReleaseReceipt $repo $outputRoot $receipt
    Assert-KaronPackageByteSnapshots $inputSnapshots
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
