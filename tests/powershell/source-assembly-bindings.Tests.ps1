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
