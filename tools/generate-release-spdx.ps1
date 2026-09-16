#requires -Version 7.4

[CmdletBinding()]
param(
    [string] $LockPath = (Join-Path $PSScriptRoot '..\release\dependencies\v2.19.1-karon.2.lock.json'),
    [string] $SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory)] [string] $CandidateRoot,
    [Parameter(Mandatory)] [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FileDigest {
    param([string] $Path, [ValidateSet('SHA1', 'SHA256')] [string] $Algorithm)
    (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash.ToLowerInvariant()
}

function Test-Property {
    param([Parameter(Mandatory)] [object] $Value, [Parameter(Mandatory)] [string] $Name)
    if ($Value -is [Collections.IDictionary]) { return $Value.Contains($Name) }
    $null -ne $Value.PSObject.Properties[$Name]
}

function Assert-RelativePath {
    param([string] $Path, [Parameter(Mandatory)] [string] $ErrorId)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '[\\:\x00-\x1f<>"|?*]' -or $Path.StartsWith('/')) { throw $ErrorId }
    foreach ($part in $Path.Split('/')) {
        if ($part -in @('', '.', '..') -or $part -match '[. ]$|^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(?:\.|$)') { throw $ErrorId }
    }
}

function Get-ChildPath {
    param([string] $Root, [string] $Relative, [string] $ErrorId)
    Assert-RelativePath $Relative $ErrorId
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $path = [IO.Path]::GetFullPath((Join-Path $rootPath $Relative))
    if (-not $path.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw $ErrorId }
    $path
}

function Assert-JsonKeys {
    param([Text.Json.JsonElement] $Element, [string] $ErrorId)
    if ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Object) {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $names.Add($property.Name)) { throw $ErrorId }
            Assert-JsonKeys $property.Value $ErrorId
        }
    }
    elseif ($Element.ValueKind -eq [Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-JsonKeys $item $ErrorId }
    }
}

function Read-JsonFile {
    param([string] $Path, [string] $ErrorId)
    try {
        $raw = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
        $document = [Text.Json.JsonDocument]::Parse($raw)
        try { Assert-JsonKeys $document.RootElement ($ErrorId + '_duplicate_key') }
        finally { $document.Dispose() }
        ConvertFrom-Json -InputObject $raw -Depth 64
    }
    catch {
        if ($_.Exception.Message.StartsWith($ErrorId, [StringComparison]::Ordinal)) { throw }
        throw $ErrorId
    }
}

function Assert-LicenseExpression {
    param([string] $Expression, [string] $ErrorId)
    if ([string]::IsNullOrWhiteSpace($Expression) -or $Expression -notmatch '^[A-Za-z0-9.+()\-\s]+$' -or
        $Expression -match '(?i)\b(?:NOASSERTION|NONE|NOT_VERIFIED|UNKNOWN|TODO)\b') { throw $ErrorId }
}

function Assert-PinnedUrl {
    param([string] $Url, [string] $Commit, [string] $ErrorId)
    $uri = $null
    if ($Commit -notmatch '^[a-fA-F0-9]{40}$' -or
        -not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -cne 'https' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or
        -not $uri.AbsolutePath.EndsWith("/$Commit.zip", [StringComparison]::OrdinalIgnoreCase)) { throw $ErrorId }
    $uri.AbsoluteUri
}

function Assert-Notice {
    param([string] $Path, [string] $ExpectedSha256)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'spdx_notice_or_source_missing' }
    if ($ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        (Get-FileDigest $Path SHA256) -cne $ExpectedSha256.ToLowerInvariant()) { throw 'spdx_notice_hash_mismatch' }
    $text = [IO.File]::ReadAllText($Path, [Text.UTF8Encoding]::new($false, $true))
    if ($text -match '(?i)\b(?:NOT_VERIFIED|UNKNOWN|TODO)\b|\bunresolved[\s_-]+blocker\b|\bblocker\s*:') {
        throw 'spdx_notice_unresolved_marker'
    }
    $text
}

