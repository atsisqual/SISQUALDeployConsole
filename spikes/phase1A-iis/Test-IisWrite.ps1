#requires -Version 5.1
<#
Phase 1A-2 spike for SISQUALDeployConsole: IIS WRITE path.

Question answered: can PowerShell 7 + Microsoft.Web.Administration (MWA) replace the current IIS write approach
(Windows PowerShell 5.1 + WebAdministration cmdlets, plus MWA for pools/bindings like the real IIS_RECONCILE engine)
and produce the same IIS configuration?

WARNING: this script CREATES and DELETES IIS sites and application pools, a local user, a self-signed certificate,
an http.sys certificate binding and C:\spike-iis. Run it ONLY on a disposable machine (GitHub-hosted runner / VM).
It refuses to run elsewhere unless SPIKE_ALLOW_IIS_WRITE=1 is set.
#>

[CmdletBinding()]
param(
    [string]$ArtifactRoot = '',
    [string]$ReportPath = '',
    [int]$ScaleSites = 8,
    [int]$ScaleAppsPerSite = 25,
    [switch]$SkipScale,
    [switch]$KeepArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:GITHUB_ACTIONS -ne 'true' -and $env:SPIKE_ALLOW_IIS_WRITE -ne '1') {
    throw 'Refusing to run: this spike creates and deletes IIS sites, app pools, a local user and a certificate. Run it only on a disposable machine (set SPIKE_ALLOW_IIS_WRITE=1 to override).'
}

# Last-resort diagnostics for terminating errors raised outside the try/catch below (for example in finally).
trap {
    Write-Host ('UNHANDLED_ERROR: ' + $_.Exception.GetType().FullName + ': ' + $_.Exception.Message)
    if ($null -ne $_.InvocationInfo) { Write-Host ([string]$_.InvocationInfo.PositionMessage) }
    Write-Host ([string]$_.ScriptStackTrace)
    break
}

$ScriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ScriptDir) -and $null -ne $MyInvocation.MyCommand -and -not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ([string]::IsNullOrWhiteSpace($ScriptDir)) { $ScriptDir = (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) { $ArtifactRoot = Join-Path $ScriptDir 'artifacts' }

$Pinned = [ordered]@{
    PowerShell = [ordered]@{
        Version     = '7.6.6'
        FileName    = 'PowerShell-7.6.6-win-x64.zip'
        Sha256      = '02FE458BE20493FBDF43F61EA20610B811EE6C738AB1676C61B9CFCD1A33C860'
        PublishedBy = 'official hashes.sha256 of the PowerShell v7.6.6 release'
    }
}

$RunId = [guid]::NewGuid().ToString('N')
$StartedUtc = [DateTime]::UtcNow
$TempRoot = Join-Path $env:TEMP ('SISQUALDeployConsole-IisWrite-' + $RunId)
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $ScriptDir ('IisWrite-Report-{0}-{1}.json' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$Results = New-Object 'System.Collections.Generic.List[object]'
$Fatal = $null
$SpikeRoot = 'C:\spike-iis'
$ps51 = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
$appcmd = Join-Path $env:windir 'System32\inetsrv\appcmd.exe'
$IdentityUser = 'spikeiis'
$CertThumbprint = ''
$UserCreated = $false
$pwsh = $null

function Add-Result {
    param(
        [string]$Id,
        [ValidateSet('PASS','FAIL','WARN','SKIP')][string]$Status,
        [string]$Message,
        $Data = $null,
        [string]$ErrorText = $null
    )
    $Results.Add([pscustomobject][ordered]@{
        Id=$Id
        Status=$Status
        Message=$Message
        Data=$Data
        Error=$ErrorText
        TimestampUtc=[DateTime]::UtcNow.ToString('o')
    })
}

function Err([System.Management.Automation.ErrorRecord]$E) {
    if ($null -eq $E) { return $null }
    $s = [string]$E
    if ($null -ne $E.Exception) {
        $s = ($E.Exception.GetType().FullName + ': ' + $E.Exception.Message)
    }
    if ($null -ne $E.InvocationInfo -and $E.InvocationInfo.PositionMessage) {
        $s += ' | AT ' + ($E.InvocationInfo.PositionMessage -replace '\s+',' ')
    }
    if ($E.ScriptStackTrace) {
        $s += ' | STACK ' + ($E.ScriptStackTrace -replace '\s+',' ')
    }
    return $s
}

function Is-Admin {
    try {
        $id=[Security.Principal.WindowsIdentity]::GetCurrent()
        $p=New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch { return $false }
}

function Assert-Sha256 {
    param([string]$Id,[string]$Path,[string]$Expected,[string]$Version,[string]$PublishedBy)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-Result ($Id+'_ARTIFACT') 'FAIL' 'Required offline artifact is missing.' ([ordered]@{Path=$Path;Version=$Version;ExpectedSha256=$Expected;PublishedBy=$PublishedBy})
        throw "Missing artifact: $Path"
    }
    $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $Expected.ToUpperInvariant()) {
        Add-Result ($Id+'_ARTIFACT') 'FAIL' 'SHA-256 mismatch. Aborting before artifact use.' ([ordered]@{Path=$Path;Version=$Version;ExpectedSha256=$Expected;ActualSha256=$actual;PublishedBy=$PublishedBy})
        throw "SHA-256 mismatch: $Path"
    }
    Add-Result ($Id+'_ARTIFACT') 'PASS' 'SHA-256 matches pinned published value.' ([ordered]@{Path=$Path;Version=$Version;Sha256=$actual;PublishedBy=$PublishedBy})
}

function Run-ChildJson {
    param([string]$Exe,[string]$Script,[string]$Out,[string[]]$Extra=@())
    $stdout=$Out+'.stdout.txt'
    $stderr=$Out+'.stderr.txt'
    $childArgs=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $Script),'-OutputPath',('"{0}"' -f $Out))
    $childArgs += $Extra
    $p=Start-Process -FilePath $Exe -ArgumentList $childArgs -PassThru -Wait -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $payload=$null
    if (Test-Path -LiteralPath $Out) {
        try { $payload=Get-Content -LiteralPath $Out -Raw -Encoding UTF8 | ConvertFrom-Json } catch {}
    }
    [pscustomobject]@{
        ExitCode=$p.ExitCode
        Payload=$payload
        StdOut=$(if(Test-Path $stdout){Get-Content $stdout -Raw}else{''})
        StdErr=$(if(Test-Path $stderr){Get-Content $stderr -Raw}else{''})
    }
}

function Child-Ok($Run) {
    return ($null -ne $Run.Payload -and [bool]$Run.Payload.Success -and $null -eq $Run.Payload.Error)
}

function Child-Error($Run) {
    if ($null -ne $Run.Payload -and $null -ne $Run.Payload.Error) { return [string]$Run.Payload.Error }
    if (-not [string]::IsNullOrWhiteSpace([string]$Run.StdErr)) { return [string]$Run.StdErr }
    return ('exit code ' + $Run.ExitCode + ', no payload')
}

