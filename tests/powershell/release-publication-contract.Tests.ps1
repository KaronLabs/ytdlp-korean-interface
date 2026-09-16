$script:RepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script:PackageTool = Join-Path $script:RepositoryRoot 'tools\package-quality-release.ps1'
$script:PublishTool = Join-Path $script:RepositoryRoot 'tools\publish-quality-release.ps1'
$script:Tag = 'v2.19.1-karon.2'
$script:HeadSha = '0123456789abcdef0123456789abcdef01234567'
$script:TagObjectSha = '89abcdef0123456789abcdef0123456789abcdef'
$script:BinaryName = 'ytdlp-korean-interface-v2.19.1-karon.2-win-x64.zip'
$script:SourcesName = 'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources.zip'
$script:SpdxName = 'ytdlp-korean-interface-v2.19.1-karon.2.spdx.json'
$script:SumsName = 'SHA256SUMS.txt'
$script:AssetNames = @($script:BinaryName, $script:SourcesName, $script:SpdxName, $script:SumsName)
$script:GuiSchemaRepositoryPath = 'release/validation/v2.19.1-karon.2/gui-validation-output.schema.json'
$script:ProducerGuiSchemaFixture = Join-Path $PSScriptRoot 'fixtures\gui-validation-output.schema-e49cc702.json'
$script:ProducerGuiSchemaSha256 = 'e49cc70253bd5dd4b4abd8ee00406f5dd8ed39434e309e3e3c74694b85c1b80e'
$script:SpdxSchemaFixture = Join-Path $PSScriptRoot 'fixtures\spdx-2.3-schema-aadf3b0b.json'
$script:GuiCases = @(
    [pscustomobject]@{ id = 'ko-KR-100'; language = 'ko-KR'; dpi = 100 },
    [pscustomobject]@{ id = 'ko-KR-150'; language = 'ko-KR'; dpi = 150 },
    [pscustomobject]@{ id = 'ko-KR-200'; language = 'ko-KR'; dpi = 200 },
    [pscustomobject]@{ id = 'en-US-100'; language = 'en-US'; dpi = 100 },
    [pscustomobject]@{ id = 'en-US-150'; language = 'en-US'; dpi = 150 },
    [pscustomobject]@{ id = 'en-US-200'; language = 'en-US'; dpi = 200 }
)

if (-not (Test-Path -LiteralPath $script:PackageTool -PathType Leaf) -or
    -not (Test-Path -LiteralPath $script:PublishTool -PathType Leaf)) {
    Describe 'Release packaging and publication production scripts' {
        It 'requires both production scripts before the contract can pass' {
            (Test-Path -LiteralPath $script:PackageTool -PathType Leaf) | Should Be $true
            (Test-Path -LiteralPath $script:PublishTool -PathType Leaf) | Should Be $true
        }
    }
    return
}

. $script:PackageTool
. $script:PublishTool

function Get-TestSha256 {
    param([Parameter(Mandatory)] [string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TestSha1 {
    param([Parameter(Mandatory)] [string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA1).Hash.ToLowerInvariant()
}

function Get-TestSpdxFileId {
    param([Parameter(Mandatory)] [string] $RelativePath)
    $bytes = [Text.Encoding]::UTF8.GetBytes($RelativePath)
    'SPDXRef-File-' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant().Substring(0, 20)
}

function Invoke-TestGit {
    param([Parameter(Mandatory)] [string] $Repository, [Parameter(Mandatory)] [string[]] $Arguments)
    $output = @(& git -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('test_git_failed: git ' + ($Arguments -join ' ') + ': ' + (($output | Out-String).Trim())) }
    (($output | Out-String).Trim())
}

function Commit-TestRepository {
    param([Parameter(Mandatory)] [object] $Case, [string] $Message = 'fixture update')
    [void](Invoke-TestGit $Case.Repository @('add', '--', 'src/application-source.txt', 'THIRD-PARTY-NOTICES.txt', 'release/dependencies/v2.19.1-karon.2.lock.json', 'release/licenses/v2.19.1-karon.2', 'release/notes/v2.19.1-karon.2.md', $script:GuiSchemaRepositoryPath, 'tests/powershell/fixtures/spdx-2.3-schema-aadf3b0b.json'))
    $pending = & git -C $Case.Repository diff --cached --quiet
    if ($LASTEXITCODE -ne 0) { [void](Invoke-TestGit $Case.Repository @('commit', '-q', '-m', $Message)) }
    [string](Invoke-TestGit $Case.Repository @('rev-parse', 'HEAD'))
}

function Write-TestUtf8 {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent) }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Write-TestJson {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [object] $Value)
    Write-TestUtf8 $Path (($Value | ConvertTo-Json -Depth 64) + [char]10)
}

function New-TestZip {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [hashtable] $Entries)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { [void](New-Item -ItemType Directory -Path $parent) }
    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::Open($Path, 'CreateNew', 'ReadWrite', 'None')
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, 'Create', $true)
        try {
            foreach ($name in @($Entries.Keys | Sort-Object -CaseSensitive)) {
                $entry = $zip.CreateEntry($name, 'Optimal')
                $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $input = [IO.File]::OpenRead([string]$Entries[$name])
                $output = $entry.Open()
                try { $input.CopyTo($output) }
                finally {
                    $input.Dispose()
                    $output.Dispose()
                }
            }
        }
        finally { $zip.Dispose() }
    }
    finally { $stream.Dispose() }
}

function New-TestHashRecord {
    param([string] $Path, [string] $Name, [string] $NameField = 'fileName')
    $record = [ordered]@{}
    $record[$NameField] = $Name
    $record.length = [long](Get-Item -LiteralPath $Path).Length
    $record.sha256 = Get-TestSha256 $Path
    $record
}

