[CmdletBinding()]
param(
    [string] $ManifestPath,
    [string] $BinaryArchivePath = 'E:\03_AllWork\ytdlp-korean-interface\.quality-presets-work\karon2-input\immutable\ffmpeg-n9.0.1-30-g9258bacca5-win64-lgpl-9.0.zip',
    [string] $ScratchRoot = 'E:\03_AllWork\ytdlp-korean-interface\.scratch\task-6-ffmpeg-corresponding-sources',
    [string] $CacheRoot,
    [string] $BtbNCacheRoot = 'E:\03_AllWork\ytdlp-korean-interface\.scratch\task-6-actions-download-cache\extracted',
    [string] $Rav1eCrateCacheRoot = 'E:\03_AllWork\ytdlp-korean-interface\.scratch\task-6-rav1e-crates',
    [string] $ToolchainSourceRoot = 'E:\03_AllWork\ytdlp-korean-interface\.scratch\task-6-toolchain-sources',
    [switch] $NoExecute
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not ('KaronPathSafety' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

[StructLayout(LayoutKind.Sequential)]
internal struct KaronFileIdInfo
{
    public ulong VolumeSerialNumber;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
    public byte[] FileId;
}

[StructLayout(LayoutKind.Sequential)]
internal struct KaronByHandleFileInformation
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

[StructLayout(LayoutKind.Sequential)]
internal struct KaronFileDispositionInfo
{
    [MarshalAs(UnmanagedType.Bool)]
    public bool DeleteFile;
}

public sealed class KaronPathIdentity
{
    public string FinalPath { get; internal set; }
    public ulong VolumeSerialNumber { get; internal set; }
    public string FileId { get; internal set; }
    public uint FileAttributes { get; internal set; }
}

public sealed class KaronPathHandle : IDisposable
{
    public SafeFileHandle Handle { get; private set; }
    internal KaronPathHandle(SafeFileHandle handle) { Handle = handle; }
    public KaronPathIdentity Refresh() { return KaronPathSafety.ReadIdentity(Handle); }
    public void Dispose() { if (Handle != null) Handle.Dispose(); }
}

public static class KaronPathSafety
{
    private const uint GenericRead = 0x80000000;
    private const uint DeleteAccess = 0x00010000;
    private const uint FileReadAttributes = 0x00000080;
    private const uint FileShareRead = 0x00000001;
    private const uint FileShareWrite = 0x00000002;
    private const uint OpenExisting = 3;
    private const uint FileFlagBackupSemantics = 0x02000000;
    private const uint FileFlagOpenReparsePoint = 0x00200000;
    private const int FileIdInfo = 0x12;
    private const int FileDispositionInfo = 4;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(
        string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
        uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandleEx(
        SafeFileHandle file, int informationClass, out KaronFileIdInfo information, uint bufferSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle file, out KaronByHandleFileInformation information);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(
        SafeFileHandle file, StringBuilder path, uint pathLength, uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetFileInformationByHandle(
        SafeFileHandle file, int informationClass, ref KaronFileDispositionInfo information, uint bufferSize);

    public static KaronPathHandle Open(string path, bool readData, bool openReparsePoint)
    {
        return Open(path, readData, openReparsePoint, false);
    }

    public static KaronPathHandle Open(string path, bool readData, bool openReparsePoint, bool deleteAccess)
    {
        uint access = readData ? GenericRead : FileReadAttributes;
        if (deleteAccess) access |= DeleteAccess;
        uint share = readData ? FileShareRead : FileShareRead | FileShareWrite;
        uint flags = FileFlagBackupSemantics | (openReparsePoint ? FileFlagOpenReparsePoint : 0);
        SafeFileHandle handle = CreateFileW(path, access, share, IntPtr.Zero, OpenExisting, flags, IntPtr.Zero);
        if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFileW failed: " + path);
        return new KaronPathHandle(handle);
    }

    public static void MarkDelete(KaronPathHandle path)
    {
        KaronFileDispositionInfo information = new KaronFileDispositionInfo { DeleteFile = true };
        if (!SetFileInformationByHandle(path.Handle, FileDispositionInfo, ref information,
                (uint)Marshal.SizeOf(typeof(KaronFileDispositionInfo))))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "SetFileInformationByHandle(FileDispositionInfo) failed");
    }

    public static KaronPathIdentity ReadIdentity(SafeFileHandle handle)
    {
        KaronFileIdInfo id;
        if (!GetFileInformationByHandleEx(handle, FileIdInfo, out id, (uint)Marshal.SizeOf(typeof(KaronFileIdInfo))))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFileInformationByHandleEx(FileIdInfo) failed");
        KaronByHandleFileInformation basic;
        if (!GetFileInformationByHandle(handle, out basic))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFileInformationByHandle failed");
        StringBuilder path = new StringBuilder(1024);
        uint length = GetFinalPathNameByHandleW(handle, path, (uint)path.Capacity, 0);
        if (length == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFinalPathNameByHandleW failed");
        if (length >= path.Capacity)
        {
            path = new StringBuilder((int)length + 1);
            length = GetFinalPathNameByHandleW(handle, path, (uint)path.Capacity, 0);
            if (length == 0 || length >= path.Capacity)
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFinalPathNameByHandleW failed");
        }
        return new KaronPathIdentity {
            FinalPath = path.ToString(),
            VolumeSerialNumber = id.VolumeSerialNumber,
            FileId = BitConverter.ToString(id.FileId).Replace("-", ""),
            FileAttributes = basic.FileAttributes
        };
    }
}
'@
}

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $PSScriptRoot '..\release\runtime\v2.19.1-karon.2\ffmpeg\manifest.json'
}

function Get-UpperSha256 {
    param([string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-SourceArchiveHash {
    param([string] $Path, [string] $ExpectedSha256, [string] $ComponentId)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "ffmpeg_source_missing_archive:$ComponentId" }
    if ((Get-UpperSha256 $Path) -cne $ExpectedSha256.ToUpperInvariant()) { throw "ffmpeg_source_sha256_mismatch:$ComponentId" }
}

function Test-ImmutableSourceUrl {
    param([string] $Url)
    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref] $uri)) { return $false }
    if ($uri.Scheme -cne 'https' -or -not [string]::IsNullOrEmpty($uri.Query)) { return $false }
    if ($uri.AbsolutePath -match '(?i)/(main|master|latest|head)([/._-]|$)') { return $false }
    if ($uri.AbsolutePath -match '/actions/artifacts/[0-9]+/zip$') { return $true }
    if ($uri.Host -ceq 'static.crates.io' -and $uri.AbsolutePath -match '^/crates/[^/]+/[^/]+-[0-9][^/]*\.crate$') { return $true }
    if ($uri.AbsolutePath -match '(?i)(^|[/._-])[0-9a-f]{40}([/._-]|$)') { return $true }
    $uri.AbsolutePath -match '(?i)(^|/)(v?[0-9]+(?:\.[0-9]+){1,3}[^/]*)[/._-]|[-_]v?[0-9]+(?:\.[0-9]+){1,3}[^/]*\.(tar\.(xz|bz2|gz)|zip)$'
}

function Test-ExternalBuildOption {
    param([string] $Option)
    if ($Option -match '^--enable-lib[a-z0-9-]+$') { return $true }
    $Option -match '^--enable-(zlib|iconv|gmp|lzma|fontconfig|vulkan|opencl|amf|chromaprint|ffnvcodec|openal|sdl2|vaapi|lv2)$'
}

function Assert-SafeBundlePath {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path.IndexOf([char] 0) -ge 0 -or
        [IO.Path]::IsPathRooted($Path) -or $Path -match '^[A-Za-z]:' -or
        $Path -match '^[\\/]{2}' -or $Path.Contains(':')) {
        throw "ffmpeg_source_unsafe_bundle_path:$Path"
    }
    $normalized = $Path.Replace('\', '/')
    $segments = $normalized.Split([char] '/', [StringSplitOptions]::None)
    foreach ($segment in $segments) {
        if ([string]::IsNullOrEmpty($segment) -or $segment -match '[\x00-\x1F]' -or
            $segment -ceq '.' -or $segment -ceq '..' -or
            $segment -match '[ .]$' -or $segment.IndexOfAny([char[]] '<>"|?*') -ge 0 -or
            $segment -match '(?i)^(CON|PRN|AUX|NUL|COM(?:[1-9]|[¹²³])|LPT(?:[1-9]|[¹²³]))(?:\.|$)') {
            throw "ffmpeg_source_unsafe_bundle_path:$Path"
        }
    }
    $normalized.Normalize([Text.NormalizationForm]::FormC)
}

function ConvertTo-KaronFinalPath {
    param([string] $Path)
    if ($Path.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        $Path = '\\' + $Path.Substring(8)
    }
    elseif ($Path.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        $Path = $Path.Substring(4)
    }
    $full = [IO.Path]::GetFullPath($Path)
    $volumeRoot = [IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $volumeRoot.Length) { return $full.TrimEnd([char[]] @('\', '/')) }
    $full
}

function ConvertTo-KaronPathIdentity {
    param($Handle)
    if ($Handle -is [KaronPathHandle]) {
        $identity = $Handle.Refresh()
    }
    elseif ($Handle -is [Microsoft.Win32.SafeHandles.SafeFileHandle]) {
        $identity = [KaronPathSafety]::ReadIdentity($Handle)
    }
    else {
        throw 'ffmpeg_source_invalid_path_handle'
    }
    [pscustomobject][ordered]@{
        FinalPath = ConvertTo-KaronFinalPath $identity.FinalPath
        VolumeSerialNumber = [uint64] $identity.VolumeSerialNumber
        FileId = ([string] $identity.FileId).ToUpperInvariant()
        FileAttributes = [uint32] $identity.FileAttributes
    }
}

function Assert-KaronPathIdentity {
    param($Expected, $Actual, [string] $ErrorCode, [string] $Label)
    if (-not ([string] $Expected.FinalPath).Equals([string] $Actual.FinalPath, [StringComparison]::OrdinalIgnoreCase) -or
        [uint64] $Expected.VolumeSerialNumber -ne [uint64] $Actual.VolumeSerialNumber -or
        -not ([string] $Expected.FileId).Equals([string] $Actual.FileId, [StringComparison]::Ordinal) -or
        [uint32] $Expected.FileAttributes -ne [uint32] $Actual.FileAttributes) {
        throw "${ErrorCode}:$Label"
    }
}

function Get-KaronLexicalPathNodes {
    param([string] $Path)
    $full = [IO.Path]::GetFullPath($Path)
    $volumeRoot = [IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($volumeRoot)) { throw "ffmpeg_source_unsafe_filesystem_path:$Path" }
    $nodes = [Collections.Generic.List[string]]::new()
    $nodes.Add($volumeRoot) | Out-Null
    $current = $volumeRoot
    $relative = $full.Substring($volumeRoot.Length)
    foreach ($segment in @($relative -split '[\\/]' | Where-Object { $_.Length -gt 0 })) {
        $current = Join-Path $current $segment
        $nodes.Add([IO.Path]::GetFullPath($current)) | Out-Null
    }
    $nodes.ToArray()
}

function Close-KaronPathChain {
    param($Chain)
    if ($null -eq $Chain) { return }
    for ($index = $Chain.Nodes.Count - 1; $index -ge 0; $index--) {
        $Chain.Nodes[$index].Handle.Dispose()
    }
}

function Open-KaronPathChain {
    param(
        [string] $Path,
        [switch] $ReadFinal,
        [switch] $DeleteFinal,
        [string] $ReparseError = 'ffmpeg_source_source_root_escape'
    )
    $lexicalNodes = @(Get-KaronLexicalPathNodes $Path)
    $openedNodes = [Collections.Generic.List[object]]::new()
    try {
        for ($index = 0; $index -lt $lexicalNodes.Count; $index++) {
            $isFinal = $index -eq ($lexicalNodes.Count - 1)
            $handle = [KaronPathSafety]::Open(
                $lexicalNodes[$index],
                [bool] ($isFinal -and $ReadFinal),
                $true,
                [bool] ($isFinal -and $DeleteFinal)
            )
            try {
                $identity = ConvertTo-KaronPathIdentity $handle
                if (($identity.FileAttributes -band [uint32] [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "$ReparseError`:$($lexicalNodes[$index])"
                }
                $lexical = ConvertTo-KaronFinalPath $lexicalNodes[$index]
                if (-not $identity.FinalPath.Equals($lexical, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "$ReparseError`:$($lexicalNodes[$index])"
                }
                $openedNodes.Add([pscustomobject][ordered]@{
                    LexicalPath = $lexical
                    Handle = $handle
                    Identity = $identity
                }) | Out-Null
                $handle = $null
            }
            finally {
                if ($null -ne $handle) { $handle.Dispose() }
            }
        }
        [pscustomobject][ordered]@{
            Path = ConvertTo-KaronFinalPath $Path
            Nodes = @($openedNodes)
            Final = $openedNodes[$openedNodes.Count - 1]
        }
    }
    catch {
        for ($index = $openedNodes.Count - 1; $index -ge 0; $index--) { $openedNodes[$index].Handle.Dispose() }
        throw
    }
}

function Assert-KaronPathChainUnchanged {
    param($Chain, [string] $ErrorCode)
    foreach ($node in $Chain.Nodes) {
        $actual = ConvertTo-KaronPathIdentity $node.Handle
        Assert-KaronPathIdentity $node.Identity $actual $ErrorCode $node.LexicalPath
    }
}

function Assert-KaronPhysicalContainment {
    param($RootIdentity, $ChildIdentity, [string] $ErrorCode)
    $root = ConvertTo-KaronFinalPath ([string] $RootIdentity.FinalPath)
    $child = ConvertTo-KaronFinalPath ([string] $ChildIdentity.FinalPath)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if ([uint64] $RootIdentity.VolumeSerialNumber -ne [uint64] $ChildIdentity.VolumeSerialNumber -or
        (-not $child.Equals($root, [StringComparison]::OrdinalIgnoreCase) -and
         -not $child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw $ErrorCode
    }
}

function Assert-KaronDirectChild {
    param($ParentIdentity, $ChildIdentity, [string] $ErrorCode)
    if ([uint64] $ParentIdentity.VolumeSerialNumber -ne [uint64] $ChildIdentity.VolumeSerialNumber -or
        -not ([IO.Path]::GetDirectoryName([string] $ChildIdentity.FinalPath)).Equals(
            [string] $ParentIdentity.FinalPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw $ErrorCode
    }
}

function Assert-ExistingKaronAncestors {
    param([string] $Path, [string] $ReparseError)
    foreach ($node in @(Get-KaronLexicalPathNodes $Path)) {
        $handle = $null
        try {
            $handle = [KaronPathSafety]::Open($node, $false, $true)
            $identity = ConvertTo-KaronPathIdentity $handle
            if (($identity.FileAttributes -band [uint32] [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                -not $identity.FinalPath.Equals((ConvertTo-KaronFinalPath $node), [StringComparison]::OrdinalIgnoreCase)) {
                throw "$ReparseError`:$node"
            }
        }
        catch [ComponentModel.Win32Exception] {
            if ($_.Exception.NativeErrorCode -in @(2, 3)) { break }
            throw
        }
        finally {
            if ($null -ne $handle) { $handle.Dispose() }
        }
    }
}

function Open-VerifiedBundleSource {
    param($Item)
    $rootChain = $null
    $sourceChain = $null
    try {
        $rootChain = Open-KaronPathChain ([string] $Item.SourceRootPath) -ReparseError 'ffmpeg_source_source_root_escape'
        $sourceChain = Open-KaronPathChain ([string] $Item.SourcePath) -ReadFinal -ReparseError 'ffmpeg_source_source_root_escape'
        Assert-KaronPathIdentity $Item.RootIdentity $rootChain.Final.Identity 'ffmpeg_source_path_identity_changed' $Item.SourceRootPath
        Assert-KaronPathIdentity $Item.SourceIdentity $sourceChain.Final.Identity 'ffmpeg_source_path_identity_changed' $Item.SourcePath
        Assert-KaronPhysicalContainment $rootChain.Final.Identity $sourceChain.Final.Identity 'ffmpeg_source_source_root_escape'
        return [pscustomobject][ordered]@{ RootChain = $rootChain; SourceChain = $sourceChain }
    }
    catch {
        Close-KaronPathChain $sourceChain
        Close-KaronPathChain $rootChain
        throw
    }
}

function Close-VerifiedBundleSource {
    param($Opened)
    if ($null -eq $Opened) { return }
    Close-KaronPathChain $Opened.SourceChain
    Close-KaronPathChain $Opened.RootChain
}

function Copy-KaronHandleToStream {
    param([KaronPathHandle] $Handle, [IO.Stream] $Output)
    $borrowed = [Microsoft.Win32.SafeHandles.SafeFileHandle]::new($Handle.Handle.DangerousGetHandle(), $false)
    $input = [IO.FileStream]::new($borrowed, [IO.FileAccess]::Read, 65536, $false)
    try {
        [void] $input.Seek(0, [IO.SeekOrigin]::Begin)
        $input.CopyTo($Output)
    }
    finally { $input.Dispose(); $borrowed.Dispose() }
}

function Get-KaronHandleDigest {
    param([KaronPathHandle] $Handle)
    $borrowed = [Microsoft.Win32.SafeHandles.SafeFileHandle]::new($Handle.Handle.DangerousGetHandle(), $false)
    $input = [IO.FileStream]::new($borrowed, [IO.FileAccess]::Read, 65536, $false)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        [void] $input.Seek(0, [IO.SeekOrigin]::Begin)
        $bytes = $input.Length
        $sha = [Convert]::ToHexString($algorithm.ComputeHash($input))
        [pscustomobject][ordered]@{ Sha256 = $sha; Bytes = [int64] $bytes }
    }
    finally { $algorithm.Dispose(); $input.Dispose(); $borrowed.Dispose() }
}

function Read-KaronHandleUtf8 {
    param([KaronPathHandle] $Handle)
    $memory = [IO.MemoryStream]::new()
    try {
        Copy-KaronHandleToStream $Handle $memory
        [Text.UTF8Encoding]::new($false, $true).GetString($memory.ToArray())
    }
    finally { $memory.Dispose() }
}

function Resolve-ContainedSourcePath {
    param([string] $SourcePath, [string[]] $AllowedSourceRoots)
    if (-not [IO.File]::Exists($SourcePath)) { throw "ffmpeg_source_missing_bundle_input:$SourcePath" }
    $resolved = ConvertTo-KaronFinalPath $SourcePath
    foreach ($root in $AllowedSourceRoots) {
        if (-not [IO.Directory]::Exists($root)) { continue }
        $rootPath = ConvertTo-KaronFinalPath $root
        $prefix = $rootPath + [IO.Path]::DirectorySeparatorChar
        if ($resolved.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase) -or
            $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $rootChain = $null
            $sourceChain = $null
            try {
                $rootChain = Open-KaronPathChain $rootPath -ReparseError 'ffmpeg_source_source_root_escape'
                $sourceChain = Open-KaronPathChain $resolved -ReadFinal -ReparseError 'ffmpeg_source_source_root_escape'
                if (($rootChain.Final.Identity.FileAttributes -band [uint32] [IO.FileAttributes]::Directory) -eq 0 -or
                    ($sourceChain.Final.Identity.FileAttributes -band [uint32] [IO.FileAttributes]::Directory) -ne 0) {
                    throw "ffmpeg_source_source_root_escape:$SourcePath"
                }
                Assert-KaronPhysicalContainment $rootChain.Final.Identity $sourceChain.Final.Identity "ffmpeg_source_source_root_escape:$SourcePath"
                return [pscustomobject][ordered]@{
                    SourcePath = $sourceChain.Final.Identity.FinalPath
                    SourceRootPath = $rootChain.Final.Identity.FinalPath
                    SourceIdentity = $sourceChain.Final.Identity
                    RootIdentity = $rootChain.Final.Identity
                }
            }
            finally {
                Close-KaronPathChain $sourceChain
                Close-KaronPathChain $rootChain
            }
        }
    }
    throw "ffmpeg_source_source_root_escape:$SourcePath"
}

function Assert-BundleItems {
    param([object[]] $Items, [string[]] $AllowedSourceRoots)
    $seen = @{}
    foreach ($item in $Items) {
        $entryPath = Assert-SafeBundlePath ([string] $item.EntryPath)
        $key = $entryPath.Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { throw "ffmpeg_source_duplicate_path:$entryPath" }
        $seen[$key] = $true
        $location = Resolve-ContainedSourcePath ([string] $item.SourcePath) $AllowedSourceRoots
        if ($null -ne $item.PSObject.Properties['SourceIdentity']) {
            Assert-KaronPathIdentity $item.SourceIdentity $location.SourceIdentity 'ffmpeg_source_path_identity_changed' $entryPath
        }
        if ($null -ne $item.PSObject.Properties['RootIdentity']) {
            Assert-KaronPathIdentity $item.RootIdentity $location.RootIdentity 'ffmpeg_source_path_identity_changed' $entryPath
        }
        $sha = ([string] $item.Sha256).ToUpperInvariant()
        if ($sha -notmatch '^[0-9A-F]{64}$') { throw "ffmpeg_source_missing_sha256:$entryPath" }
        [pscustomobject][ordered]@{
            SourcePath = $location.SourcePath
            SourceRootPath = $location.SourceRootPath
            SourceIdentity = $location.SourceIdentity
            RootIdentity = $location.RootIdentity
            EntryPath = $entryPath
            Sha256 = $sha
            Bytes = [int64] $item.Bytes
        }
    }
}

function Get-GitBlobBytes {
    param([string] $RepositoryRoot, [string] $ObjectSpec)
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = 'git'
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-C', $RepositoryRoot, 'cat-file', 'blob', $ObjectSpec)) { [void] $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    [void] $process.Start()
    $buffer = [IO.MemoryStream]::new()
    try {
        $process.StandardOutput.BaseStream.CopyTo($buffer)
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw "ffmpeg_source_git_license_blob_missing:$ObjectSpec`n$errorText" }
        return ,$buffer.ToArray()
    }
    finally {
        $buffer.Dispose()
        $process.Dispose()
    }
}

function Assert-GitLicenseCorpus {
    param($Corpus, [string] $ManifestRoot, [string] $Revision = 'HEAD')
    $repositoryRoot = @(& git -C $ManifestRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $repositoryRoot.Count -ne 1) { throw 'ffmpeg_source_git_repository_unavailable' }
    $repositoryRoot = $repositoryRoot[0].Trim()
    $relativeManifestRoot = [IO.Path]::GetRelativePath($repositoryRoot, [IO.Path]::GetFullPath($ManifestRoot)).Replace('\', '/')
    if ($relativeManifestRoot -eq '..' -or $relativeManifestRoot.StartsWith('../', [StringComparison]::Ordinal)) {
        throw 'ffmpeg_source_git_repository_unavailable'
    }
    $trackedRoot = "$relativeManifestRoot/licenses/extracted"
    $tracked = @(& git -C $repositoryRoot ls-tree -r --name-only $Revision -- $trackedRoot)
    if ($LASTEXITCODE -ne 0) { throw 'ffmpeg_source_git_license_tree_unavailable' }
    $trackedSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $tracked) { [void] $trackedSet.Add($path) }
    if ($trackedSet.Count -ne [int] $Corpus.textObjectCount) { throw 'ffmpeg_source_git_license_tree_count_mismatch' }
    foreach ($text in @($Corpus.textObjects)) {
        $bundlePath = Assert-SafeBundlePath ([string] $text.bundlePath)
        if (-not $bundlePath.StartsWith('licenses/extracted/', [StringComparison]::Ordinal)) {
            throw "ffmpeg_source_invalid_license_path:$bundlePath"
        }
        $repositoryPath = "$relativeManifestRoot/$bundlePath"
        if (-not $trackedSet.Contains($repositoryPath)) { throw "ffmpeg_source_git_license_blob_missing:$repositoryPath" }
        $bytes = Get-GitBlobBytes $repositoryRoot "${Revision}:$repositoryPath"
        $sha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
        if ($sha -cne ([string] $text.sha256).ToUpperInvariant() -or $bytes.Length -ne [int64] $text.bytes) {
            throw "ffmpeg_source_git_license_blob_mismatch:$repositoryPath"
        }
    }
    [pscustomobject][ordered]@{ revision = $Revision; verifiedBlobCount = $trackedSet.Count }
}

function Assert-LicenseCorpus {
    param($Corpus, [string] $ManifestRoot, [switch] $VerifyFiles)
    $refs = @{}
    foreach ($text in @($Corpus.textObjects)) {
        $sha = ([string] $text.sha256).ToUpperInvariant()
        $ref = [string] $text.licenseRef
        if ($sha -notmatch '^[0-9A-F]{64}$' -or $ref -cne ('LicenseRef-' + $sha.Substring(0, 16).ToLowerInvariant())) {
            throw 'ffmpeg_source_invalid_license_ref'
        }
        if ($refs.ContainsKey($sha)) { throw "ffmpeg_source_duplicate_license_text:$sha" }
        $refs[$sha] = $ref
        if ($VerifyFiles) {
            $path = Join-Path $ManifestRoot (Assert-SafeBundlePath ([string] $text.bundlePath))
            Assert-SourceArchiveHash $path $sha $ref
            if ((Get-Item -LiteralPath $path).Length -ne [int64] $text.bytes) { throw "ffmpeg_source_license_length_mismatch:$ref" }
        }
    }
    if ($refs.Count -cne [int] $Corpus.textObjectCount) { throw 'ffmpeg_source_license_corpus_count_mismatch' }
    $refs
}

function Assert-LicenseRecord {
    param($License, [string] $Id, [hashtable] $Refs)
    $expression = [string] $License.expression
    if ([string]::IsNullOrWhiteSpace($expression) -or $expression -match 'NOASSERTION' -or @($License.files).Count -eq 0) {
        throw "ffmpeg_source_missing_license:$Id"
    }
    foreach ($file in @($License.files)) {
        $sha = ([string] $file.sha256).ToUpperInvariant()
        $ref = [string] $file.licenseRef
        if (-not $Refs.ContainsKey($sha) -or $Refs[$sha] -cne $ref -or $expression -notmatch [regex]::Escape($ref)) {
            throw "ffmpeg_source_missing_license:$Id"
        }
    }
}

function Assert-FfmpegClosureMetadata {
    param($Manifest, $Graph, $Crates, $Toolchain, $Corpus, [string[]] $Options)
    foreach ($forbidden in @('--enable-gpl', '--enable-nonfree')) {
        if ($Options -ccontains $forbidden) { throw "ffmpeg_source_forbidden_configuration:$forbidden" }
    }
    foreach ($required in @('--pkg-config-flags=--static', '--enable-version3')) {
        if ($Options -cnotcontains $required) { throw "ffmpeg_source_configuration_mismatch:$required" }
    }
    if ([string] $Manifest.closureStatus -cne 'complete' -or @($Manifest.unresolvedItems).Count -ne 0) { throw 'ffmpeg_source_closure_incomplete' }

    $included = @{}
    foreach ($path in @($Manifest.includedPaths)) {
        $key = ([string] $path).ToLowerInvariant()
        if ($included.ContainsKey($key)) { throw "ffmpeg_source_duplicate_path:$path" }
        $included[$key] = $true
    }
    foreach ($name in @('ffmpeg', 'btbnScripts', 'spdxLicenseList')) {
        $source = $Manifest.sourceSets.$name
        if (-not (Test-ImmutableSourceUrl ([string] $source.url))) { throw "ffmpeg_source_mutable_url:$name" }
        if ([string] $source.sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw "ffmpeg_source_missing_sha256:$name" }
        if ([string]::IsNullOrWhiteSpace([string] $source.licenseExpression) -or [string] $source.licenseExpression -match 'NOASSERTION') {
            throw "ffmpeg_source_missing_license:$name"
        }
    }

    $refs = Assert-LicenseCorpus $Corpus ''
    $components = @{}
    foreach ($component in @($Graph.components)) {
        $id = [string] $component.id
        $key = $id.ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($id) -or $components.ContainsKey($key)) { throw "ffmpeg_source_duplicate_component:$id" }
        $components[$key] = $true
        if ([string] $component.applicability -cne 'conservative-superset') { throw "ffmpeg_source_invalid_applicability:$id" }
        if (-not (Test-ImmutableSourceUrl ([string] $component.source.url))) { throw "ffmpeg_source_mutable_url:$id" }
        if ([string] $component.source.sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw "ffmpeg_source_missing_sha256:$id" }
        Assert-LicenseRecord $component.license $id $refs
        if ([string]::IsNullOrWhiteSpace([string] $component.recipe.scriptPath) -or [string] $component.recipe.scriptSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
            throw "ffmpeg_source_missing_recipe:$id"
        }
        foreach ($patch in @($component.recipe.patches)) {
            if ([string]::IsNullOrWhiteSpace([string] $patch.path) -or [string] $patch.sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
                throw "ffmpeg_source_missing_patch:$id"
            }
        }
    }
    if ($components.Count -cne 122 -or $components.Count -cne [int] $Manifest.counts.btbnCacheArchives) {
        throw 'ffmpeg_source_cache_component_count_mismatch'
    }

    if (@($Graph.nestedClosures).Count -cne 19) { throw 'ffmpeg_source_nested_closure_count_mismatch' }
    foreach ($closure in @($Graph.nestedClosures)) {
        if ([string] $closure.applicability -cne 'conservative-superset' -or
            -not $components.ContainsKey(([string] $closure.componentId).ToLowerInvariant()) -or
            @($closure.gitmodules).Count -eq 0 -or @($closure.licenseFiles).Count -eq 0) {
            throw "ffmpeg_source_nested_closure_incomplete:$($closure.componentId)"
        }
    }

    $toolIds = @{}
    foreach ($component in @($Toolchain.components)) {
        $id = [string] $component.id
        $key = $id.ToLowerInvariant()
        if ($toolIds.ContainsKey($key)) { throw "ffmpeg_source_duplicate_component:$id" }
        $toolIds[$key] = $true
        $versionTag = [string] $component.source.url -match '/archive/refs/tags/v?[0-9]'
        if ([string] $component.applicability -cne 'conservative-superset' -or
            -not ((Test-ImmutableSourceUrl ([string] $component.source.url)) -or $versionTag)) {
            throw "ffmpeg_source_mutable_url:$id"
        }
        if ([string] $component.source.sha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw "ffmpeg_source_missing_sha256:$id" }
        Assert-LicenseRecord $component.license $id $refs
        if ([string]::IsNullOrWhiteSpace([string] $component.recipe.dockerfilePath) -or
            [string]::IsNullOrWhiteSpace([string] $component.recipe.configPath)) {
            throw "ffmpeg_source_missing_recipe:$id"
        }
        foreach ($patch in @($component.recipe.patches)) {
            if ([string]::IsNullOrWhiteSpace([string] $patch.path) -or [string] $patch.sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
                throw "ffmpeg_source_missing_patch:$id"
            }
        }
    }
    foreach ($id in @('toolchain-gcc-16.2.0', 'toolchain-mingw-w64-v14.0.0', 'toolchain-crosstool-ng-b1a94f65')) {
        if (-not $toolIds.ContainsKey($id)) { throw "ffmpeg_source_missing_toolchain:$id" }
    }
    if ($toolIds.Count -cne 12 -or -not [bool] $Toolchain.crosstool.libgompEnabled) { throw 'ffmpeg_source_toolchain_incomplete' }
    if ([string] $Toolchain.baseImage.dockerfileInputStatus -cne 'mutable-upstream-input-retained-not-reproducibly-pinned') {
        throw 'ffmpeg_source_toolchain_provenance_overclaim'
    }

    if (@($Crates.components).Count -cne 270) { throw 'ffmpeg_source_crate_count_mismatch' }
    $crateIds = @{}
    $rav1eCorpus = @{}
    $rav1eReferenceCount = 0
    foreach ($record in @($Corpus.rav1eComponents)) {
        $recordId = [string] $record.componentId
        $recordKey = $recordId.ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($recordId) -or $rav1eCorpus.ContainsKey($recordKey)) { throw "ffmpeg_source_duplicate_component:$recordId" }
        $rav1eCorpus[$recordKey] = $record
        $rav1eReferenceCount += @($record.licenseFiles).Count
    }
    if ($rav1eCorpus.Count -cne 270 -or $rav1eReferenceCount -cne 492 -or
        [int] $Corpus.textObjectCount -cne 681 -or [int] $Corpus.licenseFileReferenceCount -cne 1750) {
        throw 'ffmpeg_source_rav1e_license_corpus_incomplete'
    }
    foreach ($crate in @($Crates.components)) {
        $id = "$($crate.name)@$($crate.version)"
        $key = $id.ToLowerInvariant()
        if ($crateIds.ContainsKey($key)) { throw "ffmpeg_source_duplicate_component:$id" }
        $crateIds[$key] = $true
        if (-not (Test-ImmutableSourceUrl ([string] $crate.sourceUrl)) -or
            [string] $crate.sha256 -notmatch '^[0-9A-Fa-f]{64}$' -or
            [string]::IsNullOrWhiteSpace([string] $crate.licenseExpression) -or
            [string] $crate.licenseExpression -match 'NOASSERTION' -or @($crate.licenseTextPaths).Count -eq 0 -or
            -not $rav1eCorpus.ContainsKey($key)) {
            throw "ffmpeg_source_missing_license:$id"
        }
        $record = $rav1eCorpus[$key]
        if ([string] $record.sha256 -cne ([string] $crate.sha256).ToUpperInvariant() -or
            @($record.licenseFiles).Count -ne @($crate.licenseFiles).Count) { throw "ffmpeg_source_missing_license:$id" }
        $licenseFiles = @($crate.licenseFiles)
        if ($licenseFiles.Count -eq 0) {
            foreach ($textPath in @($crate.licenseTextPaths)) {
                if ([string] $textPath.kind -cne 'spdx-standard-text' -or
                    -not ([string] $textPath.path).StartsWith('licenses/spdx/', [StringComparison]::Ordinal) -or
                    @($Manifest.includedPaths) -cnotcontains [string] $textPath.path) {
                    throw "ffmpeg_source_missing_license:$id"
                }
            }
        }
        foreach ($file in $licenseFiles) {
            $sha = ([string] $file.sha256).ToUpperInvariant()
            $ref = [string] $file.licenseRef
            if (-not $refs.ContainsKey($sha) -or $refs[$sha] -cne $ref -or
                [string] $file.bundlePath -cne "licenses/extracted/$sha.txt" -or
                [string] $crate.licenseRefExpression -notmatch [regex]::Escape($ref)) {
                throw "ffmpeg_source_missing_license:$id"
            }
        }
    }

    $mapped = @{}
    foreach ($mapping in @($Manifest.enabledExternalLibraries)) {
        $option = [string] $mapping.option
        if ($mapped.ContainsKey($option)) { throw "ffmpeg_source_duplicate_option:$option" }
        if (-not $components.ContainsKey(([string] $mapping.componentId).ToLowerInvariant())) { throw "ffmpeg_source_unknown_component:$option" }
        $mapped[$option] = $true
    }
    foreach ($option in $Options) {
        if ((Test-ExternalBuildOption $option) -and -not $mapped.ContainsKey($option)) {
            throw "ffmpeg_source_unknown_enabled_library:$option"
        }
    }
}

function Read-FfmpegBinaryEvidence {
    param([string] $ArchivePath, [string] $ArchiveSha, [string] $FfmpegSha, [string] $FfprobeSha, [string] $ExpectedVersion)
    Assert-SourceArchiveHash $ArchivePath $ArchiveSha binary-archive
    $root = Join-Path ([IO.Path]::GetTempPath()) ('karon-ffmpeg-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($root) | Out-Null
    try {
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $root
        $ffmpeg = @(Get-ChildItem -LiteralPath $root -Filter ffmpeg.exe -File -Recurse)
        $ffprobe = @(Get-ChildItem -LiteralPath $root -Filter ffprobe.exe -File -Recurse)
        if ($ffmpeg.Count -cne 1 -or $ffprobe.Count -cne 1) { throw 'ffmpeg_source_binary_layout_mismatch' }
        Assert-SourceArchiveHash $ffmpeg[0].FullName $FfmpegSha ffmpeg
        Assert-SourceArchiveHash $ffprobe[0].FullName $FfprobeSha ffprobe
        $buildconf = @(& $ffmpeg[0].FullName -hide_banner -buildconf 2>&1 | ForEach-Object ToString)
        $version = @(& $ffmpeg[0].FullName -hide_banner -version 2>&1 | ForEach-Object ToString)
        if ($LASTEXITCODE -ne 0 -or $version[0] -notmatch ('^ffmpeg version ' + [regex]::Escape($ExpectedVersion) + '([-\s]|$)')) {
            throw 'ffmpeg_source_binary_version_mismatch'
        }
        [pscustomobject][ordered]@{
            archiveSha256 = Get-UpperSha256 $ArchivePath
            ffmpegSha256 = Get-UpperSha256 $ffmpeg[0].FullName
            ffprobeSha256 = Get-UpperSha256 $ffprobe[0].FullName
            versionLine = $version[0]
            configurationOptions = @($buildconf | ForEach-Object Trim | Where-Object { $_ -match '^--' })
            rawBuildConfiguration = $buildconf -join ([char]10)
        }
    }
    finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}

function Add-FileToContentCache {
    param([string] $SourcePath, [string] $Sha, [string] $Id, [string] $Root)
    Assert-SourceArchiveHash $SourcePath $Sha $Id
    $shaUpper = $Sha.ToUpperInvariant()
    $directory = Join-Path (Join-Path $Root sha256) $shaUpper.Substring(0, 2)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $destination = Join-Path $directory $shaUpper
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        try { New-Item -ItemType HardLink -Path $destination -Target $SourcePath | Out-Null }
        catch { Copy-Item -LiteralPath $SourcePath -Destination $destination }
    }
    Assert-SourceArchiveHash $destination $shaUpper $Id
    $destination
}

function Get-VerifiedRemoteSource {
    param($Component, [string] $ContentRoot, [string] $SeedRoot)
    $id = [string] $Component.id
    $source = $Component.source
    $sha = ([string] $source.sha256).ToUpperInvariant()
    $directory = Join-Path (Join-Path $ContentRoot sha256) $sha.Substring(0, 2)
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $destination = Join-Path $directory $sha
    if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
        $seed = $null
        if ($SeedRoot -and $source.archiveName) {
            $candidate = Join-Path $SeedRoot ([string] $source.archiveName)
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $seed = $candidate }
        }
        if ($seed) { $destination = Add-FileToContentCache $seed $sha $id $ContentRoot }
        else {
            $versionTag = [string] $source.url -match '/archive/refs/tags/v?[0-9]'
            if (-not ((Test-ImmutableSourceUrl ([string] $source.url)) -or $versionTag)) { throw "ffmpeg_source_mutable_url:$id" }
            $temporary = $destination + '.partial.' + [Guid]::NewGuid().ToString('N')
            try {
                Invoke-WebRequest -UseBasicParsing -Uri ([string] $source.url) -OutFile $temporary
                Assert-SourceArchiveHash $temporary $sha $id
                Move-Item -LiteralPath $temporary -Destination $destination
            }
            finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
        }
    }
    Assert-SourceArchiveHash $destination $sha $id
    [pscustomobject]@{ id = $id; sha256 = $sha; bytes = (Get-Item -LiteralPath $destination).Length; path = $destination; bundlePath = [string] $Component.bundlePath }
}

function New-BundleItem {
    param([string] $SourcePath, [string] $EntryPath, [string] $Sha)
    [pscustomobject]@{
        SourcePath = $SourcePath
        EntryPath = $EntryPath
        Sha256 = $(if ($Sha) { $Sha.ToUpperInvariant() } else { Get-UpperSha256 $SourcePath })
        Bytes = (Get-Item -LiteralPath $SourcePath).Length
    }
}

function Assert-OwnedBundleSnapshot {
    param($Snapshot)
    $root = [IO.Path]::GetFullPath([string] $Snapshot.Root)
    $parent = [IO.Path]::GetFullPath([string] $Snapshot.Parent).TrimEnd('\', '/')
    if ([IO.Path]::GetDirectoryName($root) -cne $parent -or
        -not [IO.Path]::GetFileName($root).StartsWith('ffmpeg-bundle-stage-', [StringComparison]::Ordinal)) {
        throw 'ffmpeg_source_snapshot_ownership_mismatch'
    }
    $access = Open-VerifiedBundleSnapshot $Snapshot
    try { $root }
    finally { Close-VerifiedBundleSnapshot $access }
}

function Close-VerifiedBundleSnapshot {
    param($Access)
    if ($null -eq $Access) { return }
    if ($null -ne $Access.OwnerHandle) { $Access.OwnerHandle.Dispose() }
    Close-KaronPathChain $Access.RootChain
    Close-KaronPathChain $Access.ParentChain
}

function Open-VerifiedBundleSnapshot {
    param($Snapshot, [switch] $ForCleanup)
    $root = [IO.Path]::GetFullPath([string] $Snapshot.Root)
    $parent = [IO.Path]::GetFullPath([string] $Snapshot.Parent).TrimEnd('\', '/')
    if ([IO.Path]::GetDirectoryName($root) -cne $parent -or
        -not [IO.Path]::GetFileName($root).StartsWith('ffmpeg-bundle-stage-', [StringComparison]::Ordinal)) {
        throw 'ffmpeg_source_snapshot_ownership_mismatch'
    }
    $parentChain = $null
    $rootChain = $null
    $ownerHandle = $null
    try {
        $parentChain = Open-KaronPathChain $parent -ReparseError 'ffmpeg_source_snapshot_reparse_point'
        $rootChain = Open-KaronPathChain $root -DeleteFinal:$ForCleanup -ReparseError 'ffmpeg_source_snapshot_reparse_point'
        $marker = Join-Path $root '.owner'
        $ownerHandle = [KaronPathSafety]::Open($marker, $true, $true, [bool] $ForCleanup)
        $ownerIdentity = ConvertTo-KaronPathIdentity $ownerHandle
        if (($ownerIdentity.FileAttributes -band [uint32] [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            -not $ownerIdentity.FinalPath.Equals((ConvertTo-KaronFinalPath $marker), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'ffmpeg_source_snapshot_reparse_point'
        }
        if (($parentChain.Final.Identity.FileAttributes -band [uint32] [IO.FileAttributes]::Directory) -eq 0 -or
            ($rootChain.Final.Identity.FileAttributes -band [uint32] [IO.FileAttributes]::Directory) -eq 0 -or
            ($ownerIdentity.FileAttributes -band [uint32] [IO.FileAttributes]::Directory) -ne 0) {
            throw 'ffmpeg_source_snapshot_ownership_mismatch'
        }
        Assert-KaronDirectChild $parentChain.Final.Identity $rootChain.Final.Identity 'ffmpeg_source_snapshot_ownership_mismatch'
        Assert-KaronDirectChild $rootChain.Final.Identity $ownerIdentity 'ffmpeg_source_snapshot_ownership_mismatch'
        foreach ($property in @('ParentIdentity', 'RootIdentity', 'OwnerIdentity')) {
            if ($null -eq $Snapshot.PSObject.Properties[$property]) { throw 'ffmpeg_source_snapshot_ownership_mismatch' }
        }
        Assert-KaronPathIdentity $Snapshot.ParentIdentity $parentChain.Final.Identity 'ffmpeg_source_snapshot_identity_changed' $parent
        Assert-KaronPathIdentity $Snapshot.RootIdentity $rootChain.Final.Identity 'ffmpeg_source_snapshot_identity_changed' $root
        Assert-KaronPathIdentity $Snapshot.OwnerIdentity $ownerIdentity 'ffmpeg_source_snapshot_identity_changed' $marker
        if ((Read-KaronHandleUtf8 $ownerHandle) -cne [string] $Snapshot.Token) {
            throw 'ffmpeg_source_snapshot_ownership_mismatch'
        }
        Assert-KaronPathChainUnchanged $parentChain 'ffmpeg_source_snapshot_identity_changed'
        Assert-KaronPathChainUnchanged $rootChain 'ffmpeg_source_snapshot_identity_changed'
        Assert-KaronPathIdentity $ownerIdentity (ConvertTo-KaronPathIdentity $ownerHandle) 'ffmpeg_source_snapshot_identity_changed' $marker
        return [pscustomobject][ordered]@{
            Root = $root
            Parent = $parent
            Marker = $marker
            ParentChain = $parentChain
            RootChain = $rootChain
            OwnerHandle = $ownerHandle
            OwnerIdentity = $ownerIdentity
        }
    }
    catch {
        if ($null -ne $ownerHandle) { $ownerHandle.Dispose() }
        Close-KaronPathChain $rootChain
        Close-KaronPathChain $parentChain
        throw
    }
}

function Remove-VerifiedBundleSnapshot {
    param($Snapshot)
    $access = Open-VerifiedBundleSnapshot $Snapshot -ForCleanup
    $childHandles = [Collections.Generic.List[object]]::new()
    try {
        if ($null -eq $Snapshot.PSObject.Properties['CreatedLeafIdentities']) {
            throw 'ffmpeg_source_snapshot_ownership_mismatch'
        }
        $expected = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $expected.Add('.owner') | Out-Null
        foreach ($createdLeaf in @($Snapshot.CreatedLeafIdentities)) {
            if (-not $expected.Add([string] $createdLeaf.Name)) { throw 'ffmpeg_source_snapshot_ownership_mismatch' }
        }
        $actual = @([IO.Directory]::EnumerateFileSystemEntries($access.Root))
        if ($actual.Count -ne $expected.Count) { throw 'ffmpeg_source_snapshot_ownership_mismatch' }
        foreach ($path in $actual) {
            if (-not $expected.Contains([IO.Path]::GetFileName($path))) { throw 'ffmpeg_source_snapshot_ownership_mismatch' }
        }

        foreach ($createdLeaf in @($Snapshot.CreatedLeafIdentities)) {
            $path = Join-Path $access.Root ([string] $createdLeaf.Name)
            $handle = [KaronPathSafety]::Open($path, $true, $true, $true)
            try {
                $identity = ConvertTo-KaronPathIdentity $handle
                if (($identity.FileAttributes -band [uint32] [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                    ($identity.FileAttributes -band [uint32] [IO.FileAttributes]::Directory) -ne 0) {
                    throw 'ffmpeg_source_snapshot_reparse_point'
                }
                Assert-KaronDirectChild $access.RootChain.Final.Identity $identity 'ffmpeg_source_snapshot_ownership_mismatch'
                Assert-KaronPathIdentity $createdLeaf.Identity $identity 'ffmpeg_source_snapshot_identity_changed' $path
                $childHandles.Add([pscustomobject]@{ Handle = $handle; Identity = $identity; Path = $path }) | Out-Null
                $handle = $null
            }
            finally { if ($null -ne $handle) { $handle.Dispose() } }
        }

        Assert-KaronPathChainUnchanged $access.ParentChain 'ffmpeg_source_snapshot_identity_changed'
        Assert-KaronPathChainUnchanged $access.RootChain 'ffmpeg_source_snapshot_identity_changed'
        Assert-KaronPathIdentity $access.OwnerIdentity (ConvertTo-KaronPathIdentity $access.OwnerHandle) 'ffmpeg_source_snapshot_identity_changed' $access.Marker
        foreach ($child in $childHandles) {
            Assert-KaronPathIdentity $child.Identity (ConvertTo-KaronPathIdentity $child.Handle) 'ffmpeg_source_snapshot_identity_changed' $child.Path
        }

        foreach ($child in $childHandles) { [KaronPathSafety]::MarkDelete($child.Handle) }
        for ($index = $childHandles.Count - 1; $index -ge 0; $index--) { $childHandles[$index].Handle.Dispose() }
        $childHandles.Clear()
        [KaronPathSafety]::MarkDelete($access.OwnerHandle)
        $access.OwnerHandle.Dispose()
        $access.OwnerHandle = $null
        if (@([IO.Directory]::EnumerateFileSystemEntries($access.Root)).Count -ne 0) {
            throw 'ffmpeg_source_snapshot_ownership_mismatch'
        }
        Assert-KaronPathChainUnchanged $access.ParentChain 'ffmpeg_source_snapshot_identity_changed'
        Assert-KaronPathChainUnchanged $access.RootChain 'ffmpeg_source_snapshot_identity_changed'
        [KaronPathSafety]::MarkDelete($access.RootChain.Final.Handle)
        Close-KaronPathChain $access.RootChain
        $access.RootChain = $null
        Assert-KaronPathChainUnchanged $access.ParentChain 'ffmpeg_source_snapshot_identity_changed'
    }
    finally {
        for ($index = $childHandles.Count - 1; $index -ge 0; $index--) { $childHandles[$index].Handle.Dispose() }
        Close-VerifiedBundleSnapshot $access
    }
}

function New-VerifiedBundleSnapshot {
    param([object[]] $Items, [string] $StagingParent, [string[]] $AllowedSourceRoots)
    $validated = @(Assert-BundleItems $Items $AllowedSourceRoots)
    $parent = [IO.Path]::GetFullPath($StagingParent)
    Assert-ExistingKaronAncestors $parent 'ffmpeg_source_snapshot_reparse_point'
    [IO.Directory]::CreateDirectory($parent) | Out-Null
    $parentChain = $null
    $rootChain = $null
    $ownerHandle = $null
    $snapshot = $null
    $failure = $null
    try {
        $parentChain = Open-KaronPathChain $parent -ReparseError 'ffmpeg_source_snapshot_reparse_point'
        $token = [Guid]::NewGuid().ToString('N')
        $root = Join-Path $parent "ffmpeg-bundle-stage-$token"
        [IO.Directory]::CreateDirectory($root) | Out-Null
        $rootChain = Open-KaronPathChain $root -ReparseError 'ffmpeg_source_snapshot_reparse_point'
        Assert-KaronDirectChild $parentChain.Final.Identity $rootChain.Final.Identity 'ffmpeg_source_snapshot_ownership_mismatch'
        $marker = Join-Path $root '.owner'
        [IO.File]::WriteAllText($marker, $token, [Text.UTF8Encoding]::new($false))
        $ownerHandle = [KaronPathSafety]::Open($marker, $true, $true)
        $ownerIdentity = ConvertTo-KaronPathIdentity $ownerHandle
        if (($ownerIdentity.FileAttributes -band [uint32] [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'ffmpeg_source_snapshot_reparse_point'
        }
        Assert-KaronDirectChild $rootChain.Final.Identity $ownerIdentity 'ffmpeg_source_snapshot_ownership_mismatch'
        $snapshot = [pscustomobject][ordered]@{
            Root = $root
            Parent = $parent
            Token = $token
            ParentIdentity = $parentChain.Final.Identity
            RootIdentity = $rootChain.Final.Identity
            OwnerIdentity = $ownerIdentity
            CreatedLeafIdentities = @()
            Items = @()
        }

        $index = 0
        foreach ($item in @($validated | Sort-Object @{Expression = { $_.EntryPath.ToLowerInvariant() }}, @{Expression = { $_.EntryPath }})) {
            $destination = Join-Path $root ('{0:D8}.bin' -f $index)
            $openedSource = $null
            $output = $null
            try {
                $openedSource = Open-VerifiedBundleSource $item
                $output = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                $createdIdentity = ConvertTo-KaronPathIdentity $output.SafeFileHandle
                $snapshot.CreatedLeafIdentities = @($snapshot.CreatedLeafIdentities) + [pscustomobject][ordered]@{
                    Name = [IO.Path]::GetFileName($destination)
                    Identity = $createdIdentity
                }
                Assert-KaronDirectChild $rootChain.Final.Identity $createdIdentity 'ffmpeg_source_snapshot_ownership_mismatch'
                Copy-KaronHandleToStream $openedSource.SourceChain.Final.Handle $output
            }
            finally {
                if ($null -ne $output) { $output.Dispose() }
            }
            try {
                Assert-KaronPathChainUnchanged $openedSource.RootChain 'ffmpeg_source_path_identity_changed'
                Assert-KaronPathChainUnchanged $openedSource.SourceChain 'ffmpeg_source_path_identity_changed'
                Assert-KaronPathIdentity $item.RootIdentity $openedSource.RootChain.Final.Identity 'ffmpeg_source_path_identity_changed' $item.SourceRootPath
                Assert-KaronPathIdentity $item.SourceIdentity $openedSource.SourceChain.Final.Identity 'ffmpeg_source_path_identity_changed' $item.SourcePath
            }
            finally { Close-VerifiedBundleSource $openedSource }

            $stagedHandle = [KaronPathSafety]::Open($destination, $true, $true)
            try {
                $stagedIdentity = ConvertTo-KaronPathIdentity $stagedHandle
                if (($stagedIdentity.FileAttributes -band [uint32] [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'ffmpeg_source_snapshot_reparse_point'
                }
                Assert-KaronDirectChild $rootChain.Final.Identity $stagedIdentity 'ffmpeg_source_snapshot_ownership_mismatch'
                Assert-KaronPathIdentity $createdIdentity $stagedIdentity 'ffmpeg_source_snapshot_identity_changed' $destination
                $digest = Get-KaronHandleDigest $stagedHandle
                if ($digest.Sha256 -cne $item.Sha256 -or $digest.Bytes -ne $item.Bytes) {
                    throw "ffmpeg_source_staged_sha256_mismatch:$($item.EntryPath)"
                }
                $stagedItem = [pscustomobject][ordered]@{
                    SourcePath = $stagedIdentity.FinalPath
                    SourceRootPath = $rootChain.Final.Identity.FinalPath
                    SourceIdentity = $stagedIdentity
                    RootIdentity = $rootChain.Final.Identity
                    EntryPath = $item.EntryPath
                    Sha256 = $digest.Sha256
                    Bytes = $digest.Bytes
                }
            }
            finally { $stagedHandle.Dispose() }
            $snapshot.Items = @($snapshot.Items) + $stagedItem
            $index++
        }
        Assert-KaronPathChainUnchanged $parentChain 'ffmpeg_source_snapshot_identity_changed'
        Assert-KaronPathChainUnchanged $rootChain 'ffmpeg_source_snapshot_identity_changed'
        Assert-KaronPathIdentity $ownerIdentity (ConvertTo-KaronPathIdentity $ownerHandle) 'ffmpeg_source_snapshot_identity_changed' $marker
        if ((Read-KaronHandleUtf8 $ownerHandle) -cne $token) { throw 'ffmpeg_source_snapshot_ownership_mismatch' }
    }
    catch { $failure = $_ }
    finally {
        if ($null -ne $ownerHandle) { $ownerHandle.Dispose() }
        Close-KaronPathChain $rootChain
        Close-KaronPathChain $parentChain
    }
    if ($null -ne $failure) {
        if ($null -ne $snapshot) {
            try { Remove-VerifiedBundleSnapshot $snapshot } catch { }
        }
        throw $failure
    }
    $snapshot
}

function Assert-ZipMatchesItems {
    param([string] $ZipPath, [object[]] $Items)
    Add-Type -AssemblyName System.IO.Compression
    $expected = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($item in $Items) {
        $path = Assert-SafeBundlePath ([string] $item.EntryPath)
        if ($expected.ContainsKey($path)) { throw "ffmpeg_source_duplicate_path:$path" }
        $expected.Add($path, $item)
    }
    $stream = [IO.File]::Open($ZipPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            if ($archive.Entries.Count -ne $expected.Count) { throw 'ffmpeg_source_zip_entry_count_mismatch' }
            $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($entry in $archive.Entries) {
                $path = Assert-SafeBundlePath $entry.FullName
                if (-not $seen.Add($path) -or -not $expected.ContainsKey($path)) { throw "ffmpeg_source_zip_path_mismatch:$path" }
                $item = $expected[$path]
                if ($entry.Length -ne [int64] $item.Bytes) { throw "ffmpeg_source_zip_length_mismatch:$path" }
                $entryStream = $entry.Open()
                $algorithm = [Security.Cryptography.SHA256]::Create()
                try { $sha = [Convert]::ToHexString($algorithm.ComputeHash($entryStream)) }
                finally { $algorithm.Dispose(); $entryStream.Dispose() }
                if ($sha -cne ([string] $item.Sha256).ToUpperInvariant()) { throw "ffmpeg_source_zip_sha256_mismatch:$path" }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
    [pscustomobject][ordered]@{ verifiedEntryCount = $expected.Count }
}

function Write-DeterministicZipFromSnapshot {
    param($Snapshot, [string] $OutputPath)
    $access = Open-VerifiedBundleSnapshot $Snapshot
    $items = @()
    Add-Type -AssemblyName System.IO.Compression
    $created = $false
    try {
        $items = @(Assert-BundleItems $Snapshot.Items @($access.Root))
        $stream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $created = $true
        try {
            $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
            try {
                foreach ($item in $items) {
                    $entry = $archive.CreateEntry($item.EntryPath, [IO.Compression.CompressionLevel]::NoCompression)
                    $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                    $openedSource = Open-VerifiedBundleSource $item
                    $output = $entry.Open()
                    try { Copy-KaronHandleToStream $openedSource.SourceChain.Final.Handle $output }
                    finally { $output.Dispose() }
                    try {
                        Assert-KaronPathChainUnchanged $openedSource.RootChain 'ffmpeg_source_path_identity_changed'
                        Assert-KaronPathChainUnchanged $openedSource.SourceChain 'ffmpeg_source_path_identity_changed'
                        Assert-KaronPathIdentity $item.RootIdentity $openedSource.RootChain.Final.Identity 'ffmpeg_source_path_identity_changed' $item.SourceRootPath
                        Assert-KaronPathIdentity $item.SourceIdentity $openedSource.SourceChain.Final.Identity 'ffmpeg_source_path_identity_changed' $item.SourcePath
                    }
                    finally { Close-VerifiedBundleSource $openedSource }
                }
            }
            finally { $archive.Dispose() }
        }
        finally { $stream.Dispose() }
        Assert-KaronPathChainUnchanged $access.ParentChain 'ffmpeg_source_snapshot_identity_changed'
        Assert-KaronPathChainUnchanged $access.RootChain 'ffmpeg_source_snapshot_identity_changed'
        Assert-KaronPathIdentity $access.OwnerIdentity (ConvertTo-KaronPathIdentity $access.OwnerHandle) 'ffmpeg_source_snapshot_identity_changed' $access.Marker
        Assert-ZipMatchesItems $OutputPath $items
    }
    catch {
        if ($created -and (Test-Path -LiteralPath $OutputPath -PathType Leaf)) { Remove-Item -LiteralPath $OutputPath -Force }
        throw
    }
    finally { Close-VerifiedBundleSnapshot $access }
}

function New-DeterministicZip {
    param([object[]] $Items, [string] $OutputPath, [string[]] $AllowedSourceRoots)
    $parent = Split-Path -Parent $OutputPath
    if ([string]::IsNullOrWhiteSpace($parent)) { $parent = (Get-Location).Path }
    $snapshot = New-VerifiedBundleSnapshot $Items $parent $AllowedSourceRoots
    try { Write-DeterministicZipFromSnapshot $snapshot $OutputPath }
    finally { Remove-VerifiedBundleSnapshot $snapshot }
}

function Invoke-FfmpegSourceCollector {
    param([string] $InputManifestPath, [string] $InputBinaryArchivePath, [string] $OutputRoot, [string] $ContentRoot)
    $manifest = Get-Content -Raw -LiteralPath $InputManifestPath | ConvertFrom-Json
    if ([int] $manifest.schemaVersion -cne 3) { throw 'ffmpeg_source_manifest_schema_unsupported' }
    $manifestRoot = Split-Path -Parent (Resolve-Path -LiteralPath $InputManifestPath)
    $graph = Get-Content -Raw -LiteralPath (Join-Path $manifestRoot $manifest.sourceSets.btbnActionsCache.componentGraphPath) | ConvertFrom-Json
    $crates = Get-Content -Raw -LiteralPath (Join-Path $manifestRoot $manifest.sourceSets.rav1eCrates.manifestPath) | ConvertFrom-Json
    $toolchain = Get-Content -Raw -LiteralPath (Join-Path $manifestRoot $manifest.sourceSets.toolchain.manifestPath) | ConvertFrom-Json
    $corpus = Get-Content -Raw -LiteralPath (Join-Path $manifestRoot $manifest.sourceSets.licenseCorpus.manifestPath) | ConvertFrom-Json
    [IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
    [IO.Directory]::CreateDirectory($ContentRoot) | Out-Null

    $evidence = Read-FfmpegBinaryEvidence $InputBinaryArchivePath $manifest.binary.archiveSha256 $manifest.binary.ffmpegSha256 $manifest.binary.ffprobeSha256 $manifest.binary.expectedVersion
    $expected = @(Get-Content -LiteralPath (Join-Path $manifestRoot $manifest.binary.buildConfigurationPath) | ForEach-Object Trim | Where-Object { $_ -match '^--' })
    if (($expected -join ([char]10)) -cne ($evidence.configurationOptions -join ([char]10))) { throw 'ffmpeg_source_build_configuration_mismatch' }
    Assert-FfmpegClosureMetadata $manifest $graph $crates $toolchain $corpus $evidence.configurationOptions
    $null = Assert-LicenseCorpus $corpus $manifestRoot -VerifyFiles
    $gitLicenseEvidence = Assert-GitLicenseCorpus $corpus $manifestRoot HEAD
    $binaryEvidencePath = Join-Path $OutputRoot binary-evidence.json
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $binaryEvidencePath -Encoding utf8NoBOM

    $sources = @()
    foreach ($name in @('ffmpeg', 'btbnScripts', 'spdxLicenseList')) {
        $sources += Get-VerifiedRemoteSource ([pscustomobject]@{ id = $name; source = $manifest.sourceSets.$name; bundlePath = "sources/direct/$name.source" }) $ContentRoot
    }
    $cacheFiles = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $BtbNCacheRoot -File -Recurse)) {
        if ($cacheFiles.ContainsKey($file.Name)) { $cacheFiles[$file.Name] = $null } else { $cacheFiles[$file.Name] = $file.FullName }
    }
    foreach ($component in @($graph.components)) {
        $name = [string] $component.source.archiveName
        if (-not $cacheFiles.ContainsKey($name) -or -not $cacheFiles[$name]) { throw "ffmpeg_source_missing_archive:$($component.id)" }
        $path = Add-FileToContentCache $cacheFiles[$name] $component.source.sha256 $component.id $ContentRoot
        $sources += [pscustomobject]@{ id = $component.id; sha256 = $component.source.sha256.ToUpperInvariant(); bytes = $component.source.bytes; path = $path; bundlePath = "sources/btbn-cache/$name" }
    }
    foreach ($crate in @($crates.components)) {
        $id = "crate:$($crate.name)@$($crate.version)"
        $path = Add-FileToContentCache (Join-Path $Rav1eCrateCacheRoot ([string] $crate.cachePath)) $crate.sha256 $id $ContentRoot
        $sources += [pscustomobject]@{ id = $id; sha256 = $crate.sha256.ToUpperInvariant(); bytes = $crate.bytes; path = $path; bundlePath = "sources/rav1e-crates/$($crate.name)-$($crate.version)-$($crate.sha256).crate" }
    }
    foreach ($tool in @($toolchain.components)) {
        $sources += Get-VerifiedRemoteSource ([pscustomobject]@{ id = $tool.id; source = $tool.source; bundlePath = "sources/toolchain/$($tool.source.archiveName)" }) $ContentRoot $ToolchainSourceRoot
    }
    if ($sources.Count -cne [int] $manifest.counts.totalSourceArchives) { throw 'ffmpeg_source_inventory_count_mismatch' }

    $items = @($sources | ForEach-Object { New-BundleItem $_.path $_.bundlePath $_.sha256 })
    $items += New-BundleItem $InputManifestPath manifest.json
    $items += New-BundleItem $binaryEvidencePath evidence/collector-binary-evidence.json
    foreach ($relative in @($manifest.includedPaths)) {
        $relative = Assert-SafeBundlePath ([string] $relative)
        $path = Join-Path $manifestRoot $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "ffmpeg_source_missing_included_path:$relative" }
        $items += New-BundleItem $path $relative
    }
    foreach ($text in @($corpus.textObjects)) {
        $path = Join-Path $manifestRoot ([string] $text.bundlePath)
        $items += New-BundleItem $path ([string] $text.bundlePath) ([string] $text.sha256)
    }

    $inventoryPath = Join-Path $OutputRoot inventory.json
    [pscustomobject][ordered]@{
        schemaVersion = 1
        policy = 'verified-conservative-superset'
        sourceArchiveCount = $sources.Count
        cacheArchiveCount = 122
        rav1eCrateCount = 270
        toolchainSourceCount = 12
        licenseTextObjectCount = $corpus.textObjectCount
        inventorySelfEntry = 'inventory.json'
        entries = @($items | Sort-Object @{Expression = { $_.EntryPath.ToLowerInvariant() }}, @{Expression = { $_.EntryPath }} | ForEach-Object {
            [pscustomobject][ordered]@{ path = $_.EntryPath; bytes = $_.Bytes; sha256 = $_.Sha256 }
        })
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $inventoryPath -Encoding utf8NoBOM
    $items += New-BundleItem $inventoryPath inventory.json
    $bundle = Join-Path $OutputRoot 'ytdlp-korean-interface-v2.19.1-karon.2-ffmpeg-corresponding-sources.zip'
    $zipVerification = New-DeterministicZip $items $bundle @($ContentRoot, $manifestRoot, $OutputRoot)

    $result = [pscustomobject][ordered]@{
        status = 'complete'
        closurePolicy = 'verified-conservative-superset'
        sourceCount = $sources.Count
        componentCount = $graph.componentCount
        rav1eCrateCount = $crates.componentCount
        toolchainSourceCount = $toolchain.componentCount
        licenseTextObjectCount = $corpus.textObjectCount
        nestedClosureCount = $graph.nestedClosureCount
        inventoryEntryCount = $items.Count
        verifiedGitLicenseBlobCount = $gitLicenseEvidence.verifiedBlobCount
        verifiedZipEntryCount = $zipVerification.verifiedEntryCount
        bundlePath = $bundle
        bundleBytes = (Get-Item -LiteralPath $bundle).Length
        bundleSha256 = Get-UpperSha256 $bundle
        inventoryPath = $inventoryPath
        blockers = @()
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutputRoot collector-result.json) -Encoding utf8NoBOM
    $result
}

if (-not $NoExecute) {
    if ([string]::IsNullOrWhiteSpace($CacheRoot)) { $CacheRoot = Join-Path $ScratchRoot cache }
    Invoke-FfmpegSourceCollector $ManifestPath $BinaryArchivePath $ScratchRoot $CacheRoot
}
