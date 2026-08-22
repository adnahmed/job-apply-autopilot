[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][string]$QuestionJson,
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml'),
    [switch]$NoLoopTrack
)

$ErrorActionPreference = 'Stop'
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
$trimmedQuestion = $QuestionJson.TrimStart()
$question = if ($trimmedQuestion.StartsWith('{') -or $trimmedQuestion.StartsWith('[')) {
    $QuestionJson | ConvertFrom-Json
} else {
    Get-Content -LiteralPath (Resolve-Path -LiteralPath $QuestionJson).Path -Raw | ConvertFrom-Json
}
$job = Get-Content -LiteralPath (Join-Path $WorkItemDir 'job.json') -Raw | ConvertFrom-Json
$metadataPath = Join-Path $WorkItemDir 'source-metadata.json'
$metadata = if (Test-Path -LiteralPath $metadataPath) { try { Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json } catch { $null } } else { $null }
$profile = Get-Content -LiteralPath $ProfilePath -Raw
$runtimeRoot = $null
$cursor = [IO.DirectoryInfo]::new($WorkItemDir)
while ($null -ne $cursor) {
    if ($cursor.Name -eq '.job-apply-autopilot') { $runtimeRoot=$cursor.FullName; break }
    $cursor=$cursor.Parent
}
$freehireContext = if ($runtimeRoot -and (Test-Path -LiteralPath (Join-Path $runtimeRoot 'freehire-context.json'))) { try { Get-Content -LiteralPath (Join-Path $runtimeRoot 'freehire-context.json') -Raw | ConvertFrom-Json } catch { $null } } else { $null }

function Scalar([string]$Name, $Default = $null) {
    $pattern = '(?m)^\s*' + [regex]::Escape($Name) + ':\s*["'']?([^\r\n"'']+)'
    if ($profile -match $pattern) { return $Matches[1].Trim() }
    return $Default
}

function Test-LocalJobLocation([string]$Location) {
    $tokensCsv = Scalar 'local_location_tokens_csv' ''
    if ([string]::IsNullOrWhiteSpace($tokensCsv)) { return $false }
    $tokens = $tokensCsv.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($token in $tokens) {
        if ($Location -match [regex]::Escape($token)) {
            return $true
        }
    }
    return $false
}

function FreeHire-Autofill([string]$Name, $Default = $null) {
    if ($freehireContext -and $freehireContext.autofill -and $freehireContext.autofill.PSObject.Properties.Name -contains $Name -and $null -ne $freehireContext.autofill.$Name -and [string]$freehireContext.autofill.$Name) { return $freehireContext.autofill.$Name }
    return $Default
}

function FreeHire-Screening([string]$Name, $Default = $null) {
    if ($freehireContext -and $freehireContext.screening -and $freehireContext.screening.PSObject.Properties.Name -contains $Name -and $null -ne $freehireContext.screening.$Name) { return $freehireContext.screening.$Name }
    return $Default
}

function Candidate-Value([string]$LocalName, [string]$FreeHireName, $Default = $null) {
    $local = Scalar $LocalName
    if ($null -ne $local -and -not [string]::IsNullOrWhiteSpace([string]$local)) { return $local }
    return FreeHire-Autofill $FreeHireName $Default
}

function Candidate-FullName {
    $local = Scalar 'full_name'
    if ($local) { return $local }
    return ("{0} {1}" -f (FreeHire-Autofill 'first_name'), (FreeHire-Autofill 'last_name')).Trim()
}

function To-Bool($Value) {
    if ($Value -is [bool]) { return [bool]$Value }
    return ([string]$Value -match '^(?i:true|1|yes|required)$')
}

