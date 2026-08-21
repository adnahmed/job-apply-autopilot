[CmdletBinding()]
param(
    [string]$Workspace = (Get-Location).Path,
    [string]$Model = '',
    [string]$Agent = 'build',
    [int]$SliceMinutes = 30,
    [int]$BrowserBackoffSeconds = 60,
    [int]$SessionBackoffSeconds = 10,
    [int]$MaxSessions = 0,
    [int]$MaxBrowserWaitCycles = 0,
    [bool]$KeepAwake = $true,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = (Get-Location).Path }
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$runtimeRoot = Join-Path $Workspace '.job-apply-autopilot'
if (-not (Test-Path -LiteralPath $runtimeRoot)) { throw "No job-apply-autopilot runtime at $runtimeRoot" }

$command = Get-Command opencode -ErrorAction Stop
$commandRoot = Split-Path -Parent $command.Source
$opencodeExe = Join-Path $commandRoot 'node_modules\opencode-ai\bin\opencode.exe'
if (-not (Test-Path -LiteralPath $opencodeExe)) {
    if ($command.Source -like '*.exe') { $opencodeExe = $command.Source }
    else { throw "Could not resolve opencode.exe from $($command.Source)" }
}

$healthScript = Join-Path $PSScriptRoot 'test-browseros-health.ps1'
$supervisorRoot = Join-Path $runtimeRoot 'supervisor'
$logsRoot = Join-Path $supervisorRoot 'logs'
$statePath = Join-Path $supervisorRoot 'state.json'
$stopPath = Join-Path $supervisorRoot 'stop.requested'
$lockPath = Join-Path $supervisorRoot 'supervisor.lock'
New-Item -ItemType Directory -Force -Path $logsRoot | Out-Null

