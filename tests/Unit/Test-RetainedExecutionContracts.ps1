#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'Convert-ManagementDb.ps1')).Path
. $toolPath -SyncFile 'unused' -OutputFolder 'unused' -Sqlite3Path 'unused'

$script:Passed = 0
$script:Failed = 0
function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) }
    else { $script:Failed++; Write-Host ('FAIL  {0} {1}' -f $Name, $Detail) }
}
function Assert-Throws {
    param([string]$Name, [scriptblock]$Block, [string]$Like = '*')
    $threw = $false
    $message = ''
    try { & $Block } catch { $threw = $true; $message = $_.Exception.Message }
    Assert-That $Name ($threw -and $message -like $Like) $message
}
function Assert-DoesNotThrow {
    param([string]$Name, [scriptblock]$Block)
    try { & $Block; Assert-That $Name $true }
    catch { Assert-That $Name $false $_.Exception.Message }
}

function New-ConfigRepairRows {
    $rows = @{}
    foreach ($table in @('ops.Action','ops.Engine','ops.ActionStep','cfg.ConfigRule','cfg.ConfigFile')) {
        $rows[$table] = [System.Collections.Generic.List[object]]::new()
    }
    $rows['ops.Action'].Add([ordered]@{
        ActionCode='V8_KEYCLOAK_CONFIG'; ActionType='ENGINE'; EngineCode='V8_KEYCLOAK_CONFIG'; IsEnabled=0
    })
    $rows['ops.Action'].Add([ordered]@{
        ActionCode='CONFIG_REPAIR'; ActionType='ENGINE'; EngineCode='CONFIG_REPAIR'; ModePolicy='PREVIEW_APPLY'; IsEnabled=1
        RequiresInstanceSelection=1; AllowAllInstances=1; PassInstanceCode=1; PassApply=1
    })
    $rows['ops.Engine'].Add([ordered]@{ EngineCode='V8_KEYCLOAK_CONFIG'; EngineVersion='1.0'; IsEnabled=0 })
    $rows['ops.Engine'].Add([ordered]@{ EngineCode='CONFIG_REPAIR'; EngineVersion='1.0'; IsEnabled=1 })
    $rows['ops.ActionStep'].Add([ordered]@{ ParentActionCode='FULL_DEPLOYMENT'; StepOrder=[long]20; ChildActionCode='CONFIG_REPAIR'; IsEnabled=1 })
    $rows['ops.ActionStep'].Add([ordered]@{ ParentActionCode='FULL_DEPLOYMENT'; StepOrder=[long]63; ChildActionCode='V8_KEYCLOAK_CONFIG'; IsEnabled=0 })
    $rows['cfg.ConfigFile'].Add([ordered]@{ FileID=40; ApplicationCode='KEYCLOAK'; RelativePath='conf\keycloak.conf'; FileFormat='TEXT'; IsRequired=1; IsEnabled=1 })
    $rows['cfg.ConfigRule'].Add([ordered]@{
        RuleID=412; FileID=40; CountryCode=$null; RuleCode='KEYCLOAK_DB_URL'; Category='KEYCLOAK'; SelectorType='TEXT_REGEX'
        Selector='db-url=jdbc:sqlserver://[^\r\n]+'
        ExpectedTemplate='db-url=jdbc:sqlserver://{SQL_INSTANCE_ESCAPED};databaseName=sisqualKeycloak;integratedSecurity=true;multipleActiveResultSets=true;encrypt=true;trustServerCertificate=true;loginTimeout=15;'
        ValidationType='EXACT'; IsRequired=1; AllowEncrypted=0; IsSensitive=0; Severity='ERROR'; IsEnabled=1
        RepairAction='SET_VALUE'; RepairValueType='STRING'; RepairGroup='KEYCLOAK'; RepairOrder=10; CreateIfMissing=0
    })
    return $rows
}

function New-DatabaseSettingsPathRows {
    $rows = @{}
    $rows['ops.Action'] = [System.Collections.Generic.List[object]]::new()
    $rows['ops.Action'].Add([ordered]@{ ActionCode='FULL_DEPLOYMENT'; ActionType='COMPOSITE'; EngineCode=$null; IsEnabled=1 })
    $rows['ops.Action'].Add([ordered]@{ ActionCode='DATABASE_SETTINGS'; ActionType='ENGINE'; EngineCode='DATABASE_CONTENT_SYNC'; IsEnabled=1 })
    $rows['ops.ActionStep'] = [System.Collections.Generic.List[object]]::new()
    $rows['ops.ActionStep'].Add([ordered]@{ ParentActionCode='FULL_DEPLOYMENT'; StepOrder=[long]30; ChildActionCode='DATABASE_SETTINGS'; IsEnabled=1 })
    $rows['ops.Engine'] = [System.Collections.Generic.List[object]]::new()
    $rows['ops.Engine'].Add([ordered]@{ EngineCode='DATABASE_CONTENT_SYNC'; EngineVersion='1.0'; IsEnabled=1 })
    return $rows
}

