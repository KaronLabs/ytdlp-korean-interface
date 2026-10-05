#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repository 'tools/release-license-producer-adapter.psm1') -Force

function New-ProducerRecord {
    param([string] $Name, [string] $Sha = ('a' * 64), [long] $Length = 10)
    [ordered]@{ fileName = $Name; sha256 = $Sha; length = $Length }
}

function New-ProductionProjectionFixture {
    # Real approved schema, small in-memory identity records; not runtime evidence.
    $manifestPath = Join-Path $repository 'release/evidence/v2.19.1-karon.2/non-runtime-components.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $commit = 'b80f594a2b6673d28e00e705659c39b0c4bed647'
    $tree = '541a9bef018b4b266ba0ca8469ecb2868ef1e6df'
    $manifestRecord = New-ProducerRecord 'component-manifest.json' (Get-FileHash $manifestPath -Algorithm SHA256).Hash (Get-Item $manifestPath).Length
    $candidateRecord = New-ProducerRecord 'candidate-manifest.json' ('b' * 64) 100
    $bundleRecord = New-ProducerRecord 'non-runtime.zip' ('c' * 64) 200
    $inventoryRecord = New-ProducerRecord 'source-cache-inventory.json' ('d' * 64) 300
    $candidateRecords = @{}
    $candidateRecords['ytdlp-interface.exe'] = New-ProducerRecord 'ytdlp-interface.exe'
    foreach ($component in $manifest.components) {
        $binding = $component.buildRecipe.candidateBinding
        if ($binding.kind -ceq 'candidate-file') {
            $candidateRecords[$binding.candidatePath] = New-ProducerRecord $binding.candidatePath $binding.sha256
        }
    }
    $candidate = [pscustomobject]@{
        applicationSourceCommit = $commit; applicationSourceTree = $tree
        attestation = [pscustomobject]@{
            source = [pscustomobject]@{ commit = $commit; tree = $tree; dirty = $false }
            dependencyArchive = [pscustomobject]@{ sha256 = $manifest.sharedInputs.dependencyArchive.sha256 }
            linkerInputs = @($manifest.sharedInputs.candidate.requiredLinkerLibraries | ForEach-Object {
                [pscustomobject]@{ library = $_; sha256 = ('e' * 64); length = 10 }
            })
            commands = @([pscustomobject]@{ name = 'fixture build description' })
        }
    }
    $artifacts = @()
    $cache = @{}
    $bundle = @{
        'component-manifest.json' = $manifestRecord
        'source-cache-inventory.json' = $inventoryRecord
        'evidence/candidate-manifest.json' = $candidateRecord
    }
    $components = @()
    foreach ($component in $manifest.components) {
        $sourceCommit = if ($component.id -ceq 'application') { $commit } else { $component.sourceCommit }
        $components += [pscustomobject]@{
            id = $component.id; version = $component.version; sourceRepository = $component.sourceRepository
            sourceCommit = $sourceCommit; licenseExpression = $component.licenseExpression
            modified = $component.modified; buildRecipe = $component.buildRecipe.description
        }
        foreach ($artifact in $component.sourceArtifacts) {
            $record = New-ProducerRecord $artifact.fileName $artifact.sha256 $artifact.length
            $cache[$artifact.fileName] = $record
            if ($artifact.includeInBundle) { $bundle['sources/' + $artifact.fileName] = $record }
            $artifacts += [pscustomobject]@{
                id = $artifact.id; component = $component.id; fileName = $artifact.fileName; url = $artifact.url
                expectedSha256 = $artifact.sha256; expectedLength = $artifact.length
                actualSha256 = $artifact.sha256; actualLength = $artifact.length
                status = 'verified'; includeInBundle = $artifact.includeInBundle
            }
        }
    }
    $appRecord = New-ProducerRecord ('karon-application-' + $commit.Substring(0, 12) + '.zip')
    $cache[$appRecord.fileName] = $appRecord
    $bundle['application/' + $appRecord.fileName] = $appRecord
    $artifacts += [pscustomobject]@{
        id = 'application-source'; component = 'application'; fileName = $appRecord.fileName
        url = 'https://github.com/KaronLabs/ytdlp-korean-interface/commit/' + $commit
        expectedSha256 = $appRecord.sha256; actualSha256 = $appRecord.sha256
        expectedLength = $appRecord.length; actualLength = $appRecord.length
        status = 'verified'; includeInBundle = $true
    }
    $dependency = $manifest.sharedInputs.dependencyArchive
    $bundle['evidence/dependency-archive/dependency-archive.bin'] = New-ProducerRecord 'dependency-archive.bin' $dependency.sha256 $dependency.length
    $task5 = $manifest.sharedInputs.sevenZipTask5
    $bundle['evidence/task5/sevenzip-runtime.7z'] = New-ProducerRecord 'sevenzip-runtime.7z' $task5.runtimeArchiveSha256 $task5.runtimeArchiveLength
    $bundle['evidence/task5/sevenzip-source.7z'] = New-ProducerRecord 'sevenzip-source.7z' $task5.sourceArchiveSha256 $task5.sourceArchiveLength
    $bundle['evidence/task5/sevenzip-verification.json'] = New-ProducerRecord 'sevenzip-verification.json' $task5.verificationSha256 $task5.verificationLength
    $transform = @($manifest.components | Where-Object id -eq 'nlohmann-json')[0].transforms[0]
    $bundle['evidence/nlohmann-json-header.transform.json'] = New-ProducerRecord 'transform.json' $transform.transformEvidenceSha256 $transform.transformEvidenceLength
    $inventory = [pscustomobject]@{
        schemaVersion = 'karon-source-cache-inventory/v1'; release = 'v2.19.1-karon.2'
        scope = 'non-ffmpeg-non-deno'; status = 'closed'; approvalProfile = $manifest.approvalProfile
        manifestSha256 = $manifestRecord.sha256
        manifestProjectionSha256 = '6120601F62EA99F4A09C9C2491854DCE7A3F3F56687958D4109F51FD393EB5BD'
        applicationCommit = $commit; candidateManifestSha256 = $candidateRecord.sha256
        candidateManifestLength = $candidateRecord.length; dependencyArchiveSha256 = $dependency.sha256
        sevenZipTask5 = [pscustomobject]@{
            runtimeArchiveSha256 = $task5.runtimeArchiveSha256
            sourceArchiveSha256 = $task5.sourceArchiveSha256
            verificationSha256 = $task5.verificationSha256
        }
        artifacts = $artifacts
    }
    @{
        Manifest = $manifest; Inventory = $inventory; Components = $components; CandidateManifest = $candidate
        CandidateRecords = $candidateRecords; ManifestRecord = $manifestRecord; InventoryRecord = $inventoryRecord
        CandidateManifestRecord = $candidateRecord; BundleRecord = $bundleRecord
        BundleInventory = $bundle; SourceCacheRecords = $cache
    }
}

