#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProviderRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$engineSource = Join-Path $repo 'engines\Invoke-DeploymentPreflight.ps1'
$hostModule = Join-Path $repo 'runtime\Sisqual.Runtime.EngineHost.psm1'
$catalogModuleSource = Join-Path $repo 'runtime\Sisqual.Runtime.Catalog.psm1'
$catalogCoreSource = Join-Path $repo 'runtime\Sisqual.Runtime.Catalog.Core.ps1'
. (Join-Path $PSScriptRoot 'TestCatalogSessionStub.ps1')

$script:Passed = 0
$script:Failed = 0
function Check([string]$Name,[bool]$Condition) {
    if ($Condition) { $script:Passed++; Write-Host ('PASS  ' + $Name) }
    else { $script:Failed++; Write-Host ('FAIL  ' + $Name) }
}
function Throws([string]$Name,[scriptblock]$Action,[string]$Expected='') {
    $ok = $false
    $caught = ''
    try { & $Action } catch { $caught = [string]$_.Exception.Message; $ok = [string]::IsNullOrEmpty($Expected) -or $caught -like ('*' + $Expected + '*') }
    if (-not $ok) { Write-Host ('DIAG  {0}: exception={1}' -f $Name,$caught) }
    Check $Name $ok
}
function Write-SafeResultDiagnostic {
    param([Parameter(Mandatory)][string]$Label,[AllowNull()][object]$Result)
    if ($null -eq $Result) {
        Write-Host ('DIAG  {0}: errorMessage=<no-result>; exitCode=-1; summary={{}}' -f $Label)
        return
    }
    $errorMessage = ''
    if ($null -ne $Result.PSObject.Properties['errorMessage']) { $errorMessage = [string]$Result.errorMessage }
    $exitCode = -1
    if ($null -ne $Result.PSObject.Properties['exitCode']) { $exitCode = [int]$Result.exitCode }
    $summary = '{}'
    if ($null -ne $Result.PSObject.Properties['summary'] -and $null -ne $Result.summary) { $summary = $Result.summary | ConvertTo-Json -Compress -Depth 5 }
    Write-Host ('DIAG  {0}: errorMessage={1}; exitCode={2}; summary={3}' -f $Label,$errorMessage,$exitCode,$summary)
}
function FileEntry([string]$PackageRoot,[string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    return [pscustomobject]@{
        path = [IO.Path]::GetRelativePath($PackageRoot,$item.FullName).Replace('\','/')
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        size = [long]$item.Length
    }
}
function PackageEntries([string]$PackageRoot) {
    return @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object Name -ne 'package-manifest.json' | ForEach-Object { FileEntry $PackageRoot $_.FullName } | Sort-Object path)
}
function TreeFingerprint([string]$Root) {
    $rows = foreach ($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName)) {
        $relative = [IO.Path]::GetRelativePath($Root,$file.FullName).Replace('\','/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        '{0}|{1}|{2}' -f $relative,$file.Length,$hash
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($rows -join "`n"))
    return ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
}
function Invoke-NonQuery($Connection,[string]$Sql) {
    $command = $Connection.CreateCommand()
    try { $command.CommandText = $Sql; [void]$command.ExecuteNonQuery() } finally { $command.Dispose() }
}
function SqlLiteral([string]$Value) { return "'" + $Value.Replace("'","''") + "'" }
function Invoke-DirectPreflightRequest {
    param([Parameter(Mandatory)][string]$Pwsh,[Parameter(Mandatory)][string]$EnginePath,[Parameter(Mandatory)][object]$Request)
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Pwsh
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($arg in @('-NoLogo','-NoProfile','-NonInteractive','-File',$EnginePath)) { [void]$info.ArgumentList.Add($arg) }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
    try {
        [void]$process.Start()
        $process.StandardInput.Write(($Request | ConvertTo-Json -Compress -Depth 30))
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return [pscustomobject]@{ ExitCode=$process.ExitCode; Stdout=$stdout; Stderr=$stderr }
    }
    finally { $process.Dispose() }
}

$temp = Join-Path $env:TEMP ('sisqual-preflight-' + [guid]::NewGuid().ToString('N'))
try {
    $package = Join-Path $temp 'package'
    $engines = Join-Path $package 'engines'
    $runtime = Join-Path $package 'runtime'
    $provider = Join-Path $runtime 'sqlite-provider'
    $catalogDir = Join-Path $package 'catalog'
    $servicesRoot = Join-Path $temp 'managed-services'
    $instanceRoot = Join-Path $servicesRoot 'preflight-host.invalid'
    $appRoot = Join-Path $instanceRoot 'App'
    New-Item -ItemType Directory -Path $engines,$runtime,$catalogDir,$servicesRoot,$instanceRoot,$appRoot -Force | Out-Null
    Copy-Item -LiteralPath $ProviderRoot -Destination $provider -Recurse -Force
    Copy-Item -LiteralPath $catalogModuleSource -Destination (Join-Path $runtime 'Sisqual.Runtime.Catalog.psm1')
    Copy-Item -LiteralPath $catalogCoreSource -Destination (Join-Path $runtime 'Sisqual.Runtime.Catalog.Core.ps1')
    Copy-Item -LiteralPath $engineSource -Destination (Join-Path $engines 'Invoke-DeploymentPreflight.ps1')
    [IO.File]::WriteAllText((Join-Path $appRoot 'config.json'),'{}',[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $instanceRoot 'service.exe'),'fixture',[Text.UTF8Encoding]::new($false))

    Import-Module (Join-Path $runtime 'Sisqual.Runtime.Catalog.psm1') -Force
    $providerEntries = @(Get-ChildItem -LiteralPath $provider -Recurse -File | ForEach-Object { FileEntry $package $_.FullName })
    [void](Initialize-SisqualRuntimeSqliteProvider -PackageRoot $package -ProviderRoot 'runtime\sqlite-provider' -VerifiedFiles $providerEntries)

    $catalog = Join-Path $catalogDir 'catalog-TESTSERVER.db'
    $builder = [Microsoft.Data.Sqlite.SqliteConnectionStringBuilder]::new()
    $builder.DataSource = $catalog
    $builder.Mode = [Microsoft.Data.Sqlite.SqliteOpenMode]::ReadWriteCreate
    $builder.Pooling = $false
    $connection = [Microsoft.Data.Sqlite.SqliteConnection]::new($builder.ConnectionString)
    $connection.Open()
    try {
        $machine = [Environment]::MachineName
        $svc = $servicesRoot.Replace("'","''")
        $sql = @"
CREATE TABLE catalog_meta(meta_id INTEGER PRIMARY KEY,schema_version INTEGER,server_code TEXT,source_kind TEXT,source_reference TEXT,built_at_utc TEXT,cut_rule_version INTEGER);
INSERT INTO catalog_meta VALUES(1,2,'TESTSERVER','conversion-tool','synthetic','2026-10-08T06:00:00Z',3);
CREATE TABLE dbo_ManagedServer(ServerCode TEXT,MachineName TEXT,ServicesRoot TEXT,ConfigBackupRoot TEXT,IsEnabled INTEGER);
INSERT INTO dbo_ManagedServer VALUES('TESTSERVER',$(SqlLiteral $machine),'$svc','$svc',1);
CREATE TABLE dbo_ManagedInstance(InstanceCode TEXT,ServerCode TEXT,HostName TEXT,CountryCode TEXT,CustomerCode TEXT,IisIdentityUserName TEXT,WebAccessUserName TEXT,CustomerLogo BLOB,CustomerLogoSha256 TEXT,IsEnabled INTEGER);
INSERT INTO dbo_ManagedInstance VALUES('INST1','TESTSERVER','preflight-host.invalid','PT','C1','svc-user','web-user',X'0102','01',1);
INSERT INTO dbo_ManagedInstance VALUES('INST2','TESTSERVER','preflight-host2.invalid','PT','C2','svc-user2','web-user2',X'0102','01',1);
INSERT INTO dbo_ManagedInstance VALUES('INST3','TESTSERVER','preflight-host3.invalid','ES','C3','svc-user3','web-user3',X'0102','01',1);
INSERT INTO dbo_ManagedInstance VALUES('INST4','TESTSERVER','preflight-host4.invalid','BR','C4','svc-user4','web-user4',X'0102','01',1);
CREATE TABLE cfg_Application(ApplicationCode TEXT,PhysicalPathTemplate TEXT,IsEnabled INTEGER);
INSERT INTO cfg_Application VALUES('APP1','{INSTANCE_ROOT}\\App',1);
CREATE TABLE cfg_ConfigFile(FileID INTEGER,ApplicationCode TEXT,RelativePath TEXT,FileFormat TEXT,IsRequired INTEGER,IsEnabled INTEGER);
INSERT INTO cfg_ConfigFile VALUES(1,'APP1','config.json','JSON',1,1);
INSERT INTO cfg_ConfigFile VALUES(2,'APP1','optional.json','JSON',0,1);
CREATE TABLE cfg_ConfigRule(RuleID INTEGER,RuleCode TEXT,FileID INTEGER,IsEnabled INTEGER);
INSERT INTO cfg_ConfigRule VALUES(1,'APP_CONFIG',1,1);
INSERT INTO cfg_ConfigRule VALUES(2,'APP_OPTIONAL',2,1);
CREATE TABLE cfg_ConfigFileRepairPolicy(FileID INTEGER,RepairMode TEXT,IsEnabled INTEGER);
INSERT INTO cfg_ConfigFileRepairPolicy VALUES(1,'PATCH',1);
CREATE TABLE cfg_WindowsServiceDefinition(ServiceCode TEXT,ServiceNameTemplate TEXT,ExecutablePathTemplate TEXT,IsEnabled INTEGER);
INSERT INTO cfg_WindowsServiceDefinition VALUES('WFM_MOBILE_APP','svc-{INSTANCE_CODE}','{INSTANCE_ROOT}\\service.exe',1);
CREATE TABLE cfg_ManagedAssetDestination(AssetType TEXT,DestinationCode TEXT,IsEnabled INTEGER);
INSERT INTO cfg_ManagedAssetDestination VALUES('CUSTOMER_LOGO','APP',1);
CREATE TABLE cfg_IisServerPolicy(ServerCode TEXT,IsEnabled INTEGER);
INSERT INTO cfg_IisServerPolicy VALUES('TESTSERVER',1);
CREATE TABLE cfg_IisApplicationDefinition(IisApplicationCode TEXT,IsEnabled INTEGER);
INSERT INTO cfg_IisApplicationDefinition VALUES('APP1',1);
CREATE TABLE cfg_WebAccessPolicy(ServerCode TEXT,BackendBaseUrlTemplate TEXT,PublicLaunchBaseUrlTemplate TEXT,IsEnabled INTEGER);
INSERT INTO cfg_WebAccessPolicy VALUES('TESTSERVER','https://127.0.0.1:8443','https://{HOST_NAME}/',1);
CREATE TABLE cfg_WebAccessTemplate(TemplateCode TEXT,IsEnabled INTEGER);
INSERT INTO cfg_WebAccessTemplate VALUES('ROOT_PAGE',1);
CREATE TABLE cfg_LinksPagePolicy(ServerCode TEXT,IsEnabled INTEGER);
INSERT INTO cfg_LinksPagePolicy VALUES('TESTSERVER',1);
CREATE TABLE cfg_LinksProfile(ProfileCode TEXT,IsEnabled INTEGER);
INSERT INTO cfg_LinksProfile VALUES('DEFAULT',1);
CREATE TABLE cfg_LinksProfileInstance(ProfileCode TEXT,InstanceCode TEXT);
INSERT INTO cfg_LinksProfileInstance VALUES('DEFAULT','INST1');
CREATE TABLE cfg_LinksPageTemplate(TemplateCode TEXT,IsEnabled INTEGER);
INSERT INTO cfg_LinksPageTemplate VALUES('INDEX',1);
CREATE TABLE cfg_LinksPagePresentationResource(ResourceCode TEXT,IsEnabled INTEGER);
INSERT INTO cfg_LinksPagePresentationResource VALUES('TEXT',1);
CREATE TABLE cfg_LinksPageAsset(AssetCode TEXT,FileName TEXT,MimeType TEXT,Content BLOB,ContentSha256 TEXT,IsEnabled INTEGER,ModifiedAt TEXT);
INSERT INTO cfg_LinksPageAsset VALUES('QR_CHANNEL_C1','qr.png','image/png',X'01','',1,NULL);
INSERT INTO cfg_LinksPageAsset VALUES('QR_CHANNEL_ZZ','zz.png','image/png',X'02','',1,NULL);
CREATE TABLE cfg_PulseProfile(HubInstanceCode TEXT,IsEnabled INTEGER);
INSERT INTO cfg_PulseProfile VALUES('INST1',1);
CREATE TABLE cfg_PulseHttpPolicy(ApplicationCode TEXT,IsEnabled INTEGER);
INSERT INTO cfg_PulseHttpPolicy VALUES('APP1',1);
CREATE TABLE cfg_PulseResource(ResourceCode TEXT,ContentSha256 TEXT,TextContent TEXT,BinaryContent BLOB,IsEnabled INTEGER);
INSERT INTO cfg_PulseResource VALUES('PULSE_INDEX_HTML','',NULL,X'01',1),('PULSE_LOGO','',NULL,X'02',1);
CREATE TABLE ops_Engine(EngineCode TEXT,SourceFileName TEXT,IsEnabled INTEGER);
INSERT INTO ops_Engine VALUES('DEPLOYMENT_PREFLIGHT','Invoke-DeploymentPreflight.ps1',1);
CREATE TABLE ops_Action(ActionCode TEXT,ActionType TEXT,EngineCode TEXT,IsEnabled INTEGER);
INSERT INTO ops_Action VALUES('DEPLOYMENT_PREFLIGHT','ENGINE','DEPLOYMENT_PREFLIGHT',1);
"@
        Invoke-NonQuery $connection $sql
    }
    finally { $connection.Dispose() }
    Remove-Module Sisqual.Runtime.Catalog -Force -ErrorAction SilentlyContinue

    # The package carries what the host verifies before it starts the engine: the launcher and the approved secret contract.
    New-Item -ItemType Directory -Path (Join-Path $package 'runtime') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $hostModule) 'Invoke-SisqualEngineLauncher.ps1') -Destination (Join-Path $package 'runtime/Invoke-SisqualEngineLauncher.ps1')
    New-Item -ItemType Directory -Path (Join-Path $package 'contracts') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $package 'contracts/engine-secret-references.json'),'{"contractVersion":"0.1-proposed","engines":{"DEPLOYMENT_PREFLIGHT":["IIS_IDENTITY.*"]}}',[Text.UTF8Encoding]::new($false))
    $entries = PackageEntries $package
    $manifest = [ordered]@{
        contractVersion='0.1-proposed'; packageId='00000000-0000-4000-8000-000000000111'; productVersion='0.0.0-test'; builtAt='2026-10-08T06:01:00Z'
        catalog=[ordered]@{ serverCode='TESTSERVER'; file='catalog/catalog-TESTSERVER.db'; schemaVersion=2; origin='conversion-tool'; originReference='synthetic' }
        files=@($entries)
        signature=[ordered]@{ issuerKeyId=('0'*64); algorithm='ECDSA-P256-SHA256'; value='AAAAAAAAAAAAAAAAAAAAAAAA' }
    }
    [IO.File]::WriteAllText((Join-Path $package 'package-manifest.json'),($manifest | ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))

    $secrets = @{ 'IIS_IDENTITY.INST1'='canary-preflight-secret-A!'; 'IIS_IDENTITY.INST2'='canary-preflight-secret-B!' }
    $directResultPath = Join-Path $temp 'direct-preview-result.json'
    $directRequest = [ordered]@{
        contractVersion='0.1-proposed'; operationId='00000000-0000-4000-8000-000000000301'; engineCode='DEPLOYMENT_PREFLIGHT'; mode='PREVIEW'; instanceCode='INST1'
        catalogPath=$catalog; planFingerprint=$null; deadlineUtc=[DateTime]::UtcNow.AddMinutes(15).ToString('yyyy-MM-ddTHH:mm:ssZ')
        cancelPath=(Join-Path $temp 'direct-preview.cancel'); resultPath=$directResultPath; secrets=$secrets
    }
    $directJson = $directRequest | ConvertTo-Json -Compress -Depth 30
    $directRoundTrip = $directJson | ConvertFrom-Json -Depth 30
    $requiredEnvelope = @('contractVersion','operationId','engineCode','mode','catalogPath','deadlineUtc','cancelPath','resultPath','secrets')
    Check 'direct valid PREVIEW JSON retains every required request field' (@($requiredEnvelope | Where-Object { $null -eq $directRoundTrip.PSObject.Properties[$_] }).Count -eq 0)
    Check 'direct valid PREVIEW JSON stays below the request limit' ([Text.UTF8Encoding]::new($false).GetByteCount($directJson) -lt 1MB)
    Check 'synthetic catalog path is fully qualified and exists before child launch' ([IO.Path]::IsPathFullyQualified($catalog) -and (Test-Path -LiteralPath $catalog -PathType Leaf))
    $direct = Invoke-DirectPreflightRequest -Pwsh (Get-Process -Id $PID).Path -EnginePath (Join-Path $engines 'Invoke-DeploymentPreflight.ps1') -Request $directRequest
    Check 'direct valid PREVIEW envelope is accepted by the engine' ($direct.ExitCode -ne 2)
    Check 'direct valid PREVIEW keeps stdout and stderr silent' ([string]::IsNullOrEmpty($direct.Stdout) -and [string]::IsNullOrEmpty($direct.Stderr))
    $directResult = $null
    if (Test-Path -LiteralPath $directResultPath -PathType Leaf) { try { $directResult = [IO.File]::ReadAllText($directResultPath) | ConvertFrom-Json -Depth 30 } catch {} }
    if ($direct.ExitCode -eq 2 -or $null -eq $directResult) { Write-Host ('DIAG  direct-preview: processExitCode={0}; resultPresent={1}' -f $direct.ExitCode,($null -ne $directResult)) }

    Initialize-SisqualEngineHostCatalogStub
    Import-Module $hostModule -Force
    $session = New-SisqualTestCatalogSession -CatalogPath $catalog -MachineName ([Environment]::MachineName)
    $engine = [pscustomobject]@{ EngineCode='DEPLOYMENT_PREFLIGHT'; EngineVersion='1.0.0'; SourceFileName='Invoke-DeploymentPreflight.ps1'; IsEnabled=1; MinimumPowerShell='7.0'; RequiresAdministrator=0 }
    $action = [pscustomobject]@{ ActionCode='DEPLOYMENT_PREFLIGHT'; ActionType='ENGINE'; EngineCode='DEPLOYMENT_PREFLIGHT'; IsEnabled=1; ModePolicy='NONE'; RequiresInstanceSelection=1; AllowAllInstances=1; PassInstanceCode=1; PassApply=0; CommandTimeoutSeconds=0; ConfirmationText='' }
    Set-SisqualTestCatalogRows -Session $session -Engine $engine -Action $action
    $preflightActionCode = [string]$action.ActionCode   # not read as $action inside Throws blocks: the helper has a parameter of that name
    $before = TreeFingerprint $servicesRoot
    $result = Invoke-SisqualEngineHost -ActionCode $preflightActionCode -EngineClass READ_ONLY -PackageRoot $package -CatalogPath $catalog -CatalogSession $session -ManifestEntries $entries -Mode PREVIEW -InstanceCode INST1 -Secrets $secrets
    $after = TreeFingerprint $servicesRoot
    if (-not [bool]$result.succeeded) { Write-SafeResultDiagnostic -Label 'complete-model' -Result $result }

    Check 'READ_ONLY preflight succeeds on the complete synthetic model' ([bool]$result.succeeded)
    Check 'READ_ONLY preflight returns PREVIEW mode' ([string]$result.mode -ceq 'PREVIEW')
    Check 'PREVIEW leaves managed filesystem byte-identical' ($before -ceq $after)
    Check 'catalog build time is INFO only' (@($result.results | Where-Object { $_.object -like 'CATALOG_BUILT_AT*' -and $_.status -ceq 'INFO' }).Count -eq 1)
    Check 'normalized result arithmetic is valid' (([int]$result.summary.succeededTargets + [int]$result.summary.failedTargets) -le [int]$result.summary.targetCount -and [int]$result.summary.errorCount -eq 0)
    Check 'an optional file that is not deployed is not reported as missing (cfg_ConfigFile.IsRequired)' (@($result.results | Where-Object { $_.object -like 'REQUIRED_FILE_MISSING*' }).Count -eq 0)
    Check 'an unassigned QR asset is INFO, as in the original review' (@($result.results | Where-Object { $_.object -ceq 'QR_ASSET_UNASSIGNED:QR_CHANNEL_ZZ' -and $_.status -ceq 'INFO' }).Count -eq 1)
    Check 'an instance whose customer has its QR_CHANNEL_<CustomerCode> asset has no missing-asset issue' (@($result.results | Where-Object { $_.object -like 'QR_ASSET_MISSING*' }).Count -eq 0)
    $serialized = $result | ConvertTo-Json -Compress -Depth 30
    Check 'canary A absent from normalized result' (-not $serialized.Contains([string]$secrets['IIS_IDENTITY.INST1'],[StringComparison]::Ordinal))
    Check 'canary B absent from normalized result' (-not $serialized.Contains([string]$secrets['IIS_IDENTITY.INST2'],[StringComparison]::Ordinal))

    $missingSecret = @{ 'IIS_IDENTITY.INST2'='another-canary-value' }
    $missing = Invoke-SisqualEngineHost -ActionCode $preflightActionCode -EngineClass READ_ONLY -PackageRoot $package -CatalogPath $catalog -CatalogSession $session -ManifestEntries $entries -Mode PREVIEW -InstanceCode INST1 -Secrets $missingSecret
    $missingHasExpectedError = (-not [bool]$missing.succeeded -and @($missing.results | Where-Object { $_.object -like 'IIS_IDENTITY_PASSWORD_PENDING*' -or $_.object -like 'SERVICE_ACCOUNT_PASSWORD_MISSING*' }).Count -ge 1)
    if (-not $missingHasExpectedError) { Write-SafeResultDiagnostic -Label 'missing-iis-credential' -Result $missing }
    Check 'missing IIS identity credential is an ERROR' $missingHasExpectedError
    Check 'missing credential run still does not alter managed filesystem' ((TreeFingerprint $servicesRoot) -ceq $before)

    Throws 'READ_ONLY engine cannot be invoked as APPLY through host' { Invoke-SisqualEngineHost -ActionCode $preflightActionCode -EngineClass READ_ONLY -PackageRoot $package -CatalogPath $catalog -CatalogSession $session -ManifestEntries $entries -Mode APPLY -InstanceCode INST1 -PlanFingerprint ('0'*64) -Secrets $secrets | Out-Null } 'READ_ONLY_APPLY_NOT_ALLOWED'

    # All instances: INST1 is fine; INST2 (PT), INST3 (ES) and INST4 (BR) have no instance root. INST2 and INST3 have no QR asset, INST4 is not PT or ES.
    $all = Invoke-SisqualEngineHost -ActionCode $preflightActionCode -EngineClass READ_ONLY -PackageRoot $package -CatalogPath $catalog -CatalogSession $session -ManifestEntries $entries -Mode PREVIEW -InstanceCode '' -Secrets $secrets
    $qrMissing = @($all.results | Where-Object { $_.object -like 'QR_ASSET_MISSING*' })
    Check 'a missing QR asset is a WARNING, for an enabled PT or ES instance with a customer code only' ($qrMissing.Count -eq 2 -and @($qrMissing | Where-Object { $_.status -cne 'WARNING' }).Count -eq 0 -and (@($qrMissing | ForEach-Object { [string]$_.object }) -join '|') -ceq 'QR_ASSET_MISSING:INST2 / C2|QR_ASSET_MISSING:INST3 / C3') ((@($qrMissing | ForEach-Object { [string]$_.status + ' ' + [string]$_.object }) -join '; '))
    $summaryText = ('target={0} failed={1} succeeded={2}' -f $all.summary.targetCount, $all.summary.failedTargets, $all.summary.succeededTargets)
    Check 'failedTargets counts every instance with an error, not just one' ([int]$all.summary.targetCount -eq 4 -and [int]$all.summary.failedTargets -eq 3 -and [int]$all.summary.succeededTargets -eq 1) $summaryText

    # A catalog module changed on disk after the manifest was made is not imported: the engine compares it with the manifest before it imports it.
    $moduleFile = Join-Path $package 'runtime/Sisqual.Runtime.Catalog.Core.ps1'
    $moduleOriginal = [IO.File]::ReadAllText($moduleFile)
    try {
        [IO.File]::WriteAllText($moduleFile, $moduleOriginal + "`n# changed after the manifest was made`n", [Text.UTF8Encoding]::new($false))
        $tampered = Invoke-SisqualEngineHost -ActionCode $preflightActionCode -EngineClass READ_ONLY -PackageRoot $package -CatalogPath $catalog -CatalogSession $session -ManifestEntries $entries -Mode PREVIEW -InstanceCode INST1 -Secrets $secrets
        Check 'a catalog module that no longer matches the manifest is not imported (the run fails before reading the catalog)' (-not [bool]$tampered.succeeded -and @($tampered.results | Where-Object { $_.object -like 'PREFLIGHT_INTERNAL_ERROR*' }).Count -ge 1 -and @($tampered.results | Where-Object { $_.object -like 'CATALOG_BUILT_AT*' }).Count -eq 0) ([string]$tampered.errorMessage)
    }
    finally { [IO.File]::WriteAllText($moduleFile, $moduleOriginal, [Text.UTF8Encoding]::new($false)) }

    $invalidInfo = [Diagnostics.ProcessStartInfo]::new()
    $invalidInfo.FileName = (Get-Process -Id $PID).Path
    $invalidInfo.UseShellExecute = $false
    $invalidInfo.CreateNoWindow = $true
    $invalidInfo.RedirectStandardInput = $true
    $invalidInfo.RedirectStandardOutput = $true
    $invalidInfo.RedirectStandardError = $true
    foreach ($arg in @('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $engines 'Invoke-DeploymentPreflight.ps1'))) { [void]$invalidInfo.ArgumentList.Add($arg) }
    $invalidProcess = [Diagnostics.Process]::new(); $invalidProcess.StartInfo = $invalidInfo
    [void]$invalidProcess.Start(); $invalidProcess.StandardInput.Write('{}'); $invalidProcess.StandardInput.Close()
    $invalidOut = $invalidProcess.StandardOutput.ReadToEnd(); $invalidErr = $invalidProcess.StandardError.ReadToEnd(); $invalidProcess.WaitForExit()
    Check 'invalid request exits 2' ($invalidProcess.ExitCode -eq 2)
    Check 'invalid request emits no stdout/stderr data' ([string]::IsNullOrEmpty($invalidOut) -and [string]::IsNullOrEmpty($invalidErr))

    $applyRequest = [ordered]@{ contractVersion='0.1-proposed'; operationId='00000000-0000-4000-8000-000000000222'; engineCode='DEPLOYMENT_PREFLIGHT'; mode='APPLY'; instanceCode='INST1'; catalogPath=$catalog; planFingerprint=('0'*64); deadlineUtc=[DateTime]::UtcNow.AddMinutes(1).ToString('yyyy-MM-ddTHH:mm:ssZ'); cancelPath=(Join-Path $temp 'cancel'); resultPath=(Join-Path $temp 'direct-result.json'); secrets=@{} }
    $applyInfo = [Diagnostics.ProcessStartInfo]::new(); $applyInfo.FileName=(Get-Process -Id $PID).Path; $applyInfo.UseShellExecute=$false; $applyInfo.CreateNoWindow=$true; $applyInfo.RedirectStandardInput=$true; $applyInfo.RedirectStandardOutput=$true; $applyInfo.RedirectStandardError=$true
    foreach ($arg in @('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $engines 'Invoke-DeploymentPreflight.ps1'))) { [void]$applyInfo.ArgumentList.Add($arg) }
    $applyProcess=[Diagnostics.Process]::new(); $applyProcess.StartInfo=$applyInfo; [void]$applyProcess.Start(); $applyProcess.StandardInput.Write(($applyRequest | ConvertTo-Json -Compress -Depth 20)); $applyProcess.StandardInput.Close(); $applyStdout=$applyProcess.StandardOutput.ReadToEnd(); $applyStderr=$applyProcess.StandardError.ReadToEnd(); $applyProcess.WaitForExit()
    Check 'direct APPLY request is invalid for READ_ONLY engine and exits 2' ($applyProcess.ExitCode -eq 2)
    Check 'direct APPLY rejection is silent' ([string]::IsNullOrEmpty($applyStdout) -and [string]::IsNullOrEmpty($applyStderr))

    $packageText = @(Get-ChildItem -LiteralPath $package -Recurse -File | Where-Object { $_.Extension -in @('.json','.ps1','.psm1') } | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
    Check 'canary values are absent from package and managed files' (-not $packageText.Contains('canary-preflight-secret',[StringComparison]::Ordinal))
}
finally {
    Remove-Module Sisqual.Runtime.EngineHost -Force -ErrorAction SilentlyContinue
    Remove-Module Sisqual.Runtime.Catalog -Force -ErrorAction SilentlyContinue
    try { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction Stop } catch { Write-Host ('INFO cleanup deferred: ' + $_.Exception.Message) }
}
Write-Host ("SUMMARY: {0} passed, {1} failed" -f $script:Passed,$script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0