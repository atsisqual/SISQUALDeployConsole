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

Assert-That 'composed converter (C7 + C1/C2) is active: tool 0.5.0, schema 2, baseline cut rule 2' ($script:ToolVersion -ceq '0.5.0' -and $script:SchemaVersion -eq 2 -and $script:CutRuleVersion -eq 2)

# The approved source model has 61 cfg.DatabaseObjectSettingRule rows and seven filter shapes.
# Three sisqualVIEW rules are intentionally unfiltered.
foreach ($code in @(
    'SISQUAL_VIEW_DATASOURCE_CONNECTION',
    'SISQUAL_VIEW_REPORT_DEFAULT_CONNECTION',
    'SISQUAL_VIEW_REPORT_DEFAULT_WFM_DATABASE'
)) {
    $all = Get-Object $null $code
    Assert-That ("unfiltered {0}: explicit ALL" -f $code) ($all.kind -ceq 'ALL' -and $all.Count -eq 1)
}
$blank = Get-Object '   ' 'BLANK'
Assert-That 'blank filter becomes explicit ALL' ($blank.kind -ceq 'ALL')

# Shape 1: one equality. This is also a real literal-only filter form.
$s1 = Get-Object "id='AD704BE6-AE67-43E3-BDB2-A89AEEEA2900'" 'DASHBOARDS_DATA_CONNECTION'
Assert-That 'shape 1: one equality' ($s1.kind -ceq 'AND' -and $s1.terms.Count -eq 1)
Assert-TextTerm $s1.terms[0] 'id' 'AD704BE6-AE67-43E3-BDB2-A89AEEEA2900' 'shape 1: id literal preserved'

# Shape 2: two equalities, including bracketed identifiers and N-prefixed text.
$s2 = Get-Object "[APPLICATION]=N'SISQUAL' AND [KEY]='LanguageLogin'"
Assert-That 'shape 2: two equality terms' ($s2.terms.Count -eq 2 -and $s2.terms[0].column -ceq 'APPLICATION' -and $s2.terms[1].column -ceq 'KEY')

# Shape 3: three equalities. This is the shape used by the WFM setting rules.
$s3 = Get-Object "Aplicacao='SisqualPonto' AND Seccao='Param''etros' AND Chave='LanguageLogin'" 'SISQUALPONTO_LANGUAGE_LOGIN'
Assert-That 'shape 3: three equality terms' ($s3.terms.Count -eq 3)
Assert-That 'shape 3: doubled quote decoded once' ($s3.terms[1].value.value -ceq "Param'etros")

# Shape 4: four equalities and numeric literals remain data, never SQL text.
$s4 = Get-Object "A='one' AND B=N'two' AND C=3 AND D=-4.50"
Assert-That 'shape 4: four equality terms' ($s4.terms.Count -eq 4)
Assert-That 'shape 4: numeric literal is invariant text' ($s4.terms[2].value.type -ceq 'NUMBER' -and $s4.terms[2].value.value -ceq '3' -and $s4.terms[3].value.value -ceq '-4.50')

# Shape 5: one-level lookup.
$s5 = Get-Object "REALM_ID=(SELECT ID FROM REALM WHERE NAME='master')"
$lookup5 = $s5.terms[0].value
Assert-That 'shape 5: lookup encoded structurally' ($lookup5.kind -ceq 'LOOKUP' -and $null -eq $lookup5.schema -and $lookup5.table -ceq 'REALM' -and $lookup5.selectColumn -ceq 'ID')
Assert-That 'shape 5: lookup predicate is structured' ($lookup5.predicate.kind -ceq 'AND' -and $lookup5.predicate.terms.Count -eq 1 -and $lookup5.predicate.terms[0].column -ceq 'NAME')

# Shape 6: schema-qualified lookup with multiple lookup terms and an outer term.
$s6 = Get-Object "CLIENT_ID=(SELECT [ID] FROM [dbo].[CLIENT] WHERE CLIENT_ID='spa' AND REALM_ID='r1') AND NAME='x'"
$lookup6 = $s6.terms[0].value
Assert-That 'shape 6: schema-qualified lookup' ($lookup6.kind -ceq 'LOOKUP' -and $lookup6.schema -ceq 'dbo' -and $lookup6.table -ceq 'CLIENT' -and $lookup6.predicate.terms.Count -eq 2)
Assert-That 'shape 6: outer AND survives lookup' ($s6.terms.Count -eq 2 -and $s6.terms[1].column -ceq 'NAME')

