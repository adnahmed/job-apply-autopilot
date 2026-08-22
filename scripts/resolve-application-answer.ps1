[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][string]$QuestionJson,
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml')
)
$ErrorActionPreference = 'Stop'
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
$question = if (Test-Path -LiteralPath $QuestionJson) { Get-Content -LiteralPath $QuestionJson -Raw | ConvertFrom-Json } else { $QuestionJson | ConvertFrom-Json }
$job = Get-Content -LiteralPath (Join-Path $WorkItemDir 'job.json') -Raw | ConvertFrom-Json
$metadataPath = Join-Path $WorkItemDir 'source-metadata.json'
$metadata = if (Test-Path -LiteralPath $metadataPath) { try { Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json } catch { $null } } else { $null }
$profile = Get-Content -LiteralPath $ProfilePath -Raw
function Scalar([string]$Name, $Default) { $pattern = '(?m)^\s*' + [regex]::Escape($Name) + ':\s*["'']?([^\r\n"'']+)'; if ($profile -match $pattern) { return $Matches[1].Trim() }; return $Default }
function Emit($Value,$Source,$Category='routine',$Details=$null) {
    $out = [ordered]@{ status='answered'; value=$Value; source=$Source; category=$Category }
    if ($Details) { foreach($property in $Details.GetEnumerator()) { $out[$property.Key]=$property.Value } }
    $out | ConvertTo-Json -Compress -Depth 8
    exit 0
}
function Convert-SalaryPeriod([double]$Value,[string]$From,[string]$To) {
    $factors = @{ year=1.0; month=12.0; day=260.0; hour=2080.0 }
    $fromKey = if ($factors.ContainsKey($From)) { $From } else { 'year' }
    $toKey = if ($factors.ContainsKey($To)) { $To } else { $fromKey }
    $annual = $Value * [double]$factors[$fromKey]
    return [math]::Round($annual / [double]$factors[$toKey],0)
}
$label = @([string]$question.label,[string]$question.question,[string]$question.text,[string]$question.name,[string]$question.placeholder,[string]$question.validation_error,[string]$question.pattern) -join ' '
$type = ([string]$question.type).ToLowerInvariant()
$options = @($question.options | ForEach-Object { if ($_ -is [string]) { $_ } elseif ($_.label) { [string]$_.label } elseif ($_.value) { [string]$_.value } })

if ($label -match '(?i)(?=.*(education|university|degree))(?=.*(start|from))(?=.*month)') { Emit ([int](Scalar 'start_month' 4)) 'profile.education' 'education-date' }
if ($label -match '(?i)(?=.*(education|university|degree))(?=.*(start|from))(?=.*year)') { Emit ([int](Scalar 'start_year' 2018)) 'profile.education' 'education-date' }
if ($label -match '(?i)(?=.*(education|university|degree))(?=.*(end|to|graduat))(?=.*month)') { Emit ([int](Scalar 'end_month' 3)) 'profile.education' 'education-date' }
if ($label -match '(?i)(?=.*(education|university|degree))(?=.*(end|to|graduat))(?=.*year)') { Emit ([int](Scalar 'end_year' 2023)) 'profile.education' 'education-date' }

if ($label -match '(?i)(current|present).*(salary|compensation|ctc)|salary.*history') {
    $decline = $options | Where-Object { $_ -match '(?i)prefer not|decline|not applicable|n/a' } | Select-Object -First 1
    if ($decline) { Emit $decline 'safe-decline-option' 'sensitive-disclosure' }
    [ordered]@{ status='blocked-protected-fact'; value=$null; source='truth-policy'; category='sensitive-disclosure'; reason_code='current-compensation-not-disclosed' } | ConvertTo-Json -Compress
    exit 0
}

