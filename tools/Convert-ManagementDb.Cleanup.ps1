#requires -Version 7.0
# PR #59 cleanup layer. Loaded only after main's C7 and C1/C2 wrappers.
# Converter 0.5.0 / schema 2 / cut_rule_version 3 remain owned by main. Cleanup changes
# global retirement metadata, not machine cut assignment, and is versioned in the manifest.

$script:CleanupValidationTable = 'cfg.DatabaseSettingRule'
$script:CleanupRetirementVersion = 1
$script:CleanupMainReadSyncSchema = ${function:Read-SyncSchema}
$script:CleanupMainReadSyncRows = ${function:Read-SyncRows}
$script:CleanupMainReadSqlServerSource = ${function:Read-SqlServerSource}
$script:CleanupMainWriteConversionManifest = ${function:Write-ConversionManifest}
$script:CleanupRawReadSyncRows = $script:C7LegacyReadSyncRows
$script:CleanupRawReadSqlServerSource = $script:C7LegacyReadSqlServerSource

[void]$script:CarriedTables.Remove($script:CleanupValidationTable)
[void]$script:RedactionTables.Remove($script:CleanupValidationTable)
$script:CleanupProductionCarriedTables = @($script:CarriedTables.Keys)
function Set-CleanupFilteredRows {
    param(
        [Parameter(Mandatory)][hashtable]$Rows,
        [Parameter(Mandatory)][string]$Table,
        [Parameter(Mandatory)][scriptblock]$Keep
    )
    if (-not $Rows.ContainsKey($Table)) { return 0 }
    $kept = [System.Collections.Generic.List[object]]::new()
    $removed = 0
    foreach ($row in @($Rows[$Table])) {
        if (& $Keep $row) { $kept.Add($row) }
        else { $removed++ }
    }
    $Rows[$Table] = $kept
    return $removed
}

function Test-CleanupHasAction {
    param([Parameter(Mandatory)][hashtable]$Rows, [Parameter(Mandatory)][string]$ActionCode)
    if (-not $Rows.ContainsKey('ops.Action')) { return $false }
    return (@($Rows['ops.Action'] | Where-Object { [string]$_['ActionCode'] -ceq $ActionCode }).Count -gt 0)
}

function Test-CleanupProductionSourceSurface {
    param([Parameter(Mandatory)][hashtable]$Rows)
    foreach ($table in @($script:CleanupProductionCarriedTables)) {
        if (-not $Rows.ContainsKey([string]$table)) { return $false }
    }
    return $true
}

function Test-CleanupRowHasKey {
    param($Row, [Parameter(Mandatory)][string]$Key)
    if ($Row -is [System.Collections.IDictionary]) { return $Row.Contains($Key) }
    return ($null -ne $Row.PSObject.Properties[$Key])
}

function Test-CleanupIsNullValue {
    param($Value)
    return ($null -eq $Value -or $Value -is [System.DBNull])
}

function Get-CleanupLegacySettingUserValue {
    param($Value)
    if (Test-CleanupIsNullValue -Value $Value) { return '' }
    return [string]$Value
}

function Test-CleanupSqlEquivalentIdentifier {
    param($Value, [Parameter(Mandatory)][string]$Canonical)
    if (Test-CleanupIsNullValue -Value $Value) { return $false }
    $normalized = ([string]$Value).TrimEnd([char[]]@([char]0x20))
    return ($normalized -ieq $Canonical)
}

