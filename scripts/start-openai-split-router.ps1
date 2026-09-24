[CmdletBinding()]
param(
    [string]$SingBoxExe = 'E:\learn\v2rayN-windows-64-desktop\v2rayN-windows-64\bin\sing_box\sing-box.exe',
    [switch]$EnableSystemProxy
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot 'config\openai-split-router.json'

foreach ($port in 7897, 7898) {
    $test = Test-NetConnection 127.0.0.1 -Port $port -WarningAction SilentlyContinue
    if (-not $test.TcpTestSucceeded) {
        throw "Required upstream proxy 127.0.0.1:$port is not listening."
    }
}

if (-not (Test-Path -LiteralPath $SingBoxExe)) {
    throw "sing-box was not found at $SingBoxExe"
}

& $SingBoxExe check -c $configPath
if ($LASTEXITCODE -ne 0) {
    throw 'The split-router configuration is invalid.'
}

$listener = Get-NetTCPConnection -State Listen -LocalPort 7899 -ErrorAction SilentlyContinue
if (-not $listener) {
    Start-Process -FilePath $SingBoxExe `
        -ArgumentList @('run', '-c', $configPath) `
        -WindowStyle Hidden

    $deadline = (Get-Date).AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 250
        $listener = Get-NetTCPConnection -State Listen -LocalPort 7899 -ErrorAction SilentlyContinue
    } until ($listener -or (Get-Date) -ge $deadline)
}

if (-not $listener) {
    throw 'The split router did not start listening on 127.0.0.1:7899.'
}

$defaultExit = (& curl.exe --silent --show-error --max-time 12 `
    --proxy http://127.0.0.1:7899 http://api.ipify.org 2>&1)
if ($LASTEXITCODE -ne 0 -or -not $defaultExit) {
    throw "The split router default path failed: $($defaultExit -join ' ')"
}

Write-Host "Split router is listening on 127.0.0.1:7899." -ForegroundColor Green
Write-Host "Default/non-OpenAI exit: $(($defaultExit -join '').Trim())"

if ($EnableSystemProxy) {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    Set-ItemProperty -Path $key -Name ProxyServer -Value '127.0.0.1:7899'
    Set-ItemProperty -Path $key -Name ProxyEnable -Type DWord -Value 1
    Remove-ItemProperty -Path $key -Name AutoConfigURL -ErrorAction SilentlyContinue

    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SplitRouterWinInet {
    [DllImport("wininet.dll", SetLastError=true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int option, IntPtr buffer, int length);
}
'@
    [SplitRouterWinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [SplitRouterWinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
    Write-Host 'Windows system proxy is now 127.0.0.1:7899.' -ForegroundColor Green
}