function New-ReleaseContractCase {
    param([Parameter(Mandatory)] [string] $Name)
    $root = Join-Path $TestDrive $Name
    $repository = Join-Path $root 'repository'
    $candidate = Join-Path $root 'candidate'
    $generated = Join-Path $root 'generated'
    $gui = Join-Path $root 'gui'
    $output = Join-Path $root 'output'
    $receipt = Join-Path $root 'private\release-receipt.json'
    foreach ($directory in @($repository, $candidate, $generated, $gui, $output)) { [void](New-Item -ItemType Directory -Path $directory) }

    [void](Invoke-TestGit $repository @('init', '-q'))
    [void](Invoke-TestGit $repository @('config', 'user.email', 'release-contract@example.invalid'))
    [void](Invoke-TestGit $repository @('config', 'user.name', 'Release Contract Test'))
    $applicationSourcePath = Join-Path $repository 'src\application-source.txt'
    Write-TestUtf8 $applicationSourcePath ('sealed application source' + [char]10)
    [void](Invoke-TestGit $repository @('add', '--', 'src/application-source.txt'))
    [void](Invoke-TestGit $repository @('commit', '-q', '-m', 'sealed application source'))
    $applicationSourceCommit = [string](Invoke-TestGit $repository @('rev-parse', 'HEAD^{commit}'))
    $applicationSourceTree = [string](Invoke-TestGit $repository @('rev-parse', 'HEAD^{tree}'))
    $spdxSchemaPath = Join-Path $repository 'tests\powershell\fixtures\spdx-2.3-schema-aadf3b0b.json'
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $spdxSchemaPath))
    [IO.File]::Copy($script:SpdxSchemaFixture, $spdxSchemaPath, $false)

    $appPath = Join-Path $candidate 'ytdlp-interface.exe'
    $ffprobePath = Join-Path $candidate 'ffprobe.exe'
    Write-TestUtf8 $appPath ('sealed application bytes' + [char]10)
    Write-TestUtf8 $ffprobePath ('sealed ffprobe bytes' + [char]10)
    $manifestPath = Join-Path $candidate 'candidate-manifest.json'
    $manifest = [ordered]@{
        schemaVersion = 1
        createdAtUtc = '2026-09-16T00:00:00Z'
        applicationSourceCommit = $applicationSourceCommit
        files = @(
            [ordered]@{ path = 'ffprobe.exe'; sha256 = Get-TestSha256 $ffprobePath; length = [long](Get-Item $ffprobePath).Length },
            [ordered]@{ path = 'ytdlp-interface.exe'; sha256 = Get-TestSha256 $appPath; length = [long](Get-Item $appPath).Length }
        )
    }
    Write-TestJson $manifestPath $manifest

    $noticePath = Join-Path $repository 'THIRD-PARTY-NOTICES.txt'
    $licensePath = Join-Path $repository 'release\licenses\v2.19.1-karon.2\application\LICENSE.txt'
    $notesPath = Join-Path $repository 'release\notes\v2.19.1-karon.2.md'
    Write-TestUtf8 $noticePath ('Verified third-party notices.' + [char]10)
    Write-TestUtf8 $licensePath ('Fixture application license.' + [char]10)
    Write-TestUtf8 $notesPath ('# v2.19.1-karon.2' + [char]10)

    $sourceText = Join-Path $root 'source.txt'
    $sourceArchive = Join-Path $root 'application-source.zip'
    Write-TestUtf8 $sourceText ('source' + [char]10)
    New-TestZip $sourceArchive @{ 'source.txt' = $sourceText }

    $metadata = [ordered]@{
        id = 'release-metadata'
        name = 'Fixture release metadata'
        version = $script:Tag
        licenseExpression = 'CC0-1.0'
        licenseConcluded = 'CC0-1.0'
        sourceCommit = $applicationSourceCommit
        downloadLocation = 'https://github.com/KaronLabs/ytdlp-korean-interface/archive/' + $applicationSourceCommit + '.zip'
    }
    $component = [ordered]@{
        id = 'application'
        name = 'Fixture application'
        version = '1.0.0'
        sourceRepository = 'https://github.com/KaronLabs/ytdlp-korean-interface'
        sourceCommit = $applicationSourceCommit
        licenseExpression = 'MIT'
        verificationStatus = 'verified'
        modified = $true
        noticeFiles = @([ordered]@{
            path = 'release/licenses/v2.19.1-karon.2/application/LICENSE.txt'
            sha256 = Get-TestSha256 $licensePath
        })
        sourceArchives = @([ordered]@{
            fileName = 'application-source.zip'
            commit = $applicationSourceCommit
            url = 'https://github.com/KaronLabs/ytdlp-korean-interface/archive/' + $applicationSourceCommit + '.zip'
            sha256 = Get-TestSha256 $sourceArchive
            length = [long](Get-Item $sourceArchive).Length
            verificationStatus = 'verified'
            blockers = @()
        })
        buildRecipe = 'Build the pinned fixture.'
        blockers = @()
        filesAnalyzed = $true
        licenseConcluded = 'MIT'
    }
    $candidateFiles = @(
        [ordered]@{ path = 'ffprobe.exe'; sha256 = Get-TestSha256 $ffprobePath; package = 'application'; licenseConcluded = 'MIT' },
        [ordered]@{ path = 'ytdlp-interface.exe'; sha256 = Get-TestSha256 $appPath; package = 'application'; licenseConcluded = 'MIT' },
        [ordered]@{ path = 'candidate-manifest.json'; sha256 = Get-TestSha256 $manifestPath; package = 'release-metadata'; licenseConcluded = 'CC0-1.0' }
    )
    $baseLock = [ordered]@{
        schemaVersion = 'karon-license-lock/v2'
        release = [ordered]@{
            tag = $script:Tag
            platform = 'win-x64'
            verificationStatus = 'verified'
            candidateFiles = $candidateFiles
            blockers = @()
            metadataPackage = $metadata
        }
        components = @($component)
    }
    $innerLock = $baseLock | ConvertTo-Json -Depth 64 | ConvertFrom-Json -Depth 64
    $innerLockPath = Join-Path $root 'inner.lock.json'
    Write-TestJson $innerLockPath $innerLock
    $sourcesPath = Join-Path $generated $script:SourcesName
    $sourcePrefix = 'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources/'
    New-TestZip $sourcesPath @{
        ($sourcePrefix + 'release/dependencies/v2.19.1-karon.2.lock.json') = $innerLockPath
        ($sourcePrefix + 'THIRD-PARTY-NOTICES.txt') = $noticePath
        ($sourcePrefix + 'release/licenses/v2.19.1-karon.2/application/LICENSE.txt') = $licensePath
        ($sourcePrefix + 'sources/application/application-source.zip') = $sourceArchive
    }

    $packages = @(
        [ordered]@{
            name = 'Fixture application'
            SPDXID = 'SPDXRef-Package-application'
            versionInfo = '1.0.0'
            downloadLocation = $component.sourceArchives[0].url
            filesAnalyzed = $true
            licenseConcluded = 'MIT'
            licenseDeclared = 'MIT'
            copyrightText = 'Fixture application copyright.'
        },
        [ordered]@{
            name = 'Fixture release metadata'
            SPDXID = 'SPDXRef-Package-release-metadata'
            versionInfo = $script:Tag
            downloadLocation = $metadata.downloadLocation
            filesAnalyzed = $true
            licenseConcluded = 'CC0-1.0'
            licenseDeclared = 'CC0-1.0'
            copyrightText = 'Fixture metadata copyright.'
        }
    )
    $spdxFiles = @()
    $relationships = @(
        [ordered]@{ spdxElementId = 'SPDXRef-DOCUMENT'; relationshipType = 'DESCRIBES'; relatedSpdxElement = 'SPDXRef-Package-application' },
        [ordered]@{ spdxElementId = 'SPDXRef-DOCUMENT'; relationshipType = 'DESCRIBES'; relatedSpdxElement = 'SPDXRef-Package-release-metadata' }
    )
    foreach ($entry in $candidateFiles) {
        $candidatePath = Join-Path $candidate ($entry.path.Replace('/', '\'))
        $fileId = Get-TestSpdxFileId $entry.path
        $spdxFiles += [ordered]@{
            fileName = './' + $entry.path
            SPDXID = $fileId
            checksums = @(
                [ordered]@{ algorithm = 'SHA1'; checksumValue = Get-TestSha1 $candidatePath },
                [ordered]@{ algorithm = 'SHA256'; checksumValue = $entry.sha256 }
            )
            licenseConcluded = $entry.licenseConcluded
            licenseInfoInFiles = @('NOASSERTION')
            copyrightText = 'Fixture file copyright.'
        }
        $relationships += [ordered]@{
            spdxElementId = 'SPDXRef-Package-' + $entry.package
            relationshipType = 'CONTAINS'
            relatedSpdxElement = $fileId
        }
    }
    $spdxPath = Join-Path $generated $script:SpdxName
    $spdx = [ordered]@{
        spdxVersion = 'SPDX-2.3'
        dataLicense = 'CC0-1.0'
        SPDXID = 'SPDXRef-DOCUMENT'
        name = 'ytdlp-korean-interface-v2.19.1-karon.2-win-x64'
        documentNamespace = 'https://github.com/KaronLabs/ytdlp-korean-interface/spdx/v2.19.1-karon.2/' + ('a' * 64)
        creationInfo = [ordered]@{
            created = '2026-09-16T00:00:00Z'
            creators = @('Tool: release-publication-contract.Tests.ps1')
        }
        documentDescribes = @('SPDXRef-Package-application', 'SPDXRef-Package-release-metadata')
        packages = $packages
        files = $spdxFiles
        relationships = $relationships
        hasExtractedLicensingInfos = @()
    }
    Write-TestJson $spdxPath $spdx

    $summaryCases = @()
    $evidenceFiles = @()
    foreach ($case in $script:GuiCases) {
        $artifactRelative = 'cases/' + $case.id + '.json'
        $artifactPath = Join-Path $gui $artifactRelative
        Write-TestUtf8 $artifactPath ('evidence for ' + $case.id + [char]10)
        $summaryCases += [ordered]@{ caseId = $case.id; language = $case.language; dpi = $case.dpi; evidenceFile = $artifactRelative; evidenceSha256 = Get-TestSha256 $artifactPath }
        $evidenceFiles += [ordered]@{ path = $artifactRelative; sha256 = Get-TestSha256 $artifactPath; length = [long](Get-Item $artifactPath).Length }
    }
    $generatedProbes = @()
    foreach ($probe in @(
        [pscustomobject]@{ CaseId = 'ko-KR-100'; Kind = 'video'; Source = 'media/ko-KR-100-video.mp4' },
        [pscustomobject]@{ CaseId = 'en-US-200'; Kind = 'video'; Source = 'media/en-US-200-video.mp4' },
        [pscustomobject]@{ CaseId = 'ko-KR-100'; Kind = 'mp3'; Source = 'media/ko-KR-100-audio.mp3' }
    )) {
        $sourcePath = Join-Path $gui $probe.Source
        Write-TestUtf8 $sourcePath ('source evidence ' + $probe.CaseId + ' ' + $probe.Kind + [char]10)
        $evidenceFiles += [ordered]@{ path = $probe.Source; sha256 = Get-TestSha256 $sourcePath; length = [long](Get-Item $sourcePath).Length }
        $probeRelative = 'probes/' + $probe.CaseId + '-' + $probe.Kind + '.ffprobe.json'
        $probePath = Join-Path $gui $probeRelative
        Write-TestUtf8 $probePath ('{"streams":[]}' + [char]10)
        $generatedProbes += [ordered]@{ caseId = $probe.CaseId; kind = $probe.Kind; sourceEvidencePath = $probe.Source; path = $probeRelative; sha256 = Get-TestSha256 $probePath; length = [long](Get-Item $probePath).Length }
    }
    $guiCandidate = [ordered]@{
        executable = [ordered]@{ fileName = 'ytdlp-interface.exe'; sha256 = Get-TestSha256 $appPath; length = [long](Get-Item $appPath).Length }
        ffprobe = [ordered]@{ fileName = 'ffprobe.exe'; sha256 = Get-TestSha256 $ffprobePath; length = [long](Get-Item $ffprobePath).Length }
        manifest = [ordered]@{ fileName = 'candidate-manifest.json'; sha256 = Get-TestSha256 $manifestPath; length = [long](Get-Item $manifestPath).Length }
    }
    $summaryPath = Join-Path $gui 'gui-validation-summary.json'
    $guiManifestPath = Join-Path $gui 'gui-validation-evidence-manifest.json'
    $summary = [ordered]@{
        schemaVersion = 2
        releaseVersion = $script:Tag
        status = 'PASS'
        candidate = $guiCandidate
        cases = $summaryCases
        fullVideoLifecycleCases = @('ko-KR-100', 'en-US-200')
        representativeChecks = [ordered]@{
            mp3Conversion = @('ko-KR-100')
            settingsSaveRestartRestore = @('ko-KR-150')
            legacySettingsTransition = @('en-US-100')
        }
        generatedProbes = $generatedProbes
        evidenceFileCount = $evidenceFiles.Count
        evidenceManifestFile = 'gui-validation-evidence-manifest.json'
    }
    $guiManifest = [ordered]@{
        schemaVersion = 2
        releaseVersion = $script:Tag
        candidate = $guiCandidate
        evidenceFiles = $evidenceFiles
        generatedProbeFiles = $generatedProbes
    }
    Write-TestJson $summaryPath $summary
    Write-TestJson $guiManifestPath $guiManifest
    $guiSchemaPath = Join-Path $repository ($script:GuiSchemaRepositoryPath.Replace('/', '\'))
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $guiSchemaPath))
    [IO.File]::Copy($script:ProducerGuiSchemaFixture, $guiSchemaPath, $false)
    $guiSchema = Get-Content -Raw $guiSchemaPath | ConvertFrom-Json -Depth 64

    $outerLock = $baseLock | ConvertTo-Json -Depth 64 | ConvertFrom-Json -Depth 64
    $receiptInputs = [ordered]@{
        candidateManifest = New-TestHashRecord $manifestPath 'candidate-manifest.json'
        correspondingSources = New-TestHashRecord $sourcesPath $script:SourcesName
        spdx = New-TestHashRecord $spdxPath $script:SpdxName
        rootThirdPartyNotices = New-TestHashRecord $noticePath 'THIRD-PARTY-NOTICES.txt'
        guiValidationSummary = New-TestHashRecord $summaryPath 'gui-validation-summary.json'
        guiValidationEvidenceManifest = New-TestHashRecord $guiManifestPath 'gui-validation-evidence-manifest.json'
        guiValidationSchema = New-TestHashRecord $guiSchemaPath $script:GuiSchemaRepositoryPath 'path'
        releaseNotes = New-TestHashRecord $notesPath 'release/notes/v2.19.1-karon.2.md' 'path'
    }
    $outerLock.release | Add-Member -MemberType NoteProperty -Name receiptInputs -Value $receiptInputs
    $lockPath = Join-Path $repository 'release\dependencies\v2.19.1-karon.2.lock.json'
    Write-TestJson $lockPath $outerLock
    $case = [pscustomobject]@{
        Root = $root
        Repository = $repository
        Candidate = $candidate
        Generated = $generated
        Gui = $gui
        Output = $output
        ReceiptPath = $receipt
        Lock = $outerLock
        InnerLock = $innerLock
        LockPath = $lockPath
        InnerLockPath = $innerLockPath
        SourcesPath = $sourcesPath
        SpdxPath = $spdxPath
        Summary = $summary
        SummaryPath = $summaryPath
        GuiManifest = $guiManifest
        GuiManifestPath = $guiManifestPath
        GuiSchema = $guiSchema
        GuiSchemaPath = $guiSchemaPath
        NotesPath = $notesPath
        NoticePath = $noticePath
        LicensePath = $licensePath
        SourceArchive = $sourceArchive
        SourcePrefix = $sourcePrefix
        AppPath = $appPath
        FfprobePath = $ffprobePath
        ManifestPath = $manifestPath
        CandidateManifest = $manifest
        Spdx = $spdx
        ApplicationSourceCommit = $applicationSourceCommit
        ApplicationSourceTree = $applicationSourceTree
    }
    [void](Commit-TestRepository $case 'fixture baseline')
    $case
}

function Save-TestLock {
    param([object] $Case)
    Write-TestJson $Case.LockPath $Case.Lock
    [void](Commit-TestRepository $Case 'fixture lock update')
}

function Rebuild-TestCorrespondingSources {
    param([Parameter(Mandatory)] [object] $Case)
    Write-TestJson $Case.InnerLockPath $Case.InnerLock
    if (Test-Path -LiteralPath $Case.SourcesPath) { Remove-Item -LiteralPath $Case.SourcesPath -Force }
    New-TestZip $Case.SourcesPath @{
        ($Case.SourcePrefix + 'release/dependencies/v2.19.1-karon.2.lock.json') = $Case.InnerLockPath
        ($Case.SourcePrefix + 'THIRD-PARTY-NOTICES.txt') = $Case.NoticePath
        ($Case.SourcePrefix + 'release/licenses/v2.19.1-karon.2/application/LICENSE.txt') = $Case.LicensePath
        ($Case.SourcePrefix + 'sources/application/application-source.zip') = $Case.SourceArchive
    }
    Refresh-TestInputRecord $Case 'correspondingSources' $Case.SourcesPath $script:SourcesName
}

function Refresh-TestInputRecord {
    param([object] $Case, [string] $Name, [string] $Path, [string] $DisplayName, [string] $NameField = 'fileName')
    $Case.Lock.release.receiptInputs.$Name = New-TestHashRecord $Path $DisplayName $NameField
    Save-TestLock $Case
}

function Save-TestGuiManifest {
    param([object] $Case)
    Write-TestJson $Case.GuiManifestPath $Case.GuiManifest
    Refresh-TestInputRecord $Case 'guiValidationEvidenceManifest' $Case.GuiManifestPath 'gui-validation-evidence-manifest.json'
}

function Save-TestSummary {
    param([object] $Case)
    Write-TestJson $Case.SummaryPath $Case.Summary
    Refresh-TestInputRecord $Case 'guiValidationSummary' $Case.SummaryPath 'gui-validation-summary.json'
}

function Save-TestSpdx {
    param([object] $Case)
    Write-TestJson $Case.SpdxPath $Case.Spdx
    Refresh-TestInputRecord $Case 'spdx' $Case.SpdxPath $script:SpdxName
}

function Set-TestApplicationSourceCommit {
    param([object] $Case, [string] $Commit)
    $url = 'https://github.com/KaronLabs/ytdlp-korean-interface/archive/' + $Commit + '.zip'
    foreach ($lock in @($Case.Lock, $Case.InnerLock)) {
        $lock.release.metadataPackage.sourceCommit = $Commit
        $lock.release.metadataPackage.downloadLocation = $url
        $lock.components[0].sourceCommit = $Commit
        $lock.components[0].sourceArchives[0].commit = $Commit
        $lock.components[0].sourceArchives[0].url = $url
    }
    ($Case.Spdx.packages | Where-Object SPDXID -ceq 'SPDXRef-Package-application').downloadLocation = $url
    ($Case.Spdx.packages | Where-Object SPDXID -ceq 'SPDXRef-Package-release-metadata').downloadLocation = $url
    Rebuild-TestCorrespondingSources $Case
    Save-TestSpdx $Case
}

function Invoke-TestPackage {
    param([object] $Case, [switch] $PlanOnly)
    $arguments = @{
        RepositoryRoot = $Case.Repository
        CandidateDirectory = $Case.Candidate
        LockPath = $Case.LockPath
        CorrespondingSourcesPath = $Case.SourcesPath
        SpdxPath = $Case.SpdxPath
        GuiValidationSummaryPath = $Case.SummaryPath
        GuiValidationEvidenceManifestPath = $Case.GuiManifestPath
        OutputDirectory = $Case.Output
        ReceiptPath = $Case.ReceiptPath
        PlanOnly = $PlanOnly
    }
    Invoke-QualityReleasePackage @arguments
}

function Get-TestFailure {
    param([scriptblock] $Action)
    try {
        & $Action | Out-Null
        'test_expected_failure_but_action_succeeded'
    }
    catch { $_.Exception.Message }
}

function New-PackagedPublicationCase {
    param([string] $Name)
    $case = New-ReleaseContractCase $Name
    [void](Invoke-TestPackage $case)
    $case
}

function New-FakePublicationRunner {
    param([object] $Case, [hashtable] $Options = @{})
    $receipt = Get-Content -Raw -LiteralPath $Case.ReceiptPath | ConvertFrom-Json -Depth 32
    $state = @{
        Origin = 'git@github.com:KaronLabs/ytdlp-korean-interface.git'
        PushOrigin = 'git@github.com:KaronLabs/ytdlp-korean-interface.git'
        Dirty = ''
        Head = [string]$receipt.packagingCommit
        RemoteHead = [string]$receipt.packagingCommit
        TagType = 'tag'
        TagObject = $script:TagObjectSha
        TagTarget = [string]$receipt.packagingCommit
        RemoteTagObject = $script:TagObjectSha
        RemoteTagTarget = [string]$receipt.packagingCommit
        NotesBlob = [string]$receipt.releaseNotes.gitBlobSha1
        Stage = 'absent'
        DigestMode = 'null'
        MainRaceAt = 0
        TagRaceAt = 0
        MainChecks = 0
        TagChecks = 0
        DownloadMismatch = $false
        DownloadCount = 0
        ReleaseId = 424242
        ReleaseIdRaceAt = 0
        ReleaseQueries = 0
        MissingReleaseId = $false
        TagNameAsArray = $false
        DuplicateTagKey = $false
        ReleaseTitle = $script:Tag
        ReleaseBody = [IO.File]::ReadAllText($Case.NotesPath, [Text.UTF8Encoding]::new($false, $true))
        AssetIdRaceAt = 0
    }
    foreach ($key in $Options.Keys) { $state[$key] = $Options[$key] }
    $calls = [Collections.Generic.List[object]]::new()
    $assetDirectory = $Case.Output
    $tag = $script:Tag
    $assetNames = @($script:AssetNames)
    $binaryName = $script:BinaryName
    $runner = {
        param([string] $Executable, [string[]] $Arguments, [string] $WorkingDirectory)
        $calls.Add([pscustomobject]@{ Executable = $Executable; Arguments = @($Arguments); WorkingDirectory = $WorkingDirectory })
        $key = $Executable + '|' + ($Arguments -join '|')
        $ok = { param([string] $Output = '') [pscustomobject]@{ ExitCode = 0; Output = $Output } }
        $fail = { param([string] $Output) [pscustomobject]@{ ExitCode = 1; Output = $Output } }
        if ($key -ceq 'git|remote|get-url|origin') { return & $ok $state.Origin }
        if ($key -ceq 'git|remote|get-url|--push|origin') { return & $ok $state.PushOrigin }
        if ($key -ceq 'git|status|--porcelain=v1|--untracked-files=all') { return & $ok $state.Dirty }
        if ($key -ceq 'git|rev-parse|--verify|HEAD^{commit}') { return & $ok $state.Head }
        if ($key -ceq 'git|ls-remote|origin|refs/heads/main') {
            $state.MainChecks++
            $value = if ($state.MainRaceAt -eq $state.MainChecks) { 'f' * 40 } else { $state.RemoteHead }
            return & $ok ($value + [char]9 + 'refs/heads/main')
        }
        if ($key -ceq ('git|cat-file|-t|refs/tags/' + $tag)) { return & $ok $state.TagType }
        if ($key -ceq ('git|rev-parse|refs/tags/' + $tag)) { return & $ok $state.TagObject }
        if ($key -ceq ('git|rev-parse|refs/tags/' + $tag + '^{}')) { return & $ok $state.TagTarget }
        if ($key -ceq ('git|ls-remote|origin|refs/tags/' + $tag + '|refs/tags/' + $tag + '^{}')) {
            $state.TagChecks++
            $object = if ($state.TagRaceAt -eq $state.TagChecks) { 'e' * 40 } else { $state.RemoteTagObject }
            $text = $object + [char]9 + 'refs/tags/' + $tag + [char]10
            $text += $state.RemoteTagTarget + [char]9 + 'refs/tags/' + $tag + '^{}'
            return & $ok $text
        }
        if ($key -ceq 'git|ls-tree|HEAD|--|release/notes/v2.19.1-karon.2.md') {
            return & $ok ('100644 blob ' + $state.NotesBlob + [char]9 + 'release/notes/v2.19.1-karon.2.md')
        }
        if ($key -ceq 'gh|auth|status|--hostname|github.com') { return & $ok 'authenticated' }
        $apiKey = 'gh|api|--method|GET|repos/KaronLabs/ytdlp-korean-interface/releases/tags/' + $tag
        if ($key -ceq $apiKey) {
            if ($state.Stage -ceq 'absent') { return & $fail 'gh: Not Found (HTTP 404)' }
            $state.ReleaseQueries++
            $assets = @()
            if ($state.Stage -ceq 'draft-assets' -or $state.Stage -ceq 'stable') {
                foreach ($name in $assetNames) {
                    $path = Join-Path $assetDirectory $name
                    $digest = $null
                    if ($state.DigestMode -ceq 'match') { $digest = 'sha256:' + (Get-TestSha256 $path) }
                    if ($state.DigestMode -ceq 'mismatch' -and $name -ceq $binaryName) { $digest = 'sha256:' + ('f' * 64) }
                    $assetId = 7000 + $assets.Count
                    if ($state.AssetIdRaceAt -eq $state.ReleaseQueries -and $assets.Count -eq 0) { $assetId += 1000 }
                    $assets += [ordered]@{ id = $assetId; name = $name; size = [long](Get-Item $path).Length; state = 'uploaded'; digest = $digest }
                }
            }
            $releaseId = if ($state.ReleaseIdRaceAt -eq $state.ReleaseQueries) { [long]$state.ReleaseId + 1L } else { [long]$state.ReleaseId }
            $release = [ordered]@{
                id = $releaseId
                tag_name = $tag
                name = [string]$state.ReleaseTitle
                body = [string]$state.ReleaseBody
                draft = ($state.Stage -ne 'stable')
                prerelease = $false
                assets = $assets
            }
            if ($state.MissingReleaseId) { $release.Remove('id') }
            $json = $release | ConvertTo-Json -Depth 8 -Compress
            if ($state.TagNameAsArray) {
                $json = $json.Replace(('"tag_name":"' + $tag + '"'), ('"tag_name":["' + $tag + '"]'))
            }
            if ($state.DuplicateTagKey) { $json = $json -replace '"tag_name":', '"TAG_NAME":"duplicate","tag_name":' }
            return & $ok $json
        }
        if ($Executable -ceq 'gh' -and $Arguments.Count -ge 3 -and $Arguments[0] -ceq 'release' -and $Arguments[1] -ceq 'create') {
            if ($state.Stage -cne 'absent') { return & $fail 'release already exists' }
            $state.Stage = 'draft-empty'
            return & $ok 'draft created'
        }
        if ($Executable -ceq 'gh' -and $Arguments.Count -ge 3 -and $Arguments[0] -ceq 'release' -and $Arguments[1] -ceq 'upload') {
            if ($state.Stage -cne 'draft-empty') { return & $fail 'upload state invalid' }
            $state.Stage = 'draft-assets'
            return & $ok 'uploaded'
        }
        if ($Executable -ceq 'gh' -and $Arguments.Count -ge 9 -and $Arguments[0] -ceq 'release' -and $Arguments[1] -ceq 'download') {
            $name = [string]$Arguments[6]
            $directory = [string]$Arguments[8]
            [IO.File]::Copy((Join-Path $assetDirectory $name), (Join-Path $directory $name), $false)
            $state.DownloadCount++
            if ($state.DownloadMismatch -and $state.DownloadCount -eq 1) {
                $path = Join-Path $directory $name
                $bytes = [IO.File]::ReadAllBytes($path)
                $bytes[0] = $bytes[0] -bxor 1
                [IO.File]::WriteAllBytes($path, $bytes)
            }
            return & $ok 'downloaded'
        }
        if ($Executable -ceq 'gh' -and $Arguments.Count -eq 6 -and $Arguments[0] -ceq 'api' -and
            $Arguments[1] -ceq '--method' -and $Arguments[2] -ceq 'PATCH' -and
            $Arguments[3] -ceq ('repos/KaronLabs/ytdlp-korean-interface/releases/' + [string]$state.ReleaseId) -and
            $Arguments[4] -ceq '--field') {
            if ($Arguments[5] -ceq 'draft=false') { $state.Stage = 'stable'; return & $ok 'published' }
            if ($Arguments[5] -ceq 'draft=true') { $state.Stage = 'draft-assets'; return & $ok 'draft restored' }
        }
        if ($Executable -ceq 'gh' -and $Arguments.Count -ge 5 -and $Arguments[0] -ceq 'release' -and $Arguments[1] -ceq 'edit') {
            if ($Arguments -contains '--draft=false') { $state.Stage = 'stable'; return & $ok 'published' }
            if ($Arguments -contains '--draft') { $state.Stage = 'draft-assets'; return & $ok 'draft restored' }
        }
        [pscustomobject]@{ ExitCode = 99; Output = 'unexpected command: ' + $key }
    }.GetNewClosure()
    [pscustomobject]@{ Runner = $runner; Calls = $calls; State = $state }
}

function Invoke-TestPublication {
    param([object] $Case, [object] $Fake, [switch] $PlanOnly, [string] $NotesPath)
    if ([string]::IsNullOrWhiteSpace($NotesPath)) { $NotesPath = $Case.NotesPath }
    $arguments = @{
        RepositoryRoot = $Case.Repository
        AssetDirectory = $Case.Output
        ReleaseNotesPath = $NotesPath
        ReceiptPath = $Case.ReceiptPath
        CommandRunner = $Fake.Runner
        PlanOnly = $PlanOnly
    }
    Invoke-QualityReleasePublication @arguments
}

Describe 'Single production publication entry point' {
    It 'does not expose the legacy publication function or direct stable command builder' {
        ($null -eq (Get-Command Invoke-QualityReleasePublicationLegacy -ErrorAction SilentlyContinue)) | Should Be $true
        ($null -eq (Get-Command Get-KaronPublishCommandPlan -ErrorAction SilentlyContinue)) | Should Be $true
    }

    It 'contains no latest flag and every release create literal is draft-first' {
        $text = [IO.File]::ReadAllText($script:PublishTool)
        $text | Should Not Match '(?i)--latest'
        $text | Should Not Match "(?i)'release'\s*,\s*'edit'"
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($script:PublishTool, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should Be 0
        $createFunctions = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Extent.Text -match "'release'\s*,\s*'create'"
        }, $true))
        $createFunctions.Count | Should Be 1
        $createFunctions[0].Extent.Text | Should Match '(?i)--verify-tag'
        $createFunctions[0].Extent.Text | Should Match '(?i)--draft'
        $createFunctions[0].Extent.Text | Should Not Match '(?i)--latest'
    }
}

