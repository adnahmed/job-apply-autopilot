[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JobIdsCsv,
    [string]$Workspace = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'

# Treat an explicitly empty -Workspace exactly like an omitted one.
# This matters when callers pass an unset PowerShell variable such as -Workspace "$workspace".
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = (Get-Location).Path
}

$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$root = Join-Path $Workspace '.job-apply-autopilot'
if (-not (Test-Path -LiteralPath $root)) { throw "No job-apply-autopilot runtime at $root" }
$ids = @($JobIdsCsv.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$wanted = @{}
foreach ($id in $ids) { $wanted[$id] = $true }
$result = @{}
foreach ($id in $ids) { $result[$id] = [ordered]@{ job_id=$id; seen=$false; locations=@(); ledger_status=$null } }

$ledger = Join-Path $root 'applications.jsonl'
if (Test-Path -LiteralPath $ledger) {
    foreach ($line in Get-Content -LiteralPath $ledger) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $row = $line | ConvertFrom-Json
            $id = [string]$row.job_id
            if ($wanted.ContainsKey($id)) {
                $result[$id].seen = $true
                $result[$id].locations = @($result[$id].locations) + 'ledger'
                $result[$id].ledger_status = [string]$row.status
            }
        } catch {}
    }
}
foreach ($kind in @('queue','generated')) {
    $dir = Join-Path $root $kind
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($child in Get-ChildItem -LiteralPath $dir -Directory) {
        $id = $child.Name.Split('-')[0]
        if ($wanted.ContainsKey($id)) {
            $result[$id].seen = $true
            $result[$id].locations = @($result[$id].locations) + $kind
        }
    }
}
@($ids | ForEach-Object { $result[$_] }) | ConvertTo-Json -Depth 5
