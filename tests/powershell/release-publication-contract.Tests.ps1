Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script:PackageTool = Join-Path $script:SourceRoot 'tools\package-quality-release.ps1'
$script:PublishTool = Join-Path $script:SourceRoot 'tools\publish-quality-release.ps1'
$script:Tag = 'v2.19.1-karon.2'
$script:BinaryName = 'ytdlp-korean-interface-v2.19.1-karon.2-win-x64.zip'
$script:SourcesName = 'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources.zip'
$script:SpdxName = 'ytdlp-korean-interface-v2.19.1-karon.2.spdx.json'
$script:SumsName = 'SHA256SUMS.txt'
$script:HeadSha = '1111111111111111111111111111111111111111'
$script:TagObjectSha = '2222222222222222222222222222222222222222'

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
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

function Write-TestJson {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [object] $Value)
    Write-TestUtf8 -Path $Path -Text (($Value | ConvertTo-Json -Depth 64) + "`n")
}

function New-ReleaseContractCase {
    param([Parameter(Mandatory)] [string] $Name)

    $root = Join-Path $TestDrive $Name
    $repository = Join-Path $root 'repository'
    $candidate = Join-Path $root 'candidate'
    $generated = Join-Path $root 'generated'
    $output = Join-Path $root 'output'
    $licensePath = Join-Path $repository 'release\licenses\v2.19.1-karon.2\application\LICENSE.txt'
    New-Item -ItemType Directory -Path $repository, $candidate, $generated, $output | Out-Null

    $appPath = Join-Path $candidate 'app.exe'
    Write-TestUtf8 -Path $appPath -Text "sealed candidate bytes`n"
    $appSha = Get-TestSha256 $appPath
    $appLength = (Get-Item -LiteralPath $appPath).Length

    $manifestPath = Join-Path $candidate 'candidate-manifest.json'
    $manifest = [ordered]@{
        schemaVersion = 1
        files = @(
            [ordered]@{ path = 'app.exe'; sha256 = $appSha; length = $appLength }
        )
    }
    Write-TestJson -Path $manifestPath -Value $manifest
    $manifestSha = Get-TestSha256 $manifestPath

    $noticePath = Join-Path $repository 'THIRD-PARTY-NOTICES.txt'
    Write-TestUtf8 -Path $noticePath -Text "Third-party notices for the sealed fixture.`n"
    Write-TestUtf8 -Path $licensePath -Text "Fixture application license.`n"

    $lock = [ordered]@{
        schemaVersion = 'karon-license-lock/v2'
        release = [ordered]@{
            tag = $script:Tag
            platform = 'win-x64'
            verificationStatus = 'verified'
            blockers = @()
            candidateFiles = @(
                [ordered]@{ path = 'app.exe'; sha256 = $appSha; package = 'application'; licenseConcluded = 'MIT' },
                [ordered]@{ path = 'candidate-manifest.json'; sha256 = $manifestSha; package = 'release-metadata'; licenseConcluded = 'CC0-1.0' }
            )
        }
        components = @(
            [ordered]@{
                id = 'application'
                verificationStatus = 'verified'
                blockers = @()
                noticeFiles = @(
                    [ordered]@{
                        path = 'release/licenses/v2.19.1-karon.2/application/LICENSE.txt'
                        sha256 = Get-TestSha256 $licensePath
                    }
                )
                sourceArchives = @(
                    [ordered]@{
                        fileName = 'application-source.zip'
                        sha256 = ('a' * 64)
                        verificationStatus = 'verified'
                        blockers = @()
                    }
                )
            }
        )
    }
    $lockPath = Join-Path $root 'release.lock.json'
    Write-TestJson -Path $lockPath -Value $lock

    $sourcesPath = Join-Path $generated $script:SourcesName
    $spdxPath = Join-Path $generated $script:SpdxName
    Write-TestUtf8 -Path $sourcesPath -Text "sealed corresponding source bytes`n"
    Write-TestUtf8 -Path $spdxPath -Text "{`"spdxVersion`":`"SPDX-2.3`"}`n"

    $notesPath = Join-Path $root 'release-notes.md'
    Write-TestUtf8 -Path $notesPath -Text "# v2.19.1-karon.2`n"

    [pscustomobject]@{
        Root = $root
        Repository = $repository
        Candidate = $candidate
        Generated = $generated
        Output = $output
        Lock = $lock
        LockPath = $lockPath
        Manifest = $manifest
        ManifestPath = $manifestPath
        SourcesPath = $sourcesPath
        SpdxPath = $spdxPath
        NotesPath = $notesPath
    }
}

