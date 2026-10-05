#requires -Version 7.0
<#
.SYNOPSIS
    Unit tests for tools/Export-ManagementEngines.ps1 (no Pester, no network, no SQL Server).

.DESCRIPTION
    Builds a small synthetic ManagementSync.sql in a temporary folder and runs the
    export against it. Marker values stand in for secrets. Exits with code 1 on failure.
    The SQL Server path (-SqlInstance) is not covered here: it needs a real server [V].
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'Export-ManagementEngines.ps1')).Path
. $toolPath -SyncFile 'unused' -OutputFolder 'unused'

$script:Failures = 0
$script:Passed = 0
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
    Assert-That $Name ($threw -and ($message -like $Like))
}

$marker = 'Q9zXk4' + 'MARKER' + '77'            # stands in for a secret value; assembled so it is not a literal
$eAcute = [string][char]0x00E9
$crlf = "`r`n"

function New-EngineInsert {
    param([string]$Code, [string]$File, [string]$Version, [string]$Text, [string]$StoredHash)
    $escaped = $Text.Replace("'", "''")
    $marker = 'INSERT INTO [ops].[Engine] ([EngineCode], [DisplayName], [SourceFileName], [EngineVersion], [ScriptText], [ScriptSha256], [MinimumPowerShell], [RequiresAdministrator], [IsEnabled], [ModifiedAt]) VALUES ('
    return ("{0}N'{1}', N'Display {1}', N'{2}', N'{3}', N'{4}', N'{5}', N'5.1', 1, 1, '2026-01-01 00:00:00.0000000');" -f $marker, $Code, $File, $Version, $escaped, $StoredHash) + $crlf
}

