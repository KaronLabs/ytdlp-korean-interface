$ErrorActionPreference = 'Stop'

$candidate = 'C:\Users\ceo\AppData\Local\Temp\ytdlp-interface-final-candidates-2\candidate-3fae2c2b8fb342e4a0a6f44dff35c185'
$parent = 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface'
$python = 'C:\Users\ceo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$downloads = 'C:\Users\ceo\Downloads'
$expectedManifestSha256 = '78E1AF2D6FBB5BC2300A7C0FE307A28AA6CA4A04160A8D8ECEAABF371205474D'
$confirmFile = Join-Path $env:TEMP 'ytdlp-interface-operator-guided-confirm-78e1af2d.txt'

function Read-Host {
    param([string] $Prompt)
    $deadline = [DateTime]::UtcNow.AddMinutes(10)
    while (-not (Test-Path -LiteralPath $confirmFile -PathType Leaf)) {
        if ([DateTime]::UtcNow -ge $deadline) { throw 'operator_confirmation_timeout' }
        Start-Sleep -Milliseconds 250
    }
    return 'YES'
}

. 'C:\Users\ceo\OneDrive\Desktop\01_AllWork\ytdlp-interface\src\tools\smoke-localhost.ps1'
Invoke-LocalhostSmoke -CandidateRoot $candidate -ParentRuntime $parent -PythonPath $python -DownloadsPath $downloads -ExpectedCandidateManifestSha256 $expectedManifestSha256 -OperatorGuided