function New-Scenario {
    param([int]$Version,[string]$Thumbprint,[string]$User,[string]$Password)
    $v2 = ($Version -eq 2)
    $poolWfm = [ordered]@{Name='sp_wfm';ManagedRuntimeVersion=$(if($v2){''}else{'v4.0'});ManagedPipelineMode='Integrated';StartMode='OnDemand';Enable32Bit=$false;IdleTimeout='00:20:00';LoadUserProfile=$false;IdentityType='ApplicationPoolIdentity';UserName='';Password=''}
    $poolApi = [ordered]@{Name='sp_api';ManagedRuntimeVersion='';ManagedPipelineMode='Integrated';StartMode='AlwaysRunning';Enable32Bit=$false;IdleTimeout=$(if($v2){'00:00:00'}else{'00:30:00'});LoadUserProfile=$true;IdentityType='ApplicationPoolIdentity';UserName='';Password=''}
    $poolIdn = [ordered]@{Name='sp_idn';ManagedRuntimeVersion='';ManagedPipelineMode='Integrated';StartMode='OnDemand';Enable32Bit=$false;IdleTimeout='00:20:00';LoadUserProfile=$false;IdentityType='SpecificUser';UserName=$User;Password=$Password}

    $bindings = @(
        [ordered]@{Protocol='http';Information='*:8111:sp1.alt.local';SslFlags=0;Thumbprint='';Store=''},
        [ordered]@{Protocol='https';Information='*:8443:sp1.local';SslFlags=1;Thumbprint=$Thumbprint;Store='My'}
    )
    if ($v2) { $bindings += [ordered]@{Protocol='http';Information='*:8112:sp1.v2.local';SslFlags=0;Thumbprint='';Store=''} }

    $apps = @(
        [ordered]@{Path='/sisqualWFM';PhysicalPath=$(if($v2){Join-Path $SpikeRoot 'sp1\wfm2'}else{Join-Path $SpikeRoot 'sp1\wfm'});PoolName=$(if($v2){'sp_api'}else{'sp_wfm'});EnabledProtocols=$(if($v2){'http,https'}else{'http'});PreloadEnabled=$v2},
        [ordered]@{Path='/V8/api';PhysicalPath=(Join-Path $SpikeRoot 'sp1\v8api');PoolName='sp_api';EnabledProtocols='http,https';PreloadEnabled=(-not $v2)},
        [ordered]@{Path='/V8/idn';PhysicalPath=(Join-Path $SpikeRoot 'sp1\v8idn');PoolName='sp_idn';EnabledProtocols='http';PreloadEnabled=$false}
    )

    $locations = @(
        [ordered]@{Location='sp1/sisqualWFM';Filter='system.webServer/directoryBrowse';Enabled=$v2},
        [ordered]@{Location='sp1/sisqualWFM';Filter='system.webServer/defaultDocument';Enabled=$true},
        [ordered]@{Location='sp1/V8/api';Filter='system.webServer/directoryBrowse';Enabled=(-not $v2)},
        [ordered]@{Location='sp1/V8/api';Filter='system.webServer/defaultDocument';Enabled=(-not $v2)}
    )

    $site = [ordered]@{
        Name='sp1'
        Id=9101
        PhysicalPath=(Join-Path $SpikeRoot 'sp1')
        PoolName='sp_wfm'
        Primary=[ordered]@{IpAddress='*';Port=8101;HostHeader='sp1.local'}
        ServerAutoStart=$true
        LogDirectory=$(if($v2){Join-Path $SpikeRoot 'logs2'}else{Join-Path $SpikeRoot 'logs1'})
        ExtraBindings=@($bindings)
        Applications=@($apps)
        LocationSettings=@($locations)
    }
    return [ordered]@{Version=$Version;Pools=@($poolWfm,$poolApi,$poolIdn);Sites=@($site)}
}

function Reset-Spike {
    $removedSites = 0
    $removedPools = 0
    $siteLines = @(& $appcmd list site 2>$null)
    foreach ($l in $siteLines) {
        if ($l -match '^SITE "([^"]+)"') {
            $n = $Matches[1]
            if ($n -match '^(sp\d+|sc\d+)$') { & $appcmd delete site $n 2>&1 | Out-Null; $removedSites++ }
        }
    }
    $poolLines = @(& $appcmd list apppool 2>$null)
    foreach ($l in $poolLines) {
        if ($l -match '^APPPOOL "([^"]+)"') {
            $n = $Matches[1]
            if ($n -match '^(sp_[A-Za-z0-9_]+|sc\d+_[A-Za-z0-9_]+)$') { & $appcmd delete apppool $n 2>&1 | Out-Null; $removedPools++ }
        }
    }
    & netsh http delete sslcert hostnameport=sp1.local:8443 2>&1 | Out-Null
    return [pscustomobject]@{SitesRemoved=$removedSites;PoolsRemoved=$removedPools}
}

function Count-SpikeObjects {
    $sites = @(@(& $appcmd list site 2>$null) | Where-Object { $_ -match '^SITE "(sp\d+|sc\d+)"' }).Count
    $pools = @(@(& $appcmd list apppool 2>$null) | Where-Object { $_ -match '^APPPOOL "(sp_[A-Za-z0-9_]+|sc\d+_[A-Za-z0-9_]+)"' }).Count
    return [pscustomobject]@{Sites=$sites;Pools=$pools}
}

function Flatten-Object {
    param($Obj,[string]$Prefix,[hashtable]$Acc)
    if ($null -eq $Obj) { $Acc[$Prefix]='<null>'; return }
    if ($Obj -is [string] -or $Obj -is [ValueType]) { $Acc[$Prefix]=[string]$Obj; return }
    if ($Obj -is [System.Collections.IEnumerable] -and -not ($Obj -is [System.Management.Automation.PSCustomObject])) {
        $i=0
        foreach ($x in $Obj) { Flatten-Object $x ($Prefix+'['+$i+']') $Acc; $i++ }
        return
    }
    foreach ($p in $Obj.PSObject.Properties) { Flatten-Object $p.Value ($Prefix+'.'+$p.Name) $Acc }
}

function Compare-Snapshots {
    param($A,$B)
    $fa=@{}; $fb=@{}
    Flatten-Object $A '' $fa
    Flatten-Object $B '' $fb
    $keys=@(@($fa.Keys)+@($fb.Keys) | Sort-Object -Unique)
    $diffs=New-Object 'System.Collections.Generic.List[object]'
    $notes=New-Object 'System.Collections.Generic.List[string]'
    $ignored=0
    foreach ($k in $keys) {
        # Runtime state of w3wp worker processes (PID, GUID, state) is not configuration.
        if ($k -match '\.workerProcesses(\.|\[|$)') { $ignored++; continue }
        $va=$(if($fa.ContainsKey($k)){$fa[$k]}else{'<missing>'})
        $vb=$(if($fb.ContainsKey($k)){$fb[$k]}else{'<missing>'})
        if ($va -cne $vb) {
            if ($k -match 'certificateStoreName$' -and [string]::Equals([string]$va,[string]$vb,[StringComparison]::OrdinalIgnoreCase)) {
                $notes.Add('certificateStoreName differs only by case: ' + $k + ' current=' + $va + ' mwa=' + $vb)
                continue
            }
            $diffs.Add([ordered]@{Path=$k;Current=$va;Mwa=$vb})
        }
    }
    return [pscustomobject]@{Compared=($keys.Count-$ignored);DiffCount=$diffs.Count;IgnoredVolatile=$ignored;Notes=@($notes);Diffs=@($diffs | Select-Object -First 80)}
}

function Get-HttpResult {
    param([string]$Url,[string]$HostHeader,[int]$Attempts=12)
    $last=$null
    for ($i=0; $i -lt $Attempts; $i++) {
        try {
            $req=[System.Net.HttpWebRequest]::Create($Url)
            $req.Host=$HostHeader
            $req.Timeout=20000
            $req.Method='GET'
            $resp=$req.GetResponse()
            try {
                $sr=New-Object System.IO.StreamReader($resp.GetResponseStream())
                $content=$sr.ReadToEnd()
                $sr.Dispose()
                return [ordered]@{Status=[int]$resp.StatusCode;Content=([string]$content).Trim();Attempts=($i+1);Error=$null}
            }
            finally { $resp.Close() }
        }
        catch [System.Net.WebException] {
            $last=$_.Exception.Message
            $resp2=$_.Exception.Response
            if ($null -ne $resp2) {
                $code=[int]$resp2.StatusCode
                $resp2.Close()
                if ($code -ne 503) { return [ordered]@{Status=$code;Content=$null;Attempts=($i+1);Error=$last} }
            }
            Start-Sleep -Seconds 2
        }
        catch {
            $last=$_.Exception.Message
            Start-Sleep -Seconds 2
        }
    }
    return [ordered]@{Status=$null;Content=$null;Attempts=$Attempts;Error=$last}
}

