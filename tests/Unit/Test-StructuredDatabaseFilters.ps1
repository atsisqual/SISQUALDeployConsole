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

Assert-That 'C7 tool version is active' ($script:ToolVersion -ceq '0.4.0' -and $script:SchemaVersion -eq 2 -and $script:CutRuleVersion -eq 2)
$all = Get-Object $null
Assert-That 'no filter becomes explicit ALL' ($all.kind -ceq 'ALL' -and $all.Count -eq 1)
$blank = Get-Object '   '
Assert-That 'blank filter becomes explicit ALL' ($blank.kind -ceq 'ALL')

# Shape 1: one equality.
$s1 = Get-Object "id='AD704BE6-AE67-43E3-BDB2-A89AEEEA2900'"
Assert-That 'shape 1: one equality' ($s1.kind -ceq 'AND' -and $s1.terms.Count -eq 1 -and $s1.terms[0].column -ceq 'id' -and $s1.terms[0].operator -ceq 'EQ')
Assert-That 'shape 1: literal value preserved' ($s1.terms[0].value.kind -ceq 'LITERAL' -and $s1.terms[0].value.type -ceq 'TEXT' -and $s1.terms[0].value.value -ceq 'AD704BE6-AE67-43E3-BDB2-A89AEEEA2900')

# Shape 2: two equalities.
$s2 = Get-Object "[APPLICATION]=N'SISQUAL' AND [KEY]='LanguageLogin'"
Assert-That 'shape 2: two equality terms' ($s2.terms.Count -eq 2 -and $s2.terms[0].column -ceq 'APPLICATION' -and $s2.terms[1].column -ceq 'KEY')

# Shape 3: three equalities, including an escaped quote.
$s3 = Get-Object "Aplicacao='SisqualPonto' AND Seccao='Param''etros' AND Chave='LanguageLogin'"
Assert-That 'shape 3: three equality terms' ($s3.terms.Count -eq 3)
Assert-That 'shape 3: doubled quote decoded once' ($s3.terms[1].value.value -ceq "Param'etros")

# Shape 4: four equalities and a numeric literal.
$s4 = Get-Object "A='one' AND B=N'two' AND C=3 AND D=-4.50"
Assert-That 'shape 4: four equality terms' ($s4.terms.Count -eq 4)
Assert-That 'shape 4: numeric literal is invariant text' ($s4.terms[2].value.type -ceq 'NUMBER' -and $s4.terms[2].value.value -ceq '3' -and $s4.terms[3].value.value -ceq '-4.50')

# Shape 5: lookup by one column.
$s5 = Get-Object "REALM_ID=(SELECT ID FROM REALM WHERE NAME='master')"
$lookup5 = $s5.terms[0].value
Assert-That 'shape 5: lookup encoded structurally' ($lookup5.kind -ceq 'LOOKUP' -and $null -eq $lookup5.schema -and $lookup5.table -ceq 'REALM' -and $lookup5.selectColumn -ceq 'ID')
Assert-That 'shape 5: lookup predicate is structured' ($lookup5.predicate.kind -ceq 'AND' -and $lookup5.predicate.terms.Count -eq 1 -and $lookup5.predicate.terms[0].column -ceq 'NAME')

# Shape 6: lookup with schema and two lookup conditions.
$s6 = Get-Object "CLIENT_ID=(SELECT [ID] FROM [dbo].[CLIENT] WHERE CLIENT_ID='spa' AND REALM_ID='r1') AND NAME='x'"
$lookup6 = $s6.terms[0].value
Assert-That 'shape 6: schema-qualified lookup' ($lookup6.schema -ceq 'dbo' -and $lookup6.table -ceq 'CLIENT' -and $lookup6.predicate.terms.Count -eq 2)
Assert-That 'shape 6: outer AND survives lookup' ($s6.terms.Count -eq 2 -and $s6.terms[1].column -ceq 'NAME')

# Shape 7: nested lookup, still only equality/AND.
$s7 = Get-Object "CLIENT_ID=(SELECT ID FROM CLIENT WHERE CLIENT_ID='spa' AND REALM_ID=(SELECT ID FROM REALM WHERE NAME='master'))"
$lookup7 = $s7.terms[0].value
Assert-That 'shape 7: nested lookup encoded' ($lookup7.predicate.terms[1].value.kind -ceq 'LOOKUP' -and $lookup7.predicate.terms[1].value.table -ceq 'REALM')

$top = Get-Object "CLIENT_ID=(SELECT TOP (1) ID FROM CLIENT WHERE CLIENT_ID='spa')"
Assert-That 'TOP (1) lookup is accepted without changing semantics' ($top.terms[0].value.kind -ceq 'LOOKUP' -and $top.terms[0].value.table -ceq 'CLIENT')

Assert-Throws 'OR is rejected' { Get-Object "A='x' OR B='y'" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'LIKE is rejected' { Get-Object "A LIKE 'x%'" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'not-equal is rejected' { Get-Object "A<>'x'" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'function expression is rejected' { Get-Object "LOWER(A)='x'" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'IN is rejected' { Get-Object "A IN ('x','y')" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'statement terminator is rejected' { Get-Object "A='x'; SELECT 1" | Out-Null } '*outside the supported predicate grammar*'
Assert-Throws 'line comment is rejected' { Get-Object "A='x' --comment" | Out-Null } '*outside the supported predicate grammar*'
Assert-Throws 'block comment is rejected' { Get-Object "A='x' /*comment*/" | Out-Null } '*outside the supported predicate grammar*'
Assert-Throws 'lookup without WHERE is rejected' { Get-Object "A=(SELECT ID FROM T)" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'trailing tokens are rejected' { Get-Object "A='x' SELECT 1" | Out-Null } '*cannot be converted safely*'

$row = [ordered]@{ ObjectSettingRuleID = 7; SettingCode = 'RULE_X'; FilterClause = "A='x' AND B=2"; ExpectedTemplate = '{HOST_NAME}' }
$converted = Convert-DatabaseObjectSettingRuleForCatalog -Row $row
Assert-That 'catalog row drops raw FilterClause' (-not $converted.Contains('FilterClause'))
Assert-That 'catalog row adds FilterPredicateJson' ($converted.Contains('FilterPredicateJson') -and ([string]$converted['FilterPredicateJson']).StartsWith('{"kind":"AND"'))
$roundTrip = ([string]$converted['FilterPredicateJson']) | ConvertFrom-Json -AsHashtable
Assert-That 'catalog row JSON round-trips as structured terms' ($roundTrip.terms.Count -eq 2 -and $roundTrip.terms[1].value.type -ceq 'NUMBER')

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
$rows['cfg.DatabaseObjectSettingRule'].Add([ordered]@{ ObjectSettingRuleID = 8; SettingCode = 'RULE_Y'; FilterClause = "C='z'" })
[void](Convert-C7DatabaseObjectRules -Rows $rows)
Assert-That 'source adapter transformation removes executable SQL before catalog build' (-not $rows['cfg.DatabaseObjectSettingRule'][0].Contains('FilterClause'))
Assert-That 'source adapter transformation creates structured JSON' ($rows['cfg.DatabaseObjectSettingRule'][0].Contains('FilterPredicateJson'))

$excluded = @(Get-ExcludedColumnList)
Assert-That 'manifest exclusion list records raw filter removal' ($excluded -contains 'cfg.DatabaseObjectSettingRule.FilterClause')

Write-Host ('Structured filter tests: {0} passed, {1} failed.' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
exit 0
