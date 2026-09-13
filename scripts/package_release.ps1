param([string]$Version = "1.0.0-rc1")

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot "build.ps1"
$binary = Join-Path $repoRoot "src\EddyTrader.ex5"
$quickStart = Join-Path $repoRoot "docs\18-QUICKSTART.md"
$distRoot = Join-Path $repoRoot "dist"
$packageDir = Join-Path $distRoot ("EddyTrader-" + $Version)
$zipPath = Join-Path $distRoot ("EddyTrader-" + $Version + ".zip")
$checksums = Join-Path $distRoot ("CHECKSUMS-" + $Version + ".txt")

Write-Host "==============================================================="
Write-Host (" EddyTrader Release Packager - " + $Version)
Write-Host "==============================================================="

Write-Host "[1/5] Executando build oficial..."
& $buildScript
if ($LASTEXITCODE -ne 0) { throw "Build oficial falhou. Empacotamento abortado." }
if (-not (Test-Path $binary)) { throw ("Binário não encontrado: " + $binary) }
if (-not (Test-Path $quickStart)) { throw ("Quick Start não encontrado: " + $quickStart) }

Write-Host "[2/5] Preparando dist..."
New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
if (Test-Path $packageDir) { Remove-Item $packageDir -Recurse -Force }
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
Copy-Item $binary (Join-Path $packageDir "EddyTrader.ex5") -Force
Copy-Item $quickStart (Join-Path $packageDir "LEIA-ME.md") -Force

Write-Host "[3/5] Calculando SHA-256..."
$ex5Hash = (Get-FileHash (Join-Path $packageDir "EddyTrader.ex5") -Algorithm SHA256).Hash.ToLowerInvariant()
$insideChecksum = "EddyTrader " + $Version + "`r`nSHA-256`r`n`r`n" + $ex5Hash + "  EddyTrader.ex5`r`n"
Set-Content -Path (Join-Path $packageDir "CHECKSUMS.txt") -Value $insideChecksum -Encoding UTF8

Write-Host "[4/5] Criando ZIP..."
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path (Join-Path $packageDir "*") -DestinationPath $zipPath -CompressionLevel Optimal
$zipHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$releaseChecksum = "EddyTrader " + $Version + "`r`nSHA-256`r`n`r`n" + $ex5Hash + "  EddyTrader.ex5`r`n" + $zipHash + "  EddyTrader-" + $Version + ".zip`r`n"
Set-Content -Path $checksums -Value $releaseChecksum -Encoding UTF8

Write-Host "[5/5] Pacote pronto." -ForegroundColor Green
Write-Host ""
Write-Host "Assets para GitHub Release:"
Write-Host ("  " + $binary)
Write-Host ("  " + $zipPath)
Write-Host ("  " + $checksums)
Write-Host ""
Write-Host "Publique como Pre-release enquanto LIVE-01 estiver pendente." -ForegroundColor Yellow