[CmdletBinding(DefaultParameterSetName='ByPath')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='ByPath')][string]$WorkItemDir,
    [Parameter(Mandatory=$true,ParameterSetName='ById')][string]$JobId,
    [ValidateSet('ai','backend')][string]$Canonical = 'backend',
    [string]$Workspace = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Write-JsonAtomic([string]$Path, $Value) {
    $temp = "$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temp -Encoding UTF8
        [IO.File]::Move($temp, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Copy-IfGeneratedArtifactInvalid([string]$Source, [string]$Destination, [scriptblock]$Validator) {
    $valid = $false
    if (Test-Path -LiteralPath $Destination) {
        try { $valid = [bool](& $Validator $Destination) } catch { $valid = $false }
    }
    if (-not $valid) { Copy-Item -LiteralPath $Source -Destination $Destination -Force }
}

if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = (Get-Location).Path }
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$queueRoot = Join-Path $Workspace '.job-apply-autopilot\queue'
$generatedRoot = Join-Path $Workspace '.job-apply-autopilot\generated'

if ($PSCmdlet.ParameterSetName -eq 'ById') {
    $matches = @(Get-ChildItem -LiteralPath $queueRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$JobId-*" })
    if ($matches.Count -ne 1) { throw "Could not resolve exactly one queue work item for JobId $JobId." }
    $WorkItemDir = $matches[0].FullName
}
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path

$jobPath = Join-Path $WorkItemDir 'job.json'
$assessmentPath = Join-Path $WorkItemDir 'assessment.json'
$fitPath = Join-Path $WorkItemDir 'fit-map.json'
$sourcePath = Join-Path $WorkItemDir 'source.md'
foreach ($path in @($jobPath,$assessmentPath,$fitPath,$sourcePath)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing work-item artifact: $path" }
}

$lock = $null
try {
    try { $lock = [IO.File]::Open((Join-Path $WorkItemDir '.work-item.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { throw 'Work-item transition is busy; rerun session state.' }

    $job = Get-Content -LiteralPath $jobPath -Raw | ConvertFrom-Json
    $assessment = Get-Content -LiteralPath $assessmentPath -Raw | ConvertFrom-Json
    $fit = Get-Content -LiteralPath $fitPath -Raw | ConvertFrom-Json
    $resolvedJobId = [string]$job.job_id
    if ([string]::IsNullOrWhiteSpace($resolvedJobId)) { throw 'job.json has no job_id.' }
    if ($assessment.status -ne 'passed') { throw 'Work item assessment is not passed.' }
    foreach ($gate in @('integrity','eligibility','role_family','mandatory_requirements','truth_feasibility')) {
        if (-not [bool]$assessment.hard_gates.$gate) { throw "Work item hard gate not passed: $gate" }
    }
    if ($fit.status -notin @('complete','passed') -or $null -eq $fit.score) { throw 'Work item fit-map is incomplete.' }

    $generatedMatches = @()
    if (Test-Path -LiteralPath $generatedRoot) {
        $generatedMatches = @(Get-ChildItem -LiteralPath $generatedRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
            $candidate = Read-JsonSafe (Join-Path $_.FullName 'job.json')
            $candidate -and [string]$candidate.job_id -eq $resolvedJobId
        })
    }
    if ($generatedMatches.Count -gt 1) { throw "Multiple generated directories exist for job $resolvedJobId." }

    if ($generatedMatches.Count -eq 1) {
        $generatedDir = $generatedMatches[0].FullName
        $generatedJob = Read-JsonSafe (Join-Path $generatedDir 'job.json')
        if ([string]$generatedJob.canonical -ne $Canonical) { throw "Existing generated directory uses canonical '$($generatedJob.canonical)', not '$Canonical'." }
        $texPath = Join-Path $generatedDir 'resume.tex'
        $canonicalSourcePath = Join-Path $generatedDir 'canonical-source.tex'
        $tailoringPath = Join-Path $generatedDir 'tailoring-audit.json'
        foreach ($required in @($texPath,$canonicalSourcePath,$tailoringPath)) {
            if (-not (Test-Path -LiteralPath $required)) { throw "Existing generated directory is incomplete: $required" }
        }
        if ([string]::IsNullOrWhiteSpace([string]$generatedJob.canonical_sha256)) { throw 'Existing generated directory has no canonical hash.' }
        $canonicalHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $canonicalSourcePath).Hash.ToLowerInvariant()
        if ($canonicalHash -ne [string]$generatedJob.canonical_sha256) { throw 'Existing generated canonical source does not match its recorded hash.' }
        $tailoring = Read-JsonSafe $tailoringPath
        if (-not $tailoring -or [string]$tailoring.job_id -ne $resolvedJobId) { throw 'Existing generated tailoring audit is invalid or belongs to another job.' }
    } else {
        $scaffold = Join-Path $PSScriptRoot 'scaffold-resume.ps1'
        $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
        $texPath = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $scaffold -JobId $resolvedJobId -Company ([string]$job.company) -Title ([string]$job.title) -Canonical $Canonical -JobUrl ([string]$job.job_url) -Location ([string]$job.location) -Workspace $Workspace | Select-Object -Last 1
        if ([string]::IsNullOrWhiteSpace([string]$texPath)) { throw 'Resume scaffold did not return a path.' }
        $generatedDir = Split-Path -Parent ([string]$texPath)
        $generatedJob = Read-JsonSafe (Join-Path $generatedDir 'job.json')
    }

    $generatedJobPath = Join-Path $generatedDir 'job.json'
    $metadataChanged = $false
    foreach ($name in @('source','discovery_lane','search_query')) {
        if ($job.PSObject.Properties.Name -contains $name -and [string]$generatedJob.$name -ne [string]$job.$name) {
            $generatedJob | Add-Member -NotePropertyName $name -NotePropertyValue $job.$name -Force
            $metadataChanged = $true
        }
    }
    $ledgerPath = Join-Path (Join-Path $Workspace '.job-apply-autopilot') 'applications.jsonl'
    $lastLedgerStatus = $null
    if (Test-Path -LiteralPath $ledgerPath) {
        foreach ($line in Get-Content -LiteralPath $ledgerPath) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                if ([string]$row.job_id -eq $resolvedJobId) { $lastLedgerStatus = [string]$row.status }
            } catch {}
        }
    }
    $technicalPriorSkips = @('skipped-low-fit','skipped-mandatory-gate','skipped-stack-mismatch','skipped-role-family')
    if ([string]$assessment.policy_version -in @('5.10','5.11','5.12','5.13','5.14','5.15','6.0','6.1') -and $lastLedgerStatus -in $technicalPriorSkips -and -not [bool]$generatedJob.allow_after_prior_skip) {
        $generatedJob | Add-Member -NotePropertyName 'allow_after_prior_skip' -NotePropertyValue $true -Force
        $generatedJob | Add-Member -NotePropertyName 'prior_ledger_status' -NotePropertyValue $lastLedgerStatus -Force
        $metadataChanged = $true
    }
    if ($metadataChanged) { Write-JsonAtomic $generatedJobPath $generatedJob }

    Copy-IfGeneratedArtifactInvalid $assessmentPath (Join-Path $generatedDir 'assessment.json') { param($p) $value = Read-JsonSafe $p; $value -and [string]$value.job_id -eq $resolvedJobId -and [string]$value.status -eq 'passed' }
    Copy-IfGeneratedArtifactInvalid $fitPath (Join-Path $generatedDir 'fit-map.json') { param($p) $value = Read-JsonSafe $p; $value -and [string]$value.job_id -eq $resolvedJobId -and [string]$value.status -in @('complete','passed') }
    Copy-IfGeneratedArtifactInvalid $sourcePath (Join-Path $generatedDir 'source.md') { param($p) $text = Get-Content -LiteralPath $p -Raw; $text.Trim().Length -ge 80 -and $text -notmatch 'Coordinator:\s*replace this placeholder' }
    foreach ($name in @('eligibility-research.json','candidate-evidence-research.json','source-metadata.json','application-route.json','application-answer-plan.json')) {
        $source = Join-Path $WorkItemDir $name
        $destination = Join-Path $generatedDir $name
        if ((Test-Path -LiteralPath $source) -and -not (Test-Path -LiteralPath $destination)) { Copy-Item -LiteralPath $source -Destination $destination }
    }

    $recoverablePath = Join-Path $WorkItemDir 'recoverable-error.json'
    if (Test-Path -LiteralPath $recoverablePath) { Remove-Item -LiteralPath $recoverablePath -Force }
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
}

& (Join-Path $PSScriptRoot 'claim-action.ps1') -Action ClearStage -Scope WorkItem -Stage 'coordinator_adjudication_pending' -WorkItemDir $WorkItemDir -Workspace $Workspace | Out-Null
Write-Output $generatedDir
