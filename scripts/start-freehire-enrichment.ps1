[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][string]$Workspace,
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml')
)

$ErrorActionPreference = 'Stop'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path

if (-not (Test-Path -LiteralPath (Join-Path $Workspace '.job-apply-autopilot'))) {
    Write-Output ([ordered]@{ status='failed'; work_item=$WorkItemDir; error='No job-apply-autopilot runtime in workspace' } | ConvertTo-Json -Compress -Depth 5)
    exit 0
}
if (-not (Test-Path -LiteralPath (Join-Path $WorkItemDir 'job.json'))) {
    Write-Output ([ordered]@{ status='failed'; work_item=$WorkItemDir; error='Work item directory missing job.json' } | ConvertTo-Json -Compress -Depth 5)
    exit 0
}

$enrichScript = Join-Path $PSScriptRoot 'enrich-freehire-workitem.ps1'
if (-not (Test-Path -LiteralPath $enrichScript)) {
    Write-Output ([ordered]@{ status='failed'; work_item=$WorkItemDir; error='enrich-freehire-workitem.ps1 not found' } | ConvertTo-Json -Compress -Depth 5)
    exit 0
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'pwsh'
$psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$enrichScript`" -WorkItemDir `"$WorkItemDir`" -Workspace `"$Workspace`" -ProfilePath `"$ProfilePath`""
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

try {
    $process = [System.Diagnostics.Process]::Start($psi)
    if (-not $process) {
        Write-Output ([ordered]@{ status='failed'; work_item=$WorkItemDir; error='Failed to start enrichment process' } | ConvertTo-Json -Compress -Depth 5)
        exit 0
    }
    Write-Output ([ordered]@{ status='started'; work_item=$WorkItemDir; pid=$process.Id } | ConvertTo-Json -Compress -Depth 5)
} catch {
    Write-Output ([ordered]@{ status='failed'; work_item=$WorkItemDir; error=$_.Exception.Message } | ConvertTo-Json -Compress -Depth 5)
}