Describe 'Independent immutable provenance anchors' {
    It 'writes application and packaging anchors without an overloaded sourceCommit' {
        $case = New-PackagedPublicationCase 'provenance-receipt-shape'
        $receipt = Get-Content -Raw $case.ReceiptPath | ConvertFrom-Json -Depth 32
        (@($receipt.PSObject.Properties.Name) -contains 'applicationSourceCommit') | Should Be $true
        (@($receipt.PSObject.Properties.Name) -contains 'applicationSourceTree') | Should Be $true
        (@($receipt.PSObject.Properties.Name) -contains 'packagingCommit') | Should Be $true
        (@($receipt.PSObject.Properties.Name) -contains 'sourceCommit') | Should Be $false
        $receipt.applicationSourceCommit | Should Be $case.ApplicationSourceCommit
        $receipt.applicationSourceTree | Should Be $case.ApplicationSourceTree
        $receipt.packagingCommit | Should Not Be $receipt.applicationSourceCommit
    }

    It 'rejects application source substitution independently of packaging HEAD' {
        $case = New-ReleaseContractCase 'provenance-application-substitution'
        Set-TestApplicationSourceCommit $case ('b' * 40)
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_application_source_mismatch'
    }

    It 'rejects an application lock that self-references the packaging commit' {
        $case = New-ReleaseContractCase 'provenance-self-reference'
        $packagingCommit = 'b' * 40
        $case.Lock.release.metadataPackage.sourceCommit = $packagingCommit
        $case.Lock.components[0].sourceCommit = $packagingCommit
        $entries = Get-KaronPackageCandidateEntries $case.Lock $case.Candidate
        (Get-TestFailure {
            Get-KaronPackageApplicationProvenance $case.Lock $entries $case.Repository $packagingCommit
        }) | Should Match 'package_provenance_self_reference'
    }

    It 'rejects equality confusion in a private receipt' {
        $case = New-PackagedPublicationCase 'provenance-equality-confusion'
        $receipt = Get-Content -Raw $case.ReceiptPath | ConvertFrom-Json -Depth 32
        $packagingCommit = [string]$receipt.packagingCommit
        $packagingTree = [string](Invoke-TestGit $case.Repository @('rev-parse', 'HEAD^{tree}'))
        $receipt.applicationSourceCommit = $packagingCommit
        $receipt.applicationSourceTree = $packagingTree
        Write-TestJson $case.ReceiptPath $receipt
        $fake = New-FakePublicationRunner $case
        (Get-TestFailure { Invoke-TestPublication $case $fake -PlanOnly }) | Should Match 'package_receipt_provenance_confused'
        $fake.Calls.Count | Should Be 0
    }

    It 'rejects a stale receipt after packaging HEAD advances' {
        $case = New-PackagedPublicationCase 'provenance-stale-receipt'
        Write-TestUtf8 (Join-Path $case.Repository 'contract-revision.txt') ('new packaging commit' + [char]10)
        [void](Invoke-TestGit $case.Repository @('add', '--', 'contract-revision.txt'))
        [void](Invoke-TestGit $case.Repository @('commit', '-q', '-m', 'advance packaging contract'))
        $fake = New-FakePublicationRunner $case
        (Get-TestFailure { Invoke-TestPublication $case $fake -PlanOnly }) | Should Match 'package_receipt_packaging_commit_mismatch'
        $fake.Calls.Count | Should Be 0
    }
}

