#requires -Version 7.0
<#
.SYNOPSIS
    Host-owned launcher of one engine run (ADR-0008 item 2). Not an engine.

.DESCRIPTION
    The host starts this script, puts the process in its job object, and only then writes one line, GO, to standard input. Nothing of the
    engine is loaded before that line, so an engine that starts a helper during its own initialisation cannot do it outside the job
    object. The engine then reads the request from the rest of standard input exactly as before. An engine must end with an explicit
    exit; the exit code of the engine is the exit code of the process.
#>
param([Parameter(Mandatory)][string]$EnginePath)

$gate = [Console]::In.ReadLine()
if ($gate -cne 'GO') { exit 2 }
$global:LASTEXITCODE = $null
& $EnginePath
# The exit code of the engine has priority: after a non-zero exit the automatic variable $? is False, which must not hide the code itself.
$engineExit = $LASTEXITCODE
if ($null -ne $engineExit) { exit $engineExit }
if (-not $?) { exit 1 }
exit 0
