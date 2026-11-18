$ErrorActionPreference = 'Stop'

$version = (Get-Content (Join-Path $PSScriptRoot '../assets/engine-version.txt') -Raw).Trim()
$libXrayHash = '666A1AF3DCF8079D545B583C41EFE60B25BCD689A8317042CFD748A42B34071E'
$xrayHash = '1262522266337B824F07BEB8E1375786B437683B3890105469088F8E17E0A69D'
$work = Join-Path $env:TEMP "nona-engine-$version"
$destination = Join-Path $PSScriptRoot 'runner/engine'

New-Item -ItemType Directory -Force -Path $work, $destination | Out-Null
$libArchive = Join-Path $work 'libxray-windows-x64.zip'
$coreArchive = Join-Path $work 'Xray-windows-64.zip'
$libExtract = Join-Path $work 'libxray'
$coreExtract = Join-Path $work 'xray'

Invoke-WebRequest `
  -Uri "https://github.com/XTLS/libXray/releases/download/v$version/libxray-windows-x64.zip" `
  -OutFile $libArchive
Invoke-WebRequest `
  -Uri "https://github.com/XTLS/Xray-core/releases/download/v$version/Xray-windows-64.zip" `
  -OutFile $coreArchive

if ((Get-FileHash $libArchive -Algorithm SHA256).Hash -ne $libXrayHash) {
  throw 'libXray Windows archive checksum does not match the pinned release.'
}
if ((Get-FileHash $coreArchive -Algorithm SHA256).Hash -ne $xrayHash) {
  throw 'Xray Windows archive checksum does not match the pinned release.'
}

Expand-Archive -Path $libArchive -DestinationPath $libExtract -Force
Expand-Archive -Path $coreArchive -DestinationPath $coreExtract -Force

$libXray = Get-ChildItem -Path $libExtract -Filter 'libXray.dll' -Recurse |
  Select-Object -First 1
$wintun = Get-ChildItem -Path $coreExtract -Filter 'wintun.dll' -Recurse |
  Select-Object -First 1
$xrayLicense = Get-ChildItem -Path $coreExtract -Filter 'LICENSE' -Recurse |
  Select-Object -First 1
$wintunLicense = Get-ChildItem -Path $coreExtract -Filter 'LICENSE-Wintun' -Recurse |
  Select-Object -First 1

foreach ($required in @($libXray, $wintun, $xrayLicense, $wintunLicense)) {
  if ($null -eq $required) { throw 'An expected upstream engine file is missing.' }
}

Copy-Item $libXray.FullName (Join-Path $destination 'libXray.dll') -Force
Copy-Item $wintun.FullName (Join-Path $destination 'wintun.dll') -Force
Copy-Item $xrayLicense.FullName (Join-Path $destination 'Xray-Core-LICENSE.txt') -Force
Copy-Item $wintunLicense.FullName (Join-Path $destination 'Wintun-LICENSE.txt') -Force
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/XTLS/libXray/v$version/LICENSE" `
  -OutFile (Join-Path $destination 'libXray-LICENSE.txt')

Write-Output "Prepared and checksum-verified libXray $version for Windows x64."
