[CmdletBinding()]
param(
    [string] $SourceArchive,
    [string] $OutputDirectory,
    [string] $DefinitionPath,
    [string] $ReleaseRequestPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:BuildToolPath = $MyInvocation.MyCommand.Path
$script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:DefaultDefinitionPath = Join-Path $script:RepositoryRoot 'release\runtime\v2.19.1-karon.2\sevenzip-no-rar.json'
$script:DefaultNoticePath = Join-Path $script:RepositoryRoot 'release\runtime\v2.19.1-karon.2\BSD-NOTICES.txt'
$script:Utf8NoBom = [Text.UTF8Encoding]::new($false)

function Get-Sha256 {
    param([Parameter(Mandatory = $true)] [string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-BytesSha256 {
    param([Parameter(Mandatory = $true)] [byte[]] $Bytes)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return (($algorithm.ComputeHash($Bytes) | ForEach-Object { $_.ToString('X2') }) -join '') }
    finally { $algorithm.Dispose() }
}

function Get-SevenZipNoRarDefinition {
    param([Parameter(Mandatory = $true)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'sevenzip_definition_invalid' }
    try { $definition = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { throw 'sevenzip_definition_invalid' }
    if ($definition.schemaVersion -ne 1 -or $definition.artifactName -cne '7z2601-x64-no-rar.7z' -or
        $definition.source.repository -cne 'ip7z/7zip' -or $definition.source.release -cne '26.01' -or
        $definition.source.commit -cne '8c63d71ff886bda90c86db28466287f977374237' -or
        [string]$definition.source.archiveSha256 -notmatch '^[A-F0-9]{64}$' -or
        [string]$definition.source.arcMakSha256 -notmatch '^[A-F0-9]{64}$' -or
        [string]$definition.source.patchedArcMakSha256 -notmatch '^[A-F0-9]{64}$') { throw 'sevenzip_definition_invalid' }
    $objects = @($definition.excludedObjects)
    if ($objects.Count -ne 11 -or @($objects | Sort-Object -Unique).Count -ne 11 -or
        @($objects | Where-Object { $_ -notmatch '^Rar[A-Za-z0-9]+\.obj$' }).Count -ne 0) { throw 'sevenzip_definition_invalid' }
    return $definition
}

function Assert-RelativeArchivePath {
    param([Parameter(Mandatory = $true)] [string] $Path)
    $normalized = $Path.Replace('\', '/').TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized.StartsWith('/') -or $normalized -match '^[A-Za-z]:' -or
        @($normalized.Split('/') | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -ne 0) {
        throw 'sevenzip_source_archive_unsafe'
    }
    return $normalized
}

function Assert-SevenZipSourceArchive {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $ExpectedSha256
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or $ExpectedSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'sevenzip_source_archive_invalid' }
    if ((Get-Sha256 $Path) -cne $ExpectedSha256.ToUpperInvariant()) { throw 'sevenzip_source_sha256_mismatch' }
    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
    try {
        $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            $roots = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            foreach ($entry in $archive.Entries) {
                $normalized = Assert-RelativeArchivePath $entry.FullName
                if (-not $seen.Add($normalized)) { throw 'sevenzip_source_archive_unsafe' }
                [void]$roots.Add($normalized.Split('/')[0])
                $unixType = ($entry.ExternalAttributes -shr 16) -band 0xF000
                if ($unixType -eq 0xA000) { throw 'sevenzip_source_archive_unsafe' }
            }
            if ($roots.Count -ne 1) { throw 'sevenzip_source_archive_unsafe' }
            return [pscustomobject]@{ RootName = @($roots)[0]; EntryCount = $seen.Count; Sha256 = $ExpectedSha256.ToUpperInvariant() }
        }
        finally { $archive.Dispose() }
    }
    catch {
        if ($_.Exception.Message -like 'sevenzip_*') { throw }
        throw 'sevenzip_source_archive_unsafe'
    }
    finally { $stream.Dispose() }
}

function Get-SevenZipNoRarArcMak {
    param(
        [Parameter(Mandatory = $true)] [string] $Content,
        [Parameter(Mandatory = $true)] [string[]] $ExcludedObjects
    )
    $patched = $Content
    foreach ($name in $ExcludedObjects) {
        $pattern = '(?m)^  \$O\\' + [regex]::Escape($name) + ' \\\r?\n'
        if ([regex]::Matches($patched, $pattern).Count -ne 1) { throw 'sevenzip_rar_exclusion_contract_mismatch' }
        $patched = [regex]::Replace($patched, $pattern, '')
    }
    $headerPattern = '(?m)^RAR_OBJS = \\\r?\n'
    if ([regex]::Matches($patched, $headerPattern).Count -ne 1) { throw 'sevenzip_rar_exclusion_contract_mismatch' }
    $patched = [regex]::Replace($patched, $headerPattern, '')
    if ($patched -match '(?i)rar' -or $patched -notmatch '\$O\\7zHandler\.obj' -or $patched -notmatch '\$O\\ZipHandler\.obj') {
        throw 'sevenzip_rar_exclusion_contract_mismatch'
    }
    return $patched
}

function Get-SevenZipLinkObjectNames {
    param([Parameter(Mandatory = $true)] [string] $BuildLogPath)
    $content = Get-Content -LiteralPath $BuildLogPath -Raw
    return @([regex]::Matches($content, '(?i)(?:^|\s)(?:[^\s"/\\]+[/\\])*([^\s"/\\]+\.obj)(?=\s|$)') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
}

function Assert-SevenZipNoRarBuildMap {
    param([Parameter(Mandatory = $true)] [string[]] $ObjectNames)
    if (@($ObjectNames | Where-Object { $_ -match '(?i)rar' }).Count -ne 0) { throw 'sevenzip_rar_object_detected' }
}

function Get-SevenZipArchiveEntries {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $SevenZipPath
    )
    $output = @(& $SevenZipPath l -slt -- $Path 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw 'sevenzip_runtime_archive_invalid' }
    $records = @(); $record = @{}; $inEntries = $false
    foreach ($line in $output) {
        $text = [string]$line
        if ($text -match '^-{10,}$') { $inEntries = $true; continue }
        if (-not $inEntries) { continue }
        if ([string]::IsNullOrWhiteSpace($text)) {
            if ($record.Count -ne 0) { $records += [pscustomobject]$record; $record = @{} }
            continue
        }
        if ($text -match '^([^=]+) = (.*)$') { $record[$matches[1].Trim()] = $matches[2] }
    }
    if ($record.Count -ne 0) { $records += [pscustomobject]$record }
    return @($records | Where-Object {
        $isFolder = ($null -ne $_.PSObject.Properties['Folder'] -and [string]$_.Folder -eq '+') -or
            ($null -ne $_.PSObject.Properties['Attributes'] -and [string]$_.Attributes -match '^D')
        -not $isFolder
    } | ForEach-Object { ([string]$_.Path).Replace('\', '/') })
}

function Assert-SevenZipRuntimeArchive {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [string] $SevenZipPath,
        [Parameter(Mandatory = $true)] [string[]] $ExpectedEntries
    )
    $actual = @(Get-SevenZipArchiveEntries -Path $Path -SevenZipPath $SevenZipPath | Sort-Object)
    $expected = @($ExpectedEntries | Sort-Object)
    if (($actual -join ',') -cne ($expected -join ',') -or
        @($actual | Where-Object { $_ -match '(?i)(^|/)(rar5?|unrar)(/|\.|$)' }).Count -ne 0) {
        throw 'sevenzip_runtime_archive_layout_invalid'
    }
}

function Invoke-SevenZipRuntimeChecks {
    param(
        [Parameter(Mandatory = $true)] [string] $DllPath,
        [Parameter(Mandatory = $true)] [string] $HostPath
    )
    $root = Join-Path ([IO.Path]::GetTempPath()) ('karon-sevenzip-runtime-' + [Guid]::NewGuid().ToString('N'))
    $hostRoot = Join-Path $root 'host'; $payloadRoot = Join-Path $root 'payload'; $zipOut = Join-Path $root 'zip-out'; $sevenOut = Join-Path $root 'seven-out'
    foreach ($path in @($hostRoot, $payloadRoot, $zipOut, $sevenOut)) { [IO.Directory]::CreateDirectory($path) | Out-Null }
    try {
        $hostExe = Join-Path $hostRoot '7z.exe'; $dll = Join-Path $hostRoot '7z.dll'
        Copy-Item -LiteralPath $HostPath -Destination $hostExe
        Copy-Item -LiteralPath $DllPath -Destination $dll
        $infoOutput = @(& $hostExe i 2>&1); $infoExitCode = $LASTEXITCODE

        Add-Type -AssemblyName System.IO.Compression
        $zipPath = Join-Path $root 'fixture.zip'
        $stream = [IO.File]::Open($zipPath, [IO.FileMode]::CreateNew)
        try {
            $zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
            try {
                $entry = $zip.CreateEntry('payload.txt'); $writer = New-Object IO.StreamWriter($entry.Open(), $script:Utf8NoBom)
                try { $writer.Write('karon-zip-payload') } finally { $writer.Dispose() }
            }
            finally { $zip.Dispose() }
        }
        finally { $stream.Dispose() }

        [IO.File]::WriteAllText((Join-Path $payloadRoot 'payload.txt'), 'karon-7z-payload', $script:Utf8NoBom)
        $sevenPath = Join-Path $root 'fixture.7z'
        Push-Location $payloadRoot
        try { $sevenCreateOutput = @(& $hostExe a -t7z -mx=1 -- $sevenPath 'payload.txt' 2>&1); $sevenCreateExitCode = $LASTEXITCODE }
        finally { Pop-Location }
        $zipOutput = @(& $hostExe x -y ('-o' + $zipOut) -- $zipPath 2>&1); $zipExitCode = $LASTEXITCODE
        $sevenOutput = @(& $hostExe x -y ('-o' + $sevenOut) -- $sevenPath 2>&1); $sevenExitCode = $LASTEXITCODE
        if ($infoExitCode -ne 0 -or $sevenCreateExitCode -ne 0 -or $zipExitCode -ne 0 -or $sevenExitCode -ne 0) { throw 'sevenzip_runtime_verification_failed' }
        $infoText = $infoOutput -join "`n"
        if ($infoText -notmatch '(?im)^\s*0\s+.*\s7z\s+7z\s' -or $infoText -notmatch '(?im)^\s*0\s+.*\szip\s+zip\s' -or
            $infoText -match '(?im)^\s*0\s+.*\sRar(?:1|2|3|5)?(?:\s|$)') { throw 'sevenzip_runtime_format_contract_failed' }
        return [ordered]@{
            InfoExitCode = $infoExitCode
            ZipExitCode = $zipExitCode
            SevenZipExitCode = $sevenExitCode
            InfoOutput = $infoText
            ZipPayload = [IO.File]::ReadAllText((Join-Path $zipOut 'payload.txt'))
            SevenZipPayload = [IO.File]::ReadAllText((Join-Path $sevenOut 'payload.txt'))
            Commands = @('7z.exe i', '7z.exe a -t7z -mx=1 fixture.7z payload.txt', '7z.exe x -y fixture.zip', '7z.exe x -y fixture.7z')
        }
    }
    finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } }
}

function Test-SevenZipNoRarRuntime {
    param(
        [Parameter(Mandatory = $true)] [string] $RuntimeArchivePath,
        [Parameter(Mandatory = $true)] [string] $HostPath
    )
    $reader = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
    $root = Join-Path ([IO.Path]::GetTempPath()) ('karon-sevenzip-artifact-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($root) | Out-Null
    try {
        & $reader x -y ('-o' + $root) -- $RuntimeArchivePath | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'sevenzip_runtime_archive_invalid' }
        return Invoke-SevenZipRuntimeChecks -DllPath (Join-Path $root 'x64\7z.dll') -HostPath $HostPath
    }
    finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue } }
}

function Enter-SevenZipVsEnvironment {
    param([Parameter(Mandatory = $true)] [string] $WorkRoot)
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    $installation = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json | ConvertFrom-Json)[0]
    if ($null -eq $installation) { throw 'sevenzip_vs2022_v143_not_found' }
    $devCmd = Join-Path $installation.installationPath 'Common7\Tools\VsDevCmd.bat'
    $environmentScript = Join-Path $WorkRoot 'capture-vs-environment.cmd'
    [IO.File]::WriteAllText($environmentScript, "@call `"$devCmd`" -arch=x64 -host_arch=x64 >nul`r`n@set`r`n", [Text.Encoding]::ASCII)
    foreach ($line in @(& cmd.exe /d /c $environmentScript)) {
        if ([string]$line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
    }
    $tools = [ordered]@{}
    foreach ($name in @('cl.exe', 'link.exe', 'nmake.exe', 'rc.exe')) {
        $path = (Get-Command $name -ErrorAction Stop).Source
        $tools[$name] = [ordered]@{ path = $path; sha256 = Get-Sha256 $path; fileVersion = (Get-Item -LiteralPath $path).VersionInfo.FileVersion }
    }
    $sdkVersion = ([string]$env:WindowsSDKVersion).TrimEnd('\')
    $sdkRoot = [string]$env:WindowsSdkDir
    $sdkFiles = @(
        (Join-Path $sdkRoot "Lib\$sdkVersion\um\x64\kernel32.lib"),
        (Join-Path $sdkRoot "Lib\$sdkVersion\um\x64\user32.lib"),
        (Join-Path $sdkRoot "Lib\$sdkVersion\um\x64\advapi32.lib"),
        (Join-Path $sdkRoot "Lib\$sdkVersion\um\x64\shell32.lib"),
        (Join-Path $sdkRoot "Lib\$sdkVersion\um\x64\ole32.lib"),
        (Join-Path $sdkRoot "Lib\$sdkVersion\um\x64\oleaut32.lib"),
        (Join-Path $sdkRoot "Lib\$sdkVersion\ucrt\x64\libucrt.lib")
    )
    $sdkHashes = @($sdkFiles | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | ForEach-Object { [ordered]@{ path = $_; sha256 = Get-Sha256 $_ } })
    return [ordered]@{ visualStudioVersion = $installation.installationVersion; windowsSdkVersion = $sdkVersion; tools = $tools; sdkFiles = $sdkHashes; devCommand = "call `"$devCmd`" -arch=x64 -host_arch=x64" }
}

function Invoke-SevenZipNativeBuild {
    param([string] $NMakePath, [string] $WorkingDirectory, [string] $LogPath)
    Push-Location $WorkingDirectory
    try { $output = @(& $NMakePath PLATFORM=x64 2>&1); $exitCode = $LASTEXITCODE }
    finally { Pop-Location }
    [IO.File]::WriteAllLines($LogPath, @("COMMAND: `"$NMakePath`" PLATFORM=x64", "WORKING_DIRECTORY: $WorkingDirectory") + @($output | ForEach-Object { [string]$_ }), $script:Utf8NoBom)
    if ($exitCode -ne 0) { throw "sevenzip_build_failed:$exitCode" }
    return [ordered]@{ command = "`"$NMakePath`" PLATFORM=x64"; workingDirectory = $WorkingDirectory; exitCode = $exitCode; log = $LogPath }
}

function Remove-SevenZipRarSource {
    param([Parameter(Mandatory = $true)] [string] $SourceRoot)
    $archiveRar = Join-Path $SourceRoot 'CPP\7zip\Archive\Rar'
    if (Test-Path -LiteralPath $archiveRar) { Remove-Item -LiteralPath $archiveRar -Recurse -Force }
    foreach ($directory in @('CPP\7zip\Compress', 'CPP\7zip\Crypto')) {
        Get-ChildItem -LiteralPath (Join-Path $SourceRoot $directory) -File -Filter 'Rar*' | Remove-Item -Force
    }
    foreach ($path in @('DOC\License.txt', 'DOC\unRarLicense.txt')) {
        $target = Join-Path $SourceRoot $path
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
    }
    $forbidden = @(Get-ChildItem -LiteralPath (Join-Path $SourceRoot 'CPP\7zip') -Recurse -File | Where-Object {
        $relative = $_.FullName.Substring($SourceRoot.Length + 1).Replace('\', '/')
        $relative -match '^CPP/7zip/(Archive/Rar/|Compress/Rar|Crypto/Rar)'
    })
    if ($forbidden.Count -ne 0 -or (Test-Path -LiteralPath (Join-Path $SourceRoot 'DOC\unRarLicense.txt'))) { throw 'sevenzip_corresponding_source_contains_rar' }
}

function New-SevenZipArchive {
    param([string] $HostPath, [string] $ArchivePath, [string] $WorkingDirectory, [string[]] $Entries)
    Push-Location $WorkingDirectory
    try { $output = @(& $HostPath a -t7z -mx=9 -mtm=off -mtc=off -mta=off -- $ArchivePath @Entries 2>&1); $exitCode = $LASTEXITCODE }
    finally { Pop-Location }
    if ($exitCode -ne 0) { throw "sevenzip_archive_creation_failed:$exitCode`n$($output -join "`n")" }
    return [ordered]@{ command = "7z.exe a -t7z -mx=9 -mtm=off -mtc=off -mta=off $ArchivePath $($Entries -join ' ')"; exitCode = $exitCode }
}

function Update-SevenZipReleaseRequest {
    param([string] $Path, [object] $Definition, [string] $ArtifactSha256, [string] $DllSha256, [string] $SourceArchiveSha256, [string] $DefinitionSha256)
    $request = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $sevenZip = @($request.runtimeOverlays | Where-Object id -ceq 'sevenZip')
    if ($sevenZip.Count -ne 1) { throw 'sevenzip_release_request_invalid' }
    $overlay = $sevenZip[0]
    $overlay.assetUrl = $null
    $overlay.archiveName = [string]$Definition.artifactName
    $overlay.archiveSha256 = $ArtifactSha256
    $overlay.shippingPolicy = 'custom-7z.dll-only-no-rar-handlers'
    foreach ($property in ([ordered]@{
        sourceArchiveUrl = [string]$Definition.source.archiveUrl
        sourceArchiveSha256 = [string]$Definition.source.archiveSha256
        buildRecipe = 'tools/build-sevenzip-no-rar.ps1'
        buildDefinition = 'release/runtime/v2.19.1-karon.2/sevenzip-no-rar.json'
        buildDefinitionSha256 = $DefinitionSha256
        dllSha256 = $DllSha256
        correspondingSource = [ordered]@{ archiveName = [string]$Definition.correspondingSourceArchiveName; archiveSha256 = $SourceArchiveSha256 }
        provenancePath = 'provenance/build-provenance.json'
    }).GetEnumerator()) {
        if ($null -eq $overlay.PSObject.Properties[$property.Key]) { $overlay | Add-Member -NotePropertyName $property.Key -NotePropertyValue $property.Value }
        else { $overlay.($property.Key) = $property.Value }
    }
    [IO.File]::WriteAllText($Path, (($request | ConvertTo-Json -Depth 20) + "`n"), $script:Utf8NoBom)
}

function Invoke-SevenZipNoRarBuild {
    param([string] $SourceArchivePath, [string] $OutputPath, [string] $BuildDefinitionPath, [string] $RequestPath)
    $definition = Get-SevenZipNoRarDefinition -Path $BuildDefinitionPath
    $sourceIdentity = Assert-SevenZipSourceArchive -Path $SourceArchivePath -ExpectedSha256 ([string]$definition.source.archiveSha256)
    if ($sourceIdentity.RootName -cne [string]$definition.source.archiveRoot) { throw 'sevenzip_source_archive_root_mismatch' }
    [IO.Directory]::CreateDirectory($OutputPath) | Out-Null
    $artifactPath = Join-Path $OutputPath ([string]$definition.artifactName)
    $sourceArtifactPath = Join-Path $OutputPath ([string]$definition.correspondingSourceArchiveName)
    if ((Test-Path -LiteralPath $artifactPath) -or (Test-Path -LiteralPath $sourceArtifactPath)) { throw 'sevenzip_output_already_exists' }
    $workRoot = Join-Path $OutputPath ('build-work-' + [Guid]::NewGuid().ToString('N'))
    $extractRoot = Join-Path $workRoot 'upstream'; $runtimeRoot = Join-Path $workRoot 'runtime'; $sourceStageParent = Join-Path $workRoot 'corresponding-source'
    foreach ($path in @($extractRoot, $runtimeRoot, $sourceStageParent)) { [IO.Directory]::CreateDirectory($path) | Out-Null }
    [IO.Compression.ZipFile]::ExtractToDirectory((Resolve-Path -LiteralPath $SourceArchivePath).Path, $extractRoot)
    $sourceRoot = Join-Path $extractRoot ([string]$definition.source.archiveRoot)
    $arcMak = Join-Path $sourceRoot ([string]$definition.source.arcMakPath).Replace('/', '\')
    if ((Get-Sha256 $arcMak) -cne [string]$definition.source.arcMakSha256) { throw 'sevenzip_arc_mak_sha256_mismatch' }
    $patched = Get-SevenZipNoRarArcMak -Content ([IO.File]::ReadAllText($arcMak)) -ExcludedObjects @($definition.excludedObjects)
    [IO.File]::WriteAllText($arcMak, $patched, $script:Utf8NoBom)
    if ((Get-Sha256 $arcMak) -cne [string]$definition.source.patchedArcMakSha256) { throw 'sevenzip_patched_arc_mak_sha256_mismatch' }

    $sourceStage = Join-Path $sourceStageParent ([string]$definition.source.archiveRoot)
    [IO.Directory]::CreateDirectory($sourceStage) | Out-Null
    Get-ChildItem -LiteralPath $sourceRoot -Force | Copy-Item -Destination $sourceStage -Recurse
    Remove-SevenZipRarSource -SourceRoot $sourceStage
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'DOC\copying.txt') -Destination (Join-Path $sourceStage 'COPYING.LGPL-2.1.txt')
    Copy-Item -LiteralPath $script:DefaultNoticePath -Destination (Join-Path $sourceStage 'BSD-NOTICES.txt')
    $recipeRoot = Join-Path $sourceStage 'KaronBuild'; [IO.Directory]::CreateDirectory($recipeRoot) | Out-Null
    Copy-Item -LiteralPath $script:BuildToolPath -Destination (Join-Path $recipeRoot 'build-sevenzip-no-rar.ps1')
    Copy-Item -LiteralPath $BuildDefinitionPath -Destination (Join-Path $recipeRoot 'sevenzip-no-rar.json')

    $toolchain = Enter-SevenZipVsEnvironment -WorkRoot $workRoot
    $env:LFLAGS = '/Brepro'
    $commandsLog = Join-Path $workRoot 'build-commands.log'; $hostLog = Join-Path $workRoot 'host-build-commands.log'
    $dllBuild = Invoke-SevenZipNativeBuild -NMakePath $toolchain.tools.'nmake.exe'.path -WorkingDirectory (Join-Path $sourceRoot 'CPP\7zip\Bundles\Format7zF') -LogPath $commandsLog
    $objectNames = @(Get-SevenZipLinkObjectNames -BuildLogPath $commandsLog)
    Assert-SevenZipNoRarBuildMap -ObjectNames $objectNames
    foreach ($required in @($definition.requiredObjects)) { if ($objectNames -cnotcontains [string]$required) { throw 'sevenzip_required_object_missing' } }
    $dllPath = Join-Path $sourceRoot 'CPP\7zip\Bundles\Format7zF\x64\7z.dll'
    if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) { throw 'sevenzip_dll_missing' }
    $binaryText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($dllPath))
    if ($binaryText -match '(?i)Rar(?:Handler|5Handler|1Decoder|2Decoder|3Decoder|3Vm|5Decoder|CodecsRegister|20Crypto|5Aes|Aes)') { throw 'sevenzip_rar_code_detected' }

    $hostBuild = Invoke-SevenZipNativeBuild -NMakePath $toolchain.tools.'nmake.exe'.path -WorkingDirectory (Join-Path $sourceRoot 'CPP\7zip\UI\Console') -LogPath $hostLog
    $hostPath = Join-Path $sourceRoot 'CPP\7zip\UI\Console\x64\7z.exe'
    $runtimeEvidence = Invoke-SevenZipRuntimeChecks -DllPath $dllPath -HostPath $hostPath
    $dllSha256 = Get-Sha256 $dllPath

    $x64Root = Join-Path $runtimeRoot 'x64'; $provenanceRoot = Join-Path $runtimeRoot 'provenance'
    [IO.Directory]::CreateDirectory($x64Root) | Out-Null; [IO.Directory]::CreateDirectory($provenanceRoot) | Out-Null
    Copy-Item -LiteralPath $dllPath -Destination (Join-Path $x64Root '7z.dll')
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'DOC\copying.txt') -Destination (Join-Path $runtimeRoot 'COPYING.LGPL-2.1.txt')
    Copy-Item -LiteralPath $script:DefaultNoticePath -Destination (Join-Path $runtimeRoot 'BSD-NOTICES.txt')
    $buildMap = [ordered]@{ schemaVersion = 1; objectCount = $objectNames.Count; objects = $objectNames; excludedObjects = @($definition.excludedObjects) }
    [IO.File]::WriteAllText((Join-Path $provenanceRoot 'build-map.json'), (($buildMap | ConvertTo-Json -Depth 5) + "`n"), $script:Utf8NoBom)
    $allCommandLines = @([IO.File]::ReadAllLines($commandsLog) + [IO.File]::ReadAllLines($hostLog))
    [IO.File]::WriteAllLines((Join-Path $provenanceRoot 'build-commands.log'), $allCommandLines, $script:Utf8NoBom)
    $provenance = [ordered]@{
        schemaVersion = 1; product = '7-Zip'; version = '26.01'; architecture = 'x64'; policy = 'no-rar-handlers-or-code'
        source = [ordered]@{ repository = $definition.source.repository; commit = $definition.source.commit; archiveUrl = $definition.source.archiveUrl; archiveSha256 = $definition.source.archiveSha256; arcMakSha256 = $definition.source.arcMakSha256; patchedArcMakSha256 = $definition.source.patchedArcMakSha256 }
        buildRecipe = [ordered]@{ path = 'tools/build-sevenzip-no-rar.ps1'; sha256 = Get-Sha256 $script:BuildToolPath; definitionPath = 'release/runtime/v2.19.1-karon.2/sevenzip-no-rar.json'; definitionSha256 = Get-Sha256 $BuildDefinitionPath }
        toolchain = $toolchain; commands = @($dllBuild, $hostBuild); buildMap = 'provenance/build-map.json'
        dll = [ordered]@{ archivePath = 'x64/7z.dll'; sha256 = $dllSha256; fileVersion = (Get-Item -LiteralPath $dllPath).VersionInfo.FileVersion; size = (Get-Item -LiteralPath $dllPath).Length }
        runtimeVerification = [ordered]@{ infoExitCode = $runtimeEvidence.InfoExitCode; zipExitCode = $runtimeEvidence.ZipExitCode; sevenZipExitCode = $runtimeEvidence.SevenZipExitCode; zipPayload = $runtimeEvidence.ZipPayload; sevenZipPayload = $runtimeEvidence.SevenZipPayload; commands = $runtimeEvidence.Commands }
        licenses = @('COPYING.LGPL-2.1.txt', 'BSD-NOTICES.txt'); legalAdvice = $false
    }
    [IO.File]::WriteAllText((Join-Path $provenanceRoot 'build-provenance.json'), (($provenance | ConvertTo-Json -Depth 12) + "`n"), $script:Utf8NoBom)

    $verificationHostRoot = Join-Path $workRoot 'verification-host'; [IO.Directory]::CreateDirectory($verificationHostRoot) | Out-Null
    Copy-Item -LiteralPath $hostPath -Destination (Join-Path $verificationHostRoot '7z.exe')
    Copy-Item -LiteralPath $dllPath -Destination (Join-Path $verificationHostRoot '7z.dll')
    $runtimeArchiveCommand = New-SevenZipArchive -HostPath (Join-Path $verificationHostRoot '7z.exe') -ArchivePath $artifactPath -WorkingDirectory $runtimeRoot -Entries @('BSD-NOTICES.txt', 'COPYING.LGPL-2.1.txt', 'provenance', 'x64')
    Assert-SevenZipRuntimeArchive -Path $artifactPath -SevenZipPath (Join-Path $verificationHostRoot '7z.exe') -ExpectedEntries @($definition.runtimeArchiveEntries)
    $postPackageEvidence = Test-SevenZipNoRarRuntime -RuntimeArchivePath $artifactPath -HostPath $hostPath
    $sourceArchiveCommand = New-SevenZipArchive -HostPath (Join-Path $verificationHostRoot '7z.exe') -ArchivePath $sourceArtifactPath -WorkingDirectory $sourceStageParent -Entries @([string]$definition.source.archiveRoot)
    $sourceEntries = @(Get-SevenZipArchiveEntries -Path $sourceArtifactPath -SevenZipPath (Join-Path $verificationHostRoot '7z.exe'))
    if (@($sourceEntries | Where-Object { $_ -match '(?i)^.+/CPP/7zip/(Archive/Rar/|Compress/Rar|Crypto/Rar)' -or $_ -match '(?i)unRarLicense\.txt$' }).Count -ne 0) { throw 'sevenzip_corresponding_source_contains_rar' }

    $artifactSha256 = Get-Sha256 $artifactPath; $sourceArtifactSha256 = Get-Sha256 $sourceArtifactPath
    $verification = [ordered]@{ runtimeArchive = $artifactPath; runtimeArchiveSha256 = $artifactSha256; dllSha256 = $dllSha256; correspondingSourceArchive = $sourceArtifactPath; correspondingSourceArchiveSha256 = $sourceArtifactSha256; hostPath = $hostPath; hostSha256 = Get-Sha256 $hostPath; fileVersion = (Get-Item -LiteralPath $dllPath).VersionInfo.FileVersion; runtime = $postPackageEvidence; archiveCommands = @($runtimeArchiveCommand, $sourceArchiveCommand) }
    $verificationPath = Join-Path $OutputPath 'verification.json'
    [IO.File]::WriteAllText($verificationPath, (($verification | ConvertTo-Json -Depth 10) + "`n"), $script:Utf8NoBom)
    if (-not [string]::IsNullOrWhiteSpace($RequestPath)) { Update-SevenZipReleaseRequest -Path $RequestPath -Definition $definition -ArtifactSha256 $artifactSha256 -DllSha256 $dllSha256 -SourceArchiveSha256 $sourceArtifactSha256 -DefinitionSha256 (Get-Sha256 $BuildDefinitionPath) }
    return [pscustomobject]@{ ArtifactPath = $artifactPath; ArtifactSha256 = $artifactSha256; DllSha256 = $dllSha256; SourceArchivePath = $sourceArtifactPath; SourceArchiveSha256 = $sourceArtifactSha256; HostPath = $hostPath; VerificationPath = $verificationPath; WorkRoot = $workRoot }
}

if ($MyInvocation.InvocationName -ne '.') {
    if ([string]::IsNullOrWhiteSpace($SourceArchive) -or [string]::IsNullOrWhiteSpace($OutputDirectory)) { throw 'SourceArchive and OutputDirectory are required.' }
    if ([string]::IsNullOrWhiteSpace($DefinitionPath)) { $DefinitionPath = $script:DefaultDefinitionPath }
    Invoke-SevenZipNoRarBuild -SourceArchivePath $SourceArchive -OutputPath $OutputDirectory -BuildDefinitionPath $DefinitionPath -RequestPath $ReleaseRequestPath | ConvertTo-Json -Depth 5
}
