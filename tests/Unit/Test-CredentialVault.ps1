#requires -Version 7.0
<#
.SYNOPSIS
    Unit tests for tools/lib/Sisqual.CredentialVault.psm1 (step B6.2a).

.DESCRIPTION
    No network, no SQL Server. Everything happens in a temporary folder that is removed at the end. The
    iteration count is lowered to 1000 for speed after the test has checked that the real default is 600000.
    Marker values stand in for secrets. Exits 1 on any failure.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sharedPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'modules' 'Sisqual.Credentials' 'Sisqual.Credentials.psm1')).Path
$vaultPath = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'tools' 'lib' 'Sisqual.CredentialVault.psm1')).Path
Import-Module $sharedPath -Force
Import-Module $vaultPath -Force
$vm = Get-Module Sisqual.CredentialVault

$script:Failures = 0
$script:Passed = 0
function Assert-That {
    param([string]$Name, [bool]$Condition)
    if ($Condition) { $script:Passed++; Write-Host ('PASS  {0}' -f $Name) }
    else { $script:Failures++; Write-Host ('FAIL  {0}' -f $Name) }
}
function Assert-Throws {
    param([string]$Name, [scriptblock]$Block, [string]$Like = '*')
    $threw = $false
    $message = ''
    try { & $Block } catch { $threw = $true; $message = $_.Exception.Message }
    Assert-That $Name ($threw -and ($message -like $Like))
}
function New-Pass { param([string]$Text) return (ConvertTo-SecureString -String $Text -AsPlainText -Force) }
function Get-Sha { param([string]$Path) return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($Path))) }
function Read-Envelope {
    param([string]$Path)
    $b64 = (([IO.File]::ReadAllText($Path) -split "`n") | Where-Object { $_ -and $_ -notlike '-----*' }) -join ''
    return ([System.Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($b64)) | ConvertFrom-Json -AsHashtable)
}
function Write-Envelope {
    param([string]$Path, $Envelope)
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes((ConvertTo-CanonicalJson $Envelope)))
    $lines = @('-----BEGIN SISQUAL VAULT-----')
    for ($i = 0; $i -lt $b64.Length; $i += 76) { $lines += $b64.Substring($i, [Math]::Min(76, $b64.Length - $i)) }
    $lines += '-----END SISQUAL VAULT-----'
    [IO.File]::WriteAllText($Path, (($lines -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ('sisqual-vault-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$goodPass = 'correct horse battery staple 42'
try {
    # -----------------------------------------------------------------------
    # A. Defaults and passphrase policy
    # -----------------------------------------------------------------------
    Assert-That 'defaults: PBKDF2 minimum and default are 600000 iterations' ((& $vm { $script:MinIterations }) -eq 600000 -and (& $vm { $script:DefaultIterations }) -eq 600000)
    Assert-That 'defaults: minimum passphrase length is 14' ((& $vm { $script:MinPassphraseLength }) -eq 14)
    $realPath = Join-Path $root 'real' 'vault.sisqual'
    $real = New-CredentialVault -Path $realPath -Passphrase (New-Pass $goodPass)
    Assert-That 'create with the real default writes 600000 iterations in the header' ((Read-Envelope $realPath)['kdf']['iterations'] -eq 600000)
    Close-CredentialVault -Vault $real
    & $vm { $script:MinIterations = 1000; $script:DefaultIterations = 1000 }

    Assert-Throws 'policy: a short passphrase is refused' { New-CredentialVault -Path (Join-Path $root 'p1' 'v') -Passphrase (New-Pass 'short') } 'VAULT_PASSPHRASE'
    Assert-Throws 'policy: 13 characters are refused' { New-CredentialVault -Path (Join-Path $root 'p2' 'v') -Passphrase (New-Pass 'abcdefghijklm') } 'VAULT_PASSPHRASE'
    Assert-Throws 'policy: one repeated character is refused' { New-CredentialVault -Path (Join-Path $root 'p3' 'v') -Passphrase (New-Pass ('a' * 30)) } 'VAULT_PASSPHRASE'
    Assert-That 'policy: a refused passphrase creates nothing' (-not (Test-Path (Join-Path $root 'p1')))

    # Known answers computed with Python hashlib (independent implementation): the KDF is PBKDF2-HMAC-SHA256.
    $kdfInputs = @{ Pass = (New-Pass 'correct horse battery staple 42'); Salt = [byte[]](0..15) }
    $kat1000 = & $vm { param($i) $pw = Get-PassphraseBytes -Passphrase $i.Pass; [Convert]::ToHexString((Get-VaultKey -PassphraseBytes $pw -Salt $i.Salt -Iterations 1000)).ToLowerInvariant() } $kdfInputs
    $kat600k = & $vm { param($i) $pw = Get-PassphraseBytes -Passphrase $i.Pass; [Convert]::ToHexString((Get-VaultKey -PassphraseBytes $pw -Salt $i.Salt -Iterations 600000)).ToLowerInvariant() } $kdfInputs
    Assert-That 'kdf: PBKDF2-HMAC-SHA256 known answer at 1000 iterations' ($kat1000 -ceq '2d934bc2eace84f0c96089ea8c1bdcfbca3b41dcbeba22d1a78497796c1de5e7')
    Assert-That 'kdf: PBKDF2-HMAC-SHA256 known answer at 600000 iterations' ($kat600k -ceq '272d5ad8fca80ccaa5f4a18baf0b80740bcaea5e7387eab0f4269b76902d603e')

    # -----------------------------------------------------------------------
    # B. Create
    # -----------------------------------------------------------------------
    $path = Join-Path $root 'v1' 'vault.sisqual'
    $out = @(New-CredentialVault -Path $path -Passphrase (New-Pass $goodPass) *>&1)
    $vault = $out[0]
    $text = [IO.File]::ReadAllText($path)
    Assert-That 'create: one object returned and nothing written to any stream' ($out.Count -eq 1)
    Assert-That 'create: armored, ASCII and LF only' (($text.StartsWith("-----BEGIN SISQUAL VAULT-----`n")) -and ($text.EndsWith("-----END SISQUAL VAULT-----`n")) -and ($text -cnotmatch '[^\x0A\x20-\x7E]'))
    $env = Read-Envelope $path
    Assert-That 'create: envelope members and algorithm names' ((($env.Keys | Sort-Object) -join ',') -ceq 'cipher,ciphertext,format,kdf,version' -and $env['kdf']['name'] -ceq 'PBKDF2-HMAC-SHA256' -and $env['cipher']['name'] -ceq 'AES-256-GCM' -and $env['version'] -eq 1)
    Assert-That 'create: salt 16 bytes, nonce 12 bytes' (([Convert]::FromBase64String($env['kdf']['salt'])).Length -eq 16 -and ([Convert]::FromBase64String($env['cipher']['nonce'])).Length -eq 12)
    Assert-That 'create: revision 1, no issuer, no secrets' ($vault.Revision -eq 1 -and $null -eq $vault.Data['issuer'] -and @($vault.Data['secrets']).Count -eq 0)
    Assert-Throws 'create: an existing vault is never overwritten' { New-CredentialVault -Path $path -Passphrase (New-Pass $goodPass) } 'VAULT_EXISTS'
    $repo = Join-Path $root 'repo'
    [void][IO.Directory]::CreateDirectory((Join-Path $repo '.git'))
    Assert-Throws 'create: refused inside a Git work tree' { New-CredentialVault -Path (Join-Path $repo 'sub' 'v') -Passphrase (New-Pass $goodPass) } 'VAULT_IN_REPOSITORY'
    Assert-Throws 'create: fewer iterations than the minimum are refused' { New-CredentialVault -Path (Join-Path $root 'w' 'v') -Passphrase (New-Pass $goodPass) -Iterations 999 } 'VAULT_WEAK_KDF'
    if ($IsWindows) {
        $acl = Get-Acl -LiteralPath $path
        $ids = @($acl.Access | ForEach-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value })
        $allowed = @([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-32-544', 'S-1-5-18')
        Assert-That 'acl (Windows): inheritance off and only the user, Administrators and SYSTEM' ($acl.AreAccessRulesProtected -and (@($ids | Where-Object { $_ -notin $allowed }).Count -eq 0))
    }
    else {
        Assert-That 'file mode (not Windows): readable and writable by the owner only' (([IO.File]::GetUnixFileMode($path)) -eq ([IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite))
    }
    Close-CredentialVault -Vault $vault

    # -----------------------------------------------------------------------
    # C. Open and every way to fail
    # -----------------------------------------------------------------------
    $opened = Open-CredentialVault -Path $path -Passphrase (New-Pass $goodPass)
    Assert-That 'open: the right passphrase returns the data' ($opened.Revision -eq 1 -and $opened.Data['formatVersion'] -eq 1 -and ([string]$opened.Data['vaultId']) -match '^[0-9a-f-]{36}$')
    Close-CredentialVault -Vault $opened
    Assert-Throws 'open: a wrong passphrase gives the generic VAULT_OPEN' { Open-CredentialVault -Path $path -Passphrase (New-Pass 'correct horse battery staple 43') } 'VAULT_OPEN'
    Assert-Throws 'open: a trailing space is a different passphrase' { Open-CredentialVault -Path $path -Passphrase (New-Pass ($goodPass + ' ')) } 'VAULT_OPEN'
    $uniPath = Join-Path $root 'uni' 'vault.sisqual'
    $uni = New-CredentialVault -Path $uniPath -Passphrase (New-Pass ('p' + [char]0x00E9 + 'ssword ' + [char]0x4E2D + [char]0x6587 + ' long enough'))
    Close-CredentialVault -Vault $uni
    $uni2 = Open-CredentialVault -Path $uniPath -Passphrase (New-Pass ('p' + [char]0x00E9 + 'ssword ' + [char]0x4E2D + [char]0x6587 + ' long enough'))
    Assert-That 'open: a non-ASCII passphrase round trips (UTF-8)' ($uni2.Revision -eq 1)
    Close-CredentialVault -Vault $uni2

    function Test-Tamper {
        param([string]$Name, [scriptblock]$Change, [string]$Expect)
        $copy = Join-Path $root ('t-' + [guid]::NewGuid().ToString('N') + '.sisqual')
        $e = Read-Envelope $path
        & $Change $e
        Write-Envelope -Path $copy -Envelope $e
        Assert-Throws $Name { Open-CredentialVault -Path $copy -Passphrase (New-Pass $goodPass) }.GetNewClosure() $Expect
    }
    Test-Tamper 'tamper: one flipped ciphertext bit fails' { param($e) $b = [Convert]::FromBase64String($e['ciphertext']); $b[0] = $b[0] -bxor 1; $e['ciphertext'] = [Convert]::ToBase64String($b) } 'VAULT_OPEN'
    Test-Tamper 'tamper: one flipped tag bit fails' { param($e) $b = [Convert]::FromBase64String($e['ciphertext']); $b[$b.Length - 1] = $b[$b.Length - 1] -bxor 1; $e['ciphertext'] = [Convert]::ToBase64String($b) } 'VAULT_OPEN'
    Test-Tamper 'tamper: a changed nonce fails' { param($e) $b = [Convert]::FromBase64String($e['cipher']['nonce']); $b[0] = $b[0] -bxor 1; $e['cipher']['nonce'] = [Convert]::ToBase64String($b) } 'VAULT_OPEN'
    Test-Tamper 'tamper: a changed salt fails' { param($e) $b = [Convert]::FromBase64String($e['kdf']['salt']); $b[0] = $b[0] -bxor 1; $e['kdf']['salt'] = [Convert]::ToBase64String($b) } 'VAULT_OPEN'
    Test-Tamper 'tamper: a changed iteration count fails' { param($e) $e['kdf']['iterations'] = [int]$e['kdf']['iterations'] + 1 } 'VAULT_OPEN'
    Test-Tamper 'tamper: another version is a format error' { param($e) $e['version'] = 2 } 'VAULT_FORMAT'
    Test-Tamper 'tamper: another cipher name is a format error' { param($e) $e['cipher']['name'] = 'AES-128-GCM' } 'VAULT_FORMAT'
    Test-Tamper 'tamper: another kdf name is a format error' { param($e) $e['kdf']['name'] = 'PBKDF2-HMAC-SHA1' } 'VAULT_FORMAT'
    Test-Tamper 'tamper: an unknown member is a format error' { param($e) $e['extra'] = 'x' } 'VAULT_FORMAT'
    Test-Tamper 'tamper: a short salt is a format error' { param($e) $e['kdf']['salt'] = [Convert]::ToBase64String([byte[]]::new(8)) } 'VAULT_FORMAT'
    Test-Tamper 'tamper: a 12-byte nonce is required' { param($e) $e['cipher']['nonce'] = [Convert]::ToBase64String([byte[]]::new(16)) } 'VAULT_FORMAT'
    Test-Tamper 'tamper: an iteration count below the minimum is refused (downgrade)' { param($e) $e['kdf']['iterations'] = 999 } 'VAULT_WEAK_KDF'

    $good = [IO.File]::ReadAllText($path)
    function Test-TextFails {
        param([string]$Name, [string]$Content, [string]$Expect = 'VAULT_FORMAT')
        $copy = Join-Path $root ('x-' + [guid]::NewGuid().ToString('N') + '.sisqual')
        [IO.File]::WriteAllText($copy, $Content, [System.Text.UTF8Encoding]::new($false))
        Assert-Throws $Name { Open-CredentialVault -Path $copy -Passphrase (New-Pass $goodPass) }.GetNewClosure() $Expect
    }
    Test-TextFails 'format: a wrong BEGIN line' ($good.Replace('BEGIN SISQUAL VAULT', 'BEGIN SISQUAL VAULTX'))
    Test-TextFails 'format: a wrong END line' ($good.Replace('END SISQUAL VAULT', 'END SISQUAL VAULTX'))
    Test-TextFails 'format: text before the armor' ("junk`n" + $good)
    Test-TextFails 'format: a non-ASCII character' ($good.TrimEnd("`n") + "`n" + [char]0x00E9 + "`n")
    Test-TextFails 'format: a body line that is not base64' ($good.Replace("`n-----END", "`nnot base64!`n-----END"))
    Test-TextFails 'format: an empty file' ''
    Test-TextFails 'format: a text that is not a vault' "hello`nworld`n"
    Test-TextFails 'format: over the size limit' ($good + ('A' * 9000000))
    $crlf = Join-Path $root 'crlf.sisqual'
    [IO.File]::WriteAllText($crlf, $good.Replace("`n", "`r`n"), [System.Text.UTF8Encoding]::new($false))
    $viaCrlf = Open-CredentialVault -Path $crlf -Passphrase (New-Pass $goodPass)
    Assert-That 'format: CRLF line endings (a pasted copy) still open' ($viaCrlf.Revision -eq 1)
    Close-CredentialVault -Vault $viaCrlf
    Assert-Throws 'open: a missing file is a format error' { Open-CredentialVault -Path (Join-Path $root 'nothing.sisqual') -Passphrase (New-Pass $goodPass) } 'VAULT_FORMAT'
    # a vault written with a weak KDF by an older tool is refused even though it is authentic
    $weakPath = Join-Path $root 'weak.sisqual'
    $weakText = & $vm {
        param($pass)
        $pw = Get-PassphraseBytes -Passphrase $pass
        $salt = [byte[]]::new(16); [System.Security.Cryptography.RandomNumberGenerator]::Fill($salt)
        $key = Get-VaultKey -PassphraseBytes $pw -Salt $salt -Iterations 100
        ConvertTo-VaultText -Key $key -Iterations 100 -Salt $salt -Plain ([System.Text.Encoding]::ASCII.GetBytes('{}'))
    } (New-Pass $goodPass)
    [IO.File]::WriteAllText($weakPath, $weakText, [System.Text.UTF8Encoding]::new($false))
    Assert-Throws 'open: an authentic vault with a weak KDF is refused' { Open-CredentialVault -Path $weakPath -Passphrase (New-Pass $goodPass) } 'VAULT_WEAK_KDF'

    # The header is authenticated: a header field that no format check or key derivation depends on still cannot change.
    $parsedForAad = & $vm { param($p) ConvertFrom-VaultText -Text ([IO.File]::ReadAllText($p)) } $path
    $keyForAad = & $vm { param($pr, $p) $pw = Get-PassphraseBytes -Passphrase $pr; Get-VaultKey -PassphraseBytes $pw -Salt $p.Salt -Iterations $p.Iterations } (New-Pass $goodPass) $parsedForAad
    $okPlain = & $vm { param($p, $k) Open-VaultContent -Parsed $p -Key $k } $parsedForAad $keyForAad
    Assert-That 'aad: opening with the untouched header works (control)' ($okPlain.Length -gt 10)
    $parsedForAad.Header['format'] = 'SISQUAL-VAULX'
    Assert-Throws 'aad: a changed header field fails to open even with the right key' { & $vm { param($p, $k) Open-VaultContent -Parsed $p -Key $k } $parsedForAad $keyForAad } 'VAULT_OPEN'

    # -----------------------------------------------------------------------
    # D. Save
    # -----------------------------------------------------------------------
    $s = Open-CredentialVault -Path $path -Passphrase (New-Pass $goodPass)
    $before = [IO.File]::ReadAllBytes($path)
    $nonceBefore = (Read-Envelope $path)['cipher']['nonce']; $saltBefore = (Read-Envelope $path)['kdf']['salt']
    $s.Data['marker'] = 'MARKER-VAULT-DATA-5e1b-not-a-real-secret'
    Save-CredentialVault -Vault $s
    $after = [IO.File]::ReadAllBytes($path)
    Assert-That 'save: revision goes to 2 and the file changes' ($s.Revision -eq 2 -and [Convert]::ToHexString($before) -cne [Convert]::ToHexString($after))
    Assert-That 'save: a new nonce for the same key and salt' (((Read-Envelope $path)['cipher']['nonce'] -cne $nonceBefore) -and ((Read-Envelope $path)['kdf']['salt'] -ceq $saltBefore))
    Assert-That 'save: the previous generation is kept as .prev and is the old file' ((Test-Path ($path + '.prev')) -and ((Get-Sha ($path + '.prev')) -ceq [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($before))))
    Assert-That 'save: no temporary file is left behind' (@(Get-ChildItem -LiteralPath (Split-Path $path) -Force | Where-Object { $_.Name -like '*.tmp-*' }).Count -eq 0)
    Assert-That 'save: the marker is not in the file in clear' (([IO.File]::ReadAllText($path)) -cnotlike '*MARKER-VAULT-DATA*')
    Save-CredentialVault -Vault $s
    Assert-That 'save: a second save works (revision 3)' ($s.Revision -eq 3)
    $r3 = Open-CredentialVault -Path $path -Passphrase (New-Pass $goodPass)
    Assert-That 'save: a fresh open sees the revision and the data' ($r3.Revision -eq 3 -and $r3.Data['marker'] -ceq 'MARKER-VAULT-DATA-5e1b-not-a-real-secret')
    $stale = Open-CredentialVault -Path $path -Passphrase (New-Pass $goodPass)
    Save-CredentialVault -Vault $r3
    Assert-Throws 'save: a vault changed on disk since it was opened is refused (VAULT_CHANGED)' { Save-CredentialVault -Vault $stale } 'VAULT_CHANGED'
    $keyRef = $s.Key
    Close-CredentialVault -Vault $s
    Assert-That 'close: the key bytes are zeroed' (@($keyRef | Where-Object { $_ -ne 0 }).Count -eq 0)
    Assert-Throws 'close: a closed vault cannot be saved' { Save-CredentialVault -Vault $s } 'VAULT_CLOSED'
    Close-CredentialVault -Vault $r3; Close-CredentialVault -Vault $stale

    # -----------------------------------------------------------------------
    # E. Issuer key inside the vault
    # -----------------------------------------------------------------------
    $ipath = Join-Path $root 'issuer' 'vault.sisqual'
    $iv = New-CredentialVault -Path $ipath -Passphrase (New-Pass $goodPass)
    Assert-Throws 'issuer: signing without a key is ISSUER_MISSING' { Invoke-VaultIssuerSign -Vault $iv -Data ([byte[]](1, 2, 3)) } 'ISSUER_MISSING'
    Assert-That 'issuer: info is null before a key exists' ($null -eq (Get-VaultIssuerInfo -Vault $iv))
    $streams = @(New-VaultIssuerKey -Vault $iv *>&1)
    $info = $streams[0]
    Assert-That 'issuer: create returns the public info only and writes nothing else' ($streams.Count -eq 1 -and ($info.PSObject.Properties.Name -join ',') -ceq 'KeyId,PublicKeySpki,PublicKeyBase64,CreatedAt')
    Assert-That 'issuer: the key id is the fingerprint of the public key' (($info.KeyId -cmatch '^[0-9a-f]{64}$') -and ($info.KeyId -ceq (Get-PublicKeyFingerprint -PublicKeySpki $info.PublicKeySpki)))
    Assert-Throws 'issuer: a second key is refused without -Replace' { New-VaultIssuerKey -Vault $iv } 'ISSUER_EXISTS'
    [byte[]]$payload = [System.Text.Encoding]::ASCII.GetBytes('{"a":1}')
    $sig = Invoke-VaultIssuerSign -Vault $iv -Data $payload
    Assert-That 'issuer: the signature has the shape Seal-Package expects and verifies' ((($sig.Keys -join ',') -ceq 'issuerKeyId,algorithm,value') -and $sig.issuerKeyId -ceq $info.KeyId -and (Test-IssuerSignature -PublicKeySpki $info.PublicKeySpki -Data $payload -Signature $sig))
    Save-CredentialVault -Vault $iv
    $fileText = [IO.File]::ReadAllText($ipath)
    $privateB64 = [string]$iv.Data['issuer']['privateKeyPkcs8']
    Assert-That 'issuer: neither the key id, the public key nor the private key appear in the file in clear' (($fileText -cnotlike ('*' + $info.KeyId + '*')) -and ($fileText -cnotlike ('*' + $info.PublicKeyBase64 + '*')) -and ($fileText -cnotlike ('*' + $privateB64.Substring(0, 40) + '*')))
    Close-CredentialVault -Vault $iv
    $iv2 = Open-CredentialVault -Path $ipath -Passphrase (New-Pass $goodPass)
    $info2 = Get-VaultIssuerInfo -Vault $iv2
    $sig2 = Invoke-VaultIssuerSign -Vault $iv2 -Data $payload
    Assert-That 'issuer: after save and reopen the same key signs and verifies' (($info2.KeyId -ceq $info.KeyId) -and (Test-IssuerSignature -PublicKeySpki $info.PublicKeySpki -Data $payload -Signature $sig2))
    $replaced = New-VaultIssuerKey -Vault $iv2 -Replace
    Assert-That 'issuer: -Replace creates a different key' ($replaced.KeyId -cne $info.KeyId)
    Assert-That 'issuer: the old public key no longer verifies the new signature' (-not (Test-IssuerSignature -PublicKeySpki $info.PublicKeySpki -Data $payload -Signature (Invoke-VaultIssuerSign -Vault $iv2 -Data $payload)))
    Close-CredentialVault -Vault $iv2
    Assert-Throws 'issuer: a closed vault gives nothing' { Get-VaultIssuerInfo -Vault $iv2 } 'VAULT_CLOSED'

    # -----------------------------------------------------------------------
    # F. Backup and restore
    # -----------------------------------------------------------------------
    $bdir = Join-Path $root 'backups'
    $b1 = Backup-CredentialVault -Path $ipath -DestinationFolder $bdir -Stamp '20261006T100000Z'
    Assert-That 'backup: a byte-identical copy with a .bak name, hash verified' (((Get-Sha $b1.BackupPath) -ceq (Get-Sha $ipath)) -and $b1.BackupPath.EndsWith('.20261006T100000Z.bak') -and ($b1.Sha256 -ceq (Get-Sha $ipath).ToLowerInvariant()))
    Assert-Throws 'backup: an existing backup is never overwritten' { Backup-CredentialVault -Path $ipath -DestinationFolder $bdir -Stamp '20261006T100000Z' } 'VAULT_EXISTS'
    Assert-Throws 'backup: a destination inside a Git work tree is refused' { Backup-CredentialVault -Path $ipath -DestinationFolder (Join-Path $repo 'bk') } 'VAULT_IN_REPOSITORY'
    $notVault = Join-Path $root 'plain.txt'; [IO.File]::WriteAllText($notVault, "hello`n")
    Assert-Throws 'backup: a file that is not a vault is refused' { Backup-CredentialVault -Path $notVault -DestinationFolder $bdir } 'VAULT_FORMAT'
    $targetBefore = Get-Sha $ipath
    Assert-Throws 'restore: a wrong passphrase refuses and changes nothing' { Restore-CredentialVault -BackupPath $b1.BackupPath -Path $ipath -Passphrase (New-Pass 'correct horse battery staple 43') -Force } 'VAULT_OPEN'
    Assert-That 'restore: the target is untouched after the refusal' ((Get-Sha $ipath) -ceq $targetBefore)
    Assert-Throws 'restore: an existing target needs -Force' { Restore-CredentialVault -BackupPath $b1.BackupPath -Path $ipath -Passphrase (New-Pass $goodPass) } 'VAULT_EXISTS'
    $newPath = Join-Path $root 'restored' 'vault.sisqual'
    $rest = Restore-CredentialVault -BackupPath $b1.BackupPath -Path $newPath -Passphrase (New-Pass $goodPass)
    $rv = Open-CredentialVault -Path $newPath -Passphrase (New-Pass $goodPass)
    Assert-That 'restore: a new path gets a vault identical to the backup that opens' (((Get-Sha $newPath) -ceq (Get-Sha $b1.BackupPath)) -and $rv.Revision -eq $rest.Revision -and ([string]$rv.Data['vaultId']) -ceq $rest.VaultId)
    Close-CredentialVault -Vault $rv
    $changed = Open-CredentialVault -Path $ipath -Passphrase (New-Pass $goodPass); $changed.Data['marker'] = 'newer'; Save-CredentialVault -Vault $changed; $newerRevision = $changed.Revision; Close-CredentialVault -Vault $changed
    $forced = Restore-CredentialVault -BackupPath $b1.BackupPath -Path $ipath -Passphrase (New-Pass $goodPass) -Force
    $back = Open-CredentialVault -Path $ipath -Passphrase (New-Pass $goodPass)
    Assert-That 'restore -Force: the older backup is back and the replaced file is kept' (($back.Revision -lt $newerRevision) -and (Test-Path -LiteralPath $forced.Replaced) -and $forced.Replaced -like '*.replaced-*')
    Close-CredentialVault -Vault $back
    $badBackup = Join-Path $bdir 'corrupt.bak'
    $bytes = [IO.File]::ReadAllBytes($b1.BackupPath); [IO.File]::WriteAllBytes($badBackup, $bytes)
    $e = Read-Envelope $badBackup; $cb = [Convert]::FromBase64String($e['ciphertext']); $cb[3] = $cb[3] -bxor 1; $e['ciphertext'] = [Convert]::ToBase64String($cb); Write-Envelope -Path $badBackup -Envelope $e
    $guard = Get-Sha $ipath
    Assert-Throws 'restore: a corrupt backup is refused (the restore test fails)' { Restore-CredentialVault -BackupPath $badBackup -Path $ipath -Passphrase (New-Pass $goodPass) -Force } 'VAULT_OPEN'
    Assert-That 'restore: the target is untouched after a corrupt backup' ((Get-Sha $ipath) -ceq $guard)

    # -----------------------------------------------------------------------
    # G. No secret in any stream
    # -----------------------------------------------------------------------
    $gp = Join-Path $root 'streams' 'vault.sisqual'
    $captured = @(
        (New-CredentialVault -Path $gp -Passphrase (New-Pass $goodPass)) | ForEach-Object { $_ } | Out-Null
        $gv = Open-CredentialVault -Path $gp -Passphrase (New-Pass $goodPass) *>&1
        [void](New-VaultIssuerKey -Vault $gv *>&1)
        Save-CredentialVault -Vault $gv *>&1
    ) 
    $joined = ($captured | Out-String)
    Assert-That 'streams: the passphrase never appears in the output' ($joined -cnotlike ('*' + $goodPass + '*'))
}
finally {
    Remove-Module Sisqual.CredentialVault -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Host ''
Write-Host ('Passed: {0}  Failed: {1}' -f $script:Passed, $script:Failures)
if ($script:Failures -gt 0) { exit 1 }
