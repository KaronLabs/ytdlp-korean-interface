$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Collector = Join-Path $RepositoryRoot 'tools\collect-ffmpeg-corresponding-sources.ps1'
$OfficialArchive = 'E:\03_AllWork\ytdlp-korean-interface\.quality-presets-work\karon2-input\immutable\ffmpeg-n9.0.1-30-g9258bacca5-win64-lgpl-9.0.zip'

if (Test-Path -LiteralPath $Collector -PathType Leaf) {
    . $Collector -NoExecute
}

function New-CompleteManifest {
    $component = [pscustomobject]@{
        id = 'zlib'
        version = '1.3.2'
        commit = 'e3dc0a85b7032e98380dec011bc8f2c2ee0d8fca'
        source = [pscustomobject]@{
            url = 'https://github.com/madler/zlib/archive/e3dc0a85b7032e98380dec011bc8f2c2ee0d8fca.tar.gz'
            sha256 = 'A' * 64
        }
        license = [pscustomobject]@{
            expression = 'Zlib'
            textPath = 'licenses/zlib.txt'
        }
        recipe = [pscustomobject]@{
            scriptPath = 'scripts.d/20-zlib.sh'
            patches = @()
        }
    }
    return [pscustomobject]@{
        schemaVersion = 1
        closureStatus = 'complete'
        includedPaths = @('licenses/zlib.txt', 'scripts.d/20-zlib.sh')
        enabledExternalLibraries = @(
            [pscustomobject]@{ option = '--enable-zlib'; componentId = 'zlib' }
        )
        components = @($component)
    }
}

function Assert-ExactError {
    param([scriptblock] $Action, [string] $Expected)
    $actual = $null
    try { & $Action | Out-Null } catch { $actual = $_.Exception.Message }
    if ($actual -cne $Expected) { throw "Expected '$Expected', got '$actual'." }
}

