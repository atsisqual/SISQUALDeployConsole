#requires -Version 7.0
<#
.SYNOPSIS
    The one-time import of the existing credentials into the vault (step B6.3b). Tool only.

.DESCRIPTION
    Plan 4.2 of docs/migration/catalog-conversion-plan.md. Three layers:
      - the PURE core: rule secret extraction (the same rule as Protect-RuleRow of Convert-ManagementDb.ps1, kept in
        step by a parity test), the plan (validation of every row read), and the three modes DryRun, Import (all or
        nothing) and Verify. No SQL here.
      - the reader: Read-LiveCredentialSource, a read-only connection that uses ONLY the existing read path:
        app.GetManagedCredentialCatalogue (instances and which credentials are configured, no secrets, no table
        permission needed), app.GetManagedCredentialRuntime (one instance at a time, decrypted through the
        certificate) and the three rule tables.
      - the report: counts per kind, failure codes with references, never a value.

    A failure is a plain string such as NULL_SECRET:WEB_ACCESS.PTCOM1. References and codes are sanitised, and a value
    is never part of a failure, a count or a report. Plaintext values exist only as byte arrays inside the plan and
    are cleared when the run ends.
#>
Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'Sisqual.CredentialVault.psm1')

# Same patterns as tools/Convert-ManagementDb.ps1 (parity test in tests/Unit/Test-CredentialImportCore.ps1).
$script:PlaceholderPattern = '\{[A-Za-z_][\w.]*\}|\{\{|\$\(|%[A-Za-z_]+%|<[A-Za-z_]+>'
$script:RulePrefixPattern = '^(?i)([A-Za-z][A-Za-z0-9._-]*(?:password|secret|token|key)[A-Za-z0-9._-]*=)\S+$'
$script:RuleTables = [ordered]@{
    'cfg.ConfigRule'                = @{ Template = 'ExpectedTemplate'; Id = 'RuleCode' }
    'cfg.DatabaseObjectSettingRule' = @{ Template = 'ExpectedTemplate'; Id = 'SettingCode' }
    'cfg.DatabaseSettingRule'       = @{ Template = 'ExpectedTemplate'; Id = 'SettingCode' }
}
$script:InstanceKinds = [ordered]@{ IisIdentityConfigured = 'IIS_IDENTITY'; WebAccessConfigured = 'WEB_ACCESS'; MobileAppTokenConfigured = 'MOBILE_APP_TOKEN' }

function ConvertTo-SafeText {
    # Anything that ends up in a failure or a report is reduced to a short, harmless set of characters.
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    $clean = [regex]::Replace($Text, '[^A-Za-z0-9_.:-]', '?')
    if ($clean.Length -gt 60) { $clean = $clean.Substring(0, 60) }
    return $clean
}

function ConvertTo-Flag {
    param($Value)
    if ($null -eq $Value -or $Value -is [System.DBNull]) { return $false }
    return ([int]$Value -ne 0)
}

function Get-RuleSecretCandidates {
    # The literal secrets of the rule rows, selected exactly as Protect-RuleRow of the conversion tool selects them.
    # Each row is a dictionary with Id, IsSensitive and Template.
    param([Parameter(Mandatory)][string]$Table, [AllowEmptyCollection()][object[]]$Rows = @())
    $found = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $Rows) {
        if (-not (ConvertTo-Flag $row['IsSensitive'])) { continue }
        if ([int]$row['IsSensitive'] -ne 1) { continue }
        $template = [string]$row['Template']
        if ([string]::IsNullOrEmpty($template)) { continue }
        if ([regex]::IsMatch($template, $script:PlaceholderPattern)) { continue }
        $m = [regex]::Match($template, $script:RulePrefixPattern)
        $value = $template
        if ($m.Success) { $value = $template.Substring($m.Groups[1].Length) }
        $found.Add([pscustomobject]@{ Table = $Table; Code = [string]$row['Id']; Value = $value })
    }
    # A flat array: callers wrap the call in @() (a comma here would give them an array holding an array).
    return $found.ToArray()
}

