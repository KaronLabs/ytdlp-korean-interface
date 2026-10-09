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

function Assert-ArtifactGenerationEligibility {
    param(
        [Parameter(Mandatory)] [object] $Release,
        [Parameter(Mandatory)] [object[]] $Components,
        [Parameter(Mandatory)] [string] $CandidateRoot,
        [string] $ErrorPrefix = 'source'
    )
    $errorId = $ErrorPrefix + '_assembly_binding_invalid'
    $status = Get-GeneratedSourceProperty $Release 'verificationStatus' $errorId
    if (@(Get-GeneratedSourceProperty $Release 'blockers' $errorId).Count -ne 0) { throw ($ErrorPrefix + '_release_blocked') }
    if ($status -ceq 'verified') { return $false }
    if ($status -cne 'NOT_VERIFIED' -or
        (Get-GeneratedSourceProperty $Release 'productionAssembly' $errorId) -cne 'ASSEMBLED_PENDING_INDEPENDENT_VALIDATION' -or
        (Get-GeneratedSourceProperty $Release 'licenseApproval' $errorId) -cne 'HOLD') { throw $errorId }
    $integration = Get-GeneratedSourceProperty $Release 'integrationEvidence' $errorId
    if ((Get-GeneratedSourceProperty $integration 'schemaVersion' $errorId) -cne 'karon-release-license-lock-integration/v1') { throw $errorId }
    $binding = Get-GeneratedSourceProperty $integration 'candidate' $errorId
    foreach ($spec in @(@('manifest', 'candidate-manifest.json'), @('executable', 'ytdlp-interface.exe'))) {
        $record = Get-GeneratedSourceProperty $binding $spec[0] $errorId
        $path = Join-Path $CandidateRoot $spec[1]
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        $digest = Get-GeneratedSourceProperty $record 'sha256' $errorId
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            $digest -notmatch '^[a-fA-F0-9]{64}$' -or
            $item.Length -ne (Get-GeneratedSourceProperty $record 'length' $errorId) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $digest) { throw $errorId }
    }
    $manifest = [IO.File]::ReadAllText((Join-Path $CandidateRoot 'candidate-manifest.json'), [Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json -Depth 64
    $source = Get-GeneratedSourceProperty $integration 'applicationSource' $errorId
    $commit = Get-GeneratedSourceProperty $source 'commit' $errorId
    $tree = Get-GeneratedSourceProperty $source 'tree' $errorId
    if ($commit -notmatch '^[a-fA-F0-9]{40}$' -or $tree -notmatch '^[a-fA-F0-9]{40}$' -or
        $manifest.applicationSourceCommit -cne $commit -or $manifest.applicationSourceTree -cne $tree -or
        (Get-GeneratedSourceProperty (Get-GeneratedSourceProperty $Release 'metadataPackage' $errorId) 'sourceCommit' $errorId) -cne $commit) { throw $errorId }
    $application = @($Components | Where-Object { (Get-GeneratedSourceProperty $_ 'id' $errorId) -ceq 'application' })
    if ($application.Count -gt 0 -and ($application.Count -ne 1 -or
        (Get-GeneratedSourceProperty $application[0] 'sourceCommit' $errorId) -cne $commit)) { throw $errorId }
    $archiveRoot = Get-GeneratedSourceProperty $Release 'sourceArchiveDirectory' $errorId
    if (-not [IO.Path]::IsPathFullyQualified($archiveRoot)) { throw $errorId }
    foreach ($component in $Components) {
        if ((Get-GeneratedSourceProperty $component 'verificationStatus' $errorId) -cne 'NOT_VERIFIED' -or
            @(Get-GeneratedSourceProperty $component 'blockers' $errorId).Count -ne 0) { throw $errorId }
        foreach ($archive in @(Get-GeneratedSourceProperty $component 'sourceArchives' $errorId)) {
            if ((Get-GeneratedSourceProperty $archive 'verificationStatus' $errorId) -cne 'NOT_VERIFIED' -or
                @(Get-GeneratedSourceProperty $archive 'blockers' $errorId).Count -ne 0) { throw $errorId }
            $name = Get-GeneratedSourceProperty $archive 'fileName' $errorId
            if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\.zip$') { throw $errorId }
            $path = Join-Path $archiveRoot $name
            $item = Get-Item -LiteralPath $path -ErrorAction Stop
            $digest = Get-GeneratedSourceProperty $archive 'sha256' $errorId
            if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                $digest -notmatch '^[a-fA-F0-9]{64}$' -or
                $item.Length -ne (Get-GeneratedSourceProperty $archive 'length' $errorId) -or
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $digest) { throw $errorId }
        }
    }
    return $true
}

function Assert-GeneratedSourceArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Archive,
        [Parameter(Mandatory)] [object] $Component,
        [Parameter(Mandatory)] [object] $Release,
        [string] $ErrorPrefix = 'source',
        [switch] $AllowPendingAssembly,
        [string] $CandidateRoot
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
    if ($AllowPendingAssembly) {
        [void](Assert-ArtifactGenerationEligibility -Release $Release -Components @($Component) -CandidateRoot $CandidateRoot -ErrorPrefix $ErrorPrefix)
    }
    elseif ((Get-GeneratedSourceProperty $Release 'verificationStatus' $releaseError) -cne 'verified') { throw $releaseError }
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

Export-ModuleMember -Function Test-GeneratedSourceArchive, Assert-GeneratedSourceArchive, Assert-ArtifactGenerationEligibility
