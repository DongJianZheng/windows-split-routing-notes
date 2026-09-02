param(
    [int]$ProxyPort = 7897,
    [string]$NodeIp,
    [int]$NodePort,
    [string]$CompanyDomain,
    [int]$CompanyPort,
    [string]$CompanyDns
)

$ErrorActionPreference = 'SilentlyContinue'

Write-Host '=== Active default gateways ==='
Get-NetIPConfiguration |
    Where-Object { $_.IPv4DefaultGateway } |
    Select-Object InterfaceAlias, InterfaceIndex, IPv4Address, IPv4DefaultGateway, DNSServer |
    Format-List

Write-Host '=== Local proxy port ==='
Test-NetConnection 127.0.0.1 -Port $ProxyPort |
    Select-Object ComputerName, RemotePort, TcpTestSucceeded |
    Format-List

if ($NodeIp) {
    Write-Host '=== Node host route ==='
    Get-NetRoute -AddressFamily IPv4 |
        Where-Object { $_.DestinationPrefix -eq "$NodeIp/32" } |
        Select-Object DestinationPrefix, NextHop, InterfaceAlias, InterfaceIndex, RouteMetric |
        Format-Table -AutoSize

    if ($NodePort -gt 0) {
        Write-Host '=== Node connectivity ==='
        Test-NetConnection $NodeIp -Port $NodePort |
            Select-Object ComputerName, RemotePort, SourceAddress, TcpTestSucceeded |
            Format-List
    }
}

if ($CompanyDomain) {
    Write-Host '=== Company DNS ==='
    if ($CompanyDns) {
        Resolve-DnsName $CompanyDomain -Server $CompanyDns -Type A |
            Select-Object Name, IPAddress |
            Format-Table -AutoSize
    } else {
        Resolve-DnsName $CompanyDomain -Type A |
            Select-Object Name, IPAddress |
            Format-Table -AutoSize
    }

    if ($CompanyPort -gt 0) {
        Write-Host '=== Company service connectivity ==='
        Test-NetConnection $CompanyDomain -Port $CompanyPort |
            Select-Object ComputerName, RemotePort, SourceAddress, TcpTestSucceeded |
            Format-List
    }
}

Write-Host '=== Relevant established connections ==='
$knownProcesses = @(Get-Process YouTuCore, YouTu, v2rayN, verge-mihomo, clash-verge -ErrorAction SilentlyContinue)
$knownIds = @($knownProcesses | Select-Object -ExpandProperty Id)
Get-NetTCPConnection -State Established |
    Where-Object { $knownIds -contains $_.OwningProcess } |
    Select-Object OwningProcess, LocalAddress, LocalPort, RemoteAddress, RemotePort |
    Sort-Object OwningProcess, RemoteAddress, RemotePort |
    Format-Table -AutoSize

