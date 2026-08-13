Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ManifestField {
    param([Parameter(Mandatory = $true)] [object] $Value, [Parameter(Mandatory = $true)] [string] $Name)
    if ($Value -is [Collections.IDictionary]) {
        if (-not $Value.Contains($Name)) { return $null }
        return $Value[$Name]
    }
    $property = $Value.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-ManifestFieldPresent {
    param([Parameter(Mandatory = $true)] [object] $Value, [Parameter(Mandatory = $true)] [string] $Name)
    if ($Value -is [Collections.IDictionary]) { return $Value.Contains($Name) }
    return $null -ne $Value.PSObject.Properties[$Name]
}

function Test-CandidateChildPath {
    param([Parameter(Mandatory = $true)] [string] $Root, [Parameter(Mandatory = $true)] [string] $Path)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $pathFull = [IO.Path]::GetFullPath($Path)
    return $pathFull.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-ExactUniqueSet {
    param([Parameter(Mandatory = $true)] [string[]] $Actual, [Parameter(Mandatory = $true)] [string[]] $Expected)
    if ($Actual.Count -ne $Expected.Count) { throw 'candidate_manifest_invalid' }
    $set = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($value in $Actual) { if ([string]::IsNullOrWhiteSpace($value) -or -not $set.Add($value)) { throw 'candidate_manifest_invalid' } }
    foreach ($value in $Expected) { if (-not $set.Contains($value)) { throw 'candidate_manifest_invalid' } }
}

function Test-ArgumentPair {
    param([string[]] $Arguments, [string] $Name, [string] $Value)
    for ($index = 0; $index -lt $Arguments.Count - 1; $index++) {
        if ($Arguments[$index] -ceq $Name -and $Arguments[$index + 1] -ceq $Value) { return $true }
    }
    return $false
}

function Test-NormalizedArgumentPath {
    param([string] $Actual, [string] $Expected)
    return $Actual.Replace('\', '/') -ceq $Expected.Replace('\', '/')
}

function Assert-HermeticMsBuildTail {
    param([string[]] $Arguments, [int] $Offset, [string] $OutDirectory, [string] $VCToolsVersion, [string] $WindowsSdkVersion)
    $expectedCount = $Offset + 10 + $(if ([string]::IsNullOrWhiteSpace($OutDirectory)) { 0 } else { 1 })
    if ($Arguments.Count -ne $expectedCount) { throw 'candidate_manifest_invalid' }
    $fixed = @('/m', '/t:Build', '/p:Configuration=Release', '/p:Platform=x64', '/p:PlatformToolset=v143', '/p:ImportDirectoryBuildProps=false', '/p:ImportDirectoryBuildTargets=false')
    for ($index = 0; $index -lt $fixed.Count; $index++) { if ($Arguments[$Offset + $index] -cne $fixed[$index]) { throw 'candidate_manifest_invalid' } }
    if ($Arguments[$Offset + 7] -cne '/p:UserRootDir=<hermetic-user-root>\' -or
        $Arguments[$Offset + 8] -cne ('/p:VCToolsVersion=' + $VCToolsVersion) -or
        $Arguments[$Offset + 9] -cne ('/p:WindowsTargetPlatformVersion=' + $WindowsSdkVersion)) { throw 'candidate_manifest_invalid' }
    if (-not [string]::IsNullOrWhiteSpace($OutDirectory) -and -not (Test-NormalizedArgumentPath $Arguments[$Offset + 10] ('/p:OutDir=' + $OutDirectory))) { throw 'candidate_manifest_invalid' }
}

function Assert-CommandSemantics {
    param([Parameter(Mandatory = $true)] [object] $Command)
    $name = [string](Get-ManifestField -Value $Command -Name 'name')
    $executable = [string](Get-ManifestField -Value $Command -Name 'executable')
    $arguments = @((Get-ManifestField -Value $Command -Name 'arguments') | ForEach-Object { [string]$_ })
    $properties = Get-ManifestField -Value $Command -Name 'effectiveProperties'
    $userRoot = [string](Get-ManifestField -Value $properties -Name 'UserRootDir')
    $vcToolsVersion = [string](Get-ManifestField -Value $properties -Name 'VCToolsVersion')
    $windowsSdkVersion = [string](Get-ManifestField -Value $properties -Name 'WindowsTargetPlatformVersion')
    if ($userRoot -cne '<hermetic-user-root>' -or $vcToolsVersion -notmatch '^[0-9]+(?:\.[0-9]+)+$' -or
        $windowsSdkVersion -notmatch '^[0-9]+(?:\.[0-9]+)+$') { throw 'candidate_manifest_invalid' }
    if ($name -eq 'libjpeg-turbo Release x64 configure') {
        if ($executable -ine 'cmake.exe' -or $arguments.Count -ne 16 -or $arguments[0] -cne '-S' -or
            -not (Test-NormalizedArgumentPath $arguments[1] '<source>/libjpeg-turbo-3.1.2') -or $arguments[2] -cne '-B' -or
            -not (Test-NormalizedArgumentPath $arguments[3] '<source>/libjpeg-turbo-3.1.2/out/build/x64-Release') -or
            $arguments[4] -cne '-G' -or $arguments[5] -cne 'Visual Studio 17 2022' -or $arguments[6] -cne '-A' -or
            $arguments[7] -cne 'x64' -or $arguments[8] -cne '-T' -or $arguments[9] -cne 'v143') { throw 'candidate_manifest_invalid' }
        $globals = @($arguments | Where-Object { $_ -like '-DCMAKE_VS_GLOBALS=*' })
        if ($globals.Count -ne 1) { throw 'candidate_manifest_invalid' }
        $expectedGlobals = '-DCMAKE_VS_GLOBALS=' + (@(
            'ImportDirectoryBuildProps=false',
            'ImportDirectoryBuildTargets=false',
            'UserRootDir=<hermetic-user-root>\',
            ('VCToolsVersion=' + $vcToolsVersion),
            ('WindowsTargetPlatformVersion=' + $windowsSdkVersion)
        ) -join ';')
        if ($globals[0] -cne $expectedGlobals) { throw 'candidate_manifest_invalid' }
        $expectedTail = @('-DENABLE_SHARED=OFF', '-DENABLE_STATIC=ON', '-DWITH_TURBOJPEG=ON', '-DWITH_CRT_DLL=OFF')
        for ($index = 0; $index -lt $expectedTail.Count; $index++) { if ($arguments[11 + $index] -cne $expectedTail[$index]) { throw 'candidate_manifest_invalid' } }
        if (-not (Test-NormalizedArgumentPath $arguments[15] '-DCMAKE_ARCHIVE_OUTPUT_DIRECTORY_RELEASE=<source>/libjpeg-turbo-3.1.2/out/build/x64-Release')) { throw 'candidate_manifest_invalid' }
        return
    }
    if ($name -eq 'libjpeg-turbo Release x64 build') {
        if ($executable -ine 'cmake.exe' -or $arguments[0] -cne '--build' -or
            -not (Test-NormalizedArgumentPath $arguments[1] '<source>/libjpeg-turbo-3.1.2/out/build/x64-Release') -or
            $arguments[2] -cne '--config' -or $arguments[3] -cne 'Release' -or $arguments[4] -cne '--target' -or
            $arguments[5] -cne 'turbojpeg-static' -or $arguments[6] -cne '--') { throw 'candidate_manifest_invalid' }
        Assert-HermeticMsBuildTail -Arguments $arguments -Offset 7 -VCToolsVersion $vcToolsVersion -WindowsSdkVersion $windowsSdkVersion
        return
    }
    if ($executable -ine 'MSBuild.exe') { throw 'candidate_manifest_invalid' }
    $requiredSuffix = switch ($name) {
        'bit7z Release x64 build' { 'bit7z/bit7z.sln' }
        'Nana Release x64 build' { 'nana/build/vc2022/nana.sln' }
        'libpng Release x64 build' { 'libpng/libpng.sln' }
        'Release x64 MSBuild' { 'ytdlp-interface/ytdlp-interface.sln' }
        default { throw 'candidate_manifest_invalid' }
    }
    if (-not (Test-NormalizedArgumentPath $arguments[0] ('<source>/' + $requiredSuffix))) { throw 'candidate_manifest_invalid' }
    $outDirectory = if ($name -eq 'libpng Release x64 build') { '<source>/libpng/x64/Release/' } else { $null }
    Assert-HermeticMsBuildTail -Arguments $arguments -Offset 1 -OutDirectory $outDirectory -VCToolsVersion $vcToolsVersion -WindowsSdkVersion $windowsSdkVersion
}

function Assert-AttestationShape {
    param([Parameter(Mandatory = $true)] [object] $Attestation)
    foreach ($name in @('source', 'dependencyArchive', 'linkerInputs', 'toolchain', 'commands')) {
        if (-not (Test-ManifestFieldPresent -Value $Attestation -Name $name)) { throw 'candidate_manifest_invalid' }
    }
    $source = Get-ManifestField -Value $Attestation -Name 'source'
    $commit = [string](Get-ManifestField -Value $source -Name 'commit')
    $treeSha256 = [string](Get-ManifestField -Value $source -Name 'treeSha256')
    $trackedFileCount = Get-ManifestField -Value $source -Name 'trackedFileCount'
    $dirty = Get-ManifestField -Value $source -Name 'dirty'
    $count = 0
    if ($commit -notmatch '^[A-Fa-f0-9]{40}([A-Fa-f0-9]{24})?$' -or $treeSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
        -not [int]::TryParse([string]$trackedFileCount, [ref]$count) -or $count -le 0 -or [bool]$dirty) { throw 'candidate_manifest_invalid' }

    $archive = Get-ManifestField -Value $Attestation -Name 'dependencyArchive'
    if ([string]::IsNullOrWhiteSpace([string](Get-ManifestField -Value $archive -Name 'name')) -or
        [string](Get-ManifestField -Value $archive -Name 'sha256') -notmatch '^[A-Fa-f0-9]{64}$') { throw 'candidate_manifest_invalid' }

    $linkerInputs = @(Get-ManifestField -Value $Attestation -Name 'linkerInputs')
    Assert-ExactUniqueSet -Actual @($linkerInputs | ForEach-Object { [string](Get-ManifestField -Value $_ -Name 'library') }) -Expected @('bit7z64.lib', 'nana_v143_Release_x64.lib', 'libpng.lib', 'turbojpeg-static.lib')
    foreach ($entry in $linkerInputs) {
        $length = 0L
        if ([string]::IsNullOrWhiteSpace([string](Get-ManifestField -Value $entry -Name 'name')) -or
            [string]::IsNullOrWhiteSpace([string](Get-ManifestField -Value $entry -Name 'library')) -or
            [string](Get-ManifestField -Value $entry -Name 'sha256') -notmatch '^[A-Fa-f0-9]{64}$' -or
            -not [long]::TryParse([string](Get-ManifestField -Value $entry -Name 'length'), [ref]$length) -or $length -lt 0) { throw 'candidate_manifest_invalid' }
    }

    $toolchain = @(Get-ManifestField -Value $Attestation -Name 'toolchain')
    $toolNames = @($toolchain | ForEach-Object { [string](Get-ManifestField -Value $_ -Name 'name') })
    Assert-ExactUniqueSet -Actual $toolNames -Expected @('msbuild', 'cmake', 'cl', 'link', 'rc', 'windows-sdk')
    foreach ($entry in $toolchain) {
        if ([string](Get-ManifestField -Value $entry -Name 'sha256') -notmatch '^[A-Fa-f0-9]{64}$' -or
            [string]::IsNullOrWhiteSpace([string](Get-ManifestField -Value $entry -Name 'version'))) { throw 'candidate_manifest_invalid' }
    }

    $commands = @(Get-ManifestField -Value $Attestation -Name 'commands')
    Assert-ExactUniqueSet -Actual @($commands | ForEach-Object { [string](Get-ManifestField -Value $_ -Name 'name') }) -Expected @(
        'bit7z Release x64 build', 'Nana Release x64 build', 'libpng Release x64 build',
        'libjpeg-turbo Release x64 configure', 'libjpeg-turbo Release x64 build', 'Release x64 MSBuild'
    )
    foreach ($entry in $commands) {
        foreach ($field in @('name', 'executable', 'arguments', 'workingDirectory', 'effectiveProperties', 'environment')) {
            if (-not (Test-ManifestFieldPresent -Value $entry -Name $field)) { throw 'candidate_manifest_invalid' }
        }
        if ([string](Get-ManifestField -Value $entry -Name 'workingDirectory') -ne '<source>') { throw 'candidate_manifest_invalid' }
        $properties = Get-ManifestField -Value $entry -Name 'effectiveProperties'
        $requiredProperties = [ordered]@{
            Configuration = 'Release'; Platform = 'x64'; PlatformToolset = 'v143'
            ImportDirectoryBuildProps = 'false'; ImportDirectoryBuildTargets = 'false'; UserRootDir = '<hermetic-user-root>'
        }
        foreach ($name in $requiredProperties.Keys) {
            if ([string](Get-ManifestField -Value $properties -Name $name) -cne [string]$requiredProperties[$name]) { throw 'candidate_manifest_invalid' }
        }
        foreach ($name in @('VCToolsVersion', 'WindowsTargetPlatformVersion')) {
            if ([string](Get-ManifestField -Value $properties -Name $name) -notmatch '^[0-9]+(?:\.[0-9]+)+$') { throw 'candidate_manifest_invalid' }
        }
        $environment = Get-ManifestField -Value $entry -Name 'environment'
        if ([string](Get-ManifestField -Value $environment -Name 'PreferredToolArchitecture') -cne 'x64') { throw 'candidate_manifest_invalid' }
        Assert-CommandSemantics -Command $entry
    }
}

function Assert-CandidateManifestSeal {
    param(
        [Parameter(Mandatory = $true)] [string] $CandidateRoot,
        [Parameter(Mandatory = $true)] [object] $Manifest
    )
    $candidate = [IO.Path]::GetFullPath($CandidateRoot)
    if ((Get-ManifestField -Value $Manifest -Name 'schemaVersion') -ne 1) { throw 'candidate_manifest_invalid' }
    if ([string]::IsNullOrWhiteSpace([string](Get-ManifestField -Value $Manifest -Name 'createdAtUtc'))) { throw 'candidate_manifest_invalid' }
    $attestation = Get-ManifestField -Value $Manifest -Name 'attestation'
    if ($null -eq $attestation) { throw 'candidate_manifest_invalid' }
    Assert-AttestationShape -Attestation $attestation
    $versions = Get-ManifestField -Value $Manifest -Name 'versions'
    if ($null -eq $versions) { throw 'candidate_manifest_invalid' }
    foreach ($name in @('product', 'ytdlp', 'ffmpeg', 'ffprobe', 'deno')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-ManifestField -Value $versions -Name $name))) { throw 'candidate_manifest_invalid' }
    }
    $files = @(Get-ManifestField -Value $Manifest -Name 'files')
    if ($files.Count -eq 0) { throw 'candidate_manifest_invalid' }
    $declared = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $files) {
        foreach ($field in @('path', 'sha256', 'length')) {
            if (-not (Test-ManifestFieldPresent -Value $entry -Name $field)) { throw 'candidate_manifest_invalid' }
        }
        $relative = [string](Get-ManifestField -Value $entry -Name 'path')
        $length = 0L
        if ([string]::IsNullOrWhiteSpace($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($relative) -or
            [string](Get-ManifestField -Value $entry -Name 'sha256') -notmatch '^[A-Fa-f0-9]{64}$' -or
            -not [long]::TryParse([string](Get-ManifestField -Value $entry -Name 'length'), [ref]$length) -or $length -lt 0) { throw 'candidate_manifest_invalid' }
        $path = Join-Path $candidate $relative
        if (-not (Test-CandidateChildPath -Root $candidate -Path $path) -or -not $declared.Add([IO.Path]::GetFullPath($path))) { throw 'candidate_manifest_invalid' }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'candidate_manifest_mismatch' }
        $item = Get-Item -LiteralPath $path
        if ($item.Length -ne $length -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant() -cne ([string](Get-ManifestField -Value $entry -Name 'sha256')).ToUpperInvariant()) { throw 'candidate_manifest_mismatch' }
    }
    $rootManifestPath = [IO.Path]::GetFullPath((Join-Path $candidate 'candidate-manifest.json'))
    $actual = @(Get-ChildItem -LiteralPath $candidate -File -Recurse | Where-Object { $_.FullName -ine $rootManifestPath })
    if ($actual.Count -ne $declared.Count) { throw 'candidate_manifest_mismatch' }
    foreach ($item in $actual) { if (-not $declared.Contains($item.FullName)) { throw 'candidate_manifest_mismatch' } }
}

Export-ModuleMember -Function Assert-CandidateManifestSeal
