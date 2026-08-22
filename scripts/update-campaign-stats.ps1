[CmdletBinding()]
param([string]$Workspace = (Get-Location).Path)

$ErrorActionPreference = 'Stop'

# Treat an explicitly empty -Workspace exactly like an omitted one.
# This matters when callers pass an unset PowerShell variable such as -Workspace "$workspace".
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = (Get-Location).Path
}

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
            $company = [string]$r.company
            $title = [string]$r.title
            $companyKey = (($company.ToLowerInvariant() -replace '&', ' and ' -replace '[^a-z0-9]+', ' ').Trim() -replace '\s+', ' ')
            do {
                $priorCompanyKey = $companyKey
                $companyKey = ($companyKey -replace '\s+(private limited|pvt ltd|pvt limited|limited|ltd|llc|incorporated|inc|corporation|corp|gmbh|plc|company|co)$', '').Trim()
            } while ($companyKey -ne $priorCompanyKey)
            $titleKey = (($title.ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim() -replace '\s+', ' ')
            $identity = if ($companyKey -and $titleKey) { "$companyKey|$titleKey" } else { "job:$([string]$r.job_id)" }
            $createdAt = if ($job -and $job.created_at) { [string]$job.created_at } else { $null }
            $durationMinutes = $null
            try { if ($createdAt -and $r.timestamp) { $durationMinutes = [math]::Round(([DateTimeOffset]::Parse([string]$r.timestamp).ToUniversalTime() - [DateTimeOffset]::Parse($createdAt).ToUniversalTime()).TotalMinutes,2) } } catch {}
            $rows += [pscustomobject]@{ job_id=[string]$r.job_id; identity=$identity; status=$status; bucket=$bucket; source=$source; lane=$lane; duration_minutes=$durationMinutes }
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
$submittedRows = @($rows | Where-Object bucket -eq 'submitted')
$submittedTotal = @($submittedRows | Group-Object identity).Count
$completedDurations = @($rows | Where-Object { $null -ne $_.duration_minutes -and $_.duration_minutes -ge 0 } | ForEach-Object { [double]$_.duration_minutes } | Sort-Object)
$submittedDurations = @($submittedRows | Where-Object { $null -ne $_.duration_minutes -and $_.duration_minutes -ge 0 } | ForEach-Object { [double]$_.duration_minutes } | Sort-Object)
function Median($Values) { $a=@($Values); if($a.Count -eq 0){return $null}; $middle=[math]::Floor($a.Count/2); if($a.Count%2){return [math]::Round([double]$a[$middle],2)}; return [math]::Round(([double]$a[$middle-1]+[double]$a[$middle])/2,2) }
$stats = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    total_decisions = $total
    submitted = $submittedTotal
    submitted_unique = $submittedTotal
    submitted_rows = $submittedRows.Count
    duplicate_submission_rows = [math]::Max(0, $submittedRows.Count - $submittedTotal)
    blocked = @($rows | Where-Object bucket -eq 'blocked').Count
    skipped = @($rows | Where-Object bucket -eq 'skipped').Count
    submission_rate = if ($total) { [math]::Round($submittedTotal / $total, 4) } else { 0 }
    median_decision_minutes = Median $completedDurations
    median_submission_minutes = Median $submittedDurations
    freehire = [ordered]@{ decisions=@($rows | Where-Object source -eq 'freehire').Count; submitted=@($submittedRows | Where-Object source -eq 'freehire').Count }
    quality_rejected = @($rows | Where-Object status -eq 'skipped-job-quality').Count
    statuses = @($rows | Group-Object status | Sort-Object Name | ForEach-Object { [ordered]@{ status=$_.Name; count=$_.Count } })
    by_source = @(Summarize $rows 'source')
    by_discovery_lane = @(Summarize $rows 'lane')
}
$stats | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Output $outPath
