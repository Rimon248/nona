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

  # Flutter's release bundle needs the matching Visual C++ runtime beside the
  # executable when Windows does not already have the redistributable installed.
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
  if (-not (Test-Path $vswhere)) { throw 'Visual Studio locator is missing.' }
  $visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if ($LASTEXITCODE -ne 0 -or -not $visualStudio) { throw 'Visual C++ build tools are missing.' }
  $redistRoot = Join-Path $visualStudio 'VC/Redist/MSVC'
  $crt = Get-ChildItem -Path $redistRoot -Directory |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64/Microsoft.VC143.CRT' } |
    Where-Object { Test-Path (Join-Path $_ 'msvcp140.dll') } |
    Select-Object -First 1
  if (-not $crt) { throw 'The matching x64 Visual C++ runtime was not found.' }
  $bundle = Join-Path $clientDirectory 'build/windows/x64/runner/Release'
  foreach ($name in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    $source = Join-Path $crt $name
    if (-not (Test-Path $source)) { throw "Missing Visual C++ runtime file: $name" }
    Copy-Item $source (Join-Path $bundle $name) -Force
  }
} finally {
  Pop-Location
}
