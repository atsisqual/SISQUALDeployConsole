#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ContractVersion = '0.1-proposed'
$script:EngineCode = 'DEPLOYMENT_PREFLIGHT'
$script:EngineVersion = '1.0.0'
$script:Issues = [System.Collections.Generic.List[object]]::new()
$script:Tables = @{}
$script:Request = $null
$script:Connection = $null

function Exit-InvalidRequest {
    exit 2
}

function Get-Field {
    param([AllowNull()][object]$Object,[Parameter(Mandatory)][string]$Name,[AllowNull()][object]$Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($key in $Object.Keys) {
            if ([string]::Equals([string]$key,$Name,[StringComparison]::OrdinalIgnoreCase)) { return $Object[$key] }
        }
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Test-Enabled {
    param([AllowNull()][object]$Row)
    $value = Get-Field $Row 'IsEnabled' 1
    if ($null -eq $value -or $value -is [DBNull]) { return $false }
    return ([int]$value -eq 1)
}

function Add-Issue {
    param(
        [Parameter(Mandatory)][ValidateSet('ERROR','WARNING','INFO')][string]$Severity,
        [Parameter(Mandatory)][string]$Area,
        [Parameter(Mandatory)][string]$Code,
        [AllowEmptyString()][string]$Object = '',
        [AllowEmptyString()][string]$InstanceCode = '',
        [AllowEmptyString()][string]$Details = ''
    )
    if ($Area -notmatch '^[A-Z][A-Z0-9_]{1,59}$') { $Area = 'MODEL_REVIEW' }
    if ([string]::IsNullOrWhiteSpace($Code)) { $Code = 'UNKNOWN_ISSUE' }
    $safeObject = if ([string]::IsNullOrWhiteSpace($Object)) { $Code } else { $Code + ':' + $Object }
    if ($safeObject.Length -gt 400) { $safeObject = $safeObject.Substring(0,400) }
    if ($Details.Length -gt 1800) { $Details = $Details.Substring(0,1800) }
    $script:Issues.Add([pscustomobject]@{
        Severity = $Severity
        Area = $Area
        Code = $Code
        Object = $safeObject
        InstanceCode = $InstanceCode
        Details = $Details
    })
}

function Test-CancelRequested {
    if ($null -eq $script:Request) { return $false }
    $path = [string](Get-Field $script:Request 'cancelPath' '')
    return (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path))
}

function Assert-NotCancelled {
    if (Test-CancelRequested) { throw [System.OperationCanceledException]::new('CANCELLED') }
}

function ConvertTo-SqliteIdentifier {
    param([Parameter(Mandatory)][string]$Name)
    if ($Name -notmatch '^[A-Za-z][A-Za-z0-9_]{1,127}$') { throw 'INVALID_LOCAL_TABLE_NAME' }
    return '[' + $Name + ']'
}

function Test-CatalogTable {
    param([Parameter(Mandatory)][string]$Name)
    $command = $script:Connection.CreateCommand()
    try {
        $command.CommandText = 'SELECT COUNT(*) FROM sqlite_master WHERE type=''table'' AND name=$name;'
        $parameter = $command.CreateParameter()
        $parameter.ParameterName = '$name'
        $parameter.Value = $Name
        [void]$command.Parameters.Add($parameter)
        return ([int64]$command.ExecuteScalar() -eq 1)
    }
    finally { $command.Dispose() }
}

function Get-CatalogRows {
    param([Parameter(Mandatory)][string]$Name)
    if ($script:Tables.ContainsKey($Name)) { return @($script:Tables[$Name]) }
    if (-not (Test-CatalogTable $Name)) {
        $script:Tables[$Name] = @()
        return @()
    }
    $identifier = ConvertTo-SqliteIdentifier $Name
    $command = $script:Connection.CreateCommand()
    try {
        $command.CommandText = 'SELECT * FROM ' + $identifier + ';'
        $reader = $command.ExecuteReader()
        try {
            $rows = [System.Collections.Generic.List[object]]::new()
            while ($reader.Read()) {
                $values = [ordered]@{}
                for ($i=0; $i -lt $reader.FieldCount; $i++) {
                    $value = $reader.GetValue($i)
                    if ($value -is [DBNull]) { $value = $null }
                    $values[$reader.GetName($i)] = $value
                }
                $rows.Add([pscustomobject]$values)
            }
            $script:Tables[$Name] = @($rows)
            return @($rows)
        }
        finally { $reader.Dispose() }
    }
    finally { $command.Dispose() }
}

function Get-EnabledRows {
    param([Parameter(Mandatory)][string]$Name)
    return @(Get-CatalogRows $Name | Where-Object { Test-Enabled $_ })
}

function Get-InstanceRoot {
    param([Parameter(Mandatory)][object]$Server,[Parameter(Mandatory)][object]$Instance)
    $servicesRoot = [string](Get-Field $Server 'ServicesRoot' '')
    $hostName = [string](Get-Field $Instance 'HostName' '')
    if ([string]::IsNullOrWhiteSpace($servicesRoot) -or [string]::IsNullOrWhiteSpace($hostName)) { return '' }
    return [IO.Path]::GetFullPath((Join-Path $servicesRoot $hostName))
}

function Expand-LocalTemplate {
    param([AllowNull()][string]$Template,[Parameter(Mandatory)][object]$Server,[Parameter(Mandatory)][object]$Instance)
    if ([string]::IsNullOrWhiteSpace($Template)) { return '' }
    $instanceRoot = Get-InstanceRoot $Server $Instance
    $values = [ordered]@{
        '{INSTANCE_ROOT}' = $instanceRoot
        '{INSTANCE_CODE}' = [string](Get-Field $Instance 'InstanceCode' '')
        '{HOST_NAME}' = [string](Get-Field $Instance 'HostName' '')
        '{COUNTRY_CODE}' = [string](Get-Field $Instance 'CountryCode' '')
        '{CUSTOMER_CODE}' = [string](Get-Field $Instance 'CustomerCode' '')
        '{SERVER_CODE}' = [string](Get-Field $Server 'ServerCode' '')
        '{MACHINE_NAME}' = [string](Get-Field $Server 'MachineName' '')
        '{SERVICES_ROOT}' = [string](Get-Field $Server 'ServicesRoot' '')
        '{CONFIG_BACKUP_ROOT}' = [string](Get-Field $Server 'ConfigBackupRoot' '')
        '{SQL_INSTANCE}' = [string](Get-Field $Instance 'SqlInstanceName' '')
    }
    $result = $Template
    foreach ($key in $values.Keys) { $result = $result.Replace($key,[string]$values[$key],[StringComparison]::Ordinal) }
    return $result
}

function Get-SelectedInstances {
    param([Parameter(Mandatory)][object[]]$Instances,[AllowNull()][string]$RequestedCode)
    $enabled = @($Instances | Where-Object { Test-Enabled $_ })
    if ([string]::IsNullOrWhiteSpace($RequestedCode)) { return $enabled }
    $matches = @($enabled | Where-Object { [string](Get-Field $_ 'InstanceCode' '') -ceq $RequestedCode })
    if ($matches.Count -ne 1) { throw 'INSTANCE_NOT_FOUND' }
    return $matches
}

function Test-SecretPresent {
    param([Parameter(Mandatory)][string]$CredentialRef)
    $secrets = Get-Field $script:Request 'secrets' $null
    if ($null -eq $secrets) { return $false }
    $property = $secrets.PSObject.Properties[$CredentialRef]
    return ($null -ne $property -and -not [string]::IsNullOrEmpty([string]$property.Value))
}

function Get-SecretHash {
    param([Parameter(Mandatory)][string]$CredentialRef)
    $secrets = Get-Field $script:Request 'secrets' $null
    if ($null -eq $secrets) { return '' }
    $property = $secrets.PSObject.Properties[$CredentialRef]
    if ($null -eq $property -or [string]::IsNullOrEmpty([string]$property.Value)) { return '' }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes([string]$property.Value)
    try { return ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant() }
    finally { [Array]::Clear($bytes,0,$bytes.Length) }
}

function Invoke-ReviewManagementModel {
    param($Context)
    $servers = @($Context.Servers | Where-Object { Test-Enabled $_ })
    if ($servers.Count -eq 0) { Add-Issue ERROR MANAGEMENT_MODEL LOCAL_SERVER_MISSING }
    elseif ($servers.Count -gt 1) { Add-Issue ERROR MANAGEMENT_MODEL LOCAL_SERVER_MULTIPLE }
    if ($servers.Count -eq 1) {
        $serverCode = [string](Get-Field $servers[0] 'ServerCode' '')
        foreach ($instance in @($Context.Instances | Where-Object { Test-Enabled $_ })) {
            $instanceServer = [string](Get-Field $instance 'ServerCode' $serverCode)
            if (-not [string]::IsNullOrEmpty($instanceServer) -and $instanceServer -cne $serverCode) {
                Add-Issue ERROR MANAGEMENT_MODEL INSTANCE_SERVER_MISMATCH ([string](Get-Field $instance 'InstanceCode' '')) ([string](Get-Field $instance 'InstanceCode' ''))
            }
        }
    }
}

function Invoke-ReviewApplicationCatalog {
    param($Context)
    $applications = @(Get-EnabledRows 'cfg_Application')
    $seen = @{}
    foreach ($application in $applications) {
        $code = [string](Get-Field $application 'ApplicationCode' '')
        if ([string]::IsNullOrWhiteSpace($code)) { Add-Issue ERROR APPLICATION_CATALOG APPLICATION_CODE_MISSING; continue }
        if ($seen.ContainsKey($code)) { Add-Issue ERROR APPLICATION_CATALOG APPLICATION_CODE_DUPLICATE $code } else { $seen[$code] = $true }
    }
    foreach ($file in @(Get-EnabledRows 'cfg_ConfigFile')) {
        $applicationCode = [string](Get-Field $file 'ApplicationCode' '')
        if (-not [string]::IsNullOrWhiteSpace($applicationCode) -and -not $seen.ContainsKey($applicationCode)) {
            Add-Issue ERROR APPLICATION_CATALOG CONFIG_FILE_APPLICATION_MISSING $applicationCode
        }
    }
}

function Invoke-ReviewManagedAssets {
    param($Context)
    $destinations = @(Get-EnabledRows 'cfg_ManagedAssetDestination')
    if ($destinations.Count -eq 0) { Add-Issue ERROR MANAGED_ASSETS ASSET_DESTINATION_MISSING }
    foreach ($instance in $Context.SelectedInstances) {
        $code = [string](Get-Field $instance 'InstanceCode' '')
        $logo = Get-Field $instance 'CustomerLogo' $null
        $hash = [string](Get-Field $instance 'CustomerLogoSha256' '')
        if ($null -eq $logo -or ($logo -is [byte[]] -and $logo.Length -eq 0)) { Add-Issue ERROR MANAGED_ASSETS ENABLED_INSTANCE_LOGO_MISSING $code $code }
        elseif ([string]::IsNullOrWhiteSpace($hash)) { Add-Issue ERROR MANAGED_ASSETS ENABLED_INSTANCE_LOGO_HASH_MISSING $code $code }
    }
}

function Invoke-ReviewRepairModel {
    param($Context)
    $files = @(Get-EnabledRows 'cfg_ConfigFile')
    $fileById = @{}
    foreach ($file in $files) { $fileById[[string](Get-Field $file 'FileID' '')] = $file }
    foreach ($rule in @(Get-EnabledRows 'cfg_ConfigRule')) {
        $fileId = [string](Get-Field $rule 'FileID' '')
        if ([string]::IsNullOrWhiteSpace($fileId) -or -not $fileById.ContainsKey($fileId)) { Add-Issue ERROR REPAIR_MODEL CONFIG_RULE_FILE_MISSING ([string](Get-Field $rule 'RuleCode' $fileId)) }
    }
    foreach ($policy in @(Get-EnabledRows 'cfg_ConfigFileRepairPolicy')) {
        $fileId = [string](Get-Field $policy 'FileID' '')
        if (-not $fileById.ContainsKey($fileId)) { Add-Issue ERROR REPAIR_MODEL CONFIG_REPAIR_FILE_MISSING $fileId }
        $mode = [string](Get-Field $policy 'RepairMode' 'PATCH')
        if ($mode -notin @('PATCH','REPLACE')) { Add-Issue ERROR REPAIR_MODEL CONFIG_REPAIR_MODE_INVALID $fileId }
    }
}

function Invoke-ReviewIisModel {
    param($Context)
    if (@(Get-EnabledRows 'cfg_IisServerPolicy').Count -eq 0) { Add-Issue ERROR IIS_MODEL SERVER_POLICY_MISSING }
    $applications = @(Get-EnabledRows 'cfg_Application')
    $appCodes = @{}
    foreach ($app in $applications) { $appCodes[[string](Get-Field $app 'ApplicationCode' '')] = $true }
    foreach ($definition in @(Get-EnabledRows 'cfg_IisApplicationDefinition')) {
        $code = [string](Get-Field $definition 'IisApplicationCode' '')
        if (-not [string]::IsNullOrWhiteSpace($code) -and -not $appCodes.ContainsKey($code)) { Add-Issue ERROR IIS_MODEL IIS_APPLICATION_MISSING $code }
    }
}

function Invoke-ReviewExtendedApplications {
    param($Context)
    foreach ($application in @(Get-EnabledRows 'cfg_Application')) {
        $code = [string](Get-Field $application 'ApplicationCode' '')
        $path = [string](Get-Field $application 'PhysicalPathTemplate' '')
        if ([string]::IsNullOrWhiteSpace($path)) { Add-Issue ERROR EXTENDED_APPLICATIONS APPLICATION_PHYSICAL_PATH_MISSING $code }
    }
}

function Invoke-ReviewWindowsServices {
    param($Context)
    $definitions = @(Get-EnabledRows 'cfg_WindowsServiceDefinition')
    if ($definitions.Count -eq 0) { Add-Issue ERROR WINDOWS_SERVICES WINDOWS_SERVICE_DEFINITION_MISSING }
    $nameSet = @{}
    foreach ($instance in $Context.SelectedInstances) {
        $instanceCode = [string](Get-Field $instance 'InstanceCode' '')
        $user = [string](Get-Field $instance 'IisIdentityUserName' '')
        if ([string]::IsNullOrWhiteSpace($user)) { Add-Issue ERROR WINDOWS_SERVICES SERVICE_ACCOUNT_USERNAME_MISSING $instanceCode $instanceCode }
        $credentialRef = 'IIS_IDENTITY.' + $instanceCode
        if (-not (Test-SecretPresent $credentialRef)) { Add-Issue ERROR WINDOWS_SERVICES SERVICE_ACCOUNT_PASSWORD_MISSING $instanceCode $instanceCode }
        foreach ($definition in $definitions) {
            $template = [string](Get-Field $definition 'ServiceNameTemplate' '')
            $name = Expand-LocalTemplate $template $Context.Server $instance
            if ($name.Length -gt 256) { Add-Issue ERROR WINDOWS_SERVICES SERVICE_NAME_TOO_LONG $name $instanceCode }
            if (-not [string]::IsNullOrWhiteSpace($name)) {
                if ($nameSet.ContainsKey($name)) { Add-Issue ERROR WINDOWS_SERVICES DUPLICATE_SERVICE_NAME $name $instanceCode } else { $nameSet[$name] = $instanceCode }
            }
        }
    }
    $userHashes = @{}
    foreach ($instance in $Context.SelectedInstances) {
        $instanceCode = [string](Get-Field $instance 'InstanceCode' '')
        $user = [string](Get-Field $instance 'IisIdentityUserName' '')
        $hash = Get-SecretHash ('IIS_IDENTITY.' + $instanceCode)
        if (-not [string]::IsNullOrWhiteSpace($user) -and -not [string]::IsNullOrWhiteSpace($hash)) {
            if ($userHashes.ContainsKey($user) -and $userHashes[$user] -cne $hash) { Add-Issue ERROR WINDOWS_SERVICES SERVICE_IDENTITY_PASSWORD_CONFLICT $user }
            else { $userHashes[$user] = $hash }
        }
    }
}

function Invoke-ReviewWebAccess {
    param($Context)
    if (@(Get-EnabledRows 'cfg_WebAccessPolicy').Count -eq 0) { Add-Issue ERROR WEB_ACCESS WEB_ACCESS_POLICY_MISSING }
    if (@(Get-EnabledRows 'cfg_WebAccessTemplate').Count -eq 0) { Add-Issue ERROR WEB_ACCESS WEB_ACCESS_TEMPLATE_MISSING }
    $users = @{}
    foreach ($instance in $Context.SelectedInstances) {
        $code = [string](Get-Field $instance 'InstanceCode' '')
        $user = [string](Get-Field $instance 'WebAccessUserName' '')
        if ([string]::IsNullOrWhiteSpace($user)) { Add-Issue ERROR WEB_ACCESS WEB_ACCESS_USERNAME_MISSING $code $code }
        elseif ($users.ContainsKey($user)) { Add-Issue ERROR WEB_ACCESS WEB_ACCESS_DUPLICATE_LOCAL_USER $user $code } else { $users[$user] = $true }
    }
    foreach ($policy in @(Get-EnabledRows 'cfg_WebAccessPolicy')) {
        if ([string]::IsNullOrWhiteSpace([string](Get-Field $policy 'BackendBaseUrlTemplate' ''))) { Add-Issue ERROR WEB_ACCESS WEB_ACCESS_BACKEND_URL_MISSING }
        if ([string]::IsNullOrWhiteSpace([string](Get-Field $policy 'PublicLaunchBaseUrlTemplate' ''))) { Add-Issue ERROR WEB_ACCESS WEB_ACCESS_PUBLIC_URL_MISSING }
    }
}

function Invoke-ReviewLinksModel {
    param($Context)
    if (@(Get-EnabledRows 'cfg_LinksPagePolicy').Count -eq 0) { Add-Issue ERROR LINKS_MODEL LINKS_PAGE_POLICY_MISSING }
    foreach ($row in @(Get-EnabledRows 'cfg_LinksProfileInstance')) {
        $instanceCode = [string](Get-Field $row 'InstanceCode' '')
        if (@($Context.Instances | Where-Object { [string](Get-Field $_ 'InstanceCode' '') -ceq $instanceCode }).Count -eq 0) { Add-Issue ERROR LINKS_MODEL LINKS_INSTANCE_MISSING $instanceCode $instanceCode }
    }
    $profiles = @(Get-EnabledRows 'cfg_LinksProfile')
    if ($profiles.Count -eq 0) { Add-Issue ERROR LINKS_MODEL LINKS_PROFILE_MISSING }
}

function Invoke-ReviewLinksPresentation {
    param($Context)
    $templates = @(Get-EnabledRows 'cfg_LinksPageTemplate')
    if ($templates.Count -eq 0) { Add-Issue ERROR LINKS_PRESENTATION LINKS_PAGE_TEMPLATE_MISSING }
    if (@(Get-EnabledRows 'cfg_LinksPagePresentationResource').Count -eq 0) { Add-Issue ERROR LINKS_PRESENTATION LINKS_PRESENTATION_RESOURCE_MISSING }
    # The QR asset of a customer is the global asset QR_CHANNEL_<CustomerCode> (docs/migration/instance-directory-design.md). Codes and severities are those
    # of the original review: a missing asset is a WARNING for an enabled PT or ES instance with a customer code, an unassigned asset is INFO.
    $assets = @(Get-EnabledRows 'cfg_LinksPageAsset')
    $assetCodes = @{}
    foreach ($asset in $assets) { $assetCodes[[string](Get-Field $asset 'AssetCode' '')] = $true }
    foreach ($instance in $Context.SelectedInstances) {
        $customer = [string](Get-Field $instance 'CustomerCode' '')
        $country = [string](Get-Field $instance 'CountryCode' '')
        if ([string]::IsNullOrWhiteSpace($customer) -or $country -cnotin @('PT','ES')) { continue }
        $instanceCode = [string](Get-Field $instance 'InstanceCode' '')
        if (-not $assetCodes.ContainsKey('QR_CHANNEL_' + $customer)) { Add-Issue WARNING LINKS_PRESENTATION QR_ASSET_MISSING ($instanceCode + ' / ' + $customer) $instanceCode 'No QR asset is configured for this enabled PT/ES environment.' }
    }
    $assignedAssetCodes = @{}
    foreach ($instance in @($Context.Instances | Where-Object { Test-Enabled $_ })) {
        $customer = [string](Get-Field $instance 'CustomerCode' '')
        if (-not [string]::IsNullOrWhiteSpace($customer)) { $assignedAssetCodes['QR_CHANNEL_' + $customer] = $true }
    }
    foreach ($asset in $assets) {
        $assetCode = [string](Get-Field $asset 'AssetCode' '')
        if (-not $assetCode.StartsWith('QR_CHANNEL_', [StringComparison]::Ordinal)) { continue }
        $hash = [string](Get-Field $asset 'ContentSha256' '')
        $bytes = Get-Field $asset 'Content' $null
        if ($null -ne $bytes -and $bytes -is [byte[]] -and -not [string]::IsNullOrWhiteSpace($hash)) {
            $actual = ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
            if ($actual -cne $hash.ToLowerInvariant()) { Add-Issue ERROR LINKS_PRESENTATION QR_CONTENT_HASH_MISMATCH $assetCode }
        }
        if (-not $assignedAssetCodes.ContainsKey($assetCode)) { Add-Issue INFO LINKS_PRESENTATION QR_ASSET_UNASSIGNED $assetCode '' 'The QR asset is currently not assigned to an enabled ManagedInstance.' }
    }
}

function Invoke-ReviewPulseModel {
    param($Context)
    $profiles = @(Get-EnabledRows 'cfg_PulseProfile')
    if ($profiles.Count -eq 0) { Add-Issue ERROR PULSE_MODEL PULSE_HUB_NOT_FOUND }
    foreach ($profile in $profiles) {
        $hub = [string](Get-Field $profile 'HubInstanceCode' '')
        $hubRows = @($Context.Instances | Where-Object { (Test-Enabled $_) -and [string](Get-Field $_ 'InstanceCode' '') -ceq $hub })
        if ($hubRows.Count -ne 1) { Add-Issue ERROR PULSE_MODEL PULSE_HUB_NOT_FOUND $hub; continue }
        if (-not (Test-SecretPresent ('IIS_IDENTITY.' + $hub))) { Add-Issue ERROR PULSE_MODEL PULSE_TASK_CREDENTIAL_MISSING $hub $hub }
    }
    $applications = @{}
    foreach ($app in @(Get-EnabledRows 'cfg_Application')) { $applications[[string](Get-Field $app 'ApplicationCode' '')] = $true }
    foreach ($policy in @(Get-EnabledRows 'cfg_PulseHttpPolicy')) {
        $code = [string](Get-Field $policy 'ApplicationCode' '')
        if (-not $applications.ContainsKey($code)) { Add-Issue ERROR PULSE_MODEL PULSE_HTTP_APPLICATION_MISSING $code }
    }
    $resources = @(Get-EnabledRows 'cfg_PulseResource')
    if (@($resources | Where-Object { [string](Get-Field $_ 'ResourceCode' '') -ceq 'PULSE_INDEX_HTML' }).Count -eq 0) { Add-Issue ERROR PULSE_MODEL PULSE_PAGE_TEMPLATE_MISSING PULSE_INDEX_HTML }
    if (@($resources | Where-Object { [string](Get-Field $_ 'ResourceCode' '') -ceq 'PULSE_LOGO' }).Count -eq 0) { Add-Issue ERROR PULSE_MODEL PULSE_LOGO_MISSING PULSE_LOGO }
    foreach ($resource in $resources) {
        $hash = [string](Get-Field $resource 'ContentSha256' '')
        $text = Get-Field $resource 'TextContent' $null
        $binary = Get-Field $resource 'BinaryContent' $null
        if ([string]::IsNullOrWhiteSpace($hash)) { continue }
        $bytes = if ($null -ne $text) { [Text.Encoding]::Unicode.GetBytes([string]$text) } elseif ($binary -is [byte[]]) { $binary } else { $null }
        if ($null -ne $bytes) {
            $actual = ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))).ToLowerInvariant()
            if ($actual -cne $hash.ToLowerInvariant()) { Add-Issue ERROR PULSE_MODEL PULSE_RESOURCE_HASH_MISMATCH ([string](Get-Field $resource 'ResourceCode' '')) }
        }
    }
}