Describe 'FFmpeg corresponding-source collector' {
    It 'rejects an unknown enabled external library' {
        $manifest = New-CompleteManifest
        Assert-ExactError {
            Assert-FfmpegSourceManifest -Manifest $manifest -BuildConfigurationOptions @(
                '--pkg-config-flags=--static',
                '--enable-version3',
                '--enable-zlib',
                '--enable-libmystery'
            )
        } 'ffmpeg_source_unknown_enabled_library:--enable-libmystery'
    }

    It 'rejects a mutable source URL' {
        $manifest = New-CompleteManifest
        $manifest.components[0].source.url = 'https://github.com/madler/zlib/archive/refs/heads/master.zip'
        Assert-ExactError {
            Assert-FfmpegSourceManifest -Manifest $manifest -BuildConfigurationOptions @(
                '--pkg-config-flags=--static', '--enable-version3', '--enable-zlib'
            )
        } 'ffmpeg_source_mutable_url:zlib'
    }

    It 'rejects a source archive SHA-256 mismatch' {
        $root = Join-Path ([IO.Path]::GetTempPath()) ('karon-ffmpeg-source-hash-' + [Guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($root) | Out-Null
        try {
            $archive = Join-Path $root 'source.tar.xz'
            [IO.File]::WriteAllText($archive, 'wrong source bytes', [Text.UTF8Encoding]::new($false))
            Assert-ExactError {
                Assert-SourceArchiveHash -Path $archive -ExpectedSha256 ('A' * 64) -ComponentId 'zlib'
            } 'ffmpeg_source_sha256_mismatch:zlib'
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects GPL or nonfree build configuration' {
        foreach ($forbidden in @('--enable-gpl', '--enable-nonfree')) {
            $manifest = New-CompleteManifest
            Assert-ExactError {
                Assert-FfmpegSourceManifest -Manifest $manifest -BuildConfigurationOptions @(
                    '--pkg-config-flags=--static', '--enable-version3', '--enable-zlib', $forbidden
                )
            } "ffmpeg_source_forbidden_configuration:$forbidden"
        }
    }

    It 'rejects missing patch or license evidence' {
        $missingLicense = New-CompleteManifest
        $missingLicense.components[0].license.textPath = ''
        Assert-ExactError {
            Assert-FfmpegSourceManifest -Manifest $missingLicense -BuildConfigurationOptions @(
                '--pkg-config-flags=--static', '--enable-version3', '--enable-zlib'
            )
        } 'ffmpeg_source_missing_license:zlib'

        $missingPatch = New-CompleteManifest
        $missingPatch.components[0].recipe.patches = @('patches/zlib.patch')
        Assert-ExactError {
            Assert-FfmpegSourceManifest -Manifest $missingPatch -BuildConfigurationOptions @(
                '--pkg-config-flags=--static', '--enable-version3', '--enable-zlib'
            )
        } 'ffmpeg_source_missing_patch:zlib:patches/zlib.patch'
    }

    It 'rejects duplicate component identifiers that collide by case' {
        $manifest = New-CompleteManifest
        $duplicate = New-CompleteManifest
        $duplicate.components[0].id = 'ZLIB'
        $manifest.components = @($manifest.components[0], $duplicate.components[0])
        Assert-ExactError {
            Assert-FfmpegSourceManifest -Manifest $manifest -BuildConfigurationOptions @(
                '--pkg-config-flags=--static', '--enable-version3', '--enable-zlib'
            )
        } 'ffmpeg_source_duplicate_component:ZLIB'
    }

    It 'accepts the exact official archive and records its real build configuration' {
        $evidence = Read-FfmpegBinaryEvidence `
            -ArchivePath $OfficialArchive `
            -ExpectedArchiveSha256 '39697D69681A09BD55A0F0224360A9A4285BC12127DF807D7242592B0E144A7B' `
            -ExpectedFfmpegSha256 '41482EABC1A33F9D1E4334CA32EC9259AA34A3EC2493FCC9F214BFE54301CE38' `
            -ExpectedFfprobeSha256 '376F55EB141C3B0D8790B64967B8CBF1737D76BEBE0820189356C71CC884B395' `
            -ExpectedVersion 'n9.0.1-30-g9258bacca5'

        $evidence.archiveSha256 | Should Be '39697D69681A09BD55A0F0224360A9A4285BC12127DF807D7242592B0E144A7B'
        $evidence.ffmpegSha256 | Should Be '41482EABC1A33F9D1E4334CA32EC9259AA34A3EC2493FCC9F214BFE54301CE38'
        $evidence.ffprobeSha256 | Should Be '376F55EB141C3B0D8790B64967B8CBF1737D76BEBE0820189356C71CC884B395'
        @($evidence.configurationOptions) -contains '--pkg-config-flags=--static' | Should Be $true
        @($evidence.configurationOptions) -contains '--enable-version3' | Should Be $true
        @($evidence.configurationOptions) -contains '--enable-gpl' | Should Be $false
        @($evidence.configurationOptions) -contains '--enable-nonfree' | Should Be $false
    }

    It 'validates all retained source records while preserving the fail-closed gate' {
        $root = Join-Path $RepositoryRoot 'release\runtime\v2.19.1-karon.2\ffmpeg'
        $manifest = Get-Content -Raw (Join-Path $root 'manifest.json') | ConvertFrom-Json
        $graph = Get-Content -Raw (Join-Path $root 'component-graph.json') | ConvertFrom-Json
        $crates = Get-Content -Raw (Join-Path $root 'rav1e-crates.json') | ConvertFrom-Json
        $options = @(Get-Content (Join-Path $root 'buildconf.txt') | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^--' })

        Assert-FfmpegClosureGraph $manifest $graph $crates $options
        $graph.components.Count | Should Be 85
        $crates.components.Count | Should Be 270
        $manifest.verifiedSourceRecordCount | Should Be 358
        $manifest.closureStatus | Should Be 'incomplete'
    }
}