function Save-TestLock {
    param([Parameter(Mandatory)] [object] $Case)
    Write-TestJson -Path $Case.LockPath -Value $Case.Lock
}

function Invoke-TestPackage {
    param([Parameter(Mandatory)] [object] $Case)
    Invoke-QualityReleasePackage `
        -RepositoryRoot $Case.Repository `
        -CandidateDirectory $Case.Candidate `
        -LockPath $Case.LockPath `
        -CorrespondingSourcesPath $Case.SourcesPath `
        -SpdxPath $Case.SpdxPath `
        -OutputDirectory $Case.Output
}

function Get-TestFailure {
    param([Parameter(Mandatory)] [scriptblock] $Action)
    try {
        & $Action | Out-Null
        return 'test_expected_failure_but_action_succeeded'
    }
    catch { return $_.Exception.Message }
}

function New-FakePublicationRunner {
    param([hashtable] $Options = @{})

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
        AuthExitCode = 0
        ExistingRelease = $false
        Created = $false
        RemoteDigestMismatch = $false
    }
    foreach ($key in $Options.Keys) { $state[$key] = $Options[$key] }
    $calls = [Collections.Generic.List[object]]::new()
    $tag = $script:Tag
    $assetNames = @($script:BinaryName, $script:SourcesName, $script:SpdxName, $script:SumsName)

    $runner = {
        param([string] $Executable, [string[]] $Arguments, [string] $WorkingDirectory)

        $calls.Add([pscustomobject]@{
            Executable = $Executable
            Arguments = @($Arguments)
            WorkingDirectory = $WorkingDirectory
        })
        $key = $Executable + '|' + ($Arguments -join '|')
        $success = { param([string] $Text = '') [pscustomobject]@{ ExitCode = 0; Output = $Text } }
        $failure = { param([string] $Text) [pscustomobject]@{ ExitCode = 1; Output = $Text } }

        if ($key -ceq ('git|cat-file|-t|refs/tags/' + $tag)) { return & $success $state.TagType }
        if ($key -ceq ('git|rev-parse|refs/tags/' + $tag)) { return & $success $state.TagObject }
        if ($key -ceq ('git|rev-parse|refs/tags/' + $tag + '^{}')) { return & $success $state.TagTarget }
        if ($key -ceq ('git|ls-remote|origin|refs/tags/' + $tag + '|refs/tags/' + $tag + '^{}')) {
            return & $success (($state.RemoteTagObject + "`trefs/tags/" + $tag) + "`n" + ($state.RemoteTagTarget + "`trefs/tags/" + $tag + '^{}'))
        }

        switch ($key) {
            'git|remote|get-url|origin' { return & $success $state.Origin }
            'git|remote|get-url|--push|origin' { return & $success $state.PushOrigin }
            'git|status|--porcelain=v1|--untracked-files=all' { return & $success $state.Dirty }
            'git|rev-parse|--verify|HEAD^{commit}' { return & $success $state.Head }
            'git|ls-remote|origin|refs/heads/main' { return & $success ($state.RemoteHead + "`trefs/heads/main") }
            'gh|auth|status|--hostname|github.com' {
                if ($state.AuthExitCode -eq 0) { return & $success 'authenticated' }
                return & $failure 'not authenticated'
            }
        }

        $apiKey = 'gh|api|--method|GET|repos/KaronLabs/ytdlp-korean-interface/releases/tags/' + $tag
        if ($key -ceq $apiKey) {
            if (-not $state.Created -and -not $state.ExistingRelease) { return & $failure 'gh: Not Found (HTTP 404)' }
            $assetDirectory = [string]$state.AssetDirectory
            $assets = @()
            foreach ($name in $assetNames) {
                $path = Join-Path $assetDirectory $name
                $digest = 'sha256:' + ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant())
                if ($state.RemoteDigestMismatch -and $name -ceq $assetNames[0]) { $digest = 'sha256:' + ('f' * 64) }
                $assets += [ordered]@{
                    name = $name
                    size = (Get-Item -LiteralPath $path).Length
                    state = 'uploaded'
                    digest = $digest
                }
            }
            return & $success (([ordered]@{
                tag_name = $tag
                draft = $false
                prerelease = $false
                assets = $assets
            }) | ConvertTo-Json -Depth 8 -Compress)
        }

        if ($Executable -ceq 'gh' -and $Arguments.Count -gt 1 -and $Arguments[0] -ceq 'release' -and $Arguments[1] -ceq 'create') {
            $state.Created = $true
            return & $success 'release created'
        }

        return [pscustomobject]@{ ExitCode = 99; Output = "unexpected command: $key" }
    }.GetNewClosure()

    [pscustomobject]@{ Runner = $runner; Calls = $calls; State = $state }
}

