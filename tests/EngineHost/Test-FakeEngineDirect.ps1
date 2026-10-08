#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fakeEngine = Join-Path $PSScriptRoot 'FakeEngine.ps1'

function Invoke-FakeDirect {
    param([string]$InputJson)
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = (Get-Process -Id $PID).Path
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    [void]$psi.ArgumentList.Add('-NoLogo')
    [void]$psi.ArgumentList.Add('-NoProfile')
    [void]$psi.ArgumentList.Add('-NonInteractive')
    [void]$psi.ArgumentList.Add('-File')
    [void]$psi.ArgumentList.Add($fakeEngine)
    $p = [Diagnostics.Process]::new()
    $p.StartInfo = $psi
    try {
        if (-not $p.Start()) { throw 'Could not start fake engine.' }
        $p.StandardInput.Write($InputJson)
        $p.StandardInput.Close()
        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        return [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $stdout; Stderr = $stderr }
    }
    finally { $p.Dispose() }
}

$passed = 0
$failed = 0
function Check([string]$Name, [bool]$Condition) {
    if ($Condition) { $script:passed++; Write-Host ('PASS  ' + $Name) }
    else { $script:failed++; Write-Host ('FAIL  ' + $Name) }
}

$bad = Invoke-FakeDirect -InputJson '{}'
Check 'fake engine invalid request exits 2' ($bad.ExitCode -eq 2)

$badUtf = Invoke-FakeDirect -InputJson '{"contractVersion":"wrong"}'
Check 'fake engine rejects wrong contract version with exit 2' ($badUtf.ExitCode -eq 2)

Write-Host ("FakeEngine direct conformance: {0} passed / {1} failed" -f $passed, $failed)
if ($failed -ne 0) { exit 1 }