function Test-CleanupApprovedLegacyFilter {
    param(
        [string]$FilterClause,
        [string]$Application,
        $SettingUser,
        [string]$SectionName,
        [string]$SettingKey
    )
    if ([string]::IsNullOrWhiteSpace($FilterClause)) { return $false }

    $pattern = "^\s*(?:\[Application\]|Application)\s*=\s*N?'((?:''|[^'])*)'\s+AND\s+ISNULL\s*\(\s*\[User\]\s*,\s*N?'((?:''|[^'])*)'\s*\)\s*=\s*N?'((?:''|[^'])*)'\s+AND\s+(?:\[Section\]|Section)\s*=\s*N?'((?:''|[^'])*)'\s+AND\s+\[Key\]\s*=\s*N?'((?:''|[^'])*)'\s*$"
    $options = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    $match = [regex]::Match($FilterClause, $pattern, $options)
    if (-not $match.Success) { return $false }

    $actualApplication = $match.Groups[1].Value.Replace("''", "'")
    $actualNullReplacement = $match.Groups[2].Value.Replace("''", "'")
    $actualUser = $match.Groups[3].Value.Replace("''", "'")
    $actualSection = $match.Groups[4].Value.Replace("''", "'")
    $actualKey = $match.Groups[5].Value.Replace("''", "'")
    $expectedUser = Get-CleanupLegacySettingUserValue -Value $SettingUser
    return (
        $actualApplication -ceq $Application -and
        $actualNullReplacement -ceq '' -and
        $actualUser -ceq $expectedUser -and
        $actualSection -ceq $SectionName -and
        $actualKey -ceq $SettingKey
    )
}

function Test-CleanupApprovedLegacyInsertColumns {
    param(
        [string]$InsertColumnsJson,
        [string]$Application,
        [string]$SettingUser,
        [string]$SectionName,
        [string]$SettingKey
    )
    if ([string]::IsNullOrWhiteSpace($InsertColumnsJson)) { return $false }
    try { $parsed = $InsertColumnsJson | ConvertFrom-Json -ErrorAction Stop }
    catch { return $false }
    if ($null -eq $parsed -or $parsed -is [System.Array]) { return $false }

    $expected = [ordered]@{
        Application = $Application
        User = $SettingUser
        Section = $SectionName
        Key = $SettingKey
    }
    $properties = @($parsed.PSObject.Properties)
    if ($properties.Count -ne $expected.Count) { return $false }
    foreach ($name in $expected.Keys) {
        $match = @($properties | Where-Object { $_.Name -ceq $name })
        if ($match.Count -ne 1 -or [string]$match[0].Value -cne [string]$expected[$name]) { return $false }
    }
    return $true
}

function Assert-LegacyDatabaseSettingRulesEquivalent {
    param([Parameter(Mandatory)][hashtable]$Rows)

    if (-not (Test-CleanupHasAction -Rows $Rows -ActionCode 'DATABASE_SETTINGS')) { return }
    foreach ($required in @($script:CleanupValidationTable, 'cfg.DatabaseObjectSettingRule')) {
        if (-not $Rows.ContainsKey($required)) {
            throw ('Retirement validation requires source table {0}.' -f $required)
        }
    }

    $legacyRules = @($Rows[$script:CleanupValidationTable] | Where-Object { [int]$_['IsEnabled'] -eq 1 })
    if ($legacyRules.Count -eq 0) { throw 'Retirement validation found no enabled cfg.DatabaseSettingRule rows.' }

    foreach ($legacy in $legacyRules) {
        $code = [string]$legacy['SettingCode']
        $matches = @($Rows['cfg.DatabaseObjectSettingRule'] | Where-Object { [string]$_['SettingCode'] -ceq $code })
        if ($matches.Count -ne 1) {
            throw ('Legacy database-setting rule {0} must have exactly one DatabaseObjectSettingRule equivalent.' -f $code)
        }
        $replacement = $matches[0]
        foreach ($field in @('CountryCode', 'ExpectedTemplate', 'IsRequired', 'IsSensitive', 'IsEnabled')) {
            if ($legacy[$field] -cne $replacement[$field]) {
                throw ('Legacy database-setting rule {0} differs from its approved replacement ({1}).' -f $code, $field)
            }
        }
        if ([string]$replacement['TargetDatabaseName'] -cne 'sisqualWFM' -or
            [string]$replacement['TargetSchemaName'] -cne 'dbo' -or
            [string]$replacement['TargetTableName'] -cne [string]$legacy['TargetTable'] -or
            [string]$replacement['TargetColumnName'] -cne 'Value') {
            throw ('Legacy database-setting rule {0} differs from its approved replacement (target).' -f $code)
        }
        $legacyUser = Get-CleanupLegacySettingUserValue -Value $legacy['SettingUser']
        $filter = [string]$replacement['FilterClause']
        if (-not (Test-CleanupApprovedLegacyFilter -FilterClause $filter -Application ([string]$legacy['Application']) -SettingUser $legacyUser -SectionName ([string]$legacy['SectionName']) -SettingKey ([string]$legacy['SettingKey']))) {
            throw ('Legacy database-setting rule {0} differs from its approved replacement (filter).' -f $code)
        }
        if ([string]$replacement['RuleType'] -cne 'FULL_REPLACE') {
            throw ('Legacy database-setting rule {0} differs from its approved replacement (RuleType).' -f $code)
        }
        if ([int]$replacement['CreateIfMissing'] -ne 1) {
            throw ('Legacy database-setting rule {0} differs from its approved replacement (CreateIfMissing).' -f $code)
        }
        if (-not (Test-CleanupApprovedLegacyInsertColumns -InsertColumnsJson ([string]$replacement['InsertColumnsJson']) -Application ([string]$legacy['Application']) -SettingUser $legacyUser -SectionName ([string]$legacy['SectionName']) -SettingKey ([string]$legacy['SettingKey']))) {
            throw ('Legacy database-setting rule {0} differs from its approved replacement (InsertColumnsJson).' -f $code)
        }
    }
}

