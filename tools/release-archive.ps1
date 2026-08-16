[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$factoryPath = Join-Path $PSScriptRoot 'release-factory.ps1'
if (-not (Test-Path -LiteralPath $factoryPath -PathType Leaf)) { throw 'release_factory_missing' }
. $factoryPath

function Initialize-ReleaseZipAssemblies {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
}

function New-ReleaseZip {
    param(
        [Parameter(Mandatory = $true)] [string] $PackageRoot,
        [Parameter(Mandatory = $true)] [string] $OutputDirectory
    )
    $config = Get-FirstReleaseConfiguration
    $package = [IO.Path]::GetFullPath($PackageRoot)
    if (-not (Test-Path -LiteralPath $package -PathType Container) -or (Split-Path -Leaf $package) -cne $config.PackageName) { throw 'release_package_invalid' }
    foreach ($item in @(Get-ChildItem -LiteralPath $package -Recurse -Force)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'release_zip_invalid' }
    }
    $output = [IO.Path]::GetFullPath($OutputDirectory)
    [IO.Directory]::CreateDirectory($output) | Out-Null
    $zip = Join-Path $output $config.ZipName
    if (Test-Path -LiteralPath $zip) { throw 'release_zip_exists' }
    Initialize-ReleaseZipAssemblies
    [IO.Compression.ZipFile]::CreateFromDirectory($package, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
    if (-not (Test-Path -LiteralPath $zip -PathType Leaf) -or (Get-Item -LiteralPath $zip).Length -le 0) { throw 'release_zip_invalid' }
    Test-ReleaseZip -ZipPath $zip -PackageRoot $package | Out-Null
    return $zip
}

function Test-ReleaseZip {
    param(
        [Parameter(Mandatory = $true)] [string] $ZipPath,
        [Parameter(Mandatory = $true)] [string] $PackageRoot
    )
    $config = Get-FirstReleaseConfiguration
    $zip = [IO.Path]::GetFullPath($ZipPath)
    $package = [IO.Path]::GetFullPath($PackageRoot)
    if (-not (Test-Path -LiteralPath $zip -PathType Leaf) -or (Split-Path -Leaf $zip) -cne $config.ZipName) { throw 'release_zip_invalid' }
    if (-not (Test-Path -LiteralPath $package -PathType Container) -or (Split-Path -Leaf $package) -cne $config.PackageName) { throw 'release_package_invalid' }
    Initialize-ReleaseZipAssemblies

    $expected = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $package -Recurse -File -Force)) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'release_zip_invalid' }
        $relative = $file.FullName.Substring($package.Length).TrimStart('\','/').Replace('\','/')
        if (-not (Test-SafeReleaseRelativePath -Path $relative)) { throw 'release_zip_invalid' }
        $entryName = $config.PackageName + '/' + $relative
        $expected[$entryName] = [pscustomobject]@{
            Length = [long]$file.Length
            Sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    if ($expected.Count -eq 0) { throw 'release_zip_invalid' }

    $stream = [IO.File]::Open($zip, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            $seen = @{}
            foreach ($entry in $archive.Entries) {
                $name = ([string]$entry.FullName).Replace('\','/')
                if ([string]::IsNullOrWhiteSpace($name)) { throw 'release_zip_invalid' }
                if ($name.EndsWith('/')) { continue }
                if ($name.StartsWith('/') -or $name.Contains("`0") -or $name -notmatch ('^' + [regex]::Escape($config.PackageName) + '/')) { throw 'release_zip_invalid' }
                $relative = $name.Substring($config.PackageName.Length + 1)
                if (-not (Test-SafeReleaseRelativePath -Path $relative)) { throw 'release_zip_invalid' }
                if ($seen.ContainsKey($name) -or -not $expected.ContainsKey($name)) { throw 'release_zip_invalid' }
                $seen[$name] = $true
                $record = $expected[$name]
                if ([long]$entry.Length -ne [long]$record.Length) { throw 'release_zip_invalid' }
                $entryStream = $entry.Open()
                try {
                    $hasher = [Security.Cryptography.SHA256]::Create()
                    try { $hash = (($hasher.ComputeHash($entryStream) | ForEach-Object { $_.ToString('x2') }) -join '') }
                    finally { $hasher.Dispose() }
                }
                finally { $entryStream.Dispose() }
                if ($hash -cne [string]$record.Sha256) { throw 'release_zip_invalid' }
            }
            if ($seen.Count -ne $expected.Count) { throw 'release_zip_invalid' }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
    return $true
}

if ($MyInvocation.InvocationName -ne '.') {
    Write-Output 'Release archive library loaded. No archive action is performed without an explicit caller.'
}