function Invoke-ReviewOperationsFramework {
    param($Context)
    $engines = @(Get-EnabledRows 'ops_Engine')
    $engineByCode = @{}
    foreach ($engine in $engines) { $engineByCode[[string](Get-Field $engine 'EngineCode' '')] = $engine }
    foreach ($action in @(Get-EnabledRows 'ops_Action')) {
        if ([string](Get-Field $action 'ActionType' '') -cne 'ENGINE') { continue }
        $code = [string](Get-Field $action 'EngineCode' '')
        if ([string]::IsNullOrWhiteSpace($code) -or -not $engineByCode.ContainsKey($code)) { Add-Issue ERROR OPERATIONS_FRAMEWORK OPS_ACTION_WITHOUT_ENGINE ([string](Get-Field $action 'ActionCode' '')) }
    }
    if (@($Context.Servers | Where-Object { Test-Enabled $_ }).Count -ne 1) { Add-Issue ERROR OPERATIONS_FRAMEWORK OPS_LOCAL_SERVER_MISSING }
    $packageRoot = $Context.PackageRoot
    foreach ($engine in $engines) {
        $leaf = [string](Get-Field $engine 'SourceFileName' '')
        if ($leaf -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*\.ps1$' -or $leaf.Contains('..') -or $leaf.Contains('/') -or $leaf.Contains('\')) { Add-Issue ERROR OPERATIONS_FRAMEWORK OPS_REQUIRED_OBJECT_MISSING ([string](Get-Field $engine 'EngineCode' '')); continue }
        $relative = 'engines/' + $leaf
        $entries = @($Context.ManifestFiles | Where-Object { [string](Get-Field $_ 'path' '') -ceq $relative })
        $path = Join-Path (Join-Path $packageRoot 'engines') $leaf
        if ($entries.Count -ne 1 -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-Issue ERROR OPERATIONS_FRAMEWORK OPS_REQUIRED_OBJECT_MISSING ([string](Get-Field $engine 'EngineCode' '')); continue }
        $expected = [string](Get-Field $entries[0] 'sha256' '')
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expected -cne $actual) { Add-Issue ERROR OPERATIONS_FRAMEWORK OPS_ENGINE_HASH_MISMATCH ([string](Get-Field $engine 'EngineCode' '')) }
    }
}

