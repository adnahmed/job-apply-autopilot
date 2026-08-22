[CmdletBinding(DefaultParameterSetName='Directory')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Directory')][string]$WorkItemDir,
    [Parameter(Mandatory=$true,ParameterSetName='Identity')][string]$JobId,
    [Parameter(ParameterSetName='Identity')][ValidateSet('auto','queue','generated')][string]$Kind = 'auto',
    [Parameter(ParameterSetName='Identity')][string]$Workspace = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
if ($PSCmdlet.ParameterSetName -eq 'Identity') {
    $Workspace = (Resolve-Path -LiteralPath $Workspace).Path
    $runtime = Join-Path $Workspace '.job-apply-autopilot'
    $roots = if ($Kind -eq 'auto') { @('generated','queue') } else { @($Kind) }
    $matches = [Collections.Generic.List[string]]::new()
    foreach ($rootName in $roots) {
        $rootPath = Join-Path $runtime $rootName
        if (-not (Test-Path -LiteralPath $rootPath)) { continue }
        foreach ($dir in Get-ChildItem -LiteralPath $rootPath -Directory -ErrorAction SilentlyContinue) {
            $jobPath = Join-Path $dir.FullName 'job.json'
            if (-not (Test-Path -LiteralPath $jobPath)) { continue }
            try {
                $candidate = Get-Content -LiteralPath $jobPath -Raw | ConvertFrom-Json
                if ([string]$candidate.job_id -eq $JobId) { $matches.Add($dir.FullName) }
            } catch {}
        }
        if ($matches.Count -gt 0 -and $Kind -eq 'auto') { break }
    }
    if ($matches.Count -ne 1) { throw "Expected one $Kind work item for job '$JobId', found $($matches.Count)." }
    $WorkItemDir = $matches[0]
}
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
    version = 2
    workspace = $workspace
    runtime_root = $runtimeRoot
    work_item = $WorkItemDir
    paths = $paths
} | ConvertTo-Json -Depth 6 -Compress
