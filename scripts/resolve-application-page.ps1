[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][string]$QuestionsJson,
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml')
)

$ErrorActionPreference = 'Stop'
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path

$questions = $QuestionsJson | ConvertFrom-Json
if (-not $questions -or -not $questions.Count) {
    Write-Output ([ordered]@{
        status = 'resolved-page'
        results = @()
    } | ConvertTo-Json -Compress -Depth 10)
    exit 0
}

$resolveScript = Join-Path $PSScriptRoot 'resolve-application-answer.ps1'
$results = @()

for ($i = 0; $i -lt $questions.Count; $i++) {
    $question = $questions[$i]
    $questionJson = $question | ConvertTo-Json -Compress -Depth 10
    $fieldId = if ($question.field_id) { [string]$question.field_id } elseif ($question.id) { [string]$question.id } elseif ($question.name) { [string]$question.name } else { "field-$i" }

    try {
        $raw = & $resolveScript -WorkItemDir $WorkItemDir -QuestionJson $questionJson -ProfilePath $ProfilePath | Select-Object -Last 1
        $result = $raw | ConvertFrom-Json
        $result.index = $i
        $result.field_id = $fieldId
        $results += $result
    } catch {
        $results += [ordered]@{
            index = $i
            field_id = $fieldId
            status = 'error'
            value = $null
            source = 'resolver-exception'
            category = 'resolver-error'
            reason_code = $_.Exception.Message
        }
    }
}

[ordered]@{
    status = 'resolved-page'
    results = $results
} | ConvertTo-Json -Compress -Depth 10 | Write-Output