$healthyRepair = New-ConfigRepairRows
Assert-DoesNotThrow 'CONFIG_REPAIR replacement keeps the approved execution contract' { Assert-V8KeycloakRetirementSafe -Rows $healthyRepair }
$badMode = New-ConfigRepairRows
$action = @($badMode['ops.Action'] | Where-Object { [string]$_['ActionCode'] -ceq 'CONFIG_REPAIR' })[0]
$action['ModePolicy'] = 'NONE'
Assert-Throws 'CONFIG_REPAIR retirement rejects a non preview/apply mode policy' { Assert-V8KeycloakRetirementSafe -Rows $badMode } '*ModePolicy=PREVIEW_APPLY*'
foreach ($field in @('RequiresInstanceSelection','AllowAllInstances','PassInstanceCode','PassApply')) {
    $bad = New-ConfigRepairRows
    $action = @($bad['ops.Action'] | Where-Object { [string]$_['ActionCode'] -ceq 'CONFIG_REPAIR' })[0]
    $action[$field] = 0
    Assert-Throws ('CONFIG_REPAIR retirement rejects disabled {0}' -f $field) { Assert-V8KeycloakRetirementSafe -Rows $bad } ('*CONFIG_REPAIR*' + $field + '*')
}

$healthySettings = New-DatabaseSettingsPathRows
Assert-DoesNotThrow 'DATABASE_SETTINGS retained path is enabled end to end' { Assert-NoRetiredCatalogMetadata -Rows $healthySettings }
# These mutations keep the retained DATABASE_CONTENT_SYNC engine fail-closed if it is disabled, NULL, or duplicated.
$disabledSettingsEngine = New-DatabaseSettingsPathRows
$disabledSettingsEngine['ops.Engine'][0]['IsEnabled'] = 0
Assert-Throws 'DATABASE_CONTENT_SYNC engine cannot be disabled after retirement' { Assert-NoRetiredCatalogMetadata -Rows $disabledSettingsEngine } '*DATABASE_CONTENT_SYNC*enabled*'
$nullSettingsEngine = New-DatabaseSettingsPathRows
$nullSettingsEngine['ops.Engine'][0]['IsEnabled'] = $null
Assert-Throws 'DATABASE_CONTENT_SYNC engine enablement cannot be NULL' { Assert-NoRetiredCatalogMetadata -Rows $nullSettingsEngine } '*DATABASE_CONTENT_SYNC*enabled*'
$duplicateSettingsEngine = New-DatabaseSettingsPathRows
$duplicateSettingsEngine['ops.Engine'].Add([ordered]@{ EngineCode='DATABASE_CONTENT_SYNC'; EngineVersion='2.0'; IsEnabled=1 })
Assert-Throws 'DATABASE_CONTENT_SYNC engine must resolve exactly once' { Assert-NoRetiredCatalogMetadata -Rows $duplicateSettingsEngine } '*exactly one enabled DATABASE_CONTENT_SYNC engine*'
$disabledAction = New-DatabaseSettingsPathRows
$disabledAction['ops.Action'][1]['IsEnabled'] = 0
Assert-Throws 'DATABASE_SETTINGS action cannot be disabled after retirement' { Assert-NoRetiredCatalogMetadata -Rows $disabledAction } '*DATABASE_SETTINGS*enabled*'
$nullAction = New-DatabaseSettingsPathRows
$nullAction['ops.Action'][1]['IsEnabled'] = $null
Assert-Throws 'DATABASE_SETTINGS action enablement cannot be NULL' { Assert-NoRetiredCatalogMetadata -Rows $nullAction } '*DATABASE_SETTINGS*enabled*'
$disabledStep = New-DatabaseSettingsPathRows
$disabledStep['ops.ActionStep'][0]['IsEnabled'] = 0
Assert-Throws 'FULL_DEPLOYMENT step 30 cannot be disabled after retirement' { Assert-NoRetiredCatalogMetadata -Rows $disabledStep } '*step 30*enabled*'
$nullStep = New-DatabaseSettingsPathRows
$nullStep['ops.ActionStep'][0]['IsEnabled'] = $null
Assert-Throws 'FULL_DEPLOYMENT step 30 enablement cannot be NULL' { Assert-NoRetiredCatalogMetadata -Rows $nullStep } '*step 30*enabled*'

Write-Host ('Retained execution contract tests: {0} passed, {1} failed.' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
