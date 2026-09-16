[CmdletBinding()]
param(
    [string] $RepositoryRoot = (Join-Path $PSScriptRoot '..'),
    [string] $AssetDirectory,
    [string] $ReleaseNotesPath = (Join-Path $PSScriptRoot '..\release\notes\v2.19.1-karon.2.md'),
    [string] $ReceiptPath,
    [switch] $PlanOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:KaronPublishTag = 'v2.19.1-karon.2'
$script:KaronPublishRepository = 'KaronLabs/ytdlp-korean-interface'
$script:KaronPublishOrigin = 'git@github.com:KaronLabs/ytdlp-korean-interface.git'
$script:KaronPublishAssetNames = @(
    'ytdlp-korean-interface-v2.19.1-karon.2-win-x64.zip',
    'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources.zip',
    'ytdlp-korean-interface-v2.19.1-karon.2.spdx.json',
    'SHA256SUMS.txt'
)
$script:KaronPublishCliReceiptPath = $ReceiptPath

if ($null -eq (Get-Command Assert-KaronReleaseReceipt -ErrorAction SilentlyContinue)) {
    $savedRepositoryRoot = $RepositoryRoot
    $savedAssetDirectory = $AssetDirectory
    $savedReleaseNotesPath = $ReleaseNotesPath
    $savedReceiptPath = $ReceiptPath
    $savedPlanOnly = $PlanOnly
    . (Join-Path $PSScriptRoot 'package-quality-release.ps1')
    $RepositoryRoot = $savedRepositoryRoot
    $AssetDirectory = $savedAssetDirectory
    $ReleaseNotesPath = $savedReleaseNotesPath
    $ReceiptPath = $savedReceiptPath
    $PlanOnly = $savedPlanOnly
}

function Get-KaronPublishSha256 {
    param([Parameter(Mandatory)] [string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-KaronPublishTextSha256 {
    param([Parameter(Mandatory)] [string] $Text)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}

function Invoke-KaronPublishExternal {
    param(
        [Parameter(Mandatory)] [string] $Executable,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [string] $WorkingDirectory
    )

    Push-Location -LiteralPath $WorkingDirectory
    try {
        $output = @(& $Executable @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally { Pop-Location }
    [pscustomobject]@{ ExitCode = $exitCode; Output = (($output | Out-String).Trim()) }
}

function Invoke-KaronPublishRunner {
    param(
        [Parameter(Mandatory)] [scriptblock] $CommandRunner,
        [Parameter(Mandatory)] [string] $Executable,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [string] $WorkingDirectory
    )

    $result = & $CommandRunner $Executable ([string[]]$Arguments) $WorkingDirectory
    if ($null -eq $result -or $null -eq $result.PSObject.Properties['ExitCode'] -or
        $null -eq $result.PSObject.Properties['Output']) { throw 'publication_command_runner_invalid' }
    [pscustomobject]@{ ExitCode = [int]$result.ExitCode; Output = ((@($result.Output) -join "`n").Trim()) }
}

function Invoke-KaronPublishChecked {
    param(
        [Parameter(Mandatory)] [scriptblock] $CommandRunner,
        [Parameter(Mandatory)] [string] $Executable,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [string] $WorkingDirectory,
        [Parameter(Mandatory)] [string] $ErrorId
    )

    $result = Invoke-KaronPublishRunner -CommandRunner $CommandRunner -Executable $Executable -Arguments $Arguments -WorkingDirectory $WorkingDirectory
    if ($result.ExitCode -ne 0) { throw "$ErrorId`: $($result.Output)" }
    $result.Output
}

function Invoke-KaronPublishHttpExternal {
    param(
        [Parameter(Mandatory)] [object] $Request,
        [Parameter(Mandatory)] [string] $Token
    )
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $true
    $client = [Net.Http.HttpClient]::new($handler, $true)
    $message = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new([string]$Request.Method), [Uri][string]$Request.Uri)
    try {
        $message.Headers.UserAgent.ParseAdd('KaronLabs-release-publisher/2.19.1-karon.2')
        $message.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)
        $message.Headers.Accept.ParseAdd([string]$Request.Accept)
        $message.Headers.TryAddWithoutValidation('X-GitHub-Api-Version', '2022-11-28') | Out-Null
        if ($null -ne $Request.PSObject.Properties['UploadPath']) {
            $stream = [IO.FileStream]::new([string]$Request.UploadPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            if ($stream.Length -ne [long]$Request.ExpectedLength) { $stream.Dispose(); throw 'publication_upload_snapshot_mismatch' }
            $algorithm = [Security.Cryptography.SHA256]::Create()
            try { $sha = [Convert]::ToHexString($algorithm.ComputeHash($stream)).ToLowerInvariant() }
            finally { $algorithm.Dispose() }
            if ($sha -cne [string]$Request.ExpectedSha256) { $stream.Dispose(); throw 'publication_upload_snapshot_mismatch' }
            $stream.Position = 0
            $message.Content = [Net.Http.StreamContent]::new($stream)
            $message.Content.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new([string]$Request.ContentType)
        }
        elseif ($null -ne $Request.PSObject.Properties['Body']) {
            $message.Content = [Net.Http.StringContent]::new([string]$Request.Body, [Text.Encoding]::UTF8, [string]$Request.ContentType)
        }
        $response = $client.SendAsync($message, [Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try {
            $status = [int]$response.StatusCode
            if ($null -ne $Request.PSObject.Properties['DownloadPath'] -and $status -in [int[]]$Request.ExpectedStatus) {
                $output = [IO.FileStream]::new([string]$Request.DownloadPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try {
                    $input = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                    try { $input.CopyTo($output) }
                    finally { $input.Dispose() }
                }
                finally { $output.Dispose() }
                return [pscustomobject]@{ StatusCode = $status; Body = '' }
            }
            $length = $response.Content.Headers.ContentLength
            if ($null -ne $length -and [long]$length -gt 1048576L) { throw 'publication_http_response_too_large' }
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ([Text.Encoding]::UTF8.GetByteCount($body) -gt 1048576) { throw 'publication_http_response_too_large' }
            [pscustomobject]@{ StatusCode = $status; Body = $body }
        }
        finally { $response.Dispose() }
    }
    finally {
        $message.Dispose()
        $client.Dispose()
    }
}

function Invoke-KaronPublishHttpChecked {
    param(
        [Parameter(Mandatory)] [scriptblock] $HttpRunner,
        [Parameter(Mandatory)] [object] $Request,
        [Parameter(Mandatory)] [string] $ErrorId
    )
    $result = & $HttpRunner $Request
    if ($null -eq $result -or $null -eq $result.PSObject.Properties['StatusCode'] -or
        $null -eq $result.PSObject.Properties['Body']) { throw 'publication_http_runner_invalid' }
    $status = [int]$result.StatusCode
    if ($status -notin [int[]]$Request.ExpectedStatus) { throw ($ErrorId + ': HTTP ' + $status) }
    [pscustomobject]@{ StatusCode = $status; Body = [string]$result.Body }
}

function ConvertFrom-KaronPublishAssetJson {
    param([Parameter(Mandatory)] [string] $Text)
    $json = ConvertFrom-KaronPackageJsonStrict $Text 'publication_asset_json_invalid'
    $raw = $json.Raw
    $id = Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $raw 'id' 'publication_asset_json_invalid') 'publication_asset_json_invalid'
    $name = Get-KaronPackageRawString (Get-KaronPackageRawProperty $raw 'name' 'publication_asset_json_invalid') 'publication_asset_json_invalid'
    $size = Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $raw 'size' 'publication_asset_json_invalid') 'publication_asset_json_invalid'
    $state = Get-KaronPackageRawString (Get-KaronPackageRawProperty $raw 'state' 'publication_asset_json_invalid') 'publication_asset_json_invalid'
    $digest = $null
    if (Test-KaronPackageRawProperty $raw 'digest') {
        $element = Get-KaronPackageRawProperty $raw 'digest' 'publication_asset_json_invalid'
        if ($element.ValueKind -eq [Text.Json.JsonValueKind]::String) { $digest = $element.GetString() }
        elseif ($element.ValueKind -ne [Text.Json.JsonValueKind]::Null) { throw 'publication_asset_json_invalid' }
    }
    if ($id -le 0 -or $size -lt 0) { throw 'publication_asset_json_invalid' }
    [pscustomobject]@{ Id = $id; Name = $name; Size = $size; State = $state; Digest = $digest }
}

function Get-KaronPublishAssetInventory {
    param([Parameter(Mandatory)] [string] $AssetRoot)

    $root = Assert-KaronPackagePathChain $AssetRoot 'publication_path_reparse_point'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'publication_asset_inventory_invalid' }
    $rootItem = Get-Item -LiteralPath $root -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'publication_asset_inventory_invalid' }

    $actual = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @(Get-ChildItem -LiteralPath $root -Force)) {
        [void](Assert-KaronPackagePathChain $item.FullName 'publication_path_reparse_point')
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -le 0) {
            throw 'publication_asset_inventory_invalid'
        }
        if (-not $actual.TryAdd($item.Name, [pscustomobject]@{
            Name = $item.Name
            Path = [IO.Path]::GetFullPath($item.FullName)
            Length = [long]$item.Length
            Sha256 = Get-KaronPublishSha256 $item.FullName
        })) { throw 'publication_asset_inventory_invalid' }
        if ([string]$actual[$item.Name].Name -cne $item.Name) { throw 'publication_asset_inventory_invalid' }
    }
    if ($actual.Count -ne $script:KaronPublishAssetNames.Count) { throw 'publication_asset_inventory_invalid' }
    foreach ($name in $script:KaronPublishAssetNames) {
        if (-not $actual.ContainsKey($name) -or [string]$actual[$name].Name -cne $name) {
            throw 'publication_asset_inventory_invalid'
        }
    }
    $actual
}

function Assert-KaronPublishInventorySnapshot {
    param(
        [Parameter(Mandatory)] [string] $AssetRoot,
        [Parameter(Mandatory)] [Collections.Generic.Dictionary[string, object]] $Snapshot
    )
    $current = Get-KaronPublishAssetInventory $AssetRoot
    foreach ($name in $script:KaronPublishAssetNames) {
        if ([long]$current[$name].Length -ne [long]$Snapshot[$name].Length -or
            [string]$current[$name].Sha256 -cne [string]$Snapshot[$name].Sha256) { throw 'publication_asset_changed' }
    }
}

function New-KaronPublishUploadSnapshot {
    param(
        [Parameter(Mandatory)] [string] $AssetRoot,
        [Parameter(Mandatory)] [Collections.Generic.Dictionary[string, object]] $Inventory
    )
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    [void](Assert-KaronPackagePathChain $temp 'publication_path_reparse_point')
    $root = Join-Path $temp ('karon-release-upload-' + [Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $root)
    [void](Assert-KaronPackagePathChain $root 'publication_path_reparse_point')
    try {
        foreach ($name in $script:KaronPublishAssetNames) {
            [IO.File]::Copy([string]$Inventory[$name].Path, (Join-Path $root $name), $false)
        }
        $sealed = Get-KaronPublishAssetInventory $root
        foreach ($name in $script:KaronPublishAssetNames) {
            if ([long]$sealed[$name].Length -ne [long]$Inventory[$name].Length -or
                [string]$sealed[$name].Sha256 -cne [string]$Inventory[$name].Sha256) { throw 'publication_asset_snapshot_failed' }
        }
        Assert-KaronPublishInventorySnapshot $AssetRoot $sealed
        [pscustomobject]@{ Root = $root; Inventory = $sealed }
    }
    catch {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
        throw
    }
}

function Remove-KaronPublishUploadSnapshot {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $full = [IO.Path]::GetFullPath($Path)
    [void](Assert-KaronPackagePathChain $full 'publication_path_reparse_point')
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ((Split-Path -Parent $full) -cne $temp -or -not ([IO.Path]::GetFileName($full)).StartsWith('karon-release-upload-', [StringComparison]::Ordinal)) {
        throw 'publication_asset_snapshot_location_invalid'
    }
    Remove-Item -LiteralPath $full -Recurse -Force
}

function Assert-KaronPublishChecksums {
    param([Parameter(Mandatory)] [Collections.Generic.Dictionary[string, object]] $Inventory)

    $sumsPath = [string]$Inventory['SHA256SUMS.txt'].Path
    $bytes = [IO.File]::ReadAllBytes($sumsPath)
    if ($bytes.Length -eq 0 -or ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) -or
        $bytes -contains 13 -or $bytes[$bytes.Length - 1] -ne 10) { throw 'publication_checksum_format_invalid' }
    try { $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes) }
    catch { throw 'publication_checksum_format_invalid' }

    $lines = @($text.Substring(0, $text.Length - 1).Split("`n"))
    $coveredNames = @($script:KaronPublishAssetNames[0], $script:KaronPublishAssetNames[1], $script:KaronPublishAssetNames[2])
    if ($lines.Count -ne $coveredNames.Count) { throw 'publication_checksum_inventory_invalid' }
    for ($index = 0; $index -lt $coveredNames.Count; $index++) {
        $match = [regex]::Match($lines[$index], '^([0-9a-f]{64})  (.+)$', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if (-not $match.Success -or $match.Groups[2].Value -cne $coveredNames[$index]) {
            throw 'publication_checksum_format_invalid'
        }
        if ($match.Groups[1].Value -cne [string]$Inventory[$coveredNames[$index]].Sha256) {
            throw "publication_checksum_mismatch: $($coveredNames[$index])"
        }
    }
}

function Assert-KaronPublishSha {
    param([string] $Value, [Parameter(Mandatory)] [string] $ErrorId)
    if ($Value -notmatch '^[a-fA-F0-9]{40}$') { throw $ErrorId }
    $Value.ToLowerInvariant()
}





function Get-KaronPublishRepositorySeal {
    param(
        [scriptblock] $CommandRunner,
        [string] $RepositoryRoot,
        [object] $Receipt,
        [object] $Expected
    )
    $fetchOrigin = Invoke-KaronPublishChecked $CommandRunner 'git' @('remote', 'get-url', 'origin') $RepositoryRoot 'publication_origin_lookup_failed'
    $pushOrigin = Invoke-KaronPublishChecked $CommandRunner 'git' @('remote', 'get-url', '--push', 'origin') $RepositoryRoot 'publication_origin_lookup_failed'
    if ($fetchOrigin -cne $script:KaronPublishOrigin -or $pushOrigin -cne $script:KaronPublishOrigin) { throw 'publication_origin_mismatch' }
    $status = Invoke-KaronPublishChecked $CommandRunner 'git' @('status', '--porcelain=v1', '--untracked-files=all') $RepositoryRoot 'publication_status_failed'
    if (-not [string]::IsNullOrWhiteSpace($status)) { throw 'publication_tree_dirty' }
    $head = Assert-KaronPublishSha (Invoke-KaronPublishChecked $CommandRunner 'git' @('rev-parse', '--verify', 'HEAD^{commit}') $RepositoryRoot 'publication_head_lookup_failed') 'publication_head_invalid'
    if ($head -cne $Receipt.PackagingCommit) { throw 'publication_receipt_head_mismatch' }
    $remoteMain = Invoke-KaronPublishChecked $CommandRunner 'git' @('ls-remote', 'origin', 'refs/heads/main') $RepositoryRoot 'publication_main_lookup_failed'
    $mainMatch = [regex]::Match($remoteMain.Trim(), '^([a-fA-F0-9]{40})\s+refs/heads/main$')
    if (-not $mainMatch.Success -or $mainMatch.Groups[1].Value.ToLowerInvariant() -cne $head) { throw 'publication_main_sha_mismatch' }

    $tagRef = 'refs/tags/' + $script:KaronPublishTag
    if ((Invoke-KaronPublishChecked $CommandRunner 'git' @('cat-file', '-t', $tagRef) $RepositoryRoot 'publication_tag_lookup_failed') -cne 'tag') {
        throw 'publication_tag_not_annotated'
    }
    $tagObject = Assert-KaronPublishSha (Invoke-KaronPublishChecked $CommandRunner 'git' @('rev-parse', $tagRef) $RepositoryRoot 'publication_tag_lookup_failed') 'publication_tag_lookup_failed'
    $tagTarget = Assert-KaronPublishSha (Invoke-KaronPublishChecked $CommandRunner 'git' @('rev-parse', ($tagRef + '^{}')) $RepositoryRoot 'publication_tag_lookup_failed') 'publication_tag_lookup_failed'
    if ($tagTarget -cne $head) { throw 'publication_tag_target_mismatch' }
    $remoteOutput = Invoke-KaronPublishChecked $CommandRunner 'git' @('ls-remote', 'origin', $tagRef, ($tagRef + '^{}')) $RepositoryRoot 'publication_remote_tag_lookup_failed'
    $remote = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($line in @($remoteOutput -split [char]10)) {
        $match = [regex]::Match($line.Trim(), '^([a-fA-F0-9]{40})\s+(.+)$')
        if (-not $match.Success -or -not $remote.TryAdd($match.Groups[2].Value, $match.Groups[1].Value.ToLowerInvariant())) {
            throw 'publication_remote_tag_lookup_failed'
        }
    }
    if ($remote.Count -ne 2 -or -not $remote.ContainsKey($tagRef) -or -not $remote.ContainsKey($tagRef + '^{}') -or
        $remote[$tagRef] -cne $tagObject -or $remote[$tagRef + '^{}'] -cne $head) { throw 'publication_remote_tag_mismatch' }

    $treeOutput = Invoke-KaronPublishChecked $CommandRunner 'git' @('ls-tree', 'HEAD', '--', 'release/notes/v2.19.1-karon.2.md') $RepositoryRoot 'publication_notes_tracking_failed'
    $treeMatch = [regex]::Match($treeOutput.Trim(), '^100644\s+blob\s+([a-fA-F0-9]{40})\s+release/notes/v2\.19\.1-karon\.2\.md$')
    if (-not $treeMatch.Success -or $treeMatch.Groups[1].Value.ToLowerInvariant() -cne $Receipt.NotesBlobSha1) {
        throw 'publication_notes_tracking_failed'
    }
    $seal = [pscustomobject]@{ Head = $head; TagObject = $tagObject; TagTarget = $tagTarget; NotesBlob = $Receipt.NotesBlobSha1 }
    if ($null -ne $Expected -and
        ($seal.Head -cne $Expected.Head -or $seal.TagObject -cne $Expected.TagObject -or
         $seal.TagTarget -cne $Expected.TagTarget -or $seal.NotesBlob -cne $Expected.NotesBlob)) {
        throw 'publication_repository_race'
    }
    $seal
}

function Assert-KaronPublishReleaseAbsent {
    param([scriptblock] $CommandRunner, [string] $RepositoryRoot)
    $api = 'repos/KaronLabs/ytdlp-korean-interface/releases/tags/' + $script:KaronPublishTag
    $result = Invoke-KaronPublishRunner $CommandRunner 'gh' @('api', '--method', 'GET', $api) $RepositoryRoot
    if ($result.ExitCode -eq 0) { throw 'publication_release_exists' }
    if ($result.Output -notmatch '(?i)(HTTP\s+404|Not Found)') { throw ('publication_release_lookup_failed: ' + $result.Output) }
}

function ConvertFrom-KaronPublishReleaseJson {
    param([Parameter(Mandatory)] [string] $Text)
    $json = ConvertFrom-KaronPackageJsonStrict $text 'publication_release_json_invalid'
    $raw = $json.Raw
    $id = Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $raw 'id' 'publication_release_json_invalid') 'publication_release_json_invalid'
    $tag = Get-KaronPackageRawString (Get-KaronPackageRawProperty $raw 'tag_name' 'publication_release_json_invalid') 'publication_release_json_invalid'
    $title = Get-KaronPackageRawString (Get-KaronPackageRawProperty $raw 'name' 'publication_release_json_invalid') 'publication_release_json_invalid'
    $body = Get-KaronPackageRawString (Get-KaronPackageRawProperty $raw 'body' 'publication_release_json_invalid') 'publication_release_json_invalid'
    $draft = Get-KaronPackageRawBoolean (Get-KaronPackageRawProperty $raw 'draft' 'publication_release_json_invalid') 'publication_release_json_invalid'
    $prerelease = Get-KaronPackageRawBoolean (Get-KaronPackageRawProperty $raw 'prerelease' 'publication_release_json_invalid') 'publication_release_json_invalid'
    $uploadUrl = Get-KaronPackageRawString (Get-KaronPackageRawProperty $raw 'upload_url' 'publication_release_json_invalid') 'publication_release_json_invalid'
    $expectedUploadUrl = 'https://uploads.github.com/repos/KaronLabs/ytdlp-korean-interface/releases/' + [string]$id + '/assets{?name,label}'
    if ($id -le 0 -or $tag -cne $script:KaronPublishTag -or $uploadUrl -cne $expectedUploadUrl) { throw 'publication_release_json_invalid' }
    $assets = [Collections.Generic.List[object]]::new()
    foreach ($asset in Get-KaronPackageRawArray (Get-KaronPackageRawProperty $raw 'assets' 'publication_release_json_invalid') 'publication_release_json_invalid') {
        $assetId = Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $asset 'id' 'publication_release_json_invalid') 'publication_release_json_invalid'
        $name = Get-KaronPackageRawString (Get-KaronPackageRawProperty $asset 'name' 'publication_release_json_invalid') 'publication_release_json_invalid'
        $size = Get-KaronPackageRawInt64 (Get-KaronPackageRawProperty $asset 'size' 'publication_release_json_invalid') 'publication_release_json_invalid'
        $state = Get-KaronPackageRawString (Get-KaronPackageRawProperty $asset 'state' 'publication_release_json_invalid') 'publication_release_json_invalid'
        $digest = $null
        if (Test-KaronPackageRawProperty $asset 'digest') {
            $digestElement = Get-KaronPackageRawProperty $asset 'digest' 'publication_release_json_invalid'
            if ($digestElement.ValueKind -eq [Text.Json.JsonValueKind]::String) { $digest = $digestElement.GetString() }
            elseif ($digestElement.ValueKind -ne [Text.Json.JsonValueKind]::Null) { throw 'publication_release_json_invalid' }
        }
        if ($assetId -le 0 -or $size -lt 0) { throw 'publication_release_json_invalid' }
        $assets.Add([pscustomobject]@{ Id = $assetId; Name = $name; Size = $size; State = $state; Digest = $digest })
    }
    [pscustomobject]@{
        Id = $id
        Tag = $tag
        Title = $title
        BodySha256 = Get-KaronPublishTextSha256 $body
        Draft = $draft
        Prerelease = $prerelease
        UploadEndpoint = $uploadUrl.Substring(0, $uploadUrl.IndexOf('{'))
        Assets = @($assets)
    }
}

