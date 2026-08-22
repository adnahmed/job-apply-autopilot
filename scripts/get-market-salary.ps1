[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [string]$Country = '',
    [string]$Category = '',
    [string]$Seniority = '',
    [string]$BaseUrl = '',
    [int]$MinimumSamples = 0,
    [int]$CacheHours = 0,
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml')
)

$ErrorActionPreference = 'Stop'
$profileText = Get-Content -LiteralPath $ProfilePath -Raw
function Read-ProfileScalar([string]$Name,$Default) {
    $pattern = '(?m)^\s*' + [regex]::Escape($Name) + ':\s*["'']?([^\r\n"'']+)'
    if($profileText -match $pattern){return $Matches[1].Trim()}
    return $Default
}
if(-not $BaseUrl){$BaseUrl=[string](Read-ProfileScalar 'base_url' 'https://freehire.me/api/v1')}
if($MinimumSamples -le 0){$MinimumSamples=[int](Read-ProfileScalar 'salary_insights_minimum_samples' 5)}
if($CacheHours -le 0){$CacheHours=[int](Read-ProfileScalar 'salary_insights_cache_hours' 168)}
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
$job = Get-Content -LiteralPath (Join-Path $WorkItemDir 'job.json') -Raw | ConvertFrom-Json
$metadataPath = Join-Path $WorkItemDir 'source-metadata.json'
$metadata = if (Test-Path -LiteralPath $metadataPath) { try { Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json } catch { $null } } else { $null }
$raw = if ($metadata -and $metadata.raw) { $metadata.raw } else { $null }
$enrichment = if ($raw -and $raw.enrichment) { $raw.enrichment } elseif ($job.enrichment) { $job.enrichment } else { $null }

if (-not $Category) { $Category = if ($enrichment -and $enrichment.category) { [string]$enrichment.category } else { 'software_engineering' } }
if (-not $Seniority) { $Seniority = if ($enrichment -and $enrichment.seniority) { [string]$enrichment.seniority } else { 'senior' } }
if (-not $Country) {
    $countries = @()
    if ($raw -and $raw.countries) { $countries = @($raw.countries) }
    elseif ($job.countries) { $countries = @($job.countries) }
    if ($countries.Count -gt 0) { $Country = [string]($countries[0]) }
}
$Country = $Country.Trim().ToUpperInvariant()

function Write-AtomicJson([string]$Path,$Value) {
    $temp = "$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try { $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temp -Encoding UTF8; [IO.File]::Move($temp,$Path,$true) }
    finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } }
}
function Get-Property($Object,[string]$Name,$Default=$null) {
    if ($Object -and $Object.PSObject.Properties.Name -contains $Name -and $null -ne $Object.$Name) { return $Object.$Name }
    return $Default
}
function Emit($Value) { $Value | ConvertTo-Json -Compress -Depth 12; exit 0 }
function Parse-UtcTime($Value) {
    if($Value -is [DateTimeOffset]){return $Value.ToUniversalTime()}
    if($Value -is [DateTime]){return ([DateTimeOffset]$Value).ToUniversalTime()}
    return [DateTimeOffset]::Parse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
}

$postedMin = Get-Property $enrichment 'salary_min'
$postedMax = Get-Property $enrichment 'salary_max'
if ($null -ne $postedMin) {
    $selected = if ($null -ne $postedMax -and [double]$postedMax -ge [double]$postedMin) { [math]::Round([double]$postedMin + 0.25 * ([double]$postedMax - [double]$postedMin),0) } else { [math]::Round([double]$postedMin,0) }
    Emit ([ordered]@{
        status='available'; source='posted-range'; value=$selected
        currency=[string](Get-Property $enrichment 'salary_currency' '')
        period=[string](Get-Property $enrichment 'salary_period' 'year')
        p25=$selected; p50=$null; p75=$null; sample_size=$null
        country=$Country; category=$Category; seniority=$Seniority
    })
}

