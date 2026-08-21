[CmdletBinding(DefaultParameterSetName='ByPath')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='ByPath')][string]$WorkItemDir,
    [Parameter(Mandatory=$true,ParameterSetName='ById')][string]$JobId,
    [ValidateSet('ai','backend')][string]$Canonical = 'backend',
    [string]$Workspace = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

# Treat an explicitly empty -Workspace exactly like an omitted one.
# This matters when callers pass an unset PowerShell variable such as -Workspace "$workspace".
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = (Get-Location).Path
}

$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
if ($PSCmdlet.ParameterSetName -eq 'ById') {
    $queueRoot = Join-Path $Workspace '.job-apply-autopilot\queue'
    $matches = @(Get-ChildItem -LiteralPath $queueRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$JobId-*" })
    if ($matches.Count -ne 1) { throw "Could not resolve exactly one queue work item for JobId $JobId." }
    $WorkItemDir = $matches[0].FullName
}
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
$skillRoot = Split-Path -Parent $PSScriptRoot

$jobPath = Join-Path $WorkItemDir 'job.json'
$assessmentPath = Join-Path $WorkItemDir 'assessment.json'
$fitPath = Join-Path $WorkItemDir 'fit-map.json'
$sourcePath = Join-Path $WorkItemDir 'source.md'

foreach ($p in @($jobPath,$assessmentPath,$fitPath,$sourcePath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing work-item artifact: $p" }
}

$job = Get-Content -LiteralPath $jobPath -Raw | ConvertFrom-Json
$assessment = Get-Content -LiteralPath $assessmentPath -Raw | ConvertFrom-Json
$fit = Get-Content -LiteralPath $fitPath -Raw | ConvertFrom-Json

if ($assessment.status -ne 'passed') { throw 'Work item assessment is not passed.' }
foreach ($gate in @('integrity','eligibility','role_family','mandatory_requirements','truth_feasibility')) {
    if (-not [bool]$assessment.hard_gates.$gate) { throw "Work item hard gate not passed: $gate" }
}
if ($fit.status -notin @('complete','passed') -or $null -eq $fit.score) { throw 'Work item fit-map is incomplete.' }

$scaffold = Join-Path $skillRoot 'scripts\scaffold-resume.ps1'
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$texPath = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $scaffold -JobId ([string]$job.job_id) -Company ([string]$job.company) -Title ([string]$job.title) -Canonical $Canonical -JobUrl ([string]$job.job_url) -Location ([string]$job.location) -Workspace $Workspace
if (-not $texPath) { throw 'Resume scaffold did not return a path.' }
$generatedDir = Split-Path -Parent ([string]$texPath)

# Carry discovery/source metadata forward so campaign analytics survives promotion.
$generatedJobPath = Join-Path $generatedDir 'job.json'
if (Test-Path -LiteralPath $generatedJobPath) {
    $generatedJob = Get-Content -LiteralPath $generatedJobPath -Raw | ConvertFrom-Json
    foreach ($name in @('source','discovery_lane','search_query')) {
        if ($job.PSObject.Properties.Name -contains $name) {
            $generatedJob | Add-Member -NotePropertyName $name -NotePropertyValue $job.$name -Force
        }
    }
    # A deliberately reassessed technical/fit skip may legitimately be reopened.
    # Carry an override only for those non-submission technical skip statuses so a restart
    # after promotion does not hide the newly approved generated job.
    $ledgerPath = Join-Path (Join-Path $Workspace '.job-apply-autopilot') 'applications.jsonl'
    $lastLedgerStatus = $null
    if (Test-Path -LiteralPath $ledgerPath) {
        foreach ($line in Get-Content -LiteralPath $ledgerPath) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                if ([string]$row.job_id -eq [string]$job.job_id) { $lastLedgerStatus = [string]$row.status }
            } catch {}
        }
    }
    $technicalPriorSkips = @('skipped-low-fit','skipped-mandatory-gate','skipped-stack-mismatch','skipped-role-family')
    if (($assessment.PSObject.Properties.Name -contains 'policy_version') -and [string]$assessment.policy_version -in @('5.10','5.11','5.12') -and $lastLedgerStatus -in $technicalPriorSkips) {
        $generatedJob | Add-Member -NotePropertyName 'allow_after_prior_skip' -NotePropertyValue $true -Force
        $generatedJob | Add-Member -NotePropertyName 'prior_ledger_status' -NotePropertyValue $lastLedgerStatus -Force
    }
    $generatedJob | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $generatedJobPath -Encoding UTF8
}

Copy-Item -LiteralPath $assessmentPath -Destination (Join-Path $generatedDir 'assessment.json') -Force
Copy-Item -LiteralPath $fitPath -Destination (Join-Path $generatedDir 'fit-map.json') -Force
Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $generatedDir 'source.md') -Force
$eligibilityResearch = Join-Path $WorkItemDir 'eligibility-research.json'
if (Test-Path -LiteralPath $eligibilityResearch) {
    Copy-Item -LiteralPath $eligibilityResearch -Destination (Join-Path $generatedDir 'eligibility-research.json') -Force
}
$candidateEvidenceResearch = Join-Path $WorkItemDir 'candidate-evidence-research.json'
if (Test-Path -LiteralPath $candidateEvidenceResearch) {
    Copy-Item -LiteralPath $candidateEvidenceResearch -Destination (Join-Path $generatedDir 'candidate-evidence-research.json') -Force
}

Write-Output $generatedDir
