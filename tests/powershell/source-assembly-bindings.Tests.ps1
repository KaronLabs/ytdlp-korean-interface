#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repository 'tools/generated-source-archive.psm1') -Force
Import-Module (Join-Path $repository 'tools/release-license-producer-adapter.psm1') -Force

Describe 'Modified static source closure bindings' {
    BeforeEach {
        $appCommit = 'b80f594a2b6673d28e00e705659c39b0c4bed647'
        $archive = [ordered]@{
            artifactType = 'generated-source-closure'; fileName = 'non-runtime.zip'
            commit = $appCommit; url = $null; sha256 = ('a' * 64); length = 123L
            provenance = [ordered]@{ component = 'application'; sourceCommit = $appCommit }
        }
        $component = [ordered]@{ id = 'bit7z'; sourceCommit = ('b' * 40); sourceRepository = 'https://github.com/rikyoz/bit7z' }
        $application = [ordered]@{ id = 'application'; sourceCommit = $appCommit; sourceArchives = @($archive) }
        $release = [ordered]@{
            verificationStatus = 'verified'; blockers = @()
            integrationEvidence = [ordered]@{
                schemaVersion = 'karon-release-license-lock-integration/v1'
                applicationSource = [ordered]@{ commit = $appCommit }
                nonRuntime = [ordered]@{ applicationSourceArchive = [ordered]@{ fileName = 'non-runtime.zip'; sha256 = ('a' * 64); length = 123L } }
            }
        }
    }
    It 'retains upstream baseline and separately binds exact modified source' {
        Assert-KaronSourceArchiveMetadata $archive $component $application $appCommit
        $proof = Assert-GeneratedSourceArchive -Archive $archive -Component $component -Release $release
        $proof.evidencePath | Should -Be 'release.integrationEvidence.nonRuntime.applicationSourceArchive'
        $component.sourceCommit | Should -Be ('b' * 40)
        $proof.commit | Should -Be $appCommit
    }
    It 'rejects an application closure for an unrelated build input' {
        $component.id = 'cpm'
        { Assert-GeneratedSourceArchive -Archive $archive -Component $component -Release $release } | Should -Throw
    }
    It 'rejects a modified-source commit differing from sealed application evidence' {
        $release.integrationEvidence.applicationSource.commit = 'c' * 40
        { Assert-GeneratedSourceArchive -Archive $archive -Component $component -Release $release } | Should -Throw
    }
    It 'rejects an unverified assembly without promoting its state' {
        $release.verificationStatus = 'NOT_VERIFIED'
        { Assert-GeneratedSourceArchive -Archive $archive -Component $component -Release $release } | Should -Throw
        $release.verificationStatus | Should -Be 'NOT_VERIFIED'
    }
    It 'rejects a static source closure absent from the application declarations' {
        $application.sourceArchives = @()
        { Assert-KaronSourceArchiveMetadata $archive $component $application $appCommit } | Should -Throw
    }
}

function Write-AssemblyBindingJson {
    param([string] $Path, [object] $Value)
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
}

function New-AssemblyBindingArtifact {
    param([string] $Id, [string] $Component, [string] $Path)
    $sha = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    $length = (Get-Item -LiteralPath $Path).Length
    [ordered]@{
        id = $Id; component = $Component; fileName = [IO.Path]::GetFileName($Path)
        expectedSha256 = $sha; actualSha256 = $sha
        expectedLength = $length; actualLength = $length; status = 'verified'
    }
}

