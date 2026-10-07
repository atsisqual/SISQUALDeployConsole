#requires -Version 7.0
<#
.SYNOPSIS
    Unit tests for the core of tools/lib/Sisqual.CredentialImport.psm1 (step B6.3b): no database, fake rows.

.DESCRIPTION
    Rows that the SQL reader would return are built here. The vault is a real one in a temporary folder (KDF iterations
    lowered for speed). The rule secret selection is compared with Protect-RuleRow of the real conversion tool, which is
    dot-sourced, so the two can never drift apart. Marker values stand in for secrets. Exits 1 on any failure.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoTools = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools')).Path
$importPath = Join-Path $repoTools 'lib' 'Sisqual.CredentialImport.psm1'
$convertPath = Join-Path $repoTools 'Convert-ManagementDb.ps1'
Import-Module (Join-Path $repoTools 'lib' 'Sisqual.CredentialVault.psm1') -Force
Import-Module $importPath -Force
$vaultModule = Get-Module Sisqual.CredentialVault
& $vaultModule { $script:MinIterations = 1000; $script:DefaultIterations = 1000 }
$importModule = Get-Module Sisqual.CredentialImport

$script:Failures = 0
$script:Passed = 0
function Assert-That { param([string]$Name, [bool]$Condition) if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) } else { $script:Failures++; Write-Host ('FAIL  {0}' -f $Name) } }
function Assert-Throws {
    param([string]$Name, [scriptblock]$Block, [string]$Like = '*')
    $threw = $false; $message = ''
    try { & $Block } catch { $threw = $true; $message = $_.Exception.Message }
    Assert-That $Name ($threw -and ($message -like $Like))
}
function New-Pass { param([string]$Text) return (ConvertTo-SecureString -String $Text -AsPlainText -Force) }
function Get-Sha { param([string]$Path) return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Path))) }
function New-Cat { param([string]$Code, [bool]$Iis = $true, [bool]$Web = $true, [bool]$Mobile = $true) return [ordered]@{ InstanceCode = $Code; IisIdentityConfigured = $Iis; WebAccessConfigured = $Web; MobileAppTokenConfigured = $Mobile } }
function New-Run { param([string]$Code, [string]$Type, $Secret, [int]$Version = 1) return [ordered]@{ InstanceCode = $Code; CredentialType = $Type; SecretValue = $Secret; SecretVersion = $Version } }
function New-Rule { param([string]$Id, $Sensitive, $Template) return [ordered]@{ Id = $Id; IsSensitive = $Sensitive; Template = $Template } }

