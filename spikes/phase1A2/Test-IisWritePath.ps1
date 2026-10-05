#requires -Version 7.0
<#
Phase 1A-2: IIS write path under PowerShell 7 with Microsoft.Web.Administration (MWA).

THIS SCRIPT MUTATES IIS, LOCAL ACCOUNTS, CERTIFICATES, THE HOSTS FILE AND ACLs.
It refuses to run outside GitHub Actions unless -IUnderstandThisMutatesTheMachine is given.
Never run it on a SISQUAL server: use a disposable VM.

Question answered: can the operations performed by the IIS_RECONCILE engine be done from PowerShell 7
through Microsoft.Web.Administration instead of the WebAdministration cmdlets and the IIS:\ provider?
#>
[CmdletBinding()]
param(
    [string]$ReportPath = '',
    [int]$ScaleSites = 10,
    [int]$ScaleAppsPerSite = 25,
    [switch]$IUnderstandThisMutatesTheMachine
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true' -and -not $IUnderstandThisMutatesTheMachine) {
    throw 'Refusing to run: this spike mutates IIS, local accounts, certificates, the hosts file and ACLs. Use a disposable VM and pass -IUnderstandThisMutatesTheMachine.'
}
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) { throw 'Administrator rights are required.' }

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $ScriptDir ('Phase1A2-Report-{0}.json' -f $env:COMPUTERNAME) }

$Tag = 'sqspike' + (Get-Date -Format 'HHmmss')
$HostName = "$Tag.test"
$HttpPort = 18081
$HttpsPort = 18443
$Root = Join-Path $env:SystemDrive "inetpub\$Tag"
$HostsFile = Join-Path $env:windir 'System32\drivers\etc\hosts'
$AppHostConfig = Join-Path $env:windir 'System32\inetsrv\config\applicationHost.config'
$AppCmd = Join-Path $env:windir 'System32\inetsrv\appcmd.exe'
$Steps = [System.Collections.Generic.List[object]]::new()
$script:S = @{}

# ---------------------------------------------------------------- helpers
function New-StrongPassword {
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#%+-='
    $bytes = [byte[]]::new(24)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($b in $bytes) { [void]$sb.Append($chars[$b % $chars.Length]) }
    return ('Aa1!' + $sb.ToString())
}

function New-Mgr { return [Microsoft.Web.Administration.ServerManager]::new() }

function Get-AppHostCounts {
    $x = [xml](Get-Content -LiteralPath $AppHostConfig -Raw)
    return [ordered]@{
        Sites     = $x.SelectNodes('/configuration/system.applicationHost/sites/site').Count
        Pools     = $x.SelectNodes('/configuration/system.applicationHost/applicationPools/add').Count
        Locations = $x.SelectNodes('/configuration/location').Count
    }
}

function Add-Step {
    param(
        [string]$Id,
        [string]$Description,
        [scriptblock]$Action,
        [switch]$Critical,
        [string]$Requires = ''
    )
    if ($Requires -and -not ($script:S.ContainsKey($Requires) -and $script:S[$Requires])) {
        $Steps.Add([ordered]@{ Id = $Id; Status = 'SKIP'; Critical = [bool]$Critical; Description = $Description; ElapsedMs = 0; Data = $null; Error = "prerequisite '$Requires' not satisfied" })
        Write-Host ('STEP SKIP  {0}' -f $Id)
        return
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $data = $null; $err = $null; $status = 'PASS'
    try { $data = & $Action }
    catch { $status = 'FAIL'; $err = $_.Exception.GetType().FullName + ': ' + $_.Exception.Message + ' | ' + (([string]$_.ScriptStackTrace) -replace '\s+', ' ') }
    $sw.Stop()
    if ($status -eq 'PASS' -and $data -is [System.Collections.IDictionary] -and $data.Contains('__Status')) { $status = [string]$data['__Status'] }
    $Steps.Add([ordered]@{ Id = $Id; Status = $status; Critical = [bool]$Critical; Description = $Description; ElapsedMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1); Data = $data; Error = $err })
    Write-Host ('STEP {0,-5} {1,-26} {2,9} ms{3}' -f $status, $Id, [math]::Round($sw.Elapsed.TotalMilliseconds), $(if ($err) { ' :: ' + $err } else { '' }))
}

function Wait-ObjectState {
    param([string]$Kind, [string]$Name, [string]$Desired, [int]$TimeoutSec = 40)
    $end = [DateTime]::UtcNow.AddSeconds($TimeoutSec)
    $state = ''
    while ([DateTime]::UtcNow -lt $end) {
        $m = New-Mgr
        try {
            if ($Kind -eq 'Pool') { $state = [string]$m.ApplicationPools[$Name].State } else { $state = [string]$m.Sites[$Name].State }
        } finally { $m.Dispose() }
        if ($state -eq $Desired) { return $state }
        Start-Sleep -Milliseconds 500
    }
    return $state
}

function Invoke-Http {
    param([string]$Url)
    $last = $null
    for ($i = 1; $i -le 4; $i++) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -TimeoutSec 60 -SkipHttpErrorCheck -SkipCertificateCheck -UseBasicParsing
            $body = [string]$resp.Content
            $last = [ordered]@{ Url = $Url; Status = [int]$resp.StatusCode; Body = $body.Substring(0, [math]::Min(40, $body.Length)); Attempts = $i }
            if ($last.Status -ne 503) { return $last }
        } catch { $last = [ordered]@{ Url = $Url; Status = -1; Body = $_.Exception.Message; Attempts = $i } }
        Start-Sleep -Seconds 2
    }
    return $last
}

