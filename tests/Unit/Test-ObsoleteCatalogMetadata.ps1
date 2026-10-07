#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sqlite3 = $env:SQLITE3_PATH
if ([string]::IsNullOrWhiteSpace($sqlite3)) {
    $found = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if ($found) { $sqlite3 = $found.Source }
}
if ([string]::IsNullOrWhiteSpace($sqlite3) -or -not (Test-Path -LiteralPath $sqlite3 -PathType Leaf)) {
    Write-Host 'sqlite3 was not found. Set SQLITE3_PATH to the pinned sqlite3 executable.'
    exit 2
}

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
function Invoke-Query {
    param([string]$CatalogDb, [string]$Sql)
    return (Invoke-Sqlite3 -Exe $sqlite3 -Arguments @('-readonly', $CatalogDb, $Sql)).Trim()
}
function New-Column {
    param([string]$Name, [string]$Type, [bool]$Nullable = $false)
    return [pscustomobject]@{ Name=$Name; Type=$Type; Length=100; Precision=0; Scale=0; Identity=$false; Nullable=$Nullable }
}
function New-Rows {
    $rows = @{}
    $rows['ops.Action'] = [System.Collections.Generic.List[object]]::new()
    $rows['ops.Action'].Add([ordered]@{ ActionCode='DATABASE_SETTINGS'; ActionType='ENGINE'; EngineCode='DATABASE_CONTENT_SYNC'; ModePolicy='PREVIEW_APPLY'; IsEnabled=1; RequiresInstanceSelection=1; AllowAllInstances=1; PassInstanceCode=1; PassApply=1 })
    $rows['ops.Action'].Add([ordered]@{ ActionCode='V8_KEYCLOAK_CONFIG'; EngineCode='V8_KEYCLOAK_CONFIG' })
    $rows['ops.Action'].Add([ordered]@{ ActionCode='KEEP_ACTION'; EngineCode='KEEP_ENGINE' })
    $rows['ops.Action'].Add([ordered]@{
        ActionCode='CONFIG_REPAIR'; ActionType='ENGINE'; EngineCode='CONFIG_REPAIR'; ModePolicy='PREVIEW_APPLY'; IsEnabled=1
        RequiresInstanceSelection=1; AllowAllInstances=1; PassInstanceCode=1; PassApply=1
    })

    $rows['ops.Engine'] = [System.Collections.Generic.List[object]]::new()
    foreach ($code in @('DATABASE_CONTENT_SYNC','DATABASE_SETTINGS','V8_KEYCLOAK_CONFIG','KEEP_ENGINE')) {
        $engineRow = [ordered]@{ EngineCode=$code; EngineVersion='1.0' }
        if ($code -ceq 'DATABASE_CONTENT_SYNC') { $engineRow['IsEnabled'] = 1 }
        $rows['ops.Engine'].Add($engineRow)
    }
    $rows['ops.Engine'].Add([ordered]@{ EngineCode='CONFIG_REPAIR'; EngineVersion='1.0'; IsEnabled=1 })

    $rows['ops.ActionStep'] = [System.Collections.Generic.List[object]]::new()
    $rows['ops.ActionStep'].Add([ordered]@{ ParentActionCode='FULL_DEPLOYMENT'; StepOrder=[long]30; ChildActionCode='DATABASE_SETTINGS'; IsEnabled=1 })
    $rows['ops.ActionStep'].Add([ordered]@{ ParentActionCode='FULL_DEPLOYMENT'; StepOrder=[long]63; ChildActionCode='V8_KEYCLOAK_CONFIG'; IsEnabled=0 })
    $rows['ops.ActionStep'].Add([ordered]@{ ParentActionCode='FULL_DEPLOYMENT'; StepOrder=[long]64; ChildActionCode='KEEP_ACTION'; IsEnabled=1 })
    $rows['ops.ActionStep'].Add([ordered]@{ ParentActionCode='FULL_DEPLOYMENT'; StepOrder=[long]20; ChildActionCode='CONFIG_REPAIR'; IsEnabled=1 })

    $rows['cfg.ConfigFile'] = [System.Collections.Generic.List[object]]::new()
    $rows['cfg.ConfigFile'].Add([ordered]@{
        FileID=40; ApplicationCode='KEYCLOAK'; RelativePath='conf\keycloak.conf'; FileFormat='TEXT'; IsRequired=1; IsEnabled=1
    })
    $rows['cfg.ConfigRule'] = [System.Collections.Generic.List[object]]::new()
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
function New-LegacyRuleRows {
    $rows = @{}
    $rows['ops.Action'] = [System.Collections.Generic.List[object]]::new()
    $rows['ops.Action'].Add([ordered]@{ ActionCode='DATABASE_SETTINGS'; EngineCode='DATABASE_CONTENT_SYNC' })
    $rows['cfg.DatabaseSettingRule'] = [System.Collections.Generic.List[object]]::new()
    $rows['cfg.DatabaseSettingRule'].Add([ordered]@{
        SettingCode='RULE_A'; CountryCode=$null; Application='APP'; SettingUser=''; SectionName='SECTION_A'; SettingKey="KEY'ONE"
        ExpectedTemplate='VALUE-{HostName}'; IsRequired=1; IsSensitive=0; IsEnabled=1; TargetTable='Settings'
    })
    $rows['cfg.DatabaseObjectSettingRule'] = [System.Collections.Generic.List[object]]::new()
    $rows['cfg.DatabaseObjectSettingRule'].Add([ordered]@{
        SettingCode='RULE_A'; CountryCode=$null; TargetDatabaseName='sisqualWFM'; TargetSchemaName='dbo'; TargetTableName='Settings'; TargetColumnName='Value'
        ExpectedTemplate='VALUE-{HostName}'; IsRequired=1; IsSensitive=0; IsEnabled=1
        FilterClause="Application='APP' AND ISNULL([User],N'')='' AND Section='SECTION_A' AND [Key]=N'KEY''ONE'"
        RuleType='FULL_REPLACE'; CreateIfMissing=1
        InsertColumnsJson='{"Application":"APP","User":"","Section":"SECTION_A","Key":"KEY''ONE"}'
    })
    return $rows
}

Assert-That 'production whitelist carries 62 tables after cleanup plus derived Links directory' ($script:CarriedTables.Count -eq 62)
Assert-That 'cfg.DatabaseSettingRule is not a carried table' (-not $script:CarriedTables.Contains('cfg.DatabaseSettingRule'))
Assert-That 'cfg.DatabaseSettingRule is validation-only and not a redaction surface' (-not $script:RedactionTables.ContainsKey('cfg.DatabaseSettingRule'))

$ruleRows = New-LegacyRuleRows
Assert-DoesNotThrow 'an enabled legacy database-setting rule with the approved four-term equivalent passes validation' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $ruleRows }
$dateLike = New-LegacyRuleRows
$dateLike['cfg.DatabaseSettingRule'][0]['SectionName'] = '2026-01-01T00:00:00Z'
$dateLike['cfg.DatabaseObjectSettingRule'][0]['FilterClause'] = "Application='APP' AND ISNULL([User],N'')='' AND Section='2026-01-01T00:00:00Z' AND [Key]=N'KEY''ONE'"
$dateLike['cfg.DatabaseObjectSettingRule'][0]['InsertColumnsJson'] = '{"Application":"APP","User":"","Section":"2026-01-01T00:00:00Z","Key":"KEY''ONE"}'
Assert-DoesNotThrow 'a section name that looks like a date is compared as text and passes (JSON dates are not converted to DateTime)' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $dateLike }
$formatVariant = New-LegacyRuleRows
$formatVariant['cfg.DatabaseObjectSettingRule'][0]['FilterClause'] = " [application] = N'APP'  AnD ISNULL ( [USER] , N'' ) = N'' AnD [section] = N'SECTION_A' AnD [KEY] = N'KEY''ONE' "
Assert-DoesNotThrow 'harmless filter whitespace, brackets and keyword casing remain equivalent' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $formatVariant }
$badRuleRows = New-LegacyRuleRows
$badRuleRows['cfg.DatabaseObjectSettingRule'][0]['ExpectedTemplate'] = 'DIFFERENT'
Assert-Throws 'a changed legacy database-setting rule cannot be silently discarded' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $badRuleRows } '*differs from its approved replacement*'
$swappedFilter = New-LegacyRuleRows
$swappedFilter['cfg.DatabaseObjectSettingRule'][0]['FilterClause'] = "Application='APP' AND ISNULL([User],N'')='' AND Section=N'KEY''ONE' AND [Key]=N'SECTION_A'"
Assert-Throws 'legacy filter values cannot be associated with the wrong columns' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $swappedFilter } '*approved replacement (filter)*'
$extraPredicate = New-LegacyRuleRows
$extraPredicate['cfg.DatabaseObjectSettingRule'][0]['FilterClause'] = "Application='APP' AND ISNULL([User],N'')='' AND Section='SECTION_A' AND [Key]=N'KEY''ONE' AND 1=0"
Assert-Throws 'legacy replacement filter cannot add a behavior-changing predicate' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $extraPredicate } '*approved replacement (filter)*'
$wrongRuleType = New-LegacyRuleRows
$wrongRuleType['cfg.DatabaseObjectSettingRule'][0]['RuleType'] = 'SUBSTRING_REPLACE'
Assert-Throws 'legacy replacement must retain FULL_REPLACE semantics' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $wrongRuleType } '*approved replacement (RuleType)*'
$noInsert = New-LegacyRuleRows
$noInsert['cfg.DatabaseObjectSettingRule'][0]['CreateIfMissing'] = 0
Assert-Throws 'legacy replacement must retain create-if-missing semantics' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $noInsert } '*approved replacement (CreateIfMissing)*'
$wrongInsertValue = New-LegacyRuleRows
$wrongInsertValue['cfg.DatabaseObjectSettingRule'][0]['InsertColumnsJson'] = '{"Application":"APP","User":"OTHER","Section":"SECTION_A","Key":"KEY''ONE"}'
Assert-Throws 'legacy replacement insert values must match the legacy key identity' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $wrongInsertValue } '*approved replacement (InsertColumnsJson)*'
foreach ($case in @(
        @{ Name = 'null'; Json = '{"Application":"APP","User":null,"Section":"SECTION_A","Key":"KEY''ONE"}' },
        @{ Name = 'an empty list'; Json = '{"Application":"APP","User":[],"Section":"SECTION_A","Key":"KEY''ONE"}' },
        @{ Name = 'the number 0'; Json = '{"Application":"APP","User":0,"Section":"SECTION_A","Key":"KEY''ONE"}' },
        @{ Name = 'the boolean false'; Json = '{"Application":"APP","User":false,"Section":"SECTION_A","Key":"KEY''ONE"}' },
        @{ Name = 'an object'; Json = '{"Application":"APP","User":{},"Section":"SECTION_A","Key":"KEY''ONE"}' }
    )) {
    $typed = New-LegacyRuleRows
    $typed['cfg.DatabaseObjectSettingRule'][0]['InsertColumnsJson'] = $case.Json
    Assert-Throws ('legacy replacement insert identity must be a JSON text, not ' + $case.Name + ' (no coercion to the empty legacy value)') { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $typed } '*approved replacement (InsertColumnsJson)*'
}
$nullApplication = New-LegacyRuleRows
$nullApplication['cfg.DatabaseObjectSettingRule'][0]['InsertColumnsJson'] = '{"Application":null,"User":"","Section":"SECTION_A","Key":"KEY''ONE"}'
Assert-Throws 'legacy replacement insert identity cannot have a null Application' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $nullApplication } '*approved replacement (InsertColumnsJson)*'
$extraInsertColumn = New-LegacyRuleRows
$extraInsertColumn['cfg.DatabaseObjectSettingRule'][0]['InsertColumnsJson'] = '{"Application":"APP","User":"","Section":"SECTION_A","Key":"KEY''ONE","Extra":"X"}'
Assert-Throws 'legacy replacement insert configuration cannot add columns' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $extraInsertColumn } '*approved replacement (InsertColumnsJson)*'

