[CmdletBinding()]
param(
    [int]$ProxyPort = 7898,
    [string]$ExpectedExitIp = ''
)

$ErrorActionPreference = 'Stop'
$proxyUrl = "http://127.0.0.1:$ProxyPort"

$tcp = Test-NetConnection 127.0.0.1 -Port $ProxyPort -WarningAction SilentlyContinue
if (-not $tcp.TcpTestSucceeded) {
    throw "Nothing is listening on $proxyUrl. Start v2rayN first."
}

$response = & curl.exe --silent --show-error --max-time 12 `
    --proxy $proxyUrl http://api.ipify.org 2>&1
if ($LASTEXITCODE -ne 0 -or -not $response) {
    throw "VPS proxy exit check failed: $($response -join ' ')"
}
$exitIp = ($response -join '').Trim()
if ($ExpectedExitIp -and $exitIp -ne $ExpectedExitIp) {
    throw "Proxy exit IP is '$exitIp', expected '$ExpectedExitIp'. Codex was not restarted."
}

$codexProcess = Get-Process ChatGPT -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like '*OpenAI.Codex*' } |
    Select-Object -First 1

if (-not $codexProcess -or -not $codexProcess.Path) {
    throw 'The Codex desktop process was not found. Open Codex and run this script again.'
}

$codexExe = $codexProcess.Path
Write-Host "Verified VPS exit: $exitIp" -ForegroundColor Green
Write-Host "Codex executable: $codexExe"
Write-Host ''
Write-Host 'Now close the Codex desktop app normally.' -ForegroundColor Yellow
Write-Host 'Do not reopen it from the taskbar or Start menu; this script will reopen it.' -ForegroundColor Yellow
Read-Host 'After it has fully closed, press Enter to continue'

$stillRunning = Get-Process ChatGPT -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like '*OpenAI.Codex*' }
if ($stillRunning) {
    throw 'Codex is still running. Close it normally and run the script again.'
}

$env:HTTP_PROXY = $proxyUrl
$env:HTTPS_PROXY = $proxyUrl
$env:ALL_PROXY = $proxyUrl
$env:NO_PROXY = 'localhost,127.0.0.1,::1'

Start-Process -FilePath $codexExe -ArgumentList "--proxy-server=$proxyUrl"
Write-Host "Codex started with explicit proxy $proxyUrl." -ForegroundColor Green
Write-Host 'These proxy variables apply only to the newly started Codex process.'