function Get-ServedCertThumbprint {
    param([string]$Name, [int]$Port)
    $tcp = [System.Net.Sockets.TcpClient]::new()
    try {
        $tcp.Connect('127.0.0.1', $Port)
        $ssl = [System.Net.Security.SslStream]::new($tcp.GetStream(), $false, { param($s, $c, $ch, $e) $true })
        $ssl.AuthenticateAsClient($Name)
        return ([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ssl.RemoteCertificate)).Thumbprint
    } finally { $tcp.Dispose() }
}

function Run-WinPs51 {
    param([string]$ScriptText, [string]$Name, [string[]]$Arguments = @())
    $path = Join-Path $Root "$Name.ps1"
    $out = Join-Path $Root "$Name.json"
    Set-Content -LiteralPath $path -Value $ScriptText -Encoding UTF8
    $ps = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $path, '-OutputPath', $out) + $Arguments
    $p = Start-Process -FilePath $ps -ArgumentList $argList -PassThru -Wait -WindowStyle Hidden
    if (-not (Test-Path -LiteralPath $out)) { throw "Windows PowerShell child produced no output (exit $($p.ExitCode))." }
    return (Get-Content -LiteralPath $out -Raw | ConvertFrom-Json)
}

# ---------------------------------------------------------------- ensure functions (idempotent; return $true when something changed)
function Ensure-Pool {
    param($Mgr, [hashtable]$Spec)
    $changed = $false
    $p = $Mgr.ApplicationPools[$Spec.Name]
    if ($null -eq $p) { $p = $Mgr.ApplicationPools.Add($Spec.Name); $changed = $true }
    if ([string]$p.ManagedRuntimeVersion -ne $Spec.Runtime) { $p.ManagedRuntimeVersion = $Spec.Runtime; $changed = $true }
    if ([bool]$p.Enable32BitAppOnWin64 -ne [bool]$Spec.Enable32) { $p.Enable32BitAppOnWin64 = [bool]$Spec.Enable32; $changed = $true }
    if ([string]$p.StartMode -ne $Spec.StartMode) { $p.StartMode = $Spec.StartMode; $changed = $true }
    if ([string]$p.ProcessModel.IdentityType -ne $Spec.Identity) { $p.ProcessModel.IdentityType = $Spec.Identity; $changed = $true }
    if ($Spec.Identity -eq 'SpecificUser') {
        if ([string]$p.ProcessModel.UserName -ne $Spec.UserName) { $p.ProcessModel.UserName = $Spec.UserName; $p.ProcessModel.Password = $Spec.Password; $changed = $true }
    }
    if ($p.ProcessModel.IdleTimeout -ne $Spec.IdleTimeout) { $p.ProcessModel.IdleTimeout = $Spec.IdleTimeout; $changed = $true }
    if ([bool]$p.ProcessModel.LoadUserProfile -ne [bool]$Spec.LoadProfile) { $p.ProcessModel.LoadUserProfile = [bool]$Spec.LoadProfile; $changed = $true }
    if ($p.Recycling.PeriodicRestart.Time -ne $Spec.RecycleTime) { $p.Recycling.PeriodicRestart.Time = $Spec.RecycleTime; $changed = $true }
    return $changed
}

function Ensure-Site {
    param($Mgr, [hashtable]$Spec)
    $changed = $false
    $s = $Mgr.Sites[$Spec.Name]
    if ($null -eq $s) { $s = $Mgr.Sites.Add($Spec.Name, 'http', $Spec.HttpBinding, $Spec.Path); $changed = $true }
    if ([string]$s.ApplicationDefaults.ApplicationPoolName -ne $Spec.DefaultPool) { $s.ApplicationDefaults.ApplicationPoolName = $Spec.DefaultPool; $changed = $true }
    $rootApp = $s.Applications['/']
    if ([string]$rootApp.ApplicationPoolName -ne $Spec.RootPool) { $rootApp.ApplicationPoolName = $Spec.RootPool; $changed = $true }
    if ([string]$rootApp.VirtualDirectories['/'].PhysicalPath -ne $Spec.Path) { $rootApp.VirtualDirectories['/'].PhysicalPath = $Spec.Path; $changed = $true }
    return $changed
}

function Ensure-HttpsBinding {
    param($Mgr, [string]$SiteName, [string]$Info, [byte[]]$Hash, [string]$Store)
    $changed = $false
    $s = $Mgr.Sites[$SiteName]
    $b = $null
    foreach ($x in $s.Bindings) { if ($x.Protocol -ieq 'https' -and $x.BindingInformation -ieq $Info) { $b = $x; break } }
    if ($null -eq $b) { $b = $s.Bindings.Add($Info, $Hash, $Store); $changed = $true }
    if (([int]$b.SslFlags -band 1) -eq 0) { $b.SslFlags = [System.Enum]::ToObject($b.SslFlags.GetType(), 1); $changed = $true }
    return $changed
}

function Ensure-App {
    param($Mgr, [string]$SiteName, [hashtable]$Spec)
    $changed = $false
    $s = $Mgr.Sites[$SiteName]
    $a = $s.Applications[$Spec.Path]
    if ($null -eq $a) { $a = $s.Applications.Add($Spec.Path, $Spec.PhysicalPath); $changed = $true }
    if ([string]$a.ApplicationPoolName -ne $Spec.Pool) { $a.ApplicationPoolName = $Spec.Pool; $changed = $true }
    if ([string]$a.EnabledProtocols -ne $Spec.Protocols) { $a.EnabledProtocols = $Spec.Protocols; $changed = $true }
    $pre = $a.Attributes['preloadEnabled']
    if ([bool]$pre.Value -ne $true) { $pre.Value = $true; $changed = $true }
    foreach ($v in $Spec.VDirs) {
        if ($null -eq $a.VirtualDirectories[$v.Path]) { [void]$a.VirtualDirectories.Add($v.Path, $v.PhysicalPath); $changed = $true }
    }
    return $changed
}

