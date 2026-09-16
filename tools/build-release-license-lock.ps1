param(
    [Parameter(Mandatory = $true)] [string] $RepositoryRoot,
    [Parameter(Mandatory = $true)] [string] $TemplateLockPath,
    [Parameter(Mandatory = $true)] [string] $CandidateDirectory,
    [Parameter(Mandatory = $true)] [string] $SourceArchiveDirectory,
    [Parameter(Mandatory = $true)] [string] $NonRuntimeManifestPath,
    [Parameter(Mandatory = $true)] [string] $NonRuntimeInventoryPath,
    [Parameter(Mandatory = $true)] [string] $NonRuntimeEvidenceBundlePath,
        [Parameter(Mandatory = $true)]
    [string]$DenoRunEvidencePath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$DenoCollectorSourceCommit,
[Parameter(Mandatory = $true)] [string] $DenoComponentManifestPath,
    [Parameter(Mandatory = $true)] [string] $DenoSourceInventoryPath,
    [Parameter(Mandatory = $true)] [string] $DenoNoticesPath,
    [Parameter(Mandatory = $true)] [string] $DenoSourcesArchivePath,
    [Parameter(Mandatory = $true)] [string] $FfmpegClosureManifestPath,
    [Parameter(Mandatory = $true)] [string] $FfmpegSourcesArchivePath,
    [Parameter(Mandatory = $true)] [string] $SevenZipRuntimeArchivePath,
    [Parameter(Mandatory = $true)] [string] $SevenZipSourceArchivePath,
        [Parameter(Mandatory = $true)]
    [string]$SevenZipSourceWrapperPath,
[Parameter(Mandatory = $true)] [string] $SevenZipVerificationPath,
    [Parameter(Mandatory = $true)] [string] $GuiValidationSummaryPath,
    [Parameter(Mandatory = $true)] [string] $GuiValidationEvidenceManifestPath,
    [Parameter(Mandatory = $true)] [string] $GuiValidationSchemaPath,
    [Parameter(Mandatory = $true)] [string] $CorrespondingSourcesPath,
    [Parameter(Mandatory = $true)] [string] $SpdxPath,
    [Parameter(Mandatory = $true)] [string] $RootThirdPartyNoticesPath,
    [Parameter(Mandatory = $true)] [string] $ReleaseNotesPath,
    [Parameter(Mandatory = $true)] [string] $OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:ReleaseTag = 'v2.19.1-karon.2'
$script:Utf8Strict = New-Object Text.UTF8Encoding($false, $true)
$script:Utf8NoBom = New-Object Text.UTF8Encoding($false)
$script:Sha256Pattern = '^[a-fA-F0-9]{64}$'
$script:CommitPattern = '^[a-fA-F0-9]{40}$'
$script:HeldInputHandles = New-Object 'Collections.Generic.List[object]'

function Close-IntegratorLockedSnapshots {
    for ($index = $script:HeldInputHandles.Count - 1; $index -ge 0; $index--) {
        $script:HeldInputHandles[$index].Dispose()
    }
    $script:HeldInputHandles.Clear()
}

function Open-IntegratorLockedSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    if (-not [IO.Path]::IsPathFullyQualified($Path) -or
        @($Path -split '[\\/]' | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -ne 0) {
        throw "${Context}_path_invalid"
    }

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (($OutputPath) -and $fullPath.Equals([IO.Path]::GetFullPath($OutputPath), [StringComparison]::OrdinalIgnoreCase)) {
        throw "${Context}_output_alias"
    }

    $cursor = $fullPath
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            $linkType = $item.PSObject.Properties['LinkType']
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                ($null -ne $linkType -and -not [string]::IsNullOrWhiteSpace([string]$linkType.Value))) {
                throw "${Context}_path_alias"
            }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) { break }
        $cursor = $parent
    }

    try {
        $stream = New-Object IO.FileStream(
            $fullPath,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::Read,
            4096,
            [IO.FileOptions]::SequentialScan
        )
    }
    catch {
        throw "${Context}_missing_or_locked"
    }
    [void]$script:HeldInputHandles.Add($stream)

    if ($stream.Length -gt [int]::MaxValue) { throw "${Context}_too_large" }
    $bytes = New-Object byte[] ([int]$stream.Length)
    $offset = 0
    while ($offset -lt $bytes.Length) {
        $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
        if ($read -eq 0) { throw "${Context}_short_read" }
        $offset += $read
    }

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try { $digest = [Convert]::ToHexString($sha256.ComputeHash($bytes)).ToLowerInvariant() }
    finally { $sha256.Dispose() }

    return [pscustomobject][ordered]@{
        fileName = [IO.Path]::GetFileName($fullPath)
        length = [long]$bytes.LongLength
        sha256 = $digest
        fullPath = $fullPath
        bytes = $bytes
    }
}

function Get-ExactProperty {
    param([Parameter(Mandatory = $true)] [object] $Value, [Parameter(Mandatory = $true)] [string] $Name, [string] $ErrorId = 'release_license_lock_json_invalid')
    if ($Value -is [Collections.IDictionary]) {
        foreach ($key in $Value.Keys) { if ([string]$key -ceq $Name) { return $Value[$key] } }
        throw $ErrorId
    }
    $property = @($Value.PSObject.Properties | Where-Object { $_.Name -ceq $Name })
    if ($property.Count -ne 1) { throw $ErrorId }
    $property[0].Value
}

function Test-ExactProperty {
    param([object] $Value, [string] $Name)
    if ($null -eq $Value) { return $false }
    if ($Value -is [Collections.IDictionary]) {
        foreach ($key in $Value.Keys) { if ([string]$key -ceq $Name) { return $true } }
        return $false
    }
    return @($Value.PSObject.Properties | Where-Object { $_.Name -ceq $Name }).Count -eq 1
}

function Set-ExactProperty {
    param([object] $Value, [string] $Name, [object] $NewValue)
    if ($Value -is [Collections.IDictionary]) { $Value[$Name] = $NewValue; return }
    $property = @($Value.PSObject.Properties | Where-Object { $_.Name -ceq $Name })
    if ($property.Count -eq 0) { $Value | Add-Member -NotePropertyName $Name -NotePropertyValue $NewValue }
    elseif ($property.Count -eq 1) { $property[0].Value = $NewValue }
    else { throw 'release_license_lock_json_duplicate' }
}

function Assert-NoDuplicateJsonProperties {
    param([Text.Json.JsonElement] $Element)
    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        $names = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw 'release_license_lock_json_duplicate' }
            Assert-NoDuplicateJsonProperties $property.Value
        }
    }
    elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-NoDuplicateJsonProperties $item }
    }
}

function Read-StrictJson {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'release_license_lock_input_missing' }
    try {
        $text = $script:Utf8Strict.GetString([IO.File]::ReadAllBytes($Path))
        $options = [Text.Json.JsonDocumentOptions]::new()
        $options.AllowTrailingCommas = $false
        $options.CommentHandling = [Text.Json.JsonCommentHandling]::Disallow
        $document = [Text.Json.JsonDocument]::Parse($text, $options)
        try {
            Assert-NoDuplicateJsonProperties $document.RootElement
            if ($document.RootElement.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw 'release_license_lock_json_invalid' }
        }
        finally { $document.Dispose() }
        return ($text | ConvertFrom-Json -Depth 100)
    }
    catch {
        if ($_.Exception.Message -match '^release_license_lock_') { throw }
        throw 'release_license_lock_json_invalid'
    }
}

function Get-ObjectProperties {
    param([object] $Value)
    if ($Value -is [Collections.IDictionary]) {
        foreach ($key in $Value.Keys) { [pscustomobject]@{ Name = [string]$key; Value = $Value[$key] } }
    }
    else { @($Value.PSObject.Properties) }
}

function Assert-EvidenceClean {
    param([object] $Value)
    if ($null -eq $Value) { return }
    if ($Value -is [string]) {
        if ($Value -ieq 'NOT_VERIFIED') { throw 'release_license_lock_not_verified' }
        return
    }
    if ($Value -is [Collections.IDictionary] -or $Value -is [pscustomobject]) {
        foreach ($property in Get-ObjectProperties $Value) {
            $name = [string]$property.Name
            $item = $property.Value
            if ($name -match '(?i)^blockers?$') {
                if ($null -ne $item -and @($item).Count -ne 0) { throw 'release_license_lock_blocked' }
            }
            elseif ($name -match '(?i)^blockerCount$') {
                if ([long]$item -ne 0) { throw 'release_license_lock_blocked' }
            }
            elseif ($name -match '(?i)^unclassified(?:Files?)?$') {
                if ($null -ne $item -and @($item).Count -ne 0) { throw 'release_license_lock_unclassified' }
            }
            elseif ($name -match '(?i)^unclassified(?:File)?Count$') {
                if ([long]$item -ne 0) { throw 'release_license_lock_unclassified' }
            }
            elseif ($name -match '(?i)rar.*count$' -and $null -ne $item -and [long]$item -ne 0) {
                throw 'release_license_lock_sevenzip_verification_invalid'
            }
            Assert-EvidenceClean $item
        }
        return
    }
    if ($Value -is [Collections.IEnumerable]) { foreach ($item in $Value) { Assert-EvidenceClean $item } }
}

function Assert-RelativePath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or
        -not [string]::Equals($Path, $Path.Normalize([Text.NormalizationForm]::FormC), [StringComparison]::Ordinal)) {
        throw 'release_license_lock_path_invalid'
    }
    $normalized = $Path.Replace('\', '/')
    if ($normalized.StartsWith('/', [StringComparison]::Ordinal) -or $normalized.EndsWith('/', [StringComparison]::Ordinal) -or
        $normalized.Contains('//') -or $normalized.Contains(':')) { throw 'release_license_lock_path_invalid' }
    foreach ($segment in $normalized.Split('/')) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -ceq '.' -or $segment -ceq '..') { throw 'release_license_lock_path_invalid' }
    }
    $normalized
}

