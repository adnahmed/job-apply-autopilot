[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [string]$Workspace = '',
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml')
)

$ErrorActionPreference='Stop'
$WorkItemDir=(Resolve-Path -LiteralPath $WorkItemDir).Path

function Read-JsonSafe([string]$Path){if(-not(Test-Path -LiteralPath $Path)){return $null};try{return Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}catch{return $null}}
function Write-JsonAtomic([string]$Path,$Value){$temp="$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp";try{$Value|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $temp -Encoding UTF8;[IO.File]::Move($temp,$Path,$true)}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}}}
function Emit($Value){$Value|ConvertTo-Json -Compress -Depth 12|Write-Output}
function Call-FreeHire([string]$Method,[string]$Path,$Body=$null){$callArgs=@{Method=$Method;Path=$Path;Auth='required';CostClass='free';Workspace=$Workspace;ProfilePath=$ProfilePath;CacheHours=0};if($null -ne $Body){$callArgs.BodyJson=$Body|ConvertTo-Json -Compress -Depth 12};return ((& (Join-Path $PSScriptRoot 'freehire-client.ps1') @callArgs|Select-Object -Last 1)|ConvertFrom-Json)}
function Profile-Scalar([string]$Name,$Default=$null){if(-not(Test-Path -LiteralPath $ProfilePath)){return $Default};$text=Get-Content -LiteralPath $ProfilePath -Raw;$pattern='(?m)^\s*'+[regex]::Escape($Name)+':\s*["'']?([^\r\n"'']+)';if($text -match $pattern){return $Matches[1].Trim()};return $Default}

if([string]::IsNullOrWhiteSpace($Workspace)){
    $cursor=[IO.DirectoryInfo]::new($WorkItemDir);$runtimeRoot=$null
    while($null -ne $cursor){if($cursor.Name -eq '.job-apply-autopilot'){$runtimeRoot=$cursor.FullName;break};$cursor=$cursor.Parent}
    if(-not$runtimeRoot){throw 'Work item is not inside a job-apply-autopilot runtime.'};$Workspace=Split-Path -Parent $runtimeRoot
}else{$Workspace=(Resolve-Path -LiteralPath $Workspace).Path}

if([string](Profile-Scalar 'tracking_mode' 'disabled') -ne 'mirror-after-local-reconcile'){Emit([ordered]@{status='disabled'});exit 0}

$result=Read-JsonSafe (Join-Path $WorkItemDir 'application-result.json')
if(-not$result -or (-not[bool]$result.submitted -and [string]$result.status -ne 'submitted')){Emit([ordered]@{status='not-submitted'});exit 0}
$metadata=Read-JsonSafe (Join-Path $WorkItemDir 'source-metadata.json')
$slug=if($metadata -and $metadata.freehire -and $metadata.freehire.public_slug){[string]$metadata.freehire.public_slug}elseif($metadata -and $metadata.public_slug){[string]$metadata.public_slug}else{''}
if(-not$slug){Emit([ordered]@{status='no-freehire-slug'});exit 0}

$sidecarPath=Join-Path $WorkItemDir 'freehire-sync.json';$prior=Read-JsonSafe $sidecarPath
if($prior -and $prior.remote_applied_at){Emit([ordered]@{status='already-synced';public_slug=$slug;remote_applied_at=$prior.remote_applied_at});exit 0}
$submittedAt=try{[DateTimeOffset]::Parse([string]$result.submitted_at).ToUniversalTime()}catch{[DateTimeOffset]::UtcNow}
$apply=Call-FreeHire 'POST' "jobs/$([Uri]::EscapeDataString($slug))/apply" ([ordered]@{applied_on=$submittedAt.ToString('yyyy-MM-dd')})
$track=$null
$stageMap=@{acknowledgement='applied';screening='screening';interview_invitation='interview';assessment='screening';offer='offer';rejection='rejected';info_request='responded';incomplete_application='preparing'}
$desiredStage=if($prior -and $prior.last_mail_signal -and $stageMap.ContainsKey([string]$prior.last_mail_signal)){[string]$stageMap[[string]$prior.last_mail_signal]}else{'applied'}
if([string]$apply.status -eq 'ok'){$track=Call-FreeHire 'PATCH' "jobs/$([Uri]::EscapeDataString($slug))/track" ([ordered]@{stage=$desiredStage;notes="Mirrored after verified local submission; local job_id=$([string]$result.job_id)"})}
$sync=[ordered]@{
    version=1;public_slug=$slug;local_ledger_authoritative=$true;last_sync_at=[DateTimeOffset]::UtcNow.ToString('o')
    remote_apply_status=[string]$apply.status;remote_track_status=if($track){[string]$track.status}else{'not-run'}
    remote_applied_at=if([string]$apply.status -eq 'ok'){[DateTimeOffset]::UtcNow.ToString('o')}else{$null}
    remote_stage=if($track -and [string]$track.status -eq 'ok'){$desiredStage}else{$null}
    last_mail_signal=if($prior){$prior.last_mail_signal}else{$null}
    mail_external_ids=if($prior -and $prior.mail_external_ids){@($prior.mail_external_ids)}else{@()}
    error_code=if([string]$apply.status -ne 'ok'){[string]$apply.error_code}elseif($track -and [string]$track.status -ne 'ok'){[string]$track.error_code}else{$null}
}
Write-JsonAtomic $sidecarPath $sync
Emit([ordered]@{status=if($sync.remote_applied_at){'synced'}else{'deferred'};public_slug=$slug;apply_status=$sync.remote_apply_status;track_status=$sync.remote_track_status;error_code=$sync.error_code})
