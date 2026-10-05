param(
    [Parameter(Mandatory = $true)]
    [string]$PodeModulePath,

    [Parameter(Mandatory = $true)]
    [int]$Port
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module -Name $PodeModulePath -Force -ErrorAction Stop

function ConvertTo-TokenHash {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) {
        return ''
    }

    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    try {
        return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
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

function Test-HashEqual {
    param([string]$Left, [string]$Right)

    if ([string]::IsNullOrEmpty($Left) -or [string]::IsNullOrEmpty($Right)) {
        return $false
    }

    $a = [Text.Encoding]::ASCII.GetBytes($Left)
    $b = [Text.Encoding]::ASCII.GetBytes($Right)
    try {
        return [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($a, $b)
    }
    finally {
        [Array]::Clear($a, 0, $a.Length)
        [Array]::Clear($b, 0, $b.Length)
    }
}

$bootstrapHash = [string]$env:SISQUAL_SPIKE_BOOTSTRAP_HASH
if ([string]::IsNullOrWhiteSpace($bootstrapHash)) {
    throw 'SISQUAL_SPIKE_BOOTSTRAP_HASH is required.'
}

$bootstrapLifetimeSeconds = 120
$sessionLifetimeSeconds = 900
if ($env:SISQUAL_SPIKE_BOOTSTRAP_SECONDS) {
    $bootstrapLifetimeSeconds = [int]$env:SISQUAL_SPIKE_BOOTSTRAP_SECONDS
}
if ($env:SISQUAL_SPIKE_SESSION_SECONDS) {
    $sessionLifetimeSeconds = [int]$env:SISQUAL_SPIKE_SESSION_SECONDS
}

$allowedHosts = @("127.0.0.1:$Port", "localhost:$Port")
$allowedOrigins = @("http://127.0.0.1:$Port", "http://localhost:$Port")

Start-PodeServer -Threads 1 -ScriptBlock {
    Add-PodeEndpoint -Address '127.0.0.1' -Port $Port -Protocol Http

    $security = [ordered]@{
        BootstrapHash       = $bootstrapHash
        BootstrapExpiresUtc = [DateTime]::UtcNow.AddSeconds($bootstrapLifetimeSeconds)
        BootstrapConsumed   = $false
        SessionHash         = ''
        CsrfHash            = ''
        SessionExpiresUtc   = [DateTime]::MinValue
        SessionSeconds      = $sessionLifetimeSeconds
        AllowedHosts        = $allowedHosts
        AllowedOrigins      = $allowedOrigins
        MutationCount       = 0
    }
    Set-PodeState -Name 'Phase1CSecurity' -Value $security | Out-Null

    Add-PodeMiddleware -Name 'SISQUALSecurityHeaders' -ScriptBlock {
        Add-PodeHeader -Name 'Cache-Control' -Value 'no-store'
        Add-PodeHeader -Name 'Pragma' -Value 'no-cache'
        Add-PodeHeader -Name 'Content-Security-Policy' -Value "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"
        Add-PodeHeader -Name 'X-Content-Type-Options' -Value 'nosniff'
        Add-PodeHeader -Name 'Referrer-Policy' -Value 'no-referrer'
        Add-PodeHeader -Name 'Permissions-Policy' -Value 'camera=(), microphone=(), geolocation=()'
        Add-PodeHeader -Name 'Cross-Origin-Opener-Policy' -Value 'same-origin'
        Add-PodeHeader -Name 'Cross-Origin-Resource-Policy' -Value 'same-origin'
        return $true
    }

    Add-PodeMiddleware -Name 'SISQUALHostGuard' -ScriptBlock {
        $state = Get-PodeState -Name 'Phase1CSecurity'
        $hostHeader = [string]$WebEvent.Request.Headers['Host']
        if ($state.AllowedHosts -notcontains $hostHeader) {
            Set-PodeResponseStatus -Code 400 -NoErrorPage
            return $false
        }

        return $true
    }

    Add-PodeRoute -Method Get -Path '/health' -ScriptBlock {
        Write-PodeJsonResponse -Value @{ status = 'ok'; binding = '127.0.0.1' }
    }

    Add-PodeRoute -Method Post -Path '/api/bootstrap' -ScriptBlock {
        $state = Get-PodeState -Name 'Phase1CSecurity'
        $origin = [string]$WebEvent.Request.Headers['Origin']
        if ($state.AllowedOrigins -notcontains $origin) {
            Set-PodeResponseStatus -Code 403 -NoErrorPage
            return
        }

        if ($state.BootstrapConsumed -or ([DateTime]::UtcNow -gt $state.BootstrapExpiresUtc)) {
            Set-PodeResponseStatus -Code 403 -NoErrorPage
            return
        }

        $presented = [string]$WebEvent.Request.Headers['X-SISQUAL-Bootstrap']
        $presentedHash = ConvertTo-TokenHash -Value $presented
        if (-not (Test-HashEqual -Left $presentedHash -Right $state.BootstrapHash)) {
            Set-PodeResponseStatus -Code 403 -NoErrorPage
            return
        }

        $sessionToken = New-RandomToken
        $csrfToken = New-RandomToken
        $state.SessionHash = ConvertTo-TokenHash -Value $sessionToken
        $state.CsrfHash = ConvertTo-TokenHash -Value $csrfToken
        $state.SessionExpiresUtc = [DateTime]::UtcNow.AddSeconds($state.SessionSeconds)
        $state.BootstrapConsumed = $true

        Write-PodeJsonResponse -Value @{ session = $sessionToken; csrf = $csrfToken }
    }

    Add-PodeRoute -Method Get -Path '/api/protected' -ScriptBlock {
        $state = Get-PodeState -Name 'Phase1CSecurity'
        $sessionToken = [string]$WebEvent.Request.Headers['X-SISQUAL-Session']
        $sessionHash = ConvertTo-TokenHash -Value $sessionToken
        if (([DateTime]::UtcNow -gt $state.SessionExpiresUtc) -or -not (Test-HashEqual -Left $sessionHash -Right $state.SessionHash)) {
            Set-PodeResponseStatus -Code 401 -NoErrorPage
            return
        }

        Write-PodeJsonResponse -Value @{ authenticated = $true }
    }

    Add-PodeRoute -Method Options -Path '/api/mutate' -ScriptBlock {
        Set-PodeResponseStatus -Code 403 -NoErrorPage
    }

    Add-PodeRoute -Method Post -Path '/api/mutate' -ScriptBlock {
        $state = Get-PodeState -Name 'Phase1CSecurity'
        $origin = [string]$WebEvent.Request.Headers['Origin']
        if ($state.AllowedOrigins -notcontains $origin) {
            Set-PodeResponseStatus -Code 403 -NoErrorPage
            return
        }

        $sessionToken = [string]$WebEvent.Request.Headers['X-SISQUAL-Session']
        $sessionHash = ConvertTo-TokenHash -Value $sessionToken
        if (([DateTime]::UtcNow -gt $state.SessionExpiresUtc) -or -not (Test-HashEqual -Left $sessionHash -Right $state.SessionHash)) {
            Set-PodeResponseStatus -Code 401 -NoErrorPage
            return
        }

        $csrfToken = [string]$WebEvent.Request.Headers['X-SISQUAL-CSRF']
        $csrfHash = ConvertTo-TokenHash -Value $csrfToken
        if (-not (Test-HashEqual -Left $csrfHash -Right $state.CsrfHash)) {
            Set-PodeResponseStatus -Code 403 -NoErrorPage
            return
        }

        $state.MutationCount = [int]$state.MutationCount + 1
        Write-PodeJsonResponse -Value @{ applied = $true; count = $state.MutationCount }
    }

    Add-PodeRoute -Method Post -Path '/api/logout' -ScriptBlock {
        $state = Get-PodeState -Name 'Phase1CSecurity'
        $origin = [string]$WebEvent.Request.Headers['Origin']
        if ($state.AllowedOrigins -notcontains $origin) {
            Set-PodeResponseStatus -Code 403 -NoErrorPage
            return
        }

        $sessionToken = [string]$WebEvent.Request.Headers['X-SISQUAL-Session']
        $sessionHash = ConvertTo-TokenHash -Value $sessionToken
        $csrfToken = [string]$WebEvent.Request.Headers['X-SISQUAL-CSRF']
        $csrfHash = ConvertTo-TokenHash -Value $csrfToken
        if (-not (Test-HashEqual -Left $sessionHash -Right $state.SessionHash) -or -not (Test-HashEqual -Left $csrfHash -Right $state.CsrfHash)) {
            Set-PodeResponseStatus -Code 403 -NoErrorPage
            return
        }

        $state.SessionHash = ''
        $state.CsrfHash = ''
        $state.SessionExpiresUtc = [DateTime]::MinValue
        Set-PodeResponseStatus -Code 204 -NoErrorPage
    }
}