function Get-KaronPublishRemoteRelease {
    param([scriptblock] $CommandRunner, [string] $RepositoryRoot, [long] $ReleaseId)
    if ($ReleaseId -le 0) { throw 'publication_release_id_invalid' }
    $api = 'repos/KaronLabs/ytdlp-korean-interface/releases/' + [string]$ReleaseId
    $text = Invoke-KaronPublishChecked $CommandRunner 'gh' @('api', '--method', 'GET', $api) $RepositoryRoot 'publication_release_lookup_failed'
    ConvertFrom-KaronPublishReleaseJson $text
}

function Assert-KaronPublishReleaseIdentity {
    param([object] $Release, [bool] $ExpectedDraft, [object] $ExpectedSeal)
    if ($Release.Draft -ne $ExpectedDraft -or $Release.Prerelease -or
        $Release.Tag -cne $ExpectedSeal.Tag -or $Release.Title -cne $ExpectedSeal.Title -or
        $Release.BodySha256 -cne $ExpectedSeal.BodySha256 -or
        ($null -ne $ExpectedSeal.UploadEndpoint -and $Release.UploadEndpoint -cne $ExpectedSeal.UploadEndpoint) -or
        ($null -ne $ExpectedSeal.Id -and [long]$Release.Id -ne [long]$ExpectedSeal.Id)) {
        throw 'publication_release_identity_mismatch'
    }
}