$cachePath = Join-Path $WorkItemDir 'salary-market.json'
if (Test-Path -LiteralPath $cachePath) {
    try {
        $cached = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
        $fetched = Parse-UtcTime $cached.fetched_at
        $requestMatches = ($cached.request -and [string]$cached.request.country -eq $Country -and [string]$cached.request.category -eq $Category -and [string]$cached.request.seniority -eq $Seniority)
        if ($requestMatches -and $fetched -gt [DateTimeOffset]::UtcNow.AddHours(-$CacheHours) -and $cached.selected) {
            $out = [ordered]@{}; foreach($p in $cached.selected.PSObject.Properties){$out[$p.Name]=$p.Value}; $out['cache']='hit'; Emit $out
        }
    } catch {}
}

$attempts = @()
if ($Country) {
    $attempts += [ordered]@{ country=$Country; category=$Category; seniority=$Seniority; scope='country-category-seniority' }
    $attempts += [ordered]@{ country=$Country; category=$Category; seniority=''; scope='country-category' }
    $attempts += [ordered]@{ country=$Country; category=''; seniority=$Seniority; scope='country-seniority' }
    $attempts += [ordered]@{ country=$Country; category=''; seniority=''; scope='country-market' }
}
$attempts += [ordered]@{ country=''; category=$Category; seniority=$Seniority; scope='global-category-seniority' }
$attempts += [ordered]@{ country=''; category=$Category; seniority=''; scope='global-category' }
$responses = @(); $selected = $null
foreach ($attempt in $attempts) {
    $query = [ordered]@{ limit=20 }
    if ($attempt.category) { $query.category=$attempt.category }
    if ($attempt.seniority) { $query.seniority=$attempt.seniority }
    if ($attempt.country) { $query.country=$attempt.country }
    $pairs = @(); foreach($key in $query.Keys){$pairs += "$([Uri]::EscapeDataString($key))=$([Uri]::EscapeDataString([string]$query[$key]))"}
    $uri = "$BaseUrl/insights/salary?$(($pairs -join '&'))"
    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{Accept='application/json'}
        $bands = if ($response.data) { @($response.data) } else { @() }
        $responses += [ordered]@{ scope=$attempt.scope; uri=$uri; count=$bands.Count }
        $eligible = @($bands | Where-Object { $null -ne $_.p25 -and [int](Get-Property $_ 'sample_size' 0) -ge $MinimumSamples })
        $band = $eligible | Sort-Object @{Expression={ if([string]$_.seniority -eq $Seniority){0}else{1} }}, @{Expression={ -[int](Get-Property $_ 'sample_size' 0) }} | Select-Object -First 1
        if ($band) {
            $selected = [ordered]@{
                status='available'; source='freehire-salary-insights'; scope=$attempt.scope
                value=[math]::Round([double]$band.p25,0); currency=[string]$band.currency
                period=[string](Get-Property $band 'period' 'year')
                p25=[double]$band.p25; p50=Get-Property $band 'p50'; p75=Get-Property $band 'p75'
                sample_size=[int](Get-Property $band 'sample_size' 0)
                country=$attempt.country; category=[string](Get-Property $band 'category' $(if($attempt.category){$attempt.category}else{$Category})); seniority=[string](Get-Property $band 'seniority' $Seniority)
                fetched_at=[DateTimeOffset]::UtcNow.ToString('o'); cache='miss'
            }
            break
        }
    } catch { $responses += [ordered]@{ scope=$attempt.scope; uri=$uri; error=$_.Exception.Message } }
}

if ($selected) {
    Write-AtomicJson $cachePath ([ordered]@{version=1;fetched_at=[DateTimeOffset]::UtcNow.ToString('o');request=[ordered]@{country=$Country;category=$Category;seniority=$Seniority};selected=$selected;attempts=$responses})
    Emit $selected
}
Emit ([ordered]@{status='unavailable';source='freehire-salary-insights';country=$Country;category=$Category;seniority=$Seniority;attempts=$responses})
