#requires -Version 7.4

. (Join-Path $PSScriptRoot 'fixtures\should-throw-like.ps1')

Import-Module (Join-Path $PSScriptRoot '..\..\tools\gui-release-waiver.psm1') -Force

function New-WaiverFixture {
    param([string] $Name)
    $root = Join-Path $TestDrive $Name
    $candidate = Join-Path $root 'candidate'
    [void][IO.Directory]::CreateDirectory($candidate)
    $exe = Join-Path $candidate 'ytdlp-interface.exe'
    [IO.File]::WriteAllText($exe, 'sealed executable', [Text.UTF8Encoding]::new($false))
    $commit = 'c' * 40
    $tree = 'd' * 40
    $exeRecord = [ordered]@{ fileName = 'ytdlp-interface.exe'; length = [long](Get-Item $exe).Length; sha256 = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant() }
    $manifest = Join-Path $candidate 'candidate-manifest.json'
    $manifestValue = [ordered]@{ schemaVersion = 1; applicationSourceCommit = $commit; applicationSourceTree = $tree; files = @([ordered]@{ path = 'ytdlp-interface.exe'; length = $exeRecord.length; sha256 = $exeRecord.sha256 }) }
    [IO.File]::WriteAllText($manifest, ($manifestValue | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))
    $value = [ordered]@{
        schemaVersion = 'karon-gui-validation-waiver/v1'; releaseVersion = 'v2.19.1-karon.2'; status = 'WAIVED_BY_OWNER'
        ownerInstruction = '남은 gui 확인 거ㅗㄴ너뛰고 릴리즈 까지 달려'
        limitedObservation = [ordered]@{ text = '잘되네'; classification = 'LIMITED_UNSTRUCTURED_USER_OBSERVATION' }
        scope = [ordered]@{
            caseIds = @('ko-KR-100', 'ko-KR-150', 'ko-KR-200', 'en-US-100', 'en-US-150', 'en-US-200')
            manualChecks = @('fullVideoLifecycle', 'mp3Conversion', 'settingsSaveRestartRestore', 'legacySettingsTransition')
            automaticTestsWaived = $false; licenseChecksWaived = $false
        }
        candidate = [ordered]@{
            manifest = [ordered]@{ fileName = 'candidate-manifest.json'; length = [long](Get-Item $manifest).Length; sha256 = (Get-FileHash $manifest -Algorithm SHA256).Hash.ToLowerInvariant() }
            executable = $exeRecord
        }
        applicationSource = [ordered]@{ commit = $commit; tree = $tree }
    }
    [pscustomobject]@{ Path = (Join-Path $root 'gui-validation-waiver.json'); Candidate = $candidate; Value = $value; Commit = $commit; Tree = $tree; Exe = $exe }
}

function Save-WaiverFixture {
    param([object] $Fixture)
    [IO.File]::WriteAllText($Fixture.Path, ($Fixture.Value | ConvertTo-Json -Depth 32), [Text.UTF8Encoding]::new($false))
}

function Read-WaiverFixture {
    param([object] $Fixture)
    Read-KaronGuiValidationWaiver -Path $Fixture.Path -CandidateDirectory $Fixture.Candidate -ApplicationSourceCommit $Fixture.Commit -ApplicationSourceTree $Fixture.Tree
}