function Assert-KaronPublishRemoteAssets {
    param(
        [object] $Release,
        [Collections.Generic.Dictionary[string, object]] $Inventory,
        [bool] $ExpectedDraft,
        [bool] $ExpectAssets,
        [object] $ExpectedSeal
    )
    Assert-KaronPublishReleaseIdentity $Release $ExpectedDraft $ExpectedSeal
    $assets = @($Release.Assets)
    if (-not $ExpectAssets) {
        if ($assets.Count -ne 0) { throw 'publication_remote_asset_inventory_invalid' }
        return [pscustomobject]@{ Id = [long]$Release.Id; Tag = $Release.Tag; Title = $Release.Title; BodySha256 = $Release.BodySha256; UploadEndpoint = $Release.UploadEndpoint; Assets = $null }
    }
    $remote = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($asset in $assets) {
        if (-not $remote.TryAdd([string]$asset.Name, $asset) -or [string]$asset.Name -cne [string]$remote[[string]$asset.Name].Name) {
            throw 'publication_remote_asset_inventory_invalid'
        }
    }
    if ($remote.Count -ne 4) { throw 'publication_remote_asset_inventory_invalid' }
    foreach ($name in $script:KaronPublishAssetNames) {
        if (-not $remote.ContainsKey($name) -or [string]$remote[$name].Name -cne $name -or
            [string]$remote[$name].State -cne 'uploaded' -or
            [long]$remote[$name].Size -ne [long]$Inventory[$name].Length) { throw 'publication_remote_asset_inventory_invalid' }
        if (-not [string]::IsNullOrWhiteSpace([string]$remote[$name].Digest)) {
            if ([string]$remote[$name].Digest -cne ('sha256:' + [string]$Inventory[$name].Sha256)) {
                throw ('publication_remote_digest_mismatch: ' + $name)
            }
        }
    }
    $sealedAssets = @($script:KaronPublishAssetNames | ForEach-Object {
        $asset = $remote[$_]
        [pscustomobject]@{ Name = [string]$asset.Name; Id = [long]$asset.Id; Size = [long]$asset.Size; Digest = $asset.Digest }
    })
    if ($null -ne $ExpectedSeal.PSObject.Properties['Assets'] -and $null -ne $ExpectedSeal.Assets) {
        $expectedAssets = @($ExpectedSeal.Assets)
        if ($expectedAssets.Count -ne $sealedAssets.Count) { throw 'publication_remote_asset_identity_mismatch' }
        for ($index = 0; $index -lt $sealedAssets.Count; $index++) {
            $expected = $expectedAssets[$index]
            $actual = $sealedAssets[$index]
            if ($expected.Name -cne $actual.Name -or [long]$expected.Id -ne [long]$actual.Id -or
                [long]$expected.Size -ne [long]$actual.Size -or
                (($null -eq $expected.Digest) -ne ($null -eq $actual.Digest)) -or
                ($null -ne $expected.Digest -and [string]$expected.Digest -cne [string]$actual.Digest)) {
                throw 'publication_remote_asset_identity_mismatch'
            }
        }
    }
    [pscustomobject]@{ Id = [long]$Release.Id; Tag = $Release.Tag; Title = $Release.Title; BodySha256 = $Release.BodySha256; UploadEndpoint = $Release.UploadEndpoint; Assets = $sealedAssets }
}