function Assert-V8KeycloakRetirementSafe {
    param([Parameter(Mandatory)][hashtable]$Rows)

    $hasV8Action = Test-CleanupHasAction -Rows $Rows -ActionCode 'V8_KEYCLOAK_CONFIG'
    $hasV8Engine = ($Rows.ContainsKey('ops.Engine') -and @($Rows['ops.Engine'] | Where-Object { [string]$_['EngineCode'] -ceq 'V8_KEYCLOAK_CONFIG' }).Count -gt 0)
    $retiredSteps = @()
    if ($Rows.ContainsKey('ops.ActionStep')) {
        $retiredSteps = @($Rows['ops.ActionStep'] | Where-Object {
            [string]$_['ParentActionCode'] -ceq 'FULL_DEPLOYMENT' -and
            [long]$_['StepOrder'] -eq 63 -and
            [string]$_['ChildActionCode'] -ceq 'V8_KEYCLOAK_CONFIG'
        })
    }
    $isProductionSurface = Test-CleanupProductionSourceSurface -Rows $Rows
    $hasRetiredV8Metadata = ($hasV8Action -or $hasV8Engine -or $retiredSteps.Count -gt 0)
    if (-not $hasRetiredV8Metadata -and -not $isProductionSurface) { return }

    foreach ($step in $retiredSteps) {
        if (-not (Test-CleanupRowHasKey -Row $step -Key 'IsEnabled')) {
            throw 'FULL_DEPLOYMENT step 63 -> V8_KEYCLOAK_CONFIG may be retired only while the source step remains explicitly disabled.'
        }
        $stepEnabled = $step['IsEnabled']
        if ((Test-CleanupIsNullValue -Value $stepEnabled) -or [int]$stepEnabled -ne 0) {
            throw 'FULL_DEPLOYMENT step 63 -> V8_KEYCLOAK_CONFIG may be retired only while the source step remains explicitly disabled.'
        }
    }

    foreach ($required in @('cfg.ConfigRule', 'cfg.ConfigFile', 'ops.Action', 'ops.ActionStep', 'ops.Engine')) {
        if (-not $Rows.ContainsKey($required)) {
            throw ('V8_KEYCLOAK_CONFIG retirement requires source table {0} to validate the executable CONFIG_REPAIR replacement path.' -f $required)
        }
    }

    $configRepairActions = @($Rows['ops.Action'] | Where-Object { [string]$_['ActionCode'] -ceq 'CONFIG_REPAIR' })
    if ($configRepairActions.Count -ne 1) {
        throw 'V8_KEYCLOAK_CONFIG retirement requires exactly one enabled CONFIG_REPAIR action.'
    }
    $configRepairAction = $configRepairActions[0]
    if ([string]$configRepairAction['ActionType'] -cne 'ENGINE' -or
        [string]$configRepairAction['EngineCode'] -cne 'CONFIG_REPAIR' -or
        -not (Test-CleanupRowHasKey -Row $configRepairAction -Key 'IsEnabled') -or
        (Test-CleanupIsNullValue -Value $configRepairAction['IsEnabled']) -or
        [int]$configRepairAction['IsEnabled'] -ne 1) {
        throw 'CONFIG_REPAIR must remain an enabled ENGINE action mapped to CONFIG_REPAIR before V8 retirement.'
    }
    if (-not (Test-CleanupRowHasKey -Row $configRepairAction -Key 'ModePolicy') -or
        (Test-CleanupIsNullValue -Value $configRepairAction['ModePolicy']) -or
        [string]$configRepairAction['ModePolicy'] -cne 'PREVIEW_APPLY') {
        throw 'CONFIG_REPAIR must retain its approved execution contract (ModePolicy=PREVIEW_APPLY) before V8 retirement.'
    }
    foreach ($field in @('RequiresInstanceSelection', 'AllowAllInstances', 'PassInstanceCode', 'PassApply')) {
        if (-not (Test-CleanupRowHasKey -Row $configRepairAction -Key $field) -or
            (Test-CleanupIsNullValue -Value $configRepairAction[$field]) -or
            [int]$configRepairAction[$field] -ne 1) {
            throw ('CONFIG_REPAIR must retain its approved execution contract ({0}=1) before V8 retirement.' -f $field)
        }
    }

    $configRepairEngines = @($Rows['ops.Engine'] | Where-Object { [string]$_['EngineCode'] -ceq 'CONFIG_REPAIR' })
    if ($configRepairEngines.Count -ne 1) {
        throw 'V8_KEYCLOAK_CONFIG retirement requires exactly one CONFIG_REPAIR engine.'
    }
    $configRepairEngine = $configRepairEngines[0]
    if (-not (Test-CleanupRowHasKey -Row $configRepairEngine -Key 'IsEnabled') -or
        (Test-CleanupIsNullValue -Value $configRepairEngine['IsEnabled']) -or
        [int]$configRepairEngine['IsEnabled'] -ne 1) {
        throw 'CONFIG_REPAIR engine must remain enabled before V8 retirement.'
    }

    $configRepairSteps = @($Rows['ops.ActionStep'] | Where-Object {
        [string]$_['ParentActionCode'] -ceq 'FULL_DEPLOYMENT' -and
        [long]$_['StepOrder'] -eq 20 -and
        [string]$_['ChildActionCode'] -ceq 'CONFIG_REPAIR'
    })
    if ($configRepairSteps.Count -ne 1) {
        throw 'V8_KEYCLOAK_CONFIG retirement requires FULL_DEPLOYMENT step 20 -> CONFIG_REPAIR.'
    }
    $configRepairStep = $configRepairSteps[0]
    if (-not (Test-CleanupRowHasKey -Row $configRepairStep -Key 'IsEnabled') -or
        (Test-CleanupIsNullValue -Value $configRepairStep['IsEnabled']) -or
        [int]$configRepairStep['IsEnabled'] -ne 1) {
        throw 'FULL_DEPLOYMENT step 20 -> CONFIG_REPAIR must remain explicitly enabled before V8 retirement.'
    }

    $rules = @($Rows['cfg.ConfigRule'] | Where-Object { [string]$_['RuleCode'] -ceq 'KEYCLOAK_DB_URL' })
    if ($rules.Count -ne 1) {
        throw 'V8_KEYCLOAK_CONFIG retirement requires exactly one approved KEYCLOAK_DB_URL replacement rule.'
    }
    $rule = $rules[0]
    if (-not (Test-CleanupRowHasKey -Row $rule -Key 'CountryCode') -or -not (Test-CleanupIsNullValue -Value $rule['CountryCode'])) {
        throw 'KEYCLOAK_DB_URL differs from the approved V8 retirement replacement (CountryCode must remain global/NULL).'
    }
    $approvedStrings = [ordered]@{
        Category = 'KEYCLOAK'
        SelectorType = 'TEXT_REGEX'
        Selector = 'db-url=jdbc:sqlserver://[^\r\n]+'
        ExpectedTemplate = 'db-url=jdbc:sqlserver://{SQL_INSTANCE_ESCAPED};databaseName=sisqualKeycloak;integratedSecurity=true;multipleActiveResultSets=true;encrypt=true;trustServerCertificate=true;loginTimeout=15;'
        ValidationType = 'EXACT'
        Severity = 'ERROR'
        RepairAction = 'SET_VALUE'
        RepairValueType = 'STRING'
        RepairGroup = 'KEYCLOAK'
    }
    foreach ($field in $approvedStrings.Keys) {
        if ([string]$rule[$field] -cne [string]$approvedStrings[$field]) {
            throw ('KEYCLOAK_DB_URL differs from the approved V8 retirement replacement ({0}).' -f $field)
        }
    }
    $approvedNumbers = [ordered]@{
        IsRequired = 1
        AllowEncrypted = 0
        IsSensitive = 0
        IsEnabled = 1
        RepairOrder = 10
        CreateIfMissing = 0
    }
    foreach ($field in $approvedNumbers.Keys) {
        if (-not (Test-CleanupRowHasKey -Row $rule -Key $field)) {
            throw ('KEYCLOAK_DB_URL differs from the approved V8 retirement replacement ({0}).' -f $field)
        }
        $value = $rule[$field]
        if ((Test-CleanupIsNullValue -Value $value) -or [int]$value -ne [int]$approvedNumbers[$field]) {
            throw ('KEYCLOAK_DB_URL differs from the approved V8 retirement replacement ({0}).' -f $field)
        }
    }

    if (-not (Test-CleanupRowHasKey -Row $rule -Key 'FileID') -or (Test-CleanupIsNullValue -Value $rule['FileID'])) {
        throw 'KEYCLOAK_DB_URL differs from the approved V8 retirement replacement (FileID).'
    }
    $files = @($Rows['cfg.ConfigFile'] | Where-Object { [long]$_['FileID'] -eq [long]$rule['FileID'] })
    if ($files.Count -ne 1) {
        throw 'KEYCLOAK_DB_URL must resolve to exactly one approved Keycloak configuration file.'
    }
    $file = $files[0]
    if ([string]$file['ApplicationCode'] -cne 'KEYCLOAK' -or
        [string]$file['RelativePath'] -cne 'conf\keycloak.conf' -or
        [string]$file['FileFormat'] -cne 'TEXT' -or
        [int]$file['IsRequired'] -ne 1 -or
        [int]$file['IsEnabled'] -ne 1) {
        throw 'KEYCLOAK_DB_URL no longer targets the approved enabled KEYCLOAK conf\keycloak.conf file.'
    }

    if ($isProductionSurface) {
        foreach ($required in @('cfg.Application', 'cfg.ConfigFileRepairPolicy')) {
            if (-not $Rows.ContainsKey($required)) {
                throw ('V8_KEYCLOAK_CONFIG retirement requires source table {0} to validate the Keycloak CONFIG_REPAIR target.' -f $required)
            }
        }

        $applications = @($Rows['cfg.Application'] | Where-Object { [string]$_['ApplicationCode'] -ceq 'KEYCLOAK' })
        if ($applications.Count -ne 1) {
            throw 'V8_KEYCLOAK_CONFIG retirement requires exactly one approved KEYCLOAK application.'
        }
        $application = $applications[0]
        if (-not (Test-CleanupRowHasKey -Row $application -Key 'IsEnabled') -or
            (Test-CleanupIsNullValue -Value $application['IsEnabled']) -or
            [int]$application['IsEnabled'] -ne 1 -or
            [string]$application['PhysicalPathTemplate'] -cne '{INSTANCE_ROOT}\V8\sisqualKeycloak') {
            throw 'KEYCLOAK application must remain enabled with PhysicalPathTemplate {INSTANCE_ROOT}\V8\sisqualKeycloak before V8 retirement.'
        }

        $activePolicies = @($Rows['cfg.ConfigFileRepairPolicy'] | Where-Object {
            [long]$_['FileID'] -eq [long]$rule['FileID'] -and
            (Test-CleanupRowHasKey -Row $_ -Key 'IsEnabled') -and
            -not (Test-CleanupIsNullValue -Value $_['IsEnabled']) -and
            [int]$_['IsEnabled'] -eq 1
        })
        if ($activePolicies.Count -gt 1) {
            throw 'KEYCLOAK configuration file must have at most one enabled repair policy before V8 retirement.'
        }
        if ($activePolicies.Count -eq 1 -and [string]$activePolicies[0]['RepairMode'] -cne 'PATCH') {
            throw 'KEYCLOAK configuration file must retain effective PATCH repair behavior before V8 retirement.'
        }
    }
}