function New-AssemblyBindingFixture {
    $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
    $repo = Join-Path $root 'repository'
    $evidence = Join-Path $root 'evidence'
    $nonRuntime = Join-Path $evidence 'non-runtime-evidence-07'
    $sourceArchives = Join-Path $evidence 'source-archives'
    $lockPath = Join-Path $repo 'release/dependencies/v2.19.1-karon.2.lock.json'
    foreach ($directory in @($nonRuntime, $sourceArchives, (Split-Path -Parent $lockPath))) {
        [void][IO.Directory]::CreateDirectory($directory)
    }
    $official = Join-Path $root 'official.zip'
    $collectedApplication = Join-Path $sourceArchives 'collected-application.zip'
    $cpmSource = Join-Path $sourceArchives 'cpm-source.zip'
    $cpmBootstrap = Join-Path $sourceArchives 'CPM.cmake'
    $bundle = Join-Path $nonRuntime 'ytdlp-korean-interface-v2.19.1-karon.2-non-runtime-component-evidence.zip'
    $denoClosurePath = Join-Path $root 'deno-2.7.14-verified-conservative-superset-sources.zip'
    [IO.File]::WriteAllBytes($official, [byte[]]@(1, 2, 3))
    [IO.File]::WriteAllBytes($collectedApplication, [byte[]]@(4, 5, 6))
    [IO.File]::WriteAllBytes($cpmSource, [byte[]]@(7, 8, 9))
    [IO.File]::WriteAllBytes($cpmBootstrap, [byte[]]@(10, 11, 12))
    [IO.File]::WriteAllBytes($bundle, [byte[]]@(13, 14, 15))
    [IO.File]::WriteAllBytes($denoClosurePath, [byte[]]@(16, 17, 18))
    $appArtifact = New-AssemblyBindingArtifact 'application-source' 'application' $collectedApplication
    $cpmArchive = New-AssemblyBindingArtifact 'cpm-source' 'cpm' $cpmSource
    $cpmScript = New-AssemblyBindingArtifact 'cpm-bootstrap' 'cpm' $cpmBootstrap
    $appCommit = 'a' * 40
    $cpmCommit = 'b' * 40
    $denoCommit = '2d674b25625bcc367853d00fe86f6e84390f88cb'
    $denoClosureSha = (Get-FileHash -LiteralPath $denoClosurePath -Algorithm SHA256).Hash
    $denoClosureLength = (Get-Item -LiteralPath $denoClosurePath).Length
    $denoEntry = 'SOURCES/deno-source-2d674b25625bcc367853d00fe86f6e84390f88cb.zip'
    $denoOrigin = [ordered]@{
        fileName = 'deno-2d674b25.zip'; commit = $denoCommit
        url = "https://github.com/denoland/deno/archive/$denoCommit.zip"
        sha256 = '0fb1aac72af419d8f7de0d623eee7713571d841736d1c01eac97363afd3996dd'
        length = 33443763L; archiveEntry = $denoEntry; containerPath = $denoClosurePath
        verificationStatus = 'NOT_VERIFIED'
    }
    $manifest = [ordered]@{
        schemaVersion = 'karon-non-runtime-component-evidence/v1'; approvalProfile = 'fixture-profile'
        release = [ordered]@{ tag = 'v2.19.1-karon.2'; expectedComponentCount = 2 }
        components = @(
            [ordered]@{ id = 'application'; sourceCommit = '$APPLICATION_RELEASE_COMMIT'; sourceArtifacts = @() },
            [ordered]@{ id = 'cpm'; sourceCommit = $cpmCommit; sourceArtifacts = @(
                [ordered]@{ id = $cpmArchive.id; sha256 = $cpmArchive.expectedSha256; length = $cpmArchive.expectedLength },
                [ordered]@{ id = $cpmScript.id; sha256 = $cpmScript.expectedSha256; length = $cpmScript.expectedLength }
            ) }
        )
    }
    $manifestPath = Join-Path $nonRuntime 'component-manifest.json'
    Write-AssemblyBindingJson $manifestPath $manifest
    $inventory = [ordered]@{
        schemaVersion = 'karon-source-cache-inventory/v1'; release = 'v2.19.1-karon.2'
        approvalProfile = 'fixture-profile'; status = 'closed'; applicationCommit = $appCommit
        manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
        artifacts = @($appArtifact, $cpmArchive, $cpmScript)
    }
    $inventoryPath = Join-Path $nonRuntime 'source-cache-inventory.json'
    Write-AssemblyBindingJson $inventoryPath $inventory
    $oldProof = [ordered]@{
        manifestPath = 'old-manifest.json'; collectorInventoryPath = 'evidence-02/inventory.json'
        collectorBlockersPath = 'evidence-02/blockers.json'; status = 'blocked'
    }
    $lock = [ordered]@{
        schemaVersion = 'karon-license-lock/v2'
        release = [ordered]@{
            applicationSource = [ordered]@{ fileName = 'official.zip'; localPath = $official; commit = $appCommit }
            metadataPackage = [ordered]@{ noticeFiles = @(); bindingNote = 'unsealed'; packagingCommit = $null }
            verificationStatus = 'NOT_VERIFIED'; blockers = @()
        }
        components = @(
            [ordered]@{
                id = 'application'; sourceCommit = $appCommit; sourceArchives = @()
                verificationStatus = 'NOT_VERIFIED'; blockers = @()
                producerEvidence = [ordered]@{
                    manifestPath = $oldProof.manifestPath; collectorInventoryPath = $oldProof.collectorInventoryPath
                    collectorBlockersPath = $oldProof.collectorBlockersPath; status = 'blocked'
                    authoritativeSourceMetadataPath = 'source-authority.json'
                }
            },
            [ordered]@{
                id = 'cpm'; sourceCommit = $cpmCommit; sourceArchives = @()
                verificationStatus = 'NOT_VERIFIED'; blockers = @()
                producerEvidence = $oldProof
            },
            [ordered]@{
                id = 'deno'; sourceCommit = $denoCommit
                verificationStatus = 'NOT_VERIFIED'; blockers = @()
                sourceArchives = @([ordered]@{
                    artifactType = 'generated-source-closure'
                    fileName = [IO.Path]::GetFileName($denoClosurePath)
                    commit = $denoCommit; url = $null; sha256 = $denoClosureSha
                    length = $denoClosureLength; localPath = $denoClosurePath
                    verificationStatus = 'NOT_VERIFIED'; blockers = @()
                    provenance = [ordered]@{
                        component = 'deno'; sourceCommit = $denoCommit
                        upstreamSourceArchives = @($denoOrigin)
                        upstreamSource = [ordered]@{
                            entryPath = $denoEntry; commit = $denoCommit; url = $denoOrigin.url
                            sha256 = $denoOrigin.sha256; length = $denoOrigin.length
                        }
                    }
                })
                upstreamSourceArchives = @($denoOrigin)
                sourceClosure = [ordered]@{
                    localPath = $denoClosurePath
                    fileName = [IO.Path]::GetFileName($denoClosurePath)
                    sha256 = $denoClosureSha; length = $denoClosureLength
                }
            }
        )
    }
    Write-AssemblyBindingJson $lockPath $lock
    $originalLock = Get-Content -LiteralPath $lockPath -Raw
    $null = & git -C $repo init -q
    if ($LASTEXITCODE -ne 0) { throw 'fixture_git_init_failed' }
    $null = & git -C $repo add -- 'release/dependencies/v2.19.1-karon.2.lock.json'
    $null = & git -C $repo -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
    if ($LASTEXITCODE -ne 0) { throw 'fixture_git_commit_failed' }
    $head = ((& git -C $repo rev-parse --verify 'HEAD^{commit}') | Out-String).Trim().ToLowerInvariant()
    [pscustomobject]@{
        Repository = $repo; Evidence = $evidence; Output = (Join-Path $root 'output')
        ManifestPath = $manifestPath; InventoryPath = $inventoryPath; Inventory = $inventory
        LockPath = $lockPath; OriginalLock = $originalLock; Head = $head
    }
}

