[CmdletBinding()]
param(
    [string] $TransportManifestPath = (Join-Path $PSScriptRoot 'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources.zip.transport.json'),
    [string] $RestoreDirectory = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-KaronSourceTransportLimits {
    [pscustomobject]@{ SplitThreshold = 2147483648L; PartLength = 1073741824L; AssetLimit = 2147483648L }
}

function Get-KaronSourceTransportNames {
    param([int] $PartCount)
    if ($PartCount -lt 1 -or $PartCount -gt 994) { throw 'source_transport_part_count_invalid' }
    $source = 'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources.zip'
    [pscustomobject]@{
        Archive = $source
        Parts = @((1..$PartCount) | ForEach-Object { $source + ('.part{0:d4}' -f $_) })
        Manifest = $source + '.transport.json'
        RestoreScript = $source + '.restore.ps1'
        Instructions = $source + '.restore.txt'
    }
}

function Assert-KaronSourceTransportPath {
    param([string] $Path)
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    $current = $root
    foreach ($part in @('') + @($full.Substring($root.Length).Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries))) {
        if ($part -ne '') { $current = Join-Path $current $part }
        if (-not (Test-Path -LiteralPath $current)) { break }
        if (((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'source_transport_path_reparse_point'
        }
    }
    $full
}

function Get-KaronSourceTransportSha256 {
    param([string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-KaronSourceTransportJson {
    param([Text.Json.JsonElement] $Element)
    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw 'source_transport_duplicate_key' }
            Assert-KaronSourceTransportJson $property.Value
        }
    }
    elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-KaronSourceTransportJson $item }
    }
}

function Assert-KaronSourceTransportFields {
    param([Text.Json.JsonElement] $Raw, [string[]] $Strings, [string[]] $Integers = @(), [string[]] $Containers = @())
    if ($Raw.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw 'source_transport_manifest_invalid' }
    $expected = @($Strings) + @($Integers) + @($Containers)
    $properties = @($Raw.EnumerateObject())
    if ($properties.Count -ne $expected.Count) { throw 'source_transport_manifest_invalid' }
    foreach ($property in $properties) {
        if ($property.Name -cnotin $expected) { throw 'source_transport_manifest_invalid' }
        if ($property.Name -cin $Strings -and $property.Value.ValueKind -ne [Text.Json.JsonValueKind]::String) {
            throw 'source_transport_manifest_invalid'
        }
        if ($property.Name -cin $Integers) {
            [long]$number = 0
            if ($property.Value.ValueKind -ne [Text.Json.JsonValueKind]::Number -or
                -not $property.Value.TryGetInt64([ref]$number) -or $number -le 0) { throw 'source_transport_manifest_invalid' }
        }
    }
}

function Read-KaronSourceTransportManifest {
    param([string] $Path)
    [void](Assert-KaronSourceTransportPath $Path)
    $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
    $document = [Text.Json.JsonDocument]::Parse($text)
    try {
        $raw = $document.RootElement
        Assert-KaronSourceTransportJson $raw
        Assert-KaronSourceTransportFields $raw @('schemaVersion', 'contract', 'tag', 'platform', 'applicationSourceCommit', 'applicationSourceTree', 'candidateManifestSha256') @('partSize') @('archive', 'parts', 'restoreScript', 'instructions')
        foreach ($name in @('archive', 'restoreScript', 'instructions')) {
            Assert-KaronSourceTransportFields ($raw.GetProperty($name)) @('fileName', 'sha256') @('length')
        }
        $partsRaw = $raw.GetProperty('parts')
        if ($partsRaw.ValueKind -ne [Text.Json.JsonValueKind]::Array) { throw 'source_transport_manifest_invalid' }
        foreach ($part in $partsRaw.EnumerateArray()) {
            Assert-KaronSourceTransportFields $part @('fileName', 'sha256') @('length')
        }
    }
    finally { $document.Dispose() }
    $value = $text | ConvertFrom-Json -Depth 16
    if ($value.schemaVersion -cne 'karon-corresponding-source-transport/v1' -or
        $value.contract -cne 'ordered-byte-concatenation/1GiB-parts' -or
        $value.tag -cne 'v2.19.1-karon.2' -or $value.platform -cne 'win-x64' -or
        $value.applicationSourceCommit -cnotmatch '^[a-f0-9]{40}$' -or
        $value.applicationSourceTree -cnotmatch '^[a-f0-9]{40}$' -or
        $value.candidateManifestSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $value.partSize -gt 1073741824L) { throw 'source_transport_manifest_invalid' }
    $parts = @($value.parts)
    $names = Get-KaronSourceTransportNames $parts.Count
    if ($value.archive.fileName -cne $names.Archive -or
        $value.restoreScript.fileName -cne $names.RestoreScript -or
        $value.instructions.fileName -cne $names.Instructions -or
        [IO.Path]::GetFileName($Path) -cne $names.Manifest) { throw 'source_transport_manifest_invalid' }
    foreach ($record in @($value.archive, $value.restoreScript, $value.instructions) + $parts) {
        if ($record.sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'source_transport_manifest_invalid' }
    }
    [long]$remaining = $value.archive.length
    for ($index = 0; $index -lt $parts.Count; $index++) {
        [long]$length = [Math]::Min([long]$value.partSize, $remaining)
        if ($length -le 0 -or $parts[$index].length -ne $length -or
            $parts[$index].fileName -cne $names.Parts[$index]) { throw 'source_transport_part_inventory_invalid' }
        $remaining -= $length
    }
    if ($remaining -ne 0) { throw 'source_transport_part_inventory_invalid' }
    $value
}

