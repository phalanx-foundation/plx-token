# tApps readiness smoke test (prod + env hints)
param(
  [string]$AppUrl = "https://app.plx.foundation/",
  [string]$TermsUrl = "https://plx.foundation/terms",
  [string]$SecurityUrl = "https://plx.foundation/security",
  [string]$BotHealthUrl = ""
)

$ErrorActionPreference = "Continue"
$results = @()

function Test-Url([string]$Name, [string]$Url) {
  try {
    $r = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 20
    $ok = $r.StatusCode -ge 200 -and $r.StatusCode -lt 400
    $script:results += [pscustomobject]@{ Check = $Name; Status = if ($ok) { "OK" } else { "FAIL" }; Detail = $r.StatusCode }
  } catch {
    $script:results += [pscustomobject]@{ Check = $Name; Status = "FAIL"; Detail = $_.Exception.Message }
  }
}

Test-Url "PLX App (app.plx.foundation)" $AppUrl
Test-Url "Terms" $TermsUrl
Test-Url "Security / Privacy" $SecurityUrl
Test-Url "Homepage (plx.foundation)" "https://plx.foundation/"
Test-Url "Build wizard" "https://plx.foundation/build"

if ($BotHealthUrl) {
  Test-Url "Bot worker health" $BotHealthUrl
}

$envFile = "D:\DATA TOOLS\PLX-ACTON\.env"
Test-Url "TonConnect manifest" "https://app.plx.foundation/tonconnect-manifest.json"
Test-Url "Ton Console tc-verify" "https://app.plx.foundation/tc-verify.json"

if (Test-Path $envFile) {
  $content = Get-Content $envFile -Raw

  # Each entry is a set of interchangeable names — one set = one requirement.
  $envGroups = @(
    @{ Label = "Bot token"; Keys = @("TOKEN_TELEGRAM_BOT", "TELEGRAM_BOT_TOKEN") },
    @{ Label = "Analytics token"; Keys = @("NEXT_PUBLIC_TG_ANALYTICS_TOKEN", "TG_ANALYTICS_TOKEN") },
    @{ Label = "Analytics app name"; Keys = @("NEXT_PUBLIC_TG_ANALYTICS_APP_NAME", "TG_ANALYTICS_APP_NAME") }
  )

  foreach ($group in $envGroups) {
    $found = @($group.Keys | Where-Object { $content -match "(?m)^$_=.+" })
    $results += [pscustomobject]@{
      Check = "Env $($group.Label)"
      Status = if ($found.Count -gt 0) { "OK" } else { "MISSING" }
      Detail = if ($found.Count -gt 0) { "$($found[0]) set in .env" } else { "one of: $($group.Keys -join ' / ')" }
    }
  }
} else {
  $results += [pscustomobject]@{ Check = ".env"; Status = "MISSING"; Detail = "copy from .env.example" }
}

Write-Host "`n=== PLX App tApps readiness ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$fail = ($results | Where-Object { $_.Status -eq "FAIL" }).Count
$miss = ($results | Where-Object { $_.Status -eq "MISSING" }).Count
if ($fail -eq 0 -and $miss -eq 0) {
  Write-Host "All automated checks passed. Next: BotFather Main Mini App URL = https://app.plx.foundation/ + @app_moderation_bot + demo video." -ForegroundColor Green
  exit 0
}
Write-Host "Fix FAIL/MISSING items, then see docs/TAPPS-SUBMISSION-RUNBOOK.md" -ForegroundColor Yellow
exit 1
