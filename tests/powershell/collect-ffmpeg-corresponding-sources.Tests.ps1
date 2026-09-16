$collector = Join-Path $PSScriptRoot '..\..\tools\collect-ffmpeg-corresponding-sources.ps1'
. $collector -NoExecute

$releaseRoot = Join-Path $PSScriptRoot '..\..\release\runtime\v2.19.1-karon.2\ffmpeg'
$manifestPath = Join-Path $releaseRoot manifest.json
$binaryPath = 'E:\03_AllWork\ytdlp-korean-interface\.quality-presets-work\karon2-input\immutable\ffmpeg-n9.0.1-30-g9258bacca5-win64-lgpl-9.0.zip'

function Copy-JsonObject {
    param($Value)
    $Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json
}

Describe 'FFmpeg corresponding-source collector schema 3' {
    BeforeAll {
        $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $graph = Get-Content -Raw -LiteralPath (Join-Path $releaseRoot $manifest.sourceSets.btbnActionsCache.componentGraphPath) | ConvertFrom-Json
        $crates = Get-Content -Raw -LiteralPath (Join-Path $releaseRoot $manifest.sourceSets.rav1eCrates.manifestPath) | ConvertFrom-Json
        $toolchain = Get-Content -Raw -LiteralPath (Join-Path $releaseRoot $manifest.sourceSets.toolchain.manifestPath) | ConvertFrom-Json
        $corpus = Get-Content -Raw -LiteralPath (Join-Path $releaseRoot $manifest.sourceSets.licenseCorpus.manifestPath) | ConvertFrom-Json
        $options = @(Get-Content -LiteralPath (Join-Path $releaseRoot $manifest.binary.buildConfigurationPath) | ForEach-Object Trim | Where-Object { $_ -match '^--' })
    }

    It 'rejects an unknown enabled external library' {
        { Assert-FfmpegClosureMetadata $manifest $graph $crates $toolchain $corpus ($options + '--enable-libunknown') } |
            Should Throw 'ffmpeg_source_unknown_enabled_library'
    }

    It 'treats lv2 as an external option that must remain mapped' {
        $bad = Copy-JsonObject $manifest
        $bad.enabledExternalLibraries = @($bad.enabledExternalLibraries | Where-Object option -ne '--enable-lv2')
        { Assert-FfmpegClosureMetadata $bad $graph $crates $toolchain $corpus $options } |
            Should Throw 'ffmpeg_source_unknown_enabled_library:--enable-lv2'
    }

    It 'rejects a mutable URL' {
        $bad = Copy-JsonObject $toolchain
        $bad.components[0].source.url = 'https://github.com/example/project/archive/main.zip'
        { Assert-FfmpegClosureMetadata $manifest $graph $crates $bad $corpus $options } |
            Should Throw 'ffmpeg_source_mutable_url'
    }

    It 'rejects a source SHA mismatch' {
        $path = Join-Path $TestDrive source.bin
        [IO.File]::WriteAllText($path, 'wrong')
        { Assert-SourceArchiveHash $path ('0' * 64) component } |
            Should Throw 'ffmpeg_source_sha256_mismatch'
    }

    It 'rejects GPL and nonfree configuration' {
        { Assert-FfmpegClosureMetadata $manifest $graph $crates $toolchain $corpus ($options + '--enable-gpl') } |
            Should Throw 'ffmpeg_source_forbidden_configuration'
        { Assert-FfmpegClosureMetadata $manifest $graph $crates $toolchain $corpus ($options + '--enable-nonfree') } |
            Should Throw 'ffmpeg_source_forbidden_configuration'
    }

    It 'rejects missing patch and license evidence' {
        $badPatch = Copy-JsonObject $graph
        $badPatch.components[0].recipe.patches = @([pscustomobject]@{ path = ''; sha256 = '' })
        { Assert-FfmpegClosureMetadata $manifest $badPatch $crates $toolchain $corpus $options } |
            Should Throw 'ffmpeg_source_missing_patch'
        $badLicense = Copy-JsonObject $graph
        $badLicense.components[0].license.files = @()
        { Assert-FfmpegClosureMetadata $manifest $badLicense $crates $toolchain $corpus $options } |
            Should Throw 'ffmpeg_source_missing_license'
    }

    It 'rejects duplicate identifiers with a case collision' {
        $bad = Copy-JsonObject $graph
        $duplicate = Copy-JsonObject $bad.components[0]
        $duplicate.id = $duplicate.id.ToUpperInvariant()
        $bad.components += $duplicate
        { Assert-FfmpegClosureMetadata $manifest $bad $crates $toolchain $corpus $options } |
            Should Throw 'ffmpeg_source_duplicate_component'
    }

    It 'accepts the exact official archive and records its build configuration' {
        $evidence = Read-FfmpegBinaryEvidence $binaryPath $manifest.binary.archiveSha256 $manifest.binary.ffmpegSha256 $manifest.binary.ffprobeSha256 $manifest.binary.expectedVersion
        $evidence.ffmpegSha256 | Should Be '41482EABC1A33F9D1E4334CA32EC9259AA34A3EC2493FCC9F214BFE54301CE38'
        $evidence.configurationOptions.Count | Should BeGreaterThan 0
        ($evidence.configurationOptions -contains '--enable-version3') | Should Be $true
        ($evidence.configurationOptions -notcontains '--enable-gpl') | Should Be $true
    }

    It 'requires deterministic LicenseRef text with matching bytes' {
        $root = Join-Path $TestDrive corpus
        [IO.Directory]::CreateDirectory((Join-Path $root 'licenses\extracted')) | Out-Null
        $file = Join-Path $root 'licenses\extracted\license.txt'
        [IO.File]::WriteAllText($file, 'exact license text')
        $sha = Get-UpperSha256 $file
        $mini = [pscustomobject]@{
            textObjectCount = 1
            textObjects = @([pscustomobject]@{
                sha256 = $sha
                licenseRef = 'LicenseRef-' + $sha.Substring(0, 16).ToLowerInvariant()
                bytes = (Get-Item -LiteralPath $file).Length
                bundlePath = 'licenses/extracted/license.txt'
            })
        }
        (Assert-LicenseCorpus $mini $root -VerifyFiles).Count | Should Be 1
        [IO.File]::WriteAllText($file, 'changed')
        { Assert-LicenseCorpus $mini $root -VerifyFiles } | Should Throw 'ffmpeg_source_sha256_mismatch'
    }

    It 'hashes committed license blobs instead of normalized working-tree bytes' {
        $repo = Join-Path $TestDrive git-license-gate
        $manifestRoot = Join-Path $repo 'release\ffmpeg'
        $licenseRoot = Join-Path $manifestRoot 'licenses\extracted'
        [IO.Directory]::CreateDirectory($licenseRoot) | Out-Null
        [IO.File]::WriteAllText((Join-Path $repo '.gitattributes'), "* -text`n", [Text.UTF8Encoding]::new($false))
        $path = Join-Path $licenseRoot 'license.txt'
        $lfBytes = [Text.Encoding]::UTF8.GetBytes("line one`nline two`n")
        $crlfBytes = [Text.Encoding]::UTF8.GetBytes("line one`r`nline two`r`n")
        [IO.File]::WriteAllBytes($path, $lfBytes)
        & git -C $repo init -q
        & git -C $repo config user.email test@example.invalid
        & git -C $repo config user.name 'Task 6 Test'
        & git -C $repo add -- .gitattributes release/ffmpeg/licenses/extracted/license.txt
        & git -C $repo commit -q -m baseline
        [IO.File]::WriteAllBytes($path, $crlfBytes)
        $sha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($crlfBytes))
        $mini = [pscustomobject]@{
            textObjectCount = 1
            textObjects = @([pscustomobject]@{
                sha256 = $sha
                licenseRef = 'LicenseRef-' + $sha.Substring(0, 16).ToLowerInvariant()
                bytes = $crlfBytes.Length
                bundlePath = 'licenses/extracted/license.txt'
            })
        }
        { Assert-GitLicenseCorpus $mini $manifestRoot HEAD } |
            Should Throw 'ffmpeg_source_git_license_blob_mismatch'
    }

    It 'requires every Rav1e license member to use the shared LicenseRef corpus' {
        $bad = Copy-JsonObject $crates
        $bad.components[0].licenseFiles = @()
        { Assert-FfmpegClosureMetadata $manifest $graph $bad $toolchain $corpus $options } |
            Should Throw 'ffmpeg_source_missing_license'
        $corpus.rav1eComponents.Count | Should Be 270
        (@($corpus.rav1eComponents | ForEach-Object { @($_.licenseFiles) }).Count) | Should Be 492
        $corpus.textObjectCount | Should Be 681
    }

    It 'requires exact GCC libgomp and MinGW toolchain sources' {
        $bad = Copy-JsonObject $toolchain
        $bad.components = @($bad.components | Where-Object id -ne 'toolchain-gcc-16.2.0')
        { Assert-FfmpegClosureMetadata $manifest $graph $crates $bad $corpus $options } |
            Should Throw 'ffmpeg_source_missing_toolchain'
    }

    It 'requires all 19 nested trees as conservative superset closures' {
        $bad = Copy-JsonObject $graph
        $bad.nestedClosures[0].applicability = 'exact-link-minimum'
        { Assert-FfmpegClosureMetadata $manifest $bad $crates $toolchain $corpus $options } |
            Should Throw 'ffmpeg_source_nested_closure_incomplete'
        $graph.nestedClosures.Count | Should Be 19
    }

    It 'creates byte-identical deterministic ZIPs' {
        $a = Join-Path $TestDrive a.txt
        $b = Join-Path $TestDrive b.txt
        [IO.File]::WriteAllText($a, 'alpha')
        [IO.File]::WriteAllText($b, 'beta')
        $items = @(
            New-BundleItem $b B.txt
            New-BundleItem $a a.txt
        )
        $one = Join-Path $TestDrive one.zip
        $two = Join-Path $TestDrive two.zip
        $first = New-DeterministicZip $items $one @($TestDrive)
        $second = New-DeterministicZip $items $two @($TestDrive)
        (Get-UpperSha256 $one) | Should Be (Get-UpperSha256 $two)
        $first.verifiedEntryCount | Should Be 2
        $second.verifiedEntryCount | Should Be 2
    }

    It 'rejects rooted traversal ADS device and Windows alias entry paths' {
        $root = Join-Path $TestDrive path-root
        [IO.Directory]::CreateDirectory($root) | Out-Null
        $source = Join-Path $root source.txt
        [IO.File]::WriteAllText($source, 'safe')
        $sha = Get-UpperSha256 $source
        foreach ($entryPath in @(
            'C:\escape.txt', '/escape.txt', '\\server\share\escape.txt', '\\?\C:\escape.txt',
            '../escape.txt', 'safe/../escape.txt', 'safe\..\escape.txt', 'safe/file.txt:ads',
            'safe/name.', 'safe/name ', 'CON/file.txt'
        )) {
            $item = [pscustomobject]@{ SourcePath = $source; EntryPath = $entryPath; Sha256 = $sha; Bytes = 4 }
            { Assert-BundleItems @($item) @($root) } | Should Throw 'ffmpeg_source_unsafe_bundle_path'
        }
    }

    It 'rejects every C0 control character in an entry path segment' {
        $root = Join-Path $TestDrive control-root
        [IO.Directory]::CreateDirectory($root) | Out-Null
        $source = Join-Path $root source.txt
        [IO.File]::WriteAllText($source, 'safe')
        $sha = Get-UpperSha256 $source
        foreach ($codePoint in 0..31) {
            $entryPath = 'safe/name' + [char] $codePoint + '.txt'
            $item = [pscustomobject]@{ SourcePath = $source; EntryPath = $entryPath; Sha256 = $sha; Bytes = 4 }
            { Assert-BundleItems @($item) @($root) } | Should Throw 'ffmpeg_source_unsafe_bundle_path'
        }
    }

    It 'rejects superscript DOS device aliases with extensions case-insensitively' {
        $root = Join-Path $TestDrive superscript-device-root
        [IO.Directory]::CreateDirectory($root) | Out-Null
        $source = Join-Path $root source.txt
        [IO.File]::WriteAllText($source, 'safe')
        $sha = Get-UpperSha256 $source
        foreach ($entryPath in @(
            ('COM' + [char] 0x00B9 + '.txt'), ('com' + [char] 0x00B2 + '.log'), ('CoM' + [char] 0x00B3 + '.bin'),
            ('LPT' + [char] 0x00B9 + '.txt'), ('lpt' + [char] 0x00B2 + '.log'), ('LpT' + [char] 0x00B3 + '.bin')
        )) {
            $item = [pscustomobject]@{ SourcePath = $source; EntryPath = $entryPath; Sha256 = $sha; Bytes = 4 }
            { Assert-BundleItems @($item) @($root) } | Should Throw 'ffmpeg_source_unsafe_bundle_path'
        }
    }

    It 'rejects a source reached through a parent junction inside an allowed root' {
        $root = Join-Path $TestDrive junction-source-root
        $outside = Join-Path $TestDrive junction-source-outside
        [IO.Directory]::CreateDirectory($root) | Out-Null
        [IO.Directory]::CreateDirectory($outside) | Out-Null
        $outsideSource = Join-Path $outside source.txt
        [IO.File]::WriteAllText($outsideSource, 'outside')
        $junction = Join-Path $root linked-parent
        New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
        try {
            $item = New-BundleItem (Join-Path $junction source.txt) entry.txt
            { Assert-BundleItems @($item) @($root) } | Should Throw 'ffmpeg_source_source_root_escape'
        }
        finally {
            if (Test-Path -LiteralPath $junction) { Remove-Item -LiteralPath $junction -Force }
        }
    }

    It 'rejects a snapshot root junction even when its owner token is valid' {
        $parent = Join-Path $TestDrive snapshot-junction-parent
        $target = Join-Path $TestDrive snapshot-junction-target
        [IO.Directory]::CreateDirectory($parent) | Out-Null
        [IO.Directory]::CreateDirectory($target) | Out-Null
        $token = '0123456789abcdef0123456789abcdef'
        [IO.File]::WriteAllText((Join-Path $target '.owner'), $token, [Text.UTF8Encoding]::new($false))
        $root = Join-Path $parent "ffmpeg-bundle-stage-$token"
        New-Item -ItemType Junction -Path $root -Target $target | Out-Null
        try {
            $snapshot = [pscustomobject]@{ Root = $root; Parent = $parent; Token = $token }
            { Assert-OwnedBundleSnapshot $snapshot } | Should Throw 'ffmpeg_source_snapshot_reparse_point'
        }
        finally {
            if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Force }
        }
    }

    It 'rejects a junction in an ancestor of the snapshot root' {
        $anchor = Join-Path $TestDrive snapshot-ancestor-anchor
        $targetParent = Join-Path $TestDrive snapshot-ancestor-target
        [IO.Directory]::CreateDirectory($anchor) | Out-Null
        [IO.Directory]::CreateDirectory($targetParent) | Out-Null
        $linkedParent = Join-Path $anchor linked-parent
        New-Item -ItemType Junction -Path $linkedParent -Target $targetParent | Out-Null
        $token = 'fedcba9876543210fedcba9876543210'
        $root = Join-Path $linkedParent "ffmpeg-bundle-stage-$token"
        [IO.Directory]::CreateDirectory($root) | Out-Null
        [IO.File]::WriteAllText((Join-Path $root '.owner'), $token, [Text.UTF8Encoding]::new($false))
        try {
            $snapshot = [pscustomobject]@{ Root = $root; Parent = $linkedParent; Token = $token }
            { Assert-OwnedBundleSnapshot $snapshot } | Should Throw 'ffmpeg_source_snapshot_reparse_point'
        }
        finally {
            if (Test-Path -LiteralPath $linkedParent) { Remove-Item -LiteralPath $linkedParent -Force }
        }
    }

    It 'rejects exact case-insensitive and Unicode-normalization path collisions' {
        $root = Join-Path $TestDrive collision-root
        [IO.Directory]::CreateDirectory($root) | Out-Null
        $source = Join-Path $root source.txt
        [IO.File]::WriteAllText($source, 'safe')
        $sha = Get-UpperSha256 $source
        foreach ($paths in @(
            @('same.txt', 'same.txt'),
            @('Case.txt', 'case.txt'),
            @(([string][char]0x00E9 + '.txt'), ('e' + [char]0x0301 + '.txt'))
        )) {
            $items = @($paths | ForEach-Object { [pscustomobject]@{ SourcePath = $source; EntryPath = $_; Sha256 = $sha; Bytes = 4 } })
            { Assert-BundleItems $items @($root) } | Should Throw 'ffmpeg_source_duplicate_path'
        }
    }

    It 'rejects a source path outside its declared containment root' {
        $root = Join-Path $TestDrive containment-root
        [IO.Directory]::CreateDirectory($root) | Out-Null
        $source = Join-Path $TestDrive outside.txt
        [IO.File]::WriteAllText($source, 'outside')
        $item = New-BundleItem $source inside.txt
        { Assert-BundleItems @($item) @($root) } | Should Throw 'ffmpeg_source_source_root_escape'
    }

    It 'detects source mutation between item hashing and private snapshot creation' {
        $root = Join-Path $TestDrive toctou-root
        [IO.Directory]::CreateDirectory($root) | Out-Null
        $source = Join-Path $root source.txt
        [IO.File]::WriteAllText($source, 'before')
        $item = New-BundleItem $source entry.txt
        [IO.File]::WriteAllText($source, 'after')
        $zip = Join-Path $TestDrive toctou.zip
        { New-DeterministicZip @($item) $zip @($root) } | Should Throw 'ffmpeg_source_staged_sha256_mismatch'
    }

    It 'removes a partial snapshot after an expected SHA mismatch' {
        $root = Join-Path $TestDrive partial-sha-root
        $stageParent = Join-Path $TestDrive partial-sha-stage
        [IO.Directory]::CreateDirectory($root) | Out-Null
        [IO.Directory]::CreateDirectory($stageParent) | Out-Null
        $source = Join-Path $root source.txt
        [IO.File]::WriteAllText($source, 'partial bytes')
        $item = New-BundleItem $source entry.txt
        $item.Sha256 = '0' * 64

        { New-VerifiedBundleSnapshot @($item) $stageParent @($root) } |
            Should Throw 'ffmpeg_source_staged_sha256_mismatch'
        @(Get-ChildItem -LiteralPath $stageParent -Directory -Filter 'ffmpeg-bundle-stage-*').Count | Should Be 0
    }

    It 'removes a partial snapshot after an expected length mismatch' {
        $root = Join-Path $TestDrive partial-length-root
        $stageParent = Join-Path $TestDrive partial-length-stage
        [IO.Directory]::CreateDirectory($root) | Out-Null
        [IO.Directory]::CreateDirectory($stageParent) | Out-Null
        $source = Join-Path $root source.txt
        [IO.File]::WriteAllText($source, 'partial bytes')
        $item = New-BundleItem $source entry.txt
        $item.Bytes = $item.Bytes + 1

        { New-VerifiedBundleSnapshot @($item) $stageParent @($root) } |
            Should Throw 'ffmpeg_source_staged_sha256_mismatch'
        @(Get-ChildItem -LiteralPath $stageParent -Directory -Filter 'ffmpeg-bundle-stage-*').Count | Should Be 0
    }

    It 'refuses to delete a same-byte replacement of a failed partial leaf' {
        $root = Join-Path $TestDrive partial-replacement-root
        $stageParent = Join-Path $TestDrive partial-replacement-stage
        [IO.Directory]::CreateDirectory($root) | Out-Null
        [IO.Directory]::CreateDirectory($stageParent) | Out-Null
        $source = Join-Path $root source.txt
        [IO.File]::WriteAllText($source, 'same partial bytes')
        $item = New-BundleItem $source entry.txt
        $item.Sha256 = '0' * 64
        $replacementBytes = [IO.File]::ReadAllBytes($source)
        $observation = [pscustomobject]@{ Root = $null; ReplacementPath = $null; CleanupError = $null }
        $originalCleanup = (Get-Item Function:\Remove-VerifiedBundleSnapshot).ScriptBlock
        $attackingCleanup = {
            param($Snapshot)
            $observation.Root = $Snapshot.Root
            $observation.ReplacementPath = Join-Path $Snapshot.Root '00000000.bin'
            Remove-Item -LiteralPath $observation.ReplacementPath -Force
            [IO.File]::WriteAllBytes($observation.ReplacementPath, $replacementBytes)
            try { & $originalCleanup $Snapshot }
            catch { $observation.CleanupError = $_.Exception.Message }
        }.GetNewClosure()

        Set-Item -Path Function:\Remove-VerifiedBundleSnapshot -Value $attackingCleanup
        try {
            { New-VerifiedBundleSnapshot @($item) $stageParent @($root) } |
                Should Throw 'ffmpeg_source_staged_sha256_mismatch'
            $observation.CleanupError | Should Match '^ffmpeg_source_snapshot_identity_changed:'
            (Test-Path -LiteralPath $observation.ReplacementPath -PathType Leaf) | Should Be $true
            @(Get-ChildItem -LiteralPath $stageParent -Directory -Filter 'ffmpeg-bundle-stage-*').Count | Should Be 1
        }
        finally {
            Set-Item -Path Function:\Remove-VerifiedBundleSnapshot -Value $originalCleanup
            if ($observation.Root -and (Test-Path -LiteralPath $observation.Root)) {
                Remove-Item -LiteralPath $observation.Root -Recurse -Force
            }
        }
    }

    It 'rejects a same-byte source identity replacement after validation' {
        $root = Join-Path $TestDrive identity-source-root
        $stageParent = Join-Path $TestDrive identity-source-stage
        [IO.Directory]::CreateDirectory($root) | Out-Null
        [IO.Directory]::CreateDirectory($stageParent) | Out-Null
        $source = Join-Path $root source.txt
        [IO.File]::WriteAllText($source, 'same bytes')
        $validated = @(Assert-BundleItems @((New-BundleItem $source entry.txt)) @($root))[0]
        Move-Item -LiteralPath $source -Destination (Join-Path $root original.txt)
        [IO.File]::WriteAllText($source, 'same bytes')
        {
            $snapshot = New-VerifiedBundleSnapshot @($validated) $stageParent @($root)
            if ($snapshot) { Remove-VerifiedBundleSnapshot $snapshot }
        } | Should Throw 'ffmpeg_source_path_identity_changed'
    }

    It 'refuses cleanup after the owner marker is replaced with the same token' {
        $root = Join-Path $TestDrive identity-owner-root
        $stageParent = Join-Path $TestDrive identity-owner-stage
        [IO.Directory]::CreateDirectory($root) | Out-Null
        [IO.Directory]::CreateDirectory($stageParent) | Out-Null
        $source = Join-Path $root source.txt
        [IO.File]::WriteAllText($source, 'owner identity')
        $snapshot = New-VerifiedBundleSnapshot @((New-BundleItem $source entry.txt)) $stageParent @($root)
        $marker = Join-Path $snapshot.Root '.owner'
        Remove-Item -LiteralPath $marker -Force
        [IO.File]::WriteAllText($marker, $snapshot.Token, [Text.UTF8Encoding]::new($false))
        try {
            { Remove-VerifiedBundleSnapshot $snapshot } | Should Throw 'ffmpeg_source_snapshot_identity_changed'
        }
        finally {
            if (Test-Path -LiteralPath $snapshot.Root) { Remove-Item -LiteralPath $snapshot.Root -Recurse -Force }
        }
    }

    It 'reopens the completed ZIP and rejects an inventory mismatch' {
        $root = Join-Path $TestDrive verify-root
        [IO.Directory]::CreateDirectory($root) | Out-Null
        $source = Join-Path $root source.txt
        [IO.File]::WriteAllText($source, 'verified')
        $item = New-BundleItem $source entry.txt
        $zip = Join-Path $TestDrive verified.zip
        $result = New-DeterministicZip @($item) $zip @($root)
        $result.verifiedEntryCount | Should Be 1
        $bad = [pscustomobject]@{ SourcePath = $source; EntryPath = 'entry.txt'; Sha256 = ('0' * 64); Bytes = 8 }
        { Assert-ZipMatchesItems $zip @($bad) } | Should Throw 'ffmpeg_source_zip_sha256_mismatch'
    }

    It 'validates the complete retained conservative closure' {
        { Assert-FfmpegClosureMetadata $manifest $graph $crates $toolchain $corpus $options } | Should Not Throw
        $manifest.closureStatus | Should Be complete
        $manifest.verifiedSourceRecordCount | Should Be 407
        $corpus.textObjectCount | Should Be 681
        $manifest.counts.licenseFileReferences | Should Be 1750
        $toolchain.baseImage.dockerfileInputStatus | Should Be 'mutable-upstream-input-retained-not-reproducibly-pinned'
    }
}

