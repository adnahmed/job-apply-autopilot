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
$workItemDirs = @{}
foreach ($base in @((Join-Path $root 'queue'), (Join-Path $root 'generated'))) {
    if (-not (Test-Path -LiteralPath $base)) { continue }
    Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $itemDir = $_.FullName
        $jp = Join-Path $itemDir 'job.json'
        if (Test-Path -LiteralPath $jp) {
            try {
                $j = Get-Content -LiteralPath $jp -Raw | ConvertFrom-Json
                if ($j.job_id) {
                    $jobs[[string]$j.job_id] = $j
                    $workItemDirs[[string]$j.job_id] = $itemDir
                }
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
            $titleNormalized = (($title.ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim() -replace '\s+', ' ')
            $titleKey = (($titleNormalized.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | Sort-Object) -join ' ')
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

$assessmentStates = [Collections.Generic.List[string]]::new()
$routeStates = [Collections.Generic.List[string]]::new()
$preflightStates = [Collections.Generic.List[string]]::new()
$recoverableAttempts = [Collections.Generic.List[int]]::new()
$answerCalls = 0
$answerQuestions = 0
$answerRepeated = 0
$answerLooped = 0
foreach ($dir in @($workItemDirs.Values | Sort-Object -Unique)) {
    $assessmentPath = Join-Path $dir 'assessment.json'
    if (Test-Path -LiteralPath $assessmentPath) {
        try { $assessmentStates.Add([string](Get-Content -LiteralPath $assessmentPath -Raw | ConvertFrom-Json).status) } catch { $assessmentStates.Add('malformed') }
    }
    $routePath = Join-Path $dir 'application-route.json'
    if (Test-Path -LiteralPath $routePath) {
        try { $routeStates.Add([string](Get-Content -LiteralPath $routePath -Raw | ConvertFrom-Json).route) } catch { $routeStates.Add('malformed') }
    } else { $routeStates.Add('missing') }
    $preflightPath = Join-Path $dir 'application-preflight.json'
    if (Test-Path -LiteralPath $preflightPath) {
        try { $preflightStates.Add([string](Get-Content -LiteralPath $preflightPath -Raw | ConvertFrom-Json).status) } catch { $preflightStates.Add('malformed') }
    }
    $recoverablePath = Join-Path $dir 'recoverable-error.json'
    if (Test-Path -LiteralPath $recoverablePath) {
        try { $recoverableAttempts.Add([int](Get-Content -LiteralPath $recoverablePath -Raw | ConvertFrom-Json).attempts) } catch {}
    }
    $answerCachePath = Join-Path $dir 'answer-resolution-cache.json'
    if (Test-Path -LiteralPath $answerCachePath) {
        try {
            foreach ($entry in @((Get-Content -LiteralPath $answerCachePath -Raw | ConvertFrom-Json).entries)) {
                $count = [int]$entry.count
                $answerQuestions++
                $answerCalls += $count
                if ($count -gt 1) { $answerRepeated++ }
                if ($count -gt 2) { $answerLooped++ }
            }
        } catch {}
    }
}

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
    workflow = [ordered]@{
        work_items = $workItemDirs.Count
        assessment_statuses = @($assessmentStates | Group-Object | Sort-Object Name | ForEach-Object { [ordered]@{status=$_.Name;count=$_.Count} })
        route_statuses = @($routeStates | Group-Object | Sort-Object Name | ForEach-Object { [ordered]@{route=$_.Name;count=$_.Count} })
        preflight_statuses = @($preflightStates | Group-Object | Sort-Object Name | ForEach-Object { [ordered]@{status=$_.Name;count=$_.Count} })
        recoverable_items = $recoverableAttempts.Count
        recoverable_attempts_total = if ($recoverableAttempts.Count) { ($recoverableAttempts | Measure-Object -Sum).Sum } else { 0 }
        recoverable_attempts_max = if ($recoverableAttempts.Count) { ($recoverableAttempts | Measure-Object -Maximum).Maximum } else { 0 }
        answer_resolution = [ordered]@{
            calls = $answerCalls
            normalized_questions = $answerQuestions
            repeated_questions = $answerRepeated
            loop_guard_triggered = $answerLooped
        }
    }
}
$stats | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Output $outPath
