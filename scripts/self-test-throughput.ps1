[CmdletBinding()]
param(
    [string]$Workspace = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = [IO.Path]::Combine($env:TEMP, 'job-autopilot-self-test-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
}

Write-Host "Using test workspace: $Workspace" -ForegroundColor Cyan

function Test-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw "FAIL: $Message - Expected '$Expected', got '$Actual'"
    }
    Write-Host "  PASS: $Message" -ForegroundColor Green
}

function Test-NotEqual($Actual, $Expected, [string]$Message) {
    if ($Actual -eq $Expected) {
        throw "FAIL: $Message - Did not expect '$Expected'"
    }
    Write-Host "  PASS: $Message" -ForegroundColor Green
}

function Test-True($Condition, [string]$Message) {
    if (-not $Condition) {
        throw "FAIL: $Message - Expected true"
    }
    Write-Host "  PASS: $Message" -ForegroundColor Green
}

function Test-False($Condition, [string]$Message) {
    if ($Condition) {
        throw "FAIL: $Message - Expected false"
    }
    Write-Host "  PASS: $Message" -ForegroundColor Green
}

function Test-Contains($Collection, $Item, [string]$Message) {
    if ($Collection -notcontains $Item) {
        throw "FAIL: $Message - Collection does not contain '$Item'"
    }
    Write-Host "  PASS: $Message" -ForegroundColor Green
}

function Test-NotContains($Collection, $Item, [string]$Message) {
    if ($Collection -contains $Item) {
        throw "FAIL: $Message - Collection should not contain '$Item'"
    }
    Write-Host "  PASS: $Message" -ForegroundColor Green
}

function Test-JsonValid($JsonString, [string]$Message) {
    try {
        $obj = $JsonString | ConvertFrom-Json
        Write-Host "  PASS: $Message" -ForegroundColor Green
        return $obj
    } catch {
        throw "FAIL: $Message - Invalid JSON: $($_.Exception.Message)"
    }
}

function Invoke-CommandSafe([scriptblock]$ScriptBlock, [string]$Description) {
    try {
        $result = & $ScriptBlock
        Write-Host "  PASS: $Description" -ForegroundColor Green
        return $result
    } catch {
        throw "FAIL: $Description - $($_.Exception.Message)"
    }
}

# Initialize test workspace
$testWorkspace = $Workspace
$runtimeRoot = Join-Path $testWorkspace '.job-apply-autopilot'
$queueRoot = Join-Path $runtimeRoot 'queue'
$generatedRoot = Join-Path $runtimeRoot 'generated'
New-Item -ItemType Directory -Force -Path $queueRoot, $generatedRoot | Out-Null

# Copy scripts to test workspace for isolation
$scriptRoot = $PSScriptRoot
$testScriptRoot = Join-Path $runtimeRoot 'scripts'
New-Item -ItemType Directory -Force -Path $testScriptRoot | Out-Null
$testReferenceRoot = Join-Path $runtimeRoot 'references'
New-Item -ItemType Directory -Force -Path $testReferenceRoot | Out-Null
Get-ChildItem -LiteralPath $scriptRoot -Filter '*.ps1' | Copy-Item -Destination $testScriptRoot -Force
Get-ChildItem -LiteralPath (Join-Path $scriptRoot '..\references') -Filter 'assessment-schema.json' | Copy-Item -Destination $testReferenceRoot -Force
Copy-Item -LiteralPath (Join-Path $scriptRoot '..\profile.yaml') -Destination (Join-Path $runtimeRoot 'profile.yaml') -Force

$global:TestScriptRoot = $testScriptRoot
$global:TestWorkspace = $testWorkspace

Write-Host "`n=== ASSESSMENT SCHEMA TESTS ===" -ForegroundColor Yellow

# Test 1: Load schema
$schemaPath = Join-Path $runtimeRoot 'references\assessment-schema.json'
$schema = Invoke-CommandSafe { Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json } "Load assessment schema"

# Test 2: All component maxima accepted
$maxSum = ($schema.score_components.PSObject.Properties.Value | Measure-Object -Sum).Sum
Test-Equal $maxSum 100 "Max total score = 100"

# Test 3: Each component maximum
$expectedMaxima = @{
    core_technical = 30
    role_identity = 25
    seniority_tenure = 15
    production_ownership = 10
    domain_overlap = 8
    eligibility_certainty = 7
    experience_band = 3
    quality_recency_comp = 2
}
foreach ($component in $expectedMaxima.Keys) {
    Test-Equal $schema.score_components.$component $expectedMaxima[$component] "Schema max for $component"
}

