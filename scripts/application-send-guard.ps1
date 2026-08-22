[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][ValidateSet('Status','Reserve','MarkSubmitted','MarkAmbiguous','MarkVerifiedAbsent','CancelBeforeSubmit','QuarantineVerification','ReopenVerification','AbandonVerification')][string]$Action,
    [ValidateSet('','external-ats','email','linkedin-easy-apply')][string]$Channel = '',
    [string]$Target = '',
    [string]$Subject = '',
    [string]$ReservationId = '',
    [string]$Proof = '',
    [ValidateSet('','authenticated-ats-tracker-absence','exact-sent-search-absence','user-confirmed-absence','freehire-exact-linked-mail')][string]$ProofKind = '',
    [switch]$ResolutionCommand,
    [int]$VerificationGraceMinutes = 15
)

$ErrorActionPreference = 'Stop'
$resolverScriptPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'resolve-application-quarantine.ps1'))
$freehireSyncScriptPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'sync-freehire-context.ps1'))
$callerScriptPath = if ([string]::IsNullOrWhiteSpace([string]$MyInvocation.ScriptName)) { '' } else { [IO.Path]::GetFullPath([string]$MyInvocation.ScriptName) }
$resolutionCommandAuthorized = ([bool]$ResolutionCommand -and $callerScriptPath -eq $resolverScriptPath)
$freehireMailAuthorized = ($ProofKind -eq 'freehire-exact-linked-mail' -and $callerScriptPath -eq $freehireSyncScriptPath)
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
$statePath = Join-Path $WorkItemDir 'application-send-state.json'
$resultPath = Join-Path $WorkItemDir 'application-result.json'
$jobPath = Join-Path $WorkItemDir 'job.json'
$artifactPath = Join-Path $WorkItemDir 'resume-artifact.json'
$runtimeRoot = $null
$cursor = [IO.DirectoryInfo]::new($WorkItemDir)
while ($null -ne $cursor) {
    if ($cursor.Name -eq '.job-apply-autopilot') { $runtimeRoot = $cursor.FullName; break }
    $cursor = $cursor.Parent
}
$lockPath = if ($runtimeRoot) { Join-Path $runtimeRoot 'application-send-guard.lock' } else { Join-Path $WorkItemDir '.application-send-guard.lock' }

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

function Write-Result($Value) {
    Write-Output ($Value | ConvertTo-Json -Depth 8 -Compress)
}

