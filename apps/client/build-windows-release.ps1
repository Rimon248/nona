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

  # Flutter's runner uses the MSVC C++ runtime. Bundle the redistributable
  # app-local DLLs so a clean Windows installation can start Nona.
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
  if (-not (Test-Path $vswhere)) { throw 'Visual Studio redistributables were not found.' }
  $vsRoot = (& $vswhere -latest -products * -property installationPath).Trim()
  $crt = Get-ChildItem (Join-Path $vsRoot 'VC/Redist/MSVC') -Directory |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64/Microsoft.VC143.CRT' } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
  if (-not $crt) { throw 'The x64 Visual C++ runtime was not found.' }
  $bundle = Join-Path $clientDirectory 'build/windows/x64/runner/Release'
  foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    if (-not (Test-Path (Join-Path $crt $name))) {
      throw "Required runtime library missing: $name"
    }
  }
  Copy-Item (Join-Path $crt '*.dll') $bundle -Force
} finally {
  Pop-Location
}
