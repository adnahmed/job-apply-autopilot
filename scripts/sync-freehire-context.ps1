[CmdletBinding()]
param(
    [string]$Workspace = (Get-Location).Path,
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml'),
    [switch]$Force,
    [switch]$Compact
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace=(Get-Location).Path }
$Workspace=(Resolve-Path -LiteralPath $Workspace).Path
$runtimeRoot=Join-Path $Workspace '.job-apply-autopilot'
if (-not (Test-Path -LiteralPath $runtimeRoot)) { throw "No job-apply-autopilot runtime in $Workspace" }
$contextPath=Join-Path $runtimeRoot 'freehire-context.json'

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Write-JsonAtomic([string]$Path, $Value, [int]$Depth = 50) {
    $temp="$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try { $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $temp -Encoding UTF8; [IO.File]::Move($temp,$Path,$true) }
    finally { if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue} }
}

function Parse-Utc($Value) {
    try { return [DateTimeOffset]::Parse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() }
    catch { return $null }
}

function Profile-Scalar([string]$Name, $Default = $null) {
    if (-not (Test-Path -LiteralPath $ProfilePath)) { return $Default }
    $text=Get-Content -LiteralPath $ProfilePath -Raw
    $pattern='(?m)^\s*'+[regex]::Escape($Name)+':\s*["'']?([^\r\n"'']+)'
    if($text -match $pattern){return $Matches[1].Trim()}
    return $Default
}

function To-Bool($Value,[bool]$Default=$false) {
    if($null -eq $Value){return $Default}; if($Value -is [bool]){return [bool]$Value}
    return [string]$Value -match '^(?i:true|1|yes|on|enabled)$'
}

function Get-Hash([string]$Value) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()}
    finally{$sha.Dispose()}
}

function Call-FreeHire([string]$Method,[string]$Path,$Query=$null,$Body=$null,[string]$Auth='required',[string]$CostClass='free',[int]$CacheHours=0) {
    $arguments=@{Method=$Method;Path=$Path;Auth=$Auth;CostClass=$CostClass;Workspace=$Workspace;ProfilePath=$ProfilePath;CacheHours=$CacheHours}
    if($null -ne $Query){$arguments.QueryJson=$Query|ConvertTo-Json -Compress -Depth 20}
    if($null -ne $Body){$arguments.BodyJson=$Body|ConvertTo-Json -Compress -Depth 30}
    return ((& (Join-Path $PSScriptRoot 'freehire-client.ps1') @arguments | Select-Object -Last 1)|ConvertFrom-Json)
}

function Get-CanonicalSkills {
    $factsPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'canonical\canonical-facts.yaml'
    if(-not (Test-Path -LiteralPath $factsPath)){return @()}
    $inside=$false; $skills=@()
    foreach($line in Get-Content -LiteralPath $factsPath){
        if($line -match '^\s{2}exact_or_explicitly_supported:\s*$'){$inside=$true;continue}
        if($inside -and $line -match '^\s{0,2}[a-zA-Z_][a-zA-Z0-9_-]*:\s*$'){break}
        if($inside -and $line -match '^\s{4}-\s*(.+?)\s*$'){$skills += $Matches[1].Trim(' "''')}
    }
    return @($skills|Sort-Object -Unique)
}

function Normalize-Skill([string]$Value){return ($Value.ToLowerInvariant() -replace '[^a-z0-9]+','')}

$now=[DateTimeOffset]::UtcNow
$prior=Read-JsonSafe $contextPath
$syncMinutes=[int](Profile-Scalar 'context_sync_minutes' 30)
$nextDue=if($prior -and $prior.next_sync_after){Parse-Utc $prior.next_sync_after}else{$null}
if(-not $Force -and $nextDue -and $nextDue -gt $now){
    $result=[ordered]@{status='cached';next_sync_after=$nextDue.ToString('o');authenticated=[bool]$prior.authenticated;mail_events=0;credit_anomaly=[bool]$prior.credit_anomaly}
    $result|ConvertTo-Json -Compress -Depth 8; exit 0
}

