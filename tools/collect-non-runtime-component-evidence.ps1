param(
    [Parameter(Mandatory = $true)] [string] $ManifestPath,
    [Parameter(Mandatory = $true)] [string] $SourceCacheDirectory,
    [Parameter(Mandatory = $true)] [string] $OutputDirectory,
    [Parameter(Mandatory = $true)] [string] $ApplicationRepository,
    [AllowEmptyString()] [string] $ApplicationCommit = '',
    [AllowEmptyString()] [string] $CandidateManifestPath = '',
    [Parameter(Mandatory = $true)] [string] $DependencyArchivePath,
    [Parameter(Mandatory = $true)] [string] $SevenZipRuntimeArchivePath,
    [Parameter(Mandatory = $true)] [string] $SevenZipSourceArchivePath,
    [Parameter(Mandatory = $true)] [string] $SevenZipVerificationPath,
    [Parameter(Mandatory = $true)] [string] $YtDlpBinaryPath,
    [AllowEmptyString()] [string] $SevenZipExecutable = '',
    [switch] $AcquireSources
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.IO.Compression.FileSystem
if ($null -eq ('KaronEvidenceDirectoryIdentity' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class KaronEvidenceDirectoryIdentity
{
    [StructLayout(LayoutKind.Sequential)]
    private struct ByHandleFileInformation
    {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(
        string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
        uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle file, out ByHandleFileInformation information);

    public static string Get(string path)
    {
        using (SafeFileHandle handle = CreateFile(path, 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero))
        {
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            ByHandleFileInformation information;
            if (!GetFileInformationByHandle(handle, out information)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return information.VolumeSerialNumber.ToString("X8") + ":" +
                information.FileIndexHigh.ToString("X8") + information.FileIndexLow.ToString("X8");
        }
    }
}
'@
}

$utf8NoBom = New-Object Text.UTF8Encoding($false)
$script:blockers = New-Object 'Collections.Generic.List[string]'
$script:blockerSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
$script:temporaryDirectories = New-Object 'Collections.Generic.List[object]'
$script:stagingRoot = $null
$script:stagedSevenZipExecutable = $null
$productionApprovalProfile = 'karon-v2.19.1-karon.2-non-runtime-v1'
$fixtureApprovalProfile = 'test-fixture-v1'
$productionManifestRelativePath = 'release/evidence/v2.19.1-karon.2/non-runtime-components.json'
$productionManifestProjectionSha256 = '6120601F62EA99F4A09C9C2491854DCE7A3F3F56687958D4109F51FD393EB5BD'

$approvedProductionComponents = @{
    'application' = [ordered]@{
        version = '2.19.1-karon.2'; sourceRepository = 'https://github.com/KaronLabs/ytdlp-korean-interface'; sourceCommit = '$APPLICATION_RELEASE_COMMIT'
        sourceTag = ''; sourceTagObject = ''; sourceTagPeeledCommit = ''; releaseTag = ''; licenseExpression = 'MIT'; artifacts = @()
    }
    'bit7z' = [ordered]@{
        version = '4.1.0'; sourceRepository = 'https://github.com/rikyoz/bit7z'; sourceCommit = 'c81c6c1cbf44e148cd4b06f4bb69d7ea1e299742'
        sourceTag = ''; sourceTagObject = ''; sourceTagPeeledCommit = ''; releaseTag = ''; licenseExpression = 'MPL-2.0'
        artifacts = @([ordered]@{ id = 'bit7z-source'; fileName = 'bit7z-c81c6c1cbf44e148cd4b06f4bb69d7ea1e299742.zip'; url = 'https://github.com/rikyoz/bit7z/archive/c81c6c1cbf44e148cd4b06f4bb69d7ea1e299742.zip'; sha256 = '6AF52B2E1B9895E8F1193728880206326161940E7A961E3162EC39752DBB3379'; length = 494710; format = 'zip'; includeInBundle = $true })
    }
    'cpm' = [ordered]@{
        version = '0.42.3'; sourceRepository = 'https://github.com/cpm-cmake/CPM.cmake'; sourceCommit = '49acea0d775087ace0522ee4cc5de45e3da094a8'
        sourceTag = 'v0.42.3'; sourceTagObject = ''; sourceTagPeeledCommit = '49acea0d775087ace0522ee4cc5de45e3da094a8'; releaseTag = ''; licenseExpression = 'MIT'
        artifacts = @(
            [ordered]@{ id = 'cpm-source'; fileName = 'cpm-49acea0d775087ace0522ee4cc5de45e3da094a8.zip'; url = 'https://github.com/cpm-cmake/CPM.cmake/archive/49acea0d775087ace0522ee4cc5de45e3da094a8.zip'; sha256 = '97D684CFB9E9F5EC37A2D52C737E24B75F2ABFDF2594E109718309CB7C0B8A33'; length = 168785; format = 'zip'; includeInBundle = $true },
            [ordered]@{ id = 'cpm-bootstrap'; fileName = 'CPM_0.42.3.cmake'; url = 'https://github.com/cpm-cmake/CPM.cmake/releases/download/v0.42.3/CPM.cmake'; sha256 = 'A609E875FD532B067174250F6ABBC3DAC22FE2D64869783FB1E80BDA1625C844'; length = 45045; format = 'text'; includeInBundle = $true }
        )
    }
    '7zip' = [ordered]@{
        version = '26.01'; sourceRepository = 'https://github.com/ip7z/7zip'; sourceCommit = '8c63d71ff886bda90c86db28466287f977374237'
        sourceTag = ''; sourceTagObject = ''; sourceTagPeeledCommit = ''; releaseTag = ''; licenseExpression = 'LGPL-2.1-or-later AND BSD-2-Clause AND BSD-3-Clause'
        artifacts = @([ordered]@{ id = 'sevenzip-source'; fileName = '7zip-8c63d71ff886bda90c86db28466287f977374237.zip'; url = 'https://github.com/ip7z/7zip/archive/8c63d71ff886bda90c86db28466287f977374237.zip'; sha256 = '01589AEDA50512955E66D360C6534B961EC95C51111A76E2FA2976A8DAA55271'; length = 2892293; format = 'zip'; includeInBundle = $true })
    }
    'nana' = [ordered]@{
        version = '1.7.4'; sourceRepository = 'https://github.com/cnjinhao/nana'; sourceCommit = '554c4fe87fc31b8ee104228e9117d545d34855b5'
        sourceTag = 'v1.7.4'; sourceTagObject = '324ab5bb2fdefe8be54b141dc12ba40a43c98815'; sourceTagPeeledCommit = '554c4fe87fc31b8ee104228e9117d545d34855b5'; releaseTag = ''; licenseExpression = 'BSL-1.0'
        artifacts = @([ordered]@{ id = 'nana-source'; fileName = 'nana-554c4fe87fc31b8ee104228e9117d545d34855b5.zip'; url = 'https://github.com/cnjinhao/nana/archive/554c4fe87fc31b8ee104228e9117d545d34855b5.zip'; sha256 = 'EF657036A4623BBB5C4E0DF4E8AA699DC6AC713CA4A6725B30D3FD8175C4C145'; length = 745596; format = 'zip'; includeInBundle = $true })
    }
    'libpng' = [ordered]@{
        version = '1.6.37'; sourceRepository = 'https://github.com/pnggroup/libpng'; sourceCommit = 'a40189cf881e9f0db80511c382292a5604c3c3d1'
        sourceTag = ''; sourceTagObject = ''; sourceTagPeeledCommit = ''; releaseTag = ''; licenseExpression = 'libpng-2.0'
        artifacts = @(
            [ordered]@{ id = 'libpng-source'; fileName = 'libpng-a40189cf881e9f0db80511c382292a5604c3c3d1.zip'; url = 'https://github.com/pnggroup/libpng/archive/a40189cf881e9f0db80511c382292a5604c3c3d1.zip'; sha256 = 'B3AF9E92167F9C4233482F49AFF02730B7DC3A275871CE637ED668413DA6283F'; length = 1803566; format = 'zip'; includeInBundle = $true },
            [ordered]@{ id = 'libpng-package'; fileName = 'libpng.static.1.6.37.nupkg'; url = 'https://api.nuget.org/v3-flatcontainer/libpng.static/1.6.37/libpng.static.1.6.37.nupkg'; sha256 = 'A5DD204D1CFB381A5BBE6E7FB8DDC3BF3ADE3818DDB177B6E23DFA495350CB68'; length = 325349; format = 'binary'; includeInBundle = $true }
        )
    }
    'zlib' = [ordered]@{
        version = '1.2.5'; sourceRepository = 'https://github.com/madler/zlib'; sourceCommit = '9712272c78b9d9c93746d9c8e156a3728c65ca72'
        sourceTag = ''; sourceTagObject = ''; sourceTagPeeledCommit = ''; releaseTag = ''; licenseExpression = 'Zlib'
        artifacts = @(
            [ordered]@{ id = 'zlib-source'; fileName = 'zlib-9712272c78b9d9c93746d9c8e156a3728c65ca72.zip'; url = 'https://github.com/madler/zlib/archive/9712272c78b9d9c93746d9c8e156a3728c65ca72.zip'; sha256 = '66FAA243EA50094C2B399F5644CD4AA6110E739EAE26800120124BBD1DA00535'; length = 703697; format = 'zip'; includeInBundle = $true },
            [ordered]@{ id = 'zlib-package'; fileName = 'zlib.static.1.2.5.nupkg'; url = 'https://api.nuget.org/v3-flatcontainer/zlib.static/1.2.5/zlib.static.1.2.5.nupkg'; sha256 = 'A2E4A9FD423F97ED8D7B46E6AFF120286E5A56ED90E8F2908231A116D81EEC5B'; length = 147388; format = 'binary'; includeInBundle = $true }
        )
    }
    'libjpeg-turbo' = [ordered]@{
        version = '3.1.2'; sourceRepository = 'https://github.com/libjpeg-turbo/libjpeg-turbo'; sourceCommit = '4e151a4ad91001b3aa8c2ece2205c15f487ce320'
        sourceTag = ''; sourceTagObject = ''; sourceTagPeeledCommit = ''; releaseTag = ''; licenseExpression = 'BSD-3-Clause AND IJG AND Zlib'
        artifacts = @([ordered]@{ id = 'libjpeg-turbo-source'; fileName = 'libjpeg-turbo-4e151a4ad91001b3aa8c2ece2205c15f487ce320.zip'; url = 'https://github.com/libjpeg-turbo/libjpeg-turbo/archive/4e151a4ad91001b3aa8c2ece2205c15f487ce320.zip'; sha256 = 'D3C33405B46AA14094EF26CD7B9618162EBCAFEED7FB2ACF2FDA5C7C10B80782'; length = 3033904; format = 'zip'; includeInBundle = $true })
    }
    'nlohmann-json' = [ordered]@{
        version = '3.12.0'; sourceRepository = 'https://github.com/nlohmann/json'; sourceCommit = '55f93686c01528224f448c19128836e7df245f72'
        sourceTag = ''; sourceTagObject = ''; sourceTagPeeledCommit = ''; releaseTag = ''; licenseExpression = 'MIT'
        artifacts = @([ordered]@{ id = 'nlohmann-source'; fileName = 'nlohmann-json-55f93686c01528224f448c19128836e7df245f72.zip'; url = 'https://github.com/nlohmann/json/archive/55f93686c01528224f448c19128836e7df245f72.zip'; sha256 = '0746352E4E9532E7AEABBCBAA79079B6BC6008E9261E4D459C9486A9B48A172E'; length = 10243783; format = 'zip'; includeInBundle = $true })
    }
    'yt-dlp' = [ordered]@{
        version = '2026.08.30.232658'; sourceRepository = 'https://github.com/yt-dlp/yt-dlp'; sourceCommit = 'bbc809a1161d3bfca51fa36f59dda35556ee85a0'
        sourceTag = ''; sourceTagObject = ''; sourceTagPeeledCommit = ''; releaseTag = '2026.08.30.232658'; licenseExpression = 'Unlicense AND LicenseRef-yt-dlp-PyInstaller-Third-Party'
        artifacts = @(
            [ordered]@{ id = 'yt-dlp-source'; fileName = 'yt-dlp-bbc809a1161d3bfca51fa36f59dda35556ee85a0.zip'; url = 'https://github.com/yt-dlp/yt-dlp/archive/bbc809a1161d3bfca51fa36f59dda35556ee85a0.zip'; sha256 = '62A651DE6FFCD3631CA34F0F617932BDEDC4A6BE652777ACAE8A11D1CAFD172B'; length = 3854279; format = 'zip'; includeInBundle = $true },
            [ordered]@{ id = 'yt-dlp-binary'; fileName = 'yt-dlp-2026.08.30.232658.exe'; url = 'https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/download/2026.08.30.232658/yt-dlp.exe'; sha256 = 'A3A504C66E91F6474CEF0BE83B16AEDFB7B42B9400A962242D0D433E98F67A70'; length = 17842860; format = 'binary'; includeInBundle = $false },
            [ordered]@{ id = 'yt-dlp-sums'; fileName = 'yt-dlp-2026.08.30.232658-SHA2-256SUMS'; url = 'https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/download/2026.08.30.232658/SHA2-256SUMS'; sha256 = 'E5384D809D9C6D70E80996AA6728620C660165930CA3C7BC08AD1D755261293E'; length = 1505; format = 'text'; includeInBundle = $true }
        )
    }
}

function Add-EvidenceBlocker {
    param([Parameter(Mandatory = $true)] [string] $Code)
    if ($script:blockerSet.Add($Code)) { $script:blockers.Add($Code) }
}

function Get-ObjectProperty {
    param([object] $Value, [string] $Name)
    if ($null -eq $Value) { return $null }
    if ($Value -is [Collections.IDictionary] -and $Value.Contains($Name)) { return $Value[$Name] }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-ProductionComponentApproval {
    param([object] $Component)
    $id = [string]$Component.id
    if (-not $approvedProductionComponents.ContainsKey($id)) { return $false }
    $expected = $approvedProductionComponents[$id]
    foreach ($field in @('version', 'sourceRepository', 'sourceCommit', 'sourceTag', 'sourceTagObject', 'sourceTagPeeledCommit', 'licenseExpression')) {
        if ([string](Get-ObjectProperty $Component $field) -cne [string](Get-ObjectProperty $expected $field)) { return $false }
    }
    if ([string](Get-ObjectProperty $expected 'releaseTag') -cne [string](Get-ObjectProperty (Get-ObjectProperty $Component 'binaryProvenance') 'releaseTag')) { return $false }
    $actualArtifacts = @($Component.sourceArtifacts)
    $expectedArtifacts = @($expected.artifacts)
    if ($actualArtifacts.Count -ne $expectedArtifacts.Count) { return $false }
    foreach ($approved in $expectedArtifacts) {
        $actual = @($actualArtifacts | Where-Object { [string]$_.id -ceq [string]$approved.id })
        if ($actual.Count -ne 1) { return $false }
        foreach ($field in @('fileName', 'url', 'format')) {
            if ([string](Get-ObjectProperty $actual[0] $field) -cne [string](Get-ObjectProperty $approved $field)) { return $false }
        }
        if (([string]$actual[0].sha256).ToUpperInvariant() -cne ([string]$approved.sha256).ToUpperInvariant() -or
            [long]$actual[0].length -ne [long]$approved.length -or [bool]$actual[0].includeInBundle -ne [bool]$approved.includeInBundle) { return $false }
    }
    return $true
}

function Test-FixtureComponentApproval {
    param([object] $Component)
    $id = [string]$Component.id
    $commitA = '1111111111111111111111111111111111111111'
    $commitB = '2222222222222222222222222222222222222222'
    $expectedVersion = switch ($id) {
        'application' { '2.19.1-karon.2' } 'bit7z' { '4.1.0' } 'cpm' { '0.42.3' } '7zip' { '26.01' }
        'nana' { '1.0' } 'libpng' { '1.0' } 'zlib' { '1.0' } 'libjpeg-turbo' { '1.0' }
        'nlohmann-json' { '3.12.0' } 'yt-dlp' { '2026.08.30.232658' } default { return $false }
    }
    $expectedRepository = if ($id -ceq 'application') { 'https://github.com/KaronLabs/ytdlp-korean-interface' } else { 'https://github.com/example/' + $id }
    $expectedCommit = if ($id -ceq 'application') { '$APPLICATION_RELEASE_COMMIT' } elseif ($id -ceq 'yt-dlp') { $commitB } else { $commitA }
    return [string]$Component.version -ceq $expectedVersion -and [string]$Component.sourceRepository -ceq $expectedRepository -and [string]$Component.sourceCommit -ceq $expectedCommit
}

function Test-ComponentApproval {
    param([object] $Component, [string] $Profile)
    if ($Profile -ceq $productionApprovalProfile) { return Test-ProductionComponentApproval $Component }
    if ($Profile -ceq $fixtureApprovalProfile) { return Test-FixtureComponentApproval $Component }
    return $false
}

function Get-BytesSha256 {
    param([Parameter(Mandatory = $true)] [byte[]] $Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToUpperInvariant() }
    finally { $sha.Dispose() }
}

function Read-BoundedPrivateFileBytes {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][long] $MaximumLength,
        [Parameter(Mandatory = $true)][string] $Label
    )
    [void](Assert-ReparseFreePath -Path $Path -Label $Label)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        $length = $stream.Length
        if ($length -le 0 -or $length -gt $MaximumLength -or $length -gt [int]::MaxValue) { throw ($Label + '_size_invalid') }
        $bytes = New-Object byte[] ([int]$length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -le 0) { throw ($Label + '_read_incomplete') }
            $offset += $read
        }
        if ($stream.ReadByte() -ne -1) { throw ($Label + '_length_changed') }
        return ,$bytes
    }
    finally {
        $stream.Dispose()
    }
}

function Get-PathSha256 {
    param([Parameter(Mandatory = $true)] [string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function ConvertTo-CanonicalJsonBytes {
    param([Parameter(Mandatory = $true)] [object] $Value)
    return $utf8NoBom.GetBytes(($Value | ConvertTo-Json -Depth 50 -Compress) + [char]10)
}

function Add-ManifestProjectionToken {
    param([object] $Value, [Collections.Generic.List[string]] $Rows)
    if ($null -eq $Value) { $Rows.Add('N'); return }
    if ($Value -is [bool]) { $Rows.Add($(if ($Value) { 'B:1' } else { 'B:0' })); return }
    if ($Value -is [string]) { $Rows.Add('S:' + [Convert]::ToBase64String($utf8NoBom.GetBytes($Value))); return }
    if ($Value -is [Collections.IDictionary]) {
        $keys = @($Value.Keys | ForEach-Object { [string]$_ })
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        $Rows.Add('O:' + $keys.Count)
        foreach ($key in $keys) {
            $Rows.Add('K:' + [Convert]::ToBase64String($utf8NoBom.GetBytes($key)))
            Add-ManifestProjectionToken $Value[$key] $Rows
        }
        return
    }
    if ($Value -is [Collections.IEnumerable]) {
        $items = @($Value)
        $Rows.Add('A:' + $items.Count)
        foreach ($item in $items) { Add-ManifestProjectionToken $item $Rows }
        return
    }
    if ($Value -is [ValueType]) {
        $Rows.Add('I:' + $Value.ToString([Globalization.CultureInfo]::InvariantCulture))
        return
    }
    $names = @($Value.PSObject.Properties | ForEach-Object { $_.Name })
    [Array]::Sort($names, [StringComparer]::Ordinal)
    $Rows.Add('O:' + $names.Count)
    foreach ($name in $names) {
        $Rows.Add('K:' + [Convert]::ToBase64String($utf8NoBom.GetBytes($name)))
        Add-ManifestProjectionToken $Value.$name $Rows
    }
}

function Get-ManifestProjectionSha256 {
    param([object] $Manifest)
    $rows = New-Object 'Collections.Generic.List[string]'
    Add-ManifestProjectionToken $Manifest $rows
    return Get-BytesSha256 $utf8NoBom.GetBytes(($rows.ToArray() -join [char]10) + [char]10)
}

function Test-ProductionManifestGitBinding {
    param([string] $OriginalManifestPath, [string] $Repository)
    try {
        $repositoryRoot = (@(& git -C $Repository rev-parse --show-toplevel 2>$null) -join '').Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) { throw 'repository-root' }
        $expectedPath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $productionManifestRelativePath.Replace('/', '\')))
        $actualPath = [IO.Path]::GetFullPath($OriginalManifestPath)
        if (-not $actualPath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
            Add-EvidenceBlocker 'production_manifest_path_invalid'
            return
        }
        $tracked = @(& git -C $repositoryRoot ls-files --full-name -- $productionManifestRelativePath 2>$null)
        if ($LASTEXITCODE -ne 0 -or $tracked.Count -ne 1 -or [string]$tracked[0] -cne $productionManifestRelativePath) {
            Add-EvidenceBlocker 'production_manifest_path_invalid'
            return
        }
        $headBlob = (@(& git -C $repositoryRoot rev-parse ('HEAD:' + $productionManifestRelativePath) 2>$null) -join '').Trim()
        $workingBlob = (@(& git -C $repositoryRoot hash-object --no-filters -- $actualPath 2>$null) -join '').Trim()
        if ($LASTEXITCODE -ne 0 -or $headBlob -notmatch '^[0-9a-f]{40}$' -or $workingBlob -cne $headBlob) {
            Add-EvidenceBlocker 'production_manifest_git_blob_mismatch'
        }
    }
    catch { Add-EvidenceBlocker 'production_manifest_git_blob_mismatch' }
}

function Write-AtomicBytes {
    param([string] $Path, [byte[]] $Bytes)
    if (Test-Path -LiteralPath $Path) { throw "output_exists:$Path" }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    $partial = $Path + '.partial.' + $PID + '.' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllBytes($partial, $Bytes)
        [IO.File]::Move($partial, $Path)
    }
    finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    }
}

function Assert-ReparseFreePath {
    param([string] $Path, [string] $Label)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '^(?i)\\\\[?.]\\|^\\\?\?\\') { throw ('unsafe_reparse_path:' + $Label) }
    $full = [IO.Path]::GetFullPath($Path)
    $current = $full
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('unsafe_reparse_path:' + $Label) }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -ceq $current) { break }
        $current = $parent
    }
    return $full
}