function Get-ContainedPath {
    param([string] $Root, [string] $RelativePath)
    $normalized = Assert-RelativePath $RelativePath
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $result = [IO.Path]::GetFullPath((Join-Path $rootFull $normalized.Replace('/', [IO.Path]::DirectorySeparatorChar)))
    if (-not $result.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'release_license_lock_path_invalid'
    }
    $result
}

function Get-RepositoryRelativePath {
    param([string] $Repository, [string] $Path)
    $root = [IO.Path]::GetFullPath($Repository).TrimEnd('\', '/')
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'release_license_lock_path_invalid' }
    Assert-RelativePath ($full.Substring($root.Length + 1).Replace('\', '/'))
}

function Get-FileRecord {
    param([string] $Path, [string] $FileName = '')
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'release_license_lock_input_missing' }
    $item = Get-Item -LiteralPath $Path
    if ([string]::IsNullOrWhiteSpace($FileName)) { $FileName = $item.Name }
    [ordered]@{ fileName = $FileName; length = [long]$item.Length; sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
}

function Assert-FileIdentity {
    param([string] $Path, [object] $ExpectedSha256, [object] $ExpectedLength, [string] $ErrorId)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'release_license_lock_input_missing' }
    $sha = [string]$ExpectedSha256
    $length = 0L
    if ($sha -notmatch $script:Sha256Pattern -or -not [long]::TryParse([string]$ExpectedLength, [ref]$length) -or $length -lt 0) { throw $ErrorId }
    $actual = Get-FileRecord $Path
    if ($actual.length -ne $length -or $actual.sha256 -cne $sha.ToLowerInvariant()) { throw $ErrorId }
    $actual
}

function Get-Sha256FromStream {
    param([IO.Stream] $Stream)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($algorithm.ComputeHash($Stream))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Get-ZipInventory {
    param([string] $Path, [switch] $CaptureBuildConfiguration, [string] $CaseCollisionError = 'release_license_lock_archive_duplicate')
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'release_license_lock_input_missing' }
    $records = New-Object 'Collections.Generic.Dictionary[string, object]' ([StringComparer]::Ordinal)
    $caseFoldedNames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    try { $archive = [IO.Compression.ZipFile]::OpenRead($Path) }
    catch { throw 'release_license_lock_archive_invalid' }
    try {
        foreach ($entry in $archive.Entries) {
            if ([string]::IsNullOrEmpty($entry.Name)) { continue }
            $name = Assert-RelativePath $entry.FullName.Replace('\', '/')
            if ($records.ContainsKey($name)) { throw 'release_license_lock_archive_duplicate' }
            if (-not $caseFoldedNames.Add($name)) { throw $CaseCollisionError }
            $stream = $entry.Open()
            try { $sha = Get-Sha256FromStream $stream }
            finally { $stream.Dispose() }
            $record = [ordered]@{ path = $name; length = [long]$entry.Length; sha256 = $sha }
            if ($CaptureBuildConfiguration -and $name -ceq 'buildconf.txt') {
                if ($entry.Length -gt 1048576) { throw 'release_license_lock_ffmpeg_policy_invalid' }
                $reader = New-Object IO.StreamReader($entry.Open(), $script:Utf8Strict, $false)
                try { $record.text = $reader.ReadToEnd() }
                finally { $reader.Dispose() }
            }
            $records.Add($name, $record)
        }
    }
    finally { $archive.Dispose() }
    $records
}

function Assert-ZipRecord {
    param([Collections.Generic.Dictionary[string, object]] $Inventory, [string] $Name, [object] $Sha256, [object] $Length, [string] $ErrorId)
    $normalized = Assert-RelativePath $Name
    if (-not $Inventory.ContainsKey($normalized)) { throw $ErrorId }
    $record = $Inventory[$normalized]
    if ([string]$Sha256 -notmatch $script:Sha256Pattern -or $record.sha256 -cne ([string]$Sha256).ToLowerInvariant() -or $record.length -ne [long]$Length) { throw $ErrorId }
    $record
}

function Get-UniqueById {
    param([object[]] $Values, [string] $Id, [string] $ErrorId)
    $matches = @($Values | Where-Object { [string](Get-ExactProperty $_ 'id' $ErrorId) -ceq $Id })
    if ($matches.Count -ne 1) { throw $ErrorId }
    $matches[0]
}

function Get-UniqueSourceArchive {
    param([object] $Component, [string] $ErrorId)
    $archives = @(Get-ExactProperty $Component 'sourceArchives' $ErrorId)
    if ($archives.Count -ne 1) { throw $ErrorId }
    $archives[0]
}

function Assert-TemplateStatusIsUntrusted {
    param([object] $Template)
    $release = Get-ExactProperty $Template 'release'
    if ([string](Get-ExactProperty $release 'verificationStatus') -cne 'NOT_VERIFIED') { throw 'release_license_lock_template_status_invalid' }
    foreach ($component in @(Get-ExactProperty $Template 'components')) {
        if ([string](Get-ExactProperty $component 'verificationStatus') -cne 'NOT_VERIFIED') { throw 'release_license_lock_template_status_invalid' }
        foreach ($archive in @(Get-ExactProperty $component 'sourceArchives')) {
            if ([string](Get-ExactProperty $archive 'verificationStatus') -cne 'NOT_VERIFIED') { throw 'release_license_lock_template_status_invalid' }
        }
    }
}

function Get-CandidateContract {
    param([string] $Repository, [string] $CandidateRoot)
    $candidateRootFull = [IO.Path]::GetFullPath($CandidateRoot)
    if (-not (Test-Path -LiteralPath $candidateRootFull -PathType Container)) { throw 'release_license_lock_input_missing' }
    $manifestPath = Join-Path $candidateRootFull 'candidate-manifest.json'
    $manifest = Read-StrictJson $manifestPath
    if ([int](Get-ExactProperty $manifest 'schemaVersion') -ne 1) { throw 'release_license_lock_schema_unsupported' }
    $commit = [string](Get-ExactProperty $manifest 'applicationSourceCommit')
    $tree = [string](Get-ExactProperty $manifest 'applicationSourceTree')
    if ($commit -notmatch $script:CommitPattern -or $tree -notmatch $script:CommitPattern) { throw 'release_license_lock_application_identity_invalid' }
    $commit = $commit.ToLowerInvariant(); $tree = $tree.ToLowerInvariant()
    $attestation = Get-ExactProperty $manifest 'attestation'
    $source = Get-ExactProperty $attestation 'source'
    if ([string](Get-ExactProperty $source 'commit') -cne $commit) { throw 'release_license_lock_application_commit_mismatch' }
    $resolvedCommit = ((@(& git -C $Repository rev-parse --verify ($commit + '^{commit}') 2>&1) | Out-String).Trim()).ToLowerInvariant()
    if ($LASTEXITCODE -ne 0 -or $resolvedCommit -cne $commit) { throw 'release_license_lock_application_commit_invalid' }
    $resolvedTree = ((@(& git -C $Repository rev-parse --verify ($commit + '^{tree}') 2>&1) | Out-String).Trim()).ToLowerInvariant()
    if ($LASTEXITCODE -ne 0 -or $resolvedTree -notmatch $script:CommitPattern) { throw 'release_license_lock_application_commit_invalid' }
    if ($resolvedTree -cne $tree) { throw 'release_license_lock_application_tree_mismatch' }

    $records = New-Object 'Collections.Generic.Dictionary[string, object]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @(Get-ExactProperty $manifest 'files')) {
        $relative = Assert-RelativePath ([string](Get-ExactProperty $entry 'path'))
        if ($relative -ceq 'candidate-manifest.json' -or $records.ContainsKey($relative)) { throw 'release_license_lock_candidate_mismatch' }
        $path = Get-ContainedPath $candidateRootFull $relative
        $record = Assert-FileIdentity $path (Get-ExactProperty $entry 'sha256') (Get-ExactProperty $entry 'length') 'release_license_lock_candidate_mismatch'
        $record.path = $relative
        $records.Add($relative, $record)
    }
    $actual = @(Get-ChildItem -LiteralPath $candidateRootFull -File -Recurse | Where-Object { $_.FullName -ine $manifestPath })
    if ($actual.Count -ne $records.Count) { throw 'release_license_lock_candidate_mismatch' }
    foreach ($file in $actual) {
        $relative = Assert-RelativePath ($file.FullName.Substring($candidateRootFull.TrimEnd('\', '/').Length + 1).Replace('\', '/'))
        if (-not $records.ContainsKey($relative)) { throw 'release_license_lock_candidate_mismatch' }
    }
    $manifestRecord = Get-FileRecord $manifestPath 'candidate-manifest.json'
    $manifestRecord.path = 'candidate-manifest.json'
    $records.Add('candidate-manifest.json', $manifestRecord)
    if (-not $records.ContainsKey('ytdlp-interface.exe')) { throw 'release_license_lock_candidate_mismatch' }
    [pscustomobject]@{ Manifest = $manifest; ManifestPath = $manifestPath; Records = $records; Commit = $commit; Tree = $tree }
}

function Assert-LockCandidateFiles {
    param([object] $Release, [Collections.Generic.Dictionary[string, object]] $CandidateRecords)
    $declared = @(Get-ExactProperty $Release 'candidateFiles')
    if ($declared.Count -ne $CandidateRecords.Count) { throw 'release_license_lock_candidate_mismatch' }
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $declared) {
        $relative = Assert-RelativePath ([string](Get-ExactProperty $entry 'path'))
        if (-not $seen.Add($relative) -or -not $CandidateRecords.ContainsKey($relative)) { throw 'release_license_lock_candidate_mismatch' }
        foreach ($name in @('package', 'licenseConcluded')) {
            if ([string]::IsNullOrWhiteSpace([string](Get-ExactProperty $entry $name))) { throw 'release_license_lock_candidate_mismatch' }
        }
        $record = $CandidateRecords[$relative]
        Set-ExactProperty $entry 'sha256' $record.sha256
        Set-ExactProperty $entry 'length' ([long]$record.length)
    }
}

function Assert-NoticeAndSourceArchives {
    param([object[]] $Components, [string] $SourceRoot, [string] $ArchiveRoot)
    foreach ($component in $Components) {
        $commit = [string](Get-ExactProperty $component 'sourceCommit')
        if ($commit -notmatch $script:CommitPattern) { throw 'release_license_lock_component_invalid' }
        foreach ($notice in @(Get-ExactProperty $component 'noticeFiles')) {
            $path = Get-ContainedPath $SourceRoot ([string](Get-ExactProperty $notice 'path'))
            [void](Assert-FileIdentity $path (Get-ExactProperty $notice 'sha256') (Get-Item -LiteralPath $path).Length 'release_license_lock_notice_mismatch')
        }
        foreach ($archive in @(Get-ExactProperty $component 'sourceArchives')) {
            $fileName = Assert-RelativePath ([string](Get-ExactProperty $archive 'fileName'))
            if ($fileName.Contains('/')) { throw 'release_license_lock_path_invalid' }
            if ([string](Get-ExactProperty $archive 'commit') -cne $commit -or
                -not ([string](Get-ExactProperty $archive 'url')).EndsWith('/' + $commit + '.zip', [StringComparison]::Ordinal)) {
                throw 'release_license_lock_source_archive_mismatch'
            }
            $path = Get-ContainedPath $ArchiveRoot $fileName
            [void](Assert-FileIdentity $path (Get-ExactProperty $archive 'sha256') (Get-ExactProperty $archive 'length') 'release_license_lock_source_archive_mismatch')
        }
    }
}

function Assert-NonRuntimeContract {
    param(
        [object] $Manifest,
        [object] $Inventory,
        [object[]] $LockComponents,
        [Collections.Generic.Dictionary[string, object]] $CandidateRecords,
        [string] $ApplicationCommit,
        [string] $SourceArchiveRoot,
        [string] $BundlePath,
        [string] $ManifestPath,
        [string] $InventoryPath,
        [string] $CandidateManifestPath,
        [string] $SevenZipRuntimePath,
        [string] $SevenZipSourcePath,
        [string] $SevenZipVerificationPath
    )
    if ([string](Get-ExactProperty $Manifest 'schemaVersion') -cne 'karon-non-runtime-component-evidence/v1' -or
        [string](Get-ExactProperty $Inventory 'schemaVersion') -cne 'karon-source-cache-inventory/v1') { throw 'release_license_lock_schema_unsupported' }
    Assert-EvidenceClean $Manifest
    Assert-EvidenceClean $Inventory
    if ([string](Get-ExactProperty $Manifest 'release') -cne $script:ReleaseTag -or
        [string](Get-ExactProperty $Inventory 'release') -cne $script:ReleaseTag -or
        [string](Get-ExactProperty $Inventory 'scope') -cne 'non-ffmpeg-non-deno' -or
        [string](Get-ExactProperty $Inventory 'status') -cne 'closed') { throw 'release_license_lock_nonruntime_invalid' }
    $profile = [string](Get-ExactProperty $Manifest 'approvalProfile')
    $components = @(Get-ExactProperty $Manifest 'components')
    if ([int](Get-ExactProperty $Manifest 'expectedComponentCount') -ne $components.Count -or
        [string](Get-ExactProperty $Inventory 'approvalProfile') -cne $profile) { throw 'release_license_lock_nonruntime_invalid' }
    $manifestRecord = Get-FileRecord $ManifestPath
    $candidateRecord = Get-FileRecord $CandidateManifestPath
    if ([string](Get-ExactProperty $Inventory 'manifestSha256') -cne $manifestRecord.sha256 -or
        [string](Get-ExactProperty $Inventory 'applicationCommit') -cne $ApplicationCommit -or
        [string](Get-ExactProperty $Inventory 'candidateManifestSha256') -cne $candidateRecord.sha256 -or
        [long](Get-ExactProperty $Inventory 'candidateManifestLength') -ne $candidateRecord.length) {
        throw 'release_license_lock_nonruntime_binding_mismatch'
    }

    $artifacts = New-Object 'Collections.Generic.Dictionary[string, object]' ([StringComparer]::Ordinal)
    foreach ($artifact in @(Get-ExactProperty $Inventory 'artifacts')) {
        $id = [string](Get-ExactProperty $artifact 'id')
        if ([string]::IsNullOrWhiteSpace($id) -or $artifacts.ContainsKey($id) -or [string](Get-ExactProperty $artifact 'status') -cne 'verified') {
            throw 'release_license_lock_nonruntime_invalid'
        }
        $fileName = Assert-RelativePath ([string](Get-ExactProperty $artifact 'fileName'))
        if ($fileName.Contains('/')) { throw 'release_license_lock_path_invalid' }
        [void](Assert-FileIdentity (Get-ContainedPath $SourceArchiveRoot $fileName) (Get-ExactProperty $artifact 'sha256') (Get-ExactProperty $artifact 'length') 'release_license_lock_nonruntime_binding_mismatch')
        $artifacts.Add($id, $artifact)
    }

    $manifestArtifactIds = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($component in $components) {
        $id = [string](Get-ExactProperty $component 'id')
        $lockComponent = Get-UniqueById $LockComponents $id 'release_license_lock_nonruntime_binding_mismatch'
        foreach ($name in @('version', 'sourceRepository', 'sourceCommit', 'licenseExpression', 'buildRecipe')) {
            if ([string](Get-ExactProperty $component $name) -cne [string](Get-ExactProperty $lockComponent $name)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
        }
        if ([bool](Get-ExactProperty $component 'modified') -ne [bool](Get-ExactProperty $lockComponent 'modified')) { throw 'release_license_lock_nonruntime_binding_mismatch' }
        foreach ($binding in @(Get-ExactProperty (Get-ExactProperty $component 'candidateBinding') 'files')) {
            $relative = Assert-RelativePath ([string](Get-ExactProperty $binding 'path'))
            if (-not $CandidateRecords.ContainsKey($relative)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
            $record = $CandidateRecords[$relative]
            if ([string](Get-ExactProperty $binding 'sha256') -cne $record.sha256 -or [long](Get-ExactProperty $binding 'length') -ne $record.length) {
                throw 'release_license_lock_nonruntime_binding_mismatch'
            }
        }
        foreach ($sourceArtifact in @(Get-ExactProperty $component 'sourceArtifacts')) {
            $artifactId = [string](Get-ExactProperty $sourceArtifact 'id')
            if (-not $manifestArtifactIds.Add($artifactId) -or -not $artifacts.ContainsKey($artifactId)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
            $inventoryArtifact = $artifacts[$artifactId]
            foreach ($name in @('fileName', 'sha256', 'length')) {
                if ([string](Get-ExactProperty $sourceArtifact $name) -cne [string](Get-ExactProperty $inventoryArtifact $name)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
            }
        }
    }
    if ($manifestArtifactIds.Count -ne $artifacts.Count) { throw 'release_license_lock_unclassified' }

    $bundle = Get-ZipInventory $BundlePath
    [void](Assert-ZipRecord $bundle 'component-manifest.json' $manifestRecord.sha256 $manifestRecord.length 'release_license_lock_nonruntime_binding_mismatch')
    $inventoryRecord = Get-FileRecord $InventoryPath
    [void](Assert-ZipRecord $bundle 'source-cache-inventory.json' $inventoryRecord.sha256 $inventoryRecord.length 'release_license_lock_nonruntime_binding_mismatch')
    [void](Assert-ZipRecord $bundle 'evidence/candidate-manifest.json' $candidateRecord.sha256 $candidateRecord.length 'release_license_lock_nonruntime_binding_mismatch')
    foreach ($path in @($SevenZipRuntimePath, $SevenZipSourcePath, $SevenZipVerificationPath)) {
        $record = Get-FileRecord $path
        [void](Assert-ZipRecord $bundle ('evidence/task5/' + $record.fileName) $record.sha256 $record.length 'release_license_lock_nonruntime_binding_mismatch')
    }
    foreach ($component in $components) {
        foreach ($sourceArtifact in @(Get-ExactProperty $component 'sourceArtifacts')) {
            if ([bool](Get-ExactProperty $sourceArtifact 'includeInBundle')) {
                [void](Assert-ZipRecord $bundle ('sources/' + [string](Get-ExactProperty $sourceArtifact 'fileName')) (Get-ExactProperty $sourceArtifact 'sha256') (Get-ExactProperty $sourceArtifact 'length') 'release_license_lock_nonruntime_binding_mismatch')
            }
        }
    }
}

function Assert-SevenZipBaseContract {
    param([object] $NonRuntimeManifest, [object] $Verification, [Collections.Generic.Dictionary[string, object]] $CandidateRecords)
    Assert-EvidenceClean $Verification
    $task5 = Get-ExactProperty (Get-ExactProperty $NonRuntimeManifest 'sharedInputs') 'sevenZipTask5'
    foreach ($name in @('excludedObjects', 'sourceExclusions', 'requiredObjects')) {
        if (@(Get-ExactProperty $task5 $name).Count -eq 0) { throw 'release_license_lock_sevenzip_policy_invalid' }
    }
    if ([string](Get-ExactProperty $task5 'forbiddenPattern') -notmatch '(?i)rar') { throw 'release_license_lock_sevenzip_policy_invalid' }
    $runtime = Assert-FileIdentity $SevenZipRuntimeArchivePath (Get-ExactProperty $task5 'runtimeArchiveSha256') (Get-ExactProperty $task5 'runtimeArchiveLength') 'release_license_lock_sevenzip_binding_mismatch'
    $source = Assert-FileIdentity $SevenZipSourceArchivePath (Get-ExactProperty $task5 'sourceArchiveSha256') (Get-ExactProperty $task5 'sourceArchiveLength') 'release_license_lock_sevenzip_binding_mismatch'
    $verificationRecord = Assert-FileIdentity $SevenZipVerificationPath (Get-ExactProperty $task5 'verificationSha256') (Get-ExactProperty $task5 'verificationLength') 'release_license_lock_sevenzip_binding_mismatch'
    if (-not $CandidateRecords.ContainsKey('7z.dll')) { throw 'release_license_lock_sevenzip_binding_mismatch' }
    $dll = $CandidateRecords['7z.dll']
    if ([string](Get-ExactProperty $task5 'dllSha256') -cne $dll.sha256 -or [long](Get-ExactProperty $task5 'dllLength') -ne $dll.length -or
        [string](Get-ExactProperty $Verification 'runtimeArchiveSha256') -cne $runtime.sha256 -or
        [string](Get-ExactProperty $Verification 'correspondingSourceArchiveSha256') -cne $source.sha256 -or
        [string](Get-ExactProperty $Verification 'dllSha256') -cne $dll.sha256) { throw 'release_license_lock_sevenzip_binding_mismatch' }
    $exitCodes = New-Object Collections.Generic.List[long]
    function Add-SevenZipExitCodes([object] $Value) {
        if ($null -eq $Value -or $Value -is [string]) { return }
        if ($Value -is [Collections.IDictionary] -or $Value -is [pscustomobject]) {
            foreach ($property in Get-ObjectProperties $Value) {
                if ([string]$property.Name -match '(?i)exitCode$') { $exitCodes.Add([long]$property.Value) }
                Add-SevenZipExitCodes $property.Value
            }
        }
        elseif ($Value -is [Collections.IEnumerable]) { foreach ($item in $Value) { Add-SevenZipExitCodes $item } }
    }
    Add-SevenZipExitCodes $Verification
    if ($exitCodes.Count -lt 5 -or @($exitCodes | Where-Object { $_ -ne 0 }).Count -ne 0) { throw 'release_license_lock_sevenzip_verification_invalid' }
    [ordered]@{ runtimeArchive = $runtime; sourceArchive = $source; verification = $verificationRecord; dll = $dll }
}

function Assert-DenoBaseContract {
    param([object] $ComponentManifest, [object] $Inventory, [object] $LockComponent, [Collections.Generic.Dictionary[string, object]] $CandidateRecords)
    if ([string](Get-ExactProperty $ComponentManifest 'schemaVersion') -cne 'deno-third-party-components/v3' -or
        [string](Get-ExactProperty $Inventory 'schemaVersion') -cne 'deno-source-inventory/v2') { throw 'release_license_lock_schema_unsupported' }
    Assert-EvidenceClean $ComponentManifest
    Assert-EvidenceClean $Inventory
    if ([string](Get-ExactProperty $ComponentManifest 'closureClassification') -cne 'verified-conservative-superset') { throw 'release_license_lock_deno_closure_invalid' }
    $overallReleasePass = Get-ExactProperty $ComponentManifest 'overallReleasePass'
    if ($overallReleasePass -isnot [bool]) { throw 'release_license_lock_deno_closure_invalid' }
    if (-not $CandidateRecords.ContainsKey('deno.exe')) { throw 'release_license_lock_deno_artifact_mismatch' }
    $identity = Get-ExactProperty $ComponentManifest 'releaseIdentity'
    if ([string](Get-ExactProperty $identity 'version') -cne [string](Get-ExactProperty $LockComponent 'version') -or
        [string](Get-ExactProperty $identity 'sha256') -cne $CandidateRecords['deno.exe'].sha256) { throw 'release_license_lock_deno_artifact_mismatch' }
    $native = Get-ExactProperty $ComponentManifest 'nativeGitTreeEvidence'
    if ([string](Get-ExactProperty $native 'commit') -cne [string](Get-ExactProperty $LockComponent 'sourceCommit') -or
        [string](Get-ExactProperty $native 'tree') -notmatch $script:CommitPattern) { throw 'release_license_lock_deno_closure_invalid' }

    $digest = Get-ExactProperty $Inventory 'canonicalTreeDigest'
    if ([string](Get-ExactProperty $digest 'algorithm') -cne 'SHA-256' -or
        [string](Get-ExactProperty $digest 'serialization') -cne 'path|length|lowercase-sha256 followed by LF per record including trailing LF') {
        throw 'release_license_lock_deno_tree_mismatch'
    }
    $files = @(Get-ExactProperty $Inventory 'files')
    if ([long](Get-ExactProperty $digest 'recordCount') -ne $files.Count -or $files.Count -eq 0) { throw 'release_license_lock_deno_tree_mismatch' }
    $builder = New-Object Text.StringBuilder
    $previous = $null
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $seenCaseFolded = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $files) {
        $path = Assert-RelativePath ([string](Get-ExactProperty $file 'path'))
        $sha = [string](Get-ExactProperty $file 'sha256')
        $length = 0L
        if ($sha -notmatch '^[a-f0-9]{64}$' -or -not [long]::TryParse([string](Get-ExactProperty $file 'length'), [ref]$length) -or $length -lt 0 -or
            ($null -ne $previous -and [StringComparer]::Ordinal.Compare($previous, $path) -ge 0)) {
            throw 'release_license_lock_deno_tree_mismatch'
        }
        if (-not $seen.Add($path)) { throw 'release_license_lock_deno_tree_mismatch' }
        if (-not $seenCaseFolded.Add($path)) { throw 'release_license_lock_deno_case_collision' }
        [void]$builder.Append($path).Append('|').Append($length).Append('|').Append($sha).Append("`n")
        $previous = $path
    }
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { $actualDigest = ([BitConverter]::ToString($algorithm.ComputeHash($script:Utf8NoBom.GetBytes($builder.ToString())))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
    if ([string](Get-ExactProperty $digest 'sha256') -cne $actualDigest) { throw 'release_license_lock_deno_tree_mismatch' }

    $zip = Get-ZipInventory $DenoSourcesArchivePath -CaseCollisionError 'release_license_lock_deno_case_collision'
    if ($zip.Count -ne $files.Count) { throw 'release_license_lock_deno_artifact_mismatch' }
    foreach ($file in $files) {
        [void](Assert-ZipRecord $zip ([string](Get-ExactProperty $file 'path')) (Get-ExactProperty $file 'sha256') (Get-ExactProperty $file 'length') 'release_license_lock_deno_artifact_mismatch')
    }
    $noticesRecord = Get-FileRecord $DenoNoticesPath
    [void](Assert-ZipRecord $zip 'THIRD-PARTY-NOTICES.txt' $noticesRecord.sha256 $noticesRecord.length 'release_license_lock_deno_artifact_mismatch')
    $archive = Get-UniqueSourceArchive $LockComponent 'release_license_lock_deno_artifact_mismatch'
    $sourceRecord = Assert-FileIdentity $DenoSourcesArchivePath (Get-ExactProperty $archive 'sha256') (Get-ExactProperty $archive 'length') 'release_license_lock_source_archive_mismatch'
    [ordered]@{
        closureClassification = 'verified-conservative-superset'
        componentOverallReleasePass = [bool]$overallReleasePass
        inventorySchemaVersion = 'deno-source-inventory/v2'
        canonicalTreeDigest = [ordered]@{ algorithm = 'SHA-256'; serialization = [string](Get-ExactProperty $digest 'serialization'); recordCount = $files.Count; sha256 = $actualDigest }
        componentManifest = Get-FileRecord $DenoComponentManifestPath
        sourceInventory = Get-FileRecord $DenoSourceInventoryPath
        notices = $noticesRecord
        sourcesArchive = $sourceRecord
    }
}

function Get-IntegratorBoundFileRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    if (-not [IO.Path]::IsPathFullyQualified($Path)) {
        throw "${Context}_path_not_absolute"
    }
    if (@($Path -split '[\\/]' | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -ne 0) {
        throw "${Context}_path_escape"
    }

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "${Context}_missing"
    }
    if (($OutputPath) -and $fullPath.Equals([IO.Path]::GetFullPath($OutputPath), [StringComparison]::OrdinalIgnoreCase)) {
        throw "${Context}_output_alias"
    }

    $item = Get-Item -LiteralPath $fullPath -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "${Context}_path_alias"
    }

    $stream = [IO.File]::Open($fullPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = [Convert]::ToHexString($sha256.ComputeHash($stream)).ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
        $stream.Dispose()
    }

    return [pscustomobject][ordered]@{
        fileName = [IO.Path]::GetFileName($fullPath)
        length = [long]$item.Length
        sha256 = $digest
        fullPath = $fullPath
    }
}

function Get-IntegratorExactProperty {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    if ($null -eq $Object) {
        throw "${Context}_missing_property_$Name"
    }

    $matches = @($Object.PSObject.Properties | Where-Object { $_.Name -ceq $Name })
    if ($matches.Count -ne 1) {
        throw "${Context}_missing_property_$Name"
    }
    return $matches[0].Value
}

function Assert-IntegratorExactPropertySet {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string[]]$Expected,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    $actual = @($Object.PSObject.Properties.Name)
    if ($actual.Count -ne $Expected.Count) {
        throw "${Context}_unsupported_shape"
    }

    $expectedSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($name in $Expected) {
        [void]$expectedSet.Add($name)
    }
    foreach ($name in $actual) {
        if (-not $expectedSet.Remove($name)) {
            throw "${Context}_unsupported_shape"
        }
    }
    if ($expectedSet.Count -ne 0) {
        throw "${Context}_unsupported_shape"
    }
}

function ConvertFrom-IntegratorStrictJsonElement {
    param([Parameter(Mandatory = $true)][Text.Json.JsonElement]$Element)

    switch ($Element.ValueKind) {
        ([Text.Json.JsonValueKind]::Object) {
            $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $result = [ordered]@{}
            foreach ($property in $Element.EnumerateObject()) {
                if (-not $seen.Add($property.Name)) {
                    throw "deno_run_duplicate_property_$($property.Name)"
                }
                $result[$property.Name] = ConvertFrom-IntegratorStrictJsonElement -Element $property.Value
            }
            return [pscustomobject]$result
        }
        ([Text.Json.JsonValueKind]::Array) {
            $values = [Collections.Generic.List[object]]::new()
            foreach ($item in $Element.EnumerateArray()) {
                $values.Add((ConvertFrom-IntegratorStrictJsonElement -Element $item))
            }
            return ,$values.ToArray()
        }
        ([Text.Json.JsonValueKind]::String) {
            return $Element.GetString()
        }
        ([Text.Json.JsonValueKind]::Number) {
            [long]$integer = 0
            if ($Element.TryGetInt64([ref]$integer)) {
                return $integer
            }
            [decimal]$decimalValue = 0
            if ($Element.TryGetDecimal([ref]$decimalValue)) {
                return $decimalValue
            }
            throw 'deno_run_number_out_of_range'
        }
        ([Text.Json.JsonValueKind]::True) {
            return $true
        }
        ([Text.Json.JsonValueKind]::False) {
            return $false
        }
        ([Text.Json.JsonValueKind]::Null) {
            return $null
        }
        default {
            throw 'deno_run_unsupported_json_value'
        }
    }
}

function Read-IntegratorStrictJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $bytes = [IO.File]::ReadAllBytes($Path)
    $document = [Text.Json.JsonDocument]::Parse([ReadOnlyMemory[byte]]::new($bytes))
    try {
        return ConvertFrom-IntegratorStrictJsonElement -Element $document.RootElement
    }
    finally {
        $document.Dispose()
    }
}

function Assert-IntegratorEvidenceClean {
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Context
    )

    if ($null -eq $Value) {
        return
    }
    if ($Value -is [string]) {
        if ($Value.IndexOf('NOT_VERIFIED', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            throw "${Context}_not_verified"
        }
        return
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [pscustomobject] -and $Value -isnot [Collections.IDictionary]) {
        foreach ($item in $Value) {
            Assert-IntegratorEvidenceClean -Value $item -Context $Context
        }
        return
    }

    foreach ($property in $Value.PSObject.Properties) {
        if ($property.Name -match '^(blockerCount|blockers|unclassifiedFileCount|unclassifiedFiles)$') {
            $blockerValue = $property.Value
            $isZero = $null -eq $blockerValue
            if ($blockerValue -is [ValueType]) {
                $isZero = ([decimal]$blockerValue -eq 0)
            }
            elseif ($blockerValue -is [string]) {
                $isZero = [string]::IsNullOrWhiteSpace($blockerValue) -or $blockerValue -ceq '0'
            }
            elseif ($blockerValue -is [Collections.ICollection]) {
                $isZero = $blockerValue.Count -eq 0
            }
            if (-not $isZero) {
                throw "${Context}_blocker"
            }
        }
        Assert-IntegratorEvidenceClean -Value $property.Value -Context $Context
    }
}

function Get-IntegratorCanonicalDigest {
    param(
        [Parameter(Mandatory = $true)]
        [object]$BaseEvidence,

        [Parameter(Mandatory = $true)]
        [object]$Inventory
    )

    $baseProperty = @($BaseEvidence.PSObject.Properties | Where-Object {
        $_.Name -ceq 'canonicalTreeDigest' -or $_.Name -ceq 'canonicalTreeSha256'
    })
    if ($baseProperty.Count -eq 1) {
        $value = $baseProperty[0].Value
        if ($value -is [string]) {
            return $value.ToLowerInvariant()
        }
        $shaProperty = @($value.PSObject.Properties | Where-Object { $_.Name -ceq 'sha256' })
        if ($shaProperty.Count -eq 1 -and $shaProperty[0].Value -is [string]) {
            return $shaProperty[0].Value.ToLowerInvariant()
        }
    }

    $inventoryProperty = @($Inventory.PSObject.Properties | Where-Object {
        $_.Name -ceq 'canonicalTreeDigest' -or $_.Name -ceq 'canonicalTreeSha256'
    })
    if ($inventoryProperty.Count -ne 1) {
        throw 'deno_inventory_canonical_digest_missing'
    }
    $value = $inventoryProperty[0].Value
    if ($value -is [string]) {
        return $value.ToLowerInvariant()
    }
    $shaProperty = @($value.PSObject.Properties | Where-Object { $_.Name -ceq 'sha256' })
    if ($shaProperty.Count -eq 1 -and $shaProperty[0].Value -is [string]) {
        return $shaProperty[0].Value.ToLowerInvariant()
    }
    throw 'deno_inventory_canonical_digest_invalid'
}

function Assert-DenoContract {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ComponentManifest,

        [Parameter(Mandatory = $true)]
        [object]$Inventory,

        [Parameter(Mandatory = $true)]
        [object]$LockComponent,

        [Parameter(Mandatory = $true)]
        [object]$CandidateRecords
    )

    $approvedCollectorCommit = '09ced74a90248fbeb54969ea03d5aacb98dfc38b'
    if ($DenoCollectorSourceCommit -cne $approvedCollectorCommit) {
        throw 'release_license_lock_deno_collector_invalid'
    }

    try {
        $observedComponentSentinel = Get-IntegratorExactProperty `
            -Object $ComponentManifest `
            -Name 'overallReleasePass' `
            -Context 'deno_component_manifest'
        if ($observedComponentSentinel -isnot [bool] -or $observedComponentSentinel -ne $false) {
            throw 'invalid'
        }
    }
    catch {
        throw "release_license_lock_deno_sentinel_invalid: $($_.Exception.Message)"
    }

    $baseEvidence = Assert-DenoBaseContract `
        -ComponentManifest $ComponentManifest `
        -Inventory $Inventory `
        -LockComponent $LockComponent `
        -CandidateRecords $CandidateRecords

    try {
    $runRecord = Get-IntegratorBoundFileRecord -Path $DenoRunEvidencePath -Context 'deno_run_evidence'
    $componentRecord = Get-IntegratorBoundFileRecord -Path $DenoComponentManifestPath -Context 'deno_component_manifest'
    $inventoryRecord = Get-IntegratorBoundFileRecord -Path $DenoSourceInventoryPath -Context 'deno_source_inventory'
    $noticeRecord = Get-IntegratorBoundFileRecord -Path $DenoNoticesPath -Context 'deno_notices'
    $sourceRecord = Get-IntegratorBoundFileRecord -Path $DenoSourcesArchivePath -Context 'deno_source_zip'

    $run = Read-IntegratorStrictJson -Path $runRecord.fullPath
    Assert-IntegratorExactPropertySet -Object $run -Expected @(
        'exitCode',
        'elapsedMilliseconds',
        'elapsed',
        'result',
        'error'
    ) -Context 'deno_run'
    Assert-IntegratorEvidenceClean -Value $run -Context 'deno_run'
    Assert-IntegratorEvidenceClean -Value $ComponentManifest -Context 'deno_component_manifest'
    Assert-IntegratorEvidenceClean -Value $Inventory -Context 'deno_source_inventory'

    $noticeText = [IO.File]::ReadAllText($noticeRecord.fullPath, [Text.UTF8Encoding]::new($false, $true))
    if ($noticeText.IndexOf('NOT_VERIFIED', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw 'deno_notices_not_verified'
    }

    $exitCode = Get-IntegratorExactProperty -Object $run -Name 'exitCode' -Context 'deno_run'
    if ($exitCode -isnot [long] -or $exitCode -ne 0) {
        throw 'deno_run_exit_code_invalid'
    }
    if ($null -ne (Get-IntegratorExactProperty -Object $run -Name 'error' -Context 'deno_run')) {
        throw 'deno_run_error_present'
    }

    $result = Get-IntegratorExactProperty -Object $run -Name 'result' -Context 'deno_run'
    Assert-IntegratorExactPropertySet -Object $result -Expected @(
        'status',
        'closureClassification',
        'outputRoot',
        'noticePath',
        'noticeSha256',
        'zipPath',
        'zipSha256',
        'canonicalTreeSha256',
        'counts',
        'overallReleasePass'
    ) -Context 'deno_run_result'

    if ((Get-IntegratorExactProperty -Object $result -Name 'status' -Context 'deno_run_result') -cne 'complete') {
        throw 'deno_run_status_invalid'
    }
    $classification = Get-IntegratorExactProperty -Object $result -Name 'closureClassification' -Context 'deno_run_result'
    if ($classification -cne 'verified-conservative-superset') {
        throw 'deno_run_classification_invalid'
    }

    $runSentinel = Get-IntegratorExactProperty -Object $result -Name 'overallReleasePass' -Context 'deno_run_result'
    $componentSentinel = Get-IntegratorExactProperty -Object $ComponentManifest -Name 'overallReleasePass' -Context 'deno_component_manifest'
    if ($runSentinel -isnot [bool] -or $runSentinel -ne $false) {
        throw 'deno_run_overall_release_pass_invalid'
    }
    if ($componentSentinel -isnot [bool] -or $componentSentinel -ne $false) {
        throw 'deno_component_overall_release_pass_invalid'
    }

    $componentClassification = Get-IntegratorExactProperty -Object $ComponentManifest -Name 'closureClassification' -Context 'deno_component_manifest'
    if ($componentClassification -cne $classification) {
        throw 'deno_component_classification_mismatch'
    }

    $outputRootValue = Get-IntegratorExactProperty -Object $result -Name 'outputRoot' -Context 'deno_run_result'
    if ($outputRootValue -isnot [string] -or -not [IO.Path]::IsPathFullyQualified($outputRootValue)) {
        throw 'deno_run_output_root_invalid'
    }
    $outputRoot = [IO.Path]::GetFullPath($outputRootValue)
    if (-not (Test-Path -LiteralPath $outputRoot -PathType Container)) {
        throw 'deno_run_output_root_missing'
    }

    foreach ($record in @($componentRecord, $inventoryRecord, $noticeRecord, $sourceRecord)) {
        if (-not [IO.Path]::GetDirectoryName($record.fullPath).Equals($outputRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'deno_artifact_output_root_mismatch'
        }
    }

    $expectedFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in @($componentRecord, $inventoryRecord, $noticeRecord, $sourceRecord)) {
        [void]$expectedFiles.Add($record.fullPath)
    }
    $children = @(Get-ChildItem -LiteralPath $outputRoot -Force)
    $files = @($children | Where-Object { -not $_.PSIsContainer })
    $directories = @($children | Where-Object { $_.PSIsContainer })
    if ($directories.Count -ne 1 -or
        $directories[0].Name -cne 'bundle' -or
        ($directories[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'deno_output_scope_invalid'
    }
    if ($files.Count -ne 4) {
        throw 'deno_output_scope_invalid'
    }
    foreach ($child in $files) {
        if (-not $expectedFiles.Remove($child.FullName)) {
            throw 'deno_output_scope_invalid'
        }
    }
    if ($expectedFiles.Count -ne 0) {
        throw 'deno_output_scope_invalid'
    }

    $recordedNoticePath = Get-IntegratorExactProperty -Object $result -Name 'noticePath' -Context 'deno_run_result'
    $recordedZipPath = Get-IntegratorExactProperty -Object $result -Name 'zipPath' -Context 'deno_run_result'
    if (-not [IO.Path]::GetFullPath($recordedNoticePath).Equals($noticeRecord.fullPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'deno_run_notice_path_mismatch'
    }
    if (-not [IO.Path]::GetFullPath($recordedZipPath).Equals($sourceRecord.fullPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'deno_run_zip_path_mismatch'
    }
    if ((Get-IntegratorExactProperty -Object $result -Name 'noticeSha256' -Context 'deno_run_result') -cne $noticeRecord.sha256) {
        throw 'deno_run_notice_hash_mismatch'
    }
    if ((Get-IntegratorExactProperty -Object $result -Name 'zipSha256' -Context 'deno_run_result') -cne $sourceRecord.sha256) {
        throw 'deno_run_zip_hash_mismatch'
    }

    $canonicalDigest = Get-IntegratorCanonicalDigest -BaseEvidence $baseEvidence -Inventory $Inventory
    if ((Get-IntegratorExactProperty -Object $result -Name 'canonicalTreeSha256' -Context 'deno_run_result') -cne $canonicalDigest) {
        throw 'deno_run_canonical_digest_mismatch'
    }

    $runCounts = Get-IntegratorExactProperty -Object $result -Name 'counts' -Context 'deno_run_result'
    $componentCounts = Get-IntegratorExactProperty -Object $ComponentManifest -Name 'counts' -Context 'deno_component_manifest'
    $runCountNames = @($runCounts.PSObject.Properties.Name)
    $componentCountNames = @($componentCounts.PSObject.Properties.Name)
    if ($runCountNames.Count -eq 0 -or $runCountNames.Count -ne $componentCountNames.Count) {
        throw 'deno_run_counts_mismatch'
    }
    foreach ($property in $componentCounts.PSObject.Properties) {
        $runValue = Get-IntegratorExactProperty -Object $runCounts -Name $property.Name -Context 'deno_run_counts'
        if ($null -eq $runValue -or $null -eq $property.Value -or $runValue.GetType() -ne $property.Value.GetType() -or $runValue -ne $property.Value) {
            throw 'deno_run_counts_mismatch'
        }
    }

    return [pscustomobject][ordered]@{
        scope = 'deno-third-party-notice-source-closure'
        predicateVersion = 'deno-component-pass/v1'
        closureClassification = $classification
        componentPass = $true
        overallReleasePassObserved = $false
        collectorSourceCommit = $DenoCollectorSourceCommit
        evidence = [pscustomobject][ordered]@{
            runEvidence = [pscustomobject][ordered]@{
                fileName = $runRecord.fileName
                length = $runRecord.length
                sha256 = $runRecord.sha256
            }
            componentManifest = [pscustomobject][ordered]@{
                fileName = $componentRecord.fileName
                length = $componentRecord.length
                sha256 = $componentRecord.sha256
            }
            inventory = [pscustomobject][ordered]@{
                fileName = $inventoryRecord.fileName
                length = $inventoryRecord.length
                sha256 = $inventoryRecord.sha256
                schemaVersion = 'deno-source-inventory/v2'
                canonicalTreeDigest = $canonicalDigest
            }
            notices = [pscustomobject][ordered]@{
                fileName = $noticeRecord.fileName
                length = $noticeRecord.length
                sha256 = $noticeRecord.sha256
            }
            sourceZip = [pscustomobject][ordered]@{
                fileName = $sourceRecord.fileName
                length = $sourceRecord.length
                sha256 = $sourceRecord.sha256
            }
        }
    }
    }
    catch {
        $message = $_.Exception.Message
        if ($message -match '(?i)blocker|blocked') {
            throw "release_license_lock_blocked: $message"
        }
        if ($message -match '(?i)not_verified') {
            throw "release_license_lock_not_verified: $message"
        }
        if ($message -match '(?i)overall_release_pass') {
            throw "release_license_lock_deno_sentinel_invalid: $message"
        }
        if ($message -match '(?i)(path|hash|digest)_mismatch|artifact_output_root') {
            throw "release_license_lock_deno_artifact_mismatch: $message"
        }
        if ($message -match '(?i)output_scope_invalid') {
            throw "release_license_lock_deno_scope_invalid: $message"
        }
        throw "release_license_lock_deno_run_invalid: $message"
    }
}

function Assert-SevenZipContract {
    param(
        [Parameter(Mandatory = $true)]
        [object]$NonRuntimeManifest,

        [Parameter(Mandatory = $true)]
        [object]$Verification,

        [Parameter(Mandatory = $true)]
        [object]$CandidateRecords,

        [Parameter(Mandatory = $true)]
        [object[]]$LockComponents,

        [Parameter(Mandatory = $true)]
        [string]$SourceArchiveRoot
    )

    $rawSnapshot = Open-IntegratorLockedSnapshot -Path $SevenZipSourceArchivePath -Context 'sevenzip_raw_source'
    $wrapperSnapshot = Open-IntegratorLockedSnapshot -Path $SevenZipSourceWrapperPath -Context 'sevenzip_source_wrapper'

    $baseEvidence = Assert-SevenZipBaseContract `
        -NonRuntimeManifest $NonRuntimeManifest `
        -Verification $Verification `
        -CandidateRecords $CandidateRecords

    if ($rawSnapshot.fileName -cne '7z2601-x64-no-rar-source.7z') {
        throw 'sevenzip_raw_source_name_invalid'
    }
    if ($wrapperSnapshot.fileName -cne '7z2601-x64-no-rar-source.zip') {
        throw 'sevenzip_source_wrapper_name_invalid'
    }

    $sevenZipComponent = Get-UniqueById $LockComponents '7zip' 'release_license_lock_sevenzip_wrapper_binding_mismatch'
    $sourceArchives = @(Get-ExactProperty $sevenZipComponent 'sourceArchives')
    if ($sourceArchives.Count -ne 1) { throw 'release_license_lock_sevenzip_wrapper_binding_mismatch' }
    $sourceArchive = $sourceArchives[0]
    $canonicalWrapperPath = Get-ContainedPath $SourceArchiveRoot '7z2601-x64-no-rar-source.zip'
    if (-not $wrapperSnapshot.fullPath.Equals($canonicalWrapperPath, [StringComparison]::OrdinalIgnoreCase) -or
        [string](Get-ExactProperty $sourceArchive 'fileName') -cne $wrapperSnapshot.fileName -or
        [string](Get-ExactProperty $sourceArchive 'sha256') -cne $wrapperSnapshot.sha256 -or
        [long](Get-ExactProperty $sourceArchive 'length') -ne $wrapperSnapshot.length) {
        throw 'release_license_lock_sevenzip_wrapper_binding_mismatch'
    }

    $baseRawRecord = Get-ExactProperty $baseEvidence 'sourceArchive'
    if ([string](Get-ExactProperty $baseRawRecord 'sha256') -cne $rawSnapshot.sha256 -or
        [long](Get-ExactProperty $baseRawRecord 'length') -ne $rawSnapshot.length) {
        throw 'release_license_lock_sevenzip_binding_mismatch'
    }

    $stream = [IO.MemoryStream]::new([byte[]]$wrapperSnapshot.bytes, $false)
    $archive = $null
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $false, [Text.Encoding]::UTF8)
        $entries = @($archive.Entries)
        if ($entries.Count -ne 1) {
            throw 'release_license_lock_sevenzip_wrapper_mismatch'
        }
        $entry = $entries[0]
        if ($entry.FullName -cne 'sevenzip/7z2601-x64-no-rar-source.7z' -or
            $entry.Name -cne '7z2601-x64-no-rar-source.7z' -or
            $entry.Length -ne $rawSnapshot.length -or
            $entry.CompressedLength -ne $entry.Length) {
            throw 'release_license_lock_sevenzip_wrapper_mismatch'
        }

        $entryStream = $entry.Open()
        $innerBuffer = [IO.MemoryStream]::new()
        try {
            $entryStream.CopyTo($innerBuffer)
            $innerBytes = $innerBuffer.ToArray()
        }
        finally {
            $innerBuffer.Dispose()
            $entryStream.Dispose()
        }
    }
    finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
        else {
            $stream.Dispose()
        }
    }

    if ($innerBytes.Length -ne $rawSnapshot.bytes.Length) {
        throw 'release_license_lock_sevenzip_wrapper_mismatch'
    }
    for ($index = 0; $index -lt $innerBytes.Length; $index++) {
        if ($innerBytes[$index] -ne $rawSnapshot.bytes[$index]) {
            throw 'release_license_lock_sevenzip_wrapper_mismatch'
        }
    }
    $innerSha256 = $rawSnapshot.sha256

    $result = [ordered]@{}
    foreach ($property in $baseEvidence.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }
    $result['rawSourceArchive'] = [pscustomobject][ordered]@{
        fileName = $rawSnapshot.fileName
        length = $rawSnapshot.length
        sha256 = $rawSnapshot.sha256
    }
    $result['sourceWrapper'] = [pscustomobject][ordered]@{
        fileName = $wrapperSnapshot.fileName
        outerLength = $wrapperSnapshot.length
        outerSha256 = $wrapperSnapshot.sha256
        entryPath = 'sevenzip/7z2601-x64-no-rar-source.7z'
        innerLength = $rawSnapshot.length
        innerSha256 = $innerSha256
    }
    return [pscustomobject]$result
}


function Assert-FfmpegContract {
    param([object] $Manifest, [object] $LockComponent, [Collections.Generic.Dictionary[string, object]] $CandidateRecords)
    if ([int](Get-ExactProperty $Manifest 'schemaVersion') -ne 3) { throw 'release_license_lock_schema_unsupported' }
    Assert-EvidenceClean $Manifest
    if ([string](Get-ExactProperty $Manifest 'release') -cne $script:ReleaseTag -or
        [string](Get-ExactProperty $Manifest 'closureStatus') -cne 'complete' -or
        [string](Get-ExactProperty $Manifest 'closurePolicy') -cne 'verified-conservative-superset' -or
        @(Get-ExactProperty $Manifest 'unresolvedItems').Count -ne 0) { throw 'release_license_lock_ffmpeg_closure_invalid' }
    $counts = Get-ExactProperty $Manifest 'counts'
    $verifiedCount = [long](Get-ExactProperty $Manifest 'verifiedSourceRecordCount')
    if ($verifiedCount -le 0 -or $verifiedCount -ne [long](Get-ExactProperty $counts 'totalSourceArchives') -or
        [long](Get-ExactProperty $counts 'licenseTextObjects') -le 0 -or [long](Get-ExactProperty $counts 'licenseFileReferences') -le 0) {
        throw 'release_license_lock_ffmpeg_closure_invalid'
    }
    $binary = Get-ExactProperty $Manifest 'binary'
    $archiveName = [string](Get-ExactProperty $binary 'archiveName')
    if ($archiveName -notmatch '(?i)(?:^|[-_])lgpl(?:[-_.]|$)' -or $archiveName -match '(?i)(?:^|[-_])(?:gpl|nonfree)(?:[-_.]|$)') {
        throw 'release_license_lock_ffmpeg_policy_invalid'
    }
    if ([string](Get-ExactProperty $binary 'ffmpegCommit') -cne [string](Get-ExactProperty $LockComponent 'sourceCommit') -or
        -not $CandidateRecords.ContainsKey('ffmpeg.exe') -or -not $CandidateRecords.ContainsKey('ffprobe.exe') -or
        [string](Get-ExactProperty $binary 'ffmpegSha256') -cne $CandidateRecords['ffmpeg.exe'].sha256 -or
        [string](Get-ExactProperty $binary 'ffprobeSha256') -cne $CandidateRecords['ffprobe.exe'].sha256) { throw 'release_license_lock_ffmpeg_binary_mismatch' }
    $sourceArchive = Get-UniqueSourceArchive $LockComponent 'release_license_lock_source_archive_mismatch'
    $sourceRecord = Assert-FileIdentity $FfmpegSourcesArchivePath (Get-ExactProperty $sourceArchive 'sha256') (Get-ExactProperty $sourceArchive 'length') 'release_license_lock_source_archive_mismatch'
    $zip = Get-ZipInventory $FfmpegSourcesArchivePath -CaptureBuildConfiguration
    $included = @(Get-ExactProperty $Manifest 'includedPaths')
    if ($included.Count -ne $zip.Count -or $included -cnotcontains 'buildconf.txt' -or $included -cnotcontains 'NOTICE.md') { throw 'release_license_lock_ffmpeg_closure_invalid' }
    foreach ($path in $included) { if (-not $zip.ContainsKey((Assert-RelativePath ([string]$path)))) { throw 'release_license_lock_ffmpeg_closure_invalid' } }
    $buildConfiguration = [string]$zip['buildconf.txt'].text
    if ($buildConfiguration -match '(?im)^\s*--enable-(?:gpl|nonfree)(?:\s|$)') { throw 'release_license_lock_ffmpeg_policy_invalid' }
    [ordered]@{
        closureStatus = 'complete'; closurePolicy = 'verified-conservative-superset'; verifiedSourceRecordCount = $verifiedCount
        manifest = Get-FileRecord $FfmpegClosureManifestPath; sourcesArchive = $sourceRecord
        ffmpeg = $CandidateRecords['ffmpeg.exe']; ffprobe = $CandidateRecords['ffprobe.exe']
    }
}

function Assert-GuiCandidateRecord {
    param([object] $Candidate, [string] $Name, [Collections.Generic.Dictionary[string, object]] $CandidateRecords)
    if (-not $CandidateRecords.ContainsKey($Name)) { throw 'release_license_lock_gui_binding_mismatch' }
    $propertyName = switch ($Name) { 'ytdlp-interface.exe' { 'executable' }; 'ffprobe.exe' { 'ffprobe' }; default { 'manifest' } }
    $record = Get-ExactProperty $Candidate $propertyName 'release_license_lock_gui_binding_mismatch'
    $expected = $CandidateRecords[$Name]
    if ([string](Get-ExactProperty $record 'fileName') -cne $Name -or
        [string](Get-ExactProperty $record 'sha256') -cne $expected.sha256 -or
        [long](Get-ExactProperty $record 'length') -ne $expected.length) { throw 'release_license_lock_gui_binding_mismatch' }
}

function Assert-GuiContract {
    param([object] $Summary, [object] $Evidence, [Collections.Generic.Dictionary[string, object]] $CandidateRecords)
    foreach ($document in @($Summary, $Evidence)) {
        if ([int](Get-ExactProperty $document 'schemaVersion') -ne 2 -or
            [string](Get-ExactProperty $document 'releaseVersion') -cne $script:ReleaseTag) { throw 'release_license_lock_schema_unsupported' }
        Assert-EvidenceClean $document
        $candidate = Get-ExactProperty $document 'candidate'
        Assert-GuiCandidateRecord $candidate 'ytdlp-interface.exe' $CandidateRecords
        Assert-GuiCandidateRecord $candidate 'ffprobe.exe' $CandidateRecords
        Assert-GuiCandidateRecord $candidate 'candidate-manifest.json' $CandidateRecords
    }
    if ([string](Get-ExactProperty $Summary 'status') -cne 'PASS' -or (Test-ExactProperty $Evidence 'status')) { throw 'release_license_lock_gui_invalid' }
    $summaryCandidate = Get-ExactProperty $Summary 'candidate'
    $evidenceCandidate = Get-ExactProperty $Evidence 'candidate'
    foreach ($name in @('ytdlp-interface.exe', 'ffprobe.exe', 'candidate-manifest.json')) {
        $propertyName = switch ($name) { 'ytdlp-interface.exe' { 'executable' }; 'ffprobe.exe' { 'ffprobe' }; default { 'manifest' } }
        foreach ($field in @('fileName', 'sha256', 'length')) {
            if ([string](Get-ExactProperty (Get-ExactProperty $summaryCandidate $propertyName) $field) -cne
                [string](Get-ExactProperty (Get-ExactProperty $evidenceCandidate $propertyName) $field)) { throw 'release_license_lock_gui_binding_mismatch' }
        }
    }
    [ordered]@{
        summary = Get-FileRecord $GuiValidationSummaryPath
        evidenceManifest = Get-FileRecord $GuiValidationEvidenceManifestPath
        candidateExecutableSha256 = $CandidateRecords['ytdlp-interface.exe'].sha256
        candidateManifestSha256 = $CandidateRecords['candidate-manifest.json'].sha256
    }
}

function ConvertTo-CanonicalNode {
    param([object] $Value)
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [Collections.IDictionary] -or $Value -is [pscustomobject]) {
        $properties = @(Get-ObjectProperties $Value)
        $names = [string[]]@($properties | ForEach-Object { [string]$_.Name })
        [Array]::Sort($names, [StringComparer]::Ordinal)
        $ordered = [ordered]@{}
        foreach ($name in $names) {
            $property = @($properties | Where-Object { [string]$_.Name -ceq $name })[0]
            $ordered[$name] = ConvertTo-CanonicalNode $property.Value
        }
        return $ordered
    }
    if ($Value -is [Collections.IEnumerable]) {
        $items = @()
        foreach ($item in $Value) { $items += ,(ConvertTo-CanonicalNode $item) }
        return ,$items
    }
    $Value
}

