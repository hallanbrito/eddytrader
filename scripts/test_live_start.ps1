$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$termData = "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"

Copy-Item "C:\Projetos\eddytrader\tests\probe_env_w07.ex5" -Destination "$termData\MQL5\Experts\probe_env_w07.ex5" -Force
Copy-Item "C:\Projetos\eddytrader\tests\probe_env_w07.ex5" -Destination "$termData\MQL5\Scripts\probe_env_w07.ex5" -Force

$outFile = "$termData\MQL5\Files\probe_env_w07.txt"
if (Test-Path $outFile) { Remove-Item $outFile -Force }

$iniPath = "$termData\run_live_test.ini"
$iniContent = @"
[Common]
Login=6272676
Server=ActivTradesCorp-Server

[Start]
Expert=probe_env_w07
Symbol=EURUSD
Period=M1
"@
Set-Content -Path $iniPath -Value $iniContent -Encoding Ascii

Write-Host "Killing any running terminal64..."
Stop-Process -Name "terminal64" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host "Starting terminal with config: $iniPath..."
$proc = Start-Process -FilePath $terminal -ArgumentList "/config:`"$iniPath`"" -PassThru -NoNewWindow

$timeout = 30
$found = $false
for ($i = 0; $i -lt $timeout; $i++) {
    Start-Sleep -Seconds 1
    if (Test-Path $outFile) {
        Write-Host "Output file detected at second $i!"
        $found = $true
        break
    }
}

Start-Sleep -Seconds 2
Stop-Process -Name "terminal64" -Force -ErrorAction SilentlyContinue

if ($found) {
    Write-Host "=== CONTENT OF probe_env_w07.txt ==="
    Get-Content $outFile
} else {
    Write-Warning "probe_env_w07.txt was not detected within $timeout seconds."
    $mqlLogs = Get-ChildItem "$termData\MQL5\logs\*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($mqlLogs) {
        Write-Host "=== Last 25 lines of MQL5 Log ($($mqlLogs[0].Name)) ==="
        Get-Content $mqlLogs[0].FullName -Encoding Unicode -Tail 25
    }
    $termLogs = Get-ChildItem "$termData\logs\20260913.log" -ErrorAction SilentlyContinue
    if ($termLogs) {
        Write-Host "=== Last 25 lines of Terminal Log ==="
        Get-Content $termLogs.FullName -Encoding Unicode -Tail 25
    }
}
