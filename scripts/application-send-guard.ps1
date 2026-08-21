[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][ValidateSet('Status','Reserve','MarkSubmitted','MarkAmbiguous','MarkVerifiedAbsent','CancelBeforeSubmit')][string]$Action,
    [string]$Channel = '',
    [string]$Target = '',
    [string]$Subject = '',
    [string]$ReservationId = '',
    [string]$Proof = '',
    [int]$VerificationGraceMinutes = 15
)

$ErrorActionPreference = 'Stop'
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
    $titleKey = (($Title.ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim() -replace '\s+', ' ')
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
            if (($otherState -and [string]$otherState.status -in @('reserved','verification-required','submitted')) -or ($otherResult -and ([bool]$otherResult.submitted -or [string]$otherResult.status -eq 'submitted'))) {
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
                resume_filename = if ($artifact) { $artifact.filename } else { $null }
                reservation_id = [string]$state.reservation_id
                submitted_at = $state.submitted_at
                blocker = $null
            }
            Write-JsonAtomic $resultPath $existingResult
        }
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
                })
            }
        }
        'Reserve' {
            if ([string]::IsNullOrWhiteSpace($Channel) -or [string]::IsNullOrWhiteSpace($Target)) {
                throw 'Reserve requires -Channel and -Target.'
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
            $semanticConflict = Find-SemanticConflict $job
            if ($semanticConflict) {
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
            $job = Read-JsonSafe $jobPath
            $artifact = Read-JsonSafe $artifactPath
            $state.status = 'submitted'
            Set-StateProperty $state 'proof' $Proof.Trim()
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
                resume_filename = if ($artifact) { $artifact.filename } else { $null }
                reservation_id = [string]$state.reservation_id
                submitted_at = $now.ToString('o')
                blocker = $null
            }
            Write-JsonAtomic $resultPath $result
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
            Write-Result ([ordered]@{ status='verify-required'; safe_to_submit=$false; reservation_id=$state.reservation_id; reserved_at=$state.reserved_at })
        }
        'MarkVerifiedAbsent' {
            if (-not (Test-Reservation $state $ReservationId)) { exit 0 }
            if ([string]::IsNullOrWhiteSpace($Proof)) { throw 'MarkVerifiedAbsent requires -Proof.' }
            $reservedAt = Parse-Time $state.reserved_at
            if ($null -eq $reservedAt) {
                Write-Result ([ordered]@{ status='invalid-reservation-time'; safe_to_submit=$false; reservation_id=$state.reservation_id })
                exit 0
            }
            $retryAt = $reservedAt.AddMinutes([Math]::Max(1, $VerificationGraceMinutes))
            if ($now -lt $retryAt) {
                Set-StateProperty $state 'verification_retry_after' $retryAt.ToString('o')
                $state.updated_at = $now.ToString('o')
                Write-JsonAtomic $statePath $state
                Write-Result ([ordered]@{ status='verification-grace'; safe_to_submit=$false; retry_after=$retryAt.ToString('o'); reservation_id=$state.reservation_id })
                exit 0
            }
            $state.status = 'verified-absent'
            Set-StateProperty $state 'verification_proof' $Proof.Trim()
            Set-StateProperty $state 'verified_at' $now.ToString('o')
            Set-StateProperty $state 'verification_retry_after' $null
            $state.updated_at = $now.ToString('o')
            Write-JsonAtomic $statePath $state
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
            Write-Result ([ordered]@{ status='cancelled-before-submit'; safe_to_submit=$true; reservation_id=$state.reservation_id })
        }
    }
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
}