Describe 'GUI evidence byte allowlist' {
    It 'rejects missing, extra, and same-length substituted GUI evidence bytes' -TestCases @(
        @{ Name = 'missing'; Mutate = { param($case) Remove-Item -LiteralPath (Join-Path $case.Gui $case.GuiManifest.evidenceFiles[0].path) } },
        @{ Name = 'extra'; Mutate = { param($case) Write-TestUtf8 (Join-Path $case.Gui 'cases/undeclared.json') ('undeclared' + [char]10) } },
        @{ Name = 'same-length'; Mutate = { param($case) $path = Join-Path $case.Gui $case.GuiManifest.evidenceFiles[0].path; $bytes = [IO.File]::ReadAllBytes($path); $bytes[0] = $bytes[0] -bxor 1; [IO.File]::WriteAllBytes($path, $bytes) } }
    ) {
        param($Name, $Mutate)
        $case = New-ReleaseContractCase ('gui-evidence-' + $Name)
        & $Mutate $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_gui_evidence_'
    }

    It 'rejects case-fold and NFC-colliding GUI evidence records' -TestCases @(
        @{ Name = 'case-fold'; Mutate = {
            param($case)
            $record = $case.GuiManifest.evidenceFiles[0]
            $case.GuiManifest.evidenceFiles += [ordered]@{ path = $record.path.ToUpperInvariant(); sha256 = $record.sha256; length = $record.length }
        } },
        @{ Name = 'nfc'; Mutate = {
            param($case)
            $composed = 'cases/caf' + [char]0x00E9 + '.json'
            $decomposed = 'cases/cafe' + [char]0x0301 + '.json'
            foreach ($relative in @($composed, $decomposed)) {
                $path = Join-Path $case.Gui $relative
                Write-TestUtf8 $path ('unicode evidence' + [char]10)
                $case.GuiManifest.evidenceFiles += [ordered]@{ path = $relative; sha256 = Get-TestSha256 $path; length = [long](Get-Item $path).Length }
            }
        } }
    ) {
        param($Name, $Mutate)
        $case = New-ReleaseContractCase ('gui-evidence-collision-' + $Name)
        & $Mutate $case
        $case.Summary.evidenceFileCount = $case.GuiManifest.evidenceFiles.Count
        Save-TestGuiManifest $case
        Save-TestSummary $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_gui_(manifest_invalid|evidence_inventory_invalid)'
    }
}