function Restore-KaronCorrespondingSources {
    param([string] $AssetDirectory, [object] $Manifest, [string] $DestinationPath)
    $root = Assert-KaronSourceTransportPath $AssetDirectory
    $destination = Assert-KaronSourceTransportPath $DestinationPath
    if ([IO.Path]::GetFileName($destination) -cne $Manifest.archive.fileName -or
        (Test-Path -LiteralPath $destination)) { throw 'source_transport_destination_exists_or_invalid' }
    $names = Get-KaronSourceTransportNames @($Manifest.parts).Count
    $actualParts = @(Get-ChildItem -LiteralPath $root -Force | Where-Object { $_.Name.StartsWith($names.Archive + '.part', [StringComparison]::OrdinalIgnoreCase) })
    if ($actualParts.Count -ne @($Manifest.parts).Count) { throw 'source_transport_part_inventory_invalid' }
    foreach ($record in @($Manifest.restoreScript, $Manifest.instructions) + @($Manifest.parts)) {
        $path = Assert-KaronSourceTransportPath (Join-Path $root $record.fileName)
        $item = Get-Item -LiteralPath $path -Force
        if ($item.PSIsContainer -or $item.Name -cne $record.fileName -or
            [long]$item.Length -ne [long]$record.length -or (Get-KaronSourceTransportSha256 $path) -cne $record.sha256) {
            throw 'source_transport_asset_mismatch'
        }
    }
    $partial = $destination + '.' + [Guid]::NewGuid().ToString('N') + '.partial'
    try {
        $output = [IO.File]::Open($partial, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            foreach ($part in $Manifest.parts) {
                $path = Assert-KaronSourceTransportPath (Join-Path $root $part.fileName)
                $input = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                try {
                    if ($input.Length -ne [long]$part.length) { throw 'source_transport_asset_mismatch' }
                    $algorithm = [Security.Cryptography.SHA256]::Create()
                    try { $hash = [Convert]::ToHexString($algorithm.ComputeHash($input)).ToLowerInvariant() }
                    finally { $algorithm.Dispose() }
                    if ($hash -cne $part.sha256) { throw 'source_transport_asset_mismatch' }
                    $input.Position = 0
                    $input.CopyTo($output, 1048576)
                }
                finally { $input.Dispose() }
            }
        }
        finally { $output.Dispose() }
        if ((Get-Item -LiteralPath $partial).Length -ne [long]$Manifest.archive.length -or
            (Get-KaronSourceTransportSha256 $partial) -cne $Manifest.archive.sha256) { throw 'source_transport_whole_mismatch' }
        [IO.File]::Move($partial, $destination, $false)
        $destination
    }
    finally { if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force } }
}

if ($MyInvocation.InvocationName -ne '.') {
    $manifest = Read-KaronSourceTransportManifest $TransportManifestPath
    Restore-KaronCorrespondingSources (Split-Path -Parent ([IO.Path]::GetFullPath($TransportManifestPath))) $manifest (Join-Path $RestoreDirectory $manifest.archive.fileName)
}
