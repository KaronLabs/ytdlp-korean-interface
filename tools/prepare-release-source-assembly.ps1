#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RepositoryRoot,
    [Parameter(Mandatory)] [string] $EvidenceDirectory,
    [Parameter(Mandatory)] [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
$lockPath = Join-Path $RepositoryRoot 'release/dependencies/v2.19.1-karon.2.lock.json'
$lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json -Depth 100
if (Test-Path -LiteralPath $OutputDirectory) { throw 'source_assembly_output_exists' }
$archives = Join-Path $OutputDirectory 'source-archives'
$nonRuntime = Join-Path $EvidenceDirectory 'non-runtime-evidence-07'
$manifestPath = [IO.Path]::GetFullPath((Join-Path $nonRuntime 'component-manifest.json'))
$inventoryPath = [IO.Path]::GetFullPath((Join-Path $nonRuntime 'source-cache-inventory.json'))
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -Depth 100
$inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json -Depth 100
$app = @($lock.components | Where-Object id -CEQ 'application')[0]
if ($inventory.status -cne 'closed' -or $inventory.release -cne 'v2.19.1-karon.2' -or
    $manifest.release.tag -cne $inventory.release -or
    $manifest.approvalProfile -cne $inventory.approvalProfile -or
    [int]$manifest.release.expectedComponentCount -ne @($manifest.components).Count -or
    $inventory.manifestSha256 -ine (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -or
    $inventory.applicationCommit -cne $app.sourceCommit -or
    $lock.release.applicationSource.commit -cne $app.sourceCommit) { throw 'source_assembly_producer_evidence_invalid' }
foreach ($artifact in $inventory.artifacts) {
    if ($artifact.status -cne 'verified' -or $artifact.expectedSha256 -ine $artifact.actualSha256 -or
        [long]$artifact.expectedLength -ne [long]$artifact.actualLength -or
        @($inventory.artifacts | Where-Object id -CEQ $artifact.id).Count -ne 1) {
        throw 'source_assembly_producer_evidence_invalid'
    }
}
foreach ($definition in $manifest.components) {
    if ($definition.id -ceq '7zip') { continue } # Its separate no-RAR producer evidence is preserved.
    $matches = @($lock.components | Where-Object id -CEQ $definition.id)
    if ($matches.Count -ne 1 -or $null -eq $matches[0].producerEvidence -or
        $matches[0].producerEvidence.PSObject.Properties.Name -cnotcontains 'collectorInventoryPath') {
        throw 'source_assembly_producer_evidence_invalid'
    }
    $component = $matches[0]
    if ($definition.id -ceq 'application') {
        if ($definition.sourceCommit -cne '$APPLICATION_RELEASE_COMMIT' -and
            $definition.sourceCommit -cne $component.sourceCommit) { throw 'source_assembly_producer_evidence_invalid' }
    }
    elseif ($definition.sourceCommit -cne $component.sourceCommit) { throw 'source_assembly_producer_evidence_invalid' }
    $artifacts = @($inventory.artifacts | Where-Object component -CEQ $definition.id)
    if ($definition.id -ceq 'application') {
        if ($artifacts.Count -ne 1 -or $artifacts[0].id -cne 'application-source') { throw 'source_assembly_producer_evidence_invalid' }
    }
    else {
        $declared = @($definition.sourceArtifacts)
        if ($declared.Count -eq 0 -or $declared.Count -ne $artifacts.Count) { throw 'source_assembly_producer_evidence_invalid' }
        foreach ($record in $declared) {
            $proof = @($artifacts | Where-Object id -CEQ $record.id)
            if ($proof.Count -ne 1 -or $proof[0].expectedSha256 -ine $record.sha256 -or
                [long]$proof[0].expectedLength -ne [long]$record.length) { throw 'source_assembly_producer_evidence_invalid' }
        }
    }
    $component.producerEvidence.manifestPath = $manifestPath
    $component.producerEvidence.collectorInventoryPath = $inventoryPath
    $component.producerEvidence.PSObject.Properties.Remove('collectorBlockersPath')
    $component.producerEvidence.status = 'verified'
}
function Set-AssemblyFilesAnalyzedFromCandidateFiles {
    param([object]$Lock)

    $invalid = 'source_assembly_candidate_files_invalid'
    if ($Lock.release.PSObject.Properties.Name -cnotcontains 'candidateFiles' -or
        $Lock.release.metadataPackage.PSObject.Properties.Name -cnotcontains 'id') { throw $invalid }

    $components = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    $counts = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($component in @($Lock.components)) {
        $id = [string]$component.id
        if ([string]::IsNullOrWhiteSpace($id) -or -not $components.TryAdd($id, $component)) { throw $invalid }
        $counts.Add($id, 0)
    }
    $metadataId = [string]$Lock.release.metadataPackage.id
    if ([string]::IsNullOrWhiteSpace($metadataId) -or $components.ContainsKey($metadataId)) { throw $invalid }
    $counts.Add($metadataId, 0)

    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $files = @($Lock.release.candidateFiles)
    if ($files.Count -eq 0) { throw $invalid }
    foreach ($file in $files) {
        if ($null -eq $file) { throw $invalid }
        foreach ($name in @('path', 'sha256', 'length', 'package', 'licenseConcluded')) {
            if ($file.PSObject.Properties.Name -cnotcontains $name) { throw $invalid }
        }
        $path = [string]$file.path
        $length = 0L
        if ([string]::IsNullOrWhiteSpace($path) -or $path.Contains('\') -or $path.Contains(':') -or
            @($path.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -ne 0 -or
            -not $paths.Add($path) -or [string]$file.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or
            -not [long]::TryParse([string]$file.length, [ref]$length) -or $length -le 0 -or
            [string]::IsNullOrWhiteSpace([string]$file.licenseConcluded)) { throw $invalid }
        $package = [string]$file.package
        if (-not $counts.ContainsKey($package)) { throw $invalid }
        if ($package -ieq $metadataId) {
            if ($package -cne $metadataId -or $path -cne 'candidate-manifest.json') { throw $invalid }
        }
        elseif ($package -cne [string]$components[$package].id) { throw $invalid }
        $counts[$package]++
    }
    if ($counts[$metadataId] -ne 1) { throw $invalid }

    $decisions = [System.Collections.Generic.List[object]]::new()
    foreach ($component in @($Lock.components)) {
        $id = [string]$component.id
        $buildInput = $component.PSObject.Properties.Name -ccontains 'usage' -and [string]$component.usage -ceq 'build-input'
        $static = $component.PSObject.Properties.Name -ccontains 'staticLinkTarget' -and
            -not [string]::IsNullOrWhiteSpace([string]$component.staticLinkTarget)
        $analyzed = $counts[$id] -gt 0
        if (($buildInput -or $static) -eq $analyzed) { throw $invalid }
        $decisions.Add([pscustomobject]@{ component = $component; analyzed = $analyzed })
    }
    foreach ($decision in $decisions) {
        $decision.component | Add-Member -NotePropertyName filesAnalyzed -NotePropertyValue $decision.analyzed -Force
    }
}
Set-AssemblyFilesAnalyzedFromCandidateFiles -Lock $lock

$repositoryPath = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
$gitRoot = @(& git -C $RepositoryRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or $gitRoot.Count -ne 1 -or
    -not ([IO.Path]::GetFullPath([string]$gitRoot[0]).TrimEnd('\', '/')).Equals($repositoryPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'source_assembly_repository_invalid'
}
$head = @(& git -C $RepositoryRoot rev-parse --verify 'HEAD^{commit}' 2>$null)
if ($LASTEXITCODE -ne 0 -or $head.Count -ne 1 -or [string]$head[0] -notmatch '^[a-fA-F0-9]{40}$' -or
    [string]$head[0] -ieq $app.sourceCommit) { throw 'source_assembly_packaging_commit_invalid' }
$dirty = @(& git -C $RepositoryRoot status --porcelain --untracked-files=no 2>$null)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'source_assembly_repository_dirty' }
[void][IO.Directory]::CreateDirectory($archives)
$pending = @('Independent exact-candidate license validation has not run.')

# Copy original input files. Identity checks belong to the assembly operation;
# this staging producer does not issue verification or approval verdicts.
foreach ($artifact in $inventory.artifacts) {
    if ($artifact.id -ceq 'application-source') { continue }
    Copy-Item -LiteralPath (Join-Path "$EvidenceDirectory/source-archives" $artifact.fileName) -Destination (Join-Path $archives $artifact.fileName)
}
$official = $lock.release.applicationSource
Copy-Item -LiteralPath $official.localPath -Destination (Join-Path $archives $official.fileName)
$bundlePath = Join-Path $nonRuntime 'ytdlp-korean-interface-v2.19.1-karon.2-non-runtime-component-evidence.zip'
$bundleFile = Get-Item -LiteralPath $bundlePath
$appClosure = [pscustomobject][ordered]@{
    artifactType = 'generated-source-closure'; fileName = $bundleFile.Name; commit = $app.sourceCommit; url = $null
    sha256 = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash.ToLowerInvariant(); length = $bundleFile.Length
    localPath = Join-Path $archives $bundleFile.Name; verificationStatus = 'NOT_VERIFIED'; blockers = $pending
    provenance = [pscustomobject]@{ component = 'application'; sourceCommit = $app.sourceCommit }
}
Copy-Item -LiteralPath $bundlePath -Destination $appClosure.localPath
function Set-UniqueApplicationClosure {
    param([object]$Component, [object]$Closure)

    $preserved = [System.Collections.Generic.List[object]]::new()
    $existing = [System.Collections.Generic.List[object]]::new()
    foreach ($archive in @($Component.sourceArchives)) {
        if ([string]$archive.fileName -ieq [string]$Closure.fileName) {
            $existing.Add($archive)
        } else {
            $preserved.Add($archive)
        }
    }

    foreach ($archive in $existing) {
        $provenance = if ($archive.PSObject.Properties.Name -ccontains 'provenance') { $archive.provenance } else { $null }
        if ([string]$archive.fileName -cne [string]$Closure.fileName -or
            $archive.PSObject.Properties.Name -cnotcontains 'artifactType' -or
            [string]$archive.artifactType -cne [string]$Closure.artifactType -or
            [string]$archive.commit -ine [string]$Closure.commit -or
            [string]$archive.sha256 -ine [string]$Closure.sha256 -or
            [long]$archive.length -ne [long]$Closure.length -or
            $null -eq $provenance -or
            @($provenance.PSObject.Properties.Name).Count -ne 2 -or
            $provenance.PSObject.Properties.Name -cnotcontains 'component' -or
            $provenance.PSObject.Properties.Name -cnotcontains 'sourceCommit' -or
            [string]$provenance.component -cne [string]$Closure.provenance.component -or
            [string]$provenance.sourceCommit -ine [string]$Closure.provenance.sourceCommit) {
            throw "source_assembly_application_closure_conflict:$($Component.id):$($Closure.fileName)"
        }
    }

    if ($existing.Count -gt 0) {
        $preserved.Add($existing[0])
    } else {
        $preserved.Add($Closure)
    }
    $Component.sourceArchives = @($preserved.ToArray())
}
Set-UniqueApplicationClosure -Component $app -Closure $appClosure

foreach ($component in $lock.components) {
    $component.verificationStatus = 'NOT_VERIFIED'
    $component.blockers = $pending
    if ($component.id -cin @('bit7z', 'nana', 'libpng', 'zlib', 'libjpeg-turbo', 'nlohmann-json')) {
        # The bundle retains the candidate dependency archive, modified source
        # trees and nlohmann transform; upstream baselines remain separate.
        Set-UniqueApplicationClosure -Component $component -Closure $appClosure
    }
    if ($component.id -cin @('deno', 'ffmpeg', '7zip')) {
        $origins = @($component.sourceArchives)
        if ($component.id -ceq 'deno' -and $component.PSObject.Properties.Name -ccontains 'upstreamSourceArchives') {
            $origins = @($component.upstreamSourceArchives)
        }
        $component | Add-Member -NotePropertyName upstreamSourceArchives -NotePropertyValue $origins -Force
        $closure = $component.sourceClosure
        if ($component.id -ceq '7zip') {
            $producerPath = Join-Path "$EvidenceDirectory/source-archives" '7z2601-x64-no-rar-source.zip'
            $file = Get-Item -LiteralPath $producerPath
            $sha = (Get-FileHash -LiteralPath $producerPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $length = $file.Length
        }
        else {
            $producerPath = $closure.localPath
            $file = Get-Item -LiteralPath $producerPath
            $sha = $closure.sha256
            $length = $closure.length
        }
        $provenance = [ordered]@{ component = $component.id; sourceCommit = $component.sourceCommit; upstreamSourceArchives = $origins }
        if ($component.id -ceq 'deno') {
            $matches = @($origins | Where-Object commit -CEQ $component.sourceCommit)
            if ($matches.Count -ne 1 -or
                $matches[0].PSObject.Properties.Name -cnotcontains 'archiveEntry' -or
                [string]::IsNullOrWhiteSpace([string]$matches[0].archiveEntry) -or
                $matches[0].PSObject.Properties.Name -cnotcontains 'url' -or
                $matches[0].PSObject.Properties.Name -cnotcontains 'sha256' -or
                $matches[0].PSObject.Properties.Name -cnotcontains 'length') {
                throw 'source_assembly_deno_upstream_origin_invalid'
            }
            $origin = $matches[0]
            $provenance.upstreamSource = [pscustomobject]@{
                entryPath = $origin.archiveEntry; commit = $origin.commit; url = $origin.url; sha256 = $origin.sha256; length = $origin.length
            }
        }
        $record = [pscustomobject][ordered]@{
            artifactType = 'generated-source-closure'; fileName = $file.Name; commit = $component.sourceCommit; url = $null
            sha256 = $sha; length = $length; localPath = Join-Path $archives $file.Name
            verificationStatus = 'NOT_VERIFIED'; blockers = $pending; provenance = [pscustomobject]$provenance
        }
        Copy-Item -LiteralPath $producerPath -Destination $record.localPath
        $component.sourceArchives = @($record)
        if ($component.id -ceq '7zip') {
            $closure.sourceWrapper.fileName = $record.fileName
            $closure.sourceWrapper.localPath = $record.localPath
            $closure.sourceWrapper.sha256 = $record.sha256
            $closure.sourceWrapper.length = $record.length
        }
    }
    foreach ($archive in $component.sourceArchives) {
        $archive.verificationStatus = 'NOT_VERIFIED'
        $archive | Add-Member -NotePropertyName blockers -NotePropertyValue $pending -Force
        $archive.localPath = Join-Path $archives $archive.fileName
    }
}
$lock.release.blockers = $pending
$lock.release.verificationStatus = 'NOT_VERIFIED'
$lock.release | Add-Member -NotePropertyName sourceTransportSplitting -NotePropertyValue 'APPROVED_BY_OWNER' -Force
$lock.release | Add-Member -NotePropertyName productionAssembly -NotePropertyValue 'NOT_RUN' -Force
$lock.release | Add-Member -NotePropertyName licenseApproval -NotePropertyValue 'HOLD' -Force
$lock.release.metadataPackage | Add-Member -NotePropertyName packagingCommit -NotePropertyValue ([string]$head[0]).ToLowerInvariant() -Force
$lock.release.metadataPackage.bindingNote = 'Application source base only. Packaging metadata is bound to committed HEAD; independent validation has not run.'
foreach ($notice in $lock.release.metadataPackage.noticeFiles) {
    $path = Join-Path $RepositoryRoot $notice.path
    $notice.sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $notice.length = (Get-Item -LiteralPath $path).Length
}
$templatePath = Join-Path $OutputDirectory 'source-closure-template.json'
$bytes = $utf8.GetBytes(($lock | ConvertTo-Json -Depth 100) + "`n")
[IO.File]::WriteAllBytes($templatePath, $bytes)
[pscustomobject]@{ template = $templatePath; sourceArchives = $archives; packagingCommit = ([string]$head[0]).ToLowerInvariant(); verificationStatus = 'NOT_VERIFIED'; licenseApproval = 'HOLD' }
