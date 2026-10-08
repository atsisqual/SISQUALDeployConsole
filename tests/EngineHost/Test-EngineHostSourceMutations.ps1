#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modulePath = Join-Path $repoRoot 'runtime\Sisqual.Runtime.EngineHost.psm1'
$text = [IO.File]::ReadAllText($modulePath)

$anchors = @(
    [pscustomobject]@{ Name = 'manifest hash enforcement'; Text = "if (`$actualHash -cne `$expectedHash) { throw 'ENGINE_HASH_MISMATCH' }" },
    [pscustomobject]@{ Name = 'stdout stderr result secret scan'; Text = 'Find-SisqualSecretLeak -Texts @($rawResultText,$stdout,$stderr) -Secrets $Secrets' },
    [pscustomobject]@{ Name = 'schema arithmetic upper bound'; Text = 'if (($summarySucceeded + $summaryFailed) -gt $summaryTarget) { return $false }' },
    [pscustomobject]@{ Name = 'same-session preview fingerprint'; Text = "if (-not `$script:PreviewFingerprints.ContainsKey(`$previewKey) -or `$script:PreviewFingerprints[`$previewKey] -cne `$PlanFingerprint) { throw 'PLAN_CHANGED' }" },
    [pscustomobject]@{ Name = 'documented child exit codes only'; Text = 'if ($exitCode -notin @(0,1,2,3))' },
    [pscustomobject]@{ Name = 'successful preview cache gate'; Text = 'if ([bool]$result.succeeded) {' },
    [pscustomobject]@{ Name = 'PowerShell 7 ACL extension'; Text = '[System.IO.FileSystemAclExtensions]::SetAccessControl' },
    [pscustomobject]@{ Name = 'JSON escaped secret representation'; Text = '$jsonLiteral = ConvertTo-Json -InputObject $value -Compress' },
    [pscustomobject]@{ Name = 'backup schema validation'; Text = '$backupAllowed = @(''created'',''name'',''location'',''sha256'',''restoreHint'')' },
    [pscustomobject]@{ Name = 'result timestamp strings preserved'; Text = 'ConvertFrom-Json -Depth 50 -DateKind String' },
    [pscustomobject]@{ Name = 'Seal-Package canonical serializer reused'; Text = 'function ConvertTo-SisqualCanonicalJson' },
    [pscustomobject]@{ Name = 'decoded result secret scan'; Text = 'Find-SisqualDecodedSecretLeak -Value $result -Secrets $Secrets' },
    [pscustomobject]@{ Name = 'failed completion audit helper'; Text = 'function New-SisqualLoggedEngineFailureResult' },
    [pscustomobject]@{ Name = 'async stdin byte write'; Text = 'StandardInput.BaseStream.WriteAsync($requestBytes, 0, $requestBytes.Length)' },
    [pscustomobject]@{ Name = 'catalog path verification'; Text = 'Get-SisqualVerifiedCatalogPath -PackageRoot' },
    [pscustomobject]@{ Name = 'action enabled guard'; Text = "throw 'ACTION_DISABLED'" },
    [pscustomobject]@{ Name = 'action engine mapping guard'; Text = "throw 'ACTION_ENGINE_MISMATCH'" },
    [pscustomobject]@{ Name = 'completion summary audit'; Text = 'targetCount = [int]$result.summary.targetCount' },
    [pscustomobject]@{ Name = 'machine ownership comes from active catalog session'; Text = "Get-Command -Name 'Get-SisqualRuntimeCatalogMachineName' -Module 'Sisqual.Runtime.Catalog'" },
    [pscustomobject]@{ Name = 'redirected stream drain is deadline bounded'; Text = 'Wait-SisqualEngineTaskUntil -Task $stdoutTask -DeadlineUtc $drainDeadline' },
    [pscustomobject]@{ Name = 'invalid UTF8 result is mapped'; Text = 'catch [Text.DecoderFallbackException]' },
    [pscustomobject]@{ Name = 'the engine is started through the host launcher that waits for the gate'; Text = "'-File',`$script:EngineLauncherPath,'-EnginePath',`$enginePath" },
    [pscustomobject]@{ Name = 'the gate line is sent only after the job assignment'; Text = 'GetBytes("GO`n" + $requestJson)' },
    [pscustomobject]@{ Name = 'form-style URL encoding is decoded before the leak check'; Text = '[System.Net.WebUtility]::UrlDecode($text)' },
    [pscustomobject]@{ Name = 'engine is contained in a job object'; Text = '$job.Assign($process.Handle)' },
    [pscustomobject]@{ Name = 'survivors are terminated through the job'; Text = '$job.TerminateSurvivors()' },
    [pscustomobject]@{ Name = 'the console host is not counted as a survivor'; Text = 'if (IsSystemConsoleHost(pid)) continue;' },
    [pscustomobject]@{ Name = 'stream drain is counted from the end of the engine, not from its expired deadline'; Text = '$drainDeadline = [DateTime]::UtcNow.AddSeconds($script:StreamDrainSeconds)' },
    [pscustomobject]@{ Name = 'a member that already exited is not a survivor'; Text = 'catch (ArgumentException) {' },
    [pscustomobject]@{ Name = 'survivors are those still alive after a settling time'; Text = 'if (names.Count == 0 || DateTime.UtcNow >= deadline) break;' },
    [pscustomobject]@{ Name = 'failure audit carries a reason'; Text = 'error = $ErrorCode; reason = $Reason; instance = [string]$InstanceCode' },
    [pscustomobject]@{ Name = 'machine ownership uses the operating system name'; Text = '[Environment]::MachineName' },
    [pscustomobject]@{ Name = 'only declared secrets are forwarded'; Text = "throw 'SECRET_NOT_DECLARED'" },
    [pscustomobject]@{ Name = 'cancel signal failure does not stop timeout handling'; Text = 'catch { $cancelSignalFailed = $true }' },
    [pscustomobject]@{ Name = 'selected instance must exist in the verified catalog'; Text = "throw 'INSTANCE_NOT_FOUND'" },
    [pscustomobject]@{ Name = 'engine environment is cleared and allowlisted'; Text = '$startInfo.Environment.Clear()' },
    [pscustomobject]@{ Name = 'result validation cannot throw out of the host'; Text = 'function Test-SisqualEngineResultSafe' }
)

$passed = 0
$failed = 0
foreach ($anchor in $anchors) {
    $count = ([regex]::Matches($text, [regex]::Escape($anchor.Text))).Count
    if ($count -ge 1) { $passed++; Write-Host ('PASS  live guard: ' + $anchor.Name) }
    else { $failed++; Write-Host ('FAIL  missing guard: ' + $anchor.Name) }
}

Write-Host ("EngineHost source mutation anchors: {0} passed / {1} failed" -f $passed, $failed)
if ($failed -ne 0) { exit 1 }