function Write-AtomicOutput {
    param([string] $Path, [byte[]] $Bytes)
    if (Test-Path -LiteralPath $Path) { throw 'release_license_lock_output_exists' }
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    $temporary = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.partial.' + [Guid]::NewGuid().ToString('N'))
    try {
        $stream = New-Object IO.FileStream($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough)
        try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true) }
        finally { $stream.Dispose() }
        Move-Item -LiteralPath $temporary -Destination $Path -ErrorAction Stop
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue } }
}

try {
$allInputs = @(
    $TemplateLockPath, $NonRuntimeManifestPath, $NonRuntimeInventoryPath, $NonRuntimeEvidenceBundlePath,
    $DenoRunEvidencePath, $DenoComponentManifestPath, $DenoSourceInventoryPath, $DenoNoticesPath, $DenoSourcesArchivePath,
    $FfmpegClosureManifestPath, $FfmpegSourcesArchivePath, $SevenZipRuntimeArchivePath, $SevenZipSourceArchivePath,
    $SevenZipSourceWrapperPath, $SevenZipVerificationPath, $GuiValidationSummaryPath, $GuiValidationEvidenceManifestPath, $GuiValidationSchemaPath,
    $CorrespondingSourcesPath, $SpdxPath, $RootThirdPartyNoticesPath, $ReleaseNotesPath
)
foreach ($inputPath in $allInputs) { if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf)) { throw 'release_license_lock_input_missing' } }
if (-not (Test-Path -LiteralPath $RepositoryRoot -PathType Container) -or -not (Test-Path -LiteralPath $CandidateDirectory -PathType Container) -or
    -not (Test-Path -LiteralPath $SourceArchiveDirectory -PathType Container)) { throw 'release_license_lock_input_missing' }