function Set-StateProperty($State, [string]$Name, $Value) {
    $State | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Clear-ApplicationClaims {
    if (-not $runtimeRoot) { return }
    $workspace = Split-Path -Parent $runtimeRoot
    $claimScript = Join-Path $PSScriptRoot 'claim-action.ps1'
    foreach ($stage in @('application_ready','application_resume','application_verification','email_application_ready','application_outcome_repair')) {
        & $claimScript -Action ClearStage -Scope WorkItem -Stage $stage -WorkItemDir $WorkItemDir -Workspace $workspace | Out-Null
    }
}

function Test-AbsenceProofKind($State, [string]$Kind) {
    if ($Kind -eq 'user-confirmed-absence') { return $resolutionCommandAuthorized }
    if ([string]$State.channel -eq 'email') { return $Kind -eq 'exact-sent-search-absence' }
    return $Kind -eq 'authenticated-ats-tracker-absence'
}

function Get-TargetDomain([string]$Value, [string]$ChannelName) {
    if ($ChannelName -eq 'email') { return 'mail.google.com' }
    try {
        if ($Value -match '^[a-z][a-z0-9+.-]*://') { return ([Uri]$Value).Host.ToLowerInvariant() }
    } catch {}
    return $Value.Trim().ToLowerInvariant()
}

function Get-SubmissionIdentity([string]$Company, [string]$Title, [string]$JobId) {
    $companyKey = (($Company.ToLowerInvariant() -replace '&', ' and ' -replace '[^a-z0-9]+', ' ').Trim() -replace '\s+', ' ')
    do {
        $priorCompanyKey = $companyKey
        $companyKey = ($companyKey -replace '\s+(private limited|pvt ltd|pvt limited|limited|ltd|llc|incorporated|inc|corporation|corp|gmbh|plc|company|co)$', '').Trim()
    } while ($companyKey -ne $priorCompanyKey)
    $titleNormalized = (($Title.ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim() -replace '\s+', ' ')
    $titleKey = (($titleNormalized.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | Sort-Object) -join ' ')
    if ($companyKey -and $titleKey) { return "$companyKey|$titleKey" }
    return "job:$JobId"
}

function Parse-Time($Value) {
    try {
        if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
        if ($Value -is [DateTime]) { return ([DateTimeOffset]$Value).ToUniversalTime() }
        return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    } catch { return $null }
}

function Find-SemanticConflict($Job) {
    if ($null -eq $runtimeRoot -or $null -eq $Job) { return $null }
    $jobId = [string]$Job.job_id
    $identity = Get-SubmissionIdentity ([string]$Job.company) ([string]$Job.title) $jobId
    $ledgerPath = Join-Path $runtimeRoot 'applications.jsonl'
    if (Test-Path -LiteralPath $ledgerPath) {
        foreach ($line in Get-Content -LiteralPath $ledgerPath) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                $submitted = ([string]$row.status -eq 'submitted' -or $row.submitted -eq $true)
                $when = Parse-Time $row.timestamp
                if (-not $submitted -or ($when -and $when -lt [DateTimeOffset]::UtcNow.AddDays(-45))) { continue }
                $rowIdentity = Get-SubmissionIdentity ([string]$row.company) ([string]$row.title) ([string]$row.job_id)
                if ($rowIdentity -eq $identity) {
                    $conflictStatus = if ([string]$row.job_id -eq $jobId) { 'already-submitted' } else { 'semantic-already-submitted' }
                    return [ordered]@{ status=$conflictStatus; matched_job_id=[string]$row.job_id; identity=$identity }
                }
            } catch {}
        }
    }
    $generatedRoot = Join-Path $runtimeRoot 'generated'
    if (Test-Path -LiteralPath $generatedRoot) {
        foreach ($dir in Get-ChildItem -LiteralPath $generatedRoot -Directory -ErrorAction SilentlyContinue) {
            if ($dir.FullName -eq $WorkItemDir) { continue }
            $otherJob = Read-JsonSafe (Join-Path $dir.FullName 'job.json')
            if ($null -eq $otherJob) { continue }
            $otherId = [string]$otherJob.job_id
            $otherIdentity = Get-SubmissionIdentity ([string]$otherJob.company) ([string]$otherJob.title) $otherId
            if ($otherIdentity -ne $identity) { continue }
            $otherState = Read-JsonSafe (Join-Path $dir.FullName 'application-send-state.json')
            $otherResult = Read-JsonSafe (Join-Path $dir.FullName 'application-result.json')
            if (($otherState -and [string]$otherState.status -in @('reserved','verification-required','verification-quarantined','abandoned-unknown-outcome','submitted')) -or ($otherResult -and ([bool]$otherResult.submitted -or [string]$otherResult.status -eq 'submitted'))) {
                return [ordered]@{ status='semantic-reservation-exists'; matched_job_id=$otherId; identity=$identity }
            }
        }
    }
    return $null
}

function Test-Reservation($State, [string]$Expected) {
    if ($null -eq $State -or [string]::IsNullOrWhiteSpace($Expected) -or [string]$State.reservation_id -ne $Expected) {
        Write-Result ([ordered]@{ status='reservation-mismatch'; safe_to_submit=$false })
        return $false
    }
    return $true
}