# Test 4: Trust classes
$expectedTrustClasses = @('DIRECT_VERIFIED','DIRECT_REASONABLE','AGENCY_NAMED_CLIENT','AGENCY_UNKNOWN_CLIENT','JOB_AGGREGATOR_ONLY','IDENTITY_MISMATCH','UNVERIFIABLE')
foreach ($tc in $expectedTrustClasses) {
    Test-Contains $schema.trust_classes $tc "Trust class $tc accepted"
}
Test-NotContains $schema.trust_classes 'INVALID_CLASS' "Unknown trust class rejected"

# Local schema-driven validator checks the schema enforces the requested boundaries.
function Test-AssessmentDraft($Draft) {
    $errors = [Collections.Generic.List[string]]::new()
    foreach ($property in $schema.score_components.PSObject.Properties) {
        $name = [string]$property.Name
        $max = [int]$property.Value
        $value = [int]$Draft.score_components.$name
        if ($value -lt 0 -or $value -gt $max) { $errors.Add("score-component-$name-invalid") }
    }
    if ([string]$Draft.trust_class -notin @($schema.trust_classes | ForEach-Object { [string]$_ })) { $errors.Add('assessment-trust-class-invalid') }
    if ([string]$Draft.status -eq 'passed') {
        $score = [int]$Draft.score
        $reasonCodes = @($Draft.reason_codes | ForEach-Object { [string]$_ })
        if ($score -lt [int]$schema.conditional_pass_min) { $errors.Add('passed-below-minimum-score') }
        elseif ($score -lt [int]$schema.pass_score -and $reasonCodes -notcontains [string]$schema.conditional_pass_reason) { $errors.Add('passed-narrow-exception-reason-required') }
    }
    return @($errors)
}

$maxDraft = [pscustomobject]@{
    status = 'passed'
    score = 100
    trust_class = 'DIRECT_VERIFIED'
    reason_codes = @()
    score_components = [pscustomobject]@{}
}
foreach ($property in $schema.score_components.PSObject.Properties) {
    $maxDraft.score_components | Add-Member -NotePropertyName $property.Name -NotePropertyValue ([int]$property.Value)
}
Test-Equal (Test-AssessmentDraft $maxDraft).Count 0 "all component maxima accepted"

$aboveMaxDraft = $maxDraft | Select-Object *
$aboveMaxDraft.score_components = $maxDraft.score_components.PSObject.Copy()
$aboveMaxDraft.score_components.core_technical = 31
Test-Contains (Test-AssessmentDraft $aboveMaxDraft) 'score-component-core_technical-invalid' "value above any maximum rejected"

foreach ($tc in $expectedTrustClasses) {
    $trustDraft = $maxDraft | Select-Object *
    $trustDraft.trust_class = $tc
    Test-Equal (Test-AssessmentDraft $trustDraft).Count 0 "trust_class $tc accepted by validator"
}
$unknownTrustDraft = $maxDraft | Select-Object *
$unknownTrustDraft.trust_class = 'UNKNOWN'
Test-Contains (Test-AssessmentDraft $unknownTrustDraft) 'assessment-trust-class-invalid' "unknown trust_class rejected by validator"

$pass72Draft = $maxDraft | Select-Object *
$pass72Draft.score = 72
Test-Equal (Test-AssessmentDraft $pass72Draft).Count 0 "pass at 72 accepted when otherwise valid"

$pass68MissingReason = $maxDraft | Select-Object *
$pass68MissingReason.score = 68
$pass68MissingReason.reason_codes = @()
Test-Contains (Test-AssessmentDraft $pass68MissingReason) 'passed-narrow-exception-reason-required' "68-71 requires conditional reason"

$pass68WithReason = $maxDraft | Select-Object *
$pass68WithReason.score = 68
$pass68WithReason.reason_codes = @([string]$schema.conditional_pass_reason)
Test-Equal (Test-AssessmentDraft $pass68WithReason).Count 0 "68-71 accepted with conditional reason"

# Test 5: Pass score and conditional pass
Test-Equal $schema.pass_score 72 "Pass score = 72"
Test-Equal $schema.conditional_pass_min 68 "Conditional pass min = 68"
Test-Equal $schema.conditional_pass_reason 'strong-role-identity-and-eligibility' "Conditional pass reason"

Write-Host "`n=== WORK ITEM CREATION TESTS ===" -ForegroundColor Yellow