function Invoke-RequiredFileChecks {
    param($Context)
    $files = @(Get-EnabledRows 'cfg_ConfigFile')
    $rules = @(Get-EnabledRows 'cfg_ConfigRule')
    $requiredFileIds = @{}
    foreach ($file in $files) { if ([int](Get-Field $file 'IsRequired' 0) -eq 1) { $requiredFileIds[[string](Get-Field $file 'FileID' '')] = $true } }
    $applications = @{}
    foreach ($app in @(Get-EnabledRows 'cfg_Application')) { $applications[[string](Get-Field $app 'ApplicationCode' '')] = $app }
    $policies = @{}
    foreach ($policy in @(Get-EnabledRows 'cfg_ConfigFileRepairPolicy')) { $policies[[string](Get-Field $policy 'FileID' '')] = [string](Get-Field $policy 'RepairMode' 'PATCH') }
    foreach ($instance in $Context.SelectedInstances) {
        Assert-NotCancelled
        $instanceCode = [string](Get-Field $instance 'InstanceCode' '')
        $instanceRoot = Get-InstanceRoot $Context.Server $instance
        if ([string]::IsNullOrWhiteSpace($instanceRoot) -or -not (Test-Path -LiteralPath $instanceRoot -PathType Container)) {
            Add-Issue ERROR APPLICATION_TREE INSTANCE_ROOT_MISSING $instanceCode $instanceCode
            continue
        }
        foreach ($file in $files) {
            $fileId = [string](Get-Field $file 'FileID' '')
            if (-not $requiredFileIds.ContainsKey($fileId)) { continue }
            $applicationCode = [string](Get-Field $file 'ApplicationCode' '')
            $basePath = $instanceRoot
            if (-not [string]::IsNullOrWhiteSpace($applicationCode) -and $applications.ContainsKey($applicationCode)) {
                $template = [string](Get-Field $applications[$applicationCode] 'PhysicalPathTemplate' '')
                $expanded = Expand-LocalTemplate $template $Context.Server $instance
                if (-not [string]::IsNullOrWhiteSpace($expanded)) { $basePath = $expanded }
            }
            $relative = [string](Get-Field $file 'RelativePath' '')
            if ([string]::IsNullOrWhiteSpace($relative) -or [string]::IsNullOrWhiteSpace($basePath)) { Add-Issue ERROR APPLICATION_TREE REQUIRED_PATH_EMPTY $fileId $instanceCode; continue }
            $fullPath = [IO.Path]::GetFullPath((Join-Path $basePath $relative))
            $mode = if ($policies.ContainsKey($fileId)) { $policies[$fileId] } else { 'PATCH' }
            if ($mode -ceq 'REPLACE') {
                $parent = Split-Path -Parent $fullPath
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) { Add-Issue ERROR APPLICATION_TREE REQUIRED_PARENT_MISSING $fileId $instanceCode }
            }
            elseif (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { Add-Issue ERROR APPLICATION_TREE REQUIRED_FILE_MISSING $fileId $instanceCode }
        }
    }
}

