$collectorPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'tools/collect-deno-third-party-notices.ps1'
if (Test-Path -LiteralPath $collectorPath) { . $collectorPath }

function Get-TestExceptionMessage {
    param([scriptblock] $Action)
    try { & $Action; return $null }
    catch { return $_.Exception.Message }
}

function New-TestSpdxCorpus {
    param([Parameter(Mandatory)] [string] $Root)
    New-Item -ItemType Directory -Path (Join-Path $Root 'json'), (Join-Path $Root 'text') | Out-Null
    $licenses = [ordered]@{
        licenseListVersion = 'test-1.0'
        licenses = @('MIT', 'Apache-2.0', 'GPL-2.0-only') | ForEach-Object { [ordered]@{ licenseId = $_ } }
    }
    $exceptions = [ordered]@{
        licenseListVersion = 'test-1.0'
        exceptions = @([ordered]@{ licenseExceptionId = 'Classpath-exception-2.0' })
    }
    [IO.File]::WriteAllText((Join-Path $Root 'json/licenses.json'), ($licenses | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $Root 'json/exceptions.json'), ($exceptions | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
    foreach ($id in @('MIT', 'Apache-2.0', 'GPL-2.0-only', 'Classpath-exception-2.0')) {
        [IO.File]::WriteAllText((Join-Path $Root "text/$id.txt"), "canonical $id`n", [Text.UTF8Encoding]::new($false))
    }
}

function New-TestCrateFixture {
    param(
        [Parameter(Mandatory)] [string] $Root,
        [string] $License = 'MIT',
        [switch] $IncludeLicense
    )
    $packageName = 'fixture'
    $version = '1.0.0'
    $packageRoot = Join-Path $Root "$packageName-$version"
    $vendorRoot = Join-Path $Root 'vendor'
    New-Item -ItemType Directory -Path $packageRoot, $vendorRoot | Out-Null
    $manifest = "[package]`nname = `"$packageName`"`nversion = `"$version`"`nlicense = `"$License`"`nrepository = `"https://example.invalid/fixture`"`n"
    foreach ($name in @('Cargo.toml', 'Cargo.toml.orig')) {
        [IO.File]::WriteAllText((Join-Path $packageRoot $name), $manifest, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $vendorRoot $name), $manifest, [Text.UTF8Encoding]::new($false))
    }
    [IO.File]::WriteAllText((Join-Path $packageRoot 'lib.rs'), 'pub fn fixture() {}', [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $vendorRoot 'lib.rs'), 'pub fn fixture() {}', [Text.UTF8Encoding]::new($false))
    if ($IncludeLicense) {
        [IO.File]::WriteAllText((Join-Path $packageRoot 'LICENSE'), "fixture license`n", [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $vendorRoot 'LICENSE'), "fixture license`n", [Text.UTF8Encoding]::new($false))
    }
    $archive = Join-Path $Root "$packageName-$version.crate"
    & tar.exe -czf $archive -C $Root "$packageName-$version"
    if ($LASTEXITCODE -ne 0) { throw 'test crate archive creation failed' }
    $packageHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    $fileHashes = [ordered]@{}
    foreach ($file in Get-ChildItem -LiteralPath $vendorRoot -File | Sort-Object Name) {
        $fileHashes[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $checksum = [ordered]@{ files = $fileHashes; package = $packageHash }
    [IO.File]::WriteAllText((Join-Path $vendorRoot '.cargo-checksum.json'), ($checksum | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{
        archive = $archive
        vendor = $vendorRoot
        package = [pscustomobject]@{
            name = $packageName
            version = $version
            source = 'registry+https://github.com/rust-lang/crates.io-index'
            checksum = $packageHash
        }
    }
}

Describe 'Deno third-party notice fail-closed contracts' {
    It 'uses canonical SPDX text when a crate has no license file' {
        $root = Join-Path $TestDrive 'missing-license'
        $spdx = Join-Path $TestDrive 'spdx-single'
        New-TestSpdxCorpus $spdx
        New-Item -ItemType Directory -Path $root | Out-Null
        $fixture = New-TestCrateFixture -Root $root

        $result = Assert-DenoCratePackage -Package $fixture.package -VendorPath $fixture.vendor -CrateArchivePath $fixture.archive -SpdxRoot $spdx

        $result.resolution | Should Be 'spdx-canonical-fallback'
        @($result.spdxLicenseIds) | Should Be @('MIT')
        @($result.resolvedLicenseFiles).Count | Should Be 1
        $result.crateManifest.path | Should Be 'fixture-1.0.0/Cargo.toml.orig'
    }

    It 'rejects a Cargo package checksum mismatch' {
        $root = Join-Path $TestDrive 'checksum-mismatch'
        New-Item -ItemType Directory -Path $root | Out-Null
        $fixture = New-TestCrateFixture -Root $root -IncludeLicense
        $package = $fixture.package.psobject.Copy()
        $package.checksum = ('a' * 64)

        Get-TestExceptionMessage { Assert-DenoCratePackage -Package $package -VendorPath $fixture.vendor -CrateArchivePath $fixture.archive } | Should Be 'deno_cargo_checksum_mismatch:fixture@1.0.0'
    }

    It 'rejects coordinated vendor manifest license and checksum tampering against the crate bytes' {
        $root = Join-Path $TestDrive 'coordinated-vendor-tamper'
        New-Item -ItemType Directory -Path $root | Out-Null
        $fixture = New-TestCrateFixture -Root $root -IncludeLicense
        Add-Content -LiteralPath (Join-Path $fixture.vendor 'Cargo.toml.orig') -Value '# tampered'
        Add-Content -LiteralPath (Join-Path $fixture.vendor 'LICENSE') -Value 'tampered'
        $checksumPath = Join-Path $fixture.vendor '.cargo-checksum.json'
        $checksum = Get-Content -Raw -LiteralPath $checksumPath | ConvertFrom-Json
        $checksum.files.'Cargo.toml.orig' = (Get-FileHash -LiteralPath (Join-Path $fixture.vendor 'Cargo.toml.orig') -Algorithm SHA256).Hash.ToLowerInvariant()
        $checksum.files.LICENSE = (Get-FileHash -LiteralPath (Join-Path $fixture.vendor 'LICENSE') -Algorithm SHA256).Hash.ToLowerInvariant()
        [IO.File]::WriteAllText($checksumPath, ($checksum | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))

        Get-TestExceptionMessage { Assert-DenoCratePackage -Package $fixture.package -VendorPath $fixture.vendor -CrateArchivePath $fixture.archive } | Should Be 'deno_vendor_archive_mismatch:fixture@1.0.0:Cargo.toml.orig'
    }

    It 'takes package metadata and license bytes from the checksum-pinned crate archive' {
        $root = Join-Path $TestDrive 'archive-authority'
        New-Item -ItemType Directory -Path $root | Out-Null
        $fixture = New-TestCrateFixture -Root $root -IncludeLicense

        $result = Assert-DenoCratePackage -Package $fixture.package -VendorPath $fixture.vendor -CrateArchivePath $fixture.archive

        $result.license | Should Be 'MIT'
        $result.repository | Should Be 'https://example.invalid/fixture'
        $result.crateManifest.path | Should Be 'fixture-1.0.0/Cargo.toml.orig'
        @($result.resolvedLicenseFiles)[0].origin | Should Be 'package-archive'
        @($result.resolvedLicenseFiles)[0].archiveEntry | Should Be 'fixture-1.0.0/LICENSE'
    }

    It 'rejects a mutable Git source' {
        Get-TestExceptionMessage { Assert-DenoImmutableCargoSource -Source 'git+https://github.com/example/project?branch=main' } | Should Be 'deno_mutable_git_source'
    }

    It 'matches all 20 native paths and commits to the pinned rusty_v8 Git tree' {
        if ([string]::IsNullOrWhiteSpace($env:DENO_RUSTY_V8_GIT_REPOSITORY)) { throw 'DENO_RUSTY_V8_GIT_REPOSITORY is required for this test' }
        $nativePath = Join-Path (Split-Path -Parent (Split-Path -Parent $collectorPath)) 'release/runtime/v2.19.1-karon.2/deno/native-components.json'
        $native = Read-DenoJson $nativePath

        $result = Assert-DenoNativeClosure -Components @($native.components) -RustyV8GitRepositoryPath $env:DENO_RUSTY_V8_GIT_REPOSITORY -ExpectedCommit $native.rustyV8Commit -ExpectedTree $native.rustyV8Tree

        @($result.gitlinks).Count | Should Be 20
        $result.tree | Should Be '6c92c73eeacce6956b194cdaba8cfb020f11a960'
    }

    It 'rejects native path omission and commit substitution against the pinned rusty_v8 Git tree' {
        if ([string]::IsNullOrWhiteSpace($env:DENO_RUSTY_V8_GIT_REPOSITORY)) { throw 'DENO_RUSTY_V8_GIT_REPOSITORY is required for this test' }
        $nativePath = Join-Path (Split-Path -Parent (Split-Path -Parent $collectorPath)) 'release/runtime/v2.19.1-karon.2/deno/native-components.json'
        $native = Read-DenoJson $nativePath
        $withoutSimdutf = @($native.components | Where-Object path -cne 'third_party/simdutf')
        Get-TestExceptionMessage { Assert-DenoNativeClosure -Components $withoutSimdutf -RustyV8GitRepositoryPath $env:DENO_RUSTY_V8_GIT_REPOSITORY -ExpectedCommit $native.rustyV8Commit -ExpectedTree '6c92c73eeacce6956b194cdaba8cfb020f11a960' } | Should Be 'deno_native_component_missing:third_party/simdutf'
        $wrongCommit = @($native.components | ConvertTo-Json -Depth 10 | ConvertFrom-Json)
        @($wrongCommit | Where-Object path -ceq 'build')[0].commit = ('0' * 40)
        Get-TestExceptionMessage { Assert-DenoNativeClosure -Components $wrongCommit -RustyV8GitRepositoryPath $env:DENO_RUSTY_V8_GIT_REPOSITORY -ExpectedCommit $native.rustyV8Commit -ExpectedTree '6c92c73eeacce6956b194cdaba8cfb020f11a960' } | Should Be 'deno_native_component_commit_mismatch:build'
    }

    It 'rejects duplicate paths that collide by case' {
        Get-TestExceptionMessage { Assert-DenoUniquePaths -Paths @('crates/Foo/LICENSE', 'crates/foo/license') } | Should Be 'deno_path_case_collision:crates/foo/license'
    }

    It 'rejects a target closure that is not contained in the conservative superset' {
        Get-TestExceptionMessage { Assert-DenoTargetClosure -OfficialPackageIds @('a@1', 'b@1') -SupersetPackageIds @('a@1') } | Should Be 'deno_target_closure_mismatch:b@1'
    }

    It 'accepts the exact official Deno 2.7.14 Windows source identity' {
        if ([string]::IsNullOrWhiteSpace($env:DENO_OFFICIAL_EXE)) { throw 'DENO_OFFICIAL_EXE is required for this test' }
        $result = Assert-DenoReleaseIdentity -DenoExePath $env:DENO_OFFICIAL_EXE -ExpectedSha256 'b6e83993f1f1ab97075a77043de61118966d719b5450bc631251d47c3a34230b' -ExpectedVersion '2.7.14' -ExpectedTarget 'x86_64-pc-windows-msvc'

        $result.version | Should Be '2.7.14'
        $result.target | Should Be 'x86_64-pc-windows-msvc'
        $result.sha256 | Should Be 'b6e83993f1f1ab97075a77043de61118966d719b5450bc631251d47c3a34230b'
    }

    It 'records the exact embedded TypeScript 5.9.2 source license and build inclusion evidence' {
        foreach ($variable in @('DENO_SOURCE_ROOT', 'DENO_SOURCE_ARCHIVE', 'DENO_SPDX_ROOT')) {
            if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($variable))) { throw "$variable is required for this test" }
        }
        $manifestRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $collectorPath)) 'release/runtime/v2.19.1-karon.2/deno'
        $inputs = Read-DenoJson (Join-Path $manifestRoot 'inputs.json')
        $component = @($inputs.embeddedComponents | Where-Object id -ceq 'typescript@5.9.2')[0]
        $stage = Join-Path $TestDrive 'typescript-stage'
        New-Item -ItemType Directory -Path $stage | Out-Null
        $notice = [Text.StringBuilder]::new()
        $outputPaths = [Collections.Generic.List[string]]::new()

        $record = Add-DenoEmbeddedComponent -Component $component -DenoSourceRoot $env:DENO_SOURCE_ROOT -DenoSourceArchivePath $env:DENO_SOURCE_ARCHIVE -SpdxRoot $env:DENO_SPDX_ROOT -StageRoot $stage -Notice $notice -OutputPaths $outputPaths

        $record.version | Should Be '5.9.2'
        $record.sourceFile.path | Should Be 'cli/tsc/00_typescript.js'
        $record.sourceFile.length | Should Be 8492282
        $record.sourceFile.sha256 | Should Be '932f9fd96b20ef8c2496d7f70419c69fa40266a92d81a2b229737fa6dd324ac8'
        $record.denoSourceCommit | Should Be '2d674b25625bcc367853d00fe86f6e84390f88cb'
        $record.copyright | Should Be 'Copyright (c) Microsoft Corporation. All rights reserved.'
        $record.license | Should Be 'Apache-2.0'
        @($record.buildInclusionEvidence.role) | Should Be @('compressed-by-cli-build-rs', 'referenced-by-cli-tsc-module')
        $notice.ToString() | Should Match 'Apache License\s+Version 2\.0, January 2004'
        $stagedSource = Join-Path $stage $record.sourceFile.bundlePath
        (Get-Item -LiteralPath $stagedSource).Length | Should Be 8492282
        (Get-FileHash -LiteralPath $stagedSource -Algorithm SHA256).Hash.ToLowerInvariant() | Should Be '932f9fd96b20ef8c2496d7f70419c69fa40266a92d81a2b229737fa6dd324ac8'
    }

    It 'distinguishes the SPDX annotated tag object from its peeled commit' {
        $inputsPath = Join-Path (Split-Path -Parent (Split-Path -Parent $collectorPath)) 'release/runtime/v2.19.1-karon.2/deno/inputs.json'
        $inputs = Read-DenoJson $inputsPath

        $inputs.spdxLicenseList.tagObject | Should Be '779ef2e5dff6d4af389c53de5e97116ab0bb52e8'
        $inputs.spdxLicenseList.peeledCommit | Should Be 'c4a7237ec8f4654e867546f9f409749300f1bf4c'
        @($inputs.spdxLicenseList.psobject.Properties.Name) -contains 'commit' | Should Be $false
    }

    It 'rejects a junction in an input or output ancestor' {
        $target = Join-Path $TestDrive 'junction-target'
        $link = Join-Path $TestDrive 'junction-link'
        New-Item -ItemType Directory -Path $target | Out-Null
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null

        Get-TestExceptionMessage { Assert-DenoNoReparsePath -Path (Join-Path $link 'missing-child') } | Should Match '^deno_reparse_path_rejected:'
    }

    It 'uses same-volume process-owned staging and atomically refuses overwrite' {
        $scratch = Join-Path $TestDrive 'atomic-scratch'
        New-Item -ItemType Directory -Path $scratch | Out-Null
        $owned = New-DenoProcessStageRoot -ScratchRoot $scratch
        [IO.Path]::GetPathRoot($owned) | Should Be ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($scratch)))
        $source = Join-Path $owned 'pending-output'
        $destination = Join-Path $scratch 'final-output'
        New-Item -ItemType Directory -Path $source, $destination | Out-Null
        [IO.File]::WriteAllText((Join-Path $source 'new.txt'), 'new', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $destination 'sentinel.txt'), 'keep', [Text.UTF8Encoding]::new($false))

        Get-TestExceptionMessage { Complete-DenoAtomicDirectory -Source $source -Destination $destination } | Should Be 'deno_output_already_exists'
        [IO.File]::ReadAllText((Join-Path $destination 'sentinel.txt')) | Should Be 'keep'
    }

    It 'resolves compound SPDX OR AND WITH expressions completely' {
        $spdx = Join-Path $TestDrive 'spdx-compound'
        New-TestSpdxCorpus $spdx

        $result = Resolve-DenoSpdxExpression -Expression 'MIT OR (Apache-2.0 AND GPL-2.0-only WITH Classpath-exception-2.0)' -SpdxRoot $spdx

        @($result.licenseIds) | Should Be @('Apache-2.0', 'GPL-2.0-only', 'MIT')
        @($result.exceptionIds) | Should Be @('Classpath-exception-2.0')
        @($result.files).Count | Should Be 4
    }

    It 'rejects invalid or custom SPDX expressions' {
        $spdx = Join-Path $TestDrive 'spdx-invalid'
        New-TestSpdxCorpus $spdx

        Get-TestExceptionMessage { Resolve-DenoSpdxExpression -Expression 'LicenseRef-private OR MIT' -SpdxRoot $spdx } | Should Be 'deno_spdx_expression_invalid:LicenseRef-private OR MIT'
    }

    It 'rejects legacy slash syntax without an explicit mapping' {
        $spdx = Join-Path $TestDrive 'spdx-slash'
        New-TestSpdxCorpus $spdx

        Get-TestExceptionMessage { Resolve-DenoSpdxExpression -Expression 'Apache-2.0/MIT' -SpdxRoot $spdx } | Should Be 'deno_spdx_expression_invalid:Apache-2.0/MIT'
    }

    It 'accepts only the exact content-addressed fxhash LicenseRef mapping' {
        foreach ($variable in @('DENO_FXHASH_CRATE', 'DENO_FXHASH_VENDOR', 'DENO_SPDX_ROOT')) {
            if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($variable))) { throw "$variable is required for this test" }
        }
        $fallbackPath = Join-Path (Split-Path -Parent (Split-Path -Parent $collectorPath)) 'release/runtime/v2.19.1-karon.2/deno/upstream-license-fallbacks.json'
        $fallbacks = Read-DenoJson $fallbackPath
        $mapping = @($fallbacks.licenseRefMappings | Where-Object id -ceq 'fxhash@0.2.1')[0]
        $package = [pscustomobject]@{ name = 'fxhash'; version = '0.2.1'; checksum = 'c31b6d751ae2c7f11320402d34e41349dd1016f8d5d45e48c4312bc8625af50c' }

        $result = Resolve-DenoExplicitLicenseRef -Package $package -DeclaredLicense 'Apache-2.0/MIT' -CrateArchivePath $env:DENO_FXHASH_CRATE -SpdxRoot $env:DENO_SPDX_ROOT -Mapping $mapping

        $result.licenseRefId | Should Be 'LicenseRef-fxhash-0.2.1-apache-2.0-mit-a7af1b0aa267'
        $result.extractedText | Should Match 'Author-declared license text \(verbatim\):\r?\nApache-2\.0/MIT'
        $result.extractedText | Should Match 'Canonical text named by the literal declaration: Apache-2\.0'
        $result.extractedText | Should Match 'Canonical text named by the literal declaration: MIT'
        Get-TestExceptionMessage { Resolve-DenoExplicitLicenseRef -Package $package -DeclaredLicense 'MIT/Apache-2.0' -CrateArchivePath $env:DENO_FXHASH_CRATE -SpdxRoot $env:DENO_SPDX_ROOT -Mapping $mapping } | Should Be 'deno_license_ref_declaration_mismatch:fxhash@0.2.1'
        $fakePackage = [pscustomobject]@{ name = 'fxhash'; version = '0.2.1'; checksum = ('0' * 64) }
        Get-TestExceptionMessage { Resolve-DenoExplicitLicenseRef -Package $fakePackage -DeclaredLicense 'Apache-2.0/MIT' -CrateArchivePath $env:DENO_FXHASH_CRATE -SpdxRoot $env:DENO_SPDX_ROOT -Mapping $mapping } | Should Be 'deno_license_ref_crate_hash_mismatch:fxhash@0.2.1'
    }

    It 'produces deterministic success ZIP output' {
        $first = Join-Path $TestDrive 'zip-first'
        $second = Join-Path $TestDrive 'zip-second'
        New-Item -ItemType Directory -Path (Join-Path $first 'nested'), (Join-Path $second 'nested') | Out-Null
        [IO.File]::WriteAllText((Join-Path $first 'nested/b.txt'), 'beta', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $first 'a.txt'), 'alpha', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $second 'a.txt'), 'alpha', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $second 'nested/b.txt'), 'beta', [Text.UTF8Encoding]::new($false))

        $firstHash = New-DenoDeterministicZip -SourceRoot $first -ZipPath (Join-Path $TestDrive 'first.zip')
        $secondHash = New-DenoDeterministicZip -SourceRoot $second -ZipPath (Join-Path $TestDrive 'second.zip')

        $firstHash | Should Be $secondHash
    }
}
