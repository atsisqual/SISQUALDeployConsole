#requires -Version 7.0
<#
.SYNOPSIS
    Integration test of the credential import against a real SQL Server engine (LocalDB on the CI runner), step B6.3b.

.DESCRIPTION
    Builds a small database with the REAL objects of the read path: a master key, a certificate and a symmetric key with
    the production names, sec.ManagedCredential, and the text of app.GetManagedCredentialRuntime and
    app.GetManagedCredentialCatalogue as they are in the reference system (both WITH EXECUTE AS OWNER, decrypting through
    DecryptByKeyAutoCert with the authenticator InstanceCode|CredentialType). Test credentials are encrypted with that key.
    It then checks the reader, the plan, the three modes against a real vault and the script run as a child process,
    including a rotated value, a credential that cannot be decrypted, an orphan credential and a wrong database.
    Marker values stand in for secrets. Exits 1 on any failure and 2 when the SQL client is not given.
#>
param(
    [string]$SqlInstance = '(localdb)\MSSQLLocalDB',
    [string]$SqlClientPath,
    [switch]$KeepDatabase
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SqlClientPath)) { Write-Host '-SqlClientPath is required.'; exit 2 }
$dll = Join-Path $SqlClientPath 'Microsoft.Data.SqlClient.dll'
if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { Write-Host ('Microsoft.Data.SqlClient.dll not found in ' + $SqlClientPath); exit 2 }
Add-Type -Path $dll

$repoTools = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools')).Path
$importScript = Join-Path $repoTools 'Import-CredentialsToVault.ps1'
Import-Module (Join-Path $repoTools 'lib' 'Sisqual.CredentialVault.psm1') -Force
Import-Module (Join-Path $repoTools 'lib' 'Sisqual.CredentialImport.psm1') -Force
$pwshPath = (Get-Process -Id $PID).Path
$savedClientPath = $SqlClientPath
$savedInstance = $SqlInstance

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

