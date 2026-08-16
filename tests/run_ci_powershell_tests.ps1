$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$testsRoot = Join-Path $PSScriptRoot 'powershell'
$runtimeTest = Join-Path $testsRoot 'runtime-maintenance.Tests.ps1'

$ordinaryTests = @(Get-ChildItem -LiteralPath $testsRoot -File -Filter '*.Tests.ps1' | Where-Object { $_.Name -ne 'runtime-maintenance.Tests.ps1' } | Sort-Object Name)
foreach ($testPath in $ordinaryTests) {
    Write-Host ('START ' + $testPath.Name)
    & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $testPath.FullName
    if ($LASTEXITCODE -ne 0) { Write-Error ('FAIL ' + $testPath.Name); exit $LASTEXITCODE }
    Write-Host ('PASS ' + $testPath.Name)
}

# GitHub-hosted Windows runners execute with an elevated administrator token.
# The public UpdateYtDlp command intentionally rejects that environment before
# doing any recovery or metadata work. Three public-command UX tests require an
# unelevated token and remain covered by the normal local runner. CI instead
# executes every elevation-independent runtime-maintenance fixture individually
# and explicitly keeps the elevated-rejection security test in the set below.
$runtimeTests = @(
    'Test-RepairSettingsPreservesUnrelatedValues',
    'Test-RepairSettingsLeavesMalformedInputUntouched',
    'Test-RepairSettingsWhatIfDoesNotReplace',
    'Test-RepairSettingsPreservesValidJsonBomAndNoBom',
    'Test-RuntimeMaintenanceModuleExportsOnlyPublicCommands',
    'Test-UpdateYtDlpRejectsCallerControlledSeams',
    'Test-YtDlpTransactionBlocksHashMismatch',
    'Test-YtDlpTransactionBlocksVersionMismatch',
    'Test-YtDlpTransactionRejectsNonCanonicalTarget',
    'Test-YtDlpTransactionRejectsTraversalTarget',
    'Test-YtDlpTransactionWritesCanonicalSiblingProvenance',
    'Test-YtDlpTransactionRecordsPreviousVersionInProvenance',
    'Test-YtDlpTransactionRestoresProvenanceAfterCommitFailure',
    'Test-YtDlpTransactionRecoversInterruptedReplacementFromJournal',
    'Test-YtDlpTransactionRejectsCorruptJournalBackupBeforeOverwrite',
    'Test-YtDlpRecoveryRejectsPreviousVersionMismatchBeforeMutation',
    'Test-YtDlpRecoveryRejectsMalformedProvenanceBase64BeforeMutation',
    'Test-YtDlpTransactionWhatIfDoesNotRecoverPendingJournal',
    'Test-YtDlpRecoveryRejectsUntrustedBackupPathsBeforeExecution',
    'Test-YtDlpRecoveryRequiresTypedJournalSchemaAndEmptyAbsentPreimage',
    'Test-YtDlpRecoveryRetainsJournalWhenProvenanceVerificationFails',
    'Test-YtDlpRollbackRetainsJournalWhenProvenanceVerificationFails',
    'Test-YtDlpRecoveryHandlesPreReplaceJournal',
    'Test-YtDlpRecoveryRejectsMissingBackupWithoutMutation',
    'Test-YtDlpRecoveryReplayIsIdempotent',
    'Test-YtDlpRecoveryRejectsSelfDeclaredBackupIdentity',
    'Test-UpdateYtDlpRejectsElevatedExecutionBeforeRecovery',
    'Test-YtDlpRecoveryKeepsSnapshotWriteLockedThroughRestore',
    'Test-YtDlpSuccessRejectsWrongProvenanceBeforeJournalDelete',
    'Test-YtDlpSuccessRejectsDeployedExecutableToctouBeforeJournalDelete',
    'Test-LockedYtDlpSnapshotPinsIdentityAgainstPathSwap',
    'Test-YtDlpRollbackRejectsMutatedGeneratedBackupBeforeTargetMutation',
    'Test-YtDlpTransactionRollsBackPostReplacementFailure',
    'Test-YtDlpTransactionWhatIfDoesNotReplace'
)

foreach ($testName in $runtimeTests) {
    Write-Host ('START runtime-maintenance::' + $testName)
    & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $runtimeTest -TestFilter $testName
    if ($LASTEXITCODE -ne 0) { Write-Error ('FAIL runtime-maintenance::' + $testName); exit $LASTEXITCODE }
    Write-Host ('PASS runtime-maintenance::' + $testName)
}

Write-Host ('CI PowerShell contracts passed. Runtime-maintenance elevated-safe tests=' + $runtimeTests.Count + '; unelevated-only tests deferred=3.')
exit 0
