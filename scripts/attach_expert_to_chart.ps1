param (
    [string]$ExpertName = "probe_env_w07",
    [string]$OutFileName = "probe_env_w07.txt",
    [int]$TimeoutSec = 30
)

$terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$termData = "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$chartPath = "$termData\MQL5\Profiles\Charts\Default\chart01.chr"
$chartBak = "$termData\MQL5\Profiles\Charts\Default\chart01.chr.clean"

Write-Host "Killing any running terminal64..."
Stop-Process -Name "terminal64" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# Ensure clean backup exists
if (-not (Test-Path $chartBak)) {
    Copy-Item $chartPath $chartBak -Force
    Write-Host "Created clean backup: $chartBak"
}

# Deploy the expert to MQL5\Experts
$sourceEx5 = "C:\Projetos\eddytrader\tests\$ExpertName.ex5"
if (-not (Test-Path $sourceEx5)) {
    $sourceEx5 = "C:\Projetos\eddytrader\src\$ExpertName.ex5"
}
if (Test-Path $sourceEx5) {
    Copy-Item $sourceEx5 "$termData\MQL5\Experts\$ExpertName.ex5" -Force
    Write-Host "Deployed $sourceEx5 to Experts."
}

# Read clean chart using Unicode
$content = Get-Content $chartBak -Encoding Unicode

# Build expert block
$expertBlock = @"
<expert>
name=$ExpertName
flags=339
window_num=0
<inputs>
</inputs>
</expert>
</chart>
"@

$joined = $content -join "`r`n"
$newContent = $joined.Replace("</chart>", $expertBlock)
Set-Content -Path $chartPath -Value $newContent -Encoding Unicode
Write-Host "chart01.chr updated with Expert $ExpertName (Unicode UTF-16LE)."

# Prepare config ini for auto-login
$iniPath = "$termData\run_expert_chart.ini"
$iniContent = @"
[Common]
Login=6272676
Server=ActivTradesCorp-Server

[Charts]
ProfileLast=Default
"@
Set-Content -Path $iniPath -Value $iniContent -Encoding Ascii

$outFile = "$termData\MQL5\Files\$OutFileName"
if (Test-Path $outFile) { Remove-Item $outFile -Force }

Write-Host "Starting terminal with attached Expert $ExpertName on chart01..."
$proc = Start-Process -FilePath $terminal -ArgumentList "/config:`"$iniPath`"" -PassThru -NoNewWindow

$waited = 0
while ($waited -lt $TimeoutSec) {
    Start-Sleep -Seconds 2
    $waited += 2
    if (Test-Path $outFile) {
        Write-Host "Output file $OutFileName detected after $waited seconds!"
        break
    }
}

Start-Sleep -Seconds 2
Stop-Process -Name "terminal64" -Force -ErrorAction SilentlyContinue

# Restore clean chart
Copy-Item $chartBak $chartPath -Force
Write-Host "Restored clean chart01.chr."

if (Test-Path $outFile) {
    Write-Host "=== CONTENT OF $OutFileName ==="
    Get-Content $outFile
} else {
    Write-Warning "$OutFileName was not created."
    $mqlLogs = Get-ChildItem "$termData\MQL5\Logs\*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
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
