#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:DatabaseFilterMaxDepth = 4
$script:DatabaseFilterMaxTerms = 16
$script:DatabaseFilterMaxLiteralLength = 4000

function Skip-DatabaseFilterWhitespace {
    param([Parameter(Mandatory)]$State)
    while ($State.Position -lt $State.Text.Length -and [char]::IsWhiteSpace($State.Text[$State.Position])) { $State.Position++ }
}

function Test-DatabaseFilterKeywordAt {
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$Keyword)
    Skip-DatabaseFilterWhitespace -State $State
    if ($State.Position + $Keyword.Length -gt $State.Text.Length) { return $false }
    if ([string]::Compare($State.Text, $State.Position, $Keyword, 0, $Keyword.Length, [System.StringComparison]::OrdinalIgnoreCase) -ne 0) { return $false }
    $after = $State.Position + $Keyword.Length
    if ($after -lt $State.Text.Length -and $State.Text[$after] -match '[A-Za-z0-9_@$#]') { return $false }
    return $true
}

function Read-DatabaseFilterKeyword {
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$Keyword)
    if (-not (Test-DatabaseFilterKeywordAt -State $State -Keyword $Keyword)) { throw ('Expected keyword {0} at offset {1}.' -f $Keyword, $State.Position) }
    $State.Position += $Keyword.Length
}

function Read-DatabaseFilterIdentifier {
    param([Parameter(Mandatory)]$State)
    Skip-DatabaseFilterWhitespace -State $State
    if ($State.Position -ge $State.Text.Length) { throw ('Expected identifier at offset {0}.' -f $State.Position) }
    if ($State.Text[$State.Position] -eq '[') {
        $start = ++$State.Position
        $end = $State.Text.IndexOf(']', $start)
        if ($end -lt 0) { throw ('Unterminated bracketed identifier at offset {0}.' -f ($start - 1)) }
        $name = $State.Text.Substring($start, $end - $start)
        $State.Position = $end + 1
    }
    else {
        $start = $State.Position
        if ($State.Text[$State.Position] -notmatch '[A-Za-z_@#]') { throw ('Invalid identifier at offset {0}.' -f $State.Position) }
        $State.Position++
        while ($State.Position -lt $State.Text.Length -and $State.Text[$State.Position] -match '[A-Za-z0-9_@$#]') { $State.Position++ }
        $name = $State.Text.Substring($start, $State.Position - $start)
    }
    if ([string]::IsNullOrWhiteSpace($name) -or $name.Length -gt 128) { throw 'Database filter identifier must contain 1 to 128 characters.' }
    return $name
}

function Read-DatabaseFilterStringLiteral {
    param([Parameter(Mandatory)]$State)
    Skip-DatabaseFilterWhitespace -State $State
    if ($State.Position -lt $State.Text.Length - 1 -and ($State.Text[$State.Position] -eq 'N' -or $State.Text[$State.Position] -eq 'n') -and $State.Text[$State.Position + 1] -eq "'") { $State.Position++ }
    if ($State.Position -ge $State.Text.Length -or $State.Text[$State.Position] -ne "'") { throw ('Expected string literal at offset {0}.' -f $State.Position) }
    $State.Position++
    $builder = [System.Text.StringBuilder]::new()
    while ($State.Position -lt $State.Text.Length) {
        $quote = $State.Text.IndexOf("'", $State.Position, [System.StringComparison]::Ordinal)
        if ($quote -lt 0) { throw 'Unterminated database filter string literal.' }
        [void]$builder.Append($State.Text, $State.Position, $quote - $State.Position)
        if ($quote + 1 -lt $State.Text.Length -and $State.Text[$quote + 1] -eq "'") {
            [void]$builder.Append("'")
            $State.Position = $quote + 2
            continue
        }
        $State.Position = $quote + 1
        $value = $builder.ToString()
        if ($value.Length -gt $script:DatabaseFilterMaxLiteralLength) { throw 'Database filter literal is longer than the supported maximum.' }
        return [ordered]@{ kind = 'LITERAL'; type = 'TEXT'; value = $value }
    }
    throw 'Unterminated database filter string literal.'
}

function Read-DatabaseFilterNumberLiteral {
    param([Parameter(Mandatory)]$State)
    Skip-DatabaseFilterWhitespace -State $State
    $remaining = $State.Text.Substring($State.Position)
    $match = [regex]::Match($remaining, '^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?')
    if (-not $match.Success) { throw ('Expected literal at offset {0}.' -f $State.Position) }
    $State.Position += $match.Length
    return [ordered]@{ kind = 'LITERAL'; type = 'NUMBER'; value = $match.Value }
}

function Test-DatabaseFilterStringLiteralStart {
    param([Parameter(Mandatory)]$State)
    if ($State.Position -ge $State.Text.Length) { return $false }
    $c = $State.Text[$State.Position]
    if ($c -eq "'") { return $true }
    return (($c -eq 'N' -or $c -eq 'n') -and $State.Position + 1 -lt $State.Text.Length -and $State.Text[$State.Position + 1] -eq "'")
}

