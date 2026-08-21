[CmdletBinding()]
param(
    [string]$HostName = '127.0.0.1',
    [int]$McpPort = 9010,
    [int]$CdpPort = 9110,
    [int]$TimeoutMilliseconds = 750
)

$ErrorActionPreference = 'Stop'

function Test-TcpPort([string]$Computer, [int]$Port, [int]$Timeout) {
    $targets = if ($Computer -in @('localhost','::1')) { @('127.0.0.1','::1') } else { @($Computer) }
    foreach ($target in $targets) {
        $client = [Net.Sockets.TcpClient]::new()
        try {
            $task = $client.ConnectAsync($target, $Port)
            if ($task.Wait($Timeout) -and $client.Connected) { return $true }
        } catch {
        } finally {
            $client.Dispose()
        }
    }
    return $false
}

$mcp = Test-TcpPort $HostName $McpPort $TimeoutMilliseconds
$cdp = Test-TcpPort $HostName $CdpPort $TimeoutMilliseconds
$healthy = ($mcp -and $cdp)
$reason = if (-not $mcp) { 'mcp-server-unavailable' } elseif (-not $cdp) { 'browser-cdp-unavailable' } else { 'healthy' }

[ordered]@{
    healthy = $healthy
    reason = $reason
    host = $HostName
    mcp_port = $McpPort
    mcp_listening = $mcp
    cdp_port = $CdpPort
    cdp_listening = $cdp
    checked_at = [DateTimeOffset]::UtcNow.ToString('o')
} | ConvertTo-Json -Compress