$missingKeycloakRule = New-Rows
$missingKeycloakRule['cfg.ConfigRule'].Clear()
Assert-Throws 'V8 retirement requires the KEYCLOAK_DB_URL replacement rule' { [void](Remove-ObsoleteCatalogMetadata -Rows $missingKeycloakRule) } '*KEYCLOAK_DB_URL*'

$disabledKeycloakRule = New-Rows
$disabledKeycloakRule['cfg.ConfigRule'][0]['IsEnabled'] = 0
Assert-Throws 'V8 retirement rejects a disabled KEYCLOAK_DB_URL replacement rule' { [void](Remove-ObsoleteCatalogMetadata -Rows $disabledKeycloakRule) } '*KEYCLOAK_DB_URL*IsEnabled*'

$repurposedKeycloakRule = New-Rows
$repurposedKeycloakRule['cfg.ConfigRule'][0]['ExpectedTemplate'] = 'hostname={HOST_NAME}'
Assert-Throws 'V8 retirement rejects a repurposed KEYCLOAK_DB_URL replacement rule' { [void](Remove-ObsoleteCatalogMetadata -Rows $repurposedKeycloakRule) } '*KEYCLOAK_DB_URL*ExpectedTemplate*'

$scopedKeycloakRule = New-Rows
$scopedKeycloakRule['cfg.ConfigRule'][0]['CountryCode'] = 'PT'
Assert-Throws 'V8 retirement requires KEYCLOAK_DB_URL to remain globally scoped' { [void](Remove-ObsoleteCatalogMetadata -Rows $scopedKeycloakRule) } '*CountryCode*global*NULL*'