if ($label -match '(?i)(expected|desired|salary expectation|compensation expectation|pay expectation|rate expectation)') {
    if ($type -match 'text|textarea' -and $label -notmatch '(?i)numeric|number|amount') { Emit (Scalar 'compensation_text' 'Negotiable; open to a market-competitive package.') 'profile.answer_policy' 'expected-compensation' }
    $min = if ($null -ne $question.salary_min) { [double]$question.salary_min } elseif ($null -ne $question.min_salary) { [double]$question.min_salary } elseif ($null -ne $job.salary_min) { [double]$job.salary_min } elseif ($metadata -and $null -ne $metadata.raw.salary_min) { [double]$metadata.raw.salary_min } else { $null }
    $max = if ($null -ne $question.salary_max) { [double]$question.salary_max } elseif ($null -ne $question.max_salary) { [double]$question.max_salary } elseif ($null -ne $job.salary_max) { [double]$job.salary_max } elseif ($metadata -and $null -ne $metadata.raw.salary_max) { [double]$metadata.raw.salary_max } else { $null }
    if ($null -ne $min) { $value = if ($null -ne $max -and $max -ge $min) { [math]::Round($min + ([double](Scalar 'posted_range_fraction' 0.25) * ($max-$min)),0) } else { [math]::Round($min,0) }; Emit $value 'posted-range-lower-quartile' 'expected-compensation' @{currency=[string]$question.currency;period=[string]$question.period} }
    $market = (& (Join-Path $PSScriptRoot 'get-market-salary.ps1') -WorkItemDir $WorkItemDir | Select-Object -Last 1) | ConvertFrom-Json
    if ([string]$market.status -eq 'available') {
        $desiredPeriod = if ($label -match '(?i)hour') { 'hour' } elseif ($label -match '(?i)month') { 'month' } elseif ($label -match '(?i)day') { 'day' } elseif ($label -match '(?i)year|annual') { 'year' } else { [string]$market.period }
        if (-not $desiredPeriod) { $desiredPeriod='year' }
        $marketValue = Convert-SalaryPeriod ([double]$market.value) ([string]$market.period) $desiredPeriod
        Emit $marketValue ([string]$market.source) 'expected-compensation' @{currency=[string]$market.currency;period=$desiredPeriod;sample_size=$market.sample_size;market_scope=$market.scope;country=$market.country;category=$market.category;seniority=$market.seniority}
    }
    $location = [string]$job.location
    if ($label -match '(?i)hour') { Emit ([int](Scalar 'global_remote_hourly_numeric' 30)) 'profile.global-remote-default' 'expected-compensation' }
    if ($label -match '(?i)month') { Emit ($(if ($location -match '(?i)pakistan|islamabad|rawalpindi|lahore|karachi') { [int](Scalar 'pakistan_local_unlabeled_numeric' 350000) } else { [int](Scalar 'global_remote_monthly_numeric' 5000) })) 'profile.location-default' 'expected-compensation' }
    if ($label -match '(?i)year|annual') { Emit ([int](Scalar 'global_remote_yearly_numeric' 60000)) 'profile.global-remote-default' 'expected-compensation' }
    if ($location -match '(?i)pakistan|islamabad|rawalpindi|lahore|karachi') { Emit ([int](Scalar 'pakistan_local_unlabeled_numeric' 350000)) 'profile.pakistan-local-default' 'expected-compensation' }
    Emit ([int](Scalar 'global_remote_yearly_numeric' 60000)) 'profile.global-remote-default' 'expected-compensation'
}

$decline = $options | Where-Object { $_ -match '(?i)prefer not|decline|not applicable|n/a' } | Select-Object -First 1
if ($label -match '(?i)gender|race|ethnic|veteran|disability|demographic') { if ($decline) { Emit $decline 'profile.optional-demographic-policy' 'optional-demographic' }; Emit 'Prefer not to answer' 'profile.optional-demographic-policy' 'optional-demographic' }
if ($label -match '(?i)background check|onsite|on-site|freelance|contract basis') { Emit 'Yes' 'profile.answer-policy' }
if ($label -match '(?i)notice period') { Emit 30 'profile.answer-policy' }
if ($label -match '(?i)start date|available to start') { Emit '30 days after offer' 'profile.answer-policy' }
if ($decline) { Emit $decline 'safe-decline-option' }
if (-not [bool]$question.required) { Emit '' 'optional-blank' }
if ($type -match 'number|numeric|integer') { $minimum = if ($null -ne $question.min) { [double]$question.min } else { 0 }; Emit $minimum 'safe-required-numeric-default' }
if ($type -match 'boolean|yes.no|radio') { Emit 'No' 'safe-required-capability-default' }
Emit 'Not applicable' 'safe-required-text-default'