# Shape 7: nested lookup, still restricted to equality/AND predicates.
$s7 = Get-Object "CLIENT_ID=(SELECT ID FROM CLIENT WHERE CLIENT_ID='spa' AND REALM_ID=(SELECT ID FROM REALM WHERE NAME='master'))"
$lookup7 = $s7.terms[0].value
Assert-That 'shape 7: nested lookup encoded' ($lookup7.kind -ceq 'LOOKUP' -and $lookup7.predicate.terms[1].value.kind -ceq 'LOOKUP' -and $lookup7.predicate.terms[1].value.table -ceq 'REALM')

$top = Get-Object "CLIENT_ID=(SELECT TOP (1) ID FROM CLIENT WHERE CLIENT_ID='spa')"
Assert-That 'TOP (1) lookup is accepted without changing semantics' ($top.terms[0].value.kind -ceq 'LOOKUP' -and $top.terms[0].value.table -ceq 'CLIENT')

# Fail closed outside the approved seven families.
Assert-Throws 'OR is rejected' { Get-Object "A='x' OR B='y'" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'LIKE is rejected' { Get-Object "A LIKE 'x%'" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'not-equal is rejected' { Get-Object "A<>'x'" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'function expression is rejected' { Get-Object "LOWER(A)='x'" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'IN is rejected' { Get-Object "A IN ('x','y')" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'statement terminator is rejected' { Get-Object "A='x'; SELECT 1" | Out-Null } '*outside the supported predicate grammar*'
Assert-Throws 'line comment is rejected' { Get-Object "A='x' --comment" | Out-Null } '*outside the supported predicate grammar*'
Assert-Throws 'block comment is rejected' { Get-Object "A='x' /*comment*/" | Out-Null } '*outside the supported predicate grammar*'
Assert-Throws 'lookup without WHERE is rejected' { Get-Object "A=(SELECT ID FROM T)" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'TOP other than 1 is rejected' { Get-Object "A=(SELECT TOP (2) ID FROM T WHERE B='x')" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'trailing tokens are rejected' { Get-Object "A='x' SELECT 1" | Out-Null } '*cannot be converted safely*'

$row = [ordered]@{ ObjectSettingRuleID = 7; SettingCode = 'RULE_LOOKUP'; FilterClause = "CLIENT_ID=(SELECT ID FROM CLIENT WHERE CLIENT_ID='spa')"; ExpectedTemplate = '{HOST_NAME}' }
$converted = Convert-DatabaseObjectSettingRuleForCatalog -Row $row
Assert-That 'catalog row drops raw FilterClause' (-not $converted.Contains('FilterClause'))
Assert-That 'catalog row adds FilterPredicateJson' ($converted.Contains('FilterPredicateJson') -and ([string]$converted['FilterPredicateJson']).StartsWith('{"kind":"AND"'))
$roundTrip = ([string]$converted['FilterPredicateJson']) | ConvertFrom-Json -AsHashtable
Assert-That 'catalog row JSON round-trips a lookup without executable SQL' ($roundTrip.terms.Count -eq 1 -and $roundTrip.terms[0].value.kind -ceq 'LOOKUP' -and $roundTrip.terms[0].value.table -ceq 'CLIENT')

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
$rows['cfg.DatabaseObjectSettingRule'].Add([ordered]@{ ObjectSettingRuleID = 8; SettingCode = 'RULE_LOOKUP'; FilterClause = "CLIENT_ID=(SELECT ID FROM CLIENT WHERE CLIENT_ID='spa')" })
[void](Convert-C7DatabaseObjectRules -Rows $rows)
Assert-That 'source adapter removes executable FilterClause before catalog build' (-not $rows['cfg.DatabaseObjectSettingRule'][0].Contains('FilterClause'))
Assert-That 'source adapter creates structured lookup JSON' (([string]$rows['cfg.DatabaseObjectSettingRule'][0]['FilterPredicateJson']) -like '*"kind":"LOOKUP"*')

# Conversion of a representative 61-row batch must not depend on a literal-only shortcut.
$batch = @{ 'cfg.DatabaseObjectSettingRule' = [System.Collections.Generic.List[object]]::new() }
$shapeFilters = @(
    "A='x'",
    "A='x' AND B='y'",
    "A='x' AND B='y' AND C='z'",
    "A='x' AND B='y' AND C='z' AND D=4",
    "A=(SELECT ID FROM T WHERE B='x')",
    "A=(SELECT ID FROM T WHERE B='x' AND C='y') AND D='z'",
    "A=(SELECT ID FROM T WHERE B=(SELECT ID FROM U WHERE C='z'))"
)
for ($i = 0; $i -lt 61; $i++) {
    $batch['cfg.DatabaseObjectSettingRule'].Add([ordered]@{ ObjectSettingRuleID = $i + 1; SettingCode = ('RULE_{0:D2}' -f ($i + 1)); FilterClause = $shapeFilters[$i % $shapeFilters.Count] })
}
[void](Convert-C7DatabaseObjectRules -Rows $batch)
Assert-That '61-row batch spanning all seven shapes converts' (@($batch['cfg.DatabaseObjectSettingRule'] | Where-Object { $_.Contains('FilterClause') -or -not $_.Contains('FilterPredicateJson') }).Count -eq 0)
Assert-That '61-row batch retains structured lookups' (@($batch['cfg.DatabaseObjectSettingRule'] | Where-Object { ([string]$_['FilterPredicateJson']) -like '*"kind":"LOOKUP"*' }).Count -gt 0)

$excluded = @(Get-ExcludedColumnList)
Assert-That 'manifest exclusion list records raw filter removal' ($excluded -contains 'cfg.DatabaseObjectSettingRule.FilterClause')

# ---------------------------------------------------------------------------
# The null-replacing equality: ISNULL(<column>, <literal>) = <value>. 14 of the 58 real filters use it.
# ---------------------------------------------------------------------------
$isn = Get-Object "Application='WFM' AND ISNULL([User],N'')='' AND Section='SISQUAL' AND [Key]='MobileAppAccessToken'"
Assert-That 'ISNULL: the real shape converts to four terms' ($isn.kind -ceq 'AND' -and $isn.terms.Count -eq 4)
Assert-That 'ISNULL: the column is the inner column and the comparison is still EQ' ($isn.terms[1].column -ceq 'User' -and $isn.terms[1].operator -ceq 'EQ' -and $isn.terms[1].value.type -ceq 'TEXT' -and $isn.terms[1].value.value -ceq '')
Assert-That 'ISNULL: the replacement is kept as a literal node (NULL is read as the empty string)' ($isn.terms[1].nullReplacement.kind -ceq 'LITERAL' -and $isn.terms[1].nullReplacement.type -ceq 'TEXT' -and $isn.terms[1].nullReplacement.value -ceq '')
Assert-That 'ISNULL: the other terms carry no nullReplacement' (-not $isn.terms[0].ContainsKey('nullReplacement') -and -not $isn.terms[2].ContainsKey('nullReplacement') -and -not $isn.terms[3].ContainsKey('nullReplacement'))
Assert-That 'ISNULL: the stored JSON holds the replacement' ((ConvertTo-StructuredDatabaseFilterJson -FilterClause "ISNULL([User],N'')=''" -RuleCode 'T') -clike '*"nullReplacement":{"kind":"LITERAL","type":"TEXT","value":""}*')
function Test-TermMatches {
    # A model of the contract for the future engine: a NULL column is read as the replacement before the comparison.
    param($Term, $RowValue)
    $effective = $RowValue
    if ($null -eq $RowValue -and $Term.ContainsKey('nullReplacement')) { $effective = $Term.nullReplacement.value }
    if ($null -eq $effective) { return $false }
    return ([string]$effective -ceq [string]$Term.value.value)
}
Assert-That 'ISNULL meaning: a NULL row matches (the whole point of keeping the replacement)' (Test-TermMatches $isn.terms[1] $null)
Assert-That 'ISNULL meaning: an empty row matches' (Test-TermMatches $isn.terms[1] '')
Assert-That 'ISNULL meaning: a row with a value does not match' (-not (Test-TermMatches $isn.terms[1] 'someone'))
$plainEq = Get-Object "[User]=''"
Assert-That 'ISNULL meaning: without ISNULL a NULL row does not match (the probe rewrite would have changed this)' (-not (Test-TermMatches $plainEq.terms[0] $null))
$spaced = Get-Object "isnull ( [User] , N'' ) = ''"
Assert-That 'ISNULL: case-insensitive keyword and free whitespace' ($spaced.terms[0].column -ceq 'User' -and $spaced.terms[0].nullReplacement.value -ceq '')
$num = Get-Object 'ISNULL(Qty, 0) = 0'
Assert-That 'ISNULL: a numeric replacement is kept as invariant text' ($num.terms[0].nullReplacement.type -ceq 'NUMBER' -and $num.terms[0].nullReplacement.value -ceq '0')
$nonEmpty = Get-Object "ISNULL([User],N'none')='none'"
Assert-That 'ISNULL: a non-empty replacement is kept as written' ($nonEmpty.terms[0].nullReplacement.value -ceq 'none' -and (Test-TermMatches $nonEmpty.terms[0] $null))
$inLookup = Get-Object "A=(SELECT ID FROM T WHERE ISNULL(B,'')='x')"
Assert-That 'ISNULL: accepted inside a lookup predicate too' ($inLookup.terms[0].value.kind -ceq 'LOOKUP' -and $inLookup.terms[0].value.predicate.terms[0].nullReplacement.value -ceq '')
$named = Get-Object "ISNULL='x'"
Assert-That 'ISNULL: a column that is itself called ISNULL still works (the function form needs a parenthesis)' ($named.terms[0].column -ceq 'ISNULL' -and -not $named.terms[0].ContainsKey('nullReplacement'))
Assert-Throws 'ISNULL: one argument is rejected' { Get-Object "ISNULL([User])=''" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'ISNULL: three arguments are rejected' { Get-Object "ISNULL([User],'a','b')=''" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'ISNULL: a column as replacement is rejected (only a literal)' { Get-Object "ISNULL([User],Other)=''" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'ISNULL: nested ISNULL is rejected' { Get-Object "ISNULL(ISNULL(A,''),'')=''" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'ISNULL: without a comparison is rejected' { Get-Object "ISNULL([User],'')" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'ISNULL: a non-equality comparison is rejected' { Get-Object "ISNULL([User],'')<>''" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'ISNULL: truncated is rejected' { Get-Object "ISNULL(" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'ISNULL: a missing comma between the arguments is rejected' { Get-Object "ISNULL([User] '')=''" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'ISNULL: a missing closing parenthesis is rejected' { Get-Object "ISNULL([User],'' = ''" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'ISNULL: on the value side is rejected' { Get-Object "A=ISNULL(B,'')" | Out-Null } '*cannot be converted safely*'
Assert-Throws 'ISNULL: another function is still rejected' { Get-Object "COALESCE([User],'')=''" | Out-Null } '*cannot be converted safely*'

# Every structural shape of the real snapshot converts (shapes only: the fixture keeps no real value).
$fx = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..' 'Fixtures' 'database-filter-shapes.json') -Raw | ConvertFrom-Json
$shapeFail = @()
foreach ($s in $fx.shapes) { try { [void](ConvertTo-StructuredDatabaseFilter -FilterClause $s.template -RuleCode 'SHAPE') } catch { $shapeFail += $s.template } }
Assert-That ('real shapes: all {0} structural templates of the snapshot convert' -f @($fx.shapes).Count) ($shapeFail.Count -eq 0 -and @($fx.shapes).Count -ge 6)
Assert-That 'real shapes: the templates cover the 58 populated filters and the three unfiltered rules make 61' (([int](@($fx.shapes | Measure-Object -Property count -Sum).Sum)) -eq 58 -and $fx.populatedFilters -eq 58 -and $fx.unfilteredRules -eq 3)
Assert-That 'real shapes: the ISNULL template is in the fixture (14 filters)' (@($fx.shapes | Where-Object { $_.template -like '*ISNULL*' -and $_.count -eq 14 }).Count -eq 1)
Assert-That 'real shapes: the fixture holds no real value (every text literal is v and every number is 0)' (@($fx.shapes | Where-Object { (($_.template -replace "N?'v'", '') -match "'") -or ($_.template -match '[1-9]') }).Count -eq 0)

Write-Host ('Structured filter tests: {0} passed, {1} failed.' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
exit 0
