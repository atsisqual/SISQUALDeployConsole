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
    $message = ''
    try { & $Block; Assert-That $Name $true }
    catch { $message = $_.Exception.Message; Assert-That $Name $false $message }
}

function New-ProductionRowsWithoutV8 {
    $rows = @{}
    foreach ($table in @($script:CleanupProductionCarriedTables)) {
        $rows[[string]$table] = [System.Collections.Generic.List[object]]::new()
    }

    $rows['ops.Action'].Add([ordered]@{
        ActionCode='CONFIG_REPAIR'; ActionType='ENGINE'; EngineCode='CONFIG_REPAIR'; ModePolicy='PREVIEW_APPLY'; IsEnabled=1
        RequiresInstanceSelection=1; AllowAllInstances=1; PassInstanceCode=1; PassApply=1
    })
    $rows['ops.Engine'].Add([ordered]@{ EngineCode='CONFIG_REPAIR'; EngineVersion='1.0'; IsEnabled=1 })
    $rows['ops.ActionStep'].Add([ordered]@{ ParentActionCode='FULL_DEPLOYMENT'; StepOrder=[long]20; ChildActionCode='CONFIG_REPAIR'; IsEnabled=1 })

    $rows['cfg.Application'].Add([ordered]@{
        ApplicationCode='KEYCLOAK'; PhysicalPathTemplate='{INSTANCE_ROOT}\V8\sisqualKeycloak'; IsEnabled=1
    })
    $rows['cfg.ConfigFile'].Add([ordered]@{
        FileID=40; ApplicationCode='KEYCLOAK'; RelativePath='conf\keycloak.conf'; FileFormat='TEXT'; IsRequired=1; IsEnabled=1
    })
    $rows['cfg.ConfigRule'].Add([ordered]@{
        RuleID=412; FileID=40; CountryCode=$null; RuleCode='KEYCLOAK_DB_URL'; Category='KEYCLOAK'; SelectorType='TEXT_REGEX'
        Selector='db-url=jdbc:sqlserver://[^\r\n]+'
        ExpectedTemplate='db-url=jdbc:sqlserver://{SQL_INSTANCE_ESCAPED};databaseName=sisqualKeycloak;integratedSecurity=true;multipleActiveResultSets=true;encrypt=true;trustServerCertificate=true;loginTimeout=15;'
        ValidationType='EXACT'; IsRequired=1; AllowEncrypted=0; IsSensitive=0; Severity='ERROR'; IsEnabled=1
        RepairAction='SET_VALUE'; RepairValueType='STRING'; RepairGroup='KEYCLOAK'; RepairOrder=10; CreateIfMissing=0
        MissingParentSelector=$null; MissingNodeTemplate=$null
    })
    return $rows
}

$healthy = New-ProductionRowsWithoutV8
Assert-DoesNotThrow 'production without retired V8 metadata still accepts the intact replacement contract' {
    Assert-V8KeycloakRetirementSafe -Rows $healthy
}

$explicitPatch = New-ProductionRowsWithoutV8
$explicitPatch['cfg.ConfigFileRepairPolicy'].Add([ordered]@{ FileID=40; RepairMode='PATCH'; IsEnabled=1 })
Assert-DoesNotThrow 'an explicit enabled PATCH policy preserves the approved replacement behavior' {
    Assert-V8KeycloakRetirementSafe -Rows $explicitPatch
}

$replacePolicy = New-ProductionRowsWithoutV8
$replacePolicy['cfg.ConfigFileRepairPolicy'].Add([ordered]@{ FileID=40; RepairMode='REPLACE'; IsEnabled=1 })
Assert-Throws 'an enabled REPLACE policy cannot retire V8 because rule patching would be bypassed' {
    Assert-V8KeycloakRetirementSafe -Rows $replacePolicy
} '*PATCH*'

$missingApplication = New-ProductionRowsWithoutV8
$missingApplication['cfg.Application'].Clear()
Assert-Throws 'production retirement requires the KEYCLOAK application target' {
    Assert-V8KeycloakRetirementSafe -Rows $missingApplication
} '*KEYCLOAK application*'

$disabledApplication = New-ProductionRowsWithoutV8
$disabledApplication['cfg.Application'][0]['IsEnabled'] = 0
Assert-Throws 'production retirement requires the KEYCLOAK application to remain enabled' {
    Assert-V8KeycloakRetirementSafe -Rows $disabledApplication
} '*KEYCLOAK application must remain enabled*'

$repointedApplication = New-ProductionRowsWithoutV8
$repointedApplication['cfg.Application'][0]['PhysicalPathTemplate'] = '{INSTANCE_ROOT}\V8\differentKeycloak'
Assert-Throws 'production retirement rejects a repointed KEYCLOAK physical path' {
    Assert-V8KeycloakRetirementSafe -Rows $repointedApplication
} '*PhysicalPathTemplate*'

$missingReplacement = New-ProductionRowsWithoutV8
$missingReplacement['cfg.ConfigRule'].Clear()
Assert-Throws 'production without retired V8 metadata still requires KEYCLOAK_DB_URL' {
    Assert-V8KeycloakRetirementSafe -Rows $missingReplacement
} '*KEYCLOAK_DB_URL*'

$disabledReplacementPath = New-ProductionRowsWithoutV8
$disabledReplacementPath['ops.Engine'][0]['IsEnabled'] = 0
Assert-Throws 'production without retired V8 metadata still requires the executable CONFIG_REPAIR path' {
    Assert-V8KeycloakRetirementSafe -Rows $disabledReplacementPath
} '*CONFIG_REPAIR engine must remain enabled*'

Write-Host ('V8 replacement-without-legacy regressions: {0} passed, {1} failed' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
