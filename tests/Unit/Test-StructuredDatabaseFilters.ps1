#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolPath = Join-Path $PSScriptRoot '..' '..' 'tools' 'Convert-ManagementDb.ps1'
. $toolPath -SyncFile 'unused' -OutputFolder 'unused' -Sqlite3Path 'unused'

$script:Passed = 0
$script:Failures = 0
function Assert-That {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) }
    else { $script:Failures++; Write-Host ('FAIL  {0}' -f $Name) }
}
function Assert-Throws {
    param([string]$Name, [scriptblock]$Block, [string]$Like = '*')
    $threw = $false
    $message = ''
    try { & $Block } catch { $threw = $true; $message = $_.Exception.Message }
    Assert-That $Name ($threw -and $message -like $Like)
}
function Get-Object {
    param([AllowNull()][string]$Filter, [string]$Code = 'TEST')
    return ((ConvertTo-StructuredDatabaseFilterJson -FilterClause $Filter -RuleCode $Code) | ConvertFrom-Json -AsHashtable)
}
function Assert-TextTerm {
    param($Term, [string]$Column, [string]$Value, [string]$Name)
    Assert-That $Name ($Term.column -ceq $Column -and $Term.operator -ceq 'EQ' -and $Term.value.kind -ceq 'LITERAL' -and $Term.value.type -ceq 'TEXT' -and $Term.value.value -ceq $Value)
}

Assert-That 'C7 tool version is active' ($script:ToolVersion -ceq '0.4.0' -and $script:SchemaVersion -eq 2 -and $script:CutRuleVersion -eq 2)

# Snapshot reconciliation: seven cfg.DatabaseObjectSettingRule rows exist in the approved baseline.
# Three sisqualVIEW rules are intentionally unfiltered.
foreach ($code in @(
    'SISQUAL_VIEW_DATASOURCE_CONNECTION',
    'SISQUAL_VIEW_REPORT_DEFAULT_CONNECTION',
    'SISQUAL_VIEW_REPORT_DEFAULT_WFM_DATABASE'
)) {
    $all = Get-Object $null $code
    Assert-That ("snapshot {0}: no filter becomes explicit ALL" -f $code) ($all.kind -ceq 'ALL' -and $all.Count -eq 1)
}
$blank = Get-Object '   ' 'BLANK'
Assert-That 'blank filter becomes explicit ALL' ($blank.kind -ceq 'ALL')

# The four populated FilterClause values from the approved snapshot.
$login = Get-Object "Aplicacao='SisqualPonto' AND Seccao='Parametros' AND Chave='LanguageLogin'" 'SISQUALPONTO_LANGUAGE_LOGIN'
Assert-That 'snapshot login filter has exactly three AND terms' ($login.kind -ceq 'AND' -and $login.terms.Count -eq 3)
Assert-TextTerm $login.terms[0] 'Aplicacao' 'SisqualPonto' 'snapshot login Aplicacao'
Assert-TextTerm $login.terms[1] 'Seccao' 'Parametros' 'snapshot login Seccao'
Assert-TextTerm $login.terms[2] 'Chave' 'LanguageLogin' 'snapshot login Chave'

$translation = Get-Object "Aplicacao='SisqualPonto' AND Seccao='Parametros' AND Chave='LanguageTranslation'" 'SISQUALPONTO_LANGUAGE_TRANSLATION'
Assert-That 'snapshot translation filter has exactly three AND terms' ($translation.kind -ceq 'AND' -and $translation.terms.Count -eq 3)
Assert-TextTerm $translation.terms[0] 'Aplicacao' 'SisqualPonto' 'snapshot translation Aplicacao'
Assert-TextTerm $translation.terms[1] 'Seccao' 'Parametros' 'snapshot translation Seccao'
Assert-TextTerm $translation.terms[2] 'Chave' 'LanguageTranslation' 'snapshot translation Chave'

$paperless = Get-Object "Aplicacao='sisqualPAPERLESS' AND Seccao='Geral' AND Chave='LanguageID'" 'PAPERLESS_LANGUAGE_ID'
Assert-That 'snapshot paperless filter has exactly three AND terms' ($paperless.kind -ceq 'AND' -and $paperless.terms.Count -eq 3)
Assert-TextTerm $paperless.terms[0] 'Aplicacao' 'sisqualPAPERLESS' 'snapshot paperless Aplicacao'
Assert-TextTerm $paperless.terms[1] 'Seccao' 'Geral' 'snapshot paperless Seccao'
Assert-TextTerm $paperless.terms[2] 'Chave' 'LanguageID' 'snapshot paperless Chave'

$dashboards = Get-Object "id='AD704BE6-AE67-43E3-BDB2-A89AEEEA2900'" 'DASHBOARDS_DATA_CONNECTION'
Assert-That 'snapshot dashboards filter has exactly one term' ($dashboards.kind -ceq 'AND' -and $dashboards.terms.Count -eq 1)
Assert-TextTerm $dashboards.terms[0] 'id' 'AD704BE6-AE67-43E3-BDB2-A89AEEEA2900' 'snapshot dashboards id'

