[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PodeModulePath,

    [string]$ReportPath = '',

    [int]$Port = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $ScriptDir 'local-web-security-report.json'
}

$ServerScript = Join-Path $ScriptDir 'LocalWebSecurityServer.ps1'
if (-not (Test-Path -LiteralPath $ServerScript -PathType Leaf)) {
    throw "Server probe script not found: $ServerScript"
}
if (-not (Test-Path -LiteralPath $PodeModulePath -PathType Leaf)) {
    throw "Pode module not found: $PodeModulePath"
}

$Results = [System.Collections.Generic.List[object]]::new()
$SecretsForLeakCheck = [System.Collections.Generic.List[string]]::new()
$CaptureErrors = [System.Collections.Generic.List[string]]::new()
$TempRoot = Join-Path $env:TEMP ('SISQUALDeployConsole-Phase1C-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

function Add-Check {
    param(
        [string]$Id,
        [bool]$Passed,
        [string]$Message,
        $Data = $null
    )

    $Results.Add([pscustomobject][ordered]@{
        Id = $Id
        Status = $(if ($Passed) { 'PASS' } else { 'FAIL' })
        Message = $Message
        Data = $Data
        TimestampUtc = [DateTime]::UtcNow.ToString('o')
    }) | Out-Null
}

function New-RandomToken {
    $bytes = [Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    try {
        return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function ConvertTo-TokenHash {
    param([string]$Value)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Get-FreePort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    }
    finally {
        $listener.Stop()
    }
}

function Test-TcpConnect {
    param([string]$Address, [int]$TargetPort, [int]$TimeoutMs = 1200)

    $client = [Net.Sockets.TcpClient]::new()
    try {
        $async = $client.BeginConnect($Address, $TargetPort, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }
        try {
            $client.EndConnect($async)
            return $client.Connected
        }
        catch {
            return $false
        }
    }
    finally {
        $client.Dispose()
    }
}

function New-HttpClient {
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $handler.UseCookies = $false
    $handler.UseProxy = $false
    $client = [Net.Http.HttpClient]::new($handler, $true)
    $client.Timeout = [TimeSpan]::FromSeconds(5)
    return $client
}

function Invoke-ProbeRequest {
    param(
        [Net.Http.HttpClient]$Client,
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers = @{}
    )

    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Uri)
    try {
        foreach ($name in $Headers.Keys) {
            if ($name -eq 'Host') {
                $request.Headers.Host = [string]$Headers[$name]
            }
            else {
                $null = $request.Headers.TryAddWithoutValidation([string]$name, [string]$Headers[$name])
            }
        }

        $response = $Client.Send($request)
        try {
            $headers = [ordered]@{}
            foreach ($header in $response.Headers) {
                $headers[$header.Key] = (@($header.Value) -join ', ')
            }
            foreach ($header in $response.Content.Headers) {
                $headers[$header.Key] = (@($header.Value) -join ', ')
            }

            return [pscustomobject]@{
                Status = [int]$response.StatusCode
                Headers = $headers
                Body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            }
        }
        finally {
            $response.Dispose()
        }
    }
    finally {
        $request.Dispose()
    }
}

function Start-ProbeServer {
    param(
        [string]$BootstrapToken,
        [int]$TargetPort,
        [string]$Suffix
    )

    $stdout = Join-Path $TempRoot ("server-$Suffix.stdout.txt")
    $stderr = Join-Path $TempRoot ("server-$Suffix.stderr.txt")
    $pwsh = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path -LiteralPath $pwsh -PathType Leaf)) {
        throw "Portable pwsh not found at $pwsh"
    }

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwsh
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.ArgumentList.Add('-NoLogo')
    $psi.ArgumentList.Add('-NoProfile')
    $psi.ArgumentList.Add('-NonInteractive')
    $psi.ArgumentList.Add('-File')
    $psi.ArgumentList.Add($ServerScript)
    $psi.ArgumentList.Add('-PodeModulePath')
    $psi.ArgumentList.Add($PodeModulePath)
    $psi.ArgumentList.Add('-Port')
    $psi.ArgumentList.Add([string]$TargetPort)
    $psi.Environment['SISQUAL_SPIKE_BOOTSTRAP_HASH'] = ConvertTo-TokenHash -Value $BootstrapToken
    $psi.Environment['SISQUAL_SPIKE_BOOTSTRAP_SECONDS'] = '120'
    $psi.Environment['SISQUAL_SPIKE_SESSION_SECONDS'] = '900'

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    if (-not $process.Start()) {
        throw 'Could not start the Pode probe server.'
    }

    return [pscustomobject]@{
        Process = $process
        StdoutPath = $stdout
        StderrPath = $stderr
    }
}

