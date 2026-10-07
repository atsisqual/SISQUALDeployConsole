#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'Convert-ManagementDb.ps1')).Path
$fixturePath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'Fixtures' 'legacy-database-setting-rule-shapes.json')).Path
. $toolPath -SyncFile 'unused' -OutputFolder 'unused' -Sqlite3Path 'unused'

$fixture = Get-Content -LiteralPath $fixturePath -Raw | ConvertFrom-Json
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
function Escape-SqlLiteral {
    param([string]$Value)
    return $Value.Replace("'", "''")
}
function New-FixtureRows {
    $rows = @{}
    $rows['ops.Action'] = [System.Collections.Generic.List[object]]::new()
    $rows['ops.Action'].Add([ordered]@{ ActionCode='DATABASE_SETTINGS'; EngineCode='DATABASE_CONTENT_SYNC'; IsEnabled=1 })
    $rows['cfg.DatabaseSettingRule'] = [System.Collections.Generic.List[object]]::new()
    $rows['cfg.DatabaseObjectSettingRule'] = [System.Collections.Generic.List[object]]::new()

    for ($i = 1; $i -le [int]$fixture.enabledLegacyRuleCount; $i++) {
        $code = ('LEGACY_SHAPE_{0:D2}' -f $i)
        $application = ('APP_{0:D2}' -f $i)
        $section = ('SECTION_{0:D2}' -f $i)
        $key = ('KEY_{0:D2}' -f $i)
        $settingUser = if (($i % 2) -eq 0) { $null } else { '' }
        $expectedUser = ''
        $expectedTemplate = ('VALUE_{0:D2}' -f $i)

        $rows['cfg.DatabaseSettingRule'].Add([ordered]@{
            SettingCode=$code; CountryCode=$null; Application=$application; SettingUser=$settingUser
            SectionName=$section; SettingKey=$key; ExpectedTemplate=$expectedTemplate
            IsRequired=1; IsSensitive=0; IsEnabled=1; TargetTable='Settings'
        })
        $filter = "Application='$(Escape-SqlLiteral $application)' AND ISNULL([User],N'')='$(Escape-SqlLiteral $expectedUser)' AND Section='$(Escape-SqlLiteral $section)' AND [Key]='$(Escape-SqlLiteral $key)'"
        $insert = [ordered]@{ Application=$application; User=$expectedUser; Section=$section; Key=$key } | ConvertTo-Json -Compress
        $rows['cfg.DatabaseObjectSettingRule'].Add([ordered]@{
            SettingCode=$code; CountryCode=$null; TargetDatabaseName='sisqualWFM'; TargetSchemaName='dbo'
            TargetTableName='Settings'; TargetColumnName='Value'; ExpectedTemplate=$expectedTemplate
            IsRequired=1; IsSensitive=0; IsEnabled=1; FilterClause=$filter
            RuleType='FULL_REPLACE'; CreateIfMissing=1; InsertColumnsJson=$insert
        })
    }
    return $rows
}

Assert-That 'fixture models exactly 14 enabled legacy rules' ([int]$fixture.enabledLegacyRuleCount -eq 14)
Assert-That 'fixture declares raw-source validation before structured conversion' ([string]$fixture.validationStage -ceq 'raw-source-before-structured-filter-conversion')

$rows = New-FixtureRows
Assert-That 'synthetic structure materializes all 14 legacy/replacement pairs' (@($rows['cfg.DatabaseSettingRule']).Count -eq 14 -and @($rows['cfg.DatabaseObjectSettingRule']).Count -eq 14)
Assert-DoesNotThrow 'cleanup equivalence accepts all 14 four-term structural pairs, including NULL/empty SettingUser' {
    Assert-LegacyDatabaseSettingRulesEquivalent -Rows $rows
    [void](Remove-ObsoleteCatalogMetadata -Rows $rows)
    [void]$rows.Remove($script:CleanupValidationTable)
}
Assert-That 'cleanup removes the validation-only legacy table from the synthetic portable surface' (-not $rows.ContainsKey($script:CleanupValidationTable))

$badApplication = New-FixtureRows
$badApplication['cfg.DatabaseObjectSettingRule'][0]['FilterClause'] = "Application='OTHER' AND ISNULL([User],N'')='' AND Section='SECTION_01' AND [Key]='KEY_01'"
Assert-Throws 'four-term equivalence rejects a changed Application term' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $badApplication } '*approved replacement (filter)*'

$badUser = New-FixtureRows
$badUser['cfg.DatabaseObjectSettingRule'][0]['FilterClause'] = "Application='APP_01' AND ISNULL([User],N'')='OTHER' AND Section='SECTION_01' AND [Key]='KEY_01'"
Assert-Throws 'four-term equivalence rejects a User term that differs from SettingUser' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $badUser } '*approved replacement (filter)*'

$badNullReplacement = New-FixtureRows
$badNullReplacement['cfg.DatabaseObjectSettingRule'][0]['FilterClause'] = "Application='APP_01' AND ISNULL([User],N'OTHER')='' AND Section='SECTION_01' AND [Key]='KEY_01'"
Assert-Throws 'four-term equivalence requires the approved empty User null replacement' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $badNullReplacement } '*approved replacement (filter)*'
$unbracketedUser = New-FixtureRows
$unbracketedUser['cfg.DatabaseObjectSettingRule'][0]['FilterClause'] = "Application='APP_01' AND ISNULL(User,N'')='' AND Section='SECTION_01' AND [Key]='KEY_01'"
Assert-Throws 'four-term equivalence rejects unbracketed reserved User identifier' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $unbracketedUser } '*approved replacement (filter)*'

$unbracketedKey = New-FixtureRows
$unbracketedKey['cfg.DatabaseObjectSettingRule'][0]['FilterClause'] = "Application='APP_01' AND ISNULL([User],N'')='' AND Section='SECTION_01' AND Key='KEY_01'"
Assert-Throws 'four-term equivalence rejects unbracketed reserved Key identifier' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $unbracketedKey } '*approved replacement (filter)*'

$legacyTwoTerm = New-FixtureRows
$legacyTwoTerm['cfg.DatabaseObjectSettingRule'][0]['FilterClause'] = "[Section]='SECTION_01' AND [Key]='KEY_01'"
Assert-Throws 'old synthetic two-term filter is not accepted as equivalent' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $legacyTwoTerm } '*approved replacement (filter)*'

$reordered = New-FixtureRows
$reordered['cfg.DatabaseObjectSettingRule'][0]['FilterClause'] = "Section='SECTION_01' AND Application='APP_01' AND ISNULL([User],N'')='' AND [Key]='KEY_01'"
Assert-Throws 'four-term filter order remains fail-closed' { Assert-LegacyDatabaseSettingRulesEquivalent -Rows $reordered } '*approved replacement (filter)*'

Write-Host ('Legacy database-setting shape tests: {0} passed, {1} failed.' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
