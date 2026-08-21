[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('List','Reverify','ConfirmSubmitted','ConfirmAbsent','RetryApplication','Abandon')][string]$Action,
    [string]$WorkItemDir = '',
    [string]$Proof = '',
    [string]$Workspace = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Emit($Value) { $Value | ConvertTo-Json -Depth 10 -Compress | Write-Output }

function Get-SubmissionIdentity([string]$Company, [string]$Title, [string]$JobId) {
    $companyKey = (($Company.ToLowerInvariant() -replace '&', ' and ' -replace '[^a-z0-9]+', ' ').Trim() -replace '\s+', ' ')
    do {
        $priorCompanyKey = $companyKey
        $companyKey = ($companyKey -replace '\s+(private limited|pvt ltd|pvt limited|limited|ltd|llc|incorporated|inc|corporation|corp|gmbh|plc|company|co)$', '').Trim()
    } while ($companyKey -ne $priorCompanyKey)
    $titleKey = (($Title.ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim() -replace '\s+', ' ')
    if ($companyKey -and $titleKey) { return "$companyKey|$titleKey" }
    return "job:$JobId"
}

function Invoke-ReopenTransition($Job, [string]$Directory) {
    $ledgerPath = Join-Path $runtimeRoot 'applications.jsonl'
    $lockPath = Join-Path $runtimeRoot 'applications.lock'
    $identity = Get-SubmissionIdentity ([string]$Job.company) ([string]$Job.title) ([string]$Job.job_id)
    $row = [ordered]@{
        timestamp = [DateTimeOffset]::UtcNow.ToString('o')
        status = 'reopened-application'
        reason_code = 'user-authorized-proven-pre-submit-retry'
        source = [string]$Job.source
        company = [string]$Job.company
        title = [string]$Job.title
        location = [string]$Job.location
        job_url = [string]$Job.job_url
        job_id = [string]$Job.job_id
    }
    $workItemLock = $null
    $lock = $null
    try {
        try { $workItemLock = [IO.File]::Open((Join-Path $Directory '.work-item.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { throw 'Work item is busy; retry this command.' }
        try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { throw 'Applications ledger is busy; retry this command.' }

        if (Test-Path -LiteralPath $ledgerPath) {
            foreach ($line in Get-Content -LiteralPath $ledgerPath) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $existing = $line | ConvertFrom-Json
                    if ([string]$existing.status -ne 'submitted' -and $existing.submitted -ne $true) { continue }
                    $existingIdentity = Get-SubmissionIdentity ([string]$existing.company) ([string]$existing.title) ([string]$existing.job_id)
                    if ([string]$existing.job_id -eq [string]$Job.job_id -or $existingIdentity -eq $identity) {
                        return [ordered]@{ status='retry-rejected'; reason='submitted-or-semantic-duplicate-exists'; matched_job_id=[string]$existing.job_id }
                    }
                } catch {}
            }
        }

        $stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
        foreach ($name in @('application-result.json','application-progress.json')) {
            $path = Join-Path $Directory $name
            if (Test-Path -LiteralPath $path) {
                $archive = Join-Path $Directory (([IO.Path]::GetFileNameWithoutExtension($name)) + ".reopened.$stamp.json")
                Move-Item -LiteralPath $path -Destination $archive
            }
        }
        $recoverablePath = Join-Path $Directory 'recoverable-error.json'
        if (Test-Path -LiteralPath $recoverablePath) { Remove-Item -LiteralPath $recoverablePath -Force }

        $stream = [IO.File]::Open($ledgerPath, 'OpenOrCreate', 'ReadWrite', 'Read')
        try {
            if ($stream.Length -gt 0) {
                $stream.Seek(-1, [IO.SeekOrigin]::End) | Out-Null
                $last = $stream.ReadByte()
                $stream.Seek(0, [IO.SeekOrigin]::End) | Out-Null
                if ($last -notin @(10,13)) {
                    $newline = [Text.Encoding]::UTF8.GetBytes([Environment]::NewLine)
                    $stream.Write($newline, 0, $newline.Length)
                }
            }
            $bytes = [Text.Encoding]::UTF8.GetBytes(($row | ConvertTo-Json -Compress -Depth 6) + [Environment]::NewLine)
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally { $stream.Dispose() }
        return [ordered]@{ status='reopened'; prior_status=$null }
    } finally {
        if ($null -ne $lock) { $lock.Dispose() }
        if ($null -ne $workItemLock) { $workItemLock.Dispose() }
    }
}

if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = (Get-Location).Path }
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$runtimeRoot = Join-Path $Workspace '.job-apply-autopilot'
$generatedRoot = Join-Path $runtimeRoot 'generated'
if (-not (Test-Path -LiteralPath $runtimeRoot)) { throw "No job-apply-autopilot runtime at $runtimeRoot" }

if ($Action -eq 'List') {
    $items = @()
    foreach ($dir in Get-ChildItem -LiteralPath $generatedRoot -Directory -ErrorAction SilentlyContinue) {
        $state = Read-JsonSafe (Join-Path $dir.FullName 'application-send-state.json')
        if (-not $state -or [string]$state.status -ne 'verification-quarantined') { continue }
        $job = Read-JsonSafe (Join-Path $dir.FullName 'job.json')
        $items += [ordered]@{
            job_id = if ($job) { [string]$job.job_id } else { $dir.Name }
            company = if ($job) { [string]$job.company } else { '' }
            title = if ($job) { [string]$job.title } else { '' }
            channel = [string]$state.channel
            target = [string]$state.target
            blocker = [string]$state.quarantine_reason
            reservation_id = [string]$state.reservation_id
            quarantined_at = $state.quarantined_at
            path = $dir.FullName
        }
    }
    Emit ([ordered]@{ status='listed'; count=$items.Count; items=$items })
    exit 0
}

if ([string]::IsNullOrWhiteSpace($WorkItemDir)) { throw "$Action requires -WorkItemDir." }
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
$generatedPrefix = $generatedRoot.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) + [IO.Path]::DirectorySeparatorChar
if (-not $WorkItemDir.StartsWith($generatedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Resolution commands apply only to generated work items in this workspace.' }
$job = Read-JsonSafe (Join-Path $WorkItemDir 'job.json')
$sendState = Read-JsonSafe (Join-Path $WorkItemDir 'application-send-state.json')
if (-not $job) { throw "Missing or invalid job.json in $WorkItemDir" }
$guard = Join-Path $PSScriptRoot 'application-send-guard.ps1'

if ($Action -ne 'RetryApplication' -and (-not $sendState -or [string]::IsNullOrWhiteSpace([string]$sendState.reservation_id))) {
    throw 'No guarded application reservation exists for this work item.'
}

switch ($Action) {
    'Reverify' {
        & $guard -WorkItemDir $WorkItemDir -Action ReopenVerification -ReservationId ([string]$sendState.reservation_id)
    }
    'ConfirmSubmitted' {
        if ([string]::IsNullOrWhiteSpace($Proof)) { throw 'ConfirmSubmitted requires -Proof describing the user-confirmed submission.' }
        & $guard -WorkItemDir $WorkItemDir -Action MarkSubmitted -ReservationId ([string]$sendState.reservation_id) -Proof ("user-confirmed: " + $Proof.Trim())
    }
    'ConfirmAbsent' {
        if ([string]::IsNullOrWhiteSpace($Proof)) { throw 'ConfirmAbsent requires -Proof describing the user confirmation.' }
        & $guard -WorkItemDir $WorkItemDir -Action MarkVerifiedAbsent -ReservationId ([string]$sendState.reservation_id) -ProofKind user-confirmed-absence -ResolutionCommand -Proof ("user-confirmed: " + $Proof.Trim())
    }
    'Abandon' {
        if ([string]::IsNullOrWhiteSpace($Proof)) { throw 'Abandon requires -Proof describing the unresolved outcome.' }
        $abandoned = (& $guard -WorkItemDir $WorkItemDir -Action AbandonVerification -ReservationId ([string]$sendState.reservation_id) -Proof $Proof | Select-Object -Last 1) | ConvertFrom-Json
        if ([string]$abandoned.status -ne 'abandoned') { Emit $abandoned; exit 0 }
        & (Join-Path $PSScriptRoot 'write-application-outcome.ps1') -WorkItemDir $WorkItemDir -Status blocked-verification-unresolved -Blocker $Proof -ApplyMethod $(if ([string]$sendState.channel -eq 'email') { 'email' } else { 'external-ats' }) -Target ([string]$sendState.target)
    }
    'RetryApplication' {
        $result = Read-JsonSafe (Join-Path $WorkItemDir 'application-result.json')
        $lastLedgerStatus = ''
        $ledgerPath = Join-Path $runtimeRoot 'applications.jsonl'
        if (Test-Path -LiteralPath $ledgerPath) {
            foreach ($line in Get-Content -LiteralPath $ledgerPath) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $row = $line | ConvertFrom-Json
                    if ([string]$row.job_id -eq [string]$job.job_id) { $lastLedgerStatus = [string]$row.status }
                } catch {}
            }
        }
        $provenPreSubmit = ($sendState -and [string]$sendState.status -in @('cancelled-before-submit','verified-absent'))
        $legacyRouteBlocked = (([string]$result.status -eq 'route_blocked' -or $lastLedgerStatus -eq 'route_blocked') -and -not $sendState)
        if (-not $provenPreSubmit -and -not $legacyRouteBlocked) {
            Emit ([ordered]@{ status='retry-rejected'; job_id=[string]$job.job_id; reason='outcome-not-proven-pre-submit-or-absent'; send_status=if ($sendState) { [string]$sendState.status } else { '' }; ledger_status=$lastLedgerStatus })
            exit 0
        }

        $reopen = Invoke-ReopenTransition $job $WorkItemDir
        if ([string]$reopen.status -ne 'reopened') {
            Emit ([ordered]@{ status=[string]$reopen.status; job_id=[string]$job.job_id; reason=[string]$reopen.reason; matched_job_id=[string]$reopen.matched_job_id })
            exit 0
        }
        foreach ($stage in @('application_ready','application_resume','application_verification','email_application_ready','application_outcome_repair')) {
            & (Join-Path $PSScriptRoot 'claim-action.ps1') -Action ClearStage -Scope WorkItem -Stage $stage -WorkItemDir $WorkItemDir -Workspace $Workspace | Out-Null
        }
        & (Join-Path $PSScriptRoot 'update-campaign-stats.ps1') -Workspace $Workspace | Out-Null
        Emit ([ordered]@{ status='reopened'; job_id=[string]$job.job_id; prior_send_status=if ($sendState) { [string]$sendState.status } else { '' }; prior_ledger_status=$lastLedgerStatus; next_stage='application_ready' })
    }
}
