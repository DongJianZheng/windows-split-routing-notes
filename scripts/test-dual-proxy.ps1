[CmdletBinding()]
param(
    [int]$YouTuPort = 7897,
    [int]$VpsPort = 7898,
    [string]$ExpectedVpsIp = ''
)

$ErrorActionPreference = 'Stop'

function Test-LocalProxy {
    param(
        [string]$Name,
        [int]$Port
    )

    $tcp = Test-NetConnection 127.0.0.1 -Port $Port -WarningAction SilentlyContinue
    if (-not $tcp.TcpTestSucceeded) {
        return [pscustomobject]@{
            Name = $Name
            Port = $Port
            Listening = $false
            ExitIp = ''
        }
    }

    $response = & curl.exe --silent --show-error --max-time 12 `
        --proxy "http://127.0.0.1:$Port" http://api.ipify.org 2>&1
    if ($LASTEXITCODE -ne 0 -or -not $response) {
        throw "$Name proxy exit check failed: $($response -join ' ')"
    }
    $exitIp = ($response -join '').Trim()

    [pscustomobject]@{
        Name = $Name
        Port = $Port
        Listening = $true
        ExitIp = $exitIp
    }
}

$results = @(
    Test-LocalProxy -Name 'YouTu' -Port $YouTuPort
    Test-LocalProxy -Name 'VPS/v2rayN' -Port $VpsPort
)

$results | Format-Table -AutoSize

$settings = Get-ItemProperty `
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

Write-Host "WinINET registry proxy enabled: $($settings.ProxyEnable)"
Write-Host "WinINET registry proxy server : $($settings.ProxyServer)"
Write-Host 'Note: the current YouTu version may manage its UI proxy state outside these legacy fields.'

$vps = $results | Where-Object Name -eq 'VPS/v2rayN'
if (-not $vps.Listening) {
    throw "VPS proxy is not listening on 127.0.0.1:$VpsPort."
}
if ($ExpectedVpsIp -and $vps.ExitIp -ne $ExpectedVpsIp) {
    throw "Unexpected VPS exit IP '$($vps.ExitIp)'; expected '$ExpectedVpsIp'."
}

Write-Host 'Dual-proxy check passed.' -ForegroundColor Green
