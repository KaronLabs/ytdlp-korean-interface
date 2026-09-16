param(
    [Parameter(Mandatory = $true)] [string] $RepositoryRoot,
    [Parameter(Mandatory = $true)] [string] $TemplateLockPath,
    [Parameter(Mandatory = $true)] [string] $CandidateDirectory,
    [Parameter(Mandatory = $true)] [string] $SourceArchiveDirectory,
    [Parameter(Mandatory = $true)] [string] $NonRuntimeManifestPath,
    [Parameter(Mandatory = $true)] [string] $NonRuntimeInventoryPath,
    [Parameter(Mandatory = $true)] [string] $NonRuntimeEvidenceBundlePath,
    [Parameter(Mandatory = $true)] [string] $DenoComponentManifestPath,
    [Parameter(Mandatory = $true)] [string] $DenoSourceInventoryPath,
    [Parameter(Mandatory = $true)] [string] $DenoNoticesPath,
    [Parameter(Mandatory = $true)] [string] $DenoSourcesArchivePath,
    [Parameter(Mandatory = $true)] [string] $FfmpegClosureManifestPath,
    [Parameter(Mandatory = $true)] [string] $FfmpegSourcesArchivePath,
    [Parameter(Mandatory = $true)] [string] $SevenZipRuntimeArchivePath,
    [Parameter(Mandatory = $true)] [string] $SevenZipSourceArchivePath,
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
    param([string] $Path, [switch] $CaptureBuildConfiguration)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'release_license_lock_input_missing' }
    $records = New-Object 'Collections.Generic.Dictionary[string, object]' ([StringComparer]::Ordinal)
    try { $archive = [IO.Compression.ZipFile]::OpenRead($Path) }
    catch { throw 'release_license_lock_archive_invalid' }
    try {
        foreach ($entry in $archive.Entries) {
            if ([string]::IsNullOrEmpty($entry.Name)) { continue }
            $name = Assert-RelativePath $entry.FullName.Replace('\', '/')
            if ($records.ContainsKey($name)) { throw 'release_license_lock_archive_duplicate' }
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

function Assert-SevenZipContract {
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

function Assert-DenoContract {
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
    foreach ($file in $files) {
        $path = Assert-RelativePath ([string](Get-ExactProperty $file 'path'))
        $sha = [string](Get-ExactProperty $file 'sha256')
        $length = 0L
        if ($sha -notmatch '^[a-f0-9]{64}$' -or -not [long]::TryParse([string](Get-ExactProperty $file 'length'), [ref]$length) -or $length -lt 0 -or
            -not $seen.Add($path) -or ($null -ne $previous -and [StringComparer]::Ordinal.Compare($previous, $path) -ge 0)) {
            throw 'release_license_lock_deno_tree_mismatch'
        }
        [void]$builder.Append($path).Append('|').Append($length).Append('|').Append($sha).Append("`n")
        $previous = $path
    }
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { $actualDigest = ([BitConverter]::ToString($algorithm.ComputeHash($script:Utf8NoBom.GetBytes($builder.ToString())))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
    if ([string](Get-ExactProperty $digest 'sha256') -cne $actualDigest) { throw 'release_license_lock_deno_tree_mismatch' }

    $zip = Get-ZipInventory $DenoSourcesArchivePath
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

$allInputs = @(
    $TemplateLockPath, $NonRuntimeManifestPath, $NonRuntimeInventoryPath, $NonRuntimeEvidenceBundlePath,
    $DenoComponentManifestPath, $DenoSourceInventoryPath, $DenoNoticesPath, $DenoSourcesArchivePath,
    $FfmpegClosureManifestPath, $FfmpegSourcesArchivePath, $SevenZipRuntimeArchivePath, $SevenZipSourceArchivePath,
    $SevenZipVerificationPath, $GuiValidationSummaryPath, $GuiValidationEvidenceManifestPath, $GuiValidationSchemaPath,
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
$sevenZipEvidence = Assert-SevenZipContract $nonRuntimeManifest $sevenZipVerification $candidate.Records

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
    deno = $denoEvidence
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