function Assert-NoRetiredCatalogMetadata {
    param([Parameter(Mandatory)][hashtable]$Rows)

    $databaseSettingsActions = @()
    $fullDeploymentActions = @()
    if ($Rows.ContainsKey('ops.Action')) {
        $databaseSettingsActions = @($Rows['ops.Action'] | Where-Object { [string]$_['ActionCode'] -ceq 'DATABASE_SETTINGS' })
        $fullDeploymentActions = @($Rows['ops.Action'] | Where-Object { [string]$_['ActionCode'] -ceq 'FULL_DEPLOYMENT' })
        foreach ($row in @($Rows['ops.Action'])) {
            $action = [string]$row['ActionCode']
            $engine = [string]$row['EngineCode']
            if (Test-CleanupSqlEquivalentIdentifier -Value $action -Canonical 'V8_KEYCLOAK_CONFIG') { throw 'Retired action V8_KEYCLOAK_CONFIG remains after cleanup.' }
            if ((Test-CleanupSqlEquivalentIdentifier -Value $engine -Canonical 'V8_KEYCLOAK_CONFIG') -or
                (Test-CleanupSqlEquivalentIdentifier -Value $engine -Canonical 'DATABASE_SETTINGS')) {
                throw ('Action {0} still references retired engine {1}.' -f $action, $engine)
            }
        }
    }

    if ($Rows.ContainsKey('ops.Engine')) {
        foreach ($row in @($Rows['ops.Engine'])) {
            $engine = [string]$row['EngineCode']
            if ((Test-CleanupSqlEquivalentIdentifier -Value $engine -Canonical 'V8_KEYCLOAK_CONFIG') -or
                (Test-CleanupSqlEquivalentIdentifier -Value $engine -Canonical 'DATABASE_SETTINGS')) {
                throw ('Retired engine {0} remains after cleanup.' -f $engine)
            }
        }
    }

    $fullDeploymentSteps = @()
    if ($Rows.ContainsKey('ops.ActionStep')) {
        $fullDeploymentSteps = @($Rows['ops.ActionStep'] | Where-Object { [string]$_['ParentActionCode'] -ceq 'FULL_DEPLOYMENT' })
        foreach ($row in @($Rows['ops.ActionStep'])) {
            if ((Test-CleanupSqlEquivalentIdentifier -Value $row['ChildActionCode'] -Canonical 'V8_KEYCLOAK_CONFIG') -or
                (Test-CleanupSqlEquivalentIdentifier -Value $row['ParentActionCode'] -Canonical 'V8_KEYCLOAK_CONFIG')) {
                throw ('Retired action reference remains in ops.ActionStep at {0}/{1}.' -f $row['ParentActionCode'], $row['StepOrder'])
            }
        }
    }

    $isProductionSurface = Test-CleanupProductionSourceSurface -Rows $Rows
    if ($isProductionSurface -and $fullDeploymentActions.Count -ne 1) {
        throw 'Portable production orchestration requires exactly one FULL_DEPLOYMENT action.'
    }
    $hasFullDeploymentContext = ($isProductionSurface -or $fullDeploymentSteps.Count -gt 0 -or $fullDeploymentActions.Count -gt 0)
    if ($hasFullDeploymentContext) {
        if ($databaseSettingsActions.Count -ne 1) {
            throw 'Portable orchestration requires exactly one DATABASE_SETTINGS action.'
        }
        $databaseSettingsAction = $databaseSettingsActions[0]
        if ([string]$databaseSettingsAction['EngineCode'] -cne 'DATABASE_CONTENT_SYNC') {
            throw 'DATABASE_SETTINGS must continue to resolve to DATABASE_CONTENT_SYNC.'
        }
        if (-not (Test-CleanupRowHasKey -Row $databaseSettingsAction -Key 'IsEnabled') -or
            (Test-CleanupIsNullValue -Value $databaseSettingsAction['IsEnabled']) -or
            [int]$databaseSettingsAction['IsEnabled'] -ne 1) {
            throw 'DATABASE_SETTINGS must remain explicitly enabled after retirement.'
        }
        if (-not $Rows.ContainsKey('ops.Engine')) {
            throw 'Portable orchestration requires exactly one enabled DATABASE_CONTENT_SYNC engine.'
        }
        $databaseContentSyncEngines = @($Rows['ops.Engine'] | Where-Object { [string]$_['EngineCode'] -ceq 'DATABASE_CONTENT_SYNC' })
        if ($databaseContentSyncEngines.Count -ne 1) {
            throw 'Portable orchestration requires exactly one enabled DATABASE_CONTENT_SYNC engine.'
        }
        $databaseContentSyncEngine = $databaseContentSyncEngines[0]
        if (-not (Test-CleanupRowHasKey -Row $databaseContentSyncEngine -Key 'IsEnabled') -or
            (Test-CleanupIsNullValue -Value $databaseContentSyncEngine['IsEnabled']) -or
            [int]$databaseContentSyncEngine['IsEnabled'] -ne 1) {
            throw 'DATABASE_CONTENT_SYNC engine must remain explicitly enabled after retirement.'
        }
        $step30 = @($fullDeploymentSteps | Where-Object { [long]$_['StepOrder'] -eq 30 -and [string]$_['ChildActionCode'] -ceq 'DATABASE_SETTINGS' })
        if ($step30.Count -ne 1) {
            throw 'Portable orchestration requires FULL_DEPLOYMENT step 30 -> DATABASE_SETTINGS.'
        }
        if (-not (Test-CleanupRowHasKey -Row $step30[0] -Key 'IsEnabled') -or
            (Test-CleanupIsNullValue -Value $step30[0]['IsEnabled']) -or
            [int]$step30[0]['IsEnabled'] -ne 1) {
            throw 'FULL_DEPLOYMENT step 30 -> DATABASE_SETTINGS must remain explicitly enabled after retirement.'
        }
    }

    foreach ($table in @('app.ActionRuntimePolicy', 'cfg.ConfigurationAdapterDefinition', 'ops.ActionRequirement', 'ops.ActionUiMetadata')) {
        if (-not $Rows.ContainsKey($table)) { continue }
        foreach ($row in @($Rows[$table])) {
            if (Test-CleanupSqlEquivalentIdentifier -Value $row['ActionCode'] -Canonical 'V8_KEYCLOAK_CONFIG') {
                throw ('Retired action reference remains in {0}.' -f $table)
            }
        }
    }
}