$m1 = 'MARKER-IIS-PTCOM1-3f9a-not-real'; $m2 = 'MARKER-WEB-PTCOM1-4b1c-not-real'; $m3 = 'MARKER-MOB-PTCOM1-5d2e-not-real'
$m4 = 'MARKER-IIS-PTCOM2-6e3f-not-real'; $m5 = 'MARKER-RULE-ONE-7f40-not-real'; $m6 = 'MARKER-RULE-TWO-8051-not-real'
$markers = @($m1, $m2, $m3, $m4, $m5, $m6)
function New-GoodSource {
    return [pscustomobject]@{
        Catalogue = @((New-Cat 'PTCOM1'), (New-Cat 'PTCOM2' $true $false $false), (New-Cat 'NOCRED' $false $false $false))
        Runtime   = @((New-Run 'PTCOM1' 'IIS_IDENTITY' $m1 3), (New-Run 'PTCOM1' 'WEB_ACCESS' $m2 1), (New-Run 'PTCOM1' 'MOBILE_APP_TOKEN' $m3 2), (New-Run 'PTCOM2' 'IIS_IDENTITY' $m4 1))
        RuleRows  = @{
            'cfg.ConfigRule'                = @((New-Rule 'RULE_ONE' 1 $m5), (New-Rule 'RULE_TWO' 1 ('Keystore-Password' + '=' + $m6)), (New-Rule 'PLAIN_RULE' 0 'not secret'), (New-Rule 'PLACEHOLDER' 1 'Password={Secret}'))
            'cfg.DatabaseObjectSettingRule' = @((New-Rule 'SET_PLAIN' 0 'x'))
            'cfg.DatabaseSettingRule'       = @()
        }
    }
}
function Get-Plan { param($Source) return (New-CredentialImportPlan -Catalogue $Source.Catalogue -Runtime $Source.Runtime -RuleRows $Source.RuleRows) }

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('sisqual-import-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$pass = 'correct horse battery staple 42'
try {
    # -----------------------------------------------------------------------
    # A. Rule secrets, and parity with the conversion tool
    # -----------------------------------------------------------------------
    function Get-Cands { param([string]$Tpl, $Sens = 1) return @(Get-RuleSecretCandidates -Table 'cfg.ConfigRule' -Rows @((New-Rule 'R1' $Sens $Tpl))) }
    Assert-That 'rule: a whole-value secret is the whole template' ((Get-Cands 'abcdefgh12345').Value -ceq 'abcdefgh12345')
    Assert-That 'rule: name=value keeps only the value (password, secret, token, key in the name)' (((Get-Cands 'Keystore-Password=Abc12345').Value -ceq 'Abc12345') -and ((Get-Cands 'client_secret=Zz999999').Value -ceq 'Zz999999') -and ((Get-Cands 'x.token=T0k3n123').Value -ceq 'T0k3n123') -and ((Get-Cands 'api_key=KEY12345').Value -ceq 'KEY12345'))
    Assert-That 'rule: the name match is case-insensitive' ((Get-Cands 'MyPASSWORDX=secretvalue1').Value -ceq 'secretvalue1')
    Assert-That 'rule: a value with a space is not name=value, so the whole template is the secret' ((Get-Cands 'token=a b').Value -ceq 'token=a b')
    Assert-That 'rule: a name without password, secret, token or key is a whole-value secret' ((Get-Cands 'x=y').Value -ceq 'x=y')
    $nameOnly = 'password' + '='
    Assert-That 'rule: name= with no value is a whole-value secret (as the conversion tool does)' ((Get-Cands $nameOnly).Value -ceq $nameOnly)
    foreach ($ph in @('Server={ServerName};Password=x', '{{secret:ref}}', 'a $(Var) b', 'a %VAR% b', 'a <name> b')) { Assert-That ('rule: a template with a placeholder is skipped: ' + $ph) (@(Get-Cands $ph).Count -eq 0) }
    Assert-That 'rule: a row that is not sensitive is skipped' (@(Get-Cands 'abcdefgh12345' 0).Count -eq 0)
    Assert-That 'rule: a null IsSensitive is skipped' (@(Get-Cands 'abcdefgh12345' $null).Count -eq 0)
    Assert-That 'rule: an empty or null template is skipped' ((@(Get-Cands '').Count -eq 0) -and (@(Get-Cands $null).Count -eq 0))
    Assert-That 'rule: the candidate carries the table and the code' ((@(Get-RuleSecretCandidates -Table 'cfg.ConfigRule' -Rows @((New-Rule 'ABC' 1 'abcdefgh1')))[0]).Table -ceq 'cfg.ConfigRule')

    $savedImport = $importPath
    . $convertPath -SyncFile 'unused' -OutputFolder 'unused' -Sqlite3Path 'unused'
    $importPath = $savedImport
    $battery = @('abcdefgh12345', 'Keystore-Password=Abc12345', 'api_key=KEY12345', 'token=a b', 'x=y', 'password=', 'MyPASSWORDX=secretvalue1', 'client_secret=Zz999999', 'Server={ServerName};Password=x', '{{secret:ref}}', 'a $(Var) b', 'a %VAR% b', 'a <name> b', '', 'plain text no secret here', 'a=b=c', 'Pwd=abc')
    $parityOk = $true; $parityChanged = 0
    foreach ($sens in @(1, 0, 2)) {
        foreach ($tpl in $battery) {
            $copy = [ordered]@{ RuleCode = 'PAR'; IsSensitive = $sens; ExpectedTemplate = $tpl }
            $changed = Protect-RuleRow -Row $copy -Spec @{ Template = 'ExpectedTemplate'; Id = 'RuleCode' }
            $cands = @(Get-RuleSecretCandidates -Table 'cfg.ConfigRule' -Rows @((New-Rule 'PAR' $sens $tpl)))
            if ([bool]$changed -ne ($cands.Count -eq 1)) { $parityOk = $false; Write-Host ('  parity differs on selection for [{0}] sens={1}' -f $tpl, $sens) }
            if ($changed) {
                $parityChanged++
                $token = '{{secret:RULE:PAR}}'
                $prefix = $copy['ExpectedTemplate'].Substring(0, $copy['ExpectedTemplate'].Length - $token.Length)
                if (-not $copy['ExpectedTemplate'].EndsWith($token) -or ($prefix + $cands[0].Value) -cne $tpl) { $parityOk = $false; Write-Host ('  parity differs on the value for [{0}]' -f $tpl) }
            }
        }
    }
    Assert-That ('parity: the selection and the secret value agree with Protect-RuleRow of the conversion tool ({0} redactions compared)' -f $parityChanged) ($parityOk -and $parityChanged -ge 8)
    $mineTables = & $importModule { $script:RuleTables }
    $samePortableTables = $true
    foreach ($k in $script:RedactionTables.Keys) {
        if (-not $mineTables.Contains($k) -or
            $mineTables[$k].Id -cne $script:RedactionTables[$k].Id -or
            $mineTables[$k].Template -cne $script:RedactionTables[$k].Template) {
            $samePortableTables = $false
        }
    }
    $legacyImportValidationOnly = ($mineTables.Contains('cfg.DatabaseSettingRule') -and
        -not $script:RedactionTables.Contains('cfg.DatabaseSettingRule') -and
        -not $script:CarriedTables.Contains('cfg.DatabaseSettingRule'))
    Assert-That 'parity: portable rule specs match; cfg.DatabaseSettingRule remains import/validation-only after cleanup' (((& $importModule { $script:PlaceholderPattern }) -ceq $script:PlaceholderPattern) -and $samePortableTables -and $legacyImportValidationOnly)

    # -----------------------------------------------------------------------
    # B. The plan
    # -----------------------------------------------------------------------
    $plan = Get-Plan (New-GoodSource)
    Assert-That 'plan: a good source is Ok with no failures' ($plan.Ok -and $plan.Failures.Count -eq 0)
    Assert-That 'plan: counts per kind, expected and read' ((($plan.Expected.Keys | ForEach-Object { $plan.Expected[$_] }) -join ',') -ceq '2,1,1,2' -and (($plan.Read.Keys | ForEach-Object { $plan.Read[$_] }) -join ',') -ceq '2,1,1,2')
    Assert-That 'plan: six entries with the right kind, code and source' (($plan.Entries.Count -eq 6) -and (@($plan.Entries | Where-Object { $_.Kind -ceq 'IIS_IDENTITY' -and $_.Code -ceq 'PTCOM1' -and $_.Source -ceq 'app.GetManagedCredentialRuntime#v3' }).Count -eq 1) -and (@($plan.Entries | Where-Object { $_.Kind -ceq 'RULE_SECRET' -and $_.Source -ceq 'cfg.ConfigRule' }).Count -eq 2))
    Assert-That 'plan: the secret bytes are the UTF-8 of the value; a name=value rule keeps only the value' (([System.Text.Encoding]::UTF8.GetString(@($plan.Entries | Where-Object { $_.Kind -ceq 'RULE_SECRET' -and $_.Code -ceq 'RULE_TWO' })[0].Bytes) -ceq $m6) -and ([System.Text.Encoding]::UTF8.GetString(@($plan.Entries | Where-Object { $_.Code -ceq 'PTCOM1' -and $_.Kind -ceq 'WEB_ACCESS' })[0].Bytes) -ceq $m2))
    Assert-That 'plan: an instance with no credential configured contributes nothing' (@($plan.Entries | Where-Object Code -ceq 'NOCRED').Count -eq 0)
    Assert-That 'plan: failures, counts and the entry list contain no marker except in the bytes' ((($plan | Select-Object Ok, Failures, Expected, Read | ConvertTo-Json -Depth 4) -cnotlike '*MARKER*'))

    function Test-PlanFails { param([string]$Name, [scriptblock]$Mutate, [string]$Expect)
        $s = New-GoodSource; & $Mutate $s; $p = Get-Plan $s
        Assert-That $Name ((-not $p.Ok) -and (@($p.Failures | Where-Object { $_ -clike $Expect }).Count -ge 1) -and (($p.Failures -join '|') -cnotlike '*MARKER*'))
    }
    Test-PlanFails 'plan: a null secret is NULL_SECRET with the reference' { param($s) $s.Runtime[1]['SecretValue'] = $null } 'NULL_SECRET:WEB_ACCESS.PTCOM1'
    Test-PlanFails 'plan: a DBNull secret is NULL_SECRET' { param($s) $s.Runtime[2]['SecretValue'] = [System.DBNull]::Value } 'NULL_SECRET:MOBILE_APP_TOKEN.PTCOM1'
    Test-PlanFails 'plan: an empty secret is NULL_SECRET' { param($s) $s.Runtime[0]['SecretValue'] = '' } 'NULL_SECRET:IIS_IDENTITY.PTCOM1'
    Test-PlanFails 'plan: a configured credential that was not returned is MISSING' { param($s) $s.Runtime = @($s.Runtime | Select-Object -SkipLast 1) } 'MISSING:IIS_IDENTITY.PTCOM2'
    Test-PlanFails 'plan: a returned credential that is not configured is UNEXPECTED' { param($s) $s.Runtime += (New-Run 'NOCRED' 'WEB_ACCESS' 'MARKER-X-not-real') } 'UNEXPECTED:WEB_ACCESS.NOCRED'
    Test-PlanFails 'plan: the same credential twice is DUPLICATE' { param($s) $s.Runtime += (New-Run 'PTCOM1' 'WEB_ACCESS' 'MARKER-Y-not-real') } 'DUPLICATE:WEB_ACCESS.PTCOM1'
    Test-PlanFails 'plan: an unknown credential type is TYPE' { param($s) $s.Runtime += (New-Run 'PTCOM1' 'SOMETHING_ELSE' 'MARKER-Z-not-real') } 'TYPE:SOMETHING_ELSE:PTCOM1'
    Test-PlanFails 'plan: a credential type in lower case is TYPE (exact match)' { param($s) $s.Runtime += (New-Run 'PTCOM1' 'web_access' 'MARKER-Z-not-real') } 'TYPE:web_access:PTCOM1'
    Test-PlanFails 'plan: an instance code in lower case is CODE' { param($s) $s.Catalogue += (New-Cat 'ptcom9') } 'CODE:ptcom9'
    Test-PlanFails 'plan: a duplicated instance in the catalogue is DUPLICATE_INSTANCE' { param($s) $s.Catalogue += (New-Cat 'PTCOM1') } 'DUPLICATE_INSTANCE:PTCOM1'
    Test-PlanFails 'plan: a rule code in lower case is CODE' { param($s) $s.RuleRows['cfg.ConfigRule'] += (New-Rule 'rule_lower' 1 'abcdefgh12345') } 'CODE:rule_lower'
    Test-PlanFails 'plan: the same rule code in two tables is RULE_CODE_COLLISION' { param($s) $s.RuleRows['cfg.DatabaseSettingRule'] += (New-Rule 'RULE_ONE' 1 'MARKER-OTHER-not-real') } 'RULE_CODE_COLLISION:RULE_ONE'
    $oddSource = New-GoodSource; $oddSource.Runtime += (New-Run "P`nTC" 'WEB_ACCESS' 'MARKER-Z-not-real')
    Assert-That 'plan: odd characters in a code are replaced by ? in the failure text (exact comparison; -like would treat ? as a wildcard)' ((Get-Plan $oddSource).Failures -ccontains 'UNEXPECTED:WEB_ACCESS.P?TC')
    $pCount = Get-Plan ([pscustomobject]@{ Catalogue = @(); Runtime = @(); RuleRows = @{} })
    Assert-That 'plan: an empty source is Ok with zero entries (a count check is the caller job)' ($pCount.Ok -and $pCount.Entries.Count -eq 0)
    Assert-That 'plan: a reference with a value over 255 characters is still imported (the vault allows 8192 bytes)' ((Get-Plan ([pscustomobject]@{ Catalogue = @((New-Cat 'A1' $true $false $false)); Runtime = @((New-Run 'A1' 'IIS_IDENTITY' ('x' * 300))); RuleRows = @{} })).Ok)

    # -----------------------------------------------------------------------
    # C. DryRun
    # -----------------------------------------------------------------------
    $dry = Invoke-CredentialImport -Plan $plan -Mode DryRun
    Assert-That 'dry run: needs no vault, reports Ok and the counts, saves nothing' ($dry.Ok -and -not $dry.Saved -and $dry.Mode -ceq 'DryRun')
    $badPlan = Get-Plan ((New-GoodSource) | ForEach-Object { $_.Runtime[0]['SecretValue'] = $null; $_ })
    Assert-That 'dry run: a bad plan is not Ok and lists the failure' ((-not (Invoke-CredentialImport -Plan $badPlan -Mode DryRun).Ok) -and (Invoke-CredentialImport -Plan $badPlan -Mode DryRun).Failures[0] -ceq 'NULL_SECRET:IIS_IDENTITY.PTCOM1')

    # -----------------------------------------------------------------------
    # D. Import: all or nothing, then Verify
    # -----------------------------------------------------------------------
    $vp = Join-Path $root 'v' 'vault.sisqual'
    $vault = New-CredentialVault -Path $vp -Passphrase (New-Pass $pass)
    Save-CredentialVault -Vault $vault
    $before = Get-Sha $vp
    $failed = Invoke-CredentialImport -Plan $badPlan -Mode Import -Vault $vault
    Assert-That 'import: a plan with a failure is refused, nothing is saved and the vault file is unchanged' ((-not $failed.Ok) -and -not $failed.Saved -and (Get-Sha $vp) -ceq $before -and @(Get-VaultSecretList -Vault $vault).Count -eq 0)
    $noVault = Invoke-CredentialImport -Plan $plan -Mode Import
    Assert-That 'import: without a vault it fails with VAULT_REQUIRED and writes nothing' ((-not $noVault.Ok) -and $noVault.Failures -ccontains 'IMPORT:VAULT_REQUIRED')
    $ok = Invoke-CredentialImport -Plan $plan -Mode Import -Vault $vault
    Assert-That 'import: all six entries are added, saved, and every fingerprint matches' ($ok.Ok -and $ok.Saved -and $ok.Matched -eq 6 -and (($ok.InVault.Keys | ForEach-Object { $ok.InVault[$_] }) -join ',') -ceq '2,1,1,2')
    Assert-That 'import: the vault holds the values and the sources' (([System.Text.Encoding]::UTF8.GetString((Get-VaultSecretValue -Vault $vault -CredentialRef 'WEB_ACCESS.PTCOM1')) -ceq $m2) -and (@(Get-VaultSecretList -Vault $vault | Where-Object { $_.Source -ceq 'cfg.ConfigRule' }).Count -eq 2))
    Close-CredentialVault -Vault $vault
    $reopened = Open-CredentialVault -Path $vp -Passphrase (New-Pass $pass)
    Assert-That 'import: after closing and reopening the six secrets are there' (@(Get-VaultSecretList -Vault $reopened).Count -eq 6)
    $filebytes = [IO.File]::ReadAllText($vp)
    Assert-That 'import: no marker, in plain, appears in the vault file' (-not (@($markers | Where-Object { $filebytes -clike ('*' + $_ + '*') }).Count))
    $afterFirst = Get-Sha $vp
    $again = Invoke-CredentialImport -Plan (Get-Plan (New-GoodSource)) -Mode Import -Vault $reopened
    Assert-That 'import: a second import without -Replace is refused at the first existing reference (one SECRET_EXISTS failure) and nothing is saved' ((-not $again.Ok) -and -not $again.Saved -and @($again.Failures).Count -eq 1 -and ($again.Failures[0] -clike 'VAULT:SECRET_EXISTS:*') -and (Get-Sha $vp) -ceq $afterFirst)
    $withReplace = Invoke-CredentialImport -Plan (Get-Plan (New-GoodSource)) -Mode Import -Vault $reopened -Replace
    Assert-That 'import: with -Replace a refresh succeeds and the fingerprints still match' ($withReplace.Ok -and $withReplace.Saved -and $withReplace.Matched -eq 6)

    $verify = Invoke-CredentialImport -Plan (Get-Plan (New-GoodSource)) -Mode Verify -Vault $reopened
    Assert-That 'verify: an unchanged source matches all six and saves nothing' ($verify.Ok -and $verify.Matched -eq 6 -and -not $verify.Saved)
    $changedSource = New-GoodSource; $changedSource.Runtime[1]['SecretValue'] = 'MARKER-ROTATED-not-real'
    $vChanged = Invoke-CredentialImport -Plan (Get-Plan $changedSource) -Mode Verify -Vault $reopened
    Assert-That 'verify: a rotated value is MISMATCH with the reference and no value' ((-not $vChanged.Ok) -and ($vChanged.Failures -ccontains 'MISMATCH:WEB_ACCESS.PTCOM1') -and $vChanged.Matched -eq 5 -and (($vChanged.Failures -join '|') -cnotlike '*MARKER*'))
    $extraSource = New-GoodSource; $extraSource.Catalogue += (New-Cat 'PTCOM3' $true $false $false); $extraSource.Runtime += (New-Run 'PTCOM3' 'IIS_IDENTITY' 'MARKER-NEW-not-real')
    $vExtra = Invoke-CredentialImport -Plan (Get-Plan $extraSource) -Mode Verify -Vault $reopened
    Assert-That 'verify: a credential that is in the source but not in the vault is NOT_IN_VAULT' ((-not $vExtra.Ok) -and ($vExtra.Failures -ccontains 'NOT_IN_VAULT:IIS_IDENTITY.PTCOM3'))
    $fewer = New-GoodSource; $fewer.Catalogue = @($fewer.Catalogue | Select-Object -First 1); $fewer.Runtime = @($fewer.Runtime | Select-Object -First 3)
    $vFewer = Invoke-CredentialImport -Plan (Get-Plan $fewer) -Mode Verify -Vault $reopened
    Assert-That 'verify: vault entries that the source no longer has are counted as Extra and are not a failure' ($vFewer.Ok -and $vFewer.Extra -ge 1)
    $vBad = Invoke-CredentialImport -Plan $badPlan -Mode Verify -Vault $reopened
    Assert-That 'verify: a bad plan is not Ok' (-not $vBad.Ok)

    # -----------------------------------------------------------------------
    # E. Report, hygiene and clearing
    # -----------------------------------------------------------------------
    $report = Format-ImportReport -Result $ok
    Assert-That 'report: counts per kind, a total and the result, with no value' (($report -clike '*IIS_IDENTITY*') -and ($report -clike '*Total*') -and ($report -clike '*Result: OK*') -and -not (@($markers | Where-Object { $report -clike ('*' + $_ + '*') }).Count))
    $reportBad = Format-ImportReport -Result $vChanged
    Assert-That 'report: a failure appears with its code and reference, never a value' (($reportBad -clike '*FAILURE MISMATCH:WEB_ACCESS.PTCOM1*') -and ($reportBad -clike '*Result: FAILED*') -and ($reportBad -cnotlike '*MARKER*'))
    $streams = @((Invoke-CredentialImport -Plan (Get-Plan (New-GoodSource)) -Mode Verify -Vault $reopened) *>&1 | Out-String)
    Assert-That 'hygiene: nothing in any stream carries a marker or the passphrase' (($streams -cnotlike '*MARKER*') -and ($streams -cnotlike ('*' + $pass + '*')))
    $clearPlan = Get-Plan (New-GoodSource)
    $firstBytes = $clearPlan.Entries[0].Bytes
    Clear-ImportPlan -Plan $clearPlan
    Assert-That 'clearing: the plan bytes are zeroed' (@($firstBytes | Where-Object { $_ -ne 0 }).Count -eq 0)
    Close-CredentialVault -Vault $reopened
}
finally {
    Remove-Module Sisqual.CredentialImport -ErrorAction SilentlyContinue
    Remove-Module Sisqual.CredentialVault -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ''
Write-Host ('Passed: {0}  Failed: {1}' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