function Ensure-AnonymousAuth {
    param($Mgr, [string]$LocationPath, [bool]$Enabled)
    $cfg = $Mgr.GetApplicationHostConfiguration()
    $sec = $cfg.GetSection('system.webServer/security/authentication/anonymousAuthentication', $LocationPath)
    if ([bool]$sec['enabled'] -ne $Enabled) { $sec['enabled'] = $Enabled; return $true }
    return $false
}

# ---------------------------------------------------------------- specs
$PoolA = @{ Name = "$Tag-poolA"; Runtime = 'v4.0'; Enable32 = $false; StartMode = 'AlwaysRunning'; Identity = 'ApplicationPoolIdentity'; IdleTimeout = [TimeSpan]::Zero; RecycleTime = [TimeSpan]::Zero; LoadProfile = $true }
$PoolB = @{ Name = "$Tag-poolB"; Runtime = ''; Enable32 = $true; StartMode = 'OnDemand'; Identity = 'ApplicationPoolIdentity'; IdleTimeout = [TimeSpan]::FromMinutes(45); RecycleTime = [TimeSpan]::FromHours(12); LoadProfile = $false }
$PoolC = @{ Name = "$Tag-poolC"; Runtime = 'v4.0'; Enable32 = $false; StartMode = 'OnDemand'; Identity = 'SpecificUser'; UserName = ''; Password = ''; IdleTimeout = [TimeSpan]::FromMinutes(20); RecycleTime = [TimeSpan]::Zero; LoadProfile = $true }
$SiteName = "$Tag-site"