function Get-Connection {
    param([string]$Database)
    $b = [Microsoft.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $b['Data Source'] = $SqlInstance
    $b['Initial Catalog'] = $Database
    $b['Integrated Security'] = $true
    $b['Trust Server Certificate'] = $true
    $b['Connect Timeout'] = 30
    $c = [Microsoft.Data.SqlClient.SqlConnection]::new($b.ConnectionString)
    $c.Open()
    return $c
}
function Invoke-NonQuery { param($Connection, [string]$Sql) $cmd = $Connection.CreateCommand(); $cmd.CommandText = $Sql; $cmd.CommandTimeout = 120; [void]$cmd.ExecuteNonQuery() }
function Invoke-Scalar { param($Connection, [string]$Sql) $cmd = $Connection.CreateCommand(); $cmd.CommandText = $Sql; return $cmd.ExecuteScalar() }
function Set-TestCredential {
    param($Connection, [string]$Instance, [string]$Type, [string]$Value, [int]$Version = 1)
    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = @'
OPEN SYMMETRIC KEY SISQUAL_ManagedCredential_Key DECRYPTION BY CERTIFICATE SISQUAL_ManagedCredential_Certificate;
DELETE FROM sec.ManagedCredential WHERE InstanceCode = @i AND CredentialType = @t;
INSERT INTO sec.ManagedCredential (InstanceCode, CredentialType, SecretCipher, SecretVersion, LastRotatedAt, ModifiedBy, ModifiedAt)
VALUES (@i, @t, ENCRYPTBYKEY(KEY_GUID(N'SISQUAL_ManagedCredential_Key'), CONVERT(nvarchar(255), @v), 1, CONVERT(varbinary(256), @i + N'|' + @t)), @ver, SYSUTCDATETIME(), N'test', SYSUTCDATETIME());
CLOSE SYMMETRIC KEY SISQUAL_ManagedCredential_Key;
'@
    $p1 = [Microsoft.Data.SqlClient.SqlParameter]::new('@i', [System.Data.SqlDbType]::VarChar, 20); $p1.Value = $Instance; [void]$cmd.Parameters.Add($p1)
    $p2 = [Microsoft.Data.SqlClient.SqlParameter]::new('@t', [System.Data.SqlDbType]::VarChar, 30); $p2.Value = $Type; [void]$cmd.Parameters.Add($p2)
    $p3 = [Microsoft.Data.SqlClient.SqlParameter]::new('@v', [System.Data.SqlDbType]::NVarChar, 255); $p3.Value = $Value; [void]$cmd.Parameters.Add($p3)
    $p4 = [Microsoft.Data.SqlClient.SqlParameter]::new('@ver', [System.Data.SqlDbType]::Int); $p4.Value = $Version; [void]$cmd.Parameters.Add($p4)
    [void]$cmd.ExecuteNonQuery()
}
function Invoke-Tool {
    param([string[]]$Arguments, [hashtable]$Env = @{})
    $psi = [System.Diagnostics.ProcessStartInfo]::new($pwshPath)
    foreach ($a in @('-NoLogo', '-NoProfile', '-File', $importScript) + $Arguments) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.RedirectStandardInput = $true; $psi.UseShellExecute = $false
    foreach ($name in @($psi.Environment.Keys | Where-Object { $_ -like 'SISQUAL_*' })) { [void]$psi.Environment.Remove($name) }
    foreach ($k in $Env.Keys) { $psi.Environment[$k] = [string]$Env[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(240000)) { $p.Kill($true); return [pscustomobject]@{ Exit = -1; Out = 'TIMEOUT'; Err = 'TIMEOUT' } }
    return [pscustomobject]@{ Exit = $p.ExitCode; Out = $out.Result; Err = $err.Result }
}

$vIis1 = 'MARKER-IIS-PTCOM1-aa11-not-real'; $vWeb1 = 'MARKER-WEB-PTCOM1-bb22-not-real'; $vMob1 = 'MARKER-MOB-PTCOM1-cc33-not-real'
$vIis2 = 'MARKER-IIS-PTCOM2-dd44-not-real'; $vGhost = 'MARKER-WEB-GHOST-ee55-not-real'
$vRule1 = 'MARKER-RULE-ONE-ff66-not-real'; $vRule2 = 'MARKER-RULE-TWO-0077-not-real'; $vRule3 = 'MARKER-RULE-THREE-1188-not-real'
$markers = @($vIis1, $vWeb1, $vMob1, $vIis2, $vGhost, $vRule1, $vRule2, $vRule3, 'MARKER-ROTATED-2299-not-real')
$passphraseText = 'correct horse battery staple 42'
$dbName = 'SisqualCredImport_' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$dbCreated = $false
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('sisqual-credimport-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)

$runtimeProc = @'
CREATE OR ALTER PROCEDURE app.GetManagedCredentialRuntime @InstanceCode varchar(20),@CredentialType varchar(30)=NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;SET @CredentialType=NULLIF(UPPER(LTRIM(RTRIM(@CredentialType))),N'');
    SELECT C.InstanceCode,C.CredentialType,
           UserName=CASE C.CredentialType WHEN 'IIS_IDENTITY' THEN I.IisIdentityUserName WHEN 'WEB_ACCESS' THEN I.WebAccessUserName END,
           SecretValue=CONVERT(nvarchar(255),DecryptByKeyAutoCert(CERT_ID(N'SISQUAL_ManagedCredential_Certificate'),NULL,C.SecretCipher,1,CONVERT(varbinary(256),C.InstanceCode+N'|'+C.CredentialType))),
           C.SecretVersion,C.LastRotatedAt
    FROM sec.ManagedCredential AS C INNER JOIN dbo.ManagedInstance AS I ON I.InstanceCode=C.InstanceCode
    WHERE C.InstanceCode=@InstanceCode AND(@CredentialType IS NULL OR C.CredentialType=@CredentialType)
    ORDER BY C.CredentialType;
END;
'@
$catalogueProc = @'
CREATE OR ALTER PROCEDURE app.GetManagedCredentialCatalogue @MachineName sysname=NULL
WITH EXECUTE AS OWNER
AS
BEGIN
    SET NOCOUNT ON;
    SELECT I.InstanceCode,I.ServerCode,I.CountryCode,I.CustomerName,I.HostName,I.IsEnabled,I.IisIdentityUserName,
           IisIdentityConfigured=CONVERT(bit,CASE WHEN X.InstanceCode IS NULL THEN 0 ELSE 1 END),IisIdentityRotatedAt=X.LastRotatedAt,
           I.WebAccessUserName,WebAccessConfigured=CONVERT(bit,CASE WHEN W.InstanceCode IS NULL THEN 0 ELSE 1 END),WebAccessRotatedAt=W.LastRotatedAt,
           MobileAppTokenConfigured=CONVERT(bit,CASE WHEN M.InstanceCode IS NULL THEN 0 ELSE 1 END),MobileAppTokenRotatedAt=M.LastRotatedAt,
           LastCredentialChange=(SELECT MAX(V.RotatedAt) FROM(VALUES(X.LastRotatedAt),(W.LastRotatedAt),(M.LastRotatedAt)) AS V(RotatedAt))
    FROM dbo.ManagedInstance AS I INNER JOIN dbo.ManagedServer AS S ON S.ServerCode=I.ServerCode
    LEFT JOIN sec.ManagedCredential AS X ON X.InstanceCode=I.InstanceCode AND X.CredentialType='IIS_IDENTITY'
    LEFT JOIN sec.ManagedCredential AS W ON W.InstanceCode=I.InstanceCode AND W.CredentialType='WEB_ACCESS'
    LEFT JOIN sec.ManagedCredential AS M ON M.InstanceCode=I.InstanceCode AND M.CredentialType='MOBILE_APP_TOKEN'
    WHERE @MachineName IS NULL OR S.MachineName=@MachineName
    ORDER BY I.IsEnabled DESC,I.CountryCode,I.InstanceCode;
END;
'@

try {
    $master = Get-Connection -Database 'master'
    try { Invoke-NonQuery $master ('CREATE DATABASE [{0}] COLLATE Latin1_General_CI_AS;' -f $dbName); $dbCreated = $true } finally { $master.Dispose() }
    $c = Get-Connection -Database $dbName
    try {
        foreach ($s in @('app', 'cfg', 'sec')) { Invoke-NonQuery $c ('CREATE SCHEMA [{0}];' -f $s) }
        Invoke-NonQuery $c 'CREATE TABLE dbo.ManagedServer (ServerCode varchar(20) NOT NULL PRIMARY KEY, MachineName sysname NOT NULL);'
        Invoke-NonQuery $c 'CREATE TABLE dbo.ManagedInstance (InstanceCode varchar(20) NOT NULL PRIMARY KEY, ServerCode varchar(20) NOT NULL, CountryCode varchar(5) NOT NULL, CustomerName nvarchar(100) NOT NULL, HostName varchar(100) NOT NULL, IsEnabled bit NOT NULL, IisIdentityUserName nvarchar(100) NULL, WebAccessUserName nvarchar(100) NULL);'
        Invoke-NonQuery $c 'CREATE TABLE sec.ManagedCredential (InstanceCode varchar(20) NOT NULL, CredentialType varchar(30) NOT NULL, SecretCipher varbinary(max) NOT NULL, SecretVersion int NOT NULL, LastRotatedAt datetime2 NOT NULL, ModifiedBy nvarchar(256) NOT NULL, ModifiedAt datetime2 NOT NULL, RowVersion timestamp NOT NULL, CONSTRAINT PK_ManagedCredential_sync PRIMARY KEY (InstanceCode, CredentialType));'
        Invoke-NonQuery $c 'CREATE TABLE cfg.ConfigRule (RuleCode varchar(80) NOT NULL PRIMARY KEY, IsSensitive bit NOT NULL, ExpectedTemplate nvarchar(max) NULL);'
        Invoke-NonQuery $c 'CREATE TABLE cfg.DatabaseObjectSettingRule (ObjectSettingRuleID int NOT NULL PRIMARY KEY, SettingCode varchar(80) NOT NULL, IsSensitive bit NOT NULL, ExpectedTemplate nvarchar(max) NULL);'
        Invoke-NonQuery $c 'CREATE TABLE cfg.DatabaseSettingRule (SettingRuleID int NOT NULL PRIMARY KEY, SettingCode varchar(80) NOT NULL, IsSensitive bit NOT NULL, ExpectedTemplate nvarchar(max) NULL);'
        $masterKeyText = 'Test-only-' + 'master-key-' + [guid]::NewGuid().ToString('N')
        Invoke-NonQuery $c ("CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'{0}';" -f $masterKeyText)
        Invoke-NonQuery $c "CREATE CERTIFICATE SISQUAL_ManagedCredential_Certificate WITH SUBJECT = N'test certificate';"
        Invoke-NonQuery $c 'CREATE SYMMETRIC KEY SISQUAL_ManagedCredential_Key WITH ALGORITHM = AES_256 ENCRYPTION BY CERTIFICATE SISQUAL_ManagedCredential_Certificate;'
        Invoke-NonQuery $c $runtimeProc
        Invoke-NonQuery $c $catalogueProc
        Invoke-NonQuery $c "INSERT INTO dbo.ManagedServer VALUES ('SRV1', N'HOST-1');"
        foreach ($i in @('PTCOM1', 'PTCOM2', 'NOCRED')) { Invoke-NonQuery $c ("INSERT INTO dbo.ManagedInstance VALUES ('{0}', 'SRV1', 'PT', N'Customer {0}', 'h-{0}', 1, N'svc-iis', N'svc-web');" -f $i) }
        Set-TestCredential $c 'PTCOM1' 'IIS_IDENTITY' $vIis1 3
        Set-TestCredential $c 'PTCOM1' 'WEB_ACCESS' $vWeb1 1
        Set-TestCredential $c 'PTCOM1' 'MOBILE_APP_TOKEN' $vMob1 2
        Set-TestCredential $c 'PTCOM2' 'IIS_IDENTITY' $vIis2 1
        Set-TestCredential $c 'GHOST' 'WEB_ACCESS' $vGhost 1
        Invoke-NonQuery $c ("INSERT INTO cfg.ConfigRule VALUES ('RULE_ONE', 1, N'{0}'), ('RULE_TWO', 1, N'Keystore-Password={1}'), ('PLAIN_RULE', 0, N'not secret'), ('PLACEHOLDER_RULE', 1, N'Password={{Secret}}');" -f $vRule1, $vRule2)
        Invoke-NonQuery $c ("INSERT INTO cfg.DatabaseObjectSettingRule VALUES (1, 'SET_SECRET', 1, N'{0}'), (2, 'SET_PLAIN', 0, N'plain');" -f $vRule3)
        Assert-That 'fixture: five credential rows, one of them an orphan with no instance' ([int](Invoke-Scalar $c 'SELECT COUNT(*) FROM sec.ManagedCredential;') -eq 5)
        $ownerOk = [string](Invoke-Scalar $c "SELECT CONVERT(nvarchar(256), SUSER_SNAME(owner_sid)) FROM sys.databases WHERE name = DB_NAME();")
        Assert-That 'fixture: the procedures are the real ones (WITH EXECUTE AS OWNER) and the database has an owner' (($ownerOk.Length -gt 0) -and ([int](Invoke-Scalar $c "SELECT COUNT(*) FROM sys.sql_modules m JOIN sys.objects o ON o.object_id = m.object_id WHERE o.name IN ('GetManagedCredentialRuntime','GetManagedCredentialCatalogue') AND m.definition LIKE '%EXECUTE AS OWNER%';") -eq 2))
    }
    finally { $c.Dispose() }
    function Get-SourceChecksum {
        $cc = Get-Connection -Database $dbName
        try { return [string](Invoke-Scalar $cc 'SELECT CONVERT(varchar(50), COUNT(*)) + ''/'' + CONVERT(varchar(50), CHECKSUM_AGG(CHECKSUM(InstanceCode, CredentialType, SecretVersion, SecretCipher))) FROM sec.ManagedCredential;') } finally { $cc.Dispose() }
    }

    # -----------------------------------------------------------------------
    # A. The reader
    # -----------------------------------------------------------------------
    $checksumBefore = Get-SourceChecksum
    $src = Read-LiveCredentialSource -SqlInstance $SqlInstance -Database $dbName -SqlClientPath $SqlClientPath -TrustServerCertificate
    Assert-That 'reader: the catalogue lists the three instances with the right configured flags' (($src.Catalogue.Count -eq 3) -and (@($src.Catalogue | Where-Object { $_['InstanceCode'] -ceq 'PTCOM1' -and $_['IisIdentityConfigured'] -and $_['WebAccessConfigured'] -and $_['MobileAppTokenConfigured'] }).Count -eq 1) -and (@($src.Catalogue | Where-Object { $_['InstanceCode'] -ceq 'NOCRED' -and -not $_['IisIdentityConfigured'] -and -not $_['WebAccessConfigured'] -and -not $_['MobileAppTokenConfigured'] }).Count -eq 1))
    Assert-That 'reader: four runtime rows, decrypted through the certificate, equal to the values that were encrypted' (($src.Runtime.Count -eq 4) -and (@($src.Runtime | Where-Object { $_['InstanceCode'] -ceq 'PTCOM1' -and $_['CredentialType'] -ceq 'WEB_ACCESS' -and $_['SecretValue'] -ceq $vWeb1 -and $_['SecretVersion'] -eq 1 }).Count -eq 1) -and (@($src.Runtime | Where-Object { $_['InstanceCode'] -ceq 'PTCOM1' -and $_['CredentialType'] -ceq 'IIS_IDENTITY' -and $_['SecretValue'] -ceq $vIis1 -and $_['SecretVersion'] -eq 3 }).Count -eq 1) -and (@($src.Runtime | Where-Object { $_['InstanceCode'] -ceq 'PTCOM2' -and $_['SecretValue'] -ceq $vIis2 }).Count -eq 1))
    Assert-That 'reader: the orphan credential (no instance) is not readable through this path and is not returned' (@($src.Runtime | Where-Object { $_['InstanceCode'] -ceq 'GHOST' }).Count -eq 0)
    Assert-That 'reader: the three rule tables are read with id, IsSensitive and template' (($src.RuleRows.Keys.Count -eq 3) -and ($src.RuleRows['cfg.ConfigRule'].Count -eq 4) -and ($src.RuleRows['cfg.DatabaseObjectSettingRule'].Count -eq 2) -and ($src.RuleRows['cfg.DatabaseSettingRule'].Count -eq 0) -and (@($src.RuleRows['cfg.ConfigRule'] | Where-Object { $_['Id'] -ceq 'RULE_ONE' -and $_['IsSensitive'] -eq 1 -and $_['Template'] -ceq $vRule1 }).Count -eq 1))
    Assert-That 'reader: it only reads (the credential table is unchanged)' ((Get-SourceChecksum) -ceq $checksumBefore)
    Assert-Throws 'reader: a database that does not exist is a code with the SQL error number and no message text' { Read-LiveCredentialSource -SqlInstance $savedInstance -Database 'NoSuchDatabase_xyz' -SqlClientPath $savedClientPath -TrustServerCertificate } 'SOURCE_READ_FAILED_SQL_*'
    Assert-Throws 'reader: a missing SQL client is SQLCLIENT_MISSING' { Read-LiveCredentialSource -SqlInstance $savedInstance -Database $dbName -SqlClientPath (Join-Path $root 'nothing') } 'SQLCLIENT_MISSING'

    # -----------------------------------------------------------------------
    # B. Plan and the three modes against a real vault
    # -----------------------------------------------------------------------
    $plan = New-CredentialImportPlan -Catalogue $src.Catalogue -Runtime $src.Runtime -RuleRows $src.RuleRows
    Assert-That 'plan: Ok, seven entries (four credentials and three rule secrets), counts 2,1,1,3' ($plan.Ok -and $plan.Entries.Count -eq 7 -and (($plan.Expected.Keys | ForEach-Object { $plan.Expected[$_] }) -join ',') -ceq '2,1,1,3')
    $vaultPath = Join-Path $root 'v1' 'vault.sisqual'
    $vault = New-CredentialVault -Path $vaultPath -Passphrase (New-Pass $passphraseText)
    $imp = Invoke-CredentialImport -Plan $plan -Mode Import -Vault $vault
    Assert-That 'import: seven secrets in a real vault, saved, every fingerprint matches' ($imp.Ok -and $imp.Saved -and $imp.Matched -eq 7)
    Assert-That 'import: the value read through the certificate is what the vault holds' ([System.Text.Encoding]::UTF8.GetString((Get-VaultSecretValue -Vault $vault -CredentialRef 'IIS_IDENTITY.PTCOM1')) -ceq $vIis1)
    Assert-That 'import: a name=value rule keeps only the value' ([System.Text.Encoding]::UTF8.GetString((Get-VaultSecretValue -Vault $vault -CredentialRef 'RULE_SECRET.RULE_TWO')) -ceq $vRule2)
    Clear-ImportPlan -Plan $plan
    $srcAgain = Read-LiveCredentialSource -SqlInstance $SqlInstance -Database $dbName -SqlClientPath $SqlClientPath -TrustServerCertificate
    $ver = Invoke-CredentialImport -Plan (New-CredentialImportPlan -Catalogue $srcAgain.Catalogue -Runtime $srcAgain.Runtime -RuleRows $srcAgain.RuleRows) -Mode Verify -Vault $vault
    Assert-That 'verify: a fresh read of the unchanged source matches all seven' ($ver.Ok -and $ver.Matched -eq 7)
    $c = Get-Connection -Database $dbName
    try { Set-TestCredential $c 'PTCOM1' 'WEB_ACCESS' 'MARKER-ROTATED-2299-not-real' 2 } finally { $c.Dispose() }
    $srcRot = Read-LiveCredentialSource -SqlInstance $SqlInstance -Database $dbName -SqlClientPath $SqlClientPath -TrustServerCertificate
    $verRot = Invoke-CredentialImport -Plan (New-CredentialImportPlan -Catalogue $srcRot.Catalogue -Runtime $srcRot.Runtime -RuleRows $srcRot.RuleRows) -Mode Verify -Vault $vault
    Assert-That 'verify: a credential rotated in the source is MISMATCH for that reference only' ((-not $verRot.Ok) -and ($verRot.Failures -ccontains 'MISMATCH:WEB_ACCESS.PTCOM1') -and $verRot.Failures.Count -eq 1 -and $verRot.Matched -eq 6)
    $c = Get-Connection -Database $dbName
    try { Set-TestCredential $c 'PTCOM1' 'WEB_ACCESS' $vWeb1 1 } finally { $c.Dispose() }
    Close-CredentialVault -Vault $vault

    # a credential that cannot be decrypted
    $c = Get-Connection -Database $dbName
    try { Invoke-NonQuery $c "UPDATE sec.ManagedCredential SET SecretCipher = 0x0123456789ABCDEF WHERE InstanceCode = 'PTCOM2' AND CredentialType = 'IIS_IDENTITY';" } finally { $c.Dispose() }
    $srcBad = Read-LiveCredentialSource -SqlInstance $SqlInstance -Database $dbName -SqlClientPath $SqlClientPath -TrustServerCertificate
    Assert-That 'reader: a ciphertext that cannot be decrypted comes back as a null value (the proc returns NULL)' (@($srcBad.Runtime | Where-Object { $_['InstanceCode'] -ceq 'PTCOM2' -and $null -eq $_['SecretValue'] }).Count -eq 1)
    $planBad = New-CredentialImportPlan -Catalogue $srcBad.Catalogue -Runtime $srcBad.Runtime -RuleRows $srcBad.RuleRows
    Assert-That 'plan: it is a failure NULL_SECRET with the reference' ((-not $planBad.Ok) -and ($planBad.Failures -ccontains 'NULL_SECRET:IIS_IDENTITY.PTCOM2'))
    $vaultBadPath = Join-Path $root 'v2' 'vault.sisqual'
    $vaultBad = New-CredentialVault -Path $vaultBadPath -Passphrase (New-Pass $passphraseText)
    $hashBefore = Get-Sha $vaultBadPath
    $refused = Invoke-CredentialImport -Plan $planBad -Mode Import -Vault $vaultBad
    Assert-That 'import: all or nothing - with one credential that cannot be read nothing is saved and the vault is byte-identical' ((-not $refused.Ok) -and -not $refused.Saved -and (Get-Sha $vaultBadPath) -ceq $hashBefore -and @(Get-VaultSecretList -Vault $vaultBad).Count -eq 0)
    Close-CredentialVault -Vault $vaultBad
    Clear-ImportPlan -Plan $planBad

    # -----------------------------------------------------------------------
    # C. The script, as a child process
    # -----------------------------------------------------------------------
    $common = @('-SqlInstance', $SqlInstance, '-Database', $dbName, '-SqlClientPath', $SqlClientPath, '-TrustServerCertificate')
    $dryBad = Invoke-Tool (@('-Mode', 'DryRun') + $common)
    Assert-That 'script: a dry run with a credential that cannot be read is exit 1 and names the reference' ($dryBad.Exit -eq 1 -and $dryBad.Out -clike '*FAILURE NULL_SECRET:IIS_IDENTITY.PTCOM2*' -and $dryBad.Out -clike '*Result: FAILED*')
    $c = Get-Connection -Database $dbName
    try { Set-TestCredential $c 'PTCOM2' 'IIS_IDENTITY' $vIis2 1 } finally { $c.Dispose() }
    $checksumScripts0 = Get-SourceChecksum
    $dry = Invoke-Tool (@('-Mode', 'DryRun') + $common)
    Assert-That 'script: the default mode is a dry run: exit 0, the counts per kind, nothing written' ($dry.Exit -eq 0 -and $dry.Out -clike '*Mode: DryRun*' -and $dry.Out -clike '*Total*' -and $dry.Out -clike '*Result: OK*' -and $dry.Out -clike '*nothing was written*')
    $defaultMode = Invoke-Tool $common
    Assert-That 'script: with no -Mode it is a DryRun (the safe default)' ($defaultMode.Exit -eq 0 -and $defaultMode.Out -clike '*Mode: DryRun*')
    $vaultScript = Join-Path $root 'v3' 'vault.sisqual'
    $v3 = New-CredentialVault -Path $vaultScript -Passphrase (New-Pass $passphraseText); Close-CredentialVault -Vault $v3
    $env1 = @{ SISQUAL_VAULT_PASSPHRASE = $passphraseText; SISQUAL_ALLOW_ENV_PASSPHRASE = '1' }
    $imported = Invoke-Tool (@('-Mode', 'Import', '-VaultPath', $vaultScript) + $common) $env1
    Assert-That 'script: Import is exit 0, saved, and the report counts match' ($imported.Exit -eq 0 -and $imported.Out -clike '*Result: OK*' -and $imported.Out -clike '*saved: True*' -and $imported.Out -clike '*Fingerprints matched: 7*')
    $verified = Invoke-Tool (@('-Mode', 'Verify', '-VaultPath', $vaultScript) + $common) $env1
    Assert-That 'script: Verify of the unchanged source is exit 0' ($verified.Exit -eq 0 -and $verified.Out -clike '*Fingerprints matched: 7*')
    $twice = Invoke-Tool (@('-Mode', 'Import', '-VaultPath', $vaultScript) + $common) $env1
    Assert-That 'script: a second Import without -Replace is exit 1 with SECRET_EXISTS' ($twice.Exit -eq 1 -and $twice.Out -clike '*VAULT:SECRET_EXISTS*')
    $replaced = Invoke-Tool (@('-Mode', 'Import', '-Replace', '-VaultPath', $vaultScript) + $common) $env1
    Assert-That 'script: with -Replace the import is exit 0' ($replaced.Exit -eq 0)
    $noPass = Invoke-Tool (@('-Mode', 'Import', '-VaultPath', $vaultScript) + $common) @{}
    Assert-That 'script: without a passphrase source it fails before any secret is read' ($noPass.Exit -eq 1 -and $noPass.Err -clike '*VAULT_PASSPHRASE_INPUT*' -and $noPass.Out -cnotlike '*Total*')
    $wrongPass = Invoke-Tool (@('-Mode', 'Verify', '-VaultPath', $vaultScript) + $common) @{ SISQUAL_VAULT_PASSPHRASE = 'correct horse battery staple 43'; SISQUAL_ALLOW_ENV_PASSPHRASE = '1' }
    Assert-That 'script: a wrong vault passphrase is VAULT_OPEN and no secret is read' ($wrongPass.Exit -eq 1 -and $wrongPass.Err -clike '*VAULT_OPEN*' -and $wrongPass.Out -cnotlike '*Total*')
    $badDb = Invoke-Tool @('-Mode', 'DryRun', '-SqlInstance', $SqlInstance, '-Database', 'NoSuchDatabase_xyz', '-SqlClientPath', $SqlClientPath, '-TrustServerCertificate')
    Assert-That 'script: a database that does not exist is exit 1 with a code and no SQL text' ($badDb.Exit -eq 1 -and $badDb.Err -clike '*IMPORT_FAILED: SOURCE_READ_FAILED_SQL_*')
    $all = ($dryBad, $dry, $defaultMode, $imported, $verified, $twice, $replaced, $noPass, $wrongPass, $badDb | ForEach-Object { $_.Out + "`n" + $_.Err }) -join "`n"
    Assert-That 'hygiene: no marker value and no passphrase in any output of the script' ((-not (@($markers | Where-Object { $all -clike ('*' + $_ + '*') }).Count)) -and ($all -cnotlike ('*' + $passphraseText + '*')))
    $scriptVault = Open-CredentialVault -Path $vaultScript -Passphrase (New-Pass $passphraseText)
    Assert-That 'script: the vault written by the script holds the seven secrets and the values' ((@(Get-VaultSecretList -Vault $scriptVault).Count -eq 7) -and ([System.Text.Encoding]::UTF8.GetString((Get-VaultSecretValue -Vault $scriptVault -CredentialRef 'RULE_SECRET.SET_SECRET')) -ceq $vRule3))
    Close-CredentialVault -Vault $scriptVault
    Assert-That 'source: the script runs (DryRun, Import, Verify, refused attempts) left the credential table exactly as it was (read only)' ((Get-SourceChecksum) -ceq $checksumScripts0)
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    if ($dbCreated -and -not $KeepDatabase) {
        try { $m = Get-Connection -Database 'master'; try { Invoke-NonQuery $m ('ALTER DATABASE [{0}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{0}];' -f $dbName) } finally { $m.Dispose() } } catch { Write-Host ('WARN  could not drop the test database: ' + $_.Exception.Message) }
    }
}
Write-Host ''
Write-Host ('Passed: {0}  Failed: {1}' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
