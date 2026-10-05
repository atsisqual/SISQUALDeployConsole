#requires -Version 5.1
<#
Phase 1A architecture spike for SISQUALDeployConsole.
READ-ONLY against IIS/Windows/SISQUAL/SQL. Writable state is limited to %TEMP%.
No Internet is required. Place the three pinned ZIPs in .\artifacts next to this script.
#>

[CmdletBinding()]
param(
    [string]$ArtifactRoot = (Join-Path $PSScriptRoot 'artifacts'),
    [string]$ReportPath = '',
    [int]$PodePort = 0,
    [switch]$KeepArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Pinned = [ordered]@{
    PowerShell = [ordered]@{
        Version = '7.6.6'
        FileName = 'PowerShell-7.6.6-win-x64.zip'
        Sha256 = '02FE458BE20493FBDF43F61EA20610B811EE6C738AB1676C61B9CFCD1A33C860'
        PublishedBy = 'PowerShell/PowerShell release hashes.sha256'
        Source = 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.6/PowerShell-7.6.6-win-x64.zip'
    }
    Pode = [ordered]@{
        Version = '2.14.1'
        FileName = '2.14.1-Binaries.zip'
        Sha256 = '85CCA8D0446E5D57F57BA9FD859166845D4997A28B71142912B6B648A3F152C6'
        PublishedBy = 'Badgerati/Pode release checksum'
        Source = 'https://github.com/Badgerati/Pode/releases/download/v2.14.1/2.14.1-Binaries.zip'
    }
    SQLite = [ordered]@{
        Version = '3.53.4'
        FileName = 'sqlite-tools-win-x64-3530400.zip'
        Sha256 = 'F46EE2475DE4CBE287E6E5F7D43C838796B14E7379CD216BDBB28D391429F9FC'
        Sha256PublishedBy = 'ScoopInstaller/Main bucket/sqlite.json (3.53.4)'
        Sha3_256 = '88B4659FE747896B853AF10157316B4ADE143553EFB89C1C8CA7423A278DCC8B'
        Sha3PublishedBy = 'sqlite.org official download page'
        Source = 'https://www.sqlite.org/2026/sqlite-tools-win-x64-3530400.zip'
    }
}

$RunId = [guid]::NewGuid().ToString('N')
$StartedUtc = [DateTime]::UtcNow
$TempRoot = Join-Path $env:TEMP ('SISQUALDeployConsole-Phase1A-' + $RunId)
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $PSScriptRoot ('Phase1A-Report-{0}-{1}.json' -f $env:COMPUTERNAME,(Get-Date -Format 'yyyyMMdd_HHmmss'))
}

$Results = New-Object 'System.Collections.Generic.List[object]'
$PodeProcess = $null
$PodePortUsed = 0
$Fatal = $null
$IisPresent = $false
$BaselineShells = @(
    Get-Process -Name pwsh,powershell -ErrorAction SilentlyContinue |
    Select-Object ProcessName,Id
)

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
    if ($null -ne $E.Exception) {
        return ($E.Exception.GetType().FullName + ': ' + $E.Exception.Message)
    }
    return [string]$E
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

function Free-Port {
    $l=New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback,0)
    try { $l.Start(); return ([System.Net.IPEndPoint]$l.LocalEndpoint).Port } finally { $l.Stop() }
}

function Tcp-Connect([string]$Address,[int]$Port,[int]$TimeoutMs=1500) {
    $c=New-Object System.Net.Sockets.TcpClient
    try {
        $a=$c.BeginConnect($Address,$Port,$null,$null)
        if (-not $a.AsyncWaitHandle.WaitOne($TimeoutMs,$false)) { return $false }
        try { $c.EndConnect($a); return $c.Connected } catch { return $false }
    }
    finally { $c.Dispose() }
}

function Listeners([int]$Port) {
    if ($Port -le 0) { return @() }
    if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
        try {
            return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop | Select-Object LocalAddress,LocalPort,OwningProcess,State)
        } catch { return @() }
    }
    return @()
}

function Run-ChildJson {
    param([string]$Pwsh,[string]$Script,[string]$Out,[string[]]$Extra=@())
    $stdout=$Out+'.stdout.txt'
    $stderr=$Out+'.stderr.txt'
    $childArgs=@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $Script),'-OutputPath',('"{0}"' -f $Out))
    $childArgs += $Extra
    $p=Start-Process -FilePath $Pwsh -ArgumentList $childArgs -PassThru -Wait -RedirectStandardOutput $stdout -RedirectStandardError $stderr
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

