#requires -Version 7.4

. {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $script:SupplementRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    Import-Module (Join-Path $script:SupplementRoot 'tools/release-license-producer-adapter.psm1') -Force

    function New-MutagenSupplementCase {
        $archive = Get-Content -LiteralPath (Join-Path $script:SupplementRoot 'tools/supplemental-sources/yt-dlp-mutagen-1.48.1.json') -Raw | ConvertFrom-Json
        $component = [pscustomobject]@{
            id = 'yt-dlp'; version = '2026.08.30.232658'
            sourceRepository = 'https://github.com/yt-dlp/yt-dlp'
            sourceCommit = 'bbc809a1161d3bfca51fa36f59dda35556ee85a0'
            binaryProvenance = [pscustomobject]@{
                sourceCommit = 'bbc809a1161d3bfca51fa36f59dda35556ee85a0'
                sha256 = 'a3a504c66e91f6474cef0be83b16aedfb7b42b9400a962242d0d433e98f67a70'
                length = 17842860L
            }
        }
        [pscustomobject]@{ Archive = $archive; Component = $component }
    }
}

Describe 'Pinned yt-dlp mutagen supplemental source' {
    It 'accepts the separate upstream source without mutating producer metadata' {
        $case = New-MutagenSupplementCase
        $before = $case | ConvertTo-Json -Depth 10 -Compress
        { Assert-KaronSourceArchiveMetadata $case.Archive $case.Component } | Should -Not -Throw
        ($case | ConvertTo-Json -Depth 10 -Compress) | Should -BeExactly $before
        $case.Archive.commit | Should -Not -Be $case.Component.sourceCommit
    }

    It 'rejects a changed source or runtime identity: <field>' -TestCases @(
        @{ field = 'commit' }, @{ field = 'url' }, @{ field = 'sha256' }, @{ field = 'length' },
        @{ field = 'version' }, @{ field = 'runtimeSha256' }, @{ field = 'runtimeLength' },
        @{ field = 'runtimePath' }, @{ field = 'relationship' }, @{ field = 'sourceRepository' },
        @{ field = 'parentCommit' }, @{ field = 'parentId' }, @{ field = 'binarySha256' }
    ) {
        param($field)
        $case = New-MutagenSupplementCase
        switch ($field) {
            'commit' { $case.Archive.commit = ('0' * 40) }
            'url' { $case.Archive.url = 'https://example.test/mutagen.zip' }
            'sha256' { $case.Archive.sha256 = ('0' * 64) }
            'length' { $case.Archive.length++ }
            'version' { $case.Archive.supplementalSource.version = '1.48.0' }
            'runtimeSha256' { $case.Archive.supplementalSource.runtimeSha256 = ('0' * 64) }
            'runtimeLength' { $case.Archive.supplementalSource.runtimeLength++ }
            'runtimePath' { $case.Archive.supplementalSource.runtimePath = 'other.exe' }
            'relationship' { $case.Archive.supplementalSource.relationship = 'static-link' }
            'sourceRepository' { $case.Archive.supplementalSource.sourceRepository = 'https://example.test/mutagen' }
            'parentCommit' { $case.Component.sourceCommit = ('0' * 40) }
            'parentId' { $case.Component.id = 'application' }
            'binarySha256' { $case.Component.binaryProvenance.sha256 = ('0' * 64) }
        }
        { Assert-KaronSourceArchiveMetadata $case.Archive $case.Component } | Should -Throw
    }

    It 'does not permit a foreign archive without the explicit supplemental identity' {
        $case = New-MutagenSupplementCase
        $case.Archive.PSObject.Properties.Remove('supplementalSource')
        { Assert-KaronSourceArchiveMetadata $case.Archive $case.Component } | Should -Throw
    }

    It 'rejects relabeling the upstream source as a generated closure' {
        $case = New-MutagenSupplementCase
        $case.Archive | Add-Member -NotePropertyName artifactType -NotePropertyValue 'generated-source-closure'
        { Assert-KaronSourceArchiveMetadata $case.Archive $case.Component } | Should -Throw
    }

    It 'continues to accept the original primary yt-dlp source contract' {
        $case = New-MutagenSupplementCase
        $primary = [pscustomobject]@{
            fileName = 'yt-dlp-bbc809a1161d3bfca51fa36f59dda35556ee85a0.zip'
            commit = $case.Component.sourceCommit
            url = ($case.Component.sourceRepository + '/archive/' + $case.Component.sourceCommit + '.zip')
            sha256 = '62a651de6ffcd3631ca34f0f617932bdedc4a6be652777acae8a11d1cafd172b'
            length = 3854279L
        }
        { Assert-KaronSourceArchiveMetadata $primary $case.Component } | Should -Not -Throw
    }
}