function Remove-ObsoleteCatalogMetadata {
    param([Parameter(Mandatory)][hashtable]$Rows)

    Assert-V8KeycloakRetirementSafe -Rows $Rows

    $removedAction = Set-CleanupFilteredRows -Rows $Rows -Table 'ops.Action' -Keep {
        param($row)
        return ([string]$row['ActionCode'] -cne 'V8_KEYCLOAK_CONFIG')
    }
    $removedEngine = Set-CleanupFilteredRows -Rows $Rows -Table 'ops.Engine' -Keep {
        param($row)
        $code = [string]$row['EngineCode']
        return ($code -cne 'V8_KEYCLOAK_CONFIG' -and $code -cne 'DATABASE_SETTINGS')
    }
    $removedStep = Set-CleanupFilteredRows -Rows $Rows -Table 'ops.ActionStep' -Keep {
        param($row)
        $isRetiredStep = ([string]$row['ParentActionCode'] -ceq 'FULL_DEPLOYMENT' -and [long]$row['StepOrder'] -eq 63 -and [string]$row['ChildActionCode'] -ceq 'V8_KEYCLOAK_CONFIG')
        return (-not $isRetiredStep)
    }

    Assert-NoRetiredCatalogMetadata -Rows $Rows
    return [pscustomobject]@{
        Rows = $Rows
        RemovedActionRows = $removedAction
        RemovedEngineRows = $removedEngine
        RemovedActionStepRows = $removedStep
    }
}
function Read-SyncSchema {
    param([string]$Text, [string[]]$Tables)
    $readTables = [System.Collections.Generic.List[string]]::new()
    foreach ($table in @($Tables)) { if (-not $readTables.Contains($table)) { $readTables.Add($table) } }
    if (-not $readTables.Contains($script:CleanupValidationTable)) { $readTables.Add($script:CleanupValidationTable) }
    return (& $script:CleanupMainReadSyncSchema -Text $Text -Tables $readTables.ToArray())
}

