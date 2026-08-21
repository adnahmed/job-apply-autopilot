[CmdletBinding()]
param(
    [string]$Workspace = (Get-Location).Path,
    [string]$Model = '',
    [string]$Agent = 'build',
    [int]$SliceMinutes = 30
)

$ErrorActionPreference = 'Stop'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$runtimeRoot = Join-Path $Workspace '.job-apply-autopilot'
if (-not (Test-Path -LiteralPath $runtimeRoot)) { throw "No job-apply-autopilot runtime at $runtimeRoot" }
$runner = Join-Path $PSScriptRoot 'run-campaign.ps1'
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source

$arguments = [Collections.Generic.List[string]]::new()
foreach ($value in @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runner,'-Workspace',$Workspace,'-Agent',$Agent,'-SliceMinutes',[string]$SliceMinutes)) { $arguments.Add($value) }
if ($Model) { $arguments.Add('-Model'); $arguments.Add($Model) }

$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $pwsh
$startInfo.WorkingDirectory = $Workspace
$startInfo.UseShellExecute = $true
$startInfo.CreateNoWindow = $true
$startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
foreach ($argument in $arguments) { [void]$startInfo.ArgumentList.Add($argument) }
$process = [Diagnostics.Process]::Start($startInfo)
$statePath = Join-Path $runtimeRoot 'supervisor\state.json'
$deadline = (Get-Date).AddSeconds(6)
do {
    Start-Sleep -Milliseconds 250
    $process.Refresh()
    if ($process.HasExited) { throw "Autopilot supervisor exited immediately with code $($process.ExitCode). Run run-campaign.ps1 in the foreground for diagnostics." }
    $state = try { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { $null }
} while (($null -eq $state -or [int]$state.pid -ne $process.Id) -and (Get-Date) -lt $deadline)
if ($null -eq $state -or [int]$state.pid -ne $process.Id) { throw 'Autopilot supervisor started but did not publish healthy state within six seconds.' }

[ordered]@{
    status = 'started'
    pid = $process.Id
    workspace = $Workspace
    state = $statePath
    stop_command = "pwsh -NoProfile -File `"$(Join-Path $PSScriptRoot 'stop-autopilot.ps1')`" -Workspace `"$Workspace`""
} | ConvertTo-Json -Depth 4
