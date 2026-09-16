Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:ArchivePath = Join-Path $script:RepositoryRoot 'ytdlp-interface dependencies.7z'
$script:ExpectedArchiveSha256 = '41004108B9FC41454A97B97850C4E41D537F226A27255E8213ABD14BFFFFEBD3'
$script:Bit7zCommit = 'c81c6c1cbf44e148cd4b06f4bb69d7ea1e299742'
$script:Bit7zSourceUrl = 'https://github.com/rikyoz/bit7z/archive/c81c6c1cbf44e148cd4b06f4bb69d7ea1e299742.zip'
$script:Bit7zSourceSha256 = '6AF52B2E1B9895E8F1193728880206326161940E7A961E3162EC39752DBB3379'
$programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$script:SevenZip = @(
    (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
    (Join-Path $programFilesX86 '7-Zip\7z.exe')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1

. (Join-Path $script:RepositoryRoot 'tools\build-candidate.ps1')
Import-Module (Join-Path $script:RepositoryRoot 'tools\candidate-manifest.psm1') -Force

$script:ExpectedRemovedPaths = @(
    'lib/7zSDK/CPP/7zip/Archive/Rar',
    'lib/7zSDK/CPP/7zip/Archive/Icons/rar.ico',
    'lib/7zSDK/CPP/7zip/Archive/Rar/Rar5Handler.cpp',
    'lib/7zSDK/CPP/7zip/Archive/Rar/Rar5Handler.h',
    'lib/7zSDK/CPP/7zip/Archive/Rar/RarHandler.cpp',
    'lib/7zSDK/CPP/7zip/Archive/Rar/RarHandler.h',
    'lib/7zSDK/CPP/7zip/Archive/Rar/RarHeader.h',
    'lib/7zSDK/CPP/7zip/Archive/Rar/RarItem.h',
    'lib/7zSDK/CPP/7zip/Archive/Rar/RarVol.h',
    'lib/7zSDK/CPP/7zip/Archive/Rar/StdAfx.cpp',
    'lib/7zSDK/CPP/7zip/Archive/Rar/StdAfx.h',
    'lib/7zSDK/CPP/7zip/Compress/Rar1Decoder.cpp',
    'lib/7zSDK/CPP/7zip/Compress/Rar1Decoder.h',
    'lib/7zSDK/CPP/7zip/Compress/Rar2Decoder.cpp',
    'lib/7zSDK/CPP/7zip/Compress/Rar2Decoder.h',
    'lib/7zSDK/CPP/7zip/Compress/Rar3Decoder.cpp',
    'lib/7zSDK/CPP/7zip/Compress/Rar3Decoder.h',
    'lib/7zSDK/CPP/7zip/Compress/Rar3Vm.cpp',
    'lib/7zSDK/CPP/7zip/Compress/Rar3Vm.h',
    'lib/7zSDK/CPP/7zip/Compress/Rar5Decoder.cpp',
    'lib/7zSDK/CPP/7zip/Compress/Rar5Decoder.h',
    'lib/7zSDK/CPP/7zip/Compress/RarCodecsRegister.cpp',
    'lib/7zSDK/CPP/7zip/Crypto/Rar20Crypto.cpp',
    'lib/7zSDK/CPP/7zip/Crypto/Rar20Crypto.h',
    'lib/7zSDK/CPP/7zip/Crypto/Rar5Aes.cpp',
    'lib/7zSDK/CPP/7zip/Crypto/Rar5Aes.h',
    'lib/7zSDK/CPP/7zip/Crypto/RarAes.cpp',
    'lib/7zSDK/CPP/7zip/Crypto/RarAes.h',
    'lib/7zSDK/DOC/unRarLicense.txt'
)

function New-TestBuildInputs {
    param([Parameter(Mandatory = $true)] [string] $Root)
    $source = Join-Path $Root 'source'
    $userRoot = 'C:\hermetic-user'
    [IO.Directory]::CreateDirectory($source) | Out-Null
    $common = @(
        '/p:Configuration=Release',
        '/p:Platform=x64',
        '/p:PlatformToolset=v143',
        '/p:ImportDirectoryBuildProps=false',
        '/p:ImportDirectoryBuildTargets=false',
        ('/p:UserRootDir=' + $userRoot + '\'),
        '/p:VCToolsVersion=14.40.1',
        '/p:WindowsTargetPlatformVersion=10.0.1'
    )
    $globals = '-DCMAKE_VS_GLOBALS=ImportDirectoryBuildProps=false;ImportDirectoryBuildTargets=false;UserRootDir=' + $userRoot + '\;VCToolsVersion=14.40.1;WindowsTargetPlatformVersion=10.0.1'
    $plan = @(Get-ReleaseX64DependencyPlan -SourceRoot $source -MsBuildPath 'C:\Tools\MSBuild.exe' -CmakePath 'C:\Tools\cmake.exe' -CommonMsBuildArguments $common -CmakeVsGlobalsArgument $globals)
    $source = Split-Path -Parent $plan[0].SourceDirectory
    $context = [pscustomobject]@{
        UserRootDirectory = $userRoot
        AttestedWorkingDirectory = '<source>'
        EffectiveProperties = [ordered]@{
            Configuration = 'Release'; Platform = 'x64'; PlatformToolset = 'v143'
            ImportDirectoryBuildProps = 'false'; ImportDirectoryBuildTargets = 'false'; UserRootDir = '<hermetic-user-root>'
            VCToolsVersion = '14.40.1'; WindowsTargetPlatformVersion = '10.0.1'
        }
        AttestedEnvironment = [ordered]@{ PreferredToolArchitecture = 'x64' }
    }
    $productArguments = @((Join-Path $source 'ytdlp-interface\ytdlp-interface.sln'), '/m', '/t:Build') + $common
    return [pscustomobject]@{ Source = $source; Plan = $plan; Context = $context; ProductArguments = $productArguments }
}

function New-TestAttestation {
    param([Parameter(Mandatory = $true)] [object] $Inputs)
    $commands = @(Get-BuildCommandAttestation -SourceRoot $Inputs.Source -DependencyPlan $Inputs.Plan -ProductExecutable 'C:\Tools\MSBuild.exe' -ProductArguments $Inputs.ProductArguments -BuildContext $Inputs.Context)
    return [ordered]@{
        source = [ordered]@{ commit = ('1' * 40); dirty = $false; treeSha256 = ('2' * 64); trackedFileCount = 1 }
        dependencyArchive = [ordered]@{
            name = 'ytdlp-interface dependencies.7z'; sha256 = $script:ExpectedArchiveSha256
            bit7zSource = [ordered]@{
                version = '4.1.0'; commit = $script:Bit7zCommit; license = 'MPL-2.0'
                sourceUrl = $script:Bit7zSourceUrl; sourceSha256 = $script:Bit7zSourceSha256
                sourceTreeStatus = 'MPL-2.0-permitted modified subset'
                provenancePath = 'bit7z/KARON_DEPENDENCY_PROVENANCE.json'
            }
        }
        linkerInputs = @(
            [ordered]@{ name = 'bit7z'; library = 'bit7z.lib'; sha256 = ('4' * 64); length = 1 },
            [ordered]@{ name = 'Nana'; library = 'nana_v143_Release_x64.lib'; sha256 = ('B' * 64); length = 1 },
            [ordered]@{ name = 'libpng'; library = 'libpng.lib'; sha256 = ('C' * 64); length = 1 },
            [ordered]@{ name = 'libjpeg-turbo'; library = 'turbojpeg-static.lib'; sha256 = ('D' * 64); length = 1 }
        )
        toolchain = @(
            [ordered]@{ name = 'msbuild'; sha256 = ('5' * 64); version = '1' },
            [ordered]@{ name = 'cmake'; sha256 = ('6' * 64); version = '1' },
            [ordered]@{ name = 'cl'; sha256 = ('7' * 64); version = '1' },
            [ordered]@{ name = 'link'; sha256 = ('8' * 64); version = '1' },
            [ordered]@{ name = 'rc'; sha256 = ('9' * 64); version = '1' },
            [ordered]@{ name = 'windows-sdk'; sha256 = ('A' * 64); version = '10.0.1' }
        )
        commands = $commands
    }
}

Describe 'bit7z v4 dependency and candidate contracts' {
    BeforeAll {
        if ([string]::IsNullOrWhiteSpace($script:SevenZip)) { throw '7z.exe is required.' }
        $manifest = Get-DependencyArchiveManifest -SourceRoot $script:RepositoryRoot
        $script:DependencyManifest = $manifest
        $listing = & $script:SevenZip l -slt $script:ArchivePath
        if ($LASTEXITCODE -ne 0) { throw 'Dependency archive listing failed.' }
        $script:ArchiveEntries = @(Get-ArchiveEntriesFromListing -Listing $listing)
        $script:ExtractionRoot = Join-Path $TestDrive 'dependency-extraction'
        & $script:SevenZip x $script:ArchivePath ('-o' + $script:ExtractionRoot) 'bit7z\*' -y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Dependency archive extraction failed.' }
        $script:Bit7zRoot = Join-Path $script:ExtractionRoot 'bit7z'
        $script:Provenance = Get-Content -LiteralPath (Join-Path $script:Bit7zRoot 'KARON_DEPENDENCY_PROVENANCE.json') -Raw | ConvertFrom-Json
    }

    It 'uses the production manifest and archive safety functions for every entry' {
        $script:DependencyManifest.name | Should Be 'ytdlp-interface dependencies.7z'
        ([string]$script:DependencyManifest.sha256).ToUpperInvariant() | Should Be $script:ExpectedArchiveSha256
        (Get-FileHash -LiteralPath $script:ArchivePath -Algorithm SHA256).Hash | Should Be $script:ExpectedArchiveSha256
        $script:ArchiveEntries.Count | Should BeGreaterThan 0
        foreach ($entry in $script:ArchiveEntries) {
            (Test-ArchiveEntrySafe -Entry $entry -ExpectedRoots @($script:DependencyManifest.roots)) | Should Be $true
        }
        (Test-ArchiveEntrySafe -Entry '..\escape' -ExpectedRoots @('bit7z')) | Should Be $false
    }

    It 'contains no RAR or unRAR entries and records the exact modified-subset patch' {
        $rarEntries = @($script:ArchiveEntries | Where-Object {
            $segments = $_ -split '[\\/]'
            $_ -match '(?i)^bit7z[\\/]lib[\\/]7zSDK[\\/]' -and
                @($segments | Where-Object { $_ -match '^(?i:rar)' -or $_ -match '^(?i:unrarlicense)(?:\..*)?$' }).Count -gt 0
        })
        $rarEntries.Count | Should Be 0
        @($script:ArchiveEntries | Where-Object { (Split-Path -Leaf $_) -ieq 'Rar.dll' }).Count | Should Be 0
        $script:Provenance.packaging.sourceTreeStatus | Should Be 'MPL-2.0-permitted modified subset'
        $script:Provenance.packaging.originalUpstream.commit | Should Be $script:Bit7zCommit
        $script:Provenance.packaging.originalUpstream.sourceUrl | Should Be $script:Bit7zSourceUrl
        $script:Provenance.packaging.originalUpstream.sourceSha256 | Should Be $script:Bit7zSourceSha256
        $patch = @($script:Provenance.packaging.patches)[0]
        $patch.buildOptions.BIT7Z_DISABLE_RAR | Should Be 'ON'
        $script:Provenance.sevenZip.build.options.BIT7Z_DISABLE_RAR | Should Be 'ON'
        @($patch.removedPaths).Count | Should Be 29
        @(Compare-Object -ReferenceObject ($script:ExpectedRemovedPaths | Sort-Object) -DifferenceObject (@($patch.removedPaths) | Sort-Object)).Count | Should Be 0
        foreach ($path in $script:ExpectedRemovedPaths) {
            (Test-Path -LiteralPath (Join-Path $script:Bit7zRoot $path)) | Should Be $false
        }
    }

    It 'uses the production bit7z v4 CMake configure and build plan' {
        $inputs = New-TestBuildInputs -Root (Join-Path $TestDrive 'plan')
        $inputs.Plan.Count | Should Be 4
        $bit7z = @($inputs.Plan | Where-Object Name -eq 'bit7z')[0]
        (Split-Path -Leaf $bit7z.FilePath) | Should Be 'cmake.exe'
        (Split-Path -Leaf $bit7z.LibraryPath) | Should Be 'bit7z.lib'
        @($bit7z.Arguments).Count | Should Be 18
        $bit7z.Arguments[0] | Should Be '-S'
        $bit7z.Arguments[5] | Should Be 'Visual Studio 17 2022'
        ($bit7z.Arguments -contains '-DBIT7Z_USE_NATIVE_STRING=ON') | Should Be $true
        ($bit7z.Arguments -contains '-DBIT7Z_PATH_SANITIZATION=ON') | Should Be $true
        $bit7z.BuildArguments[0] | Should Be '--build'
        ($bit7z.BuildArguments -contains 'bit7z') | Should Be $true
        ($bit7z.Arguments -join '|') | Should Not Match 'bit7z\.sln|bit7z64\.lib'
    }

    It 'attests bit7z configure and build as distinct exact commands' {
        $inputs = New-TestBuildInputs -Root (Join-Path $TestDrive 'attestation')
        $commands = @(Get-BuildCommandAttestation -SourceRoot $inputs.Source -DependencyPlan $inputs.Plan -ProductExecutable 'C:\Tools\MSBuild.exe' -ProductArguments $inputs.ProductArguments -BuildContext $inputs.Context)
        $commands.Count | Should Be 7
        @($commands.name | Sort-Object -Unique).Count | Should Be 7
        $configure = @($commands | Where-Object name -eq 'bit7z Release x64 configure')[0]
        $build = @($commands | Where-Object name -eq 'bit7z Release x64 build')[0]
        $configure.executable | Should Be 'cmake.exe'
        @($configure.arguments).Count | Should Be 18
        $configure.arguments[1] | Should Be '<source>\bit7z'
        ($configure.arguments -contains '-DBIT7Z_CUSTOM_7ZIP_PATH=<source>\bit7z\lib\7zSDK') | Should Be $true
        $build.executable | Should Be 'cmake.exe'
        @($build.arguments).Count | Should Be 9
        $build.arguments[1] | Should Be '<source>\bit7z\out\build\x64-Release'
        $build.arguments[5] | Should Be 'bit7z'
    }

    It 'seals only the exact v4 source identity command and linker contract' {
        $inputs = New-TestBuildInputs -Root (Join-Path $TestDrive 'seal-inputs')
        $candidate = Join-Path $TestDrive 'candidate'
        [IO.Directory]::CreateDirectory($candidate) | Out-Null
        $payload = Join-Path $candidate 'payload.bin'
        [IO.File]::WriteAllText($payload, 'payload', [Text.Encoding]::ASCII)
        $item = Get-Item -LiteralPath $payload
        $manifest = [ordered]@{
            schemaVersion = 1
            createdAtUtc = '2026-09-16T00:00:00.0000000Z'
            attestation = New-TestAttestation -Inputs $inputs
            versions = [ordered]@{ product = '2.19.1.0'; ytdlp = 'fixture'; ffmpeg = 'fixture'; ffprobe = 'fixture'; deno = 'fixture' }
            files = @([ordered]@{ path = 'payload.bin'; sha256 = (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash; length = $item.Length })
        }
        $accepted = try { Assert-CandidateManifestSeal -CandidateRoot $candidate -Manifest $manifest; 'accepted' } catch { $_.Exception.Message }
        $accepted | Should Be 'accepted'
        $manifest.attestation.dependencyArchive.bit7zSource.commit = ('0' * 40)
        $rejected = try { Assert-CandidateManifestSeal -CandidateRoot $candidate -Manifest $manifest; 'accepted' } catch { $_.Exception.Message }
        $rejected | Should Be 'candidate_manifest_invalid'
    }
}
