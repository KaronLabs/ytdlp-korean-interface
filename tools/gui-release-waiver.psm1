#requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-KaronGuiValidationInputs {
    param(
        [string] $GuiValidationWaiverPath,
        [string] $GuiValidationSummaryPath,
        [string] $GuiValidationEvidenceManifestPath,
        [string] $GuiValidationSchemaPath,
        [Collections.IDictionary] $BoundParameters = @{},
        [switch] $RequireSchema
    )
    $waiverProvided = @($BoundParameters.Keys) -ccontains 'GuiValidationWaiverPath' -or -not [string]::IsNullOrWhiteSpace($GuiValidationWaiverPath)
    $normalProvided = @($BoundParameters.Keys) -ccontains 'GuiValidationSummaryPath' -or @($BoundParameters.Keys) -ccontains 'GuiValidationEvidenceManifestPath' -or
        @($BoundParameters.Keys) -ccontains 'GuiValidationSchemaPath' -or -not [string]::IsNullOrWhiteSpace($GuiValidationSummaryPath) -or
        -not [string]::IsNullOrWhiteSpace($GuiValidationEvidenceManifestPath) -or -not [string]::IsNullOrWhiteSpace($GuiValidationSchemaPath)
    if ($waiverProvided -and $normalProvided) { throw 'gui_validation_input_conflict' }
    if ($waiverProvided) {
        if ([string]::IsNullOrWhiteSpace($GuiValidationWaiverPath)) { throw 'gui_validation_input_missing' }
        return 'waiver'
    }
    if ([string]::IsNullOrWhiteSpace($GuiValidationSummaryPath) -or [string]::IsNullOrWhiteSpace($GuiValidationEvidenceManifestPath) -or
        ($RequireSchema -and [string]::IsNullOrWhiteSpace($GuiValidationSchemaPath))) { throw 'gui_validation_input_missing' }
    'normal'
}

function Assert-WaiverJsonKeys {
    param([Text.Json.JsonElement] $Element)
    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw 'gui_validation_waiver_json_invalid' }
            Assert-WaiverJsonKeys $property.Value
        }
    }
    elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-WaiverJsonKeys $item }
    }
}

function ConvertFrom-WaiverJson {
    param([string] $Text)
    try {
        $document = [Text.Json.JsonDocument]::Parse($Text)
        try {
            Assert-WaiverJsonKeys $document.RootElement
            [pscustomobject]@{ Raw = $document.RootElement.Clone(); Value = ($Text | ConvertFrom-Json -Depth 64) }
        }
        finally { $document.Dispose() }
    }
    catch { throw 'gui_validation_waiver_json_invalid' }
}

function Get-WaiverProperty {
    param([Text.Json.JsonElement] $Element, [string] $Name)
    if ($Element.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw 'gui_validation_waiver_invalid' }
    foreach ($property in $Element.EnumerateObject()) { if ($property.Name -ceq $Name) { return $property.Value.Clone() } }
    throw 'gui_validation_waiver_invalid'
}

function Assert-WaiverExactKeys {
    param([Text.Json.JsonElement] $Element, [string[]] $Names)
    if ($Element.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw 'gui_validation_waiver_invalid' }
    $actual = @($Element.EnumerateObject() | ForEach-Object Name)
    if ($actual.Count -ne $Names.Count) { throw 'gui_validation_waiver_invalid' }
    foreach ($name in $Names) { if ($actual -cnotcontains $name) { throw 'gui_validation_waiver_invalid' } }
}

function Get-WaiverString {
    param([Text.Json.JsonElement] $Element, [string] $Name)
    $value = Get-WaiverProperty $Element $Name
    if ($value.ValueKind -ne [Text.Json.JsonValueKind]::String) { throw 'gui_validation_waiver_invalid' }
    $value.GetString()
}

function Assert-WaiverFixedArray {
    param([Text.Json.JsonElement] $Element, [string[]] $Expected)
    if ($Element.ValueKind -ne [Text.Json.JsonValueKind]::Array -or $Element.GetArrayLength() -ne $Expected.Count) { throw 'gui_validation_waiver_invalid' }
    $index = 0
    foreach ($item in $Element.EnumerateArray()) {
        if ($item.ValueKind -ne [Text.Json.JsonValueKind]::String -or $item.GetString() -cne $Expected[$index]) { throw 'gui_validation_waiver_invalid' }
        $index++
    }
}

