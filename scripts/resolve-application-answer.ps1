[CmdletBinding(DefaultParameterSetName='Single')]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true, ParameterSetName='Single')][string]$QuestionJson,
    [Parameter(Mandatory=$true, ParameterSetName='Batch')][string]$QuestionsJson,
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml'),
    [switch]$NoLoopTrack
)

$ErrorActionPreference = 'Stop'
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path

# Load all context ONCE
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

# Load semantic answer bank
$semanticAnswersPath = Join-Path $WorkItemDir 'application-semantic-answers.json'
$semanticBank = @{}
if (Test-Path -LiteralPath $semanticAnswersPath) {
    try {
        $bank = Get-Content -LiteralPath $semanticAnswersPath -Raw | ConvertFrom-Json
        if ($bank -and $bank.answers) {
            foreach ($a in $bank.answers) {
                $semanticBank[$a.key] = $a
            }
        }
    } catch {}
}

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

function Needs-Semantic([string]$Reason = 'no-deterministic-answer', [string]$Category = 'routine', [string]$QuestionLabel = '', [object]$QuestionOptions = @()) {
    Finish ([ordered]@{
        status = 'needs-semantic-answer'
        value = $null
        source = 'agent-generated-required'
        category = $Category
        reason_code = $Reason
        strategy = 'generate-one-context-aware-answer-and-continue'
        question = $QuestionLabel.Trim()
        options = @($QuestionOptions)
    })
}

function Normalize-Option([string]$Value) {
    return (($Value.ToLowerInvariant() -replace '[^a-z0-9]+',' ').Trim() -replace '\s+',' ')
}

function Normalize-Key([string]$Question, [string]$Type, [array]$Options) {
    $base = ($Question -replace '[^a-z0-9]+',' ' -replace '\s+',' ').Trim().ToLowerInvariant()
    $typeNorm = ($Type -replace '[^a-z0-9]+','').ToLowerInvariant()
    $optionsNorm = @($Options | ForEach-Object { ($_ -replace '[^a-z0-9]+','').ToLowerInvariant() } | Sort-Object) -join ','
    return "$base|$typeNorm|$optionsNorm"
}

function Emit-Answer($Value, [string]$Source, [string]$Category = 'routine', $Details = $null, [object]$Options = @(), [string]$Type = '', [string]$Label = '') {
    $resolvedValue = $Value
    if ($Options.Count -gt 0 -and $Type -match 'select|radio|choice|boolean|yes.no') {
        $target = Normalize-Option ([string]$Value)
        $matched = $Options | Where-Object { (Normalize-Option ([string]$_)) -eq $target } | Select-Object -First 1
        if (-not $matched) { Needs-Semantic 'deterministic-value-not-present-in-options' $Category $Label $Options }
        $resolvedValue = $matched
    }
    $out = [ordered]@{ status='answered'; value=$resolvedValue; source=$Source; category=$Category }
    if ($Details) { foreach ($property in $Details.GetEnumerator()) { $out[$property.Key] = $property.Value } }
    Finish $out
}

function Convert-SalaryPeriod([double]$Value, [string]$From, [string]$To) {
    $factors = @{ year=1.0; month=12.0; day=260.0; hour=2080.0 }
    $fromKey = if ($factors.ContainsKey($From)) { $From } else { 'year' }
    $toKey = if ($factors.ContainsKey($To)) { $To } else { $fromKey }
    return [math]::Round(($Value * [double]$factors[$fromKey]) / [double]$factors[$toKey], 0)
}