$enabledV8Step = New-Rows
$v8Step = @($enabledV8Step['ops.ActionStep'] | Where-Object { [long]$_['StepOrder'] -eq 63 -and [string]$_['ChildActionCode'] -ceq 'V8_KEYCLOAK_CONFIG' })[0]
$v8Step['IsEnabled'] = 1
Assert-Throws 'an enabled FULL_DEPLOYMENT step 63 cannot be retired' { [void](Remove-ObsoleteCatalogMetadata -Rows $enabledV8Step) } '*step 63*explicitly disabled*'

$nullV8Step = New-Rows
$v8Step = @($nullV8Step['ops.ActionStep'] | Where-Object { [long]$_['StepOrder'] -eq 63 -and [string]$_['ChildActionCode'] -ceq 'V8_KEYCLOAK_CONFIG' })[0]
$v8Step['IsEnabled'] = $null
Assert-Throws 'a NULL FULL_DEPLOYMENT step 63 flag cannot be treated as disabled' { [void](Remove-ObsoleteCatalogMetadata -Rows $nullV8Step) } '*step 63*explicitly disabled*'

$missingConfigRepairAction = New-Rows
$configAction = @($missingConfigRepairAction['ops.Action'] | Where-Object { [string]$_['ActionCode'] -ceq 'CONFIG_REPAIR' })[0]
[void]$missingConfigRepairAction['ops.Action'].Remove($configAction)
Assert-Throws 'V8 retirement requires the CONFIG_REPAIR action' { [void](Remove-ObsoleteCatalogMetadata -Rows $missingConfigRepairAction) } '*exactly one enabled CONFIG_REPAIR action*'