if ([IO.Path]::GetFullPath($TemplateLockPath) -ieq [IO.Path]::GetFullPath($OutputPath)) { throw 'release_license_lock_output_must_be_new' }

$template = Read-StrictJson $TemplateLockPath
Assert-TemplateStatusIsUntrusted $template
if ([string](Get-ExactProperty $template 'schemaVersion') -cne 'karon-license-lock/v2') { throw 'release_license_lock_schema_unsupported' }
$release = Get-ExactProperty $template 'release'
if ([string](Get-ExactProperty $release 'tag') -cne $script:ReleaseTag -or [string](Get-ExactProperty $release 'platform') -cne 'win-x64') {
    throw 'release_license_lock_release_invalid'
}
$components = @(Get-ExactProperty $template 'components')
if ($components.Count -eq 0) { throw 'release_license_lock_component_invalid' }
$componentIds = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($component in $components) {
    $id = [string](Get-ExactProperty $component 'id')
    if ([string]::IsNullOrWhiteSpace($id) -or -not $componentIds.Add($id)) { throw 'release_license_lock_component_invalid' }
}

$candidate = Get-CandidateContract $RepositoryRoot $CandidateDirectory
Assert-LockCandidateFiles $release $candidate.Records
$metadata = Get-ExactProperty $release 'metadataPackage'
Set-ExactProperty $metadata 'sourceCommit' $candidate.Commit
$applicationComponent = Get-UniqueById $components 'application' 'release_license_lock_nonruntime_binding_mismatch'
if ([string](Get-ExactProperty $applicationComponent 'sourceCommit') -cne $candidate.Commit) { throw 'release_license_lock_nonruntime_binding_mismatch' }
$sourceRoot = Split-Path -Parent ([IO.Path]::GetFullPath($RootThirdPartyNoticesPath))
Assert-NoticeAndSourceArchives $components $sourceRoot $SourceArchiveDirectory

