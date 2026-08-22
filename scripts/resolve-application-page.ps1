[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][string]$QuestionsJson,
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml')
)

$ErrorActionPreference = 'Stop'
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path

$resolveScript = Join-Path $PSScriptRoot 'resolve-application-answer.ps1'
$raw = & $resolveScript -WorkItemDir $WorkItemDir -QuestionsJson $QuestionsJson -ProfilePath $ProfilePath | Select-Object -Last 1
$raw | Write-Output