function Read-DatabaseFilterPredicate {
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][int]$Depth, [char]$StopCharacter = [char]0)
    if ($Depth -gt $script:DatabaseFilterMaxDepth) { throw 'Database filter lookup nesting is too deep.' }
    $terms = [System.Collections.Generic.List[object]]::new()
    while ($true) {
        Skip-DatabaseFilterWhitespace -State $State
        $wrapped = $false
        if ($State.Position -lt $State.Text.Length -and $State.Text[$State.Position] -eq '(') {
            $probe = [pscustomobject]@{ Text = $State.Text; Position = $State.Position + 1 }
            if (-not (Test-DatabaseFilterKeywordAt -State $probe -Keyword 'SELECT')) { $wrapped = $true; $State.Position++ }
        }
        $column = $null
        $nullReplacement = $null
        $probe = [pscustomobject]@{ Text = $State.Text; Position = $State.Position }
        if (Test-DatabaseFilterKeywordAt -State $probe -Keyword 'ISNULL') {
            $probe.Position += 'ISNULL'.Length
            Skip-DatabaseFilterWhitespace -State $probe
            if ($probe.Position -lt $probe.Text.Length -and $probe.Text[$probe.Position] -eq '(') {
                # ISNULL(<column>, <literal>) = <value>: an equality that reads a NULL column as the literal (the one function the grammar accepts).
                $State.Position = $probe.Position + 1
                $column = Read-DatabaseFilterIdentifier -State $State
                Skip-DatabaseFilterWhitespace -State $State
                if ($State.Position -ge $State.Text.Length -or $State.Text[$State.Position] -ne ',') { throw 'ISNULL takes exactly two arguments: a column and a literal.' }
                $State.Position++
                Skip-DatabaseFilterWhitespace -State $State
                if (Test-DatabaseFilterStringLiteralStart -State $State) { $nullReplacement = Read-DatabaseFilterStringLiteral -State $State }
                else { $nullReplacement = Read-DatabaseFilterNumberLiteral -State $State }
                Skip-DatabaseFilterWhitespace -State $State
                if ($State.Position -ge $State.Text.Length -or $State.Text[$State.Position] -ne ')') { throw 'ISNULL takes exactly two arguments: a column and a literal.' }
                $State.Position++
            }
        }
        if ($null -eq $column) { $column = Read-DatabaseFilterIdentifier -State $State }
        Skip-DatabaseFilterWhitespace -State $State
        if ($State.Position -ge $State.Text.Length -or $State.Text[$State.Position] -ne '=') { throw ('Only equality comparisons are supported; expected = after {0}.' -f $column) }
        $State.Position++
        Skip-DatabaseFilterWhitespace -State $State
        if ($State.Position -lt $State.Text.Length -and $State.Text[$State.Position] -eq '(') {
            $value = Read-DatabaseFilterLookup -State $State -Depth ($Depth + 1)
        }
        elseif ($State.Position -lt $State.Text.Length -and ($State.Text[$State.Position] -eq "'" -or (($State.Text[$State.Position] -eq 'N' -or $State.Text[$State.Position] -eq 'n') -and $State.Position + 1 -lt $State.Text.Length -and $State.Text[$State.Position + 1] -eq "'"))) {
            $value = Read-DatabaseFilterStringLiteral -State $State
        }
        else { $value = Read-DatabaseFilterNumberLiteral -State $State }
        $term = [ordered]@{ column = $column; operator = 'EQ'; value = $value }
        if ($null -ne $nullReplacement) { $term['nullReplacement'] = $nullReplacement }
        $terms.Add($term)
        if ($terms.Count -gt $script:DatabaseFilterMaxTerms) { throw 'Database filter contains too many comparisons.' }
        Skip-DatabaseFilterWhitespace -State $State
        if ($wrapped) {
            if ($State.Position -ge $State.Text.Length -or $State.Text[$State.Position] -ne ')') { throw ('Expected ) at offset {0}.' -f $State.Position) }
            $State.Position++
            Skip-DatabaseFilterWhitespace -State $State
        }
        if ($StopCharacter -ne [char]0 -and $State.Position -lt $State.Text.Length -and $State.Text[$State.Position] -eq $StopCharacter) { break }
        if (Test-DatabaseFilterKeywordAt -State $State -Keyword 'AND') { Read-DatabaseFilterKeyword -State $State -Keyword 'AND'; continue }
        break
    }
    if ($terms.Count -eq 0) { throw 'Database filter predicate is empty.' }
    return [ordered]@{ kind = 'AND'; terms = $terms.ToArray() }
}