$nonRuntimeManifest = Read-StrictJson $NonRuntimeManifestPath
$nonRuntimeInventory = Read-StrictJson $NonRuntimeInventoryPath
$sevenZipVerification = Read-StrictJson $SevenZipVerificationPath
Assert-NonRuntimeContract $nonRuntimeManifest $nonRuntimeInventory $components $candidate.Records $candidate.Commit $SourceArchiveDirectory $NonRuntimeEvidenceBundlePath $NonRuntimeManifestPath $NonRuntimeInventoryPath $candidate.ManifestPath $SevenZipRuntimeArchivePath $SevenZipSourceArchivePath $SevenZipVerificationPath
$sevenZipEvidence = Assert-SevenZipContract $nonRuntimeManifest $sevenZipVerification $candidate.Records $components $SourceArchiveDirectory

$denoManifest = Read-StrictJson $DenoComponentManifestPath
$denoInventory = Read-StrictJson $DenoSourceInventoryPath
$denoComponent = Get-UniqueById $components 'deno' 'release_license_lock_deno_closure_invalid'
$denoEvidence = Assert-DenoContract $denoManifest $denoInventory $denoComponent $candidate.Records

$ffmpegManifest = Read-StrictJson $FfmpegClosureManifestPath
$ffmpegComponent = Get-UniqueById $components 'ffmpeg' 'release_license_lock_ffmpeg_closure_invalid'
$ffmpegEvidence = Assert-FfmpegContract $ffmpegManifest $ffmpegComponent $candidate.Records