Describe 'Explicit GUI validation input selection' {
    It 'rejects neither route and incomplete normal evidence' {
        { Assert-KaronGuiValidationInputs } | Assert-TestThrowsLike -ExpectedPattern '*gui_validation_input_missing*'
        { Assert-KaronGuiValidationInputs -GuiValidationSummaryPath 'summary.json' } | Assert-TestThrowsLike -ExpectedPattern '*gui_validation_input_missing*'
        { Assert-KaronGuiValidationInputs -GuiValidationSummaryPath 'summary.json' -GuiValidationEvidenceManifestPath 'evidence.json' -RequireSchema } | Assert-TestThrowsLike -ExpectedPattern '*gui_validation_input_missing*'
    }

    It 'rejects each explicitly supplied normal input alongside a waiver even if empty' -TestCases @(
        @{ Name = 'GuiValidationSummaryPath' }, @{ Name = 'GuiValidationEvidenceManifestPath' }, @{ Name = 'GuiValidationSchemaPath' }
    ) {
        param($Name)
        $bound = @{ GuiValidationWaiverPath = 'waiver.json' }
        $bound[$Name] = ''
        { Assert-KaronGuiValidationInputs -GuiValidationWaiverPath 'waiver.json' -BoundParameters $bound } | Assert-TestThrowsLike -ExpectedPattern '*gui_validation_input_conflict*'
    }

    It 'selects only complete normal evidence or the explicit waiver' {
        (Assert-KaronGuiValidationInputs -GuiValidationSummaryPath 'summary.json' -GuiValidationEvidenceManifestPath 'evidence.json' -GuiValidationSchemaPath 'schema.json' -RequireSchema) | Should -Be 'normal'
        (Assert-KaronGuiValidationInputs -GuiValidationWaiverPath 'waiver.json') | Should -Be 'waiver'
        { Assert-KaronGuiValidationInputs -BoundParameters @{ GuiValidationWaiverPath = '' } } | Assert-TestThrowsLike -ExpectedPattern '*gui_validation_input_missing*'
    }
}