$textA = '# engine A' + $crlf + 'Write-Host ''it''''s quoted''' + $crlf + '# accent: ' + $eAcute + $crlf
$textB = '# engine B' + $crlf + '$Password = [string]$Row.SomePassword' + $crlf + '$Pwd = ''' + $marker + '''' + $crlf + 'Password = ' + $marker + $crlf
$hashA = Get-ScriptTextHash -Text $textA
$hashB = Get-ScriptTextHash -Text $textB

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('export-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    # 1. Parsing -------------------------------------------------------------
    $sql = '/* header */' + $crlf +
    (New-EngineInsert 'ENGINE_A' 'Invoke-A.ps1' '1.0' $textA $hashA) +
    'INSERT INTO [ops].[Engine_BackupIisFix] ([EngineCode]) VALUES (N''IGNORED'');' + $crlf +
    (New-EngineInsert 'ENGINE_B' 'Invoke-B.ps1' 'v2' $textB $hashB)
    $engines = Read-EnginesFromSyncText -Text $sql
    Assert-That 'parses exactly the two ops.Engine rows' ($engines.Count -eq 2)
    Assert-That 'quotes are unescaped' ($engines[0].ScriptText -eq $textA)
    Assert-That 'metadata is read' ($engines[0].EngineCode -eq 'ENGINE_A' -and $engines[0].EngineVersion -eq '1.0' -and $engines[0].RequiresAdministrator -and $engines[0].IsEnabled)
    Assert-That 'stored hash equals UTF-16LE hash' ($engines[0].ScriptSha256 -eq (Get-ScriptTextHash -Text $engines[0].ScriptText))

    # 2. Export ---------------------------------------------------------------
    $out = Join-Path $work 'out'
    $info = @{ kind = 'test' }
    $r = Invoke-EngineExport -Engines $engines -Folder $out -SourceInfo $info
    Assert-That 'export reports 2 engines and 0 mismatches' ($r.Engines -eq 2 -and $r.Mismatches -eq 0)
    $bytesA = [System.IO.File]::ReadAllBytes((Join-Path $out 'Invoke-A.ps1'))
    Assert-That 'file is UTF-8 without BOM and keeps CRLF' ($bytesA[0] -ne 0xEF -and [System.Text.Encoding]::UTF8.GetString($bytesA) -eq $textA)
    $manifestRaw = [System.IO.File]::ReadAllBytes($r.ManifestPath)
    $manifestText = [System.Text.Encoding]::UTF8.GetString($manifestRaw)
    Assert-That 'manifest is ASCII and LF' (-not ($manifestRaw | Where-Object { $_ -gt 127 }) -and -not ($manifestRaw | Where-Object { $_ -eq 13 }))
    $manifest = $manifestText | ConvertFrom-Json
    $entryA = $manifest.engines | Where-Object engineCode -eq 'ENGINE_A'
    Assert-That 'manifest records CRLF and the non-ASCII character' ($entryA.lineEndings -eq 'CRLF' -and $entryA.nonAsciiCharacters -eq 1 -and $entryA.hashMatches)

    # 3. Secret safety --------------------------------------------------------
    $entryB = $manifest.engines | Where-Object engineCode -eq 'ENGINE_B'
    Assert-That 'literal password values are counted' ($entryB.secretPatternHits.passwordLiteral -ge 1)
    Assert-That 'a type cast is not a hit' ((Get-SecretPatternCounts -Text '$Password = [string]$Row.SomePassword').passwordLiteral -eq 0)
    Assert-That 'a placeholder is not a hit' ((Get-SecretPatternCounts -Text 'Password = {{secret:X}}').passwordLiteral -eq 0)
    Assert-That 'the marker value never reaches the manifest' (-not $manifestText.Contains($marker))

    # 4. Hash mismatch --------------------------------------------------------
    $bad = Read-EnginesFromSyncText -Text ($sql.Replace($hashA, ('0' * 64)))
    $out2 = Join-Path $work 'out2'
    Assert-Throws 'a hash mismatch stops the export' { Invoke-EngineExport -Engines $bad -Folder $out2 -SourceInfo $info } '*failed the stored-hash check*'
    Assert-That 'the mismatching file is not written' (-not (Test-Path (Join-Path $out2 'Invoke-A.ps1')))
    Assert-That 'the mismatch is recorded in the manifest' ((Get-Content (Join-Path $out2 'engines-export-manifest.json') -Raw | ConvertFrom-Json).hashMismatches -eq 1)

    # 5. Output folder, names, filters ----------------------------------------
    $inside = Join-Path $script:RepoRoot 'should-not-exist'
    Assert-Throws 'an output folder inside the repository is refused' { Invoke-EngineExport -Engines $engines -Folder $inside -SourceInfo $info } '*inside the repository*'
    Assert-That 'the refused folder was not created' (-not (Test-Path $inside))
    $evil = @([pscustomobject]@{ EngineCode = 'EVIL'; DisplayName = 'x'; SourceFileName = '..\evil.ps1'; EngineVersion = '1'; ScriptText = 'x'; ScriptSha256 = (Get-ScriptTextHash 'x'); MinimumPowerShell = '5.1'; RequiresAdministrator = $false; IsEnabled = $true; ModifiedAt = 'x' })
    Assert-Throws 'a path in SourceFileName is refused' { Invoke-EngineExport -Engines $evil -Folder (Join-Path $work 'out3') -SourceInfo $info } '*Unsafe SourceFileName*'
    $one = Invoke-EngineExport -Engines $engines -Folder (Join-Path $work 'out4') -Only @('ENGINE_B') -SourceInfo $info
    Assert-That 'the engine filter exports only the selected engine' ($one.Engines -eq 1 -and -not (Test-Path (Join-Path $work 'out4' 'Invoke-A.ps1')))
    Assert-Throws 'an unknown engine code is an error' { Invoke-EngineExport -Engines $engines -Folder (Join-Path $work 'out5') -Only @('NOPE') -SourceInfo $info } '*not found*'
    $dup = @($engines[0], ([pscustomobject]@{ EngineCode = 'ENGINE_A2'; DisplayName = 'x'; SourceFileName = 'invoke-a.ps1'; EngineVersion = '1'; ScriptText = 'x'; ScriptSha256 = (Get-ScriptTextHash 'x'); MinimumPowerShell = '5.1'; RequiresAdministrator = $false; IsEnabled = $true; ModifiedAt = 'x' }))
    Assert-Throws 'two engines with the same file name are refused' { Invoke-EngineExport -Engines $dup -Folder (Join-Path $work 'out6') -SourceInfo $info } '*share the file name*'
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ('{0} passed, {1} failed' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
