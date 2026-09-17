$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$BuildCandidate = Join-Path $RepositoryRoot 'tools\build-candidate.ps1'
$SevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'

function New-TestDirectory {
    $path = Join-Path ([IO.Path]::GetTempPath()) ('karon-runtime-overlay-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
}

function New-ZipArchive {
    param([string] $Path, [object[]] $Entries)
    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
    try {
        $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            foreach ($entrySpec in $Entries) {
                $entry = $archive.CreateEntry([string]$entrySpec.Name)
                $writer = New-Object IO.StreamWriter($entry.Open(), [Text.UTF8Encoding]::new($false))
                try { $writer.Write([string]$entrySpec.Content) } finally { $writer.Dispose() }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
}

function New-SevenZipArchive {
    param([string] $Path, [string] $WorkingDirectory, [string[]] $RelativePaths)
    Push-Location $WorkingDirectory
    try {
        & $SevenZip a -t7z $Path @RelativePaths | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "7-Zip fixture creation failed with exit code $LASTEXITCODE." }
    }
    finally { Pop-Location }
}

function New-OverlayFixture {
    param(
        [switch] $MissingFfprobe,
        [ValidateSet('None', 'CaseDuplicate', 'FileDirectory')] [string] $FfmpegCollision = 'None'
    )
    $root = New-TestDirectory
    $archives = Join-Path $root 'archives'
    $parent = Join-Path $root 'parent'
    $candidate = Join-Path $root 'candidate'
    $stagingBase = Join-Path $root 'private-staging'
    [IO.Directory]::CreateDirectory($archives) | Out-Null
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    [IO.Directory]::CreateDirectory($candidate) | Out-Null
    [IO.Directory]::CreateDirectory($stagingBase) | Out-Null

    foreach ($name in @('yt-dlp.exe', 'ffmpeg.exe', 'ffprobe.exe', 'deno.exe', '7z.dll', 'ytdlp-interface.json', 'unchanged.bin')) {
        [IO.File]::WriteAllText((Join-Path $parent $name), "parent-$name", [Text.UTF8Encoding]::new($false))
    }
    Copy-Item -Path (Join-Path $parent '*') -Destination $candidate -Recurse

    $ffmpegArchiveName = 'ffmpeg-n9.0.1-30-g9258bacca5-win64-lgpl-9.0.zip'
    $ffmpegRoot = 'ffmpeg-n9.0.1-30-g9258bacca5-win64-lgpl-9.0'
    $ffmpegEntries = @(
        [pscustomobject]@{ Name = $ffmpegRoot + '/bin/ffmpeg.exe'; Content = 'overlay-ffmpeg' }
        [pscustomobject]@{ Name = $ffmpegRoot + '/bin/ffplay.exe'; Content = 'must-not-ship-ffplay' }
        [pscustomobject]@{ Name = $ffmpegRoot + '/README.txt'; Content = 'must-not-ship-readme' }
    )
    if (-not $MissingFfprobe) { $ffmpegEntries += [pscustomobject]@{ Name = $ffmpegRoot + '/bin/ffprobe.exe'; Content = 'overlay-ffprobe' } }
    if ($FfmpegCollision -ceq 'CaseDuplicate') {
        $ffmpegEntries += [pscustomobject]@{ Name = $ffmpegRoot.ToUpperInvariant() + '/BIN/FFMPEG.EXE'; Content = 'case-collision' }
    }
    elseif ($FfmpegCollision -ceq 'FileDirectory') {
        $ffmpegEntries += [pscustomobject]@{ Name = $ffmpegRoot + '/collision'; Content = 'file-collision' }
        $ffmpegEntries += [pscustomobject]@{ Name = $ffmpegRoot + '/collision/child.bin'; Content = 'child-collision' }
    }
    $ffmpegArchive = Join-Path $archives $ffmpegArchiveName
    New-ZipArchive -Path $ffmpegArchive -Entries $ffmpegEntries

    $sevenSource = Join-Path $root 'seven-source'
    [IO.Directory]::CreateDirectory((Join-Path $sevenSource 'x64')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $sevenSource 'x64\7z.dll'), 'overlay-7z', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $sevenSource 'x64\Rar.dll'), 'must-not-ship-rar', [Text.UTF8Encoding]::new($false))
    $sevenArchiveName = '7z2601-x64-no-rar.7z'
    $sevenArchive = Join-Path $archives $sevenArchiveName
    New-SevenZipArchive -Path $sevenArchive -WorkingDirectory $sevenSource -RelativePaths @('x64\7z.dll', 'x64\Rar.dll')

    $definitions = @(
        [pscustomobject]@{
            id = 'ffmpeg'
            archiveName = $ffmpegArchiveName
            archiveSha256 = (Get-FileHash -LiteralPath $ffmpegArchive -Algorithm SHA256).Hash
            archiveFormat = 'zip'
            expectedVersion = 'n9.0.1-30-g9258bacca5'
            files = @(
                [pscustomobject]@{ archivePath = $ffmpegRoot + '/bin/ffmpeg.exe'; destination = 'ffmpeg.exe'; identity = 'ffmpeg' }
                [pscustomobject]@{ archivePath = $ffmpegRoot + '/bin/ffprobe.exe'; destination = 'ffprobe.exe'; identity = 'ffprobe' }
            )
        }
        [pscustomobject]@{
            id = 'sevenZip'
            archiveName = $sevenArchiveName
            archiveSha256 = (Get-FileHash -LiteralPath $sevenArchive -Algorithm SHA256).Hash
            archiveFormat = '7z'
            expectedVersion = '26.01'
            files = @(
                [pscustomobject]@{ archivePath = 'x64/7z.dll'; destination = '7z.dll'; identity = 'sevenZip' }
            )
        }
    )
    return [pscustomobject]@{
        Root = $root
        Archives = $archives
        Parent = $parent
        Candidate = $candidate
        StagingBase = $stagingBase
        FfmpegArchive = $ffmpegArchive
        SevenZipArchive = $sevenArchive
        Definitions = $definitions
    }
}

