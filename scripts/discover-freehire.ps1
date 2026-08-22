[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Workspace,
    [int]$TargetNew = 8,
    [string]$BaseUrl = '',
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml')
)

$ErrorActionPreference = 'Stop'
if(-not $BaseUrl){
    $profileText=Get-Content -LiteralPath $ProfilePath -Raw
    if($profileText -match '(?m)^\s*base_url:\s*["'']?([^\r\n"'']+)'){$BaseUrl=$Matches[1].Trim()}else{$BaseUrl='https://freehire.me/api/v1'}
}
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
if (-not (Test-Path -LiteralPath (Join-Path $Workspace '.job-apply-autopilot'))) { throw "No job-apply-autopilot runtime in $Workspace" }

function Pick($Object,[string[]]$Names,$Default='') {
    foreach($name in $Names) {
        if ($Object -and $Object.PSObject.Properties.Name -contains $name -and $null -ne $Object.$name -and [string]$Object.$name) { return $Object.$name }
    }
    return $Default
}
function Slug([string]$Value) {
    $valueSlug = ($Value.ToLowerInvariant() -replace '[^a-z0-9]+','-').Trim('-')
    if ($valueSlug.Length -gt 90) { $valueSlug=$valueSlug.Substring(0,90).Trim('-') }
    return $valueSlug
}
function Write-AtomicJson([string]$Path,$Value) {
    $temp="$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try { $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $temp -Encoding UTF8; [IO.File]::Move($temp,$Path,$true) }
    finally { if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue} }
}
function Get-CopyUrl($Copy) {
    return [string](Pick $Copy @('apply_url','application_url','job_url','url'))
}
function Test-AggregatorUrl([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    try { $hostName = ([Uri]$Url).Host.ToLowerInvariant() -replace '^www\.','' } catch { return $false }
    return $hostName -match '(^|\.)(whatjobs\.com|jobleads\.[a-z.]+|jooble\.[a-z.]+|adzuna\.[a-z.]+|talent\.com|bebee\.[a-z.]+|jobrapido\.com|freehire\.me)$'
}
function Get-RouteRank([string]$Url) {
    if ([string]::IsNullOrWhiteSpace($Url)) { return 100 }
    try { $hostName = ([Uri]$Url).Host.ToLowerInvariant() -replace '^www\.','' } catch { return 90 }
    if ($hostName -match '(^|\.)(greenhouse\.io|lever\.co|ashbyhq\.com|workable\.com|smartrecruiters\.com|myworkdayjobs\.com|bamboohr\.com|recruitee\.com)$') { return 0 }
    if (Test-AggregatorUrl $Url) { return 80 }
    if ($hostName -match '(^|\.)linkedin\.com$') { return 70 }
    return 10
}
function Invoke-FreeHireGet([string]$Path,[hashtable]$Query=@{}) {
    $pairs=@()
    foreach($key in $Query.Keys){$pairs += "$([Uri]::EscapeDataString($key))=$([Uri]::EscapeDataString([string]$Query[$key]))"}
    $uri="$BaseUrl/$Path"
    if($pairs.Count){$uri += "?$(($pairs -join '&'))"}
    return Invoke-RestMethod -Method Get -Uri $uri -Headers @{Accept='application/json'}
}

$categories = @('software_engineering','backend','fullstack','devops','sre','ai_engineering','solutions_engineering')
$categoryFilter = $categories -join ','
$seniorityFilter = 'middle,senior,lead,staff,principal'
$lanes = @(
    [ordered]@{ name='freehire-pakistan'; geography=@{ countries='PK' } },
    [ordered]@{ name='freehire-global-remote'; geography=@{ regions='global'; work_mode='remote' } },
    [ordered]@{ name='freehire-visa-sponsorship'; geography=@{ visa_sponsorship='true' } }
)

$candidatePool = [Collections.Generic.List[object]]::new()
$seenSlugs = @{}
$apiWarnings = [Collections.Generic.List[object]]::new()
$laneStats = [Collections.Generic.List[object]]::new()
foreach($lane in $lanes) {
    $query = @{
        limit=100
        category=$categoryFilter
        seniority=$seniorityFilter
        reality='fresh'
        posted_within_days=7
        company_type_exclude='agency,outsource,outstaff'
        role_type_exclude='people_manager'
        description_format='markdown'
        sort='posted_at'
        order='desc'
    }
    foreach($key in $lane.geography.Keys){$query[$key]=$lane.geography[$key]}
    Write-Progress -Activity 'FreeHire discovery' -Status "Fetching $($lane.name)"
    try { $response=Invoke-FreeHireGet 'agent/jobs/search' $query } catch { $apiWarnings.Add([ordered]@{lane=$lane.name;error=$_.Exception.Message}); continue }
    $items = if($response.data){@($response.data)}elseif($response.jobs){@($response.jobs)}else{@()}
    $ignored = if($response.meta -and $response.meta.ignored_params){@($response.meta.ignored_params)}else{@()}
    if($ignored.Count){$apiWarnings.Add([ordered]@{lane=$lane.name;ignored_params=$ignored})}
    $laneStats.Add([ordered]@{lane=$lane.name;returned=$items.Count;total=if($response.meta){$response.meta.total}else{$items.Count};ignored_params=$ignored})
    foreach($item in $items){
        $publicSlug=[string](Pick $item @('public_slug','slug','id'))
        if(-not $publicSlug -or $seenSlugs.ContainsKey($publicSlug)){continue}
        $seenSlugs[$publicSlug]=$true
        $item | Add-Member -NotePropertyName '_discovery_lane' -NotePropertyValue $lane.name -Force
        $candidatePool.Add($item)
    }
}

# Semantic neighbors are a cheap fallback when strict fresh lanes are sparse.
if($candidatePool.Count -lt [Math]::Max($TargetNew * 2,16)) {
    foreach($seed in @($candidatePool | Select-Object -First 5)) {
        $seedSlug=[string](Pick $seed @('public_slug','slug'))
        if(-not $seedSlug){continue}
        try { $similar=Invoke-FreeHireGet "jobs/$([Uri]::EscapeDataString($seedSlug))/similar" @{limit=10} } catch { continue }
        foreach($item in @($similar.data)){
            $publicSlug=[string](Pick $item @('public_slug','slug','id'))
            if(-not $publicSlug -or $seenSlugs.ContainsKey($publicSlug)){continue}
            $seenSlugs[$publicSlug]=$true
            $item | Add-Member -NotePropertyName '_discovery_lane' -NotePropertyValue 'freehire-similar' -Force
            $candidatePool.Add($item)
        }
    }
}

$created=0; $existing=0; $examined=0; $rejected=0; $duplicates=0; $routePending=0
foreach($item in $candidatePool) {
    if($created -ge $TargetNew){break}
    $examined++
    $publicSlug=[string](Pick $item @('public_slug','slug','id'))
    $company=[string](Pick $item @('company_name','company','employer_name') 'Unknown employer')
    if($item.company -and -not ($item.company -is [string])){$company=[string](Pick $item.company @('name','company_name') $company)}
    $title=[string](Pick $item @('title','job_title','position') 'Software Engineer')
    $jobUrl=[string](Pick $item @('apply_url','url','job_url','application_url'))
    $location=[string](Pick $item @('location','location_name','country'))
    if($item.location -and -not ($item.location -is [string])){$parts=@((Pick $item.location @('city')),(Pick $item.location @('country','country_name')))|Where-Object{$_};$location=$parts -join ', '}
    $description=[string](Pick $item @('description','description_text','full_description'))

    # Similar results may omit a full description; hydrate only those candidates.
    if(-not $description -or $description.Length -lt 80){
        try { $detail=Invoke-FreeHireGet "jobs/$([Uri]::EscapeDataString($publicSlug))"; if($detail.data){$item=$detail.data;$description=[string](Pick $item @('description','description_text','full_description'));$jobUrl=[string](Pick $item @('apply_url','url','job_url','application_url') $jobUrl)} } catch {}
    }

    $copies=@()
    if(-not $jobUrl -or $jobUrl -match '(?i)linkedin\.com' -or (Test-AggregatorUrl $jobUrl)){
        try {
            $copyResponse=Invoke-FreeHireGet "jobs/$([Uri]::EscapeDataString($publicSlug))/copies" @{limit=50}
            $copies=@($copyResponse.data)
            $routeCandidates = @(
                if($jobUrl){[pscustomobject]@{url=$jobUrl;location=$location;rank=(Get-RouteRank $jobUrl)}}
                foreach($copy in $copies){$copyUrl=Get-CopyUrl $copy;if($copyUrl){[pscustomobject]@{url=$copyUrl;location=[string]$copy.location;rank=(Get-RouteRank $copyUrl)}}}
            )
            $bestRoute=$routeCandidates | Sort-Object rank | Select-Object -First 1
            if($bestRoute){$jobUrl=[string]$bestRoute.url;if($bestRoute.location){$location=[string]$bestRoute.location}}
        } catch {}
    }

    $lane=[string](Pick $item @('_discovery_lane') 'freehire')
    $metadata=[ordered]@{
        provider='freehire';fetched_at=[DateTimeOffset]::UtcNow.ToString('o');public_slug=$publicSlug
        lane=$lane;reality=$item.reality;apply_url=$jobUrl;description=$description;copies=$copies;raw=$item
    }
    $jobCandidate=[ordered]@{job_id="fh-$(Slug $publicSlug)";company=$company;title=$title;location=$location;job_url=$jobUrl;source='freehire';discovery_lane=$lane;description=$description}
    $quality=(& (Join-Path $PSScriptRoot 'check-job-quality.ps1') -JobJson ($jobCandidate|ConvertTo-Json -Compress -Depth 8) -MetadataJson ($metadata|ConvertTo-Json -Compress -Depth 30) | Select-Object -Last 1)|ConvertFrom-Json
    if(-not [bool]$quality.allowed){
        $rejected++
        & (Join-Path $PSScriptRoot 'log-decision.ps1') -JobId $jobCandidate.job_id -Status 'skipped-job-quality' -ReasonCode ([string]$quality.reason_code) -Company $company -Title $title -Location $location -JobUrl $jobUrl -Source 'freehire' -Notes ([string]$quality.evidence) -Workspace $Workspace | Out-Null
        continue
    }
    $creationRaw=& (Join-Path $PSScriptRoot 'new-workitem.ps1') -JobId $jobCandidate.job_id -Company $company -Title $title -JobUrl $jobUrl -Location $location -Source 'freehire' -DiscoveryLane $lane -SearchQuery 'fresh engineering composite lane' -Workspace $Workspace -Structured
    $creation=([string]($creationRaw|Select-Object -Last 1))|ConvertFrom-Json
    if([string]$creation.status -eq 'existing'){$existing++;continue}
    if([string]$creation.status -eq 'duplicate'){$duplicates++;continue}
    if([string]$creation.status -eq 'rejected'){$rejected++;continue}
    if([string]$creation.status -ne 'created' -or [string]::IsNullOrWhiteSpace([string]$creation.path){$apiWarnings.Add([ordered]@{lane=$lane;error="unexpected-new-workitem-status:$($creation.status)"});continue}
    $workItem=[string]$creation.path
    $metadata.quality=$quality
    Write-AtomicJson (Join-Path $workItem 'source-metadata.json') $metadata
    "# $title`n`nEmployer: $company`nLocation: $location`nSource: FreeHire ($publicSlug)`nApply URL: $jobUrl`n`n$description`n" | Set-Content -LiteralPath (Join-Path $workItem 'source.md') -Encoding UTF8
    if($jobUrl -and $jobUrl -notmatch '(?i)linkedin\.com' -and -not (Test-AggregatorUrl $jobUrl)){
        & (Join-Path $PSScriptRoot 'set-application-route.ps1') -WorkItemDir $workItem -Route 'external' -Target $jobUrl -Evidence 'FreeHire direct job/copy apply URL' | Out-Null
    } elseif($jobUrl -and (Test-AggregatorUrl $jobUrl)) {
        & (Join-Path $PSScriptRoot 'set-application-route.ps1') -WorkItemDir $workItem -Route 'unresolved' -Target $jobUrl -Evidence 'Aggregator-only route requires direct employer or ATS resolution before application' | Out-Null
        $routePending++
    }
    try {
        $formResponse=Invoke-FreeHireGet "jobs/$([Uri]::EscapeDataString($publicSlug))/apply-form"
        $form=if($formResponse.data){$formResponse.data}else{$formResponse}
        $plan=[ordered]@{provider=[string]$form.provider;basics=@($form.basics);questions=@($form.questions);fetched_at=[DateTimeOffset]::UtcNow.ToString('o')}
        Write-AtomicJson (Join-Path $workItem 'application-answer-plan.json') $plan
    } catch {}
    $created++
    Write-Output "DISCOVERED:$($jobCandidate.job_id):${company}:$title"
}

Write-Progress -Activity 'FreeHire discovery' -Completed
[ordered]@{
    status='complete';source='freehire';created=$created;target=$TargetNew;examined=$examined
    candidates=$candidatePool.Count;quality_rejected=$rejected;duplicates=$duplicates;existing=$existing;route_pending=$routePending
    lanes=$laneStats;api_warnings=$apiWarnings
} | ConvertTo-Json -Compress -Depth 12