$remappedConfigRepairAction = New-Rows
$configAction = @($remappedConfigRepairAction['ops.Action'] | Where-Object { [string]$_['ActionCode'] -ceq 'CONFIG_REPAIR' })[0]
$configAction['EngineCode'] = 'KEEP_ENGINE'
Assert-Throws 'V8 retirement rejects a remapped CONFIG_REPAIR action' { [void](Remove-ObsoleteCatalogMetadata -Rows $remappedConfigRepairAction) } '*mapped to CONFIG_REPAIR*'

$disabledConfigRepairAction = New-Rows
$configAction = @($disabledConfigRepairAction['ops.Action'] | Where-Object { [string]$_['ActionCode'] -ceq 'CONFIG_REPAIR' })[0]
$configAction['IsEnabled'] = 0
Assert-Throws 'V8 retirement requires the CONFIG_REPAIR action to remain enabled' { [void](Remove-ObsoleteCatalogMetadata -Rows $disabledConfigRepairAction) } '*enabled ENGINE action*'

$missingConfigRepairEngine = New-Rows
$configEngine = @($missingConfigRepairEngine['ops.Engine'] | Where-Object { [string]$_['EngineCode'] -ceq 'CONFIG_REPAIR' })[0]
[void]$missingConfigRepairEngine['ops.Engine'].Remove($configEngine)
Assert-Throws 'V8 retirement requires the CONFIG_REPAIR engine' { [void](Remove-ObsoleteCatalogMetadata -Rows $missingConfigRepairEngine) } '*exactly one CONFIG_REPAIR engine*'
$disabledConfigRepairEngine = New-Rows
$configEngine = @($disabledConfigRepairEngine['ops.Engine'] | Where-Object { [string]$_['EngineCode'] -ceq 'CONFIG_REPAIR' })[0]
$configEngine['IsEnabled'] = 0
Assert-Throws 'V8 retirement requires the CONFIG_REPAIR engine to remain enabled' { [void](Remove-ObsoleteCatalogMetadata -Rows $disabledConfigRepairEngine) } '*engine must remain enabled*'