function Assert-ThrowsMessage {
    param([scriptblock] $Action, [string] $Expected)
    $message = $null
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    if ($message -cne $Expected) { throw "Expected exception '$Expected', got '$message'." }
}

function Read-TestOverlayIdentity {
    param([string] $Identity, [string] $Path)
    switch ($Identity) {
        'ffmpeg' { return "ffmpeg version n9.0.1-30-g9258bacca5 Copyright fixture`nconfiguration: fixture" }
        'ffprobe' { return "ffprobe version n9.0.1-30-g9258bacca5 Copyright fixture`nconfiguration: fixture" }
        'sevenZip' { return '26.01' }
        default { throw "Unexpected fixture identity: $Identity" }
    }
}

Describe 'Reviewed runtime overlay contract' {
    BeforeAll {
        if (-not (Test-Path -LiteralPath $SevenZip -PathType Leaf)) { throw 'The focused runtime overlay tests require Program Files 7-Zip.' }
        . $BuildCandidate
    }

    It 'rejects an archive whose SHA-256 differs from reviewed provenance' {
        $fixture = New-OverlayFixture
        try {
            $fixture.Definitions[0].archiveSha256 = '0' * 64
            Assert-ThrowsMessage {
                Install-ReviewedRuntimeOverlays -CandidateRoot $fixture.Candidate -RuntimeArchiveDirectory $fixture.Archives -OverlayDefinitions $fixture.Definitions -SevenZipPath $SevenZip -IdentityReader ${function:Read-TestOverlayIdentity}
            } 'runtime_overlay_sha256_mismatch'
        }
        finally { Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects an unsafe selected archive path' {
        $fixture = New-OverlayFixture
        try {
            $fixture.Definitions[0].files[0].archivePath = '../ffmpeg.exe'
            Assert-ThrowsMessage {
                Install-ReviewedRuntimeOverlays -CandidateRoot $fixture.Candidate -RuntimeArchiveDirectory $fixture.Archives -OverlayDefinitions $fixture.Definitions -SevenZipPath $SevenZip -IdentityReader ${function:Read-TestOverlayIdentity}
            } 'runtime_overlay_manifest_invalid'
        }
        finally { Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a reviewed archive missing an expected inner binary' {
        $fixture = New-OverlayFixture -MissingFfprobe
        try {
            Assert-ThrowsMessage {
                Install-ReviewedRuntimeOverlays -CandidateRoot $fixture.Candidate -RuntimeArchiveDirectory $fixture.Archives -OverlayDefinitions $fixture.Definitions -SevenZipPath $SevenZip -IdentityReader ${function:Read-TestOverlayIdentity}
            } 'runtime_overlay_layout_invalid'
        }
        finally { Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'changes only ffmpeg.exe ffprobe.exe and 7z.dll relative to the parent runtime' {
        $fixture = New-OverlayFixture
        try {
            Install-ReviewedRuntimeOverlays -CandidateRoot $fixture.Candidate -RuntimeArchiveDirectory $fixture.Archives -OverlayDefinitions $fixture.Definitions -SevenZipPath $SevenZip -IdentityReader ${function:Read-TestOverlayIdentity}
            $changed = @(Get-ChildItem -LiteralPath $fixture.Parent -File | Where-Object {
                (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath (Join-Path $fixture.Candidate $_.Name) -Algorithm SHA256).Hash
            } | ForEach-Object Name | Sort-Object)
            @($changed) | Should Be @('7z.dll', 'ffmpeg.exe', 'ffprobe.exe')
            Test-Path -LiteralPath (Join-Path $fixture.Candidate 'Rar.dll') | Should Be $false
            Test-Path -LiteralPath (Join-Path $fixture.Candidate 'ffplay.exe') | Should Be $false
        }
        finally { Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'uses only a private archive copy after the external source is replaced' {
        $fixture = New-OverlayFixture
        try {
            $copyDestinations = New-Object Collections.Generic.List[string]
            $ffmpegArchiveName = Split-Path -Leaf $fixture.FfmpegArchive
            $archiveCopier = {
                param([string] $Source, [string] $Destination)
                Copy-Item -LiteralPath $Source -Destination $Destination
                $copyDestinations.Add($Destination)
                if ((Split-Path -Leaf $Source) -ceq $ffmpegArchiveName) {
                    [IO.File]::WriteAllText($Source, 'source-replaced-after-private-copy', [Text.UTF8Encoding]::new($false))
                }
            }.GetNewClosure()
            Install-ReviewedRuntimeOverlays -CandidateRoot $fixture.Candidate -RuntimeArchiveDirectory $fixture.Archives -OverlayDefinitions $fixture.Definitions -SevenZipPath $SevenZip -IdentityReader ${function:Read-TestOverlayIdentity} -StagingBase $fixture.StagingBase -ArchiveCopier $archiveCopier
            [IO.File]::ReadAllText((Join-Path $fixture.Candidate 'ffmpeg.exe')) | Should Be 'overlay-ffmpeg'
            $copyDestinations.Count | Should Be 2
            @($copyDestinations | Where-Object { -not (Test-PathContained -Root $fixture.StagingBase -Path $_) }).Count | Should Be 0
        }
        finally { Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a candidate destination changed by the overlay copy operation' {
        $fixture = New-OverlayFixture
        try {
            $overlayCopier = {
                param([string] $Source, [string] $Destination)
                Copy-Item -LiteralPath $Source -Destination $Destination -Force
                if ((Split-Path -Leaf $Destination) -ceq 'ffmpeg.exe') {
                    [IO.File]::WriteAllText($Destination, 'destination-tamper', [Text.UTF8Encoding]::new($false))
                }
            }
            Assert-ThrowsMessage {
                Install-ReviewedRuntimeOverlays -CandidateRoot $fixture.Candidate -RuntimeArchiveDirectory $fixture.Archives -OverlayDefinitions $fixture.Definitions -SevenZipPath $SevenZip -IdentityReader ${function:Read-TestOverlayIdentity} -OverlayCopier $overlayCopier
            } 'runtime_overlay_destination_mismatch'
        }
        finally { Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects case-insensitive duplicate normalized archive entries' {
        $fixture = New-OverlayFixture -FfmpegCollision CaseDuplicate
        try {
            Assert-ThrowsMessage {
                Install-ReviewedRuntimeOverlays -CandidateRoot $fixture.Candidate -RuntimeArchiveDirectory $fixture.Archives -OverlayDefinitions $fixture.Definitions -SevenZipPath $SevenZip -IdentityReader ${function:Read-TestOverlayIdentity}
            } 'runtime_overlay_layout_invalid'
        }
        finally { Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects an archive file and directory prefix collision' {
        $fixture = New-OverlayFixture -FfmpegCollision FileDirectory
        try {
            Assert-ThrowsMessage {
                Install-ReviewedRuntimeOverlays -CandidateRoot $fixture.Candidate -RuntimeArchiveDirectory $fixture.Archives -OverlayDefinitions $fixture.Definitions -SevenZipPath $SevenZip -IdentityReader ${function:Read-TestOverlayIdentity}
            } 'runtime_overlay_layout_invalid'
        }
        finally { Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'accepts only anchored product-specific first-line identities' {
        $ffmpeg = Get-RuntimeOverlayIdentity -Identity 'ffmpeg' -Path 'fixture-ffmpeg.exe' -ExpectedVersion 'n9.0.1-30-g9258bacca5' -IdentityReader {
            "ffmpeg version n9.0.1-30-g9258bacca5 Copyright fixture`nconfiguration: fixture"
        }
        $ffprobe = Get-RuntimeOverlayIdentity -Identity 'ffprobe' -Path 'fixture-ffprobe.exe' -ExpectedVersion 'n9.0.1-30-g9258bacca5' -IdentityReader {
            "ffprobe version n9.0.1-30-g9258bacca5 Copyright fixture`nconfiguration: fixture"
        }
        $datedFfmpeg = Get-RuntimeOverlayIdentity -Identity 'ffmpeg' -Path 'fixture-ffmpeg.exe' -ExpectedVersion 'n9.0.1-30-g9258bacca5' -IdentityReader {
            "ffmpeg version n9.0.1-30-g9258bacca5-20260915 Copyright fixture`nconfiguration: fixture"
        }
        $datedFfprobe = Get-RuntimeOverlayIdentity -Identity 'ffprobe' -Path 'fixture-ffprobe.exe' -ExpectedVersion 'n9.0.1-30-g9258bacca5' -IdentityReader {
            "ffprobe version n9.0.1-30-g9258bacca5-20260915 Copyright fixture`nconfiguration: fixture"
        }
        $sevenZip = Get-RuntimeOverlayIdentity -Identity 'sevenZip' -Path 'fixture-7z.dll' -ExpectedVersion '26.01' -IdentityReader { '26.01' }
        $ffmpeg | Should Be 'ffmpeg version n9.0.1-30-g9258bacca5 Copyright fixture'
        $ffprobe | Should Be 'ffprobe version n9.0.1-30-g9258bacca5 Copyright fixture'
        $datedFfmpeg | Should Be 'ffmpeg version n9.0.1-30-g9258bacca5-20260915 Copyright fixture'
        $datedFfprobe | Should Be 'ffprobe version n9.0.1-30-g9258bacca5-20260915 Copyright fixture'
        $sevenZip | Should Be '26.01'
    }

    It 'rejects substring wrong-product second-line and inexact version identities' {
        $cases = @(
            [pscustomobject]@{ Identity = 'ffmpeg'; Version = 'n9.0.1-30-g9258bacca5'; Output = 'wrapper ffmpeg version n9.0.1-30-g9258bacca5' }
            [pscustomobject]@{ Identity = 'ffmpeg'; Version = 'n9.0.1-30-g9258bacca5'; Output = 'ffprobe version n9.0.1-30-g9258bacca5' }
            [pscustomobject]@{ Identity = 'ffmpeg'; Version = 'n9.0.1-30-g9258bacca5'; Output = "banner`nffmpeg version n9.0.1-30-g9258bacca5" }
            [pscustomobject]@{ Identity = 'ffmpeg'; Version = 'n9.0.1-30-g9258bacca5'; Output = 'ffmpeg version n9.0.1-30-g9258bacca5evil' }
            [pscustomobject]@{ Identity = 'ffprobe'; Version = 'n9.0.1-30-g9258bacca5'; Output = 'ffmpeg version n9.0.1-30-g9258bacca5' }
            [pscustomobject]@{ Identity = 'sevenZip'; Version = '26.01'; Output = '26.01.0.0' }
            [pscustomobject]@{ Identity = 'sevenZip'; Version = '26.01'; Output = ' 26.01' }
        )
        foreach ($case in $cases) {
            $observed = $case.Output
            $reader = { $observed }.GetNewClosure()
            Assert-ThrowsMessage {
                Get-RuntimeOverlayIdentity -Identity $case.Identity -Path 'fixture' -ExpectedVersion $case.Version -IdentityReader $reader
            } 'runtime_overlay_version_mismatch'
        }
    }

    It 'rejects swapped ffmpeg and ffprobe destination mappings' {
        $fixture = New-OverlayFixture
        try {
            $fixture.Definitions[0].files[0].destination = 'ffprobe.exe'
            $fixture.Definitions[0].files[1].destination = 'ffmpeg.exe'
            Assert-ThrowsMessage {
                Install-ReviewedRuntimeOverlays -CandidateRoot $fixture.Candidate -RuntimeArchiveDirectory $fixture.Archives -OverlayDefinitions $fixture.Definitions -SevenZipPath $SevenZip -IdentityReader ${function:Read-TestOverlayIdentity}
            } 'runtime_overlay_manifest_invalid'
        }
        finally { Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'loads the production request and maps runtime archives through installation attestation' {
        $fixture = New-OverlayFixture
        try {
            $definitions = Get-ReleaseRuntimeOverlayDefinitions -SourceRoot $RepositoryRoot
            ($definitions | Where-Object id -ceq 'ffmpeg').archiveSha256 = $fixture.Definitions[0].archiveSha256
            ($definitions | Where-Object id -ceq 'sevenZip').archiveSha256 = $fixture.Definitions[1].archiveSha256
            $attestation = @(Install-ReviewedRuntimeOverlays -CandidateRoot $fixture.Candidate -RuntimeArchiveDirectory $fixture.Archives -OverlayDefinitions $definitions -SevenZipPath $SevenZip -IdentityReader ${function:Read-TestOverlayIdentity})
            $mapping = @($attestation.files | ForEach-Object { "$($_.sourceArchivePath)|$($_.destination)|$($_.productIdentity)" } | Sort-Object)
            ($mapping -join ',') | Should Be (
                'ffmpeg-n9.0.1-30-g9258bacca5-win64-lgpl-9.0/bin/ffmpeg.exe|ffmpeg.exe|ffmpeg,' +
                'ffmpeg-n9.0.1-30-g9258bacca5-win64-lgpl-9.0/bin/ffprobe.exe|ffprobe.exe|ffprobe,' +
                'x64/7z.dll|7z.dll|sevenZip'
            )
        }
        finally { Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects non-overlay candidate bytes that differ from the verified parent snapshot' {
        $fixture = New-OverlayFixture
        try {
            $parentFiles = Get-RuntimeFileAttestation -Root $fixture.Parent -Names @('yt-dlp.exe', 'deno.exe')
            [IO.File]::WriteAllText((Join-Path $fixture.Candidate 'deno.exe'), 'mutated-deno', [Text.UTF8Encoding]::new($false))
            Assert-ThrowsMessage {
                Assert-CandidateRuntimePreserved -CandidateRoot $fixture.Candidate -ParentFiles $parentFiles
            } 'runtime_parent_copy_mismatch'
        }
        finally { Remove-Item -LiteralPath $fixture.Root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects an extracted filesystem reparse object' {
        $fixtureRoot = New-TestDirectory
        $target = Join-Path $fixtureRoot 'target'
        $link = Join-Path $fixtureRoot 'link'
        try {
            [IO.Directory]::CreateDirectory($target) | Out-Null
            New-Item -ItemType Junction -Path $link -Target $target | Out-Null
            Assert-ThrowsMessage { Assert-NoRuntimeOverlayReparsePoints -Root $fixtureRoot } 'runtime_overlay_layout_invalid'
        }
        finally {
            if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue }
            Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