function Write-JsonAtomic([string]$Path, $Value, [int]$Depth = 8) {
    $temp = "$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $temp -Encoding UTF8
        [IO.File]::Move($temp, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Finish($Value) {
    $Value | ConvertTo-Json -Compress -Depth 10
    exit 0
}

function Needs-Semantic([string]$Reason = 'no-deterministic-answer', [string]$Category = 'routine') {
    Finish ([ordered]@{
        status = 'needs-semantic-answer'
        value = $null
        source = 'agent-generated-required'
        category = $Category
        reason_code = $Reason
        strategy = 'generate-one-context-aware-answer-and-continue'
        question = $label.Trim()
        options = @($options)
    })
}

function Normalize-Option([string]$Value) {
    return (($Value.ToLowerInvariant() -replace '[^a-z0-9]+',' ').Trim() -replace '\s+',' ')
}

$label = @(
    [string]$question.label,
    [string]$question.question,
    [string]$question.text,
    [string]$question.name,
    [string]$question.placeholder,
    [string]$question.validation_error,
    [string]$question.pattern
) -join ' '
$label = $label -creplace '([a-z0-9])([A-Z])', '$1 $2'
$label = $label -replace '[_-]+', ' '
$type = ([string]$question.type).ToLowerInvariant()
$options = @($question.options | ForEach-Object {
    if ($_ -is [string]) { $_ }
    elseif ($_.label) { [string]$_.label }
    elseif ($_.value) { [string]$_.value }
})
$required = To-Bool $question.required

function Emit-Answer($Value, [string]$Source, [string]$Category = 'routine', $Details = $null) {
    $resolvedValue = $Value
    if ($options.Count -gt 0 -and $type -match 'select|radio|choice|boolean|yes.no') {
        $target = Normalize-Option ([string]$Value)
        $matched = $options | Where-Object { (Normalize-Option ([string]$_)) -eq $target } | Select-Object -First 1
        if (-not $matched) { Needs-Semantic 'deterministic-value-not-present-in-options' $Category }
        $resolvedValue = $matched
    }
    $out = [ordered]@{ status='answered'; value=$resolvedValue; source=$Source; category=$Category }
    if ($Details) { foreach ($property in $Details.GetEnumerator()) { $out[$property.Key] = $property.Value } }
    Finish $out
}

if (-not $NoLoopTrack) {
    $ownerId = 'unclaimed'
    $claimPath = Join-Path $WorkItemDir 'action-claim.json'
    if (Test-Path -LiteralPath $claimPath) {
        try {
            $claim = Get-Content -LiteralPath $claimPath -Raw | ConvertFrom-Json
            if ($claim.owner_id) { $ownerId = [string]$claim.owner_id }
        } catch {}
    }
    $normalizedQuestion = [ordered]@{
        label = Normalize-Option $label
        type = $type
        required = $required
        options = @($options | ForEach-Object { Normalize-Option ([string]$_) })
    } | ConvertTo-Json -Compress -Depth 5
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = [Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes("$ownerId|$normalizedQuestion"))).ToLowerInvariant() }
    finally { $sha.Dispose() }
    $cachePath = Join-Path $WorkItemDir 'answer-resolution-cache.json'
    $lockPath = Join-Path $WorkItemDir '.answer-resolution.lock'
    $lock = $null
    try {
        try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') } catch {}
        if ($null -ne $lock) {
            $entries = @()
            if (Test-Path -LiteralPath $cachePath) {
                try { $entries = @((Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json).entries) } catch { $entries = @() }
            }
            $entry = $entries | Where-Object { [string]$_.key -eq $hash } | Select-Object -First 1
            if ($entry) {
                $entry.count = [int]$entry.count + 1
            } else {
                $entry = [pscustomobject]@{ key=$hash; owner_id=$ownerId; count=1; first_seen=[DateTimeOffset]::UtcNow.ToString('o'); last_seen=$null }
                $entries += $entry
            }
            $entry.last_seen = [DateTimeOffset]::UtcNow.ToString('o')
            Write-JsonAtomic $cachePath ([ordered]@{version=1;entries=$entries}) 6
            if ([int]$entry.count -gt 2) {
                Finish ([ordered]@{
                    status = 'loop-detected'
                    value = $null
                    source = 'answer-resolution-loop-guard'
                    category = 'workflow'
                    reason_code = 'same-question-resolved-more-than-twice'
                    attempts = [int]$entry.count
                })
            }
        }
    } finally {
        if ($null -ne $lock) { $lock.Dispose() }
    }
}

function Convert-SalaryPeriod([double]$Value, [string]$From, [string]$To) {
    $factors = @{ year=1.0; month=12.0; day=260.0; hour=2080.0 }
    $fromKey = if ($factors.ContainsKey($From)) { $From } else { 'year' }
    $toKey = if ($factors.ContainsKey($To)) { $To } else { $fromKey }
    return [math]::Round(($Value * [double]$factors[$fromKey]) / [double]$factors[$toKey], 0)
}

