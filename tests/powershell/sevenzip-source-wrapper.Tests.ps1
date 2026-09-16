$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:WrapperTool = Join-Path $script:RepositoryRoot 'tools\build-sevenzip-source-wrapper.ps1'
$script:EntryPath = 'sevenzip/7z2601-x64-no-rar-source.7z'
$script:Utf8 = New-Object Text.UTF8Encoding($false)

function Get-WrapperTestSha256 {
    param([string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-WrapperTestFixture {
    param([string] $Name)
    $root = Join-Path $TestDrive $Name
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $raw = Join-Path $root '7z2601-x64-no-rar-source.7z'
    [IO.File]::WriteAllBytes($raw, $script:Utf8.GetBytes(('no-rar-source-' + ('x' * 4096))))
    [pscustomobject]@{
        Root = $root
        Raw = $raw
        Length = [long](Get-Item -LiteralPath $raw).Length
        Sha256 = Get-WrapperTestSha256 $raw
        Output = Join-Path $root '7z2601-x64-no-rar-source.zip'
    }
}

function Invoke-WrapperTool {
    param([object] $Fixture, [string] $OutputPath = '', [object] $ExpectedLength = $null, [string] $ExpectedSha256 = '')
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = $Fixture.Output }
    if ($null -eq $ExpectedLength) { $ExpectedLength = $Fixture.Length }
    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) { $ExpectedSha256 = $Fixture.Sha256 }
    & $script:WrapperTool -InputPath $Fixture.Raw -ExpectedLength $ExpectedLength -ExpectedSha256 $ExpectedSha256 -OutputPath $OutputPath
}

function Assert-WrapperRejected {
    param([object] $Fixture, [string] $Pattern, [string] $OutputPath = '')
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = $Fixture.Output }
    $caught = $null
    try { Invoke-WrapperTool $Fixture $OutputPath | Out-Null }
    catch { $caught = $_ }
    $caught | Should Not BeNullOrEmpty
    $caught.Exception.Message | Should Match $Pattern
    if ([IO.Path]::GetFullPath($OutputPath) -ine [IO.Path]::GetFullPath($Fixture.Raw)) {
        (Test-Path -LiteralPath $OutputPath) | Should Be $false
    }
    @(Get-ChildItem -LiteralPath (Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))) -Filter '.*.partial.*' -ErrorAction SilentlyContinue).Count | Should Be 0
}

Describe 'deterministic 7z no-RAR source ZIP wrapper' {
    It 'uses one exact immutable snapshot and emits deterministic stored ZIP bytes' {
        $fixture = New-WrapperTestFixture 'happy'
        $second = Join-Path $fixture.Root 'second.zip'
        $firstResult = Invoke-WrapperTool $fixture
        $secondResult = Invoke-WrapperTool $fixture $second

        $firstResult.schemaVersion | Should Be 'karon-sevenzip-source-wrapper/v1'
        $firstResult.entryPath | Should Be $script:EntryPath
        $firstResult.inner.length | Should Be $fixture.Length
        $firstResult.inner.sha256 | Should Be $fixture.Sha256
        $firstResult.outer.length | Should Be ([long](Get-Item $fixture.Output).Length)
        $firstResult.outer.sha256 | Should Be (Get-WrapperTestSha256 $fixture.Output)
        $secondResult.outer.length | Should Be $firstResult.outer.length
        $secondResult.outer.sha256 | Should Be $firstResult.outer.sha256

        $archive = [IO.Compression.ZipFile]::OpenRead($fixture.Output)
        try {
            @($archive.Entries).Count | Should Be 1
            $entry = $archive.Entries[0]
            $entry.FullName | Should Be $script:EntryPath
            $entry.Length | Should Be $fixture.Length
            $entry.CompressedLength | Should Be $fixture.Length
            $entry.LastWriteTime.DateTime | Should Be ([DateTime]::new(1980, 1, 1, 0, 0, 0))
            $stream = $entry.Open()
            $memory = New-Object IO.MemoryStream
            try { $stream.CopyTo($memory) }
            finally { $stream.Dispose() }
            try { [Convert]::ToBase64String($memory.ToArray()) | Should Be ([Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture.Raw))) }
            finally { $memory.Dispose() }
        }
        finally { $archive.Dispose() }
    }

    It 'rejects invalid raw length or SHA without a final or partial output' {
        $fixture = New-WrapperTestFixture 'bad-length'
        $caught = $null
        try { Invoke-WrapperTool $fixture '' ($fixture.Length + 1) $fixture.Sha256 | Out-Null } catch { $caught = $_ }
        $caught.Exception.Message | Should Match 'sevenzip_wrapper_raw_identity_mismatch'
        (Test-Path $fixture.Output) | Should Be $false

        $fixture = New-WrapperTestFixture 'bad-sha'
        $caught = $null
        try { Invoke-WrapperTool $fixture '' $fixture.Length ('0' * 64) | Out-Null } catch { $caught = $_ }
        $caught.Exception.Message | Should Match 'sevenzip_wrapper_raw_identity_mismatch'
        (Test-Path $fixture.Output) | Should Be $false
        @(Get-ChildItem -LiteralPath $fixture.Root -Filter '.*.partial.*').Count | Should Be 0
    }

    It 'preserves a preexisting output byte-for-byte' {
        $fixture = New-WrapperTestFixture 'preexisting'
        [IO.File]::WriteAllText($fixture.Output, 'owner bytes', $script:Utf8)
        $before = Get-WrapperTestSha256 $fixture.Output
        $caught = $null
        try { Invoke-WrapperTool $fixture | Out-Null } catch { $caught = $_ }
        $caught.Exception.Message | Should Match 'sevenzip_wrapper_output_exists'
        (Get-WrapperTestSha256 $fixture.Output) | Should Be $before
        @(Get-ChildItem -LiteralPath $fixture.Root -Filter '.*.partial.*').Count | Should Be 0
    }

    It 'rejects traversal and input-output aliases' {
        $fixture = New-WrapperTestFixture 'paths'
        $child = Join-Path $fixture.Root 'child'
        [IO.Directory]::CreateDirectory($child) | Out-Null
        $fixture.Raw = Join-Path $child '..\7z2601-x64-no-rar-source.7z'
        Assert-WrapperRejected $fixture 'sevenzip_wrapper_path_invalid'

        $fixture = New-WrapperTestFixture 'alias'
        $caught = $null
        try { Invoke-WrapperTool $fixture $fixture.Raw | Out-Null } catch { $caught = $_ }
        $caught.Exception.Message | Should Match 'sevenzip_wrapper_path_alias'
        (Get-WrapperTestSha256 $fixture.Raw) | Should Be $fixture.Sha256
    }

    It 'contains one raw read and never reopens the input after identity verification' {
        $source = [IO.File]::ReadAllText($script:WrapperTool, $script:Utf8)
        ([regex]::Matches($source, '\[IO\.File\]::ReadAllBytes\(')).Count | Should Be 1
        $source | Should Not Match 'Get-FileHash|OpenRead\('
        $source | Should Match 'MemoryStream'
        $source | Should Match 'CompressionLevel\]::NoCompression'
    }
}
