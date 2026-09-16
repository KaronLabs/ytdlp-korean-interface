param(
    [Parameter(Mandatory = $true)] [string] $ManifestPath,
    [Parameter(Mandatory = $true)] [string] $SourceCacheDirectory,
    [Parameter(Mandatory = $true)] [string] $OutputDirectory,
    [Parameter(Mandatory = $true)] [string] $ApplicationRepository,
    [AllowEmptyString()] [string] $ApplicationCommit = '',
    [AllowEmptyString()] [string] $CandidateManifestPath = '',
    [Parameter(Mandatory = $true)] [string] $DependencyArchivePath,
    [Parameter(Mandatory = $true)] [string] $SevenZipRuntimeArchivePath,
    [Parameter(Mandatory = $true)] [string] $SevenZipSourceArchivePath,
    [Parameter(Mandatory = $true)] [string] $SevenZipVerificationPath,
    [Parameter(Mandatory = $true)] [string] $YtDlpBinaryPath,
    [AllowEmptyString()] [string] $SevenZipExecutable = '',
    [switch] $AcquireSources
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.IO.Compression.FileSystem

$utf8NoBom = New-Object Text.UTF8Encoding($false)
$script:blockers = New-Object 'Collections.Generic.List[string]'
$script:blockerSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$script:temporaryDirectories = New-Object 'Collections.Generic.List[string]'

function Add-EvidenceBlocker {
    param([Parameter(Mandatory = $true)] [string] $Code)
    if ($script:blockerSet.Add($Code)) { $script:blockers.Add($Code) }
}

function Get-ObjectProperty {
    param([object] $Value, [string] $Name)
    if ($null -eq $Value) { return $null }
    if ($Value -is [Collections.IDictionary] -and $Value.Contains($Name)) { return $Value[$Name] }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-BytesSha256 {
    param([Parameter(Mandatory = $true)] [byte[]] $Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Get-PathSha256 {
    param([Parameter(Mandatory = $true)] [string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function ConvertTo-CanonicalJsonBytes {
    param([Parameter(Mandatory = $true)] [object] $Value)
    return $utf8NoBom.GetBytes(($Value | ConvertTo-Json -Depth 50 -Compress) + [char]10)
}

function Write-AtomicBytes {
    param([string] $Path, [byte[]] $Bytes)
    if (Test-Path -LiteralPath $Path) { throw "output_exists:$Path" }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    $partial = $Path + '.partial.' + $PID + '.' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllBytes($partial, $Bytes)
        [IO.File]::Move($partial, $Path)
    }
    finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    }
}

function New-TemporaryDirectory {
    param([string] $Label)
    $path = Join-Path ([IO.Path]::GetTempPath()) ('karon-' + $Label + '-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($path) | Out-Null
    $script:temporaryDirectories.Add($path)
    return $path
}

function Test-ChildPath {
    param([string] $Root, [string] $Path)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $pathFull = [IO.Path]::GetFullPath($Path)
    return $pathFull.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Test-ImmutableSourceUrl {
    param([string] $Url)
    if ([string]::IsNullOrWhiteSpace($Url) -or $Url -notmatch '^https://') { return $false }
    if ($Url -match '(?i)/(?:main|master|latest)(?:[./]|$)') { return $false }
    if ($Url -match '(?i)^https://github\.com/[^/]+/[^/]+/archive/[0-9a-f]{40}\.zip$') { return $true }
    if ($Url -match '(?i)^https://raw\.githubusercontent\.com/[^/]+/[^/]+/[0-9a-f]{40}/.+$') { return $true }
    if ($Url -match '(?i)^https://github\.com/[^/]+/[^/]+/releases/download/[^/?#]+/[^?#]+$') { return $true }
    if ($Url -match '(?i)^https://api\.nuget\.org/v3-flatcontainer/[a-z0-9_.-]+/[0-9]+(?:\.[0-9]+){1,3}/[a-z0-9_.-]+\.nupkg$') { return $true }
    return $false
}

function Get-ZipEntryBytes {
    param([string] $ArchivePath, [string] $EntryPath)
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $matches = @($archive.Entries | Where-Object { $_.FullName -ceq $EntryPath })
        if ($matches.Count -ne 1) { return $null }
        $memory = New-Object IO.MemoryStream
        $stream = $matches[0].Open()
        try { $stream.CopyTo($memory) }
        finally { $stream.Dispose() }
        return ,$memory.ToArray()
    }
    finally { $archive.Dispose() }
}

function Expand-SafeZip {
    param([string] $ArchivePath, [string] $Destination)
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    $names = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ([string]::IsNullOrWhiteSpace($name) -or $name.StartsWith('/') -or $name -match '(^|/)\.\.(/|$)' -or -not $names.Add($name)) {
                throw 'archive_path_or_case_collision'
            }
            if ($name.EndsWith('/')) { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $name.Replace('/', '\')))
            if (-not (Test-ChildPath -Root $Destination -Path $target)) { throw 'archive_path_escape' }
            [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
            $source = $entry.Open()
            $output = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $source.CopyTo($output) }
            finally { $output.Dispose(); $source.Dispose() }
        }
    }
    finally { $archive.Dispose() }
}

function Expand-EvidenceArchive {
    param([string] $ArchivePath, [string] $Format, [string] $Destination)
    if ($Format -ceq 'zip') { Expand-SafeZip -ArchivePath $ArchivePath -Destination $Destination; return }
    if ($Format -cne '7z' -or [string]::IsNullOrWhiteSpace($SevenZipExecutable) -or -not (Test-Path -LiteralPath $SevenZipExecutable -PathType Leaf)) {
        throw 'sevenzip_extractor_required'
    }
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    & $SevenZipExecutable 'x' '-y' ('-o' + $Destination) $ArchivePath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "sevenzip_extract_failed:$LASTEXITCODE" }
    foreach ($entry in @(Get-ChildItem -LiteralPath $Destination -Force -Recurse)) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or -not (Test-ChildPath -Root $Destination -Path $entry.FullName)) {
            throw 'archive_reparse_or_escape'
        }
    }
}

function Get-OrderedTreeEvidence {
    param([string] $Root)
    $basePath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $basePrefix = $basePath + [IO.Path]::DirectorySeparatorChar
    $files = @(Get-ChildItem -LiteralPath $basePath -File -Recurse)
    $rows = New-Object 'Collections.Generic.List[string]'
    foreach ($file in $files) {
        $fullPath = [IO.Path]::GetFullPath($file.FullName)
        if (-not $fullPath.StartsWith($basePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Tree file escaped root: $fullPath"
        }
        $relative = $fullPath.Substring($basePrefix.Length).Replace('\', '/')
        $rows.Add($relative + [char]0 + $file.Length + [char]0 + (Get-PathSha256 $file.FullName).ToLowerInvariant() + [char]10)
    }
    $ordered = $rows.ToArray()
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    $length = [long](($files | Measure-Object Length -Sum).Sum)
    if ($files.Count -eq 0) { $length = 0 }
    return [ordered]@{
        fileCount = $files.Count
        length = $length
        orderedTreeSha256 = Get-BytesSha256 $utf8NoBom.GetBytes(($ordered -join ''))
    }
}

function Get-OrderedChunkDigest {
    param([byte[]] $Bytes)
    $rows = New-Object 'Collections.Generic.List[string]'
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $chunkSize = 65536
        $index = 0
        for ($offset = 0; $offset -lt $Bytes.Length; $offset += $chunkSize) {
            $length = [Math]::Min($chunkSize, $Bytes.Length - $offset)
            $chunk = New-Object byte[] $length
            [Array]::Copy($Bytes, $offset, $chunk, 0, $length)
            $chunkHash = ([BitConverter]::ToString($sha.ComputeHash($chunk))).Replace('-', '').ToLowerInvariant()
            $rows.Add($index.ToString('D8') + [char]0 + $length + [char]0 + $chunkHash + "`r`n")
            $index++
        }
        return ([BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes(($rows -join ''))))).Replace('-', '').ToUpperInvariant()
    }
    finally { $sha.Dispose() }
}

function Test-FileIdentity {
    param([string] $Path, [string] $ExpectedSha256, [long] $ExpectedLength)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $file = Get-Item -LiteralPath $Path
    return $file.Length -eq $ExpectedLength -and (Get-PathSha256 $Path) -ceq $ExpectedSha256.ToUpperInvariant()
}

function Acquire-SourceArtifact {
    param([object] $Artifact, [string] $Destination)
    if (Test-Path -LiteralPath $Destination) { return }
    if (-not $AcquireSources) { return }
    $partial = $Destination + '.partial.' + $PID + '.' + [Guid]::NewGuid().ToString('N')
    try {
        Invoke-WebRequest -UseBasicParsing -Uri ([string]$Artifact.url) -OutFile $partial
        if (-not (Test-FileIdentity -Path $partial -ExpectedSha256 ([string]$Artifact.sha256) -ExpectedLength ([long]$Artifact.length))) {
            throw 'downloaded_source_identity_mismatch'
        }
        try { [IO.File]::Move($partial, $Destination) }
        catch {
            if (-not (Test-FileIdentity -Path $Destination -ExpectedSha256 ([string]$Artifact.sha256) -ExpectedLength ([long]$Artifact.length))) { throw }
        }
    }
    finally { if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue } }
}

function New-DeterministicZip {
    param([string] $OutputPath, [object[]] $Entries)
    $nameSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $Entries) {
        if (-not $nameSet.Add([string]$entry.name)) { throw 'bundle_entry_case_collision' }
    }
    $partial = $OutputPath + '.partial.' + $PID + '.' + [Guid]::NewGuid().ToString('N')
    $stream = $null
    $archive = $null
    try {
        $stream = [IO.File]::Open($partial, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        foreach ($item in @($Entries | Sort-Object { [string]$_.name })) {
            $zipEntry = $archive.CreateEntry(([string]$item.name).Replace('\', '/'), [IO.Compression.CompressionLevel]::Optimal)
            $zipEntry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
            $target = $zipEntry.Open()
            try {
                if ($null -ne (Get-ObjectProperty -Value $item -Name 'path')) {
                    $source = [IO.File]::OpenRead([string]$item.path)
                    try { $source.CopyTo($target) }
                    finally { $source.Dispose() }
                }
                else {
                    $bytes = [byte[]]$item.bytes
                    $target.Write($bytes, 0, $bytes.Length)
                }
            }
            finally { $target.Dispose() }
        }
        $archive.Dispose(); $archive = $null
        $stream.Dispose(); $stream = $null
        [IO.File]::Move($partial, $OutputPath)
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    }
}

function Get-ComponentById {
    param([object] $Manifest, [string] $Id)
    return @($Manifest.components | Where-Object { [string]$_.id -ceq $Id }) | Select-Object -First 1
}

function Get-CandidateFile {
    param([object] $Candidate, [string] $Path)
    return @($Candidate.files | Where-Object { ([string]$_.path).Replace('\', '/') -ieq $Path.Replace('\', '/') }) | Select-Object -First 1
}

$manifest = $null
$manifestBytes = $null
$manifestSha256 = $null
$artifactById = @{}
$artifactValid = @{}
$inventoryRecords = New-Object 'Collections.Generic.List[object]'
$bundleEntries = New-Object 'Collections.Generic.List[object]'
$nlohmannEvidenceBytes = $null
$applicationSourceArchive = $null
$candidate = $null
$dependencyExtracted = $null
$task5RuntimeExtracted = $null
$task5SourceExtracted = $null

try {
    [IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($SourceCacheDirectory)) | Out-Null
    [IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory)) | Out-Null
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw 'component_manifest_missing' }
    $manifestBytes = [IO.File]::ReadAllBytes($ManifestPath)
    $manifestSha256 = Get-BytesSha256 $manifestBytes
    $manifestText = $utf8NoBom.GetString($manifestBytes)
    if ($manifestText -match '(?i)NOASSERTION') { Add-EvidenceBlocker 'forbidden_license_assertion' }
    $manifest = $manifestText | ConvertFrom-Json
}
catch {
    Add-EvidenceBlocker ('component_manifest_invalid:' + $_.Exception.Message)
}

if ($null -ne $manifest) {
    if ([string]$manifest.schemaVersion -cne 'karon-non-runtime-component-evidence/v1' -or
        [string]$manifest.release.tag -cne 'v2.19.1-karon.2' -or [string]$manifest.release.platform -cne 'win-x64') {
        Add-EvidenceBlocker 'component_manifest_contract_mismatch'
    }
    $expectedIds = @('7zip', 'application', 'bit7z', 'cpm', 'libjpeg-turbo', 'libpng', 'nana', 'nlohmann-json', 'yt-dlp', 'zlib')
    $actualIds = @($manifest.components | ForEach-Object { [string]$_.id })
    $idSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $actualIds) { if ([string]::IsNullOrWhiteSpace($id) -or -not $idSet.Add($id)) { Add-EvidenceBlocker 'component_id_collision' } }
    if ($actualIds.Count -ne [int]$manifest.release.expectedComponentCount -or $actualIds.Count -ne $expectedIds.Count) { Add-EvidenceBlocker 'component_count_mismatch' }
    foreach ($id in $expectedIds) { if (-not $idSet.Contains($id)) { Add-EvidenceBlocker ('component_missing:' + $id) } }
    foreach ($excluded in @($manifest.release.excludedComponents)) { if ($idSet.Contains([string]$excluded)) { Add-EvidenceBlocker ('excluded_component_present:' + $excluded) } }

    $fileNameSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $artifactIdSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($component in @($manifest.components)) {
        if ([string]::IsNullOrWhiteSpace([string]$component.licenseExpression) -or [string]$component.licenseExpression -match '(?i)NOASSERTION') {
            Add-EvidenceBlocker ('license_expression_missing:' + [string]$component.id)
        }
        if ([string]$component.id -cne 'application' -and [string]$component.sourceCommit -notmatch '^[0-9a-f]{40}$') {
            Add-EvidenceBlocker ('source_commit_invalid:' + [string]$component.id)
        }
        if ($null -eq (Get-ObjectProperty $component 'buildRecipe') -or $null -eq (Get-ObjectProperty $component.buildRecipe 'candidateBinding')) {
            Add-EvidenceBlocker ('candidate_binding_missing:' + [string]$component.id)
        }
        foreach ($artifact in @($component.sourceArtifacts)) {
            $id = [string]$artifact.id
            $fileName = [string]$artifact.fileName
            if (-not $artifactIdSet.Add($id)) { Add-EvidenceBlocker 'source_artifact_id_collision' }
            if (-not $fileNameSet.Add($fileName)) { Add-EvidenceBlocker 'source_cache_name_collision' }
            if (-not (Test-ImmutableSourceUrl ([string]$artifact.url))) { Add-EvidenceBlocker ('mutable_source_url:' + $id) }
            $artifactById[$id] = $artifact
            $path = Join-Path $SourceCacheDirectory $fileName
            try { Acquire-SourceArtifact -Artifact $artifact -Destination $path }
            catch { Add-EvidenceBlocker ('source_acquire_failed:' + $id) }
            $exists = Test-Path -LiteralPath $path -PathType Leaf
            $actualSha = $null
            $actualLength = $null
            $valid = $false
            if ($exists) {
                $file = Get-Item -LiteralPath $path
                $actualLength = [long]$file.Length
                $actualSha = Get-PathSha256 $path
                $valid = $actualLength -eq [long]$artifact.length -and $actualSha -ceq ([string]$artifact.sha256).ToUpperInvariant()
            }
            if (-not $exists) { Add-EvidenceBlocker ('source_missing:' + $id) }
            elseif (-not $valid) { Add-EvidenceBlocker ('source_hash_mismatch:' + $id) }
            $artifactValid[$id] = $valid
            $inventoryRecords.Add([ordered]@{
                id = $id; component = [string]$component.id; fileName = $fileName; url = [string]$artifact.url
                expectedSha256 = ([string]$artifact.sha256).ToUpperInvariant(); expectedLength = [long]$artifact.length
                actualSha256 = $actualSha; actualLength = $actualLength; status = $(if ($valid) { 'verified' } elseif ($exists) { 'mismatch' } else { 'missing' })
                includeInBundle = [bool]$artifact.includeInBundle
            })
        }
    }

    foreach ($component in @($manifest.components)) {
        foreach ($license in @($component.licenseTexts)) {
            $kind = [string]$license.kind
            if ($kind -ceq 'archive-entry') {
                $artifactId = [string]$license.sourceArtifactId
                if (-not $artifactById.ContainsKey($artifactId) -or -not [bool]$artifactValid[$artifactId]) { continue }
                $artifact = $artifactById[$artifactId]
                if ([string]$artifact.format -cne 'zip') { Add-EvidenceBlocker ('license_archive_format_invalid:' + [string]$component.id); continue }
                try { $bytes = Get-ZipEntryBytes -ArchivePath (Join-Path $SourceCacheDirectory ([string]$artifact.fileName)) -EntryPath ([string]$license.archivePath) }
                catch { $bytes = $null }
                if ($null -eq $bytes) { Add-EvidenceBlocker ('license_entry_missing:' + [string]$component.id); continue }
                if ($bytes.Length -ne [long]$license.length -or (Get-BytesSha256 $bytes) -cne ([string]$license.sha256).ToUpperInvariant()) {
                    Add-EvidenceBlocker ('license_hash_mismatch:' + [string]$component.id)
                }
            }
            elseif ($kind -ceq 'repository-file') {
                $path = Join-Path $ApplicationRepository ([string]$license.path)
                if (-not (Test-ChildPath $ApplicationRepository $path) -or -not (Test-FileIdentity $path ([string]$license.sha256) ([long]$license.length))) {
                    Add-EvidenceBlocker ('license_repository_file_mismatch:' + [string]$component.id)
                }
            }
            elseif ($kind -cne 'task5-runtime-entry') { Add-EvidenceBlocker ('license_evidence_kind_invalid:' + [string]$component.id) }
        }
    }

    $dependency = $manifest.sharedInputs.dependencyArchive
    if (-not (Test-FileIdentity $DependencyArchivePath ([string]$dependency.sha256) ([long]$dependency.length))) {
        Add-EvidenceBlocker 'dependency_archive_mismatch'
    }
    else {
        try {
            $dependencyExtracted = New-TemporaryDirectory 'dependency-evidence'
            Expand-EvidenceArchive $DependencyArchivePath ([string]$dependency.format) $dependencyExtracted
            foreach ($embedded in @($dependency.embeddedFiles)) {
                $path = Join-Path $dependencyExtracted ([string]$embedded.path).Replace('/', '\')
                if (-not (Test-FileIdentity $path ([string]$embedded.sha256) ([long]$embedded.length))) { Add-EvidenceBlocker ('dependency_embedded_file_mismatch:' + [string]$embedded.path) }
            }
            foreach ($root in @($dependency.roots)) {
                $path = Join-Path $dependencyExtracted ([string]$root.path).Replace('/', '\')
                if (-not (Test-Path -LiteralPath $path -PathType Container)) { Add-EvidenceBlocker ('dependency_root_missing:' + [string]$root.path); continue }
                $actual = Get-OrderedTreeEvidence $path
                if ($actual.fileCount -ne [int]$root.fileCount -or $actual.length -ne [long]$root.length -or
                    [string]$actual.orderedTreeSha256 -cne ([string]$root.orderedTreeSha256).ToUpperInvariant()) {
                    Add-EvidenceBlocker ('dependency_tree_mismatch:{0}:expected={1}/{2}/{3}:actual={4}/{5}/{6}' -f
                        [string]$root.path, [int]$root.fileCount, [long]$root.length, ([string]$root.orderedTreeSha256).ToUpperInvariant(),
                        [int]$actual.fileCount, [long]$actual.length, [string]$actual.orderedTreeSha256)
                }
            }
            $provenancePath = Join-Path $dependencyExtracted ([string]$dependency.provenancePath).Replace('/', '\')
            if (-not (Test-FileIdentity $provenancePath ([string]$dependency.provenanceSha256) ((Get-Item $provenancePath).Length))) { Add-EvidenceBlocker 'dependency_provenance_hash_mismatch' }
            else {
                $provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
                $bit7z = Get-ComponentById $manifest 'bit7z'
                $cpm = Get-ComponentById $manifest 'cpm'
                $sevenZip = Get-ComponentById $manifest '7zip'
                if ([string]$provenance.bit7z.version -cne [string]$bit7z.version -or [string]$provenance.bit7z.commit -cne [string]$bit7z.sourceCommit -or
                    [string]$provenance.bit7z.license -cne [string]$bit7z.licenseExpression -or
                    ([string]$provenance.bit7z.sourceSha256).ToUpperInvariant() -cne ([string]$artifactById['bit7z-source'].sha256).ToUpperInvariant()) { Add-EvidenceBlocker 'bit7z_provenance_mismatch' }
                if ([string]$provenance.cpmBootstrap.version -cne [string]$cpm.version -or [string]$provenance.cpmBootstrap.commit -cne [string]$cpm.sourceCommit -or
                    ([string]$provenance.cpmBootstrap.sourceSha256).ToUpperInvariant() -cne ([string]$artifactById['cpm-bootstrap'].sha256).ToUpperInvariant()) { Add-EvidenceBlocker 'cpm_provenance_mismatch' }
                if ([string]$provenance.sevenZip.version -cne [string]$sevenZip.version -or [string]$provenance.sevenZip.commit -cne [string]$sevenZip.sourceCommit -or
                    [string]$provenance.sevenZip.license -cne [string]$sevenZip.licenseExpression) { Add-EvidenceBlocker 'sevenzip_dependency_provenance_mismatch' }
            }
        }
        catch { Add-EvidenceBlocker ('dependency_archive_extract_failed:' + $_.Exception.Message) }
    }

    $task5 = $manifest.sharedInputs.sevenZipTask5
    $task5InputsValid = $true
    foreach ($check in @(
        @($SevenZipRuntimeArchivePath, [string]$task5.runtimeArchiveSha256, [long]$task5.runtimeArchiveLength, 'sevenzip_runtime_archive_mismatch'),
        @($SevenZipSourceArchivePath, [string]$task5.sourceArchiveSha256, [long]$task5.sourceArchiveLength, 'sevenzip_source_archive_mismatch'),
        @($SevenZipVerificationPath, [string]$task5.verificationSha256, [long]$task5.verificationLength, 'sevenzip_verification_mismatch'))) {
        if (-not (Test-FileIdentity $check[0] $check[1] $check[2])) { Add-EvidenceBlocker $check[3]; $task5InputsValid = $false }
    }
    if ($task5InputsValid) {
        try {
            $verification = Get-Content -LiteralPath $SevenZipVerificationPath -Raw | ConvertFrom-Json
            if (([string]$verification.runtimeArchiveSha256).ToUpperInvariant() -cne ([string]$task5.runtimeArchiveSha256).ToUpperInvariant() -or
                ([string]$verification.dllSha256).ToUpperInvariant() -cne ([string]$task5.dllSha256).ToUpperInvariant() -or
                ([string]$verification.correspondingSourceArchiveSha256).ToUpperInvariant() -cne ([string]$task5.sourceArchiveSha256).ToUpperInvariant()) { Add-EvidenceBlocker 'sevenzip_verification_crosscheck_mismatch' }
            $task5RuntimeExtracted = New-TemporaryDirectory 'sevenzip-runtime'
            $task5SourceExtracted = New-TemporaryDirectory 'sevenzip-source'
            Expand-EvidenceArchive $SevenZipRuntimeArchivePath ([string]$task5.format) $task5RuntimeExtracted
            Expand-EvidenceArchive $SevenZipSourceArchivePath ([string]$task5.format) $task5SourceExtracted
            $dllPath = Join-Path $task5RuntimeExtracted 'x64\7z.dll'
            if (-not (Test-FileIdentity $dllPath ([string]$task5.dllSha256) ([long]$task5.dllLength))) { Add-EvidenceBlocker 'sevenzip_dll_mismatch' }
            $buildMapPath = Join-Path $task5RuntimeExtracted ([string]$task5.buildMapPath).Replace('/', '\')
            if (-not (Test-FileIdentity $buildMapPath ([string]$task5.buildMapSha256) ((Get-Item $buildMapPath).Length))) { Add-EvidenceBlocker 'sevenzip_build_map_mismatch' }
            else {
                $map = Get-Content -LiteralPath $buildMapPath -Raw | ConvertFrom-Json
                $objects = @($map.objects | ForEach-Object { [string]$_ })
                if ([int]$map.objectCount -ne $objects.Count -or @($objects | Where-Object { $_ -match [string]$task5.forbiddenPattern }).Count -gt 0) { Add-EvidenceBlocker 'sevenzip_rar_evidence_mismatch' }
                foreach ($required in @($task5.requiredObjects)) { if ($objects -notcontains [string]$required) { Add-EvidenceBlocker 'sevenzip_required_object_missing' } }
            }
            $buildProvenancePath = Join-Path $task5RuntimeExtracted 'provenance\build-provenance.json'
            $buildProvenance = Get-Content -LiteralPath $buildProvenancePath -Raw | ConvertFrom-Json
            if ([string]$buildProvenance.policy -cne 'no-rar-handlers-or-code' -or [string]$buildProvenance.version -cne '26.01' -or
                [string]$buildProvenance.source.commit -cne [string]$task5.sourceCommit -or
                ([string]$buildProvenance.source.archiveSha256).ToUpperInvariant() -cne ([string]$artifactById['sevenzip-source'].sha256).ToUpperInvariant() -or
                ([string]$buildProvenance.dll.sha256).ToUpperInvariant() -cne ([string]$task5.dllSha256).ToUpperInvariant()) { Add-EvidenceBlocker 'sevenzip_build_provenance_mismatch' }
            foreach ($file in @(Get-ChildItem -LiteralPath $task5SourceExtracted -File -Recurse)) {
                $relative = $file.FullName.Substring($task5SourceExtracted.Length).TrimStart('\', '/').Replace('\', '/')
                if ($relative -match [string]$task5.forbiddenSourcePattern) { Add-EvidenceBlocker 'sevenzip_rar_evidence_mismatch'; break }
            }
            $sevenZipComponent = Get-ComponentById $manifest '7zip'
            foreach ($license in @($sevenZipComponent.licenseTexts | Where-Object { [string]$_.kind -ceq 'task5-runtime-entry' })) {
                $path = Join-Path $task5RuntimeExtracted ([string]$license.archivePath).Replace('/', '\')
                if (-not (Test-FileIdentity $path ([string]$license.sha256) ([long]$license.length))) { Add-EvidenceBlocker 'license_hash_mismatch:7zip' }
            }
        }
        catch { Add-EvidenceBlocker ('sevenzip_evidence_extract_failed:' + $_.Exception.Message) }
    }

    $nlohmann = Get-ComponentById $manifest 'nlohmann-json'
    if ($null -ne $nlohmann -and @($nlohmann.transforms).Count -eq 1) {
        try {
            $transform = $nlohmann.transforms[0]
            $artifact = $artifactById[[string]$transform.sourceArtifactId]
            $sourceBytes = Get-ZipEntryBytes (Join-Path $SourceCacheDirectory ([string]$artifact.fileName)) ([string]$transform.sourceArchivePath)
            $targetPath = Join-Path $ApplicationRepository ([string]$transform.repositoryPath).Replace('/', '\')
            if ($null -eq $sourceBytes -or -not (Test-Path -LiteralPath $targetPath -PathType Leaf)) { throw 'header_missing' }
            $targetBytes = [IO.File]::ReadAllBytes($targetPath)
            $converted = New-Object IO.MemoryStream
            foreach ($byte in $sourceBytes) { if ($byte -eq 10) { $converted.WriteByte(13) }; $converted.WriteByte($byte) }
            $convertedBytes = $converted.ToArray(); $converted.Dispose()
            $evidence = [ordered]@{
                schemaVersion = 'karon-text-transform/v1'; algorithm = 'lf-to-crlf'
                sourceSha256 = Get-BytesSha256 $sourceBytes; sourceLength = $sourceBytes.Length
                targetSha256 = Get-BytesSha256 $targetBytes; targetLength = $targetBytes.Length
                lineFeedCount = @($sourceBytes | Where-Object { $_ -eq 10 }).Count
                sourceCarriageReturnCount = @($sourceBytes | Where-Object { $_ -eq 13 }).Count
                sourceOrderedChunkSha256 = Get-OrderedChunkDigest $sourceBytes
                targetOrderedChunkSha256 = Get-OrderedChunkDigest $targetBytes
            }
            $nlohmannEvidenceBytes = $utf8NoBom.GetBytes(($evidence | ConvertTo-Json -Depth 50 -Compress) + "`r`n")
            $convertedMatches = $convertedBytes.Length -eq $targetBytes.Length -and (Get-BytesSha256 $convertedBytes) -ceq (Get-BytesSha256 $targetBytes)
            if ([string]$transform.kind -cne 'lf-to-crlf' -or -not $convertedMatches -or
                $evidence.sourceCarriageReturnCount -ne 0 -or $evidence.lineFeedCount -ne [int]$transform.lineFeedCount -or
                $evidence.sourceSha256 -cne ([string]$transform.sourceSha256).ToUpperInvariant() -or $evidence.sourceLength -ne [long]$transform.sourceLength -or
                $evidence.targetSha256 -cne ([string]$transform.targetSha256).ToUpperInvariant() -or $evidence.targetLength -ne [long]$transform.targetLength -or
                $evidence.sourceOrderedChunkSha256 -cne ([string]$transform.sourceOrderedChunkSha256).ToUpperInvariant() -or
                $evidence.targetOrderedChunkSha256 -cne ([string]$transform.targetOrderedChunkSha256).ToUpperInvariant() -or
                $nlohmannEvidenceBytes.Length -ne [long]$transform.transformEvidenceLength -or
                (Get-BytesSha256 $nlohmannEvidenceBytes) -cne ([string]$transform.transformEvidenceSha256).ToUpperInvariant()) { Add-EvidenceBlocker 'nlohmann_transform_mismatch' }
        }
        catch { Add-EvidenceBlocker 'nlohmann_transform_mismatch' }
    }
    else { Add-EvidenceBlocker 'nlohmann_transform_mismatch' }

    $ytDlp = Get-ComponentById $manifest 'yt-dlp'
    if ($null -ne $ytDlp) {
        $binaryArtifact = $artifactById[[string]$ytDlp.binaryProvenance.binaryArtifactId]
        $sumsArtifact = $artifactById[[string]$ytDlp.binaryProvenance.checksumsArtifactId]
        $expectedBinarySha = ([string]$binaryArtifact.sha256).ToUpperInvariant()
        $expectedBinaryLength = [long]$binaryArtifact.length
        if (-not (Test-FileIdentity $YtDlpBinaryPath $expectedBinarySha $expectedBinaryLength)) { Add-EvidenceBlocker 'yt_dlp_binary_mismatch' }
        if ($artifactValid[[string]$sumsArtifact.id]) {
            $sumsText = Get-Content -LiteralPath (Join-Path $SourceCacheDirectory ([string]$sumsArtifact.fileName)) -Raw
            if ($sumsText -notmatch ('(?im)^' + [regex]::Escape($expectedBinarySha.ToLowerInvariant()) + '  yt-dlp\.exe\r?$')) { Add-EvidenceBlocker 'yt_dlp_checksum_manifest_mismatch' }
        }
        if ([string]$ytDlp.binaryProvenance.sourceCommit -cne [string]$ytDlp.sourceCommit -or -not [bool]$ytDlp.binaryProvenance.releaseImmutable) { Add-EvidenceBlocker 'yt_dlp_release_provenance_mismatch' }
    }

    $application = Get-ComponentById $manifest 'application'
    if ([string]::IsNullOrWhiteSpace($ApplicationCommit) -or $ApplicationCommit -notmatch '^[0-9a-f]{40}$') { Add-EvidenceBlocker 'application_release_commit_required' }
    elseif (-not (Test-Path -LiteralPath $ApplicationRepository -PathType Container)) { Add-EvidenceBlocker 'application_repository_missing' }
    else {
        try {
            $head = (& git -C $ApplicationRepository rev-parse HEAD 2>$null | Out-String).Trim()
            $status = (& git -C $ApplicationRepository status --porcelain=v1 --untracked-files=all 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or $head -cne $ApplicationCommit) { Add-EvidenceBlocker 'application_commit_mismatch' }
            elseif (-not [string]::IsNullOrEmpty($status)) { Add-EvidenceBlocker 'application_tree_dirty' }
            else {
                $applicationTemp = New-TemporaryDirectory 'application-source'
                $applicationSourceArchive = Join-Path $applicationTemp ('karon-application-' + $ApplicationCommit.Substring(0, 12) + '.zip')
                & git -C $ApplicationRepository archive --format=zip --output=$applicationSourceArchive $ApplicationCommit
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $applicationSourceArchive -PathType Leaf)) { throw 'git_archive_failed' }
                $appFile = Get-Item -LiteralPath $applicationSourceArchive
                $inventoryRecords.Add([ordered]@{
                    id = 'application-source'; component = 'application'; fileName = $appFile.Name
                    url = ([string]$application.sourceRepository).TrimEnd('/') + '/commit/' + $ApplicationCommit
                    expectedSha256 = Get-PathSha256 $applicationSourceArchive; expectedLength = $appFile.Length
                    actualSha256 = Get-PathSha256 $applicationSourceArchive; actualLength = $appFile.Length; status = 'verified'; includeInBundle = $true
                })
            }
        }
        catch { Add-EvidenceBlocker ('application_source_archive_failed:' + $_.Exception.Message) }
    }

    if ([string]::IsNullOrWhiteSpace($CandidateManifestPath) -or -not (Test-Path -LiteralPath $CandidateManifestPath -PathType Leaf)) { Add-EvidenceBlocker 'candidate_manifest_required' }
    else {
        try {
            $candidate = Get-Content -LiteralPath $CandidateManifestPath -Raw | ConvertFrom-Json
            if ([string]$candidate.attestation.source.commit -cne $ApplicationCommit -or [bool]$candidate.attestation.source.dirty) { Add-EvidenceBlocker 'candidate_source_binding_mismatch' }
            $dependency = $manifest.sharedInputs.dependencyArchive
            if ([string]$candidate.attestation.dependencyArchive.name -cne [string]$dependency.fileName -or
                ([string]$candidate.attestation.dependencyArchive.sha256).ToUpperInvariant() -cne ([string]$dependency.sha256).ToUpperInvariant()) { Add-EvidenceBlocker 'candidate_dependency_binding_mismatch' }
            $linkerSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($input in @($candidate.attestation.linkerInputs)) {
                if ([string]$input.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or [long]$input.length -le 0) { Add-EvidenceBlocker 'candidate_linker_identity_invalid' }
                [void]$linkerSet.Add([string]$input.library)
            }
            foreach ($required in @($manifest.sharedInputs.candidate.requiredLinkerLibraries)) { if (-not $linkerSet.Contains([string]$required)) { Add-EvidenceBlocker ('candidate_linker_missing:' + [string]$required) } }
            foreach ($componentId in @('7zip', 'yt-dlp')) {
                $component = Get-ComponentById $manifest $componentId
                $binding = $component.buildRecipe.candidateBinding
                $file = Get-CandidateFile $candidate ([string]$binding.candidatePath)
                if ($null -eq $file -or ([string]$file.sha256).ToUpperInvariant() -cne ([string]$binding.sha256).ToUpperInvariant()) { Add-EvidenceBlocker ('candidate_file_binding_mismatch:' + $componentId) }
            }
        }
        catch { Add-EvidenceBlocker ('candidate_manifest_invalid:' + $_.Exception.Message) }
    }
}

$inventoryStatus = if ($script:blockers.Count -eq 0) { 'closed' } else { 'blocked' }
$orderedInventory = @($inventoryRecords | Sort-Object { [string]$_.id })
$inventory = [ordered]@{
    schemaVersion = 'karon-source-cache-inventory/v1'
    release = 'v2.19.1-karon.2'
    scope = 'non-ffmpeg-non-deno'
    status = $inventoryStatus
    manifestSha256 = $manifestSha256
    applicationCommit = $(if ([string]::IsNullOrWhiteSpace($ApplicationCommit)) { $null } else { $ApplicationCommit })
    candidateManifestSha256 = $(if (-not [string]::IsNullOrWhiteSpace($CandidateManifestPath) -and (Test-Path -LiteralPath $CandidateManifestPath -PathType Leaf)) { Get-PathSha256 $CandidateManifestPath } else { $null })
    dependencyArchiveSha256 = $(if (Test-Path -LiteralPath $DependencyArchivePath -PathType Leaf) { Get-PathSha256 $DependencyArchivePath } else { $null })
    sevenZipTask5 = [ordered]@{
        runtimeArchiveSha256 = $(if (Test-Path -LiteralPath $SevenZipRuntimeArchivePath -PathType Leaf) { Get-PathSha256 $SevenZipRuntimeArchivePath } else { $null })
        sourceArchiveSha256 = $(if (Test-Path -LiteralPath $SevenZipSourceArchivePath -PathType Leaf) { Get-PathSha256 $SevenZipSourceArchivePath } else { $null })
        verificationSha256 = $(if (Test-Path -LiteralPath $SevenZipVerificationPath -PathType Leaf) { Get-PathSha256 $SevenZipVerificationPath } else { $null })
    }
    artifacts = $orderedInventory
}
$inventoryBytes = ConvertTo-CanonicalJsonBytes $inventory
$inventoryPath = Join-Path $OutputDirectory 'source-cache-inventory.json'

try {
    Write-AtomicBytes $inventoryPath $inventoryBytes
    if ($script:blockers.Count -gt 0) {
        $orderedBlockers = $script:blockers.ToArray()
        [Array]::Sort($orderedBlockers, [StringComparer]::Ordinal)
        $blockerDocument = [ordered]@{
            schemaVersion = 'karon-component-evidence-blockers/v1'
            release = 'v2.19.1-karon.2'
            scope = 'non-ffmpeg-non-deno'
            status = 'blocked'
            componentCount = $(if ($null -eq $manifest) { 0 } else { @($manifest.components).Count })
            manifestSha256 = $manifestSha256
            sourceCacheInventorySha256 = Get-BytesSha256 $inventoryBytes
            blockers = $orderedBlockers
        }
        $blockerPath = Join-Path $OutputDirectory 'non-runtime-component-blockers.json'
        Write-AtomicBytes $blockerPath (ConvertTo-CanonicalJsonBytes $blockerDocument)
        Write-Output $blockerPath
        exit 1
    }

    foreach ($component in @($manifest.components)) {
        foreach ($artifact in @($component.sourceArtifacts | Where-Object { [bool]$_.includeInBundle })) {
            $bundleEntries.Add([ordered]@{ name = 'sources/' + [string]$artifact.fileName; path = Join-Path $SourceCacheDirectory ([string]$artifact.fileName) })
        }
    }
    $bundleEntries.Add([ordered]@{ name = 'component-manifest.json'; path = $ManifestPath })
    $bundleEntries.Add([ordered]@{ name = 'source-cache-inventory.json'; path = $inventoryPath })
    $bundleEntries.Add([ordered]@{ name = 'application/' + (Split-Path -Leaf $applicationSourceArchive); path = $applicationSourceArchive })
    $bundleEntries.Add([ordered]@{ name = 'evidence/candidate-manifest.json'; path = $CandidateManifestPath })
    $bundleEntries.Add([ordered]@{ name = 'evidence/nlohmann-json-header.transform.json'; bytes = $nlohmannEvidenceBytes })
    $bundleEntries.Add([ordered]@{ name = 'evidence/dependency-archive/' + (Split-Path -Leaf $DependencyArchivePath); path = $DependencyArchivePath })
    $bundleEntries.Add([ordered]@{ name = 'evidence/task5/' + (Split-Path -Leaf $SevenZipRuntimeArchivePath); path = $SevenZipRuntimeArchivePath })
    $bundleEntries.Add([ordered]@{ name = 'evidence/task5/' + (Split-Path -Leaf $SevenZipSourceArchivePath); path = $SevenZipSourceArchivePath })
    $bundleEntries.Add([ordered]@{ name = 'evidence/task5/' + (Split-Path -Leaf $SevenZipVerificationPath); path = $SevenZipVerificationPath })
    $bundlePath = Join-Path $OutputDirectory 'ytdlp-korean-interface-v2.19.1-karon.2-non-runtime-component-evidence.zip'
    New-DeterministicZip -OutputPath $bundlePath -Entries $bundleEntries.ToArray()
    Write-Output $bundlePath
    exit 0
}
finally {
    foreach ($directory in $script:temporaryDirectories) {
        if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
