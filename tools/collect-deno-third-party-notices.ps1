#requires -Version 7.4
[CmdletBinding()]
param(
    [string] $ManifestRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'release/runtime/v2.19.1-karon.2/deno'),
    [string] $DenoSourceRoot,
    [string] $RustyV8SourceRoot,
    [string] $RustyV8GitRepositoryPath,
    [string] $V8SourceRoot,
    [string] $VendorRoot,
    [string] $OfficialMetadataPath,
    [string] $SupersetMetadataPath,
    [string] $DenoExePath,
    [string] $DenoSourceArchivePath,
    [string] $RustyV8SourceArchivePath,
    [string] $V8SourceArchivePath,
    [string] $RustyV8StaticLibArchivePath,
    [string] $NativeSourceRoot,
    [string] $CrateArchiveRoot,
    [string] $SpdxRoot,
    [string] $SpdxArchivePath,
    [string] $UpstreamSourceRoot,
    [string] $UpstreamFallbackManifest,
    [string] $ScratchRoot,
    [switch] $Run
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('DenoPathSafety' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using Microsoft.Win32.SafeHandles;

[StructLayout(LayoutKind.Sequential)]
internal struct DenoFileIdInfo
{
    public ulong VolumeSerialNumber;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 16)]
    public byte[] FileId;
}

[StructLayout(LayoutKind.Sequential)]
internal struct DenoByHandleFileInformation
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
internal struct DenoFileDispositionInfo
{
    public byte DeleteFile;
}

[StructLayout(LayoutKind.Sequential)]
internal struct DenoIoStatusBlock
{
    public IntPtr Status;
    public IntPtr Information;
}

public sealed class DenoPathIdentity
{
    public string FinalPath { get; internal set; }
    public ulong VolumeSerialNumber { get; internal set; }
    public string FileId { get; internal set; }
    public uint FileAttributes { get; internal set; }
}

public sealed class DenoPathHandle : IDisposable
{
    public SafeFileHandle Handle { get; private set; }
    internal DenoPathHandle(SafeFileHandle handle) { Handle = handle; }
    public DenoPathIdentity Refresh() { return DenoPathSafety.ReadIdentity(Handle); }
    public void Dispose() { if (Handle != null) Handle.Dispose(); }
}

public static class DenoPathSafety
{
    private const uint GenericRead = 0x80000000;
    private const uint DeleteAccess = 0x00010000;
    private const uint FileReadAttributes = 0x00000080;
    private const uint FileShareRead = 0x00000001;
    private const uint FileShareWrite = 0x00000002;
    private const uint FileShareDelete = 0x00000004;
    private const uint OpenExisting = 3;
    private const uint FileFlagBackupSemantics = 0x02000000;
    private const uint FileFlagOpenReparsePoint = 0x00200000;
    private const int FileDispositionInfo = 4;
    private const int FileIdInfo = 0x12;
    private const int NtFileRenameInformation = 10;

    public static int DispositionInfoSize
    {
        get { return Marshal.SizeOf(typeof(DenoFileDispositionInfo)); }
    }

    public static string FindDuplicateJsonProperty(byte[] bytes)
    {
        if (bytes == null) throw new ArgumentNullException("bytes");
        Utf8JsonReader reader = new Utf8JsonReader(bytes, new JsonReaderOptions
        {
            AllowTrailingCommas = false,
            CommentHandling = JsonCommentHandling.Disallow,
            MaxDepth = 128
        });
        Stack<HashSet<string>> objects = new Stack<HashSet<string>>();
        while (reader.Read())
        {
            if (reader.TokenType == JsonTokenType.StartObject)
                objects.Push(new HashSet<string>(StringComparer.Ordinal));
            else if (reader.TokenType == JsonTokenType.EndObject)
                objects.Pop();
            else if (reader.TokenType == JsonTokenType.PropertyName)
            {
                string name = reader.GetString();
                if (objects.Count == 0 || !objects.Peek().Add(name)) return name;
            }
        }
        return null;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(
        string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
        uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandleEx(
        SafeFileHandle file, int informationClass, out DenoFileIdInfo information, uint bufferSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle file, out DenoByHandleFileInformation information);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(
        SafeFileHandle file, StringBuilder path, uint pathLength, uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetFileInformationByHandle(
        SafeFileHandle file, int informationClass, ref DenoFileDispositionInfo information, uint bufferSize);

    [DllImport("ntdll.dll")]
    private static extern int NtSetInformationFile(
        SafeFileHandle file, out DenoIoStatusBlock ioStatusBlock,
        IntPtr information, uint bufferSize, int informationClass);

    [DllImport("ntdll.dll")]
    private static extern uint RtlNtStatusToDosError(int status);

    private static string ToExtendedPath(string path)
    {
        if (path.StartsWith(@"\\?\", StringComparison.Ordinal)) return path;
        if (path.StartsWith(@"\\", StringComparison.Ordinal))
            return @"\\?\UNC\" + path.Substring(2);
        return @"\\?\" + path;
    }

    public static DenoPathHandle Open(
        string path, bool readData, bool openReparsePoint, bool deleteAccess, bool shareDelete)
    {
        uint access = readData ? GenericRead : FileReadAttributes;
        if (deleteAccess) access |= DeleteAccess;
        uint share = readData ? FileShareRead : FileShareRead | FileShareWrite;
        if (shareDelete) share |= FileShareDelete;
        uint flags = FileFlagBackupSemantics | (openReparsePoint ? FileFlagOpenReparsePoint : 0);
        SafeFileHandle handle = CreateFileW(
            ToExtendedPath(path), access, share, IntPtr.Zero, OpenExisting, flags, IntPtr.Zero);
        if (handle.IsInvalid)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFileW failed: " + path);
        return new DenoPathHandle(handle);
    }

    public static void MarkDelete(DenoPathHandle path)
    {
        if (DispositionInfoSize != 1)
            throw new InvalidOperationException("FILE_DISPOSITION_INFO must be one byte.");
        DenoFileDispositionInfo information = new DenoFileDispositionInfo { DeleteFile = 1 };
        if (!SetFileInformationByHandle(path.Handle, FileDispositionInfo, ref information,
                (uint)Marshal.SizeOf(typeof(DenoFileDispositionInfo))))
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "SetFileInformationByHandle(FileDispositionInfo) failed");
    }

    public static void Rename(
        DenoPathHandle source, DenoPathHandle destinationParent, string destinationName)
    {
        if (String.IsNullOrEmpty(destinationName) ||
            destinationName.IndexOfAny(new char[] { '\\', '/', ':' }) >= 0)
            throw new ArgumentException("Destination must be one leaf name.", "destinationName");

        byte[] name = Encoding.Unicode.GetBytes(destinationName);
        int rootOffset = IntPtr.Size == 8 ? 8 : 4;
        int lengthOffset = rootOffset + IntPtr.Size;
        int nameOffset = lengthOffset + 4;
        int size = nameOffset + name.Length;
        IntPtr buffer = Marshal.AllocHGlobal(size);
        try
        {
            for (int index = 0; index < size; index++) Marshal.WriteByte(buffer, index, 0);
            Marshal.WriteInt32(buffer, 0, 0);
            Marshal.WriteIntPtr(buffer, rootOffset, destinationParent.Handle.DangerousGetHandle());
            Marshal.WriteInt32(buffer, lengthOffset, name.Length);
            Marshal.Copy(name, 0, IntPtr.Add(buffer, nameOffset), name.Length);
            DenoIoStatusBlock ioStatusBlock;
            int status = NtSetInformationFile(
                source.Handle, out ioStatusBlock, buffer, (uint)size, NtFileRenameInformation);
            if (status != 0)
                throw new Win32Exception(
                    unchecked((int)RtlNtStatusToDosError(status)),
                    "NtSetInformationFile(FileRenameInformation) failed");
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    public static DenoPathIdentity ReadIdentity(SafeFileHandle handle)
    {
        DenoFileIdInfo id;
        if (!GetFileInformationByHandleEx(
                handle, FileIdInfo, out id, (uint)Marshal.SizeOf(typeof(DenoFileIdInfo))))
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "GetFileInformationByHandleEx(FileIdInfo) failed");
        DenoByHandleFileInformation basic;
        if (!GetFileInformationByHandle(handle, out basic))
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "GetFileInformationByHandle failed");
        StringBuilder path = new StringBuilder(1024);
        uint length = GetFinalPathNameByHandleW(handle, path, (uint)path.Capacity, 0);
        if (length == 0)
            throw new Win32Exception(
                Marshal.GetLastWin32Error(),
                "GetFinalPathNameByHandleW failed");
        if (length >= path.Capacity)
        {
            path = new StringBuilder((int)length + 1);
            length = GetFinalPathNameByHandleW(handle, path, (uint)path.Capacity, 0);
            if (length == 0 || length >= path.Capacity)
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "GetFinalPathNameByHandleW failed");
        }
        return new DenoPathIdentity {
            FinalPath = path.ToString(),
            VolumeSerialNumber = id.VolumeSerialNumber,
            FileId = BitConverter.ToString(id.FileId).Replace("-", ""),
            FileAttributes = basic.FileAttributes
        };
    }
}
'@
}

function ConvertTo-DenoFinalPath {
    param([Parameter(Mandatory)] [string] $Path)
    if ($Path.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        $Path = '\\' + $Path.Substring(8)
    }
    elseif ($Path.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        $Path = $Path.Substring(4)
    }
    $full = [IO.Path]::GetFullPath($Path)
    $volumeRoot = [IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $volumeRoot.Length) { return $full.TrimEnd([char[]] @('\', '/')) }
    return $full
}

function ConvertTo-DenoPathIdentity {
    param([Parameter(Mandatory)] $Handle)
    if ($Handle -is [DenoPathHandle]) {
        $identity = $Handle.Refresh()
    }
    elseif ($Handle -is [Microsoft.Win32.SafeHandles.SafeFileHandle]) {
        $identity = [DenoPathSafety]::ReadIdentity($Handle)
    }
    else {
        throw 'deno_invalid_path_handle'
    }
    return [pscustomobject][ordered]@{
        FinalPath = ConvertTo-DenoFinalPath ([string]$identity.FinalPath)
        VolumeSerialNumber = [uint64]$identity.VolumeSerialNumber
        FileId = ([string]$identity.FileId).ToUpperInvariant()
        FileAttributes = [uint32]$identity.FileAttributes
    }
}

function Assert-DenoPathIdentity {
    param(
        [Parameter(Mandatory)] $Expected,
        [Parameter(Mandatory)] $Actual,
        [Parameter(Mandatory)] [string] $ErrorCode,
        [Parameter(Mandatory)] [string] $Label
    )
    if (-not ([string]$Expected.FinalPath).Equals([string]$Actual.FinalPath, [StringComparison]::OrdinalIgnoreCase) -or
        [uint64]$Expected.VolumeSerialNumber -ne [uint64]$Actual.VolumeSerialNumber -or
        -not ([string]$Expected.FileId).Equals([string]$Actual.FileId, [StringComparison]::Ordinal) -or
        [uint32]$Expected.FileAttributes -ne [uint32]$Actual.FileAttributes) {
        throw ('{0}:{1}' -f $ErrorCode, $Label)
    }
}

function Get-DenoLexicalPathNodes {
    param([Parameter(Mandatory)] [string] $Path)
    $full = [IO.Path]::GetFullPath($Path)
    $volumeRoot = [IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($volumeRoot)) { throw ('deno_path_invalid:{0}' -f $Path) }
    $nodes = [Collections.Generic.List[string]]::new()
    $nodes.Add($volumeRoot) | Out-Null
    $current = $volumeRoot
    foreach ($segment in @($full.Substring($volumeRoot.Length) -split '[\\/]' | Where-Object { $_.Length -gt 0 })) {
        $current = Join-Path $current $segment
        $nodes.Add([IO.Path]::GetFullPath($current)) | Out-Null
    }
    return $nodes.ToArray()
}

function Close-DenoPathChain {
    param($Chain)
    if ($null -eq $Chain) { return }
    for ($index = $Chain.Nodes.Count - 1; $index -ge 0; $index--) {
        $Chain.Nodes[$index].Handle.Dispose()
    }
}

function Open-DenoPathChain {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [switch] $ReadFinal,
        [switch] $DeleteFinal,
        [switch] $ShareDeleteFinal,
        [string] $ReparseError = 'deno_reparse_path_rejected'
    )
    $lexicalNodes = @(Get-DenoLexicalPathNodes $Path)
    $openedNodes = [Collections.Generic.List[object]]::new()
    try {
        for ($index = 0; $index -lt $lexicalNodes.Count; $index++) {
            $isFinal = $index -eq ($lexicalNodes.Count - 1)
            $handle = [DenoPathSafety]::Open(
                $lexicalNodes[$index],
                [bool]($isFinal -and $ReadFinal),
                $true,
                [bool]($isFinal -and $DeleteFinal),
                [bool]($isFinal -and $ShareDeleteFinal)
            )
            try {
                $identity = ConvertTo-DenoPathIdentity $handle
                if (($identity.FileAttributes -band [uint32][IO.FileAttributes]::ReparsePoint) -ne 0 -or
                    -not $identity.FinalPath.Equals((ConvertTo-DenoFinalPath $lexicalNodes[$index]), [StringComparison]::OrdinalIgnoreCase)) {
                    throw ('{0}:{1}' -f $ReparseError, $lexicalNodes[$index])
                }
                $openedNodes.Add([pscustomobject][ordered]@{
                    LexicalPath = ConvertTo-DenoFinalPath $lexicalNodes[$index]
                    Handle = $handle
                    Identity = $identity
                }) | Out-Null
                $handle = $null
            }
            finally {
                if ($null -ne $handle) { $handle.Dispose() }
            }
        }
        return [pscustomobject][ordered]@{
            Path = ConvertTo-DenoFinalPath $Path
            Nodes = @($openedNodes)
            Final = $openedNodes[$openedNodes.Count - 1]
        }
    }
    catch {
        for ($index = $openedNodes.Count - 1; $index -ge 0; $index--) {
            $openedNodes[$index].Handle.Dispose()
        }
        throw
    }
}

function Assert-DenoPathChainUnchanged {
    param([Parameter(Mandatory)] $Chain, [string] $ErrorCode = 'deno_path_identity_changed')
    foreach ($node in $Chain.Nodes) {
        Assert-DenoPathIdentity $node.Identity (ConvertTo-DenoPathIdentity $node.Handle) $ErrorCode $node.LexicalPath
    }
    return $true
}

function Assert-DenoPhysicalContainment {
    param(
        [Parameter(Mandatory)] $RootIdentity,
        [Parameter(Mandatory)] $ChildIdentity,
        [Parameter(Mandatory)] [string] $ErrorCode
    )
    $root = ConvertTo-DenoFinalPath ([string]$RootIdentity.FinalPath)
    $child = ConvertTo-DenoFinalPath ([string]$ChildIdentity.FinalPath)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if ([uint64]$RootIdentity.VolumeSerialNumber -ne [uint64]$ChildIdentity.VolumeSerialNumber -or
        (-not $child.Equals($root, [StringComparison]::OrdinalIgnoreCase) -and
         -not $child.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw $ErrorCode
    }
}

function Assert-DenoDirectChild {
    param(
        [Parameter(Mandatory)] $ParentIdentity,
        [Parameter(Mandatory)] $ChildIdentity,
        [Parameter(Mandatory)] [string] $ErrorCode
    )
    if ([uint64]$ParentIdentity.VolumeSerialNumber -ne [uint64]$ChildIdentity.VolumeSerialNumber -or
        -not ([IO.Path]::GetDirectoryName([string]$ChildIdentity.FinalPath)).Equals(
            [string]$ParentIdentity.FinalPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw $ErrorCode
    }
}

function Assert-DenoExistingAncestors {
    param([Parameter(Mandatory)] [string] $Path)
    foreach ($node in @(Get-DenoLexicalPathNodes $Path)) {
        $handle = $null
        try {
            $handle = [DenoPathSafety]::Open($node, $false, $true, $false, $false)
            $identity = ConvertTo-DenoPathIdentity $handle
            if (($identity.FileAttributes -band [uint32][IO.FileAttributes]::ReparsePoint) -ne 0 -or
                -not $identity.FinalPath.Equals((ConvertTo-DenoFinalPath $node), [StringComparison]::OrdinalIgnoreCase)) {
                throw ('deno_reparse_path_rejected:{0}' -f $node)
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

function Open-DenoVerifiedReadFile {
    param([Parameter(Mandatory)] [string] $Path)
    $chain = $null
    $borrowed = $null
    $stream = $null
    try {
        $chain = Open-DenoPathChain -Path $Path -ReadFinal
        $borrowed = [Microsoft.Win32.SafeHandles.SafeFileHandle]::new(
            $chain.Final.Handle.Handle.DangerousGetHandle(), $false)
        $stream = [IO.FileStream]::new($borrowed, [IO.FileAccess]::Read, 131072, $false)
        return [pscustomobject][ordered]@{
            Path = $chain.Path
            Chain = $chain
            BorrowedHandle = $borrowed
            Stream = $stream
        }
    }
    catch {
        if ($null -ne $stream) { $stream.Dispose() }
        elseif ($null -ne $borrowed) { $borrowed.Dispose() }
        Close-DenoPathChain $chain
        throw
    }
}

function Close-DenoVerifiedReadFile {
    param($VerifiedFile)
    if ($null -eq $VerifiedFile) { return }
    if ($null -ne $VerifiedFile.Stream) { $VerifiedFile.Stream.Dispose() }
    if ($null -ne $VerifiedFile.BorrowedHandle) { $VerifiedFile.BorrowedHandle.Dispose() }
    Close-DenoPathChain $VerifiedFile.Chain
}

function Assert-DenoVerifiedReadFileUnchanged {
    param([Parameter(Mandatory)] $VerifiedFile)
    return Assert-DenoPathChainUnchanged -Chain $VerifiedFile.Chain -ErrorCode 'deno_input_path_identity_changed'
}

function Get-DenoStreamDigest {
    param([Parameter(Mandatory)] [IO.Stream] $Stream)
    [void]$Stream.Seek(0, [IO.SeekOrigin]::Begin)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $sha256 = ([Convert]::ToHexString($algorithm.ComputeHash($Stream))).ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
        [void]$Stream.Seek(0, [IO.SeekOrigin]::Begin)
    }
    return [pscustomobject][ordered]@{ length = [long]$Stream.Length; sha256 = $sha256 }
}

function Get-DenoVerifiedByteMaterial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [long] $MaximumLength = 67108864,
        [string] $ExpectedSha256,
        [long] $ExpectedLength = -1,
        [scriptblock] $AfterHashAction,
        [switch] $Cache
    )
    if ($MaximumLength -lt 0 -or $MaximumLength -gt [int]::MaxValue) { throw 'deno_input_bound_invalid' }
    $cacheVariable = Get-Variable -Name DenoVerifiedMaterialCache -Scope Script -ErrorAction SilentlyContinue
    if ($null -eq $cacheVariable) { $script:DenoVerifiedMaterialCache = @{} }
    $cacheKey = (ConvertTo-DenoFinalPath $Path).ToLowerInvariant()
    if ($Cache -and $script:DenoVerifiedMaterialCache.ContainsKey($cacheKey)) {
        $material = $script:DenoVerifiedMaterialCache[$cacheKey]
        if ($material.length -gt $MaximumLength) { throw "deno_input_too_large:$Path" }
        if ($ExpectedLength -ge 0 -and $material.length -ne $ExpectedLength) { throw "deno_input_length_mismatch:$Path" }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256) -and
            ($ExpectedSha256 -notmatch '^[0-9a-f]{64}$' -or $material.sha256 -cne $ExpectedSha256)) {
            throw "deno_input_hash_mismatch:$Path"
        }
        return $material
    }

    $verified = Open-DenoVerifiedReadFile -Path $Path
    try {
        $length = [long]$verified.Stream.Length
        if ($length -gt $MaximumLength) { throw "deno_input_too_large:$Path" }
        if ($ExpectedLength -ge 0 -and $length -ne $ExpectedLength) { throw "deno_input_length_mismatch:$Path" }
        $bytes = [byte[]]::new([int]$length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $verified.Stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -eq 0) { throw "deno_input_truncated:$Path" }
            $offset += $read
        }
        $sha256 = ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256) -and
            ($ExpectedSha256 -notmatch '^[0-9a-f]{64}$' -or $sha256 -cne $ExpectedSha256)) {
            throw "deno_input_hash_mismatch:$Path"
        }
        if ($null -ne $AfterHashAction) { [void](& $AfterHashAction) }
        [void](Assert-DenoVerifiedReadFileUnchanged -VerifiedFile $verified)
        $material = [pscustomobject][ordered]@{ path = $verified.Path; length = $length; sha256 = $sha256; bytes = $bytes }
        if ($Cache) { $script:DenoVerifiedMaterialCache[$cacheKey] = $material }
        return $material
    }
    finally {
        Close-DenoVerifiedReadFile -VerifiedFile $verified
    }
}

function ConvertFrom-DenoUtf8Bytes {
    param([Parameter(Mandatory)] [byte[]] $Bytes)
    return [Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
}

function Read-DenoUtf8Text {
    param([Parameter(Mandatory)] [string] $Path)
    $verified = Open-DenoVerifiedReadFile -Path $Path
    try {
        $reader = [IO.StreamReader]::new(
            $verified.Stream, [Text.UTF8Encoding]::new($false, $true), $true, 65536, $true)
        try { return $reader.ReadToEnd() }
        finally { $reader.Dispose() }
    }
    finally {
        [void](Assert-DenoVerifiedReadFileUnchanged -VerifiedFile $verified)
        Close-DenoVerifiedReadFile -VerifiedFile $verified
    }
}

function Write-DenoBytes {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [byte[]] $Bytes
    )
    $full = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $full
    $leaf = Split-Path -Leaf $full
    Assert-DenoUniquePaths @($leaf) | Out-Null
    $parentChain = Open-DenoPathChain -Path $parent
    $stream = $null
    try {
        if ([IO.File]::Exists($full) -or [IO.Directory]::Exists($full)) {
            throw 'deno_output_already_exists'
        }
        $stream = [IO.File]::Open($full, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $identity = ConvertTo-DenoPathIdentity $stream.SafeFileHandle
        if (($identity.FileAttributes -band [uint32][IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('deno_reparse_path_rejected:{0}' -f $full)
        }
        Assert-DenoDirectChild $parentChain.Final.Identity $identity 'deno_output_parent_escape'
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
        Assert-DenoPathIdentity $identity (ConvertTo-DenoPathIdentity $stream.SafeFileHandle) 'deno_output_path_identity_changed' $full
        [void](Assert-DenoPathChainUnchanged -Chain $parentChain -ErrorCode 'deno_output_parent_identity_changed')
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        Close-DenoPathChain $parentChain
    }
}

function Add-DenoLicenseMaterial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [byte[]] $Bytes,
        [Parameter(Mandatory)] [string] $DestinationPath,
        [Parameter(Mandatory)] [string] $DestinationRelative,
        [Parameter(Mandatory)] [Text.StringBuilder] $Notice,
        [string] $ExpectedSha256,
        [long] $ExpectedLength = -1,
        [scriptblock] $AfterStageAction
    )
    $sha256 = ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))).ToLowerInvariant()
    if ($ExpectedLength -ge 0 -and $Bytes.Length -ne $ExpectedLength) { throw "deno_license_length_mismatch:$DestinationRelative" }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256) -and
        ($ExpectedSha256 -notmatch '^[0-9a-f]{64}$' -or $sha256 -cne $ExpectedSha256)) {
        throw "deno_license_hash_mismatch:$DestinationRelative"
    }
    $text = ConvertFrom-DenoUtf8Bytes -Bytes $Bytes
    New-Item -ItemType Directory -Path (Split-Path -Parent $DestinationPath) -Force | Out-Null
    Write-DenoBytes -Path $DestinationPath -Bytes $Bytes
    if ($null -ne $AfterStageAction) { [void](& $AfterStageAction) }
    $Notice.AppendLine("--- $DestinationRelative ---").AppendLine($text).AppendLine() | Out-Null
    return [pscustomobject][ordered]@{ length = [long]$Bytes.Length; sha256 = $sha256; text = $text }
}