$missingConfigRepairStep = New-Rows
$configStep = @($missingConfigRepairStep['ops.ActionStep'] | Where-Object { [long]$_['StepOrder'] -eq 20 -and [string]$_['ChildActionCode'] -ceq 'CONFIG_REPAIR' })[0]
[void]$missingConfigRepairStep['ops.ActionStep'].Remove($configStep)
Assert-Throws 'V8 retirement requires FULL_DEPLOYMENT step 20 CONFIG_REPAIR' { [void](Remove-ObsoleteCatalogMetadata -Rows $missingConfigRepairStep) } '*step 20*CONFIG_REPAIR*'

$disabledConfigRepairStep = New-Rows
$configStep = @($disabledConfigRepairStep['ops.ActionStep'] | Where-Object { [long]$_['StepOrder'] -eq 20 -and [string]$_['ChildActionCode'] -ceq 'CONFIG_REPAIR' })[0]
$configStep['IsEnabled'] = 0
Assert-Throws 'V8 retirement requires FULL_DEPLOYMENT step 20 CONFIG_REPAIR to remain enabled' { [void](Remove-ObsoleteCatalogMetadata -Rows $disabledConfigRepairStep) } '*step 20*explicitly enabled*'

$rows = New-Rows
$result = Remove-ObsoleteCatalogMetadata -Rows $rows
Assert-That 'exactly the V8 action is removed' ($result.RemovedActionRows -eq 1 -and @($rows['ops.Action']).Count -eq 3)
Assert-That 'both retired engine rows are removed' ($result.RemovedEngineRows -eq 2 -and @($rows['ops.Engine']).Count -eq 3)
Assert-That 'FULL_DEPLOYMENT step 63 is removed' ($result.RemovedActionStepRows -eq 1 -and @($rows['ops.ActionStep']).Count -eq 3)
Assert-That 'DATABASE_SETTINGS action is retained and resolves to DATABASE_CONTENT_SYNC' (@($rows['ops.Action'] | Where-Object { $_['ActionCode'] -ceq 'DATABASE_SETTINGS' -and $_['EngineCode'] -ceq 'DATABASE_CONTENT_SYNC' }).Count -eq 1)
Assert-That 'FULL_DEPLOYMENT step 30 DATABASE_SETTINGS is retained' (@($rows['ops.ActionStep'] | Where-Object { $_['ParentActionCode'] -ceq 'FULL_DEPLOYMENT' -and [long]$_['StepOrder'] -eq 30 -and $_['ChildActionCode'] -ceq 'DATABASE_SETTINGS' }).Count -eq 1)
Assert-That 'CONFIG_REPAIR action is retained and executable' (@($rows['ops.Action'] | Where-Object { $_['ActionCode'] -ceq 'CONFIG_REPAIR' -and $_['EngineCode'] -ceq 'CONFIG_REPAIR' -and [int]$_['IsEnabled'] -eq 1 }).Count -eq 1)
Assert-That 'FULL_DEPLOYMENT step 20 CONFIG_REPAIR is retained and enabled' (@($rows['ops.ActionStep'] | Where-Object { $_['ParentActionCode'] -ceq 'FULL_DEPLOYMENT' -and [long]$_['StepOrder'] -eq 20 -and $_['ChildActionCode'] -ceq 'CONFIG_REPAIR' -and [int]$_['IsEnabled'] -eq 1 }).Count -eq 1)
Assert-That 'no retired action remains in filtered action rows' (@($rows['ops.Action'] | Where-Object { $_['ActionCode'] -ceq 'V8_KEYCLOAK_CONFIG' }).Count -eq 0)
Assert-That 'no retired engine remains in filtered engine rows' (@($rows['ops.Engine'] | Where-Object { $_['EngineCode'] -ceq 'V8_KEYCLOAK_CONFIG' -or $_['EngineCode'] -ceq 'DATABASE_SETTINGS' }).Count -eq 0)
Assert-That 'no retired action remains in filtered action steps' (@($rows['ops.ActionStep'] | Where-Object { $_['ChildActionCode'] -ceq 'V8_KEYCLOAK_CONFIG' -or $_['ParentActionCode'] -ceq 'V8_KEYCLOAK_CONFIG' }).Count -eq 0)