function Stop-ProbeServer {
    param($Server)

    if ($null -eq $Server -or $null -eq $Server.Process) {
        return
    }

    $process = $Server.Process
    try {
        if (-not $process.HasExited) {
            try {
                $process.Kill($true)
            }
            catch {
                $process.Kill()
            }
            $null = $process.WaitForExit(5000)
        }

        if (-not $process.HasExited) {
            $CaptureErrors.Add('Probe process did not exit before output capture.') | Out-Null
            return
        }

        try {
            $stdoutText = $process.StandardOutput.ReadToEnd()
            $stderrText = $process.StandardError.ReadToEnd()
            Set-Content -LiteralPath $Server.StdoutPath -Value $stdoutText -Encoding ascii -ErrorAction Stop
            Set-Content -LiteralPath $Server.StderrPath -Value $stderrText -Encoding ascii -ErrorAction Stop
        }
        catch {
            $CaptureErrors.Add(('Server output capture failed: ' + $_.Exception.GetType().FullName)) | Out-Null
        }
    }
    catch {
        $CaptureErrors.Add(('Server stop failed before complete output capture: ' + $_.Exception.GetType().FullName)) | Out-Null
    }
    finally {
        $process.Dispose()
    }
}

function Wait-ForServer {
    param([Net.Http.HttpClient]$Client, [string]$BaseUri, [int]$TimeoutSeconds = 20)

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $response = Invoke-ProbeRequest -Client $Client -Method 'GET' -Uri "$BaseUri/health"
            if ($response.Status -eq 200) {
                return $true
            }
        }
        catch {}
        Start-Sleep -Milliseconds 250
    }

    return $false
}

$client = New-HttpClient
$server = $null
$server2 = $null
$fatal = $null
$sessionToken = $null
$csrf = $null
$bootstrap1 = New-RandomToken
$SecretsForLeakCheck.Add($bootstrap1) | Out-Null

if ($Port -le 0) {
    $Port = Get-FreePort
}
$baseUri = "http://127.0.0.1:$Port"
$canonicalOrigin = $baseUri

