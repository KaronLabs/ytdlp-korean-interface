$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:Builder = Join-Path $script:RepositoryRoot 'tools\build-release-license-lock.ps1'
$script:SourcesConsumer = Join-Path $script:RepositoryRoot 'tools\build-corresponding-sources.ps1'
$script:SpdxConsumer = Join-Path $script:RepositoryRoot 'tools\generate-release-spdx.ps1'
$script:PackageConsumer = Join-Path $script:RepositoryRoot 'tools\package-quality-release.ps1'
$script:Utf8 = New-Object Text.UTF8Encoding($false)
$script:Tag = 'v2.19.1-karon.2'
$script:ApprovedDenoCollectorCommit = '09ced74a90248fbeb54969ea03d5aacb98dfc38b'

function Write-TestText {
    param([string] $Path, [string] $Text)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, $script:Utf8)
}

function Write-TestJson {
    param([string] $Path, [object] $Value)
    Write-TestText $Path (($Value | ConvertTo-Json -Depth 100) + "`n")
}

function Read-TestJson {
    param([string] $Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-TestSha256 {
    param([string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TestRecord {
    param([string] $Path, [string] $Name = '')
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = Split-Path -Leaf $Path }
    [ordered]@{ fileName = $Name; length = [long](Get-Item -LiteralPath $Path).Length; sha256 = Get-TestSha256 $Path }
}

function New-TestZip {
    param([string] $Path, [Collections.IDictionary] $Entries, [switch] $NoCompression)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        try {
            foreach ($name in @($Entries.Keys | Sort-Object)) {
                $level = if ($NoCompression) { [IO.Compression.CompressionLevel]::NoCompression } else { [IO.Compression.CompressionLevel]::Optimal }
                $entry = $archive.CreateEntry(([string]$name).Replace('\', '/'), $level)
                $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $input = [IO.File]::OpenRead([string]$Entries[$name])
                $output = $entry.Open()
                try { $input.CopyTo($output) }
                finally { $output.Dispose(); $input.Dispose() }
            }
        }
        finally { $archive.Dispose() }
    }
    finally { $stream.Dispose() }
}

function New-TestComponent {
    param(
        [string] $Id,
        [string] $Version,
        [string] $Commit,
        [string] $License,
        [string] $NoticePath,
        [string] $NoticeSha,
        [string] $ArchivePath
    )
    $record = Get-TestRecord $ArchivePath
    [ordered]@{
        id = $Id
        name = $Id
        version = $Version
        sourceRepository = 'https://example.test/' + $Id
        sourceCommit = $Commit
        licenseExpression = $License
        modified = $false
        filesAnalyzed = $true
        buildRecipe = 'synthetic fixture'
        licenseConcluded = $License
        verificationStatus = 'NOT_VERIFIED'
        blockers = @('stale-template-is-not-authority')
        noticeFiles = @([ordered]@{ path = $NoticePath; sha256 = $NoticeSha })
        sourceArchives = @([ordered]@{
            fileName = $record.fileName
            commit = $Commit
            url = 'https://example.test/archive/' + $Commit + '.zip'
            length = $record.length
            sha256 = $record.sha256
            verificationStatus = 'NOT_VERIFIED'
            blockers = @('stale-template-is-not-authority')
        })
    }
}

function New-TestFixture {
    param(
        [string] $Name,
        [switch] $DenoCaseCollision
    )
    $root = Join-Path $TestDrive $Name
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $repo = Join-Path $root 'repository'
    [IO.Directory]::CreateDirectory($repo) | Out-Null
    & git -c core.autocrlf=false -C $repo init -q
    Write-TestText (Join-Path $repo 'application.txt') "application source`n"
    Write-TestText (Join-Path $repo 'THIRD-PARTY-NOTICES.txt') "root third-party notices`n"
    $spdxSchemaTarget = Join-Path $repo 'tests\powershell\fixtures\spdx-2.3-schema-aadf3b0b.json'
    [IO.Directory]::CreateDirectory((Split-Path -Parent $spdxSchemaTarget)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'tests\powershell\fixtures\spdx-2.3-schema-aadf3b0b.json') -Destination $spdxSchemaTarget
    & git -c core.autocrlf=false -C $repo add -- application.txt THIRD-PARTY-NOTICES.txt tests/powershell/fixtures/spdx-2.3-schema-aadf3b0b.json
    & git -c core.autocrlf=false -c user.name='Karon Test' -c user.email='karon-test@example.invalid' -C $repo commit -q -m application
    $applicationCommit = ((& git -C $repo rev-parse HEAD) | Out-String).Trim().ToLowerInvariant()
    $applicationTree = ((& git -C $repo rev-parse 'HEAD^{tree}') | Out-String).Trim().ToLowerInvariant()

    $candidate = Join-Path $root 'candidate'
    [IO.Directory]::CreateDirectory($candidate) | Out-Null
    $candidatePayloads = [ordered]@{
        '7z.dll' = 'sevenzip dll no rar handlers'
        'deno.exe' = 'deno runtime'
        'ffmpeg.exe' = 'ffmpeg lgpl runtime'
        'ffprobe.exe' = 'ffprobe lgpl runtime'
        'yt-dlp.exe' = 'yt-dlp runtime'
        'ytdlp-interface.exe' = 'karon application executable'
    }
    foreach ($name in $candidatePayloads.Keys) { Write-TestText (Join-Path $candidate $name) ([string]$candidatePayloads[$name]) }
    $candidateFiles = @()
    foreach ($name in @($candidatePayloads.Keys | Sort-Object)) {
        $path = Join-Path $candidate $name
        $candidateFiles += [ordered]@{ path = $name; length = [long](Get-Item $path).Length; sha256 = Get-TestSha256 $path }
    }
    $candidateManifestPath = Join-Path $candidate 'candidate-manifest.json'
    $candidateManifest = [ordered]@{
        schemaVersion = 1
        createdAtUtc = '2026-09-16T00:00:00.000Z'
        applicationSourceCommit = $applicationCommit
        applicationSourceTree = $applicationTree
        attestation = [ordered]@{ source = [ordered]@{ commit = $applicationCommit; treeSha256 = ('a' * 64); trackedFileCount = 1; dirty = $false } }
        versions = [ordered]@{ product = '2.19.1-karon.2'; ytdlp = '2026.09.11'; ffmpeg = 'n9.0.1'; ffprobe = 'n9.0.1'; deno = '2.7.14' }
        files = $candidateFiles
    }
    Write-TestJson $candidateManifestPath $candidateManifest

    $cache = Join-Path $root 'source-cache'
    [IO.Directory]::CreateDirectory($cache) | Out-Null
    $applicationSource = Join-Path $cache 'application-source.zip'
    $sevenZipSource = Join-Path $cache '7z2601-x64-no-rar-source.7z'
    $sevenZipConsumerSource = Join-Path $cache '7z2601-x64-no-rar-source.zip'
    $ytDlpSource = Join-Path $cache 'yt-dlp-source.zip'
    $applicationSourcePayload = Join-Path $root 'source-payloads\application.txt'
    $ytDlpSourcePayload = Join-Path $root 'source-payloads\yt-dlp.txt'
    Write-TestText $applicationSourcePayload 'application corresponding source'
    Write-TestText $ytDlpSourcePayload 'yt-dlp corresponding source'
    New-TestZip $applicationSource ([ordered]@{ 'application.txt' = $applicationSourcePayload })
    Write-TestText $sevenZipSource 'sevenzip corresponding source without rar paths'
    New-TestZip $sevenZipConsumerSource ([ordered]@{ 'sevenzip/7z2601-x64-no-rar-source.7z' = $sevenZipSource }) -NoCompression
    New-TestZip $ytDlpSource ([ordered]@{ 'yt-dlp.txt' = $ytDlpSourcePayload })

    $denoOutputRoot = Join-Path $root 'deno'
    [IO.Directory]::CreateDirectory((Join-Path $denoOutputRoot 'bundle')) | Out-Null
    $denoNotices = Join-Path $denoOutputRoot 'THIRD-PARTY-NOTICES.txt'
    $denoLicense = Join-Path $root 'source-payloads\deno-license.txt'
    Write-TestText $denoNotices "Deno third-party notices`n"
    Write-TestText $denoLicense "MIT license`n"
    $denoSources = Join-Path $denoOutputRoot 'deno-2.7.14-verified-conservative-superset-sources.zip'
    if ($DenoCaseCollision) {
        New-TestCaseCollisionZip -OutputPath $denoSources -Entries @(
            [pscustomobject]@{ Path = 'LICENSES/A.TXT'; Source = $denoLicense },
            [pscustomobject]@{ Path = 'LICENSES/a.txt'; Source = $denoLicense },
            [pscustomobject]@{ Path = 'THIRD-PARTY-NOTICES.txt'; Source = $denoNotices }
        )
    }
    else {
        New-TestZip $denoSources ([ordered]@{
            'LICENSES/a.txt' = $denoLicense
            'THIRD-PARTY-NOTICES.txt' = $denoNotices
        })
    }
    $denoCacheSources = Join-Path $cache (Split-Path -Leaf $denoSources)
    Copy-Item -LiteralPath $denoSources -Destination $denoCacheSources
    $denoInventoryPath = Join-Path $denoOutputRoot 'source-inventory.json'
    $denoInventoryFiles = @(
        [ordered]@{ path = 'LICENSES/a.txt'; length = [long](Get-Item $denoLicense).Length; sha256 = Get-TestSha256 $denoLicense },
        [ordered]@{ path = 'THIRD-PARTY-NOTICES.txt'; length = [long](Get-Item $denoNotices).Length; sha256 = Get-TestSha256 $denoNotices }
    )
    if ($DenoCaseCollision) {
        $denoInventoryFiles = @(
            [ordered]@{ path = 'LICENSES/A.TXT'; length = [long](Get-Item $denoLicense).Length; sha256 = Get-TestSha256 $denoLicense }
        ) + $denoInventoryFiles
    }
    $serialized = (($denoInventoryFiles | ForEach-Object { $_.path + '|' + $_.length + '|' + $_.sha256 }) -join "`n") + "`n"
    $digestBytes = $script:Utf8.GetBytes($serialized)
    $digest = [Security.Cryptography.SHA256]::Create()
    try { $treeDigest = ([BitConverter]::ToString($digest.ComputeHash($digestBytes))).Replace('-', '').ToLowerInvariant() }
    finally { $digest.Dispose() }
    Write-TestJson $denoInventoryPath ([ordered]@{
        schemaVersion = 'deno-source-inventory/v2'
        canonicalTreeDigest = [ordered]@{
            algorithm = 'SHA-256'
            serialization = 'path|length|lowercase-sha256 followed by LF per record including trailing LF'
            recordCount = $denoInventoryFiles.Count
            sha256 = $treeDigest
        }
        files = $denoInventoryFiles
    })
    $denoComponentPath = Join-Path $denoOutputRoot 'component-manifest.json'
    Write-TestJson $denoComponentPath ([ordered]@{
        schemaVersion = 'deno-third-party-components/v3'
        closureClassification = 'verified-conservative-superset'
        releaseIdentity = [ordered]@{ version = '2.7.14'; target = 'x86_64-pc-windows-msvc'; sha256 = Get-TestSha256 (Join-Path $candidate 'deno.exe') }
        counts = [ordered]@{ cargoLockPackages = 1; resolvedRegistryPackages = 1; workspacePackages = 1; resolvedWorkspacePackages = 1; nativeComponents = 1; embeddedComponents = 1 }
        embeddedComponents = @([ordered]@{ name = 'fixture'; licenseExpression = 'MIT' })
        crates = @([ordered]@{ name = 'fixture'; classification = 'SPDX' })
        workspacePackages = @([ordered]@{ name = 'fixture'; classification = 'SPDX' })
        nativeGitTreeEvidence = [ordered]@{ commit = ('3' * 40); tree = ('4' * 40); gitlinks = @() }
        nativeComponents = @([ordered]@{ name = 'fixture'; classification = 'SPDX' })
        overallReleasePass = $false
    })
    $denoRunEvidencePath = Join-Path $root 'g6-run-evidence.json'
    Write-TestJson $denoRunEvidencePath ([ordered]@{
        exitCode = 0
        elapsedMilliseconds = 1
        elapsed = '00:00:00.0010000'
        result = [ordered]@{
            status = 'complete'
            closureClassification = 'verified-conservative-superset'
            outputRoot = $denoOutputRoot
            noticePath = $denoNotices
            noticeSha256 = Get-TestSha256 $denoNotices
            zipPath = $denoSources
            zipSha256 = Get-TestSha256 $denoSources
            canonicalTreeSha256 = $treeDigest
            counts = [ordered]@{ cargoLockPackages = 1; resolvedRegistryPackages = 1; workspacePackages = 1; resolvedWorkspacePackages = 1; nativeComponents = 1; embeddedComponents = 1 }
            overallReleasePass = $false
        }
        error = $null
    })

    $ffmpegBuildConf = Join-Path $root 'ffmpeg\buildconf.txt'
    $ffmpegNotice = Join-Path $root 'ffmpeg\NOTICE.md'
    Write-TestText $ffmpegBuildConf "--enable-shared`n--disable-gpl`n--disable-nonfree`n"
    Write-TestText $ffmpegNotice "LGPL-2.1-or-later`n"
    $ffmpegSources = Join-Path $cache 'ffmpeg-corresponding-sources.zip'
    New-TestZip $ffmpegSources ([ordered]@{ 'NOTICE.md' = $ffmpegNotice; 'buildconf.txt' = $ffmpegBuildConf })
    $ffmpegManifestPath = Join-Path $root 'ffmpeg\manifest.json'
    Write-TestJson $ffmpegManifestPath ([ordered]@{
        schemaVersion = 3
        release = $script:Tag
        closureStatus = 'complete'
        binary = [ordered]@{
            repository = 'BtbN/FFmpeg-Builds'; releaseTag = 'fixture'; assetId = 1
            archiveName = 'ffmpeg-fixture-win64-lgpl-9.0.zip'; archiveSha256 = ('5' * 64)
            ffmpegSha256 = Get-TestSha256 (Join-Path $candidate 'ffmpeg.exe')
            ffprobeSha256 = Get-TestSha256 (Join-Path $candidate 'ffprobe.exe')
            expectedVersion = 'fixture'; ffmpegCommit = ('6' * 40); buildConfigurationPath = 'buildconf.txt'
        }
        provenance = [ordered]@{ builderCommit = ('7' * 40) }
        sourceSets = [ordered]@{}
        includedPaths = @('NOTICE.md', 'buildconf.txt')
        enabledExternalLibraries = @()
        unresolvedItems = @()
        verifiedSourceRecordCount = 2
        closurePolicy = 'verified-conservative-superset'
        counts = [ordered]@{ directSourceArchives = 2; btbnCacheArchives = 0; rav1eCrates = 0; toolchainSourceArchives = 0; totalSourceArchives = 2; licenseTextObjects = 1; licenseFileReferences = 1; nestedSubmoduleArchives = 0 }
    })

    $sevenZipRuntime = Join-Path $root 'sevenzip\sevenzip-runtime.7z'
    Write-TestText $sevenZipRuntime 'runtime archive containing only x64/7z.dll and LGPL notices'
    $sevenZipVerification = Join-Path $root 'sevenzip\verification.json'
    Write-TestJson $sevenZipVerification ([ordered]@{
        runtimeArchive = 'sevenzip-runtime.7z'
        runtimeArchiveSha256 = Get-TestSha256 $sevenZipRuntime
        dllSha256 = Get-TestSha256 (Join-Path $candidate '7z.dll')
        correspondingSourceArchive = 'sevenzip-no-rar-source.7z'
        correspondingSourceArchiveSha256 = Get-TestSha256 $sevenZipSource
        hostPath = '7z.exe'
        hostSha256 = ('8' * 64)
        fileVersion = '26.01'
        runtime = [ordered]@{ infoExitCode = 0; zipExitCode = 0; sevenZipExitCode = 0; rarHandlerCount = 0 }
        archiveCommands = @([ordered]@{ exitCode = 0 }, [ordered]@{ exitCode = 0 })
    })

    $nonRuntimeManifestPath = Join-Path $root 'non-runtime\component-manifest.json'
    $sourceArtifacts = [ordered]@{
        application = [ordered]@{ id = 'application-source'; fileName = (Split-Path -Leaf $applicationSource); sha256 = Get-TestSha256 $applicationSource; length = [long](Get-Item $applicationSource).Length; includeInBundle = $true }
        '7zip' = [ordered]@{ id = 'sevenzip-source'; fileName = (Split-Path -Leaf $sevenZipSource); sha256 = Get-TestSha256 $sevenZipSource; length = [long](Get-Item $sevenZipSource).Length; includeInBundle = $true }
        'yt-dlp' = [ordered]@{ id = 'yt-dlp-source'; fileName = (Split-Path -Leaf $ytDlpSource); sha256 = Get-TestSha256 $ytDlpSource; length = [long](Get-Item $ytDlpSource).Length; includeInBundle = $true }
    }
    $nonRuntimeComponents = @()
    foreach ($spec in @(
        @('application', '2.19.1-karon.2', $applicationCommit, 'MIT', 'ytdlp-interface.exe'),
        @('7zip', '26.01', ('1' * 40), 'LGPL-2.1-or-later', '7z.dll'),
        @('yt-dlp', '2026.09.11', ('2' * 40), 'Unlicense', 'yt-dlp.exe')
    )) {
        $boundPath = Join-Path $candidate $spec[4]
        $nonRuntimeComponents += [ordered]@{
            id = $spec[0]; name = $spec[0]; version = $spec[1]; sourceRepository = 'https://example.test/' + $spec[0]
            sourceCommit = $spec[2]; licenseExpression = $spec[3]; modified = $false; buildRecipe = 'synthetic fixture'
            sourceArtifacts = @($sourceArtifacts[$spec[0]])
            candidateBinding = [ordered]@{ files = @([ordered]@{ path = $spec[4]; length = [long](Get-Item $boundPath).Length; sha256 = Get-TestSha256 $boundPath }) }
        }
    }
    $task5 = [ordered]@{
        format = '7z'; runtimeArchiveSha256 = Get-TestSha256 $sevenZipRuntime; runtimeArchiveLength = [long](Get-Item $sevenZipRuntime).Length
        sourceArchiveSha256 = Get-TestSha256 $sevenZipSource; sourceArchiveLength = [long](Get-Item $sevenZipSource).Length
        verificationSha256 = Get-TestSha256 $sevenZipVerification; verificationLength = [long](Get-Item $sevenZipVerification).Length
        dllSha256 = Get-TestSha256 (Join-Path $candidate '7z.dll'); dllLength = [long](Get-Item (Join-Path $candidate '7z.dll')).Length
        forbiddenPattern = '(?i)rar'; requiredObjects = @('7z.obj'); excludedObjects = @('RarHandler.obj'); sourceExclusions = @('CPP/7zip/Archive/Rar')
    }
    Write-TestJson $nonRuntimeManifestPath ([ordered]@{
        schemaVersion = 'karon-non-runtime-component-evidence/v1'
        release = $script:Tag
        approvalProfile = 'karon-v2.19.1-karon.2-non-runtime-v1'
        expectedComponentCount = 3
        sharedInputs = [ordered]@{ sevenZipTask5 = $task5 }
        components = $nonRuntimeComponents
    })
    $nonRuntimeInventoryPath = Join-Path $root 'non-runtime\source-cache-inventory.json'
    $inventoryArtifacts = @()
    foreach ($artifact in $sourceArtifacts.Values) {
        $inventoryArtifacts += [ordered]@{ id = $artifact.id; fileName = $artifact.fileName; length = $artifact.length; sha256 = $artifact.sha256; status = 'verified' }
    }
    Write-TestJson $nonRuntimeInventoryPath ([ordered]@{
        schemaVersion = 'karon-source-cache-inventory/v1'; release = $script:Tag; scope = 'non-ffmpeg-non-deno'; status = 'closed'
        approvalProfile = 'karon-v2.19.1-karon.2-non-runtime-v1'; manifestSha256 = Get-TestSha256 $nonRuntimeManifestPath
        manifestProjectionSha256 = ('9' * 64); applicationCommit = $applicationCommit
        candidateManifestSha256 = Get-TestSha256 $candidateManifestPath; candidateManifestLength = [long](Get-Item $candidateManifestPath).Length
        sevenZipTask5 = [ordered]@{ runtimeArchiveSha256 = Get-TestSha256 $sevenZipRuntime; sourceArchiveSha256 = Get-TestSha256 $sevenZipSource; verificationSha256 = Get-TestSha256 $sevenZipVerification }
        artifacts = $inventoryArtifacts
        blockers = @(); unclassifiedFiles = @()
    })
    $nonRuntimeBundle = Join-Path $root 'non-runtime\non-runtime-evidence.zip'
    New-TestZip $nonRuntimeBundle ([ordered]@{
        'component-manifest.json' = $nonRuntimeManifestPath
        'source-cache-inventory.json' = $nonRuntimeInventoryPath
        'evidence/candidate-manifest.json' = $candidateManifestPath
        ('evidence/task5/' + (Split-Path -Leaf $sevenZipRuntime)) = $sevenZipRuntime
        ('evidence/task5/' + (Split-Path -Leaf $sevenZipSource)) = $sevenZipSource
        ('evidence/task5/' + (Split-Path -Leaf $sevenZipVerification)) = $sevenZipVerification
        ('sources/' + (Split-Path -Leaf $applicationSource)) = $applicationSource
        ('sources/' + (Split-Path -Leaf $sevenZipSource)) = $sevenZipSource
        ('sources/' + (Split-Path -Leaf $ytDlpSource)) = $ytDlpSource
    })

    $guiRoot = Join-Path $root 'gui'
    $guiSummary = Join-Path $guiRoot 'gui-validation-summary.json'
    $guiEvidence = Join-Path $guiRoot 'gui-validation-evidence-manifest.json'
    $guiSchema = Join-Path $root 'repository\release\validation\v2.19.1-karon.2\gui-validation-output.schema.json'
    $candidateBinding = [ordered]@{
        executable = Get-TestRecord (Join-Path $candidate 'ytdlp-interface.exe') 'ytdlp-interface.exe'
        ffprobe = Get-TestRecord (Join-Path $candidate 'ffprobe.exe') 'ffprobe.exe'
        manifest = Get-TestRecord $candidateManifestPath 'candidate-manifest.json'
    }
    Write-TestJson $guiSummary ([ordered]@{ schemaVersion = 2; releaseVersion = $script:Tag; status = 'PASS'; candidate = $candidateBinding; evidenceFileCount = 0; cases = @(); fullVideoLifecycleCases = @(); representativeChecks = [ordered]@{}; generatedProbes = @() })
    Write-TestJson $guiEvidence ([ordered]@{ schemaVersion = 2; releaseVersion = $script:Tag; candidate = $candidateBinding; evidenceFiles = @(); generatedProbeFiles = @() })
    Write-TestJson $guiSchema ([ordered]@{ '$schema' = 'https://json-schema.org/draft/2020-12/schema'; '$id' = 'https://example.test/gui'; type = 'object' })

    $sourceRoot = $repo
    $notices = @{}
    foreach ($id in @('application', '7zip', 'yt-dlp', 'deno', 'ffmpeg')) {
        $relative = 'release/licenses/v2.19.1-karon.2/' + $id + '/LICENSE.txt'
        $path = Join-Path $sourceRoot $relative
        Write-TestText $path ($id + " license`n")
        $notices[$id] = [ordered]@{ relative = $relative; sha = Get-TestSha256 $path }
    }
    $rootNotices = Join-Path $repo 'THIRD-PARTY-NOTICES.txt'
    $releaseNotes = Join-Path $repo 'release\notes\v2.19.1-karon.2.md'
    Write-TestText $rootNotices "root third-party notices`n"
    Write-TestText $releaseNotes "# Synthetic release notes`n"
    $prebuiltSources = Join-Path $root 'prebuilt-corresponding-sources.zip'
    $prebuiltSpdx = Join-Path $root 'prebuilt.spdx.json'
    Write-TestText $prebuiltSources 'prebuilt sources receipt input'
    Write-TestText $prebuiltSpdx '{"spdxVersion":"SPDX-2.3"}'

    $components = @(
        (New-TestComponent 'application' '2.19.1-karon.2' $applicationCommit 'MIT' $notices.application.relative $notices.application.sha $applicationSource),
        (New-TestComponent '7zip' '26.01' ('1' * 40) 'LGPL-2.1-or-later' $notices.'7zip'.relative $notices.'7zip'.sha $sevenZipConsumerSource),
        (New-TestComponent 'yt-dlp' '2026.09.11' ('2' * 40) 'Unlicense' $notices.'yt-dlp'.relative $notices.'yt-dlp'.sha $ytDlpSource),
        (New-TestComponent 'deno' '2.7.14' ('3' * 40) 'MIT' $notices.deno.relative $notices.deno.sha $denoCacheSources),
        (New-TestComponent 'ffmpeg' 'fixture' ('6' * 40) 'LGPL-2.1-or-later' $notices.ffmpeg.relative $notices.ffmpeg.sha $ffmpegSources)
    )
    $lockCandidateFiles = @()
    foreach ($entry in $candidateFiles) {
        $package = switch ($entry.path) { '7z.dll' { '7zip' }; 'deno.exe' { 'deno' }; 'ffmpeg.exe' { 'ffmpeg' }; 'ffprobe.exe' { 'ffmpeg' }; 'yt-dlp.exe' { 'yt-dlp' }; default { 'application' } }
        $lockCandidateFiles += [ordered]@{ path = $entry.path; length = $entry.length; sha256 = $entry.sha256; package = $package; licenseConcluded = (@($components | Where-Object id -eq $package)[0].licenseConcluded) }
    }
    $lockCandidateFiles += [ordered]@{ path = 'candidate-manifest.json'; length = [long](Get-Item $candidateManifestPath).Length; sha256 = Get-TestSha256 $candidateManifestPath; package = 'release-metadata'; licenseConcluded = 'CC0-1.0' }
    $template = Join-Path $root 'license-template.json'
    Write-TestJson $template ([ordered]@{
        schemaVersion = 'karon-license-lock/v2'
        release = [ordered]@{
            tag = $script:Tag; platform = 'win-x64'; verificationStatus = 'NOT_VERIFIED'; blockers = @('stale-lock-is-not-authority')
            metadataPackage = [ordered]@{ id = 'release-metadata'; name = 'Karon release metadata'; version = '2.19.1-karon.2'; licenseExpression = 'CC0-1.0'; licenseConcluded = 'CC0-1.0'; sourceCommit = $applicationCommit; downloadLocation = ('https://example.test/archive/' + $applicationCommit + '.zip') }
            candidateFiles = $lockCandidateFiles
        }
        components = $components
    })

    $output = Join-Path $root 'generated-license-lock.json'
    [pscustomobject]@{
        Root = $root; Repository = $repo; SourceRoot = $sourceRoot; Candidate = $candidate; Cache = $cache
        Template = $template; Output = $output; CandidateManifest = $candidateManifestPath
        NonRuntimeManifest = $nonRuntimeManifestPath; NonRuntimeInventory = $nonRuntimeInventoryPath; NonRuntimeBundle = $nonRuntimeBundle
        DenoRunEvidence = $denoRunEvidencePath; DenoCollectorSourceCommit = $script:ApprovedDenoCollectorCommit
        DenoComponent = $denoComponentPath; DenoInventory = $denoInventoryPath; DenoNotices = $denoNotices; DenoSources = $denoSources
        FfmpegManifest = $ffmpegManifestPath; FfmpegSources = $ffmpegSources
        SevenZipRuntime = $sevenZipRuntime; SevenZipSource = $sevenZipSource; SevenZipWrapper = $sevenZipConsumerSource; SevenZipVerification = $sevenZipVerification
        GuiSummary = $guiSummary; GuiEvidence = $guiEvidence; GuiSchema = $guiSchema
        CorrespondingSources = $prebuiltSources; Spdx = $prebuiltSpdx; RootNotices = $rootNotices; ReleaseNotes = $releaseNotes
        ApplicationCommit = $applicationCommit; ApplicationTree = $applicationTree
    }
}

function Get-BuilderArguments {
    param([object] $Fixture, [string] $OutputPath = '')
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = $Fixture.Output }
    [ordered]@{
        RepositoryRoot = $Fixture.Repository
        TemplateLockPath = $Fixture.Template
        CandidateDirectory = $Fixture.Candidate
        SourceArchiveDirectory = $Fixture.Cache
        NonRuntimeManifestPath = $Fixture.NonRuntimeManifest
        NonRuntimeInventoryPath = $Fixture.NonRuntimeInventory
        NonRuntimeEvidenceBundlePath = $Fixture.NonRuntimeBundle
        DenoRunEvidencePath = $Fixture.DenoRunEvidence
        DenoCollectorSourceCommit = $Fixture.DenoCollectorSourceCommit
        DenoComponentManifestPath = $Fixture.DenoComponent
        DenoSourceInventoryPath = $Fixture.DenoInventory
        DenoNoticesPath = $Fixture.DenoNotices
        DenoSourcesArchivePath = $Fixture.DenoSources
        FfmpegClosureManifestPath = $Fixture.FfmpegManifest
        FfmpegSourcesArchivePath = $Fixture.FfmpegSources
        SevenZipRuntimeArchivePath = $Fixture.SevenZipRuntime
        SevenZipSourceArchivePath = $Fixture.SevenZipSource
        SevenZipSourceWrapperPath = $Fixture.SevenZipWrapper
        SevenZipVerificationPath = $Fixture.SevenZipVerification
        GuiValidationSummaryPath = $Fixture.GuiSummary
        GuiValidationEvidenceManifestPath = $Fixture.GuiEvidence
        GuiValidationSchemaPath = $Fixture.GuiSchema
        CorrespondingSourcesPath = $Fixture.CorrespondingSources
        SpdxPath = $Fixture.Spdx
        RootThirdPartyNoticesPath = $Fixture.RootNotices
        ReleaseNotesPath = $Fixture.ReleaseNotes
        OutputPath = $OutputPath
    }
}

function Invoke-TestBuilder {
    param([object] $Fixture, [string] $OutputPath = '')
    $arguments = Get-BuilderArguments $Fixture $OutputPath
    & $script:Builder @arguments
}

function Assert-TestRejected {
    param([object] $Fixture, [string] $Pattern = 'release_license_lock_')
    $caught = $null
    try { Invoke-TestBuilder $Fixture | Out-Null }
    catch { $caught = $_ }
    $caught | Should -Not -BeNullOrEmpty
    $caught.Exception.Message | Should -Match $Pattern
    (Test-Path -LiteralPath $Fixture.Output) | Should -Be $false
    @(Get-ChildItem -LiteralPath (Split-Path -Parent $Fixture.Output) -Filter '.generated-license-lock.json.partial.*' -ErrorAction SilentlyContinue).Count | Should -Be 0
}

function Set-PackageGuiFixture {
    param([object] $Fixture)
    Copy-Item -LiteralPath (Join-Path $script:RepositoryRoot 'tests\powershell\fixtures\gui-validation-output.schema-e49cc702.json') -Destination $Fixture.GuiSchema -Force
    $candidate = (Read-TestJson $Fixture.GuiSummary).candidate
    $cases = @()
    $evidenceFiles = @()
    foreach ($spec in @(
        @('ko-KR-100', 'ko-KR', 100), @('ko-KR-150', 'ko-KR', 150), @('ko-KR-200', 'ko-KR', 200),
        @('en-US-100', 'en-US', 100), @('en-US-150', 'en-US', 150), @('en-US-200', 'en-US', 200)
    )) {
        $relative = 'cases/' + $spec[0] + '.json'
        $path = Join-Path (Split-Path -Parent $Fixture.GuiSummary) $relative
        Write-TestJson $path ([ordered]@{ caseId = $spec[0]; status = 'PASS' })
        $sha = Get-TestSha256 $path
        $cases += [ordered]@{ caseId = $spec[0]; language = $spec[1]; dpi = [int]$spec[2]; evidenceFile = $relative; evidenceSha256 = $sha }
        $evidenceFiles += [ordered]@{ path = $relative; sha256 = $sha; length = [long](Get-Item $path).Length }
    }
    $probes = @()
    foreach ($spec in @(
        @('ko-KR-100', 'video'), @('en-US-200', 'video'), @('ko-KR-100', 'mp3')
    )) {
        $sourcePath = 'cases/' + $spec[0] + '.json'
        $relative = 'probes/' + $spec[0] + '-' + $spec[1] + '.ffprobe.json'
        $path = Join-Path (Split-Path -Parent $Fixture.GuiSummary) $relative
        Write-TestJson $path ([ordered]@{ streams = @(); format = [ordered]@{ format_name = $spec[1] } })
        $probes += [ordered]@{ caseId = $spec[0]; kind = $spec[1]; sourceEvidencePath = $sourcePath; path = $relative; sha256 = Get-TestSha256 $path; length = [long](Get-Item $path).Length }
    }
    Write-TestJson $Fixture.GuiSummary ([ordered]@{
        schemaVersion = 2; releaseVersion = $script:Tag; status = 'PASS'; candidate = $candidate; cases = $cases
        fullVideoLifecycleCases = @('ko-KR-100', 'en-US-200')
        representativeChecks = [ordered]@{ mp3Conversion = @('ko-KR-100'); settingsSaveRestartRestore = @('ko-KR-100'); legacySettingsTransition = @('en-US-200') }
        generatedProbes = $probes; evidenceFileCount = 6; evidenceManifestFile = 'gui-validation-evidence-manifest.json'
    })
    Write-TestJson $Fixture.GuiEvidence ([ordered]@{
        schemaVersion = 2; releaseVersion = $script:Tag; candidate = $candidate; evidenceFiles = $evidenceFiles; generatedProbeFiles = $probes
    })
}

function Get-FixtureProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Fixture,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $matches = @($Fixture.PSObject.Properties | Where-Object { $_.Name -ceq $name })
        if ($matches.Count -eq 1) {
            return $matches[0]
        }
    }
    throw "fixture_property_missing_$($Names -join '_')"
}

function New-TestCaseCollisionZip {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $true)]
        [object[]]$Entries
    )

    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($OutputPath)) | Out-Null
    $output = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $archive = [IO.Compression.ZipArchive]::new($output, [IO.Compression.ZipArchiveMode]::Create, $true, [Text.Encoding]::UTF8)
        try {
            foreach ($record in $Entries) {
                $entry = $archive.CreateEntry([string]$record.Path, [IO.Compression.CompressionLevel]::NoCompression)
                $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
                $entryStream = $entry.Open()
                try {
                    $bytes = [IO.File]::ReadAllBytes([string]$record.Source)
                    $entryStream.Write($bytes, 0, $bytes.Length)
                }
                finally {
                    $entryStream.Dispose()
                }
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        $output.Dispose()
    }
}

