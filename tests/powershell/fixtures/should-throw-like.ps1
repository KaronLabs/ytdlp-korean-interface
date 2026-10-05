function Assert-TestThrowsLike {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [scriptblock] $ScriptBlock,

        [Parameter(Mandatory = $true)]
        [string] $ExpectedPattern
    )

    process {
        $caughtError = $null
        try {
            & $ScriptBlock | Out-Null
        }
        catch {
            $caughtError = $_
        }

        $caughtError | Should -Not -BeNullOrEmpty
        ($caughtError.Exception.Message -like $ExpectedPattern) | Should -BeTrue
    }
}
