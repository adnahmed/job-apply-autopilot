[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [string]$Workspace = '',
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Write-JsonAtomic([string]$Path, $Value, [int]$Depth = 50) {
    $temp = "$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $temp -Encoding UTF8
        [IO.File]::Move($temp, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Emit($Value) { $Value | ConvertTo-Json -Depth 30 -Compress | Write-Output }

function Get-Hash([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Profile-Scalar([string]$Name, $Default = $null) {
    if (-not (Test-Path -LiteralPath $ProfilePath)) { return $Default }
    $text = Get-Content -LiteralPath $ProfilePath -Raw
    $pattern = '(?m)^\s*' + [regex]::Escape($Name) + ':\s*["'']?([^\r\n"'']+)'
    if ($text -match $pattern) { return $Matches[1].Trim() }
    return $Default
}

function Call-FreeHire([string]$Method, [string]$Path, $Query = $null, $Body = $null, [string]$Auth = 'optional', [string]$CostClass = 'free', [int]$CacheHours = 24) {
    $arguments = @{
        Method=$Method; Path=$Path; Auth=$Auth; CostClass=$CostClass; Workspace=$Workspace
        ProfilePath=$ProfilePath; CacheHours=$CacheHours
    }
    if ($null -ne $Query) { $arguments.QueryJson = $Query | ConvertTo-Json -Compress -Depth 20 }
    if ($null -ne $Body) { $arguments.BodyJson = $Body | ConvertTo-Json -Compress -Depth 30 }
    $raw = & (Join-Path $PSScriptRoot 'freehire-client.ps1') @arguments | Select-Object -Last 1
    return $raw | ConvertFrom-Json
}

function Test-PublicJobUrl([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    try { $uri = [Uri]$Value } catch { return $false }
    if ($uri.Scheme -notin @('http','https') -or -not [string]::IsNullOrWhiteSpace($uri.UserInfo)) { return $false }
    $hostName = $uri.Host.ToLowerInvariant().TrimEnd('.')
    if ($hostName -in @('localhost','localhost.localdomain') -or $hostName.EndsWith('.local')) { return $false }
    $ip = $null
    if ([Net.IPAddress]::TryParse($hostName, [ref]$ip)) {
        $bytes = $ip.GetAddressBytes()
        if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
            if ($bytes[0] -eq 10 -or $bytes[0] -eq 127 -or ($bytes[0] -eq 169 -and $bytes[1] -eq 254) -or ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31)) { return $false }
        } elseif ($ip.IsIPv6LinkLocal -or $ip.IsIPv6SiteLocal -or $ip.Equals([Net.IPAddress]::IPv6Loopback)) { return $false }
    }
    return $true
}

function Get-CopyUrl($Copy) {
    foreach ($name in @('apply_url','application_url','job_url','url')) {
        if ($Copy -and $Copy.PSObject.Properties.Name -contains $name -and $Copy.$name) { return [string]$Copy.$name }
    }
    return ''
}

function Test-AggregatorUrl([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    try { $hostName = ([Uri]$Url).Host.ToLowerInvariant() -replace '^www\.','' } catch { return $false }
    return $hostName -match '(^|\.)(whatjobs\.com|jobleads\.[a-z.]+|jooble\.[a-z.]+|adzuna\.[a-z.]+|talent\.com|bebee\.[a-z.]+|jobrapido\.com|freehire\.me)$'
}

function Route-Rank([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { return 100 }
    try { $hostName = ([Uri]$Url).Host.ToLowerInvariant() -replace '^www\.','' } catch { return 90 }
    if ($hostName -match '(^|\.)(greenhouse\.io|lever\.co|ashbyhq\.com|workable\.com|smartrecruiters\.com|myworkdayjobs\.com|bamboohr\.com|recruitee\.com)$') { return 0 }
    if (Test-AggregatorUrl $Url) { return 80 }
    if ($hostName -match '(^|\.)linkedin\.com$') { return 70 }
    return 10
}

if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $cursor = [IO.DirectoryInfo]::new($WorkItemDir)
    $runtimeRoot = $null
    while ($null -ne $cursor) {
        if ($cursor.Name -eq '.job-apply-autopilot') { $runtimeRoot=$cursor.FullName; break }
        $cursor=$cursor.Parent
    }
    if (-not $runtimeRoot) { throw 'Work item is not inside a job-apply-autopilot runtime.' }
    $Workspace = Split-Path -Parent $runtimeRoot
} else { $Workspace = (Resolve-Path -LiteralPath $Workspace).Path }

$jobPath = Join-Path $WorkItemDir 'job.json'
$sourcePath = Join-Path $WorkItemDir 'source.md'
$metadataPath = Join-Path $WorkItemDir 'source-metadata.json'
if (-not (Test-Path -LiteralPath $jobPath) -or -not (Test-Path -LiteralPath $sourcePath)) { throw 'FreeHire enrichment requires job.json and source.md.' }
$job = Read-JsonSafe $jobPath
$metadata = Read-JsonSafe $metadataPath
if (-not $metadata) { $metadata = [pscustomobject]@{} }
$source = Get-Content -LiteralPath $sourcePath -Raw
$sourceHash = Get-Hash $source
$existingFreeHire = if ($metadata.PSObject.Properties.Name -contains 'freehire') { $metadata.freehire } else { $null }
if (-not $Force -and $existingFreeHire -and [string]$existingFreeHire.source_hash -eq $sourceHash -and [string]$existingFreeHire.status -eq 'complete') {
    Emit ([ordered]@{status='unchanged';job_id=[string]$job.job_id;public_slug=[string]$existingFreeHire.public_slug;match_percent=$existingFreeHire.match_percent})
    exit 0
}

$lock = $null
try {
    try { $lock = [IO.File]::Open((Join-Path $WorkItemDir '.freehire-enrichment.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { Emit ([ordered]@{status='busy';job_id=[string]$job.job_id}); exit 0 }

    $publicSlug = ''
    foreach ($candidate in @(
        $(if ($existingFreeHire) { $existingFreeHire.public_slug } else { $null }),
        $(if ($metadata.PSObject.Properties.Name -contains 'public_slug') { $metadata.public_slug } else { $null })
    )) { if ($candidate) { $publicSlug=[string]$candidate; break } }

    $resolution = [ordered]@{status=if ($publicSlug){'known'}else{'not-attempted'};source=if ($publicSlug){'source-metadata'}else{$null};public_url=$null;company_slug=$null}
    $jobUrl = [string]$job.job_url
    if (-not $publicSlug -and (Test-PublicJobUrl $jobUrl)) {
        $resolution.public_url = $jobUrl
        $found = Call-FreeHire 'GET' 'jobs/find' ([ordered]@{url=$jobUrl}) $null 'none' 'free' 24
        if ([string]$found.status -eq 'ok' -and $found.data -and $found.data.public_slug) {
            $publicSlug=[string]$found.data.public_slug; $resolution.status='found'; $resolution.source='jobs/find'
        } elseif ([string](Profile-Scalar 'cross_source_resolution' 'lookup-only') -eq 'public-only') {
            $resolved = Call-FreeHire 'POST' 'jobs/resolve' $null ([ordered]@{url=$jobUrl;surface='job-apply-autopilot'}) 'required' 'free' 24
            if ([string]$resolved.status -eq 'ok' -and $resolved.data) {
                $resolution.status=[string]$resolved.data.status; $resolution.source='jobs/resolve'; $resolution.company_slug=[string]$resolved.data.company_slug
                if ($resolved.data.public_slug) { $publicSlug=[string]$resolved.data.public_slug }
            } else { $resolution.status=[string]$resolved.status; $resolution.source='jobs/resolve' }
        } else { $resolution.status='not-found'; $resolution.source='jobs/find' }
    } elseif (-not $publicSlug) { $resolution.status='ineligible-url' }

    $match = $null; $matchStatus='not-attempted'; $analysis=$null; $analysisStatus='not-attempted'; $copies=@(); $form=$null
    if ($publicSlug) {
        $encodedSlug=[Uri]::EscapeDataString($publicSlug)
        $matchResponse=Call-FreeHire 'GET' "jobs/$encodedSlug/match" $null $null 'required' 'free' 24
        $matchStatus=[string]$matchResponse.status; if ($matchStatus -eq 'ok') { $match=$matchResponse.data }
        $analysisResponse=Call-FreeHire 'GET' "jobs/$encodedSlug/match-analysis" $null $null 'required' 'cached-ai' 6
        $analysisStatus=[string]$analysisResponse.status; if ($analysisStatus -eq 'ok') { $analysis=$analysisResponse.data }
        $copyResponse=Call-FreeHire 'GET' "jobs/$encodedSlug/copies" ([ordered]@{limit=50}) $null 'none' 'free' 24
        if ([string]$copyResponse.status -eq 'ok') { $copies=@($copyResponse.data) }
        $formResponse=Call-FreeHire 'GET' "jobs/$encodedSlug/apply-form" $null $null 'none' 'free' 24
        if ([string]$formResponse.status -eq 'ok') { $form=$formResponse.data }
    } else {
        $textResponse=Call-FreeHire 'POST' 'me/match-text' $null ([ordered]@{title=[string]$job.title;text=$source.Substring(0,[Math]::Min($source.Length,50000))}) 'required' 'free' 24
        $matchStatus=[string]$textResponse.status; if ($matchStatus -eq 'ok') { $match=$textResponse.data }
    }

    $matchPercent = $null
    if ($match) {
        if ($null -ne $match.coverage_percent) { $matchPercent=[int]$match.coverage_percent }
        elseif ($null -ne $match.score) { $matchPercent=[int]$match.score }
    }
    $freehire = [ordered]@{
        status='complete';source_hash=$sourceHash;public_slug=if($publicSlug){$publicSlug}else{$null};resolution=$resolution
        deterministic_match=[ordered]@{status=$matchStatus;data=$match};match_percent=$matchPercent
        cached_match_analysis=[ordered]@{status=$analysisStatus;data=$analysis;authoritative=$false;credit_spent=$false}
        copies=$copies;apply_form=$form;enriched_at=[DateTimeOffset]::UtcNow.ToString('o')
    }
    $metadata | Add-Member -NotePropertyName freehire -NotePropertyValue $freehire -Force
    if ($publicSlug) { $metadata | Add-Member -NotePropertyName public_slug -NotePropertyValue $publicSlug -Force }
    Write-JsonAtomic $metadataPath $metadata

    if ($form) {
        $plan=[ordered]@{provider=[string]$form.provider;basics=@($form.basics);questions=@($form.questions);fetched_at=[DateTimeOffset]::UtcNow.ToString('o');source='freehire-api'}
        Write-JsonAtomic (Join-Path $WorkItemDir 'application-answer-plan.json') $plan 30
    }

    $routeCandidates=@()
    if ($jobUrl) { $routeCandidates += [pscustomobject]@{url=$jobUrl;rank=(Route-Rank $jobUrl)} }
    foreach ($copy in $copies) { $copyUrl=Get-CopyUrl $copy; if($copyUrl){$routeCandidates += [pscustomobject]@{url=$copyUrl;rank=(Route-Rank $copyUrl)}} }
    $best=$routeCandidates | Sort-Object rank | Select-Object -First 1
    if ($best -and [int]$best.rank -le 10) {
        & (Join-Path $PSScriptRoot 'set-application-route.ps1') -WorkItemDir $WorkItemDir -Route 'external' -Target ([string]$best.url) -Evidence 'FreeHire zero-credit route/copy resolution' | Out-Null
    }

    Emit ([ordered]@{status='enriched';job_id=[string]$job.job_id;public_slug=if($publicSlug){$publicSlug}else{$null};resolution_status=$resolution.status;match_status=$matchStatus;match_percent=$matchPercent;analysis_status=$analysisStatus;copies=$copies.Count;apply_form=[bool]$form})
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
}
