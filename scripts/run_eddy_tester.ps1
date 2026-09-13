$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$termData = "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$iniPath = "$termData\run_eddy_tester.ini"

$iniContent = @"
[Common]
Login=6272676
Server=ActivTradesCorp-Server

[Tester]
Expert=EddyTrader.ex5
Symbol=EURUSD
Period=M1
Deposit=10000
Currency=USD
Model=1
ExecutionMode=0
FromDate=2026.09.01
ToDate=2026.09.02
ShutdownTerminal=1
"@

Set-Content -Path $iniPath -Value $iniContent -Encoding Ascii

Write-Host "Killing existing terminal64 processes..."
Stop-Process -Name "terminal64" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Host "Launching terminal with EddyTrader in Tester mode..."
$proc = Start-Process -FilePath $terminal -ArgumentList "/config:`"$iniPath`"" -Wait -PassThru -NoNewWindow
Start-Sleep -Seconds 2

Write-Host "Checking Tester logs for EddyTrader execution..."
$testerLogs = Get-ChildItem "$termData\Tester\logs\*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if ($testerLogs) {
    Write-Host "Found Tester log: $($testerLogs[0].Name)"
    Get-Content $testerLogs[0].FullName -Encoding Unicode -Tail 40
}