function New-PackagedPublicationCase {
    param([Parameter(Mandatory)] [string] $Name)
    $case = New-ReleaseContractCase $Name
    Invoke-TestPackage $case | Out-Null
    $case
}

Describe 'Exact release package contract' {
    It 'packages the sealed candidate, notices, licenses, and exactly four release assets' {
        $case = New-ReleaseContractCase 'package-positive'
        $result = Invoke-TestPackage $case

        @($result.AssetPaths).Count | Should Be 4
        $names = @(Get-ChildItem -LiteralPath $case.Output -File | ForEach-Object Name | Sort-Object)
        ($names -join '|') | Should Be (($script:BinaryName, $script:SourcesName, $script:SpdxName, $script:SumsName | Sort-Object) -join '|')

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $case.Output $script:BinaryName))
        try { $entries = @($zip.Entries | ForEach-Object FullName) }
        finally { $zip.Dispose() }
        ($entries -join '|') | Should Be 'THIRD-PARTY-NOTICES.txt|app.exe|candidate-manifest.json|release/licenses/v2.19.1-karon.2/application/LICENSE.txt'

        $expectedSums = @(
            ((Get-TestSha256 (Join-Path $case.Output $script:BinaryName)) + '  ' + $script:BinaryName)
            ((Get-TestSha256 (Join-Path $case.Output $script:SourcesName)) + '  ' + $script:SourcesName)
            ((Get-TestSha256 (Join-Path $case.Output $script:SpdxName)) + '  ' + $script:SpdxName)
        ) -join "`n"
        [IO.File]::ReadAllText((Join-Path $case.Output $script:SumsName)) | Should Be ($expectedSums + "`n")
    }

    It 'rejects an unverified release lock before creating output' {
        $case = New-ReleaseContractCase 'package-unverified'
        $case.Lock.release.verificationStatus = 'NOT_VERIFIED'
        Save-TestLock $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_release_not_verified'
        @(Get-ChildItem -LiteralPath $case.Output -Force).Count | Should Be 0
    }

    It 'requires every source archive status to be exactly verified' {
        $case = New-ReleaseContractCase 'package-source-unverified'
        $case.Lock.components[0].sourceArchives[0].verificationStatus = 'Verified'
        Save-TestLock $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_source_not_verified'
        @(Get-ChildItem -LiteralPath $case.Output -Force).Count | Should Be 0
    }

    It 'rejects an unlisted candidate file' {
        $case = New-ReleaseContractCase 'package-extra-candidate'
        Write-TestUtf8 -Path (Join-Path $case.Candidate 'extra.dll') -Text 'unsealed'
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_candidate_inventory_mismatch'
        @(Get-ChildItem -LiteralPath $case.Output -Force).Count | Should Be 0
    }

    It 'rejects a duplicate-case candidate lock path' {
        $case = New-ReleaseContractCase 'package-case-collision'
        $case.Lock.release.candidateFiles += [ordered]@{
            path = 'APP.EXE'
            sha256 = $case.Lock.release.candidateFiles[0].sha256
            package = 'application'
            licenseConcluded = 'MIT'
        }
        Save-TestLock $case
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_candidate_path_collision'
    }

    It 'requires the already generated exact source and SPDX asset names' {
        $case = New-ReleaseContractCase 'package-missing-generated'
        Remove-Item -LiteralPath $case.SpdxPath
        (Get-TestFailure { Invoke-TestPackage $case }) | Should Match 'package_spdx_invalid'
        @(Get-ChildItem -LiteralPath $case.Output -Force).Count | Should Be 0
    }

    It 'preserves another producers final artifact when atomic move loses the race' {
        $case = New-ReleaseContractCase 'package-atomic-race'
        $partial = Join-Path $case.Output ('.owned.' + [Guid]::NewGuid().ToString('N') + '.partial')
        $final = Join-Path $case.Output $script:BinaryName
        Write-TestUtf8 -Path $partial -Text 'owned partial'
        Write-TestUtf8 -Path $final -Text 'independent final'
        $before = Get-TestSha256 $final

        (Get-TestFailure { Move-KaronPackageOwnedArtifact -PartialPath $partial -FinalPath $final }) | Should Match 'package_output_race'
        (Test-Path -LiteralPath $partial) | Should Be $false
        (Get-TestSha256 $final) | Should Be $before
    }
}

