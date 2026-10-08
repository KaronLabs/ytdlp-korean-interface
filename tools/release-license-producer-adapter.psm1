#requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProducerProperty {
    param([object] $Value, [string] $Name)
    if ($null -ne $Value) {
        if ($Value -is [Collections.IDictionary]) {
            foreach ($key in $Value.Keys) { if ([string]$key -ceq $Name) { return $Value[$key] } }
        }
        else {
            $property = $Value.PSObject.Properties[$Name]
            if ($null -ne $property -and $property.Name -ceq $Name) { return $property.Value }
        }
    }
    throw 'release_license_lock_producer_property_missing'
}

function Assert-ProducerDigest {
    param([object] $Actual, [object] $Expected)
    if ($Actual -isnot [string] -or $Expected -isnot [string] -or
        $Actual -notmatch '^[a-fA-F0-9]{64}$' -or $Expected -notmatch '^[a-fA-F0-9]{64}$' -or
        $Actual.ToLowerInvariant() -cne $Expected.ToLowerInvariant()) { throw 'release_license_lock_producer_digest_mismatch' }
}

function Assert-ProducerLength {
    param([object] $Actual, [object] $Expected)
    foreach ($value in @($Actual, $Expected)) {
        if (($value -isnot [int] -and $value -isnot [long]) -or $value -lt 0) { throw 'release_license_lock_producer_length_invalid' }
    }
    if ($Actual -ne $Expected) { throw 'release_license_lock_producer_length_mismatch' }
}

function Assert-ProducerRecord {
    param([object] $Record, [object] $Sha256, [object] $Length)
    Assert-ProducerDigest (Get-ProducerProperty $Record 'sha256') $Sha256
    Assert-ProducerLength (Get-ProducerProperty $Record 'length') $Length
}

function Assert-ProducerPath {
    param([string] $Path, [switch] $Leaf)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Contains('\') -or $Path.Contains(':') -or
        $Path.StartsWith('/') -or $Path.EndsWith('/') -or $Path.Contains('//') -or
        $Path -cne $Path.Normalize([Text.NormalizationForm]::FormC) -or
        @($Path.Split('/') | Where-Object { $_ -ceq '.' -or $_ -ceq '..' }).Count -ne 0 -or
        ($Leaf -and $Path.Contains('/'))) { throw 'release_license_lock_producer_path_invalid' }
}

function Test-KaronNonRuntimeProducer {
    param([object] $Manifest)
    (Get-ProducerProperty $Manifest 'release') -isnot [string]
}

