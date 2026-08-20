[CmdletBinding()]
param([string]$Workspace = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
$root = Join-Path $Workspace '.job-apply-autopilot'
$appLog = Join-Path $root 'applications.jsonl'
$outPath = Join-Path $root 'campaign-stats.json'

$jobs = @{}
foreach ($base in @((Join-Path $root 'queue'), (Join-Path $root 'generated'))) {
    if (-not (Test-Path -LiteralPath $base)) { continue }
    Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $jp = Join-Path $_.FullName 'job.json'
        if (Test-Path -LiteralPath $jp) {
            try {
                $j = Get-Content -LiteralPath $jp -Raw | ConvertFrom-Json
                if ($j.job_id) { $jobs[[string]$j.job_id] = $j }
            } catch { }
        }
    }
}

$rows = @()
if (Test-Path -LiteralPath $appLog) {
    Get-Content -LiteralPath $appLog | ForEach-Object {
        $line = $_.Trim()
        if ($line) {
        try {
            $r = $line | ConvertFrom-Json
            $job = if ($r.job_id -and $jobs.ContainsKey([string]$r.job_id)) { $jobs[[string]$r.job_id] } else { $null }
            $lane = if ($r.discovery_lane) { [string]$r.discovery_lane } elseif ($job -and $job.discovery_lane) { [string]$job.discovery_lane } else { 'unknown' }
            $source = if ($r.source) { [string]$r.source } elseif ($job -and $job.source) { [string]$job.source } else { 'unknown' }
            $status = [string]$r.status
            $bucket = if ($status -eq 'submitted') { 'submitted' } elseif ($status -like 'blocked-*' -or $status -like '*blocked*' -or $status -eq 'failed') { 'blocked' } else { 'skipped' }
            $rows += [pscustomobject]@{ job_id=[string]$r.job_id; status=$status; bucket=$bucket; source=$source; lane=$lane }
        } catch { }
        }
    }
}

function Summarize($items, [string]$property) {
    $out = @()
    foreach ($g in ($items | Group-Object -Property $property | Sort-Object Name)) {
        $submitted = @($g.Group | Where-Object bucket -eq 'submitted').Count
        $blocked = @($g.Group | Where-Object bucket -eq 'blocked').Count
        $skipped = @($g.Group | Where-Object bucket -eq 'skipped').Count
        $count = $g.Count
        $out += [ordered]@{
            name = $g.Name
            total = $count
            submitted = $submitted
            blocked = $blocked
            skipped = $skipped
            submission_rate = if ($count) { [math]::Round($submitted / $count, 4) } else { 0 }
        }
    }
    return $out
}

$total = @($rows).Count
$submittedTotal = @($rows | Where-Object bucket -eq 'submitted').Count
$stats = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    total_decisions = $total
    submitted = $submittedTotal
    blocked = @($rows | Where-Object bucket -eq 'blocked').Count
    skipped = @($rows | Where-Object bucket -eq 'skipped').Count
    submission_rate = if ($total) { [math]::Round($submittedTotal / $total, 4) } else { 0 }
    statuses = @($rows | Group-Object status | Sort-Object Name | ForEach-Object { [ordered]@{ status=$_.Name; count=$_.Count } })
    by_source = @(Summarize $rows 'source')
    by_discovery_lane = @(Summarize $rows 'lane')
}
$stats | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Output $outPath