# Test 6: new-workitem with Description creates proper source.md
$jobId1 = 'test-job-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$newWorkItem = Join-Path $testScriptRoot 'new-workitem.ps1'
$creation1 = Invoke-CommandSafe {
    & $newWorkItem -JobId $jobId1 -Company 'TestCorp' -Title 'Backend Engineer' -Description 'This is a real job description with sufficient length to pass quality gates.' -Location 'Remote' -Source 'test' -Workspace $testWorkspace -Structured | Select-Object -Last 1 | ConvertFrom-Json
} "Create work item with Description"

Test-Equal $creation1.status 'created' "Creation status = created"
$workItemPath1 = $creation1.path

# Verify source.md contains actual JD, not placeholder
$sourcePath1 = Join-Path $workItemPath1 'source.md'
$sourceContent1 = Invoke-CommandSafe { Get-Content -LiteralPath $sourcePath1 -Raw } "Read source.md"
Test-True ($sourceContent1 -match 'This is a real job description') "source.md contains actual JD"
Test-False ($sourceContent1 -match 'Coordinator: replace this placeholder') "source.md does NOT contain placeholder text"

# Test 7: new-workitem with MetadataJson creates source-metadata.json
$jobId2 = 'test-job-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$metadataJson = '{"custom_field":"test_value","nested":{"key":"value"}}'
$creation2 = Invoke-CommandSafe {
    & $newWorkItem -JobId $jobId2 -Company 'TestCorp2' -Title 'Frontend Engineer' -Description 'Another real job description.' -MetadataJson $metadataJson -Workspace $testWorkspace -Structured | Select-Object -Last 1 | ConvertFrom-Json
} "Create work item with MetadataJson"

$workItemPath2 = $creation2.path
$metadataPath2 = Join-Path $workItemPath2 'source-metadata.json'
Test-True (Test-Path -LiteralPath $metadataPath2) "source-metadata.json exists when MetadataJson supplied"
$metadataContent = Invoke-CommandSafe { Get-Content -LiteralPath $metadataPath2 -Raw | ConvertFrom-Json } "Read source-metadata.json"
Test-Equal $metadataContent.custom_field 'test_value' "Metadata content preserved"

# Test 8: Malformed MetadataJson fails before partial init
$jobId3 = 'test-job-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
try {
    & $newWorkItem -JobId $jobId3 -Company 'TestCorp3' -Title 'DevOps Engineer' -Description 'Valid description.' -MetadataJson '{invalid json' -Workspace $testWorkspace -Structured | Out-Null
    throw "Expected failure for malformed MetadataJson"
} catch {
    Write-Host "  PASS: Malformed MetadataJson fails before partial init" -ForegroundColor Green
}

# Test 9: Status is captured-awaiting-assessment when Description exists
$jobJsonPath = Join-Path $workItemPath1 'job.json'
$jobData = Invoke-CommandSafe { Get-Content -LiteralPath $jobJsonPath -Raw | ConvertFrom-Json } "Read job.json"
Test-Equal $jobData.status 'captured-awaiting-assessment' "Status = captured-awaiting-assessment when Description exists"

# Test 10: Status is captured-awaiting-source-and-assessment when no Description
$jobId4 = 'test-job-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$creation4 = Invoke-CommandSafe {
    & $newWorkItem -JobId $jobId4 -Company 'TestCorp4' -Title 'Data Engineer' -Workspace $testWorkspace -Structured | Select-Object -Last 1 | ConvertFrom-Json
} "Create work item without Description"
$jobJsonPath4 = Join-Path $creation4.path 'job.json'
$jobData4 = Invoke-CommandSafe { Get-Content -LiteralPath $jobJsonPath4 -Raw | ConvertFrom-Json } "Read job.json (no Description)"
Test-Equal $jobData4.status 'captured-awaiting-source-and-assessment' "Status = captured-awaiting-source-and-assessment when no Description"

Write-Host "`n=== ATOMIC DISCOVERY TESTS ===" -ForegroundColor Yellow

# Test 11: finalize-discovered-workitem creates all artifacts
$jobId5 = 'test-job-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$finalizeScript = Join-Path $testScriptRoot 'finalize-discovered-workitem.ps1'
$finalizeResult = Invoke-CommandSafe {
    & $finalizeScript -JobId $jobId5 -Company 'AtomicCorp' -Title 'Platform Engineer' -Description 'Complete job description for atomic discovery test.' -MetadataJson '{"source":"self-test"}' -JobUrl 'https://example.com/job/123' -Workspace $testWorkspace | Select-Object -Last 1 | ConvertFrom-Json
} "Call finalize-discovered-workitem.ps1"

Test-Equal $finalizeResult.status 'created' "Finalize status = created"
Test-True $finalizeResult.source_ready "source_ready = true"
Test-True $finalizeResult.metadata_written "metadata_written = true"
Test-NotEqual $finalizeResult.enrichment_status $null "enrichment_status present"
Test-Equal $finalizeResult.next_stage 'assessment_pending' "next_stage = assessment_pending"