function New-KaronPublishDraftPlan {
    param(
        [Collections.Generic.Dictionary[string, object]] $Inventory,
        [string] $NotesBody
    )
    $createBody = [ordered]@{ tag_name = $script:KaronPublishTag; name = $script:KaronPublishTag; body = $NotesBody; draft = $true; prerelease = $false } | ConvertTo-Json -Compress
    $create = [pscustomobject]@{
        Name = 'create-draft'
        Method = 'POST'
        Uri = 'https://api.github.com/repos/KaronLabs/ytdlp-korean-interface/releases'
        Accept = 'application/vnd.github+json'
        ContentType = 'application/json'
        Body = $createBody
        ExpectedStatus = @(201)
    }
    $uploads = @($script:KaronPublishAssetNames | ForEach-Object {
        $name = $_
        [pscustomobject]@{
            Name = 'upload-' + $name
            AssetName = $name
            Method = 'POST'
            Uri = '{sealed-upload-url}?name=' + [Uri]::EscapeDataString($name)
            Accept = 'application/vnd.github+json'
            ContentType = if ($name.EndsWith('.zip', [StringComparison]::Ordinal)) { 'application/zip' } elseif ($name.EndsWith('.json', [StringComparison]::Ordinal)) { 'application/json' } else { 'text/plain' }
            UploadPath = [string]$Inventory[$name].Path
            ExpectedLength = [long]$Inventory[$name].Length
            ExpectedSha256 = [string]$Inventory[$name].Sha256
            ExpectedStatus = @(201)
        }
    })
    $downloads = @()
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('karon-release-verify-' + [Guid]::NewGuid().ToString('N'))
    foreach ($name in $script:KaronPublishAssetNames) {
        $downloads += [pscustomobject]@{
            Name = 'download-' + $name
            Directory = $directory
            DownloadPath = Join-Path $directory $name
            Method = 'GET'
            Uri = 'https://api.github.com/repos/KaronLabs/ytdlp-korean-interface/releases/assets/{sealed-asset-id}'
            Accept = 'application/octet-stream'
            ExpectedStatus = @(200)
        }
    }
    $publish = [pscustomobject]@{
        Name = 'publish-draft'
        Executable = 'gh'
        Arguments = @('api', '--method', 'PATCH', 'repos/KaronLabs/ytdlp-korean-interface/releases/{sealed-release-id}', '--field', 'draft=false')
    }
    [pscustomobject]@{
        Create = $create
        Uploads = $uploads
        Downloads = $downloads
        Publish = $publish
        Commands = @($create) + @($uploads) + @($downloads) + @($publish)
    }
}

