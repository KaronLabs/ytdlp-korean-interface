$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$HeaderPath = Join-Path $RepositoryRoot 'ytdlp-interface\gui.hpp'
$ResourcePath = Join-Path $RepositoryRoot 'ytdlp-interface\ytdlp-interface.rc'
$AboutPath = Join-Path $RepositoryRoot 'ytdlp-interface\forms\form_settings.cpp'
$LocalePath = Join-Path $RepositoryRoot 'locales\ko-KR.json'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$header = Get-Content -LiteralPath $HeaderPath -Raw
$resource = Get-Content -LiteralPath $ResourcePath -Raw
$about = Get-Content -LiteralPath $AboutPath -Raw
$locale = (Get-Content -LiteralPath $LocalePath -Raw -Encoding UTF8 | ConvertFrom-Json).strings

Assert-True ($header -match 'display_ver_tag\s*\{\s*"v2\.19\.1-karon\.2"\s*\}') 'display version must be an explicit v2.19.1-karon.2 constant'
Assert-True ($header -match 'title\s*\{\s*"ytdlp-interface "\s*\+\s*display_ver_tag\s*\}') 'window title must use the display version, not derive branding from the upstream tag'
Assert-True ($resource -match 'FILEVERSION\s+2,19,1,0') 'numeric FILEVERSION must remain 2.19.1.0'
Assert-True ($resource -match 'PRODUCTVERSION\s+2,19,1,0') 'numeric PRODUCTVERSION must remain 2.19.1.0'
Assert-True ($resource -match 'VALUE\s+"FileVersion",\s+"v2\.19\.1-karon\.2"') 'human FileVersion must expose v2.19.1-karon.2'
Assert-True ($resource -match 'VALUE\s+"ProductVersion",\s+"v2\.19\.1-karon\.2"') 'human ProductVersion must expose v2.19.1-karon.2'
Assert-True ($about -match 'display_ver_tag') 'About must use the Karon display version'

$localeKeys = @(
    'about.license_summary',
    'about.notices_summary',
    'about.source_details_hint',
    'about.source_details_title',
    'about.source_details_body'
)
foreach ($key in $localeKeys) {
    $property = $locale.PSObject.Properties[$key]
    Assert-True ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) "ko-KR locale is missing $key"
}

Assert-True ($about -match 'KaronLabs application code is MIT') 'English About must limit the MIT statement to KaronLabs application code'
Assert-True ($about -match 'third-party components have their own licenses') 'English About must distinguish third-party licenses'
Assert-True ($about -match 'THIRD-PARTY-NOTICES\.txt') 'About must point to the bundled third-party notices'
Assert-True ($about -match 'corresponding-sources') 'About must point to the corresponding-sources release asset'

$durableSources = @(
    'https://github.com/yt-dlp/yt-dlp',
    'https://github.com/FFmpeg/FFmpeg/commit/9258bacca50d7ca28bcb6d797e8952123e35105b',
    'https://github.com/BtbN/FFmpeg-Builds/tree/3e6685eda92f9288c15ac320139622dcedca09a4',
    'https://github.com/rikyoz/bit7z/tree/c81c6c1cbf44e148cd4b06f4bb69d7ea1e299742',
    'https://github.com/ip7z/7zip/tree/8c63d71ff886bda90c86db28466287f977374237',
    'https://github.com/denoland/deno/tree/2d674b25625bcc367853d00fe86f6e84390f88cb'
)
foreach ($source in $durableSources) {
    Assert-True ($about.Contains($source)) "About source details are missing $source"
}

Write-Host 'PASS: v2.19.1-karon.2 release branding and About notices contract'
exit 0
