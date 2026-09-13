$path = "C:\Program Files\MetaTrader 5\terminal64.exe"
$bytes = [System.IO.File]::ReadAllBytes($path)
$unicode = [System.Text.Encoding]::Unicode.GetString($bytes)

$idx = $unicode.IndexOf("/config")
if ($idx -ge 0) {
    $start = [Math]::Max(0, $idx - 200)
    $len = [Math]::Min(1000, $unicode.Length - $start)
    Write-Host "Found /config context:"
    Write-Host $unicode.Substring($start, $len)
} else {
    Write-Host "/config not found as Unicode, checking ASCII..."
    $ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
    $idxA = $ascii.IndexOf("/config")
    if ($idxA -ge 0) {
        $start = [Math]::Max(0, $idxA - 200)
        $len = [Math]::Min(1000, $ascii.Length - $start)
        Write-Host "Found /config in ASCII:"
        Write-Host $ascii.Substring($start, $len)
    }
}
