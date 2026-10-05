#requires -Version 7.4

[CmdletBinding()]
param([Parameter(Mandatory)] [string[]] $Path)

$ErrorActionPreference = 'Stop'
Import-Module Pester -RequiredVersion 4.10.1 -Force -ErrorAction Stop
foreach ($test in $Path) {
    if (-not (Test-Path -LiteralPath $test -PathType Leaf)) { throw "contract_test_missing: $test" }
    $result = Invoke-Pester -Script $test -PassThru
    if ($null -eq $result -or $result.TotalCount -le 0 -or
        $result.FailedCount -gt 0 -or $result.PassedCount -ne $result.TotalCount) {
        Write-Error "contract_test_not_passed: $test" -ErrorAction Continue
        exit 1
    }
}
exit 0