Describe 'Fail-closed publication preflight' {
    It 'rejects missing or extra asset inventory before external commands' -TestCases @(
        @{ Mutation = 'missing' },
        @{ Mutation = 'extra' }
    ) {
        param($Mutation)
        $case = New-PackagedPublicationCase ("publication-inventory-$Mutation")
        if ($Mutation -eq 'missing') { Remove-Item -LiteralPath (Join-Path $case.Output $script:SpdxName) }
        else { Write-TestUtf8 -Path (Join-Path $case.Output 'unexpected.bin') -Text 'unexpected' }
        $fake = New-FakePublicationRunner
        $fake.State.AssetDirectory = $case.Output

        (Get-TestFailure { Invoke-QualityReleasePublication -RepositoryRoot $case.Repository -AssetDirectory $case.Output -ReleaseNotesPath $case.NotesPath -PlanOnly -CommandRunner $fake.Runner }) | Should Match 'publication_asset_inventory_invalid'
        $fake.Calls.Count | Should Be 0
    }

    It 'rejects a checksum mismatch before external commands' {
        $case = New-PackagedPublicationCase 'publication-checksum-mismatch'
        [IO.File]::AppendAllText((Join-Path $case.Output $script:SpdxName), 'tamper')
        $fake = New-FakePublicationRunner
        $fake.State.AssetDirectory = $case.Output

        (Get-TestFailure { Invoke-QualityReleasePublication -RepositoryRoot $case.Repository -AssetDirectory $case.Output -ReleaseNotesPath $case.NotesPath -PlanOnly -CommandRunner $fake.Runner }) | Should Match 'publication_checksum_mismatch'
        $fake.Calls.Count | Should Be 0
    }

    It 'rejects wrong origin, dirty tree, remote HEAD drift, and tag target mismatch' -TestCases @(
        @{ Name = 'origin'; Options = @{ Origin = 'https://github.com/KaronLabs/ytdlp-korean-interface.git' }; ErrorId = 'publication_origin_mismatch' },
        @{ Name = 'dirty'; Options = @{ Dirty = ' M tools/file.ps1' }; ErrorId = 'publication_tree_dirty' },
        @{ Name = 'head'; Options = @{ RemoteHead = '3333333333333333333333333333333333333333' }; ErrorId = 'publication_main_sha_mismatch' },
        @{ Name = 'tag'; Options = @{ TagTarget = '4444444444444444444444444444444444444444' }; ErrorId = 'publication_tag_target_mismatch' }
    ) {
        param($Name, $Options, $ErrorId)
        $case = New-PackagedPublicationCase ("publication-$Name")
        $fake = New-FakePublicationRunner $Options
        $fake.State.AssetDirectory = $case.Output
        (Get-TestFailure { Invoke-QualityReleasePublication -RepositoryRoot $case.Repository -AssetDirectory $case.Output -ReleaseNotesPath $case.NotesPath -PlanOnly -CommandRunner $fake.Runner }) | Should Match $ErrorId
    }

    It 'rejects an existing release instead of clobbering its assets' {
        $case = New-PackagedPublicationCase 'publication-existing-release'
        $fake = New-FakePublicationRunner @{ ExistingRelease = $true }
        $fake.State.AssetDirectory = $case.Output
        (Get-TestFailure { Invoke-QualityReleasePublication -RepositoryRoot $case.Repository -AssetDirectory $case.Output -ReleaseNotesPath $case.NotesPath -PlanOnly -CommandRunner $fake.Runner }) | Should Match 'publication_release_exists'
        @($fake.Calls | Where-Object { $_.Executable -ceq 'gh' -and $_.Arguments[0] -ceq 'release' }).Count | Should Be 0
    }
}