function Assert-WindowsPathSegment {
    param([string] $Segment)
    if ([string]::IsNullOrEmpty($Segment) -or $Segment -ceq '.' -or $Segment -ceq '..') { throw 'windows_path_segment_invalid' }
    if ($Segment -match '[<>:"/\\|?*\x00-\x1f]' -or $Segment.TrimEnd(' ', '.') -cne $Segment) { throw 'windows_path_segment_invalid' }
    $canonical = $Segment.Normalize([Text.NormalizationForm]::FormC)
    if ($canonical -cne $Segment) { throw 'windows_path_segment_not_nfc' }
    if ($canonical -match '^(?i)(CON|PRN|AUX|NUL|CLOCK\$|CONIN\$|CONOUT\$|COM[1-9\u00B9\u00B2\u00B3]|LPT[1-9\u00B9\u00B2\u00B3])(?:\..*)?$') {
        throw 'windows_path_segment_reserved'
    }
    return $canonical
}

function Test-SafeLeafFileName {
    param([string] $Name)
    try { return (Assert-WindowsPathSegment $Name) -ceq $Name }
    catch { return $false }
}

function Get-DirectChildPath {
    param([string] $Root, [string] $Leaf)
    if (-not (Test-SafeLeafFileName $Leaf)) { throw 'unsafe_leaf_file_name' }
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $path = [IO.Path]::GetFullPath((Join-Path $rootFull $Leaf))
    if ((Split-Path -Parent $path).TrimEnd('\', '/') -ine $rootFull) { throw 'unsafe_leaf_file_name' }
    return $path
}

function Copy-InputToPrivateStaging {
    param([string] $SourcePath, [string] $RelativePath, [string] $Label)
    $sourceFull = Assert-ReparseFreePath -Path $SourcePath -Label $Label
    if (-not (Test-Path -LiteralPath $sourceFull -PathType Leaf)) { throw ('input_missing:' + $Label) }
    if ([string]::IsNullOrWhiteSpace($script:stagingRoot)) { throw 'private_staging_unavailable' }
    Assert-OwnedTemporaryDirectory $script:stagingRoot
    $destination = [IO.Path]::GetFullPath((Join-Path $script:stagingRoot $RelativePath))
    if (-not (Test-ChildPath -Root $script:stagingRoot -Path $destination)) { throw ('private_staging_escape:' + $Label) }
    $parent = Split-Path -Parent $destination
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    [void](Assert-ReparseFreePath -Path $parent -Label 'private-staging')
    $inputStream = [IO.File]::Open($sourceFull, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $outputStream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $inputStream.CopyTo($outputStream) }
        finally { $outputStream.Dispose() }
    }
    finally { $inputStream.Dispose() }
    [void](Assert-ReparseFreePath -Path $destination -Label 'private-staging')
    return $destination
}

function Get-OwnedTemporaryDirectory {
    param([string] $Path)
    return @($script:temporaryDirectories | Where-Object { [string]$_.path -ceq [IO.Path]::GetFullPath($Path) }) | Select-Object -First 1
}

function Assert-OwnedTemporaryDirectory {
    param([string] $Path)
    $record = Get-OwnedTemporaryDirectory $Path
    if ($null -eq $record -or -not (Test-Path -LiteralPath $record.path -PathType Container)) { throw 'private_staging_ownership_mismatch' }
    [void](Assert-ReparseFreePath -Path $record.path -Label 'private-staging')
    if ([KaronEvidenceDirectoryIdentity]::Get($record.path) -cne [string]$record.identity -or
        -not (Test-Path -LiteralPath $record.markerPath -PathType Leaf)) { throw 'private_staging_ownership_mismatch' }
    [void](Assert-ReparseFreePath -Path $record.markerPath -Label 'private-staging-marker')
    $marker = Get-Content -LiteralPath $record.markerPath -Raw | ConvertFrom-Json
    if ([string]$marker.token -cne [string]$record.token -or [string]$marker.identity -cne [string]$record.identity) {
        throw 'private_staging_ownership_mismatch'
    }
}

function New-TemporaryDirectory {
    param([string] $Label)
    $tempRoot = Assert-ReparseFreePath -Path ([IO.Path]::GetTempPath()) -Label 'private-staging'
    $suffix = [Guid]::NewGuid().ToString('N')
    $creating = Join-Path $tempRoot ('karon-private-creating-' + $suffix)
    $path = Join-Path $tempRoot ('karon-' + $Label + '-' + $suffix)
    [IO.Directory]::CreateDirectory($creating) | Out-Null
    [void](Assert-ReparseFreePath -Path $creating -Label 'private-staging')
    $identity = [KaronEvidenceDirectoryIdentity]::Get($creating)
    $token = [Guid]::NewGuid().ToString('N')
    $markerName = '.karon-owner-' + $token + '.json'
    $markerCreating = Join-Path $creating $markerName
    [IO.File]::WriteAllBytes($markerCreating, (ConvertTo-CanonicalJsonBytes ([ordered]@{ token = $token; identity = $identity })))
    [IO.Directory]::Move($creating, $path)
    $markerPath = Join-Path $path $markerName
    [void](Assert-ReparseFreePath -Path $path -Label 'private-staging')
    if ([KaronEvidenceDirectoryIdentity]::Get($path) -cne $identity) { throw 'private_staging_ownership_mismatch' }
    $script:temporaryDirectories.Add([pscustomobject]@{ path = $path; token = $token; identity = $identity; markerPath = $markerPath })
    return $path
}

function Test-ChildPath {
    param([string] $Root, [string] $Path)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $pathFull = [IO.Path]::GetFullPath($Path)
    return $pathFull.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Test-ImmutableSourceUrl {
    param([string] $Url)
    if ([string]::IsNullOrWhiteSpace($Url) -or $Url -notmatch '^https://') { return $false }
    if ($Url -match '(?i)/(?:main|master|latest)(?:[./]|$)') { return $false }
    if ($Url -match '(?i)^https://github\.com/[^/]+/[^/]+/archive/[0-9a-f]{40}\.zip$') { return $true }
    if ($Url -match '(?i)^https://raw\.githubusercontent\.com/[^/]+/[^/]+/[0-9a-f]{40}/.+$') { return $true }
    if ($Url -match '(?i)^https://github\.com/[^/]+/[^/]+/releases/download/[^/?#]+/[^?#]+$') { return $true }
    if ($Url -match '(?i)^https://api\.nuget\.org/v3-flatcontainer/[a-z0-9_.-]+/[0-9]+(?:\.[0-9]+){1,3}/[a-z0-9_.-]+\.nupkg$') { return $true }
    return $false
}

function Assert-SafeArchiveEntryName {
    param([string] $Name, [object] $ExactNames, [object] $CaseInsensitiveNames)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.StartsWith('/') -or $Name.StartsWith('\') -or $Name -match '^[A-Za-z]:' -or $Name -match '[\x00-\x1f]') { throw 'archive_entry_path_invalid' }
    $normalized = $Name.Replace('\', '/')
    $directory = $normalized.EndsWith('/')
    $trimmed = if ($directory) { $normalized.Substring(0, $normalized.Length - 1) } else { $normalized }
    if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.EndsWith('/')) { throw 'archive_entry_path_invalid' }
    $segments = New-Object 'Collections.Generic.List[string]'
    try { foreach ($segment in $trimmed.Split('/')) { $segments.Add((Assert-WindowsPathSegment $segment)) } }
    catch { throw 'archive_entry_path_invalid' }
    $canonical = $segments.ToArray() -join '/'
    if (-not $ExactNames.Add($canonical)) { throw 'archive_entry_duplicate' }
    if (-not $CaseInsensitiveNames.Add($canonical.ToUpperInvariant())) { throw 'archive_entry_case_collision' }
    return $canonical + $(if ($directory) { '/' } else { '' })
}

function Get-RawZipDirectoryEntries {
    param([string] $ArchivePath)
    $bytes = [IO.File]::ReadAllBytes($ArchivePath)
    $minimum = [Math]::Max(0, $bytes.Length - 65557)
    $eocd = -1
    for ($offset = $bytes.Length - 22; $offset -ge $minimum; $offset--) {
        if ([BitConverter]::ToUInt32($bytes, $offset) -eq 0x06054B50) { $eocd = $offset; break }
    }
    if ($eocd -lt 0) { throw 'zip_central_directory_missing' }
    $count = [BitConverter]::ToUInt16($bytes, $eocd + 10)
    $centralOffset = [BitConverter]::ToUInt32($bytes, $eocd + 16)
    if ($count -eq 0xFFFF -or $centralOffset -eq 0xFFFFFFFF) { throw 'zip64_not_supported' }
    $entries = New-Object 'Collections.Generic.List[object]'
    $offset = [int64]$centralOffset
    for ($index = 0; $index -lt $count; $index++) {
        if ($offset -lt 0 -or $offset + 46 -gt $bytes.Length -or [BitConverter]::ToUInt32($bytes, [int]$offset) -ne 0x02014B50) {
            throw 'zip_central_directory_invalid'
        }
        $flags = [BitConverter]::ToUInt16($bytes, [int]$offset + 8)
        $nameLength = [BitConverter]::ToUInt16($bytes, [int]$offset + 28)
        $extraLength = [BitConverter]::ToUInt16($bytes, [int]$offset + 30)
        $commentLength = [BitConverter]::ToUInt16($bytes, [int]$offset + 32)
        $externalAttributes = [BitConverter]::ToUInt32($bytes, [int]$offset + 38)
        $next = $offset + 46 + $nameLength + $extraLength + $commentLength
        if ($nameLength -eq 0 -or $next -gt $bytes.Length) { throw 'zip_central_directory_invalid' }
        $encoding = if (($flags -band 0x0800) -ne 0) { [Text.Encoding]::UTF8 } else { [Text.Encoding]::GetEncoding(437) }
        $name = $encoding.GetString($bytes, [int]$offset + 46, $nameLength)
        $entries.Add([ordered]@{ name = $name; externalAttributes = $externalAttributes })
        $offset = $next
    }
    return $entries.ToArray()
}

function Assert-ZipArchivePreflight {
    param([string] $ArchivePath)
    $exactNames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $caseNames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $rawEntries = @(Get-RawZipDirectoryEntries $ArchivePath)
    foreach ($entry in $rawEntries) {
        [void](Assert-SafeArchiveEntryName -Name ([string]$entry.name) -ExactNames $exactNames -CaseInsensitiveNames $caseNames)
        $attributes = [uint32]$entry.externalAttributes
        $unixType = ($attributes -shr 16) -band 0xF000
        if ($unixType -eq 0xA000 -or ($attributes -band [uint32][IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'archive_link_or_reparse_entry' }
    }
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        if ($archive.Entries.Count -ne $rawEntries.Count) { throw 'zip_managed_entry_projection_mismatch' }
        for ($index = 0; $index -lt $rawEntries.Count; $index++) {
            if ([string]$archive.Entries[$index].FullName -cne [string]$rawEntries[$index].name) { throw 'zip_managed_entry_projection_mismatch' }
        }
    }
    finally { $archive.Dispose() }
}

function Assert-SevenZipArchivePreflight {
    param([string] $ArchivePath)
    if ([string]::IsNullOrWhiteSpace($script:stagedSevenZipExecutable) -or -not (Test-Path -LiteralPath $script:stagedSevenZipExecutable -PathType Leaf)) { throw 'sevenzip_extractor_required' }
    $lines = @(& $script:stagedSevenZipExecutable 'l' '-slt' '-ba' $ArchivePath 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('sevenzip_list_failed:' + $LASTEXITCODE) }
    $exactNames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $caseNames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in $lines) {
        $text = [string]$line
        if ($text -match '^Path = (.*)$') { [void](Assert-SafeArchiveEntryName -Name $Matches[1] -ExactNames $exactNames -CaseInsensitiveNames $caseNames) }
        elseif ($text -match '^Attributes = (.*)$' -and $Matches[1] -match '(?i)L|REPARSE|LINK') { throw 'archive_link_or_reparse_entry' }
        elseif ($text -match '^(?:Symbolic Link|Hard Link|Reparse Point) = .+$') { throw 'archive_link_or_reparse_entry' }
    }
}

function Assert-ArchivePreflight {
    param([string] $ArchivePath, [string] $Format)
    if ($Format -ceq 'zip' -or [IO.Path]::GetExtension($ArchivePath) -ieq '.nupkg') { Assert-ZipArchivePreflight $ArchivePath; return }
    if ($Format -ceq '7z') { Assert-SevenZipArchivePreflight $ArchivePath; return }
}

function Get-ZipEntryBytes {
    param([string] $ArchivePath, [string] $EntryPath)
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $matches = @($archive.Entries | Where-Object { $_.FullName -ceq $EntryPath })
        if ($matches.Count -ne 1) { return $null }
        $memory = New-Object IO.MemoryStream
        $stream = $matches[0].Open()
        try { $stream.CopyTo($memory) }
        finally { $stream.Dispose() }
        return ,$memory.ToArray()
    }
    finally { $archive.Dispose() }
}

function Expand-SafeZip {
    param([string] $ArchivePath, [string] $Destination)
    Assert-ZipArchivePreflight $ArchivePath
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    $names = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ([string]::IsNullOrWhiteSpace($name) -or $name.StartsWith('/') -or $name -match '(^|/)\.\.(/|$)' -or -not $names.Add($name)) {
                throw 'archive_path_or_case_collision'
            }
            if ($name.EndsWith('/')) { continue }
            $target = [IO.Path]::GetFullPath((Join-Path $Destination $name.Replace('/', '\')))
            if (-not (Test-ChildPath -Root $Destination -Path $target)) { throw 'archive_path_escape' }
            [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
            $source = $entry.Open()
            $output = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $source.CopyTo($output) }
            finally { $output.Dispose(); $source.Dispose() }
        }
    }
    finally { $archive.Dispose() }
}

function Expand-EvidenceArchive {
    param([string] $ArchivePath, [string] $Format, [string] $Destination)
    if ($Format -ceq 'zip') { Expand-SafeZip -ArchivePath $ArchivePath -Destination $Destination; return }
    if ($Format -cne '7z' -or [string]::IsNullOrWhiteSpace($script:stagedSevenZipExecutable) -or -not (Test-Path -LiteralPath $script:stagedSevenZipExecutable -PathType Leaf)) {
        throw 'sevenzip_extractor_required'
    }
    Assert-SevenZipArchivePreflight $ArchivePath
    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    & $script:stagedSevenZipExecutable 'x' '-y' ('-o' + $Destination) $ArchivePath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "sevenzip_extract_failed:$LASTEXITCODE" }
    foreach ($entry in @(Get-ChildItem -LiteralPath $Destination -Force -Recurse)) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or -not (Test-ChildPath -Root $Destination -Path $entry.FullName)) {
            throw 'archive_reparse_or_escape'
        }
    }
}

