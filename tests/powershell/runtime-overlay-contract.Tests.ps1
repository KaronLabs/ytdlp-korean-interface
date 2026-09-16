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
    param([string] $Path, [hashtable] $Entries)
    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
    try {
        $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            foreach ($name in $Entries.Keys) {
                $entry = $archive.CreateEntry($name)
                $writer = New-Object IO.StreamWriter($entry.Open(), [Text.UTF8Encoding]::new($false))
                try { $writer.Write([string]$Entries[$name]) } finally { $writer.Dispose() }
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
    param([switch] $MissingFfprobe)
    $root = New-TestDirectory
    $archives = Join-Path $root 'archives'
    $parent = Join-Path $root 'parent'
    $candidate = Join-Path $root 'candidate'
    [IO.Directory]::CreateDirectory($archives) | Out-Null
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    [IO.Directory]::CreateDirectory($candidate) | Out-Null

    foreach ($name in @('yt-dlp.exe', 'ffmpeg.exe', 'ffprobe.exe', 'deno.exe', '7z.dll', 'ytdlp-interface.json', 'unchanged.bin')) {
        [IO.File]::WriteAllText((Join-Path $parent $name), "parent-$name", [Text.UTF8Encoding]::new($false))
    }
    Copy-Item -Path (Join-Path $parent '*') -Destination $candidate -Recurse

    $ffmpegArchiveName = 'ffmpeg-n9.0.1-30-g9258bacca5-win64-lgpl-9.0.zip'
    $ffmpegRoot = 'ffmpeg-n9.0.1-30-g9258bacca5-win64-lgpl-9.0'
    $ffmpegEntries = @{
        ($ffmpegRoot + '/bin/ffmpeg.exe') = 'overlay-ffmpeg'
        ($ffmpegRoot + '/bin/ffplay.exe') = 'must-not-ship-ffplay'
        ($ffmpegRoot + '/README.txt') = 'must-not-ship-readme'
    }
    if (-not $MissingFfprobe) { $ffmpegEntries[$ffmpegRoot + '/bin/ffprobe.exe'] = 'overlay-ffprobe' }
    $ffmpegArchive = Join-Path $archives $ffmpegArchiveName
    New-ZipArchive -Path $ffmpegArchive -Entries $ffmpegEntries

    $sevenSource = Join-Path $root 'seven-source'
    [IO.Directory]::CreateDirectory((Join-Path $sevenSource 'x64')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $sevenSource 'x64\7z.dll'), 'overlay-7z', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $sevenSource 'x64\Rar.dll'), 'must-not-ship-rar', [Text.UTF8Encoding]::new($false))
    $sevenArchiveName = '7z2601-extra.7z'
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
    return [pscustomobject]@{ Root = $root; Archives = $archives; Parent = $parent; Candidate = $candidate; Definitions = $definitions }
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
        'ffmpeg' { return 'ffmpeg version n9.0.1-30-g9258bacca5' }
        'ffprobe' { return 'ffprobe version n9.0.1-30-g9258bacca5' }
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
}
