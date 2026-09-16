$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ArchivePath = Join-Path $RepositoryRoot 'ytdlp-interface dependencies.7z'
$SevenZip = @(
    (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
    (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
$script:Failures = 0
$script:Tests = 0

function Assert-True { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw $Message } }
function Assert-Equal { param($Expected,$Actual,[string]$Message='values differ') if ($Expected -cne $Actual) { throw "$Message expected='$Expected' actual='$Actual'" } }
function Invoke-Test { param([string]$Name,[scriptblock]$Body) $script:Tests++; try { & $Body; Write-Host "PASS: $Name" } catch { $script:Failures++; Write-Host "FAIL: $Name"; Write-Host $_ } }

Assert-True (-not [string]::IsNullOrWhiteSpace($SevenZip)) '7z.exe must be installed under Program Files.'
Assert-True (Test-Path -LiteralPath $ArchivePath -PathType Leaf) 'dependency archive is missing.'

$ExtractionRoot = Join-Path ([IO.Path]::GetTempPath()) ('karon-dependency-contract-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($ExtractionRoot) | Out-Null

try {
    & $SevenZip x $ArchivePath ('-o' + $ExtractionRoot) 'bit7z\*' -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "7z extraction failed with exit code $LASTEXITCODE." }
    $Bit7zRoot = Join-Path $ExtractionRoot 'bit7z'

    Invoke-Test 'archive carries bit7z 4.1.0 under MPL-2.0 with the v4 file extractor API' {
        $Cmake = Get-Content -LiteralPath (Join-Path $Bit7zRoot 'CMakeLists.txt') -Raw
        $License = Get-Content -LiteralPath (Join-Path $Bit7zRoot 'LICENSE') -Raw
        Assert-True ($Cmake -match '(?m)^\s*VERSION 4\.1\.0\s*$') 'bit7z CMake project is not version 4.1.0.'
        Assert-True ($License -match 'Mozilla Public License Version 2\.0') 'bit7z LICENSE is not MPL-2.0.'
        Assert-True (Test-Path -LiteralPath (Join-Path $Bit7zRoot 'include\bit7z\bitfileextractor.hpp') -PathType Leaf) 'bit7z v4 file extractor header is missing.'
    }

    Invoke-Test 'archive carries the pinned 7-Zip 26.01 source identity' {
        $VersionHeader = Get-Content -LiteralPath (Join-Path $Bit7zRoot 'lib\7zSDK\C\7zVersion.h') -Raw
        Assert-True ($VersionHeader -match '(?m)^#define MY_VER_MAJOR 26\s*$') '7-Zip major version is not 26.'
        Assert-True ($VersionHeader -match '(?m)^#define MY_VER_MINOR 1\s*$') '7-Zip minor version is not 01.'
        Assert-True ($VersionHeader -match '(?m)^#define MY_VERSION_NUMBERS "26\.01"\s*$') '7-Zip version string is not 26.01.'
    }

    Invoke-Test 'archive binds x64 Release artifacts to pinned non-RAR build provenance' {
        $ProvenancePath = Join-Path $Bit7zRoot 'KARON_DEPENDENCY_PROVENANCE.json'
        Assert-True (Test-Path -LiteralPath $ProvenancePath -PathType Leaf) 'dependency provenance manifest is missing.'
        $Provenance = Get-Content -LiteralPath $ProvenancePath -Raw | ConvertFrom-Json
        Assert-Equal 1 ([int]$Provenance.schemaVersion) 'unexpected provenance schema'
        Assert-Equal '4.1.0' ([string]$Provenance.bit7z.version) 'unexpected bit7z version'
        Assert-Equal 'c81c6c1cbf44e148cd4b06f4bb69d7ea1e299742' ([string]$Provenance.bit7z.commit) 'unexpected bit7z commit'
        Assert-Equal 'MPL-2.0' ([string]$Provenance.bit7z.license) 'unexpected bit7z license'
        Assert-Equal 'Release' ([string]$Provenance.bit7z.build.configuration) 'unexpected bit7z configuration'
        Assert-Equal 'x64' ([string]$Provenance.bit7z.build.platform) 'unexpected bit7z platform'
        Assert-Equal 'v143' ([string]$Provenance.bit7z.build.toolset) 'unexpected bit7z toolset'
        Assert-Equal 'ON' ([string]$Provenance.bit7z.build.options.BIT7Z_USE_NATIVE_STRING) 'native-string build option is not enabled'
        Assert-Equal 'ON' ([string]$Provenance.bit7z.build.options.BIT7Z_PATH_SANITIZATION) 'path sanitization is not enabled'
        Assert-Equal 'ON' ([string]$Provenance.bit7z.build.options.BIT7Z_STATIC_RUNTIME) 'static runtime ABI option is not enabled'
        Assert-Equal 'ON' ([string]$Provenance.bit7z.build.options.BIT7Z_REGEX_MATCHING) 'regex matching required by update extraction is not enabled'
        Assert-Equal '26.01' ([string]$Provenance.sevenZip.version) 'unexpected 7-Zip version'
        Assert-Equal '8c63d71ff886bda90c86db28466287f977374237' ([string]$Provenance.sevenZip.commit) 'unexpected 7-Zip commit'
        Assert-Equal 'Format7zF' ([string]$Provenance.sevenZip.build.bundle) 'unexpected 7-Zip DLL bundle'
        Assert-Equal '1' ([string]$Provenance.sevenZip.build.options.DISABLE_RAR) 'RAR code was not disabled at build time'

        foreach ($Artifact in @($Provenance.bit7z.artifact, $Provenance.sevenZip.artifact)) {
            $ArtifactPath = Join-Path $Bit7zRoot ([string]$Artifact.path)
            Assert-True (Test-Path -LiteralPath $ArtifactPath -PathType Leaf) "dependency artifact is missing: $($Artifact.path)"
            Assert-Equal ([string]$Artifact.sha256).ToUpperInvariant() (Get-FileHash -LiteralPath $ArtifactPath -Algorithm SHA256).Hash.ToUpperInvariant() "dependency artifact hash mismatch: $($Artifact.path)"
        }

        $RuntimePath = Join-Path $Bit7zRoot ([string]$Provenance.sevenZip.artifact.path)
        $RuntimeVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($RuntimePath)
        Assert-Equal 26 $RuntimeVersion.FileMajorPart 'unexpected 7-Zip DLL major version'
        Assert-Equal 1 $RuntimeVersion.FileMinorPart 'unexpected 7-Zip DLL minor version'
    }

    Invoke-Test 'application consumes the bit7z v4 native-string contract and reports exact licenses' {
        $Util = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'ytdlp-interface\util.cpp') -Raw
        [xml]$Project = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'ytdlp-interface\ytdlp-interface.vcxproj') -Raw
        $Settings = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'ytdlp-interface\forms\form_settings.cpp') -Raw
        Assert-True ($Util -match '#include <bit7z/bitfileextractor\.hpp>') 'util.cpp does not include the v4 file extractor header.'
        Assert-True ($Util -match '\bBitFileExtractor\b') 'util.cpp does not use BitFileExtractor.'
        Assert-True ($Util -notmatch '\bBitExtractor\b') 'util.cpp still uses the v3 BitExtractor API.'
        $ReleaseX64 = @($Project.Project.ItemDefinitionGroup | Where-Object { $_.Condition -eq "'`$(Configuration)|`$(Platform)'=='Release|x64'" })
        Assert-Equal 1 $ReleaseX64.Count 'Release x64 project definition is ambiguous'
        $Definitions = [string]$ReleaseX64[0].ClCompile.PreprocessorDefinitions
        Assert-True (($Definitions -split ';') -contains 'BIT7Z_USE_NATIVE_STRING') 'Release x64 consumer is missing BIT7Z_USE_NATIVE_STRING.'
        Assert-True (($Definitions -split ';') -contains 'BIT7Z_PATH_SANITIZATION') 'Release x64 consumer is missing BIT7Z_PATH_SANITIZATION.'
        Assert-True (($Definitions -split ';') -contains 'BIT7Z_REGEX_MATCHING') 'Release x64 consumer is missing BIT7Z_REGEX_MATCHING.'
        Assert-True ($Settings -match [regex]::Escape('v4.1.0 (MPL-2.0) / 7-Zip v26.01 (LGPL-2.1-or-later, BSD-2-Clause, BSD-3-Clause; RAR disabled)')) 'About text does not report exact dependency versions and licenses.'
    }
}
finally {
    Remove-Item -LiteralPath $ExtractionRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:Failures -gt 0) { throw "$($script:Failures) of $($script:Tests) dependency contract tests failed." }
Write-Host "All $($script:Tests) dependency contract tests passed."
exit 0