function Add-DenoVerifiedLicenseMaterial {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SourcePath,
        [Parameter(Mandatory)] [string] $DestinationPath,
        [Parameter(Mandatory)] [string] $DestinationRelative,
        [Parameter(Mandatory)] [Text.StringBuilder] $Notice,
        [string] $ExpectedSha256,
        [long] $ExpectedLength = -1,
        [scriptblock] $AfterStageAction
    )
    $material = Get-DenoVerifiedByteMaterial -Path $SourcePath -ExpectedSha256 $ExpectedSha256 -ExpectedLength $ExpectedLength -Cache
    return Add-DenoLicenseMaterial -Bytes $material.bytes -DestinationPath $DestinationPath -DestinationRelative $DestinationRelative -Notice $Notice -ExpectedSha256 $ExpectedSha256 -ExpectedLength $ExpectedLength -AfterStageAction $AfterStageAction
}

function Copy-DenoVerifiedFile {
    param(
        [Parameter(Mandatory)] [string] $SourcePath,
        [Parameter(Mandatory)] [string] $DestinationPath,
        [string] $ExpectedSha256,
        [long] $ExpectedLength = -1
    )
    $source = Open-DenoVerifiedReadFile -Path $SourcePath
    $parentChain = $null
    $output = $null
    try {
        if ($ExpectedLength -ge 0 -and $source.Stream.Length -ne $ExpectedLength) {
            throw ('deno_input_length_mismatch:{0}' -f $SourcePath)
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedSha256)) {
            $digest = Get-DenoStreamDigest -Stream $source.Stream
            if ($ExpectedSha256 -notmatch '^[0-9a-f]{64}$' -or $digest.sha256 -cne $ExpectedSha256) {
                throw ('deno_input_hash_mismatch:{0}' -f $SourcePath)
            }
        }
        $destination = [IO.Path]::GetFullPath($DestinationPath)
        $parent = Split-Path -Parent $destination
        Assert-DenoUniquePaths @((Split-Path -Leaf $destination)) | Out-Null
        $parentChain = Open-DenoPathChain -Path $parent
        if ([IO.File]::Exists($destination) -or [IO.Directory]::Exists($destination)) {
            throw 'deno_output_already_exists'
        }
        $output = [IO.File]::Open(
            $destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $outputIdentity = ConvertTo-DenoPathIdentity $output.SafeFileHandle
        Assert-DenoDirectChild $parentChain.Final.Identity $outputIdentity 'deno_output_parent_escape'
        [void]$source.Stream.Seek(0, [IO.SeekOrigin]::Begin)
        $source.Stream.CopyTo($output)
        $output.Flush($true)
        Assert-DenoPathIdentity $outputIdentity (ConvertTo-DenoPathIdentity $output.SafeFileHandle) 'deno_output_path_identity_changed' $destination
        [void](Assert-DenoVerifiedReadFileUnchanged -VerifiedFile $source)
        [void](Assert-DenoPathChainUnchanged -Chain $parentChain -ErrorCode 'deno_output_parent_identity_changed')
    }
    finally {
        if ($null -ne $output) { $output.Dispose() }
        Close-DenoPathChain $parentChain
        Close-DenoVerifiedReadFile -VerifiedFile $source
    }
}

function Assert-DenoNoReparsePath {
    param([Parameter(Mandatory)] [string] $Path)
    $full = ConvertTo-DenoFinalPath $Path
    $chain = $null
    try {
        $chain = Open-DenoPathChain -Path $full
    }
    catch [ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -notin @(2, 3)) { throw }
        Assert-DenoExistingAncestors -Path $full
    }
    finally {
        Close-DenoPathChain $chain
    }
    return $full
}

$script:DenoOwnedStages = @{}

function New-DenoProcessStageRoot {
    param([Parameter(Mandatory)] [string] $ScratchRoot)
    $scratch = Assert-DenoNoReparsePath $ScratchRoot
    if (-not [IO.Directory]::Exists($scratch)) { [void][IO.Directory]::CreateDirectory($scratch) }
    $scratchChain = $null
    $stageChain = $null
    $ownerChain = $null
    try {
        $scratchChain = Open-DenoPathChain -Path $scratch
        $stageName = '.deno-third-party-stage-' + $PID + '-' + [guid]::NewGuid().ToString('N')
        Assert-DenoUniquePaths @($stageName) | Out-Null
        $stage = Join-Path $scratch $stageName
        if ([IO.Directory]::Exists($stage) -or [IO.File]::Exists($stage)) {
            throw 'deno_process_stage_collision'
        }
        [void][IO.Directory]::CreateDirectory($stage)
        $stageChain = Open-DenoPathChain -Path $stage -DeleteFinal
        Assert-DenoDirectChild $scratchChain.Final.Identity $stageChain.Final.Identity 'deno_process_stage_parent_escape'
        $token = [guid]::NewGuid().ToString('N')
        $ownerPath = Join-Path $stage ('.deno-stage-owner-' + $token)
        Write-DenoUtf8Text -Path $ownerPath -Text $token
        $ownerChain = Open-DenoPathChain -Path $ownerPath -DeleteFinal
        Assert-DenoDirectChild $stageChain.Final.Identity $ownerChain.Final.Identity 'deno_process_stage_owner_escape'
        $key = (ConvertTo-DenoFinalPath $stage).ToLowerInvariant()
        $script:DenoOwnedStages[$key] = [pscustomobject][ordered]@{
            Path = ConvertTo-DenoFinalPath $stage
            ScratchChain = $scratchChain
            StageChain = $stageChain
            OwnerPath = ConvertTo-DenoFinalPath $ownerPath
            OwnerChain = $ownerChain
        }
        $scratchChain = $null
        $stageChain = $null
        $ownerChain = $null
        return ConvertTo-DenoFinalPath $stage
    }
    catch {
        Close-DenoPathChain $ownerChain
        Close-DenoPathChain $stageChain
        Close-DenoPathChain $scratchChain
        throw
    }
}

