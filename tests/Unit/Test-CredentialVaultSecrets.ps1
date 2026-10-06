#requires -Version 7.0
<#
.SYNOPSIS
    Unit tests for the secrets model of tools/lib/Sisqual.CredentialVault.psm1 (step B6.3a).

.DESCRIPTION
    No network, no database. Everything happens in a temporary folder removed at the end. The KDF iteration count
    is lowered to 1000 for speed (the default of 600000 is checked in Test-CredentialVault.ps1), and the limits of
    the secrets and of the access log are lowered through the module scope to test them. Marker values stand in
    for secrets. Exits 1 on any failure.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sharedPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'modules' 'Sisqual.Credentials' 'Sisqual.Credentials.psm1')).Path
$vaultPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'lib' 'Sisqual.CredentialVault.psm1')).Path
Import-Module $sharedPath -Force
Import-Module $vaultPath -Force
$vm = Get-Module Sisqual.CredentialVault
& $vm { $script:MinIterations = 1000; $script:DefaultIterations = 1000 }

$script:Failures = 0
$script:Passed = 0
function Assert-That { param([string]$Name, [bool]$Condition) if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) } else { $script:Failures++; Write-Host ('FAIL  {0}' -f $Name) } }
function Assert-Throws {
    param([string]$Name, [scriptblock]$Block, [string]$Like = '*')
    $threw = $false; $message = ''
    try { & $Block } catch { $threw = $true; $message = $_.Exception.Message }
    Assert-That $Name ($threw -and ($message -like $Like))
}
function New-Pass { param([string]$Text) return (ConvertTo-SecureString -String $Text -AsPlainText -Force) }
function Get-Text { param([byte[]]$Bytes) return [System.Text.Encoding]::UTF8.GetString($Bytes) }
function Get-Bytes { param([string]$Text) return , [System.Text.Encoding]::UTF8.GetBytes($Text) }

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('sisqual-secrets-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$pass = 'correct horse battery staple 42'
$marker = 'MARKER-SECRET-VALUE-7d41-not-a-real-secret'
try {
    # -----------------------------------------------------------------------
    # A. The derived reference
    # -----------------------------------------------------------------------
    Assert-That 'ref: derived as KIND.CODE' ((Get-CredentialRef -Kind 'IIS_IDENTITY' -Code 'PTCOM1') -ceq 'IIS_IDENTITY.PTCOM1')
    foreach ($k in @('IIS_IDENTITY', 'WEB_ACCESS', 'MOBILE_APP_TOKEN', 'RULE_SECRET')) { Assert-That ('ref: kind ' + $k + ' is accepted') ((Get-CredentialRef -Kind $k -Code 'A_B-1') -ceq ($k + '.A_B-1')) }
    Assert-Throws 'ref: an unknown kind is SECRET_KIND' { Get-CredentialRef -Kind 'PASSWORD' -Code 'X' } 'SECRET_KIND'
    Assert-Throws 'ref: a kind in lower case is SECRET_KIND (case sensitive)' { Get-CredentialRef -Kind 'iis_identity' -Code 'X' } 'SECRET_KIND'
    Assert-Throws 'ref: a code in lower case is SECRET_CODE' { Get-CredentialRef -Kind 'WEB_ACCESS' -Code 'ptcom1' } 'SECRET_CODE'
    Assert-Throws 'ref: a code with a dot is SECRET_CODE (the reference stays unambiguous)' { Get-CredentialRef -Kind 'WEB_ACCESS' -Code 'A.B' } 'SECRET_CODE'
    Assert-Throws 'ref: a 61-character code is SECRET_CODE' { Get-CredentialRef -Kind 'WEB_ACCESS' -Code ('A' * 61) } 'SECRET_CODE'
    Assert-That 'ref: a 60-character code is accepted' ((Get-CredentialRef -Kind 'WEB_ACCESS' -Code ('A' * 60)).Length -eq 71)
    Assert-Throws 'ref: an empty code is refused' { Get-CredentialRef -Kind 'WEB_ACCESS' -Code '' }

    # -----------------------------------------------------------------------
    # B. Add and list
    # -----------------------------------------------------------------------
    $path = Join-Path $root 'v1' 'vault.sisqual'
    $v = New-CredentialVault -Path $path -Passphrase (New-Pass $pass)
    $streams = @(Add-VaultSecret -Vault $v -Kind 'WEB_ACCESS' -Code 'PTCOM2' -Value (Get-Bytes $marker) -Source 'sec.ManagedCredential#12' *>&1)
    Assert-That 'add: returns one object (reference and fingerprint) and writes nothing to any stream' ($streams.Count -eq 1 -and $streams[0].CredentialRef -ceq 'WEB_ACCESS.PTCOM2' -and $streams[0].Fingerprint -cmatch '^[0-9a-f]{64}$')
    [void](Add-VaultSecret -Vault $v -Kind 'IIS_IDENTITY' -Code 'PTCOM2' -Value (Get-Bytes 'iis-one'))
    [void](Add-VaultSecret -Vault $v -Kind 'RULE_SECRET' -Code 'MOBILE_APP_ACCESS_TOKEN' -Value (Get-Bytes 'rule-one'))
    [void](Add-VaultSecret -Vault $v -Kind 'MOBILE_APP_TOKEN' -Code 'PTCOM1' -Value (Get-Bytes 'mobile-one'))
    [void](Add-VaultSecret -Vault $v -Kind 'IIS_IDENTITY' -Code 'PTCOM1' -Value (Get-Bytes 'iis-two'))
    $list = Get-VaultSecretList -Vault $v
    Assert-That 'list: five entries sorted by reference (ordinal)' (($list.CredentialRef -join ',') -ceq 'IIS_IDENTITY.PTCOM1,IIS_IDENTITY.PTCOM2,MOBILE_APP_TOKEN.PTCOM1,RULE_SECRET.MOBILE_APP_ACCESS_TOKEN,WEB_ACCESS.PTCOM2')
    Assert-That 'list: metadata only - no property carries a value' ((($list[0].PSObject.Properties.Name) -join ',') -ceq 'CredentialRef,Kind,Code,ImportedAt,Source,Fingerprint' -and (($list | Out-String) -cnotlike '*MARKER*'))
    Assert-That 'list: the source and the time are kept' (($list | Where-Object CredentialRef -ceq 'WEB_ACCESS.PTCOM2').Source -ceq 'sec.ManagedCredential#12' -and ($list[0].ImportedAt -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'))
    Assert-That 'list: every fingerprint is 64 lower-case hex and they differ' ((@($list | Where-Object { $_.Fingerprint -cmatch '^[0-9a-f]{64}$' }).Count -eq 5) -and (@($list.Fingerprint | Sort-Object -Unique).Count -eq 5))

    # -----------------------------------------------------------------------
    # C. Values
    # -----------------------------------------------------------------------
    Assert-That 'get: the value round trips' ((Get-Text (Get-VaultSecretValue -Vault $v -CredentialRef 'WEB_ACCESS.PTCOM2')) -ceq $marker)
    $uni = 'p' + [char]0x00E9 + 'ss ' + [char]0x4E2D + [char]0x6587 + ' "q" \ / ' + [char]::ConvertFromUtf32(0x1F600)
    [void](Add-VaultSecret -Vault $v -Kind 'WEB_ACCESS' -Code 'UNI' -Value (Get-Bytes $uni))
    Assert-That 'get: a non-ASCII value round trips (UTF-8 bytes)' ((Get-Text (Get-VaultSecretValue -Vault $v -CredentialRef 'WEB_ACCESS.UNI')) -ceq $uni)
    [byte[]]$all = 0..255 | ForEach-Object { [byte]$_ }
    [void](Add-VaultSecret -Vault $v -Kind 'WEB_ACCESS' -Code 'BIN' -Value $all)
    Assert-That 'get: all 256 byte values round trip' ([Convert]::ToHexString((Get-VaultSecretValue -Vault $v -CredentialRef 'WEB_ACCESS.BIN')) -ceq [Convert]::ToHexString($all))
    [byte[]]$max = [byte[]]::new(8192); [System.Security.Cryptography.RandomNumberGenerator]::Fill($max)
    [void](Add-VaultSecret -Vault $v -Kind 'WEB_ACCESS' -Code 'MAX' -Value $max)
    Assert-That 'get: an 8192-byte value round trips' ([Convert]::ToHexString((Get-VaultSecretValue -Vault $v -CredentialRef 'WEB_ACCESS.MAX')) -ceq [Convert]::ToHexString($max))
    Assert-Throws 'add: an empty value is SECRET_VALUE' { Add-VaultSecret -Vault $v -Kind 'WEB_ACCESS' -Code 'EMPTY' -Value ([byte[]]@()) } 'SECRET_VALUE'
    Assert-Throws 'add: an 8193-byte value is SECRET_VALUE' { Add-VaultSecret -Vault $v -Kind 'WEB_ACCESS' -Code 'BIG' -Value ([byte[]]::new(8193)) } 'SECRET_VALUE'
    Assert-Throws 'add: a source with a line break is SECRET_SOURCE' { Add-VaultSecret -Vault $v -Kind 'WEB_ACCESS' -Code 'SRC1' -Value (Get-Bytes 'x') -Source "a`nb" } 'SECRET_SOURCE'
    Assert-Throws 'add: a non-ASCII source is SECRET_SOURCE' { Add-VaultSecret -Vault $v -Kind 'WEB_ACCESS' -Code 'SRC2' -Value (Get-Bytes 'x') -Source ('caf' + [char]0x00E9) } 'SECRET_SOURCE'
    Assert-Throws 'add: a 101-character source is SECRET_SOURCE' { Add-VaultSecret -Vault $v -Kind 'WEB_ACCESS' -Code 'SRC3' -Value (Get-Bytes 'x') -Source ('s' * 101) } 'SECRET_SOURCE'
    Assert-That 'add: a refused add leaves the vault unchanged' (@(Get-VaultSecretList -Vault $v | Where-Object Code -in @('EMPTY', 'BIG', 'SRC1', 'SRC2', 'SRC3')).Count -eq 0)
    $copy = Get-VaultSecretValue -Vault $v -CredentialRef 'WEB_ACCESS.PTCOM2'
    [Array]::Clear($copy, 0, $copy.Length)
    Assert-That 'get: the returned array is a copy (clearing it leaves the vault intact)' ((Get-Text (Get-VaultSecretValue -Vault $v -CredentialRef 'WEB_ACCESS.PTCOM2')) -ceq $marker)
    Assert-Throws 'get: an unknown reference is SECRET_MISSING' { Get-VaultSecretValue -Vault $v -CredentialRef 'WEB_ACCESS.NOPE' } 'SECRET_MISSING'
    Assert-Throws 'get: a malformed reference is SECRET_MISSING' { Get-VaultSecretValue -Vault $v -CredentialRef "x`ny" } 'SECRET_MISSING'

    # -----------------------------------------------------------------------
    # D. Duplicates and -Replace
    # -----------------------------------------------------------------------
    $fpBefore = ($list | Where-Object CredentialRef -ceq 'WEB_ACCESS.PTCOM2').Fingerprint
    Assert-Throws 'add: an existing reference is SECRET_EXISTS' { Add-VaultSecret -Vault $v -Kind 'WEB_ACCESS' -Code 'PTCOM2' -Value (Get-Bytes 'other') } 'SECRET_EXISTS'
    Assert-That 'add: the refused duplicate did not change the stored value' ((Get-Text (Get-VaultSecretValue -Vault $v -CredentialRef 'WEB_ACCESS.PTCOM2')) -ceq $marker)
    [void](Add-VaultSecret -Vault $v -Kind 'WEB_ACCESS' -Code 'PTCOM2' -Value (Get-Bytes 'replaced') -Replace)
    $fpAfter = (Get-VaultSecretList -Vault $v | Where-Object CredentialRef -ceq 'WEB_ACCESS.PTCOM2').Fingerprint
    Assert-That '-Replace: the value and its fingerprint change, and there is still one entry for the reference' ((Get-Text (Get-VaultSecretValue -Vault $v -CredentialRef 'WEB_ACCESS.PTCOM2')) -ceq 'replaced' -and $fpAfter -cne $fpBefore -and @(Get-VaultSecretList -Vault $v | Where-Object CredentialRef -ceq 'WEB_ACCESS.PTCOM2').Count -eq 1)
    [void](Add-VaultSecret -Vault $v -Kind 'WEB_ACCESS' -Code 'PTCOM2' -Value (Get-Bytes $marker) -Replace)

    # -----------------------------------------------------------------------
    # E. Salted fingerprint
    # -----------------------------------------------------------------------
    Assert-That 'fingerprint: the right value matches' (Test-VaultSecretFingerprint -Vault $v -CredentialRef 'WEB_ACCESS.PTCOM2' -Value (Get-Bytes $marker))
    Assert-That 'fingerprint: another value does not match' (-not (Test-VaultSecretFingerprint -Vault $v -CredentialRef 'WEB_ACCESS.PTCOM2' -Value (Get-Bytes ($marker + 'x'))))
    [byte[]]$flip = Get-Bytes $marker; $flip[3] = $flip[3] -bxor 1
    Assert-That 'fingerprint: one flipped bit does not match' (-not (Test-VaultSecretFingerprint -Vault $v -CredentialRef 'WEB_ACCESS.PTCOM2' -Value $flip))
    Assert-Throws 'fingerprint: an unknown reference is SECRET_MISSING' { Test-VaultSecretFingerprint -Vault $v -CredentialRef 'WEB_ACCESS.NOPE' -Value (Get-Bytes 'x') } 'SECRET_MISSING'
    $v2 = New-CredentialVault -Path (Join-Path $root 'v2' 'vault.sisqual') -Passphrase (New-Pass $pass)
    $r2 = Add-VaultSecret -Vault $v2 -Kind 'WEB_ACCESS' -Code 'PTCOM2' -Value (Get-Bytes $marker)
    Assert-That 'fingerprint: the same value in another vault has another fingerprint (the salt is per vault)' ($r2.Fingerprint -cne (Get-VaultSecretList -Vault $v | Where-Object CredentialRef -ceq 'WEB_ACCESS.PTCOM2').Fingerprint)
    Assert-That 'fingerprint: it is SHA-256 of the vault salt followed by the value' ((Get-VaultSecretList -Vault $v | Where-Object CredentialRef -ceq 'WEB_ACCESS.PTCOM2').Fingerprint -ceq ([Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([byte[]]([Convert]::FromBase64String($v.Data['fingerprintSalt']) + (Get-Bytes $marker)))).ToLowerInvariant()))
    Close-CredentialVault -Vault $v2

    # -----------------------------------------------------------------------
    # F. Persistence and what the file shows
    # -----------------------------------------------------------------------
    Save-CredentialVault -Vault $v
    $revision = $v.Revision
    $fileText = [IO.File]::ReadAllText($path)
    Assert-That 'file: neither the marker (plain, base64, hex) nor any reference appears in clear' (($fileText -cnotlike '*MARKER*') -and ($fileText -cnotlike ('*' + [Convert]::ToBase64String((Get-Bytes $marker)) + '*')) -and ($fileText -cnotlike ('*' + [Convert]::ToHexString((Get-Bytes $marker)) + '*')) -and ($fileText -cnotlike '*WEB_ACCESS.PTCOM2*') -and ($fileText -cnotlike '*PTCOM*'))
    Close-CredentialVault -Vault $v
    $r = Open-CredentialVault -Path $path -Passphrase (New-Pass $pass)
    Assert-That 'reopen: every entry, value and fingerprint survived and the revision matches the save' ((@(Get-VaultSecretList -Vault $r).Count -eq 8) -and (Get-Text (Get-VaultSecretValue -Vault $r -CredentialRef 'WEB_ACCESS.PTCOM2')) -ceq $marker -and (Test-VaultSecretFingerprint -Vault $r -CredentialRef 'WEB_ACCESS.PTCOM2' -Value (Get-Bytes $marker)) -and $r.Revision -eq $revision)
    Assert-That 'reopen: the access log survived and holds references and actions only' ((@(Get-VaultAccessLog -Vault $r).Count -ge 9) -and ((Get-VaultAccessLog -Vault $r | Out-String) -cnotlike '*MARKER*'))

    # -----------------------------------------------------------------------
    # G. Access log
    # -----------------------------------------------------------------------
    $log0 = @(Get-VaultAccessLog -Vault $r).Count
    [void](Get-VaultSecretValue -Vault $r -CredentialRef 'IIS_IDENTITY.PTCOM1')
    $log1 = @(Get-VaultAccessLog -Vault $r)
    Assert-That 'log: a read is recorded with the reference and no value' ($log1.Count -eq $log0 + 1 -and $log1[-1].Action -ceq 'READ' -and $log1[-1].CredentialRef -ceq 'IIS_IDENTITY.PTCOM1' -and $log1[-1].At -cmatch '^\d{4}-')
    Assert-That 'log: the first events were ADD for the entries created' ((Get-VaultAccessLog -Vault $r)[0].Action -ceq 'ADD')
    Assert-That 'log: the -Replace was recorded' (@(Get-VaultAccessLog -Vault $r | Where-Object { $_.Action -ceq 'REPLACE' -and $_.CredentialRef -ceq 'WEB_ACCESS.PTCOM2' }).Count -ge 2)
    & $vm { $script:MaxAccessLog = 5 }
    1..8 | ForEach-Object { [void](Get-VaultSecretValue -Vault $r -CredentialRef 'IIS_IDENTITY.PTCOM1') }
    Assert-That 'log: it keeps only the newest entries when it passes the limit' (@(Get-VaultAccessLog -Vault $r).Count -eq 5 -and (Get-VaultAccessLog -Vault $r)[-1].Action -ceq 'READ')
    & $vm { $script:MaxAccessLog = 10000 }

    # -----------------------------------------------------------------------
    # H. Limit, I. Remove
    # -----------------------------------------------------------------------
    $v3 = New-CredentialVault -Path (Join-Path $root 'v3' 'vault.sisqual') -Passphrase (New-Pass $pass)
    & $vm { $script:MaxSecrets = 3 }
    1..3 | ForEach-Object { [void](Add-VaultSecret -Vault $v3 -Kind 'WEB_ACCESS' -Code ('L' + $_) -Value (Get-Bytes 'x')) }
    Assert-Throws 'limit: one more than the maximum is SECRETS_LIMIT' { Add-VaultSecret -Vault $v3 -Kind 'WEB_ACCESS' -Code 'L4' -Value (Get-Bytes 'x') } 'SECRETS_LIMIT'
    Assert-That 'limit: replacing an existing entry at the limit still works' ((Add-VaultSecret -Vault $v3 -Kind 'WEB_ACCESS' -Code 'L1' -Value (Get-Bytes 'y') -Replace).CredentialRef -ceq 'WEB_ACCESS.L1')
    & $vm { $script:MaxSecrets = 5000 }
    Remove-VaultSecret -Vault $v3 -CredentialRef 'WEB_ACCESS.L2'
    Assert-That 'remove: the entry is gone and the removal is logged' (@(Get-VaultSecretList -Vault $v3).Count -eq 2 -and (Get-VaultAccessLog -Vault $v3)[-1].Action -ceq 'REMOVE')
    Assert-Throws 'remove: its value is SECRET_MISSING afterwards' { Get-VaultSecretValue -Vault $v3 -CredentialRef 'WEB_ACCESS.L2' } 'SECRET_MISSING'
    Assert-Throws 'remove: an unknown reference is SECRET_MISSING' { Remove-VaultSecret -Vault $v3 -CredentialRef 'WEB_ACCESS.NOPE' } 'SECRET_MISSING'
    Assert-That 'add: after a removal the same reference can be added again' ((Add-VaultSecret -Vault $v3 -Kind 'WEB_ACCESS' -Code 'L2' -Value (Get-Bytes 'z')).CredentialRef -ceq 'WEB_ACCESS.L2')
    $v3.Data.Remove('secrets')
    Assert-That 'compat: a vault whose data has no secrets list gets one on the first add' ((Add-VaultSecret -Vault $v3 -Kind 'RULE_SECRET' -Code 'R1' -Value (Get-Bytes 'x')).CredentialRef -ceq 'RULE_SECRET.R1' -and @(Get-VaultSecretList -Vault $v3).Count -eq 1)

    # -----------------------------------------------------------------------
    # J. Closed vault and secret hygiene
    # -----------------------------------------------------------------------
    Close-CredentialVault -Vault $v3
    Assert-Throws 'closed: add is VAULT_CLOSED' { Add-VaultSecret -Vault $v3 -Kind 'WEB_ACCESS' -Code 'Z' -Value (Get-Bytes 'x') } 'VAULT_CLOSED'
    Assert-Throws 'closed: list is VAULT_CLOSED' { Get-VaultSecretList -Vault $v3 } 'VAULT_CLOSED'
    Assert-Throws 'closed: get is VAULT_CLOSED' { Get-VaultSecretValue -Vault $v3 -CredentialRef 'RULE_SECRET.R1' } 'VAULT_CLOSED'
    Assert-Throws 'closed: remove is VAULT_CLOSED' { Remove-VaultSecret -Vault $v3 -CredentialRef 'RULE_SECRET.R1' } 'VAULT_CLOSED'
    Assert-Throws 'closed: the log is VAULT_CLOSED' { Get-VaultAccessLog -Vault $v3 } 'VAULT_CLOSED'
    $captured = @(
        (Get-VaultSecretList -Vault $r)
        (Get-VaultAccessLog -Vault $r)
    ) *>&1 | Out-String
    $failText = ''
    try { Get-VaultSecretValue -Vault $r -CredentialRef 'WEB_ACCESS.NOPE' } catch { $failText = $_.Exception.Message + ($_ | Out-String) }
    Assert-That 'hygiene: no marker in the list, the log or any failure' (($captured -cnotlike '*MARKER*') -and ($failText -cnotlike '*MARKER*'))
    Close-CredentialVault -Vault $r
}
finally {
    Remove-Module Sisqual.CredentialVault -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ''
Write-Host ('Passed: {0}  Failed: {1}' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