# Canonical identity fields. Missing required values are handed to the applicator for
# one context-aware generated answer; they never terminate or skip the application.
if (($label -match '(?i)\b(full|legal|candidate)\s*name\b' -or $label.Trim() -match '(?i)^name(\s+of\s+(applicant|candidate))?$') -and $label -notmatch '(?i)company|employer') { Emit-Answer (Candidate-FullName) 'candidate-authoritative-local-first' 'identity' }
if ($label -match '(?i)\bfirst\s*name\b') { $localName=[string](Scalar 'full_name'); Emit-Answer ($(if($localName){$localName.Split(' ')[0]}else{FreeHire-Autofill 'first_name'})) 'candidate-authoritative-local-first' 'identity' }
if ($label -match '(?i)\blast\s*name\b|\bsurname\b') { $localName=[string](Scalar 'full_name'); if($localName){$parts=$localName.Split(' ',[StringSplitOptions]::RemoveEmptyEntries);$last=$parts[$parts.Count-1]}else{$last=FreeHire-Autofill 'last_name'}; Emit-Answer $last 'candidate-authoritative-local-first' 'identity' }
if ($label -match '(?i)\be[\s-]?mail\b') { Emit-Answer (Candidate-Value 'email' 'email') 'candidate-authoritative-local-first' 'identity' }
if ($label -match '(?i)linkedin') { Emit-Answer (Candidate-Value 'linkedin' 'linkedin') 'candidate-authoritative-local-first' 'identity' }
if ($label -match '(?i)github') { Emit-Answer (Scalar 'github') 'profile.candidate.github' 'identity' }
if ($label -match '(?i)\b(portfolio|personal\s*website)\b') { Emit-Answer (Candidate-Value 'github' 'portfolio') 'candidate-authoritative-local-first' 'identity' }
if ($label -match '(?i)\b(phone|mobile|telephone|whatsapp|contact\s*number)\b') {
    $phone = Candidate-Value 'phone' 'phone'
    if ($phone) { Emit-Answer $phone 'candidate-authoritative-local-first' 'identity' }
    if ($required) { Needs-Semantic 'required-phone-missing' 'identity' }
    Emit-Answer '' 'optional-blank' 'identity'
}
if ($label -match '(?i)\b(street\s*address|address\s*line|postal\s*code|zip\s*code|passport|national\s*id|date\s*of\s*birth|birth\s*date|citizenship|nationality)\b') {
    if ($required) { Needs-Semantic 'required-identity-fact-missing' 'identity' }
    Emit-Answer '' 'optional-blank' 'identity'
}
if ($label -match '(?i)\bcity\b') { Emit-Answer (Scalar 'city') 'profile.candidate.location.city' 'identity' }
if ($label -match '(?i)\b(current\s*)?location\b') { Emit-Answer "$(Scalar 'city'), $(Scalar 'country')" 'profile.candidate.location' 'identity' }
if ($label -match '(?i)\bcountry\b' -and $label -notmatch '(?i)work|authoriz|eligible|visa|sponsor|citizen|nationality') { Emit-Answer (Scalar 'country') 'profile.candidate.location.country' 'identity' }
if ($label -match '(?i)(require|need).*(visa|immigration).*(sponsor)|sponsorship.*(require|need)') {
    $sponsorship = FreeHire-Screening 'visa_sponsorship_needed'
    if ($null -ne $sponsorship) { Emit-Answer ($(if([bool]$sponsorship){'Yes'}else{'No'})) 'freehire.candidate-screening' 'legal-authorization' }
}
if ($label -match '(?i)(work\s*authoriz|authorized\s*to\s*work|legally\s*(eligible|entitled)|visa\s*(status|sponsor)|require\s*sponsorship|right\s*to\s*work)') {
    $countryCode = if ($question.country_code) { [string]$question.country_code } elseif ([string]$question.country -match '^[A-Za-z]{2}$') { [string]$question.country } else { '' }
    $authorizedCountries = @(FreeHire-Screening 'authorized_countries' @())
    if ($countryCode -and $authorizedCountries.Count -gt 0) { Emit-Answer ($(if($authorizedCountries -contains $countryCode.ToUpperInvariant()){'Yes'}else{'No'})) 'freehire.candidate-screening' 'legal-authorization' }
    if ($required) { Needs-Semantic 'work-authorization-not-verified' 'legal-authorization' }
    Emit-Answer '' 'optional-blank' 'legal-authorization'
}

