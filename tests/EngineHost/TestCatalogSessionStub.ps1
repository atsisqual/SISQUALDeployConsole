#requires -Version 7.0
Set-StrictMode -Version Latest

function Initialize-SisqualEngineHostCatalogStub {
    Remove-Module Sisqual.Runtime.Catalog -Force -ErrorAction SilentlyContinue
    $module = New-Module -Name Sisqual.Runtime.Catalog -ScriptBlock {
        $script:Sessions = @{}
        function New-SisqualTestCatalogSession {
            param([Parameter(Mandatory)][string]$CatalogPath,[Parameter(Mandatory)][string]$MachineName)
            $id = [guid]::NewGuid().ToString('N')
            $script:Sessions[$id] = [pscustomobject]@{ CatalogPath = [IO.Path]::GetFullPath($CatalogPath); MachineName = $MachineName; Instances = $null }
            return [pscustomobject]@{ PSTypeName = 'Sisqual.Runtime.CatalogSession'; SessionId = $id; CatalogPath = [IO.Path]::GetFullPath($CatalogPath) }
        }
        function Set-SisqualTestCatalogMachineName {
            param([Parameter(Mandatory)][object]$Session,[Parameter(Mandatory)][string]$MachineName)
            $id = [string]$Session.SessionId
            if (-not $script:Sessions.ContainsKey($id)) { throw 'Catalog session is not active.' }
            $script:Sessions[$id].MachineName = $MachineName
        }
        function Set-SisqualTestCatalogInstances {
            # $Instances maps InstanceCode to IsEnabled. Without a call to this function every instance exists and is enabled.
            param([Parameter(Mandatory)][object]$Session,[Parameter(Mandatory)][hashtable]$Instances)
            $id = [string]$Session.SessionId
            if (-not $script:Sessions.ContainsKey($id)) { throw 'Catalog session is not active.' }
            $script:Sessions[$id].Instances = $Instances
        }
        function Get-SisqualRuntimeCatalogInstance {
            param([Parameter(Mandatory)][object]$Session,[Parameter(Mandatory)][string]$InstanceCode)
            $id = [string]$Session.SessionId
            if (-not $script:Sessions.ContainsKey($id)) { throw 'Catalog session is not active.' }
            $entry = $script:Sessions[$id]
            if ($null -eq $entry.Instances) { return [pscustomobject]@{ InstanceCode = $InstanceCode; IsEnabled = 1 } }
            if (-not $entry.Instances.ContainsKey($InstanceCode)) { return $null }
            return [pscustomobject]@{ InstanceCode = $InstanceCode; IsEnabled = [int]$entry.Instances[$InstanceCode] }
        }
        function Get-SisqualRuntimeCatalogMachineName {
            param([Parameter(Mandatory)][object]$Session)
            $id = [string]$Session.SessionId
            if (-not $script:Sessions.ContainsKey($id)) { throw 'Catalog session is not active.' }
            $entry = $script:Sessions[$id]
            if (-not [IO.Path]::GetFullPath([string]$Session.CatalogPath).Equals([string]$entry.CatalogPath,[StringComparison]::OrdinalIgnoreCase)) { throw 'Catalog session path mismatch.' }
            return [string]$entry.MachineName
        }
        Export-ModuleMember -Function New-SisqualTestCatalogSession,Set-SisqualTestCatalogMachineName,Set-SisqualTestCatalogInstances,Get-SisqualRuntimeCatalogInstance,Get-SisqualRuntimeCatalogMachineName
    }
    Import-Module $module -Global -Force
}