function Get-OrderedTreeEvidence {
    param([string] $Root)
    $basePath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $basePrefix = $basePath + [IO.Path]::DirectorySeparatorChar
    $files = @(Get-ChildItem -LiteralPath $basePath -File -Recurse)
    $rows = New-Object 'Collections.Generic.List[string]'
    foreach ($file in $files) {
        $fullPath = [IO.Path]::GetFullPath($file.FullName)
        if (-not $fullPath.StartsWith($basePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Tree file escaped root: $fullPath"
        }
        $relative = $fullPath.Substring($basePrefix.Length).Replace('\', '/')
        $rows.Add($relative + [char]0 + $file.Length + [char]0 + (Get-PathSha256 $file.FullName).ToLowerInvariant() + [char]10)
    }
    $ordered = $rows.ToArray()
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    $length = [long](($files | Measure-Object Length -Sum).Sum)
    if ($files.Count -eq 0) { $length = 0 }
    return [ordered]@{
        fileCount = $files.Count
        length = $length
        orderedTreeSha256 = Get-BytesSha256 $utf8NoBom.GetBytes(($ordered -join ''))
    }
}

function Get-OrderedChunkDigest {
    param([byte[]] $Bytes)
    $rows = New-Object 'Collections.Generic.List[string]'
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $chunkSize = 65536
        $index = 0
        for ($offset = 0; $offset -lt $Bytes.Length; $offset += $chunkSize) {
            $length = [Math]::Min($chunkSize, $Bytes.Length - $offset)
            $chunk = New-Object byte[] $length
            [Array]::Copy($Bytes, $offset, $chunk, 0, $length)
            $chunkHash = ([BitConverter]::ToString($sha.ComputeHash($chunk))).Replace('-', '').ToLowerInvariant()
            $rows.Add($index.ToString('D8') + [char]0 + $length + [char]0 + $chunkHash + "`r`n")
            $index++
        }
        return ([BitConverter]::ToString($sha.ComputeHash($utf8NoBom.GetBytes(($rows -join ''))))).Replace('-', '').ToUpperInvariant()
    }
    finally { $sha.Dispose() }
}

function Test-FileIdentity {
    param([string] $Path, [string] $ExpectedSha256, [long] $ExpectedLength)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $file = Get-Item -LiteralPath $Path
    return $file.Length -eq $ExpectedLength -and (Get-PathSha256 $Path) -ceq $ExpectedSha256.ToUpperInvariant()
}

function Acquire-SourceArtifact {
    param([object] $Artifact, [string] $Destination)
    [void](Assert-ReparseFreePath -Path (Split-Path -Parent $Destination) -Label 'source-cache')
    if (Test-Path -LiteralPath $Destination) { [void](Assert-ReparseFreePath -Path $Destination -Label 'source-cache'); return }
    if (-not $AcquireSources) { return }
    $partial = $Destination + '.partial.' + $PID + '.' + [Guid]::NewGuid().ToString('N')
    try {
        Invoke-WebRequest -UseBasicParsing -Uri ([string]$Artifact.url) -OutFile $partial
        if (-not (Test-FileIdentity -Path $partial -ExpectedSha256 ([string]$Artifact.sha256) -ExpectedLength ([long]$Artifact.length))) {
            throw 'downloaded_source_identity_mismatch'
        }
        try { [IO.File]::Move($partial, $Destination) }
        catch {
            if (-not (Test-FileIdentity -Path $Destination -ExpectedSha256 ([string]$Artifact.sha256) -ExpectedLength ([long]$Artifact.length))) { throw }
        }
    }
    finally { if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue } }
}

