[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$configName = 'openai-split-router.json'
$targets = Get-CimInstance Win32_Process |
    Where-Object {
        $_.Name -eq 'sing-box.exe' -and
        $_.CommandLine -like "*$configName*"
    }

foreach ($target in $targets) {
    Stop-Process -Id $target.ProcessId
}

$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
Set-ItemProperty -Path $key -Name ProxyServer -Value '127.0.0.1:7897'
Set-ItemProperty -Path $key -Name ProxyEnable -Type DWord -Value 1

Write-Host 'Split router stopped; Windows proxy restored to YouTu at 127.0.0.1:7897.'