function New-CredentialImportPlan {
    # Validates everything that was read. Entries carry the values; Failures and Counts never do.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Catalogue,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Runtime,
        [hashtable]$RuleRows = @{}
    )
    $failures = [System.Collections.Generic.List[string]]::new()
    $entries = [System.Collections.Generic.List[object]]::new()
    $expected = [ordered]@{ IIS_IDENTITY = 0; WEB_ACCESS = 0; MOBILE_APP_TOKEN = 0; RULE_SECRET = 0 }
    $wanted = [System.Collections.Generic.List[object]]::new()
    $seenInstances = @{}
    foreach ($c in $Catalogue) {
        $code = [string]$c['InstanceCode']
        if ($code -cnotmatch '^[A-Z0-9_-]{1,60}$') { $failures.Add('CODE:' + (ConvertTo-SafeText $code)); continue }
        if ($seenInstances.ContainsKey($code)) { $failures.Add('DUPLICATE_INSTANCE:' + $code); continue }
        $seenInstances[$code] = $true
        foreach ($bit in $script:InstanceKinds.Keys) {
            if (ConvertTo-Flag $c[$bit]) { $kind = $script:InstanceKinds[$bit]; $expected[$kind]++; $wanted.Add([pscustomobject]@{ Kind = $kind; Code = $code }) }
        }
    }
    $index = @{}
    foreach ($r in $Runtime) {
        $type = [string]$r['CredentialType']
        $code = [string]$r['InstanceCode']
        if ($type -cnotin @('IIS_IDENTITY', 'WEB_ACCESS', 'MOBILE_APP_TOKEN')) { $failures.Add('TYPE:' + (ConvertTo-SafeText $type) + ':' + (ConvertTo-SafeText $code)); continue }
        $key = $type + '.' + $code
        if ($index.ContainsKey($key)) { $failures.Add('DUPLICATE:' + (ConvertTo-SafeText $key)); continue }
        $index[$key] = $r
    }
    $used = @{}
    foreach ($w in $wanted) {
        $key = $w.Kind + '.' + $w.Code
        if (-not $index.ContainsKey($key)) { $failures.Add('MISSING:' + $key); continue }
        $used[$key] = $true
        $r = $index[$key]
        $secret = $r['SecretValue']
        if ($null -eq $secret -or $secret -is [System.DBNull] -or [string]::IsNullOrEmpty([string]$secret)) { $failures.Add('NULL_SECRET:' + $key); continue }
        $version = [string]$r['SecretVersion']
        if ($version -cnotmatch '^\d{1,9}$') { $version = '0' }
        $entries.Add([pscustomobject]@{ Kind = $w.Kind; Code = $w.Code; Bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$secret); Source = ('app.GetManagedCredentialRuntime#v' + $version) })
    }
    foreach ($key in $index.Keys) { if (-not $used.ContainsKey($key)) { $failures.Add('UNEXPECTED:' + (ConvertTo-SafeText $key)) } }
    $ruleCodes = @{}
    foreach ($table in $script:RuleTables.Keys) {
        if (-not $RuleRows.ContainsKey($table)) { continue }
        foreach ($cand in @(Get-RuleSecretCandidates -Table $table -Rows @($RuleRows[$table]))) {
            $expected['RULE_SECRET']++
            if ($cand.Code -cnotmatch '^[A-Z0-9_-]{1,60}$') { $failures.Add('CODE:' + (ConvertTo-SafeText $cand.Code)); continue }
            if ($ruleCodes.ContainsKey($cand.Code)) { $failures.Add('RULE_CODE_COLLISION:' + $cand.Code); continue }
            $ruleCodes[$cand.Code] = $true
            if ([string]::IsNullOrEmpty($cand.Value)) { $failures.Add('NULL_SECRET:RULE_SECRET.' + $cand.Code); continue }
            $entries.Add([pscustomobject]@{ Kind = 'RULE_SECRET'; Code = $cand.Code; Bytes = [System.Text.Encoding]::UTF8.GetBytes($cand.Value); Source = $table })
        }
    }
    $read = [ordered]@{ IIS_IDENTITY = 0; WEB_ACCESS = 0; MOBILE_APP_TOKEN = 0; RULE_SECRET = 0 }
    foreach ($e in $entries) { $read[$e.Kind]++ }
    return [pscustomobject]@{ Ok = ($failures.Count -eq 0); Failures = $failures.ToArray(); Expected = $expected; Read = $read; Entries = $entries.ToArray() }
}

function Clear-ImportPlan {
    param($Plan)
    foreach ($e in @($Plan.Entries)) { if ($null -ne $e.Bytes) { [Array]::Clear($e.Bytes, 0, $e.Bytes.Length) } }
}

