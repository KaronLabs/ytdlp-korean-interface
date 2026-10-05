#requires -Version 7.4

# Pester 4.10.1 loads shared setup directly in the test-file scope.
. {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $script:GeneratedSourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $script:GeneratedSourceRoot 'tools\generated-source-archive.psm1') -Force

    function New-GeneratedArchiveContract {
        param([string] $ComponentId = 'deno')
        $commit = '0123456789abcdef0123456789abcdef01234567'
        $record = [ordered]@{ fileName = "$ComponentId-closure.zip"; length = 123L; sha256 = ('a' * 64) }
        $integration = [ordered]@{ schemaVersion = 'karon-release-license-lock-integration/v1' }
        switch ($ComponentId) {
            'application' { $integration.nonRuntime = [ordered]@{ applicationSourceArchive = $record } }
            'deno' { $integration.denoComponent = [ordered]@{ sourcesArchive = $record } }
            'ffmpeg' { $integration.ffmpeg = [ordered]@{ sourcesArchive = $record } }
            '7zip' {
                $integration.sevenZip = [ordered]@{ sourceWrapper = [ordered]@{
                    fileName = $record.fileName; outerLength = $record.length; outerSha256 = $record.sha256
                    innerLength = 55L; innerSha256 = ('b' * 64)
                } }
            }
        }
        [pscustomobject]@{
            Archive = [ordered]@{
                artifactType = 'generated-source-closure'; url = $null; fileName = $record.fileName
                commit = $commit; length = $record.length; sha256 = $record.sha256; verificationStatus = 'verified'
                provenance = [ordered]@{ component = $ComponentId; sourceCommit = $commit }
            }
            Component = [ordered]@{ id = $ComponentId; sourceCommit = $commit; sourceRepository = "https://example.test/$ComponentId" }
            Release = [ordered]@{ verificationStatus = 'verified'; blockers = @(); integrationEvidence = $integration }
        }
    }

    function Write-GeneratedTestJson {
        param([string] $Path, [object] $Value)
        [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 64) + "`n"), [Text.UTF8Encoding]::new($false))
    }

    function New-GeneratedConsumerCase {
        $root = Join-Path $TestDrive ([Guid]::NewGuid().ToString('N'))
        foreach ($name in @('candidate', 'metadata', 'cache', 'output')) {
            New-Item -ItemType Directory -Path (Join-Path $root $name) -Force | Out-Null
        }
        $candidate = Join-Path $root 'candidate'
        $metadata = Join-Path $root 'metadata'
        $cache = Join-Path $root 'cache'
        $output = Join-Path $root 'output'
        $binaryPath = Join-Path $candidate 'deno.exe'
        [IO.File]::WriteAllBytes($binaryPath, [byte[]](1, 2, 3, 4))
        $noticePath = Join-Path $metadata 'NOTICE.txt'
        [IO.File]::WriteAllText($noticePath, "Synthetic fixture notice.`n", [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $metadata 'THIRD-PARTY-NOTICES.txt'), "Synthetic fixture notices.`n", [Text.UTF8Encoding]::new($false))
        $contract = New-GeneratedArchiveContract
        $archivePath = Join-Path $cache $contract.Archive.fileName
        $stream = [IO.File]::Open($archivePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
        try {
            $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
            try {
                $writer = [IO.StreamWriter]::new($zip.CreateEntry('README.txt').Open(), [Text.UTF8Encoding]::new($false))
                try { $writer.Write('Synthetic generated source closure.') } finally { $writer.Dispose() }
            }
            finally { $zip.Dispose() }
        }
        finally { $stream.Dispose() }
        $contract.Archive.length = (Get-Item -LiteralPath $archivePath).Length
        $contract.Archive.sha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $proof = $contract.Release.integrationEvidence.denoComponent.sourcesArchive
        $proof.length = $contract.Archive.length
        $proof.sha256 = $contract.Archive.sha256
        $binarySha256 = (Get-FileHash -LiteralPath $binaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifestPath = Join-Path $candidate 'candidate-manifest.json'
        Write-GeneratedTestJson $manifestPath ([ordered]@{
            schemaVersion = 1
            files = @([ordered]@{ path = 'deno.exe'; length = 4L; sha256 = $binarySha256 })
        })
        $officialUrl = "https://example.test/deno/archive/$($contract.Archive.commit).zip"
        $component = $contract.Component
        $component.name = 'Synthetic Deno fixture'
        $component.version = '1.0.0'
        $component.verificationStatus = 'verified'
        $component.blockers = @()
        $component.modified = $true
        $component.filesAnalyzed = $true
        $component.licenseExpression = 'MIT'
        $component.licenseConcluded = 'MIT'
        $component.buildRecipe = 'Synthetic fixture recipe.'
        $component.noticeFiles = @([ordered]@{ path = 'NOTICE.txt'; sha256 = (Get-FileHash -LiteralPath $noticePath -Algorithm SHA256).Hash.ToLowerInvariant() })
        $component.sourceArchives = @($contract.Archive)
        $release = $contract.Release
        $release.tag = 'v2.19.1-karon.2'
        $release.platform = 'win-x64'
        $release.metadataPackage = [ordered]@{
            id = 'release-metadata'; name = 'Synthetic metadata'; version = '1.0.0'
            sourceCommit = $contract.Archive.commit; downloadLocation = $officialUrl
            licenseExpression = 'CC0-1.0'; licenseConcluded = 'CC0-1.0'
        }
        $release.candidateFiles = @(
            [ordered]@{ path = 'deno.exe'; sha256 = $binarySha256; package = 'deno'; licenseConcluded = 'MIT' },
            [ordered]@{ path = 'candidate-manifest.json'; sha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant(); package = 'release-metadata'; licenseConcluded = 'CC0-1.0' }
        )
        $lock = [ordered]@{ schemaVersion = 'karon-license-lock/v2'; release = $release; components = @($component) }
        $lockPath = Join-Path $metadata 'lock.json'
        Write-GeneratedTestJson $lockPath $lock
        [pscustomobject]@{
            Lock = $lock; LockPath = $lockPath; Candidate = $candidate; Metadata = $metadata
            Cache = $cache; Output = $output; ArchivePath = $archivePath; OfficialUrl = $officialUrl
        }
    }

    function Invoke-GeneratedConsumer {
        param([object] $Case, [string] $Tool)
        Write-GeneratedTestJson $Case.LockPath $Case.Lock
        $arguments = @{ LockPath = $Case.LockPath; SourceRoot = $Case.Metadata; CandidateRoot = $Case.Candidate; OutputDirectory = $Case.Output }
        if ($Tool -ceq 'sources') {
            $arguments.CacheDirectory = $Case.Cache
            & (Join-Path $script:GeneratedSourceRoot 'tools\build-corresponding-sources.ps1') @arguments
        }
        else { & (Join-Path $script:GeneratedSourceRoot 'tools\generate-release-spdx.ps1') @arguments }
    }
}

Describe 'Generated source archive producer binding' {
    It 'accepts the designated producer record for <ComponentId>' -TestCases @(
        @{ ComponentId = 'application'; Selector = 'nonRuntime.applicationSourceArchive' },
        @{ ComponentId = 'deno'; Selector = 'denoComponent.sourcesArchive' },
        @{ ComponentId = 'ffmpeg'; Selector = 'ffmpeg.sourcesArchive' },
        @{ ComponentId = '7zip'; Selector = 'sevenZip.sourceWrapper' }
    ) {
        param($ComponentId, $Selector)
        $case = New-GeneratedArchiveContract $ComponentId
        $validated = Assert-GeneratedSourceArchive -Archive $case.Archive -Component $case.Component -Release $case.Release
        $validated.fileName | Should -Be $case.Archive.fileName
        $validated.length | Should -Be 123L
        $validated.sha256 | Should -Be ('a' * 64)
        ($null -eq $validated.url) | Should -Be $true
        $validated.evidencePath | Should -Be "release.integrationEvidence.$Selector"
        $validated.sourceInfo | Should -Match ([regex]::Escape($case.Component.sourceRepository))
        $validated.sourceInfo | Should -Match $case.Component.sourceCommit
    }

    It 'accepts the same contract after JSON deserialization' {
        $case = New-GeneratedArchiveContract | ConvertTo-Json -Depth 20 | ConvertFrom-Json -Depth 20
        (Assert-GeneratedSourceArchive -Archive $case.Archive -Component $case.Component -Release $case.Release).length | Should -Be 123L
    }

    It 'rejects <Mutation> with the specified contract error' -TestCases @(
        @{ Mutation = 'unapproved-component'; Expected = 'component_invalid' },
        @{ Mutation = 'other-approved-component-proof'; Expected = 'proof_missing' },
        @{ Mutation = 'wrong-commit'; Expected = 'commit_mismatch' },
        @{ Mutation = 'wrong-hash'; Expected = 'proof_mismatch' },
        @{ Mutation = 'wrong-length'; Expected = 'proof_mismatch' },
        @{ Mutation = 'wrong-proof-name'; Expected = 'proof_mismatch' },
        @{ Mutation = 'missing-proof'; Expected = 'proof_missing' },
        @{ Mutation = 'unrelated-proof'; Expected = 'proof_missing' },
        @{ Mutation = 'non-null-url'; Expected = 'url_invalid' },
        @{ Mutation = 'empty-url'; Expected = 'url_invalid' },
        @{ Mutation = 'missing-url'; Expected = 'url_invalid' },
        @{ Mutation = 'missing-provenance'; Expected = 'provenance_invalid' },
        @{ Mutation = 'wrong-provenance-component'; Expected = 'provenance_invalid' },
        @{ Mutation = 'wrong-provenance-commit'; Expected = 'provenance_invalid' },
        @{ Mutation = 'unverified-release'; Expected = 'release_unverified' },
        @{ Mutation = 'blocked-release'; Expected = 'release_blocked' }
    ) {
        param($Mutation, $Expected)
        $case = New-GeneratedArchiveContract
        switch ($Mutation) {
            'unapproved-component' { $case.Component.id = 'bit7z' }
            'other-approved-component-proof' { $case.Component.id = 'ffmpeg'; $case.Archive.provenance.component = 'ffmpeg' }
            'wrong-commit' { $case.Archive.commit = ('b' * 40) }
            'wrong-hash' { $case.Archive.sha256 = ('b' * 64) }
            'wrong-length' { $case.Archive.length = 124L }
            'wrong-proof-name' { $case.Release.integrationEvidence.denoComponent.sourcesArchive.fileName = 'different.zip' }
            'missing-proof' { $case.Release.integrationEvidence.denoComponent.Remove('sourcesArchive') }
            'unrelated-proof' {
                $case.Release.integrationEvidence.ffmpeg = $case.Release.integrationEvidence.denoComponent
                $case.Release.integrationEvidence.Remove('denoComponent')
            }
            'non-null-url' { $case.Archive.url = "https://example.test/archive/$($case.Archive.commit).zip" }
            'empty-url' { $case.Archive.url = '' }
            'missing-url' { $case.Archive.Remove('url') }
            'missing-provenance' { $case.Archive.Remove('provenance') }
            'wrong-provenance-component' { $case.Archive.provenance.component = 'ffmpeg' }
            'wrong-provenance-commit' { $case.Archive.provenance.sourceCommit = ('b' * 40) }
            'unverified-release' { $case.Release.verificationStatus = 'NOT_VERIFIED' }
            'blocked-release' { $case.Release.blockers = @('synthetic blocker') }
        }
        { Assert-GeneratedSourceArchive -Archive $case.Archive -Component $case.Component -Release $case.Release } |
            Should -Throw "source_generated_archive_$Expected"
    }

    It 'rejects unsafe generated basename <FileName>' -TestCases @(
        @{ FileName = '../closure.zip' }, @{ FileName = 'nested/closure.zip' },
        @{ FileName = 'C:\closure.zip' }, @{ FileName = 'NUL.zip' }, @{ FileName = 'closure.7z' }
    ) {
        param($FileName)
        $case = New-GeneratedArchiveContract
        $case.Archive.fileName = $FileName
        { Assert-GeneratedSourceArchive -Archive $case.Archive -Component $case.Component -Release $case.Release } |
            Should -Throw 'source_generated_archive_metadata_invalid'
    }

    It 'requires an actual positive integer length <Length>' -TestCases @(
        @{ Length = 0L }, @{ Length = -1L }, @{ Length = 123.5 }, @{ Length = '123' }, @{ Length = $true }
    ) {
        param($Length)
        $case = New-GeneratedArchiveContract
        $case.Archive.length = $Length
        { Assert-GeneratedSourceArchive -Archive $case.Archive -Component $case.Component -Release $case.Release } |
            Should -Throw 'source_generated_archive_metadata_invalid'
    }

    It 'rejects a malformed SHA256 rather than coercing it' {
        $case = New-GeneratedArchiveContract
        $case.Archive.sha256 = 'not-a-sha256'
        { Assert-GeneratedSourceArchive -Archive $case.Archive -Component $case.Component -Release $case.Release } |
            Should -Throw 'source_generated_archive_metadata_invalid'
    }

    It 'does not mistake the 7Zip inner source identity for the outer ZIP' {
        $case = New-GeneratedArchiveContract '7zip'
        $proof = $case.Release.integrationEvidence.sevenZip.sourceWrapper
        $case.Archive.sha256 = $proof.innerSha256
        $case.Archive.length = $proof.innerLength
        { Assert-GeneratedSourceArchive -Archive $case.Archive -Component $case.Component -Release $case.Release } |
            Should -Throw 'source_generated_archive_proof_mismatch'
    }
}

Describe 'Generated source consumer contract' {
    It 'packages exact generated cache bytes' {
        $case = New-GeneratedConsumerCase
        $path = Invoke-GeneratedConsumer $case 'sources'
        $zip = [IO.Compression.ZipFile]::OpenRead($path)
        try {
            $entry = $zip.GetEntry('ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources/sources/deno/deno-closure.zip')
            $entry.Length | Should -Be $case.Lock.components[0].sourceArchives[0].length
            $stream = $entry.Open()
            try { $sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)).ToLowerInvariant() }
            finally { $stream.Dispose() }
            $sha256 | Should -Be $case.Lock.components[0].sourceArchives[0].sha256
        }
        finally { $zip.Dispose() }
    }

    It 'uses NOASSERTION and generated sourceInfo without inventing an upstream download' {
        $case = New-GeneratedConsumerCase
        $document = Get-Content -LiteralPath (Invoke-GeneratedConsumer $case 'spdx') -Raw | ConvertFrom-Json -Depth 64
        $sources = @($document.packages | Where-Object { $_.SPDXID -like 'SPDXRef-Source-deno-*' })
        $sources.Count | Should -Be 1
        $sources[0].downloadLocation | Should -Be 'NOASSERTION'
        $sources[0].filesAnalyzed | Should -Be $false
        $sources[0].sourceInfo | Should -Match 'locally generated source closure: deno-closure.zip'
        $sources[0].sourceInfo | Should -Match $case.Lock.components[0].sourceCommit
        $sources[0].checksums[0].checksumValue | Should -Be $case.Lock.components[0].sourceArchives[0].sha256
        @($document.relationships | Where-Object relationshipType -ceq 'GENERATED_FROM').Count | Should -Be 1
        @($document.packages | Where-Object SPDXID -ceq 'SPDXRef-Package-deno')[0].downloadLocation | Should -Be 'NOASSERTION'
    }

    It 'preserves an explicitly provided pinned official component source URL' {
        $case = New-GeneratedConsumerCase
        $case.Lock.components[0].downloadLocation = $case.OfficialUrl
        $document = Get-Content -LiteralPath (Invoke-GeneratedConsumer $case 'spdx') -Raw | ConvertFrom-Json -Depth 64
        @($document.packages | Where-Object SPDXID -ceq 'SPDXRef-Package-deno')[0].downloadLocation | Should -Be $case.OfficialUrl
        @($document.packages | Where-Object { $_.SPDXID -like 'SPDXRef-Source-deno-*' })[0].downloadLocation | Should -Be 'NOASSERTION'
    }

    It 'rejects generated cache <Mutation> without downloading' -TestCases @(
        @{ Mutation = 'missing'; Expected = 'source_generated_archive_cache_missing' },
        @{ Mutation = 'length'; Expected = 'source_generated_archive_length_mismatch' },
        @{ Mutation = 'hash'; Expected = 'source_archive_hash_mismatch' }
    ) {
        param($Mutation, $Expected)
        $case = New-GeneratedConsumerCase
        Mock Invoke-WebRequest { throw 'unexpected_generated_download' }
        switch ($Mutation) {
            'missing' { Remove-Item -LiteralPath $case.ArchivePath }
            'length' { [IO.File]::WriteAllBytes($case.ArchivePath, [byte[]](1, 2, 3)) }
            'hash' {
                $bytes = [IO.File]::ReadAllBytes($case.ArchivePath)
                $bytes[0] = $bytes[0] -bxor 1
                [IO.File]::WriteAllBytes($case.ArchivePath, $bytes)
            }
        }
        { Invoke-GeneratedConsumer $case 'sources' } | Should -Throw "$Expected"
        Assert-MockCalled Invoke-WebRequest -Times 0 -Exactly -Scope It
        @(Get-ChildItem -LiteralPath $case.Output -Force).Count | Should -Be 0
    }

    It 'retains the pinned raw URL path in <Tool>' -TestCases @(@{ Tool = 'sources' }, @{ Tool = 'spdx' }) {
        param($Tool)
        $case = New-GeneratedConsumerCase
        $archive = $case.Lock.components[0].sourceArchives[0]
        $archive.Remove('artifactType')
        $archive.Remove('provenance')
        $archive.url = $case.OfficialUrl
        Test-GeneratedSourceArchive $archive | Should -Be $false
        $path = Invoke-GeneratedConsumer $case $Tool
        Test-Path -LiteralPath $path -PathType Leaf | Should -Be $true
        if ($Tool -ceq 'spdx') {
            $document = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 64
            @($document.packages | Where-Object SPDXID -ceq 'SPDXRef-Package-deno')[0].downloadLocation | Should -Be $case.OfficialUrl
            @($document.packages | Where-Object { $_.SPDXID -like 'SPDXRef-Source-*' }).Count | Should -Be 0
        }
    }

    It 'still rejects raw <UrlKind> URLs in <Tool>' -TestCases @(
        @{ Tool = 'sources'; UrlKind = 'null'; Expected = 'source_url_unpinned' },
        @{ Tool = 'spdx'; UrlKind = 'null'; Expected = 'spdx_source_url_unpinned' },
        @{ Tool = 'sources'; UrlKind = 'branch'; Expected = 'source_url_unpinned' },
        @{ Tool = 'spdx'; UrlKind = 'branch'; Expected = 'spdx_source_url_unpinned' }
    ) {
        param($Tool, $UrlKind, $Expected)
        $case = New-GeneratedConsumerCase
        $archive = $case.Lock.components[0].sourceArchives[0]
        $archive.Remove('artifactType')
        $archive.url = if ($UrlKind -ceq 'null') { $null } else { 'https://example.test/deno/archive/main.zip' }
        { Invoke-GeneratedConsumer $case $Tool } | Should -Throw "$Expected"
    }

    It 'keeps the existing verified-release gate in <Tool>' -TestCases @(
        @{ Tool = 'sources'; Expected = 'source_release_not_verified' },
        @{ Tool = 'spdx'; Expected = 'spdx_release_not_verified' }
    ) {
        param($Tool, $Expected)
        $case = New-GeneratedConsumerCase
        $case.Lock.release.verificationStatus = 'NOT_VERIFIED'
        { Invoke-GeneratedConsumer $case $Tool } | Should -Throw "$Expected"
    }
}