$nonRuntimeIds = @((Get-ExactProperty $nonRuntimeManifest 'components') | ForEach-Object { [string](Get-ExactProperty $_ 'id') })
foreach ($id in $componentIds) {
    if ($id -cne 'deno' -and $id -cne 'ffmpeg' -and $nonRuntimeIds -cnotcontains $id) { throw 'release_license_lock_unclassified' }
}

$guiSummary = Read-StrictJson $GuiValidationSummaryPath
$guiEvidenceManifest = Read-StrictJson $GuiValidationEvidenceManifestPath
$guiEvidence = Assert-GuiContract $guiSummary $guiEvidenceManifest $candidate.Records

$guiSchemaRelative = Get-RepositoryRelativePath $RepositoryRoot $GuiValidationSchemaPath
$releaseNotesRelative = Get-RepositoryRelativePath $RepositoryRoot $ReleaseNotesPath
$receiptInputs = [ordered]@{
    candidateManifest = Get-FileRecord $candidate.ManifestPath 'candidate-manifest.json'
    correspondingSources = Get-FileRecord $CorrespondingSourcesPath
    spdx = Get-FileRecord $SpdxPath
    rootThirdPartyNotices = Get-FileRecord $RootThirdPartyNoticesPath
    guiValidationSummary = Get-FileRecord $GuiValidationSummaryPath 'gui-validation-summary.json'
    guiValidationEvidenceManifest = Get-FileRecord $GuiValidationEvidenceManifestPath 'gui-validation-evidence-manifest.json'
    guiValidationSchema = [ordered]@{ path = $guiSchemaRelative; length = [long](Get-Item $GuiValidationSchemaPath).Length; sha256 = (Get-FileHash $GuiValidationSchemaPath -Algorithm SHA256).Hash.ToLowerInvariant() }
    releaseNotes = [ordered]@{ path = $releaseNotesRelative; length = [long](Get-Item $ReleaseNotesPath).Length; sha256 = (Get-FileHash $ReleaseNotesPath -Algorithm SHA256).Hash.ToLowerInvariant() }
}