try {
    $server = Start-ProbeServer -BootstrapToken $bootstrap1 -TargetPort $Port -Suffix 'first'
    $ready = Wait-ForServer -Client $client -BaseUri $baseUri
    Add-Check 'SERVER_READY' $ready 'Pode server became reachable on the canonical loopback URL.' @{ Port = $Port }
    if (-not $ready) { throw 'Probe server did not become ready.' }

    $nonLoopback = [Net.Dns]::GetHostAddresses($env:COMPUTERNAME) |
        Where-Object { $_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and -not [Net.IPAddress]::IsLoopback($_) } |
        Select-Object -First 1
    if ($null -ne $nonLoopback) {
        $remoteReachable = Test-TcpConnect -Address $nonLoopback.IPAddressToString -TargetPort $Port
        Add-Check 'LOOPBACK_ONLY' (-not $remoteReachable) 'The Pode endpoint is not reachable through the host non-loopback IPv4 address.' @{ Address = $nonLoopback.IPAddressToString }
    }
    else {
        Add-Check 'LOOPBACK_ONLY' $true 'No non-loopback IPv4 address was available; endpoint binding remains explicitly 127.0.0.1.' @{ Address = $null }
    }

    $unauth = Invoke-ProbeRequest -Client $client -Method 'GET' -Uri "$baseUri/api/protected"
    Add-Check 'SESSION_REQUIRED' ($unauth.Status -eq 401) 'Protected route rejects a request without an explicit session header.' @{ Status = $unauth.Status }

    $forgedHost = Invoke-ProbeRequest -Client $client -Method 'GET' -Uri "$baseUri/health" -Headers @{ Host = "evil.example:$Port" }
    Add-Check 'HOST_REJECTED' ($forgedHost.Status -eq 400) 'Unexpected Host header is rejected.' @{ Status = $forgedHost.Status }

    $bootstrap = Invoke-ProbeRequest -Client $client -Method 'POST' -Uri "$baseUri/api/bootstrap" -Headers @{
        Origin = $canonicalOrigin
        'X-SISQUAL-Bootstrap' = $bootstrap1
    }
    $bootstrapJson = $bootstrap.Body | ConvertFrom-Json
    $sessionToken = [string]$bootstrapJson.session
    $csrf = [string]$bootstrapJson.csrf
    $SecretsForLeakCheck.Add($sessionToken) | Out-Null
    $SecretsForLeakCheck.Add($csrf) | Out-Null
    $hasSessionCookie = $bootstrap.Headers.Contains('Set-Cookie')
    Add-Check 'BOOTSTRAP_ACCEPTED' ($bootstrap.Status -eq 200 -and -not [string]::IsNullOrWhiteSpace($sessionToken) -and -not [string]::IsNullOrWhiteSpace($csrf)) 'One-time bootstrap returns explicit in-memory session and CSRF credentials.' @{ Status = $bootstrap.Status }
    Add-Check 'NO_SESSION_COOKIE' (-not $hasSessionCookie) 'Bootstrap does not create an ambient browser cookie that can cross loopback ports.' @{ SetCookiePresent = $hasSessionCookie }

    $replay = Invoke-ProbeRequest -Client $client -Method 'POST' -Uri "$baseUri/api/bootstrap" -Headers @{
        Origin = $canonicalOrigin
        'X-SISQUAL-Bootstrap' = $bootstrap1
    }
    Add-Check 'BOOTSTRAP_SINGLE_USE' ($replay.Status -eq 403) 'Consumed bootstrap token cannot be replayed.' @{ Status = $replay.Status }

    $wrongSession = Invoke-ProbeRequest -Client $client -Method 'GET' -Uri "$baseUri/api/protected" -Headers @{
        'X-SISQUAL-Session' = (New-RandomToken)
    }
    Add-Check 'WRONG_SESSION_REJECTED' ($wrongSession.Status -eq 401) 'An incorrect explicit session credential is rejected.' @{ Status = $wrongSession.Status }

    $validRead = Invoke-ProbeRequest -Client $client -Method 'GET' -Uri "$baseUri/api/protected" -Headers @{
        'X-SISQUAL-Session' = $sessionToken
    }
    Add-Check 'SESSION_ACCEPTED' ($validRead.Status -eq 200) 'Valid explicit session header reaches a protected route.' @{ Status = $validRead.Status }

    $foreignOrigin = Invoke-ProbeRequest -Client $client -Method 'POST' -Uri "$baseUri/api/mutate" -Headers @{
        'X-SISQUAL-Session' = $sessionToken
        Origin = 'https://attacker.invalid'
        'X-SISQUAL-CSRF' = $csrf
    }
    Add-Check 'ORIGIN_REJECTED' ($foreignOrigin.Status -eq 403) 'State-changing request from a foreign Origin is rejected.' @{ Status = $foreignOrigin.Status }

    $missingCsrf = Invoke-ProbeRequest -Client $client -Method 'POST' -Uri "$baseUri/api/mutate" -Headers @{
        'X-SISQUAL-Session' = $sessionToken
        Origin = $canonicalOrigin
    }
    Add-Check 'CSRF_REQUIRED' ($missingCsrf.Status -eq 403) 'State-changing request without CSRF token is rejected.' @{ Status = $missingCsrf.Status }

    $wrongCsrf = Invoke-ProbeRequest -Client $client -Method 'POST' -Uri "$baseUri/api/mutate" -Headers @{
        'X-SISQUAL-Session' = $sessionToken
        Origin = $canonicalOrigin
        'X-SISQUAL-CSRF' = (New-RandomToken)
    }
    Add-Check 'CSRF_WRONG_REJECTED' ($wrongCsrf.Status -eq 403) 'Wrong CSRF token is rejected.' @{ Status = $wrongCsrf.Status }

    $validMutation = Invoke-ProbeRequest -Client $client -Method 'POST' -Uri "$baseUri/api/mutate" -Headers @{
        'X-SISQUAL-Session' = $sessionToken
        Origin = $canonicalOrigin
        'X-SISQUAL-CSRF' = $csrf
    }
    Add-Check 'MUTATION_ACCEPTED' ($validMutation.Status -eq 200) 'Valid same-origin explicit session plus CSRF token reaches the mutation route.' @{ Status = $validMutation.Status }

    $preflight = Invoke-ProbeRequest -Client $client -Method 'OPTIONS' -Uri "$baseUri/api/mutate" -Headers @{
        Origin = 'https://attacker.invalid'
        'Access-Control-Request-Method' = 'POST'
        'Access-Control-Request-Headers' = 'X-SISQUAL-Session, X-SISQUAL-CSRF'
    }
    $hasAcao = $preflight.Headers.Contains('Access-Control-Allow-Origin')
    Add-Check 'CORS_PREFLIGHT_DENIED' ($preflight.Status -eq 403 -and -not $hasAcao) 'Foreign CORS preflight is denied and no Access-Control-Allow-Origin header is emitted.' @{ Status = $preflight.Status; AccessControlAllowOriginPresent = $hasAcao }

    $requiredHeaders = [ordered]@{
        'Content-Security-Policy' = "frame-ancestors 'none'"
        'X-Content-Type-Options' = 'nosniff'
        'Referrer-Policy' = 'no-referrer'
        'Cache-Control' = 'no-store'
        'Cross-Origin-Opener-Policy' = 'same-origin'
        'Cross-Origin-Resource-Policy' = 'same-origin'
    }
    foreach ($headerName in $requiredHeaders.Keys) {
        $value = [string]$validRead.Headers[$headerName]
        $expectedFragment = [string]$requiredHeaders[$headerName]
        Add-Check ("HEADER_" + ($headerName -replace '[^A-Za-z0-9]', '_').ToUpperInvariant()) ($value -like "*$expectedFragment*") "Security header $headerName contains the required value." @{ Header = $headerName; Value = $value }
    }

    Stop-ProbeServer -Server $server
    $server = $null
    Start-Sleep -Milliseconds 400
    Add-Check 'SERVER_STOPPED' (-not (Test-TcpConnect -Address '127.0.0.1' -TargetPort $Port)) 'Stopping the process removes the loopback listener.' @{ Port = $Port }

    $bootstrap2 = New-RandomToken
    $SecretsForLeakCheck.Add($bootstrap2) | Out-Null
    $server2 = Start-ProbeServer -BootstrapToken $bootstrap2 -TargetPort $Port -Suffix 'second'
    $ready2 = Wait-ForServer -Client $client -BaseUri $baseUri
    Add-Check 'SERVER_RESTARTED' $ready2 'A fresh process starts on the same loopback endpoint.' @{ Port = $Port }
    if (-not $ready2) { throw 'Restarted probe server did not become ready.' }

    $oldSessionAfterRestart = Invoke-ProbeRequest -Client $client -Method 'GET' -Uri "$baseUri/api/protected" -Headers @{
        'X-SISQUAL-Session' = $sessionToken
    }
    Add-Check 'SESSION_INVALID_AFTER_RESTART' ($oldSessionAfterRestart.Status -eq 401) 'In-memory session from the previous process is invalid after restart.' @{ Status = $oldSessionAfterRestart.Status }

    $bootstrapAgain = Invoke-ProbeRequest -Client $client -Method 'POST' -Uri "$baseUri/api/bootstrap" -Headers @{
        Origin = $canonicalOrigin
        'X-SISQUAL-Bootstrap' = $bootstrap2
    }
    $bootstrapAgainJson = $bootstrapAgain.Body | ConvertFrom-Json
    $sessionToken2 = [string]$bootstrapAgainJson.session
    $csrf2 = [string]$bootstrapAgainJson.csrf
    $SecretsForLeakCheck.Add($sessionToken2) | Out-Null
    $SecretsForLeakCheck.Add($csrf2) | Out-Null

    $logout = Invoke-ProbeRequest -Client $client -Method 'POST' -Uri "$baseUri/api/logout" -Headers @{
        'X-SISQUAL-Session' = $sessionToken2
        Origin = $canonicalOrigin
        'X-SISQUAL-CSRF' = $csrf2
    }
    Add-Check 'LOGOUT_INVALIDATES' ($logout.Status -eq 204) 'Logout clears the in-memory session.' @{ Status = $logout.Status }

    $afterLogout = Invoke-ProbeRequest -Client $client -Method 'GET' -Uri "$baseUri/api/protected" -Headers @{
        'X-SISQUAL-Session' = $sessionToken2
    }
    Add-Check 'SESSION_INVALID_AFTER_LOGOUT' ($afterLogout.Status -eq 401) 'Logged-out session cannot be reused.' @{ Status = $afterLogout.Status }
}
catch {
    $fatal = $_.Exception.GetType().FullName + ': ' + $_.Exception.Message
}
finally {
    Stop-ProbeServer -Server $server
    Stop-ProbeServer -Server $server2
    $client.Dispose()

    $logText = ''
    $captureFiles = @(Get-ChildItem -LiteralPath $TempRoot -Filter 'server-*.txt' -File -ErrorAction SilentlyContinue)
    if ($captureFiles.Count -ne 4) {
        $CaptureErrors.Add(('Expected 4 server output files but found ' + $captureFiles.Count + '.')) | Out-Null
    }

    foreach ($file in $captureFiles) {
        try {
            $logText += (Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop)
        }
        catch {
            $CaptureErrors.Add(('Could not read captured server output: ' + $_.Exception.GetType().FullName)) | Out-Null
        }
    }

    $captureComplete = ($CaptureErrors.Count -eq 0)
    Add-Check 'OUTPUT_CAPTURE_COMPLETE' $captureComplete 'All stdout/stderr streams from both probe server processes were captured and readable.' @{ ErrorCount = $CaptureErrors.Count; FileCount = $captureFiles.Count }

    $leaked = $false
    if ($captureComplete) {
        foreach ($secret in $SecretsForLeakCheck) {
            if (-not [string]::IsNullOrEmpty($secret) -and $logText.Contains($secret, [StringComparison]::Ordinal)) {
                $leaked = $true
                break
            }
        }
    }
    Add-Check 'NO_TOKEN_LOG_LEAK' ($captureComplete -and -not $leaked) 'Bootstrap, session and CSRF token values are absent from completely captured server stdout/stderr.' $null

    $failed = @($Results | Where-Object Status -eq 'FAIL')
    $report = [pscustomobject][ordered]@{
        Schema = 'SISQUAL_PHASE1C_LOCAL_WEB_SECURITY_V2'
        StartedOn = $env:COMPUTERNAME
        PowerShell = $PSVersionTable.PSVersion.ToString()
        PodeModule = $PodeModulePath
        Port = $Port
        Fatal = $fatal
        PassCount = @($Results | Where-Object Status -eq 'PASS').Count
        FailCount = $failed.Count
        Checks = @($Results)
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding ascii

    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($fatal) {
    Write-Error $fatal
    exit 1
}
if (@($Results | Where-Object Status -eq 'FAIL').Count -gt 0) {
    Write-Error 'One or more Phase 1C local-web-security checks failed.'
    exit 2
}

Write-Host 'Phase 1C local web security spike: PASS'
exit 0