$lock = $null
try {
    try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch {
        Write-Result ([ordered]@{ status='busy'; safe_to_submit=$false })
        exit 0
    }

    $now = [DateTimeOffset]::UtcNow
    $state = Read-JsonSafe $statePath
    $existingResult = Read-JsonSafe $resultPath
    $alreadySubmitted = ($existingResult -and ([bool]$existingResult.submitted -or [string]$existingResult.status -eq 'submitted')) -or ($state -and [string]$state.status -eq 'submitted')

    if ($alreadySubmitted) {
        if ($null -eq $existingResult -and $state -and [string]$state.status -eq 'submitted') {
            $job = Read-JsonSafe $jobPath
            $artifact = Read-JsonSafe $artifactPath
            $existingResult = [ordered]@{
                job_id = if ($job) { $job.job_id } else { $null }
                company = if ($job) { $job.company } else { $null }
                title = if ($job) { $job.title } else { $null }
                apply_method = [string]$state.channel
                target = [string]$state.target
                ats_domain = Get-TargetDomain ([string]$state.target) ([string]$state.channel)
                employer_email = if ([string]$state.channel -eq 'email') { [string]$state.target } else { $null }
                status = 'submitted'
                submitted = $true
                confirmation = [string]$state.proof
                proof_kind = if ($state.PSObject.Properties.Name -contains 'proof_kind') { [string]$state.proof_kind } else { $null }
                resume_filename = if ($artifact) { $artifact.filename } else { $null }
                reservation_id = [string]$state.reservation_id
                submitted_at = $state.submitted_at
                blocker = $null
            }
            Write-JsonAtomic $resultPath $existingResult
        }
        Clear-ApplicationClaims
        Write-Result ([ordered]@{
            status = 'already-submitted'
            safe_to_submit = $false
            submitted_at = if ($state) { $state.submitted_at } else { $null }
            confirmation = if ($existingResult) { $existingResult.confirmation } else { $state.proof }
        })
        exit 0
    }

    switch ($Action) {
        'Status' {
            if ($null -eq $state -or [string]$state.status -in @('verified-absent','cancelled-before-submit')) {
                Write-Result ([ordered]@{ status='available'; safe_to_submit=$true; prior_status=if ($state) { $state.status } else { $null } })
            } else {
                Write-Result ([ordered]@{
                    status = [string]$state.status
                    safe_to_submit = $false
                    reservation_id = $state.reservation_id
                    reserved_at = $state.reserved_at
                    channel = $state.channel
                    target = $state.target
                    subject = $state.subject
                    retry_after = $state.verification_retry_after
                    quarantine_reason = $state.quarantine_reason
                })
            }
        }
        'Reserve' {
            if ([string]::IsNullOrWhiteSpace($Channel) -or [string]::IsNullOrWhiteSpace($Target)) {
                throw 'Reserve requires -Channel and -Target.'
            }
            if ($state -and [string]$state.status -in @('verification-quarantined','abandoned-unknown-outcome')) {
                Clear-ApplicationClaims
                Write-Result ([ordered]@{
                    status = if ([string]$state.status -eq 'verification-quarantined') { 'quarantined' } else { 'abandoned' }
                    safe_to_submit = $false
                    reservation_id = $state.reservation_id
                    channel = $state.channel
                    target = $state.target
                    subject = $state.subject
                    reason = if ($state.quarantine_reason) { $state.quarantine_reason } else { $state.abandonment_reason }
                })
                exit 0
            }
            if ($state -and [string]$state.status -in @('reserved','verification-required')) {
                Write-Result ([ordered]@{
                    status = 'verify-required'
                    safe_to_submit = $false
                    reservation_id = $state.reservation_id
                    reserved_at = $state.reserved_at
                    channel = $state.channel
                    target = $state.target
                    subject = $state.subject
                    retry_after = $state.verification_retry_after
                })
                exit 0
            }
            $job = Read-JsonSafe $jobPath
            $targetHost = Get-TargetDomain $Target $Channel
            $aggregatorDomains = @('whatjobs.com','jobleads.com','jooble.org','talent.com','bebee.com','jobrapido.com','adzuna.com')
            $aggregatorTarget = $false
            foreach ($aggregatorDomain in $aggregatorDomains) {
                if ($targetHost -eq $aggregatorDomain -or $targetHost.EndsWith(".$aggregatorDomain")) { $aggregatorTarget = $true; break }
            }
            if ($Channel -eq 'external-ats' -and $aggregatorTarget) {
                & (Join-Path $PSScriptRoot 'set-application-route.ps1') -WorkItemDir $WorkItemDir -Route unresolved -Target $Target -Evidence 'Reservation rejected aggregator route; direct employer or ATS route required.' | Out-Null
                Write-Result ([ordered]@{ status='route-unresolved'; safe_to_submit=$false; target=$Target; reason_code='aggregator-route-rejected' })
                exit 0
            }
            $metadataPath = Join-Path $WorkItemDir 'source-metadata.json'
            $qualityArgs = @{ JobJson = ($job | ConvertTo-Json -Compress -Depth 8) }
            if (Test-Path -LiteralPath $metadataPath) { $qualityArgs.MetadataJson = $metadataPath }
            $sourcePath = Join-Path $WorkItemDir 'source.md'
            if (Test-Path -LiteralPath $sourcePath) { $qualityArgs.SourcePath = $sourcePath }
            $quality = (& (Join-Path $PSScriptRoot 'check-job-quality.ps1') @qualityArgs | Select-Object -Last 1) | ConvertFrom-Json
            if (-not [bool]$quality.allowed) {
                & (Join-Path $PSScriptRoot 'write-application-outcome.ps1') -WorkItemDir $WorkItemDir -Status 'skipped-job-quality' -Blocker ([string]$quality.reason_code) -ApplyMethod $Channel -Target $Target | Out-Null
                Clear-ApplicationClaims
                Write-Result ([ordered]@{ status='quality-rejected'; safe_to_submit=$false; reason_code=[string]$quality.reason_code; evidence=[string]$quality.evidence })
                exit 0
            }
            $semanticConflict = Find-SemanticConflict $job
            if ($semanticConflict) {
                Clear-ApplicationClaims
                Write-Result ([ordered]@{ status=$semanticConflict.status; safe_to_submit=$false; matched_job_id=$semanticConflict.matched_job_id; identity=$semanticConflict.identity })
                exit 0
            }
            $attempt = if ($state -and $state.attempt) { [int]$state.attempt + 1 } else { 1 }
            $reservation = [Guid]::NewGuid().ToString('N')
            $newState = [ordered]@{
                version = 1
                status = 'reserved'
                reservation_id = $reservation
                attempt = $attempt
                channel = $Channel.Trim().ToLowerInvariant()
                target = $Target.Trim()
                subject = $Subject.Trim()
                reserved_at = $now.ToString('o')
                updated_at = $now.ToString('o')
                prior_status = if ($state) { $state.status } else { $null }
            }
            Write-JsonAtomic $statePath $newState
            Write-Result ([ordered]@{ status='acquired'; safe_to_submit=$true; reservation_id=$reservation; attempt=$attempt; reserved_at=$newState.reserved_at })
        }
        'MarkSubmitted' {
            if (-not (Test-Reservation $state $ReservationId)) { exit 0 }
            if ([string]::IsNullOrWhiteSpace($Proof)) { throw 'MarkSubmitted requires -Proof.' }
            if ($ProofKind -eq 'freehire-exact-linked-mail' -and -not $freehireMailAuthorized) {
                Write-Result ([ordered]@{ status='rejected-proof'; safe_to_submit=$false; reservation_id=$state.reservation_id; proof_kind=$ProofKind; required_caller='sync-freehire-context.ps1' })
                exit 0
            }
            $job = Read-JsonSafe $jobPath
            $artifact = Read-JsonSafe $artifactPath
            $state.status = 'submitted'
            Set-StateProperty $state 'proof' $Proof.Trim()
            if ($ProofKind) { Set-StateProperty $state 'proof_kind' $ProofKind }
            Set-StateProperty $state 'submitted_at' $now.ToString('o')
            Set-StateProperty $state 'verification_retry_after' $null
            $state.updated_at = $now.ToString('o')
            Write-JsonAtomic $statePath $state
            $result = [ordered]@{
                job_id = if ($job) { $job.job_id } else { $null }
                company = if ($job) { $job.company } else { $null }
                title = if ($job) { $job.title } else { $null }
                apply_method = [string]$state.channel
                target = [string]$state.target
                ats_domain = Get-TargetDomain ([string]$state.target) ([string]$state.channel)
                employer_email = if ([string]$state.channel -eq 'email') { [string]$state.target } else { $null }
                status = 'submitted'
                submitted = $true
                confirmation = $Proof.Trim()
                proof_kind = if ($ProofKind) { $ProofKind } else { $null }
                resume_filename = if ($artifact) { $artifact.filename } else { $null }
                reservation_id = [string]$state.reservation_id
                submitted_at = $now.ToString('o')
                blocker = $null
            }
            Write-JsonAtomic $resultPath $result
            Clear-ApplicationClaims
            Write-Result ([ordered]@{ status='submitted'; safe_to_submit=$false; reservation_id=$state.reservation_id; result=$resultPath })
        }
        'MarkAmbiguous' {
            if (-not (Test-Reservation $state $ReservationId)) { exit 0 }
            if ([string]::IsNullOrWhiteSpace($Proof)) { throw 'MarkAmbiguous requires -Proof describing the uncertain outcome.' }
            $state.status = 'verification-required'
            Set-StateProperty $state 'proof' $Proof.Trim()
            Set-StateProperty $state 'verification_retry_after' $null
            $state.updated_at = $now.ToString('o')
            Write-JsonAtomic $statePath $state
            Clear-ApplicationClaims
            Write-Result ([ordered]@{ status='verify-required'; safe_to_submit=$false; reservation_id=$state.reservation_id; reserved_at=$state.reserved_at })
        }
        'MarkVerifiedAbsent' {
            if (-not (Test-Reservation $state $ReservationId)) { exit 0 }
            if ([string]::IsNullOrWhiteSpace($Proof)) { throw 'MarkVerifiedAbsent requires -Proof.' }
            if (-not (Test-AbsenceProofKind $state $ProofKind)) {
                $requiredKind = if ($ProofKind -eq 'user-confirmed-absence' -and -not $resolutionCommandAuthorized) { 'resolution-command-required' } elseif ([string]$state.channel -eq 'email') { 'exact-sent-search-absence' } else { 'authenticated-ats-tracker-absence' }
                Write-Result ([ordered]@{ status='rejected-proof'; safe_to_submit=$false; reservation_id=$state.reservation_id; channel=$state.channel; proof_kind=$ProofKind; required_proof_kind=$requiredKind })
                exit 0
            }
            $reservedAt = Parse-Time $state.reserved_at
            if ($null -eq $reservedAt) {
                Write-Result ([ordered]@{ status='invalid-reservation-time'; safe_to_submit=$false; reservation_id=$state.reservation_id })
                exit 0
            }
            $retryAt = $reservedAt.AddMinutes([Math]::Max(1, $VerificationGraceMinutes))
            if ($ProofKind -ne 'user-confirmed-absence' -and $now -lt $retryAt) {
                Set-StateProperty $state 'verification_retry_after' $retryAt.ToString('o')
                $state.updated_at = $now.ToString('o')
                Write-JsonAtomic $statePath $state
                Clear-ApplicationClaims
                Write-Result ([ordered]@{ status='verification-grace'; safe_to_submit=$false; retry_after=$retryAt.ToString('o'); reservation_id=$state.reservation_id })
                exit 0
            }
            $state.status = 'verified-absent'
            Set-StateProperty $state 'verification_proof' $Proof.Trim()
            Set-StateProperty $state 'verification_proof_kind' $ProofKind
            Set-StateProperty $state 'verified_at' $now.ToString('o')
            Set-StateProperty $state 'verification_retry_after' $null
            $state.updated_at = $now.ToString('o')
            Write-JsonAtomic $statePath $state
            Clear-ApplicationClaims
            Write-Result ([ordered]@{ status='verified-absent'; safe_to_submit=$true; reservation_id=$state.reservation_id })
        }
        'CancelBeforeSubmit' {
            if (-not (Test-Reservation $state $ReservationId)) { exit 0 }
            if ([string]::IsNullOrWhiteSpace($Proof)) { throw 'CancelBeforeSubmit requires -Proof.' }
            $state.status = 'cancelled-before-submit'
            Set-StateProperty $state 'cancellation_proof' $Proof.Trim()
            Set-StateProperty $state 'cancelled_at' $now.ToString('o')
            Set-StateProperty $state 'verification_retry_after' $null
            $state.updated_at = $now.ToString('o')
            Write-JsonAtomic $statePath $state
            Clear-ApplicationClaims
            Write-Result ([ordered]@{ status='cancelled-before-submit'; safe_to_submit=$true; reservation_id=$state.reservation_id })
        }
        'QuarantineVerification' {
            if (-not (Test-Reservation $state $ReservationId)) { exit 0 }
            if ([string]::IsNullOrWhiteSpace($Proof)) { throw 'QuarantineVerification requires -Proof describing why authoritative verification is unavailable.' }
            $state.status = 'verification-quarantined'
            Set-StateProperty $state 'quarantine_reason' $Proof.Trim()
            Set-StateProperty $state 'quarantined_at' $now.ToString('o')
            Set-StateProperty $state 'verification_retry_after' $null
            $state.updated_at = $now.ToString('o')
            Write-JsonAtomic $statePath $state
            Clear-ApplicationClaims
            Write-Result ([ordered]@{ status='quarantined'; safe_to_submit=$false; reservation_id=$state.reservation_id; reason=$state.quarantine_reason })
        }
        'ReopenVerification' {
            if (-not (Test-Reservation $state $ReservationId)) { exit 0 }
            if ([string]$state.status -ne 'verification-quarantined') {
                Write-Result ([ordered]@{ status='not-quarantined'; safe_to_submit=$false; reservation_id=$state.reservation_id })
                exit 0
            }
            $state.status = 'verification-required'
            Set-StateProperty $state 'reverified_at' $now.ToString('o')
            Set-StateProperty $state 'verification_retry_after' $null
            $state.updated_at = $now.ToString('o')
            Write-JsonAtomic $statePath $state
            Clear-ApplicationClaims
            Write-Result ([ordered]@{ status='verify-required'; safe_to_submit=$false; reservation_id=$state.reservation_id })
        }
        'AbandonVerification' {
            if (-not (Test-Reservation $state $ReservationId)) { exit 0 }
            if ([string]::IsNullOrWhiteSpace($Proof)) { throw 'AbandonVerification requires -Proof.' }
            if ([string]$state.status -notin @('verification-quarantined','verification-required','reserved')) {
                Write-Result ([ordered]@{ status='not-abandonable'; safe_to_submit=$false; reservation_id=$state.reservation_id })
                exit 0
            }
            $state.status = 'abandoned-unknown-outcome'
            Set-StateProperty $state 'abandonment_reason' $Proof.Trim()
            Set-StateProperty $state 'abandoned_at' $now.ToString('o')
            Set-StateProperty $state 'verification_retry_after' $null
            $state.updated_at = $now.ToString('o')
            Write-JsonAtomic $statePath $state
            Clear-ApplicationClaims
            Write-Result ([ordered]@{ status='abandoned'; safe_to_submit=$false; reservation_id=$state.reservation_id })
        }
    }
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
}