function Invoke-CredentialImport {
    # DryRun reports. Import is ALL OR NOTHING: any failure in the plan or in the vault stops before anything is saved.
    # Verify compares a fresh read with the salted fingerprints in the vault. A value is never part of the result.
    param(
        [Parameter(Mandatory)]$Plan,
        [ValidateSet('DryRun', 'Import', 'Verify')][string]$Mode = 'DryRun',
        $Vault,
        [switch]$Replace
    )
    $failures = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $Plan.Failures) { $failures.Add($f) }
    $result = [ordered]@{ Mode = $Mode; Ok = $false; Expected = $Plan.Expected; Read = $Plan.Read; InVault = [ordered]@{ IIS_IDENTITY = 0; WEB_ACCESS = 0; MOBILE_APP_TOKEN = 0; RULE_SECRET = 0 }; Matched = 0; Extra = 0; Saved = $false; Failures = @() }
    try {
        if ($Mode -eq 'DryRun') { $result.Failures = $failures.ToArray(); $result.Ok = ($failures.Count -eq 0); return [pscustomobject]$result }
        if ($null -eq $Vault) { throw 'VAULT_REQUIRED' }
        if ($Mode -eq 'Import') {
            if ($failures.Count -eq 0) {
                foreach ($e in $Plan.Entries) {
                    try { [void](Add-VaultSecret -Vault $Vault -Kind $e.Kind -Code $e.Code -Value $e.Bytes -Source $e.Source -Replace:$Replace) }
                    catch { $failures.Add(('VAULT:{0}:{1}.{2}' -f (ConvertTo-SafeText ([string]$_.Exception.Message)), $e.Kind, $e.Code)); break }
                }
            }
            if ($failures.Count -eq 0) {
                Save-CredentialVault -Vault $Vault
                $result.Saved = $true
            }
        }
        if ($Mode -eq 'Verify' -or ($Mode -eq 'Import' -and $result.Saved)) {
            foreach ($e in $Plan.Entries) {
                $ref = $e.Kind + '.' + $e.Code
                try {
                    if (Test-VaultSecretFingerprint -Vault $Vault -CredentialRef $ref -Value $e.Bytes) { $result.Matched++ }
                    else { $failures.Add('MISMATCH:' + $ref) }
                }
                catch { $failures.Add('NOT_IN_VAULT:' + $ref) }
            }
            $planned = @{}
            foreach ($e in $Plan.Entries) { $planned[$e.Kind + '.' + $e.Code] = $true }
            foreach ($s in (Get-VaultSecretList -Vault $Vault)) {
                if ($s.Kind -in @($result.InVault.Keys)) { $result.InVault[$s.Kind]++ }
                if (-not $planned.ContainsKey($s.CredentialRef)) { $result.Extra++ }
            }
        }
    }
    catch {
        $code = [string]$_.Exception.Message
        if ($code -cnotmatch '^[A-Z][A-Z0-9_]{2,40}$') { $code = 'UNEXPECTED' }
        $failures.Add('IMPORT:' + $code)
    }
    $result.Failures = $failures.ToArray()
    $result.Ok = ($failures.Count -eq 0)
    return [pscustomobject]$result
}

function Format-ImportReport {
    # Counts and codes only. Safe to print and to keep in a log.
    param([Parameter(Mandatory)]$Result)
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add(('Mode: {0}' -f $Result.Mode))
    $lines.Add(('{0,-18} {1,9} {2,6} {3,9}' -f 'Kind', 'Expected', 'Read', 'In vault'))
    $te = 0; $tr = 0; $tv = 0
    foreach ($k in $Result.Expected.Keys) {
        $lines.Add(('{0,-18} {1,9} {2,6} {3,9}' -f $k, $Result.Expected[$k], $Result.Read[$k], $Result.InVault[$k]))
        $te += $Result.Expected[$k]; $tr += $Result.Read[$k]; $tv += $Result.InVault[$k]
    }
    $lines.Add(('{0,-18} {1,9} {2,6} {3,9}' -f 'Total', $te, $tr, $tv))
    if ($Result.Mode -ne 'DryRun') { $lines.Add(('Fingerprints matched: {0}; vault entries outside this read: {1}; saved: {2}' -f $Result.Matched, $Result.Extra, $Result.Saved)) }
    foreach ($f in $Result.Failures) { $lines.Add('FAILURE ' + $f) }
    $lines.Add(('Result: {0}' -f $(if ($Result.Ok) { 'OK' } else { 'FAILED' })))
    return ($lines -join "`n")
}

# ---------------------------------------------------------------------------
# The reader: read-only, through the existing read path only
# ---------------------------------------------------------------------------

