#requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-GeneratedSourceProperty {
    param([AllowNull()] [object] $Value, [string] $Name, [string] $ErrorId)
    if ($null -ne $Value) {
        if ($Value -is [Collections.IDictionary]) {
            foreach ($key in $Value.Keys) {
                if ([string]$key -ceq $Name) { return $Value[$key] }
            }
        }
        else {
            $property = $Value.PSObject.Properties[$Name]
            if ($null -ne $property -and $property.Name -ceq $Name) { return $property.Value }
        }
    }
    throw $ErrorId
}

function Test-GeneratedSourceLength {
    param([AllowNull()] [object] $Value)
    ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [short] -or $Value -is [ushort] -or
        $Value -is [int] -or $Value -is [uint] -or $Value -is [long] -or $Value -is [ulong]) -and
        $Value -gt 0 -and $Value -le [long]::MaxValue
}

function Test-GeneratedSourceArchive {
    # This is only a discriminator; acceptance requires Assert-GeneratedSourceArchive.
    param([Parameter(Mandatory)] [object] $Archive)
    if ($Archive -is [Collections.IDictionary]) {
        return $Archive.Contains('artifactType') -and $Archive['artifactType'] -ceq 'generated-source-closure'
    }
    $property = $Archive.PSObject.Properties['artifactType']
    $null -ne $property -and $property.Value -ceq 'generated-source-closure'
}

function Assert-GeneratedSourceArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Archive,
        [Parameter(Mandatory)] [object] $Component,
        [Parameter(Mandatory)] [object] $Release,
        [string] $ErrorPrefix = 'source'
    )

    $metadataError = $ErrorPrefix + '_generated_archive_metadata_invalid'
    if ((Get-GeneratedSourceProperty $Archive 'artifactType' $metadataError) -cne 'generated-source-closure') { throw $metadataError }
    $componentId = Get-GeneratedSourceProperty $Component 'id' $metadataError
    $provenanceError = $ErrorPrefix + '_generated_archive_provenance_invalid'
    $provenance = Get-GeneratedSourceProperty $Archive 'provenance' $provenanceError
    $staticApplication = $componentId -cin @('bit7z', 'nana', 'libpng', 'zlib', 'libjpeg-turbo', 'nlohmann-json') -and
        (Get-GeneratedSourceProperty $provenance 'component' $provenanceError) -ceq 'application'
    $owner = if ($staticApplication) { 'application' } else { $componentId }
    if ($componentId -isnot [string] -or ($componentId -cnotin @('application', 'deno', 'ffmpeg', '7zip') -and -not $staticApplication)) {
        throw ($ErrorPrefix + '_generated_archive_component_invalid')
    }
    if ($null -ne (Get-GeneratedSourceProperty $Archive 'url' ($ErrorPrefix + '_generated_archive_url_invalid'))) {
        throw ($ErrorPrefix + '_generated_archive_url_invalid')
    }

    $commit = Get-GeneratedSourceProperty $Archive 'commit' $metadataError
    $sourceCommit = Get-GeneratedSourceProperty $Component 'sourceCommit' $metadataError
    if ($staticApplication) {
        $integration = Get-GeneratedSourceProperty $Release 'integrationEvidence' $provenanceError
        $applicationSource = Get-GeneratedSourceProperty $integration 'applicationSource' $provenanceError
        $sourceCommit = Get-GeneratedSourceProperty $applicationSource 'commit' $provenanceError
    }
    if ($commit -isnot [string] -or $commit -notmatch '^[a-fA-F0-9]{40}$' -or $commit -cne $sourceCommit) {
        throw ($ErrorPrefix + '_generated_archive_commit_mismatch')
    }
    $fileName = Get-GeneratedSourceProperty $Archive 'fileName' $metadataError
    $length = Get-GeneratedSourceProperty $Archive 'length' $metadataError
    $sha256 = Get-GeneratedSourceProperty $Archive 'sha256' $metadataError
    if ($fileName -isnot [string] -or $fileName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\.zip$' -or
        $fileName -match '^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)' -or
        -not (Test-GeneratedSourceLength $length) -or $sha256 -isnot [string] -or $sha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw $metadataError
    }

    if ((Get-GeneratedSourceProperty $provenance 'component' $provenanceError) -cne $owner -or
        (Get-GeneratedSourceProperty $provenance 'sourceCommit' $provenanceError) -cne $commit) { throw $provenanceError }
    $origin = Get-GeneratedSourceProperty $Component 'sourceRepository' $metadataError
    if ($origin -isnot [string] -or [string]::IsNullOrWhiteSpace($origin)) { throw $metadataError }

    $releaseError = $ErrorPrefix + '_generated_archive_release_unverified'
    if ((Get-GeneratedSourceProperty $Release 'verificationStatus' $releaseError) -cne 'verified') { throw $releaseError }
    if (@(Get-GeneratedSourceProperty $Release 'blockers' $releaseError).Count -ne 0) {
        throw ($ErrorPrefix + '_generated_archive_release_blocked')
    }
    $proofError = $ErrorPrefix + '_generated_archive_proof_missing'
    $integration = Get-GeneratedSourceProperty $Release 'integrationEvidence' $proofError
    if ((Get-GeneratedSourceProperty $integration 'schemaVersion' $proofError) -cne 'karon-release-license-lock-integration/v1') { throw $proofError }
    # Fixed producer selectors only. Never search unrelated evidence for a matching hash.
    $selector = switch ($owner) {
        'application' { @('nonRuntime', 'applicationSourceArchive') }
        'deno' { @('denoComponent', 'sourcesArchive') }
        'ffmpeg' { @('ffmpeg', 'sourcesArchive') }
        '7zip' { @('sevenZip', 'sourceWrapper') }
    }
    $proof = $integration
    foreach ($name in $selector) { $proof = Get-GeneratedSourceProperty $proof $name $proofError }
    $proofName = Get-GeneratedSourceProperty $proof 'fileName' $proofError
    $lengthField = if ($componentId -ceq '7zip') { 'outerLength' } else { 'length' }
    $shaField = if ($componentId -ceq '7zip') { 'outerSha256' } else { 'sha256' }
    $proofLength = Get-GeneratedSourceProperty $proof $lengthField $proofError
    $proofSha256 = Get-GeneratedSourceProperty $proof $shaField $proofError
    if ($proofName -isnot [string] -or $proofName -cne $fileName -or
        -not (Test-GeneratedSourceLength $proofLength) -or $proofLength -ne $length -or
        $proofSha256 -isnot [string] -or $proofSha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        $proofSha256.ToLowerInvariant() -cne $sha256.ToLowerInvariant()) {
        throw ($ErrorPrefix + '_generated_archive_proof_mismatch')
    }

    $evidencePath = 'release.integrationEvidence.' + ($selector -join '.')
    $normalizedSha256 = $sha256.ToLowerInvariant()
    [pscustomobject]@{
        artifactType = 'generated-source-closure'
        component = $componentId
        fileName = $fileName
        commit = $commit
        url = $null
        length = [long]$length
        sha256 = $normalizedSha256
        provenance = $provenance
        evidencePath = $evidencePath
        sourceInfo = "Origin: $origin; baseline commit: $(Get-GeneratedSourceProperty $Component 'sourceCommit' $metadataError); closure owner: $owner; source commit: $commit; locally generated source closure: $fileName; length: $length; SHA256: $normalizedSha256; producer evidence: $evidencePath."
    }
}

Export-ModuleMember -Function Test-GeneratedSourceArchive, Assert-GeneratedSourceArchive
