[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir
)

$ErrorActionPreference = 'Stop'
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path

$cursor = [IO.DirectoryInfo]$WorkItemDir
$runtimeRoot = $null
while ($null -ne $cursor) {
    if ($cursor.Name -eq '.job-apply-autopilot') {
        $runtimeRoot = $cursor.FullName
        break
    }
    $cursor = $cursor.Parent
}
if ([string]::IsNullOrWhiteSpace($runtimeRoot)) {
    throw "Work item is not inside a .job-apply-autopilot runtime: $WorkItemDir"
}

$workspace = Split-Path -Parent $runtimeRoot
$skillRoot = Split-Path -Parent $PSScriptRoot

function File-Entry([string]$Path) {
    return [ordered]@{
        path = $Path
        exists = Test-Path -LiteralPath $Path -PathType Leaf
    }
}

$paths = [ordered]@{
    job = File-Entry (Join-Path $WorkItemDir 'job.json')
    source = File-Entry (Join-Path $WorkItemDir 'source.md')
    source_metadata = File-Entry (Join-Path $WorkItemDir 'source-metadata.json')
    assessment = File-Entry (Join-Path $WorkItemDir 'assessment.json')
    fit_map = File-Entry (Join-Path $WorkItemDir 'fit-map.json')
    eligibility_research = File-Entry (Join-Path $WorkItemDir 'eligibility-research.json')
    candidate_research = File-Entry (Join-Path $WorkItemDir 'candidate-evidence-research.json')
    canonical_facts = File-Entry (Join-Path $skillRoot 'canonical\canonical-facts.yaml')
    canonical_source_tex = File-Entry (Join-Path $WorkItemDir 'canonical-source.tex')
    profile = File-Entry (Join-Path $skillRoot 'profile.yaml')
    candidate_evidence = File-Entry (Join-Path $runtimeRoot 'candidate-evidence.json')
    resume_artifact = File-Entry (Join-Path $WorkItemDir 'resume-artifact.json')
    resume_tex = File-Entry (Join-Path $WorkItemDir 'resume.tex')
    tailoring_audit = File-Entry (Join-Path $WorkItemDir 'tailoring-audit.json')
    application_route = File-Entry (Join-Path $WorkItemDir 'application-route.json')
    application_progress = File-Entry (Join-Path $WorkItemDir 'application-progress.json')
    application_send_state = File-Entry (Join-Path $WorkItemDir 'application-send-state.json')
    application_result = File-Entry (Join-Path $WorkItemDir 'application-result.json')
    application_answer_plan = File-Entry (Join-Path $WorkItemDir 'application-answer-plan.json')
    application_answer_bank = File-Entry (Join-Path $WorkItemDir 'application-answer-bank.json')
    application_preflight = File-Entry (Join-Path $WorkItemDir 'application-preflight.json')
}

[ordered]@{
    version = 1
    workspace = $workspace
    runtime_root = $runtimeRoot
    work_item = $WorkItemDir
    paths = $paths
} | ConvertTo-Json -Depth 6 -Compress
