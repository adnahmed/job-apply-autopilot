[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir
)

$ErrorActionPreference = 'Stop'
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
$planPath = Join-Path $WorkItemDir 'application-answer-plan.json'
$outPath = Join-Path $WorkItemDir 'application-preflight.json'

function Write-JsonAtomic([string]$Path, $Value, [int]$Depth = 10) {
    $temp = "$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $temp -Encoding UTF8
        [IO.File]::Move($temp, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

if (-not (Test-Path -LiteralPath $planPath)) {
    [ordered]@{status='unavailable';reason_code='answer-plan-missing';questions=0;results=@()} | ConvertTo-Json -Compress
    exit 0
}

try { $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json }
catch {
    [ordered]@{status='unavailable';reason_code='answer-plan-invalid';questions=0;results=@()} | ConvertTo-Json -Compress
    exit 0
}

$questions = [Collections.Generic.List[object]]::new()
foreach ($basic in @($plan.basics)) {
    if ($basic -is [string]) {
        if ([string]$basic -match '(?i)(resume|(^|[^a-z])cv([^a-z]|$)|cover.?letter|attachment|file)') { continue }
        $questions.Add([pscustomobject]@{label=[string]$basic;type='text';required=$true})
    } else {
        if ([string]$basic.type -match '(?i)file|upload' -or [string]$basic.label -match '(?i)resume|cv|cover.?letter') { continue }
        $questions.Add($basic)
    }
}
foreach ($question in @($plan.questions)) {
    if ([string]$question.type -match '(?i)file|upload') { continue }
    $questions.Add($question)
}

$resolver = Join-Path $PSScriptRoot 'resolve-application-answer.ps1'
$results = [Collections.Generic.List[object]]::new()
foreach ($question in $questions) {
    $questionJson = $question | ConvertTo-Json -Compress -Depth 8
    try {
        $resolution = (& $resolver -WorkItemDir $WorkItemDir -QuestionJson $questionJson -NoLoopTrack | Select-Object -Last 1) | ConvertFrom-Json
    } catch {
        $resolution = [pscustomobject]@{status='needs-semantic-answer';value=$null;category='workflow';reason_code='resolver-exception'}
    }
    $questionLabel = @([string]$question.label,[string]$question.question,[string]$question.text,[string]$question.name) -join ' '
    $results.Add([ordered]@{
        label = $questionLabel.Trim()
        required = if ($question.required -is [bool]) { [bool]$question.required } else { [string]$question.required -match '^(?i:true|1|yes|required)$' }
        status = [string]$resolution.status
        value = $resolution.value
        category = [string]$resolution.category
        source = [string]$resolution.source
        reason_code = [string]$resolution.reason_code
    })
}

$semantic = @($results | Where-Object { $_.status -in @('needs-semantic-answer','loop-detected') })
$status = if ($semantic.Count -gt 0) { 'needs-semantic-answer' } else { 'ready' }
$preflight = [ordered]@{
    version = 2
    status = $status
    questions = $results.Count
    answered = @($results | Where-Object { $_.status -eq 'answered' }).Count
    semantic_required = $semantic.Count
    results = @($results)
    resolved_at = [DateTimeOffset]::UtcNow.ToString('o')
}
Write-JsonAtomic $outPath $preflight 10
$preflight | ConvertTo-Json -Compress -Depth 10
