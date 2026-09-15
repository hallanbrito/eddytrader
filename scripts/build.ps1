<#
.SYNOPSIS
    Build oficial reproduzível do EddyTrader (Release Candidate).
.DESCRIPTION
    Compila todos os artefatos de produção e homologação via MetaEditor 64-bit nativo.
    Verifica estritamente que a compilação produziu 0 erros e 0 warnings.
    Em caso de sucesso, copia os binários (.ex5) para o diretório de Experts do MetaTrader 5.
#>

$ErrorActionPreference = "Stop"

$metaeditor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
$termData   = "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$expertsDir = "$termData\MQL5\Experts"

if (-not (Test-Path $metaeditor)) {
    Write-Error "[BUILD ERROR] MetaEditor 64-bit não localizado em $metaeditor"
    exit 1
}

Write-Host "================================================================"
Write-Host " Disciplinador Trader Build Reproduzível — Release Candidate 1.0.0-rc3"
Write-Host " Compilador: $metaeditor"
Write-Host "================================================================"

$filesToCompile = @(
    "C:\Projetos\eddytrader\src\EddyTrader.mq5",
    "C:\Projetos\eddytrader\tests\test_fsm_w06.mq5",
    "C:\Projetos\eddytrader\tests\probe_env_w07.mq5",
    "C:\Projetos\eddytrader\tests\probe_trade_w07.mq5",
    "C:\Projetos\eddytrader\tests\test_demo_live_w07.mq5",
    "C:\Projetos\eddytrader\tests\test_demo_trade_w07.mq5",
    "C:\Projetos\eddytrader\tests\probe_external_ea_w10.mq5",
    "C:\Projetos\eddytrader\tests\test_visual_w10.mq5",
    "C:\Projetos\eddytrader\tests\probe_demo_restart_w10_2.mq5"
)

$hasFailure = $false

foreach ($srcPath in $filesToCompile) {
    if (-not (Test-Path $srcPath)) {
        Write-Error "[BUILD ERROR] Arquivo fonte não encontrado: $srcPath"
        $hasFailure = $true
        continue
    }

    $fileName = [System.IO.Path]::GetFileName($srcPath)
    $logPath  = [System.IO.Path]::ChangeExtension($srcPath, ".log")
    if (Test-Path $logPath) { Remove-Item $logPath -Force }

    Write-Host -NoNewline "Compilando $fileName... "

    $proc = Start-Process -FilePath $metaeditor -ArgumentList "/compile:`"$srcPath`" /log:`"$logPath`"" -Wait -PassThru -NoNewWindow
    Start-Sleep -Milliseconds 300

    if (Test-Path $logPath) {
        $logContent = Get-Content $logPath -Encoding Unicode
        $resultLine = $logContent | Where-Object { $_ -match "Result:" }
        
        if ($resultLine -match "0 errors, 0 warnings") {
            Write-Host -ForegroundColor Green "OK ($resultLine)"
        } else {
            Write-Host -ForegroundColor Red "FALHA ($resultLine)"
            Write-Host "--- Detalhes do Log ($fileName) ---"
            $logContent | ForEach-Object { Write-Host "  $_" }
            $hasFailure = $true
        }
    } else {
        Write-Host -ForegroundColor Red "FALHA (Nenhum log gerado pelo MetaEditor)"
        $hasFailure = $true
    }
}

if ($hasFailure) {
    Write-Error "`n[BUILD FAILED] Um ou mais arquivos apresentaram erros ou warnings de compilação!"
    exit 1
}

Write-Host "`nTodos os artefatos compilaram com 0 errors e 0 warnings."

# Deploy dos binários para o terminal ativo
if (Test-Path $expertsDir) {
    Write-Host "Copiando binários compilados (.ex5) para $expertsDir..."
    Copy-Item "C:\Projetos\eddytrader\src\EddyTrader.ex5" "$expertsDir\EddyTrader.ex5" -Force
    Copy-Item "C:\Projetos\eddytrader\tests\test_fsm_w06.ex5" "$expertsDir\test_fsm_w06.ex5" -Force
    Copy-Item "C:\Projetos\eddytrader\tests\test_visual_w10.ex5" "$expertsDir\test_visual_w10.ex5" -Force
    Copy-Item "C:\Projetos\eddytrader\tests\probe_demo_restart_w10_2.ex5" "$expertsDir\probe_demo_restart_w10_2.ex5" -Force
    Write-Host -ForegroundColor Green "[DEPLOY OK] Binários de produção e teste atualizados no terminal MT5."
} else {
    Write-Warning "[DEPLOY WARNING] Diretório de destino do terminal não encontrado: $expertsDir"
}

Write-Host "`n================================================================"
Write-Host -ForegroundColor Green " Build concluído com sucesso (100% LIMPO - 0 ERRORS, 0 WARNINGS)"
Write-Host "================================================================"
