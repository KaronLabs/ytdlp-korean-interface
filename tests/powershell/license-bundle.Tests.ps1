#requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:SpdxTool = Join-Path $script:SourceRoot 'tools\generate-release-spdx.ps1'
$script:SourceTool = Join-Path $script:SourceRoot 'tools\build-corresponding-sources.ps1'

function Get-TestSha256 {
    param([Parameter(Mandatory)] [string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-LicenseBundleCase {
    param([string] $Name)

        $root = Join-Path $TestDrive $Name
        $candidate = Join-Path $root 'candidate'
        $metadata = Join-Path $root 'metadata'
        $cache = Join-Path $root 'cache'
        $output = Join-Path $root 'output'
        $noticeDirectory = Join-Path $metadata 'release\licenses\test-component'
        foreach ($directory in @($candidate, $noticeDirectory, $cache, $output)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        $binaryPath = Join-Path $candidate 'app.exe'
        [IO.File]::WriteAllBytes($binaryPath, [byte[]](1, 2, 3, 4))
        $noticePath = Join-Path $noticeDirectory 'NOTICE.txt'
        [IO.File]::WriteAllText($noticePath, "Test notice`n", [Text.UTF8Encoding]::new($false))

        $commit = '0123456789abcdef0123456789abcdef01234567'
        $lock = [ordered]@{
            schemaVersion = 'karon-license-lock/v1'
            release = [ordered]@{
                tag = 'v2.19.1-karon.2'
                platform = 'win-x64'
            }
            components = @(
                [ordered]@{
                    id = 'test-component'
                    name = 'Test Component'
                    version = '1.0.0'
                    sourceRepository = 'https://github.com/example/test-component'
                    sourceCommit = $commit
                    licenseExpression = 'MIT'
                    verificationStatus = 'verified'
                    modified = $false
                    binaryFiles = @(
                        [ordered]@{ path = 'app.exe'; sha256 = (Get-TestSha256 $binaryPath) }
                    )
                    noticeFiles = @(
                        [ordered]@{
                            path = 'release/licenses/test-component/NOTICE.txt'
                            sha256 = (Get-TestSha256 $noticePath)
                        }
                    )
                    sourceArchives = @(
                        [ordered]@{
                            fileName = 'test-component-source.zip'
                            url = "https://github.com/example/test-component/archive/$commit.zip"
                            sha256 = ('a' * 64)
                        }
                    )
                    buildRecipe = 'Compile the pinned source commit for Windows x64.'
                }
            )
        }
        $lockPath = Join-Path $metadata 'lock.json'
        $lock | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $lockPath -Encoding utf8NoBOM

        [pscustomobject]@{
            Root = $root
            Candidate = $candidate
            Metadata = $metadata
            Cache = $cache
            Output = $output
            Lock = $lock
            LockPath = $lockPath
            NoticePath = $noticePath
        }
}

function Save-TestLock {
    param([Parameter(Mandatory)] [object] $Case)
    $Case.Lock | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Case.LockPath -Encoding utf8NoBOM
}

function Invoke-TestTool {
    param([Parameter(Mandatory)] [string] $ScriptPath, [Parameter(Mandatory)] [string[]] $Arguments)
    $output = @(& pwsh -NoLogo -NoProfile -File $ScriptPath @Arguments 2>&1)
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

Describe 'Fail-closed release SPDX generation' {
    It 'rejects a candidate file that has no component assignment' {
        $case = New-LicenseBundleCase 'unknown-component'
        [IO.File]::WriteAllBytes((Join-Path $case.Candidate 'unknown.bin'), [byte[]](9, 8, 7))

        $result = Invoke-TestTool $script:SpdxTool @(
            '-LockPath', $case.LockPath,
            '-SourceRoot', $case.Metadata,
            '-CandidateRoot', $case.Candidate,
            '-OutputDirectory', $case.Output
        )

        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match 'spdx_unknown_candidate_file'
    }

    It 'rejects a component with a missing notice or source archive' {
        $case = New-LicenseBundleCase 'missing-notice-source'
        $case.Lock.components[0].noticeFiles = @()
        $case.Lock.components[0].sourceArchives = @()
        Save-TestLock $case

        $result = Invoke-TestTool $script:SpdxTool @(
            '-LockPath', $case.LockPath,
            '-SourceRoot', $case.Metadata,
            '-CandidateRoot', $case.Candidate,
            '-OutputDirectory', $case.Output
        )

        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match 'spdx_notice_or_source_missing'
    }

    It 'rejects a candidate hash mismatch' {
        $case = New-LicenseBundleCase 'hash-mismatch'
        $case.Lock.components[0].binaryFiles[0].sha256 = '0' * 64
        Save-TestLock $case

        $result = Invoke-TestTool $script:SpdxTool @(
            '-LockPath', $case.LockPath,
            '-SourceRoot', $case.Metadata,
            '-CandidateRoot', $case.Candidate,
            '-OutputDirectory', $case.Output
        )

        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match 'spdx_candidate_hash_mismatch'
    }

    It 'rejects NOASSERTION and NOT_VERIFIED metadata' -TestCases @(
        @{ Field = 'licenseExpression'; Value = 'NOASSERTION'; ErrorId = 'spdx_license_unverified' }
        @{ Field = 'verificationStatus'; Value = 'NOT_VERIFIED'; ErrorId = 'spdx_component_not_verified' }
    ) {
        param($Field, $Value, $ErrorId)
        $case = New-LicenseBundleCase "unverified-$Field"
        $case.Lock.components[0].$Field = $Value
        Save-TestLock $case

        $result = Invoke-TestTool $script:SpdxTool @(
            '-LockPath', $case.LockPath,
            '-SourceRoot', $case.Metadata,
            '-CandidateRoot', $case.Candidate,
            '-OutputDirectory', $case.Output
        )

        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match $ErrorId
    }
}

Describe 'Fail-closed corresponding-source bundle generation' {
    It 'rejects an archive containing a parent traversal entry' {
        $case = New-LicenseBundleCase 'unsafe-source-archive'
        $archivePath = Join-Path $case.Cache 'test-component-source.zip'
        $stream = [IO.File]::Open($archivePath, [IO.FileMode]::CreateNew)
        try {
            $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
            try {
                $entry = $archive.CreateEntry('../escape.txt')
                $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
                try { $writer.Write('escape') } finally { $writer.Dispose() }
            }
            finally { $archive.Dispose() }
        }
        finally { $stream.Dispose() }
        $case.Lock.components[0].sourceArchives[0].sha256 = Get-TestSha256 $archivePath
        Save-TestLock $case

        $result = Invoke-TestTool $script:SourceTool @(
            '-LockPath', $case.LockPath,
            '-SourceRoot', $case.Metadata,
            '-CandidateRoot', $case.Candidate,
            '-CacheDirectory', $case.Cache,
            '-OutputDirectory', $case.Output
        )

        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match 'source_archive_entry_unsafe'
    }
}