function Copy-StreamWithSha256 {
    param([IO.Stream] $Source, [IO.Stream] $Destination)
    $sha = [Security.Cryptography.SHA256]::Create()
    $buffer = New-Object byte[] 65536
    $length = [long]0
    try {
        while (($read = $Source.Read($buffer, 0, $buffer.Length)) -gt 0) {
            [void]$sha.TransformBlock($buffer, 0, $read, $buffer, 0)
            if ($null -ne $Destination) { $Destination.Write($buffer, 0, $read) }
            $length += $read
        }
        [void]$sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        return [ordered]@{ sha256 = ([BitConverter]::ToString($sha.Hash)).Replace('-', ''); length = $length }
    }
    finally { $sha.Dispose() }
}

function Skip-EvidenceJsonWhitespace {
    param([string] $Text, [ref] $Index)

    while ($Index.Value -lt $Text.Length) {
        $character = $Text[$Index.Value]
        if ($character -ne ' ' -and $character -ne "`t" -and $character -ne "`r" -and $character -ne "`n") { return }
        $Index.Value++
    }
}

function Read-EvidenceJsonString {
    param([string] $Text, [ref] $Index)

    if ($Index.Value -ge $Text.Length -or $Text[$Index.Value] -ne '"') { throw 'bundle_candidate_inventory_mismatch' }
    $Index.Value++
    $builder = New-Object Text.StringBuilder
    while ($Index.Value -lt $Text.Length) {
        $character = $Text[$Index.Value]
        $Index.Value++
        if ($character -eq '"') { return $builder.ToString() }
        if ([int][char]$character -lt 0x20) { throw 'bundle_candidate_inventory_mismatch' }
        if ($character -ne '\') {
            [void]$builder.Append($character)
            continue
        }
        if ($Index.Value -ge $Text.Length) { throw 'bundle_candidate_inventory_mismatch' }
        $escape = $Text[$Index.Value]
        $Index.Value++
        switch ($escape) {
            '"' { [void]$builder.Append([char]0x22); continue }
            '\' { [void]$builder.Append([char]0x5C); continue }
            '/' { [void]$builder.Append([char]0x2F); continue }
            'b' { [void]$builder.Append([char]0x08); continue }
            'f' { [void]$builder.Append([char]0x0C); continue }
            'n' { [void]$builder.Append([char]0x0A); continue }
            'r' { [void]$builder.Append([char]0x0D); continue }
            't' { [void]$builder.Append([char]0x09); continue }
            'u' {
                if ($Index.Value + 4 -gt $Text.Length) { throw 'bundle_candidate_inventory_mismatch' }
                $codeUnit = 0
                if (-not [int]::TryParse(
                    $Text.Substring($Index.Value, 4),
                    [Globalization.NumberStyles]::HexNumber,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [ref]$codeUnit
                )) { throw 'bundle_candidate_inventory_mismatch' }
                $Index.Value += 4
                $decoded = [char]$codeUnit
                if ([char]::IsHighSurrogate($decoded)) {
                    if ($Index.Value + 6 -gt $Text.Length -or
                        $Text[$Index.Value] -ne '\' -or $Text[$Index.Value + 1] -ne 'u') {
                        throw 'bundle_candidate_inventory_mismatch'
                    }
                    $lowCodeUnit = 0
                    if (-not [int]::TryParse(
                        $Text.Substring($Index.Value + 2, 4),
                        [Globalization.NumberStyles]::HexNumber,
                        [Globalization.CultureInfo]::InvariantCulture,
                        [ref]$lowCodeUnit
                    )) { throw 'bundle_candidate_inventory_mismatch' }
                    $lowDecoded = [char]$lowCodeUnit
                    if (-not [char]::IsLowSurrogate($lowDecoded)) { throw 'bundle_candidate_inventory_mismatch' }
                    [void]$builder.Append($decoded)
                    [void]$builder.Append($lowDecoded)
                    $Index.Value += 6
                    continue
                }
                if ([char]::IsLowSurrogate($decoded)) { throw 'bundle_candidate_inventory_mismatch' }
                [void]$builder.Append($decoded)
                continue
            }
            default { throw 'bundle_candidate_inventory_mismatch' }
        }
    }
    throw 'bundle_candidate_inventory_mismatch'
}

function Skip-EvidenceJsonValue {
    param([string] $Text, [ref] $Index)

    Skip-EvidenceJsonWhitespace -Text $Text -Index $Index
    if ($Index.Value -ge $Text.Length) { throw 'bundle_candidate_inventory_mismatch' }
    $first = $Text[$Index.Value]
    if ($first -eq '"') {
        [void](Read-EvidenceJsonString -Text $Text -Index $Index)
        return
    }
    if ($first -eq '{' -or $first -eq '[') {
        $stack = New-Object 'Collections.Generic.Stack[char]'
        $stack.Push($first)
        $Index.Value++
        while ($Index.Value -lt $Text.Length) {
            $character = $Text[$Index.Value]
            if ($character -eq '"') {
                [void](Read-EvidenceJsonString -Text $Text -Index $Index)
                continue
            }
            if ($character -eq '{' -or $character -eq '[') {
                $stack.Push($character)
                $Index.Value++
                continue
            }
            if ($character -eq '}' -or $character -eq ']') {
                if ($stack.Count -eq 0) { throw 'bundle_candidate_inventory_mismatch' }
                $opening = $stack.Pop()
                if (($opening -eq '{' -and $character -ne '}') -or
                    ($opening -eq '[' -and $character -ne ']')) {
                    throw 'bundle_candidate_inventory_mismatch'
                }
                $Index.Value++
                if ($stack.Count -eq 0) { return }
                continue
            }
            $Index.Value++
        }
        throw 'bundle_candidate_inventory_mismatch'
    }

    $start = $Index.Value
    while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -ne ',' -and $Text[$Index.Value] -ne '}') {
        $Index.Value++
    }
    $end = $Index.Value
    while ($end -gt $start) {
        $character = $Text[$end - 1]
        if ($character -ne ' ' -and $character -ne "`t" -and $character -ne "`r" -and $character -ne "`n") { break }
        $end--
    }
    if ($end -eq $start) { throw 'bundle_candidate_inventory_mismatch' }
}

function Assert-UniqueCandidateInventoryIdentityProperties {
    param([string] $JsonText)

    try {
        $index = 0
        Skip-EvidenceJsonWhitespace -Text $JsonText -Index ([ref]$index)
        if ($index -ge $JsonText.Length -or $JsonText[$index] -ne '{') { throw 'bundle_candidate_inventory_mismatch' }
        $index++
        $shaCount = 0
        $lengthCount = 0
        while ($true) {
            Skip-EvidenceJsonWhitespace -Text $JsonText -Index ([ref]$index)
            if ($index -ge $JsonText.Length) { throw 'bundle_candidate_inventory_mismatch' }
            if ($JsonText[$index] -eq '}') {
                $index++
                break
            }
            $propertyName = Read-EvidenceJsonString -Text $JsonText -Index ([ref]$index)
            if ($propertyName -ceq 'candidateManifestSha256') { $shaCount++ }
            if ($propertyName -ceq 'candidateManifestLength') { $lengthCount++ }
            Skip-EvidenceJsonWhitespace -Text $JsonText -Index ([ref]$index)
            if ($index -ge $JsonText.Length -or $JsonText[$index] -ne ':') { throw 'bundle_candidate_inventory_mismatch' }
            $index++
            Skip-EvidenceJsonValue -Text $JsonText -Index ([ref]$index)
            Skip-EvidenceJsonWhitespace -Text $JsonText -Index ([ref]$index)
            if ($index -ge $JsonText.Length) { throw 'bundle_candidate_inventory_mismatch' }
            if ($JsonText[$index] -eq ',') {
                $index++
                Skip-EvidenceJsonWhitespace -Text $JsonText -Index ([ref]$index)
                if ($index -ge $JsonText.Length -or $JsonText[$index] -eq '}') {
                    throw 'bundle_candidate_inventory_mismatch'
                }
                continue
            }
            if ($JsonText[$index] -eq '}') {
                $index++
                break
            }
            throw 'bundle_candidate_inventory_mismatch'
        }
        Skip-EvidenceJsonWhitespace -Text $JsonText -Index ([ref]$index)
        if ($index -ne $JsonText.Length -or $shaCount -ne 1 -or $lengthCount -ne 1) {
            throw 'bundle_candidate_inventory_mismatch'
        }
    }
    catch {
        if ($_.Exception.Message -ceq 'bundle_candidate_inventory_mismatch') { throw }
        throw 'bundle_candidate_inventory_mismatch'
    }
}

