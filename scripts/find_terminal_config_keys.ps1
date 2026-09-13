$path = "C:\Program Files\MetaTrader 5\terminal64.exe"
$bytes = [System.IO.File]::ReadAllBytes($path)
$unicode = [System.Text.Encoding]::Unicode.GetString($bytes)

Write-Host "Matches for ProfileLast:"
[regex]::Matches($unicode, '.{0,30}ProfileLast.{0,50}') | ForEach-Object { Write-Host $_.Value }

Write-Host "`nMatches for Script=:"
[regex]::Matches($unicode, '.{0,30}Script=.{0,50}') | ForEach-Object { Write-Host $_.Value }

Write-Host "`nMatches for Expert=:"
[regex]::Matches($unicode, '.{0,30}Expert=.{0,50}') | ForEach-Object { Write-Host $_.Value }
