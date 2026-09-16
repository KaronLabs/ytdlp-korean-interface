[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [long]$ExpectedLength,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedSha256,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedInputName = '7z2601-x64-no-rar-source.7z'
$entryPath = 'sevenzip/7z2601-x64-no-rar-source.7z'
$fixedTimestamp = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)

function Assert-LexicalAbsolutePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ErrorCode
    )

    if (-not [IO.Path]::IsPathFullyQualified($Path)) {
        throw $ErrorCode
    }

    $segments = $Path -split '[\\/]'
    if (@($segments | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count -ne 0) {
        throw $ErrorCode
    }
}

function Assert-NoReparseAlias {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ErrorCode
    )

    $cursor = $Path
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw $ErrorCode
            }
        }

        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) {
            break
        }
        $cursor = $parent
    }
}

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return [Convert]::ToHexString($sha256.ComputeHash($Bytes)).ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

Assert-LexicalAbsolutePath -Path $InputPath -ErrorCode 'sevenzip_wrapper_path_invalid'
Assert-LexicalAbsolutePath -Path $OutputPath -ErrorCode 'sevenzip_wrapper_path_invalid'

$inputFull = [IO.Path]::GetFullPath($InputPath)
$outputFull = [IO.Path]::GetFullPath($OutputPath)
$comparison = [StringComparison]::OrdinalIgnoreCase

if (-not [IO.Path]::GetFileName($inputFull).Equals($expectedInputName, $comparison)) {
    throw 'sevenzip_wrapper_raw_identity_mismatch'
}
if ($inputFull.Equals($outputFull, $comparison) -or $outputFull.StartsWith($inputFull + [IO.Path]::DirectorySeparatorChar, $comparison)) {
    throw 'sevenzip_wrapper_path_alias'
}
if (-not [IO.Path]::GetExtension($outputFull).Equals('.zip', $comparison)) {
    throw 'sevenzip_wrapper_path_invalid'
}
if (-not (Test-Path -LiteralPath $inputFull -PathType Leaf)) {
    throw 'sevenzip_wrapper_input_missing'
}
if (Test-Path -LiteralPath $outputFull) {
    throw 'sevenzip_wrapper_output_exists'
}

Assert-NoReparseAlias -Path $inputFull -ErrorCode 'sevenzip_wrapper_input_alias'
$outputParent = [IO.Path]::GetDirectoryName($outputFull)
if ([string]::IsNullOrWhiteSpace($outputParent)) {
    throw 'sevenzip_wrapper_output_path_invalid'
}
Assert-NoReparseAlias -Path $outputParent -ErrorCode 'sevenzip_wrapper_output_alias'

$rawBytes = [IO.File]::ReadAllBytes($inputFull)
$rawLength = [long]$rawBytes.LongLength
$rawSha256 = Get-Sha256Hex -Bytes $rawBytes
if ($rawLength -ne $ExpectedLength -or $rawSha256 -cne $ExpectedSha256.ToLowerInvariant()) {
    throw 'sevenzip_wrapper_raw_identity_mismatch'
}

$zipBuffer = [IO.MemoryStream]::new()
try {
    $archive = [IO.Compression.ZipArchive]::new(
        $zipBuffer,
        [IO.Compression.ZipArchiveMode]::Create,
        $true,
        [Text.Encoding]::UTF8
    )
    try {
        $entry = $archive.CreateEntry($entryPath, [IO.Compression.CompressionLevel]::NoCompression)
        $entry.LastWriteTime = $fixedTimestamp
        $entryStream = $entry.Open()
        try {
            $entryStream.Write($rawBytes, 0, $rawBytes.Length)
        }
        finally {
            $entryStream.Dispose()
        }
    }
    finally {
        $archive.Dispose()
    }

    $zipBytes = $zipBuffer.ToArray()
}
finally {
    $zipBuffer.Dispose()
}

$outerLength = [long]$zipBytes.LongLength
$outerSha256 = Get-Sha256Hex -Bytes $zipBytes

[IO.Directory]::CreateDirectory($outputParent) | Out-Null
$temporaryPath = Join-Path $outputParent ('.{0}.partial.{1}' -f [IO.Path]::GetFileName($outputFull), [Guid]::NewGuid().ToString('N'))
try {
    [IO.File]::WriteAllBytes($temporaryPath, $zipBytes)
    [IO.File]::Move($temporaryPath, $outputFull)
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}

[pscustomobject][ordered]@{
    schemaVersion = 'karon-sevenzip-source-wrapper/v1'
    entryPath = $entryPath
    inner = [pscustomobject][ordered]@{
        length = $rawLength
        sha256 = $rawSha256
    }
    outer = [pscustomobject][ordered]@{
        fileName = [IO.Path]::GetFileName($outputFull)
        length = $outerLength
        sha256 = $outerSha256
    }
}