function Assert-WaiverPath {
    param([string] $Path)
    $full = [IO.Path]::GetFullPath($Path)
    $cursor = $full
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'gui_validation_waiver_file_invalid' }
        }
        $parent = [IO.Path]::GetDirectoryName($cursor)
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw 'gui_validation_waiver_file_invalid' }
    $full
}

function Get-WaiverFileRecord {
    param([string] $Path)
    $full = Assert-WaiverPath $Path
    $stream = [IO.File]::Open($full, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { [ordered]@{ fileName = [IO.Path]::GetFileName($full); length = [long]$stream.Length; sha256 = [Convert]::ToHexString($algorithm.ComputeHash($stream)).ToLowerInvariant() } }
    finally { $algorithm.Dispose(); $stream.Dispose() }
}

function Assert-WaiverFileRecord {
    param([Text.Json.JsonElement] $Record, [object] $Expected)
    Assert-WaiverExactKeys $Record @('fileName', 'length', 'sha256')
    $lengthValue = Get-WaiverProperty $Record 'length'
    $length = 0L
    if ($lengthValue.ValueKind -ne [Text.Json.JsonValueKind]::Number -or -not $lengthValue.TryGetInt64([ref]$length) -or $length -le 0) { throw 'gui_validation_waiver_invalid' }
    $sha = Get-WaiverString $Record 'sha256'
    if ($sha -cnotmatch '^[a-f0-9]{64}$') { throw 'gui_validation_waiver_invalid' }
    if ((Get-WaiverString $Record 'fileName') -cne $Expected.fileName -or $length -ne $Expected.length -or $sha -cne $Expected.sha256) {
        throw 'gui_validation_waiver_candidate_mismatch'
    }
}

function Assert-KaronGuiValidationWaiverRecord {
    param(
        [Parameter(Mandatory)] [object] $Record,
        [Parameter(Mandatory)] [object] $ManifestRecord,
        [Parameter(Mandatory)] [object] $ExecutableRecord,
        [Parameter(Mandatory)] [string] $ApplicationSourceCommit,
        [Parameter(Mandatory)] [string] $ApplicationSourceTree
    )
    $root = if ($Record -is [Text.Json.JsonElement]) { $Record } else { (ConvertFrom-WaiverJson ($Record | ConvertTo-Json -Depth 32 -Compress)).Raw }
    Assert-WaiverExactKeys $root @('schemaVersion', 'releaseVersion', 'status', 'ownerInstruction', 'limitedObservation', 'scope', 'candidate', 'applicationSource')
    foreach ($pair in @(
        @('schemaVersion', 'karon-gui-validation-waiver/v1'), @('releaseVersion', 'v2.19.1-karon.2'), @('status', 'WAIVED_BY_OWNER'),
        @('ownerInstruction', '남은 gui 확인 거ㅗㄴ너뛰고 릴리즈 까지 달려')
    )) { if ((Get-WaiverString $root $pair[0]) -cne $pair[1]) { throw 'gui_validation_waiver_invalid' } }
    $observation = Get-WaiverProperty $root 'limitedObservation'
    Assert-WaiverExactKeys $observation @('text', 'classification')
    if ((Get-WaiverString $observation 'text') -cne '잘되네' -or
        (Get-WaiverString $observation 'classification') -cne 'LIMITED_UNSTRUCTURED_USER_OBSERVATION') { throw 'gui_validation_waiver_invalid' }
    $scope = Get-WaiverProperty $root 'scope'
    Assert-WaiverExactKeys $scope @('caseIds', 'manualChecks', 'automaticTestsWaived', 'licenseChecksWaived')
    Assert-WaiverFixedArray (Get-WaiverProperty $scope 'caseIds') @('ko-KR-100', 'ko-KR-150', 'ko-KR-200', 'en-US-100', 'en-US-150', 'en-US-200')
    Assert-WaiverFixedArray (Get-WaiverProperty $scope 'manualChecks') @('fullVideoLifecycle', 'mp3Conversion', 'settingsSaveRestartRestore', 'legacySettingsTransition')
    foreach ($name in @('automaticTestsWaived', 'licenseChecksWaived')) {
        if ((Get-WaiverProperty $scope $name).ValueKind -ne [Text.Json.JsonValueKind]::False) { throw 'gui_validation_waiver_invalid' }
    }
    $candidate = Get-WaiverProperty $root 'candidate'
    Assert-WaiverExactKeys $candidate @('manifest', 'executable')
    Assert-WaiverFileRecord (Get-WaiverProperty $candidate 'manifest') $ManifestRecord
    Assert-WaiverFileRecord (Get-WaiverProperty $candidate 'executable') $ExecutableRecord
    $source = Get-WaiverProperty $root 'applicationSource'
    Assert-WaiverExactKeys $source @('commit', 'tree')
    $commit = Get-WaiverString $source 'commit'
    $tree = Get-WaiverString $source 'tree'
    if ($commit -cnotmatch '^[a-f0-9]{40}$' -or $tree -cnotmatch '^[a-f0-9]{40}$') { throw 'gui_validation_waiver_invalid' }
    if ($commit -cne $ApplicationSourceCommit -or $tree -cne $ApplicationSourceTree) { throw 'gui_validation_waiver_application_source_mismatch' }
}

function Read-KaronGuiValidationWaiver {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $CandidateDirectory,
        [Parameter(Mandatory)] [string] $ApplicationSourceCommit,
        [Parameter(Mandatory)] [string] $ApplicationSourceTree
    )
    $full = Assert-WaiverPath $Path
    if ([IO.Path]::GetFileName($full) -cne 'gui-validation-waiver.json') { throw 'gui_validation_waiver_file_invalid' }
    $bytes = [IO.File]::ReadAllBytes($full)
    $json = ConvertFrom-WaiverJson ([Text.UTF8Encoding]::new($false, $true).GetString($bytes))
    $manifestPath = Assert-WaiverPath (Join-Path $CandidateDirectory 'candidate-manifest.json')
    $manifestBytes = [IO.File]::ReadAllBytes($manifestPath)
    $manifest = ConvertFrom-WaiverJson ([Text.UTF8Encoding]::new($false, $true).GetString($manifestBytes))
    if ((Get-WaiverString $manifest.Raw 'applicationSourceCommit').ToLowerInvariant() -cne $ApplicationSourceCommit -or
        (Get-WaiverString $manifest.Raw 'applicationSourceTree').ToLowerInvariant() -cne $ApplicationSourceTree) { throw 'gui_validation_waiver_application_source_mismatch' }
    $manifestRecord = [ordered]@{ fileName = 'candidate-manifest.json'; length = [long]$manifestBytes.LongLength; sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($manifestBytes)).ToLowerInvariant() }
    $executableRecord = Get-WaiverFileRecord (Join-Path $CandidateDirectory 'ytdlp-interface.exe')
    $files = Get-WaiverProperty $manifest.Raw 'files'
    if ($files.ValueKind -ne [Text.Json.JsonValueKind]::Array) { throw 'gui_validation_waiver_invalid' }
    $matches = @($files.EnumerateArray() | Where-Object { (Get-WaiverString $_ 'path') -ceq 'ytdlp-interface.exe' })
    if ($matches.Count -ne 1) { throw 'gui_validation_waiver_candidate_mismatch' }
    $exeLength = Get-WaiverProperty $matches[0] 'length'
    $length = 0L
    if ($exeLength.ValueKind -ne [Text.Json.JsonValueKind]::Number -or -not $exeLength.TryGetInt64([ref]$length) -or
        $length -ne $executableRecord.length -or (Get-WaiverString $matches[0] 'sha256') -cne $executableRecord.sha256) { throw 'gui_validation_waiver_candidate_mismatch' }
    Assert-KaronGuiValidationWaiverRecord $json.Raw $manifestRecord $executableRecord $ApplicationSourceCommit $ApplicationSourceTree
    [pscustomobject]@{
        Record = $json.Value
        LocalPath = $full
        FileRecord = [ordered]@{ fileName = 'gui-validation-waiver.json'; length = [long]$bytes.LongLength; sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant() }
    }
}

Export-ModuleMember -Function Assert-KaronGuiValidationInputs, Assert-KaronGuiValidationWaiverRecord, Read-KaronGuiValidationWaiver