function New-TestSevenZipWrapper {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($OutputPath)) | Out-Null
    $output = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $archive = [IO.Compression.ZipArchive]::new($output, [IO.Compression.ZipArchiveMode]::Create, $true, [Text.Encoding]::UTF8)
        try {
            $entry = $archive.CreateEntry('sevenzip/7z2601-x64-no-rar-source.7z', [IO.Compression.CompressionLevel]::NoCompression)
            $entry.LastWriteTime = [DateTimeOffset]::new(1980, 1, 1, 0, 0, 2, [TimeSpan]::Zero)
            $entryStream = $entry.Open()
            try {
                $bytes = [IO.File]::ReadAllBytes($RawPath)
                $entryStream.Write($bytes, 0, $bytes.Length)
            }
            finally {
                $entryStream.Dispose()
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        $output.Dispose()
    }
}

function New-SwapInstrumentedBuilder {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('raw', 'wrapper')]
        [string]$Kind,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter(Mandatory = $true)]
        [string]$ReplacementPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )

    $builderVariables = @(Get-Variable -Scope Script | Where-Object {
        $_.Value -is [string] -and [IO.Path]::GetFileName([string]$_.Value) -ceq 'build-release-license-lock.ps1'
    })
    if ($builderVariables.Count -ne 1) {
        throw 'release_lock_builder_variable_missing'
    }
    $builderVariable = $builderVariables[0]
    $text = [IO.File]::ReadAllText([string]$builderVariable.Value)
    $newLine = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }

    if ($Kind -ceq 'raw') {
        $unsafePattern = '(?m)^\s*\$rawRecord\s*=\s*Get-IntegratorBoundFileRecord\s+-Path\s+\$SevenZipSourceArchivePath[^\r\n]*$'
        $safePattern = '(?m)^\s*\$rawSnapshot\s*=\s*Open-IntegratorLockedSnapshot\s+-Path\s+\$SevenZipSourceArchivePath[^\r\n]*$'
    }
    else {
        $unsafePattern = '(?m)^\s*\$wrapperRecord\s*=\s*Get-IntegratorBoundFileRecord\s+-Path\s+\$SevenZipSourceWrapperPath[^\r\n]*$'
        $safePattern = '(?m)^\s*\$wrapperSnapshot\s*=\s*Open-IntegratorLockedSnapshot\s+-Path\s+\$SevenZipSourceWrapperPath[^\r\n]*$'
    }

    $pattern = if ([regex]::Matches($text, $unsafePattern).Count -eq 1) { $unsafePattern } else { $safePattern }
    $matches = [regex]::Matches($text, $pattern)
    if ($matches.Count -ne 1) {
        throw "release_lock_${Kind}_swap_boundary_missing"
    }

    $targetLiteral = $TargetPath.Replace("'", "''")
    $replacementLiteral = $ReplacementPath.Replace("'", "''")
    $backupPath = Join-Path $OutputDirectory ("$Kind-before-swap.bin")
    $backupLiteral = $backupPath.Replace("'", "''")
    $attack = @(
        '        try {'
        "            [IO.File]::Move('$targetLiteral', '$backupLiteral')"
        "            [IO.File]::Move('$replacementLiteral', '$targetLiteral')"
        '        }'
        '        catch {'
        "            throw 'release_license_lock_input_swap_blocked'"
        '        }'
    ) -join $newLine

    $instrumented = Join-Path $OutputDirectory ("build-release-license-lock-$Kind-race.ps1")
    $rewritten = [regex]::Replace(
        $text,
        $pattern,
        { param($match) $match.Value + $newLine + $attack },
        [Text.RegularExpressions.RegexOptions]::None,
        [TimeSpan]::FromSeconds(2)
    )
    [IO.File]::WriteAllText($instrumented, $rewritten, [Text.UTF8Encoding]::new($false))

    return [pscustomobject]@{
        BuilderVariableName = $builderVariable.Name
        OriginalBuilderPath = [string]$builderVariable.Value
        InstrumentedBuilderPath = $instrumented
        BackupPath = $backupPath
    }
}