function Write-State([System.Collections.IDictionary]$State) {
    $State.updated_at = [DateTimeOffset]::UtcNow.ToString('o')
    $temp = "$statePath.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $temp -Encoding UTF8
        [IO.File]::Move($temp, $statePath, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Wait-WithStop([int]$Seconds) {
    for ($i = 0; $i -lt $Seconds; $i++) {
        if (Test-Path -LiteralPath $stopPath) { return $false }
        Start-Sleep -Seconds 1
    }
    return $true
}

$validation = [ordered]@{
    valid = $true
    workspace = $Workspace
    runtime = $runtimeRoot
    opencode = $opencodeExe
    health_script = $healthScript
    slice_minutes = $SliceMinutes
}
if ($ValidateOnly) {
    $validation | ConvertTo-Json -Depth 4
    exit 0
}

if (Test-Path -LiteralPath $stopPath) { Remove-Item -LiteralPath $stopPath -Force }
$lock = $null
$executionStateSet = $false
try {
    try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { throw "An autopilot supervisor is already running for $Workspace" }
    $lock.SetLength(0)
    $writer = [IO.StreamWriter]::new($lock, [Text.UTF8Encoding]::new($false), 1024, $true)
    $writer.Write("$PID`n$([DateTimeOffset]::UtcNow.ToString('o'))")
    $writer.Flush()

    if ($KeepAwake -and $IsWindows) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AutopilotPower {
  [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);
}
'@
        [void][AutopilotPower]::SetThreadExecutionState([Convert]::ToUInt32('80000001', 16))
        $executionStateSet = $true
    }

    $session = 0
    $browserWaitCycles = 0
    while ($MaxSessions -le 0 -or $session -lt $MaxSessions) {
        if (Test-Path -LiteralPath $stopPath) { break }

        $healthText = try { & $healthScript 2>$null | Select-Object -Last 1 } catch { $null }
        $health = try { $healthText | ConvertFrom-Json } catch { $null }
        if ($null -eq $health -or -not $health.healthy) {
            $browserWaitCycles++
            Write-State ([ordered]@{
                status = 'waiting-browseros'
                pid = $PID
                session = $session
                reason = if ($health) { [string]$health.reason } else { 'health-check-failed' }
                instruction = 'Start BrowserOS neo and leave its Cockpit/browser running; the supervisor will resume automatically.'
            })
            if ($MaxBrowserWaitCycles -gt 0 -and $browserWaitCycles -ge $MaxBrowserWaitCycles) { break }
            if (-not (Wait-WithStop $BrowserBackoffSeconds)) { break }
            continue
        }
        $browserWaitCycles = 0

        $session++
        $stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssZ')
        $stdoutPath = Join-Path $logsRoot ("slice-{0:D4}-$stamp.jsonl" -f $session)
        $stderrPath = Join-Path $logsRoot ("slice-{0:D4}-$stamp.stderr.log" -f $session)
        $prompt = @"
Use job-apply-autopilot. Continue applying to jobs.

This is autonomous supervisor slice $session. Act immediately from session-state.ps1. Optimize for NET-NEW unique company/title submissions, not raw ledger rows. Do not re-apply to a repost or regional duplicate. Process source_pending before assessment. Use at most five task-owned BrowserOS tabs and close disposable tabs before returning, except unresolved CAPTCHA tabs: preserve them, trigger the installed solver once when an ordinary challenge control is available, and wait up to 120 seconds as documented in references/captcha-recovery.md. If BrowserOS becomes unavailable, persist local state and end this slice; do not call it a campaign/runtime completion because the supervisor will retry after BrowserOS health returns. End the slice after three net-new submissions or when no useful action can proceed right now. Never ask routine questions; do not manually solve challenge puzzles, synthesize tokens, or bypass MFA/security controls.
Direct email applications go to job-autopilot-email-apply. Every external side effect uses application-send-guard.ps1; an ambiguous prior attempt must be verified before any retry. Record domain security signals only through domain-circuit-breaker.ps1. Never call work paused/completed while session-state reports actionable work; switch to another route or discovery. Returning ends only this bounded slice, not the persistent supervisor.
"@

        $arguments = [Collections.Generic.List[string]]::new()
        foreach ($value in @('run','--auto','--agent',$Agent,'--format','json','--title',"Job autopilot slice $session",'--dir',$Workspace)) { $arguments.Add($value) }
        if ($Model) { $arguments.Add('--model'); $arguments.Add($Model) }
        $arguments.Add($prompt)

        $process = $null
        $stopRequested = $false
        try {
            Write-State ([ordered]@{
                status = 'running-slice'
                pid = $PID
                session = $session
                started_at = [DateTimeOffset]::UtcNow.ToString('o')
                stdout = $stdoutPath
                stderr = $stderrPath
            })

            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $opencodeExe
            $startInfo.WorkingDirectory = $Workspace
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            foreach ($argument in $arguments) { [void]$startInfo.ArgumentList.Add($argument) }
            $process = [Diagnostics.Process]::new()
            $process.StartInfo = $startInfo
            if (-not $process.Start()) { throw 'Failed to start OpenCode.' }
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $deadline = [DateTimeOffset]::UtcNow.AddMinutes([math]::Max(5, $SliceMinutes))
            $timedOut = $false
            while (-not $process.HasExited) {
                if (Test-Path -LiteralPath $stopPath) { $stopRequested = $true; break }
                if ([DateTimeOffset]::UtcNow -ge $deadline) { $timedOut = $true; break }
                Start-Sleep -Seconds 2
                $process.Refresh()
            }
            if (($timedOut -or $stopRequested) -and -not $process.HasExited) {
                Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                $process.WaitForExit(5000) | Out-Null
            }
            $stdoutTask.GetAwaiter().GetResult() | Set-Content -LiteralPath $stdoutPath -Encoding UTF8
            $stderrTask.GetAwaiter().GetResult() | Set-Content -LiteralPath $stderrPath -Encoding UTF8

            Write-State ([ordered]@{
                status = if ($stopRequested) { 'stopping' } elseif ($timedOut) { 'slice-timeout' } else { 'slice-complete' }
                pid = $PID
                session = $session
                child_exit_code = if ($process.HasExited) { $process.ExitCode } else { $null }
                stdout = $stdoutPath
                stderr = $stderrPath
                completed_at = [DateTimeOffset]::UtcNow.ToString('o')
            })
        } catch {
            try {
                if ($null -ne $process -and -not $process.HasExited) {
                    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
                    $process.WaitForExit(5000) | Out-Null
                }
            } catch {}
            $_.Exception.ToString() | Set-Content -LiteralPath $stderrPath -Encoding UTF8
            Write-State ([ordered]@{
                status = 'slice-error-recovering'
                pid = $PID
                session = $session
                error = $_.Exception.Message
                stdout = $stdoutPath
                stderr = $stderrPath
                completed_at = [DateTimeOffset]::UtcNow.ToString('o')
            })
            if (-not (Wait-WithStop $SessionBackoffSeconds)) { break }
            continue
        }
        if ($stopRequested) { break }
        if (-not (Wait-WithStop $SessionBackoffSeconds)) { break }
    }

    Write-State ([ordered]@{ status='stopped'; pid=$PID; sessions=$session; stopped_at=[DateTimeOffset]::UtcNow.ToString('o') })
} finally {
    if ($executionStateSet) { [void][AutopilotPower]::SetThreadExecutionState([Convert]::ToUInt32('80000000', 16)) }
    if ($null -ne $lock) { $lock.Dispose() }
}