function Read-DatabaseFilterLookup {
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][int]$Depth)
    if ($Depth -gt $script:DatabaseFilterMaxDepth) { throw 'Database filter lookup nesting is too deep.' }
    Skip-DatabaseFilterWhitespace -State $State
    if ($State.Position -ge $State.Text.Length -or $State.Text[$State.Position] -ne '(') { throw ('Expected lookup ( at offset {0}.' -f $State.Position) }
    $State.Position++
    Read-DatabaseFilterKeyword -State $State -Keyword 'SELECT'
    if (Test-DatabaseFilterKeywordAt -State $State -Keyword 'TOP') {
        Read-DatabaseFilterKeyword -State $State -Keyword 'TOP'
        Skip-DatabaseFilterWhitespace -State $State
        if ($State.Position -ge $State.Text.Length -or $State.Text[$State.Position] -ne '(') { throw 'Only TOP (1) is supported in a lookup.' }
        $State.Position++
        Skip-DatabaseFilterWhitespace -State $State
        if ($State.Position -ge $State.Text.Length -or $State.Text[$State.Position] -ne '1') { throw 'Only TOP (1) is supported in a lookup.' }
        $State.Position++
        Skip-DatabaseFilterWhitespace -State $State
        if ($State.Position -ge $State.Text.Length -or $State.Text[$State.Position] -ne ')') { throw 'Only TOP (1) is supported in a lookup.' }
        $State.Position++
    }
    $selectColumn = Read-DatabaseFilterIdentifier -State $State
    Read-DatabaseFilterKeyword -State $State -Keyword 'FROM'
    $first = Read-DatabaseFilterIdentifier -State $State
    Skip-DatabaseFilterWhitespace -State $State
    $schema = $null
    $table = $first
    if ($State.Position -lt $State.Text.Length -and $State.Text[$State.Position] -eq '.') { $State.Position++; $schema = $first; $table = Read-DatabaseFilterIdentifier -State $State }
    Read-DatabaseFilterKeyword -State $State -Keyword 'WHERE'
    $predicate = Read-DatabaseFilterPredicate -State $State -Depth $Depth -StopCharacter ')'
    Skip-DatabaseFilterWhitespace -State $State
    if ($State.Position -ge $State.Text.Length -or $State.Text[$State.Position] -ne ')') { throw ('Expected lookup ) at offset {0}.' -f $State.Position) }
    $State.Position++
    return [ordered]@{ kind = 'LOOKUP'; schema = $schema; table = $table; selectColumn = $selectColumn; predicate = $predicate }
}

function ConvertTo-StructuredDatabaseFilter {
    [CmdletBinding()]
    param([AllowNull()][string]$FilterClause, [string]$RuleCode = '')
    if ([string]::IsNullOrWhiteSpace($FilterClause)) { return [ordered]@{ kind = 'ALL' } }
    if ($FilterClause -match ';|--|/\*|\*/') { throw ('Database filter for rule {0} contains SQL syntax outside the supported predicate grammar.' -f $RuleCode) }
    $state = [pscustomobject]@{ Text = $FilterClause; Position = 0 }
    try {
        $predicate = Read-DatabaseFilterPredicate -State $state -Depth 0
        Skip-DatabaseFilterWhitespace -State $state
        if ($state.Position -ne $state.Text.Length) { throw ('Unexpected token at offset {0}.' -f $state.Position) }
        return $predicate
    }
    catch {
        $code = if ([string]::IsNullOrWhiteSpace($RuleCode)) { '<unknown>' } else { $RuleCode }
        throw ('Database filter for rule {0} cannot be converted safely: {1}' -f $code, $_.Exception.Message)
    }
}

function ConvertTo-StructuredDatabaseFilterJson {
    [CmdletBinding()]
    param([AllowNull()][string]$FilterClause, [string]$RuleCode = '')
    return ((ConvertTo-StructuredDatabaseFilter -FilterClause $FilterClause -RuleCode $RuleCode) | ConvertTo-Json -Depth 16 -Compress -EscapeHandling EscapeNonAscii)
}

function Get-StructuredDatabaseFilterColumnInfo {
    return [pscustomobject]@{ Name = 'FilterPredicateJson'; Type = 'nvarchar'; Length = -1; Precision = 0; Scale = 0; Identity = $false; Nullable = $false }
}

function Convert-DatabaseObjectSettingRuleForCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Row)
    if (-not $Row.Contains('SettingCode')) { throw 'cfg.DatabaseObjectSettingRule row has no SettingCode.' }
    $filter = $null
    if ($Row.Contains('FilterClause')) { $filter = $Row['FilterClause'] }
    $json = ConvertTo-StructuredDatabaseFilterJson -FilterClause ([string]$filter) -RuleCode ([string]$Row['SettingCode'])
    if ($Row.Contains('FilterClause')) { [void]$Row.Remove('FilterClause') }
    $Row['FilterPredicateJson'] = $json
    return $Row
}