Describe 'Pinned SPDX and LicenseRef enforcement' {
    It 'pins the exact canonical producer GUI schema fixture' {
        (Get-TestSha256 $script:ProducerGuiSchemaFixture) | Should Be $script:ProducerGuiSchemaSha256
    }

    It 'rejects SPDX documents missing official 2.3 required evidence' -TestCases @(
        @{ Name = 'creation-info'; Mutate = { param($case) [void]$case.Spdx.Remove('creationInfo') } },
        @{ Name = 'package-copyright'; Mutate = { param($case) [void]$case.Spdx.packages[0].Remove('copyrightText') } },
        @{ Name = 'file-copyright'; Mutate = { param($case) [void]$case.Spdx.files[0].Remove('copyrightText') } }
    ) {
        param($Name, $Mutate)
        $case = New-ReleaseContractCase ('spdx-required-' + $Name)
        & $Mutate $case
        Save-TestSpdx $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_spdx_schema_invalid'
    }

    It 'rejects a LicenseRef notice hidden in dot-git and absent from component noticeFiles' {
        $case = New-ReleaseContractCase 'license-ref-rogue-git'
        $roguePath = Join-Path $case.Repository '.git\rogue-license.txt'
        Write-TestUtf8 $roguePath ('rogue license text' + [char]10)
        foreach ($lock in @($case.Lock, $case.InnerLock)) {
            $component = $lock.components[0]
            $component.licenseExpression = 'LicenseRef-Rogue'
            $component.licenseConcluded = 'LicenseRef-Rogue'
            $component | Add-Member NoteProperty licenseRefs @([ordered]@{
                licenseId = 'LicenseRef-Rogue'
                name = 'Rogue license'
                noticePath = '.git/rogue-license.txt'
            }) -Force
        }
        $package = $case.Spdx.packages | Where-Object SPDXID -ceq 'SPDXRef-Package-application'
        $package.licenseDeclared = 'LicenseRef-Rogue'
        $package.licenseConcluded = 'LicenseRef-Rogue'
        $case.Spdx.hasExtractedLicensingInfos = @([ordered]@{
            licenseId = 'LicenseRef-Rogue'
            name = 'Rogue license'
            extractedText = [IO.File]::ReadAllText($roguePath, [Text.UTF8Encoding]::new($false, $true))
        })
        Rebuild-TestCorrespondingSources $case
        Save-TestSpdx $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_license_ref_notice_invalid'
    }
}