Describe 'Closed producer evidence in source assembly' {
    BeforeEach {
        $fixture = New-AssemblyBindingFixture
        $prepare = Join-Path $repository 'tools/prepare-release-source-assembly.ps1'
    }
    It 'derives exact e07 proof paths and leaves the committed template untouched' {
        & $prepare -RepositoryRoot $fixture.Repository -EvidenceDirectory $fixture.Evidence -OutputDirectory $fixture.Output | Out-Null
        $result = Get-Content -LiteralPath (Join-Path $fixture.Output 'source-closure-template.json') -Raw | ConvertFrom-Json
        foreach ($component in @($result.components | Where-Object { $_.PSObject.Properties.Name -contains 'producerEvidence' })) {
            $component.producerEvidence.manifestPath | Should -Be $fixture.ManifestPath
            $component.producerEvidence.collectorInventoryPath | Should -Be $fixture.InventoryPath
            $component.producerEvidence.status | Should -Be 'verified'
            ($component.producerEvidence.PSObject.Properties.Name -contains 'collectorBlockersPath') | Should -BeFalse
        }
        $result.components[0].producerEvidence.authoritativeSourceMetadataPath | Should -Be 'source-authority.json'
        $deno = @($result.components | Where-Object id -CEQ 'deno')[0]
        $deno.sourceArchives[0].provenance.upstreamSource.entryPath | Should -Be 'SOURCES/deno-source-2d674b25625bcc367853d00fe86f6e84390f88cb.zip'
        $deno.sourceArchives[0].provenance.upstreamSourceArchives[0].archiveEntry | Should -Be $deno.upstreamSourceArchives[0].archiveEntry
        $deno.sourceArchives[0].provenance.upstreamSource.sha256 | Should -Be $deno.upstreamSourceArchives[0].sha256
        $result.release.metadataPackage.packagingCommit | Should -Be $fixture.Head
        $result.release.verificationStatus | Should -Be 'NOT_VERIFIED'
        $result.release.licenseApproval | Should -Be 'HOLD'
        (Get-Content -LiteralPath $fixture.LockPath -Raw) | Should -Be $fixture.OriginalLock
    }
    It 'refuses a component artifact whose recorded digest is not verified' {
        $fixture.Inventory.artifacts[1].actualSha256 = 'f' * 64
        Write-AssemblyBindingJson $fixture.InventoryPath $fixture.Inventory
        $failure = $null
        try { & $prepare -RepositoryRoot $fixture.Repository -EvidenceDirectory $fixture.Evidence -OutputDirectory $fixture.Output | Out-Null }
        catch { $failure = $_.Exception.Message }
        $failure | Should -Be 'source_assembly_producer_evidence_invalid'
    }
    It 'refuses a missing component proof instead of upgrading stale metadata' {
        $fixture.Inventory.artifacts = @($fixture.Inventory.artifacts | Where-Object id -CNE 'cpm-bootstrap')
        Write-AssemblyBindingJson $fixture.InventoryPath $fixture.Inventory
        $failure = $null
        try { & $prepare -RepositoryRoot $fixture.Repository -EvidenceDirectory $fixture.Evidence -OutputDirectory $fixture.Output | Out-Null }
        catch { $failure = $_.Exception.Message }
        $failure | Should -Be 'source_assembly_producer_evidence_invalid'
    }
    It 'requires the release metadata to be committed before assembly' {
        [IO.File]::AppendAllText($fixture.LockPath, ' ')
        $failure = $null
        try { & $prepare -RepositoryRoot $fixture.Repository -EvidenceDirectory $fixture.Evidence -OutputDirectory $fixture.Output | Out-Null }
        catch { $failure = $_.Exception.Message }
        $failure | Should -Be 'source_assembly_repository_dirty'
    }
}
