$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$BuildTool = Join-Path $RepositoryRoot 'tools\build-sevenzip-no-rar.ps1'
$DefinitionFile = Join-Path $RepositoryRoot 'release\runtime\v2.19.1-karon.2\sevenzip-no-rar.json'
$SevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'

if (Test-Path -LiteralPath $BuildTool -PathType Leaf) {
    . $BuildTool
}

function New-TestDirectory {
    $path = Join-Path ([IO.Path]::GetTempPath()) ('karon-sevenzip-no-rar-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
}

function New-ZipFixture {
    param([string] $Path, [string[]] $EntryNames)

    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
    try {
        $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            foreach ($name in $EntryNames) {
                $entry = $archive.CreateEntry($name)
                $writer = New-Object IO.StreamWriter($entry.Open(), [Text.UTF8Encoding]::new($false))
                try { $writer.Write('fixture') } finally { $writer.Dispose() }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
}

function New-SevenZipFixture {
    param([string] $Path, [string] $Root, [string[]] $Entries)

    Push-Location $Root
    try {
        & $SevenZip a -t7z $Path @Entries | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "7-Zip fixture creation failed with exit code $LASTEXITCODE." }
    }
    finally { Pop-Location }
}

Describe '7-Zip 26.01 no-RAR build contract' {
    It 'loads the immutable upstream source and complete exclusion definition' {
        Get-Command Get-SevenZipNoRarDefinition -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        $definition = Get-SevenZipNoRarDefinition -Path $DefinitionFile
        $definition.source.repository | Should Be 'ip7z/7zip'
        $definition.source.commit | Should Be '8c63d71ff886bda90c86db28466287f977374237'
        $definition.source.archiveSha256 | Should Be '01589AEDA50512955E66D360C6534B961EC95C51111A76E2FA2976A8DAA55271'
        $definition.source.arcMakSha256 | Should Be '21BDEC7EF04A92DBB7A19E71146929A85A851A6E7A4D992AC9529E963D9BF381'
        @($definition.excludedObjects).Count | Should Be 11
        (@($definition.excludedObjects | Sort-Object) -join ',') | Should Be 'Rar1Decoder.obj,Rar20Crypto.obj,Rar2Decoder.obj,Rar3Decoder.obj,Rar3Vm.obj,Rar5Aes.obj,Rar5Decoder.obj,Rar5Handler.obj,RarAes.obj,RarCodecsRegister.obj,RarHandler.obj'
    }

    It 'accepts only the reviewed source bytes and rejects archive traversal' {
        $root = New-TestDirectory
        try {
            $safe = Join-Path $root 'safe.zip'
            New-ZipFixture -Path $safe -EntryNames @('7zip-fixed/README.md')
            $safeHash = (Get-FileHash -LiteralPath $safe -Algorithm SHA256).Hash
            (Assert-SevenZipSourceArchive -Path $safe -ExpectedSha256 $safeHash).RootName | Should Be '7zip-fixed'
            { Assert-SevenZipSourceArchive -Path $safe -ExpectedSha256 ('0' * 64) } | Should Throw 'sevenzip_source_sha256_mismatch'

            $unsafe = Join-Path $root 'unsafe.zip'
            New-ZipFixture -Path $unsafe -EntryNames @('7zip-fixed/../escape.txt')
            $unsafeHash = (Get-FileHash -LiteralPath $unsafe -Algorithm SHA256).Hash
            { Assert-SevenZipSourceArchive -Path $unsafe -ExpectedSha256 $unsafeHash } | Should Throw 'sevenzip_source_archive_unsafe'
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'removes every reviewed RAR object while preserving 7z and ZIP objects' {
        $definition = Get-SevenZipNoRarDefinition -Path $DefinitionFile
        $lines = @('7Z_OBJS = \', '  $O\7zHandler.obj \', 'ZIP_OBJS = \', '  $O\ZipHandler.obj \', 'RAR_OBJS = \')
        $lines += @($definition.excludedObjects | ForEach-Object { '  $O\' + $_ + ' \' })
        $patched = Get-SevenZipNoRarArcMak -Content (($lines -join "`r`n") + "`r`n") -ExcludedObjects @($definition.excludedObjects)
        $patched | Should Match '\$O\\7zHandler\.obj'
        $patched | Should Match '\$O\\ZipHandler\.obj'
        $patched | Should Not Match '(?i)rar'
    }

    It 'fails when the source exclusion contract is incomplete' {
        $definition = Get-SevenZipNoRarDefinition -Path $DefinitionFile
        $incomplete = @($definition.excludedObjects | Where-Object { $_ -cne 'Rar5Handler.obj' })
        $content = 'RAR_OBJS = \' + "`r`n" + (($incomplete | ForEach-Object { '  $O\' + $_ + ' \' }) -join "`r`n")
        { Get-SevenZipNoRarArcMak -Content $content -ExcludedObjects @($definition.excludedObjects) } | Should Throw 'sevenzip_rar_exclusion_contract_mismatch'
    }

    It 'parses the linker build map and rejects any RAR object name' {
        $root = New-TestDirectory
        try {
            $safeLog = Join-Path $root 'safe.log'
            [IO.File]::WriteAllText($safeLog, 'link -out:x64\7z.dll x64\7zHandler.obj x64\ZipHandler.obj', [Text.UTF8Encoding]::new($false))
            $safe = @(Get-SevenZipLinkObjectNames -BuildLogPath $safeLog)
            ($safe -join ',') | Should Be '7zHandler.obj,ZipHandler.obj'
            { Assert-SevenZipNoRarBuildMap -ObjectNames $safe } | Should Not Throw

            $unsafe = @($safe + 'Rar5Handler.obj')
            { Assert-SevenZipNoRarBuildMap -ObjectNames $unsafe } | Should Throw 'sevenzip_rar_object_detected'
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'accepts only the reviewed runtime archive layout and rejects RAR members' {
        Test-Path -LiteralPath $SevenZip -PathType Leaf | Should Be $true
        $root = New-TestDirectory
        try {
            $layout = Join-Path $root 'layout'
            [IO.Directory]::CreateDirectory((Join-Path $layout 'x64')) | Out-Null
            [IO.Directory]::CreateDirectory((Join-Path $layout 'provenance')) | Out-Null
            [IO.File]::WriteAllText((Join-Path $layout 'x64\7z.dll'), 'fixture', [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText((Join-Path $layout 'COPYING.LGPL-2.1.txt'), 'LGPL fixture', [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText((Join-Path $layout 'BSD-NOTICES.txt'), 'BSD fixture', [Text.UTF8Encoding]::new($false))
            foreach ($name in @('build-provenance.json', 'build-map.json', 'build-commands.log')) {
                [IO.File]::WriteAllText((Join-Path $layout ('provenance\' + $name)), '{}', [Text.UTF8Encoding]::new($false))
            }
            $expected = @('BSD-NOTICES.txt', 'COPYING.LGPL-2.1.txt', 'provenance/build-commands.log', 'provenance/build-map.json', 'provenance/build-provenance.json', 'x64/7z.dll')
            $safeArchive = Join-Path $root 'safe.7z'
            New-SevenZipFixture -Path $safeArchive -Root $layout -Entries @('BSD-NOTICES.txt', 'COPYING.LGPL-2.1.txt', 'provenance', 'x64')
            { Assert-SevenZipRuntimeArchive -Path $safeArchive -SevenZipPath $SevenZip -ExpectedEntries $expected } | Should Not Throw

            [IO.File]::WriteAllText((Join-Path $layout 'x64\Rar.dll'), 'forbidden', [Text.UTF8Encoding]::new($false))
            $unsafeArchive = Join-Path $root 'unsafe.7z'
            New-SevenZipFixture -Path $unsafeArchive -Root $layout -Entries @('BSD-NOTICES.txt', 'COPYING.LGPL-2.1.txt', 'provenance', 'x64')
            { Assert-SevenZipRuntimeArchive -Path $unsafeArchive -SevenZipPath $SevenZip -ExpectedEntries $expected } | Should Throw 'sevenzip_runtime_archive_layout_invalid'
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Built 7-Zip 26.01 no-RAR runtime' {
    $ArtifactPath = [string]$env:KARON_SEVENZIP_NO_RAR_ARTIFACT
    $HostPath = [string]$env:KARON_SEVENZIP_NO_RAR_HOST
    $SkipRuntime = [string]::IsNullOrWhiteSpace($ArtifactPath) -or [string]::IsNullOrWhiteSpace($HostPath)

    It 'enumerates no RAR handlers and extracts ZIP and 7z payloads' -Skip:$SkipRuntime {
        $result = Test-SevenZipNoRarRuntime -RuntimeArchivePath $ArtifactPath -HostPath $HostPath
        $result.InfoExitCode | Should Be 0
        $result.ZipExitCode | Should Be 0
        $result.SevenZipExitCode | Should Be 0
        $result.InfoOutput | Should Match '(?im)^\s*0\s+.*\s7z\s+7z\s'
        $result.InfoOutput | Should Match '(?im)^\s*0\s+.*\szip\s+zip\s'
        $result.InfoOutput | Should Not Match '(?im)^\s*0\s+.*\sRar(?:1|2|3|5)?(?:\s|$)'
        $result.ZipPayload | Should Be 'karon-zip-payload'
        $result.SevenZipPayload | Should Be 'karon-7z-payload'
    }
}
