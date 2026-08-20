[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [ValidateSet('ai','backend')][string]$Canonical = 'backend',
    [string]$Workspace = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
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
if ($fit.status -ne 'complete' -or $null -eq $fit.score) { throw 'Work item fit-map is incomplete.' }

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
    $generatedJob | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $generatedJobPath -Encoding UTF8
}

Copy-Item -LiteralPath $assessmentPath -Destination (Join-Path $generatedDir 'assessment.json') -Force
Copy-Item -LiteralPath $fitPath -Destination (Join-Path $generatedDir 'fit-map.json') -Force
Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $generatedDir 'source.md') -Force
$eligibilityResearch = Join-Path $WorkItemDir 'eligibility-research.json'
if (Test-Path -LiteralPath $eligibilityResearch) {
    Copy-Item -LiteralPath $eligibilityResearch -Destination (Join-Path $generatedDir 'eligibility-research.json') -Force
}

Write-Output $generatedDir