function Invoke-ServiceFileChecks {
    param($Context)
    $definitions = @(Get-EnabledRows 'cfg_WindowsServiceDefinition')
    foreach ($instance in $Context.SelectedInstances) {
        Assert-NotCancelled
        $instanceCode = [string](Get-Field $instance 'InstanceCode' '')
        foreach ($definition in $definitions) {
            $template = [string](Get-Field $definition 'ExecutablePathTemplate' '')
            $path = Expand-LocalTemplate $template $Context.Server $instance
            if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-Issue ERROR WINDOWS_SERVICE SERVICE_EXECUTABLE_MISSING ([string](Get-Field $definition 'ServiceCode' '')) $instanceCode }
        }
        if ([string]::IsNullOrWhiteSpace([string](Get-Field $instance 'IisIdentityUserName' ''))) { Add-Issue ERROR WINDOWS_SERVICE IIS_IDENTITY_USERNAME_PENDING $instanceCode $instanceCode }
        if (-not (Test-SecretPresent ('IIS_IDENTITY.' + $instanceCode))) { Add-Issue ERROR WINDOWS_SERVICE IIS_IDENTITY_PASSWORD_PENDING $instanceCode $instanceCode }
    }
}

function Open-PreflightCatalog {
    param([Parameter(Mandatory)][string]$PackageRoot,[Parameter(Mandatory)][string]$CatalogPath,[Parameter(Mandatory)][object[]]$ManifestFiles)
    # The modules run inside this process: each is compared with the manifest immediately before it is imported, as the host does with the engine file.
    foreach ($relative in @('runtime/Sisqual.Runtime.Catalog.psm1','runtime/Sisqual.Runtime.Catalog.Core.ps1')) {
        $entry = @($ManifestFiles | Where-Object { [string](Get-Field $_ 'path' '') -ceq $relative })
        if ($entry.Count -ne 1) { throw 'RUNTIME_MODULE_MANIFEST_MISSING' }
        $moduleFile = Join-Path $PackageRoot ($relative -replace '/',[string][IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $moduleFile -PathType Leaf)) { throw 'RUNTIME_CATALOG_MODULE_MISSING' }
        if ((Get-FileHash -LiteralPath $moduleFile -Algorithm SHA256).Hash.ToLowerInvariant() -cne ([string](Get-Field $entry[0] 'sha256' '')).ToLowerInvariant()) { throw 'RUNTIME_MODULE_HASH_MISMATCH' }
    }
    $catalogModule = Join-Path $PackageRoot 'runtime\Sisqual.Runtime.Catalog.psm1'
    if (-not (Test-Path -LiteralPath $catalogModule -PathType Leaf)) { throw 'RUNTIME_CATALOG_MODULE_MISSING' }
    Import-Module $catalogModule -Force -ErrorAction Stop
    $providerEntries = @($ManifestFiles | Where-Object { [string](Get-Field $_ 'path' '') -like 'runtime/sqlite-provider/*' })
    if ($providerEntries.Count -eq 0) { throw 'SQLITE_PROVIDER_MANIFEST_MISSING' }
    [void](Initialize-SisqualRuntimeSqliteProvider -PackageRoot $PackageRoot -ProviderRoot 'runtime\sqlite-provider' -VerifiedFiles $providerEntries)
    foreach ($suffix in @('-wal','-shm','-journal')) { if (Test-Path -LiteralPath ($CatalogPath + $suffix)) { throw 'CATALOG_SIDECAR_NOT_ALLOWED' } }
    $uri = [Uri]::new([IO.Path]::GetFullPath($CatalogPath)).AbsoluteUri + '?immutable=1'
    $builder = [Microsoft.Data.Sqlite.SqliteConnectionStringBuilder]::new()
    $builder.DataSource = $uri
    $builder.Mode = [Microsoft.Data.Sqlite.SqliteOpenMode]::ReadOnly
    $builder.Cache = [Microsoft.Data.Sqlite.SqliteCacheMode]::Private
    $builder.Pooling = $false
    $connection = [Microsoft.Data.Sqlite.SqliteConnection]::new($builder.ConnectionString)
    $connection.Open()
    $command = $connection.CreateCommand()
    try { $command.CommandText = 'PRAGMA query_only=ON;'; [void]$command.ExecuteNonQuery() } finally { $command.Dispose() }
    $command = $connection.CreateCommand()
    try { $command.CommandText = 'PRAGMA integrity_check;'; if ([string]$command.ExecuteScalar() -cne 'ok') { throw 'CATALOG_INTEGRITY_FAILED' } } finally { $command.Dispose() }
    foreach ($suffix in @('-wal','-shm','-journal')) { if (Test-Path -LiteralPath ($CatalogPath + $suffix)) { $connection.Dispose(); throw 'CATALOG_SIDECAR_NOT_ALLOWED' } }
    return $connection
}