try {

    Add-Step 'ENV' 'Environment inventory' {
        $os = Get-CimInstance Win32_OperatingSystem
        [ordered]@{
            PowerShell = $PSVersionTable.PSVersion.ToString()
            Edition    = $PSVersionTable.PSEdition
            Dotnet     = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
            OsCaption  = $os.Caption
            OsBuild    = $os.BuildNumber
            Machine    = $env:COMPUTERNAME
            Tag        = $Tag
        }
    }

    Add-Step 'MWA_LOAD' 'Load Microsoft.Web.Administration and take a baseline' -Critical {
        $dll = Join-Path $env:windir 'System32\inetsrv\Microsoft.Web.Administration.dll'
        $asm = [Reflection.Assembly]::LoadFrom($dll)
        $m = New-Mgr
        try { $script:S.BaseSites = @($m.Sites).Count; $script:S.BasePools = @($m.ApplicationPools).Count } finally { $m.Dispose() }
        $script:S.BaseCounts = Get-AppHostCounts
        $script:S.BaseHash = (Get-FileHash -LiteralPath $AppHostConfig -Algorithm SHA256).Hash
        $script:S.MwaOk = $true
        [ordered]@{ Assembly = $asm.FullName; Sites = $script:S.BaseSites; Pools = $script:S.BasePools; Counts = $script:S.BaseCounts }
    }

    Add-Step 'PS7_SERVICES' 'W3SVC and WAS running (Get-Service under PowerShell 7)' {
        $svc = @(Get-Service -Name W3SVC, WAS)
        $bad = @($svc | Where-Object { $_.Status -ne 'Running' })
        if ($bad.Count -gt 0) { throw ('Not running: ' + (($bad | ForEach-Object { $_.Name + '=' + $_.Status }) -join ', ')) }
        [ordered]@{ Services = @($svc | ForEach-Object { $_.Name + '=' + $_.Status }) }
    }

    Add-Step 'PS7_WINDOWSFEATURE' 'Get-WindowsFeature under PowerShell 7 (ServerManager module)' {
        $f = Get-WindowsFeature -Name Web-Server
        [ordered]@{ Name = $f.Name; Installed = [bool]$f.Installed; InstallState = [string]$f.InstallState }
    }

    Add-Step 'PS7_LOCALACCOUNTS' 'Create a local user in IIS_IUSRS (LocalAccounts cmdlets, ADSI fallback)' {
        $userName = ($Tag + 'u')
        $pw = New-StrongPassword
        $info = [ordered]@{ UserName = $userName; CmdletsOk = $false; CmdletsError = $null; AdsiOk = $false; AdsiError = $null; Method = $null }
        try {
            $sec = ConvertTo-SecureString $pw -AsPlainText -Force
            New-LocalUser -Name $userName -Password $sec -AccountNeverExpires -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
            Add-LocalGroupMember -Group 'IIS_IUSRS' -Member $userName
            $info.CmdletsOk = $true; $info.Method = 'LocalAccounts cmdlets'
        } catch {
            $info.CmdletsError = $_.Exception.GetType().FullName + ': ' + $_.Exception.Message
            try {
                $comp = [ADSI]"WinNT://$env:COMPUTERNAME,computer"
                $u = $comp.Create('user', $userName); $u.SetPassword($pw); $u.SetInfo()
                $u.UserFlags = 65536; $u.SetInfo()
                $g = [ADSI]"WinNT://$env:COMPUTERNAME/IIS_IUSRS,group"
                $g.Add("WinNT://$env:COMPUTERNAME/$userName,user")
                $info.AdsiOk = $true; $info.Method = 'ADSI fallback'
            } catch { $info.AdsiError = $_.Exception.GetType().FullName + ': ' + $_.Exception.Message }
        }
        if (-not ($info.CmdletsOk -or $info.AdsiOk)) { throw 'Could not create the local user by any method.' }
        $script:S.UserName = $userName; $script:S.Pw = $pw; $script:S.UserOk = $true
        if (-not $info.CmdletsOk) { $info['__Status'] = 'WARN' }
        $info
    }

    Add-Step 'PS7_ACL_FILES' 'Create content folders and grant IIS_IUSRS (Get-Acl / Set-Acl under PowerShell 7)' {
        foreach ($d in @('site', 'app1', 'appc')) {
            $dir = Join-Path $Root $d
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $dir 'index.html') -Value "ok-$d" -Encoding ASCII
        }
        $acl = Get-Acl -LiteralPath $Root
        $rule = [System.Security.AccessControl.FileSystemAccessRule]::new('IIS_IUSRS', 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $Root -AclObject $acl
        $found = @((Get-Acl -LiteralPath (Join-Path $Root 'site')).Access | Where-Object { $_.IdentityReference.Value -like '*IIS_IUSRS' })
        if ($found.Count -eq 0) { throw 'IIS_IUSRS rule not present after Set-Acl.' }
        $script:S.FilesOk = $true
        [ordered]@{ Root = $Root; IisIusrsRules = $found.Count }
    } -Critical

    Add-Step 'PS7_CERTIFICATE' 'Create a self-signed certificate in LocalMachine\My (PKI cmdlet, .NET fallback)' {
        $info = [ordered]@{ Method = $null; CmdletError = $null; Thumbprint = $null }
        $thumb = $null
        try {
            $c = New-SelfSignedCertificate -DnsName $HostName -CertStoreLocation 'Cert:\LocalMachine\My'
            $thumb = $c.Thumbprint; $info.Method = 'New-SelfSignedCertificate'
        } catch {
            $info.CmdletError = $_.Exception.GetType().FullName + ': ' + $_.Exception.Message
            $rsa = [System.Security.Cryptography.RSA]::Create(2048)
            $req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new("CN=$HostName", $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $san = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
            $san.AddDnsName($HostName)
            $req.CertificateExtensions.Add($san.Build())
            $self = $req.CreateSelfSigned([DateTimeOffset]::UtcNow.AddDays(-1), [DateTimeOffset]::UtcNow.AddDays(30))
            $pfx = $self.Export('Pfx', 'spike')
            $c2 = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($pfx, 'spike', 'MachineKeySet,PersistKeySet,Exportable')
            $store = [System.Security.Cryptography.X509Certificates.X509Store]::new('My', 'LocalMachine')
            $store.Open('ReadWrite'); $store.Add($c2); $store.Close()
            $thumb = $c2.Thumbprint; $info.Method = '.NET CertificateRequest'
        }
        $script:S.Thumb = $thumb; $script:S.CertOk = $true
        $info.Thumbprint = $thumb
        if ($info.CmdletError) { $info['__Status'] = 'WARN' }
        $info
    }

    Add-Step 'POOLS_WRITE' 'Create three application pools through MWA and verify the round trip' -Critical -Requires 'MwaOk' {
        $specs = @($PoolA, $PoolB)
        if ($script:S.ContainsKey('UserOk') -and $script:S.UserOk) {
            $PoolC.UserName = "$env:COMPUTERNAME\$($script:S.UserName)"; $PoolC.Password = $script:S.Pw
            $specs += $PoolC
        }
        $m = New-Mgr
        try { foreach ($sp in $specs) { [void](Ensure-Pool $m $sp) }; $m.CommitChanges() } finally { $m.Dispose() }
        $m2 = New-Mgr
        try {
            $out = @()
            foreach ($sp in $specs) {
                $p = $m2.ApplicationPools[$sp.Name]
                if ($null -eq $p) { throw "Pool missing after commit: $($sp.Name)" }
                $ok = ([string]$p.ManagedRuntimeVersion -eq $sp.Runtime) -and ([bool]$p.Enable32BitAppOnWin64 -eq [bool]$sp.Enable32) -and ([string]$p.StartMode -eq $sp.StartMode) -and ([string]$p.ProcessModel.IdentityType -eq $sp.Identity) -and ($p.ProcessModel.IdleTimeout -eq $sp.IdleTimeout) -and ([bool]$p.ProcessModel.LoadUserProfile -eq [bool]$sp.LoadProfile) -and ($p.Recycling.PeriodicRestart.Time -eq $sp.RecycleTime)
                if ($sp.Identity -eq 'SpecificUser') { $ok = $ok -and ([string]$p.ProcessModel.UserName -eq $sp.UserName) }
                $out += [ordered]@{ Pool = $sp.Name; Identity = [string]$p.ProcessModel.IdentityType; RoundTripOk = $ok }
                if (-not $ok) { throw "Round trip mismatch for $($sp.Name)" }
            }
        } finally { $m2.Dispose() }
        $script:S.PoolsOk = $true
        $script:S.PoolCOk = ($specs.Count -eq 3)
        [ordered]@{ Pools = $out }
    }

    Add-Step 'SITE_WRITE' 'Create a site with two http bindings and root application' -Critical -Requires 'PoolsOk' {
        $spec = @{ Name = $SiteName; HttpBinding = "*:${HttpPort}:$HostName"; Path = (Join-Path $Root 'site'); DefaultPool = $PoolA.Name; RootPool = $PoolA.Name }
        $m = New-Mgr
        try {
            [void](Ensure-Site $m $spec)
            $s = $m.Sites[$SiteName]
            $second = "*:$($HttpPort + 1):$HostName"
            $has = $false; foreach ($b in $s.Bindings) { if ($b.BindingInformation -ieq $second) { $has = $true } }
            if (-not $has) { [void]$s.Bindings.Add($second, 'http') }
            $m.CommitChanges()
        } finally { $m.Dispose() }
        $m2 = New-Mgr
        try {
            $s2 = $m2.Sites[$SiteName]
            if ($null -eq $s2) { throw 'Site missing after commit.' }
            $binds = @($s2.Bindings | ForEach-Object { $_.Protocol + ' ' + $_.BindingInformation })
            if ($binds.Count -lt 2) { throw 'Expected two bindings.' }
        } finally { $m2.Dispose() }
        $script:S.SiteOk = $true
        [ordered]@{ Site = $SiteName; Bindings = $binds }
    }

    Add-Step 'BINDING_HTTPS_SNI' 'Add an https binding with certificate and SNI, verify http.sys registration' -Critical -Requires 'SiteOk' {
        if (-not ($script:S.ContainsKey('CertOk') -and $script:S.CertOk)) { throw 'No certificate available.' }
        $hash = [byte[]]::new($script:S.Thumb.Length / 2)
        for ($i = 0; $i -lt $hash.Length; $i++) { $hash[$i] = [Convert]::ToByte($script:S.Thumb.Substring($i * 2, 2), 16) }
        $info = "*:${HttpsPort}:$HostName"
        $m = New-Mgr
        try { [void](Ensure-HttpsBinding $m $SiteName $info $hash 'My'); $m.CommitChanges() } finally { $m.Dispose() }
        $m2 = New-Mgr
        try {
            $b = $null
            foreach ($x in $m2.Sites[$SiteName].Bindings) { if ($x.Protocol -ieq 'https') { $b = $x } }
            if ($null -eq $b) { throw 'https binding missing after commit.' }
            $hex = ($b.CertificateHash | ForEach-Object { $_.ToString('X2') }) -join ''
            if ($hex -ne $script:S.Thumb.ToUpperInvariant()) { throw "Certificate hash mismatch: $hex" }
            $flags = [int]$b.SslFlags
        } finally { $m2.Dispose() }
        $netsh = (& netsh http show sslcert "hostnameport=${HostName}:$HttpsPort") -join ' '
        $httpSys = ($netsh -match [regex]::Escape($script:S.Thumb))
        $script:S.HttpsOk = $true
        [ordered]@{ SslFlags = $flags; CertificateHash = $hex; HttpSysHasCertificate = $httpSys }
    }

    Add-Step 'APPS_WRITE' 'Create applications, enabledProtocols, preloadEnabled and a virtual directory' -Critical -Requires 'SiteOk' {
        $apps = @(
            @{ Path = '/app1'; PhysicalPath = (Join-Path $Root 'app1'); Pool = $PoolB.Name; Protocols = 'http'; VDirs = @(@{ Path = '/files'; PhysicalPath = (Join-Path $Root 'app1') }) }
        )
        if ($script:S.ContainsKey('PoolCOk') -and $script:S.PoolCOk) {
            $apps += @{ Path = '/appc'; PhysicalPath = (Join-Path $Root 'appc'); Pool = $PoolC.Name; Protocols = 'http'; VDirs = @() }
        }
        $m = New-Mgr
        try { foreach ($a in $apps) { [void](Ensure-App $m $SiteName $a) }; $m.CommitChanges() } finally { $m.Dispose() }
        $m2 = New-Mgr
        try {
            $out = @()
            foreach ($a in $apps) {
                $x = $m2.Sites[$SiteName].Applications[$a.Path]
                if ($null -eq $x) { throw "Application missing: $($a.Path)" }
                if ([string]$x.ApplicationPoolName -ne $a.Pool) { throw "Pool mismatch on $($a.Path)" }
                $vd = @($x.VirtualDirectories | ForEach-Object { $_.Path })
                $out += [ordered]@{ Path = $a.Path; Pool = [string]$x.ApplicationPoolName; Protocols = [string]$x.EnabledProtocols; Preload = [bool]$x.Attributes['preloadEnabled'].Value; VirtualDirectories = $vd }
            }
        } finally { $m2.Dispose() }
        $script:S.AppsOk = $true
        [ordered]@{ Applications = $out }
    }

    Add-Step 'LOCATION_AUTH' 'Disable anonymous authentication for /app1 through a location-scoped section' -Critical -Requires 'AppsOk' {
        $loc = "$SiteName/app1"
        $m = New-Mgr
        try { [void](Ensure-AnonymousAuth $m $loc $false); $m.CommitChanges() } finally { $m.Dispose() }
        $m2 = New-Mgr
        try {
            $sec = $m2.GetApplicationHostConfiguration().GetSection('system.webServer/security/authentication/anonymousAuthentication', $loc)
            $val = [bool]$sec['enabled']
        } finally { $m2.Dispose() }
        if ($val) { throw 'anonymousAuthentication is still enabled after commit.' }
        $script:S.AuthOk = $true
        [ordered]@{ Location = $loc; AnonymousEnabled = $val }
    }

    Add-Step 'LIFECYCLE_HTTP' 'Start pools and site, then prove behaviour with real HTTP and TLS requests; recycle' -Critical -Requires 'AppsOk' {
        Add-Content -LiteralPath $HostsFile -Value "127.0.0.1 $HostName"
        $script:S.HostsAdded = $true
        $m = New-Mgr
        try {
            foreach ($p in @($m.ApplicationPools | Where-Object { $_.Name -like "$Tag-pool*" })) { try { [void]$p.Start() } catch { } }
            try { [void]$m.Sites[$SiteName].Start() } catch { }
        } finally { $m.Dispose() }
        $siteState = Wait-ObjectState -Kind Site -Name $SiteName -Desired 'Started'
        $root = Invoke-Http "http://${HostName}:$HttpPort/"
        $app1 = Invoke-Http "http://${HostName}:$HttpPort/app1/"
        $appc = $null
        if ($script:S.ContainsKey('PoolCOk') -and $script:S.PoolCOk) { $appc = Invoke-Http "http://${HostName}:$HttpPort/appc/" }
        $served = $null; $servedError = $null
        try { $served = Get-ServedCertThumbprint -Name $HostName -Port $HttpsPort } catch { $servedError = $_.Exception.Message }
        $m = New-Mgr
        try { [void]$m.ApplicationPools[$PoolA.Name].Recycle() } finally { $m.Dispose() }
        Start-Sleep -Seconds 2
        $after = Invoke-Http "http://${HostName}:$HttpPort/"
        $poolState = Wait-ObjectState -Kind Pool -Name $PoolA.Name -Desired 'Started'
        $problems = @()
        if ($siteState -ne 'Started') { $problems += "site state=$siteState" }
        if ($root.Status -ne 200) { $problems += "root status=$($root.Status)" }
        if ($app1.Status -ne 401) { $problems += "app1 status=$($app1.Status) (expected 401 with anonymous disabled)" }
        if ($null -ne $appc -and $appc.Status -ne 200) { $problems += "appc (SpecificUser pool) status=$($appc.Status)" }
        if ($served -ne $script:S.Thumb) { $problems += "served certificate=$served $servedError" }
        if ($after.Status -ne 200) { $problems += "after recycle status=$($after.Status)" }
        $result = [ordered]@{ SiteState = $siteState; Root = $root; App1 = $app1; AppcSpecificUser = $appc; ServedThumbprint = $served; AfterRecycle = $after; PoolAStateAfterRecycle = $poolState; Problems = $problems }
        if ($problems.Count -gt 0) { throw ('Runtime verification failed: ' + ($problems -join '; ')) }
        $result
    }

    Add-Step 'INTEROP_WINPS51' 'Windows PowerShell 5.1 cmdlets see the state written through MWA' -Requires 'AppsOk' {
        $child = @'
param([string]$OutputPath,[string]$Site,[string]$Pool,[string]$PoolC)
$ErrorActionPreference='Stop'
function V($x){ if($null -eq $x){return $null}; if($x -is [string] -or $x -is [ValueType]){return [string]$x}; if($x.PSObject.Properties.Name -contains 'Value'){return [string]$x.Value}; return [string]$x }
$r=[ordered]@{Success=$false;SiteFound=$false;SiteState=$null;Bindings=@();Applications=@();PoolIdentity=$null;PoolCIdentity=$null;AppcmdSiteState=$null;Error=$null}
try{
    Import-Module WebAdministration
    $s=Get-Website -Name $Site
    $r.SiteFound=($null -ne $s)
    $r.SiteState=V((Get-WebsiteState -Name $Site).Value)
    $r.Bindings=@(Get-WebBinding -Name $Site | ForEach-Object { '{0} {1} ssl={2}' -f $_.protocol,$_.bindingInformation,$_.sslFlags })
    $r.Applications=@(Get-WebApplication -Site $Site | ForEach-Object { '{0} pool={1} protocols={2}' -f $_.path,$_.applicationPool,$_.enabledProtocols })
    $r.PoolIdentity=V(Get-ItemProperty ('IIS:\AppPools\'+$Pool) -Name processModel.identityType)
    if($PoolC){$r.PoolCIdentity=V(Get-ItemProperty ('IIS:\AppPools\'+$PoolC) -Name processModel.identityType)}
    $appcmd=Join-Path $env:windir 'System32\inetsrv\appcmd.exe'
    $r.AppcmdSiteState=[string](& $appcmd list site $Site /text:state)
    $r.Success=$true
}catch{$r.Error=$_.Exception.GetType().FullName+': '+$_.Exception.Message}
$r|ConvertTo-Json -Depth 6|Set-Content $OutputPath -Encoding utf8
'@
        $poolCArg = if ($script:S.ContainsKey('PoolCOk') -and $script:S.PoolCOk) { $PoolC.Name } else { '' }
        $r = Run-WinPs51 -ScriptText $child -Name 'interop' -Arguments @('-Site', $SiteName, '-Pool', $PoolA.Name, '-PoolC', $poolCArg)
        if (-not $r.Success) { throw ('Windows PowerShell read failed: ' + $r.Error) }
        $problems = @()
        if (-not $r.SiteFound) { $problems += 'site not found' }
        if (@($r.Bindings | Where-Object { $_ -like 'https*' }).Count -lt 1) { $problems += 'https binding not visible' }
        if (@($r.Applications | Where-Object { $_ -like '/app1*' }).Count -lt 1) { $problems += '/app1 not visible' }
        if (@('ApplicationPoolIdentity', '4') -notcontains [string]$r.PoolIdentity) { $problems += "pool A identity=$($r.PoolIdentity)" }
        if ($poolCArg -and @('SpecificUser', '3') -notcontains [string]$r.PoolCIdentity) { $problems += "pool C identity=$($r.PoolCIdentity)" }
        if ($problems.Count -gt 0) { throw ('Interop mismatch: ' + ($problems -join '; ')) }
        $r
    }

    Add-Step 'IDEMPOTENCY' 'Repeat every ensure operation: nothing may change in applicationHost.config' -Critical -Requires 'AuthOk' {
        $before = (Get-FileHash -LiteralPath $AppHostConfig -Algorithm SHA256).Hash
        $changes = [ordered]@{}
        $m = New-Mgr
        try {
            $specs = @($PoolA, $PoolB); if ($script:S.PoolCOk) { $specs += $PoolC }
            $c = $false; foreach ($sp in $specs) { if (Ensure-Pool $m $sp) { $c = $true } }; $changes.Pools = $c
            $changes.Site = [bool](Ensure-Site $m @{ Name = $SiteName; HttpBinding = "*:${HttpPort}:$HostName"; Path = (Join-Path $Root 'site'); DefaultPool = $PoolA.Name; RootPool = $PoolA.Name })
            $hash = [byte[]]::new($script:S.Thumb.Length / 2)
            for ($i = 0; $i -lt $hash.Length; $i++) { $hash[$i] = [Convert]::ToByte($script:S.Thumb.Substring($i * 2, 2), 16) }
            $changes.Https = [bool](Ensure-HttpsBinding $m $SiteName "*:${HttpsPort}:$HostName" $hash 'My')
            $changes.App1 = [bool](Ensure-App $m $SiteName @{ Path = '/app1'; PhysicalPath = (Join-Path $Root 'app1'); Pool = $PoolB.Name; Protocols = 'http'; VDirs = @(@{ Path = '/files'; PhysicalPath = (Join-Path $Root 'app1') }) })
            $changes.Auth = [bool](Ensure-AnonymousAuth $m "$SiteName/app1" $false)
            if ($changes.Values -contains $true) { $m.CommitChanges() }
        } finally { $m.Dispose() }
        $after = (Get-FileHash -LiteralPath $AppHostConfig -Algorithm SHA256).Hash
        $result = [ordered]@{ ReportedChanges = $changes; HashUnchanged = ($before -eq $after) }
        if ($changes.Values -contains $true) { throw ('A second run reported changes: ' + (($changes.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object { $_.Key }) -join ', ')) }
        if ($before -ne $after) { throw 'applicationHost.config changed although no change was reported.' }
        $result
    }

    Add-Step 'SCALE' "Create $ScaleSites sites x $ScaleAppsPerSite applications (own pool each) in one commit, enumerate three ways, delete" -Requires 'MwaOk' {
        $t = [ordered]@{ Sites = $ScaleSites; ApplicationsPerSite = $ScaleAppsPerSite }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $m = New-Mgr
        try {
            for ($s = 1; $s -le $ScaleSites; $s++) {
                $sn = 'SQSCALE{0:D2}' -f $s
                $rp = $m.ApplicationPools.Add("$sn-root"); $rp.ManagedRuntimeVersion = ''
                $site = $m.Sites.Add($sn, 'http', ('*:{0}:{1}.scale.test' -f (19000 + $s), $sn.ToLowerInvariant()), $Root)
                $site.ServerAutoStart = $false
                $site.Applications['/'].ApplicationPoolName = "$sn-root"
                for ($a = 1; $a -le $ScaleAppsPerSite; $a++) {
                    $pn = '{0}-p{1:D2}' -f $sn, $a
                    $pool = $m.ApplicationPools.Add($pn); $pool.ManagedRuntimeVersion = ''
                    $app = $site.Applications.Add(('/a{0:D2}' -f $a), $Root)
                    $app.ApplicationPoolName = $pn
                }
            }
            $t.BuildInMemoryMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
            $sw.Restart(); $m.CommitChanges(); $t.CommitMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        } finally { $m.Dispose() }

        $sw.Restart()
        $m2 = New-Mgr
        try {
            $siteCount = @($m2.Sites | Where-Object { $_.Name -like 'SQSCALE*' }).Count
            $appCount = 0; foreach ($s in @($m2.Sites | Where-Object { $_.Name -like 'SQSCALE*' })) { $appCount += @($s.Applications).Count }
            $poolCount = @($m2.ApplicationPools | Where-Object { $_.Name -like 'SQSCALE*' }).Count
        } finally { $m2.Dispose() }
        $t.EnumerateMwaMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        $t.Created = [ordered]@{ Sites = $siteCount; Applications = $appCount; Pools = $poolCount }
        if ($siteCount -ne $ScaleSites -or $poolCount -ne ($ScaleSites * ($ScaleAppsPerSite + 1))) { throw "Unexpected object counts after commit: $($t.Created | ConvertTo-Json -Compress)" }

        try {
            Import-Module IISAdministration -ErrorAction Stop
            $sw.Restart(); $null = @(Get-IISSite); $t.EnumerateIisAdministrationSitesMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
            $sw.Restart(); $null = @(Get-IISAppPool); $t.EnumerateIisAdministrationPoolsMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        } catch { $t.IisAdministrationError = $_.Exception.Message }

        $child = @'
param([string]$OutputPath)
$ErrorActionPreference='Stop'
$r=[ordered]@{Success=$false;GetWebsiteMs=$null;Sites=$null;GetWebApplicationMs=$null;Applications=$null;ProviderPoolsMs=$null;Pools=$null;Error=$null}
try{
    Import-Module WebAdministration
    $sw=[Diagnostics.Stopwatch]::StartNew();$s=@(Get-Website);$sw.Stop();$r.GetWebsiteMs=[math]::Round($sw.Elapsed.TotalMilliseconds,1);$r.Sites=$s.Count
    $sw=[Diagnostics.Stopwatch]::StartNew();$a=@(Get-WebApplication);$sw.Stop();$r.GetWebApplicationMs=[math]::Round($sw.Elapsed.TotalMilliseconds,1);$r.Applications=$a.Count
    $sw=[Diagnostics.Stopwatch]::StartNew();$p=@(Get-ChildItem 'IIS:\AppPools');$sw.Stop();$r.ProviderPoolsMs=[math]::Round($sw.Elapsed.TotalMilliseconds,1);$r.Pools=$p.Count
    $r.Success=$true
}catch{$r.Error=$_.Exception.GetType().FullName+': '+$_.Exception.Message}
$r|ConvertTo-Json -Depth 4|Set-Content $OutputPath -Encoding utf8
'@
        $t.WindowsPowerShell51 = Run-WinPs51 -ScriptText $child -Name 'scale51'

        $sw.Restart()
        $m3 = New-Mgr
        try {
            foreach ($s in @($m3.Sites | Where-Object { $_.Name -like 'SQSCALE*' })) { $m3.Sites.Remove($s) }
            foreach ($p in @($m3.ApplicationPools | Where-Object { $_.Name -like 'SQSCALE*' })) { $m3.ApplicationPools.Remove($p) }
            $m3.CommitChanges()
        } finally { $m3.Dispose() }
        $t.DeleteCommitMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        $t
    }

} finally {

    Add-Step 'CLEANUP_VERIFY' 'Remove everything this spike created and verify the machine returned to baseline' -Critical {
        $log = [System.Collections.Generic.List[string]]::new()
        if ([System.AppDomain]::CurrentDomain.GetAssemblies().Where({ $_.GetName().Name -eq 'Microsoft.Web.Administration' }).Count -gt 0) {
            $m = New-Mgr
            try {
                $cfg = $m.GetApplicationHostConfiguration()
                foreach ($s in @($m.Sites | Where-Object { $_.Name -like "$Tag*" -or $_.Name -like 'SQSCALE*' })) {
                    foreach ($a in @($s.Applications | Where-Object { $_.Path -ne '/' })) {
                        try { $sec = $cfg.GetSection('system.webServer/security/authentication/anonymousAuthentication', ($s.Name + $a.Path)); $sec.RevertToParent() } catch { }
                    }
                    try { [void]$s.Stop() } catch { }
                    $m.Sites.Remove($s); $log.Add("site removed: $($s.Name)")
                }
                foreach ($p in @($m.ApplicationPools | Where-Object { $_.Name -like "$Tag*" -or $_.Name -like 'SQSCALE*' })) {
                    try { [void]$p.Stop() } catch { }
                    $m.ApplicationPools.Remove($p); $log.Add("pool removed: $($p.Name)")
                }
                $m.CommitChanges()
            } finally { $m.Dispose() }
        }
        if (Test-Path -LiteralPath $HostsFile) {
            $lines = @(Get-Content -LiteralPath $HostsFile)
            $kept = @($lines | Where-Object { $_ -notmatch [regex]::Escape($Tag) })
            if ($kept.Count -ne $lines.Count) { Set-Content -LiteralPath $HostsFile -Value $kept; $log.Add('hosts entry removed') }
        }
        $ssl = (& netsh http show sslcert "hostnameport=${HostName}:$HttpsPort") -join ' '
        if ($ssl -match 'Certificate Hash') { & netsh http delete sslcert "hostnameport=${HostName}:$HttpsPort" | Out-Null; $log.Add('http.sys sslcert removed') }
        foreach ($c in @(Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq "CN=$HostName" })) { Remove-Item -LiteralPath $c.PSPath -Force; $log.Add("certificate removed: $($c.Thumbprint)") }
        $uname = ($Tag + 'u')
        try { Remove-LocalUser -Name $uname -ErrorAction Stop; $log.Add('local user removed (cmdlet)') } catch {
            try { ([ADSI]"WinNT://$env:COMPUTERNAME,computer").Delete('user', $uname); $log.Add('local user removed (ADSI)') } catch { }
        }
        if (Test-Path -LiteralPath $Root) { Remove-Item -LiteralPath $Root -Recurse -Force; $log.Add('content folder removed') }

        $problems = @()
        if ($script:S.ContainsKey('BaseCounts')) {
            $now = Get-AppHostCounts
            foreach ($k in @('Sites', 'Pools', 'Locations')) { if ($now[$k] -ne $script:S.BaseCounts[$k]) { $problems += "$k now=$($now[$k]) baseline=$($script:S.BaseCounts[$k])" } }
        }
        if (Test-Path -LiteralPath $Root) { $problems += 'content folder still exists' }
        if (@(Get-Content -LiteralPath $HostsFile | Where-Object { $_ -match [regex]::Escape($Tag) }).Count -gt 0) { $problems += 'hosts entry still present' }
        $hashNow = (Get-FileHash -LiteralPath $AppHostConfig -Algorithm SHA256).Hash
        $result = [ordered]@{ Log = @($log); BaselineCounts = $script:S.BaseCounts; ConfigHashIdenticalToBaseline = ($script:S.ContainsKey('BaseHash') -and $hashNow -eq $script:S.BaseHash); Problems = $problems }
        if ($problems.Count -gt 0) { throw ('Cleanup verification failed: ' + ($problems -join '; ')) }
        $result
    }

    $critical = @($Steps | Where-Object { $_.Critical })
    $failed = @($critical | Where-Object { $_.Status -eq 'FAIL' })
    $skipped = @($critical | Where-Object { $_.Status -eq 'SKIP' })
    $overall = if ($failed.Count -gt 0) { 'FAIL' } elseif ($skipped.Count -gt 0) { 'INCOMPLETE' } else { 'PASS' }
    $report = [ordered]@{
        Phase      = '1A-2'
        Name       = 'IIS write path under PowerShell 7 (Microsoft.Web.Administration)'
        Machine    = $env:COMPUTERNAME
        PowerShell = $PSVersionTable.PSVersion.ToString()
        Overall    = $overall
        Steps      = @($Steps)
    }
    try {
        $json = $report | ConvertTo-Json -Depth 12
    } catch {
        $json = ([ordered]@{ Phase = '1A-2'; Overall = $overall; SerializationError = $_.Exception.Message; Steps = @($Steps | ForEach-Object { [ordered]@{ Id = $_.Id; Status = $_.Status; Critical = $_.Critical; ElapsedMs = $_.ElapsedMs; Error = $_.Error } }) } | ConvertTo-Json -Depth 6)
    }
    $dir = Split-Path -Parent $ReportPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $ReportPath -Value $json -Encoding UTF8
    Write-Host ''
    Write-Host '========== PHASE 1A-2 SUMMARY =========='
    foreach ($s in $Steps) { Write-Host ('{0,-5} {1,-26} {2}' -f $s.Status, $s.Id, $(if ($s.Error) { $s.Error } else { '' })) }
    Write-Host ('OVERALL: ' + $overall)
    Write-Host ('Report saved to: ' + $ReportPath)
}