Describe 'Exact publication command and remote evidence' {
    It 'returns the exact stable release command in plan mode without executing it' {
        $case = New-PackagedPublicationCase 'publication-plan-positive'
        $fake = New-FakePublicationRunner
        $fake.State.AssetDirectory = $case.Output
        $result = Invoke-QualityReleasePublication -RepositoryRoot $case.Repository -AssetDirectory $case.Output -ReleaseNotesPath $case.NotesPath -PlanOnly -CommandRunner $fake.Runner

        $result.Mode | Should Be 'plan'
        $result.Command.Executable | Should Be 'gh'
        $expected = @(
            'release', 'create', $script:Tag,
            [IO.Path]::GetFullPath((Join-Path $case.Output $script:BinaryName)),
            [IO.Path]::GetFullPath((Join-Path $case.Output $script:SourcesName)),
            [IO.Path]::GetFullPath((Join-Path $case.Output $script:SpdxName)),
            [IO.Path]::GetFullPath((Join-Path $case.Output $script:SumsName)),
            '--repo', 'KaronLabs/ytdlp-korean-interface',
            '--title', $script:Tag,
            '--notes-file', [IO.Path]::GetFullPath($case.NotesPath),
            '--verify-tag', '--latest'
        )
        ($result.Command.Arguments -join "`n") | Should Be ($expected -join "`n")
        ($result.Command.Arguments -join ' ') | Should Not Match '(?i)--(?:clobber|draft|prerelease|force)\b'
        @($fake.Calls | Where-Object { $_.Executable -ceq 'gh' -and $_.Arguments[0] -ceq 'release' }).Count | Should Be 0
    }

    It 'executes the exact local-byte release command and verifies remote asset digests' {
        $case = New-PackagedPublicationCase 'publication-execute-positive'
        $fake = New-FakePublicationRunner
        $fake.State.AssetDirectory = $case.Output
        $result = Invoke-QualityReleasePublication -RepositoryRoot $case.Repository -AssetDirectory $case.Output -ReleaseNotesPath $case.NotesPath -CommandRunner $fake.Runner

        $result.Mode | Should Be 'published'
        $result.DigestsVerified | Should Be 4
        @($fake.Calls | Where-Object { $_.Executable -ceq 'gh' -and $_.Arguments[0] -ceq 'release' -and $_.Arguments[1] -ceq 'create' }).Count | Should Be 1
    }

    It 'fails closed when GitHub exposes a mismatching asset digest' {
        $case = New-PackagedPublicationCase 'publication-remote-digest-mismatch'
        $fake = New-FakePublicationRunner @{ RemoteDigestMismatch = $true }
        $fake.State.AssetDirectory = $case.Output
        (Get-TestFailure { Invoke-QualityReleasePublication -RepositoryRoot $case.Repository -AssetDirectory $case.Output -ReleaseNotesPath $case.NotesPath -CommandRunner $fake.Runner }) | Should Match 'publication_remote_digest_mismatch'
    }
}
