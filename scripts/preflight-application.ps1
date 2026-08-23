[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml')
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
$questionsJson = $questions | ConvertTo-Json -Compress -Depth 10
try {
    $raw = & $resolver -WorkItemDir $WorkItemDir -QuestionsJson $questionsJson -ProfilePath $ProfilePath -NoLoopTrack | Select-Object -Last 1
    $pageResult = $raw | ConvertFrom-Json
    if ($pageResult.status -eq 'resolved-page') {
        $results = @()
        foreach ($r in $pageResult.results) {
            $question = $questions[$r.index]
            $questionLabel = @([string]$question.label,[string]$question.question,[string]$question.text,[string]$question.name) -join ' '
            $results.Add([ordered]@{
                label = $questionLabel.Trim()
                required = if ($question.required -is [bool]) { [bool]$question.required } else { [string]$question.required -match '^(?i:true|1|yes|required)$' }
                status = [string]$r.status
                value = $r.value
                category = [string]$r.category
                source = [string]$r.source
                reason_code = [string]$r.reason_code
            })
        }
    } else {
        $preflight = [ordered]@{
            version = 2
            status = 'unavailable'
            reason_code = 'unexpected-answer-resolver-result'
            error = "Resolver returned status '$($pageResult.status)' instead of 'resolved-page'"
            questions = $questions.Count
            answered = 0
            semantic_required = 0
            results = @()
            resolved_at = [DateTimeOffset]::UtcNow.ToString('o')
        }
        Write-JsonAtomic $outPath $preflight 10
        $preflight | ConvertTo-Json -Compress -Depth 10
        exit 0
    }
} catch {
    $preflight = [ordered]@{
        version = 2
        status = 'unavailable'
        reason_code = 'answer-resolver-error'
        error = $_.Exception.Message
        questions = $questions.Count
        answered = 0
        semantic_required = 0
        results = @()
        resolved_at = [DateTimeOffset]::UtcNow.ToString('o')
    }
    Write-JsonAtomic $outPath $preflight 10
    $preflight | ConvertTo-Json -Compress -Depth 10
    exit 0
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