Describe 'Raw non-runtime producer protocol' {
    BeforeEach { $fixture = New-ProductionProjectionFixture }
    It 'binds raw approved objects without changing placeholder or buildRecipe' {
        $proof = Assert-KaronNonRuntimeProducer @fixture
        $proof.applicationSourceArchive.sha256 | Should -Be $fixture.BundleRecord.sha256
        $proof.gitApplicationSourceArchive.fileName | Should -Be 'karon-application-b80f594a2b66.zip'
        $fixture.Manifest.components[0].sourceCommit | Should -Be '$APPLICATION_RELEASE_COMMIT'
        $fixture.Manifest.components[0].buildRecipe.candidateBinding.kind | Should -Be 'application-source'
    }
    It 'rejects altered approved manifest bytes' {
        $fixture.ManifestRecord.sha256 = 'f' * 64
        { Assert-KaronNonRuntimeProducer @fixture } | Should -Throw
    }
    It 'rejects stale application identity' {
        $fixture.Inventory.applicationCommit = '8f776b34cf9e644accb9f5e1230dd7e1b24d3def'
        { Assert-KaronNonRuntimeProducer @fixture } | Should -Throw
    }
    It 'rejects expected versus actual source disagreement' {
        $fixture.Inventory.artifacts[0].actualSha256 = 'f' * 64
        { Assert-KaronNonRuntimeProducer @fixture } | Should -Throw
    }
    It 'rejects a missing modified dependency archive' {
        $fixture.BundleInventory.Remove('evidence/dependency-archive/dependency-archive.bin')
        { Assert-KaronNonRuntimeProducer @fixture } | Should -Throw
    }
    It 'rejects missing transform evidence' {
        $fixture.BundleInventory.Remove('evidence/nlohmann-json-header.transform.json')
        { Assert-KaronNonRuntimeProducer @fixture } | Should -Throw
    }
    It 'rejects unclassified bundle entries' {
        $fixture.BundleInventory['unclassified.bin'] = New-ProducerRecord 'unclassified.bin'
        { Assert-KaronNonRuntimeProducer @fixture } | Should -Throw
    }
    It 'rejects a missing static linker input' {
        $fixture.CandidateManifest.attestation.linkerInputs = @($fixture.CandidateManifest.attestation.linkerInputs | Where-Object library -ne 'bit7z.lib')
        { Assert-KaronNonRuntimeProducer @fixture } | Should -Throw
    }
    It 'rejects missing auxiliary source-cache material' {
        $fixture.SourceCacheRecords.Remove('CPM_0.42.3.cmake')
        { Assert-KaronNonRuntimeProducer @fixture } | Should -Throw
    }
}

