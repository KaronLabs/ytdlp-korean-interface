#requires -Version 7.4

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:SpdxTool = Join-Path $script:SourceRoot 'tools\generate-release-spdx.ps1'
$script:SourceTool = Join-Path $script:SourceRoot 'tools\build-corresponding-sources.ps1'
$script:RealLock = Join-Path $script:SourceRoot 'release\dependencies\v2.19.1-karon.2.lock.json'
$script:OfficialSchema = Join-Path $PSScriptRoot 'fixtures\spdx-2.3-schema-aadf3b0b.json'
$script:OfficialSchemaSha256 = '3ec6cd5b8ba0c9a3e821da48536fa1b814567dc7e4376efe98d3e7b2a7a8d230'
$script:OfficialSchemaUpstreamSha256 = '239208b7ac287b3cf5d9a9af23f9d69863971102a5e1587a27a398b43490b89b'
$script:ExpectedJsonSchemaVersion = '4.26.0'
$script:FixtureApplicationVerificationCode = 'd5512016a069e03eb10b95146c23f2983433a39a'
$script:FixtureMetadataVerificationCode = 'd0a102a87ad65fa323c22d95cb63446323c5fb17'

function Get-TestSha256 {
    param([Parameter(Mandatory)] [string] $Path)
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-TestJson {
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [object] $Value)
    $json = $Value | ConvertTo-Json -Depth 64
    [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}

function New-TestZip {
    param([Parameter(Mandatory)] [string] $Path, [string] $EntryName = 'README.txt')
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $entry = $zip.CreateEntry($EntryName)
            $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
            try { $writer.Write('fixture source') } finally { $writer.Dispose() }
        }
        finally { $zip.Dispose() }
    }
    finally { $stream.Dispose() }
}