function Assert-CompletedEvidenceZip {
    param([string] $ArchivePath, [object[]] $Entries)
    Assert-ZipArchivePreflight $ArchivePath
    $expected = New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    foreach ($entry in $Entries) { $expected.Add([string]$entry.name, $entry) }
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        if ($archive.Entries.Count -ne $expected.Count) { throw 'bundle_entry_count_mismatch' }
        foreach ($entry in $archive.Entries) {
            if (-not $expected.ContainsKey($entry.FullName)) { throw ('bundle_entry_unexpected:' + $entry.FullName) }
            $stream = $entry.Open()
            try { $actual = Copy-StreamWithSha256 -Source $stream -Destination $null }
            finally { $stream.Dispose() }
            $wanted = $expected[$entry.FullName]
            if ($actual.sha256 -cne [string]$wanted.expectedSha256 -or $actual.length -ne [long]$wanted.expectedLength) {
                throw ('bundle_entry_identity_mismatch:' + $entry.FullName)
            }
        }

        $inventoryEntries = @($archive.Entries | Where-Object { $_.FullName -ceq 'source-cache-inventory.json' })
        $candidateEntries = @($archive.Entries | Where-Object { $_.FullName -ceq 'evidence/candidate-manifest.json' })
        if ($inventoryEntries.Count -ne 1 -or $candidateEntries.Count -ne 1) { throw 'bundle_candidate_inventory_mismatch' }

        try {
            $inventoryEntry = $inventoryEntries[0]
            if ($inventoryEntry.Length -le 0 -or $inventoryEntry.Length -gt 1MB -or $inventoryEntry.Length -gt [int]::MaxValue) {
                throw 'bundle_candidate_inventory_mismatch'
            }
            $inventoryBytes = New-Object byte[] ([int]$inventoryEntry.Length)
            $inventoryStream = $inventoryEntry.Open()
            try {
                $offset = 0
                while ($offset -lt $inventoryBytes.Length) {
                    $read = $inventoryStream.Read($inventoryBytes, $offset, $inventoryBytes.Length - $offset)
                    if ($read -le 0) { throw 'bundle_candidate_inventory_mismatch' }
                    $offset += $read
                }
                if ($inventoryStream.ReadByte() -ne -1) { throw 'bundle_candidate_inventory_mismatch' }
            }
            finally { $inventoryStream.Dispose() }

            $inventoryText = (New-Object Text.UTF8Encoding($false, $true)).GetString($inventoryBytes)
            Assert-UniqueCandidateInventoryIdentityProperties -JsonText $inventoryText
            $inventory = $inventoryText | ConvertFrom-Json
            $shaProperty = $inventory.PSObject.Properties['candidateManifestSha256']
            $lengthProperty = $inventory.PSObject.Properties['candidateManifestLength']
            $lengthTypeSupported = $null -ne $lengthProperty -and
                ($lengthProperty.Value -is [int] -or $lengthProperty.Value -is [long])
            if ($null -eq $shaProperty -or $shaProperty.Value -isnot [string] -or
                $shaProperty.Value -notmatch '^[0-9a-fA-F]{64}$' -or
                -not $lengthTypeSupported -or
                $lengthProperty.Value -le 0 -or $lengthProperty.Value -gt 1MB) {
                throw 'bundle_candidate_inventory_mismatch'
            }
            $claimedSha256 = $shaProperty.Value.ToUpperInvariant()
            $claimedLength = [long]$lengthProperty.Value

            $candidateStream = $candidateEntries[0].Open()
            try { $candidateActual = Copy-StreamWithSha256 -Source $candidateStream -Destination $null }
            finally { $candidateStream.Dispose() }
            if ($candidateActual.sha256 -cne $claimedSha256 -or $candidateActual.length -ne $claimedLength) {
                throw 'bundle_candidate_inventory_mismatch'
            }
        }
        catch {
            if ($_.Exception.Message -ceq 'bundle_candidate_inventory_mismatch') { throw }
            throw 'bundle_candidate_inventory_mismatch'
        }
    }
    finally { $archive.Dispose() }
}

