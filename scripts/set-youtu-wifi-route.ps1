[CmdletBinding()]
param(
    [string]$WifiAlias = 'WLAN',
    [string[]]$NodeIp,
    [int]$NodePort,
    [string]$VpsHost,
    [switch]$NoApply
)

$ErrorActionPreference = 'Stop'

function Test-PublicIPv4 {
    param([string]$Address)

    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$parsed)) { return $false }
    $bytes = $parsed.GetAddressBytes()
    if ($bytes.Length -ne 4) { return $false }
    if ($bytes[0] -eq 10) { return $false }
    if ($bytes[0] -eq 127) { return $false }
    if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { return $false }
    if ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) { return $false }
    if ($bytes[0] -eq 192 -and $bytes[1] -eq 168) { return $false }
    if ($bytes[0] -ge 224) { return $false }
    return $true
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host '=== YouTu Wi-Fi route helper ===' -ForegroundColor Cyan

$wifi = Get-NetIPConfiguration -InterfaceAlias $WifiAlias -ErrorAction Stop
$wifiIp = @($wifi.IPv4Address | Select-Object -ExpandProperty IPAddress)[0]
$wifiGateway = @($wifi.IPv4DefaultGateway | Select-Object -ExpandProperty NextHop)[0]
$wifiIndex = $wifi.InterfaceIndex

if (-not $wifiIp -or -not $wifiGateway) {
    throw "Interface '$WifiAlias' has no IPv4 address or default gateway. Connect to the phone Wi-Fi hotspot first."
}

Write-Host "Wi-Fi alias  : $WifiAlias"
Write-Host "IfIndex      : $wifiIndex"
Write-Host "Local IPv4   : $wifiIp"
Write-Host "Wi-Fi gateway: $wifiGateway"

$detectedPort = $NodePort
$candidateRows = @()

if (-not $NodeIp) {
    # YouTu may run directly as YouTuCore, or through Clash Verge's Mihomo core.
    $processIds = @(Get-Process YouTuCore, YouTu, verge-mihomo, clash-verge -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
    if ($processIds.Count -eq 0) {
        throw 'YouTu/YouTuCore or Clash Verge is not running. Start the client and connect a node first.'
    }

    $connections = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Where-Object {
            $processIds -contains $_.OwningProcess -and
            (Test-PublicIPv4 $_.RemoteAddress)
        })

    $isClashCore = @(Get-Process verge-mihomo, clash-verge -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id |
        Where-Object { $processIds -contains $_ }).Count -gt 0

    if ($detectedPort -gt 0) {
        $nodeConnections = @($connections | Where-Object { $_.RemotePort -eq $detectedPort })
    } elseif ($isClashCore) {
        # Mihomo subscription nodes commonly use TCP/443. Exclude the VPS
        # endpoint so its outer connection can keep using the wired route.
        $vpsIps = @()
        if ($VpsHost) {
            $vpsIps = @(Resolve-DnsName $VpsHost -Type A -ErrorAction SilentlyContinue |
                Where-Object { $_.Type -eq 'A' -and $_.IPAddress } |
                Select-Object -ExpandProperty IPAddress)
        }
        $nodeConnections = @($connections |
            Where-Object { $_.RemotePort -eq 443 -and $_.RemoteAddress -notin $vpsIps })
    } else {
        $commonPorts = @(53, 80, 123, 443, 853)
        $portGroups = @($connections |
            Where-Object { $_.RemotePort -notin $commonPorts } |
            Group-Object RemotePort |
            Sort-Object Count -Descending)

        $eligiblePorts = @($portGroups |
            Where-Object { $_.Count -ge 2 } |
            Select-Object -First 8 |
            ForEach-Object { [int]$_.Name })

        if ($eligiblePorts.Count -eq 0) {
            throw 'Cannot identify the node port safely. Generate proxy traffic or pass -NodePort.'
        }

        $nodeConnections = @($connections | Where-Object { $_.RemotePort -in $eligiblePorts })
    }

    $candidateRows = @($nodeConnections |
        Group-Object RemoteAddress |
        ForEach-Object {
            [pscustomobject]@{
                NodeIp = $_.Name
                NodePort = (($_.Group.RemotePort | Sort-Object -Unique) -join ',')
                Connections = $_.Count
                CurrentLocalAddresses = (($_.Group.LocalAddress | Sort-Object -Unique) -join ',')
            }
        } |
        Sort-Object Connections -Descending)

    if ($candidateRows.Count -eq 0) {
        throw 'No eligible YouTu node connection was found. Generate proxy traffic and retry.'
    }
    if ($candidateRows.Count -gt 12) {
        throw "Found $($candidateRows.Count) candidate IPs. Pass -NodePort or -NodeIp to avoid changing the wrong route."
    }
    $NodeIp = @($candidateRows.NodeIp)
} else {
    foreach ($address in $NodeIp) {
        if (-not (Test-PublicIPv4 $address)) {
            throw "'$address' is not an accepted public IPv4 address."
        }
    }

    $candidateRows = @($NodeIp | ForEach-Object {
        [pscustomobject]@{
            NodeIp = $_
            NodePort = $(if ($detectedPort -gt 0) { $detectedPort } else { 'not specified' })
            Connections = 'manual'
            CurrentLocalAddresses = '-'
        }
    })
}

Write-Host ''
Write-Host 'Detected candidate nodes:' -ForegroundColor Cyan
$candidateRows | Format-Table -AutoSize

if ($NoApply) {
    Write-Host 'NoApply is enabled. No route was changed.' -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Administrator)) {
    throw 'Administrator permission is required. Reopen PowerShell as Administrator.'
}

foreach ($address in $NodeIp) {
    $prefix = "$address/32"
    $correctRoute = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $prefix -ErrorAction SilentlyContinue |
        Where-Object {
            $_.InterfaceIndex -eq $wifiIndex -and
            $_.NextHop -eq $wifiGateway
        })

    if ($correctRoute.Count -gt 0) {
        Write-Host "Correct route already exists: $address -> $wifiGateway (if $wifiIndex)" -ForegroundColor Green
        continue
    }

    # The route may not exist yet; suppress the expected "element not found"
    # message so strict PowerShell error handling does not abort the script.
    & cmd.exe /c "route.exe delete $address >nul 2>&1"
    & route.exe -p add $address mask 255.255.255.255 $wifiGateway if $wifiIndex metric 1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to add route: $address -> $wifiGateway (if $wifiIndex)"
    }
    Write-Host "Added persistent route: $address -> $wifiGateway (if $wifiIndex)" -ForegroundColor Green
}

Write-Host ''
Write-Host '=== Current node routes ===' -ForegroundColor Cyan
foreach ($address in $NodeIp) {
    Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "$address/32" -ErrorAction SilentlyContinue |
        Select-Object DestinationPrefix, NextHop, InterfaceAlias, InterfaceIndex, RouteMetric |
        Format-Table -AutoSize
}

Write-Host 'Done. Disconnect and reconnect YouTu, then verify that LocalAddress is the Wi-Fi address.' -ForegroundColor Yellow
