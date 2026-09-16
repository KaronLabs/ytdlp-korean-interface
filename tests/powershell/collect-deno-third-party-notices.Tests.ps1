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

Describe 'Deno third-party notice fail-closed contracts' {
    It 'uses canonical SPDX text when a crate has no license file' {
        $root = Join-Path $TestDrive 'missing-license'
        $spdx = Join-Path $TestDrive 'spdx-single'
        New-Item -ItemType Directory -Path $root | Out-Null
        New-TestSpdxCorpus $spdx
        [IO.File]::WriteAllText((Join-Path $root 'Cargo.toml'), "[package]`nname = `"fixture`"`nversion = `"1.0.0`"`nlicense = `"MIT`"`n", [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $root '.cargo-checksum.json'), '{"files":{},"package":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}', [Text.UTF8Encoding]::new($false))
        $package = [pscustomobject]@{ name = 'fixture'; version = '1.0.0'; source = 'registry+https://github.com/rust-lang/crates.io-index'; checksum = ('a' * 64) }

        $result = Assert-DenoCratePackage -Package $package -VendorPath $root -SpdxRoot $spdx

        $result.resolution | Should Be 'spdx-canonical-fallback'
        @($result.spdxLicenseIds) | Should Be @('MIT')
        @($result.resolvedLicenseFiles).Count | Should Be 1
    }

    It 'rejects a Cargo package checksum mismatch' {
        $root = Join-Path $TestDrive 'checksum-mismatch'
        New-Item -ItemType Directory -Path $root | Out-Null
        [IO.File]::WriteAllText((Join-Path $root 'Cargo.toml'), "[package]`nname = `"fixture`"`nversion = `"1.0.0`"`nlicense = `"MIT`"`n", [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $root 'LICENSE'), 'fixture license', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $root '.cargo-checksum.json'), '{"files":{},"package":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}', [Text.UTF8Encoding]::new($false))
        $package = [pscustomobject]@{ name = 'fixture'; version = '1.0.0'; source = 'registry+https://github.com/rust-lang/crates.io-index'; checksum = ('a' * 64) }

        Get-TestExceptionMessage { Assert-DenoCratePackage -Package $package -VendorPath $root } | Should Be 'deno_cargo_checksum_mismatch:fixture@1.0.0'
    }

    It 'rejects a mutable Git source' {
        Get-TestExceptionMessage { Assert-DenoImmutableCargoSource -Source 'git+https://github.com/example/project?branch=main' } | Should Be 'deno_mutable_git_source'
    }

    It 'rejects an omitted required V8 third-party component' {
        Get-TestExceptionMessage { Assert-DenoNativeClosure -RequiredComponents @('v8', 'third_party/icu', 'third_party/simdutf') -ObservedComponents @('v8', 'third_party/icu') } | Should Be 'deno_native_component_missing:third_party/simdutf'
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