try {
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

    $os=Get-CimInstance Win32_OperatingSystem
    Add-Result 'HOST_INFO' 'PASS' 'Host inventory.' ([ordered]@{ComputerName=$env:COMPUTERNAME;Caption=$os.Caption;Build=$os.BuildNumber;HostPowerShell=$PSVersionTable.PSVersion.ToString()})

    $admin=Is-Admin
    Add-Result 'HOST_ADMINISTRATOR' $(if($admin){'PASS'}else{'FAIL'}) $(if($admin){'Process is elevated.'}else{'Not elevated; IIS writes will fail.'}) ([ordered]@{IsAdministrator=$admin})
    if (-not $admin) { throw 'Administrator rights are required.' }

    $inet=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\InetStp' -ErrorAction SilentlyContinue
    if ($null -eq $inet) { throw 'IIS is not installed on this machine.' }
    Add-Result 'HOST_IIS_PRESENT' 'PASS' 'IIS detected.' ([ordered]@{Version=('{0}.{1}' -f $inet.MajorVersion,$inet.MinorVersion);Appcmd=(Test-Path $appcmd)})

    # Portable PowerShell 7 (same pinned artifact as Phase 1A)
    $psZip=Join-Path $ArtifactRoot $Pinned.PowerShell.FileName
    Assert-Sha256 'POWERSHELL' $psZip $Pinned.PowerShell.Sha256 $Pinned.PowerShell.Version $Pinned.PowerShell.PublishedBy
    $psRoot=Join-Path $TempRoot 'pwsh'
    Expand-Archive -LiteralPath $psZip -DestinationPath $psRoot -Force
    $pwsh=Get-ChildItem $psRoot -Filter pwsh.exe -File -Recurse | Select-Object -First 1 -ExpandProperty FullName
    if (-not $pwsh) { throw 'pwsh.exe not found after extraction.' }

    # Test fixtures: directories with content, local identity user, self-signed certificate
    foreach ($d in @('sp1','sp1\wfm','sp1\wfm2','sp1\v8api','sp1\v8idn','logs1','logs2','scale')) {
        New-Item -ItemType Directory -Path (Join-Path $SpikeRoot $d) -Force | Out-Null
    }
    Set-Content -LiteralPath (Join-Path $SpikeRoot 'sp1\wfm\index.html') -Value 'sp1-wfm' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $SpikeRoot 'sp1\wfm2\index.html') -Value 'sp1-wfm2' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $SpikeRoot 'sp1\v8api\index.html') -Value 'sp1-v8api' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $SpikeRoot 'scale\index.html') -Value 'scale' -Encoding ASCII

    $idPassword='Aa1!'+(-join ((48..57)+(65..90)+(97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ }))
    try {
        New-LocalUser -Name $IdentityUser -Password (ConvertTo-SecureString $idPassword -AsPlainText -Force) -AccountNeverExpires -PasswordNeverExpires | Out-Null
        $UserCreated=$true
    } catch { Add-Result 'FIXTURE_LOCAL_USER' 'WARN' 'Could not create the local identity user; SpecificUser pool will use a non-existent account (configuration only).' $null (Err $_) }

    $cert=New-SelfSignedCertificate -DnsName 'sp1.local' -CertStoreLocation 'Cert:\LocalMachine\My'
    $CertThumbprint=$cert.Thumbprint
    Add-Result 'FIXTURES' 'PASS' 'Fixtures created (directories, local user, self-signed certificate).' ([ordered]@{LocalUserCreated=$UserCreated;CertificateThumbprint=$CertThumbprint})

    $scenario1=Join-Path $TempRoot 'scenario-v1.json'
    $scenario2=Join-Path $TempRoot 'scenario-v2.json'
    (New-Scenario -Version 1 -Thumbprint $CertThumbprint -User $IdentityUser -Password $idPassword) | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $scenario1 -Encoding UTF8
    (New-Scenario -Version 2 -Thumbprint $CertThumbprint -User $IdentityUser -Password $idPassword) | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $scenario2 -Encoding UTF8

    # ---------------------------------------------------------------- child scripts
    $applyCurrent=Join-Path $TempRoot 'Apply-Current.ps1'
    @'
