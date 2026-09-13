$path = "C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Profiles\Charts\Default\chart01.chr"
$bytes = [System.IO.File]::ReadAllBytes($path)
Write-Host "File: $path"
Write-Host "Length: $($bytes.Length)"
if ($bytes.Length -gt 4) {
    Write-Host "First 4 bytes: $($bytes[0]) $($bytes[1]) $($bytes[2]) $($bytes[3])"
}
$enc = if ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { "Unicode (UTF-16LE)" } elseif ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB) { "UTF-8" } else { "ANSI / Other" }
Write-Host "Encoding detected: $enc"