Describe 'Owner waiver closed schema and candidate binding' {
    It 'returns the limited observation and exact authorization file identity' {
        $fixture = New-WaiverFixture 'accepted'
        Save-WaiverFixture $fixture
        $result = Read-WaiverFixture $fixture
        $result.Record.status | Should -Be 'WAIVED_BY_OWNER'
        $result.Record.ownerInstruction | Should -Be '남은 gui 확인 거ㅗㄴ너뛰고 릴리즈 까지 달려'
        $result.Record.limitedObservation.text | Should -Be '잘되네'
        $result.Record.scope.automaticTestsWaived | Should -Be $false
        $result.Record.scope.licenseChecksWaived | Should -Be $false
        $result.FileRecord.sha256 | Should -Be (Get-FileHash $fixture.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    It 'accepts an uppercase executable digest in the sealed candidate manifest' {
        $fixture = New-WaiverFixture 'uppercase-candidate-digest'
        $manifestPath = Join-Path $fixture.Candidate 'candidate-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.files[0].sha256 = $manifest.files[0].sha256.ToUpperInvariant()
        [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))
        $fixture.Value.candidate.manifest.length = [long](Get-Item $manifestPath).Length
        $fixture.Value.candidate.manifest.sha256 = (Get-FileHash $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Save-WaiverFixture $fixture
        $result = Read-WaiverFixture $fixture
        $result.Record.status | Should -Be 'WAIVED_BY_OWNER'
        $result.Record.scope.automaticTestsWaived | Should -Be $false
        $result.Record.scope.licenseChecksWaived | Should -Be $false
    }

    It 'rejects a different uppercase executable digest in the sealed candidate manifest' {
        $fixture = New-WaiverFixture 'different-uppercase-candidate-digest'
        $manifestPath = Join-Path $fixture.Candidate 'candidate-manifest.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.files[0].sha256 = 'A' * 64
        [IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 16), [Text.UTF8Encoding]::new($false))
        $fixture.Value.candidate.manifest.length = [long](Get-Item $manifestPath).Length
        $fixture.Value.candidate.manifest.sha256 = (Get-FileHash $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        Save-WaiverFixture $fixture
        { Read-WaiverFixture $fixture } | Assert-TestThrowsLike -ExpectedPattern '*gui_validation_waiver_candidate_mismatch*'
    }

    It 'rejects broader authority, fabricated evidence, coercible types and incomplete scope' -TestCases @(
        @{ Name = 'release'; Mutate = { param($v) $v.releaseVersion = 'v2.19.1-karon.3' } },
        @{ Name = 'pass'; Mutate = { param($v) $v.status = 'PASS' } },
        @{ Name = 'array-status'; Mutate = { param($v) $v.status = @('WAIVED_BY_OWNER') } },
        @{ Name = 'instruction'; Mutate = { param($v) $v.ownerInstruction = 'skip all checks' } },
        @{ Name = 'observation'; Mutate = { param($v) $v.limitedObservation.text = 'six cases passed' } },
        @{ Name = 'observation-class'; Mutate = { param($v) $v.limitedObservation.classification = 'PASS' } },
        @{ Name = 'auto'; Mutate = { param($v) $v.scope.automaticTestsWaived = $true } },
        @{ Name = 'license'; Mutate = { param($v) $v.scope.licenseChecksWaived = $true } },
        @{ Name = 'string-false'; Mutate = { param($v) $v.scope.automaticTestsWaived = 'false' } },
        @{ Name = 'five'; Mutate = { param($v) $v.scope.caseIds = @($v.scope.caseIds | Select-Object -First 5) } },
        @{ Name = 'duplicate-case'; Mutate = { param($v) $v.scope.caseIds[5] = 'ko-KR-100' } },
        @{ Name = 'manual'; Mutate = { param($v) $v.scope.manualChecks = @('mp3Conversion') } },
        @{ Name = 'screenshots'; Mutate = { param($v) $v.screenshots = @('invented.png') } },
        @{ Name = 'media'; Mutate = { param($v) $v.candidate.media = 'invented.mp4' } },
        @{ Name = 'string-length'; Mutate = { param($v) $v.candidate.executable.length = [string]$v.candidate.executable.length } },
        @{ Name = 'array-hash'; Mutate = { param($v) $v.candidate.manifest.sha256 = @($v.candidate.manifest.sha256) } },
        @{ Name = 'missing'; Mutate = { param($v) [void]$v.Remove('ownerInstruction') } }
    ) {
        param($Name, $Mutate)
        $fixture = New-WaiverFixture $Name
        & $Mutate $fixture.Value
        Save-WaiverFixture $fixture
        { Read-WaiverFixture $fixture } | Assert-TestThrowsLike -ExpectedPattern '*gui_validation_waiver_*'
    }

    It 'rejects substituted manifest, executable and application source identities' -TestCases @(
        @{ Name = 'manifest-hash'; Mutate = { param($f) $f.Value.candidate.manifest.sha256 = 'a' * 64 } },
        @{ Name = 'exe-hash'; Mutate = { param($f) $f.Value.candidate.executable.sha256 = 'a' * 64 } },
        @{ Name = 'exe-bytes'; Mutate = { param($f) [IO.File]::WriteAllText($f.Exe, 'swapped executable') } },
        @{ Name = 'commit'; Mutate = { param($f) $f.Value.applicationSource.commit = 'a' * 40 } },
        @{ Name = 'tree'; Mutate = { param($f) $f.Value.applicationSource.tree = 'a' * 40 } },
        @{ Name = 'proven-source'; Mutate = { param($f) $f.Commit = 'a' * 40 } }
    ) {
        param($Name, $Mutate)
        $fixture = New-WaiverFixture $Name
        & $Mutate $fixture
        Save-WaiverFixture $fixture
        { Read-WaiverFixture $fixture } | Assert-TestThrowsLike -ExpectedPattern '*gui_validation_waiver_*mismatch*'
    }

    It 'rejects duplicate and case-folded JSON keys' -TestCases @(@{ Name = 'status' }, @{ Name = 'Status' }) {
        param($Name)
        $fixture = New-WaiverFixture ('duplicate-' + $Name)
        $text = $fixture.Value | ConvertTo-Json -Depth 32 -Compress
        [IO.File]::WriteAllText($fixture.Path, ('{"' + $Name + '":"WAIVED_BY_OWNER",' + $text.Substring(1)), [Text.UTF8Encoding]::new($false))
        { Read-WaiverFixture $fixture } | Assert-TestThrowsLike -ExpectedPattern '*gui_validation_waiver_json_invalid*'
    }
}
