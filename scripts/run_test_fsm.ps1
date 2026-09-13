$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$termData = "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$iniPath = "$termData\run_test.ini"

$iniContent = @"
[Common]
Login=6272676
Server=ActivTradesCorp-Server

[Start]
Script=test_fsm_w06
Symbol=EURUSD
Period=M1
"@

Set-Content -Path $iniPath -Value $iniContent -Encoding Ascii

Write-Host "Killing existing terminal64 processes..."
Stop-Process -Name "terminal64" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "Launching terminal64 with config $iniPath..."
$proc = Start-Process -FilePath $terminal -ArgumentList "/config:`"$iniPath`"" -PassThru -NoNewWindow
Start-Sleep -Seconds 12

Write-Host "Checking for test_results.txt in MQL5\Files..."
$resFile = "$termData\MQL5\Files\test_results.txt"
if (Test-Path $resFile) {
    Write-Host "=== TEST RESULTS FOUND in MQL5\Files\test_results.txt ==="
    Get-Content $resFile
} else {
    Write-Host "test_results.txt not found yet."
}

Write-Host "Checking for Experts/Scripts logs in MQL5\Logs..."
$mqlLogs = Get-ChildItem "$termData\MQL5\Logs\*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if ($mqlLogs) {
    Write-Host "=== Content of $($mqlLogs[0].Name) ==="
    Get-Content $mqlLogs[0].FullName -Encoding Unicode -Tail 40
} else {
    Write-Host "No MQL5 logs generated yet."
}

Write-Host "Checking terminal logs in logs\..."
$termLogs = Get-ChildItem "$termData\logs\20260913.log" -ErrorAction SilentlyContinue
if ($termLogs) {
    Get-Content $termLogs.FullName -Encoding Unicode -Tail 20
}