function Get-CandidateFiles {
    param([string] $Root)
    foreach ($item in Get-ChildItem -LiteralPath $Root -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'spdx_candidate_reparse_point' }
        if ($item.PSIsContainer) { Get-CandidateFiles $item.FullName } else { $item }
    }
}

function Get-PackageVerificationCode {
    param([string[]] $RelativePaths, [Collections.Generic.Dictionary[string, string]] $ActualPaths)
    $sha1Values = @($RelativePaths | ForEach-Object { Get-FileDigest $ActualPaths[$_] SHA1 } | Sort-Object)
    $bytes = [Text.Encoding]::ASCII.GetBytes(($sha1Values -join ''))
    [Convert]::ToHexString([Security.Cryptography.SHA1]::HashData($bytes)).ToLowerInvariant()
}

function Assert-SpdxSemantics {
    param(
        [object] $Document,
        [Collections.Generic.Dictionary[string, object]] $Inventory,
        [Collections.Generic.Dictionary[string, string]] $ActualPaths,
        [Collections.Generic.Dictionary[string, object]] $PackageContracts,
        [Collections.Generic.HashSet[string]] $LicenseRefIds
    )
    if ($Document.spdxVersion -cne 'SPDX-2.3' -or $Document.dataLicense -cne 'CC0-1.0') { throw 'spdx_semantic_document_invalid' }
    $elementIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [void]$elementIds.Add('SPDXRef-DOCUMENT')
    $packageById = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($package in @($Document.packages)) {
        if (-not $elementIds.Add([string]$package.SPDXID) -or -not $packageById.TryAdd([string]$package.SPDXID, $package)) {
            throw 'spdx_semantic_duplicate_id'
        }
        $contract = $PackageContracts[[string]$package.SPDXID]
        [void](Assert-PinnedUrl ([string]$package.downloadLocation) ([string]$contract.commit) 'spdx_semantic_download_invalid')
        Assert-LicenseExpression ([string]$package.licenseDeclared) 'spdx_semantic_license_invalid'
        Assert-LicenseExpression ([string]$package.licenseConcluded) 'spdx_semantic_license_invalid'
    }
    $fileById = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    $relativeById = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    foreach ($file in @($Document.files)) {
        if (-not $elementIds.Add([string]$file.SPDXID) -or -not $fileById.TryAdd([string]$file.SPDXID, $file)) { throw 'spdx_semantic_duplicate_id' }
        $relative = ([string]$file.fileName).Substring(2)
        if (-not $Inventory.ContainsKey($relative)) { throw 'spdx_semantic_file_invalid' }
        $relativeById.Add([string]$file.SPDXID, $relative)
        Assert-LicenseExpression ([string]$file.licenseConcluded) 'spdx_semantic_license_invalid'
        $sha1 = @($file.checksums | Where-Object algorithm -ceq 'SHA1')
        $sha256 = @($file.checksums | Where-Object algorithm -ceq 'SHA256')
        if ($sha1.Count -ne 1 -or $sha256.Count -ne 1 -or
            $sha1[0].checksumValue -cne (Get-FileDigest $ActualPaths[$relative] SHA1) -or
            $sha256[0].checksumValue -cne (Get-FileDigest $ActualPaths[$relative] SHA256)) { throw 'spdx_semantic_checksum_invalid' }
    }
    if ($fileById.Count -ne $Inventory.Count) { throw 'spdx_semantic_file_invalid' }

    $owners = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $containedPaths = [Collections.Generic.Dictionary[string, Collections.Generic.List[string]]]::new([StringComparer]::Ordinal)
    foreach ($packageId in $packageById.Keys) { $containedPaths.Add($packageId, [Collections.Generic.List[string]]::new()) }
    foreach ($relationship in @($Document.relationships)) {
        if (-not $elementIds.Contains([string]$relationship.spdxElementId) -or
            -not $elementIds.Contains([string]$relationship.relatedSpdxElement)) { throw 'spdx_semantic_relationship_invalid' }
        if ($relationship.relationshipType -ceq 'CONTAINS') {
            if (-not $packageById.ContainsKey([string]$relationship.spdxElementId) -or
                -not $fileById.ContainsKey([string]$relationship.relatedSpdxElement) -or
                -not $owners.TryAdd([string]$relationship.relatedSpdxElement, [string]$relationship.spdxElementId)) {
                throw 'spdx_semantic_file_ownership_invalid'
            }
            $containedPaths[[string]$relationship.spdxElementId].Add($relativeById[[string]$relationship.relatedSpdxElement])
        }
    }
    if ($owners.Count -ne $fileById.Count) { throw 'spdx_semantic_file_ownership_invalid' }

    foreach ($packageId in $packageById.Keys) {
        $package = $packageById[$packageId]
        $paths = @($containedPaths[$packageId])
        if ($package.filesAnalyzed) {
            if ($paths.Count -eq 0 -or -not (Test-Property $package 'packageVerificationCode')) { throw 'spdx_semantic_verification_code_missing' }
            $expected = Get-PackageVerificationCode $paths $ActualPaths
            if ($package.packageVerificationCode.packageVerificationCodeValue -cne $expected) { throw 'spdx_semantic_verification_code_invalid' }
        }
        elseif ($paths.Count -ne 0 -or (Test-Property $package 'packageVerificationCode')) { throw 'spdx_semantic_unanalyzed_package_invalid' }
    }

    $definitions = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($definition in @($Document.hasExtractedLicensingInfos)) {
        if ($definition.licenseId -notmatch '^LicenseRef-[A-Za-z0-9.-]+$' -or -not $definitions.Add([string]$definition.licenseId) -or
            [string]::IsNullOrWhiteSpace([string]$definition.extractedText)) { throw 'spdx_semantic_license_ref_invalid' }
    }
    if ($definitions.Count -ne $LicenseRefIds.Count) { throw 'spdx_semantic_license_ref_invalid' }
    foreach ($licenseRefId in $LicenseRefIds) { if (-not $definitions.Contains($licenseRefId)) { throw 'spdx_semantic_license_ref_invalid' } }
}

