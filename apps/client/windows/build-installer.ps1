param(
  [Parameter(Mandatory = $true)]
  [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$clientDirectory = Split-Path $PSScriptRoot -Parent
$version = ((Select-String -Path (Join-Path $clientDirectory 'pubspec.yaml') -Pattern '^version:\s*(.+)$').Matches.Groups[1].Value).Split('+')[0]
$candidates = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "${env:ProgramFiles(x86)}\Inno Setup 7\ISCC.exe"
)
$compiler = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $compiler) {
  choco install innosetup --yes --no-progress
  if ($LASTEXITCODE -ne 0) { throw 'Could not install Inno Setup.' }
  $compiler = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $compiler) { throw 'Inno Setup compiler is missing.' }

$output = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $output -Force | Out-Null
& $compiler "/DAppVersion=$version" "/O$output" (Join-Path $PSScriptRoot 'installer.iss')
if ($LASTEXITCODE -ne 0) { throw 'Windows installer build failed.' }

$name = "nona-v$version-windows-setup.exe"
$file = Join-Path $output $name
if (-not (Test-Path $file)) { throw 'Windows installer was not produced.' }
$hash = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
$encoding = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText("$file.sha256", "$hash  $name`n", $encoding)
Write-Output $file
