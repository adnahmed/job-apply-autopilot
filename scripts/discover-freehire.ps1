[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Workspace,
    [int]$TargetNew = 8,
    [string]$BaseUrl = 'https://freehire.me/api/v1'
)
$ErrorActionPreference = 'Stop'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
if (-not (Test-Path -LiteralPath (Join-Path $Workspace '.job-apply-autopilot'))) { throw "No job-apply-autopilot runtime in $Workspace" }
function Pick($Object,[string[]]$Names,$Default='') { foreach($name in $Names) { if ($Object -and $Object.PSObject.Properties.Name -contains $name -and $null -ne $Object.$name -and [string]$Object.$name) { return $Object.$name } }; return $Default }
function Slug([string]$Value) { $v=($Value.ToLowerInvariant() -replace '[^a-z0-9]+','-').Trim('-'); if($v.Length -gt 90){$v=$v.Substring(0,90).Trim('-')}; return $v }
function Write-AtomicJson([string]$Path,$Value) { $temp="$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"; try{$Value|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $temp -Encoding UTF8;[IO.File]::Move($temp,$Path,$true)}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}} }

$categories = @('software_engineering','backend','fullstack','devops','sre','ai_engineering','solutions_engineering')
$seniorities = 'middle,senior,lead,staff,principal'
$lanes = @(
    [ordered]@{ name='freehire-pakistan'; params=@{ countries='PK' } },
    [ordered]@{ name='freehire-global-remote'; params=@{ regions='global'; work_mode='remote' } },
    [ordered]@{ name='freehire-visa-sponsorship'; params=@{ visa_sponsorship='true' } }
)
$seen = @{}; $created = 0; $examined = 0; $rejected = 0; $duplicates = 0
foreach($lane in $lanes) {
    foreach($category in $categories) {
        if($created -ge $TargetNew){break}
        $query = [ordered]@{ limit=100; category=$category; seniorities=$seniorities; reality='fresh'; posted_within_days=7; sort='newest'; exclude='agency,outsource,outstaff,people_manager' }
        foreach($key in $lane.params.Keys){$query[$key]=$lane.params[$key]}
        $pairs=@(); foreach($key in $query.Keys){$pairs += "$([Uri]::EscapeDataString($key))=$([Uri]::EscapeDataString([string]$query[$key]))"}
        $uri="$BaseUrl/agent/jobs/search?$(($pairs -join '&'))"
        Write-Progress -Activity 'FreeHire discovery' -Status "$($lane.name) / $category; created $created of $TargetNew"
        try { $response=Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Accept='application/json' } } catch { Write-Warning "FreeHire lane failed: $($_.Exception.Message)"; continue }
        $items = if($response.jobs){@($response.jobs)}elseif($response.data -and $response.data.jobs){@($response.data.jobs)}elseif($response.data){@($response.data)}else{@($response)}
        foreach($item in $items) {
            if($created -ge $TargetNew){break}
            $examined++
            $publicSlug=[string](Pick $item @('public_slug','slug','id'))
            if(-not $publicSlug){continue}
            if($seen.ContainsKey($publicSlug)){continue}; $seen[$publicSlug]=$true
            $company=[string](Pick $item @('company_name','company','employer_name') 'Unknown employer')
            if($item.company -and -not ($item.company -is [string])){$company=[string](Pick $item.company @('name','company_name') $company)}
            $title=[string](Pick $item @('title','job_title','position') 'Software Engineer')
            $jobUrl=[string](Pick $item @('apply_url','url','job_url','application_url'))
            $location=[string](Pick $item @('location','location_name','country'))
            if($item.location -and -not ($item.location -is [string])){$location=@((Pick $item.location @('city')), (Pick $item.location @('country','country_name'))) | Where-Object {$_}; $location=$location -join ', '}
            $description=[string](Pick $item @('description','description_text','full_description'))
            $metadata=[ordered]@{ provider='freehire'; fetched_at=[DateTimeOffset]::UtcNow.ToString('o'); public_slug=$publicSlug; query=$query; lane=$lane.name; reality=$item.reality; apply_url=$jobUrl; description=$description; raw=$item }
            $jobCandidate=[ordered]@{ job_id="fh-$(Slug $publicSlug)"; company=$company; title=$title; location=$location; job_url=$jobUrl; source='freehire'; discovery_lane=$lane.name; description=$description }
            $quality=(& (Join-Path $PSScriptRoot 'check-job-quality.ps1') -JobJson ($jobCandidate|ConvertTo-Json -Compress -Depth 8) -MetadataJson ($metadata|ConvertTo-Json -Compress -Depth 20) | Select-Object -Last 1)|ConvertFrom-Json
            if(-not [bool]$quality.allowed){
                $rejected++
                & (Join-Path $PSScriptRoot 'log-decision.ps1') -JobId $jobCandidate.job_id -Status 'skipped-job-quality' -ReasonCode ([string]$quality.reason_code) -Company $company -Title $title -Location $location -JobUrl $jobUrl -Source 'freehire' -Notes ([string]$quality.evidence) -Workspace $Workspace | Out-Null
                continue
            }
            $workItem=& (Join-Path $PSScriptRoot 'new-workitem.ps1') -JobId $jobCandidate.job_id -Company $company -Title $title -JobUrl $jobUrl -Location $location -Source 'freehire' -DiscoveryLane $lane.name -SearchQuery "$category newest fresh" -Workspace $Workspace
            $workItem=[string]($workItem|Select-Object -Last 1)
            if($workItem.StartsWith('DUPLICATE:') -or $workItem.StartsWith('REJECTED:')){$duplicates++;continue}
            Write-AtomicJson (Join-Path $workItem 'source-metadata.json') $metadata
            $source="# $title`n`nEmployer: $company`nLocation: $location`nSource: FreeHire ($publicSlug)`nApply URL: $jobUrl`n`n$description`n"
            $source | Set-Content -LiteralPath (Join-Path $workItem 'source.md') -Encoding UTF8
            if($jobUrl -and $jobUrl -notmatch '(?i)linkedin\.com'){
                & (Join-Path $PSScriptRoot 'set-application-route.ps1') -WorkItemDir $workItem -Route 'external' -Target $jobUrl -Evidence 'FreeHire direct apply_url field' | Out-Null
            }
            try {
                $form=Invoke-RestMethod -Method Get -Uri "$BaseUrl/jobs/$([Uri]::EscapeDataString($publicSlug))/apply-form" -Headers @{Accept='application/json'}
                $plan=[ordered]@{ provider=(Pick $form @('provider')); basics=$form.basics; questions=$form.questions; fetched_at=[DateTimeOffset]::UtcNow.ToString('o') }
                Write-AtomicJson (Join-Path $workItem 'application-answer-plan.json') $plan
            } catch {}
            $created++
            Write-Output "DISCOVERED:$($jobCandidate.job_id):${company}:$title"
        }
    }
    if($created -ge $TargetNew){break}
}
Write-Progress -Activity 'FreeHire discovery' -Completed
[ordered]@{status='complete';source='freehire';created=$created;target=$TargetNew;examined=$examined;quality_rejected=$rejected;duplicates=$duplicates} | ConvertTo-Json -Compress
