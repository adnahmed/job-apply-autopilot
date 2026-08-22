[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JobJson,
    [string]$MetadataJson = '',
    [string]$SourcePath = '',
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml')
)

$ErrorActionPreference = 'Stop'

function Read-JsonInput([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    if (Test-Path -LiteralPath $Value) { return Get-Content -LiteralPath $Value -Raw | ConvertFrom-Json }
    return $Value | ConvertFrom-Json
}
function Read-YamlList([string[]]$Lines, [string]$Key) {
    $values = @(); $inside = $false; $indent = 0
    foreach ($line in $Lines) {
        if ($line -match "^(\s*)$([regex]::Escape($Key)):\s*$") { $inside = $true; $indent = $Matches[1].Length; continue }
        if ($inside -and $line -match '^(\s*)[A-Za-z0-9_]+:' -and $Matches[1].Length -le $indent) { break }
        if ($inside -and $line -match '^\s*-\s*["'']?(.+?)["'']?\s*$') { $values += $Matches[1] }
    }
    return $values
}
function Normalize([string]$Value) { return (($Value.ToLowerInvariant() -replace '[^a-z0-9]+',' ').Trim() -replace '\s+',' ') }

$job = Read-JsonInput $JobJson
$metadata = Read-JsonInput $MetadataJson
$profileLines = Get-Content -LiteralPath $ProfilePath
$excludedEmployers = @(Read-YamlList $profileLines 'excluded_employers')
$excludedDomains = @(Read-YamlList $profileLines 'excluded_domains')
$company = [string]$job.company
$companyKey = Normalize $company
$url = if ($job.job_url) { [string]$job.job_url } elseif ($metadata -and $metadata.url) { [string]$metadata.url } else { '' }
$domain = ''
try { if ($url) { $domain = ([Uri]$url).Host.ToLowerInvariant() -replace '^www\.','' } } catch {}
$metadataDescription = if ($metadata) { [string]$metadata.description } else { '' }
$sourceDescription = if ($SourcePath -and (Test-Path -LiteralPath $SourcePath)) { Get-Content -LiteralPath $SourcePath -Raw } else { '' }
$description = @([string]$job.description, $metadataDescription, $sourceDescription) -join "`n"

foreach ($name in $excludedEmployers) {
    $key = Normalize $name
    if ($companyKey -eq $key -or $companyKey.StartsWith("$key ")) {
        [ordered]@{ allowed=$false; classification='predatory-or-ghost'; reason_code='excluded-employer'; evidence=$company } | ConvertTo-Json -Compress
        exit 0
    }
}
foreach ($blockedDomain in $excludedDomains) {
    $blocked = $blockedDomain.ToLowerInvariant()
    if ($domain -eq $blocked -or $domain.EndsWith(".$blocked")) {
        [ordered]@{ allowed=$false; classification='predatory-or-ghost'; reason_code='excluded-domain'; evidence=$domain } | ConvertTo-Json -Compress
        exit 0
    }
}

if ($description -match '(?i)our\s+(confidential\s+)?client|undisclosed\s+client|on\s+behalf\s+of\s+our\s+client|hiring\s+for\s+(one\s+of\s+)?(our\s+)?clients?|for\s+an?\s+(unnamed\s+)?client') {
    [ordered]@{ allowed=$false; classification='agency-unknown-client'; reason_code='unnamed-client'; evidence='Description conceals the hiring employer.' } | ConvertTo-Json -Compress
    exit 0
}

# Aggregator feeds occasionally attach one company's header to another employer's
# body. When the advertised company never appears in the body but a different
# organization explicitly says it is hiring/seeking, the identity is not safe.
$identityBody = $description -replace '(?im)^\s*(?:#+.*|Employer:.*|Company:.*|Location:.*|Source:.*|Apply URL:.*)\s*$', ''
$bodyKey = Normalize $identityBody
$companyWords = @($companyKey.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | Where-Object { $_.Length -gt 2 })
$companyMentioned = ($companyWords.Count -gt 0 -and @($companyWords | Where-Object { $bodyKey -match "(^| )$([regex]::Escape($_))( |$)" }).Count -eq $companyWords.Count)
$hiringMatch = [regex]::Match($identityBody, '(?is)([A-Z][A-Za-z0-9&.\-]+(?:\s+[A-Z][A-Za-z0-9&.\-]+){0,4})(?:\s+in\s+[^.,\r\n]{2,50})?\s+(?:is\s+seeking|seeks|is\s+hiring)')
if (-not $companyMentioned -and $hiringMatch.Success) {
    $observedEmployer = $hiringMatch.Groups[1].Value.Trim()
    $observedKey = Normalize $observedEmployer
    if ($observedKey -and $observedKey -ne $companyKey) {
        [ordered]@{ allowed=$false; classification='identity-mismatch'; reason_code='employer-body-mismatch'; evidence="Advertised employer '$company' conflicts with body employer '$observedEmployer'." } | ConvertTo-Json -Compress
        exit 0
    }
}
if ($description -match '(?i)unpaid\s+(trial|assessment|project)|pay\s+(a|the)\s+fee|purchase\s+.*(assessment|training)|mandatory\s+video\s+interview\s+before') {
    [ordered]@{ allowed=$false; classification='predatory-assessment-funnel'; reason_code='predatory-assessment'; evidence='Job requests an exploitative pre-application funnel.' } | ConvertTo-Json -Compress
    exit 0
}

$reality = if ($metadata -and $metadata.reality) { $metadata.reality } elseif ($metadata -and $metadata.raw -and $metadata.raw.reality) { $metadata.raw.reality } else { $null }
$realityClass = if ($reality -and $reality.class) { [string]$reality.class } else { '' }
$fakeFreshness = if ($reality -and $reality.fake_freshness) { [bool]$reality.fake_freshness } else { $false }
$reposts = if ($reality -and $null -ne $reality.repost_count) { [int]$reality.repost_count } else { 0 }
$directDomains = @('greenhouse.io','lever.co','ashbyhq.com','workable.com','smartrecruiters.com','myworkdayjobs.com')
$direct = $false
foreach ($known in $directDomains) { if ($domain -eq $known -or $domain.EndsWith(".$known")) { $direct = $true } }
$realitySignals = @()
if ($realityClass) { $realitySignals += "class=$realityClass" }
if ($reposts -gt 0) { $realitySignals += "repost_count=$reposts" }
if ($reality -and $null -ne $reality.mass_posting_count -and [int]$reality.mass_posting_count -gt 0) { $realitySignals += "mass_posting_count=$([int]$reality.mass_posting_count)" }
if ($fakeFreshness) { $realitySignals += 'fake_freshness=true' }
$riskSignal = ($fakeFreshness -or $realityClass -in @('stale','likely-evergreen') -or $reposts -ge 3)
$classification = if ($riskSignal) { 'reality-signal-present' } elseif ($realityClass) { "reality-$realityClass" } else { 'not-flagged' }
$reasonCode = if ($riskSignal) { 'quality-pass-with-reality-signal' } else { 'quality-pass' }
$evidence = if ($realitySignals.Count -gt 0) { $realitySignals -join '; ' } elseif ($domain) { $domain } else { $company }
[ordered]@{
    allowed = $true
    classification = $classification
    reason_code = $reasonCode
    evidence = $evidence
    reality_signal = $riskSignal
    reality = $reality
    direct_route = $direct
} | ConvertTo-Json -Compress -Depth 8