function Remove-DenoProcessStageRoot {
    param([Parameter(Mandatory)] [string] $Path)
    $key = (ConvertTo-DenoFinalPath $Path).ToLowerInvariant()
    if (-not $script:DenoOwnedStages.ContainsKey($key)) { throw 'deno_process_stage_not_owned' }
    $owned = $script:DenoOwnedStages[$key]
    $deleted = $false
    try {
        [void](Assert-DenoPathChainUnchanged -Chain $owned.ScratchChain -ErrorCode 'deno_process_stage_parent_identity_changed')
        [void](Assert-DenoPathChainUnchanged -Chain $owned.StageChain -ErrorCode 'deno_process_stage_identity_changed')
        [void](Assert-DenoPathChainUnchanged -Chain $owned.OwnerChain -ErrorCode 'deno_process_stage_owner_identity_changed')
        $entries = @([IO.Directory]::EnumerateFileSystemEntries($owned.Path))
        if ($entries.Count -eq 1 -and
            (ConvertTo-DenoFinalPath $entries[0]).Equals($owned.OwnerPath, [StringComparison]::OrdinalIgnoreCase)) {
            [DenoPathSafety]::MarkDelete($owned.OwnerChain.Final.Handle)
            Close-DenoPathChain $owned.OwnerChain
            $owned.OwnerChain = $null
            if (@([IO.Directory]::EnumerateFileSystemEntries($owned.Path)).Count -ne 0) {
                throw 'deno_process_stage_cleanup_not_empty'
            }
            [DenoPathSafety]::MarkDelete($owned.StageChain.Final.Handle)
            $deleted = $true
        }
    }
    finally {
        Close-DenoPathChain $owned.OwnerChain
        Close-DenoPathChain $owned.StageChain
        Close-DenoPathChain $owned.ScratchChain
        [void]$script:DenoOwnedStages.Remove($key)
    }
    return $deleted
}

function Close-DenoProcessStageOwnership {
    param([Parameter(Mandatory)] [string] $Key)
    if (-not $script:DenoOwnedStages.ContainsKey($Key)) { return }
    $owned = $script:DenoOwnedStages[$Key]
    Close-DenoPathChain $owned.OwnerChain
    Close-DenoPathChain $owned.StageChain
    Close-DenoPathChain $owned.ScratchChain
    [void]$script:DenoOwnedStages.Remove($Key)
}

function Complete-DenoAtomicDirectory {
    param(
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Destination,
        [scriptblock] $BeforeFinalizeAction
    )
    $sourceFull = ConvertTo-DenoFinalPath $Source
    $destinationFull = ConvertTo-DenoFinalPath $Destination
    if (-not [IO.Directory]::Exists($sourceFull)) { throw 'deno_process_stage_missing' }
    $destinationParent = Split-Path -Parent $destinationFull
    $destinationLeaf = Split-Path -Leaf $destinationFull
    Assert-DenoUniquePaths @($destinationLeaf) | Out-Null
    $ownedStageKey = $null
    foreach ($candidate in @($script:DenoOwnedStages.Keys)) {
        $prefix = ([string]$script:DenoOwnedStages[$candidate].Path).TrimEnd('\') + '\'
        if ($sourceFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $ownedStageKey = [string]$candidate
            break
        }
    }
    $sourceChain = $null
    $destinationParentChain = $null
    try {
        $destinationParentChain = Open-DenoPathChain -Path $destinationParent
        $sourceChain = Open-DenoPathChain -Path $sourceFull -DeleteFinal -ShareDeleteFinal
        $sourceParent = $sourceChain.Nodes[$sourceChain.Nodes.Count - 2]
        Assert-DenoDirectChild $sourceParent.Identity $sourceChain.Final.Identity 'deno_process_stage_source_escape'
        if ([uint64]$sourceChain.Final.Identity.VolumeSerialNumber -ne
            [uint64]$destinationParentChain.Final.Identity.VolumeSerialNumber) {
            throw 'deno_process_stage_volume_mismatch'
        }
        if ([IO.Directory]::Exists($destinationFull) -or [IO.File]::Exists($destinationFull)) {
            throw 'deno_output_already_exists'
        }
        if ($null -ne $BeforeFinalizeAction) { & $BeforeFinalizeAction }
        [void](Assert-DenoPathChainUnchanged -Chain $sourceChain -ErrorCode 'deno_process_stage_identity_changed')
        [void](Assert-DenoPathChainUnchanged -Chain $destinationParentChain -ErrorCode 'deno_output_parent_identity_changed')
        if ([IO.Directory]::Exists($destinationFull) -or [IO.File]::Exists($destinationFull)) {
            throw 'deno_output_already_exists'
        }
        $before = $sourceChain.Final.Identity
        [DenoPathSafety]::Rename(
            $sourceChain.Final.Handle,
            $destinationParentChain.Final.Handle,
            $destinationLeaf)
        $after = ConvertTo-DenoPathIdentity $sourceChain.Final.Handle
        if ([uint64]$before.VolumeSerialNumber -ne [uint64]$after.VolumeSerialNumber -or
            -not ([string]$before.FileId).Equals([string]$after.FileId, [StringComparison]::Ordinal) -or
            [uint32]$before.FileAttributes -ne [uint32]$after.FileAttributes -or
            -not $after.FinalPath.Equals($destinationFull, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'deno_output_finalize_identity_changed'
        }
        return $true
    }
    catch {
        if ($null -ne $ownedStageKey) {
            Close-DenoProcessStageOwnership -Key $ownedStageKey
        }
        throw
    }
    finally {
        Close-DenoPathChain $sourceChain
        Close-DenoPathChain $destinationParentChain
    }
}

function Get-DenoSha256 {
    param([Parameter(Mandatory)] [string] $Path)
    $verified = Open-DenoVerifiedReadFile -Path $Path
    try {
        return (Get-DenoStreamDigest -Stream $verified.Stream).sha256
    }
    finally {
        [void](Assert-DenoVerifiedReadFileUnchanged -VerifiedFile $verified)
        Close-DenoVerifiedReadFile -VerifiedFile $verified
    }
}

function Get-DenoFileLength {
    param([Parameter(Mandatory)] [string] $Path)
    $verified = Open-DenoVerifiedReadFile -Path $Path
    try { return [long]$verified.Stream.Length }
    finally {
        [void](Assert-DenoVerifiedReadFileUnchanged -VerifiedFile $verified)
        Close-DenoVerifiedReadFile -VerifiedFile $verified
    }
}

function Write-DenoUtf8Text {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $Text)
    $normalized = $Text.Replace([string][char]13 + [char]10, [string][char]10).Replace([string][char]13, [string][char]10)
    Write-DenoBytes -Path $Path -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($normalized))
}

function Read-DenoJson {
    param([Parameter(Mandatory)] [string] $Path)
    $material = Get-DenoVerifiedByteMaterial -Path $Path -Cache
    $duplicate = [DenoPathSafety]::FindDuplicateJsonProperty($material.bytes)
    if ($null -ne $duplicate) { throw "deno_json_duplicate_property:$duplicate" }
    $raw = ConvertFrom-DenoUtf8Bytes -Bytes $material.bytes
    return ConvertFrom-Json -InputObject $raw -Depth 100
}

function Assert-DenoHash {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $ExpectedSha256)
    if ($ExpectedSha256 -notmatch '^[0-9a-f]{64}$' -or (Get-DenoSha256 $Path) -cne $ExpectedSha256) {
        throw "deno_input_hash_mismatch:$Path"
    }
}

function Assert-DenoEmbeddedProfile {
    param([Parameter(Mandatory)] [object] $Inputs)
    if (@($Inputs.embeddedComponents).Count -ne 1) {
        throw 'deno_embedded_profile_invalid'
    }
    $expected = [ordered]@{
        id = 'typescript@5.9.2'
        name = 'TypeScript'
        version = '5.9.2'
        denoSourceCommit = '2d674b25625bcc367853d00fe86f6e84390f88cb'
        sourceFile = [ordered]@{
            path = 'cli/tsc/00_typescript.js'
            archiveEntry = 'deno-2d674b25625bcc367853d00fe86f6e84390f88cb/cli/tsc/00_typescript.js'
            bundlePath = 'SOURCES/embedded/typescript-5.9.2/cli/tsc/00_typescript.js'
            length = [long]8492282
            sha256 = '932f9fd96b20ef8c2496d7f70419c69fa40266a92d81a2b229737fa6dd324ac8'
            requiredText = @(
                'version = "5.9.2"',
                'Copyright (c) Microsoft Corporation. All rights reserved.'
            )
        }
        copyright = 'Copyright (c) Microsoft Corporation. All rights reserved.'
        license = 'Apache-2.0'
        licenseFile = [ordered]@{
            path = 'text/Apache-2.0.txt'
            bundlePath = 'LICENSES/embedded/typescript-5.9.2/Apache-2.0.txt'
            length = [long]10280
            sha256 = '074e6e32c86a4c0ef8b3ed25b721ca23aca83df277cd88106ef7177c354615ff'
        }
        buildInclusionEvidence = @(
            [ordered]@{
                role = 'compressed-by-cli-build-rs'
                path = 'cli/build.rs'
                archiveEntry = 'deno-2d674b25625bcc367853d00fe86f6e84390f88cb/cli/build.rs'
                requiredText = '"./tsc/00_typescript.js",'
            },
            [ordered]@{
                role = 'referenced-by-cli-tsc-module'
                path = 'cli/tsc/mod.rs'
                archiveEntry = 'deno-2d674b25625bcc367853d00fe86f6e84390f88cb/cli/tsc/mod.rs'
                requiredText = 'maybe_compressed_source!("tsc/00_typescript.js");'
            }
        )
        inclusionReason = 'embedded-compressed-typescript-compiler-source'
    }
    $actualJson = $Inputs.embeddedComponents[0] | ConvertTo-Json -Depth 20 -Compress
    $expectedJson = $expected | ConvertTo-Json -Depth 20 -Compress
    if ($actualJson -cne $expectedJson) { throw 'deno_embedded_profile_invalid' }
    return $true
}

function Assert-DenoImmutableCargoSource {
    param([Parameter(Mandatory)] [string] $Source)
    if ($Source -ceq 'registry+https://github.com/rust-lang/crates.io-index') { return $true }
    if ($Source.StartsWith('git+', [StringComparison]::Ordinal)) {
        if ($Source -match '(?i)[?&](branch|tag)=' -or
            $Source -notmatch '#(?<commit>[0-9a-f]{40})$' -or
            ($Source -match '[?&]rev=(?<revision>[0-9a-f]{40})(?:&|#)' -and $Matches.revision -cne $Matches.commit)) {
            throw 'deno_mutable_git_source'
        }
        return $true
    }
    throw 'deno_unsupported_cargo_source'
}