Describe 'Canonical producer GUI schema handshake' {
    It 'rejects the legacy no-blob schema identity' {
        $case = New-ReleaseContractCase 'gui-schema-legacy-id'
        $case.GuiSchema.'$id' = 'https://github.com/KaronLabs/ytdlp-korean-interface/release/validation/v2.19.1-karon.2/gui-validation-output.schema.json'
        Write-TestJson $case.GuiSchemaPath $case.GuiSchema
        Refresh-TestInputRecord $case 'guiValidationSchema' $case.GuiSchemaPath $script:GuiSchemaRepositoryPath 'path'
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_gui_schema_(lock_mismatch|identity_invalid)'
    }

    It 'accepts producer $defs.evidenceManifest without the stale $defs.manifest alias' {
        $case = New-ReleaseContractCase 'gui-schema-producer-integration'
        [IO.File]::Copy($script:ProducerGuiSchemaFixture, $case.GuiSchemaPath, $true)
        Refresh-TestInputRecord $case 'guiValidationSchema' $case.GuiSchemaPath $script:GuiSchemaRepositoryPath 'path'
        $result = Invoke-TestPackage $case -PlanOnly
        $result.Mode | Should Be 'plan'
    }
}

Describe 'Exact package, GUI evidence, and receipt contract' {
    It 'packages exact public assets and creates a non-public bound receipt' {
        $case = New-ReleaseContractCase 'package-positive'
        $result = Invoke-TestPackage $case
        @($result.AssetPaths).Count | Should Be 4
        (Test-Path -LiteralPath $case.ReceiptPath -PathType Leaf) | Should Be $true
        @(Get-ChildItem -LiteralPath $case.Output -File).Count | Should Be 4
        @((Get-Content -Raw $case.ReceiptPath | ConvertFrom-Json).guiCaseIds).Count | Should Be 6
        $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $case.Output $script:BinaryName))
        try { $names = @($zip.Entries | ForEach-Object FullName) }
        finally { $zip.Dispose() }
        ($names -join '|') | Should Be 'THIRD-PARTY-NOTICES.txt|candidate-manifest.json|ffprobe.exe|release/licenses/v2.19.1-karon.2/application/LICENSE.txt|ytdlp-interface.exe'
    }

    It 'rejects an unverified release and nonempty blockers' -TestCases @(
        @{ Name = 'status'; Mutate = { param($case) $case.Lock.release.verificationStatus = 'NOT_VERIFIED' } },
        @{ Name = 'blocker'; Mutate = { param($case) $case.Lock.release.blockers = @('blocked') } }
    ) {
        param($Name, $Mutate)
        $case = New-ReleaseContractCase ('package-release-' + $Name)
        & $Mutate $case
        Save-TestLock $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_'
        @(Get-ChildItem $case.Output -Force).Count | Should Be 0
    }

    It 'rejects array-valued release and source statuses before PowerShell coercion' -TestCases @(
        @{ Name = 'release'; Mutate = { param($case) $case.Lock.release.verificationStatus = @('verified') } },
        @{ Name = 'source'; Mutate = { param($case) $case.Lock.components[0].sourceArchives[0].verificationStatus = @('verified') } }
    ) {
        param($Name, $Mutate)
        $case = New-ReleaseContractCase ('package-array-' + $Name)
        & $Mutate $case
        Save-TestLock $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_lock_type_invalid'
    }

    It 'rejects zero GUI evidence and incomplete six-case inventory' -TestCases @(
        @{ Name = 'zero'; Mutate = { param($case) $case.GuiManifest.evidenceFiles = @(); Save-TestGuiManifest $case } },
        @{ Name = 'five'; Mutate = { param($case) $case.Summary.cases = @($case.Summary.cases | Select-Object -First 5); Save-TestSummary $case } }
    ) {
        param($Name, $Mutate)
        $case = New-ReleaseContractCase ('package-gui-' + $Name)
        & $Mutate $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_gui_'
    }

    It 'rejects GUI evidence bound to a different candidate executable' {
        $case = New-ReleaseContractCase 'package-gui-candidate'
        $case.Summary.candidate.executable.sha256 = 'f' * 64
        Save-TestSummary $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_gui_candidate_mismatch'
    }

    It 'rejects the deprecated string-v1 flat GUI evidence contract' {
        $case = New-ReleaseContractCase 'package-gui-v1'
        $oldCases = @()
        $oldManifestCases = @()
        foreach ($old in @(
            [pscustomobject]@{ id = 'gui-en-US-100'; language = 'en-US'; dpi = 100 },
            [pscustomobject]@{ id = 'gui-en-US-150'; language = 'en-US'; dpi = 150 },
            [pscustomobject]@{ id = 'gui-en-US-200'; language = 'en-US'; dpi = 200 },
            [pscustomobject]@{ id = 'gui-ko-KR-100'; language = 'ko-KR'; dpi = 100 },
            [pscustomobject]@{ id = 'gui-ko-KR-150'; language = 'ko-KR'; dpi = 150 },
            [pscustomobject]@{ id = 'gui-ko-KR-200'; language = 'ko-KR'; dpi = 200 }
        )) {
            $artifact = $case.GuiManifest.evidenceFiles | Select-Object -First 1
            $oldCases += [ordered]@{ id = $old.id; language = $old.language; dpiPercent = $old.dpi; status = 'verified'; evidenceId = $old.id }
            $oldManifestCases += [ordered]@{ id = $old.id; status = 'verified'; artifacts = @($artifact) }
        }
        $flat = [ordered]@{ fileName = 'ytdlp-interface.exe'; length = [long](Get-Item $case.AppPath).Length; sha256 = Get-TestSha256 $case.AppPath }
        $case.Summary = [ordered]@{ schemaVersion = 'karon-gui-validation-summary/v1'; tag = $script:Tag; status = 'verified'; blockers = @(); candidate = $flat; cases = $oldCases }
        $case.GuiManifest = [ordered]@{ schemaVersion = 'karon-gui-validation-evidence-manifest/v1'; tag = $script:Tag; status = 'verified'; blockers = @(); candidate = $flat; cases = $oldManifestCases }
        Save-TestSummary $case
        Save-TestGuiManifest $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_gui_'
    }

    It 'rejects producer schema divergence even when the changed schema is tracked and lock-bound' {
        $case = New-ReleaseContractCase 'package-gui-schema-divergence'
        $case.GuiSchema.'$id' = 'https://github.com/KaronLabs/ytdlp-korean-interface/blob/v2.19.1-karon.other/release/validation/v2.19.1-karon.2/gui-validation-output.schema.json'
        Write-TestJson $case.GuiSchemaPath $case.GuiSchema
        Refresh-TestInputRecord $case 'guiValidationSchema' $case.GuiSchemaPath $script:GuiSchemaRepositoryPath 'path'
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_gui_'
    }

    It 'rejects undeclared v2 GUI properties and a string schema version' -TestCases @(
        @{ Name = 'extra'; Mutate = { param($case) $case.Summary.obsolete = $true } },
        @{ Name = 'string-version'; Mutate = { param($case) $case.Summary.schemaVersion = '2' } }
    ) {
        param($Name, $Mutate)
        $case = New-ReleaseContractCase ('package-gui-closed-' + $Name)
        & $Mutate $case
        Save-TestSummary $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_gui_'
    }

    It 'rejects a plain-text corresponding-sources impostor after lock rebinding' {
        $case = New-ReleaseContractCase 'package-fake-sources'
        [IO.File]::WriteAllText($case.SourcesPath, 'not a zip', [Text.Encoding]::ASCII)
        Refresh-TestInputRecord $case 'correspondingSources' $case.SourcesPath $script:SourcesName
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_sources_zip_invalid'
    }

    It 'rejects a source ZIP without its internal dependency manifest' {
        $case = New-ReleaseContractCase 'package-source-manifest-missing'
        Remove-Item -LiteralPath $case.SourcesPath
        New-TestZip $case.SourcesPath @{
            ($case.SourcePrefix + 'THIRD-PARTY-NOTICES.txt') = $case.NoticePath
        }
        Refresh-TestInputRecord $case 'correspondingSources' $case.SourcesPath $script:SourcesName
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_sources_manifest_missing'
    }

    It 'rejects any canonical inner and outer lock projection mismatch' {
        $case = New-ReleaseContractCase 'package-inner-outer-mismatch'
        $case.InnerLock.components[0].version = '2.0.0'
        Rebuild-TestCorrespondingSources $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_sources_manifest_mismatch'
    }

    It 'rejects a declared nested source archive that is not a real ZIP' {
        $case = New-ReleaseContractCase 'package-fake-inner-archive'
        Write-TestUtf8 $case.SourceArchive 'plain text posing as a source archive'
        foreach ($lock in @($case.Lock, $case.InnerLock)) {
            $lock.components[0].sourceArchives[0].sha256 = Get-TestSha256 $case.SourceArchive
            $lock.components[0].sourceArchives[0].length = [long](Get-Item $case.SourceArchive).Length
        }
        Rebuild-TestCorrespondingSources $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_source_archive_invalid'
    }

    It 'rejects plain-text and wrong-identity SPDX impostors' -TestCases @(
        @{ Name = 'text'; Mutate = { param($case) Write-TestUtf8 $case.SpdxPath 'SPDX-2.3' } },
        @{ Name = 'identity'; Mutate = { param($case) $value = Get-Content -Raw $case.SpdxPath | ConvertFrom-Json; $value.spdxVersion = 'SPDX-2.2'; Write-TestJson $case.SpdxPath $value } }
    ) {
        param($Name, $Mutate)
        $case = New-ReleaseContractCase ('package-spdx-' + $Name)
        & $Mutate $case
        Refresh-TestInputRecord $case 'spdx' $case.SpdxPath $script:SpdxName
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_spdx_'
    }

    It 'rejects an SPDX package license contradicting the verified lock' {
        $case = New-ReleaseContractCase 'package-spdx-license-mismatch'
        $spdx = Get-Content -Raw $case.SpdxPath | ConvertFrom-Json -Depth 64
        $spdx.packages[0].licenseDeclared = 'GPL-3.0-only'
        Write-TestJson $case.SpdxPath $spdx
        Refresh-TestInputRecord $case 'spdx' $case.SpdxPath $script:SpdxName
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_spdx_package_contract_mismatch'
    }

    It 'rejects the lock from an arbitrary external path even when bytes are identical' {
        $case = New-ReleaseContractCase 'package-external-lock'
        $externalLock = Join-Path $case.Root 'external-lock.json'
        [IO.File]::Copy($case.LockPath, $externalLock)
        $failure = Get-TestFailure {
            Invoke-QualityReleasePackage -RepositoryRoot $case.Repository -CandidateDirectory $case.Candidate `
                -LockPath $externalLock -CorrespondingSourcesPath $case.SourcesPath -SpdxPath $case.SpdxPath `
                -GuiValidationSummaryPath $case.SummaryPath -GuiValidationEvidenceManifestPath $case.GuiManifestPath `
                -OutputDirectory $case.Output -ReceiptPath $case.ReceiptPath
        }
        $failure | Should Match 'package_lock_path_invalid'
    }

    It 'rejects a semantically unchanged working-tree lock whose tracked blob changed' {
        $case = New-ReleaseContractCase 'package-lock-working-tree-change'
        [IO.File]::AppendAllText($case.LockPath, ' ', [Text.UTF8Encoding]::new($false))
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_tracked_blob_mismatch'
    }

    It 'rejects a repository reached through an ancestor junction' {
        $case = New-ReleaseContractCase 'package-ancestor-junction'
        $alias = Join-Path $case.Root 'repository-junction'
        [void](New-Item -ItemType Junction -Path $alias -Target $case.Repository)
        $aliasLock = Join-Path $alias 'release\dependencies\v2.19.1-karon.2.lock.json'
        $failure = Get-TestFailure {
            Invoke-QualityReleasePackage -RepositoryRoot $alias -CandidateDirectory $case.Candidate `
                -LockPath $aliasLock -CorrespondingSourcesPath $case.SourcesPath -SpdxPath $case.SpdxPath `
                -GuiValidationSummaryPath $case.SummaryPath -GuiValidationEvidenceManifestPath $case.GuiManifestPath `
                -OutputDirectory $case.Output -ReceiptPath $case.ReceiptPath
        }
        $failure | Should Match 'package_path_reparse_point'
    }

    It 'rejects a same-length root notice substitution despite outer lock rebinding' {
        $case = New-ReleaseContractCase 'package-root-notice-swap'
        $bytes = [IO.File]::ReadAllBytes($case.NoticePath)
        $bytes[0] = $bytes[0] -bxor 1
        [IO.File]::WriteAllBytes($case.NoticePath, $bytes)
        Refresh-TestInputRecord $case 'rootThirdPartyNotices' $case.NoticePath 'THIRD-PARTY-NOTICES.txt'
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_sources_entry_hash_mismatch'
    }

    It 'rejects unlisted and duplicate-case candidate paths' -TestCases @(
        @{ Name = 'extra'; Mutate = { param($case) Write-TestUtf8 (Join-Path $case.Candidate 'extra.dll') 'extra' } },
        @{ Name = 'case'; Mutate = { param($case) $case.Lock.release.candidateFiles += [ordered]@{ path = 'FFPROBE.EXE'; sha256 = Get-TestSha256 $case.FfprobePath; package = 'application'; licenseConcluded = 'MIT' }; Save-TestLock $case } }
    ) {
        param($Name, $Mutate)
        $case = New-ReleaseContractCase ('package-candidate-' + $Name)
        & $Mutate $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_candidate_'
    }

    It 'preserves an independent producers final file on an atomic move race' {
        $case = New-ReleaseContractCase 'package-output-race'
        $partial = Join-Path $case.Output 'owned.partial'
        $final = Join-Path $case.Output $script:BinaryName
        Write-TestUtf8 $partial 'owned'
        Write-TestUtf8 $final 'independent'
        $before = Get-TestSha256 $final
        (Get-TestFailure { Move-KaronPackageOwnedArtifact $partial $final }) | Should Match 'package_output_race'
        (Get-TestSha256 $final) | Should Be $before
    }
}