# Syntax details retained because they are safe variants of the approved equality-only grammar.
$bracketed = Get-Object "[Aplicacao]=N'SisqualPonto' AND [Chave]='LanguageLogin'"
Assert-That 'bracketed identifiers and N-prefixed strings are accepted' ($bracketed.terms.Count -eq 2 -and $bracketed.terms[0].column -ceq 'Aplicacao' -and $bracketed.terms[0].value.value -ceq 'SisqualPonto')
$escaped = Get-Object "A='it''s exact'"
Assert-That 'doubled single quote decodes once' ($escaped.terms[0].value.value -ceq "it's exact")
$numeric = Get-Object 'A=3 AND B=-4.50'
Assert-That 'numeric literals stay invariant text' ($numeric.terms[0].value.type -ceq 'NUMBER' -and $numeric.terms[0].value.value -ceq '3' -and $numeric.terms[1].value.value -ceq '-4.50')

# Fail closed outside the approved equality + AND grammar.
Assert-Throws 'OR is rejected' { Get-Object "A='x' OR B='y'" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'LIKE is rejected' { Get-Object "A LIKE 'x%'" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'not-equal is rejected' { Get-Object "A<>'x'" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'function expression is rejected' { Get-Object "LOWER(A)='x'" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'IN is rejected' { Get-Object "A IN ('x','y')" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'SELECT lookup is rejected' { Get-Object "A=(SELECT ID FROM T WHERE B='x')" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'parenthesized expression is rejected' { Get-Object "(A='x')" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'statement terminator is rejected' { Get-Object "A='x'; SELECT 1" | Out-Null } '*outside the supported predicate grammar*'
Assert-Throws 'line comment is rejected' { Get-Object "A='x' --comment" | Out-Null } '*outside the supported predicate grammar*'
Assert-Throws 'block comment is rejected' { Get-Object "A='x' /*comment*/" | Out-Null } '*outside the supported predicate grammar*'
Assert-Throws 'trailing tokens are rejected' { Get-Object "A='x' SELECT 1" | Out-Null } '*cannot be converted safely*'

$row = [ordered]@{ ObjectSettingRuleID = 7; SettingCode = 'SISQUALPONTO_LANGUAGE_LOGIN'; FilterClause = "Aplicacao='SisqualPonto' AND Seccao='Parametros' AND Chave='LanguageLogin'"; ExpectedTemplate = '{HOST_NAME}' }
$converted = Convert-DatabaseObjectSettingRuleForCatalog -Row $row
Assert-That 'catalog row drops raw FilterClause' (-not $converted.Contains('FilterClause'))
Assert-That 'catalog row adds FilterPredicateJson' ($converted.Contains('FilterPredicateJson') -and ([string]$converted['FilterPredicateJson']).StartsWith('{"kind":"AND"'))
$roundTrip = ([string]$converted['FilterPredicateJson']) | ConvertFrom-Json -AsHashtable
Assert-That 'catalog row JSON round-trips the real snapshot predicate' ($roundTrip.terms.Count -eq 3 -and $roundTrip.terms[2].value.value -ceq 'LanguageLogin')

$schema = [pscustomobject]@{
    Table = 'cfg.DatabaseObjectSettingRule'
    PrimaryKey = @('ObjectSettingRuleID')
    Columns = @(
        [pscustomobject]@{ Name = 'ObjectSettingRuleID'; Type = 'int'; Length = 0; Precision = 0; Scale = 0; Identity = $true; Nullable = $false },
        [pscustomobject]@{ Name = 'SettingCode'; Type = 'varchar'; Length = 100; Precision = 0; Scale = 0; Identity = $false; Nullable = $false },
        [pscustomobject]@{ Name = 'FilterClause'; Type = 'nvarchar'; Length = -1; Precision = 0; Scale = 0; Identity = $false; Nullable = $true }
    )
}
$columns = @(Get-CarriedColumns -Table 'cfg.DatabaseObjectSettingRule' -TableSchema $schema)
Assert-That 'catalog schema excludes raw FilterClause' ($columns.Name -notcontains 'FilterClause')
Assert-That 'catalog schema contains required FilterPredicateJson' ($columns.Name -contains 'FilterPredicateJson' -and -not ($columns | Where-Object Name -eq 'FilterPredicateJson').Nullable)

$rows = @{ 'cfg.DatabaseObjectSettingRule' = [System.Collections.Generic.List[object]]::new() }
$rows['cfg.DatabaseObjectSettingRule'].Add([ordered]@{ ObjectSettingRuleID = 8; SettingCode = 'DASHBOARDS_DATA_CONNECTION'; FilterClause = "id='AD704BE6-AE67-43E3-BDB2-A89AEEEA2900'" })
[void](Convert-C7DatabaseObjectRules -Rows $rows)
Assert-That 'source adapter removes executable FilterClause before catalog build' (-not $rows['cfg.DatabaseObjectSettingRule'][0].Contains('FilterClause'))
Assert-That 'source adapter creates structured JSON' ($rows['cfg.DatabaseObjectSettingRule'][0].Contains('FilterPredicateJson'))

$excluded = @(Get-ExcludedColumnList)
Assert-That 'manifest exclusion list records raw filter removal' ($excluded -contains 'cfg.DatabaseObjectSettingRule.FilterClause')

Write-Host ('Structured filter tests: {0} passed, {1} failed.' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
exit 0