function Assert-DenoUniquePaths {
    param([Parameter(Mandatory)] [string[]] $Paths)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($inputPath in $Paths) {
        $path = $inputPath.Replace('\', '/')
        if ([string]::IsNullOrWhiteSpace($path) -or $path.StartsWith('/') -or
            $path -match '^[A-Za-z]:' -or
            -not $path.Equals($path.Normalize([Text.NormalizationForm]::FormC), [StringComparison]::Ordinal)) {
            throw "deno_path_invalid:$path"
        }
        $segments = $path.Split([char]'/', [StringSplitOptions]::None)
        foreach ($segment in $segments) {
            if ([string]::IsNullOrEmpty($segment) -or
                $segment -ceq '.' -or $segment -ceq '..' -or
                $segment -match '[\x00-\x1F]' -or
                $segment -match '[ .]$' -or
                $segment.IndexOfAny([char[]]'<>:"|?*') -ge 0 -or
                $segment -match '(?i)^(CON|PRN|AUX|NUL|COM(?:[1-9]|[¹²³])|LPT(?:[1-9]|[¹²³]))(?:\.|$)') {
                throw "deno_path_invalid:$path"
            }
        }
        if (-not $seen.Add($path)) {
            throw "deno_path_case_collision:$($path.ToLowerInvariant())"
        }
    }
    return $true
}

function Assert-DenoNativeClosure {
    param(
        [Parameter(Mandatory)] [object[]] $Components,
        [Parameter(Mandatory)] [string] $RustyV8GitRepositoryPath,
        [Parameter(Mandatory)] [string] $ExpectedCommit,
        [Parameter(Mandatory)] [string] $ExpectedTree
    )
    $repository = Assert-DenoNoReparsePath $RustyV8GitRepositoryPath
    if (-not [IO.Directory]::Exists($repository)) { throw 'deno_rusty_v8_git_repository_missing' }
    $commitExpression = "$ExpectedCommit^{commit}"
    $actualCommit = @(& git.exe -C $repository rev-parse $commitExpression 2>$null)
    if ($LASTEXITCODE -ne 0 -or $actualCommit.Count -ne 1 -or $actualCommit[0] -cne $ExpectedCommit) { throw 'deno_rusty_v8_git_commit_mismatch' }
    $treeExpression = "$ExpectedCommit^{tree}"
    $actualTree = @(& git.exe -C $repository rev-parse $treeExpression 2>$null)
    if ($LASTEXITCODE -ne 0 -or $actualTree.Count -ne 1 -or $actualTree[0] -cne $ExpectedTree) { throw 'deno_rusty_v8_git_tree_mismatch' }
    $treeLines = @(& git.exe -C $repository ls-tree -r $ExpectedCommit 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'deno_rusty_v8_git_tree_unreadable' }
    $gitlinks = [Collections.Generic.List[object]]::new()
    $gitlinkMap = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($line in $treeLines) {
        if ($line -notmatch '^160000 commit (?<commit>[0-9a-f]{40})\t(?<path>.+)$') { continue }
        $path = $Matches.path.Replace('\', '/')
        if ($gitlinkMap.ContainsKey($path)) { throw "deno_native_gitlink_duplicate:$path" }
        $gitlinkMap.Add($path, $Matches.commit)
        $gitlinks.Add([ordered]@{ path = $path; commit = $Matches.commit })
    }
    Assert-DenoUniquePaths @($gitlinks.path) | Out-Null
    $manifestMap = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($component in $Components) {
        $path = ([string]$component.path).Replace('\', '/')
        if ($manifestMap.ContainsKey($path)) { throw "deno_native_component_duplicate:$path" }
        $manifestMap.Add($path, $component)
    }
    foreach ($gitlink in $gitlinks | Sort-Object path) {
        if (-not $manifestMap.ContainsKey([string]$gitlink.path)) { throw "deno_native_component_missing:$($gitlink.path)" }
        if ([string]$manifestMap[[string]$gitlink.path].commit -cne [string]$gitlink.commit) { throw "deno_native_component_commit_mismatch:$($gitlink.path)" }
    }
    foreach ($component in $Components | Sort-Object path) {
        if (-not $gitlinkMap.ContainsKey([string]$component.path)) { throw "deno_native_component_not_gitlink:$($component.path)" }
    }
    return [pscustomobject]@{ commit = $ExpectedCommit; tree = $ExpectedTree; gitlinks = @($gitlinks | Sort-Object path) }
}

function Assert-DenoTargetClosure {
    param(
        [Parameter(Mandatory)] [string[]] $OfficialPackageIds,
        [Parameter(Mandatory)] [string[]] $SupersetPackageIds
    )
    $superset = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($packageId in $SupersetPackageIds) { [void]$superset.Add($packageId) }
    foreach ($id in $OfficialPackageIds | Sort-Object -Unique) {
        if (-not $superset.Contains($id)) { throw "deno_target_closure_mismatch:$id" }
    }
    return $true
}

function Assert-DenoReleaseIdentity {
    param(
        [Parameter(Mandatory)] [string] $DenoExePath,
        [Parameter(Mandatory)] [string] $ExpectedSha256,
        [Parameter(Mandatory)] [string] $ExpectedVersion,
        [Parameter(Mandatory)] [string] $ExpectedTarget
    )
    Assert-DenoHash $DenoExePath $ExpectedSha256
    $lines = @(& $DenoExePath --version 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0 -or $lines.Count -lt 1 -or
        $lines[0] -notmatch '^deno (?<version>[^ ]+) \(stable, release, (?<target>[^)]+)\)$' -or
        $Matches.version -cne $ExpectedVersion -or $Matches.target -cne $ExpectedTarget) {
        throw 'deno_release_identity_mismatch'
    }
    return [pscustomobject]@{ version = $Matches.version; target = $Matches.target; sha256 = $ExpectedSha256 }
}

function Get-DenoLicenseFiles {
    param([Parameter(Mandatory)] [string] $Root, [string] $DeclaredLicenseFile)
    $files = [Collections.Generic.List[IO.FileInfo]]::new()
    $Root = Assert-DenoNoReparsePath $Root
    foreach ($item in Get-ChildItem -LiteralPath $Root -Recurse -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "deno_reparse_path_rejected:$($item.FullName)" }
        if (-not $item.PSIsContainer -and $item.Name -match '^(?i:LICENSE|LICENCE|COPYING|NOTICE|PATENTS|COPYRIGHT)(?:[._-].*)?$') { $files.Add($item) }
    }
    if (-not [string]::IsNullOrWhiteSpace($DeclaredLicenseFile)) {
        $declared = [IO.Path]::GetFullPath((Join-Path $Root $DeclaredLicenseFile))
        $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
        if (-not $declared.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $declared -PathType Leaf)) {
            throw 'deno_declared_license_file_missing'
        }
        if ($files.FullName -notcontains $declared) { $files.Add((Get-Item -LiteralPath $declared)) }
    }
    return @($files | Sort-Object FullName -Unique)
}

function Get-DenoSpdxIndex {
    param([Parameter(Mandatory)] [string] $SpdxRoot)
    $licenses = Read-DenoJson (Join-Path $SpdxRoot 'json/licenses.json')
    $exceptions = Read-DenoJson (Join-Path $SpdxRoot 'json/exceptions.json')
    if ([string]$licenses.licenseListVersion -cne [string]$exceptions.licenseListVersion) { throw 'deno_spdx_version_mismatch' }
    $licenseMap = @{}
    foreach ($item in $licenses.licenses) { $licenseMap[[string]$item.licenseId] = $item }
    $exceptionMap = @{}
    foreach ($item in $exceptions.exceptions) { $exceptionMap[[string]$item.licenseExceptionId] = $item }
    return [pscustomobject]@{ version = [string]$licenses.licenseListVersion; licenses = $licenseMap; exceptions = $exceptionMap }
}

function Resolve-DenoSpdxExpression {
    param([Parameter(Mandatory)] [string] $Expression, [Parameter(Mandatory)] [string] $SpdxRoot)
    $failure = "deno_spdx_expression_invalid:$Expression"
    if ([string]::IsNullOrWhiteSpace($Expression) -or $Expression -match '(?i)NOASSERTION|UNKNOWN|LicenseRef-|DocumentRef-') { throw $failure }
    $index = Get-DenoSpdxIndex $SpdxRoot
    $tokens = [Collections.Generic.List[string]]::new()
    $position = 0
    $tokenPattern = [regex]::new('\G\s*(?<token>\(|\)|AND(?=\s|\()|OR(?=\s|\()|WITH(?=\s|\()|[A-Za-z0-9][A-Za-z0-9.+-]*)', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    while ($position -lt $Expression.Length) {
        $match = $tokenPattern.Match($Expression, $position)
        if (-not $match.Success -or $match.Index -ne $position -or [string]::IsNullOrWhiteSpace($match.Groups['token'].Value)) {
            if ($Expression.Substring($position) -match '^\s+$') { $position = $Expression.Length; break }
            throw $failure
        }
        $tokens.Add($match.Groups['token'].Value)
        $position += $match.Length
    }
    if ($tokens.Count -eq 0) { throw $failure }

    $state = [pscustomobject]@{ index = 0 }
    $licenseIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $exceptionIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $parseOr = $null
    $parsePrimary = {
        if ($state.index -ge $tokens.Count) { throw $failure }
        $token = $tokens[$state.index]
        if ($token -ceq '(') {
            $state.index++
            & $parseOr
            if ($state.index -ge $tokens.Count -or $tokens[$state.index] -cne ')') { throw $failure }
            $state.index++
            return
        }
        if ($token -in @(')', 'AND', 'OR', 'WITH') -or -not $index.licenses.ContainsKey($token)) { throw $failure }
        [void]$licenseIds.Add($token)
        $state.index++
        if ($state.index -lt $tokens.Count -and $tokens[$state.index] -ceq 'WITH') {
            $state.index++
            if ($state.index -ge $tokens.Count -or -not $index.exceptions.ContainsKey($tokens[$state.index])) { throw $failure }
            [void]$exceptionIds.Add($tokens[$state.index])
            $state.index++
        }
    }
    $parseAnd = {
        & $parsePrimary
        while ($state.index -lt $tokens.Count -and $tokens[$state.index] -ceq 'AND') { $state.index++; & $parsePrimary }
    }
    $parseOr = {
        & $parseAnd
        while ($state.index -lt $tokens.Count -and $tokens[$state.index] -ceq 'OR') { $state.index++; & $parseAnd }
    }
    & $parseOr
    if ($state.index -ne $tokens.Count) { throw $failure }

    $files = [Collections.Generic.List[object]]::new()
    foreach ($id in @($licenseIds | Sort-Object)) {
        $path = "text/$id.txt"
        $fullPath = Join-Path $SpdxRoot $path
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "deno_spdx_text_missing:$id" }
        $material = Get-DenoVerifiedByteMaterial -Path $fullPath -Cache
        $files.Add([ordered]@{ origin = 'spdx-license'; id = $id; path = $path; length = $material.length; sha256 = $material.sha256 })
    }
    foreach ($id in @($exceptionIds | Sort-Object)) {
        $path = "text/$id.txt"
        $fullPath = Join-Path $SpdxRoot $path
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "deno_spdx_exception_text_missing:$id" }
        $material = Get-DenoVerifiedByteMaterial -Path $fullPath -Cache
        $files.Add([ordered]@{ origin = 'spdx-exception'; id = $id; path = $path; length = $material.length; sha256 = $material.sha256 })
    }
    return [pscustomobject]@{ version = $index.version; licenseIds = @($licenseIds | Sort-Object); exceptionIds = @($exceptionIds | Sort-Object); files = @($files) }
}

function Get-DenoUtf8StringSha256 {
    param([Parameter(Mandatory)] [string] $Text)
    return ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text)))).ToLowerInvariant()
}

function New-DenoLicenseRefId {
    param([Parameter(Mandatory)] [string] $PackageId, [Parameter(Mandatory)] [string] $DeclaredLicense)
    $packageSlug = (($PackageId.ToLowerInvariant() -replace '@', '-') -replace '[^a-z0-9.-]', '-') -replace '-+', '-'
    $licenseSlug = (($DeclaredLicense.ToLowerInvariant() -replace '[^a-z0-9.-]', '-') -replace '-+', '-').Trim('-')
    $prefix = (Get-DenoUtf8StringSha256 $DeclaredLicense).Substring(0, 12)
    return "LicenseRef-$packageSlug-$licenseSlug-$prefix"
}

function Resolve-DenoExplicitLicenseRef {
    param(
        [Parameter(Mandatory)] [object] $Package,
        [Parameter(Mandatory)] [string] $DeclaredLicense,
        [Parameter(Mandatory)] [string] $CrateArchivePath,
        [Parameter(Mandatory)] [string] $SpdxRoot,
        [Parameter(Mandatory)] [object] $Mapping,
        [object] $CrateEvidence
    )
    $id = ([string]$Package.name) + '@' + ([string]$Package.version)
    if ([string]$Mapping.id -cne $id) { throw "deno_license_ref_mapping_mismatch:$id" }
    if ([string]$Mapping.declaredLicense -cne $DeclaredLicense) { throw "deno_license_ref_declaration_mismatch:$id" }
    $declaredHash = Get-DenoUtf8StringSha256 $DeclaredLicense
    if ($declaredHash -cne [string]$Mapping.declaredTextSha256) { throw "deno_license_ref_declaration_hash_mismatch:$id" }
    if ([string]$Package.checksum -cne [string]$Mapping.crateArchiveSha256) { throw "deno_license_ref_crate_hash_mismatch:$id" }
    $expectedRef = New-DenoLicenseRefId -PackageId $id -DeclaredLicense $DeclaredLicense
    if ([string]$Mapping.licenseRefId -cne $expectedRef) { throw "deno_license_ref_id_mismatch:$id" }
    if ($null -eq $CrateEvidence) { $CrateEvidence = Get-DenoCrateArchiveEvidence -Package $Package -CrateArchivePath $CrateArchivePath }
    if ([string]$CrateEvidence.manifest.path -cne [string]$Mapping.manifest.path -or
        [long]$CrateEvidence.manifest.length -ne [long]$Mapping.manifest.length -or
        [string]$CrateEvidence.manifest.sha256 -cne [string]$Mapping.manifest.sha256) { throw "deno_license_ref_manifest_hash_mismatch:$id" }
    $manifestLicense = Get-DenoTomlString -Text ([string]$CrateEvidence.manifestText) -Name 'license'
    if ($manifestLicense -cne $DeclaredLicense) { throw "deno_license_ref_manifest_declaration_mismatch:$id" }

    $canonical = [Collections.Generic.List[object]]::new()
    $builder = [Text.StringBuilder]::new()
    $builder.AppendLine('SPDX-2.3 Extracted Licensing Information').AppendLine("LicenseID: $expectedRef").AppendLine("Package: $id").AppendLine("Crate source path: $($Mapping.crateSourcePath)").AppendLine("Crate SHA-256: $($Mapping.crateArchiveSha256)").AppendLine("Manifest path: $($Mapping.manifest.path)").AppendLine("Manifest SHA-256: $($Mapping.manifest.sha256)").AppendLine().AppendLine('Author-declared license text (verbatim):').AppendLine($DeclaredLicense).AppendLine() | Out-Null
    foreach ($textRecord in $Mapping.canonicalTexts) {
        $path = Join-Path $SpdxRoot ([string]$textRecord.path)
        try {
            $material = Get-DenoVerifiedByteMaterial -Path $path -ExpectedLength ([long]$textRecord.length) -ExpectedSha256 ([string]$textRecord.sha256) -Cache
        }
        catch { throw "deno_license_ref_canonical_text_mismatch:$id`:$($textRecord.id)" }
        $text = ConvertFrom-DenoUtf8Bytes -Bytes $material.bytes
        $builder.AppendLine("Canonical text named by the literal declaration: $($textRecord.id)").AppendLine('--- BEGIN CANONICAL TEXT ---').Append($text) | Out-Null
        if (-not $text.EndsWith("`n", [StringComparison]::Ordinal)) { $builder.AppendLine() | Out-Null }
        $builder.AppendLine('--- END CANONICAL TEXT ---').AppendLine() | Out-Null
        $canonical.Add([ordered]@{ id = [string]$textRecord.id; path = [string]$textRecord.path; length = [long]$textRecord.length; sha256 = [string]$textRecord.sha256 })
    }
    $extractedText = $builder.ToString().Replace("`r`n", "`n").Replace("`r", "`n")
    $extractedHash = Get-DenoUtf8StringSha256 $extractedText
    $file = [ordered]@{ origin = 'license-ref-extracted'; path = "$expectedRef.txt"; length = [Text.Encoding]::UTF8.GetByteCount($extractedText); sha256 = $extractedHash; text = $extractedText }
    return [pscustomobject]@{ licenseRefId = $expectedRef; extractedText = $extractedText; extractedTextSha256 = $extractedHash; licenseComments = [string]$Mapping.licenseComments; canonicalTexts = @($canonical); resolvedLicenseFiles = @($file); provenance = $Mapping }
}

function Get-DenoSha256Bytes {
    param([Parameter(Mandatory)] [byte[]] $Bytes)
    return ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))).ToLowerInvariant()
}

function Get-DenoTomlString {
    param([Parameter(Mandatory)] [string] $Text, [Parameter(Mandatory)] [string] $Name)
    $escaped = [regex]::Escape($Name)
    $pattern = '(?m)^\s*' + $escaped + '\s*=\s*"(?<value>[^"]*)"'
    $match = [regex]::Match($Text, $pattern)
    if (-not $match.Success) { return '' }
    return $match.Groups['value'].Value
}

