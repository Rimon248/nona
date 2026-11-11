$ErrorActionPreference = 'Stop'

$clientDirectory = $PSScriptRoot
$keyFile = Join-Path $clientDirectory 'trust/nona-config-2026-11.b64'
$verifyKey = (Get-Content -Raw $keyFile).Trim()
if ($verifyKey -notmatch '^[A-Za-z0-9_-]{43}$') {
  throw 'Invalid public configuration verification key.'
}

& (Join-Path $clientDirectory 'windows/prepare-engine.ps1')
if (-not $?) { throw 'Could not prepare the Windows VPN engine.' }
Push-Location $clientDirectory
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'Could not resolve Flutter dependencies.' }
  flutter build windows --release `
    --dart-define=NONA_API_BASE_URL=https://nona.server.basketref.ru `
    --dart-define=NONA_CONFIG_KEY_ID=nona-config-2026-11 `
    "--dart-define=NONA_CONFIG_VERIFY_KEY_B64=$verifyKey"
  if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
} finally {
  Pop-Location
}
