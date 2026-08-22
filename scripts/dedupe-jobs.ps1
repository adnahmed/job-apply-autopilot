[CmdletBinding(DefaultParameterSetName='Ids')]
param(
    [Parameter(Mandatory=$true, ParameterSetName='Ids')][string]$JobIdsCsv,
    [Parameter(Mandatory=$true, ParameterSetName='Json')][string]$CandidatesJson,
    [Parameter(Mandatory=$true, ParameterSetName='File')][string]$CandidatesFile,
    [string]$Workspace = (Get-Location).Path,
    [int]$SubmissionWindowDays = 45
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'job-identity.ps1')

if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = (Get-Location).Path }
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$root = Join-Path $Workspace '.job-apply-autopilot'
if (-not (Test-Path -LiteralPath $root)) { throw "No job-apply-autopilot runtime at $root" }

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

switch ($PSCmdlet.ParameterSetName) {
    'Ids' {
        $candidates = @($JobIdsCsv.Split(',') | ForEach-Object {
            $id = $_.Trim()
            if ($id) { [pscustomobject]@{ job_id=$id; company=''; title='' } }
        })
    }
    'Json' { $candidates = @(ConvertFrom-Json -InputObject $CandidatesJson) }
    'File' {
        $CandidatesFile = (Resolve-Path -LiteralPath $CandidatesFile).Path
        $candidates = @(Get-Content -LiteralPath $CandidatesFile -Raw | ConvertFrom-Json)
    }
}

$result = [ordered]@{}
foreach ($candidate in $candidates) {
    $id = [string]$candidate.job_id
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    $result[$id] = [ordered]@{
        job_id = $id
        company = [string]$candidate.company
        title = [string]$candidate.title
        seen = $false
        reason = $null
        matched_job_id = $null
        locations = @()
        ledger_status = $null
    }
}

function Mark-Seen([string]$CandidateId, [string]$Reason, [string]$Location, [string]$MatchedJobId, [string]$LedgerStatus = '') {
    if (-not $result.Contains($CandidateId)) { return }
    $entry = $result[$CandidateId]
    $entry.seen = $true
    if (-not $entry.reason -or $Reason -like 'exact-*') { $entry.reason = $Reason }
    if (-not $entry.matched_job_id -or $Reason -like 'exact-*') { $entry.matched_job_id = $MatchedJobId }
    $entry.locations = @($entry.locations) + $Location
    if ($LedgerStatus) { $entry.ledger_status = $LedgerStatus }
}

# Dedupe within the incoming batch before touching persistent state.
for ($i = 0; $i -lt $candidates.Count; $i++) {
    for ($j = 0; $j -lt $i; $j++) {
        $match = Test-JobIdentityMatch $candidates[$i] $candidates[$j]
        if ([bool]$match.matched) {
            Mark-Seen ([string]$candidates[$i].job_id) 'semantic-batch' 'candidate-batch' ([string]$candidates[$j].job_id)
            break
        }
    }
}

$cutoff = [DateTimeOffset]::UtcNow.AddDays(-1 * [math]::Abs($SubmissionWindowDays))
$ledger = Join-Path $root 'applications.jsonl'
if (Test-Path -LiteralPath $ledger) {
    foreach ($line in Get-Content -LiteralPath $ledger) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $row = $line | ConvertFrom-Json
            $rowId = [string]$row.job_id
            if ($result.Contains($rowId)) {
                Mark-Seen $rowId 'exact-ledger' 'ledger' $rowId ([string]$row.status)
            }

            $submitted = ([string]$row.status -eq 'submitted' -or $row.submitted -eq $true)
            if (-not $submitted) { continue }
            $recent = $true
            if ($row.timestamp) {
                try {
                    $rowTime = if ($row.timestamp -is [DateTime]) { ([DateTimeOffset]$row.timestamp).ToUniversalTime() } else { [DateTimeOffset]::Parse(([string]$row.timestamp), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() }
                    $recent = ($rowTime -ge $cutoff)
                } catch {}
            }
            if (-not $recent) { continue }
            foreach ($candidate in $candidates) {
                $candidateId = [string]$candidate.job_id
                if ($candidateId -ne $rowId -and [bool](Test-JobIdentityMatch $candidate $row).matched) {
                    Mark-Seen $candidateId 'semantic-submission' 'ledger' $rowId ([string]$row.status)
                }
            }
        } catch {}
    }
}

foreach ($kind in @('queue','generated')) {
    $dir = Join-Path $root $kind
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($child in Get-ChildItem -LiteralPath $dir -Directory) {
        $job = Read-JsonSafe (Join-Path $child.FullName 'job.json')
        $rowId = if ($job -and $job.job_id) { [string]$job.job_id } else { $child.Name.Split('-')[0] }
        if ($result.Contains($rowId)) {
            Mark-Seen $rowId "exact-$kind" $kind $rowId
        }
        if ($job) {
            $metadata = Read-JsonSafe (Join-Path $child.FullName 'source-metadata.json')
            if (-not ($job.PSObject.Properties.Name -contains 'description') -or [string]::IsNullOrWhiteSpace([string]$job.description)) {
                $sourcePath = Join-Path $child.FullName 'source.md'
                if ($metadata -and $metadata.description) { $job | Add-Member -NotePropertyName description -NotePropertyValue ([string]$metadata.description) -Force }
                elseif (Test-Path -LiteralPath $sourcePath) { $job | Add-Member -NotePropertyName description -NotePropertyValue (Get-Content -LiteralPath $sourcePath -Raw) -Force }
            }
            foreach ($name in @('posted_at','external_id')) {
                if ($metadata -and $metadata.raw -and $metadata.raw.PSObject.Properties.Name -contains $name -and -not ($job.PSObject.Properties.Name -contains $name)) {
                    $job | Add-Member -NotePropertyName $name -NotePropertyValue $metadata.raw.$name -Force
                }
            }
            foreach ($candidate in $candidates) {
                $candidateId = [string]$candidate.job_id
                if ($candidateId -ne $rowId -and [bool](Test-JobIdentityMatch $candidate $job).matched) {
                    Mark-Seen $candidateId "semantic-workitem" $kind $rowId
                }
            }
        }
    }
}

$json = @($result.Values) | ConvertTo-Json -Depth 6 -Compress
Write-Output $json
