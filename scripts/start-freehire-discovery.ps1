[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Workspace,
    [int]$TargetNew = 8,
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml')
)

$ErrorActionPreference = 'Stop'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
if (-not (Test-Path -LiteralPath (Join-Path $Workspace '.job-apply-autopilot'))) { throw "No job-apply-autopilot runtime in $Workspace" }

$claimScript = Join-Path $PSScriptRoot 'claim-action.ps1'
$claim = (& $claimScript -Action Acquire -Scope Discovery -Stage discovery -DiscoverySource freehire -Workspace $Workspace -LeaseMinutes 15 | Select-Object -Last 1) | ConvertFrom-Json
if (-not $claim -or [string]$claim.status -ne 'acquired') {
    Write-Output ([ordered]@{ status='busy'; source='freehire'; message='FreeHire discovery claim not acquired' } | ConvertTo-Json -Compress -Depth 5)
    exit 0
}
$ownerId = $claim.owner_id

$discoverScript = Join-Path $PSScriptRoot 'discover-freehire.ps1'
if (-not (Test-Path -LiteralPath $discoverScript)) {
    & $claimScript -Action Release -Scope Discovery -Stage discovery -DiscoverySource freehire -Workspace $Workspace -OwnerId $ownerId | Out-Null
    throw "discover-freehire.ps1 not found at $discoverScript"
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'pwsh'
$psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$discoverScript`" -Workspace `"$Workspace`" -TargetNew $TargetNew -ProfilePath `"$ProfilePath`" -ClaimOwnerId $ownerId"
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

$process = [System.Diagnostics.Process]::Start($psi)
if (-not $process) {
    & $claimScript -Action Release -Scope Discovery -Stage discovery -DiscoverySource freehire -Workspace $Workspace -OwnerId $ownerId | Out-Null
    throw "Failed to start discover-freehire.ps1 process"
}

[ordered]@{
    status = 'started'
    source = 'freehire'
    owner_id = $ownerId
    pid = $process.Id
} | ConvertTo-Json -Compress -Depth 5 | Write-Output