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
$script:GuiCases = @(
    [pscustomobject]@{ id = 'gui-en-US-100'; language = 'en-US'; dpi = 100 },
    [pscustomobject]@{ id = 'gui-en-US-150'; language = 'en-US'; dpi = 150 },
    [pscustomobject]@{ id = 'gui-en-US-200'; language = 'en-US'; dpi = 200 },
    [pscustomobject]@{ id = 'gui-ko-KR-100'; language = 'ko-KR'; dpi = 100 },
    [pscustomobject]@{ id = 'gui-ko-KR-150'; language = 'ko-KR'; dpi = 150 },
    [pscustomobject]@{ id = 'gui-ko-KR-200'; language = 'ko-KR'; dpi = 200 }
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

    $appPath = Join-Path $candidate 'ytdlp-interface.exe'
    $ffprobePath = Join-Path $candidate 'ffprobe.exe'
    Write-TestUtf8 $appPath ('sealed application bytes' + [char]10)
    Write-TestUtf8 $ffprobePath ('sealed ffprobe bytes' + [char]10)
    $manifestPath = Join-Path $candidate 'candidate-manifest.json'
    $manifest = [ordered]@{
        schemaVersion = 1
        createdAtUtc = '2026-09-16T00:00:00Z'
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
        sourceCommit = $script:HeadSha
        downloadLocation = 'https://github.com/KaronLabs/ytdlp-korean-interface/archive/' + $script:HeadSha + '.zip'
    }
    $component = [ordered]@{
        id = 'application'
        name = 'Fixture application'
        version = '1.0.0'
        sourceRepository = 'https://github.com/KaronLabs/ytdlp-korean-interface'
        sourceCommit = $script:HeadSha
        licenseExpression = 'MIT'
        verificationStatus = 'verified'
        modified = $true
        noticeFiles = @([ordered]@{
            path = 'release/licenses/v2.19.1-karon.2/application/LICENSE.txt'
            sha256 = Get-TestSha256 $licensePath
        })
        sourceArchives = @([ordered]@{
            fileName = 'application-source.zip'
            commit = $script:HeadSha
            url = 'https://github.com/KaronLabs/ytdlp-korean-interface/archive/' + $script:HeadSha + '.zip'
            sha256 = Get-TestSha256 $sourceArchive
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
    $innerLockPath = Join-Path $root 'inner.lock.json'
    Write-TestJson $innerLockPath $baseLock
    $sourcesPath = Join-Path $generated $script:SourcesName
    $sourcePrefix = 'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources/'
    New-TestZip $sourcesPath @{
        ($sourcePrefix + 'release/dependencies/v2.19.1-karon.2.lock.json') = $innerLockPath
        ($sourcePrefix + 'THIRD-PARTY-NOTICES.txt') = $noticePath
        ($sourcePrefix + 'release/licenses/v2.19.1-karon.2/application/LICENSE.txt') = $licensePath
        ($sourcePrefix + 'sources/application/application-source.zip') = $sourceArchive
    }

    $packages = @(
        [ordered]@{ name = 'Fixture application'; SPDXID = 'SPDXRef-Package-application'; versionInfo = '1.0.0' },
        [ordered]@{ name = 'Fixture release metadata'; SPDXID = 'SPDXRef-Package-release-metadata'; versionInfo = $script:Tag }
    )
    $spdxFiles = @()
    foreach ($entry in $candidateFiles) {
        $spdxFiles += [ordered]@{
            fileName = './' + $entry.path
            SPDXID = 'SPDXRef-File-' + ([Guid]::NewGuid().ToString('N'))
            checksums = @(
                [ordered]@{ algorithm = 'SHA1'; checksumValue = ('1' * 40) },
                [ordered]@{ algorithm = 'SHA256'; checksumValue = $entry.sha256 }
            )
        }
    }
    $spdxPath = Join-Path $generated $script:SpdxName
    $spdx = [ordered]@{
        spdxVersion = 'SPDX-2.3'
        dataLicense = 'CC0-1.0'
        SPDXID = 'SPDXRef-DOCUMENT'
        name = 'ytdlp-korean-interface-v2.19.1-karon.2-win-x64'
        documentNamespace = 'https://github.com/KaronLabs/ytdlp-korean-interface/spdx/v2.19.1-karon.2/' + ('a' * 64)
        documentDescribes = @('SPDXRef-Package-application', 'SPDXRef-Package-release-metadata')
        packages = $packages
        files = $spdxFiles
    }
    Write-TestJson $spdxPath $spdx

    $summaryCases = @()
    $manifestCases = @()
    foreach ($case in $script:GuiCases) {
        $artifactRelative = 'evidence/' + $case.id + '.txt'
        $artifactPath = Join-Path $gui $artifactRelative
        Write-TestUtf8 $artifactPath ('evidence for ' + $case.id + [char]10)
        $summaryCases += [ordered]@{ id = $case.id; language = $case.language; dpiPercent = $case.dpi; status = 'verified'; evidenceId = $case.id }
        $manifestCases += [ordered]@{
            id = $case.id
            status = 'verified'
            artifacts = @([ordered]@{ path = $artifactRelative; length = [long](Get-Item $artifactPath).Length; sha256 = Get-TestSha256 $artifactPath })
        }
    }
    $guiCandidate = [ordered]@{ fileName = 'ytdlp-interface.exe'; length = [long](Get-Item $appPath).Length; sha256 = Get-TestSha256 $appPath }
    $summaryPath = Join-Path $gui 'gui-validation-summary.json'
    $guiManifestPath = Join-Path $gui 'gui-validation-evidence-manifest.json'
    $summary = [ordered]@{
        schemaVersion = 'karon-gui-validation-summary/v1'
        tag = $script:Tag
        status = 'verified'
        blockers = @()
        candidate = $guiCandidate
        cases = $summaryCases
    }
    $guiManifest = [ordered]@{
        schemaVersion = 'karon-gui-validation-evidence-manifest/v1'
        tag = $script:Tag
        status = 'verified'
        blockers = @()
        candidate = $guiCandidate
        cases = $manifestCases
    }
    Write-TestJson $summaryPath $summary
    Write-TestJson $guiManifestPath $guiManifest

    $outerLock = $baseLock
    $outerLock.release.receiptInputs = [ordered]@{
        candidateManifest = New-TestHashRecord $manifestPath 'candidate-manifest.json'
        correspondingSources = New-TestHashRecord $sourcesPath $script:SourcesName
        spdx = New-TestHashRecord $spdxPath $script:SpdxName
        rootThirdPartyNotices = New-TestHashRecord $noticePath 'THIRD-PARTY-NOTICES.txt'
        guiValidationSummary = New-TestHashRecord $summaryPath 'gui-validation-summary.json'
        guiValidationEvidenceManifest = New-TestHashRecord $guiManifestPath 'gui-validation-evidence-manifest.json'
        releaseNotes = New-TestHashRecord $notesPath 'release/notes/v2.19.1-karon.2.md' 'path'
    }
    $lockPath = Join-Path $root 'release.lock.json'
    Write-TestJson $lockPath $outerLock
    [pscustomobject]@{
        Root = $root
        Repository = $repository
        Candidate = $candidate
        Generated = $generated
        Gui = $gui
        Output = $output
        ReceiptPath = $receipt
        Lock = $outerLock
        LockPath = $lockPath
        InnerLockPath = $innerLockPath
        SourcesPath = $sourcesPath
        SpdxPath = $spdxPath
        Summary = $summary
        SummaryPath = $summaryPath
        GuiManifest = $guiManifest
        GuiManifestPath = $guiManifestPath
        NotesPath = $notesPath
        NoticePath = $noticePath
        LicensePath = $licensePath
        SourceArchive = $sourceArchive
        SourcePrefix = $sourcePrefix
        AppPath = $appPath
        FfprobePath = $ffprobePath
        ManifestPath = $manifestPath
    }
}

function Save-TestLock {
    param([object] $Case)
    Write-TestJson $Case.LockPath $Case.Lock
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
        Head = $script:HeadSha
        RemoteHead = $script:HeadSha
        TagType = 'tag'
        TagObject = $script:TagObjectSha
        TagTarget = $script:HeadSha
        RemoteTagObject = $script:TagObjectSha
        RemoteTagTarget = $script:HeadSha
        NotesBlob = [string]$receipt.releaseNotes.gitBlobSha1
        Stage = 'absent'
        DigestMode = 'null'
        MainRaceAt = 0
        TagRaceAt = 0
        MainChecks = 0
        TagChecks = 0
        DownloadMismatch = $false
        DownloadCount = 0
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
            $assets = @()
            if ($state.Stage -ceq 'draft-assets' -or $state.Stage -ceq 'stable') {
                foreach ($name in $assetNames) {
                    $path = Join-Path $assetDirectory $name
                    $digest = $null
                    if ($state.DigestMode -ceq 'match') { $digest = 'sha256:' + (Get-TestSha256 $path) }
                    if ($state.DigestMode -ceq 'mismatch' -and $name -ceq $binaryName) { $digest = 'sha256:' + ('f' * 64) }
                    $assets += [ordered]@{ name = $name; size = [long](Get-Item $path).Length; state = 'uploaded'; digest = $digest }
                }
            }
            $release = [ordered]@{
                tag_name = $tag
                draft = ($state.Stage -ne 'stable')
                prerelease = $false
                assets = $assets
            }
            return & $ok ($release | ConvertTo-Json -Depth 8 -Compress)
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
        @{ Name = 'zero'; Mutate = { param($case) $case.GuiManifest.cases[0].artifacts = @(); Save-TestGuiManifest $case } },
        @{ Name = 'five'; Mutate = { param($case) $case.Summary.cases = @($case.Summary.cases | Select-Object -First 5); Save-TestSummary $case } }
    ) {
        param($Name, $Mutate)
        $case = New-ReleaseContractCase ('package-gui-' + $Name)
        & $Mutate $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_gui_'
    }

    It 'rejects GUI evidence bound to a different candidate executable' {
        $case = New-ReleaseContractCase 'package-gui-candidate'
        $case.Summary.candidate.sha256 = 'f' * 64
        Save-TestSummary $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_gui_candidate_mismatch'
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
        $receipt.sourceCommit = 'f' * 40
        Write-TestJson $case.ReceiptPath $receipt
        $fake = New-FakePublicationRunner $case
        (Get-TestFailure { Invoke-TestPublication $case $fake -PlanOnly }) | Should Match 'package_receipt_source_mismatch'
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
        ($result.Commands[6].Arguments -join '|') | Should Be ('release|edit|' + $script:Tag + '|--repo|KaronLabs/ytdlp-korean-interface|--draft=false')
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
        $publishIndex = [Array]::FindIndex([object[]]$releaseCalls, [Predicate[object]]{ param($call) $call.Arguments -contains '--draft=false' })
        $lastDownloadIndex = [Array]::FindLastIndex([object[]]$releaseCalls, [Predicate[object]]{ param($call) $call.Arguments[1] -ceq 'download' })
        ($publishIndex -gt $lastDownloadIndex) | Should Be $true
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
        $fake = New-FakePublicationRunner $case @{ MainRaceAt = 6 }
        (Get-TestFailure { Invoke-TestPublication $case $fake }) | Should Match 'publication_'
        $fake.State.Stage | Should Be 'draft-assets'
        (@($fake.Calls | Where-Object {
            $_.Executable -ceq 'gh' -and $_.Arguments[0] -ceq 'release' -and
            $_.Arguments[1] -ceq 'edit' -and $_.Arguments -contains '--draft'
        })).Count | Should Be 1
    }
}
