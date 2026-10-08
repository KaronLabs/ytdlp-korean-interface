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
[void][IO.Directory]::CreateDirectory($archives)
$nonRuntime = Join-Path $EvidenceDirectory 'non-runtime-evidence-07'
$inventory = Get-Content -LiteralPath (Join-Path $nonRuntime 'source-cache-inventory.json') -Raw | ConvertFrom-Json -Depth 100
$pending = @('Independent exact-candidate license validation has not run.', 'Packaging metadata has not been sealed into a separate packaging commit.')

# Copy original input files. Identity checks belong to the assembly operation;
# this staging producer does not issue verification or approval verdicts.
foreach ($artifact in $inventory.artifacts) {
    if ($artifact.id -ceq 'application-source') { continue }
    Copy-Item -LiteralPath (Join-Path "$EvidenceDirectory/source-archives" $artifact.fileName) -Destination (Join-Path $archives $artifact.fileName)
}
$official = $lock.release.applicationSource
Copy-Item -LiteralPath $official.localPath -Destination (Join-Path $archives $official.fileName)
$app = @($lock.components | Where-Object id -CEQ 'application')[0]
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
$lock.release.metadataPackage | Add-Member -NotePropertyName packagingCommit -NotePropertyValue $null -Force
$lock.release.metadataPackage.bindingNote = 'Application source base only. Packaging metadata is unsealed and independent validation has not run.'
foreach ($notice in $lock.release.metadataPackage.noticeFiles) {
    $path = Join-Path $RepositoryRoot $notice.path
    $notice.sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $notice.length = (Get-Item -LiteralPath $path).Length
}
$templatePath = Join-Path $OutputDirectory 'source-closure-template.json'
$bytes = $utf8.GetBytes(($lock | ConvertTo-Json -Depth 100) + "`n")
[IO.File]::WriteAllBytes($templatePath, $bytes)
# Refresh the root's untrusted template, never a verified license lock.
[IO.File]::WriteAllBytes($lockPath, $bytes)
[pscustomobject]@{ template = $templatePath; sourceArchives = $archives; verificationStatus = 'NOT_VERIFIED'; licenseApproval = 'HOLD' }