$lock=$null
try{
    try{$lock=[IO.File]::Open((Join-Path $runtimeRoot 'freehire-context.lock'),'OpenOrCreate','ReadWrite','None')}
    catch{[ordered]@{status='busy'}|ConvertTo-Json -Compress;exit 0}

    $autofill=Call-FreeHire 'GET' 'me/autofill-profile' $null $null 'required' 'free' 24
    $screening=Call-FreeHire 'GET' 'me/screening-answers' $null $null 'required' 'free' 24
    $credits=Call-FreeHire 'GET' 'me/credits' $null $null 'required' 'free' 1
    $creditHistory=Call-FreeHire 'GET' 'me/credits/history' ([ordered]@{limit=100;offset=0}) $null 'required' 'free' 1
    $authenticated=([string]$autofill.status -eq 'ok' -or [string]$screening.status -eq 'ok' -or [string]$credits.status -eq 'ok')
    $candidateConflicts=@()
    if([string]$autofill.status -eq 'ok' -and $autofill.data){
        $comparisons=@(
            [ordered]@{field='full_name';local=[string](Profile-Scalar 'full_name' '');remote=("{0} {1}" -f $autofill.data.first_name,$autofill.data.last_name).Trim()},
            [ordered]@{field='email';local=[string](Profile-Scalar 'email' '');remote=[string]$autofill.data.email},
            [ordered]@{field='linkedin';local=[string](Profile-Scalar 'linkedin' '');remote=[string]$autofill.data.linkedin}
        )
        foreach($comparison in $comparisons){if($comparison.local -and $comparison.remote -and $comparison.local.Trim().ToLowerInvariant().TrimEnd('/') -ne $comparison.remote.Trim().ToLowerInvariant().TrimEnd('/')){$candidateConflicts += $comparison.field}}
    }

    $priorCreditHashes=@(); if($prior -and $prior.credit_history_hashes){$priorCreditHashes=@($prior.credit_history_hashes)}
    $creditHashes=@(); $newDebits=@()
    if([string]$creditHistory.status -eq 'ok'){
        foreach($entry in @($creditHistory.data)){
            $hash=Get-Hash "$($entry.delta)|$($entry.reason)|$($entry.label)|$($entry.created_at)"
            $creditHashes += $hash
            if([int]$entry.delta -lt 0 -and $priorCreditHashes.Count -gt 0 -and $priorCreditHashes -notcontains $hash){
                $newDebits += [ordered]@{delta=[int]$entry.delta;reason=[string]$entry.reason;created_at=$entry.created_at}
            }
        }
    }

    $facets=Call-FreeHire 'GET' 'jobs/facets' $null $null 'none' 'free' 24
    $coverage=$null
    if([string]$facets.status -eq 'ok'){
        $facetRoot=$facets.data
        $skillEntries=if($facetRoot -and $facetRoot.facets -and $facetRoot.facets.skills){@($facetRoot.facets.skills)}elseif($facetRoot -and $facetRoot.skills){@($facetRoot.skills)}else{@()}
        $canonicalByKey=@{}
        foreach($entry in $skillEntries){
            $value=if($entry -is [string]){[string]$entry}elseif($entry.value){[string]$entry.value}elseif($entry.slug){[string]$entry.slug}elseif($entry.name){[string]$entry.name}else{''}
            if($value){$canonicalByKey[(Normalize-Skill $value)]=$value}
        }
        $measured=@()
        foreach($skill in Get-CanonicalSkills){$key=Normalize-Skill $skill;if($canonicalByKey.ContainsKey($key)){$measured += [string]$canonicalByKey[$key]}}
        $measured=@($measured|Sort-Object -Unique|Select-Object -First 100)
        if($measured.Count){
            $coverage=Call-FreeHire 'POST' 'market/coverage' ([ordered]@{category='software_engineering,backend,fullstack,devops,sre,ai_engineering'}) ([ordered]@{skills=$measured}) 'required' 'free' 24
        }
    }

    $gmail=Call-FreeHire 'GET' 'me/gmail' $null $null 'required' 'free' 1
    $mailMode=[string](Profile-Scalar 'mail_mode' 'disabled')
    $candidateEmail=if([string]$autofill.status -eq 'ok' -and $autofill.data -and $autofill.data.email){[string]$autofill.data.email}else{[string](Profile-Scalar 'email' '')}
    $mailboxVerified=([string]$gmail.status -eq 'ok' -and $gmail.data -and $gmail.data.email -and $candidateEmail -and [string]$gmail.data.email -eq $candidateEmail)
    $gmailSync=$null; $inbox=$null; $mailEvents=0; $mailProofs=0; $mailStageUpdates=0
    if($mailMode -eq 'optional-exact-match' -and $mailboxVerified -and [bool]$gmail.data.connected -and [string]$gmail.data.status -eq 'ok'){
        $gmailSync=Call-FreeHire 'POST' 'me/gmail/sync' $null ([ordered]@{}) 'required' 'free' 0
        $inbox=Call-FreeHire 'GET' 'me/inbox' ([ordered]@{link='linked';limit=50;offset=0}) $null 'required' 'free' 0
    }

    if($inbox -and [string]$inbox.status -eq 'ok'){
        $bySlug=@{}
        foreach($base in @((Join-Path $runtimeRoot 'queue'),(Join-Path $runtimeRoot 'generated'))){
            if(-not (Test-Path -LiteralPath $base)){continue}
            foreach($dir in Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue){
                $metadata=Read-JsonSafe (Join-Path $dir.FullName 'source-metadata.json')
                $slug=if($metadata -and $metadata.freehire -and $metadata.freehire.public_slug){[string]$metadata.freehire.public_slug}elseif($metadata -and $metadata.public_slug){[string]$metadata.public_slug}else{''}
                if($slug){$bySlug[$slug]=$dir.FullName}
            }
        }
        $stageMap=@{acknowledgement='applied';screening='screening';interview_invitation='interview';assessment='screening';offer='offer';rejection='rejected';info_request='responded';incomplete_application='preparing'}
        foreach($message in @($inbox.data)){
            $slug=[string]$message.linked_slug; $externalId=[string]$message.external_id; $signal=[string]$message.status_signal
            if(-not $slug -or -not $externalId -or -not $stageMap.ContainsKey($signal) -or -not $bySlug.ContainsKey($slug)){continue}
            $dir=[string]$bySlug[$slug]; $sendState=Read-JsonSafe (Join-Path $dir 'application-send-state.json'); $result=Read-JsonSafe (Join-Path $dir 'application-result.json')
            $received=Parse-Utc $message.received_at; $reserved=if($sendState -and $sendState.reserved_at){Parse-Utc $sendState.reserved_at}else{$null}
            if(-not $received -or -not $reserved -or $received -lt $reserved){continue}
            $sidecarPath=Join-Path $dir 'freehire-sync.json'; $sidecar=Read-JsonSafe $sidecarPath
            $seenIds=if($sidecar -and $sidecar.mail_external_ids){@($sidecar.mail_external_ids)}else{@()}
            if($seenIds -contains $externalId){continue}
            if($sendState -and [string]$sendState.status -in @('verification-required','verification-quarantined')){
                $proof="FreeHire exact linked employer mail id=$($message.id) external_id=$externalId signal=$signal slug=$slug received_at=$($message.received_at)"
                $marked=(& (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $dir -Action MarkSubmitted -ReservationId ([string]$sendState.reservation_id) -Proof $proof -ProofKind 'freehire-exact-linked-mail' | Select-Object -Last 1)|ConvertFrom-Json
                if([string]$marked.status -eq 'submitted'){$mailProofs++;$result=Read-JsonSafe (Join-Path $dir 'application-result.json')}
            }
            $job=Read-JsonSafe (Join-Path $dir 'job.json');$locallyReconciled=$false;$ledgerPath=Join-Path $runtimeRoot 'applications.jsonl'
            if($job -and (Test-Path -LiteralPath $ledgerPath)){
                foreach($line in Get-Content -LiteralPath $ledgerPath){if([string]::IsNullOrWhiteSpace($line)){continue};try{$row=$line|ConvertFrom-Json;if([string]$row.job_id -eq [string]$job.job_id -and [string]$row.status -eq 'submitted'){$locallyReconciled=$true;break}}catch{}}
            }
            $track=$null
            if($locallyReconciled -and $result -and ([bool]$result.submitted -or [string]$result.status -eq 'submitted')){
                $track=Call-FreeHire 'PATCH' "jobs/$([Uri]::EscapeDataString($slug))/track" $null ([ordered]@{stage=[string]$stageMap[$signal];notes="Synced from exact linked application mail $externalId"}) 'required' 'free' 0
                if([string]$track.status -eq 'ok'){$mailStageUpdates++}
            }
            $newSidecar=[ordered]@{
                version=1;public_slug=$slug;last_sync_at=$now.ToString('o');last_mail_signal=$signal
                mail_external_ids=@($seenIds+$externalId|Sort-Object -Unique);remote_stage=if($track -and [string]$track.status -eq 'ok'){[string]$stageMap[$signal]}elseif($locallyReconciled){'sync-failed'}else{'pending-local-reconcile'}
                remote_applied_at=if($sidecar){$sidecar.remote_applied_at}else{$null};remote_apply_status=if($sidecar){$sidecar.remote_apply_status}else{$null};remote_track_status=if($track){[string]$track.status}elseif($sidecar){$sidecar.remote_track_status}else{$null};error_code=if($track -and [string]$track.status -ne 'ok'){[string]$track.error_code}elseif($sidecar){$sidecar.error_code}else{$null}
                local_ledger_authoritative=$true
            }
            Write-JsonAtomic $sidecarPath $newSidecar 12; $mailEvents++
        }
    }

    $context=[ordered]@{
        version=1;status='complete';authenticated=$authenticated;fetched_at=$now.ToString('o');next_sync_after=$now.AddMinutes([Math]::Max(5,$syncMinutes)).ToString('o')
        autofill=if([string]$autofill.status -eq 'ok'){$autofill.data}else{$null};screening=if([string]$screening.status -eq 'ok'){$screening.data}else{$null};candidate_conflicts=@($candidateConflicts)
        credits=if([string]$credits.status -eq 'ok'){$credits.data}else{$null};credit_history_hashes=$creditHashes;new_credit_debits=$newDebits;credit_anomaly=($newDebits.Count -gt 0)
        market_coverage=if($coverage -and [string]$coverage.status -eq 'ok'){$coverage.data}else{$null};gmail=if([string]$gmail.status -eq 'ok'){$gmail.data}else{$null}
        mail=[ordered]@{mailbox_verified=$mailboxVerified;sync_status=if($gmailSync){[string]$gmailSync.status}else{'not-run'};inbox_status=if($inbox){[string]$inbox.status}else{'not-run'};exact_events=$mailEvents;submission_proofs=$mailProofs;stage_updates=$mailStageUpdates}
        policy=[ordered]@{ai_credits_allowed=$false;local_ledger_authoritative=$true;mail_mode=$mailMode}
    }
    Write-JsonAtomic $contextPath $context 50
    $output=[ordered]@{status='complete';authenticated=$authenticated;next_sync_after=$context.next_sync_after;match_profile=[bool]$context.autofill;screening=[bool]$context.screening;candidate_conflicts=$candidateConflicts.Count;market_coverage=[bool]$context.market_coverage;gmail_connected=[bool]($context.gmail -and $context.gmail.connected);mail_events=$mailEvents;submission_proofs=$mailProofs;stage_updates=$mailStageUpdates;credit_anomaly=[bool]$context.credit_anomaly}
    $output|ConvertTo-Json -Compress -Depth 10
}finally{if($null -ne $lock){$lock.Dispose()}}