function Read-SyncRows {
    param([string]$Text, [hashtable]$Schema)
    # Mandatory order: validate the executable legacy SQL predicate on raw source rows first.
    $rawRows = & $script:CleanupRawReadSyncRows -Text $Text -Schema $Schema
    Assert-LegacyDatabaseSettingRulesEquivalent -Rows $rawRows

    # Then execute main's already-composed C7 + C1/C2 row layer and apply retirement last.
    $rows = & $script:CleanupMainReadSyncRows -Text $Text -Schema $Schema
    $rows = (Remove-ObsoleteCatalogMetadata -Rows $rows).Rows
    [void]$rows.Remove($script:CleanupValidationTable)
    [void]$Schema.Remove($script:CleanupValidationTable)
    return $rows
}

function Read-SqlServerSource {
    param([string]$Instance, [string]$DatabaseName, [string]$ClientPath, [string[]]$Tables, [switch]$TrustCertificate)
    $readTables = [System.Collections.Generic.List[string]]::new()
    foreach ($table in @($Tables)) { if (-not $readTables.Contains($table)) { $readTables.Add($table) } }
    if (-not $readTables.Contains($script:CleanupValidationTable)) { $readTables.Add($script:CleanupValidationTable) }

    # Raw preflight is deliberately below C7. The derived directory is not a SQL source table.
    $rawTables = @($readTables.ToArray() | Where-Object { $_ -cne 'cfg.LinksPageDirectory' })
    $raw = & $script:CleanupRawReadSqlServerSource -Instance $Instance -DatabaseName $DatabaseName -ClientPath $ClientPath -Tables $rawTables -TrustCertificate:$TrustCertificate
    Assert-LegacyDatabaseSettingRulesEquivalent -Rows $raw.Rows

    # Main's composed reader runs next (C7, then C1/C2); cleanup is the final layer.
    $source = & $script:CleanupMainReadSqlServerSource -Instance $Instance -DatabaseName $DatabaseName -ClientPath $ClientPath -Tables $readTables.ToArray() -TrustCertificate:$TrustCertificate
    $source.Rows = (Remove-ObsoleteCatalogMetadata -Rows $source.Rows).Rows
    [void]$source.Rows.Remove($script:CleanupValidationTable)
    [void]$source.Schema.Remove($script:CleanupValidationTable)
    return $source
}

function Write-ConversionManifest {
    param([string]$Folder, [string]$Mode, [string]$BuiltAtUtc, [hashtable]$SourceInfo, [bool]$UseCodeCollation, $Entries, [hashtable]$Extra = @{})
    $merged = @{}
    foreach ($key in $Extra.Keys) { $merged[$key] = $Extra[$key] }
    $merged['excludedTableCount'] = 56
    $merged['retiredCatalogMetadata'] = [ordered]@{
        version = $script:CleanupRetirementVersion
        excludedSourceTable = 'cfg.DatabaseSettingRule'
        removedActionCode = 'V8_KEYCLOAK_CONFIG'
        removedEngineCodes = @('DATABASE_SETTINGS', 'V8_KEYCLOAK_CONFIG')
        removedFullDeploymentStep = 63
        databaseSettingsActionEngine = 'DATABASE_CONTENT_SYNC'
    }
    return (& $script:CleanupMainWriteConversionManifest -Folder $Folder -Mode $Mode -BuiltAtUtc $BuiltAtUtc -SourceInfo $SourceInfo -UseCodeCollation $UseCodeCollation -Entries $Entries -Extra $merged)
}