Describe 'Fail-closed publication preflight and receipt checks' {
    It 'rejects missing or extra public assets before external commands' -TestCases @(
        @{ Name = 'missing'; Mutate = { param($case) Remove-Item (Join-Path $case.Output $script:SpdxName) } },
        @{ Name = 'extra'; Mutate = { param($case) Write-TestUtf8 (Join-Path $case.Output 'extra.bin') 'extra' } }
    ) {
        param($Name, $Mutate)
        $case = New-PackagedPublicationCase ('publish-assets-' + $Name)
        & $Mutate $case
        $fake = New-FakePublicationRunner $case
        (Get-TestFailure { Invoke-TestPublication $case $fake -PlanOnly }) | Should Match 'package_'
        $fake.Calls.Count | Should Be 0
    }

    It 'rejects checksum mismatch and same-length asset swaps through the receipt' -TestCases @(
        @{ Name = 'checksum'; Mutate = { param($case) [IO.File]::AppendAllText((Join-Path $case.Output $script:SpdxName), 'x') } },
        @{ Name = 'same-length'; Mutate = { param($case) $path = Join-Path $case.Output $script:BinaryName; $bytes = [IO.File]::ReadAllBytes($path); $bytes[0] = $bytes[0] -bxor 1; [IO.File]::WriteAllBytes($path, $bytes) } }
    ) {
        param($Name, $Mutate)
        $case = New-PackagedPublicationCase ('publish-tamper-' + $Name)
        & $Mutate $case
        $fake = New-FakePublicationRunner $case
        (Get-TestFailure { Invoke-TestPublication $case $fake -PlanOnly }) | Should Match 'package_receipt_'
        $fake.Calls.Count | Should Be 0
    }

    It 'rejects receipt tampering before external commands' {
        $case = New-PackagedPublicationCase 'publish-receipt-tamper'
        $receipt = Get-Content -Raw $case.ReceiptPath | ConvertFrom-Json -Depth 32
        $receipt.packagingCommit = 'f' * 40
        Write-TestJson $case.ReceiptPath $receipt
        $fake = New-FakePublicationRunner $case
        (Get-TestFailure { Invoke-TestPublication $case $fake -PlanOnly }) | Should Match 'package_receipt_packaging_commit_mismatch'
        $fake.Calls.Count | Should Be 0
    }

    It 'rejects external release notes even when their bytes match' {
        $case = New-PackagedPublicationCase 'publish-external-notes'
        $outside = Join-Path $case.Root 'outside.md'
        [IO.File]::Copy($case.NotesPath, $outside)
        $fake = New-FakePublicationRunner $case
        (Get-TestFailure { Invoke-TestPublication $case $fake -PlanOnly -NotesPath $outside }) | Should Match 'publication_notes_invalid'
        $fake.Calls.Count | Should Be 0
    }

    It 'rejects wrong origin, dirty state, wrong main, and tag mismatch' -TestCases @(
        @{ Name = 'origin'; Options = @{ Origin = 'https://github.com/KaronLabs/ytdlp-korean-interface.git' }; Error = 'publication_origin_mismatch' },
        @{ Name = 'dirty'; Options = @{ Dirty = ' M tools/file.ps1' }; Error = 'publication_tree_dirty' },
        @{ Name = 'main'; Options = @{ RemoteHead = '3' * 40 }; Error = 'publication_main_sha_mismatch' },
        @{ Name = 'tag'; Options = @{ TagTarget = '4' * 40 }; Error = 'publication_tag_target_mismatch' }
    ) {
        param($Name, $Options, $Error)
        $case = New-PackagedPublicationCase ('publish-preflight-' + $Name)
        $fake = New-FakePublicationRunner $case $Options
        (Get-TestFailure { Invoke-TestPublication $case $fake -PlanOnly }) | Should Match $Error
    }

    It 'rejects an existing release without clobbering karon.1 or its assets' {
        $case = New-PackagedPublicationCase 'publish-existing'
        $fake = New-FakePublicationRunner $case @{ Stage = 'draft-assets' }
        (Get-TestFailure { Invoke-TestPublication $case $fake -PlanOnly }) | Should Match 'publication_release_exists'
        (@($fake.Calls | ForEach-Object { $_.Arguments -join ' ' }) -join '|') | Should Not Match 'karon\.1|--clobber|--force'
    }
}