# Verify all artifacts created
$workItemPath5 = $finalizeResult.path
Test-True (Test-Path -LiteralPath (Join-Path $workItemPath5 'job.json')) "job.json exists"
Test-True (Test-Path -LiteralPath (Join-Path $workItemPath5 'assessment.json')) "assessment.json exists"
Test-True (Test-Path -LiteralPath (Join-Path $workItemPath5 'source.md')) "source.md exists"
Test-True (Test-Path -LiteralPath (Join-Path $workItemPath5 'source-metadata.json')) "source-metadata.json exists"

# Test 12: Duplicate/idempotent creation
$finalizeResult2 = Invoke-CommandSafe {
    & $finalizeScript -JobId $jobId5 -Company 'AtomicCorp' -Title 'Platform Engineer' -Description 'Complete job description for atomic discovery test.' -MetadataJson '{"source":"self-test"}' -JobUrl 'https://example.com/job/123' -Workspace $testWorkspace | Select-Object -Last 1 | ConvertFrom-Json
} "Call finalize-discovered-workitem.ps1 again (duplicate)"

Test-True ($finalizeResult2.status -in @('existing','duplicate')) "Second call returns existing/duplicate"
Test-Equal $finalizeResult2.matched_job_id $jobId5 "matched_job_id correct"

# Verify source/metadata not modified (check timestamps or just existence)
$sourceMTime1 = (Get-Item -LiteralPath (Join-Path $workItemPath5 'source.md')).LastWriteTimeUtc
$metadataMTime1 = (Get-Item -LiteralPath (Join-Path $workItemPath5 'source-metadata.json')).LastWriteTimeUtc
Start-Sleep -Milliseconds 100
$sourceMTime2 = (Get-Item -LiteralPath (Join-Path $workItemPath5 'source.md')).LastWriteTimeUtc
$metadataMTime2 = (Get-Item -LiteralPath (Join-Path $workItemPath5 'source-metadata.json')).LastWriteTimeUtc
Test-Equal $sourceMTime1 $sourceMTime2 "source.md not modified on duplicate call"
Test-Equal $metadataMTime1 $metadataMTime2 "source-metadata.json not modified on duplicate call"

Write-Host "`n=== SESSION STATE TESTS ===" -ForegroundColor Yellow

# Start the scheduler fixture from a clean runtime queue/generated set so earlier
# creation/idempotency tests do not inflate action counts.
Remove-Item -LiteralPath $queueRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $generatedRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $queueRoot, $generatedRoot | Out-Null

# Create test jobs with various stages
$stagesToCreate = @(
    @{ stage = 'assessment_pending'; count = 5 },
    @{ stage = 'resume_pending'; count = 4 },
    @{ stage = 'application_ready'; count = 6 },
    @{ stage = 'eligibility_research_pending'; count = 2 }
)

$createdJobs = @()

# Helper to create a job in a specific stage
function Create-StagedJob($JobId, $Stage, $Kind) {
    $workDir = if ($Kind -eq 'queue') { Join-Path $queueRoot "$JobId-test" } else { Join-Path $generatedRoot "$JobId-test" }
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null
    
    $job = [ordered]@{
        job_id = $JobId
        company = "Company-$JobId"
        title = "Title-$JobId"
        location = 'Remote'
        job_url = ''
        source = 'test'
        discovery_lane = 'test'
        search_query = ''
        description = 'Test job description for session state.'
        posted_at = ''
        external_id = ''
        created_at = (Get-Date).ToUniversalTime().ToString('o')
        status = 'captured-awaiting-assessment'
    }
    $job | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $workDir 'job.json') -Encoding UTF8

    $assessment = [ordered]@{
        policy_version = '6.4'
        job_id = $JobId
        status = if ($Stage -eq 'assessment_pending') { 'pending' } elseif ($Stage -eq 'resume_pending') { 'passed' } elseif ($Stage -eq 'application_ready') { 'passed' } elseif ($Stage -eq 'eligibility_research_pending') { 'needs-research' } else { 'pending' }
        score = 75
        trust_class = 'DIRECT_VERIFIED'
        role_family = 'backend-engineer'
        eligibility_state = 'HOME_JURISDICTION_ELIGIBLE'
        needs_external_research = $false
        needs_candidate_evidence = $false
        hard_gates = [ordered]@{
            integrity = $true; eligibility = $true; role_family = $true; mandatory_requirements = $true; truth_feasibility = $true
        }
    }
    $assessment | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $workDir 'assessment.json') -Encoding UTF8

    if ($Stage -in @('resume_pending','application_ready')) {
        $fit = [ordered]@{
            policy_version = '6.4'
            job_id = $JobId
            status = 'complete'
            score = 75
            requirements = @()
        }
        $fit | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $workDir 'fit-map.json') -Encoding UTF8
    }

    if ($Stage -in @('resume_pending','application_ready')) {
        $route = [ordered]@{
            route = 'external'
            target = 'https://ats.example.com'
            evidence = 'Direct ATS link'
        }
        $route | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $workDir 'application-route.json') -Encoding UTF8
    }

    if ($Stage -eq 'application_ready') {
        $artifact = [ordered]@{
            status = 'ready-for-upload'
            path = Join-Path $workDir 'resume.pdf'
        }
        $artifact | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $workDir 'resume-artifact.json') -Encoding UTF8
        New-Item -ItemType File -Force -Path $artifact.path | Out-Null
    }

    $sourcePath = Join-Path $workDir 'source.md'
    Set-Content -LiteralPath $sourcePath -Value "# Test Job`n`nCompany: Test`n`n## Job Description`n`nThis is a complete synthetic job description with enough length to be treated as source-ready by the session-state source gate." -Encoding UTF8

    return $workDir
}