function Write-EngineResult {
    param([Parameter(Mandatory)][string]$ResultPath,[Parameter(Mandatory)][datetime]$StartedAt,[bool]$Cancelled = $false)
    $now = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $errorCount = @($script:Issues | Where-Object Severity -eq 'ERROR').Count
    $warningCount = @($script:Issues | Where-Object Severity -eq 'WARNING').Count
    # When the catalog could not be opened (a module that no longer matches the manifest, the provider, the file) there is nothing to count, and the result
    # must still be written: one target, failed.
    $targetCount = 1
    if ($null -ne $script:Connection) {
        try { $targetCount = [Math]::Max(1,@(Get-SelectedInstances -Instances (Get-CatalogRows 'dbo_ManagedInstance') -RequestedCode ([string](Get-Field $script:Request 'instanceCode' ''))).Count) }
        catch { $targetCount = 1 }
    }
    # A failed target is an instance with at least one ERROR; an ERROR that belongs to no instance (the catalog or the server) fails one target.
    $failedInstanceCount = @($script:Issues | Where-Object { $_.Severity -eq 'ERROR' -and -not [string]::IsNullOrWhiteSpace([string]$_.InstanceCode) } | ForEach-Object { [string]$_.InstanceCode } | Sort-Object -Unique).Count
    $globalErrors = @($script:Issues | Where-Object { $_.Severity -eq 'ERROR' -and [string]::IsNullOrWhiteSpace([string]$_.InstanceCode) }).Count
    $failedTargets = [Math]::Min($targetCount, $failedInstanceCount + $(if ($failedInstanceCount -eq 0 -and ($globalErrors -gt 0 -or $Cancelled)) { 1 } else { 0 }))
    $succeededTargets = if ($failedTargets -eq 0) { $targetCount } else { [Math]::Max(0,$targetCount - $failedTargets) }
    $severityOrder = @{ ERROR=0; WARNING=1; INFO=2 }
    $rows = foreach ($issue in @($script:Issues | Sort-Object @{Expression={$severityOrder[$_.Severity]}},Area,InstanceCode,Object)) {
        [ordered]@{
            timestamp = $now
            instanceCode = [string]$issue.InstanceCode
            operationType = [string]$issue.Area
            object = [string]$issue.Object
            status = [string]$issue.Severity
            details = [string]$issue.Details
        }
    }
    $succeeded = ($errorCount -eq 0 -and -not $Cancelled)
    $result = [ordered]@{
        contractVersion = $script:ContractVersion
        operationId = [string](Get-Field $script:Request 'operationId' '')
        engineCode = $script:EngineCode
        engineVersion = $script:EngineVersion
        mode = 'PREVIEW'
        startedAt = $StartedAt.ToString('yyyy-MM-ddTHH:mm:ssZ')
        completedAt = $now
        succeeded = $succeeded
        exitCode = if ($succeeded) { 0 } else { 1 }
        errorMessage = if ($Cancelled) { 'CANCELLED' } elseif ($errorCount -gt 0) { 'PREFLIGHT_ERRORS' } else { '' }
        summary = [ordered]@{ targetCount=$targetCount; succeededTargets=$succeededTargets; failedTargets=$failedTargets; warningCount=$warningCount; errorCount=$errorCount }
        results = @($rows)
    }
    [IO.File]::WriteAllText($ResultPath,($result | ConvertTo-Json -Compress -Depth 30),[Text.UTF8Encoding]::new($false))
    return $(if ($succeeded) { 0 } else { 1 })
}