Describe 'final verified release license lock integrator' {
    It 'rejects a supplied 7z wrapper that differs from the component corresponding source archive' {
        $fixture = New-TestFixture 'wrapper-binding-remand'
        $root = (Get-FixtureProperty $fixture @('Root')).Value
        $raw = (Get-FixtureProperty $fixture @('SevenZipSource', 'SevenZipSourceArchive', 'SevenZipRawSource')).Value
        $wrapperProperty = Get-FixtureProperty $fixture @('SevenZipWrapper', 'SevenZipSourceWrapper')
        $boundWrapper = [string]$wrapperProperty.Value
        $alternateWrapper = Join-Path $root 'alternate-sevenzip\7z2601-x64-no-rar-source.zip'
        New-TestSevenZipWrapper -RawPath $raw -OutputPath $alternateWrapper
        (Get-TestSha256 $alternateWrapper) | Should -Not -Be (Get-TestSha256 $boundWrapper)
        $wrapperProperty.Value = $alternateWrapper

        Assert-TestRejected $fixture 'release_license_lock_sevenzip_wrapper_binding_mismatch'
    }

    It 'blocks raw 7z replacement after identity capture and leaves no verified output' {
        $fixture = New-TestFixture 'raw-swap-remand'
        $root = (Get-FixtureProperty $fixture @('Root')).Value
        $raw = [string](Get-FixtureProperty $fixture @('SevenZipSource', 'SevenZipSourceArchive', 'SevenZipRawSource')).Value
        $replacement = Join-Path $root 'raw-swap-candidate.7z'
        $replacementBytes = [IO.File]::ReadAllBytes($raw)
        $replacementBytes[0] = $replacementBytes[0] -bxor 1
        [IO.File]::WriteAllBytes($replacement, $replacementBytes)
        $race = New-SwapInstrumentedBuilder -Kind raw -TargetPath $raw -ReplacementPath $replacement -OutputDirectory $root

        Set-Variable -Scope Script -Name $race.BuilderVariableName -Value $race.InstrumentedBuilderPath
        try {
            Assert-TestRejected $fixture 'release_license_lock_input_swap_blocked'
            (Test-Path -LiteralPath $race.BackupPath) | Should -Be $false
        }
        finally {
            Set-Variable -Scope Script -Name $race.BuilderVariableName -Value $race.OriginalBuilderPath
        }
    }

    It 'blocks wrapper replacement after outer hash capture and leaves no verified output' {
        $fixture = New-TestFixture 'wrapper-swap-remand'
        $root = (Get-FixtureProperty $fixture @('Root')).Value
        $raw = [string](Get-FixtureProperty $fixture @('SevenZipSource', 'SevenZipSourceArchive', 'SevenZipRawSource')).Value
        $wrapper = [string](Get-FixtureProperty $fixture @('SevenZipWrapper', 'SevenZipSourceWrapper')).Value
        $replacement = Join-Path $root 'wrapper-swap\7z2601-x64-no-rar-source.zip'
        New-TestSevenZipWrapper -RawPath $raw -OutputPath $replacement
        (Get-TestSha256 $replacement) | Should -Not -Be (Get-TestSha256 $wrapper)
        $race = New-SwapInstrumentedBuilder -Kind wrapper -TargetPath $wrapper -ReplacementPath $replacement -OutputDirectory $root

        Set-Variable -Scope Script -Name $race.BuilderVariableName -Value $race.InstrumentedBuilderPath
        try {
            Assert-TestRejected $fixture 'release_license_lock_input_swap_blocked'
            (Test-Path -LiteralPath $race.BackupPath) | Should -Be $false
        }
        finally {
            Set-Variable -Scope Script -Name $race.BuilderVariableName -Value $race.OriginalBuilderPath
        }
    }

    It 'rejects ordinal-ignore-case collisions in self-consistent Deno inventory and ZIP paths' {
        $fixture = New-TestFixture 'deno-case-collision-remand' -DenoCaseCollision
        Assert-TestRejected $fixture 'release_license_lock_deno_case_collision'
    }
    It 'writes deterministic canonical UTF-8 only after deriving verified status' {
        $fixture = New-TestFixture 'happy'
        $second = Join-Path $fixture.Root 'generated-license-lock-second.json'
        Invoke-TestBuilder $fixture | Out-Null
        Invoke-TestBuilder $fixture $second | Out-Null
        (Get-TestSha256 $fixture.Output) | Should -Be (Get-TestSha256 $second)
        $bytes = [IO.File]::ReadAllBytes($fixture.Output)
        ($bytes.Length -gt 3) | Should -Be $true
        (($bytes[0] -eq 0xEF) -and ($bytes[1] -eq 0xBB) -and ($bytes[2] -eq 0xBF)) | Should -Be $false
        $bytes[$bytes.Length - 1] | Should -Be 10
        ([Text.Encoding]::UTF8.GetString($bytes).Contains("`r")) | Should -Be $false
        $lock = Read-TestJson $fixture.Output
        $lock.release.verificationStatus | Should -Be 'verified'
        @($lock.release.blockers).Count | Should -Be 0
        @($lock.components | Where-Object verificationStatus -ne 'verified').Count | Should -Be 0
        @($lock.components.sourceArchives | Where-Object verificationStatus -ne 'verified').Count | Should -Be 0
        $lock.release.integrationEvidence.denoComponent.scope | Should -Be 'deno-third-party-notice-source-closure'
        $lock.release.integrationEvidence.denoComponent.predicateVersion | Should -Be 'deno-component-pass/v1'
        $lock.release.integrationEvidence.denoComponent.componentPass | Should -Be $true
        $lock.release.integrationEvidence.denoComponent.overallReleasePassObserved | Should -Be $false
        $lock.release.integrationEvidence.denoComponent.collectorSourceCommit | Should -Be $script:ApprovedDenoCollectorCommit
        $lock.release.integrationEvidence.denoComponent.evidence.inventory.schemaVersion | Should -Be 'deno-source-inventory/v2'
        $lock.release.integrationEvidence.denoComponent.evidence.inventory.canonicalTreeDigest | Should -Be (Read-TestJson $fixture.DenoInventory).canonicalTreeDigest.sha256
        $lock.release.integrationEvidence.sevenZip.sourceWrapper.innerSha256 | Should -Be (Get-TestSha256 $fixture.SevenZipSource)
        $lock.release.integrationEvidence.sevenZip.sourceWrapper.outerSha256 | Should -Be (Get-TestSha256 $fixture.SevenZipWrapper)
        (Get-Command $script:Builder).Parameters.ContainsKey('verificationStatus') | Should -Be $false
    }

    It 'rejects stale Git source identity and candidate executable bytes' {
        $fixture = New-TestFixture 'candidate-git'
        $manifest = Read-TestJson $fixture.CandidateManifest
        $manifest.applicationSourceTree = ('f' * 40)
        Write-TestJson $fixture.CandidateManifest $manifest
        Assert-TestRejected $fixture 'release_license_lock_application_tree_mismatch|release_license_lock_binding_mismatch'

        $fixture = New-TestFixture 'candidate-exe'
        Write-TestText (Join-Path $fixture.Candidate 'ytdlp-interface.exe') 'changed executable bytes'
        Assert-TestRejected $fixture 'release_license_lock_candidate_mismatch'
    }

    It 'rejects GUI evidence bound to another executable or candidate manifest' {
        $fixture = New-TestFixture 'gui-exe'
        $summary = Read-TestJson $fixture.GuiSummary
        $summary.candidate.executable.sha256 = ('0' * 64)
        Write-TestJson $fixture.GuiSummary $summary
        Assert-TestRejected $fixture 'release_license_lock_gui_binding_mismatch'

        $fixture = New-TestFixture 'gui-manifest'
        $evidence = Read-TestJson $fixture.GuiEvidence
        $evidence.candidate.manifest.length = [long]$evidence.candidate.manifest.length + 1
        Write-TestJson $fixture.GuiEvidence $evidence
        Assert-TestRejected $fixture 'release_license_lock_gui_binding_mismatch'
    }

    It 'derives the Deno component predicate only from the approved successful conjunction' {
        $fixture = New-TestFixture 'deno-v1'
        $inventory = Read-TestJson $fixture.DenoInventory
        $inventory.schemaVersion = 'deno-source-inventory/v1'
        Write-TestJson $fixture.DenoInventory $inventory
        Assert-TestRejected $fixture 'release_license_lock_schema_unsupported'

        $fixture = New-TestFixture 'deno-digest'
        $inventory = Read-TestJson $fixture.DenoInventory
        $inventory.canonicalTreeDigest.sha256 = ('0' * 64)
        Write-TestJson $fixture.DenoInventory $inventory
        Assert-TestRejected $fixture 'release_license_lock_deno_tree_mismatch'

        $fixture = New-TestFixture 'deno-blocker'
        $component = Read-TestJson $fixture.DenoComponent
        $component | Add-Member -NotePropertyName blockers -NotePropertyValue @('fixture blocker')
        Write-TestJson $fixture.DenoComponent $component
        Assert-TestRejected $fixture 'release_license_lock_blocked'

        $fixture = New-TestFixture 'deno-not-verified'
        $component = Read-TestJson $fixture.DenoComponent
        $component | Add-Member -NotePropertyName classificationStatus -NotePropertyValue 'NOT_VERIFIED'
        Write-TestJson $fixture.DenoComponent $component
        Assert-TestRejected $fixture 'release_license_lock_not_verified'

        $fixture = New-TestFixture 'deno-artifact'
        Write-TestText $fixture.DenoNotices 'changed notices'
        Assert-TestRejected $fixture 'release_license_lock_deno_artifact_mismatch'

        $fixture = New-TestFixture 'deno-run-status'
        $run = Read-TestJson $fixture.DenoRunEvidence
        $run.result.status = 'failed'
        Write-TestJson $fixture.DenoRunEvidence $run
        Assert-TestRejected $fixture 'release_license_lock_deno_run_invalid'

        $fixture = New-TestFixture 'deno-run-error'
        $run = Read-TestJson $fixture.DenoRunEvidence
        $run.error = 'collector failed'
        Write-TestJson $fixture.DenoRunEvidence $run
        Assert-TestRejected $fixture 'release_license_lock_deno_run_invalid'

        $fixture = New-TestFixture 'deno-run-blocker'
        $run = Read-TestJson $fixture.DenoRunEvidence
        $run.result | Add-Member -NotePropertyName blockers -NotePropertyValue @('blocked')
        Write-TestJson $fixture.DenoRunEvidence $run
        Assert-TestRejected $fixture 'release_license_lock_blocked'

        $fixture = New-TestFixture 'deno-sentinel-true'
        $component = Read-TestJson $fixture.DenoComponent
        $component.overallReleasePass = $true
        Write-TestJson $fixture.DenoComponent $component
        Assert-TestRejected $fixture 'release_license_lock_deno_sentinel_invalid'

        $fixture = New-TestFixture 'deno-sentinel-malformed'
        $component = Read-TestJson $fixture.DenoComponent
        $component.overallReleasePass = 'false'
        Write-TestJson $fixture.DenoComponent $component
        Assert-TestRejected $fixture 'release_license_lock_deno_sentinel_invalid'

        $fixture = New-TestFixture 'deno-collector-commit'
        $fixture.DenoCollectorSourceCommit = ('0' * 40)
        Assert-TestRejected $fixture 'release_license_lock_deno_collector_invalid'

        $fixture = New-TestFixture 'deno-run-artifact'
        $run = Read-TestJson $fixture.DenoRunEvidence
        $run.result.noticeSha256 = ('0' * 64)
        Write-TestJson $fixture.DenoRunEvidence $run
        Assert-TestRejected $fixture 'release_license_lock_deno_artifact_mismatch'

        $fixture = New-TestFixture 'deno-blocker-report'
        Write-TestJson (Join-Path (Split-Path -Parent $fixture.DenoComponent) 'blocker-report.json') ([ordered]@{ blockers = @('failed') })
        Assert-TestRejected $fixture 'release_license_lock_deno_scope_invalid'
    }

    It 'rejects incomplete, blocked, non-LGPL, source-drifted, or runtime-drifted FFmpeg closure' {
        $fixture = New-TestFixture 'ffmpeg-incomplete'
        $manifest = Read-TestJson $fixture.FfmpegManifest
        $manifest.closureStatus = 'incomplete'
        Write-TestJson $fixture.FfmpegManifest $manifest
        Assert-TestRejected $fixture 'release_license_lock_ffmpeg_closure_invalid'

        $fixture = New-TestFixture 'ffmpeg-blocked'
        $manifest = Read-TestJson $fixture.FfmpegManifest
        $manifest | Add-Member -NotePropertyName blockers -NotePropertyValue @('blocked')
        Write-TestJson $fixture.FfmpegManifest $manifest
        Assert-TestRejected $fixture 'release_license_lock_blocked'

        $fixture = New-TestFixture 'ffmpeg-gpl'
        $manifest = Read-TestJson $fixture.FfmpegManifest
        $manifest.binary.archiveName = 'ffmpeg-fixture-win64-gpl.zip'
        Write-TestJson $fixture.FfmpegManifest $manifest
        Assert-TestRejected $fixture 'release_license_lock_ffmpeg_policy_invalid'

        $fixture = New-TestFixture 'ffmpeg-source'
        Write-TestText $fixture.FfmpegSources 'changed source archive'
        Assert-TestRejected $fixture 'release_license_lock_source_archive_mismatch'

        $fixture = New-TestFixture 'ffmpeg-runtime'
        Write-TestText (Join-Path $fixture.Candidate 'ffprobe.exe') 'changed ffprobe'
        Assert-TestRejected $fixture 'release_license_lock_candidate_mismatch'
    }

    It 'rejects 7z evidence that does not prove exact no-RAR runtime and source artifacts' {
        $fixture = New-TestFixture 'sevenzip-hash'
        $verification = Read-TestJson $fixture.SevenZipVerification
        $verification.correspondingSourceArchiveSha256 = ('0' * 64)
        Write-TestJson $fixture.SevenZipVerification $verification
        Assert-TestRejected $fixture 'release_license_lock_sevenzip_binding_mismatch|release_license_lock_nonruntime_binding_mismatch'

        $fixture = New-TestFixture 'sevenzip-runtime'
        $verification = Read-TestJson $fixture.SevenZipVerification
        $verification.runtime.infoExitCode = 1
        Write-TestJson $fixture.SevenZipVerification $verification
        Assert-TestRejected $fixture 'release_license_lock_sevenzip_verification_invalid|release_license_lock_nonruntime_binding_mismatch'

        $fixture = New-TestFixture 'sevenzip-rar'
        $manifest = Read-TestJson $fixture.NonRuntimeManifest
        $manifest.sharedInputs.sevenZipTask5.excludedObjects = @()
        Write-TestJson $fixture.NonRuntimeManifest $manifest
        Assert-TestRejected $fixture 'release_license_lock_sevenzip_policy_invalid|release_license_lock_binding_mismatch|release_license_lock_nonruntime_binding_mismatch'

        $fixture = New-TestFixture 'sevenzip-wrapper-inner'
        Remove-Item -LiteralPath $fixture.SevenZipWrapper
        $wrongInner = Join-Path $fixture.Root 'wrong-source.7z'
        Write-TestText $wrongInner 'different inner bytes'
        New-TestZip $fixture.SevenZipWrapper ([ordered]@{ 'sevenzip/7z2601-x64-no-rar-source.7z' = $wrongInner }) -NoCompression
        $template = Read-TestJson $fixture.Template
        $archive = @($template.components | Where-Object id -eq '7zip')[0].sourceArchives[0]
        $archive.sha256 = Get-TestSha256 $fixture.SevenZipWrapper
        $archive.length = [long](Get-Item $fixture.SevenZipWrapper).Length
        Write-TestJson $fixture.Template $template
        Assert-TestRejected $fixture 'release_license_lock_sevenzip_wrapper_mismatch'
    }

    It 'rejects non-runtime stale identity, blockers, unclassified files, and component binding drift' {
        $fixture = New-TestFixture 'nonruntime-commit'
        $inventory = Read-TestJson $fixture.NonRuntimeInventory
        $inventory.applicationCommit = ('0' * 40)
        Write-TestJson $fixture.NonRuntimeInventory $inventory
        Assert-TestRejected $fixture 'release_license_lock_nonruntime_binding_mismatch'

        $fixture = New-TestFixture 'nonruntime-blocker'
        $inventory = Read-TestJson $fixture.NonRuntimeInventory
        $inventory.blockers = @('blocked')
        Write-TestJson $fixture.NonRuntimeInventory $inventory
        Assert-TestRejected $fixture 'release_license_lock_blocked'

        $fixture = New-TestFixture 'nonruntime-unclassified'
        $inventory = Read-TestJson $fixture.NonRuntimeInventory
        $inventory.unclassifiedFiles = @('unknown.bin')
        Write-TestJson $fixture.NonRuntimeInventory $inventory
        Assert-TestRejected $fixture 'release_license_lock_unclassified'

        $fixture = New-TestFixture 'nonruntime-component'
        $manifest = Read-TestJson $fixture.NonRuntimeManifest
        $manifest.components[2].candidateBinding.files[0].sha256 = ('0' * 64)
        Write-TestJson $fixture.NonRuntimeManifest $manifest
        Assert-TestRejected $fixture 'release_license_lock_nonruntime_binding_mismatch'
    }

    It 'fails closed on missing files, path escape, duplicate JSON properties, and unsupported schemas' {
        $fixture = New-TestFixture 'missing'
        Remove-Item -LiteralPath $fixture.GuiEvidence
        Assert-TestRejected $fixture 'release_license_lock_input_missing'

        $fixture = New-TestFixture 'escape'
        $template = Read-TestJson $fixture.Template
        $template.release.candidateFiles[0].path = '../escape.bin'
        Write-TestJson $fixture.Template $template
        Assert-TestRejected $fixture 'release_license_lock_path_invalid'

        $fixture = New-TestFixture 'duplicate'
        $raw = [IO.File]::ReadAllText($fixture.DenoComponent)
        $raw = $raw -replace '"schemaVersion"\s*:', '"schemaVersion":"deno-third-party-components/v3","schemaVersion":'
        Write-TestText $fixture.DenoComponent $raw
        Assert-TestRejected $fixture 'release_license_lock_json_duplicate'

        $fixture = New-TestFixture 'schema'
        $manifest = Read-TestJson $fixture.NonRuntimeManifest
        $manifest.schemaVersion = 'karon-non-runtime-component-evidence/v99'
        Write-TestJson $fixture.NonRuntimeManifest $manifest
        Assert-TestRejected $fixture 'release_license_lock_schema_unsupported'
    }

    It 'does not trust caller-supplied verified status and never leaves a partial verified lock' {
        $fixture = New-TestFixture 'caller-status'
        $template = Read-TestJson $fixture.Template
        $template.release.verificationStatus = 'verified'
        Write-TestJson $fixture.Template $template
        Assert-TestRejected $fixture 'release_license_lock_template_status_invalid'

        $fixture = New-TestFixture 'atomic'
        $inventory = Read-TestJson $fixture.DenoInventory
        $inventory.canonicalTreeDigest.recordCount = 99
        Write-TestJson $fixture.DenoInventory $inventory
        Assert-TestRejected $fixture 'release_license_lock_deno_tree_mismatch'
    }

    It 'produces a lock accepted by corresponding-sources and SPDX consumers' {
        $fixture = New-TestFixture 'consumers'
        Invoke-TestBuilder $fixture | Out-Null
        $sourcesOutput = Join-Path $fixture.Root 'sources-output'
        $spdxOutput = Join-Path $fixture.Root 'spdx-output'
        [IO.Directory]::CreateDirectory($sourcesOutput) | Out-Null
        [IO.Directory]::CreateDirectory($spdxOutput) | Out-Null
        & $script:SourcesConsumer -LockPath $fixture.Output -SourceRoot $fixture.SourceRoot -CandidateRoot $fixture.Candidate -CacheDirectory $fixture.Cache -OutputDirectory $sourcesOutput | Out-Null
        & $script:SpdxConsumer -LockPath $fixture.Output -SourceRoot $fixture.SourceRoot -CandidateRoot $fixture.Candidate -OutputDirectory $spdxOutput | Out-Null
        @(Get-ChildItem -LiteralPath $sourcesOutput -File).Count | Should -BeGreaterThan 0
        @(Get-ChildItem -LiteralPath $spdxOutput -File).Count | Should -BeGreaterThan 0
    }

    It 'produces a tracked canonical lock accepted by package PlanOnly' {
        $fixture = New-TestFixture 'package-plan'
        Set-PackageGuiFixture $fixture
        $draftLock = Join-Path $fixture.Root 'draft-license-lock.json'
        Invoke-TestBuilder $fixture $draftLock | Out-Null

        $sourcesOutput = Join-Path $fixture.Root 'package-sources'
        $spdxOutput = Join-Path $fixture.Root 'package-spdx'
        [IO.Directory]::CreateDirectory($sourcesOutput) | Out-Null
        [IO.Directory]::CreateDirectory($spdxOutput) | Out-Null
        & $script:SourcesConsumer -LockPath $draftLock -SourceRoot $fixture.SourceRoot -CandidateRoot $fixture.Candidate -CacheDirectory $fixture.Cache -OutputDirectory $sourcesOutput | Out-Null
        & $script:SpdxConsumer -LockPath $draftLock -SourceRoot $fixture.SourceRoot -CandidateRoot $fixture.Candidate -OutputDirectory $spdxOutput | Out-Null
        $fixture.CorrespondingSources = @(Get-ChildItem -LiteralPath $sourcesOutput -File -Filter '*.zip')[0].FullName
        $fixture.Spdx = @(Get-ChildItem -LiteralPath $spdxOutput -File -Filter '*.json')[0].FullName

        $canonicalLock = Join-Path $fixture.Repository 'release\dependencies\v2.19.1-karon.2.lock.json'
        Invoke-TestBuilder $fixture $canonicalLock | Out-Null
        & git -c core.autocrlf=false -C $fixture.Repository add -- release
        & git -c core.autocrlf=false -c user.name='Karon Test' -c user.email='karon-test@example.invalid' -C $fixture.Repository commit -q -m packaging

        $packageOutput = Join-Path $fixture.Root 'package-output'
        $receipt = Join-Path $fixture.Root 'release-receipt.json'
        $plan = & $script:PackageConsumer -RepositoryRoot $fixture.Repository -CandidateDirectory $fixture.Candidate -LockPath $canonicalLock -CorrespondingSourcesPath $fixture.CorrespondingSources -SpdxPath $fixture.Spdx -GuiValidationSummaryPath $fixture.GuiSummary -GuiValidationEvidenceManifestPath $fixture.GuiEvidence -OutputDirectory $packageOutput -ReceiptPath $receipt -PlanOnly
        $plan | Should -Not -BeNullOrEmpty
    }
}
