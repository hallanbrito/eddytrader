<#
.SYNOPSIS
    Simulação automatizada do protocolo de recovery no Strategy Tester (W10.2).
.DESCRIPTION
    Executa probe_demo_restart_w10_2 no Strategy Tester para validar o modelo de
    saúde operacional e ausência de falso FAIL-CLOSED após restart em estado BLOCKED.
#>

$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$termData = "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$iniPath = "$termData\run_demo_restart.ini"

Copy-Item "C:\Projetos\eddytrader\tests\probe_demo_restart_w10_2.ex5" "$termData\MQL5\Experts\probe_demo_restart_w10_2.ex5" -Force

$iniContent = @"
[Common]
Login=6272676
Server=ActivTradesCorp-Server

[Tester]
Expert=probe_demo_restart_w10_2.ex5
Symbol=EURUSD
Period=M1
Deposit=10000
Currency=USD
Model=1
ExecutionMode=0
FromDate=2026.09.01
ToDate=2026.09.12
ShutdownTerminal=1
"@

Set-Content -Path $iniPath -Value $iniContent -Encoding Ascii

Write-Host "Killing existing terminal64 processes..."
Stop-Process -Name "terminal64" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "Launching terminal with $iniPath..."
$proc = Start-Process -FilePath $terminal -ArgumentList "/config:`"$iniPath`"" -Wait -PassThru -NoNewWindow
Start-Sleep -Seconds 2

Write-Host "Checking for probe_demo_restart_w10_2.txt in MQL5\Files and Tester\Files..."
$resFile1 = "$termData\MQL5\Files\probe_demo_restart_w10_2.txt"
$resFile2 = "$termData\Tester\Files\probe_demo_restart_w10_2.txt"
$testerFiles = Get-ChildItem "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Tester\*\Agent-*\MQL5\Files\probe_demo_restart_w10_2.txt" -ErrorAction SilentlyContinue

if (Test-Path $resFile1) {
    Write-Host "=== TEST RESULTS in $resFile1 ==="
    Get-Content $resFile1
} elseif (Test-Path $resFile2) {
    Write-Host "=== TEST RESULTS in $resFile2 ==="
    Get-Content $resFile2
} elseif ($testerFiles) {
    Write-Host "=== TEST RESULTS in $($testerFiles[0].FullName) ==="
    Get-Content $testerFiles[0].FullName
}

Write-Host "Checking Tester logs..."
$testerLogs = Get-ChildItem "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Tester\*\Agent-*\logs\*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if ($testerLogs) {
    Write-Host "Found Tester log: $($testerLogs[0].FullName)"
    Get-Content $testerLogs[0].FullName -Encoding Unicode -Tail 30
}