$startedAt = [DateTime]::UtcNow
$raw = [Console]::In.ReadToEnd()
try {
    if ([string]::IsNullOrWhiteSpace($raw) -or [Text.UTF8Encoding]::new($false).GetByteCount($raw) -gt 1MB) { Exit-InvalidRequest }
    $script:Request = $raw | ConvertFrom-Json -Depth 30 -DateKind String   # ISO text must stay text: as a DateTime its string form is culture text and the deadline check would reject a valid request
    foreach ($name in @('contractVersion','operationId','engineCode','mode','catalogPath','deadlineUtc','cancelPath','resultPath','secrets')) {
        if ($null -eq $script:Request.PSObject.Properties[$name]) { Exit-InvalidRequest }
    }
    if ([string](Get-Field $script:Request 'contractVersion' '') -cne $script:ContractVersion) { Exit-InvalidRequest }
    if ([string](Get-Field $script:Request 'engineCode' '') -cne $script:EngineCode) { Exit-InvalidRequest }
    if ([string](Get-Field $script:Request 'mode' '') -cne 'PREVIEW') { Exit-InvalidRequest }
    if ([string](Get-Field $script:Request 'operationId' '') -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { Exit-InvalidRequest }
    $catalogPath = [string](Get-Field $script:Request 'catalogPath' '')
    $resultPath = [string](Get-Field $script:Request 'resultPath' '')
    if (-not [IO.Path]::IsPathFullyQualified($catalogPath) -or -not (Test-Path -LiteralPath $catalogPath -PathType Leaf) -or [string]::IsNullOrWhiteSpace($resultPath)) { Exit-InvalidRequest }
    $deadline = [datetime]::MinValue
    if (-not [datetime]::TryParseExact([string](Get-Field $script:Request 'deadlineUtc' ''),'yyyy-MM-ddTHH:mm:ssZ',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,[ref]$deadline)) { Exit-InvalidRequest }
}
catch [System.Management.Automation.ExitException] { throw }
catch { Exit-InvalidRequest }

try {
    Assert-NotCancelled
    $packageRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
    $manifestPath = Join-Path $packageRoot 'package-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'PACKAGE_MANIFEST_MISSING' }
    $manifestText = [IO.File]::ReadAllText($manifestPath,[Text.UTF8Encoding]::new($false,$true))
    $manifest = $manifestText | ConvertFrom-Json -Depth 50 -DateKind String
    $manifestFiles = @($manifest.files)
    if ($manifestFiles.Count -eq 0) { throw 'PACKAGE_MANIFEST_FILES_MISSING' }
    $script:Connection = Open-PreflightCatalog -PackageRoot $packageRoot -CatalogPath ([string](Get-Field $script:Request 'catalogPath' '')) -ManifestFiles $manifestFiles

    $servers = @(Get-CatalogRows 'dbo_ManagedServer')
    $instances = @(Get-CatalogRows 'dbo_ManagedInstance')
    $enabledServers = @($servers | Where-Object { Test-Enabled $_ })
    if ($enabledServers.Count -ne 1) { throw 'LOCAL_SERVER_INVALID' }
    $server = $enabledServers[0]
    if (-not [string]::Equals([string](Get-Field $server 'MachineName' ''),[Environment]::MachineName,[StringComparison]::OrdinalIgnoreCase)) { throw 'CATALOG_MACHINE_MISMATCH' }
    $selected = @(Get-SelectedInstances -Instances $instances -RequestedCode ([string](Get-Field $script:Request 'instanceCode' '')))
    $context = [pscustomobject]@{ Server=$server; Servers=$servers; Instances=$instances; SelectedInstances=$selected; PackageRoot=$packageRoot; ManifestFiles=$manifestFiles }

    $meta = @(Get-CatalogRows 'catalog_meta')
    if ($meta.Count -eq 1) { Add-Issue INFO CATALOG CATALOG_BUILT_AT ([string](Get-Field $meta[0] 'built_at_utc' '')) '' 'Catalog build time; no age limit is applied.' }

    Invoke-RequiredFileChecks $context
    Invoke-ServiceFileChecks $context

    $reviews = [ordered]@{
        MANAGEMENT_MODEL = ${function:Invoke-ReviewManagementModel}
        APPLICATION_CATALOG = ${function:Invoke-ReviewApplicationCatalog}
        MANAGED_ASSETS = ${function:Invoke-ReviewManagedAssets}
        REPAIR_MODEL = ${function:Invoke-ReviewRepairModel}
        IIS_MODEL = ${function:Invoke-ReviewIisModel}
        EXTENDED_APPLICATIONS = ${function:Invoke-ReviewExtendedApplications}
        WINDOWS_SERVICES = ${function:Invoke-ReviewWindowsServices}
        WEB_ACCESS = ${function:Invoke-ReviewWebAccess}
        LINKS_MODEL = ${function:Invoke-ReviewLinksModel}
        LINKS_PRESENTATION = ${function:Invoke-ReviewLinksPresentation}
        PULSE_MODEL = ${function:Invoke-ReviewPulseModel}
        OPERATIONS_FRAMEWORK = ${function:Invoke-ReviewOperationsFramework}
    }
    foreach ($entry in $reviews.GetEnumerator()) {
        Assert-NotCancelled
        try { & $entry.Value $context }
        catch [System.OperationCanceledException] { throw }
        catch { Add-Issue ERROR MODEL_REVIEW REVIEW_EXECUTION_FAILED ([string]$entry.Key) '' 'Local model review failed.' }
    }

    $exitCode = Write-EngineResult -ResultPath ([string](Get-Field $script:Request 'resultPath' '')) -StartedAt $startedAt
    exit $exitCode
}
catch [System.OperationCanceledException] {
    Add-Issue ERROR PREFLIGHT CANCELLED
    $exitCode = Write-EngineResult -ResultPath ([string](Get-Field $script:Request 'resultPath' '')) -StartedAt $startedAt -Cancelled
    exit $exitCode
}
catch {
    Add-Issue ERROR PREFLIGHT PREFLIGHT_INTERNAL_ERROR '' '' 'Preflight could not complete.'
    try {
        $exitCode = Write-EngineResult -ResultPath ([string](Get-Field $script:Request 'resultPath' '')) -StartedAt $startedAt
        exit $exitCode
    }
    catch { exit 1 }
}
finally {
    if ($null -ne $script:Connection) { try { $script:Connection.Dispose() } catch {} }
}