$lockFile = (Resolve-Path -LiteralPath $LockPath).Path
$source = (Resolve-Path -LiteralPath $SourceRoot).Path
$candidate = (Resolve-Path -LiteralPath $CandidateRoot).Path.TrimEnd('\', '/')
$outputRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path
$lock = Read-JsonFile $lockFile 'spdx_lock_invalid'

if ($lock.schemaVersion -cne 'karon-license-lock/v2' -or $lock.release.tag -cne 'v2.19.1-karon.2' -or
    $lock.release.platform -cne 'win-x64') { throw 'spdx_lock_invalid' }
if (-not (Test-Property $lock.release 'verificationStatus')) { throw 'spdx_release_status_missing' }
if ($lock.release.verificationStatus -cne 'verified') { throw 'spdx_release_not_verified' }
if (-not (Test-Property $lock.release 'blockers')) { throw 'spdx_release_blockers_missing' }
if (@($lock.release.blockers).Count -ne 0) { throw 'spdx_release_blocked' }

if (-not (Test-Property $lock.release 'metadataPackage')) { throw 'spdx_release_metadata_missing' }
$metadataPackage = $lock.release.metadataPackage
if ($metadataPackage.id -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$') { throw 'spdx_release_metadata_invalid' }
Assert-LicenseExpression ([string]$metadataPackage.licenseExpression) 'spdx_license_unverified'
Assert-LicenseExpression ([string]$metadataPackage.licenseConcluded) 'spdx_license_unverified'
$metadataDownload = Assert-PinnedUrl ([string]$metadataPackage.downloadLocation) ([string]$metadataPackage.sourceCommit) 'spdx_source_url_unpinned'

$componentById = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
$componentDownload = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
$noticePaths = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
$licenseRefs = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
$expressions = [Collections.Generic.List[string]]::new()
$expressions.Add([string]$metadataPackage.licenseExpression)
$expressions.Add([string]$metadataPackage.licenseConcluded)

foreach ($component in @($lock.components)) {
    if ($component.id -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*$' -or -not $componentById.TryAdd([string]$component.id, $component)) {
        throw 'spdx_component_invalid'
    }
    if (-not (Test-Property $component 'verificationStatus')) { throw 'spdx_component_status_missing' }
    if ($component.verificationStatus -cne 'verified') { throw 'spdx_component_not_verified' }
    if (-not (Test-Property $component 'blockers')) { throw 'spdx_component_blockers_missing' }
    if (@($component.blockers).Count -ne 0) { throw 'spdx_component_blocked' }
    Assert-LicenseExpression ([string]$component.licenseExpression) 'spdx_license_unverified'
    Assert-LicenseExpression ([string]$component.licenseConcluded) 'spdx_license_unverified'
    $expressions.Add([string]$component.licenseExpression)
    $expressions.Add([string]$component.licenseConcluded)
    if ($component.modified -isnot [bool] -or $component.filesAnalyzed -isnot [bool] -or
        [string]::IsNullOrWhiteSpace([string]$component.buildRecipe) -or
        @($component.noticeFiles).Count -eq 0 -or @($component.sourceArchives).Count -eq 0) { throw 'spdx_notice_or_source_missing' }

    foreach ($notice in @($component.noticeFiles)) {
        $relative = [string]$notice.path
        $noticePath = Get-ChildPath $source $relative 'spdx_notice_path_invalid'
        $text = Assert-Notice $noticePath ([string]$notice.sha256)
        if ($noticePaths.ContainsKey($relative)) {
            if ($noticePaths[$relative].sha256 -cne ([string]$notice.sha256).ToLowerInvariant()) { throw 'spdx_notice_hash_mismatch' }
        }
        else { $noticePaths.Add($relative, [pscustomobject]@{ path = $noticePath; sha256 = ([string]$notice.sha256).ToLowerInvariant(); text = $text }) }
    }

    $primaryDownload = $null
    foreach ($archive in @($component.sourceArchives)) {
        if ($archive.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or -not (Test-Property $archive 'commit')) { throw 'spdx_source_hash_invalid' }
        $url = Assert-PinnedUrl ([string]$archive.url) ([string]$archive.commit) 'spdx_source_url_unpinned'
        if ([string]$archive.commit -ceq [string]$component.sourceCommit) { $primaryDownload = $url }
    }
    if ($null -eq $primaryDownload) { throw 'spdx_notice_or_source_missing' }
    $componentDownload.Add([string]$component.id, $primaryDownload)

    $componentLicenseRefs = if (Test-Property $component 'licenseRefs') { @($component.licenseRefs) } else { @() }
    foreach ($licenseRef in $componentLicenseRefs) {
        if ($licenseRef.licenseId -notmatch '^LicenseRef-[A-Za-z0-9.-]+$' -or -not $licenseRefs.TryAdd([string]$licenseRef.licenseId, $licenseRef) -or
            -not $noticePaths.ContainsKey([string]$licenseRef.noticePath) -or [string]::IsNullOrWhiteSpace([string]$licenseRef.name)) {
            throw 'spdx_license_ref_invalid'
        }
    }
}
if ($componentById.Count -eq 0 -or $componentById.ContainsKey([string]$metadataPackage.id)) { throw 'spdx_component_invalid' }

$inventory = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
$packageCounts = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::OrdinalIgnoreCase)
$packageCounts.Add([string]$metadataPackage.id, 0)
foreach ($componentId in $componentById.Keys) { $packageCounts.Add($componentId, 0) }
foreach ($entry in @($lock.release.candidateFiles)) {
    $relative = [string]$entry.path
    Assert-RelativePath $relative 'spdx_candidate_inventory_invalid'
    Assert-LicenseExpression ([string]$entry.licenseConcluded) 'spdx_license_unverified'
    $expressions.Add([string]$entry.licenseConcluded)
    if ($entry.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or -not $packageCounts.ContainsKey([string]$entry.package) -or
        -not $inventory.TryAdd($relative, $entry)) {
        if (-not $packageCounts.ContainsKey([string]$entry.package)) { throw 'spdx_candidate_package_unknown' }
        throw 'spdx_candidate_inventory_duplicate'
    }
    $packageCounts[[string]$entry.package]++
}
if ($inventory.Count -eq 0 -or -not $inventory.ContainsKey('candidate-manifest.json')) { throw 'spdx_candidate_inventory_missing' }
if ([string]$inventory['candidate-manifest.json'].path -cne 'candidate-manifest.json' -or
    [string]$inventory['candidate-manifest.json'].package -cne [string]$metadataPackage.id) { throw 'spdx_candidate_manifest_inventory_mismatch' }

$actualPaths = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($file in @(Get-CandidateFiles $candidate)) {
    $relative = [IO.Path]::GetRelativePath($candidate, $file.FullName).Replace('\', '/')
    if (-not $actualPaths.TryAdd($relative, $file.FullName)) { throw 'spdx_candidate_inventory_duplicate' }
    if (-not $inventory.ContainsKey($relative)) { throw "spdx_candidate_inventory_extra: $relative" }
    if ((Get-FileDigest $file.FullName SHA256) -cne ([string]$inventory[$relative].sha256).ToLowerInvariant()) {
        throw "spdx_candidate_hash_mismatch: $relative"
    }
}
if ($actualPaths.Count -ne $inventory.Count) { throw 'spdx_candidate_inventory_missing' }

foreach ($component in $componentById.Values) {
    $count = $packageCounts[[string]$component.id]
    if ($component.filesAnalyzed) {
        if ($count -eq 0) { throw 'spdx_candidate_package_empty' }
    }
    else {
        if ($count -ne 0 -or -not (Test-Property $component 'staticLinkTarget') -or
            -not $componentById.ContainsKey([string]$component.staticLinkTarget) -or
            -not $componentById[[string]$component.staticLinkTarget].filesAnalyzed) { throw 'spdx_static_link_invalid' }
    }
}
if ($packageCounts[[string]$metadataPackage.id] -ne 1) { throw 'spdx_release_metadata_inventory_invalid' }

$manifestPath = Get-ChildPath $candidate 'candidate-manifest.json' 'spdx_candidate_manifest_invalid'
$manifest = Read-JsonFile $manifestPath 'spdx_candidate_manifest_invalid'
if ($manifest.schemaVersion -ne 1 -or -not (Test-Property $manifest 'files')) { throw 'spdx_candidate_manifest_invalid' }
$manifestFiles = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($entry in @($manifest.files)) {
    $relative = [string]$entry.path
    Assert-RelativePath $relative 'spdx_candidate_manifest_inventory_mismatch'
    if ($relative -ieq 'candidate-manifest.json' -or $entry.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        ([string]$entry.length) -notmatch '^(0|[1-9][0-9]*)$') { throw 'spdx_candidate_manifest_inventory_mismatch' }
    if (-not $manifestFiles.TryAdd($relative, $entry)) { throw 'spdx_candidate_manifest_duplicate' }
}
if ($manifestFiles.Count -ne ($inventory.Count - 1)) { throw 'spdx_candidate_manifest_inventory_mismatch' }
foreach ($relative in $inventory.Keys) {
    if ($relative -ieq 'candidate-manifest.json') { continue }
    if (-not $manifestFiles.ContainsKey($relative)) { throw 'spdx_candidate_manifest_inventory_mismatch' }
    $manifestEntry = $manifestFiles[$relative]
    if ([string]$manifestEntry.sha256 -cne [string]$inventory[$relative].sha256) { throw "spdx_candidate_manifest_hash_mismatch: $relative" }
    if ([long]$manifestEntry.length -ne (Get-Item -LiteralPath $actualPaths[$relative]).Length) { throw "spdx_candidate_manifest_inventory_mismatch: $relative" }
}

$usedLicenseRefs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($expression in $expressions) {
    foreach ($match in [regex]::Matches($expression, 'LicenseRef-[A-Za-z0-9.-]+')) {
        if (-not $licenseRefs.ContainsKey($match.Value)) { throw "spdx_license_ref_missing: $($match.Value)" }
        [void]$usedLicenseRefs.Add($match.Value)
    }
}

$rootNotice = Join-Path $source 'THIRD-PARTY-NOTICES.txt'
if (-not (Test-Path -LiteralPath $rootNotice -PathType Leaf)) { throw 'spdx_notice_or_source_missing' }
$rootNoticeText = [IO.File]::ReadAllText($rootNotice, [Text.UTF8Encoding]::new($false, $true))
if ($rootNoticeText -match '(?i)\b(?:NOT_VERIFIED|UNKNOWN|TODO)\b|\bunresolved[\s_-]+blocker\b|\bblocker\s*:') {
    throw 'spdx_notice_unresolved_marker'
}

$packages = [Collections.Generic.List[object]]::new()
$relationships = [Collections.Generic.List[object]]::new()
$packageContracts = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)

foreach ($component in @($lock.components)) {
    $packageId = 'SPDXRef-Package-' + [string]$component.id
    $assigned = @($inventory.Keys | Where-Object { [string]$inventory[$_].package -ieq [string]$component.id } | Sort-Object)
    $package = [ordered]@{
        name = [string]$component.name
        SPDXID = $packageId
        versionInfo = [string]$component.version
        downloadLocation = $componentDownload[[string]$component.id]
        filesAnalyzed = [bool]$component.filesAnalyzed
        licenseConcluded = [string]$component.licenseConcluded
        licenseDeclared = [string]$component.licenseExpression
        copyrightText = 'Copyright and attribution are identified in the component notice files recorded by the release lock.'
    }
    if ($component.filesAnalyzed) {
        $package.packageVerificationCode = [ordered]@{ packageVerificationCodeValue = (Get-PackageVerificationCode $assigned $actualPaths) }
    }
    $packages.Add($package)
    $relationships.Add([ordered]@{ spdxElementId = 'SPDXRef-DOCUMENT'; relationshipType = 'DESCRIBES'; relatedSpdxElement = $packageId })
    $packageContracts.Add($packageId, [pscustomobject]@{ commit = [string]$component.sourceCommit })
}

$metadataPackageId = 'SPDXRef-Package-' + [string]$metadataPackage.id
$metadataAssigned = @($inventory.Keys | Where-Object { [string]$inventory[$_].package -ieq [string]$metadataPackage.id } | Sort-Object)
$packages.Add([ordered]@{
    name = [string]$metadataPackage.name
    SPDXID = $metadataPackageId
    versionInfo = [string]$metadataPackage.version
    downloadLocation = $metadataDownload
    filesAnalyzed = $true
    packageVerificationCode = [ordered]@{ packageVerificationCodeValue = (Get-PackageVerificationCode $metadataAssigned $actualPaths) }
    licenseConcluded = [string]$metadataPackage.licenseConcluded
    licenseDeclared = [string]$metadataPackage.licenseExpression
    copyrightText = 'Release metadata is provided under the declared metadata license.'
})
$relationships.Add([ordered]@{ spdxElementId = 'SPDXRef-DOCUMENT'; relationshipType = 'DESCRIBES'; relatedSpdxElement = $metadataPackageId })
$packageContracts.Add($metadataPackageId, [pscustomobject]@{ commit = [string]$metadataPackage.sourceCommit })

$files = [Collections.Generic.List[object]]::new()
foreach ($relative in @($inventory.Keys | Sort-Object)) {
    $pathDigest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($relative))).ToLowerInvariant()
    $fileId = 'SPDXRef-File-' + $pathDigest.Substring(0, 20)
    $actualPath = $actualPaths[$relative]
    $files.Add([ordered]@{
        fileName = './' + $relative
        SPDXID = $fileId
        checksums = @(
            [ordered]@{ algorithm = 'SHA1'; checksumValue = (Get-FileDigest $actualPath SHA1) },
            [ordered]@{ algorithm = 'SHA256'; checksumValue = (Get-FileDigest $actualPath SHA256) }
        )
        licenseConcluded = [string]$inventory[$relative].licenseConcluded
        copyrightText = 'Copyright and attribution are identified by the assigned package and its recorded notices.'
    })
    $relationships.Add([ordered]@{
        spdxElementId = 'SPDXRef-Package-' + [string]$inventory[$relative].package
        relationshipType = 'CONTAINS'
        relatedSpdxElement = $fileId
    })
}