param([string]$OutputPath,[string]$ScenarioPath)
$ErrorActionPreference='Stop'
$r=[ordered]@{Success=$false;ElapsedMs=$null;Notes=@();Error=$null}
$sw=[Diagnostics.Stopwatch]::StartNew()
try{
    Import-Module WebAdministration -ErrorAction Stop
    [void][Reflection.Assembly]::LoadFrom((Join-Path $env:windir 'System32\inetsrv\Microsoft.Web.Administration.dll'))
    $sc=Get-Content -LiteralPath $ScenarioPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($p in @($sc.Pools)){
        $m=New-Object Microsoft.Web.Administration.ServerManager
        try{
            $pool=$m.ApplicationPools[[string]$p.Name]
            if($null -eq $pool){$pool=$m.ApplicationPools.Add([string]$p.Name)}
            $pool.ManagedRuntimeVersion=[string]$p.ManagedRuntimeVersion
            $pool.ManagedPipelineMode=[Microsoft.Web.Administration.ManagedPipelineMode]([string]$p.ManagedPipelineMode)
            $pool.StartMode=[Microsoft.Web.Administration.StartMode]([string]$p.StartMode)
            $pool.Enable32BitAppOnWin64=[bool]$p.Enable32Bit
            $pool.ProcessModel.IdleTimeout=[TimeSpan]::Parse([string]$p.IdleTimeout)
            $pool.ProcessModel.LoadUserProfile=[bool]$p.LoadUserProfile
            if([string]$p.IdentityType -eq 'SpecificUser'){
                $pool.ProcessModel.IdentityType=[Microsoft.Web.Administration.ProcessModelIdentityType]::SpecificUser
                $pool.ProcessModel.UserName=[string]$p.UserName
                $pool.ProcessModel.Password=[string]$p.Password
            }else{
                $pool.ProcessModel.IdentityType=[Microsoft.Web.Administration.ProcessModelIdentityType]::ApplicationPoolIdentity
            }
            $m.CommitChanges()
        }finally{$m.Dispose()}
    }
    foreach($s in @($sc.Sites)){
        $name=[string]$s.Name
        if($null -eq (Get-Website -Name $name -ErrorAction SilentlyContinue)){
            New-Website -Name $name -Id ([int]$s.Id) -PhysicalPath ([string]$s.PhysicalPath) -ApplicationPool ([string]$s.PoolName) -IPAddress ([string]$s.Primary.IpAddress) -Port ([int]$s.Primary.Port) -HostHeader ([string]$s.Primary.HostHeader) | Out-Null
        }
        Set-ItemProperty -Path ('IIS:\Sites\'+$name) -Name serverAutoStart -Value ([bool]$s.ServerAutoStart)
        Set-ItemProperty -Path ('IIS:\Sites\'+$name) -Name logFile.directory -Value ([string]$s.LogDirectory)
        foreach($eb in @($s.ExtraBindings)){
            $m=New-Object Microsoft.Web.Administration.ServerManager
            try{
                $site=$m.Sites[$name]
                $exists=$false
                foreach($b in $site.Bindings){ if([string]$b.Protocol -eq [string]$eb.Protocol -and [string]$b.BindingInformation -eq [string]$eb.Information){$exists=$true} }
                if(-not $exists){
                    $nb=$site.Bindings.Add([string]$eb.Information,[string]$eb.Protocol)
                    if([string]$eb.Protocol -eq 'https'){$nb.SslFlags=[Enum]::ToObject($nb.SslFlags.GetType(),[int]$eb.SslFlags)}
                    $m.CommitChanges()
                }
            }finally{$m.Dispose()}
            if([string]$eb.Protocol -eq 'https' -and -not [string]::IsNullOrEmpty([string]$eb.Thumbprint)){
                $wb=@(Get-WebBinding -Name $name -Protocol https | Where-Object { [string]$_.bindingInformation -eq [string]$eb.Information })[0]
                if($null -eq $wb){throw ('https binding not found: '+$eb.Information)}
                if([string]$wb.certificateHash -ne [string]$eb.Thumbprint){$wb.AddSslCertificate([string]$eb.Thumbprint,[string]$eb.Store)}
            }
        }
        foreach($a in @($s.Applications)){
            $appName=([string]$a.Path).TrimStart('/')
            if($null -eq (Get-WebApplication -Site $name -Name $appName -ErrorAction SilentlyContinue)){
                New-WebApplication -Site $name -Name $appName -PhysicalPath ([string]$a.PhysicalPath) -ApplicationPool ([string]$a.PoolName) -ErrorAction Stop | Out-Null
            }
            $filter="system.applicationHost/sites/site[@name='$name']/application[@path='$($a.Path)']"
            $vfilter="$filter/virtualDirectory[@path='/']"
            Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $filter -Name applicationPool -Value ([string]$a.PoolName)
            Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $filter -Name enabledProtocols -Value ([string]$a.EnabledProtocols)
            Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $vfilter -Name physicalPath -Value ([string]$a.PhysicalPath)
            Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $filter -Name preloadEnabled -Value ([bool]$a.PreloadEnabled)
        }
        foreach($ls in @($s.LocationSettings)){
            Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location ([string]$ls.Location) -Filter ([string]$ls.Filter) -Name enabled -Value ([bool]$ls.Enabled)
        }
    }
    $r.Success=$true
}catch{$r.Error=$_.Exception.GetType().FullName+': '+$_.Exception.Message+' | '+(([string]$_.ScriptStackTrace) -replace '\s+',' ')}
$sw.Stop();$r.ElapsedMs=$sw.Elapsed.TotalMilliseconds
$r|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $OutputPath -Encoding utf8
'@ | Set-Content -LiteralPath $applyCurrent -Encoding UTF8

    $applyMwa=Join-Path $TempRoot 'Apply-Mwa.ps1'
    @'
param([string]$OutputPath,[string]$ScenarioPath)
$ErrorActionPreference='Stop'
$r=[ordered]@{Success=$false;ElapsedMs=$null;Error=$null}
$sw=[Diagnostics.Stopwatch]::StartNew()
try{
    [void][Reflection.Assembly]::LoadFrom((Join-Path $env:windir 'System32\inetsrv\Microsoft.Web.Administration.dll'))
    $sc=Get-Content -LiteralPath $ScenarioPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $sm=[Microsoft.Web.Administration.ServerManager]::new()
    try{
        foreach($p in @($sc.Pools)){
            $pool=$sm.ApplicationPools[[string]$p.Name]
            if($null -eq $pool){$pool=$sm.ApplicationPools.Add([string]$p.Name)}
            $pool.ManagedRuntimeVersion=[string]$p.ManagedRuntimeVersion
            $pool.ManagedPipelineMode=[Microsoft.Web.Administration.ManagedPipelineMode]([string]$p.ManagedPipelineMode)
            $pool.StartMode=[Microsoft.Web.Administration.StartMode]([string]$p.StartMode)
            $pool.Enable32BitAppOnWin64=[bool]$p.Enable32Bit
            $pool.ProcessModel.IdleTimeout=[TimeSpan]::Parse([string]$p.IdleTimeout)
            $pool.ProcessModel.LoadUserProfile=[bool]$p.LoadUserProfile
            if([string]$p.IdentityType -eq 'SpecificUser'){
                $pool.ProcessModel.IdentityType=[Microsoft.Web.Administration.ProcessModelIdentityType]::SpecificUser
                $pool.ProcessModel.UserName=[string]$p.UserName
                $pool.ProcessModel.Password=[string]$p.Password
            }else{
                $pool.ProcessModel.IdentityType=[Microsoft.Web.Administration.ProcessModelIdentityType]::ApplicationPoolIdentity
            }
        }
        foreach($s in @($sc.Sites)){
            $site=$sm.Sites[[string]$s.Name]
            if($null -eq $site){
                $info=('{0}:{1}:{2}' -f $s.Primary.IpAddress,$s.Primary.Port,$s.Primary.HostHeader)
                $site=$sm.Sites.Add([string]$s.Name,'http',$info,[string]$s.PhysicalPath)
                $site.Id=[long]$s.Id
            }
            $root=$site.Applications['/']
            $root.ApplicationPoolName=[string]$s.PoolName
            $root.VirtualDirectories['/'].PhysicalPath=[string]$s.PhysicalPath
            $site.ServerAutoStart=[bool]$s.ServerAutoStart
            $site.LogFile.Directory=[string]$s.LogDirectory
            foreach($eb in @($s.ExtraBindings)){
                $exists=$false
                foreach($b in $site.Bindings){ if([string]$b.Protocol -eq [string]$eb.Protocol -and [string]$b.BindingInformation -eq [string]$eb.Information){$exists=$true} }
                if(-not $exists){
                    if([string]$eb.Protocol -eq 'https' -and -not [string]::IsNullOrEmpty([string]$eb.Thumbprint)){
                        $hash=[Convert]::FromHexString([string]$eb.Thumbprint)
                        [void]$site.Bindings.Add([string]$eb.Information,$hash,[string]$eb.Store,[Microsoft.Web.Administration.SslFlags]([int]$eb.SslFlags))
                    }else{
                        [void]$site.Bindings.Add([string]$eb.Information,[string]$eb.Protocol)
                    }
                }
            }
            foreach($a in @($s.Applications)){
                $app=$site.Applications[[string]$a.Path]
                if($null -eq $app){$app=$site.Applications.Add([string]$a.Path,[string]$a.PhysicalPath)}
                $app.ApplicationPoolName=[string]$a.PoolName
                $app.EnabledProtocols=[string]$a.EnabledProtocols
                $app.SetAttributeValue('preloadEnabled',[bool]$a.PreloadEnabled)
                $app.VirtualDirectories['/'].PhysicalPath=[string]$a.PhysicalPath
            }
        }
        $cfg=$sm.GetApplicationHostConfiguration()
        foreach($s in @($sc.Sites)){
            foreach($ls in @($s.LocationSettings)){
                $sec=$cfg.GetSection([string]$ls.Filter,[string]$ls.Location)
                $sec['enabled']=[bool]$ls.Enabled
            }
        }
        $sm.CommitChanges()
    }finally{$sm.Dispose()}
    $r.Success=$true
}catch{$r.Error=$_.Exception.GetType().FullName+': '+$_.Exception.Message+' | '+(([string]$_.ScriptStackTrace) -replace '\s+',' ')}
$sw.Stop();$r.ElapsedMs=$sw.Elapsed.TotalMilliseconds
$r|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $OutputPath -Encoding utf8
'@ | Set-Content -LiteralPath $applyMwa -Encoding UTF8

    $snapMwa=Join-Path $TempRoot 'Snapshot-Mwa.ps1'
    @'
param([string]$OutputPath,[string]$ScenarioPath,[string]$SnapshotPath)
$ErrorActionPreference='Stop'
$r=[ordered]@{Success=$false;Error=$null;Bytes=$null}
function Convert-Value($v){
    if($null -eq $v){return $null}
    if($v -is [byte[]]){return ([BitConverter]::ToString($v) -replace '-','')}
    return [string]$v
}
function Dump-Element($e,[int]$depth){
    $o=[ordered]@{}
    if($null -eq $e -or $depth -gt 8){return $o}
    foreach($a in $e.Attributes){
        $n=[string]$a.Name
        if($n -match 'password|secret'){$o[$n]='(masked)'}else{$o[$n]=Convert-Value $a.Value}
    }
    foreach($c in $e.ChildElements){
        $tag=[string]$c.ElementTagName
        if($c -is [Microsoft.Web.Administration.ConfigurationElementCollection]){
            $items=[ordered]@{}
            $i=0
            foreach($item in $c){
                $names=@($item.Attributes|ForEach-Object{[string]$_.Name})
                $key=$null
                if($names -contains 'bindingInformation'){$key=([string]$item.GetAttributeValue('protocol'))+' '+([string]$item.GetAttributeValue('bindingInformation'))}
                elseif($names -contains 'path'){$key=[string]$item.GetAttributeValue('path')}
                elseif($names -contains 'name'){$key=[string]$item.GetAttributeValue('name')}
                if($null -eq $key){$key='#'+$i}
                $items[$key]=Dump-Element $item ($depth+1)
                $i++
            }
            $o[$tag]=$items
        }else{
            $o[$tag]=Dump-Element $c ($depth+1)
        }
    }
    return $o
}
try{
    [void][Reflection.Assembly]::LoadFrom((Join-Path $env:windir 'System32\inetsrv\Microsoft.Web.Administration.dll'))
    $sc=Get-Content -LiteralPath $ScenarioPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $sm=[Microsoft.Web.Administration.ServerManager]::new()
    try{
        $snap=[ordered]@{Pools=[ordered]@{};Sites=[ordered]@{};Locations=[ordered]@{}}
        foreach($p in @($sc.Pools)){
            $pool=$sm.ApplicationPools[[string]$p.Name]
            if($null -eq $pool){$snap.Pools[[string]$p.Name]='<missing>'}else{$snap.Pools[[string]$p.Name]=Dump-Element $pool 0}
        }
        $cfg=$sm.GetApplicationHostConfiguration()
        foreach($s in @($sc.Sites)){
            $site=$sm.Sites[[string]$s.Name]
            if($null -eq $site){$snap.Sites[[string]$s.Name]='<missing>'}else{$snap.Sites[[string]$s.Name]=Dump-Element $site 0}
            foreach($ls in @($s.LocationSettings)){
                $sec=$cfg.GetSection([string]$ls.Filter,[string]$ls.Location)
                $snap.Locations[([string]$ls.Location)+' '+([string]$ls.Filter)]=[string]$sec['enabled']
            }
        }
    }finally{$sm.Dispose()}
    $json=$snap|ConvertTo-Json -Depth 30
    $json|Set-Content -LiteralPath $SnapshotPath -Encoding utf8
    $r.Bytes=$json.Length
    $r.Success=$true
}catch{$r.Error=$_.Exception.GetType().FullName+': '+$_.Exception.Message+' | '+(([string]$_.ScriptStackTrace) -replace '\s+',' ')}
$r|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $OutputPath -Encoding utf8
'@ | Set-Content -LiteralPath $snapMwa -Encoding UTF8

    $stateMwa=Join-Path $TempRoot 'State-Mwa.ps1'
    @'
param([string]$OutputPath,[string]$PoolName,[string]$SiteName,[ValidateSet('Stop','Start','Recycle')][string]$Action)
$ErrorActionPreference='Stop'
$r=[ordered]@{Success=$false;Action=$Action;PoolStateAfter=$null;SiteStateAfter=$null;Reached=$false;Error=$null}
function New-Manager{[Microsoft.Web.Administration.ServerManager]::new()}
function Get-PoolState{$m=New-Manager;try{return [string]$m.ApplicationPools[$PoolName].State}finally{$m.Dispose()}}
function Get-SiteState{$m=New-Manager;try{return [string]$m.Sites[$SiteName].State}finally{$m.Dispose()}}
function Wait-For([scriptblock]$Get,[string]$Want,[int]$TimeoutMs=30000){
    $sw=[Diagnostics.Stopwatch]::StartNew()
    while($sw.ElapsedMilliseconds -lt $TimeoutMs){ if((& $Get) -eq $Want){return $true}; Start-Sleep -Milliseconds 300 }
    return $false
}
try{
    [void][Reflection.Assembly]::LoadFrom((Join-Path $env:windir 'System32\inetsrv\Microsoft.Web.Administration.dll'))
    $m=New-Manager
    try{
        if($Action -eq 'Stop'){
            [void]$m.ApplicationPools[$PoolName].Stop()
            [void]$m.Sites[$SiteName].Stop()
            $r.Reached=((Wait-For {Get-PoolState} 'Stopped') -and (Wait-For {Get-SiteState} 'Stopped'))
        }elseif($Action -eq 'Start'){
            [void]$m.ApplicationPools[$PoolName].Start()
            [void]$m.Sites[$SiteName].Start()
            $r.Reached=((Wait-For {Get-PoolState} 'Started') -and (Wait-For {Get-SiteState} 'Started'))
        }else{
            [void]$m.ApplicationPools[$PoolName].Recycle()
            Start-Sleep -Seconds 2
            $r.Reached=((Get-PoolState) -eq 'Started')
        }
    }finally{$m.Dispose()}
    $r.PoolStateAfter=Get-PoolState
    $r.SiteStateAfter=Get-SiteState
    $r.Success=$true
}catch{$r.Error=$_.Exception.GetType().FullName+': '+$_.Exception.Message+' | '+(([string]$_.ScriptStackTrace) -replace '\s+',' ')}
$r|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $OutputPath -Encoding utf8
'@ | Set-Content -LiteralPath $stateMwa -Encoding UTF8

    $readCmdlets=Join-Path $TempRoot 'Read-Cmdlets.ps1'
    @'
param([string]$OutputPath,[string]$PoolName,[string]$SiteName)
$ErrorActionPreference='Stop'
$r=[ordered]@{Success=$false;PoolState=$null;SiteState=$null;Applications=@();Bindings=@();Pools=@();Error=$null}
try{
    Import-Module WebAdministration -ErrorAction Stop
    $r.PoolState=[string](Get-WebAppPoolState -Name $PoolName).Value
    $r.SiteState=[string](Get-WebsiteState -Name $SiteName).Value
    $r.Applications=@(Get-WebApplication -Site $SiteName | ForEach-Object { [string]$_.path })
    $r.Bindings=@(Get-WebBinding -Name $SiteName | ForEach-Object { [string]$_.protocol+' '+[string]$_.bindingInformation })
    $r.Pools=@(Get-ChildItem 'IIS:\AppPools' | ForEach-Object { [string]$_.Name } | Where-Object { $_ -like 'sp_*' })
    $r.Success=$true
}catch{$r.Error=$_.Exception.GetType().FullName+': '+$_.Exception.Message}
$r|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $OutputPath -Encoding utf8
'@ | Set-Content -LiteralPath $readCmdlets -Encoding UTF8

    $scaleCurrent=Join-Path $TempRoot 'Scale-Current.ps1'
    @'
param([string]$OutputPath,[int]$Sites,[int]$AppsPerSite,[string]$ContentPath)
$ErrorActionPreference='Stop'
$r=[ordered]@{Success=$false;Sites=$Sites;AppsPerSite=$AppsPerSite;Pools=$null;Applications=$null;CreateMs=$null;EnumSitesMs=$null;EnumAppsMs=$null;EnumPoolsMs=$null;PoolStatesMs=$null;Error=$null}
try{
    Import-Module WebAdministration -ErrorAction Stop
    [void][Reflection.Assembly]::LoadFrom((Join-Path $env:windir 'System32\inetsrv\Microsoft.Web.Administration.dll'))
    $sw=[Diagnostics.Stopwatch]::StartNew()
    for($s=1;$s -le $Sites;$s++){
        $site=('sc{0:D2}' -f $s)
        $sitePool=$site+'_site'
        $m=New-Object Microsoft.Web.Administration.ServerManager
        try{[void]$m.ApplicationPools.Add($sitePool);$m.CommitChanges()}finally{$m.Dispose()}
        New-Website -Name $site -Id (9200+$s) -PhysicalPath $ContentPath -ApplicationPool $sitePool -IPAddress '*' -Port (8200+$s) -HostHeader ($site+'.local') | Out-Null
        for($a=1;$a -le $AppsPerSite;$a++){
            $pool=('{0}_a{1:D2}' -f $site,$a)
            $m=New-Object Microsoft.Web.Administration.ServerManager
            try{[void]$m.ApplicationPools.Add($pool);$m.CommitChanges()}finally{$m.Dispose()}
            New-WebApplication -Site $site -Name ('app{0:D2}' -f $a) -PhysicalPath $ContentPath -ApplicationPool $pool | Out-Null
        }
    }
    $sw.Stop();$r.CreateMs=$sw.Elapsed.TotalMilliseconds
    $sw=[Diagnostics.Stopwatch]::StartNew();$siteList=@(Get-Website | Where-Object { $_.Name -like 'sc*' });$sw.Stop();$r.EnumSitesMs=$sw.Elapsed.TotalMilliseconds
    $sw=[Diagnostics.Stopwatch]::StartNew();$apps=@(Get-WebApplication | Where-Object { $_.path -like '/app*' });$sw.Stop();$r.EnumAppsMs=$sw.Elapsed.TotalMilliseconds;$r.Applications=$apps.Count
    $sw=[Diagnostics.Stopwatch]::StartNew();$pools=@(Get-ChildItem 'IIS:\AppPools' | Where-Object { $_.Name -like 'sc*' });$sw.Stop();$r.EnumPoolsMs=$sw.Elapsed.TotalMilliseconds;$r.Pools=$pools.Count
    $sw=[Diagnostics.Stopwatch]::StartNew();foreach($p in $pools){[void](Get-WebAppPoolState -Name ([string]$p.Name))};$sw.Stop();$r.PoolStatesMs=$sw.Elapsed.TotalMilliseconds
    $r.Success=$true
}catch{$r.Error=$_.Exception.GetType().FullName+': '+$_.Exception.Message+' | '+(([string]$_.ScriptStackTrace) -replace '\s+',' ')}
$r|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $OutputPath -Encoding utf8
'@ | Set-Content -LiteralPath $scaleCurrent -Encoding UTF8

    $scaleMwa=Join-Path $TempRoot 'Scale-Mwa.ps1'
    @'
param([string]$OutputPath,[int]$Sites,[int]$AppsPerSite,[string]$ContentPath)
$ErrorActionPreference='Stop'
$r=[ordered]@{Success=$false;Sites=$Sites;AppsPerSite=$AppsPerSite;Pools=$null;Applications=$null;CreateMs=$null;EnumSitesMs=$null;EnumAppsMs=$null;EnumPoolsMs=$null;PoolStatesMs=$null;Error=$null}
try{
    [void][Reflection.Assembly]::LoadFrom((Join-Path $env:windir 'System32\inetsrv\Microsoft.Web.Administration.dll'))
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $sm=[Microsoft.Web.Administration.ServerManager]::new()
    try{
        for($s=1;$s -le $Sites;$s++){
            $siteName=('sc{0:D2}' -f $s)
            $sitePool=$siteName+'_site'
            [void]$sm.ApplicationPools.Add($sitePool)
            $site=$sm.Sites.Add($siteName,'http',('*:{0}:{1}.local' -f (8200+$s),$siteName),$ContentPath)
            $site.Id=[long](9200+$s)
            $site.Applications['/'].ApplicationPoolName=$sitePool
            for($a=1;$a -le $AppsPerSite;$a++){
                $pool=('{0}_a{1:D2}' -f $siteName,$a)
                [void]$sm.ApplicationPools.Add($pool)
                $app=$site.Applications.Add(('/app{0:D2}' -f $a),$ContentPath)
                $app.ApplicationPoolName=$pool
            }
        }
        $sm.CommitChanges()
    }finally{$sm.Dispose()}
    $sw.Stop();$r.CreateMs=$sw.Elapsed.TotalMilliseconds
    $sm=[Microsoft.Web.Administration.ServerManager]::new()
    try{
        $sw=[Diagnostics.Stopwatch]::StartNew();$siteList=@($sm.Sites | Where-Object { $_.Name -like 'sc*' });$sw.Stop();$r.EnumSitesMs=$sw.Elapsed.TotalMilliseconds
        $sw=[Diagnostics.Stopwatch]::StartNew();$count=0;foreach($x in $siteList){$count+=@($x.Applications | Where-Object { $_.Path -like '/app*' }).Count};$sw.Stop();$r.EnumAppsMs=$sw.Elapsed.TotalMilliseconds;$r.Applications=$count
        $sw=[Diagnostics.Stopwatch]::StartNew();$pools=@($sm.ApplicationPools | Where-Object { $_.Name -like 'sc*' });$sw.Stop();$r.EnumPoolsMs=$sw.Elapsed.TotalMilliseconds;$r.Pools=$pools.Count
        $sw=[Diagnostics.Stopwatch]::StartNew();foreach($p in $pools){[void][string]$p.State};$sw.Stop();$r.PoolStatesMs=$sw.Elapsed.TotalMilliseconds
    }finally{$sm.Dispose()}
    $r.Success=$true
}catch{$r.Error=$_.Exception.GetType().FullName+': '+$_.Exception.Message+' | '+(([string]$_.ScriptStackTrace) -replace '\s+',' ')}
$r|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $OutputPath -Encoding utf8
'@ | Set-Content -LiteralPath $scaleMwa -Encoding UTF8

    # ---------------------------------------------------------------- phase A: current approach (5.1 + cmdlets + MWA like the engine)
    $clean0=Reset-Spike
    Add-Result 'RESET_INITIAL' 'PASS' 'Spike objects removed before starting.' $clean0

    $snaps=@{}
    $n=0
    foreach ($step in @(@('M5_CREATE',$scenario1,'s5v1'),@('M5_MODIFY',$scenario2,'s5v2'))) {
        try {
            $out=Join-Path $TempRoot ($step[2]+'-apply.json')
            $run=Run-ChildJson $ps51 $applyCurrent $out @('-ScenarioPath',('"{0}"' -f $step[1]))
            if (Child-Ok $run) {
                $snapPath=Join-Path $TempRoot ($step[2]+'.json')
                $srun=Run-ChildJson $pwsh $snapMwa (Join-Path $TempRoot ($step[2]+'-snap.json')) @('-ScenarioPath',('"{0}"' -f $step[1]),'-SnapshotPath',('"{0}"' -f $snapPath))
                if (Child-Ok $srun) {
                    $snaps[$step[2]]=Get-Content -LiteralPath $snapPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    Add-Result $step[0] 'PASS' 'Current approach (Windows PowerShell 5.1 + cmdlets + MWA like IIS_RECONCILE) applied the scenario and PowerShell 7 + MWA read it back.' ([ordered]@{ApplyMs=$run.Payload.ElapsedMs;SnapshotBytes=$srun.Payload.Bytes})
                } else { Add-Result $step[0] 'FAIL' 'Scenario applied but the MWA snapshot (PowerShell 7) failed.' $null (Child-Error $srun) }
            } else { Add-Result $step[0] 'FAIL' 'Current approach failed to apply the scenario.' $null (Child-Error $run) }
        } catch { Add-Result $step[0] 'FAIL' 'Unexpected failure in the current-approach phase.' $null (Err $_) }
        $n++
    }
    $null=Reset-Spike

    # ---------------------------------------------------------------- phase B: candidate approach (PowerShell 7 + MWA only)
    $m7create=$false
    try {
        $run=Run-ChildJson $pwsh $applyMwa (Join-Path $TempRoot 's7v1-apply.json') @('-ScenarioPath',('"{0}"' -f $scenario1))
        if (Child-Ok $run) {
            $m7create=$true
            $snapPath=Join-Path $TempRoot 's7v1.json'
            $srun=Run-ChildJson $pwsh $snapMwa (Join-Path $TempRoot 's7v1-snap.json') @('-ScenarioPath',('"{0}"' -f $scenario1),'-SnapshotPath',('"{0}"' -f $snapPath))
            if (Child-Ok $srun) { $snaps['s7v1']=Get-Content -LiteralPath $snapPath -Raw -Encoding UTF8 | ConvertFrom-Json }
            Add-Result 'M7_CREATE' 'PASS' 'PowerShell 7 + Microsoft.Web.Administration created pools, site, bindings (with certificate), applications and location settings and committed.' ([ordered]@{ApplyMs=$run.Payload.ElapsedMs})
        } else { Add-Result 'M7_CREATE' 'FAIL' 'PowerShell 7 + MWA failed to apply the scenario.' $null (Child-Error $run) }
    } catch { Add-Result 'M7_CREATE' 'FAIL' 'Unexpected failure in the MWA create phase.' $null (Err $_) }

    if ($m7create) {
        # HTTP: the site created by MWA must actually serve content
        try {
            $h1=Get-HttpResult 'http://127.0.0.1:8101/sisqualWFM/' 'sp1.local'
            $h2=Get-HttpResult 'http://127.0.0.1:8111/sisqualWFM/' 'sp1.alt.local'
            $httpOk=($h1.Status -eq 200 -and $h1.Content -eq 'sp1-wfm' -and $h2.Status -eq 200)
            Add-Result 'M7_HTTP_SERVES' $(if($httpOk){'PASS'}else{'FAIL'}) 'Site and application created by MWA answer HTTP 200 through the primary and the extra binding.' ([ordered]@{Primary=$h1;ExtraBinding=$h2})
        } catch { Add-Result 'M7_HTTP_SERVES' 'FAIL' 'HTTP check threw.' $null (Err $_) }

        # certificate binding really registered in http.sys
        try {
            $ssl=(& netsh http show sslcert hostnameport=sp1.local:8443 2>&1 | Out-String)
            $sslOk=($ssl -match [regex]::Escape($CertThumbprint))
            Add-Result 'M7_SSL_BINDING' $(if($sslOk){'PASS'}else{'FAIL'}) 'The https binding created by MWA registered the certificate in http.sys.' ([ordered]@{ThumbprintFound=$sslOk})
        } catch { Add-Result 'M7_SSL_BINDING' 'FAIL' 'netsh check threw.' $null (Err $_) }

        # interop: cmdlets (5.1) see what MWA wrote
        try {
            $rrun=Run-ChildJson $ps51 $readCmdlets (Join-Path $TempRoot 'read1.json') @('-PoolName','sp_wfm','-SiteName','sp1')
            $p=$rrun.Payload
            $interopOk=((Child-Ok $rrun) -and @($p.Applications).Count -ge 3 -and @($p.Bindings).Count -ge 3 -and @($p.Pools).Count -ge 3)
            Add-Result 'M7_INTEROP_CMDLET_READ' $(if($interopOk){'PASS'}else{'FAIL'}) 'Windows PowerShell 5.1 WebAdministration cmdlets read the objects written by MWA from PowerShell 7.' $p (Child-Error $rrun)
        } catch { Add-Result 'M7_INTEROP_CMDLET_READ' 'FAIL' 'Interop read threw.' $null (Err $_) }

        # state operations through MWA, verified with cmdlets
        try {
            $stateOk=$true
            $stateData=[ordered]@{}
            foreach ($act in @('Stop','Start','Recycle')) {
                $srun=Run-ChildJson $pwsh $stateMwa (Join-Path $TempRoot ('state-'+$act+'.json')) @('-PoolName','sp_wfm','-SiteName','sp1','-Action',$act)
                $rrun=Run-ChildJson $ps51 $readCmdlets (Join-Path $TempRoot ('read-'+$act+'.json')) @('-PoolName','sp_wfm','-SiteName','sp1')
                $stateData[$act]=[ordered]@{Mwa=$srun.Payload;Cmdlets=$(if($null -ne $rrun.Payload){[ordered]@{Pool=$rrun.Payload.PoolState;Site=$rrun.Payload.SiteState}}else{$null})}
                if (-not (Child-Ok $srun) -or -not [bool]$srun.Payload.Reached) { $stateOk=$false }
                if ($act -eq 'Stop' -and ($rrun.Payload.PoolState -ne 'Stopped' -or $rrun.Payload.SiteState -ne 'Stopped')) { $stateOk=$false }
                if ($act -ne 'Stop' -and ($rrun.Payload.PoolState -ne 'Started' -or $rrun.Payload.SiteState -ne 'Started')) { $stateOk=$false }
            }
            Add-Result 'M7_STATE_OPERATIONS' $(if($stateOk){'PASS'}else{'FAIL'}) 'MWA stop/start/recycle of a pool and a site, confirmed by the 5.1 cmdlets.' $stateData
        } catch { Add-Result 'M7_STATE_OPERATIONS' 'FAIL' 'State operations threw.' $null (Err $_) }

        # modify (drift correction) and idempotency
        try {
            $run=Run-ChildJson $pwsh $applyMwa (Join-Path $TempRoot 's7v2-apply.json') @('-ScenarioPath',('"{0}"' -f $scenario2))
            if (Child-Ok $run) {
                $snapPath=Join-Path $TempRoot 's7v2.json'
                $srun=Run-ChildJson $pwsh $snapMwa (Join-Path $TempRoot 's7v2-snap.json') @('-ScenarioPath',('"{0}"' -f $scenario2),'-SnapshotPath',('"{0}"' -f $snapPath))
                if (Child-Ok $srun) { $snaps['s7v2']=Get-Content -LiteralPath $snapPath -Raw -Encoding UTF8 | ConvertFrom-Json }
                Add-Result 'M7_MODIFY' 'PASS' 'MWA applied the modified scenario on top of the existing state (drift correction path).' ([ordered]@{ApplyMs=$run.Payload.ElapsedMs})
                $run2=Run-ChildJson $pwsh $applyMwa (Join-Path $TempRoot 's7v2b-apply.json') @('-ScenarioPath',('"{0}"' -f $scenario2))
                $snapPathB=Join-Path $TempRoot 's7v2b.json'
                $srunB=Run-ChildJson $pwsh $snapMwa (Join-Path $TempRoot 's7v2b-snap.json') @('-ScenarioPath',('"{0}"' -f $scenario2),'-SnapshotPath',('"{0}"' -f $snapPathB))
                if ((Child-Ok $run2) -and (Child-Ok $srunB) -and $snaps.ContainsKey('s7v2')) {
                    $cmp=Compare-Snapshots $snaps['s7v2'] (Get-Content -LiteralPath $snapPathB -Raw -Encoding UTF8 | ConvertFrom-Json)
                    Add-Result 'M7_IDEMPOTENT' $(if($cmp.DiffCount -eq 0){'PASS'}else{'FAIL'}) 'Applying the same scenario twice with MWA changes nothing.' $cmp
                } else { Add-Result 'M7_IDEMPOTENT' 'FAIL' 'Second apply or its snapshot failed.' $null ((Child-Error $run2)+' / '+(Child-Error $srunB)) }
            } else { Add-Result 'M7_MODIFY' 'FAIL' 'MWA failed to apply the modified scenario.' $null (Child-Error $run) }
        } catch { Add-Result 'M7_MODIFY' 'FAIL' 'Modify phase threw.' $null (Err $_) }
    } else {
        foreach ($id in @('M7_HTTP_SERVES','M7_SSL_BINDING','M7_INTEROP_CMDLET_READ','M7_STATE_OPERATIONS','M7_MODIFY','M7_IDEMPOTENT')) { Add-Result $id 'SKIP' 'Skipped because the MWA create phase failed.' }
    }
    $null=Reset-Spike

    # ---------------------------------------------------------------- phase C: equivalence
    foreach ($pair in @(@('EQUIVALENCE_CREATE','s5v1','s7v1'),@('EQUIVALENCE_MODIFY','s5v2','s7v2'))) {
        if ($snaps.ContainsKey($pair[1]) -and $snaps.ContainsKey($pair[2])) {
            $cmp=Compare-Snapshots $snaps[$pair[1]] $snaps[$pair[2]]
            Add-Result $pair[0] $(if($cmp.DiffCount -eq 0){'PASS'}else{'FAIL'}) 'Effective configuration (pools, site, bindings, applications, virtual directories, location settings) is identical between the current approach and PowerShell 7 + MWA.' $cmp
        } else {
            Add-Result $pair[0] 'FAIL' 'A snapshot needed for the comparison is missing.' ([ordered]@{Have=@($snaps.Keys)})
        }
    }

    # ---------------------------------------------------------------- phase D: scale
    if ($SkipScale) {
        Add-Result 'SCALE_CURRENT' 'SKIP' 'Scale phase skipped by parameter.'
        Add-Result 'SCALE_MWA' 'SKIP' 'Scale phase skipped by parameter.'
    } else {
        $contentPath=Join-Path $SpikeRoot 'scale'
        foreach ($sc in @(@('SCALE_CURRENT',$ps51,$scaleCurrent),@('SCALE_MWA',$pwsh,$scaleMwa))) {
            try {
                $run=Run-ChildJson $sc[1] $sc[2] (Join-Path $TempRoot ($sc[0]+'.json')) @('-Sites',[string]$ScaleSites,'-AppsPerSite',[string]$ScaleAppsPerSite,'-ContentPath',('"{0}"' -f $contentPath))
                $sw=[Diagnostics.Stopwatch]::StartNew()
                $rs=Reset-Spike
                $sw.Stop()
                $data=[ordered]@{Result=$run.Payload;ResetMs=$sw.Elapsed.TotalMilliseconds;Removed=$rs}
                if ((Child-Ok $run) -and [int]$run.Payload.Applications -eq ($ScaleSites*$ScaleAppsPerSite)) {
                    Add-Result $sc[0] 'PASS' ('Created and enumerated {0} sites x {1} applications (one pool per application).' -f $ScaleSites,$ScaleAppsPerSite) $data
                } else { Add-Result $sc[0] 'FAIL' 'Scale run failed or counts do not match.' $data (Child-Error $run) }
            } catch { Add-Result $sc[0] 'FAIL' 'Scale phase threw.' $null (Err $_) }
        }
    }
}
catch {
    $Fatal = Err $_
    Add-Result 'RUN_FATAL' 'FAIL' 'Spike stopped after a fatal prerequisite/runtime failure.' $null $Fatal
}
finally {
    # cleanup (always) - no break/continue here, Windows PowerShell 5.1 rejects them in finally
    try { $null=Reset-Spike } catch { Add-Result 'CLEANUP_RESET' 'WARN' 'Final reset threw.' $null (Err $_) }
    try {
        $left=Count-SpikeObjects
        Add-Result 'CLEANUP_IIS_OBJECTS' $(if($left.Sites -eq 0 -and $left.Pools -eq 0){'PASS'}else{'FAIL'}) 'No spike site or application pool may remain.' $left
    } catch { Add-Result 'CLEANUP_IIS_OBJECTS' 'WARN' 'Could not count remaining objects.' $null (Err $_) }
    try {
        $ssl2=(& netsh http show sslcert hostnameport=sp1.local:8443 2>&1 | Out-String)
        $stillBound=($ssl2 -match 'Certificate Hash')
        Add-Result 'CLEANUP_SSL_BINDING' $(if($stillBound){'FAIL'}else{'PASS'}) 'No http.sys certificate binding may remain.' ([ordered]@{StillBound=$stillBound})
    } catch { Add-Result 'CLEANUP_SSL_BINDING' 'WARN' 'Could not query http.sys.' $null (Err $_) }
    try { if ($CertThumbprint) { Remove-Item -LiteralPath ('Cert:\LocalMachine\My\'+$CertThumbprint) -Force -ErrorAction SilentlyContinue } } catch {}
    try { if ($UserCreated) { Remove-LocalUser -Name $IdentityUser -ErrorAction SilentlyContinue } } catch {}
    try { if (Test-Path -LiteralPath $SpikeRoot) { Remove-Item -LiteralPath $SpikeRoot -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
    if (-not $KeepArtifacts) {
        try { if (Test-Path -LiteralPath $TempRoot) { Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
        Add-Result 'CLEANUP_TEMP_ROOT' $(if(Test-Path -LiteralPath $TempRoot){'FAIL'}else{'PASS'}) 'Temporary directory removed.' ([ordered]@{Path=$TempRoot})
    }

    $critical=@('M5_CREATE','M5_MODIFY','M7_CREATE','M7_HTTP_SERVES','M7_SSL_BINDING','M7_INTEROP_CMDLET_READ','M7_STATE_OPERATIONS','M7_MODIFY','M7_IDEMPOTENT','EQUIVALENCE_CREATE','EQUIVALENCE_MODIFY','CLEANUP_IIS_OBJECTS','CLEANUP_SSL_BINDING')
    $fail=@($Results|Where-Object{$critical -contains $_.Id -and $_.Status -eq 'FAIL'})
    $overall='PASS'
    if($fail.Count -gt 0 -or $Fatal){$overall='FAIL'}

    foreach($c in $Results){
        Write-Host ('CHECK {0,-5} {1,-28} {2}' -f $c.Status,$c.Id,$c.Message)
        if($c.Status -eq 'FAIL' -or $c.Status -eq 'WARN'){
            try{
                if($null -ne $c.Error -and [string]$c.Error -ne ''){Write-Host ('      ERROR: '+([string]$c.Error))}
                if($null -ne $c.Data){Write-Host ('      DATA : '+(($c.Data|ConvertTo-Json -Depth 6 -Compress)))}
            }catch{Write-Host ('      (could not print details: '+(Err $_)+')')}
        }
    }
    if($Fatal){Write-Host ('FATAL: '+$Fatal)}

    $flatChecks=@($Results|ForEach-Object{
        $item=$_
        $dj=$null
        try{ if($null -ne $item.Data){ $dj=($item.Data|ConvertTo-Json -Depth 12 -Compress) } }catch{ $dj='(data not serializable: '+$_.Exception.Message+')' }
        [ordered]@{Id=$item.Id;Status=$item.Status;Message=$item.Message;Error=$item.Error;DataJson=$dj}
    })
    $done=[DateTime]::UtcNow
    $report=[ordered]@{}
    $report['Phase']='1A-2'
    $report['Name']='IIS write path: PowerShell 7 + MWA vs current approach'
    $report['RunId']=$RunId
    $report['Machine']=$env:COMPUTERNAME
    $report['StartedAtUtc']=$StartedUtc.ToString('o')
    $report['CompletedAtUtc']=$done.ToString('o')
    $report['DurationSeconds']=[math]::Round(($done-$StartedUtc).TotalSeconds,3)
    $report['Overall']=$overall
    $report['ScaleSites']=$ScaleSites
    $report['ScaleAppsPerSite']=$ScaleAppsPerSite
    $report['PinnedArtifacts']=$Pinned
    $report['Checks']=@($flatChecks)
    $report['FatalError']=$Fatal

    $json=$null
    try{ $json=$report|ConvertTo-Json -Depth 20 }
    catch{
        $serr=Err $_
        Write-Host ('REPORT_SERIALIZATION_FAILED: '+$serr)
        $json=([ordered]@{Phase='1A-2';RunId=$RunId;Overall=$overall;FatalError=$Fatal;SerializationError=$serr;Checks=@($flatChecks)}|ConvertTo-Json -Depth 6)
    }
    $dir=Split-Path -Parent $ReportPath
    if($dir -and -not(Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $json|Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-Host ''
    Write-Host '========== SISQUALDeployConsole PHASE 1A-2 (IIS WRITE) REPORT =========='
    Write-Output $json
    Write-Host '========== END PHASE 1A-2 REPORT =========='
    Write-Host ('Report saved to: '+$ReportPath)
}