try {
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

    $os=Get-CimInstance Win32_OperatingSystem
    Add-Result 'HOST_WINDOWS_X64' $(if([Environment]::Is64BitOperatingSystem){'PASS'}else{'FAIL'}) 'Host inventory.' ([ordered]@{
        ComputerName=$env:COMPUTERNAME
        Caption=$os.Caption
        Version=$os.Version
        Build=$os.BuildNumber
        Architecture=$os.OSArchitecture
        HostPowerShell=$PSVersionTable.PSVersion.ToString()
    })

    $admin=Is-Admin
    Add-Result 'HOST_ADMINISTRATOR' $(if($admin){'PASS'}else{'WARN'}) $(if($admin){'Process is elevated.'}else{'Not elevated; IIS visibility can be incomplete.'}) ([ordered]@{IsAdministrator=$admin})

    $inet=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\InetStp' -ErrorAction SilentlyContinue
    $IisPresent=($null -ne $inet)
    Add-Result 'HOST_IIS_PRESENT' $(if($IisPresent){'PASS'}else{'SKIP'}) $(if($IisPresent){'IIS detected.'}else{'IIS not detected; IIS block will be skipped.'}) ([ordered]@{
        Installed=$IisPresent
        Version=$(if($IisPresent){('{0}.{1}' -f $inet.MajorVersion,$inet.MinorVersion)}else{$null})
    })

    $psZip=Join-Path $ArtifactRoot $Pinned.PowerShell.FileName
    $podeZip=Join-Path $ArtifactRoot $Pinned.Pode.FileName
    $sqliteZip=Join-Path $ArtifactRoot $Pinned.SQLite.FileName

    Assert-Sha256 'POWERSHELL' $psZip $Pinned.PowerShell.Sha256 $Pinned.PowerShell.Version $Pinned.PowerShell.PublishedBy
    Assert-Sha256 'PODE' $podeZip $Pinned.Pode.Sha256 $Pinned.Pode.Version $Pinned.Pode.PublishedBy
    Assert-Sha256 'SQLITE' $sqliteZip $Pinned.SQLite.Sha256 $Pinned.SQLite.Version $Pinned.SQLite.Sha256PublishedBy

    # 1. Portable PowerShell 7
    $psRoot=Join-Path $TempRoot 'pwsh'
    Expand-Archive -LiteralPath $psZip -DestinationPath $psRoot -Force
    $pwsh=Get-ChildItem $psRoot -Filter pwsh.exe -File -Recurse | Select-Object -First 1 -ExpandProperty FullName
    if (-not $pwsh) { throw 'pwsh.exe not found after extraction.' }

    $psInfoScript=Join-Path $TempRoot 'Probe-Pwsh.ps1'
    @'
param([string]$OutputPath)
[pscustomobject]@{
    PSVersion=$PSVersionTable.PSVersion.ToString()
    PSEdition=$PSVersionTable.PSEdition
    PSHome=$PSHOME
    Framework=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
    ProcessArchitecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    Is64Bit=[Environment]::Is64BitProcess
}|ConvertTo-Json|Set-Content $OutputPath -Encoding utf8
'@ | Set-Content $psInfoScript -Encoding UTF8
    $psInfoOut=Join-Path $TempRoot 'pwsh.json'
    $psRun=Run-ChildJson $pwsh $psInfoScript $psInfoOut
    $psInfo=$psRun.Payload
    $psPass=($psRun.ExitCode -eq 0 -and $null -ne $psInfo -and [string]$psInfo.PSVersion -eq $Pinned.PowerShell.Version -and [bool]$psInfo.Is64Bit -and ([IO.Path]::GetFullPath([string]$psInfo.PSHome)).StartsWith([IO.Path]::GetFullPath($psRoot),[StringComparison]::OrdinalIgnoreCase))
    Add-Result 'POWERSHELL_PORTABLE' $(if($psPass){'PASS'}else{'FAIL'}) 'Pinned pwsh started from extracted runtime.' $psInfo $psRun.StdErr
    if (-not $psPass) { throw 'Portable PowerShell validation failed.' }

    # SQLite second provenance check: official sqlite.org SHA3-256.
    # SHA3 is only available on newer OS/.NET combinations (for example recent Windows 11 builds and
    # Windows Server 2025). Where it is unsupported this check is reported as WARN and the run continues:
    # the SHA-256 (official Scoop bucket) was already enforced above.
    $sha3Script=Join-Path $TempRoot 'Probe-Sha3.ps1'
    @'
param([string]$OutputPath,[string]$InputPath)
$ErrorActionPreference='Stop'
try{
    $supported=$false
    try{$supported=[bool][Security.Cryptography.SHA3_256]::IsSupported}catch{$supported=$false}
    if(-not $supported){
        [pscustomobject]@{Success=$true;Supported=$false;Sha3_256=$null;Error=$null}|ConvertTo-Json|Set-Content $OutputPath -Encoding utf8
        exit 0
    }
    $hex=[Convert]::ToHexString([Security.Cryptography.SHA3_256]::HashData([IO.File]::ReadAllBytes($InputPath)))
    [pscustomobject]@{Success=$true;Supported=$true;Sha3_256=$hex;Error=$null}|ConvertTo-Json|Set-Content $OutputPath -Encoding utf8
}catch{
    [pscustomobject]@{Success=$false;Supported=$null;Sha3_256=$null;Error=$_.Exception.GetType().FullName+': '+$_.Exception.Message}|ConvertTo-Json|Set-Content $OutputPath -Encoding utf8
    exit 1
}
'@ | Set-Content $sha3Script -Encoding UTF8
    $sha3Out=Join-Path $TempRoot 'sha3.json'
    $sha3Run=Run-ChildJson $pwsh $sha3Script $sha3Out @('-InputPath',('"{0}"' -f $sqliteZip))
    $sha3Payload=$sha3Run.Payload
    $sha3Info=[ordered]@{Expected=$Pinned.SQLite.Sha3_256;PublishedBy=$Pinned.SQLite.Sha3PublishedBy;WindowsBuild=$os.BuildNumber;Dotnet=$psInfo.Framework;Supported=$null;Actual=$null}
    if($null -eq $sha3Payload -or -not [bool]$sha3Payload.Success){
        Add-Result 'SQLITE_ARTIFACT_SHA3' 'WARN' 'SHA3-256 could not be computed (probe error). SHA-256 from the official Scoop bucket remains enforced.' $sha3Info $(if($null -ne $sha3Payload){[string]$sha3Payload.Error}else{$sha3Run.StdErr})
    }elseif(-not [bool]$sha3Payload.Supported){
        $sha3Info['Supported']=$false
        Add-Result 'SQLITE_ARTIFACT_SHA3' 'WARN' 'SHA3-256 is not supported by this OS/.NET combination, so it cannot be verified here. SHA-256 from the official Scoop bucket remains enforced; verify SHA3 on the download machine.' $sha3Info
    }else{
        $sha3=([string]$sha3Payload.Sha3_256).ToUpperInvariant()
        $sha3Info['Supported']=$true;$sha3Info['Actual']=$sha3
        $sha3Pass=($sha3 -eq $Pinned.SQLite.Sha3_256.ToUpperInvariant())
        Add-Result 'SQLITE_ARTIFACT_SHA3' $(if($sha3Pass){'PASS'}else{'FAIL'}) $(if($sha3Pass){'SQLite also matches official sqlite.org SHA3-256.'}else{'SQLite SHA3-256 mismatch. Aborting before artifact use.'}) $sha3Info
        if (-not $sha3Pass) { throw 'SQLite SHA3-256 mismatch.' }
    }

    # 2. Pode portable + loopback isolation
    $podeRoot=Join-Path $TempRoot 'pode'
    Expand-Archive -LiteralPath $podeZip -DestinationPath $podeRoot -Force
    $podeManifest=Get-ChildItem $podeRoot -Filter Pode.psd1 -File -Recurse | Select-Object -First 1 -ExpandProperty FullName
    if (-not $podeManifest) { throw 'Pode.psd1 not found.' }

    $podeProbe=Join-Path $TempRoot 'Probe-Pode.ps1'
    @'
param([string]$OutputPath,[string]$Manifest)
$ErrorActionPreference='Stop'
try{
    Import-Module -LiteralPath $Manifest -Force
    $m=Get-Module Pode
    [pscustomobject]@{Success=$true;Name=$m.Name;Version=$m.Version.ToString();Path=$m.Path}|ConvertTo-Json|Set-Content $OutputPath -Encoding utf8
}catch{
    [pscustomobject]@{Success=$false;Error=$_.Exception.GetType().FullName+': '+$_.Exception.Message}|ConvertTo-Json|Set-Content $OutputPath -Encoding utf8
    exit 1
}
'@ | Set-Content $podeProbe -Encoding UTF8
    $podeProbeOut=Join-Path $TempRoot 'pode-probe.json'
    $pr=Run-ChildJson $pwsh $podeProbe $podeProbeOut @('-Manifest',('"{0}"' -f $podeManifest))
    $podePass=($pr.ExitCode -eq 0 -and $null -ne $pr.Payload -and [bool]$pr.Payload.Success -and [string]$pr.Payload.Version -eq $Pinned.Pode.Version)
    Add-Result 'PODE_PORTABLE_IMPORT' $(if($podePass){'PASS'}else{'FAIL'}) 'Pode imported from extracted offline artifact.' $pr.Payload $pr.StdErr
    if (-not $podePass) { throw 'Pode portable import failed.' }

    $PodePortUsed=$(if($PodePort -gt 0){$PodePort}else{Free-Port})
    if (@(Listeners $PodePortUsed).Count -gt 0) { throw "Pode test port already in use: $PodePortUsed" }

    $server=Join-Path $TempRoot 'Start-PodeSpike.ps1'
    $serverText=@'
param([string]$Manifest)
$ErrorActionPreference='Stop'
Import-Module -LiteralPath $Manifest -Force
Start-PodeServer -ScriptBlock {
    Add-PodeEndpoint -Address '127.0.0.1' -Port __PORT__ -Protocol Http
    Add-PodeRoute -Method Get -Path '/health' -ScriptBlock {
        Write-PodeJsonResponse -Value @{status='ok';binding='127.0.0.1';phase='1A'}
    }
}
'@
    $serverText=$serverText.Replace('__PORT__',[string]$PodePortUsed)
    $serverText | Set-Content $server -Encoding UTF8
    $so=Join-Path $TempRoot 'pode.out.txt'
    $se=Join-Path $TempRoot 'pode.err.txt'
    $PodeProcess=Start-Process -FilePath $pwsh -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $server),'-Manifest',('"{0}"' -f $podeManifest)) -PassThru -RedirectStandardOutput $so -RedirectStandardError $se

    $ready=$false
    $deadline=(Get-Date).AddSeconds(20)
    do{
        if($PodeProcess.HasExited){break}
        try{
            $w=Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri ('http://127.0.0.1:{0}/health' -f $PodePortUsed)
            if($w.StatusCode -eq 200){$ready=$true;break}
        }catch{Start-Sleep -Milliseconds 250}
    }while((Get-Date)-lt $deadline)
    Add-Result 'PODE_LOOPBACK_POSITIVE' $(if($ready){'PASS'}else{'FAIL'}) 'Pode health route over 127.0.0.1.' ([ordered]@{Port=$PodePortUsed;Exited=$PodeProcess.HasExited}) $(if(Test-Path $se){Get-Content $se -Raw}else{$null})
    if(-not $ready){throw 'Pode did not become reachable on loopback.'}

    $ls=@(Listeners $PodePortUsed)
    $onlyLoopback=$true
    foreach($row in $ls){if([string]$row.LocalAddress -notin @('127.0.0.1','::1')){$onlyLoopback=$false}}
    Add-Result 'PODE_LISTENER_LOOPBACK_ONLY' $(if($ls.Count -gt 0 -and $onlyLoopback){'PASS'}else{'FAIL'}) 'Listener must exist only on loopback.' ([ordered]@{Port=$PodePortUsed;Listeners=$ls})

    $ips=@([Net.Dns]::GetHostAddresses($env:COMPUTERNAME)|Where-Object{$_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and -not [Net.IPAddress]::IsLoopback($_) -and $_.ToString() -notlike '169.254.*'}|ForEach-Object{$_.ToString()}|Sort-Object -Unique)
    if($ips.Count -eq 0){
        Add-Result 'PODE_NON_LOOPBACK_NEGATIVE' 'SKIP' 'No usable non-loopback IPv4 address exists on this machine.'
    }else{
        $attempts=@();$bad=@()
        foreach($ip in $ips){$ok=Tcp-Connect $ip $PodePortUsed;$attempts+=[pscustomobject]@{Address=$ip;Connected=$ok};if($ok){$bad+=$ip}}
        Add-Result 'PODE_NON_LOOPBACK_NEGATIVE' $(if($bad.Count -eq 0){'PASS'}else{'FAIL'}) 'Connection via the machine non-loopback IP must fail.' $attempts
    }

    # 3. SQLite no-install engine
    $sqliteRoot=Join-Path $TempRoot 'sqlite'
    Expand-Archive -LiteralPath $sqliteZip -DestinationPath $sqliteRoot -Force
    $sqlite=Get-ChildItem $sqliteRoot -Filter sqlite3.exe -File -Recurse | Select-Object -First 1 -ExpandProperty FullName
    if(-not $sqlite){throw 'sqlite3.exe not found.'}
    $sqliteVersion=((& $sqlite -version 2>&1|Out-String).Trim())
    $db=Join-Path $TempRoot 'phase1a.sqlite'
    $o1=@(& $sqlite $db "PRAGMA journal_mode=WAL; CREATE TABLE spike(id INTEGER PRIMARY KEY,value TEXT NOT NULL); BEGIN; INSERT INTO spike(value) VALUES('portable'); COMMIT; SELECT value FROM spike WHERE id=1;" 2>&1);$e1=$LASTEXITCODE
    $o2=@(& $sqlite $db "SELECT COUNT(*) || '|' || MIN(value) FROM spike;" 2>&1);$e2=$LASTEXITCODE
    $o3=@(& $sqlite $db "BEGIN; INSERT INTO spike(value) VALUES('rollback'); ROLLBACK; SELECT COUNT(*) FROM spike;" 2>&1);$e3=$LASTEXITCODE
    $journal=$(if($o1.Count){[string]$o1[0]}else{''});$value=$(if($o1.Count){[string]$o1[$o1.Count-1]}else{''});$reopen=$(if($o2.Count){[string]$o2[$o2.Count-1]}else{''});$rollback=$(if($o3.Count){[string]$o3[$o3.Count-1]}else{''})
    $sqlitePass=$sqliteVersion.StartsWith($Pinned.SQLite.Version,[StringComparison]::OrdinalIgnoreCase) -and $e1 -eq 0 -and $e2 -eq 0 -and $e3 -eq 0 -and $journal.Trim().ToLowerInvariant() -eq 'wal' -and $value.Trim() -eq 'portable' -and $reopen.Trim() -eq '1|portable' -and $rollback.Trim() -eq '1'
    Add-Result 'SQLITE_PORTABLE' $(if($sqlitePass){'PASS'}else{'FAIL'}) 'SQLite extracted ZIP: version/WAL/create/insert/reopen/rollback.' ([ordered]@{Version=$sqliteVersion;ExpectedVersion=$Pinned.SQLite.Version;JournalMode=$journal;Inserted=$value;Reopen=$reopen;RollbackCount=$rollback;ExitCodes=@($e1,$e2,$e3)})

    # 4. IIS WebAdministration and direct Microsoft.Web.Administration, read-only
    if(-not $IisPresent){
        foreach($id in @('IIS_WEBADMIN_NATIVE','IIS_WEBADMIN_COMPAT','IIS_MUTABLE_COMMAND_SURFACE_COMPAT','IIS_PROVIDER','IIS_ENUMERATION_PERFORMANCE','IIS_SERIALIZED_PROPERTIES','IIS_MICROSOFT_WEB_ADMINISTRATION')){Add-Result $id 'SKIP' 'IIS is not installed on this machine.'}
    }else{
        $iisScript=Join-Path $TempRoot 'Probe-IIS.ps1'
        @'
param([string]$OutputPath,[ValidateSet('Native','Compat')][string]$Mode)
$ErrorActionPreference='Stop'
function Desc($o){if($null -eq $o){return [pscustomobject]@{Present=$false;TypeNames=@();Properties=@()}};[pscustomobject]@{Present=$true;TypeNames=@($o.PSObject.TypeNames);Properties=@($o.PSObject.Properties.Name|Sort-Object -Unique)}}
$r=[ordered]@{Mode=$Mode;ImportSuccess=$false;UsedCompatSession=$false;Read=[ordered]@{};Mutable=[ordered]@{};ProviderAvailable=$false;ProviderError=$null;Counts=[ordered]@{};TimingsMs=[ordered]@{};Samples=[ordered]@{};Error=$null}
try{
    if($Mode -eq 'Compat'){Import-Module WebAdministration -UseWindowsPowerShell -Force -ErrorAction Stop}else{Import-Module WebAdministration -Force -ErrorAction Stop}
    $r.ImportSuccess=$true
    $r.UsedCompatSession=(@(Get-PSSession -ErrorAction SilentlyContinue|Where-Object Name -eq 'WinPSCompatSession').Count -gt 0)
    foreach($name in @('Get-Website','Get-WebApplication','Get-WebsiteState','Get-WebAppPoolState','Get-WebGlobalModule')){try{$cmd=Get-Command $name -ErrorAction Stop;$r.Read[$name]=[ordered]@{Present=$true;Module=$cmd.ModuleName;Parameters=@($cmd.Parameters.Keys|Sort-Object)}}catch{$r.Read[$name]=[ordered]@{Present=$false;Error=$_.Exception.Message}}}
    if($Mode -eq 'Compat'){
        $expected=[ordered]@{'Start-WebAppPool'=@('Name');'Stop-WebAppPool'=@('Name');'Restart-WebAppPool'=@('Name');'Start-Website'=@('Name');'Stop-Website'=@('Name');'New-Website'=@('Name','PhysicalPath');'New-WebApplication'=@('Name','Site','PhysicalPath');'Set-WebConfigurationProperty'=@('Filter','Name','Value')}
        foreach($x in $expected.GetEnumerator()){try{$cmd=Get-Command $x.Key -ErrorAction Stop;$pars=@($cmd.Parameters.Keys|Sort-Object);$missing=@($x.Value|Where-Object{$pars -notcontains $_});$r.Mutable[$x.Key]=[ordered]@{Present=$true;Parameters=$pars;Expected=@($x.Value);Missing=$missing;Pass=($missing.Count -eq 0);Executed=$false}}catch{$r.Mutable[$x.Key]=[ordered]@{Present=$false;Expected=@($x.Value);Missing=@($x.Value);Pass=$false;Executed=$false;Error=$_.Exception.Message}}}
    }
    $sw=[Diagnostics.Stopwatch]::StartNew();$sites=@(Get-Website -ErrorAction Stop);$sw.Stop();$r.TimingsMs.GetWebsiteAll=$sw.Elapsed.TotalMilliseconds;$r.Counts.Sites=$sites.Count;$r.Samples.Website=Desc($sites|Select-Object -First 1)
    $sw=[Diagnostics.Stopwatch]::StartNew();$apps=@(Get-WebApplication -ErrorAction Stop);$sw.Stop();$r.TimingsMs.GetWebApplicationAll=$sw.Elapsed.TotalMilliseconds;$r.Counts.Applications=$apps.Count;$r.Samples.WebApplication=Desc($apps|Select-Object -First 1)
    $mods=@(Get-WebGlobalModule -ErrorAction Stop);$r.Counts.GlobalModules=$mods.Count;$r.Samples.WebGlobalModule=Desc($mods|Select-Object -First 1)
    $siteStates=@();$sw=[Diagnostics.Stopwatch]::StartNew();foreach($s in $sites){$siteStates+=Get-WebsiteState -Name ([string]$s.Name) -ErrorAction Stop};$sw.Stop();$r.TimingsMs.GetWebsiteStateAll=$sw.Elapsed.TotalMilliseconds;$r.Samples.WebsiteState=Desc($siteStates|Select-Object -First 1)
    try{$null=Get-PSDrive IIS -ErrorAction Stop;$r.ProviderAvailable=$true;$sw=[Diagnostics.Stopwatch]::StartNew();$null=@(Get-ChildItem 'IIS:\Sites' -ErrorAction Stop);$sw.Stop();$r.TimingsMs.ProviderSitesAll=$sw.Elapsed.TotalMilliseconds;$sw=[Diagnostics.Stopwatch]::StartNew();$pools=@(Get-ChildItem 'IIS:\AppPools' -ErrorAction Stop);$sw.Stop();$r.TimingsMs.ProviderPoolsAll=$sw.Elapsed.TotalMilliseconds;$r.Counts.Pools=$pools.Count;$r.Samples.ProviderPool=Desc($pools|Select-Object -First 1);$poolStates=@();$sw=[Diagnostics.Stopwatch]::StartNew();foreach($p in $pools){$poolStates+=Get-WebAppPoolState -Name ([string]$p.Name) -ErrorAction Stop};$sw.Stop();$r.TimingsMs.GetWebAppPoolStateAll=$sw.Elapsed.TotalMilliseconds;$r.Samples.WebAppPoolState=Desc($poolStates|Select-Object -First 1)}catch{$r.ProviderError=$_.Exception.GetType().FullName+': '+$_.Exception.Message}
}catch{$r.Error=$_.Exception.GetType().FullName+': '+$_.Exception.Message}
$r|ConvertTo-Json -Depth 14|Set-Content $OutputPath -Encoding utf8
'@ | Set-Content $iisScript -Encoding UTF8

        $nativeOut=Join-Path $TempRoot 'iis-native.json';$compatOut=Join-Path $TempRoot 'iis-compat.json'
        $native=Run-ChildJson $pwsh $iisScript $nativeOut @('-Mode','Native');$compat=Run-ChildJson $pwsh $iisScript $compatOut @('-Mode','Compat')
        $n=$native.Payload;$c=$compat.Payload

        $nativePass=($null -ne $n -and [bool]$n.ImportSuccess -and $null -eq $n.Error)
        Add-Result 'IIS_WEBADMIN_NATIVE' $(if($nativePass){'PASS'}else{'FAIL'}) 'Default/native WebAdministration import and real reads under PowerShell 7.' $n $native.StdErr

        $compatPass=($null -ne $c -and [bool]$c.ImportSuccess -and [bool]$c.UsedCompatSession -and $null -eq $c.Error)
        Add-Result 'IIS_WEBADMIN_COMPAT' $(if($compatPass){'PASS'}else{'FAIL'}) 'Forced Windows PowerShell compatibility import and real reads.' $c $compat.StdErr

        $mutPass=$false
        if($null -ne $c){$mutPass=$true;foreach($p in $c.Mutable.PSObject.Properties){if(-not [bool]$p.Value.Pass -or [bool]$p.Value.Executed){$mutPass=$false}}}
        Add-Result 'IIS_MUTABLE_COMMAND_SURFACE_COMPAT' $(if($mutPass){'PASS'}else{'FAIL'}) 'Mutating commands checked only with Get-Command; expected parameters present; Executed=false.' $(if($null -ne $c){$c.Mutable}else{$null})

        $providerPass=(($null -ne $n -and [bool]$n.ProviderAvailable) -or ($null -ne $c -and [bool]$c.ProviderAvailable))
        Add-Result 'IIS_PROVIDER' $(if($providerPass){'PASS'}else{'FAIL'}) 'IIS:\ provider availability under PowerShell 7.' ([ordered]@{Native=$(if($null -ne $n){$n.ProviderAvailable}else{$false});NativeError=$(if($null -ne $n){$n.ProviderError}else{$null});Compat=$(if($null -ne $c){$c.ProviderAvailable}else{$false});CompatError=$(if($null -ne $c){$c.ProviderError}else{$null})})

        Add-Result 'IIS_ENUMERATION_PERFORMANCE' 'PASS' 'Captured timings/counts for all sites, applications, pools and state calls.' ([ordered]@{NativeTimings=$(if($null -ne $n){$n.TimingsMs}else{$null});NativeCounts=$(if($null -ne $n){$n.Counts}else{$null});CompatTimings=$(if($null -ne $c){$c.TimingsMs}else{$null});CompatCounts=$(if($null -ne $c){$c.Counts}else{$null})})
        Add-Result 'IIS_SERIALIZED_PROPERTIES' 'PASS' 'Captured type names and usable property names only, not site values.' ([ordered]@{Native=$(if($null -ne $n){$n.Samples}else{$null});Compat=$(if($null -ne $c){$c.Samples}else{$null})})

        $mwaScript=Join-Path $TempRoot 'Probe-MWA.ps1'
        @'
param([string]$OutputPath)
$ErrorActionPreference='Stop'
$m=$null
$r=[ordered]@{Success=$false;AssemblyPath=$null;AssemblyFullName=$null;SiteCount=$null;ApplicationCount=$null;PoolCount=$null;SitesMs=$null;ApplicationsMs=$null;PoolsMs=$null;Error=$null}
try{$dll=Join-Path $env:windir 'System32\inetsrv\Microsoft.Web.Administration.dll';$r.AssemblyPath=$dll;if(-not(Test-Path $dll)){throw "Assembly not found: $dll"};$a=[Reflection.Assembly]::LoadFrom($dll);$r.AssemblyFullName=$a.FullName;$m=[Microsoft.Web.Administration.ServerManager]::new();$sw=[Diagnostics.Stopwatch]::StartNew();$sites=@($m.Sites);$sw.Stop();$r.SitesMs=$sw.Elapsed.TotalMilliseconds;$r.SiteCount=$sites.Count;$sw=[Diagnostics.Stopwatch]::StartNew();$ac=0;foreach($s in $sites){$ac+=@($s.Applications).Count};$sw.Stop();$r.ApplicationsMs=$sw.Elapsed.TotalMilliseconds;$r.ApplicationCount=$ac;$sw=[Diagnostics.Stopwatch]::StartNew();$pools=@($m.ApplicationPools);$sw.Stop();$r.PoolsMs=$sw.Elapsed.TotalMilliseconds;$r.PoolCount=$pools.Count;$r.Success=$true}catch{$r.Error=$_.Exception.GetType().FullName+': '+$_.Exception.Message}finally{if($null -ne $m){$m.Dispose()}}
$r|ConvertTo-Json -Depth 8|Set-Content $OutputPath -Encoding utf8
if(-not $r.Success){exit 1}
'@ | Set-Content $mwaScript -Encoding UTF8
        $mwaOut=Join-Path $TempRoot 'mwa.json';$mwa=Run-ChildJson $pwsh $mwaScript $mwaOut
        $mwaPass=($mwa.ExitCode -eq 0 -and $null -ne $mwa.Payload -and [bool]$mwa.Payload.Success)
        Add-Result 'IIS_MICROSOFT_WEB_ADMINISTRATION' $(if($mwaPass){'PASS'}else{'FAIL'}) 'Direct Microsoft.Web.Administration.dll load and read-only site/app/pool enumeration.' $mwa.Payload $mwa.StdErr
    }
}
catch{
    $Fatal=Err $_
    Add-Result 'RUN_FATAL' 'FAIL' 'Spike stopped after a fatal prerequisite/integrity/runtime failure.' $null $Fatal
}
finally{
    if($null -ne $PodeProcess){try{if(-not $PodeProcess.HasExited){Stop-Process -Id $PodeProcess.Id -Force;$PodeProcess.WaitForExit(5000)}}catch{Add-Result 'CLEANUP_PODE_PROCESS' 'FAIL' 'Could not stop Pode child pwsh.' $null (Err $_)}}
    Start-Sleep -Milliseconds 750

    if($PodePortUsed -gt 0){$remain=@(Listeners $PodePortUsed);Add-Result 'CLEANUP_PORT' $(if($remain.Count -eq 0){'PASS'}else{'FAIL'}) 'No listener may remain on the Pode test port.' ([ordered]@{Port=$PodePortUsed;Remaining=$remain})}

    $after=@(Get-Process -Name pwsh,powershell -ErrorAction SilentlyContinue|Select-Object ProcessName,Id)
    $base=@{};foreach($p in $BaselineShells){$base[([string]$p.ProcessName+':'+[string]$p.Id)]=$true}
    $new=@($after|Where-Object{-not $base.ContainsKey(([string]$_.ProcessName+':'+[string]$_.Id))})
    Add-Result 'CLEANUP_SHELL_PROCESSES' $(if($new.Count -eq 0){'PASS'}else{'FAIL'}) 'No new pwsh/powershell process may remain after the spike.' ([ordered]@{Baseline=$BaselineShells;RemainingNew=$new})

    if($KeepArtifacts){
        Add-Result 'CLEANUP_TEMP_ROOT' 'PASS' 'Temporary directory intentionally retained because -KeepArtifacts was used.' ([ordered]@{TempRoot=$TempRoot;Kept=$true})
    }else{
        try{if(Test-Path $TempRoot){Remove-Item $TempRoot -Recurse -Force};Add-Result 'CLEANUP_TEMP_ROOT' $(if(-not(Test-Path $TempRoot)){'PASS'}else{'FAIL'}) 'Temporary directory removed.' ([ordered]@{TempRoot=$TempRoot;Kept=$false})}catch{Add-Result 'CLEANUP_TEMP_ROOT' 'FAIL' 'Could not remove temporary directory.' ([ordered]@{TempRoot=$TempRoot}) (Err $_)}
    }

    $critical=@('POWERSHELL_ARTIFACT','PODE_ARTIFACT','SQLITE_ARTIFACT','POWERSHELL_PORTABLE','SQLITE_ARTIFACT_SHA3','PODE_PORTABLE_IMPORT','PODE_LOOPBACK_POSITIVE','PODE_LISTENER_LOOPBACK_ONLY','PODE_NON_LOOPBACK_NEGATIVE','SQLITE_PORTABLE','CLEANUP_PORT','CLEANUP_SHELL_PROCESSES','CLEANUP_TEMP_ROOT')
    if($IisPresent){$critical+=@('IIS_WEBADMIN_COMPAT','IIS_MUTABLE_COMMAND_SURFACE_COMPAT','IIS_PROVIDER','IIS_MICROSOFT_WEB_ADMINISTRATION')}
    $fail=@($Results|Where-Object{$critical -contains $_.Id -and $_.Status -eq 'FAIL'})
    $overall='PASS'
    if($fail.Count -gt 0 -or $Fatal){$overall='FAIL'}elseif(-not $IisPresent){$overall='INCOMPLETE_IIS'}elseif(@($Results|Where-Object{$_.Id -eq 'PODE_NON_LOOPBACK_NEGATIVE' -and $_.Status -eq 'SKIP'}).Count -gt 0){$overall='INCOMPLETE_NETWORK'}

    $done=[DateTime]::UtcNow
    $report=[pscustomobject][ordered]@{
        Phase='1A'
        Name='Portable Runtime Compatibility'
        RunId=$RunId
        Machine=$env:COMPUTERNAME
        StartedAtUtc=$StartedUtc.ToString('o')
        CompletedAtUtc=$done.ToString('o')
        DurationSeconds=[math]::Round(($done-$StartedUtc).TotalSeconds,3)
        Overall=$overall
        IisInstalled=$IisPresent
        KeepArtifacts=[bool]$KeepArtifacts
        ArtifactRoot=[IO.Path]::GetFullPath($ArtifactRoot)
        ReportPath=[IO.Path]::GetFullPath($ReportPath)
        PinnedArtifacts=$Pinned
        Checks=@($Results)
        FatalError=$Fatal
        DecisionHint=$(switch($overall){'PASS'{'ADR-0001 Phase 1A runtime gate passed on this machine.';break};'INCOMPLETE_IIS'{'Repeat the same script on the IIS sandbox before closing Phase 1A.';break};'INCOMPLETE_NETWORK'{'Repeat on a machine with a non-loopback IPv4 address before closing Phase 1A.';break};default{'At least one architecture gate failed. Reopen ADR-0001 before continuing.'}})
    }
    $dir=Split-Path -Parent $ReportPath
    if($dir -and -not(Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    $json=$report|ConvertTo-Json -Depth 20
    $json|Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-Host ''
    Write-Host '========== SISQUALDeployConsole PHASE 1A REPORT =========='
    Write-Output $json
    Write-Host '========== END PHASE 1A REPORT =========='
    Write-Host ('Report saved to: '+$ReportPath)
}