function Assert-KaronSourceArchiveMetadata {
    param([object] $Archive, [object] $Component, [object] $ApplicationComponent, [string] $ApplicationCommit)
    $fileName = [string](Get-ProducerProperty $Archive 'fileName')
    Assert-ProducerPath $fileName -Leaf
    $sha = Get-ProducerProperty $Archive 'sha256'
    Assert-ProducerDigest $sha $sha
    $length = Get-ProducerProperty $Archive 'length'
    Assert-ProducerLength $length $length
    if ($length -le 0) { throw 'release_license_lock_source_archive_mismatch' }
    $id = [string](Get-ProducerProperty $Component 'id')
    $commit = [string](Get-ProducerProperty $Archive 'commit')
    $sourceCommit = [string](Get-ProducerProperty $Component 'sourceCommit')
    if ($commit -notmatch '^[a-f0-9]{40}$') { throw 'release_license_lock_source_archive_mismatch' }
    $url = Get-ProducerProperty $Archive 'url'
    $typeProperty = $Archive.PSObject.Properties['artifactType']
    if ($Archive -is [Collections.IDictionary]) { $type = $Archive['artifactType'] }
    else { $type = if ($null -ne $typeProperty) { $typeProperty.Value } else { $null } }
    if ($null -ne $type) {
        $provenance = Get-ProducerProperty $Archive 'provenance'
        $staticApplication = $id -cin @('bit7z', 'nana', 'libpng', 'zlib', 'libjpeg-turbo', 'nlohmann-json') -and
            (Get-ProducerProperty $provenance 'component') -ceq 'application'
        $owner = if ($staticApplication) { 'application' } else { $id }
        $ownerCommit = if ($staticApplication) { $ApplicationCommit } else { $sourceCommit }
        if ($type -cne 'generated-source-closure' -or ($id -cnotin @('application', 'deno', 'ffmpeg', '7zip') -and -not $staticApplication) -or
            $null -ne $url -or $commit -cne $ownerCommit -or $fileName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\.zip$' -or
            $fileName -match '^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)' -or
            (Get-ProducerProperty $provenance 'component') -cne $owner -or
            (Get-ProducerProperty $provenance 'sourceCommit') -cne $commit) { throw 'release_license_lock_source_archive_mismatch' }
        if ($staticApplication) {
            if ((Get-ProducerProperty $ApplicationComponent 'sourceCommit') -cne $commit) { throw 'release_license_lock_source_archive_mismatch' }
            $matches = @((Get-ProducerProperty $ApplicationComponent 'sourceArchives') | Where-Object {
                (Get-ProducerProperty $_ 'fileName') -ceq $fileName -and (Get-ProducerProperty $_ 'commit') -ceq $commit -and
                (Get-ProducerProperty $_ 'url') -eq $null
            })
            if ($matches.Count -ne 1 -or (Get-ProducerProperty $matches[0] 'artifactType') -cne $type) { throw 'release_license_lock_source_archive_mismatch' }
            Assert-ProducerRecord $Archive (Get-ProducerProperty $matches[0] 'sha256') (Get-ProducerProperty $matches[0] 'length')
        }
        return
    }
    $repository = [string](Get-ProducerProperty $Component 'sourceRepository')
    if ($commit -ceq $sourceCommit -and $url -ceq ($repository.TrimEnd('/') + '/archive/' + $commit + '.zip')) { return }
    if ($id -cnotin @('bit7z', 'nana', 'libpng', 'zlib', 'libjpeg-turbo', 'nlohmann-json') -or
        $commit -cne $ApplicationCommit -or (Get-ProducerProperty $ApplicationComponent 'sourceCommit') -cne $ApplicationCommit) {
        throw 'release_license_lock_source_archive_mismatch'
    }
    $appRepository = [string](Get-ProducerProperty $ApplicationComponent 'sourceRepository')
    if ($url -cne ($appRepository.TrimEnd('/') + '/archive/' + $ApplicationCommit + '.zip')) { throw 'release_license_lock_source_archive_mismatch' }
    $matches = @((Get-ProducerProperty $ApplicationComponent 'sourceArchives') | Where-Object {
        (Get-ProducerProperty $_ 'fileName') -ceq $fileName -and (Get-ProducerProperty $_ 'commit') -ceq $commit -and
        (Get-ProducerProperty $_ 'url') -ceq $url
    })
    if ($matches.Count -ne 1) { throw 'release_license_lock_source_archive_mismatch' }
    Assert-ProducerRecord $Archive (Get-ProducerProperty $matches[0] 'sha256') (Get-ProducerProperty $matches[0] 'length')
}