$badRows = New-Rows
$badRows['ops.Action'][0]['EngineCode'] = 'DATABASE_SETTINGS'
Assert-Throws 'DATABASE_SETTINGS action cannot regress to the retired legacy engine' { [void](Remove-ObsoleteCatalogMetadata -Rows $badRows) } '*still references retired engine*'

$missingAction = New-Rows
$databaseSettingsAction = @($missingAction['ops.Action'] | Where-Object { [string]$_['ActionCode'] -ceq 'DATABASE_SETTINGS' })[0]
[void]$missingAction['ops.Action'].Remove($databaseSettingsAction)
Assert-Throws 'FULL_DEPLOYMENT cannot silently lose the DATABASE_SETTINGS action' { [void](Remove-ObsoleteCatalogMetadata -Rows $missingAction) } '*exactly one DATABASE_SETTINGS action*'

$missingStep = New-Rows
$databaseSettingsStep = @($missingStep['ops.ActionStep'] | Where-Object { [long]$_['StepOrder'] -eq 30 -and [string]$_['ChildActionCode'] -ceq 'DATABASE_SETTINGS' })[0]
[void]$missingStep['ops.ActionStep'].Remove($databaseSettingsStep)
Assert-Throws 'FULL_DEPLOYMENT cannot silently lose step 30 DATABASE_SETTINGS' { [void](Remove-ObsoleteCatalogMetadata -Rows $missingStep) } '*step 30*DATABASE_SETTINGS*'

$productionMissingFullDeployment = New-Rows
$v8Action = @($productionMissingFullDeployment['ops.Action'] | Where-Object { [string]$_['ActionCode'] -ceq 'V8_KEYCLOAK_CONFIG' })[0]
[void]$productionMissingFullDeployment['ops.Action'].Remove($v8Action)
$v8Engine = @($productionMissingFullDeployment['ops.Engine'] | Where-Object { [string]$_['EngineCode'] -ceq 'V8_KEYCLOAK_CONFIG' })[0]
[void]$productionMissingFullDeployment['ops.Engine'].Remove($v8Engine)
foreach ($table in @($script:CarriedTables.Keys)) {
    if (-not $productionMissingFullDeployment.ContainsKey([string]$table)) {
        $productionMissingFullDeployment[[string]$table] = [System.Collections.Generic.List[object]]::new()
    }
}
$productionMissingFullDeployment['ops.ActionStep'] = [System.Collections.Generic.List[object]]::new()
Assert-Throws 'production source cannot silently lose the entire FULL_DEPLOYMENT surface' { [void](Remove-ObsoleteCatalogMetadata -Rows $productionMissingFullDeployment) } '*FULL_DEPLOYMENT*'

