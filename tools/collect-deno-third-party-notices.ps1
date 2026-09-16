#requires -Version 7.4
[CmdletBinding()]
param(
    [string] $ManifestRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'release/runtime/v2.19.1-karon.2/deno'),
    [string] $DenoSourceRoot,
    [string] $RustyV8SourceRoot,
    [string] $V8SourceRoot,
    [string] $VendorRoot,
    [string] $OfficialMetadataPath,
    [string] $SupersetMetadataPath,
    [string] $DenoExePath,
    [string] $DenoSourceArchivePath,
    [string] $RustyV8SourceArchivePath,
    [string] $V8SourceArchivePath,
    [string] $RustyV8StaticLibArchivePath,
    [string] $NativeSourceRoot,
    [string] $ScratchRoot,
    [switch] $Run
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DenoSha256 {
    param([Parameter(Mandatory)] [string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-DenoUtf8Text {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $Text)
    $normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    [IO.File]::WriteAllText($Path, $normalized, [Text.UTF8Encoding]::new($false))
}

function Read-DenoJson {
    param([Parameter(Mandatory)] [string] $Path)
    $raw = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
    return ConvertFrom-Json -InputObject $raw -Depth 100
}

function Assert-DenoHash {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $ExpectedSha256)
    if ($ExpectedSha256 -notmatch '^[0-9a-f]{64}$' -or (Get-DenoSha256 $Path) -cne $ExpectedSha256) {
        throw "deno_input_hash_mismatch:$Path"
    }
}

function Assert-DenoImmutableCargoSource {
    param([Parameter(Mandatory)] [string] $Source)
    if ($Source -ceq 'registry+https://github.com/rust-lang/crates.io-index') { return $true }
    if ($Source.StartsWith('git+', [StringComparison]::Ordinal)) {
        if ($Source -match '(?i)[?&](branch|tag)=' -or
            $Source -notmatch '#(?<commit>[0-9a-f]{40})$' -or
            ($Source -match '[?&]rev=(?<revision>[0-9a-f]{40})(?:&|#)' -and $Matches.revision -cne $Matches.commit)) {
            throw 'deno_mutable_git_source'
        }
        return $true
    }
    throw 'deno_unsupported_cargo_source'
}

function Assert-DenoUniquePaths {
    param([Parameter(Mandatory)] [string[]] $Paths)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($inputPath in $Paths) {
        $path = $inputPath.Replace('\', '/')
        if ([string]::IsNullOrWhiteSpace($path) -or $path.StartsWith('/') -or
            $path -match '^[A-Za-z]:' -or $path.Contains([char]0) -or
            @($path.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
            throw "deno_path_invalid:$path"
        }
        if (-not $seen.Add($path)) { throw "deno_path_case_collision:$($path.ToLowerInvariant())" }
    }
    return $true
}

function Assert-DenoNativeClosure {
    param(
        [Parameter(Mandatory)] [string[]] $RequiredComponents,
        [Parameter(Mandatory)] [string[]] $ObservedComponents
    )
    $observed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($component in $ObservedComponents) { [void]$observed.Add($component) }
    foreach ($component in $RequiredComponents | Sort-Object) {
        if (-not $observed.Contains($component)) { throw "deno_native_component_missing:$component" }
    }
    return $true
}

function Assert-DenoTargetClosure {
    param(
        [Parameter(Mandatory)] [string[]] $OfficialPackageIds,
        [Parameter(Mandatory)] [string[]] $SupersetPackageIds
    )
    $superset = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($packageId in $SupersetPackageIds) { [void]$superset.Add($packageId) }
    foreach ($id in $OfficialPackageIds | Sort-Object -Unique) {
        if (-not $superset.Contains($id)) { throw "deno_target_closure_mismatch:$id" }
    }
    return $true
}

function Assert-DenoReleaseIdentity {
    param(
        [Parameter(Mandatory)] [string] $DenoExePath,
        [Parameter(Mandatory)] [string] $ExpectedSha256,
        [Parameter(Mandatory)] [string] $ExpectedVersion,
        [Parameter(Mandatory)] [string] $ExpectedTarget
    )
    Assert-DenoHash $DenoExePath $ExpectedSha256
    $lines = @(& $DenoExePath --version 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0 -or $lines.Count -lt 1 -or
        $lines[0] -notmatch '^deno (?<version>[^ ]+) \(stable, release, (?<target>[^)]+)\)$' -or
        $Matches.version -cne $ExpectedVersion -or $Matches.target -cne $ExpectedTarget) {
        throw 'deno_release_identity_mismatch'
    }
    return [pscustomobject]@{ version = $Matches.version; target = $Matches.target; sha256 = $ExpectedSha256 }
}

function Get-DenoLicenseFiles {
    param([Parameter(Mandatory)] [string] $Root, [string] $DeclaredLicenseFile)
    $files = [Collections.Generic.List[IO.FileInfo]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force) {
        if ($file.Name -match '^(?i:LICENSE|LICENCE|COPYING|NOTICE|PATENTS)(?:[._-].*)?$') { $files.Add($file) }
    }
    if (-not [string]::IsNullOrWhiteSpace($DeclaredLicenseFile)) {
        $declared = [IO.Path]::GetFullPath((Join-Path $Root $DeclaredLicenseFile))
        $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
        if (-not $declared.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $declared -PathType Leaf)) {
            throw 'deno_declared_license_file_missing'
        }
        if ($files.FullName -notcontains $declared) { $files.Add((Get-Item -LiteralPath $declared)) }
    }
    return @($files | Sort-Object FullName -Unique)
}

function Assert-DenoCratePackage {
    param(
        [Parameter(Mandatory)] [object] $Package,
        [Parameter(Mandatory)] [string] $VendorPath
    )
    $id = ([string]$Package.name) + '@' + ([string]$Package.version)
    Assert-DenoImmutableCargoSource ([string]$Package.source) | Out-Null
    if ([string]$Package.checksum -notmatch '^[0-9a-f]{64}$') { throw "deno_cargo_checksum_missing:$id" }
    $checksum = Read-DenoJson (Join-Path $VendorPath '.cargo-checksum.json')
    if ([string]$checksum.package -cne [string]$Package.checksum) { throw "deno_cargo_checksum_mismatch:$id" }

    $toml = [IO.File]::ReadAllText((Join-Path $VendorPath 'Cargo.toml'), [Text.UTF8Encoding]::new($false, $true))
    $license = [regex]::Match($toml, '(?m)^license\s*=\s*"([^"]+)"').Groups[1].Value
    $licenseFile = [regex]::Match($toml, '(?m)^license-file\s*=\s*"([^"]+)"').Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($license) -and [string]::IsNullOrWhiteSpace($licenseFile)) {
        throw "deno_crate_license_metadata_missing:$id"
    }
    if ($license -match '(?i)NOASSERTION|UNKNOWN') { throw "deno_crate_license_ambiguous:$id" }
    $files = @(Get-DenoLicenseFiles -Root $VendorPath -DeclaredLicenseFile $licenseFile)
    if ($files.Count -eq 0) { throw "deno_crate_license_file_missing:$id" }
    $root = [IO.Path]::GetFullPath($VendorPath).TrimEnd('\')
    $records = foreach ($file in $files) {
        [ordered]@{
            path = $file.FullName.Substring($root.Length + 1).Replace('\', '/')
            length = $file.Length
            sha256 = Get-DenoSha256 $file.FullName
        }
    }
    return [pscustomobject]@{ id = $id; license = $license; licenseFile = $licenseFile; licenseFiles = @($records) }
}

function Read-DenoCargoLockPackages {
    param([Parameter(Mandatory)] [string] $CargoLockPath)
    $raw = [IO.File]::ReadAllText($CargoLockPath, [Text.UTF8Encoding]::new($false, $true))
    $packages = [Collections.Generic.List[object]]::new()
    foreach ($match in [regex]::Matches($raw, '(?ms)^\[\[package\]\]\r?\n(.*?)(?=^\[\[package\]\]|\z)')) {
        $block = $match.Groups[1].Value
        $name = [regex]::Match($block, '(?m)^name = "([^"]+)"').Groups[1].Value
        $version = [regex]::Match($block, '(?m)^version = "([^"]+)"').Groups[1].Value
        $source = [regex]::Match($block, '(?m)^source = "([^"]+)"').Groups[1].Value
        $checksum = [regex]::Match($block, '(?m)^checksum = "([0-9a-f]{64})"').Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($version)) { throw 'deno_cargo_lock_parse_failed' }
        if (-not [string]::IsNullOrWhiteSpace($source)) { Assert-DenoImmutableCargoSource $source | Out-Null }
        $packages.Add([pscustomobject]@{ name = $name; version = $version; source = $source; checksum = $checksum })
    }
    if ($packages.Count -eq 0) { throw 'deno_cargo_lock_empty' }
    return @($packages)
}

function Get-DenoMetadataPackageIds {
    param([Parameter(Mandatory)] [object] $Metadata)
    return @($Metadata.packages | ForEach-Object { ([string]$_.name) + '@' + ([string]$_.version) } | Sort-Object -Unique)
}

function Write-DenoBlockerReport {
    param(
        [Parameter(Mandatory)] [string] $ScratchRoot,
        [Parameter(Mandatory)] [object] $Identity,
        [Parameter(Mandatory)] [string[]] $Blockers,
        [Parameter(Mandatory)] [hashtable] $Counts
    )
    $report = [ordered]@{
        schemaVersion = 'deno-third-party-collection-blockers/v1'
        status = 'NOT_VERIFIED'
        closureClassification = 'verified-conservative-superset'
        releaseIdentity = $Identity
        counts = [ordered]@{ cargoLockPackages = $Counts.cargoLockPackages; registryPackages = $Counts.registryPackages; workspacePackages = $Counts.workspacePackages; nativeComponents = $Counts.nativeComponents }
        blockers = @($Blockers | Sort-Object -Unique)
        noticeArtifactProduced = $false
        sourceBundleProduced = $false
        overallReleasePass = $false
    }
    $path = Join-Path $ScratchRoot 'deno-collection-blockers.json'
    Write-DenoUtf8Text $path (($report | ConvertTo-Json -Depth 10) + "`n")
    return $path
}

function New-DenoDeterministicZip {
    param([Parameter(Mandatory)] [string] $SourceRoot, [Parameter(Mandatory)] [string] $ZipPath)
    $root = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Sort-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') })
    $relative = @($files | ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') })
    Assert-DenoUniquePaths $relative | Out-Null
    $stream = [IO.File]::Open($ZipPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            for ($index = 0; $index -lt $files.Count; $index++) {
                $entry = $zip.CreateEntry($relative[$index], [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $input = [IO.File]::OpenRead($files[$index].FullName)
                try { $output = $entry.Open(); try { $input.CopyTo($output) } finally { $output.Dispose() } } finally { $input.Dispose() }
            }
        }
        finally { $zip.Dispose() }
    }
    finally { $stream.Dispose() }
    return Get-DenoSha256 $ZipPath
}

function Invoke-DenoThirdPartyNoticeCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ManifestRoot,
        [Parameter(Mandatory)] [string] $DenoSourceRoot,
        [Parameter(Mandatory)] [string] $RustyV8SourceRoot,
        [Parameter(Mandatory)] [string] $V8SourceRoot,
        [Parameter(Mandatory)] [string] $VendorRoot,
        [Parameter(Mandatory)] [string] $OfficialMetadataPath,
        [Parameter(Mandatory)] [string] $SupersetMetadataPath,
        [Parameter(Mandatory)] [string] $DenoExePath,
        [Parameter(Mandatory)] [string] $DenoSourceArchivePath,
        [Parameter(Mandatory)] [string] $RustyV8SourceArchivePath,
        [Parameter(Mandatory)] [string] $V8SourceArchivePath,
        [Parameter(Mandatory)] [string] $RustyV8StaticLibArchivePath,
        [Parameter(Mandatory)] [string] $NativeSourceRoot,
        [Parameter(Mandatory)] [string] $ScratchRoot
    )
    $inputs = Read-DenoJson (Join-Path $ManifestRoot 'inputs.json')
    $native = Read-DenoJson (Join-Path $ManifestRoot 'native-components.json')
    if ($inputs.schemaVersion -cne 'deno-third-party-inputs/v1' -or
        $inputs.closureClassification -cne 'verified-conservative-superset') { throw 'deno_input_manifest_invalid' }
    New-Item -ItemType Directory -Path $ScratchRoot -Force | Out-Null
    $identity = Assert-DenoReleaseIdentity -DenoExePath $DenoExePath -ExpectedSha256 $inputs.releaseIdentity.denoExeSha256 -ExpectedVersion $inputs.releaseIdentity.version -ExpectedTarget $inputs.releaseIdentity.target

    $artifactPaths = @{
        denoSource = $DenoSourceArchivePath; rustyV8Source = $RustyV8SourceArchivePath
        v8Source = $V8SourceArchivePath; rustyV8StaticLibrary = $RustyV8StaticLibArchivePath
    }
    foreach ($artifact in $inputs.sourceArtifacts) {
        $path = [string]$artifactPaths[[string]$artifact.id]
        if ([string]::IsNullOrWhiteSpace($path)) { throw "deno_source_artifact_unmapped:$($artifact.id)" }
        $item = Get-Item -LiteralPath $path
        if ($item.Length -ne [long]$artifact.length) { throw "deno_source_artifact_length_mismatch:$($artifact.id)" }
        Assert-DenoHash $path ([string]$artifact.sha256)
    }
    foreach ($pinned in $inputs.pinnedSourceFiles) {
        $base = switch ([string]$pinned.root) { 'deno' { $DenoSourceRoot } 'rusty_v8' { $RustyV8SourceRoot } 'v8' { $V8SourceRoot } default { throw 'deno_pinned_source_root_invalid' } }
        Assert-DenoHash (Join-Path $base ([string]$pinned.path)) ([string]$pinned.sha256)
    }

    $official = Read-DenoJson $OfficialMetadataPath
    $superset = Read-DenoJson $SupersetMetadataPath
    $officialIds = @(Get-DenoMetadataPackageIds $official)
    $supersetIds = @(Get-DenoMetadataPackageIds $superset)
    Assert-DenoTargetClosure -OfficialPackageIds $officialIds -SupersetPackageIds $supersetIds | Out-Null
    $officialSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($packageId in $officialIds) { [void]$officialSet.Add($packageId) }
    $supersetSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($packageId in $supersetIds) { [void]$supersetSet.Add($packageId) }

    $lockPackages = @(Read-DenoCargoLockPackages (Join-Path $DenoSourceRoot 'Cargo.lock'))
    $registryPackages = @($lockPackages | Where-Object { $_.source -like 'registry+*' })
    $workspacePackages = @($superset.packages | Where-Object { $null -eq $_.source })
    $vendorMap = @{}
    foreach ($directory in Get-ChildItem -LiteralPath $VendorRoot -Directory) {
        $toml = [IO.File]::ReadAllText((Join-Path $directory.FullName 'Cargo.toml'))
        $name = [regex]::Match($toml, '(?m)^name\s*=\s*"([^"]+)"').Groups[1].Value
        $version = [regex]::Match($toml, '(?m)^version\s*=\s*"([^"]+)"').Groups[1].Value
        $key = $name + "`0" + $version
        if ($vendorMap.ContainsKey($key)) { throw "deno_vendor_duplicate:$name@$version" }
        $vendorMap[$key] = $directory.FullName
    }
    if ($vendorMap.Count -ne $registryPackages.Count) { throw 'deno_vendor_lock_count_mismatch' }

    $requiredNative = @($native.components | Where-Object { $_.required } | ForEach-Object { [string]$_.path })
    $observedNative = @($native.components | ForEach-Object { [string]$_.path })
    Assert-DenoNativeClosure -RequiredComponents $requiredNative -ObservedComponents $observedNative | Out-Null
    foreach ($component in $native.components | Where-Object { $_.path -ne 'v8' }) {
        $archive = Join-Path $NativeSourceRoot ([string]$component.archiveFile)
        $item = Get-Item -LiteralPath $archive
        if ($item.Length -ne [long]$component.length) { throw "deno_native_archive_length_mismatch:$($component.path)" }
        Assert-DenoHash $archive ([string]$component.sha256)
        $entries = @(& tar.exe -tzf $archive)
        if ($LASTEXITCODE -ne 0 -or $entries.Count -eq 0) { throw "deno_native_archive_invalid:$($component.path)" }
        Assert-DenoUniquePaths @($entries | Where-Object { -not $_.EndsWith('/') }) | Out-Null
        $licenses = @($entries | Where-Object { (Split-Path $_ -Leaf) -match '^(?i:LICENSE|LICENCE|COPYING|NOTICE|PATENTS)(?:[._-].*)?$' })
        if ($component.licenseRequired -and $licenses.Count -eq 0) { throw "deno_native_license_file_missing:$($component.path)" }
    }

    $blockers = [Collections.Generic.List[string]]::new()
    $crateRecords = [Collections.Generic.List[object]]::new()
    foreach ($package in $registryPackages | Sort-Object name, version) {
        $id = $package.name + '@' + $package.version
        $key = $package.name + "`0" + $package.version
        if (-not $vendorMap.ContainsKey($key)) { $blockers.Add("deno_vendor_package_missing:$id"); continue }
        try {
            $record = Assert-DenoCratePackage -Package $package -VendorPath $vendorMap[$key]
            $reason = if ($officialSet.Contains($id)) { 'official-workflow-profile' } elseif ($supersetSet.Contains($id)) { 'all-features-conservative-superset' } else { 'cargo-lock-conservative-superset' }
            $crateRecords.Add([ordered]@{ name = $package.name; version = $package.version; source = $package.source; checksum = $package.checksum; license = $record.license; licenseFile = $record.licenseFile; licenseFiles = $record.licenseFiles; inclusionReason = $reason })
        }
        catch { $blockers.Add($_.Exception.Message) }
    }
    foreach ($package in $workspacePackages | Sort-Object name, version) {
        $id = ([string]$package.name) + '@' + ([string]$package.version)
        if ([string]::IsNullOrWhiteSpace([string]$package.license) -or [string]$package.license -match '(?i)NOASSERTION|UNKNOWN') {
            $blockers.Add("deno_workspace_license_ambiguous:$id")
        }
    }

    $counts = @{ cargoLockPackages = $lockPackages.Count; registryPackages = $registryPackages.Count; workspacePackages = $workspacePackages.Count; nativeComponents = @($native.components).Count }
    if ($blockers.Count -gt 0) {
        $reportPath = Write-DenoBlockerReport -ScratchRoot $ScratchRoot -Identity $identity -Blockers @($blockers) -Counts $counts
        throw "deno_collection_blocked:$($blockers.Count):$reportPath"
    }

    $outputRoot = Join-Path $ScratchRoot 'deno-third-party-output'
    if (Test-Path -LiteralPath $outputRoot) { throw 'deno_output_already_exists' }
    $stage = Join-Path $outputRoot 'bundle'
    $licenseRoot = Join-Path $stage 'LICENSES/cargo'
    $sourceRoot = Join-Path $stage 'SOURCES'
    New-Item -ItemType Directory -Path $licenseRoot, $sourceRoot | Out-Null
    $notice = [Text.StringBuilder]::new([IO.File]::ReadAllText((Join-Path $ManifestRoot 'THIRD-PARTY-NOTICES.template.txt')))
    $notice.Append("`n") | Out-Null
    $outputPaths = [Collections.Generic.List[string]]::new()
    foreach ($record in $crateRecords) {
        $safeId = ($record.name + '-' + $record.version) -replace '[^A-Za-z0-9._+-]', '_'
        $notice.AppendLine("=== $($record.name) $($record.version) ===").AppendLine("Source: $($record.source)").AppendLine("Checksum: $($record.checksum)").AppendLine("License: $($record.license)").AppendLine("Inclusion: $($record.inclusionReason)") | Out-Null
        $vendorPath = $vendorMap[$record.name + "`0" + $record.version]
        foreach ($license in $record.licenseFiles) {
            $destinationRelative = "LICENSES/cargo/$safeId/$($license.path)"
            $destination = Join-Path $stage $destinationRelative
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $vendorPath $license.path) -Destination $destination
            $outputPaths.Add($destinationRelative)
            $notice.AppendLine("--- $destinationRelative ---").AppendLine([IO.File]::ReadAllText($destination)).AppendLine() | Out-Null
        }
    }
    Assert-DenoUniquePaths @($outputPaths) | Out-Null
    foreach ($artifact in $inputs.sourceArtifacts) {
        $source = [string]$artifactPaths[[string]$artifact.id]
        Copy-Item -LiteralPath $source -Destination (Join-Path $sourceRoot ([string]$artifact.fileName))
    }
    foreach ($component in $native.components | Where-Object { $_.path -ne 'v8' }) {
        Copy-Item -LiteralPath (Join-Path $NativeSourceRoot ([string]$component.archiveFile)) -Destination (Join-Path $sourceRoot ([string]$component.archiveFile))
    }
    Copy-Item -LiteralPath $VendorRoot -Destination (Join-Path $sourceRoot 'cargo-vendor') -Recurse
    Write-DenoUtf8Text (Join-Path $outputRoot 'THIRD-PARTY-NOTICES.txt') ($notice.ToString())
    Write-DenoUtf8Text (Join-Path $outputRoot 'component-manifest.json') (([ordered]@{ schemaVersion = 'deno-third-party-components/v1'; closureClassification = $inputs.closureClassification; releaseIdentity = $identity; counts = $counts; crates = @($crateRecords); nativeComponents = @($native.components); overallReleasePass = $false } | ConvertTo-Json -Depth 20) + "`n")
    $inventory = foreach ($file in Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName) { [ordered]@{ path = $file.FullName.Substring($stage.Length + 1).Replace('\', '/'); length = $file.Length; sha256 = Get-DenoSha256 $file.FullName } }
    Write-DenoUtf8Text (Join-Path $outputRoot 'source-inventory.json') (([ordered]@{ schemaVersion = 'deno-source-inventory/v1'; files = @($inventory) } | ConvertTo-Json -Depth 10) + "`n")
    $zipPath = Join-Path $outputRoot 'deno-2.7.14-verified-conservative-superset-sources.zip'
    $zipSha256 = New-DenoDeterministicZip -SourceRoot $stage -ZipPath $zipPath
    return [pscustomobject]@{ status = 'complete'; closureClassification = $inputs.closureClassification; outputRoot = $outputRoot; zipPath = $zipPath; zipSha256 = $zipSha256; counts = $counts; overallReleasePass = $false }
}

if ($Run) {
    $required = @($DenoSourceRoot, $RustyV8SourceRoot, $V8SourceRoot, $VendorRoot, $OfficialMetadataPath,
        $SupersetMetadataPath, $DenoExePath, $DenoSourceArchivePath, $RustyV8SourceArchivePath,
        $V8SourceArchivePath, $RustyV8StaticLibArchivePath, $NativeSourceRoot, $ScratchRoot)
    if (@($required | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { throw 'deno_run_parameters_required' }
    Invoke-DenoThirdPartyNoticeCollection -ManifestRoot $ManifestRoot -DenoSourceRoot $DenoSourceRoot `
        -RustyV8SourceRoot $RustyV8SourceRoot -V8SourceRoot $V8SourceRoot -VendorRoot $VendorRoot `
        -OfficialMetadataPath $OfficialMetadataPath -SupersetMetadataPath $SupersetMetadataPath `
        -DenoExePath $DenoExePath -DenoSourceArchivePath $DenoSourceArchivePath `
        -RustyV8SourceArchivePath $RustyV8SourceArchivePath -V8SourceArchivePath $V8SourceArchivePath `
        -RustyV8StaticLibArchivePath $RustyV8StaticLibArchivePath -NativeSourceRoot $NativeSourceRoot `
        -ScratchRoot $ScratchRoot
}