Describe 'Explicit raw and generated source provenance' {
    BeforeEach {
        $commit = 'b80f594a2b6673d28e00e705659c39b0c4bed647'
        $archive = [pscustomobject]@{
            fileName = 'app.zip'; commit = $commit; sha256 = ('a' * 64); length = 10
            url = 'https://github.com/KaronLabs/ytdlp-korean-interface/archive/' + $commit + '.zip'
        }
        $application = [pscustomobject]@{
            id = 'application'; sourceCommit = $commit; sourceRepository = 'https://github.com/KaronLabs/ytdlp-korean-interface'
            sourceArchives = @($archive)
        }
        $static = [pscustomobject]@{ id = 'bit7z'; sourceCommit = ('c' * 40); sourceRepository = 'https://github.com/rikyoz/bit7z' }
    }
    It 'accepts the exact explicitly application-bound secondary archive' {
        Assert-KaronSourceArchiveMetadata $archive $static $application $commit
    }
    It 'rejects a secondary archive with changed hash' {
        $other = $archive | ConvertTo-Json | ConvertFrom-Json
        $other.sha256 = 'f' * 64
        { Assert-KaronSourceArchiveMetadata $other $static $application $commit } | Should -Throw
    }
    It 'accepts a local generated closure with null URL' {
        $archive | Add-Member artifactType 'generated-source-closure'
        $archive | Add-Member provenance ([pscustomobject]@{ component = 'application'; sourceCommit = $commit })
        $archive.url = $null
        Assert-KaronSourceArchiveMetadata $archive $application $application $commit
    }
    It 'rejects a fabricated upstream URL for generated bytes' {
        $archive | Add-Member artifactType 'generated-source-closure'
        $archive | Add-Member provenance ([pscustomobject]@{ component = 'application'; sourceCommit = $commit })
        { Assert-KaronSourceArchiveMetadata $archive $application $application $commit } | Should -Throw
    }
}

Describe 'FFmpeg complete inventory versus manifest projection' {
    BeforeEach {
        $full = [pscustomobject]@{
            schemaVersion = 1; policy = 'verified-conservative-superset'; inventorySelfEntry = 'inventory.json'
            sourceArchiveCount = 1; cacheArchiveCount = 0; rav1eCrateCount = 0; toolchainSourceCount = 0; licenseTextObjectCount = 1
            entries = @(
                [pscustomobject]@{ path = 'buildconf.txt'; bytes = 10; sha256 = ('a' * 64) }
                [pscustomobject]@{ path = 'NOTICE.md'; bytes = 10; sha256 = ('b' * 64) }
                [pscustomobject]@{ path = 'sources/dependency.tar.gz'; bytes = 10; sha256 = ('c' * 64) }
            )
        }
        $manifest = [pscustomobject]@{
            includedPaths = @('buildconf.txt', 'NOTICE.md')
            counts = [pscustomobject]@{ totalSourceArchives = 1; btbnCacheArchives = 0; rav1eCrates = 0; toolchainSourceArchives = 0; licenseTextObjects = 1 }
        }
        $zip = @{'inventory.json' = (New-ProducerRecord 'inventory.json')}
        foreach ($entry in $full.entries) { $zip[$entry.path] = New-ProducerRecord $entry.path $entry.sha256 $entry.bytes }
    }
    It 'accepts complete indexed content beyond the projection' { Assert-KaronFfmpegInventory $full $manifest $zip }
    It 'rejects an omitted dependency even when all projected files remain' {
        $zip.Remove('sources/dependency.tar.gz')
        { Assert-KaronFfmpegInventory $full $manifest $zip } | Should -Throw
    }
    It 'rejects a changed dependency hash' {
        $zip['sources/dependency.tar.gz'].sha256 = 'f' * 64
        { Assert-KaronFfmpegInventory $full $manifest $zip } | Should -Throw
    }
    It 'rejects undeclared archive content' {
        $zip['extra.bin'] = New-ProducerRecord 'extra.bin'
        { Assert-KaronFfmpegInventory $full $manifest $zip } | Should -Throw
    }
    It 'rejects duplicate or self-referential inventory rows' {
        $full.entries += $full.entries[0]
        { Assert-KaronFfmpegInventory $full $manifest $zip } | Should -Throw
    }
    It 'rejects mismatched source archive counts' {
        $full.sourceArchiveCount = 2
        { Assert-KaronFfmpegInventory $full $manifest $zip } | Should -Throw
    }
}

Describe 'Deno root source versus native tree identity' {
    BeforeEach {
        $commit = '2d674b25625bcc367853d00fe86f6e84390f88cb'
        $entry = 'SOURCES/deno-source-' + $commit + '.zip'
        $root = [pscustomobject]@{
            entryPath = $entry; commit = $commit; sha256 = ('a' * 64); length = 10
            url = 'https://github.com/denoland/deno/archive/' + $commit + '.zip'
        }
        $component = [pscustomobject]@{
            id = 'deno'; sourceCommit = $commit; sourceRepository = 'https://github.com/denoland/deno'
            sourceArchives = @([pscustomobject]@{ provenance = [pscustomobject]@{ upstreamSource = $root } })
        }
        $zip = @{}; $zip[$entry] = New-ProducerRecord $entry $root.sha256 $root.length
    }
    It 'binds the actual Deno root archive rather than rewriting a native commit' { Assert-KaronDenoRootSource $component $zip }
    It 'rejects the wrong root source commit' {
        $root.commit = '348006707529fa4559d931169ad985b3ce518460'
        { Assert-KaronDenoRootSource $component $zip } | Should -Throw
    }
    It 'rejects a changed Deno root archive' {
        $zip[$entry].sha256 = 'f' * 64
        { Assert-KaronDenoRootSource $component $zip } | Should -Throw
    }
}