$unexpected = New-Rows
$unexpected['ops.ActionStep'].Add([ordered]@{ ParentActionCode='OTHER'; StepOrder=[long]99; ChildActionCode='V8_KEYCLOAK_CONFIG'; IsEnabled=0 })
Assert-Throws 'an unexpected second child reference to the retired V8 action fails closed' { [void](Remove-ObsoleteCatalogMetadata -Rows $unexpected) } '*retired action reference remains*'

$unexpectedParent = New-Rows
$unexpectedParent['ops.ActionStep'].Add([ordered]@{ ParentActionCode='V8_KEYCLOAK_CONFIG'; StepOrder=[long]10; ChildActionCode='KEEP_ACTION'; IsEnabled=0 })
Assert-Throws 'the retired V8 action cannot remain as a composite parent' { [void](Remove-ObsoleteCatalogMetadata -Rows $unexpectedParent) } '*retired action reference remains*'

$dependent = New-Rows
$dependent['ops.ActionRequirement'] = [System.Collections.Generic.List[object]]::new()
$dependent['ops.ActionRequirement'].Add([ordered]@{ ActionCode='V8_KEYCLOAK_CONFIG'; RequirementCode='R1' })
Assert-Throws 'dependent metadata for the retired V8 action fails closed instead of becoming orphaned' { [void](Remove-ObsoleteCatalogMetadata -Rows $dependent) } '*ops.ActionRequirement*'

$script:CarriedTables = [ordered]@{ 'ops.Action'='G'; 'ops.Engine'='G'; 'ops.ActionStep'='G' }
$schema = @{
    'ops.Action' = [pscustomobject]@{
        Table='ops.Action'
        Columns=@((New-Column 'ActionCode' 'varchar'), (New-Column 'EngineCode' 'varchar' $true))
        PrimaryKey=@('ActionCode')
    }
    'ops.Engine' = [pscustomobject]@{
        Table='ops.Engine'
        Columns=@((New-Column 'EngineCode' 'varchar'), (New-Column 'EngineVersion' 'varchar'))
        PrimaryKey=@('EngineCode')
    }
    'ops.ActionStep' = [pscustomobject]@{
        Table='ops.ActionStep'
        Columns=@((New-Column 'ParentActionCode' 'varchar'), (New-Column 'StepOrder' 'int'), (New-Column 'ChildActionCode' 'varchar'))
        PrimaryKey=@('ParentActionCode','StepOrder')
    }
}
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('obsolete-catalog-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $catalog = New-CatalogFile -Code 'TEST' -Schema $schema -Rows $rows -Folder $work -Sqlite3 $sqlite3 -SourceKind 'unit-test' -SourceRef 'obsolete-cleanup' -UseCodeCollation $false
    Assert-That 'exported catalog contains no V8 action' ((Invoke-Query $catalog.File "SELECT count(*) FROM ops_Action WHERE ActionCode='V8_KEYCLOAK_CONFIG';") -ceq '0')
    Assert-That 'exported catalog contains neither retired engine' ((Invoke-Query $catalog.File "SELECT count(*) FROM ops_Engine WHERE EngineCode IN ('V8_KEYCLOAK_CONFIG','DATABASE_SETTINGS');") -ceq '0')
    Assert-That 'exported catalog contains no FULL_DEPLOYMENT step 63' ((Invoke-Query $catalog.File "SELECT count(*) FROM ops_ActionStep WHERE ParentActionCode='FULL_DEPLOYMENT' AND StepOrder=63;") -ceq '0')
    Assert-That 'exported catalog keeps DATABASE_SETTINGS action mapped to DATABASE_CONTENT_SYNC' ((Invoke-Query $catalog.File "SELECT count(*) FROM ops_Action WHERE ActionCode='DATABASE_SETTINGS' AND EngineCode='DATABASE_CONTENT_SYNC';") -ceq '1')
    Assert-That 'exported catalog has no cfg_DatabaseSettingRule table' ((Invoke-Query $catalog.File "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='cfg_DatabaseSettingRule';") -ceq '0')
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ('Obsolete catalog metadata tests: {0} passed, {1} failed.' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