function Get-DenoCrateArchiveEvidence {
    param(
        [Parameter(Mandatory)] [object] $Package,
        [Parameter(Mandatory)] [string] $CrateArchivePath,
        [scriptblock] $AfterHashAction
    )
    $id = ([string]$Package.name) + '@' + ([string]$Package.version)
    if ([string]$Package.checksum -notmatch '^[0-9a-f]{64}$') { throw "deno_cargo_checksum_missing:$id" }
    $prefix = ([string]$Package.name) + '-' + ([string]$Package.version) + '/'
    $files = [Collections.Generic.List[object]]::new()
    $fileMap = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $manifest = $null
    $manifestText = $null
    $metadataManifest = $null
    $metadataManifestText = $null
    $verified = Open-DenoVerifiedReadFile -Path $CrateArchivePath
    try {
        $digest = Get-DenoStreamDigest -Stream $verified.Stream
        if ($digest.sha256 -cne [string]$Package.checksum) {
            throw ('deno_input_hash_mismatch:{0}' -f $CrateArchivePath)
        }
        if ($null -ne $AfterHashAction) { & $AfterHashAction }
        [void](Assert-DenoVerifiedReadFileUnchanged -VerifiedFile $verified)
        [void]$verified.Stream.Seek(0, [IO.SeekOrigin]::Begin)
        $gzip = [IO.Compression.GZipStream]::new($verified.Stream, [IO.Compression.CompressionMode]::Decompress, $true)
        try {
            $reader = [System.Formats.Tar.TarReader]::new($gzip, $true)
            try {
                while ($null -ne ($entry = $reader.GetNextEntry())) {
                    $entryPath = $entry.Name.Replace('\', '/')
                    if ($entry.EntryType -eq [System.Formats.Tar.TarEntryType]::Directory) { continue }
                    if ($entry.EntryType -notin @([System.Formats.Tar.TarEntryType]::RegularFile, [System.Formats.Tar.TarEntryType]::V7RegularFile)) { throw "deno_crate_archive_non_regular_entry:$id`:$entryPath" }
                    if (-not $entryPath.StartsWith($prefix, [StringComparison]::Ordinal)) { throw "deno_crate_archive_path_invalid:$id`:$entryPath" }
                    $relative = $entryPath.Substring($prefix.Length)
                    Assert-DenoUniquePaths @($relative) | Out-Null
                    if (-not $seen.Add($relative)) { throw "deno_path_case_collision:$($relative.ToLowerInvariant())" }
                    $capture = $relative -ceq 'Cargo.toml' -or $relative -ceq 'Cargo.toml.orig'
                    $memory = if ($capture) { [IO.MemoryStream]::new() } else { $null }
                    $hash = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
                    $length = 0L
                    try {
                        $buffer = [byte[]]::new(131072)
                        if ($null -eq $entry.DataStream) {
                            if ($entry.Length -ne 0) { throw "deno_crate_archive_stream_missing:$id`:$relative" }
                        }
                        else {
                            while (($read = $entry.DataStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                                $hash.AppendData($buffer, 0, $read)
                                if ($capture) { $memory.Write($buffer, 0, $read) }
                                $length += $read
                            }
                        }
                        $sha256 = ([Convert]::ToHexString($hash.GetHashAndReset())).ToLowerInvariant()
                    }
                    finally { $hash.Dispose() }
                    if ($length -ne [long]$entry.Length) { throw "deno_crate_archive_length_mismatch:$id`:$relative" }
                    $record = [ordered]@{ path = $relative; archiveEntry = $entryPath; length = $length; sha256 = $sha256 }
                    $files.Add($record)
                    $fileMap.Add($relative, $record)
                    if ($capture) {
                        try { $capturedText = [Text.UTF8Encoding]::new($false, $true).GetString($memory.ToArray()) } finally { $memory.Dispose() }
                        $capturedManifest = [ordered]@{ path = $entryPath; length = $length; sha256 = $sha256 }
                        if ($relative -ceq 'Cargo.toml.orig') {
                            $manifestText = $capturedText
                            $manifest = $capturedManifest
                        }
                        else {
                            $metadataManifestText = $capturedText
                            $metadataManifest = $capturedManifest
                        }
                    }
                }
            }
            finally { $reader.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally {
        try { [void](Assert-DenoVerifiedReadFileUnchanged -VerifiedFile $verified) }
        finally { Close-DenoVerifiedReadFile -VerifiedFile $verified }
    }
    if ($null -eq $metadataManifest -or [string]::IsNullOrWhiteSpace($metadataManifestText)) { throw "deno_crate_manifest_missing:$id" }
    if ($null -eq $manifest) {
        $manifest = $metadataManifest
        $manifestText = $metadataManifestText
    }
    return [pscustomobject]@{ manifest = $manifest; manifestText = $manifestText; metadataManifest = $metadataManifest; metadataManifestText = $metadataManifestText; files = @($files); fileMap = $fileMap }
}

function Assert-DenoVendorAgainstCrate {
    param(
        [Parameter(Mandatory)] [string] $VendorPath,
        [Parameter(Mandatory)] [object] $CrateEvidence,
        [Parameter(Mandatory)] [string] $ExpectedPackageChecksum,
        [Parameter(Mandatory)] [string] $Id
    )
    $vendor = (Assert-DenoNoReparsePath $VendorPath).TrimEnd('\')
    $checksumPath = Join-Path $vendor '.cargo-checksum.json'
    $checksum = Read-DenoJson $checksumPath
    if ([string]$checksum.package -cne $ExpectedPackageChecksum) { throw "deno_cargo_checksum_mismatch:$Id" }
    $checksumProperties = @($checksum.files.psobject.Properties)
    Assert-DenoUniquePaths @($checksumProperties.Name) | Out-Null
    $checksumMap = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($property in $checksumProperties) { $checksumMap.Add($property.Name.Replace('\', '/'), [string]$property.Value) }
    $vendorFiles = [Collections.Generic.List[object]]::new()
    foreach ($item in Get-ChildItem -LiteralPath $vendor -Recurse -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "deno_reparse_path_rejected:$($item.FullName)" }
        if ($item.PSIsContainer) { continue }
        $relative = $item.FullName.Substring($vendor.Length + 1).Replace('\', '/')
        if ($relative -ceq '.cargo-checksum.json') { continue }
        $vendorFiles.Add([ordered]@{ path = $relative; fullName = $item.FullName })
    }
    Assert-DenoUniquePaths @($vendorFiles.path) | Out-Null
    foreach ($file in $vendorFiles | Sort-Object path) {
        if (-not $CrateEvidence.fileMap.ContainsKey([string]$file.path)) { throw "deno_vendor_file_not_in_archive:$Id`:$($file.path)" }
        $archiveHash = [string]$CrateEvidence.fileMap[[string]$file.path].sha256
        if ((Get-DenoSha256 ([string]$file.fullName)) -cne $archiveHash) { throw "deno_vendor_archive_mismatch:$Id`:$($file.path)" }
        if (-not $checksumMap.ContainsKey([string]$file.path)) { throw "deno_vendor_unchecksummed_file:$Id`:$($file.path)" }
        if ($checksumMap[[string]$file.path] -cne $archiveHash) { throw "deno_vendor_checksum_archive_mismatch:$Id`:$($file.path)" }
    }
    foreach ($path in $checksumMap.Keys | Sort-Object) {
        if (-not $CrateEvidence.fileMap.ContainsKey($path)) { throw "deno_vendor_checksum_path_not_in_archive:$Id`:$path" }
        if ($checksumMap[$path] -cne [string]$CrateEvidence.fileMap[$path].sha256) { throw "deno_vendor_checksum_archive_mismatch:$Id`:$path" }
        if (-not [IO.File]::Exists((Join-Path $vendor $path))) { throw "deno_vendor_checksum_file_missing:$Id`:$path" }
    }
}

function Get-DenoZipEntrySha256 {
    param([Parameter(Mandatory)] [string] $ArchivePath, [Parameter(Mandatory)] [string] $EntryPath)
    return Get-DenoSha256Bytes (Get-DenoZipEntryBytes -ArchivePath $ArchivePath -EntryPath $EntryPath)
}

function Get-DenoZipEntryBytes {
    param([Parameter(Mandatory)] [string] $ArchivePath, [Parameter(Mandatory)] [string] $EntryPath)
    Assert-DenoUniquePaths @($EntryPath) | Out-Null
    $verified = Open-DenoVerifiedReadFile -Path $ArchivePath
    try {
        $zip = [IO.Compression.ZipArchive]::new(
            $verified.Stream, [IO.Compression.ZipArchiveMode]::Read, $true)
        try {
            Assert-DenoUniquePaths @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') } | ForEach-Object FullName) | Out-Null
            $entries = @($zip.Entries | Where-Object { $_.FullName -ceq $EntryPath })
            if ($entries.Count -ne 1) { throw "deno_upstream_license_entry_missing:$EntryPath" }
            $stream = $entries[0].Open()
            try {
                $memory = [IO.MemoryStream]::new()
                try { $stream.CopyTo($memory); return ,$memory.ToArray() }
                finally { $memory.Dispose() }
            }
            finally { $stream.Dispose() }
        }
        finally { $zip.Dispose() }
    }
    finally {
        [void](Assert-DenoVerifiedReadFileUnchanged -VerifiedFile $verified)
        Close-DenoVerifiedReadFile -VerifiedFile $verified
    }
}

function Copy-DenoZipEntry {
    param([Parameter(Mandatory)] [string] $ArchivePath, [Parameter(Mandatory)] [string] $EntryPath, [Parameter(Mandatory)] [string] $Destination)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Write-DenoBytes -Path $Destination -Bytes (Get-DenoZipEntryBytes -ArchivePath $ArchivePath -EntryPath $EntryPath)
}

function Get-DenoTarEntryBytes {
    param([Parameter(Mandatory)] [string] $ArchivePath, [Parameter(Mandatory)] [string] $EntryPath)
    Assert-DenoUniquePaths @($EntryPath) | Out-Null
    $verified = Open-DenoVerifiedReadFile -Path $ArchivePath
    try {
        $gzip = [IO.Compression.GZipStream]::new($verified.Stream, [IO.Compression.CompressionMode]::Decompress, $true)
        try {
            $reader = [System.Formats.Tar.TarReader]::new($gzip, $true)
            try {
                $found = $null
                while ($null -ne ($entry = $reader.GetNextEntry())) {
                    if ($entry.Name.Replace('\', '/') -cne $EntryPath.Replace('\', '/')) { continue }
                    if ($null -ne $found) { throw "deno_native_license_entry_duplicate:$EntryPath" }
                    if ($entry.EntryType -notin @([System.Formats.Tar.TarEntryType]::RegularFile, [System.Formats.Tar.TarEntryType]::V7RegularFile)) { throw "deno_native_license_entry_not_regular:$EntryPath" }
                    $memory = [IO.MemoryStream]::new()
                    try { $entry.DataStream.CopyTo($memory); $found = $memory.ToArray() } finally { $memory.Dispose() }
                }
                if ($null -eq $found) { throw "deno_native_license_entry_missing:$EntryPath" }
                return ,$found
            }
            finally { $reader.Dispose() }
        }
        finally { $gzip.Dispose() }
    }
    finally {
        [void](Assert-DenoVerifiedReadFileUnchanged -VerifiedFile $verified)
        Close-DenoVerifiedReadFile -VerifiedFile $verified
    }
}

function Copy-DenoTarEntry {
    param([Parameter(Mandatory)] [string] $ArchivePath, [Parameter(Mandatory)] [string] $EntryPath, [Parameter(Mandatory)] [string] $Destination)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Write-DenoBytes -Path $Destination -Bytes (Get-DenoTarEntryBytes -ArchivePath $ArchivePath -EntryPath $EntryPath)
}

function Get-DenoTarArchiveEntries {
    param(
        [Parameter(Mandatory)] [string] $ArchivePath,
        [Parameter(Mandatory)] [string] $ExpectedSha256,
        [Parameter(Mandatory)] [long] $ExpectedLength
    )
    $verified = Open-DenoVerifiedReadFile -Path $ArchivePath
    try {
        $digest = Get-DenoStreamDigest -Stream $verified.Stream
        if ($digest.length -ne $ExpectedLength) { throw ('deno_native_archive_length_mismatch:{0}' -f $ArchivePath) }
        if ($ExpectedSha256 -notmatch '^[0-9a-f]{64}$' -or $digest.sha256 -cne $ExpectedSha256) {
            throw ('deno_input_hash_mismatch:{0}' -f $ArchivePath)
        }
        $gzip = [IO.Compression.GZipStream]::new($verified.Stream, [IO.Compression.CompressionMode]::Decompress, $true)
        try {
            $reader = [System.Formats.Tar.TarReader]::new($gzip, $true)
            try {
                $entries = [Collections.Generic.List[string]]::new()
                while ($null -ne ($entry = $reader.GetNextEntry())) {
                    if ($entry.EntryType -eq [System.Formats.Tar.TarEntryType]::Directory) { continue }
                    $entries.Add($entry.Name.Replace('\', '/')) | Out-Null
                }
            }
            finally { $reader.Dispose() }
        }
        finally { $gzip.Dispose() }
        if ($entries.Count -eq 0) { throw ('deno_native_archive_invalid:{0}' -f $ArchivePath) }
        Assert-DenoUniquePaths @($entries) | Out-Null
        return @($entries)
    }
    finally {
        [void](Assert-DenoVerifiedReadFileUnchanged -VerifiedFile $verified)
        Close-DenoVerifiedReadFile -VerifiedFile $verified
    }
}

function Add-DenoEmbeddedComponent {
    param(
        [Parameter(Mandatory)] [object] $Component,
        [Parameter(Mandatory)] [string] $DenoSourceRoot,
        [Parameter(Mandatory)] [string] $DenoSourceArchivePath,
        [Parameter(Mandatory)] [string] $SpdxRoot,
        [Parameter(Mandatory)] [string] $StageRoot,
        [Parameter(Mandatory)] [Text.StringBuilder] $Notice,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [Collections.Generic.List[string]] $OutputPaths
    )
    $source = $Component.sourceFile
    $sourceBytes = Get-DenoZipEntryBytes -ArchivePath $DenoSourceArchivePath -EntryPath ([string]$source.archiveEntry)
    $sourceHash = Get-DenoSha256Bytes $sourceBytes
    if ($sourceBytes.Length -ne [long]$source.length -or $sourceHash -cne [string]$source.sha256) { throw "deno_embedded_source_mismatch:$($Component.id)" }
    $sourcePath = Join-Path $DenoSourceRoot ([string]$source.path)
    $sourceItem = Get-Item -LiteralPath (Assert-DenoNoReparsePath $sourcePath)
    if ($sourceItem.Length -ne [long]$source.length -or (Get-DenoSha256 $sourcePath) -cne $sourceHash) { throw "deno_embedded_source_root_mismatch:$($Component.id)" }
    $sourceText = [Text.UTF8Encoding]::new($false, $true).GetString($sourceBytes)
    foreach ($requiredText in $source.requiredText) {
        if (-not $sourceText.Contains([string]$requiredText, [StringComparison]::Ordinal)) { throw "deno_embedded_source_content_mismatch:$($Component.id)" }
    }
    $buildEvidence = [Collections.Generic.List[object]]::new()
    foreach ($evidence in $Component.buildInclusionEvidence) {
        $bytes = Get-DenoZipEntryBytes -ArchivePath $DenoSourceArchivePath -EntryPath ([string]$evidence.archiveEntry)
        $sha256 = Get-DenoSha256Bytes $bytes
        $path = Join-Path $DenoSourceRoot ([string]$evidence.path)
        $item = Get-Item -LiteralPath (Assert-DenoNoReparsePath $path)
        if ($item.Length -ne $bytes.Length -or (Get-DenoSha256 $path) -cne $sha256) { throw "deno_embedded_build_evidence_mismatch:$($Component.id):$($evidence.path)" }
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        if (-not $text.Contains([string]$evidence.requiredText, [StringComparison]::Ordinal)) { throw "deno_embedded_build_reference_missing:$($Component.id):$($evidence.path)" }
        $buildEvidence.Add([ordered]@{ role = [string]$evidence.role; path = [string]$evidence.path; archiveEntry = [string]$evidence.archiveEntry; length = $bytes.Length; sha256 = $sha256; requiredText = [string]$evidence.requiredText })
    }
    $license = $Component.licenseFile
    $licensePath = Join-Path $SpdxRoot ([string]$license.path)
    try {
        $licenseMaterial = Get-DenoVerifiedByteMaterial -Path $licensePath -ExpectedLength ([long]$license.length) -ExpectedSha256 ([string]$license.sha256) -Cache
    }
    catch { throw "deno_embedded_license_mismatch:$($Component.id)" }
    $sourceDestination = Join-Path $StageRoot ([string]$source.bundlePath)
    New-Item -ItemType Directory -Path (Split-Path -Parent $sourceDestination) -Force | Out-Null
    [IO.File]::WriteAllBytes((Assert-DenoNoReparsePath $sourceDestination), $sourceBytes)
    $licenseDestination = Join-Path $StageRoot ([string]$license.bundlePath)
    New-Item -ItemType Directory -Path (Split-Path -Parent $licenseDestination) -Force | Out-Null
    Write-DenoBytes -Path (Assert-DenoNoReparsePath $licenseDestination) -Bytes $licenseMaterial.bytes
    $OutputPaths.Add([string]$source.bundlePath)
    $OutputPaths.Add([string]$license.bundlePath)
    $licenseText = ConvertFrom-DenoUtf8Bytes -Bytes $licenseMaterial.bytes
    $Notice.AppendLine("=== embedded $($Component.name) $($Component.version) ===").AppendLine("Deno source commit: $($Component.denoSourceCommit)").AppendLine("Source path: $($source.path)").AppendLine("Source length: $($source.length)").AppendLine("Source SHA-256: $($source.sha256)").AppendLine("Copyright: $($Component.copyright)").AppendLine("License: $($Component.license)").AppendLine("Inclusion: $($Component.inclusionReason)") | Out-Null
    foreach ($evidence in $buildEvidence) { $Notice.AppendLine("Build evidence: $($evidence.role) $($evidence.path) $($evidence.sha256)") | Out-Null }
    $Notice.AppendLine("--- $($license.bundlePath) ---").AppendLine($licenseText).AppendLine() | Out-Null
    return [ordered]@{
        id = [string]$Component.id
        name = [string]$Component.name
        version = [string]$Component.version
        denoSourceCommit = [string]$Component.denoSourceCommit
        sourceFile = [ordered]@{ path = [string]$source.path; archiveEntry = [string]$source.archiveEntry; bundlePath = [string]$source.bundlePath; length = [long]$source.length; sha256 = [string]$source.sha256 }
        copyright = [string]$Component.copyright
        license = [string]$Component.license
        licenseFile = [ordered]@{ origin = 'spdx-license'; path = [string]$license.path; bundlePath = [string]$license.bundlePath; length = [long]$license.length; sha256 = [string]$license.sha256 }
        buildInclusionEvidence = @($buildEvidence)
        inclusionReason = [string]$Component.inclusionReason
    }
}

function Resolve-DenoUpstreamFallback {
    param([Parameter(Mandatory)] [object] $Fallback, [Parameter(Mandatory)] [string] $UpstreamSourceRoot)
    $archive = Join-Path $UpstreamSourceRoot ([string]$Fallback.archiveFile)
    $item = Get-Item -LiteralPath $archive
    if ($item.Length -ne [long]$Fallback.length) { throw "deno_upstream_archive_length_mismatch:$($Fallback.id)" }
    Assert-DenoHash $archive ([string]$Fallback.sha256)
    $files = [Collections.Generic.List[object]]::new()
    foreach ($license in $Fallback.licenseFiles) {
        $actual = Get-DenoZipEntrySha256 -ArchivePath $archive -EntryPath ([string]$license.path)
        if ($actual -cne [string]$license.sha256) { throw "deno_upstream_license_hash_mismatch:$($Fallback.id):$($license.path)" }
        $files.Add([ordered]@{ origin = 'upstream-commit'; path = [string]$license.path; length = [long]$license.length; sha256 = $actual; archiveFile = [string]$Fallback.archiveFile })
    }
    if ($files.Count -eq 0) { throw "deno_upstream_license_file_missing:$($Fallback.id)" }
    return [pscustomobject]@{ files = @($files); provenance = $Fallback }
}

function Assert-DenoCratePackage {
    param(
        [Parameter(Mandatory)] [object] $Package,
        [Parameter(Mandatory)] [string] $VendorPath,
        [string] $CrateArchivePath,
        [string] $SpdxRoot,
        [object] $LicenseRefMapping,
        [object] $UpstreamFallback,
        [string] $UpstreamSourceRoot
    )
    $id = ([string]$Package.name) + '@' + ([string]$Package.version)
    Assert-DenoImmutableCargoSource ([string]$Package.source) | Out-Null
    if ([string]$Package.checksum -notmatch '^[0-9a-f]{64}$') { throw "deno_cargo_checksum_missing:$id" }
    if ([string]::IsNullOrWhiteSpace($CrateArchivePath)) { throw "deno_crate_archive_missing:$id" }
    $checksum = Read-DenoJson (Join-Path $VendorPath '.cargo-checksum.json')
    if ([string]$checksum.package -cne [string]$Package.checksum) { throw "deno_cargo_checksum_mismatch:$id" }
    $crateEvidence = Get-DenoCrateArchiveEvidence -Package $Package -CrateArchivePath $CrateArchivePath
    Assert-DenoVendorAgainstCrate -VendorPath $VendorPath -CrateEvidence $crateEvidence -ExpectedPackageChecksum ([string]$Package.checksum) -Id $id
    $toml = [string]$crateEvidence.metadataManifestText
    $manifestName = Get-DenoTomlString -Text $toml -Name 'name'
    $manifestVersion = Get-DenoTomlString -Text $toml -Name 'version'
    if ($manifestName -cne [string]$Package.name -or $manifestVersion -cne [string]$Package.version) { throw "deno_crate_manifest_identity_mismatch:$id" }
    $license = Get-DenoTomlString -Text $toml -Name 'license'
    $licenseFile = Get-DenoTomlString -Text $toml -Name 'license-file'
    $repository = Get-DenoTomlString -Text $toml -Name 'repository'
    if ([string]::IsNullOrWhiteSpace($license) -and [string]::IsNullOrWhiteSpace($licenseFile)) {
        throw "deno_crate_license_metadata_missing:$id"
    }
    if ($license -match '(?i)NOASSERTION|UNKNOWN') { throw "deno_crate_license_ambiguous:$id" }
    $licensePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($file in $crateEvidence.files) {
        if ([IO.Path]::GetFileName([string]$file.path) -match '^(?i:LICENSE|LICENCE|COPYING|NOTICE|PATENTS|COPYRIGHT)(?:[._-].*)?$') { [void]$licensePaths.Add([string]$file.path) }
    }
    if (-not [string]::IsNullOrWhiteSpace($licenseFile)) {
        $declaredPath = $licenseFile.Replace('\', '/')
        Assert-DenoUniquePaths @($declaredPath) | Out-Null
        if (-not $crateEvidence.fileMap.ContainsKey($declaredPath)) { throw "deno_declared_license_file_missing:$id" }
        [void]$licensePaths.Add($declaredPath)
    }
    $records = @($licensePaths | Sort-Object | ForEach-Object {
        $file = $crateEvidence.fileMap[$_]
        [ordered]@{ origin = 'package-archive'; path = [string]$file.path; archiveEntry = [string]$file.archiveEntry; length = [long]$file.length; sha256 = [string]$file.sha256 }
    })
    if ($records.Count -gt 0) {
        return [pscustomobject]@{ id = $id; license = $license; licenseFile = $licenseFile; repository = $repository; crateManifest = $crateEvidence.manifest; crateMetadataManifest = $crateEvidence.metadataManifest; resolution = 'package-files'; resolvedLicenseFiles = $records; spdxLicenseIds = @(); spdxExceptionIds = @(); licenseRefId = $null; extractedTextSha256 = $null; licenseComments = $null; canonicalTexts = @(); provenance = $null }
    }
    if (-not [string]::IsNullOrWhiteSpace($SpdxRoot)) {
        try {
            $spdx = Resolve-DenoSpdxExpression -Expression $license -SpdxRoot $SpdxRoot
            return [pscustomobject]@{ id = $id; license = $license; licenseFile = $licenseFile; repository = $repository; crateManifest = $crateEvidence.manifest; crateMetadataManifest = $crateEvidence.metadataManifest; resolution = 'spdx-canonical-fallback'; resolvedLicenseFiles = @($spdx.files); spdxLicenseIds = @($spdx.licenseIds); spdxExceptionIds = @($spdx.exceptionIds); licenseRefId = $null; extractedTextSha256 = $null; licenseComments = $null; canonicalTexts = @(); provenance = [ordered]@{ spdxVersion = $spdx.version } }
        }
        catch {
            if ($null -eq $LicenseRefMapping -and $null -eq $UpstreamFallback) { throw }
        }
    }
    if ($null -ne $LicenseRefMapping -and -not [string]::IsNullOrWhiteSpace($CrateArchivePath)) {
        $licenseRef = Resolve-DenoExplicitLicenseRef -Package $Package -DeclaredLicense $license -CrateArchivePath $CrateArchivePath -SpdxRoot $SpdxRoot -Mapping $LicenseRefMapping -CrateEvidence $crateEvidence
        return [pscustomobject]@{ id = $id; license = $license; licenseFile = $licenseFile; repository = $repository; crateManifest = $crateEvidence.manifest; crateMetadataManifest = $crateEvidence.metadataManifest; resolution = 'spdx-license-ref'; resolvedLicenseFiles = @($licenseRef.resolvedLicenseFiles); spdxLicenseIds = @(); spdxExceptionIds = @(); licenseRefId = $licenseRef.licenseRefId; extractedTextSha256 = $licenseRef.extractedTextSha256; licenseComments = $licenseRef.licenseComments; canonicalTexts = $licenseRef.canonicalTexts; provenance = $licenseRef.provenance }
    }
    if ($null -ne $UpstreamFallback -and -not [string]::IsNullOrWhiteSpace($UpstreamSourceRoot)) {
        $upstream = Resolve-DenoUpstreamFallback -Fallback $UpstreamFallback -UpstreamSourceRoot $UpstreamSourceRoot
        return [pscustomobject]@{ id = $id; license = $license; licenseFile = $licenseFile; repository = $repository; crateManifest = $crateEvidence.manifest; crateMetadataManifest = $crateEvidence.metadataManifest; resolution = 'upstream-commit-license-files'; resolvedLicenseFiles = @($upstream.files); spdxLicenseIds = @(); spdxExceptionIds = @(); licenseRefId = $null; extractedTextSha256 = $null; licenseComments = $null; canonicalTexts = @(); provenance = $upstream.provenance }
    }
    throw "deno_crate_license_file_missing:$id"
}

function Read-DenoCargoLockPackages {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Path')] [string] $CargoLockPath,
        [Parameter(Mandatory, ParameterSetName = 'Bytes')] [byte[]] $Bytes,
        [Parameter(Mandatory, ParameterSetName = 'Text')] [string] $Text,
        [Parameter(ParameterSetName = 'Path')] [string] $ExpectedSha256,
        [Parameter(ParameterSetName = 'Path')] [long] $MaximumLength = 67108864,
        [Parameter(ParameterSetName = 'Path')] [scriptblock] $AfterHashAction
    )
    $raw = switch ($PSCmdlet.ParameterSetName) {
        'Path' {
            $material = Get-DenoVerifiedByteMaterial -Path $CargoLockPath -MaximumLength $MaximumLength -ExpectedSha256 $ExpectedSha256 -AfterHashAction $AfterHashAction
            ConvertFrom-DenoUtf8Bytes -Bytes $material.bytes
        }
        'Bytes' { ConvertFrom-DenoUtf8Bytes -Bytes $Bytes }
        'Text' { $Text }
    }
    $packages = [Collections.Generic.List[object]]::new()
    foreach ($match in [regex]::Matches($raw, '(?ms)^\[\[package\]\]\r?\n(.*?)(?=^\[\[package\]\]|\z)')) {
        $block = $match.Groups[1].Value
        $name = [regex]::Match($block, '(?m)^name = "([^"]+)"').Groups[1].Value
        $version = [regex]::Match($block, '(?m)^version = "([^"]+)"').Groups[1].Value
        $source = [regex]::Match($block, '(?m)^source = "([^"]+)"').Groups[1].Value
        $checksum = [regex]::Match($block, '(?m)^checksum = "([0-9a-f]{64})"').Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($version)) { throw 'deno_cargo_lock_parse_failed' }
        if (-not [string]::IsNullOrWhiteSpace($source)) { Assert-DenoImmutableCargoSource $source | Out-Null }
        $packages.Add([pscustomobject]@{ name = $name; version = $version; source = $source; checksum = $checksum })
    }
    if ($packages.Count -eq 0) { throw 'deno_cargo_lock_empty' }
    return @($packages)
}

function Get-DenoMetadataPackageIds {
    param([Parameter(Mandatory)] [object] $Metadata)
    return @($Metadata.packages | ForEach-Object { ([string]$_.name) + '@' + ([string]$_.version) } | Sort-Object -Unique)
}

function Write-DenoBlockerReport {
    param(
        [Parameter(Mandatory)] [string] $ScratchRoot,
        [Parameter(Mandatory)] [object] $Identity,
        [Parameter(Mandatory)] [string[]] $Blockers,
        [Parameter(Mandatory)] [hashtable] $Counts,
        [object[]] $UnresolvedEvidence = @()
    )
    $report = [ordered]@{
        schemaVersion = 'deno-third-party-collection-blockers/v1'
        status = 'NOT_VERIFIED'
        closureClassification = 'verified-conservative-superset'
        releaseIdentity = $Identity
        counts = [ordered]@{
            cargoLockPackages = $Counts.cargoLockPackages
            registryPackages = $Counts.registryPackages
            resolvedRegistryPackages = $Counts.resolvedRegistryPackages
            registryPackageFileResolutions = $Counts.registryPackageFileResolutions
            registrySpdxResolutions = $Counts.registrySpdxResolutions
            registryLicenseRefResolutions = $Counts.registryLicenseRefResolutions
            registryUpstreamResolutions = $Counts.registryUpstreamResolutions
            workspacePackages = $Counts.workspacePackages
            resolvedWorkspacePackages = $Counts.resolvedWorkspacePackages
            workspaceSpdxResolutions = $Counts.workspaceSpdxResolutions
            workspaceUpstreamResolutions = $Counts.workspaceUpstreamResolutions
            nativeComponents = $Counts.nativeComponents
            embeddedComponents = $Counts.embeddedComponents
        }
        blockers = @($Blockers | Sort-Object -Unique)
        unresolvedEvidence = @($UnresolvedEvidence | Sort-Object id)
        noticeArtifactProduced = $false
        sourceBundleProduced = $false
        overallReleasePass = $false
    }
    $path = Join-Path $ScratchRoot 'deno-collection-blockers.json'
    Write-DenoUtf8Text $path (($report | ConvertTo-Json -Depth 10) + "`n")
    return $path
}

function New-DenoDeterministicZip {
    param([Parameter(Mandatory)] [string] $SourceRoot, [Parameter(Mandatory)] [string] $ZipPath)
    $root = [IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force | Sort-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') })
    $relative = @($files | ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') })
    Assert-DenoUniquePaths $relative | Out-Null
    $stream = [IO.File]::Open($ZipPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            for ($index = 0; $index -lt $files.Count; $index++) {
                $entry = $zip.CreateEntry($relative[$index], [IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $input = Open-DenoVerifiedReadFile -Path $files[$index].FullName
                try {
                    $output = $entry.Open()
                    try { $input.Stream.CopyTo($output) }
                    finally { $output.Dispose() }
                    [void](Assert-DenoVerifiedReadFileUnchanged -VerifiedFile $input)
                }
                finally { Close-DenoVerifiedReadFile -VerifiedFile $input }
            }
        }
        finally { $zip.Dispose() }
    }
    finally { $stream.Dispose() }
    return Get-DenoSha256 $ZipPath
}

function Invoke-DenoThirdPartyNoticeCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ManifestRoot,
        [Parameter(Mandatory)] [string] $DenoSourceRoot,
        [Parameter(Mandatory)] [string] $RustyV8SourceRoot,
        [Parameter(Mandatory)] [string] $RustyV8GitRepositoryPath,
        [Parameter(Mandatory)] [string] $V8SourceRoot,
        [Parameter(Mandatory)] [string] $VendorRoot,
        [Parameter(Mandatory)] [string] $OfficialMetadataPath,
        [Parameter(Mandatory)] [string] $SupersetMetadataPath,
        [Parameter(Mandatory)] [string] $DenoExePath,
        [Parameter(Mandatory)] [string] $DenoSourceArchivePath,
        [Parameter(Mandatory)] [string] $RustyV8SourceArchivePath,
        [Parameter(Mandatory)] [string] $V8SourceArchivePath,
        [Parameter(Mandatory)] [string] $RustyV8StaticLibArchivePath,
        [Parameter(Mandatory)] [string] $NativeSourceRoot,
        [Parameter(Mandatory)] [string] $CrateArchiveRoot,
        [Parameter(Mandatory)] [string] $SpdxRoot,
        [Parameter(Mandatory)] [string] $SpdxArchivePath,
        [Parameter(Mandatory)] [string] $UpstreamSourceRoot,
        [Parameter(Mandatory)] [string] $UpstreamFallbackManifest,
        [Parameter(Mandatory)] [string] $ScratchRoot
    )
    $mainGuards = [Collections.Generic.List[object]]::new()
    try {
        $script:DenoVerifiedMaterialCache = @{}
        foreach ($inputPath in @($ManifestRoot, $DenoSourceRoot, $RustyV8SourceRoot, $RustyV8GitRepositoryPath,
                $V8SourceRoot, $VendorRoot, $OfficialMetadataPath, $SupersetMetadataPath, $DenoExePath,
                $DenoSourceArchivePath, $RustyV8SourceArchivePath, $V8SourceArchivePath,
                $RustyV8StaticLibArchivePath, $NativeSourceRoot, $CrateArchiveRoot, $SpdxRoot,
                $SpdxArchivePath, $UpstreamSourceRoot, $UpstreamFallbackManifest)) {
            $guard = Open-DenoPathChain -Path $inputPath -ReadFinal:([IO.File]::Exists($inputPath))
            $mainGuards.Add($guard) | Out-Null
        }
        $ScratchRoot = Assert-DenoNoReparsePath $ScratchRoot
        if (-not [IO.Directory]::Exists($ScratchRoot)) { [void][IO.Directory]::CreateDirectory($ScratchRoot) }
        $scratchGuard = Open-DenoPathChain -Path $ScratchRoot
        $mainGuards.Add($scratchGuard) | Out-Null
        $finalOutputRoot = Join-Path $ScratchRoot 'deno-third-party-output'
        [void](Assert-DenoNoReparsePath $finalOutputRoot)
        if ([IO.Directory]::Exists($finalOutputRoot) -or [IO.File]::Exists($finalOutputRoot)) { throw 'deno_output_already_exists' }
    $inputs = Read-DenoJson (Join-Path $ManifestRoot 'inputs.json')
    Assert-DenoEmbeddedProfile -Inputs $inputs | Out-Null
    $native = Read-DenoJson (Join-Path $ManifestRoot 'native-components.json')
    $fallbacks = Read-DenoJson $UpstreamFallbackManifest
    if ($inputs.schemaVersion -cne 'deno-third-party-inputs/v3' -or
        $native.schemaVersion -cne 'deno-native-components/v2' -or
        $fallbacks.schemaVersion -cne 'deno-license-fallbacks/v1' -or
        $inputs.closureClassification -cne 'verified-conservative-superset') { throw 'deno_input_manifest_invalid' }
    $identity = Assert-DenoReleaseIdentity -DenoExePath $DenoExePath -ExpectedSha256 $inputs.releaseIdentity.denoExeSha256 -ExpectedVersion $inputs.releaseIdentity.version -ExpectedTarget $inputs.releaseIdentity.target

    $artifactPaths = @{
        denoSource = $DenoSourceArchivePath; rustyV8Source = $RustyV8SourceArchivePath
        v8Source = $V8SourceArchivePath; rustyV8StaticLibrary = $RustyV8StaticLibArchivePath
        spdxLicenseListData = $SpdxArchivePath
    }
    foreach ($artifact in $inputs.sourceArtifacts) {
        $path = [string]$artifactPaths[[string]$artifact.id]
        if ([string]::IsNullOrWhiteSpace($path)) { throw "deno_source_artifact_unmapped:$($artifact.id)" }
        $item = Get-Item -LiteralPath $path
        if ($item.Length -ne [long]$artifact.length) { throw "deno_source_artifact_length_mismatch:$($artifact.id)" }
        Assert-DenoHash $path ([string]$artifact.sha256)
    }
    $cargoLockPins = @($inputs.pinnedSourceFiles | Where-Object { [string]$_.root -ceq 'deno' -and [string]$_.path -ceq 'Cargo.lock' })
    if ($cargoLockPins.Count -ne 1) { throw 'deno_cargo_lock_pin_invalid' }
    foreach ($pinned in $inputs.pinnedSourceFiles) {
        if ([string]$pinned.root -ceq 'deno' -and [string]$pinned.path -ceq 'Cargo.lock') { continue }
        $base = switch ([string]$pinned.root) { 'deno' { $DenoSourceRoot } 'rusty_v8' { $RustyV8SourceRoot } 'v8' { $V8SourceRoot } 'spdx' { $SpdxRoot } default { throw 'deno_pinned_source_root_invalid' } }
        Assert-DenoHash (Join-Path $base ([string]$pinned.path)) ([string]$pinned.sha256)
    }
    $spdxIndex = Get-DenoSpdxIndex $SpdxRoot
    if ($spdxIndex.version -cne [string]$inputs.spdxLicenseList.version) { throw 'deno_spdx_version_mismatch' }
    if ([string]$inputs.spdxLicenseList.tagObject -notmatch '^[0-9a-f]{40}$' -or
        [string]$inputs.spdxLicenseList.peeledCommit -notmatch '^[0-9a-f]{40}$' -or
        [string]$inputs.spdxLicenseList.tagObject -ceq [string]$inputs.spdxLicenseList.peeledCommit) { throw 'deno_spdx_git_identity_invalid' }
    $spdxArtifact = @($inputs.sourceArtifacts | Where-Object id -ceq 'spdxLicenseListData')[0]
    if ([string]$spdxArtifact.sourceUrl -cne "https://codeload.github.com/spdx/license-list-data/zip/$($inputs.spdxLicenseList.tagObject)") { throw 'deno_spdx_archive_object_mismatch' }

    $registryFallbackMap = @{}
    foreach ($fallback in $fallbacks.registryFallbacks) {
        if ($registryFallbackMap.ContainsKey([string]$fallback.id)) { throw "deno_fallback_duplicate:$($fallback.id)" }
        $registryFallbackMap[[string]$fallback.id] = $fallback
    }
    $licenseRefMap = @{}
    foreach ($mapping in $fallbacks.licenseRefMappings) {
        if ($licenseRefMap.ContainsKey([string]$mapping.id)) { throw "deno_fallback_duplicate:$($mapping.id)" }
        $licenseRefMap[[string]$mapping.id] = $mapping
    }
    $workspaceFallbackMap = @{}
    foreach ($fallback in $fallbacks.workspaceFallbacks) {
        if ($workspaceFallbackMap.ContainsKey([string]$fallback.id)) { throw "deno_fallback_duplicate:$($fallback.id)" }
        $workspaceFallbackMap[[string]$fallback.id] = $fallback
    }
    $unresolvedMap = @{}
    foreach ($unresolved in $fallbacks.unresolved) { $unresolvedMap[[string]$unresolved.id] = $unresolved }

    $official = Read-DenoJson $OfficialMetadataPath
    $superset = Read-DenoJson $SupersetMetadataPath
    $officialIds = @(Get-DenoMetadataPackageIds $official)
    $supersetIds = @(Get-DenoMetadataPackageIds $superset)
    Assert-DenoTargetClosure -OfficialPackageIds $officialIds -SupersetPackageIds $supersetIds | Out-Null
    $officialSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($packageId in $officialIds) { [void]$officialSet.Add($packageId) }
    $supersetSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($packageId in $supersetIds) { [void]$supersetSet.Add($packageId) }

    $lockPackages = @(Read-DenoCargoLockPackages -CargoLockPath (Join-Path $DenoSourceRoot 'Cargo.lock') -ExpectedSha256 ([string]$cargoLockPins[0].sha256))
    $registryPackages = @($lockPackages | Where-Object { $_.source -like 'registry+*' })
    $workspacePackages = @($superset.packages | Where-Object { $null -eq $_.source })
    $vendorMap = @{}
    foreach ($directory in Get-ChildItem -LiteralPath $VendorRoot -Directory) {
        $toml = [IO.File]::ReadAllText((Join-Path $directory.FullName 'Cargo.toml'))
        $name = [regex]::Match($toml, '(?m)^name\s*=\s*"([^"]+)"').Groups[1].Value
        $version = [regex]::Match($toml, '(?m)^version\s*=\s*"([^"]+)"').Groups[1].Value
        $key = $name + "`0" + $version
        if ($vendorMap.ContainsKey($key)) { throw "deno_vendor_duplicate:$name@$version" }
        $vendorMap[$key] = $directory.FullName
    }
    if ($vendorMap.Count -ne $registryPackages.Count) { throw 'deno_vendor_lock_count_mismatch' }
    if (@(Get-ChildItem -LiteralPath $CrateArchiveRoot -Filter '*.crate' -File).Count -ne $registryPackages.Count) { throw 'deno_crate_archive_lock_count_mismatch' }

    if ([string]$native.rustyV8Commit -cne [string]$inputs.releaseIdentity.rustyV8Commit) { throw 'deno_native_rusty_v8_commit_mismatch' }
    $nativeTreeEvidence = Assert-DenoNativeClosure -Components @($native.components) -RustyV8GitRepositoryPath $RustyV8GitRepositoryPath -ExpectedCommit ([string]$native.rustyV8Commit) -ExpectedTree ([string]$native.rustyV8Tree)
    $nativeLicenseMap = @{}
    foreach ($component in $native.components | Where-Object { $_.path -ne 'v8' }) {
        $archive = Join-Path $NativeSourceRoot ([string]$component.archiveFile)
        $entries = @(Get-DenoTarArchiveEntries -ArchivePath $archive -ExpectedSha256 ([string]$component.sha256) -ExpectedLength ([long]$component.length))
        $licenses = @($entries | Where-Object { (Split-Path $_ -Leaf) -match '^(?i:LICENSE|LICENCE|COPYING|NOTICE|PATENTS|COPYRIGHT)(?:[._-].*)?$' })
        if ($component.licenseRequired -and $licenses.Count -eq 0) { throw "deno_native_license_file_missing:$($component.path)" }
        $nativeLicenseMap[[string]$component.path] = @($licenses | Sort-Object -Unique)
    }

    $blockers = [Collections.Generic.List[string]]::new()
    $crateRecords = [Collections.Generic.List[object]]::new()
    foreach ($package in $registryPackages | Sort-Object name, version) {
        $id = $package.name + '@' + $package.version
        $key = $package.name + "`0" + $package.version
        if (-not $vendorMap.ContainsKey($key)) { $blockers.Add("deno_vendor_package_missing:$id"); continue }
        $crateArchive = Join-Path $CrateArchiveRoot ($package.name + '-' + $package.version + '.crate')
        if (-not (Test-Path -LiteralPath $crateArchive -PathType Leaf)) { $blockers.Add("deno_crate_archive_missing:$id"); continue }
        try {
            $fallback = if ($registryFallbackMap.ContainsKey($id)) { $registryFallbackMap[$id] } else { $null }
            $licenseRefMapping = if ($licenseRefMap.ContainsKey($id)) { $licenseRefMap[$id] } else { $null }
            $record = Assert-DenoCratePackage -Package $package -VendorPath $vendorMap[$key] -CrateArchivePath $crateArchive -SpdxRoot $SpdxRoot -LicenseRefMapping $licenseRefMapping -UpstreamFallback $fallback -UpstreamSourceRoot $UpstreamSourceRoot
            $reason = if ($officialSet.Contains($id)) { 'official-workflow-profile' } elseif ($supersetSet.Contains($id)) { 'all-features-conservative-superset' } else { 'cargo-lock-conservative-superset' }
            $crateRecords.Add([ordered]@{ name = $package.name; version = $package.version; source = $package.source; sourceArchive = [ordered]@{ fileName = (Split-Path $crateArchive -Leaf); length = (Get-DenoFileLength $crateArchive); sha256 = $package.checksum; url = "https://static.crates.io/crates/$($package.name)/$($package.name)-$($package.version).crate" }; checksum = $package.checksum; crateManifest = $record.crateManifest; license = $record.license; licenseFile = $record.licenseFile; repository = $record.repository; resolution = $record.resolution; resolvedLicenseFiles = $record.resolvedLicenseFiles; spdxLicenseIds = $record.spdxLicenseIds; spdxExceptionIds = $record.spdxExceptionIds; licenseRefId = $record.licenseRefId; extractedTextSha256 = $record.extractedTextSha256; licenseComments = $record.licenseComments; canonicalTexts = $record.canonicalTexts; provenance = $record.provenance; inclusionReason = $reason })
        }
        catch {
            if ($unresolvedMap.ContainsKey($id)) { $blockers.Add("deno_upstream_license_unresolved:$id") }
            else { $blockers.Add($_.Exception.Message) }
        }
    }
    $workspaceRecords = [Collections.Generic.List[object]]::new()
    foreach ($package in $workspacePackages | Sort-Object name, version) {
        $id = ([string]$package.name) + '@' + ([string]$package.version)
        $manifestPath = [IO.Path]::GetFullPath([string]$package.manifest_path)
        $denoRoot = [IO.Path]::GetFullPath($DenoSourceRoot).TrimEnd('\') + '\'
        if (-not $manifestPath.StartsWith($denoRoot, [StringComparison]::OrdinalIgnoreCase)) { $blockers.Add("deno_workspace_manifest_outside_source:$id"); continue }
        $relativeManifest = $manifestPath.Substring($denoRoot.Length).Replace('\', '/')
        try {
            $license = [string]$package.license
            $resolution = $null
            $resolvedFiles = @()
            $spdxLicenseIds = @()
            $spdxExceptionIds = @()
            $provenance = $null
            if (-not [string]::IsNullOrWhiteSpace($license)) {
                $spdx = Resolve-DenoSpdxExpression -Expression $license -SpdxRoot $SpdxRoot
                $resolution = 'spdx-canonical-fallback'
                $resolvedFiles = @($spdx.files)
                $spdxLicenseIds = @($spdx.licenseIds)
                $spdxExceptionIds = @($spdx.exceptionIds)
                $provenance = [ordered]@{ spdxVersion = $spdx.version }
            }
            elseif ($workspaceFallbackMap.ContainsKey($id)) {
                $fallback = $workspaceFallbackMap[$id]
                $resolvedFiles = @($fallback.evidenceFiles | ForEach-Object {
                    $path = Join-Path $DenoSourceRoot ([string]$_.path)
                    Assert-DenoHash $path ([string]$_.sha256)
                    [ordered]@{ origin = 'pinned-workspace-source'; path = [string]$_.path; length = [long]$_.length; sha256 = [string]$_.sha256 }
                })
                $resolution = 'pinned-workspace-upstream-license'
                $license = [string]$fallback.resolvedLicense
                $provenance = $fallback
            }
            else { throw "deno_workspace_license_ambiguous:$id" }
            $reason = if ($officialSet.Contains($id)) { 'official-workflow-profile' } else { 'all-features-conservative-superset' }
            $workspaceRecords.Add([ordered]@{ name = [string]$package.name; version = [string]$package.version; source = "https://github.com/denoland/deno/tree/$($inputs.releaseIdentity.denoSourceCommit)/$($relativeManifest.Substring(0, $relativeManifest.LastIndexOf('/')))"; sourceManifest = [ordered]@{ path = $relativeManifest; length = (Get-DenoFileLength $manifestPath); sha256 = Get-DenoSha256 $manifestPath }; license = $license; licenseFile = [string]$package.license_file; repository = [string]$package.repository; resolution = $resolution; resolvedLicenseFiles = $resolvedFiles; spdxLicenseIds = $spdxLicenseIds; spdxExceptionIds = $spdxExceptionIds; provenance = $provenance; inclusionReason = $reason })
        }
        catch { $blockers.Add($_.Exception.Message) }
    }

    $counts = [ordered]@{
        cargoLockPackages = $lockPackages.Count
        registryPackages = $registryPackages.Count
        resolvedRegistryPackages = $crateRecords.Count
        registryPackageFileResolutions = @($crateRecords | Where-Object resolution -ceq 'package-files').Count
        registrySpdxResolutions = @($crateRecords | Where-Object resolution -ceq 'spdx-canonical-fallback').Count
        registryLicenseRefResolutions = @($crateRecords | Where-Object resolution -ceq 'spdx-license-ref').Count
        registryUpstreamResolutions = @($crateRecords | Where-Object resolution -ceq 'upstream-commit-license-files').Count
        workspacePackages = $workspacePackages.Count
        resolvedWorkspacePackages = $workspaceRecords.Count
        workspaceSpdxResolutions = @($workspaceRecords | Where-Object resolution -ceq 'spdx-canonical-fallback').Count
        workspaceUpstreamResolutions = @($workspaceRecords | Where-Object resolution -ceq 'pinned-workspace-upstream-license').Count
        nativeComponents = @($native.components).Count
        embeddedComponents = @($inputs.embeddedComponents).Count
    }
    if ($blockers.Count -gt 0) {
        $reportPath = Write-DenoBlockerReport -ScratchRoot $ScratchRoot -Identity $identity -Blockers @($blockers) -Counts $counts -UnresolvedEvidence @($fallbacks.unresolved)
        throw "deno_collection_blocked:$($blockers.Count):$reportPath"
    }

    $workRoot = New-DenoProcessStageRoot -ScratchRoot $ScratchRoot
    try {
        $outputRoot = Join-Path $workRoot 'deno-third-party-output'
        $stage = Join-Path $outputRoot 'bundle'
        $licenseRoot = Join-Path $stage 'LICENSES/cargo'
        $workspaceLicenseRoot = Join-Path $stage 'LICENSES/workspace'
        $nativeLicenseRoot = Join-Path $stage 'LICENSES/native'
        $sourceRoot = Join-Path $stage 'SOURCES'
        New-Item -ItemType Directory -Path $licenseRoot, $workspaceLicenseRoot, $nativeLicenseRoot, $sourceRoot | Out-Null
        $notice = [Text.StringBuilder]::new((Read-DenoUtf8Text -Path (Join-Path $ManifestRoot 'THIRD-PARTY-NOTICES.template.txt')))
        $notice.Append("`n") | Out-Null
        $outputPaths = [Collections.Generic.List[string]]::new()
        $embeddedRecords = [Collections.Generic.List[object]]::new()
        foreach ($component in $inputs.embeddedComponents | Sort-Object id) {
            $embeddedRecords.Add((Add-DenoEmbeddedComponent -Component $component -DenoSourceRoot $DenoSourceRoot -DenoSourceArchivePath $DenoSourceArchivePath -SpdxRoot $SpdxRoot -StageRoot $stage -Notice $notice -OutputPaths $outputPaths))
        }
        foreach ($record in $crateRecords) {
            $safeId = ($record.name + '-' + $record.version) -replace '[^A-Za-z0-9._+-]', '_'
            $notice.AppendLine("=== $($record.name) $($record.version) ===").AppendLine("Source: $($record.sourceArchive.url)").AppendLine("Checksum: $($record.checksum)").AppendLine("Manifest: $($record.crateManifest.path) $($record.crateManifest.sha256)").AppendLine("Repository: $($record.repository)").AppendLine("Author declaration: $($record.license)").AppendLine("Resolved identifier: $(if ($record.licenseRefId) { $record.licenseRefId } else { $record.license })").AppendLine("License comments: $($record.licenseComments)").AppendLine("Resolution: $($record.resolution)").AppendLine("Inclusion: $($record.inclusionReason)") | Out-Null
            foreach ($license in $record.resolvedLicenseFiles) {
                $destinationRelative = "LICENSES/cargo/$safeId/$($license.origin)/$($license.path)"
                $destination = Join-Path $stage $destinationRelative
                [byte[]]$licenseBytes = switch ([string]$license.origin) {
                    'package-archive' { Get-DenoTarEntryBytes -ArchivePath (Join-Path $CrateArchiveRoot ([string]$record.sourceArchive.fileName)) -EntryPath ([string]$license.archiveEntry) }
                    'spdx-license' { (Get-DenoVerifiedByteMaterial -Path (Join-Path $SpdxRoot ([string]$license.path)) -ExpectedSha256 ([string]$license.sha256) -ExpectedLength ([long]$license.length) -Cache).bytes }
                    'spdx-exception' { (Get-DenoVerifiedByteMaterial -Path (Join-Path $SpdxRoot ([string]$license.path)) -ExpectedSha256 ([string]$license.sha256) -ExpectedLength ([long]$license.length) -Cache).bytes }
                    'upstream-commit' { Get-DenoZipEntryBytes -ArchivePath (Join-Path $UpstreamSourceRoot ([string]$license.archiveFile)) -EntryPath ([string]$license.path) }
                    'license-ref-extracted' { [Text.UTF8Encoding]::new($false).GetBytes([string]$license.text) }
                    default { throw "deno_license_origin_invalid:$($license.origin)" }
                }
                [void](Add-DenoLicenseMaterial -Bytes $licenseBytes -DestinationPath $destination -DestinationRelative $destinationRelative -Notice $notice -ExpectedSha256 ([string]$license.sha256) -ExpectedLength ([long]$license.length))
                $outputPaths.Add($destinationRelative)
            }
        }
        foreach ($record in $workspaceRecords) {
            $safeId = ($record.name + '-' + $record.version) -replace '[^A-Za-z0-9._+-]', '_'
            $notice.AppendLine("=== workspace $($record.name) $($record.version) ===").AppendLine("Source: $($record.source)").AppendLine("Manifest: $($record.sourceManifest.path)").AppendLine("License: $($record.license)").AppendLine("Resolution: $($record.resolution)").AppendLine("Inclusion: $($record.inclusionReason)") | Out-Null
            foreach ($license in $record.resolvedLicenseFiles) {
                $destinationRelative = "LICENSES/workspace/$safeId/$($license.origin)/$($license.path)"
                $destination = Join-Path $stage $destinationRelative
                if ([string]$license.origin -in @('spdx-license', 'spdx-exception')) { $licenseSource = Join-Path $SpdxRoot ([string]$license.path) }
                elseif ([string]$license.origin -ceq 'pinned-workspace-source') { $licenseSource = Join-Path $DenoSourceRoot ([string]$license.path) }
                else { throw "deno_license_origin_invalid:$($license.origin)" }
                [void](Add-DenoVerifiedLicenseMaterial -SourcePath $licenseSource -DestinationPath $destination -DestinationRelative $destinationRelative -Notice $notice -ExpectedSha256 ([string]$license.sha256) -ExpectedLength ([long]$license.length))
                $outputPaths.Add($destinationRelative)
            }
        }
        foreach ($rootLicense in @(Get-DenoLicenseFiles -Root $RustyV8SourceRoot)) {
            $relative = $rootLicense.FullName.Substring([IO.Path]::GetFullPath($RustyV8SourceRoot).TrimEnd('\').Length + 1).Replace('\', '/')
            $destinationRelative = "LICENSES/native/rusty_v8/$relative"
            $destination = Join-Path $stage $destinationRelative
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            $licenseMaterial = Get-DenoVerifiedByteMaterial -Path $rootLicense.FullName -Cache
            Write-DenoBytes -Path $destination -Bytes $licenseMaterial.bytes
            $outputPaths.Add($destinationRelative)
        }
        foreach ($v8License in @(Get-DenoLicenseFiles -Root $V8SourceRoot)) {
            $relative = $v8License.FullName.Substring([IO.Path]::GetFullPath($V8SourceRoot).TrimEnd('\').Length + 1).Replace('\', '/')
            $destinationRelative = "LICENSES/native/v8/$relative"
            $destination = Join-Path $stage $destinationRelative
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            $licenseMaterial = Get-DenoVerifiedByteMaterial -Path $v8License.FullName -Cache
            Write-DenoBytes -Path $destination -Bytes $licenseMaterial.bytes
            $outputPaths.Add($destinationRelative)
        }
        foreach ($component in $native.components | Where-Object { $_.path -ne 'v8' }) {
            $safeComponent = ([string]$component.path) -replace '[^A-Za-z0-9._+-]', '_'
            foreach ($entry in @($nativeLicenseMap[[string]$component.path])) {
                $destinationRelative = "LICENSES/native/$safeComponent/$entry"
                $destination = Join-Path $stage $destinationRelative
                [byte[]]$licenseBytes = Get-DenoTarEntryBytes -ArchivePath (Join-Path $NativeSourceRoot ([string]$component.archiveFile)) -EntryPath $entry
                New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
                Write-DenoBytes -Path $destination -Bytes $licenseBytes
                $outputPaths.Add($destinationRelative)
            }
        }
        Assert-DenoUniquePaths @($outputPaths) | Out-Null
        foreach ($artifact in $inputs.sourceArtifacts) {
            $source = [string]$artifactPaths[[string]$artifact.id]
            Copy-DenoVerifiedFile -SourcePath $source -DestinationPath (Join-Path $sourceRoot ([string]$artifact.fileName)) -ExpectedSha256 ([string]$artifact.sha256) -ExpectedLength ([long]$artifact.length)
        }
        foreach ($component in $native.components | Where-Object { $_.path -ne 'v8' }) {
            Copy-DenoVerifiedFile -SourcePath (Join-Path $NativeSourceRoot ([string]$component.archiveFile)) -DestinationPath (Join-Path $sourceRoot ([string]$component.archiveFile)) -ExpectedSha256 ([string]$component.sha256) -ExpectedLength ([long]$component.length)
        }
        $crateSourceRoot = Join-Path $sourceRoot 'cargo-crates'
        $upstreamSourceDestination = Join-Path $sourceRoot 'upstream-license-sources'
        New-Item -ItemType Directory -Path $crateSourceRoot, $upstreamSourceDestination | Out-Null
        foreach ($record in $crateRecords) { Copy-DenoVerifiedFile -SourcePath (Join-Path $CrateArchiveRoot ([string]$record.sourceArchive.fileName)) -DestinationPath (Join-Path $crateSourceRoot ([string]$record.sourceArchive.fileName)) -ExpectedSha256 ([string]$record.sourceArchive.sha256) -ExpectedLength ([long]$record.sourceArchive.length) }
        foreach ($archiveFile in @($fallbacks.registryFallbacks.archiveFile | Sort-Object -Unique)) { Copy-DenoVerifiedFile -SourcePath (Join-Path $UpstreamSourceRoot $archiveFile) -DestinationPath (Join-Path $upstreamSourceDestination $archiveFile) }
        $noticePath = Join-Path $outputRoot 'THIRD-PARTY-NOTICES.txt'
        Write-DenoUtf8Text $noticePath ($notice.ToString())
        Copy-DenoVerifiedFile -SourcePath $noticePath -DestinationPath (Join-Path $stage 'THIRD-PARTY-NOTICES.txt')
        Write-DenoUtf8Text (Join-Path $outputRoot 'component-manifest.json') (([ordered]@{ schemaVersion = 'deno-third-party-components/v3'; closureClassification = $inputs.closureClassification; releaseIdentity = $identity; spdxLicenseList = $inputs.spdxLicenseList; counts = $counts; embeddedComponents = @($embeddedRecords); crates = @($crateRecords); workspacePackages = @($workspaceRecords); nativeGitTreeEvidence = $nativeTreeEvidence; nativeComponents = @($native.components); overallReleasePass = $false } | ConvertTo-Json -Depth 30) + "`n")
        $inventory = foreach ($file in Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName) { [ordered]@{ path = $file.FullName.Substring($stage.Length + 1).Replace('\', '/'); length = $file.Length; sha256 = Get-DenoSha256 $file.FullName } }
        Write-DenoUtf8Text (Join-Path $outputRoot 'source-inventory.json') (([ordered]@{ schemaVersion = 'deno-source-inventory/v1'; files = @($inventory) } | ConvertTo-Json -Depth 10) + "`n")
        $zipPath = Join-Path $outputRoot 'deno-2.7.14-verified-conservative-superset-sources.zip'
        $zipSha256 = New-DenoDeterministicZip -SourceRoot $stage -ZipPath $zipPath
        Complete-DenoAtomicDirectory -Source $outputRoot -Destination $finalOutputRoot | Out-Null
        $noticePath = Join-Path $finalOutputRoot 'THIRD-PARTY-NOTICES.txt'
        $zipPath = Join-Path $finalOutputRoot 'deno-2.7.14-verified-conservative-superset-sources.zip'
        return [pscustomobject]@{ status = 'complete'; closureClassification = $inputs.closureClassification; outputRoot = $finalOutputRoot; noticePath = $noticePath; noticeSha256 = Get-DenoSha256 $noticePath; zipPath = $zipPath; zipSha256 = Get-DenoSha256 $zipPath; counts = $counts; overallReleasePass = $false }
    }
    finally {
        $ownedKey = (ConvertTo-DenoFinalPath $workRoot).ToLowerInvariant()
        if ($script:DenoOwnedStages.ContainsKey($ownedKey)) {
            [void](Remove-DenoProcessStageRoot -Path $workRoot)
        }
    }
    }
    finally {
        for ($index = $mainGuards.Count - 1; $index -ge 0; $index--) {
            Close-DenoPathChain $mainGuards[$index]
        }
    }
}

if ($Run) {
    $required = @($DenoSourceRoot, $RustyV8SourceRoot, $RustyV8GitRepositoryPath, $V8SourceRoot, $VendorRoot, $OfficialMetadataPath,
        $SupersetMetadataPath, $DenoExePath, $DenoSourceArchivePath, $RustyV8SourceArchivePath,
        $V8SourceArchivePath, $RustyV8StaticLibArchivePath, $NativeSourceRoot, $CrateArchiveRoot,
        $SpdxRoot, $SpdxArchivePath, $UpstreamSourceRoot, $UpstreamFallbackManifest, $ScratchRoot)
    if (@($required | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { throw 'deno_run_parameters_required' }
    Invoke-DenoThirdPartyNoticeCollection -ManifestRoot $ManifestRoot -DenoSourceRoot $DenoSourceRoot `
        -RustyV8SourceRoot $RustyV8SourceRoot -RustyV8GitRepositoryPath $RustyV8GitRepositoryPath `
        -V8SourceRoot $V8SourceRoot -VendorRoot $VendorRoot `
        -OfficialMetadataPath $OfficialMetadataPath -SupersetMetadataPath $SupersetMetadataPath `
        -DenoExePath $DenoExePath -DenoSourceArchivePath $DenoSourceArchivePath `
        -RustyV8SourceArchivePath $RustyV8SourceArchivePath -V8SourceArchivePath $V8SourceArchivePath `
        -RustyV8StaticLibArchivePath $RustyV8StaticLibArchivePath -NativeSourceRoot $NativeSourceRoot `
        -CrateArchiveRoot $CrateArchiveRoot -SpdxRoot $SpdxRoot -SpdxArchivePath $SpdxArchivePath `
        -UpstreamSourceRoot $UpstreamSourceRoot -UpstreamFallbackManifest $UpstreamFallbackManifest `
        -ScratchRoot $ScratchRoot
}