Describe 'Draft-first publication, redownload proof, and race gates' {
    It 'returns the exact draft, upload, four download, and publish command order' {
        $case = New-PackagedPublicationCase 'publish-plan'
        $fake = New-FakePublicationRunner $case
        $result = Invoke-TestPublication $case $fake -PlanOnly
        $result.Mode | Should Be 'plan'
        @($result.Commands).Count | Should Be 7
        ($result.Commands[0].Arguments -join '|') | Should Be ('release|create|' + $script:Tag + '|--repo|KaronLabs/ytdlp-korean-interface|--title|' + $script:Tag + '|--notes-file|' + [IO.Path]::GetFullPath($case.NotesPath) + '|--verify-tag|--draft')
        $result.Commands[1].Arguments[0] | Should Be 'release'
        $result.Commands[1].Arguments[1] | Should Be 'upload'
        for ($index = 0; $index -lt 4; $index++) {
            $command = $result.Commands[$index + 2]
            $command.Arguments[1] | Should Be 'download'
            $command.Arguments[5] | Should Be '--pattern'
            $command.Arguments[6] | Should Be $script:AssetNames[$index]
            ($command.Arguments -contains '--clobber') | Should Be $false
        }
        @($result.Commands[2..5] | ForEach-Object { $_.Arguments[8] } | Select-Object -Unique).Count | Should Be 1
        ($result.Commands[6].Arguments -join '|') | Should Be 'api|--method|PATCH|repos/KaronLabs/ytdlp-korean-interface/releases/{sealed-release-id}|--field|draft=false'
        (@($fake.Calls | Where-Object { $_.Executable -ceq 'gh' -and $_.Arguments[0] -ceq 'release' })).Count | Should Be 0
    }

    It 'publishes only after four exact draft redownload hashes succeed with null API digests' {
        $case = New-PackagedPublicationCase 'publish-positive'
        $fake = New-FakePublicationRunner $case @{ DigestMode = 'null' }
        $result = Invoke-TestPublication $case $fake
        $result.Mode | Should Be 'published'
        $result.RedownloadsVerified | Should Be 4
        $fake.State.Stage | Should Be 'stable'
        $releaseCalls = @($fake.Calls | Where-Object { $_.Executable -ceq 'gh' -and $_.Arguments[0] -ceq 'release' })
        ($releaseCalls | ForEach-Object { $_.Arguments[1] } | Where-Object { $_ -ceq 'download' }).Count | Should Be 4
        (@($releaseCalls | Where-Object { $_.Arguments[1] -ceq 'verify-asset' })).Count | Should Be 0
        $allCalls = [object[]]@($fake.Calls)
        $publishIndex = [Array]::FindIndex($allCalls, [Predicate[object]]{ param($call) $call.Executable -ceq 'gh' -and $call.Arguments[0] -ceq 'api' -and $call.Arguments -contains 'draft=false' })
        $lastDownloadIndex = [Array]::FindLastIndex($allCalls, [Predicate[object]]{ param($call) $call.Executable -ceq 'gh' -and $call.Arguments[0] -ceq 'release' -and $call.Arguments[1] -ceq 'download' })
        ($publishIndex -gt $lastDownloadIndex) | Should Be $true
        $fake.State.ReleaseQueries | Should BeGreaterThan 8
    }

    It 'rejects a missing or recreated GitHub release identity' -TestCases @(
        @{ Name = 'missing'; Options = @{ MissingReleaseId = $true } },
        @{ Name = 'recreated'; Options = @{ ReleaseIdRaceAt = 2 } }
    ) {
        param($Name, $Options)
        $case = New-PackagedPublicationCase ('publish-release-id-' + $Name)
        $fake = New-FakePublicationRunner $case $Options
        (Get-TestFailure { Invoke-TestPublication $case $fake }) | Should Match 'publication_release_'
        $fake.State.Stage | Should Match '^draft-'
    }

    It 'rejects array-valued tag_name before PowerShell coercion' {
        $case = New-PackagedPublicationCase 'publish-array-tag-name'
        $fake = New-FakePublicationRunner $case @{ TagNameAsArray = $true }
        (Get-TestFailure { Invoke-TestPublication $case $fake }) | Should Match 'publication_release_json_invalid'
        $fake.State.Stage | Should Match '^draft-'
    }

    It 'rejects release title or body drift while preserving draft state' -TestCases @(
        @{ Name = 'title'; Options = @{ ReleaseTitle = 'recreated title' } },
        @{ Name = 'body'; Options = @{ ReleaseBody = 'recreated body' } }
    ) {
        param($Name, $Options)
        $case = New-PackagedPublicationCase ('publish-release-metadata-' + $Name)
        $fake = New-FakePublicationRunner $case $Options
        (Get-TestFailure { Invoke-TestPublication $case $fake }) | Should Match 'publication_release_'
        $fake.State.Stage | Should Match '^draft-'
    }

    It 'leaves the release draft when a redownload hash differs' {
        $case = New-PackagedPublicationCase 'publish-redownload-mismatch'
        $fake = New-FakePublicationRunner $case @{ DownloadMismatch = $true }
        (Get-TestFailure { Invoke-TestPublication $case $fake }) | Should Match 'publication_redownload_mismatch'
        $fake.State.Stage | Should Be 'draft-assets'
    }

    It 'leaves the release draft when GitHub exposes a mismatching digest' {
        $case = New-PackagedPublicationCase 'publish-digest-mismatch'
        $fake = New-FakePublicationRunner $case @{ DigestMode = 'mismatch' }
        (Get-TestFailure { Invoke-TestPublication $case $fake }) | Should Match 'publication_remote_digest_mismatch'
        $fake.State.Stage | Should Be 'draft-assets'
    }

    It 'fails before create on a remote main or tag race' -TestCases @(
        @{ Name = 'main'; Options = @{ MainRaceAt = 2 } },
        @{ Name = 'tag'; Options = @{ TagRaceAt = 2 } }
    ) {
        param($Name, $Options)
        $case = New-PackagedPublicationCase ('publish-precreate-race-' + $Name)
        $fake = New-FakePublicationRunner $case $Options
        (Get-TestFailure { Invoke-TestPublication $case $fake }) | Should Match 'publication_'
        $fake.State.Stage | Should Be 'absent'
    }

    It 'keeps draft on a main or tag race after upload' -TestCases @(
        @{ Name = 'main'; Options = @{ MainRaceAt = 4 } },
        @{ Name = 'tag'; Options = @{ TagRaceAt = 4 } }
    ) {
        param($Name, $Options)
        $case = New-PackagedPublicationCase ('publish-postupload-race-' + $Name)
        $fake = New-FakePublicationRunner $case $Options
        (Get-TestFailure { Invoke-TestPublication $case $fake }) | Should Match 'publication_'
        $fake.State.Stage | Should Be 'draft-assets'
    }

    It 'rolls a stable transition back to draft if the final ref recheck races' {
        $case = New-PackagedPublicationCase 'publish-poststable-race'
        $fake = New-FakePublicationRunner $case @{ MainRaceAt = 7 }
        (Get-TestFailure { Invoke-TestPublication $case $fake }) | Should Match 'publication_'
        $fake.State.Stage | Should Be 'draft-assets'
        (@($fake.Calls | Where-Object {
            $_.Executable -ceq 'gh' -and $_.Arguments[0] -ceq 'api' -and
            $_.Arguments[2] -ceq 'PATCH' -and $_.Arguments -contains 'draft=true'
        })).Count | Should Be 1
    }

    It 'seals every numeric remote asset id after upload' -TestCases @(
        @{ Name = 'post-upload'; Query = 4 },
        @{ Name = 'mid-redownload'; Query = 7 },
        @{ Name = 'post-stable'; Query = 10 }
    ) {
        param($Name, $Query)
        $case = New-PackagedPublicationCase ('publish-asset-id-race-' + $Name)
        $fake = New-FakePublicationRunner $case @{ AssetIdRaceAt = $Query }
        (Get-TestFailure { Invoke-TestPublication $case $fake }) | Should Match 'publication_remote_asset_identity_mismatch'
        $fake.State.Stage | Should Be 'draft-assets'
    }

    It 'uses one fresh verification directory for all four pre-stable downloads' {
        $case = New-PackagedPublicationCase 'publish-single-verification-directory'
        $fake = New-FakePublicationRunner $case
        $plan = Invoke-TestPublication $case $fake -PlanOnly
        $directories = @($plan.Commands | Where-Object Name -like 'download-*' | ForEach-Object { [string]$_.Arguments[8] } | Select-Object -Unique)
        $directories.Count | Should Be 1
        [IO.Path]::GetFileName($directories[0]) | Should Match '^karon-release-verify-[a-f0-9]{32}$'
    }

    It 'targets stable mutation by sealed numeric release id and never by tag' {
        $case = New-PackagedPublicationCase 'publish-numeric-id-mutation'
        $fake = New-FakePublicationRunner $case
        [void](Invoke-TestPublication $case $fake)
        $patches = @($fake.Calls | Where-Object {
            $_.Executable -ceq 'gh' -and $_.Arguments[0] -ceq 'api' -and $_.Arguments[2] -ceq 'PATCH'
        })
        $patches.Count | Should Be 1
        ($patches[0].Arguments -join '|') | Should Be 'api|--method|PATCH|repos/KaronLabs/ytdlp-korean-interface/releases/424242|--field|draft=false'
        (@($fake.Calls | Where-Object {
            $_.Executable -ceq 'gh' -and $_.Arguments[0] -ceq 'release' -and $_.Arguments[1] -ceq 'edit'
        })).Count | Should Be 0
    }
}