function Read-LiveCredentialSource {
    param(
        [Parameter(Mandatory)][string]$SqlInstance,
        [Parameter(Mandatory)][string]$Database,
        [Parameter(Mandatory)][string]$SqlClientPath,
        [switch]$TrustServerCertificate
    )
    $dll = $SqlClientPath
    if (Test-Path -LiteralPath $SqlClientPath -PathType Container) { $dll = Join-Path $SqlClientPath 'Microsoft.Data.SqlClient.dll' }
    if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { throw 'SQLCLIENT_MISSING' }
    if (-not ('Microsoft.Data.SqlClient.SqlConnection' -as [type])) { Add-Type -Path $dll }
    $builder = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $SqlInstance
    $builder['Initial Catalog'] = $Database
    $builder['Integrated Security'] = $true
    $builder['Application Intent'] = [Microsoft.Data.SqlClient.ApplicationIntent]::ReadOnly
    $builder['Application Name'] = 'Import-CredentialsToVault'
    $builder['Connect Timeout'] = 30
    if ($TrustServerCertificate) { $builder['Trust Server Certificate'] = $true }
    $catalogue = [System.Collections.Generic.List[object]]::new()
    $runtime = [System.Collections.Generic.List[object]]::new()
    $ruleRows = @{}
    $connection = [Microsoft.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    try {
        try {
            $connection.Open()
            $cmd = $connection.CreateCommand()
            $cmd.CommandType = [System.Data.CommandType]::StoredProcedure
            $cmd.CommandText = 'app.GetManagedCredentialCatalogue'
            $cmd.CommandTimeout = 120
            $reader = $cmd.ExecuteReader()
            try {
                $ordinals = @{}
                foreach ($n in @('InstanceCode', 'IisIdentityConfigured', 'WebAccessConfigured', 'MobileAppTokenConfigured')) { $ordinals[$n] = $reader.GetOrdinal($n) }
                while ($reader.Read()) {
                    $row = [ordered]@{ InstanceCode = [string]$reader.GetValue($ordinals['InstanceCode']) }
                    foreach ($n in @('IisIdentityConfigured', 'WebAccessConfigured', 'MobileAppTokenConfigured')) {
                        $v = $reader.GetValue($ordinals[$n])
                        $row[$n] = $false
                        if ($v -isnot [System.DBNull]) { $row[$n] = [bool]$v }
                    }
                    $catalogue.Add($row)
                }
            }
            finally { $reader.Dispose() }
            foreach ($c in $catalogue) {
                if (-not ($c['IisIdentityConfigured'] -or $c['WebAccessConfigured'] -or $c['MobileAppTokenConfigured'])) { continue }
                $rc = $connection.CreateCommand()
                $rc.CommandType = [System.Data.CommandType]::StoredProcedure
                $rc.CommandText = 'app.GetManagedCredentialRuntime'
                $rc.CommandTimeout = 120
                $p = [Microsoft.Data.SqlClient.SqlParameter]::new('@InstanceCode', [System.Data.SqlDbType]::VarChar, 20)
                $p.Value = [string]$c['InstanceCode']
                [void]$rc.Parameters.Add($p)
                $rr = $rc.ExecuteReader()
                try {
                    $oType = $rr.GetOrdinal('CredentialType'); $oInst = $rr.GetOrdinal('InstanceCode'); $oSecret = $rr.GetOrdinal('SecretValue'); $oVer = $rr.GetOrdinal('SecretVersion')
                    while ($rr.Read()) {
                        $secret = $null
                        if (-not $rr.IsDBNull($oSecret)) { $secret = [string]$rr.GetValue($oSecret) }
                        $runtime.Add([ordered]@{ InstanceCode = [string]$rr.GetValue($oInst); CredentialType = [string]$rr.GetValue($oType); SecretValue = $secret; SecretVersion = [int]$rr.GetValue($oVer) })
                    }
                }
                finally { $rr.Dispose() }
            }
            foreach ($table in $script:RuleTables.Keys) {
                $spec = $script:RuleTables[$table]
                $parts = $table.Split('.')
                $qc = $connection.CreateCommand()
                $qc.CommandTimeout = 120
                $qc.CommandText = 'SELECT [{0}], [IsSensitive], [{1}] FROM [{2}].[{3}];' -f $spec.Id, $spec.Template, $parts[0], $parts[1]
                $qr = $qc.ExecuteReader()
                $list = [System.Collections.Generic.List[object]]::new()
                try {
                    while ($qr.Read()) {
                        $sens = 0
                        if (-not $qr.IsDBNull(1)) { $sens = [int]$qr.GetValue(1) }
                        $tpl = $null
                        if (-not $qr.IsDBNull(2)) { $tpl = [string]$qr.GetValue(2) }
                        $list.Add([ordered]@{ Id = [string]$qr.GetValue(0); IsSensitive = $sens; Template = $tpl })
                    }
                }
                finally { $qr.Dispose() }
                $ruleRows[$table] = $list.ToArray()
            }
        }
        catch [Microsoft.Data.SqlClient.SqlException] { throw ('SOURCE_READ_FAILED_SQL_' + [string]$_.Exception.Number) }
        catch {
            $m = [string]$_.Exception.Message
            if ($m -cmatch '^[A-Z][A-Z0-9_]{2,40}$') { throw $m }
            throw 'SOURCE_READ_FAILED'
        }
    }
    finally { $connection.Dispose() }
    return [pscustomobject]@{ Catalogue = $catalogue.ToArray(); Runtime = $runtime.ToArray(); RuleRows = $ruleRows }
}

Export-ModuleMember -Function @(
    'Get-RuleSecretCandidates', 'New-CredentialImportPlan', 'Clear-ImportPlan', 'Invoke-CredentialImport', 'Format-ImportReport', 'Read-LiveCredentialSource'
)
