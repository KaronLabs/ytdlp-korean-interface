$collector = Join-Path $PSScriptRoot '..\..\tools\collect-ffmpeg-corresponding-sources.ps1'
. $collector -NoExecute

$releaseRoot = Join-Path $PSScriptRoot '..\..\release\runtime\v2.19.1-karon.2\ffmpeg'
$manifestPath = Join-Path $releaseRoot manifest.json
$binaryPath = 'E:\03_AllWork\ytdlp-korean-interface\.quality-presets-work\karon2-input\immutable\ffmpeg-n9.0.1-30-g9258bacca5-win64-lgpl-9.0.zip'

function Copy-JsonObject {
    param($Value)
    $Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json
}

Describe 'FFmpeg corresponding-source collector schema 3' {
    BeforeAll {
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $graph = Get-Content -Raw -LiteralPath (Join-Path $releaseRoot $manifest.sourceSets.btbnActionsCache.componentGraphPath) | ConvertFrom-Json
        $crates = Get-Content -Raw -LiteralPath (Join-Path $releaseRoot $manifest.sourceSets.rav1eCrates.manifestPath) | ConvertFrom-Json
        $toolchain = Get-Content -Raw -LiteralPath (Join-Path $releaseRoot $manifest.sourceSets.toolchain.manifestPath) | ConvertFrom-Json
        $corpus = Get-Content -Raw -LiteralPath (Join-Path $releaseRoot $manifest.sourceSets.licenseCorpus.manifestPath) | ConvertFrom-Json
        $options = @(Get-Content -LiteralPath (Join-Path $releaseRoot $manifest.binary.buildConfigurationPath) | ForEach-Object Trim | Where-Object { $_ -match '^--' })
    }

    It 'rejects an unknown enabled external library' {
        { Assert-FfmpegClosureMetadata $manifest $graph $crates $toolchain $corpus ($options + '--enable-libunknown') } |
            Should Throw 'ffmpeg_source_unknown_enabled_library'
    }

    It 'rejects a mutable URL' {
        $bad = Copy-JsonObject $toolchain
        $bad.components[0].source.url = 'https://github.com/example/project/archive/main.zip'
        { Assert-FfmpegClosureMetadata $manifest $graph $crates $bad $corpus $options } |
            Should Throw 'ffmpeg_source_mutable_url'
    }

    It 'rejects a source SHA mismatch' {
        $path = Join-Path $TestDrive source.bin
        [IO.File]::WriteAllText($path, 'wrong')
        { Assert-SourceArchiveHash $path ('0' * 64) component } |
            Should Throw 'ffmpeg_source_sha256_mismatch'
    }

    It 'rejects GPL and nonfree configuration' {
        { Assert-FfmpegClosureMetadata $manifest $graph $crates $toolchain $corpus ($options + '--enable-gpl') } |
            Should Throw 'ffmpeg_source_forbidden_configuration'
        { Assert-FfmpegClosureMetadata $manifest $graph $crates $toolchain $corpus ($options + '--enable-nonfree') } |
            Should Throw 'ffmpeg_source_forbidden_configuration'
    }

    It 'rejects missing patch and license evidence' {
        $badPatch = Copy-JsonObject $graph
        $badPatch.components[0].recipe.patches = @([pscustomobject]@{ path = ''; sha256 = '' })
        { Assert-FfmpegClosureMetadata $manifest $badPatch $crates $toolchain $corpus $options } |
            Should Throw 'ffmpeg_source_missing_patch'
        $badLicense = Copy-JsonObject $graph
        $badLicense.components[0].license.files = @()
        { Assert-FfmpegClosureMetadata $manifest $badLicense $crates $toolchain $corpus $options } |
            Should Throw 'ffmpeg_source_missing_license'
    }

    It 'rejects duplicate identifiers with a case collision' {
        $bad = Copy-JsonObject $graph
        $duplicate = Copy-JsonObject $bad.components[0]
        $duplicate.id = $duplicate.id.ToUpperInvariant()
        $bad.components += $duplicate
        { Assert-FfmpegClosureMetadata $manifest $bad $crates $toolchain $corpus $options } |
            Should Throw 'ffmpeg_source_duplicate_component'
    }

    It 'accepts the exact official archive and records its build configuration' {
        $evidence = Read-FfmpegBinaryEvidence $binaryPath $manifest.binary.archiveSha256 $manifest.binary.ffmpegSha256 $manifest.binary.ffprobeSha256 $manifest.binary.expectedVersion
        $evidence.ffmpegSha256 | Should Be '41482EABC1A33F9D1E4334CA32EC9259AA34A3EC2493FCC9F214BFE54301CE38'
        $evidence.configurationOptions.Count | Should BeGreaterThan 0
        ($evidence.configurationOptions -contains '--enable-version3') | Should Be $true
        ($evidence.configurationOptions -notcontains '--enable-gpl') | Should Be $true
    }

    It 'requires deterministic LicenseRef text with matching bytes' {
        $root = Join-Path $TestDrive corpus
        [IO.Directory]::CreateDirectory((Join-Path $root 'licenses\extracted')) | Out-Null
        $file = Join-Path $root 'licenses\extracted\license.txt'
        [IO.File]::WriteAllText($file, 'exact license text')
        $sha = Get-UpperSha256 $file
        $mini = [pscustomobject]@{
            textObjectCount = 1
            textObjects = @([pscustomobject]@{
                sha256 = $sha
                licenseRef = 'LicenseRef-' + $sha.Substring(0, 16).ToLowerInvariant()
                bundlePath = 'licenses/extracted/license.txt'
            })
        }
        (Assert-LicenseCorpus $mini $root -VerifyFiles).Count | Should Be 1
        [IO.File]::WriteAllText($file, 'changed')
        { Assert-LicenseCorpus $mini $root -VerifyFiles } | Should Throw 'ffmpeg_source_sha256_mismatch'
    }

    It 'requires exact GCC libgomp and MinGW toolchain sources' {
        $bad = Copy-JsonObject $toolchain
        $bad.components = @($bad.components | Where-Object id -ne 'toolchain-gcc-16.2.0')
        { Assert-FfmpegClosureMetadata $manifest $graph $crates $bad $corpus $options } |
            Should Throw 'ffmpeg_source_missing_toolchain'
    }

    It 'requires all 19 nested trees as conservative superset closures' {
        $bad = Copy-JsonObject $graph
        $bad.nestedClosures[0].applicability = 'exact-link-minimum'
        { Assert-FfmpegClosureMetadata $manifest $bad $crates $toolchain $corpus $options } |
            Should Throw 'ffmpeg_source_nested_closure_incomplete'
        $graph.nestedClosures.Count | Should Be 19
    }

    It 'creates byte-identical deterministic ZIPs' {
        $a = Join-Path $TestDrive a.txt
        $b = Join-Path $TestDrive b.txt
        [IO.File]::WriteAllText($a, 'alpha')
        [IO.File]::WriteAllText($b, 'beta')
        $items = @(
            [pscustomobject]@{ SourcePath = $b; EntryPath = 'B.txt' },
            [pscustomobject]@{ SourcePath = $a; EntryPath = 'a.txt' }
        )
        $one = Join-Path $TestDrive one.zip
        $two = Join-Path $TestDrive two.zip
        New-DeterministicZip $items $one
        New-DeterministicZip $items $two
        (Get-UpperSha256 $one) | Should Be (Get-UpperSha256 $two)
    }

    It 'validates the complete retained conservative closure' {
        { Assert-FfmpegClosureMetadata $manifest $graph $crates $toolchain $corpus $options } | Should Not Throw
        $manifest.closureStatus | Should Be complete
        $manifest.verifiedSourceRecordCount | Should Be 407
        $corpus.textObjectCount | Should Be 628
    }
}

