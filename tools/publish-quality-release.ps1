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

function Get-KaronPublishAssetInventory {
    param([Parameter(Mandatory)] [string] $AssetRoot)

    $root = [IO.Path]::GetFullPath($AssetRoot)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'publication_asset_inventory_invalid' }
    $rootItem = Get-Item -LiteralPath $root -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'publication_asset_inventory_invalid' }

    $actual = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @(Get-ChildItem -LiteralPath $root -Force)) {
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

function Get-KaronPublishCommandPlan {
    param(
        [Parameter(Mandatory)] [Collections.Generic.Dictionary[string, object]] $Inventory,
        [Parameter(Mandatory)] [string] $NotesPath
    )

    $arguments = [Collections.Generic.List[string]]::new()
    foreach ($value in @('release', 'create', $script:KaronPublishTag)) { $arguments.Add($value) }
    foreach ($name in $script:KaronPublishAssetNames) { $arguments.Add([string]$Inventory[$name].Path) }
    foreach ($value in @(
        '--repo', $script:KaronPublishRepository,
        '--title', $script:KaronPublishTag,
        '--notes-file', [IO.Path]::GetFullPath($NotesPath),
        '--verify-tag', '--latest'
    )) { $arguments.Add($value) }
    [pscustomobject]@{ Executable = 'gh'; Arguments = [string[]]$arguments.ToArray() }
}

function Invoke-QualityReleasePublicationLegacy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $AssetDirectory,
        [Parameter(Mandatory)] [string] $ReleaseNotesPath,
        [switch] $PlanOnly,
        [scriptblock] $CommandRunner
    )

    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'publication_repository_missing' }
    $notes = [IO.Path]::GetFullPath($ReleaseNotesPath)
    if (-not (Test-Path -LiteralPath $notes -PathType Leaf)) { throw 'publication_notes_invalid' }
    $notesItem = Get-Item -LiteralPath $notes -Force
    if ($notesItem.Length -le 0 -or ($notesItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'publication_notes_invalid'
    }

    $inventory = Get-KaronPublishAssetInventory -AssetRoot $AssetDirectory
    Assert-KaronPublishChecksums -Inventory $inventory
    if ($null -eq $CommandRunner) {
        $CommandRunner = { param($Executable, $Arguments, $WorkingDirectory) Invoke-KaronPublishExternal -Executable $Executable -Arguments $Arguments -WorkingDirectory $WorkingDirectory }
    }

    $fetchOrigin = Invoke-KaronPublishChecked $CommandRunner 'git' @('remote', 'get-url', 'origin') $root 'publication_origin_lookup_failed'
    $pushOrigin = Invoke-KaronPublishChecked $CommandRunner 'git' @('remote', 'get-url', '--push', 'origin') $root 'publication_origin_lookup_failed'
    if ($fetchOrigin -cne $script:KaronPublishOrigin -or $pushOrigin -cne $script:KaronPublishOrigin) {
        throw 'publication_origin_mismatch'
    }

    $status = Invoke-KaronPublishChecked $CommandRunner 'git' @('status', '--porcelain=v1', '--untracked-files=all') $root 'publication_status_failed'
    if (-not [string]::IsNullOrWhiteSpace($status)) { throw 'publication_tree_dirty' }

    $head = Assert-KaronPublishSha (Invoke-KaronPublishChecked $CommandRunner 'git' @('rev-parse', '--verify', 'HEAD^{commit}') $root 'publication_head_lookup_failed') 'publication_head_invalid'
    $remoteMainOutput = Invoke-KaronPublishChecked $CommandRunner 'git' @('ls-remote', 'origin', 'refs/heads/main') $root 'publication_main_lookup_failed'
    $mainMatch = [regex]::Match($remoteMainOutput, '^([a-fA-F0-9]{40})\s+refs/heads/main$')
    if (-not $mainMatch.Success) { throw 'publication_main_lookup_failed' }
    $remoteHead = Assert-KaronPublishSha $mainMatch.Groups[1].Value 'publication_main_lookup_failed'
    if ($head -cne $remoteHead) { throw 'publication_main_sha_mismatch' }

    $tagRef = 'refs/tags/' + $script:KaronPublishTag
    $tagType = Invoke-KaronPublishChecked $CommandRunner 'git' @('cat-file', '-t', $tagRef) $root 'publication_tag_lookup_failed'
    if ($tagType -cne 'tag') { throw 'publication_tag_not_annotated' }
    $tagObject = Assert-KaronPublishSha (Invoke-KaronPublishChecked $CommandRunner 'git' @('rev-parse', $tagRef) $root 'publication_tag_lookup_failed') 'publication_tag_lookup_failed'
    $tagTarget = Assert-KaronPublishSha (Invoke-KaronPublishChecked $CommandRunner 'git' @('rev-parse', ($tagRef + '^{}')) $root 'publication_tag_lookup_failed') 'publication_tag_lookup_failed'
    if ($tagTarget -cne $head) { throw 'publication_tag_target_mismatch' }

    $remoteTagOutput = Invoke-KaronPublishChecked $CommandRunner 'git' @('ls-remote', 'origin', $tagRef, ($tagRef + '^{}')) $root 'publication_remote_tag_lookup_failed'
    $remoteTags = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($line in @($remoteTagOutput -split "`n")) {
        $match = [regex]::Match($line.Trim(), '^([a-fA-F0-9]{40})\s+(.+)$')
        if (-not $match.Success -or -not $remoteTags.TryAdd($match.Groups[2].Value, $match.Groups[1].Value.ToLowerInvariant())) {
            throw 'publication_remote_tag_lookup_failed'
        }
    }
    if ($remoteTags.Count -ne 2 -or -not $remoteTags.ContainsKey($tagRef) -or -not $remoteTags.ContainsKey($tagRef + '^{}') -or
        $remoteTags[$tagRef] -cne $tagObject -or $remoteTags[$tagRef + '^{}'] -cne $head) {
        throw 'publication_remote_tag_mismatch'
    }

    [void](Invoke-KaronPublishChecked $CommandRunner 'gh' @('auth', 'status', '--hostname', 'github.com') $root 'publication_gh_auth_failed')
    $releaseApi = 'repos/KaronLabs/ytdlp-korean-interface/releases/tags/' + $script:KaronPublishTag
    $existing = Invoke-KaronPublishRunner $CommandRunner 'gh' @('api', '--method', 'GET', $releaseApi) $root
    if ($existing.ExitCode -eq 0) { throw 'publication_release_exists' }
    if ($existing.Output -notmatch '(?i)(HTTP\s+404|Not Found)') { throw "publication_release_lookup_failed: $($existing.Output)" }

    $command = Get-KaronPublishCommandPlan -Inventory $inventory -NotesPath $notes
    if ($PlanOnly) {
        return [pscustomobject]@{ Mode = 'plan'; Command = $command; Head = $head; Tag = $script:KaronPublishTag }
    }

    [void](Invoke-KaronPublishChecked $CommandRunner $command.Executable $command.Arguments $root 'publication_create_failed')
    $publishedJson = Invoke-KaronPublishChecked $CommandRunner 'gh' @('api', '--method', 'GET', $releaseApi) $root 'publication_verify_failed'
    try { $published = $publishedJson | ConvertFrom-Json -Depth 16 }
    catch { throw 'publication_verify_json_invalid' }
    if ($published.tag_name -cne $script:KaronPublishTag -or [bool]$published.draft -or [bool]$published.prerelease) {
        throw 'publication_release_state_invalid'
    }

    $remoteAssets = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($asset in @($published.assets)) {
        if (-not $remoteAssets.TryAdd([string]$asset.name, $asset) -or [string]$remoteAssets[[string]$asset.name].name -cne [string]$asset.name) {
            throw 'publication_remote_asset_inventory_invalid'
        }
    }
    if ($remoteAssets.Count -ne $script:KaronPublishAssetNames.Count) { throw 'publication_remote_asset_inventory_invalid' }
    $digestsVerified = 0
    foreach ($name in $script:KaronPublishAssetNames) {
        if (-not $remoteAssets.ContainsKey($name) -or [string]$remoteAssets[$name].name -cne $name -or
            [string]$remoteAssets[$name].state -cne 'uploaded' -or [long]$remoteAssets[$name].size -ne [long]$inventory[$name].Length) {
            throw 'publication_remote_asset_inventory_invalid'
        }
        if ($null -ne $remoteAssets[$name].PSObject.Properties['digest'] -and
            -not [string]::IsNullOrWhiteSpace([string]$remoteAssets[$name].digest)) {
            $expectedDigest = 'sha256:' + [string]$inventory[$name].Sha256
            if ([string]$remoteAssets[$name].digest -cne $expectedDigest) { throw "publication_remote_digest_mismatch: $name" }
            $digestsVerified++
        }
    }

    [pscustomobject]@{
        Mode = 'published'
        Head = $head
        Tag = $script:KaronPublishTag
        Assets = [string[]]$script:KaronPublishAssetNames
        DigestsVerified = $digestsVerified
    }
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
    if ($head -cne $Receipt.SourceCommit) { throw 'publication_receipt_head_mismatch' }
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

function Get-KaronPublishRemoteRelease {
    param([scriptblock] $CommandRunner, [string] $RepositoryRoot)
    $api = 'repos/KaronLabs/ytdlp-korean-interface/releases/tags/' + $script:KaronPublishTag
    $text = Invoke-KaronPublishChecked $CommandRunner 'gh' @('api', '--method', 'GET', $api) $RepositoryRoot 'publication_release_lookup_failed'
    try {
        $document = [Text.Json.JsonDocument]::Parse($text)
        $raw = $document.RootElement.Clone()
        $document.Dispose()
        $value = $text | ConvertFrom-Json -Depth 16
    }
    catch { throw 'publication_release_json_invalid' }
    if ($raw.ValueKind -ne [Text.Json.JsonValueKind]::Object -or
        (Get-KaronPackageRawProperty $raw 'draft' 'publication_release_json_invalid').ValueKind -notin @([Text.Json.JsonValueKind]::True, [Text.Json.JsonValueKind]::False) -or
        (Get-KaronPackageRawProperty $raw 'prerelease' 'publication_release_json_invalid').ValueKind -notin @([Text.Json.JsonValueKind]::True, [Text.Json.JsonValueKind]::False)) {
        throw 'publication_release_json_invalid'
    }
    [void](Get-KaronPackageRawArray (Get-KaronPackageRawProperty $raw 'assets' 'publication_release_json_invalid') 'publication_release_json_invalid')
    if ([string]$value.tag_name -cne $script:KaronPublishTag) { throw 'publication_release_state_invalid' }
    $value
}

function Assert-KaronPublishRemoteAssets {
    param(
        [object] $Release,
        [Collections.Generic.Dictionary[string, object]] $Inventory,
        [bool] $ExpectedDraft,
        [bool] $ExpectAssets
    )
    if ([bool]$Release.draft -ne $ExpectedDraft -or [bool]$Release.prerelease) { throw 'publication_release_state_invalid' }
    $assets = @($Release.assets)
    if (-not $ExpectAssets) {
        if ($assets.Count -ne 0) { throw 'publication_remote_asset_inventory_invalid' }
        return
    }
    $remote = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($asset in $assets) {
        if (-not $remote.TryAdd([string]$asset.name, $asset) -or [string]$asset.name -cne [string]$remote[[string]$asset.name].name) {
            throw 'publication_remote_asset_inventory_invalid'
        }
    }
    if ($remote.Count -ne 4) { throw 'publication_remote_asset_inventory_invalid' }
    foreach ($name in $script:KaronPublishAssetNames) {
        if (-not $remote.ContainsKey($name) -or [string]$remote[$name].name -cne $name -or
            [long]$remote[$name].size -ne [long]$Inventory[$name].Length) { throw 'publication_remote_asset_inventory_invalid' }
        if ($null -ne $remote[$name].PSObject.Properties['digest'] -and
            $null -ne $remote[$name].digest -and -not [string]::IsNullOrWhiteSpace([string]$remote[$name].digest)) {
            if ([string]$remote[$name].digest -cne ('sha256:' + [string]$Inventory[$name].Sha256)) {
                throw ('publication_remote_digest_mismatch: ' + $name)
            }
        }
    }
}

function New-KaronPublishDraftPlan {
    param(
        [Collections.Generic.Dictionary[string, object]] $Inventory,
        [string] $NotesPath
    )
    $create = [pscustomobject]@{
        Name = 'create-draft'
        Executable = 'gh'
        Arguments = @('release', 'create', $script:KaronPublishTag, '--repo', $script:KaronPublishRepository, '--title', $script:KaronPublishTag, '--notes-file', $NotesPath, '--verify-tag', '--draft')
    }
    $uploadArguments = @('release', 'upload', $script:KaronPublishTag)
    foreach ($name in $script:KaronPublishAssetNames) { $uploadArguments += [string]$Inventory[$name].Path }
    $uploadArguments += @('--repo', $script:KaronPublishRepository)
    $upload = [pscustomobject]@{ Name = 'upload'; Executable = 'gh'; Arguments = $uploadArguments }
    $downloads = @()
    foreach ($name in $script:KaronPublishAssetNames) {
        $directory = Join-Path ([IO.Path]::GetTempPath()) ('karon-release-verify-' + [Guid]::NewGuid().ToString('N'))
        $downloads += [pscustomobject]@{
            Name = 'download-' + $name
            Directory = $directory
            DownloadPath = Join-Path $directory $name
            Executable = 'gh'
            Arguments = @('release', 'download', $script:KaronPublishTag, '--repo', $script:KaronPublishRepository, '--pattern', $name, '--dir', $directory)
        }
    }
    $publish = [pscustomobject]@{
        Name = 'publish-draft'
        Executable = 'gh'
        Arguments = @('release', 'edit', $script:KaronPublishTag, '--repo', $script:KaronPublishRepository, '--draft=false')
    }
    [pscustomobject]@{
        Create = $create
        Upload = $upload
        Downloads = $downloads
        Publish = $publish
        Commands = @($create, $upload) + @($downloads) + @($publish)
    }
}

function Remove-KaronPublishVerificationDirectory {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $full = [IO.Path]::GetFullPath($Path)
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
        [Collections.Generic.Dictionary[string, object]] $Inventory
    )
    foreach ($download in $Plan.Downloads) {
        if (Test-Path -LiteralPath $download.Directory) { throw 'publication_verification_directory_exists' }
        [void](New-Item -ItemType Directory -Path $download.Directory)
        try {
            [void](Invoke-KaronPublishChecked $CommandRunner $download.Executable $download.Arguments $RepositoryRoot 'publication_asset_download_failed')
            $items = @(Get-ChildItem -LiteralPath $download.Directory -Force)
            $name = [string]$download.Arguments[6]
            if ($items.Count -ne 1 -or $items[0].PSIsContainer -or $items[0].Name -cne $name -or
                ($items[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                [long]$items[0].Length -ne [long]$Inventory[$name].Length -or
                (Get-KaronPublishSha256 $items[0].FullName) -cne [string]$Inventory[$name].Sha256) {
                throw ('publication_redownload_mismatch: ' + $name)
            }
        }
        finally { Remove-KaronPublishVerificationDirectory $download.Directory }
    }
}

function Protect-KaronPublishDraft {
    param([scriptblock] $CommandRunner, [string] $RepositoryRoot)
    [void](Invoke-KaronPublishChecked $CommandRunner 'gh' @('release', 'edit', $script:KaronPublishTag, '--repo', $script:KaronPublishRepository, '--draft') $RepositoryRoot 'publication_draft_restore_failed')
    $release = Get-KaronPublishRemoteRelease $CommandRunner $RepositoryRoot
    if (-not [bool]$release.draft) { throw 'publication_draft_restore_failed' }
}

function Invoke-QualityReleasePublication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $AssetDirectory,
        [Parameter(Mandatory)] [string] $ReleaseNotesPath,
        [string] $ReceiptPath = $script:KaronPublishCliReceiptPath,
        [switch] $PlanOnly,
        [scriptblock] $CommandRunner
    )
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $assets = [IO.Path]::GetFullPath($AssetDirectory)
    $notes = [IO.Path]::GetFullPath($ReleaseNotesPath)
    $expectedNotes = [IO.Path]::GetFullPath((Join-Path $root 'release\notes\v2.19.1-karon.2.md'))
    if ($notes -cne $expectedNotes -or [string]::IsNullOrWhiteSpace($ReceiptPath)) { throw 'publication_notes_invalid' }
    $receiptPathFull = [IO.Path]::GetFullPath($ReceiptPath)
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
    $plan = New-KaronPublishDraftPlan $inventory $notes
    if ($PlanOnly) {
        return [pscustomobject]@{ Mode = 'plan'; Commands = @($plan.Commands); Head = $seal.Head; Tag = $script:KaronPublishTag }
    }

    $releaseCreated = $false
    try {
        $preCreateReceipt = Assert-KaronReleaseReceipt $root $assets $receiptPathFull
        if ($preCreateReceipt.ReceiptSha256 -cne $receipt.ReceiptSha256) { throw 'publication_receipt_changed' }
        [void](Get-KaronPublishRepositorySeal $CommandRunner $root $preCreateReceipt $seal)
        Assert-KaronPublishReleaseAbsent $CommandRunner $root
        [void](Invoke-KaronPublishChecked $CommandRunner $plan.Create.Executable $plan.Create.Arguments $root 'publication_create_failed')
        $releaseCreated = $true
        Assert-KaronPublishRemoteAssets (Get-KaronPublishRemoteRelease $CommandRunner $root) $inventory $true $false

        $preUploadReceipt = Assert-KaronReleaseReceipt $root $assets $receiptPathFull
        if ($preUploadReceipt.ReceiptSha256 -cne $receipt.ReceiptSha256) { throw 'publication_receipt_changed' }
        $inventory = Get-KaronPublishAssetInventory $assets
        Assert-KaronPublishChecksums $inventory
        [void](Get-KaronPublishRepositorySeal $CommandRunner $root $preUploadReceipt $seal)
        [void](Invoke-KaronPublishChecked $CommandRunner $plan.Upload.Executable $plan.Upload.Arguments $root 'publication_upload_failed')
        [void](Get-KaronPublishRepositorySeal $CommandRunner $root $preUploadReceipt $seal)
        Assert-KaronPublishRemoteAssets (Get-KaronPublishRemoteRelease $CommandRunner $root) $inventory $true $true
        Invoke-KaronPublishDownloadVerification $CommandRunner $root $plan $inventory

        $postUploadReceipt = Assert-KaronReleaseReceipt $root $assets $receiptPathFull
        if ($postUploadReceipt.ReceiptSha256 -cne $receipt.ReceiptSha256) { throw 'publication_receipt_changed' }
        [void](Get-KaronPublishRepositorySeal $CommandRunner $root $postUploadReceipt $seal)
        Assert-KaronPublishRemoteAssets (Get-KaronPublishRemoteRelease $CommandRunner $root) $inventory $true $true
        [void](Invoke-KaronPublishChecked $CommandRunner $plan.Publish.Executable $plan.Publish.Arguments $root 'publication_publish_failed')
        Assert-KaronPublishRemoteAssets (Get-KaronPublishRemoteRelease $CommandRunner $root) $inventory $false $true
        [void](Get-KaronPublishRepositorySeal $CommandRunner $root $postUploadReceipt $seal)
        [pscustomobject]@{
            Mode = 'published'
            Head = $seal.Head
            Tag = $script:KaronPublishTag
            Assets = [string[]]$script:KaronPublishAssetNames
            RedownloadsVerified = 4
        }
    }
    catch {
        $failure = $_
        if ($releaseCreated) {
            try { Protect-KaronPublishDraft $CommandRunner $root }
            catch { throw ('publication_draft_preservation_failed; original=' + $failure.Exception.Message + '; restore=' + $_.Exception.Message) }
        }
        throw $failure
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-QualityReleasePublication `
        -RepositoryRoot $RepositoryRoot `
        -AssetDirectory $AssetDirectory `
        -ReleaseNotesPath $ReleaseNotesPath `
        -PlanOnly:$PlanOnly
}