# Canonical education and employment facts.
if ($label -match '(?i)(?=.*(education|university|degree))(?=.*(start|from))(?=.*month)') { Emit-Answer ([int](Scalar 'start_month' 4)) 'profile.education' 'education-date' }
if ($label -match '(?i)(?=.*(education|university|degree))(?=.*(start|from))(?=.*year)') { Emit-Answer ([int](Scalar 'start_year' 2018)) 'profile.education' 'education-date' }
if ($label -match '(?i)(?=.*(education|university|degree))(?=.*(end|to|graduat))(?=.*month)') { Emit-Answer ([int](Scalar 'end_month' 3)) 'profile.education' 'education-date' }
if ($label -match '(?i)(?=.*(education|university|degree))(?=.*(end|to|graduat))(?=.*year)') { Emit-Answer ([int](Scalar 'end_year' 2023)) 'profile.education' 'education-date' }
if ($label -match '(?i)\b(degree|qualification)\b' -and $label -notmatch '(?i)year|month|date') { Emit-Answer (Scalar 'degree') 'profile.education.degree' 'education' }
if ($label -match '(?i)\b(university|institution|college|school)\b' -and $label -notmatch '(?i)year|month|date') { Emit-Answer (Scalar 'institution') 'profile.education.institution' 'education' }
if ($label -match '(?i)(current|present).*(employer|company)') { Emit-Answer (Scalar 'company') 'profile.current_employment.company' 'employment' }
if ($label -match '(?i)(current|present).*(title|position|role)') { Emit-Answer (Scalar 'title') 'profile.current_employment.title' 'employment' }

if ($label -match '(?i)(current|present).*(salary|compensation|ctc)|salary.*history') {
    # The configured policy intentionally answers mandatory current-compensation
    # fields through the same posted/market/profile calculation as expected pay.
    $label = "expected compensation $label"
}