$integrationEvidence = [ordered]@{
    schemaVersion = 'karon-release-license-lock-integration/v1'
    applicationSource = [ordered]@{ commit = $candidate.Commit; tree = $candidate.Tree }
    candidate = [ordered]@{ manifest = Get-FileRecord $candidate.ManifestPath; executable = $candidate.Records['ytdlp-interface.exe'] }
    nonRuntime = [ordered]@{
        manifest = Get-FileRecord $NonRuntimeManifestPath
        inventory = Get-FileRecord $NonRuntimeInventoryPath
        evidenceBundle = Get-FileRecord $NonRuntimeEvidenceBundlePath
        applicationSourceCommit = $candidate.Commit
        applicationSourceTree = $candidate.Tree
    }
    denoComponent = $denoEvidence
    ffmpeg = $ffmpegEvidence
    sevenZip = $sevenZipEvidence
    gui = $guiEvidence
}
Set-ExactProperty $release 'receiptInputs' $receiptInputs
Set-ExactProperty $release 'integrationEvidence' $integrationEvidence

foreach ($component in $components) {
    Set-ExactProperty $component 'verificationStatus' 'verified'
    Set-ExactProperty $component 'blockers' @()
    foreach ($archive in @(Get-ExactProperty $component 'sourceArchives')) {
        Set-ExactProperty $archive 'verificationStatus' 'verified'
        Set-ExactProperty $archive 'blockers' @()
    }
}
Set-ExactProperty $release 'verificationStatus' 'verified'
Set-ExactProperty $release 'blockers' @()

$canonical = ConvertTo-CanonicalNode $template
$json = $canonical | ConvertTo-Json -Depth 100 -Compress
$bytes = $script:Utf8NoBom.GetBytes($json + "`n")
Write-AtomicOutput ([IO.Path]::GetFullPath($OutputPath)) $bytes
Write-Output ([IO.Path]::GetFullPath($OutputPath))
}
finally {
    Close-IntegratorLockedSnapshots
}