function Remove-KaronPublishVerificationDirectory {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $full = [IO.Path]::GetFullPath($Path)
    [void](Assert-KaronPackagePathChain $full 'publication_path_reparse_point')
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ((Split-Path -Parent $full) -cne $temp -or -not ([IO.Path]::GetFileName($full)).StartsWith('karon-release-verify-', [StringComparison]::Ordinal)) {
        throw 'publication_verification_directory_invalid'
    }
    Remove-Item -LiteralPath $full -Recurse -Force
}

function Invoke-KaronPublishDownloadVerification {
    param(
        [scriptblock] $CommandRunner,
        [string] $RepositoryRoot,
        [object] $Plan,
        [Collections.Generic.Dictionary[string, object]] $Inventory,
        [object] $ReleaseSeal,
        [scriptblock] $HttpRunner
    )
    $directory = [string]$Plan.Downloads[0].Directory
    if (Test-Path -LiteralPath $directory) { throw 'publication_verification_directory_exists' }
    [void](Assert-KaronPackagePathChain $directory 'publication_path_reparse_point')
    [void](New-Item -ItemType Directory -Path $directory)
    [void](Assert-KaronPackagePathChain $directory 'publication_path_reparse_point')
    try {
        for ($index = 0; $index -lt $Plan.Downloads.Count; $index++) {
            $download = $Plan.Downloads[$index]
            $asset = $ReleaseSeal.Assets[$index]
            if ([string]$download.Directory -cne $directory) { throw 'publication_verification_directory_invalid' }
            if ([string]$asset.Name -cne [string]$download.Name.Substring(9)) { throw 'publication_remote_asset_identity_mismatch' }
            $request = [pscustomobject]@{
                Method = 'GET'
                Uri = 'https://api.github.com/repos/KaronLabs/ytdlp-korean-interface/releases/assets/' + [string]$asset.Id
                Accept = 'application/octet-stream'
                DownloadPath = [string]$download.DownloadPath
                ExpectedStatus = @(200)
            }
            [void](Invoke-KaronPublishHttpChecked $HttpRunner $request 'publication_asset_download_failed')
            [void](Assert-KaronPublishRemoteAssets (Get-KaronPublishRemoteRelease $CommandRunner $RepositoryRoot $ReleaseSeal.Id) $Inventory $true $true $ReleaseSeal)
        }
        $items = @(Get-ChildItem -LiteralPath $directory -Force)
        if ($items.Count -ne 4) { throw 'publication_redownload_inventory_mismatch' }
        foreach ($name in $script:KaronPublishAssetNames) {
            $matches = @($items | Where-Object { $_.Name -ceq $name })
            if ($matches.Count -ne 1 -or $matches[0].PSIsContainer -or
                ($matches[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                [long]$matches[0].Length -ne [long]$Inventory[$name].Length -or
                (Get-KaronPublishSha256 $matches[0].FullName) -cne [string]$Inventory[$name].Sha256) {
                throw ('publication_redownload_mismatch: ' + $name)
            }
        }
    }
    finally { Remove-KaronPublishVerificationDirectory $directory }
}

function Protect-KaronPublishDraft {
    param(
        [scriptblock] $CommandRunner,
        [string] $RepositoryRoot,
        [object] $ReleaseSeal
    )
    $release = Get-KaronPublishRemoteRelease $CommandRunner $RepositoryRoot $ReleaseSeal.Id
    if ($release.Draft) {
        Assert-KaronPublishReleaseIdentity $release $true $ReleaseSeal
        return
    }
    Assert-KaronPublishReleaseIdentity $release $false $ReleaseSeal
    [void](Invoke-KaronPublishChecked $CommandRunner 'gh' @('api', '--method', 'PATCH', ('repos/KaronLabs/ytdlp-korean-interface/releases/' + [string]$ReleaseSeal.Id), '--field', 'draft=true') $RepositoryRoot 'publication_draft_restore_failed')
    Assert-KaronPublishReleaseIdentity (Get-KaronPublishRemoteRelease $CommandRunner $RepositoryRoot $ReleaseSeal.Id) $true $ReleaseSeal
}

function Invoke-QualityReleasePublication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $AssetDirectory,
        [Parameter(Mandatory)] [string] $ReleaseNotesPath,
        [string] $ReceiptPath = $script:KaronPublishCliReceiptPath,
        [switch] $PlanOnly,
        [scriptblock] $CommandRunner,
        [scriptblock] $HttpRunner
    )
    $root = Assert-KaronPackagePathChain $RepositoryRoot 'publication_path_reparse_point'
    $assets = Assert-KaronPackagePathChain $AssetDirectory 'publication_path_reparse_point'
    $notes = Assert-KaronPackagePathChain $ReleaseNotesPath 'publication_path_reparse_point'
    $expectedNotes = [IO.Path]::GetFullPath((Join-Path $root 'release\notes\v2.19.1-karon.2.md'))
    if ($notes -cne $expectedNotes -or [string]::IsNullOrWhiteSpace($ReceiptPath)) { throw 'publication_notes_invalid' }
    $receiptPathFull = Assert-KaronPackagePathChain $ReceiptPath 'publication_path_reparse_point'
    $receipt = Assert-KaronReleaseReceipt $root $assets $receiptPathFull
    if ($receipt.NotesPath -cne $notes) { throw 'publication_notes_invalid' }
    $inventory = Get-KaronPublishAssetInventory $assets
    Assert-KaronPublishChecksums $inventory
    if ($null -eq $CommandRunner) {
        $CommandRunner = { param($Executable, $Arguments, $WorkingDirectory) Invoke-KaronPublishExternal $Executable $Arguments $WorkingDirectory }
    }

    $seal = Get-KaronPublishRepositorySeal $CommandRunner $root $receipt $null
    [void](Invoke-KaronPublishChecked $CommandRunner 'gh' @('auth', 'status', '--hostname', 'github.com') $root 'publication_gh_auth_failed')
    Assert-KaronPublishReleaseAbsent $CommandRunner $root
    $plan = New-KaronPublishDraftPlan $inventory $receipt.NotesBody
    if ($PlanOnly) {
        return [pscustomobject]@{ Mode = 'plan'; Commands = @($plan.Commands); Head = $seal.Head; Tag = $script:KaronPublishTag }
    }

    $releaseCreated = $false
    $uploadSnapshot = $null
    $token = $null
    $releaseSeal = [pscustomobject]@{
        Id = $null
        Tag = $script:KaronPublishTag
        Title = $script:KaronPublishTag
        BodySha256 = Get-KaronPublishTextSha256 $receipt.NotesBody
        UploadEndpoint = $null
        Assets = $null
    }
    try {
        $preCreateReceipt = Assert-KaronReleaseReceipt $root $assets $receiptPathFull
        if ($preCreateReceipt.ReceiptSha256 -cne $receipt.ReceiptSha256) { throw 'publication_receipt_changed' }
        [void](Get-KaronPublishRepositorySeal $CommandRunner $root $preCreateReceipt $seal)
        Assert-KaronPublishReleaseAbsent $CommandRunner $root
        $uploadSnapshot = New-KaronPublishUploadSnapshot $assets $inventory
        $uploadInventory = $uploadSnapshot.Inventory
        $plan = New-KaronPublishDraftPlan $uploadInventory $receipt.NotesBody
        $token = Invoke-KaronPublishChecked $CommandRunner 'gh' @('auth', 'token', '--hostname', 'github.com') $root 'publication_gh_token_failed'
        if ([string]::IsNullOrWhiteSpace($token) -or $token -match '\s') { throw 'publication_gh_token_failed' }
        if ($null -eq $HttpRunner) {
            $capturedToken = $token
            $HttpRunner = { param($request) Invoke-KaronPublishHttpExternal $request $capturedToken }.GetNewClosure()
        }
        $createResponse = Invoke-KaronPublishHttpChecked $HttpRunner $plan.Create 'publication_create_failed'
        $releaseCreated = $true
        $createdRelease = ConvertFrom-KaronPublishReleaseJson $createResponse.Body
        $releaseSeal.Id = [long]$createdRelease.Id
        $releaseSeal.UploadEndpoint = $createdRelease.UploadEndpoint
        $releaseSeal = Assert-KaronPublishRemoteAssets $createdRelease $uploadInventory $true $false $releaseSeal

        $preUploadReceipt = Assert-KaronReleaseReceipt $root $assets $receiptPathFull
        if ($preUploadReceipt.ReceiptSha256 -cne $receipt.ReceiptSha256) { throw 'publication_receipt_changed' }
        Assert-KaronPublishInventorySnapshot $assets $uploadInventory
        Assert-KaronPublishChecksums $uploadInventory
        [void](Get-KaronPublishRepositorySeal $CommandRunner $root $preUploadReceipt $seal)
        [void](Assert-KaronPublishRemoteAssets (Get-KaronPublishRemoteRelease $CommandRunner $root $releaseSeal.Id) $uploadInventory $true $false $releaseSeal)
        $sealedAssets = [Collections.Generic.List[object]]::new()
        $sealedIds = [Collections.Generic.HashSet[long]]::new()
        foreach ($upload in $plan.Uploads) {
            $request = [pscustomobject]@{
                Method = $upload.Method
                Uri = $releaseSeal.UploadEndpoint + '?name=' + [Uri]::EscapeDataString([string]$upload.AssetName)
                Accept = $upload.Accept
                ContentType = $upload.ContentType
                UploadPath = $upload.UploadPath
                ExpectedLength = $upload.ExpectedLength
                ExpectedSha256 = $upload.ExpectedSha256
                ExpectedStatus = $upload.ExpectedStatus
            }
            $response = Invoke-KaronPublishHttpChecked $HttpRunner $request 'publication_upload_failed'
            $asset = ConvertFrom-KaronPublishAssetJson $response.Body
            if (-not [string]::IsNullOrWhiteSpace([string]$asset.Digest) -and [string]$asset.Digest -cne ('sha256:' + [string]$upload.ExpectedSha256)) {
                throw ('publication_remote_digest_mismatch: ' + [string]$upload.AssetName)
            }
            if ($asset.Name -cne $upload.AssetName -or $asset.State -cne 'uploaded' -or
                [long]$asset.Size -ne [long]$upload.ExpectedLength -or -not $sealedIds.Add([long]$asset.Id)) {
                throw 'publication_remote_asset_identity_mismatch'
            }
            $sealedAssets.Add([pscustomobject]@{ Name = $asset.Name; Id = [long]$asset.Id; Size = [long]$asset.Size; Digest = $asset.Digest })
            $releaseSeal.Assets = @($sealedAssets)
        }
        Assert-KaronPublishInventorySnapshot $assets $uploadInventory
        [void](Get-KaronPublishRepositorySeal $CommandRunner $root $preUploadReceipt $seal)
        $releaseSeal = Assert-KaronPublishRemoteAssets (Get-KaronPublishRemoteRelease $CommandRunner $root $releaseSeal.Id) $uploadInventory $true $true $releaseSeal

        $postUploadReceipt = Assert-KaronReleaseReceipt $root $assets $receiptPathFull
        if ($postUploadReceipt.ReceiptSha256 -cne $receipt.ReceiptSha256) { throw 'publication_receipt_changed' }
        Assert-KaronPublishInventorySnapshot $assets $uploadInventory
        [void](Get-KaronPublishRepositorySeal $CommandRunner $root $postUploadReceipt $seal)
        [void](Assert-KaronPublishRemoteAssets (Get-KaronPublishRemoteRelease $CommandRunner $root $releaseSeal.Id) $uploadInventory $true $true $releaseSeal)
        Invoke-KaronPublishDownloadVerification $CommandRunner $root $plan $uploadInventory $releaseSeal $HttpRunner
        $preStableReceipt = Assert-KaronReleaseReceipt $root $assets $receiptPathFull
        if ($preStableReceipt.ReceiptSha256 -cne $receipt.ReceiptSha256) { throw 'publication_receipt_changed' }
        Assert-KaronPublishInventorySnapshot $assets $uploadInventory
        [void](Get-KaronPublishRepositorySeal $CommandRunner $root $preStableReceipt $seal)
        [void](Assert-KaronPublishRemoteAssets (Get-KaronPublishRemoteRelease $CommandRunner $root $releaseSeal.Id) $uploadInventory $true $true $releaseSeal)
        [void](Invoke-KaronPublishChecked $CommandRunner 'gh' @('api', '--method', 'PATCH', ('repos/KaronLabs/ytdlp-korean-interface/releases/' + [string]$releaseSeal.Id), '--field', 'draft=false') $root 'publication_publish_failed')
        [void](Assert-KaronPublishRemoteAssets (Get-KaronPublishRemoteRelease $CommandRunner $root $releaseSeal.Id) $uploadInventory $false $true $releaseSeal)
        [void](Get-KaronPublishRepositorySeal $CommandRunner $root $postUploadReceipt $seal)
        $finalReceipt = Assert-KaronReleaseReceipt $root $assets $receiptPathFull
        if ($finalReceipt.ReceiptSha256 -cne $receipt.ReceiptSha256) { throw 'publication_receipt_changed' }
        Assert-KaronPublishInventorySnapshot $assets $uploadInventory
        [pscustomobject]@{
            Mode = 'published'
            Head = $seal.Head
            Tag = $script:KaronPublishTag
            ReleaseId = [long]$releaseSeal.Id
            Assets = [string[]]$script:KaronPublishAssetNames
            RedownloadsVerified = 4
        }
    }
    catch {
        $failure = $_
        if ($releaseCreated -and $null -ne $releaseSeal.Id) {
            try { Protect-KaronPublishDraft $CommandRunner $root $releaseSeal }
            catch { throw ('publication_draft_preservation_failed; original=' + $failure.Exception.Message + '; restore=' + $_.Exception.Message) }
        }
        throw $failure
    }
    finally {
        if ($null -ne $uploadSnapshot) { Remove-KaronPublishUploadSnapshot $uploadSnapshot.Root }
        $token = $null
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-QualityReleasePublication `
        -RepositoryRoot $RepositoryRoot `
        -AssetDirectory $AssetDirectory `
        -ReleaseNotesPath $ReleaseNotesPath `
        -PlanOnly:$PlanOnly
}
