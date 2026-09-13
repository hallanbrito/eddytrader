param(
    [string]$Version = "1.0.0-rc1",
    [string]$Target = "master"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$packageScript = Join-Path $PSScriptRoot "package_release.ps1"
$binary = Join-Path $repoRoot "src\EddyTrader.ex5"
$zipPath = Join-Path $repoRoot ("dist\EddyTrader-" + $Version + ".zip")
$checksums = Join-Path $repoRoot ("dist\CHECKSUMS-" + $Version + ".txt")
$notes = Join-Path $repoRoot ("docs\17-RELEASE-NOTES-" + $Version + ".md")
$tag = "v" + $Version

Write-Host "==============================================================="
Write-Host (" EddyTrader GitHub Release Publisher - " + $Version)
Write-Host "==============================================================="

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host ""
    Write-Host "[ERRO] GitHub CLI (gh) não encontrado." -ForegroundColor Red
    Write-Host "Instale com:"
    Write-Host "  winget install --id GitHub.cli"
    Write-Host ""
    Write-Host "Depois autentique:"
    Write-Host "  gh auth login"
    exit 1
}

Write-Host "[1/4] Validando autenticação GitHub..."
& gh auth status
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERRO] GitHub CLI não está autenticado." -ForegroundColor Red
    Write-Host "Execute: gh auth login"
    exit 1
}

Write-Host "[2/4] Gerando assets..."
& $packageScript -Version $Version
if ($LASTEXITCODE -ne 0) {
    throw "Empacotamento falhou."
}

foreach ($asset in @($binary, $zipPath, $checksums)) {
    if (-not (Test-Path $asset)) {
        throw ("Asset não encontrado: " + $asset)
    }
}

if (-not (Test-Path $notes)) {
    throw ("Release notes não encontradas: " + $notes)
}

Write-Host "[3/4] Publicando GitHub Release..."

$existing = $false
& gh release view $tag *> $null
if ($LASTEXITCODE -eq 0) {
    $existing = $true
}

if ($existing) {
    Write-Host ("Release " + $tag + " já existe; atualizando assets...")
    & gh release upload $tag $binary $zipPath $checksums --clobber
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao atualizar assets da Release."
    }
} else {
    $args = @(
        "release", "create", $tag,
        $binary, $zipPath, $checksums,
        "--target", $Target,
        "--title", ("EddyTrader " + $Version),
        "--notes-file", $notes
    )

    if ($Version -match "-rc|-beta|-alpha") {
        $args += "--prerelease"
    }

    & gh @args
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao criar GitHub Release."
    }
}

Write-Host "[4/4] Verificando Release publicada..."
& gh release view $tag --web

Write-Host ""
Write-Host ("Release publicada: " + $tag) -ForegroundColor Green
Write-Host "Assets:"
Write-Host "  EddyTrader.ex5"
Write-Host ("  EddyTrader-" + $Version + ".zip")
Write-Host ("  CHECKSUMS-" + $Version + ".txt")
