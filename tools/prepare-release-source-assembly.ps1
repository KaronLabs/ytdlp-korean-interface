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
$app.sourceArchives = @($app.sourceArchives) + @($appClosure)

foreach ($component in $lock.components) {
    $component.verificationStatus = 'NOT_VERIFIED'
    $component.blockers = $pending
    if ($component.id -cin @('bit7z', 'nana', 'libpng', 'zlib', 'libjpeg-turbo', 'nlohmann-json')) {
        # The bundle retains the candidate dependency archive, modified source
        # trees and nlohmann transform; upstream baselines remain separate.
        $component.sourceArchives = @($component.sourceArchives) + @($appClosure)
    }
    if ($component.id -cin @('deno', 'ffmpeg', '7zip')) {
        $origins = @($component.sourceArchives)
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
            $origin = @($origins | Where-Object commit -CEQ $component.sourceCommit)[0]
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