function New-LicenseBundleCase {
    param([Parameter(Mandatory)] [string] $Name)

    $root = Join-Path $TestDrive $Name
    $candidate = Join-Path $root 'candidate'
    $metadata = Join-Path $root 'metadata'
    $cache = Join-Path $root 'cache'
    $output = Join-Path $root 'output'
    $appNoticeDirectory = Join-Path $metadata 'release\licenses\application'
    $staticNoticeDirectory = Join-Path $metadata 'release\licenses\test-static'
    foreach ($directory in @($candidate, $appNoticeDirectory, $staticNoticeDirectory, $cache, $output)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $appPath = Join-Path $candidate 'app.exe'
    $settingsPath = Join-Path $candidate 'settings.json'
    [IO.File]::WriteAllBytes($appPath, [byte[]](1, 2, 3, 4))
    [IO.File]::WriteAllText($settingsPath, "{`"fixture`":true}`n", [Text.UTF8Encoding]::new($false))

    $appNoticePath = Join-Path $appNoticeDirectory 'NOTICE.txt'
    $staticNoticePath = Join-Path $staticNoticeDirectory 'LICENSE.txt'
    [IO.File]::WriteAllText($appNoticePath, "Fixture application notice.`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($staticNoticePath, "Fixture extracted static license text.`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $metadata 'THIRD-PARTY-NOTICES.txt'), "Fixture notices are complete.`n", [Text.UTF8Encoding]::new($false))

    $appArchivePath = Join-Path $cache 'application-source.zip'
    $staticArchivePath = Join-Path $cache 'test-static-source.zip'
    New-TestZip $appArchivePath
    New-TestZip $staticArchivePath

    $manifest = [ordered]@{
        schemaVersion = 1
        createdAtUtc = '2026-09-16T00:00:00Z'
        files = @(
            [ordered]@{ path = 'app.exe'; sha256 = (Get-TestSha256 $appPath); length = (Get-Item $appPath).Length },
            [ordered]@{ path = 'settings.json'; sha256 = (Get-TestSha256 $settingsPath); length = (Get-Item $settingsPath).Length }
        )
    }
    $manifestPath = Join-Path $candidate 'candidate-manifest.json'
    Write-TestJson $manifestPath $manifest

    $commit = '0123456789abcdef0123456789abcdef01234567'
    $appSourceUrl = "https://github.com/example/application/archive/$commit.zip"
    $staticSourceUrl = "https://github.com/example/test-static/archive/$commit.zip"
    $lock = [ordered]@{
        schemaVersion = 'karon-license-lock/v2'
        release = [ordered]@{
            tag = 'v2.19.1-karon.2'
            platform = 'win-x64'
            verificationStatus = 'verified'
            blockers = @()
            metadataPackage = [ordered]@{
                id = 'release-metadata'
                name = 'Fixture release metadata'
                version = 'v2.19.1-karon.2'
                licenseExpression = 'CC0-1.0'
                licenseConcluded = 'CC0-1.0'
                sourceCommit = $commit
                downloadLocation = $appSourceUrl
            }
            candidateFiles = @(
                [ordered]@{ path = 'app.exe'; sha256 = (Get-TestSha256 $appPath); package = 'application'; licenseConcluded = 'MIT AND LicenseRef-Test-Static' },
                [ordered]@{ path = 'settings.json'; sha256 = (Get-TestSha256 $settingsPath); package = 'application'; licenseConcluded = 'MIT' },
                [ordered]@{ path = 'candidate-manifest.json'; sha256 = (Get-TestSha256 $manifestPath); package = 'release-metadata'; licenseConcluded = 'CC0-1.0' }
            )
        }
        components = @(
            [ordered]@{
                id = 'application'
                name = 'Fixture application'
                version = '1.0.0'
                sourceRepository = 'https://github.com/example/application'
                sourceCommit = $commit
                licenseExpression = 'MIT'
                licenseConcluded = 'MIT AND LicenseRef-Test-Static'
                verificationStatus = 'verified'
                blockers = @()
                modified = $true
                filesAnalyzed = $true
                noticeFiles = @([ordered]@{ path = 'release/licenses/application/NOTICE.txt'; sha256 = (Get-TestSha256 $appNoticePath) })
                sourceArchives = @([ordered]@{ fileName = 'application-source.zip'; commit = $commit; url = $appSourceUrl; sha256 = (Get-TestSha256 $appArchivePath) })
                buildRecipe = 'Compile the pinned fixture application source.'
            },
            [ordered]@{
                id = 'test-static'
                name = 'Fixture static dependency'
                version = '2.0.0'
                sourceRepository = 'https://github.com/example/test-static'
                sourceCommit = $commit
                licenseExpression = 'LicenseRef-Test-Static'
                licenseConcluded = 'LicenseRef-Test-Static'
                verificationStatus = 'verified'
                blockers = @()
                modified = $false
                filesAnalyzed = $false
                staticLinkTarget = 'application'
                noticeFiles = @([ordered]@{ path = 'release/licenses/test-static/LICENSE.txt'; sha256 = (Get-TestSha256 $staticNoticePath) })
                sourceArchives = @([ordered]@{ fileName = 'test-static-source.zip'; commit = $commit; url = $staticSourceUrl; sha256 = (Get-TestSha256 $staticArchivePath) })
                licenseRefs = @([ordered]@{ licenseId = 'LicenseRef-Test-Static'; name = 'Fixture static license'; noticePath = 'release/licenses/test-static/LICENSE.txt' })
                buildRecipe = 'Compile and statically link the pinned fixture dependency.'
            }
        )
    }
    $lockPath = Join-Path $metadata 'lock.json'
    Write-TestJson $lockPath $lock

    [pscustomobject]@{
        Root = $root
        Candidate = $candidate
        Metadata = $metadata
        Cache = $cache
        Output = $output
        Lock = $lock
        LockPath = $lockPath
        Manifest = $manifest
        ManifestPath = $manifestPath
        AppNoticePath = $appNoticePath
        StaticNoticePath = $staticNoticePath
    }
}

function Save-TestLock {
    param([Parameter(Mandatory)] [object] $Case)
    Write-TestJson $Case.LockPath $Case.Lock
}

function Save-TestManifest {
    param([Parameter(Mandatory)] [object] $Case)
    Write-TestJson $Case.ManifestPath $Case.Manifest
    $entry = @($Case.Lock.release.candidateFiles | Where-Object { $_.path -ceq 'candidate-manifest.json' })[0]
    $entry.sha256 = Get-TestSha256 $Case.ManifestPath
    Save-TestLock $Case
}

function Invoke-TestTool {
    param([Parameter(Mandatory)] [string] $ScriptPath, [Parameter(Mandatory)] [string[]] $Arguments)
    $output = @(& pwsh -NoLogo -NoProfile -File $ScriptPath @Arguments 2>&1)
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

function Invoke-TestSpdx {
    param([Parameter(Mandatory)] [object] $Case, [string] $LockPath = $Case.LockPath, [string] $SourceRoot = $Case.Metadata)
    Invoke-TestTool $script:SpdxTool @('-LockPath', $LockPath, '-SourceRoot', $SourceRoot, '-CandidateRoot', $Case.Candidate, '-OutputDirectory', $Case.Output)
}

function Invoke-TestSources {
    param([Parameter(Mandatory)] [object] $Case, [string] $LockPath = $Case.LockPath, [string] $SourceRoot = $Case.Metadata)
    Invoke-TestTool $script:SourceTool @('-LockPath', $LockPath, '-SourceRoot', $SourceRoot, '-CandidateRoot', $Case.Candidate, '-CacheDirectory', $Case.Cache, '-OutputDirectory', $Case.Output)
}

function Invoke-TestToolWithFinalInjection {
    param(
        [Parameter(Mandatory)] [string] $ScriptPath,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [string] $OutputDirectory,
        [Parameter(Mandatory)] [string] $SeedPath,
        [Parameter(Mandatory)] [string] $FinalPath
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command pwsh).Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $ScriptPath) + $Arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $watcher = [IO.FileSystemWatcher]::new($OutputDirectory, '*.partial')
    $watcher.NotifyFilter = [IO.NotifyFilters]::FileName
    $watcher.EnableRaisingEvents = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $started = $false
    try {
        $started = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $change = $watcher.WaitForChanged([IO.WatcherChangeTypes]::Created, 30000)
        if ($change.TimedOut) { throw 'race_partial_timeout' }

        [IO.File]::Copy($SeedPath, $FinalPath, $false)
        $seedSha256 = Get-TestSha256 $SeedPath
        $seedLength = (Get-Item -LiteralPath $SeedPath).Length
        if (-not $process.WaitForExit(30000)) { throw 'race_process_timeout' }

        $output = ($stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()).Trim()
        $finalExists = Test-Path -LiteralPath $FinalPath -PathType Leaf
        $finalSha256 = if ($finalExists) { Get-TestSha256 $FinalPath } else { $null }
        $finalLength = if ($finalExists) { (Get-Item -LiteralPath $FinalPath).Length } else { -1 }
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = $output
            FinalExists = $finalExists
            SeedSha256 = $seedSha256
            FinalSha256 = $finalSha256
            SeedLength = $seedLength
            FinalLength = $finalLength
            PartialCount = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*.partial' -File -Force).Count
        }
    }
    finally {
        if ($started -and -not $process.HasExited) {
            $process.Kill($true)
            $process.WaitForExit()
        }
        $process.Dispose()
        $watcher.Dispose()
    }
}

Describe 'Fail-closed lock and candidate contract' {
    It 'refuses the committed real NOT_VERIFIED lock in both generators' -TestCases @(
        @{ Tool = 'spdx'; ErrorId = 'spdx_release_not_verified' },
        @{ Tool = 'sources'; ErrorId = 'source_release_not_verified' }
    ) {
        param($Tool, $ErrorId)
        $case = New-LicenseBundleCase "real-lock-$Tool"
        $result = if ($Tool -eq 'spdx') { Invoke-TestSpdx $case $script:RealLock $script:SourceRoot } else { Invoke-TestSources $case $script:RealLock $script:SourceRoot }
        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match $ErrorId
    }

    It 'rejects missing or non-exact verification status' -TestCases @(
        @{ Scope = 'release'; Value = $null; ErrorId = 'spdx_release_status_missing' },
        @{ Scope = 'release'; Value = 'Verified'; ErrorId = 'spdx_release_not_verified' },
        @{ Scope = 'component'; Value = $null; ErrorId = 'spdx_component_status_missing' },
        @{ Scope = 'component'; Value = 'UNKNOWN'; ErrorId = 'spdx_component_not_verified' }
    ) {
        param($Scope, $Value, $ErrorId)
        $case = New-LicenseBundleCase "status-$Scope-$Value"
        $target = if ($Scope -eq 'release') { $case.Lock.release } else { $case.Lock.components[0] }
        if ($null -eq $Value) { [void]$target.Remove('verificationStatus') } else { $target.verificationStatus = $Value }
        Save-TestLock $case
        $result = Invoke-TestSpdx $case
        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match $ErrorId
    }

    It 'rejects missing or nonempty blockers' -TestCases @(
        @{ Scope = 'release'; Missing = $true; ErrorId = 'spdx_release_blockers_missing' },
        @{ Scope = 'release'; Missing = $false; ErrorId = 'spdx_release_blocked' },
        @{ Scope = 'component'; Missing = $true; ErrorId = 'spdx_component_blockers_missing' },
        @{ Scope = 'component'; Missing = $false; ErrorId = 'spdx_component_blocked' }
    ) {
        param($Scope, $Missing, $ErrorId)
        $case = New-LicenseBundleCase "blockers-$Scope-$Missing"
        $target = if ($Scope -eq 'release') { $case.Lock.release } else { $case.Lock.components[0] }
        if ($Missing) { [void]$target.Remove('blockers') } else { $target.blockers = @('open blocker') }
        Save-TestLock $case
        $result = Invoke-TestSpdx $case
        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match $ErrorId
    }

    It 'rejects unresolved markers even when notice hash matches' -TestCases @(
        @{ Marker = 'NOT_VERIFIED' },
        @{ Marker = 'UNKNOWN' },
        @{ Marker = 'TODO' },
        @{ Marker = 'unresolved blocker' }
    ) {
        param($Marker)
        $case = New-LicenseBundleCase "notice-marker-$Marker"
        [IO.File]::WriteAllText($case.AppNoticePath, "Fixture $Marker`n", [Text.UTF8Encoding]::new($false))
        $case.Lock.components[0].noticeFiles[0].sha256 = Get-TestSha256 $case.AppNoticePath
        Save-TestLock $case
        $result = Invoke-TestSpdx $case
        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match 'spdx_notice_unresolved_marker'
    }

    It 'rejects extra, missing, duplicate-case, or unknown-package candidate inventory' -TestCases @(
        @{ Mutation = 'extra' },
        @{ Mutation = 'missing' },
        @{ Mutation = 'duplicate-case' },
        @{ Mutation = 'unknown-package' }
    ) {
        param($Mutation)
        $case = New-LicenseBundleCase "inventory-$Mutation"
        switch ($Mutation) {
            'extra' { [IO.File]::WriteAllBytes((Join-Path $case.Candidate 'extra.bin'), [byte[]](9)) }
            'missing' { Remove-Item -LiteralPath (Join-Path $case.Candidate 'settings.json') -Force }
            'duplicate-case' { $case.Lock.release.candidateFiles += [ordered]@{ path = 'APP.EXE'; sha256 = $case.Lock.release.candidateFiles[0].sha256; package = 'application'; licenseConcluded = 'MIT' }; Save-TestLock $case }
            'unknown-package' { $case.Lock.release.candidateFiles[0].package = 'absent'; Save-TestLock $case }
        }
        $result = Invoke-TestSpdx $case
        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match 'spdx_candidate_(inventory|package)'
    }

    It 'cross-checks candidate manifest path, hash, and length inventory' -TestCases @(
        @{ Mutation = 'hash' },
        @{ Mutation = 'missing' },
        @{ Mutation = 'duplicate-case' }
    ) {
        param($Mutation)
        $case = New-LicenseBundleCase "manifest-$Mutation"
        switch ($Mutation) {
            'hash' { $case.Manifest.files[0].sha256 = '0' * 64 }
            'missing' { $case.Manifest.files = @($case.Manifest.files[0]) }
            'duplicate-case' { $case.Manifest.files += [ordered]@{ path = 'APP.EXE'; sha256 = $case.Manifest.files[0].sha256; length = $case.Manifest.files[0].length } }
        }
        Save-TestManifest $case
        $result = Invoke-TestSpdx $case
        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match 'spdx_candidate_manifest_(hash|inventory|duplicate)'
    }

    It 'rejects an explicit candidate-manifest length mismatch in both generators' -TestCases @(
        @{ Tool = 'spdx'; ErrorPrefix = 'spdx' },
        @{ Tool = 'sources'; ErrorPrefix = 'source' }
    ) {
        param($Tool, $ErrorPrefix)
        $case = New-LicenseBundleCase "manifest-length-$Tool"
        $case.Manifest.files[0].length = [long]$case.Manifest.files[0].length + 1
        Save-TestManifest $case
        $result = if ($Tool -eq 'spdx') { Invoke-TestSpdx $case } else { Invoke-TestSources $case }
        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match ($ErrorPrefix + '_candidate_manifest_inventory_mismatch: app\.exe')
        @(Get-ChildItem -LiteralPath $case.Output -Force).Count | Should Be 0
    }

    It 'rejects NOASSERTION license metadata and missing notice or source metadata' -TestCases @(
        @{ Mutation = 'license' },
        @{ Mutation = 'notice' },
        @{ Mutation = 'source' }
    ) {
        param($Mutation)
        $case = New-LicenseBundleCase "metadata-$Mutation"
        switch ($Mutation) {
            'license' { $case.Lock.components[0].licenseExpression = 'NOASSERTION' }
            'notice' { $case.Lock.components[0].noticeFiles = @() }
            'source' { $case.Lock.components[0].sourceArchives = @() }
        }
        Save-TestLock $case
        $result = Invoke-TestSpdx $case
        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match 'spdx_(license_unverified|notice_or_source_missing)'
    }
}

Describe 'SPDX 2.3 generation semantics' {
    It 'generates the exact named SPDX with verification codes, static links, immutable downloads, and extracted LicenseRef text' {
        $case = New-LicenseBundleCase 'spdx-positive'
        $result = Invoke-TestSpdx $case
        $path = Join-Path $case.Output 'ytdlp-korean-interface-v2.19.1-karon.2.spdx.json'
        if ($result.ExitCode -ne 0) { throw "positive SPDX generation failed: $($result.Output)" }
        $result.Output.Trim() | Should Be $path
        @(Get-ChildItem -LiteralPath $case.Output -File).Count | Should Be 1

        $document = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 64
        $document.spdxVersion | Should Be 'SPDX-2.3'
        @($document.files).Count | Should Be 3
        @($document.packages).Count | Should Be 3

        $appPackage = @($document.packages | Where-Object SPDXID -ceq 'SPDXRef-Package-application')[0]
        $staticPackage = @($document.packages | Where-Object SPDXID -ceq 'SPDXRef-Package-test-static')[0]
        $metadataPackage = @($document.packages | Where-Object SPDXID -ceq 'SPDXRef-Package-release-metadata')[0]
        $appPackage.filesAnalyzed | Should Be $true
        $appPackage.packageVerificationCode.packageVerificationCodeValue | Should Be $script:FixtureApplicationVerificationCode
        $metadataPackage.packageVerificationCode.packageVerificationCodeValue | Should Be $script:FixtureMetadataVerificationCode
        $staticPackage.filesAnalyzed | Should Be $false
        ($null -eq $staticPackage.PSObject.Properties['packageVerificationCode']) | Should Be $true

        $staticLinks = @($document.relationships | Where-Object relationshipType -ceq 'STATIC_LINK')
        @($staticLinks).Count | Should Be 1
        $staticLinks[0].spdxElementId | Should Be 'SPDXRef-Package-application'
        $staticLinks[0].relatedSpdxElement | Should Be 'SPDXRef-Package-test-static'
        @($document.relationships | Where-Object { $_.relationshipType -ceq 'CONTAINS' -and $_.spdxElementId -ceq 'SPDXRef-Package-test-static' }).Count | Should Be 0

        foreach ($package in @($document.packages)) { $package.downloadLocation | Should Match '^https://[^?#]+/[0-9a-f]{40}\.zip$' }
        foreach ($file in @($document.files)) {
            @($file.checksums | Where-Object algorithm -ceq 'SHA1').Count | Should Be 1
            @($file.checksums | Where-Object algorithm -ceq 'SHA256').Count | Should Be 1
            $file.licenseConcluded | Should Not Match 'NOASSERTION|NOT_VERIFIED|UNKNOWN'
        }
        @($document.files | Where-Object fileName -ceq './candidate-manifest.json')[0].licenseConcluded | Should Be 'CC0-1.0'
        @($document.hasExtractedLicensingInfos).Count | Should Be 1
        $document.hasExtractedLicensingInfos[0].licenseId | Should Be 'LicenseRef-Test-Static'
        $document.hasExtractedLicensingInfos[0].extractedText | Should Be "Fixture extracted static license text.`n"
    }

    It 'validates positive output against the commit-pinned official SPDX 2.3 JSON schema with pinned jsonschema' {
        (Get-TestSha256 $script:OfficialSchema) | Should Be $script:OfficialSchemaSha256
        $schemaBytes = [IO.File]::ReadAllBytes($script:OfficialSchema)
        $schemaBytes[-1] | Should Be 10
        $upstreamBytes = [byte[]]::new($schemaBytes.Length - 1)
        [Array]::Copy($schemaBytes, $upstreamBytes, $upstreamBytes.Length)
        $upstreamHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($upstreamBytes)).ToLowerInvariant()
        $upstreamHash | Should Be $script:OfficialSchemaUpstreamSha256
        $case = New-LicenseBundleCase 'spdx-official-schema'
        $result = Invoke-TestSpdx $case
        if ($result.ExitCode -ne 0) { throw "schema fixture SPDX generation failed: $($result.Output)" }
        $path = Join-Path $case.Output 'ytdlp-korean-interface-v2.19.1-karon.2.spdx.json'
        $code = @'
import importlib.metadata
import json
import sys
import jsonschema
schema = json.load(open(sys.argv[1], encoding="utf-8"))
document = json.load(open(sys.argv[2], encoding="utf-8"))
version = importlib.metadata.version("jsonschema")
print("jsonschema=" + version)
if version != sys.argv[3]:
    raise SystemExit("unexpected jsonschema version: " + version)
jsonschema.Draft7Validator.check_schema(schema)
errors = sorted(jsonschema.Draft7Validator(schema).iter_errors(document), key=lambda error: list(error.path))
for error in errors:
    print(error.json_path + ": " + error.message)
raise SystemExit(1 if errors else 0)
'@
        $validation = @(& python -c $code $script:OfficialSchema $path $script:ExpectedJsonSchemaVersion 2>&1)
        $LASTEXITCODE | Should Be 0
        ($validation -join "`n") | Should Match "jsonschema=$($script:ExpectedJsonSchemaVersion)"
    }
}

Describe 'Atomic corresponding-source bundle generation' {
    It 'generates only the exact named ZIP with the exact expected inventory' {
        $case = New-LicenseBundleCase 'sources-positive'
        $result = Invoke-TestSources $case
        $bundle = 'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources'
        $path = Join-Path $case.Output "$bundle.zip"
        $result.ExitCode | Should Be 0
        $result.Output.Trim() | Should Be $path
        @(Get-ChildItem -LiteralPath $case.Output -File).Count | Should Be 1

        $zip = [IO.Compression.ZipFile]::OpenRead($path)
        try { $actual = @($zip.Entries | ForEach-Object FullName | Sort-Object) }
        finally { $zip.Dispose() }
        $expected = @(
            "$bundle/THIRD-PARTY-NOTICES.txt",
            "$bundle/release/dependencies/v2.19.1-karon.2.lock.json",
            "$bundle/release/licenses/application/NOTICE.txt",
            "$bundle/release/licenses/test-static/LICENSE.txt",
            "$bundle/sources/application/application-source.zip",
            "$bundle/sources/test-static/test-static-source.zip"
        ) | Sort-Object
        ($actual -join "`n") | Should Be ($expected -join "`n")
        @($actual | Sort-Object -Unique).Count | Should Be $actual.Count
    }

    It 'rejects an unsafe source ZIP and leaves no final or partial output' {
        $case = New-LicenseBundleCase 'unsafe-source-archive'
        $archivePath = Join-Path $case.Cache 'application-source.zip'
        New-TestZip $archivePath '../escape.txt'
        $case.Lock.components[0].sourceArchives[0].sha256 = Get-TestSha256 $archivePath
        Save-TestLock $case
        $result = Invoke-TestSources $case
        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match 'source_archive_entry_unsafe'
        @(Get-ChildItem -LiteralPath $case.Output -Force).Count | Should Be 0
    }

    It 'rejects duplicate output entries and cleans every partial artifact' {
        $case = New-LicenseBundleCase 'duplicate-output-entry'
        $case.Lock.components[0].sourceArchives += $case.Lock.components[0].sourceArchives[0]
        Save-TestLock $case
        $result = Invoke-TestSources $case
        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match 'source_output_entry_duplicate'
        @(Get-ChildItem -LiteralPath $case.Output -Force).Count | Should Be 0
    }

    It 'rejects candidate hash mismatch through the authoritative release inventory' {
        $case = New-LicenseBundleCase 'source-candidate-hash'
        $case.Lock.release.candidateFiles[0].sha256 = '0' * 64
        Save-TestLock $case
        $result = Invoke-TestSources $case
        $result.ExitCode | Should Not Be 0
        $result.Output | Should Match 'source_candidate_hash_mismatch'
        @(Get-ChildItem -LiteralPath $case.Output -Force).Count | Should Be 0
    }
}

Describe 'Atomic output ownership under check-to-move races' {
    It 'preserves an independently created SPDX artifact byte-for-byte and cleans only its partial' {
        $case = New-LicenseBundleCase 'spdx-output-race'
        $largeNotice = "Fixture extracted static license text.`n" + ('x' * (8 * 1024 * 1024))
        [IO.File]::WriteAllText($case.StaticNoticePath, $largeNotice, [Text.UTF8Encoding]::new($false))
        $case.Lock.components[1].noticeFiles[0].sha256 = Get-TestSha256 $case.StaticNoticePath
        Save-TestLock $case

        $seedDirectory = Join-Path $case.Root 'seed-output'
        $raceDirectory = Join-Path $case.Root 'race-output'
        New-Item -ItemType Directory -Path $seedDirectory, $raceDirectory | Out-Null
        $arguments = @('-LockPath', $case.LockPath, '-SourceRoot', $case.Metadata, '-CandidateRoot', $case.Candidate)
        $seedResult = Invoke-TestTool $script:SpdxTool ($arguments + @('-OutputDirectory', $seedDirectory))
        if ($seedResult.ExitCode -ne 0) { throw "seed SPDX generation failed: $($seedResult.Output)" }

        $name = 'ytdlp-korean-interface-v2.19.1-karon.2.spdx.json'
        $seedPath = Join-Path $seedDirectory $name
        $finalPath = Join-Path $raceDirectory $name
        $race = Invoke-TestToolWithFinalInjection $script:SpdxTool ($arguments + @('-OutputDirectory', $raceDirectory)) $raceDirectory $seedPath $finalPath
        Write-Host ('RACE_RESULT generator=spdx ' + (($race | Select-Object ExitCode, FinalExists, SeedSha256, FinalSha256, SeedLength, FinalLength, PartialCount) | ConvertTo-Json -Compress))

        $race.ExitCode | Should Not Be 0
        $race.FinalExists | Should Be $true
        $race.FinalSha256 | Should Be $race.SeedSha256
        $race.FinalLength | Should Be $race.SeedLength
        $race.PartialCount | Should Be 0
    }

    It 'preserves an independently created source bundle byte-for-byte and cleans only its partial' {
        $case = New-LicenseBundleCase 'source-output-race'
        $largeNotice = "Fixture extracted static license text.`n" + ('x' * (8 * 1024 * 1024))
        [IO.File]::WriteAllText($case.StaticNoticePath, $largeNotice, [Text.UTF8Encoding]::new($false))
        $case.Lock.components[1].noticeFiles[0].sha256 = Get-TestSha256 $case.StaticNoticePath
        Save-TestLock $case

        $seedDirectory = Join-Path $case.Root 'seed-output'
        $raceDirectory = Join-Path $case.Root 'race-output'
        New-Item -ItemType Directory -Path $seedDirectory, $raceDirectory | Out-Null
        $arguments = @('-LockPath', $case.LockPath, '-SourceRoot', $case.Metadata, '-CandidateRoot', $case.Candidate, '-CacheDirectory', $case.Cache)
        $seedResult = Invoke-TestTool $script:SourceTool ($arguments + @('-OutputDirectory', $seedDirectory))
        if ($seedResult.ExitCode -ne 0) { throw "seed source generation failed: $($seedResult.Output)" }

        $name = 'ytdlp-korean-interface-v2.19.1-karon.2-corresponding-sources.zip'
        $seedPath = Join-Path $seedDirectory $name
        $finalPath = Join-Path $raceDirectory $name
        $race = Invoke-TestToolWithFinalInjection $script:SourceTool ($arguments + @('-OutputDirectory', $raceDirectory)) $raceDirectory $seedPath $finalPath
        Write-Host ('RACE_RESULT generator=sources ' + (($race | Select-Object ExitCode, FinalExists, SeedSha256, FinalSha256, SeedLength, FinalLength, PartialCount) | ConvertTo-Json -Compress))

        $race.ExitCode | Should Not Be 0
        $race.FinalExists | Should Be $true
        $race.FinalSha256 | Should Be $race.SeedSha256
        $race.FinalLength | Should Be $race.SeedLength
        $race.PartialCount | Should Be 0
    }
}
