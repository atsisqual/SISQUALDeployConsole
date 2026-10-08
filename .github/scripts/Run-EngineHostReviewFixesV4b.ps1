#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$driver = '.github/scripts/Apply-EngineHostReviewFixesV4.ps1'
$text = [IO.File]::ReadAllText($driver)
$needle = '$t = $t.Replace(''-CatalogMachineName $env:COMPUTERNAME -ManifestEntries'',''-CatalogSession $Context.CatalogSession -ManifestEntries'')'
$replacement = @'
$t = $t.Replace('-CatalogMachineName $env:COMPUTERNAME -ManifestEntries','-CatalogSession $Context.CatalogSession -ManifestEntries')
$t = $t.Replace('-CatalogSession $Context.CatalogSession -ManifestEntries $timedMutable.Manifest','-CatalogSession $timedMutable.CatalogSession -ManifestEntries $timedMutable.Manifest')
'@.TrimEnd()
if (-not $text.Contains($needle)) { throw 'Expected V4 substitution anchor was not found.' }
$text = $text.Replace($needle,$replacement)
[IO.File]::WriteAllText($driver,$text,[Text.UTF8Encoding]::new($false))

# The V4 driver commits only the functional patch. Remove this transport wrapper first.
Remove-Item '.github/workflows/run-enginehost-review-fixes-v4b.yml' -Force -ErrorAction SilentlyContinue
Remove-Item '.github/scripts/Run-EngineHostReviewFixesV4b.ps1' -Force

& $driver
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
