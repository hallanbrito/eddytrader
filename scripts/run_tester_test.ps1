$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$termData = "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$iniPath = "$termData\run_tester.ini"

Copy-Item "C:\Projetos\eddytrader\tests\test_fsm_w06.ex5" "$termData\MQL5\Experts\test_fsm_w06.ex5" -Force
Copy-Item "C:\Projetos\eddytrader\src\EddyTrader.ex5" "$termData\MQL5\Experts\EddyTrader.ex5" -Force

$iniContent = @"
[Common]
Login=6272676
Server=ActivTradesCorp-Server

[Tester]
Expert=test_fsm_w06.ex5
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

Write-Host "Launching terminal in Tester mode with $iniPath..."
$proc = Start-Process -FilePath $terminal -ArgumentList "/config:`"$iniPath`"" -Wait -PassThru -NoNewWindow
Start-Sleep -Seconds 2

Write-Host "Checking for test_results.txt in MQL5\Files..."
$resFile = "$termData\MQL5\Files\test_results.txt"
if (Test-Path $resFile) {
    Write-Host "=== TEST RESULTS in MQL5\Files\test_results.txt ==="
    Get-Content $resFile
} else {
    Write-Host "test_results.txt not in MQL5\Files. Checking Tester\Files..."
    $resFileTester = "$termData\Tester\Files\test_results.txt"
    if (Test-Path $resFileTester) {
        Write-Host "=== TEST RESULTS in Tester\Files\test_results.txt ==="
        Get-Content $resFileTester
    } else {
        Write-Host "Not found in Tester\Files either."
    }
}

Write-Host "Checking Tester logs..."
$testerLogs = Get-ChildItem "$termData\Tester\logs\*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if ($testerLogs) {
    Write-Host "Found Tester log: $($testerLogs[0].Name)"
    Get-Content $testerLogs[0].FullName -Encoding Unicode -Tail 40
}