foreach ($component in @($lock.components | Where-Object { -not $_.filesAnalyzed })) {
    $relationships.Add([ordered]@{
        spdxElementId = 'SPDXRef-Package-' + [string]$component.staticLinkTarget
        relationshipType = 'STATIC_LINK'
        relatedSpdxElement = 'SPDXRef-Package-' + [string]$component.id
    })
}

$extracted = [Collections.Generic.List[object]]::new()
foreach ($licenseRefId in @($usedLicenseRefs | Sort-Object)) {
    $definition = $licenseRefs[$licenseRefId]
    $extracted.Add([ordered]@{
        licenseId = $licenseRefId
        extractedText = [string]$noticePaths[[string]$definition.noticePath].text
        name = [string]$definition.name
    })
}

$lockHash = Get-FileDigest $lockFile SHA256
$document = [ordered]@{
    spdxVersion = 'SPDX-2.3'
    dataLicense = 'CC0-1.0'
    SPDXID = 'SPDXRef-DOCUMENT'
    name = 'ytdlp-korean-interface-v2.19.1-karon.2-win-x64'
    documentNamespace = "https://github.com/KaronLabs/ytdlp-korean-interface/spdx/v2.19.1-karon.2/$lockHash"
    creationInfo = [ordered]@{
        created = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        creators = @('Organization: KaronLabs', 'Tool: generate-release-spdx.ps1')
        licenseListVersion = '3.27'
    }
    documentDescribes = @($packages | ForEach-Object { [string]$_.SPDXID })
    packages = @($packages)
    files = @($files)
    relationships = @($relationships)
    hasExtractedLicensingInfos = @($extracted)
}

Assert-SpdxSemantics $document $inventory $actualPaths $packageContracts $usedLicenseRefs

$outputPath = Join-Path $outputRoot 'ytdlp-korean-interface-v2.19.1-karon.2.spdx.json'
if (Test-Path -LiteralPath $outputPath) { throw 'spdx_output_exists' }
$partialPath = "$outputPath.$PID.$([Guid]::NewGuid().ToString('N')).partial"
try {
    $json = $document | ConvertTo-Json -Depth 32
    [IO.File]::WriteAllText($partialPath, $json + "`n", [Text.UTF8Encoding]::new($false))
    [void](Read-JsonFile $partialPath 'spdx_output_invalid')
    [IO.File]::Move($partialPath, $outputPath, $false)
}
catch {
    if (Test-Path -LiteralPath $partialPath) { Remove-Item -LiteralPath $partialPath -Force }
    if (Test-Path -LiteralPath $outputPath) { Remove-Item -LiteralPath $outputPath -Force }
    throw
}
finally {
    if (Test-Path -LiteralPath $partialPath) { Remove-Item -LiteralPath $partialPath -Force }
}

Write-Output $outputPath