function New-DeterministicZip {
    param([string] $OutputPath, [object[]] $Entries, [string] $PrivateRoot)
    Assert-OwnedTemporaryDirectory $PrivateRoot
    $exactNames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $caseNames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $prepared = New-Object 'Collections.Generic.List[object]'
    foreach ($entry in $Entries) {
        $name = Assert-SafeArchiveEntryName -Name ([string]$entry.name) -ExactNames $exactNames -CaseInsensitiveNames $caseNames
        $sourcePath = Get-ObjectProperty -Value $entry -Name 'path'
        if ($null -ne $sourcePath) {
            $sourceFull = Assert-ReparseFreePath -Path ([string]$sourcePath) -Label 'private-staging'
            if (-not (Test-ChildPath -Root $PrivateRoot -Path $sourceFull)) { throw 'bundle_source_not_staged' }
            $expectedSha = ([string](Get-ObjectProperty $entry 'expectedSha256')).ToUpperInvariant()
            $expectedLength = [long](Get-ObjectProperty $entry 'expectedLength')
            if ($expectedSha -notmatch '^[0-9A-F]{64}$' -or $expectedLength -lt 0) { throw ('bundle_source_identity_missing:' + $name) }
            $prepared.Add([ordered]@{ name = $name; path = $sourceFull; expectedSha256 = $expectedSha; expectedLength = $expectedLength })
        }
        else {
            $bytes = [byte[]]$entry.bytes
            $actualSha256 = Get-BytesSha256 $bytes
            $actualLength = [long]$bytes.Length
            $declaredSha256 = [string](Get-ObjectProperty -Value $entry -Name 'expectedSha256')
            $declaredLength = Get-ObjectProperty -Value $entry -Name 'expectedLength'
            if (-not [string]::IsNullOrWhiteSpace($declaredSha256) -and $actualSha256 -cne $declaredSha256.ToUpperInvariant()) { throw ('bundle_entry_hash_mismatch:' + $name) }
            if ($null -ne $declaredLength -and $actualLength -ne [long]$declaredLength) { throw ('bundle_entry_length_mismatch:' + $name) }
            $prepared.Add([ordered]@{ name = $name; bytes = $bytes; expectedSha256 = $actualSha256; expectedLength = $actualLength })
        }
    }
    $partial = $OutputPath + '.partial.' + $PID + '.' + [Guid]::NewGuid().ToString('N')
    $stream = $null
    $archive = $null
    try {
        $stream = [IO.File]::Open($partial, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        foreach ($item in @($prepared.ToArray() | Sort-Object { [string]$_.name })) {
            $zipEntry = $archive.CreateEntry(([string]$item.name).Replace('\', '/'), [IO.Compression.CompressionLevel]::Optimal)
            $zipEntry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
            $target = $zipEntry.Open()
            try {
                if ($null -ne (Get-ObjectProperty -Value $item -Name 'path')) {
                    Assert-OwnedTemporaryDirectory $PrivateRoot
                    $source = [IO.File]::Open([string]$item.path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
                    try { $actual = Copy-StreamWithSha256 -Source $source -Destination $target }
                    finally { $source.Dispose() }
                    if ($actual.sha256 -cne [string]$item.expectedSha256 -or $actual.length -ne [long]$item.expectedLength) {
                        throw ('bundle_source_identity_mismatch:' + [string]$item.name)
                    }
                }
                else {
                    $bytes = [byte[]]$item.bytes
                    $target.Write($bytes, 0, $bytes.Length)
                }
            }
            finally { $target.Dispose() }
        }
        $archive.Dispose(); $archive = $null
        $stream.Dispose(); $stream = $null
        Assert-CompletedEvidenceZip -ArchivePath $partial -Entries $prepared.ToArray()
        [IO.File]::Move($partial, $OutputPath)
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    }
}

function Get-ComponentById {
    param([object] $Manifest, [string] $Id)
    return @($Manifest.components | Where-Object { [string]$_.id -ceq $Id }) | Select-Object -First 1
}

function Get-CandidateFile {
    param([object] $Candidate, [string] $Path)
    return @($Candidate.files | Where-Object { ([string]$_.path).Replace('\', '/') -ieq $Path.Replace('\', '/') }) | Select-Object -First 1
}

$manifest = $null
$originalManifestPath = [IO.Path]::GetFullPath($ManifestPath)
$manifestBytes = $null
$manifestSha256 = $null
$manifestProjectionSha256 = $null
$artifactById = @{}
$artifactValid = @{}
$artifactStagedPath = @{}
$inventoryRecords = New-Object 'Collections.Generic.List[object]'
$bundleEntries = New-Object 'Collections.Generic.List[object]'
$nlohmannEvidenceBytes = $null
$applicationSourceArchive = $null
$candidate = $null
$candidateManifestBytes = $null
$candidateManifestSha256 = $null
$candidateManifestLength = $null
$candidateManifestParseFailed = $false
$dependencyExtracted = $null
$task5RuntimeExtracted = $null
$task5SourceExtracted = $null
$sourceCacheSafe = $true
$applicationRepositorySafe = $true
$releaseTag = 'v2.19.1-karon.2'

try {
    $OutputDirectory = Assert-ReparseFreePath -Path $OutputDirectory -Label 'output'
    [IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
    [void](Assert-ReparseFreePath -Path $OutputDirectory -Label 'output')
}
catch { throw }

$script:stagingRoot = New-TemporaryDirectory 'component-evidence-staging'

try {
    $SourceCacheDirectory = Assert-ReparseFreePath -Path $SourceCacheDirectory -Label 'source-cache'
    [IO.Directory]::CreateDirectory($SourceCacheDirectory) | Out-Null
    [void](Assert-ReparseFreePath -Path $SourceCacheDirectory -Label 'source-cache')
}
catch { Add-EvidenceBlocker $_.Exception.Message; $sourceCacheSafe = $false }

try { [void](Assert-ReparseFreePath -Path $ApplicationRepository -Label 'application-repository') }
catch { Add-EvidenceBlocker $_.Exception.Message; $applicationRepositorySafe = $false }

try {
    $ManifestPath = Copy-InputToPrivateStaging -SourcePath $ManifestPath -RelativePath 'inputs\component-manifest.json' -Label 'component-manifest'
    $manifestBytes = [IO.File]::ReadAllBytes($ManifestPath)
    $manifestSha256 = Get-BytesSha256 $manifestBytes
    $manifestText = $utf8NoBom.GetString($manifestBytes)
    if ($manifestText -match '(?i)NOASSERTION') { Add-EvidenceBlocker 'forbidden_license_assertion' }
    $manifest = $manifestText | ConvertFrom-Json
    $manifestProjectionSha256 = Get-ManifestProjectionSha256 $manifest
}
catch {
    Add-EvidenceBlocker ('component_manifest_invalid:' + $_.Exception.Message)
}

foreach ($input in @(
    @('DependencyArchivePath', $DependencyArchivePath, 'inputs\dependency-archive.bin', 'dependency-archive'),
    @('SevenZipRuntimeArchivePath', $SevenZipRuntimeArchivePath, 'inputs\sevenzip-runtime.7z', 'sevenzip-runtime'),
    @('SevenZipSourceArchivePath', $SevenZipSourceArchivePath, 'inputs\sevenzip-source.7z', 'sevenzip-source'),
    @('SevenZipVerificationPath', $SevenZipVerificationPath, 'inputs\sevenzip-verification.json', 'sevenzip-verification'),
    @('YtDlpBinaryPath', $YtDlpBinaryPath, 'inputs\yt-dlp.exe', 'yt-dlp-binary'))) {
    try {
        $staged = Copy-InputToPrivateStaging -SourcePath ([string]$input[1]) -RelativePath ([string]$input[2]) -Label ([string]$input[3])
        Set-Variable -Name ([string]$input[0]) -Value $staged
    }
    catch { Add-EvidenceBlocker $_.Exception.Message; Set-Variable -Name ([string]$input[0]) -Value '' }
}

if (-not [string]::IsNullOrWhiteSpace($CandidateManifestPath)) {
    try {
        $CandidateManifestPath = Copy-InputToPrivateStaging -SourcePath $CandidateManifestPath -RelativePath 'inputs\candidate-manifest.json' -Label 'candidate-manifest'
        $candidateManifestBytes = Read-BoundedPrivateFileBytes -Path $CandidateManifestPath -MaximumLength (1MB) -Label 'candidate_manifest'
        $candidateManifestLength = [int64]$candidateManifestBytes.Length
        $candidateManifestSha256 = Get-BytesSha256 $candidateManifestBytes
        $candidateText = (New-Object Text.UTF8Encoding($false, $true)).GetString($candidateManifestBytes)
        $candidate = $candidateText | ConvertFrom-Json
    }
    catch {
        if ($_.Exception.Message -ceq 'candidate_manifest_size_invalid') { Add-EvidenceBlocker 'candidate_manifest_size_invalid' }
        else { Add-EvidenceBlocker ('candidate_manifest_invalid:' + $_.Exception.Message) }
        $candidateManifestParseFailed = $true
    }
}

if (-not [string]::IsNullOrWhiteSpace($SevenZipExecutable)) {
    try {
        $SevenZipExecutable = Copy-InputToPrivateStaging -SourcePath $SevenZipExecutable -RelativePath 'tools\7z.exe' -Label 'sevenzip-executable'
        $script:stagedSevenZipExecutable = $SevenZipExecutable
    }
    catch { Add-EvidenceBlocker $_.Exception.Message; $SevenZipExecutable = '' }
}

if ($null -ne $manifest) {
    $approvalProfile = [string](Get-ObjectProperty $manifest 'approvalProfile')
    $releaseTag = [string]$manifest.release.tag
    $profileReleaseValid = ($approvalProfile -ceq $productionApprovalProfile -and $releaseTag -ceq 'v2.19.1-karon.2') -or
        ($approvalProfile -ceq $fixtureApprovalProfile -and $releaseTag -ceq 'test-fixture')
    if ($approvalProfile -cne $productionApprovalProfile -and $approvalProfile -cne $fixtureApprovalProfile) { Add-EvidenceBlocker 'approval_profile_invalid' }
    if ($approvalProfile -ceq $productionApprovalProfile) {
        Test-ProductionManifestGitBinding -OriginalManifestPath $originalManifestPath -Repository $ApplicationRepository
        if ($manifestProjectionSha256 -cne $productionManifestProjectionSha256) { Add-EvidenceBlocker 'production_manifest_projection_mismatch' }
    }
    if ([string]$manifest.schemaVersion -cne 'karon-non-runtime-component-evidence/v1' -or -not $profileReleaseValid -or [string]$manifest.release.platform -cne 'win-x64') {
        Add-EvidenceBlocker 'component_manifest_contract_mismatch'
    }
    $expectedIds = @('7zip', 'application', 'bit7z', 'cpm', 'libjpeg-turbo', 'libpng', 'nana', 'nlohmann-json', 'yt-dlp', 'zlib')
    $actualIds = @($manifest.components | ForEach-Object { [string]$_.id })
    $idSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($id in $actualIds) { if ([string]::IsNullOrWhiteSpace($id) -or -not $idSet.Add($id)) { Add-EvidenceBlocker 'component_id_collision' } }
    if ($actualIds.Count -ne [int]$manifest.release.expectedComponentCount -or $actualIds.Count -ne $expectedIds.Count) { Add-EvidenceBlocker 'component_count_mismatch' }
    foreach ($id in $expectedIds) { if (-not $idSet.Contains($id)) { Add-EvidenceBlocker ('component_missing:' + $id) } }
    foreach ($excluded in @($manifest.release.excludedComponents)) { if ($idSet.Contains([string]$excluded)) { Add-EvidenceBlocker ('excluded_component_present:' + $excluded) } }

    $fileNameSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $artifactIdSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($component in @($manifest.components)) {
        if (-not (Test-ComponentApproval -Component $component -Profile $approvalProfile)) { Add-EvidenceBlocker ('component_approval_mismatch:' + [string]$component.id) }
        if ([string]::IsNullOrWhiteSpace([string]$component.licenseExpression) -or [string]$component.licenseExpression -match '(?i)NOASSERTION') {
            Add-EvidenceBlocker ('license_expression_missing:' + [string]$component.id)
        }
        if ([string]$component.id -cne 'application' -and [string]$component.sourceCommit -notmatch '^[0-9a-f]{40}$') {
            Add-EvidenceBlocker ('source_commit_invalid:' + [string]$component.id)
        }
        if ($null -eq (Get-ObjectProperty $component 'buildRecipe') -or $null -eq (Get-ObjectProperty $component.buildRecipe 'candidateBinding')) {
            Add-EvidenceBlocker ('candidate_binding_missing:' + [string]$component.id)
        }
        foreach ($artifact in @($component.sourceArtifacts)) {
            $id = [string]$artifact.id
            $fileName = [string]$artifact.fileName
            $idAccepted = $artifactIdSet.Add($id)
            $fileNameValid = Test-SafeLeafFileName $fileName
            $fileNameAccepted = $fileNameValid -and $fileNameSet.Add($fileName)
            if (-not $idAccepted) { Add-EvidenceBlocker 'source_artifact_id_collision' }
            if (-not $fileNameValid) { Add-EvidenceBlocker ('source_artifact_file_name_invalid:' + $id) }
            elseif (-not $fileNameAccepted) { Add-EvidenceBlocker 'source_cache_name_collision' }
            if (-not (Test-ImmutableSourceUrl ([string]$artifact.url))) { Add-EvidenceBlocker ('mutable_source_url:' + $id) }
            $artifactById[$id] = $artifact
            $exists = $false
            $actualSha = $null
            $actualLength = $null
            $valid = $false
            $status = 'unavailable'
            if ($sourceCacheSafe -and $idAccepted -and $fileNameAccepted) {
                try {
                    $path = Get-DirectChildPath -Root $SourceCacheDirectory -Leaf $fileName
                    Acquire-SourceArtifact -Artifact $artifact -Destination $path
                    $exists = Test-Path -LiteralPath $path -PathType Leaf
                    if ($exists) {
                        [void](Assert-ReparseFreePath -Path $path -Label ('source-artifact-' + $id))
                        $stagedPath = Copy-InputToPrivateStaging -SourcePath $path -RelativePath ('sources\' + $fileName) -Label ('source-artifact-' + $id)
                        $file = Get-Item -LiteralPath $stagedPath
                        $actualLength = [long]$file.Length
                        $actualSha = Get-PathSha256 $stagedPath
                        $valid = $actualLength -eq [long]$artifact.length -and $actualSha -ceq ([string]$artifact.sha256).ToUpperInvariant()
                        if ($valid -and ([string]$artifact.format -ceq 'zip' -or [string]$artifact.format -ceq '7z' -or [IO.Path]::GetExtension($fileName) -ieq '.nupkg')) {
                            try { Assert-ArchivePreflight -ArchivePath $stagedPath -Format ([string]$artifact.format) }
                            catch { Add-EvidenceBlocker ('source_archive_preflight_failed:' + $id + ':' + $_.Exception.Message); $valid = $false; $status = 'archive-invalid' }
                        }
                        if ($valid) { $artifactStagedPath[$id] = $stagedPath; $status = 'verified' }
                    }
                }
                catch { Add-EvidenceBlocker ('source_access_failed:' + $id + ':' + $_.Exception.Message) }
            }
            if ($sourceCacheSafe -and $fileNameAccepted -and -not $exists) { Add-EvidenceBlocker ('source_missing:' + $id) }
            elseif ($exists -and -not $valid -and $status -cne 'archive-invalid') { Add-EvidenceBlocker ('source_hash_mismatch:' + $id); $status = 'mismatch' }
            $artifactValid[$id] = $valid
            $inventoryRecords.Add([ordered]@{
                id = $id; component = [string]$component.id; fileName = $fileName; url = [string]$artifact.url
                expectedSha256 = ([string]$artifact.sha256).ToUpperInvariant(); expectedLength = [long]$artifact.length
                actualSha256 = $actualSha; actualLength = $actualLength; status = $status
                includeInBundle = [bool]$artifact.includeInBundle
            })
        }
    }

    foreach ($component in @($manifest.components)) {
        foreach ($license in @($component.licenseTexts)) {
            $kind = [string]$license.kind
            if ($kind -ceq 'archive-entry') {
                $artifactId = [string]$license.sourceArtifactId
                if (-not $artifactById.ContainsKey($artifactId) -or -not [bool]$artifactValid[$artifactId] -or -not $artifactStagedPath.ContainsKey($artifactId)) { continue }
                $artifact = $artifactById[$artifactId]
                if ([string]$artifact.format -cne 'zip') { Add-EvidenceBlocker ('license_archive_format_invalid:' + [string]$component.id); continue }
                try { $bytes = Get-ZipEntryBytes -ArchivePath $artifactStagedPath[$artifactId] -EntryPath ([string]$license.archivePath) }
                catch { $bytes = $null }
                if ($null -eq $bytes) { Add-EvidenceBlocker ('license_entry_missing:' + [string]$component.id); continue }
                if ($bytes.Length -ne [long]$license.length -or (Get-BytesSha256 $bytes) -cne ([string]$license.sha256).ToUpperInvariant()) {
                    Add-EvidenceBlocker ('license_hash_mismatch:' + [string]$component.id)
                }
            }
            elseif ($kind -ceq 'repository-file') {
                $path = Join-Path $ApplicationRepository ([string]$license.path)
                $repositoryLicenseValid = $applicationRepositorySafe -and (Test-ChildPath $ApplicationRepository $path)
                if ($repositoryLicenseValid) {
                    try { [void](Assert-ReparseFreePath -Path $path -Label 'application-license') }
                    catch { Add-EvidenceBlocker $_.Exception.Message; $repositoryLicenseValid = $false }
                }
                $stagedLicense = $null
                if ($repositoryLicenseValid -and (Test-Path -LiteralPath $path -PathType Leaf)) {
                    try { $stagedLicense = Copy-InputToPrivateStaging -SourcePath $path -RelativePath ('application\licenses\' + [string]$component.id + '.txt') -Label 'application-license' }
                    catch { Add-EvidenceBlocker $_.Exception.Message; $repositoryLicenseValid = $false }
                }
                if (-not $repositoryLicenseValid -or -not (Test-FileIdentity $stagedLicense ([string]$license.sha256) ([long]$license.length))) {
                    Add-EvidenceBlocker ('license_repository_file_mismatch:' + [string]$component.id)
                }
            }
            elseif ($kind -cne 'task5-runtime-entry') { Add-EvidenceBlocker ('license_evidence_kind_invalid:' + [string]$component.id) }
        }
    }

    $dependency = $manifest.sharedInputs.dependencyArchive
    if (-not (Test-FileIdentity $DependencyArchivePath ([string]$dependency.sha256) ([long]$dependency.length))) {
        Add-EvidenceBlocker 'dependency_archive_mismatch'
    }
    else {
        try {
            Assert-ArchivePreflight -ArchivePath $DependencyArchivePath -Format ([string]$dependency.format)
            $dependencyExtracted = New-TemporaryDirectory 'dependency-evidence'
            Expand-EvidenceArchive $DependencyArchivePath ([string]$dependency.format) $dependencyExtracted
            foreach ($embedded in @($dependency.embeddedFiles)) {
                $path = Join-Path $dependencyExtracted ([string]$embedded.path).Replace('/', '\')
                if (-not (Test-FileIdentity $path ([string]$embedded.sha256) ([long]$embedded.length))) { Add-EvidenceBlocker ('dependency_embedded_file_mismatch:' + [string]$embedded.path) }
            }
            foreach ($root in @($dependency.roots)) {
                $path = Join-Path $dependencyExtracted ([string]$root.path).Replace('/', '\')
                if (-not (Test-Path -LiteralPath $path -PathType Container)) { Add-EvidenceBlocker ('dependency_root_missing:' + [string]$root.path); continue }
                $actual = Get-OrderedTreeEvidence $path
                if ($actual.fileCount -ne [int]$root.fileCount -or $actual.length -ne [long]$root.length -or
                    [string]$actual.orderedTreeSha256 -cne ([string]$root.orderedTreeSha256).ToUpperInvariant()) {
                    Add-EvidenceBlocker ('dependency_tree_mismatch:{0}:expected={1}/{2}/{3}:actual={4}/{5}/{6}' -f
                        [string]$root.path, [int]$root.fileCount, [long]$root.length, ([string]$root.orderedTreeSha256).ToUpperInvariant(),
                        [int]$actual.fileCount, [long]$actual.length, [string]$actual.orderedTreeSha256)
                }
            }
            $provenancePath = Join-Path $dependencyExtracted ([string]$dependency.provenancePath).Replace('/', '\')
            if (-not (Test-FileIdentity $provenancePath ([string]$dependency.provenanceSha256) ((Get-Item $provenancePath).Length))) { Add-EvidenceBlocker 'dependency_provenance_hash_mismatch' }
            else {
                $provenance = Get-Content -LiteralPath $provenancePath -Raw | ConvertFrom-Json
                $bit7z = Get-ComponentById $manifest 'bit7z'
                $cpm = Get-ComponentById $manifest 'cpm'
                $sevenZip = Get-ComponentById $manifest '7zip'
                if ([string]$provenance.bit7z.version -cne [string]$bit7z.version -or [string]$provenance.bit7z.commit -cne [string]$bit7z.sourceCommit -or
                    [string]$provenance.bit7z.license -cne [string]$bit7z.licenseExpression -or
                    ([string]$provenance.bit7z.sourceSha256).ToUpperInvariant() -cne ([string]$artifactById['bit7z-source'].sha256).ToUpperInvariant()) { Add-EvidenceBlocker 'bit7z_provenance_mismatch' }
                if ([string]$provenance.cpmBootstrap.version -cne [string]$cpm.version -or [string]$provenance.cpmBootstrap.commit -cne [string]$cpm.sourceCommit -or
                    ([string]$provenance.cpmBootstrap.sourceSha256).ToUpperInvariant() -cne ([string]$artifactById['cpm-bootstrap'].sha256).ToUpperInvariant()) { Add-EvidenceBlocker 'cpm_provenance_mismatch' }
                if ([string]$provenance.sevenZip.version -cne [string]$sevenZip.version -or [string]$provenance.sevenZip.commit -cne [string]$sevenZip.sourceCommit -or
                    [string]$provenance.sevenZip.license -cne [string]$sevenZip.licenseExpression) { Add-EvidenceBlocker 'sevenzip_dependency_provenance_mismatch' }
            }
        }
        catch { Add-EvidenceBlocker ('dependency_archive_extract_failed:' + $_.Exception.Message) }
    }

    $task5 = $manifest.sharedInputs.sevenZipTask5
    $task5InputsValid = $true
    foreach ($check in @(
        @($SevenZipRuntimeArchivePath, [string]$task5.runtimeArchiveSha256, [long]$task5.runtimeArchiveLength, 'sevenzip_runtime_archive_mismatch'),
        @($SevenZipSourceArchivePath, [string]$task5.sourceArchiveSha256, [long]$task5.sourceArchiveLength, 'sevenzip_source_archive_mismatch'),
        @($SevenZipVerificationPath, [string]$task5.verificationSha256, [long]$task5.verificationLength, 'sevenzip_verification_mismatch'))) {
        if (-not (Test-FileIdentity $check[0] $check[1] $check[2])) { Add-EvidenceBlocker $check[3]; $task5InputsValid = $false }
    }
    if ($task5InputsValid) {
        try {
            Assert-ArchivePreflight -ArchivePath $SevenZipRuntimeArchivePath -Format ([string]$task5.format)
            Assert-ArchivePreflight -ArchivePath $SevenZipSourceArchivePath -Format ([string]$task5.format)
            $verification = Get-Content -LiteralPath $SevenZipVerificationPath -Raw | ConvertFrom-Json
            if (([string]$verification.runtimeArchiveSha256).ToUpperInvariant() -cne ([string]$task5.runtimeArchiveSha256).ToUpperInvariant() -or
                ([string]$verification.dllSha256).ToUpperInvariant() -cne ([string]$task5.dllSha256).ToUpperInvariant() -or
                ([string]$verification.correspondingSourceArchiveSha256).ToUpperInvariant() -cne ([string]$task5.sourceArchiveSha256).ToUpperInvariant()) { Add-EvidenceBlocker 'sevenzip_verification_crosscheck_mismatch' }
            if (-not [string]::IsNullOrWhiteSpace($SevenZipExecutable) -and $null -ne (Get-ObjectProperty $verification 'hostSha256') -and
                (Get-PathSha256 $SevenZipExecutable) -cne ([string]$verification.hostSha256).ToUpperInvariant()) { Add-EvidenceBlocker 'sevenzip_extractor_identity_mismatch' }
            $task5RuntimeExtracted = New-TemporaryDirectory 'sevenzip-runtime'
            $task5SourceExtracted = New-TemporaryDirectory 'sevenzip-source'
            Expand-EvidenceArchive $SevenZipRuntimeArchivePath ([string]$task5.format) $task5RuntimeExtracted
            Expand-EvidenceArchive $SevenZipSourceArchivePath ([string]$task5.format) $task5SourceExtracted
            $dllPath = Join-Path $task5RuntimeExtracted 'x64\7z.dll'
            if (-not (Test-FileIdentity $dllPath ([string]$task5.dllSha256) ([long]$task5.dllLength))) { Add-EvidenceBlocker 'sevenzip_dll_mismatch' }
            $buildMapPath = Join-Path $task5RuntimeExtracted ([string]$task5.buildMapPath).Replace('/', '\')
            if (-not (Test-FileIdentity $buildMapPath ([string]$task5.buildMapSha256) ((Get-Item $buildMapPath).Length))) { Add-EvidenceBlocker 'sevenzip_build_map_mismatch' }
            else {
                $map = Get-Content -LiteralPath $buildMapPath -Raw | ConvertFrom-Json
                $objects = @($map.objects | ForEach-Object { [string]$_ })
                if ([int]$map.objectCount -ne $objects.Count -or @($objects | Where-Object { $_ -match [string]$task5.forbiddenPattern }).Count -gt 0) { Add-EvidenceBlocker 'sevenzip_rar_evidence_mismatch' }
                foreach ($required in @($task5.requiredObjects)) { if ($objects -notcontains [string]$required) { Add-EvidenceBlocker 'sevenzip_required_object_missing' } }
            }
            $buildProvenancePath = Join-Path $task5RuntimeExtracted 'provenance\build-provenance.json'
            $buildProvenance = Get-Content -LiteralPath $buildProvenancePath -Raw | ConvertFrom-Json
            if ([string]$buildProvenance.policy -cne 'no-rar-handlers-or-code' -or [string]$buildProvenance.version -cne '26.01' -or
                [string]$buildProvenance.source.commit -cne [string]$task5.sourceCommit -or
                ([string]$buildProvenance.source.archiveSha256).ToUpperInvariant() -cne ([string]$artifactById['sevenzip-source'].sha256).ToUpperInvariant() -or
                ([string]$buildProvenance.dll.sha256).ToUpperInvariant() -cne ([string]$task5.dllSha256).ToUpperInvariant()) { Add-EvidenceBlocker 'sevenzip_build_provenance_mismatch' }
            foreach ($file in @(Get-ChildItem -LiteralPath $task5SourceExtracted -File -Recurse)) {
                $relative = $file.FullName.Substring($task5SourceExtracted.Length).TrimStart('\', '/').Replace('\', '/')
                if ($relative -match [string]$task5.forbiddenSourcePattern) { Add-EvidenceBlocker 'sevenzip_rar_evidence_mismatch'; break }
            }
            $sevenZipComponent = Get-ComponentById $manifest '7zip'
            foreach ($license in @($sevenZipComponent.licenseTexts | Where-Object { [string]$_.kind -ceq 'task5-runtime-entry' })) {
                $path = Join-Path $task5RuntimeExtracted ([string]$license.archivePath).Replace('/', '\')
                if (-not (Test-FileIdentity $path ([string]$license.sha256) ([long]$license.length))) { Add-EvidenceBlocker 'license_hash_mismatch:7zip' }
            }
        }
        catch { Add-EvidenceBlocker ('sevenzip_evidence_extract_failed:' + $_.Exception.Message) }
    }

    $nlohmann = Get-ComponentById $manifest 'nlohmann-json'
    if ($null -ne $nlohmann -and @($nlohmann.transforms).Count -eq 1) {
        try {
            $transform = $nlohmann.transforms[0]
            $artifact = $artifactById[[string]$transform.sourceArtifactId]
            $sourceBytes = Get-ZipEntryBytes $artifactStagedPath[[string]$transform.sourceArtifactId] ([string]$transform.sourceArchivePath)
            $targetPath = Join-Path $ApplicationRepository ([string]$transform.repositoryPath).Replace('/', '\')
            if ($null -eq $sourceBytes -or -not (Test-Path -LiteralPath $targetPath -PathType Leaf)) { throw 'header_missing' }
            [void](Assert-ReparseFreePath -Path $targetPath -Label 'application-header')
            $stagedTargetPath = Copy-InputToPrivateStaging -SourcePath $targetPath -RelativePath 'application\nlohmann-json.hpp' -Label 'application-header'
            $targetBytes = [IO.File]::ReadAllBytes($stagedTargetPath)
            $converted = New-Object IO.MemoryStream
            foreach ($byte in $sourceBytes) { if ($byte -eq 10) { $converted.WriteByte(13) }; $converted.WriteByte($byte) }
            $convertedBytes = $converted.ToArray(); $converted.Dispose()
            $evidence = [ordered]@{
                schemaVersion = 'karon-text-transform/v1'; algorithm = 'lf-to-crlf'
                sourceSha256 = Get-BytesSha256 $sourceBytes; sourceLength = $sourceBytes.Length
                targetSha256 = Get-BytesSha256 $targetBytes; targetLength = $targetBytes.Length
                lineFeedCount = @($sourceBytes | Where-Object { $_ -eq 10 }).Count
                sourceCarriageReturnCount = @($sourceBytes | Where-Object { $_ -eq 13 }).Count
                sourceOrderedChunkSha256 = Get-OrderedChunkDigest $sourceBytes
                targetOrderedChunkSha256 = Get-OrderedChunkDigest $targetBytes
            }
            $nlohmannEvidenceBytes = $utf8NoBom.GetBytes(($evidence | ConvertTo-Json -Depth 50 -Compress) + "`r`n")
            $convertedMatches = $convertedBytes.Length -eq $targetBytes.Length -and (Get-BytesSha256 $convertedBytes) -ceq (Get-BytesSha256 $targetBytes)
            if ([string]$transform.kind -cne 'lf-to-crlf' -or -not $convertedMatches -or
                $evidence.sourceCarriageReturnCount -ne 0 -or $evidence.lineFeedCount -ne [int]$transform.lineFeedCount -or
                $evidence.sourceSha256 -cne ([string]$transform.sourceSha256).ToUpperInvariant() -or $evidence.sourceLength -ne [long]$transform.sourceLength -or
                $evidence.targetSha256 -cne ([string]$transform.targetSha256).ToUpperInvariant() -or $evidence.targetLength -ne [long]$transform.targetLength -or
                $evidence.sourceOrderedChunkSha256 -cne ([string]$transform.sourceOrderedChunkSha256).ToUpperInvariant() -or
                $evidence.targetOrderedChunkSha256 -cne ([string]$transform.targetOrderedChunkSha256).ToUpperInvariant() -or
                $nlohmannEvidenceBytes.Length -ne [long]$transform.transformEvidenceLength -or
                (Get-BytesSha256 $nlohmannEvidenceBytes) -cne ([string]$transform.transformEvidenceSha256).ToUpperInvariant()) { Add-EvidenceBlocker 'nlohmann_transform_mismatch' }
        }
        catch { Add-EvidenceBlocker 'nlohmann_transform_mismatch' }
    }
    else { Add-EvidenceBlocker 'nlohmann_transform_mismatch' }

    $ytDlp = Get-ComponentById $manifest 'yt-dlp'
    if ($null -ne $ytDlp) {
        $binaryArtifact = $artifactById[[string]$ytDlp.binaryProvenance.binaryArtifactId]
        $sumsArtifact = $artifactById[[string]$ytDlp.binaryProvenance.checksumsArtifactId]
        $expectedBinarySha = ([string]$binaryArtifact.sha256).ToUpperInvariant()
        $expectedBinaryLength = [long]$binaryArtifact.length
        if (-not (Test-FileIdentity $YtDlpBinaryPath $expectedBinarySha $expectedBinaryLength)) { Add-EvidenceBlocker 'yt_dlp_binary_mismatch' }
        if ($artifactValid[[string]$sumsArtifact.id]) {
            $sumsText = Get-Content -LiteralPath $artifactStagedPath[[string]$sumsArtifact.id] -Raw
            if ($sumsText -notmatch ('(?im)^' + [regex]::Escape($expectedBinarySha.ToLowerInvariant()) + '  yt-dlp\.exe\r?$')) { Add-EvidenceBlocker 'yt_dlp_checksum_manifest_mismatch' }
        }
        if ([string]$ytDlp.binaryProvenance.sourceCommit -cne [string]$ytDlp.sourceCommit -or -not [bool]$ytDlp.binaryProvenance.releaseImmutable) { Add-EvidenceBlocker 'yt_dlp_release_provenance_mismatch' }
    }

    $application = Get-ComponentById $manifest 'application'
    if ([string]::IsNullOrWhiteSpace($ApplicationCommit) -or $ApplicationCommit -notmatch '^[0-9a-f]{40}$') { Add-EvidenceBlocker 'application_release_commit_required' }
    elseif (-not $applicationRepositorySafe -or -not (Test-Path -LiteralPath $ApplicationRepository -PathType Container)) { Add-EvidenceBlocker 'application_repository_missing' }
    else {
        try {
            $head = (& git -C $ApplicationRepository rev-parse HEAD 2>$null | Out-String).Trim()
            $status = (& git -C $ApplicationRepository status --porcelain=v1 --untracked-files=all 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or $head -cne $ApplicationCommit) { Add-EvidenceBlocker 'application_commit_mismatch' }
            elseif (-not [string]::IsNullOrEmpty($status)) { Add-EvidenceBlocker 'application_tree_dirty' }
            else {
                $applicationTemp = Join-Path $script:stagingRoot 'application'
                [IO.Directory]::CreateDirectory($applicationTemp) | Out-Null
                [void](Assert-ReparseFreePath -Path $applicationTemp -Label 'private-staging')
                $applicationSourceArchive = Join-Path $applicationTemp ('karon-application-' + $ApplicationCommit.Substring(0, 12) + '.zip')
                & git -C $ApplicationRepository archive --format=zip --output=$applicationSourceArchive $ApplicationCommit
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $applicationSourceArchive -PathType Leaf)) { throw 'git_archive_failed' }
                Assert-ZipArchivePreflight $applicationSourceArchive
                $appFile = Get-Item -LiteralPath $applicationSourceArchive
                $inventoryRecords.Add([ordered]@{
                    id = 'application-source'; component = 'application'; fileName = $appFile.Name
                    url = ([string]$application.sourceRepository).TrimEnd('/') + '/commit/' + $ApplicationCommit
                    expectedSha256 = Get-PathSha256 $applicationSourceArchive; expectedLength = $appFile.Length
                    actualSha256 = Get-PathSha256 $applicationSourceArchive; actualLength = $appFile.Length; status = 'verified'; includeInBundle = $true
                })
            }
        }
        catch { Add-EvidenceBlocker ('application_source_archive_failed:' + $_.Exception.Message) }
    }

    if ([string]::IsNullOrWhiteSpace($CandidateManifestPath)) { Add-EvidenceBlocker 'candidate_manifest_required' }
    elseif ($candidateManifestParseFailed) { }
    elseif ($null -eq $candidate) { Add-EvidenceBlocker 'candidate_manifest_invalid:root_null' }
    else {
        try {
            if ([string]$candidate.attestation.source.commit -cne $ApplicationCommit -or [bool]$candidate.attestation.source.dirty) { Add-EvidenceBlocker 'candidate_source_binding_mismatch' }
            $dependency = $manifest.sharedInputs.dependencyArchive
            if ([string]$candidate.attestation.dependencyArchive.name -cne [string]$dependency.fileName -or
                ([string]$candidate.attestation.dependencyArchive.sha256).ToUpperInvariant() -cne ([string]$dependency.sha256).ToUpperInvariant()) { Add-EvidenceBlocker 'candidate_dependency_binding_mismatch' }
            $linkerSet = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            foreach ($input in @($candidate.attestation.linkerInputs)) {
                if ([string]$input.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or [long]$input.length -le 0) { Add-EvidenceBlocker 'candidate_linker_identity_invalid' }
                [void]$linkerSet.Add([string]$input.library)
            }
            foreach ($required in @($manifest.sharedInputs.candidate.requiredLinkerLibraries)) { if (-not $linkerSet.Contains([string]$required)) { Add-EvidenceBlocker ('candidate_linker_missing:' + [string]$required) } }
            foreach ($componentId in @('7zip', 'yt-dlp')) {
                $component = Get-ComponentById $manifest $componentId
                $binding = $component.buildRecipe.candidateBinding
                $file = Get-CandidateFile $candidate ([string]$binding.candidatePath)
                if ($null -eq $file -or ([string]$file.sha256).ToUpperInvariant() -cne ([string]$binding.sha256).ToUpperInvariant()) { Add-EvidenceBlocker ('candidate_file_binding_mismatch:' + $componentId) }
            }
        }
        catch { Add-EvidenceBlocker ('candidate_manifest_invalid:' + $_.Exception.Message) }
    }
}

$inventoryStatus = if ($script:blockers.Count -eq 0) { 'closed' } else { 'blocked' }
$orderedInventory = @($inventoryRecords | Sort-Object { [string]$_.id })
$inventory = [ordered]@{
    schemaVersion = 'karon-source-cache-inventory/v1'
    release = $releaseTag
    scope = 'non-ffmpeg-non-deno'
    status = $inventoryStatus
    approvalProfile = $(if ($null -eq $manifest) { $null } else { [string](Get-ObjectProperty $manifest 'approvalProfile') })
    manifestSha256 = $manifestSha256
    manifestProjectionSha256 = $manifestProjectionSha256
    applicationCommit = $(if ([string]::IsNullOrWhiteSpace($ApplicationCommit)) { $null } else { $ApplicationCommit })
    candidateManifestSha256 = $candidateManifestSha256
    candidateManifestLength = $candidateManifestLength
    dependencyArchiveSha256 = $(if (Test-Path -LiteralPath $DependencyArchivePath -PathType Leaf) { Get-PathSha256 $DependencyArchivePath } else { $null })
    sevenZipTask5 = [ordered]@{
        runtimeArchiveSha256 = $(if (Test-Path -LiteralPath $SevenZipRuntimeArchivePath -PathType Leaf) { Get-PathSha256 $SevenZipRuntimeArchivePath } else { $null })
        sourceArchiveSha256 = $(if (Test-Path -LiteralPath $SevenZipSourceArchivePath -PathType Leaf) { Get-PathSha256 $SevenZipSourceArchivePath } else { $null })
        verificationSha256 = $(if (Test-Path -LiteralPath $SevenZipVerificationPath -PathType Leaf) { Get-PathSha256 $SevenZipVerificationPath } else { $null })
    }
    artifacts = $orderedInventory
}
$inventoryBytes = ConvertTo-CanonicalJsonBytes $inventory
$inventoryPath = Join-Path $OutputDirectory 'source-cache-inventory.json'

try {
    Write-AtomicBytes $inventoryPath $inventoryBytes
    if ([string]$manifest.approvalProfile -ceq $fixtureApprovalProfile -and
        $env:KARON_EVIDENCE_INTERNAL_TEST_HOOK -ceq 'candidate-after-inventory-v1') {
        $hookSignalPath = Join-Path $OutputDirectory '.candidate-after-inventory.signal'
        $hookContinuePath = Join-Path $OutputDirectory '.candidate-after-inventory.continue'
        if ((Test-Path -LiteralPath $hookSignalPath) -or (Test-Path -LiteralPath $hookContinuePath)) { throw 'internal_candidate_hook_path_exists' }
        [IO.File]::WriteAllText($hookSignalPath, $CandidateManifestPath, (New-Object Text.UTF8Encoding($false)))
        $hookDeadline = [DateTime]::UtcNow.AddSeconds(30)
        while (-not [IO.File]::Exists($hookContinuePath)) {
            if ([DateTime]::UtcNow -ge $hookDeadline) { throw 'internal_candidate_hook_timeout' }
            Start-Sleep -Milliseconds 5
        }
    }
    if ($script:blockers.Count -gt 0) {
        $orderedBlockers = $script:blockers.ToArray()
        [Array]::Sort($orderedBlockers, [StringComparer]::Ordinal)
        $blockerDocument = [ordered]@{
            schemaVersion = 'karon-component-evidence-blockers/v1'
            release = $releaseTag
            scope = 'non-ffmpeg-non-deno'
            status = 'blocked'
            componentCount = $(if ($null -eq $manifest) { 0 } else { @($manifest.components).Count })
            manifestSha256 = $manifestSha256
            sourceCacheInventorySha256 = Get-BytesSha256 $inventoryBytes
            blockers = $orderedBlockers
        }
        $blockerPath = Join-Path $OutputDirectory 'non-runtime-component-blockers.json'
        Write-AtomicBytes $blockerPath (ConvertTo-CanonicalJsonBytes $blockerDocument)
        Write-Output $blockerPath
        exit 1
    }

    foreach ($component in @($manifest.components)) {
        foreach ($artifact in @($component.sourceArtifacts | Where-Object { [bool]$_.includeInBundle })) {
            $bundleEntries.Add([ordered]@{ name = 'sources/' + [string]$artifact.fileName; path = $artifactStagedPath[[string]$artifact.id]; expectedSha256 = ([string]$artifact.sha256).ToUpperInvariant(); expectedLength = [long]$artifact.length })
        }
    }
    $bundleEntries.Add([ordered]@{ name = 'component-manifest.json'; path = $ManifestPath; expectedSha256 = $manifestSha256; expectedLength = $manifestBytes.Length })
    $bundleEntries.Add([ordered]@{ name = 'source-cache-inventory.json'; bytes = $inventoryBytes })
    $bundleEntries.Add([ordered]@{ name = 'application/' + (Split-Path -Leaf $applicationSourceArchive); path = $applicationSourceArchive; expectedSha256 = Get-PathSha256 $applicationSourceArchive; expectedLength = (Get-Item -LiteralPath $applicationSourceArchive).Length })
    $bundleEntries.Add([ordered]@{ name = 'evidence/candidate-manifest.json'; bytes = $candidateManifestBytes; expectedSha256 = $candidateManifestSha256; expectedLength = $candidateManifestLength })
    $bundleEntries.Add([ordered]@{ name = 'evidence/nlohmann-json-header.transform.json'; bytes = $nlohmannEvidenceBytes })
    $bundleEntries.Add([ordered]@{ name = 'evidence/dependency-archive/' + (Split-Path -Leaf $DependencyArchivePath); path = $DependencyArchivePath; expectedSha256 = ([string]$manifest.sharedInputs.dependencyArchive.sha256).ToUpperInvariant(); expectedLength = [long]$manifest.sharedInputs.dependencyArchive.length })
    $bundleEntries.Add([ordered]@{ name = 'evidence/task5/' + (Split-Path -Leaf $SevenZipRuntimeArchivePath); path = $SevenZipRuntimeArchivePath; expectedSha256 = ([string]$manifest.sharedInputs.sevenZipTask5.runtimeArchiveSha256).ToUpperInvariant(); expectedLength = [long]$manifest.sharedInputs.sevenZipTask5.runtimeArchiveLength })
    $bundleEntries.Add([ordered]@{ name = 'evidence/task5/' + (Split-Path -Leaf $SevenZipSourceArchivePath); path = $SevenZipSourceArchivePath; expectedSha256 = ([string]$manifest.sharedInputs.sevenZipTask5.sourceArchiveSha256).ToUpperInvariant(); expectedLength = [long]$manifest.sharedInputs.sevenZipTask5.sourceArchiveLength })
    $bundleEntries.Add([ordered]@{ name = 'evidence/task5/' + (Split-Path -Leaf $SevenZipVerificationPath); path = $SevenZipVerificationPath; expectedSha256 = ([string]$manifest.sharedInputs.sevenZipTask5.verificationSha256).ToUpperInvariant(); expectedLength = [long]$manifest.sharedInputs.sevenZipTask5.verificationLength })
    $bundleFileName = if ([string](Get-ObjectProperty $manifest 'approvalProfile') -ceq $productionApprovalProfile) { 'ytdlp-korean-interface-v2.19.1-karon.2-non-runtime-component-evidence.zip' } else { 'test-fixture-non-runtime-component-evidence.zip' }
    $bundlePath = Join-Path $OutputDirectory $bundleFileName
    New-DeterministicZip -OutputPath $bundlePath -Entries $bundleEntries.ToArray() -PrivateRoot $script:stagingRoot
    Write-Output $bundlePath
    exit 0
}
finally {
    foreach ($directory in $script:temporaryDirectories) {
        try {
            Assert-OwnedTemporaryDirectory $directory.path
            Remove-Item -LiteralPath $directory.path -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch { }
    }
}