function Assert-KaronNonRuntimeProducer {
    param(
        [object] $Manifest, [object] $Inventory, [object[]] $Components, [object] $CandidateManifest,
        [object] $CandidateRecords, [object] $ManifestRecord, [object] $InventoryRecord,
        [object] $CandidateManifestRecord, [object] $BundleRecord, [object] $BundleInventory, [object] $SourceCacheRecords
    )
    # Immutable approved bytes authenticate the original object schemas and transforms.
    Assert-ProducerDigest $ManifestRecord.sha256 '4DBA01D3EF824458AD50A5A212700D4932F0240FF328075C097B68FA8C3388D6'
    Assert-ProducerDigest $Inventory.manifestSha256 $ManifestRecord.sha256
    Assert-ProducerDigest $Inventory.manifestProjectionSha256 '6120601F62EA99F4A09C9C2491854DCE7A3F3F56687958D4109F51FD393EB5BD'
    if ($Manifest.schemaVersion -cne 'karon-non-runtime-component-evidence/v1' -or
        $Inventory.schemaVersion -cne 'karon-source-cache-inventory/v1' -or
        $Manifest.approvalProfile -cne 'karon-v2.19.1-karon.2-non-runtime-v1' -or
        $Inventory.approvalProfile -cne $Manifest.approvalProfile -or
        $Manifest.release.tag -cne 'v2.19.1-karon.2' -or $Manifest.release.platform -cne 'win-x64' -or
        $Inventory.release -cne $Manifest.release.tag -or $Inventory.scope -cne 'non-ffmpeg-non-deno' -or
        $Inventory.status -cne 'closed') { throw 'release_license_lock_nonruntime_invalid' }
    $commit = $CandidateManifest.applicationSourceCommit
    $tree = $CandidateManifest.applicationSourceTree
    if ($commit -notmatch '^[a-f0-9]{40}$' -or $tree -notmatch '^[a-f0-9]{40}$' -or
        $Inventory.applicationCommit -cne $commit -or $CandidateManifest.attestation.source.commit -cne $commit -or
        $CandidateManifest.attestation.source.tree -cne $tree -or
        $CandidateManifest.attestation.source.dirty -isnot [bool] -or $CandidateManifest.attestation.source.dirty -or
        @($CandidateManifest.attestation.commands).Count -eq 0) { throw 'release_license_lock_nonruntime_binding_mismatch' }
    Assert-ProducerDigest $Inventory.candidateManifestSha256 $CandidateManifestRecord.sha256
    Assert-ProducerLength $Inventory.candidateManifestLength $CandidateManifestRecord.length
    Assert-ProducerDigest $Inventory.dependencyArchiveSha256 $Manifest.sharedInputs.dependencyArchive.sha256
    Assert-ProducerDigest $CandidateManifest.attestation.dependencyArchive.sha256 $Inventory.dependencyArchiveSha256

    $expectedBundle = @{
        'component-manifest.json' = $ManifestRecord
        'source-cache-inventory.json' = $InventoryRecord
        'evidence/candidate-manifest.json' = $CandidateManifestRecord
    }
    $dependency = $Manifest.sharedInputs.dependencyArchive
    $expectedBundle['evidence/dependency-archive/dependency-archive.bin'] = @{ sha256 = $dependency.sha256; length = $dependency.length }
    $task5 = $Manifest.sharedInputs.sevenZipTask5
    foreach ($item in @(
        @('runtimeArchive', 'sevenzip-runtime.7z'), @('sourceArchive', 'sevenzip-source.7z'), @('verification', 'sevenzip-verification.json')
    )) {
        $sha = Get-ProducerProperty $task5 ($item[0] + 'Sha256')
        Assert-ProducerDigest (Get-ProducerProperty $Inventory.sevenZipTask5 ($item[0] + 'Sha256')) $sha
        $expectedBundle['evidence/task5/' + $item[1]] = @{ sha256 = $sha; length = (Get-ProducerProperty $task5 ($item[0] + 'Length')) }
    }
    $declared = @{}
    $bindings = @()
    $linkers = @{}
    foreach ($input in $CandidateManifest.attestation.linkerInputs) {
        if ($linkers.ContainsKey($input.library)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
        Assert-ProducerDigest $input.sha256 $input.sha256
        Assert-ProducerLength $input.length $input.length
        if ($input.length -le 0) { throw 'release_license_lock_nonruntime_binding_mismatch' }
        $linkers[$input.library] = $input
    }
    foreach ($library in $Manifest.sharedInputs.candidate.requiredLinkerLibraries) {
        if (-not $linkers.ContainsKey($library)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
    }
    if (@($Manifest.components).Count -ne $Manifest.release.expectedComponentCount) { throw 'release_license_lock_nonruntime_invalid' }
    foreach ($component in $Manifest.components) {
        $matches = @($Components | Where-Object { $_.id -ceq $component.id })
        if ($matches.Count -ne 1) { throw 'release_license_lock_nonruntime_binding_mismatch' }
        $lock = $matches[0]
        foreach ($name in @('version', 'sourceRepository', 'licenseExpression', 'modified')) {
            if ((Get-ProducerProperty $component $name) -cne (Get-ProducerProperty $lock $name)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
        }
        $sourceCommit = if ($component.id -ceq 'application') { $commit } else { $component.sourceCommit }
        if ($lock.sourceCommit -cne $sourceCommit -or $lock.buildRecipe -cne $component.buildRecipe.description) { throw 'release_license_lock_nonruntime_binding_mismatch' }
        foreach ($artifact in $component.sourceArtifacts) {
            if ($declared.ContainsKey($artifact.id)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
            $declared[$artifact.id] = @{ component = $component.id; record = $artifact }
        }
        $binding = $component.buildRecipe.candidateBinding
        switch -CaseSensitive ($binding.kind) {
            'application-source' {
                if ($component.id -cne 'application' -or -not $CandidateRecords.ContainsKey($binding.candidatePath)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
                $bindings += @{ component = $component.id; kind = $binding.kind; file = $CandidateRecords[$binding.candidatePath]; commit = $commit; tree = $tree }
            }
            'candidate-file' {
                if (-not $CandidateRecords.ContainsKey($binding.candidatePath)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
                Assert-ProducerDigest $CandidateRecords[$binding.candidatePath].sha256 $binding.sha256
                $bindings += @{ component = $component.id; kind = $binding.kind; file = $CandidateRecords[$binding.candidatePath] }
            }
            'static-linker-input' {
                if (-not $linkers.ContainsKey($binding.library)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
                $bindings += @{ component = $component.id; kind = $binding.kind; linkerInput = $linkers[$binding.library] }
            }
            'build-input' {
                $embedded = @($dependency.embeddedFiles | Where-Object { $_.path -ceq $binding.dependencyPath })
                if ($embedded.Count -ne 1) { throw 'release_license_lock_nonruntime_binding_mismatch' }
                $bindings += @{ component = $component.id; kind = $binding.kind; dependencyInput = $embedded[0] }
            }
            'transitive-static-source' {
                $roots = @($dependency.roots | Where-Object { $_.path -ceq $binding.dependencyPath })
                if (-not $linkers.ContainsKey($binding.parentLibrary) -or $roots.Count -ne 1) { throw 'release_license_lock_nonruntime_binding_mismatch' }
                $bindings += @{ component = $component.id; kind = $binding.kind; dependencyRoot = $roots[0]; linkerInput = $linkers[$binding.parentLibrary] }
            }
            'compiled-header' {
                $transforms = @($component.transforms | Where-Object { $_.kind -ceq 'lf-to-crlf' -and $_.repositoryPath -ceq $binding.repositoryPath })
                if ($transforms.Count -ne 1) { throw 'release_license_lock_nonruntime_binding_mismatch' }
                $transform = $transforms[0]
                Assert-ProducerDigest $binding.targetSha256 $transform.targetSha256
                $expectedBundle['evidence/nlohmann-json-header.transform.json'] = @{ sha256 = $transform.transformEvidenceSha256; length = $transform.transformEvidenceLength }
                $bindings += @{ component = $component.id; kind = $binding.kind; transform = $transform }
            }
            default { throw 'release_license_lock_nonruntime_binding_mismatch' }
        }
    }
    $appName = 'karon-application-' + $commit.Substring(0, 12) + '.zip'
    $declared['application-source'] = @{ component = 'application'; record = $null }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $fileNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $applicationSource = $null
    foreach ($artifact in $Inventory.artifacts) {
        if (-not $seen.Add($artifact.id) -or -not $declared.ContainsKey($artifact.id) -or
            -not $fileNames.Add($artifact.fileName) -or $artifact.status -cne 'verified') { throw 'release_license_lock_nonruntime_invalid' }
        Assert-ProducerPath $artifact.fileName -Leaf
        Assert-ProducerDigest $artifact.expectedSha256 $artifact.actualSha256
        Assert-ProducerLength $artifact.expectedLength $artifact.actualLength
        if ($artifact.id -ceq 'application-source') {
            $entryPath = 'application/' + $appName
            if (-not $BundleInventory.ContainsKey($entryPath)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
            $embedded = $BundleInventory[$entryPath]
            $record = [ordered]@{ fileName = $appName; sha256 = $embedded.sha256; length = $embedded.length }
        }
        else {
            if (-not $SourceCacheRecords.ContainsKey($artifact.fileName)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
            $record = $SourceCacheRecords[$artifact.fileName]
        }
        Assert-ProducerRecord $record $artifact.actualSha256 $artifact.actualLength
        $declaration = $declared[$artifact.id]
        if ($artifact.component -cne $declaration.component) { throw 'release_license_lock_nonruntime_binding_mismatch' }
        if ($artifact.id -ceq 'application-source') {
            if ($artifact.fileName -cne $appName -or $artifact.includeInBundle -isnot [bool] -or -not $artifact.includeInBundle -or
                $artifact.url -cne ('https://github.com/KaronLabs/ytdlp-korean-interface/commit/' + $commit)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
            $applicationSource = $record
            $expectedBundle['application/' + $appName] = $record
        }
        else {
            $wanted = $declaration.record
            foreach ($name in @('fileName', 'url', 'includeInBundle')) {
                if ((Get-ProducerProperty $artifact $name) -cne (Get-ProducerProperty $wanted $name)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
            }
            Assert-ProducerRecord $record $wanted.sha256 $wanted.length
            if ($wanted.includeInBundle) { $expectedBundle['sources/' + $wanted.fileName] = $record }
        }
    }
    if ($seen.Count -ne $declared.Count -or $BundleInventory.Count -ne $expectedBundle.Count) { throw 'release_license_lock_unclassified' }
    foreach ($path in $expectedBundle.Keys) {
        if (-not $BundleInventory.ContainsKey($path)) { throw 'release_license_lock_nonruntime_binding_mismatch' }
        Assert-ProducerRecord $BundleInventory[$path] $expectedBundle[$path].sha256 $expectedBundle[$path].length
    }
    [ordered]@{
        applicationSourceArchive = $BundleRecord
        gitApplicationSourceArchive = $applicationSource
        manifestProjectionSha256 = $Inventory.manifestProjectionSha256.ToLowerInvariant()
        candidateBindings = $bindings
        sourceArtifacts = $Inventory.artifacts
    }
}

function Assert-KaronFfmpegInventory {
    param([object] $Inventory, [object] $Manifest, [object] $ArchiveInventory, [object] $ManifestRecord)
    if ($Inventory.schemaVersion -ne 1 -or $Inventory.policy -cne 'verified-conservative-superset' -or
        $Inventory.inventorySelfEntry -cne 'inventory.json' -or -not $ArchiveInventory.ContainsKey('inventory.json')) {
        throw 'release_license_lock_ffmpeg_closure_invalid'
    }
    foreach ($pair in @(
        @('sourceArchiveCount', 'totalSourceArchives'), @('cacheArchiveCount', 'btbnCacheArchives'),
        @('rav1eCrateCount', 'rav1eCrates'), @('toolchainSourceCount', 'toolchainSourceArchives'), @('licenseTextObjectCount', 'licenseTextObjects')
    )) { Assert-ProducerLength (Get-ProducerProperty $Inventory $pair[0]) (Get-ProducerProperty $Manifest.counts $pair[1]) }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $Inventory.entries) {
        Assert-ProducerPath $entry.path
        if ($entry.path -ceq 'inventory.json' -or -not $seen.Add($entry.path) -or -not $ArchiveInventory.ContainsKey($entry.path)) {
            throw 'release_license_lock_ffmpeg_closure_invalid'
        }
        Assert-ProducerRecord $ArchiveInventory[$entry.path] $entry.sha256 $entry.bytes
    }
    if ($seen.Count -eq 0 -or $ArchiveInventory.Count -ne ($seen.Count + 1)) { throw 'release_license_lock_ffmpeg_closure_invalid' }
    foreach ($pair in @(
        @('sources/direct/', 'directSourceArchives'), @('sources/btbn-cache/', 'btbnCacheArchives'),
        @('sources/rav1e-crates/', 'rav1eCrates'), @('sources/toolchain/', 'toolchainSourceArchives')
    )) {
        $count = @($Inventory.entries | Where-Object { $_.path.StartsWith($pair[0], [StringComparison]::Ordinal) }).Count
        Assert-ProducerLength ([long]$count) (Get-ProducerProperty $Manifest.counts $pair[1])
    }
    $sourceCount = @($Inventory.entries | Where-Object { $_.path.StartsWith('sources/', [StringComparison]::Ordinal) }).Count
    Assert-ProducerLength ([long]$sourceCount) (Get-ProducerProperty $Inventory 'sourceArchiveCount')
    if ($null -ne $ManifestRecord) {
        if (-not $ArchiveInventory.ContainsKey('manifest.json')) { throw 'release_license_lock_ffmpeg_closure_invalid' }
        Assert-ProducerRecord $ArchiveInventory['manifest.json'] $ManifestRecord.sha256 $ManifestRecord.length
    }
    $projection = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $Manifest.includedPaths) {
        Assert-ProducerPath $path
        if (-not $projection.Add($path) -or -not $ArchiveInventory.ContainsKey($path)) { throw 'release_license_lock_ffmpeg_closure_invalid' }
    }
    if (-not $projection.Contains('buildconf.txt') -or -not $projection.Contains('NOTICE.md')) { throw 'release_license_lock_ffmpeg_closure_invalid' }
}

function Assert-KaronDenoRootSource {
    param([object] $Component, [object] $ArchiveInventory)
    $archives = @(Get-ProducerProperty $Component 'sourceArchives')
    if ($archives.Count -ne 1) { throw 'release_license_lock_deno_artifact_mismatch' }
    $provenance = Get-ProducerProperty $archives[0] 'provenance'
    $source = Get-ProducerProperty $provenance 'upstreamSource'
    $commit = [string](Get-ProducerProperty $Component 'sourceCommit')
    $entryPath = 'SOURCES/deno-source-' + $commit + '.zip'
    $repository = [string](Get-ProducerProperty $Component 'sourceRepository')
    if ($commit -notmatch '^[a-f0-9]{40}$' -or (Get-ProducerProperty $source 'commit') -cne $commit -or
        (Get-ProducerProperty $source 'entryPath') -cne $entryPath -or
        (Get-ProducerProperty $source 'url') -cne ($repository.TrimEnd('/') + '/archive/' + $commit + '.zip') -or
        -not $ArchiveInventory.ContainsKey($entryPath)) { throw 'release_license_lock_deno_artifact_mismatch' }
    Assert-ProducerRecord $ArchiveInventory[$entryPath] (Get-ProducerProperty $source 'sha256') (Get-ProducerProperty $source 'length')
    $source
}

Export-ModuleMember -Function Test-KaronNonRuntimeProducer, Assert-KaronSourceArchiveMetadata, Assert-KaronNonRuntimeProducer, Assert-KaronFfmpegInventory, Assert-KaronDenoRootSource
