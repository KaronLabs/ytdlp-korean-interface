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

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -cne $Actual) { throw "$Message expected='$Expected' actual='$Actual'" }
}

$header = Get-Content -LiteralPath $HeaderPath -Raw
$resource = Get-Content -LiteralPath $ResourcePath -Raw
$about = Get-Content -LiteralPath $AboutPath -Raw
$locale = (Get-Content -LiteralPath $LocalePath -Raw -Encoding UTF8 | ConvertFrom-Json).strings

Assert-True ($header -match 'ver_tag\s*\{\s*"v2\.19\.1"\s*\}') 'upstream version must remain exactly v2.19.1'
Assert-True ($header -match 'display_ver_tag\s*\{\s*"v2\.19\.1-karon\.2"\s*\}') 'display version must be an explicit v2.19.1-karon.2 constant'
Assert-True ($header -match 'title\s*\{\s*"ytdlp-interface "\s*\+\s*display_ver_tag\s*\}') 'window title must use the display version, not derive branding from the upstream tag'
Assert-True ($header -match 'cur_ver\s*\{\s*ver_tag\s*\}') 'update comparison version must still be built from the upstream ver_tag'
Assert-True ($resource -match 'FILEVERSION\s+2,19,1,0') 'numeric FILEVERSION must remain 2.19.1.0'
Assert-True ($resource -match 'PRODUCTVERSION\s+2,19,1,0') 'numeric PRODUCTVERSION must remain 2.19.1.0'
Assert-True ($resource -match 'VALUE\s+"FileVersion",\s+"v2\.19\.1-karon\.2"') 'human FileVersion must expose v2.19.1-karon.2'
Assert-True ($resource -match 'VALUE\s+"ProductVersion",\s+"v2\.19\.1-karon\.2"') 'human ProductVersion must expose v2.19.1-karon.2'
Assert-True ($about -match 'display_ver_tag') 'About must use the Karon display version'

$localeKeys = @(
    'about.license_summary',
    'about.notices_summary',
    'about.license_details_action',
    'about.source_details_title',
    'about.source_details_body'
)
foreach ($key in $localeKeys) {
    $property = $locale.PSObject.Properties[$key]
    Assert-True ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) "ko-KR locale is missing $key"
}

$englishLicense = 'KaronLabs application code is MIT. Third-party components have their own licenses.'
$koreanLicense = -join (@(75,97,114,111,110,76,97,98,115,32,50528,54540,47532,52992,51060,49496,32,53076,46300,45716,32,77,73,84,32,46972,51060,49440,49828,51077,45768,45796,46,32,51228,51,51088,32,44396,49457,32,50836,49548,50640,45716,32,44033,44033,51032,32,46972,51060,49440,49828,44032,32,51201,50857,46121,45768,45796,46) | ForEach-Object { [char]$_ })
$koreanAction = -join (@(46972,51060,49440,49828,32,48143,32,49548,49828,32,49464,48512,32,51221,48372) | ForEach-Object { [char]$_ })
Assert-True ($about.Contains($englishLicense)) 'English About must use the exact scoped license statement'
Assert-Equal $koreanLicense ([string]$locale.PSObject.Properties['about.license_summary'].Value) 'ko-KR About must use the exact scoped license statement'
Assert-True ($about -match 'widgets::Button\s+btn_license_details') 'About must use the existing keyboard-accessible Nana button control'
Assert-True ($about -match 'about\["btn_license_details"\]\s*<<\s*btn_license_details') 'license details button must be attached to the About layout'
Assert-True ($about -match 'btn_license_details\.events\(\)\.click') 'license details button must open details through its click event'
Assert-True ($about -notmatch 'l_about_ver\.events\(\)\.click') 'plain version label must not have a mouse-only click handler'
Assert-True ($about.Contains('Licenses and source details')) 'English About action must be concise and localizable'
Assert-Equal $koreanAction ([string]$locale.PSObject.Properties['about.license_details_action'].Value) 'ko-KR About action text differs'
Assert-True ($about -match 'fm\.center\(820,\s*720\)') 'settings window base height must accommodate the About action at 100% DPI'
Assert-True ($about -match 'about_summary_height\s*\{\s*fm\.dpi_scale\(64\)\s*\}') 'About summary row must scale for 100/150/200% DPI'
Assert-True ($about -match 'about_action_height\s*\{\s*fm\.dpi_scale\(34\)\s*\}') 'About action row must scale for 100/150/200% DPI'

$artifactNames = @(
    'THIRD-PARTY-NOTICES.txt',
    'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources.zip'
)
$koreanDetails = [string]$locale.PSObject.Properties['about.source_details_body'].Value
foreach ($artifactName in $artifactNames) {
    Assert-True ($about.Contains($artifactName)) "English About details are missing exact artifact $artifactName"
    Assert-True ($koreanDetails.Contains($artifactName)) "ko-KR About details are missing exact artifact $artifactName"
}

$durableSources = @(
    'https://github.com/yt-dlp/yt-dlp',
    'https://github.com/FFmpeg/FFmpeg/commit/9258bacca50d7ca28bcb6d797e8952123e35105b',
    'https://github.com/BtbN/FFmpeg-Builds/tree/3e6685eda92f9288c15ac320139622dcedca09a4',
    'https://github.com/rikyoz/bit7z/tree/c81c6c1cbf44e148cd4b06f4bb69d7ea1e299742',
    'https://github.com/ip7z/7zip/tree/8c63d71ff886bda90c86db28466287f977374237',
    'https://github.com/denoland/deno/tree/2d674b25625bcc367853d00fe86f6e84390f88cb'
)
foreach ($source in $durableSources) {
    Assert-True ($about.Contains($source)) "English About source details are missing $source"
    Assert-True ($koreanDetails.Contains($source)) "ko-KR About source details are missing $source"
}

Write-Host 'PASS: v2.19.1-karon.2 release branding and About notices contract'
exit 0
