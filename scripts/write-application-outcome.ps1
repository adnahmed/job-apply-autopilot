[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][ValidateSet('blocked-auth','blocked-security','blocked-automation','blocked-domain-circuit-breaker','blocked-identity-mismatch','blocked-work-auth','blocked-technical','blocked-verification-unresolved','skipped-closed','skipped-ineligible','skipped-duplicate','skipped-job-quality','failed')][string]$Status,
    [Parameter(Mandatory=$true)][string]$Blocker,
    [ValidateSet('external-ats','email','linkedin-easy-apply','external')][string]$ApplyMethod = 'external-ats',
    [string]$Target = ''
)

$ErrorActionPreference = 'Stop'

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Write-JsonAtomic([string]$Path, $Value) {
    $temp = "$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
        [IO.File]::Move($temp, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Emit($Value) { $Value | ConvertTo-Json -Depth 8 -Compress | Write-Output }

$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
$jobPath = Join-Path $WorkItemDir 'job.json'
$resultPath = Join-Path $WorkItemDir 'application-result.json'
if (-not (Test-Path -LiteralPath $jobPath)) { throw "Missing job.json in $WorkItemDir" }
if ([string]::IsNullOrWhiteSpace($Blocker)) { throw 'Blocker must be non-empty.' }

$lock = $null
try {
    try { $lock = [IO.File]::Open((Join-Path $WorkItemDir '.work-item.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
    catch {
        Emit ([ordered]@{ status='busy'; outcome_status=$Status; written=$false })
        exit 0
    }

    $job = Get-Content -LiteralPath $jobPath -Raw | ConvertFrom-Json
    $existing = Read-JsonSafe $resultPath
    if ($existing -and [string]$existing.status -notlike 'handoff-*') {
        Emit ([ordered]@{ status='already-written'; job_id=[string]$job.job_id; outcome_status=[string]$existing.status; submitted=[bool]$existing.submitted; written=$false })
        exit 0
    }

    $sendState = Read-JsonSafe (Join-Path $WorkItemDir 'application-send-state.json')
    $artifact = Read-JsonSafe (Join-Path $WorkItemDir 'resume-artifact.json')
    $result = [ordered]@{
        job_id = [string]$job.job_id
        company = [string]$job.company
        title = [string]$job.title
        apply_method = $ApplyMethod
        target = if ($Target) { $Target } elseif ($sendState) { [string]$sendState.target } else { '' }
        status = $Status
        submitted = $false
        confirmation = $null
        resume_filename = if ($artifact) { [string]$artifact.filename } else { $null }
        reservation_id = if ($sendState) { [string]$sendState.reservation_id } else { $null }
        submitted_at = $null
        blocker = $Blocker.Trim()
        completed_at = [DateTimeOffset]::UtcNow.ToString('o')
    }
    Write-JsonAtomic $resultPath $result
    $recoverablePath = Join-Path $WorkItemDir 'recoverable-error.json'
    if (Test-Path -LiteralPath $recoverablePath) { Remove-Item -LiteralPath $recoverablePath -Force }
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
}

$runtimeRoot = Split-Path -Parent (Split-Path -Parent $WorkItemDir)
$workspace = Split-Path -Parent $runtimeRoot
foreach ($stage in @('application_ready','application_resume','application_verification','email_application_ready','application_outcome_repair')) {
    & (Join-Path $PSScriptRoot 'claim-action.ps1') -Action ClearStage -Scope WorkItem -Stage $stage -WorkItemDir $WorkItemDir -Workspace $workspace | Out-Null
}
Emit ([ordered]@{ status='written'; job_id=[string]$job.job_id; outcome_status=$Status; submitted=$false; result=$resultPath; written=$true })
