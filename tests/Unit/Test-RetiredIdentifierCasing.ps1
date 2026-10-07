#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'Convert-ManagementDb.ps1')).Path
. $toolPath -SyncFile 'unused' -OutputFolder 'unused' -Sqlite3Path 'unused'

$script:Passed = 0
$script:Failed = 0
function Assert-Throws {
    param([string]$Name, [scriptblock]$Block, [string]$Like = '*')
    $threw = $false
    $message = ''
    try { & $Block } catch { $threw = $true; $message = $_.Exception.Message }
    if ($threw -and $message -like $Like) {
        $script:Passed++
        Write-Host ('PASS  {0}' -f $Name)
    }
    else {
        $script:Failed++
        Write-Host ('FAIL  {0} {1}' -f $Name, $message)
    }
}

$actionVariant = @{ 'ops.Action' = [System.Collections.Generic.List[object]]::new() }
$actionVariant['ops.Action'].Add([ordered]@{ ActionCode='v8_keycloak_config'; EngineCode='v8_keycloak_config' })
Assert-Throws 'case variant of retired V8 action is rejected' { Assert-NoRetiredCatalogMetadata -Rows $actionVariant } '*Retired action*'

$actionEngineVariant = @{ 'ops.Action' = [System.Collections.Generic.List[object]]::new() }
$actionEngineVariant['ops.Action'].Add([ordered]@{ ActionCode='KEEP'; EngineCode='v8_keycloak_config' })
Assert-Throws 'case variant of retired V8 engine reference is rejected' { Assert-NoRetiredCatalogMetadata -Rows $actionEngineVariant } '*retired engine*'

$engineVariant = @{ 'ops.Engine' = [System.Collections.Generic.List[object]]::new() }
$engineVariant['ops.Engine'].Add([ordered]@{ EngineCode='v8_keycloak_config' })
Assert-Throws 'case variant of retired V8 engine row is rejected' { Assert-NoRetiredCatalogMetadata -Rows $engineVariant } '*Retired engine*'

$legacyEngineVariant = @{ 'ops.Engine' = [System.Collections.Generic.List[object]]::new() }
$legacyEngineVariant['ops.Engine'].Add([ordered]@{ EngineCode='database_settings' })
Assert-Throws 'case variant of retired DATABASE_SETTINGS engine row is rejected' { Assert-NoRetiredCatalogMetadata -Rows $legacyEngineVariant } '*Retired engine*'

$childVariant = @{ 'ops.ActionStep' = [System.Collections.Generic.List[object]]::new() }
$childVariant['ops.ActionStep'].Add([ordered]@{ ParentActionCode='OTHER'; StepOrder=[long]99; ChildActionCode='v8_keycloak_config' })
Assert-Throws 'case variant of retired V8 child reference is rejected' { Assert-NoRetiredCatalogMetadata -Rows $childVariant } '*Retired action reference*'

$parentVariant = @{ 'ops.ActionStep' = [System.Collections.Generic.List[object]]::new() }
$parentVariant['ops.ActionStep'].Add([ordered]@{ ParentActionCode='v8_keycloak_config'; StepOrder=[long]10; ChildActionCode='KEEP' })
Assert-Throws 'case variant of retired V8 parent reference is rejected' { Assert-NoRetiredCatalogMetadata -Rows $parentVariant } '*Retired action reference*'

$dependentVariant = @{ 'ops.ActionRequirement' = [System.Collections.Generic.List[object]]::new() }
$dependentVariant['ops.ActionRequirement'].Add([ordered]@{ ActionCode='v8_keycloak_config'; RequirementCode='R1' })
Assert-Throws 'case variant of retired V8 dependent metadata is rejected' { Assert-NoRetiredCatalogMetadata -Rows $dependentVariant } '*ops.ActionRequirement*'

$paddedAction = @{ 'ops.Action' = [System.Collections.Generic.List[object]]::new() }
$paddedAction['ops.Action'].Add([ordered]@{ ActionCode='V8_KEYCLOAK_CONFIG '; EngineCode='KEEP' })
Assert-Throws 'SQL-equivalent right-padded V8 action is rejected' { Assert-NoRetiredCatalogMetadata -Rows $paddedAction } '*Retired action*'

$paddedActionEngine = @{ 'ops.Action' = [System.Collections.Generic.List[object]]::new() }
$paddedActionEngine['ops.Action'].Add([ordered]@{ ActionCode='KEEP'; EngineCode='DATABASE_SETTINGS ' })
Assert-Throws 'SQL-equivalent right-padded retired engine reference is rejected' { Assert-NoRetiredCatalogMetadata -Rows $paddedActionEngine } '*retired engine*'

$paddedV8Engine = @{ 'ops.Engine' = [System.Collections.Generic.List[object]]::new() }
$paddedV8Engine['ops.Engine'].Add([ordered]@{ EngineCode='v8_keycloak_config  ' })
Assert-Throws 'case-and-padding variant of retired V8 engine row is rejected' { Assert-NoRetiredCatalogMetadata -Rows $paddedV8Engine } '*Retired engine*'

$paddedLegacyEngine = @{ 'ops.Engine' = [System.Collections.Generic.List[object]]::new() }
$paddedLegacyEngine['ops.Engine'].Add([ordered]@{ EngineCode='DATABASE_SETTINGS   ' })
Assert-Throws 'SQL-equivalent right-padded DATABASE_SETTINGS engine row is rejected' { Assert-NoRetiredCatalogMetadata -Rows $paddedLegacyEngine } '*Retired engine*'

$paddedChild = @{ 'ops.ActionStep' = [System.Collections.Generic.List[object]]::new() }
$paddedChild['ops.ActionStep'].Add([ordered]@{ ParentActionCode='OTHER'; StepOrder=[long]99; ChildActionCode='V8_KEYCLOAK_CONFIG ' })
Assert-Throws 'SQL-equivalent right-padded V8 child reference is rejected' { Assert-NoRetiredCatalogMetadata -Rows $paddedChild } '*Retired action reference*'

$paddedParent = @{ 'ops.ActionStep' = [System.Collections.Generic.List[object]]::new() }
$paddedParent['ops.ActionStep'].Add([ordered]@{ ParentActionCode='v8_keycloak_config '; StepOrder=[long]10; ChildActionCode='KEEP' })
Assert-Throws 'case-and-padding variant of retired V8 parent reference is rejected' { Assert-NoRetiredCatalogMetadata -Rows $paddedParent } '*Retired action reference*'

$paddedDependent = @{ 'ops.ActionRequirement' = [System.Collections.Generic.List[object]]::new() }
$paddedDependent['ops.ActionRequirement'].Add([ordered]@{ ActionCode='V8_KEYCLOAK_CONFIG '; RequirementCode='R1' })
Assert-Throws 'SQL-equivalent right-padded V8 dependent metadata is rejected' { Assert-NoRetiredCatalogMetadata -Rows $paddedDependent } '*ops.ActionRequirement*'

Write-Host ('Retired identifier SQL-equivalence tests: {0} passed, {1} failed.' -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