if ($label -match '(?i)(expected|desired|salary expectation|compensation expectation|pay expectation|rate expectation)') {
    if ($type -match 'text|textarea' -and $label -notmatch '(?i)numeric|number|amount') {
        Emit-Answer (Scalar 'compensation_text' 'Negotiable; open to a market-competitive package.') 'profile.answer_policy' 'expected-compensation'
    }
    $min = if ($null -ne $question.salary_min) { [double]$question.salary_min } elseif ($null -ne $question.min_salary) { [double]$question.min_salary } elseif ($null -ne $job.salary_min) { [double]$job.salary_min } elseif ($metadata -and $metadata.raw -and $null -ne $metadata.raw.salary_min) { [double]$metadata.raw.salary_min } else { $null }
    $max = if ($null -ne $question.salary_max) { [double]$question.salary_max } elseif ($null -ne $question.max_salary) { [double]$question.max_salary } elseif ($null -ne $job.salary_max) { [double]$job.salary_max } elseif ($metadata -and $metadata.raw -and $null -ne $metadata.raw.salary_max) { [double]$metadata.raw.salary_max } else { $null }
    if ($null -ne $min) {
        $value = if ($null -ne $max -and $max -ge $min) { [math]::Round($min + ([double](Scalar 'posted_range_fraction' 0.25) * ($max-$min)),0) } else { [math]::Round($min,0) }
        Emit-Answer $value 'posted-range-lower-quartile' 'expected-compensation' @{currency=[string]$question.currency;period=[string]$question.period}
    }
    $market = (& (Join-Path $PSScriptRoot 'get-market-salary.ps1') -WorkItemDir $WorkItemDir | Select-Object -Last 1) | ConvertFrom-Json
    if ([string]$market.status -eq 'available') {
        $desiredPeriod = if ($label -match '(?i)hour') { 'hour' } elseif ($label -match '(?i)month') { 'month' } elseif ($label -match '(?i)day') { 'day' } elseif ($label -match '(?i)year|annual') { 'year' } else { [string]$market.period }
        if (-not $desiredPeriod) { $desiredPeriod = 'year' }
        Emit-Answer (Convert-SalaryPeriod ([double]$market.value) ([string]$market.period) $desiredPeriod) ([string]$market.source) 'expected-compensation' @{currency=[string]$market.currency;period=$desiredPeriod;sample_size=$market.sample_size;market_scope=$market.scope;country=$market.country;category=$market.category;seniority=$market.seniority}
    }
    $screeningSalary=FreeHire-Screening 'desired_salary_amount'
    if($null -ne $screeningSalary){
        $fromPeriod=[string](FreeHire-Screening 'desired_salary_period' 'year')
        $desiredPeriod=if($label -match '(?i)hour'){'hour'}elseif($label -match '(?i)month'){'month'}elseif($label -match '(?i)day'){'day'}elseif($label -match '(?i)year|annual'){'year'}else{$fromPeriod}
        Emit-Answer (Convert-SalaryPeriod ([double]$screeningSalary) $fromPeriod $desiredPeriod) 'freehire.candidate-screening' 'expected-compensation' @{currency=[string](FreeHire-Screening 'desired_salary_currency');period=$desiredPeriod}
    }
    $location = [string]$job.location
    if ($label -match '(?i)hour') { Emit-Answer ([int](Scalar 'global_remote_hourly_numeric' 30)) 'profile.global-remote-default' 'expected-compensation' }
    if ($label -match '(?i)month') { Emit-Answer ($(if (Test-LocalJobLocation $location) { [int](Scalar 'local_unlabeled_numeric' 350000) } else { [int](Scalar 'global_remote_monthly_numeric' 5000) })) 'profile.local-market-default' 'expected-compensation' }
    if ($label -match '(?i)year|annual') { Emit-Answer ([int](Scalar 'global_remote_yearly_numeric' 60000)) 'profile.global-remote-default' 'expected-compensation' }
    if (Test-LocalJobLocation $location) { Emit-Answer ([int](Scalar 'local_unlabeled_numeric' 350000)) 'profile.local-market-default' 'expected-compensation' }
    Emit-Answer ([int](Scalar 'global_remote_yearly_numeric' 60000)) 'profile.global-remote-default' 'expected-compensation'
}

$decline = $options | Where-Object { $_ -match '(?i)prefer not|decline|not applicable|n/a' } | Select-Object -First 1
if ($label -match '(?i)gender|race|ethnic|veteran|disability|demographic') {
    if ($decline) { Emit-Answer $decline 'profile.optional-demographic-policy' 'optional-demographic' }
    if (-not $required) { Emit-Answer '' 'optional-blank' 'optional-demographic' }
    Needs-Semantic 'required-sensitive-disclosure-without-decline-option' 'sensitive-disclosure'
}
if ($label -match '(?i)(willing|open).*(relocat)|relocat.*(willing|open)') { $relocate=FreeHire-Screening 'willing_to_relocate'; if($null -ne $relocate){Emit-Answer ($(if([bool]$relocate){'Yes'}else{'No'})) 'freehire.candidate-screening' 'availability'} }
if ($label -match '(?i)(18|eighteen).*(older|age)|age.*(18|eighteen)') { $adult=FreeHire-Screening 'age_18_or_older'; if($null -ne $adult){Emit-Answer ($(if([bool]$adult){'Yes'}else{'No'})) 'freehire.candidate-screening' 'identity'} }
if ($label -match '(?i)notice\s*period') { $notice=FreeHire-Screening 'notice_period_days'; Emit-Answer ($(if($null -ne $notice){[int]$notice}else{30})) ($(if($null -ne $notice){'freehire.candidate-screening'}else{'profile.answer_policy'})) 'availability' }
if ($label -match '(?i)start\s*date|available\s*to\s*start') { Emit-Answer '30 days after offer' 'profile.answer_policy' 'availability' }
if (-not $required) { Emit-Answer '' 'optional-blank' }

# Capability, background-check, onsite, and arbitrary required questions need evidence-aware semantics.
# They must never be converted to zero, No, or Not applicable merely because of their field type.
Needs-Semantic 'no-deterministic-answer' 'agent-generated'
