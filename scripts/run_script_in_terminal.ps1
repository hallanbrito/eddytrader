$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$termData = "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$iniPath = "$termData\run_test.ini"

$iniContent = @"
[Start]
Script=test_fsm_w06
"@

Set-Content -Path $iniPath -Value $iniContent -Encoding Ascii

Write-Host "Starting terminal with script config: $iniPath..."
$proc = Start-Process -FilePath $terminal -ArgumentList "/config:`"$iniPath`"" -PassThru -NoNewWindow
Start-Sleep -Seconds 5

Write-Host "Checking MQL5\Logs..."
$logs = Get-ChildItem "$termData\MQL5\Logs\*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if ($logs) {
    Write-Host "Found log: $($logs[0].FullName)"
    Get-Content $logs[0].FullName -Encoding Unicode -Tail 40
} else {
    Write-Host "No MQL5 logs found yet. Checking terminal logs..."
    $termLogs = Get-ChildItem "$termData\logs\*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($termLogs) {
        Get-Content $termLogs[0].FullName -Encoding Unicode -Tail 20
    }
}
