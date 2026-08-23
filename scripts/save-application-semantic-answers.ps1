[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][string]$AnswersJson
)

$ErrorActionPreference = 'Stop'
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path

function Write-JsonAtomic([string]$Path, $Value, [int]$Depth = 10) {
    $temp = "$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $temp -Encoding UTF8
        [IO.File]::Move($temp, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Normalize-Key([string]$Question, [string]$Type, [array]$Options) {
    $base = ($Question -replace '[^a-z0-9]+',' ' -replace '\s+',' ').Trim().ToLowerInvariant()
    $typeNorm = ($Type -replace '[^a-z0-9]+','').ToLowerInvariant()
    $optionsNorm = @($Options | ForEach-Object { ($_ -replace '[^a-z0-9]+','').ToLowerInvariant() } | Sort-Object) -join ','
    return "$base|$typeNorm|$optionsNorm"
}

$answersPath = Join-Path $WorkItemDir 'application-semantic-answers.json'

$newAnswers = $AnswersJson | ConvertFrom-Json
if (-not $newAnswers -or -not $newAnswers.answers -or $newAnswers.answers.Count -eq 0) {
    [ordered]@{status='saved';count=0} | ConvertTo-Json -Compress
    exit 0
}

$existing = @{version=1;answers=@()}
if (Test-Path -LiteralPath $answersPath) {
    try { $existing = Get-Content -LiteralPath $answersPath -Raw | ConvertFrom-Json } catch { $existing = @{version=1;answers=@()} }
}

$existingMap = @{}
foreach ($a in $existing.answers) {
    $key = Normalize-Key $a.question $a.type $a.options
    $existingMap[$key] = $a
}

$updated = 0
$added = 0
foreach ($new in $newAnswers.answers) {
    $key = Normalize-Key $new.question $new.type $new.options
    $entry = [ordered]@{
        key = $key
        question = [string]$new.question
        type = [string]$new.type
        options = @($new.options)
        value = [string]$new.value
        category = [string]$new.category
        updated_at = [DateTimeOffset]::UtcNow.ToString('o')
    }
    if ($existingMap.ContainsKey($key)) {
        $existingMap[$key] = $entry
        $updated++
    } else {
        $existingMap[$key] = $entry
        $added++
    }
}

$merged = [ordered]@{
    version = 1
    answers = @($existingMap.Values)
}

Write-JsonAtomic $answersPath $merged 10
[ordered]@{status='saved';count=$merged.answers.Count} | ConvertTo-Json -Compress