# Internal function to resolve a single question using pre-loaded context
function Resolve-OneApplicationQuestion($question, $index) {
    $trimmedQuestion = $question | ConvertTo-Json | ConvertFrom-Json  # normalize
    $label = @(
        [string]$trimmedQuestion.label,
        [string]$trimmedQuestion.question,
        [string]$trimmedQuestion.text,
        [string]$trimmedQuestion.name,
        [string]$trimmedQuestion.placeholder,
        [string]$trimmedQuestion.validation_error,
        [string]$trimmedQuestion.pattern
    ) -join ' '
    $label = $label -creplace '([a-z0-9])([A-Z])', '$1 $2'
    $label = $label -replace '[_-]+', ' '
    $type = ([string]$trimmedQuestion.type).ToLowerInvariant()
    $options = @($trimmedQuestion.options | ForEach-Object {
        if ($_ -is [string]) { $_ }
        elseif ($_.label) { [string]$_.label }
        elseif ($_.value) { [string]$_.value }
    })
    $required = To-Bool $trimmedQuestion.required

    # Loop tracking (only in Single mode for now, or could be per-question in batch)
    if (-not $NoLoopTrack -and $PSCmdlet.ParameterSetName -eq 'Single') {
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
                    return [ordered]@{
                        status = 'loop-detected'
                        value = $null
                        source = 'answer-resolution-loop-guard'
                        category = 'workflow'
                        reason_code = 'same-question-resolved-more-than-twice'
                        attempts = [int]$entry.count
                    }
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

    # Canonical identity fields.
    if (($label -match '(?i)\b(full|legal|candidate)\s*name\b' -or $label.Trim() -match '(?i)^name(\s+of\s+(applicant|candidate))?$') -and $label -notmatch '(?i)company|employer') { return [ordered]@{ status='answered'; value=(Candidate-FullName); source='candidate-authoritative-local-first'; category='identity'; index=$index } }
    if ($label -match '(?i)\bfirst\s*name\b') { $localName=[string](Scalar 'full_name'); return [ordered]@{ status='answered'; value=$(if($localName){$localName.Split(' ')[0]}else{FreeHire-Autofill 'first_name'}); source='candidate-authoritative-local-first'; category='identity'; index=$index } }
    if ($label -match '(?i)\blast\s*name\b|\bsurname\b') { $localName=[string](Scalar 'full_name'); if($localName){$parts=$localName.Split(' ',[StringSplitOptions]::RemoveEmptyEntries);$last=$parts[$parts.Count-1]}else{$last=FreeHire-Autofill 'last_name'}; return [ordered]@{ status='answered'; value=$last; source='candidate-authoritative-local-first'; category='identity'; index=$index } }
    if ($label -match '(?i)\be[\s-]?mail\b') { return [ordered]@{ status='answered'; value=(Candidate-Value 'email' 'email'); source='candidate-authoritative-local-first'; category='identity'; index=$index } }
    if ($label -match '(?i)linkedin') { return [ordered]@{ status='answered'; value=(Candidate-Value 'linkedin' 'linkedin'); source='candidate-authoritative-local-first'; category='identity'; index=$index } }
    if ($label -match '(?i)github') { return [ordered]@{ status='answered'; value=(Scalar 'github'); source='profile.candidate.github'; category='identity'; index=$index } }
    if ($label -match '(?i)\b(portfolio|personal\s*website)\b') { return [ordered]@{ status='answered'; value=(Candidate-Value 'github' 'portfolio'); source='candidate-authoritative-local-first'; category='identity'; index=$index } }
    if ($label -match '(?i)\b(phone|mobile|telephone|whatsapp|contact\s*number)\b') {
        $phone = Candidate-Value 'phone' 'phone'
        if ($phone) { return [ordered]@{ status='answered'; value=$phone; source='candidate-authoritative-local-first'; category='identity'; index=$index } }
        if ($required) { return [ordered]@{ status='needs-semantic-answer'; value=$null; source='agent-generated-required'; category='identity'; reason_code='required-phone-missing'; strategy='generate-one-context-aware-answer-and-continue'; question=$label.Trim(); options=@($options); index=$index } }
        return [ordered]@{ status='answered'; value=''; source='optional-blank'; category='identity'; index=$index }
    }
    if ($label -match '(?i)\b(street\s*address|address\s*line|postal\s*code|zip\s*code|passport|national\s*id|date\s*of\s*birth|birth\s*date|citizenship|nationality)\b') {
        if ($required) { return [ordered]@{ status='needs-semantic-answer'; value=$null; source='agent-generated-required'; category='identity'; reason_code='required-identity-fact-missing'; strategy='generate-one-context-aware-answer-and-continue'; question=$label.Trim(); options=@($options); index=$index } }
        return [ordered]@{ status='answered'; value=''; source='optional-blank'; category='identity'; index=$index }
    }
    if ($label -match '(?i)\bcity\b') { return [ordered]@{ status='answered'; value=(Scalar 'city'); source='profile.candidate.location.city'; category='identity'; index=$index } }
    if ($label -match '(?i)\b(current\s*)?location\b') { return [ordered]@{ status='answered'; value="$(Scalar 'city'), $(Scalar 'country')"; source='profile.candidate.location'; category='identity'; index=$index } }
    if ($label -match '(?i)\bcountry\b' -and $label -notmatch '(?i)work|authoriz|eligible|visa|sponsor|citizen|nationality') { return [ordered]@{ status='answered'; value=(Scalar 'country'); source='profile.candidate.location.country'; category='identity'; index=$index } }
    if ($label -match '(?i)(require|need).*(visa|immigration).*(sponsor)|sponsorship.*(require|need)') {
        $sponsorship = FreeHire-Screening 'visa_sponsorship_needed'
        if ($null -ne $sponsorship) { return [ordered]@{ status='answered'; value=$(if([bool]$sponsorship){'Yes'}else{'No'}); source='freehire.candidate-screening'; category='legal-authorization'; index=$index } }
    }
    if ($label -match '(?i)(work\s*authoriz|authorized\s*to\s*work|legally\s*(eligible|entitled)|visa\s*(status|sponsor)|require\s*sponsorship|right\s*to\s*work)') {
        $countryCode = if ($trimmedQuestion.country_code) { [string]$trimmedQuestion.country_code } elseif ([string]$trimmedQuestion.country -match '^[A-Za-z]{2}$') { [string]$trimmedQuestion.country } else { '' }
        $authorizedCountries = @(FreeHire-Screening 'authorized_countries' @())
        if ($countryCode -and $authorizedCountries.Count -gt 0) { return [ordered]@{ status='answered'; value=$(if($authorizedCountries -contains $countryCode.ToUpperInvariant()){'Yes'}else{'No'}); source='freehire.candidate-screening'; category='legal-authorization'; index=$index } }
        if ($required) { return [ordered]@{ status='needs-semantic-answer'; value=$null; source='agent-generated-required'; category='legal-authorization'; reason_code='work-authorization-not-verified'; strategy='generate-one-context-aware-answer-and-continue'; question=$label.Trim(); options=@($options); index=$index } }
        return [ordered]@{ status='answered'; value=''; source='optional-blank'; category='legal-authorization'; index=$index }
    }

    # Canonical education and employment facts.
    if ($label -match '(?i)(?=.*(education|university|degree))(?=.*(start|from))(?=.*month)') { return [ordered]@{ status='answered'; value=([int](Scalar 'start_month' 4)); source='profile.education'; category='education-date'; index=$index } }
    if ($label -match '(?i)(?=.*(education|university|degree))(?=.*(start|from))(?=.*year)') { return [ordered]@{ status='answered'; value=([int](Scalar 'start_year' 2018)); source='profile.education'; category='education-date'; index=$index } }
    if ($label -match '(?i)(?=.*(education|university|degree))(?=.*(end|to|graduat))(?=.*month)') { return [ordered]@{ status='answered'; value=([int](Scalar 'end_month' 3)); source='profile.education'; category='education-date'; index=$index } }
    if ($label -match '(?i)(?=.*(education|university|degree))(?=.*(end|to|graduat))(?=.*year)') { return [ordered]@{ status='answered'; value=([int](Scalar 'end_year' 2023)); source='profile.education'; category='education-date'; index=$index } }
    if ($label -match '(?i)\b(degree|qualification)\b' -and $label -notmatch '(?i)year|month|date') { return [ordered]@{ status='answered'; value=(Scalar 'degree'); source='profile.education.degree'; category='education'; index=$index } }
    if ($label -match '(?i)\b(university|institution|college|school)\b' -and $label -notmatch '(?i)year|month|date') { return [ordered]@{ status='answered'; value=(Scalar 'institution'); source='profile.education.institution'; category='education'; index=$index } }
    if ($label -match '(?i)(current|present).*(employer|company)') { return [ordered]@{ status='answered'; value=(Scalar 'company'); source='profile.current_employment.company'; category='employment'; index=$index } }
    if ($label -match '(?i)(current|present).*(title|position|role)') { return [ordered]@{ status='answered'; value=(Scalar 'title'); source='profile.current_employment.title'; category='employment'; index=$index } }

    if ($label -match '(?i)(current|present).*(salary|compensation|ctc)|salary.*history') {
        $label = "expected compensation $label"
    }

    if ($label -match '(?i)(expected|desired|salary expectation|compensation expectation|pay expectation|rate expectation)') {
        if ($type -match 'text|textarea' -and $label -notmatch '(?i)numeric|number|amount') { return [ordered]@{ status='answered'; value=(Scalar 'compensation_text' 'Negotiable; open to a market-competitive package.'); source='profile.answer_policy'; category='expected-compensation'; index=$index } }
        $min = if ($null -ne $trimmedQuestion.salary_min) { [double]$trimmedQuestion.salary_min } elseif ($null -ne $trimmedQuestion.min_salary) { [double]$trimmedQuestion.min_salary } elseif ($null -ne $job.salary_min) { [double]$job.salary_min } elseif ($metadata -and $metadata.raw -and $null -ne $metadata.raw.salary_min) { [double]$metadata.raw.salary_min } else { $null }
        $max = if ($null -ne $trimmedQuestion.salary_max) { [double]$trimmedQuestion.salary_max } elseif ($null -ne $trimmedQuestion.max_salary) { [double]$trimmedQuestion.max_salary } elseif ($null -ne $job.salary_max) { [double]$job.salary_max } elseif ($metadata -and $metadata.raw -and $null -ne $metadata.raw.salary_max) { [double]$metadata.raw.salary_max } else { $null }
        if ($null -ne $min) {
            $value = if ($null -ne $max -and $max -ge $min) { [math]::Round($min + ([double](Scalar 'posted_range_fraction' 0.25) * ($max-$min)),0) } else { [math]::Round($min,0) }
            return [ordered]@{ status='answered'; value=$value; source='posted-range-lower-quartile'; category='expected-compensation'; details=@{currency=[string]$trimmedQuestion.currency;period=[string]$trimmedQuestion.period}; index=$index }
        }
        $market = (& (Join-Path $PSScriptRoot 'get-market-salary.ps1') -WorkItemDir $WorkItemDir | Select-Object -Last 1) | ConvertFrom-Json
        if ([string]$market.status -eq 'available') {
            $desiredPeriod = if ($label -match '(?i)hour') { 'hour' } elseif ($label -match '(?i)month') { 'month' } elseif ($label -match '(?i)day') { 'day' } elseif ($label -match '(?i)year|annual') { 'year' } else { [string]$market.period }
            if (-not $desiredPeriod) { $desiredPeriod = 'year' }
            return [ordered]@{ status='answered'; value=(Convert-SalaryPeriod ([double]$market.value) ([string]$market.period) $desiredPeriod); source=[string]$market.source; category='expected-compensation'; details=@{currency=[string]$market.currency;period=$desiredPeriod;sample_size=$market.sample_size;market_scope=$market.scope;country=$market.country;category=$market.category;seniority=$market.seniority}; index=$index }
        }
        $screeningSalary=FreeHire-Screening 'desired_salary_amount'
        if($null -ne $screeningSalary){
            $fromPeriod=[string](FreeHire-Screening 'desired_salary_period' 'year')
            $desiredPeriod=if($label -match '(?i)hour'){'hour'}elseif($label -match '(?i)month'){'month'}elseif($label -match '(?i)day'){'day'}elseif($label -match '(?i)year|annual'){'year'}else{$fromPeriod}
            return [ordered]@{ status='answered'; value=(Convert-SalaryPeriod ([double]$screeningSalary) $fromPeriod $desiredPeriod); source='freehire.candidate-screening'; category='expected-compensation'; details=@{currency=[string](FreeHire-Screening 'desired_salary_currency');period=$desiredPeriod}; index=$index }
        }
        $location = [string]$job.location
        if ($label -match '(?i)hour') { return [ordered]@{ status='answered'; value=([int](Scalar 'global_remote_hourly_numeric' 30)); source='profile.global-remote-default'; category='expected-compensation'; index=$index } }
        if ($label -match '(?i)month') { return [ordered]@{ status='answered'; value=$(if (Test-LocalJobLocation $location) { [int](Scalar 'local_unlabeled_numeric' 350000) } else { [int](Scalar 'global_remote_monthly_numeric' 5000) }); source='profile.local-market-default'; category='expected-compensation'; index=$index } }
        if ($label -match '(?i)year|annual') { return [ordered]@{ status='answered'; value=([int](Scalar 'global_remote_yearly_numeric' 60000)); source='profile.global-remote-default'; category='expected-compensation'; index=$index } }
        if (Test-LocalJobLocation $location) { return [ordered]@{ status='answered'; value=([int](Scalar 'local_unlabeled_numeric' 350000)); source='profile.local-market-default'; category='expected-compensation'; index=$index } }
        return [ordered]@{ status='answered'; value=([int](Scalar 'global_remote_yearly_numeric' 60000)); source='profile.global-remote-default'; category='expected-compensation'; index=$index }
    }

    $decline = $options | Where-Object { $_ -match '(?i)prefer not|decline|not applicable|n/a' } | Select-Object -First 1
    if ($label -match '(?i)gender|race|ethnic|veteran|disability|demographic') {
        if ($decline) { return [ordered]@{ status='answered'; value=$decline; source='profile.optional-demographic-policy'; category='optional-demographic'; index=$index } }
        if (-not $required) { return [ordered]@{ status='answered'; value=''; source='optional-blank'; category='optional-demographic'; index=$index } }
        return [ordered]@{ status='needs-semantic-answer'; value=$null; source='agent-generated-required'; category='sensitive-disclosure'; reason_code='required-sensitive-disclosure-without-decline-option'; strategy='generate-one-context-aware-answer-and-continue'; question=$label.Trim(); options=@($options); index=$index }
    }
    if ($label -match '(?i)(willing|open).*(relocat)|relocat.*(willing|open)') { $relocate=FreeHire-Screening 'willing_to_relocate'; if($null -ne $relocate){ return [ordered]@{ status='answered'; value=$(if([bool]$relocate){'Yes'}else{'No'}); source='freehire.candidate-screening'; category='availability'; index=$index } } }
    if ($label -match '(?i)(18|eighteen).*(older|age)|age.*(18|eighteen)') { $adult=FreeHire-Screening 'age_18_or_older'; if($null -ne $adult){ return [ordered]@{ status='answered'; value=$(if([bool]$adult){'Yes'}else{'No'}); source='freehire.candidate-screening'; category='identity'; index=$index } } }
    if ($label -match '(?i)notice\s*period') { $notice=FreeHire-Screening 'notice_period_days'; return [ordered]@{ status='answered'; value=$(if($null -ne $notice){[int]$notice}else{30}); source=$(if($null -ne $notice){'freehire.candidate-screening'}else{'profile.answer_policy'}); category='availability'; index=$index } }
    if ($label -match '(?i)start\s*date|available\s*to\s*start') { return [ordered]@{ status='answered'; value='30 days after offer'; source='profile.answer_policy'; category='availability'; index=$index } }
    if (-not $required) { return [ordered]@{ status='answered'; value=''; source='optional-blank'; index=$index } }

    # Check semantic answer bank for saved answer
    $normKey = Normalize-Key $label $type $options
    if ($semanticBank.ContainsKey($normKey)) {
        $saved = $semanticBank[$normKey]
        $savedValue = [string]$saved.value
        $canReuse = $true
        if ($type -match 'select|radio|choice|boolean|yes.no' -and $options.Count -gt 0) {
            $target = Normalize-Option $savedValue
            $matched = $options | Where-Object { (Normalize-Option ([string]$_)) -eq $target } | Select-Object -First 1
            if (-not $matched) { $canReuse = $false }
        }
        if ($canReuse) {
            return [ordered]@{
                status = 'answered'
                value = $savedValue
                source = 'application-semantic-answer-bank'
                category = [string]$saved.category
                index = $index
            }
        }
    }

    # Capability, background-check, onsite, and arbitrary required questions need evidence-aware semantics.
    return [ordered]@{ status='needs-semantic-answer'; value=$null; source='agent-generated-required'; category='agent-generated'; reason_code='no-deterministic-answer'; strategy='generate-one-context-aware-answer-and-continue'; question=$label.Trim(); options=@($options); index=$index }
}

# Main execution logic
if ($PSCmdlet.ParameterSetName -eq 'Batch') {
    $questions = $QuestionsJson | ConvertFrom-Json
    if (-not $questions -or -not $questions.Count) {
        Write-Output ([ordered]@{ status='resolved-page'; results=@() } | ConvertTo-Json -Compress -Depth 10)
        exit 0
    }
    $results = @()
    for ($i = 0; $i -lt $questions.Count; $i++) {
        try {
            $result = Resolve-OneApplicationQuestion $questions[$i] $i
            $results += $result
        } catch {
            $results += [ordered]@{
                index = $i
                status = 'error'
                value = $null
                source = 'resolver-exception'
                category = 'resolver-error'
                reason_code = $_.Exception.Message
            }
        }
    }
    [ordered]@{ status='resolved-page'; results=$results } | ConvertTo-Json -Compress -Depth 10 | Write-Output
} else {
    # Single mode
    $trimmedQuestion = $QuestionJson.TrimStart()
    $question = if ($trimmedQuestion.StartsWith('{') -or $trimmedQuestion.StartsWith('[')) {
        $QuestionJson | ConvertFrom-Json
    } else {
        Get-Content -LiteralPath (Resolve-Path -LiteralPath $QuestionJson).Path -Raw | ConvertFrom-Json
    }
    $result = Resolve-OneApplicationQuestion $question 0
    $result | ConvertTo-Json -Compress -Depth 10 | Write-Output
}