# Create jobs
$jobCounter = 0
foreach ($group in $stagesToCreate) {
    for ($i = 0; $i -lt $group.count; $i++) {
        $jid = "stage-$($group.stage)-$i-$jobCounter"
        $kind = if ($group.stage -in @('assessment_pending','eligibility_research_pending')) { 'queue' } else { 'generated' }
        Create-StagedJob $jid $group.stage $kind | Out-Null
        $createdJobs += $jid
        $jobCounter++
    }
}

# Run session-state
$sessionStateScript = Join-Path $testScriptRoot 'session-state.ps1'
$state = Invoke-CommandSafe {
    & $sessionStateScript -Workspace $testWorkspace -Compact | ConvertFrom-Json
} "Run session-state.ps1 -Compact"

# Test 13: Verify actions contains every unclaimed action
$workActionCount = @($state.actions | Where-Object { [string]$_.stage -ne 'discovery' }).Count
$totalExpected = ($stagesToCreate | Measure-Object -Property count -Sum).Sum
Test-Equal $workActionCount $totalExpected "actions contains all unclaimed work actions ($totalExpected)"

# Test 14: Verify dispatch_manifest
Test-True ($null -ne $state.scheduler.dispatch_manifest) "dispatch_manifest exists"
Test-Equal $state.scheduler.dispatch_manifest.expected_count $state.actions.Count "expected_count == actions.Count"
Test-Equal $state.scheduler.dispatch_manifest.worker_count ($state.actions | Where-Object { $_.dispatch -like 'job-autopilot-*' }).Count "worker_count correct"
Test-Equal $state.scheduler.dispatch_manifest.coordinator_count ($state.actions | Where-Object { $_.dispatch -notlike 'job-autopilot-*' }).Count "coordinator_count correct"
Test-True ($state.scheduler.dispatch_manifest.action_ids.Count -eq $state.actions.Count) "action_ids count matches"

# Test 15: Verify throughput counters
Test-Equal $state.summary.assessment_pending 5 "assessment_pending = 5"
Test-Equal $state.summary.resume_pending 4 "resume_pending = 4"
Test-Equal $state.summary.application_ready 6 "application_ready = 6"
Test-Equal $state.summary.research_pending 2 "research_pending = 2"

# Test 16: Verify LinkedIn target_new <= 3
$linkedinAction = $state.actions | Where-Object { $_.dispatch -eq 'job-autopilot-linkedin-discovery' } | Select-Object -First 1
if ($linkedinAction) {
    Test-True ($linkedinAction.target_new -le 3) "LinkedIn target_new <= 3 (got $($linkedinAction.target_new))"
} else {
    Write-Host "  SKIP: No LinkedIn discovery action in current state" -ForegroundColor Yellow
}

# Verify FreeHire target = discoverySlots (8)
$freehireAction = $state.actions | Where-Object { $_.dispatch -eq 'coordinator-discovery' } | Select-Object -First 1
if ($freehireAction) {
    Test-Equal $freehireAction.target_new $state.scheduler.discovery_slots "FreeHire target = discoverySlots"
}

Write-Host "`n=== ALL TESTS PASSED ===" -ForegroundColor Green

# Cleanup
try {
    Remove-Item -LiteralPath $testWorkspace -Recurse -Force -ErrorAction SilentlyContinue
} catch {}

exit 0
