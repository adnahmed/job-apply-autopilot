[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Acquire','Release','Status','ClearStage')][string]$Action,
    [Parameter(Mandatory=$true)][ValidateSet('WorkItem','Discovery')][string]$Scope,
    [Parameter(Mandatory=$true)][string]$Stage,
    [string]$WorkItemDir = '',
    [string]$Workspace = '',
    [string]$OwnerId = '',
    [ValidateRange(1,1440)][int]$LeaseMinutes = 90
)

$ErrorActionPreference = 'Stop'

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Parse-Utc($Value) {
    try {
        if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
        if ($Value -is [DateTime]) { return ([DateTimeOffset]$Value).ToUniversalTime() }
        return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    } catch { return $null }
}

function Write-JsonAtomic([string]$Path, $Value) {
    $temp = "$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
        [IO.File]::Move($temp, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Emit($Value) {
    $Value | ConvertTo-Json -Depth 8 -Compress | Write-Output
}

if ($Scope -eq 'WorkItem') {
    if ([string]::IsNullOrWhiteSpace($WorkItemDir)) { throw 'WorkItem scope requires -WorkItemDir.' }
    $WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
    if ([string]::IsNullOrWhiteSpace($Workspace)) {
        $cursor = [IO.DirectoryInfo]::new($WorkItemDir)
        $runtimeRoot = $null
        while ($null -ne $cursor) {
            if ($cursor.Name -eq '.job-apply-autopilot') { $runtimeRoot = $cursor.FullName; break }
            $cursor = $cursor.Parent
        }
        if (-not $runtimeRoot) { throw 'Work item is not inside a job-apply-autopilot runtime.' }
        $Workspace = Split-Path -Parent $runtimeRoot
    } else {
        $Workspace = (Resolve-Path -LiteralPath $Workspace).Path
        $runtimeRoot = Join-Path $Workspace '.job-apply-autopilot'
    }
    if (-not (Test-Path -LiteralPath $runtimeRoot)) { throw "No job-apply-autopilot runtime at $runtimeRoot" }
    $runtimePrefix = $runtimeRoot.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) + [IO.Path]::DirectorySeparatorChar
    if (-not $WorkItemDir.StartsWith($runtimePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Work item is outside this campaign runtime.' }
    $claimPath = Join-Path $WorkItemDir 'action-claim.json'
    $lockPath = Join-Path $WorkItemDir '.action-claim.lock'
} else {
    if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = (Get-Location).Path }
    $Workspace = (Resolve-Path -LiteralPath $Workspace).Path
    $runtimeRoot = Join-Path $Workspace '.job-apply-autopilot'
    if (-not (Test-Path -LiteralPath $runtimeRoot)) { throw "No job-apply-autopilot runtime at $runtimeRoot" }
    $claimPath = Join-Path $runtimeRoot 'discovery-action-claim.json'
    $lockPath = Join-Path $runtimeRoot 'discovery-action-claim.lock'
}

$lock = $null
try {
    try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch {
        Emit ([ordered]@{ status='busy'; scope=$Scope; stage=$Stage; acquired=$false })
        exit 0
    }

    $now = [DateTimeOffset]::UtcNow
    $claim = Read-JsonSafe $claimPath
    $expiresAt = if ($claim -and $claim.expires_at) { Parse-Utc $claim.expires_at } else { $null }
    $active = ($claim -and $null -ne $expiresAt -and $expiresAt -gt $now)
    if ($claim -and -not $active) {
        Remove-Item -LiteralPath $claimPath -Force -ErrorAction SilentlyContinue
        $claim = $null
    }

    switch ($Action) {
        'Status' {
            if ($active) {
                Emit ([ordered]@{ status='claimed'; scope=$Scope; stage=[string]$claim.stage; owner_id=[string]$claim.owner_id; acquired_at=$claim.acquired_at; expires_at=$claim.expires_at; acquired=$false })
            } else {
                Emit ([ordered]@{ status='available'; scope=$Scope; stage=$Stage; acquired=$false })
            }
        }
        'Acquire' {
            if ($active) {
                if (-not [string]::IsNullOrWhiteSpace($OwnerId) -and [string]$claim.owner_id -eq $OwnerId -and [string]$claim.stage -eq $Stage) {
                    $claim.expires_at = $now.AddMinutes($LeaseMinutes).ToString('o')
                    $claim.updated_at = $now.ToString('o')
                    Write-JsonAtomic $claimPath $claim
                    Emit ([ordered]@{ status='renewed'; scope=$Scope; stage=$Stage; owner_id=$OwnerId; acquired_at=$claim.acquired_at; expires_at=$claim.expires_at; acquired=$true })
                } else {
                    Emit ([ordered]@{ status='busy'; scope=$Scope; stage=[string]$claim.stage; owner_id=[string]$claim.owner_id; acquired_at=$claim.acquired_at; expires_at=$claim.expires_at; acquired=$false })
                }
                exit 0
            }
            if ([string]::IsNullOrWhiteSpace($OwnerId)) { $OwnerId = [Guid]::NewGuid().ToString('N') }
            $newClaim = [ordered]@{
                version = 1
                scope = $Scope.ToLowerInvariant()
                stage = $Stage
                owner_id = $OwnerId
                work_item = if ($Scope -eq 'WorkItem') { $WorkItemDir } else { $null }
                acquired_at = $now.ToString('o')
                updated_at = $now.ToString('o')
                expires_at = $now.AddMinutes($LeaseMinutes).ToString('o')
            }
            Write-JsonAtomic $claimPath $newClaim
            Emit ([ordered]@{ status='acquired'; scope=$Scope; stage=$Stage; owner_id=$OwnerId; acquired_at=$newClaim.acquired_at; expires_at=$newClaim.expires_at; acquired=$true })
        }
        'Release' {
            if (-not $claim) {
                Emit ([ordered]@{ status='not-claimed'; scope=$Scope; stage=$Stage; released=$false })
            } elseif ([string]::IsNullOrWhiteSpace($OwnerId) -or [string]$claim.owner_id -ne $OwnerId) {
                Emit ([ordered]@{ status='owner-mismatch'; scope=$Scope; stage=[string]$claim.stage; owner_id=[string]$claim.owner_id; released=$false })
            } elseif ([string]$claim.stage -ne $Stage) {
                Emit ([ordered]@{ status='stage-mismatch'; scope=$Scope; stage=[string]$claim.stage; owner_id=[string]$claim.owner_id; released=$false })
            } else {
                Remove-Item -LiteralPath $claimPath -Force
                Emit ([ordered]@{ status='released'; scope=$Scope; stage=$Stage; owner_id=$OwnerId; released=$true })
            }
        }
        'ClearStage' {
            if ($claim -and [string]$claim.stage -eq $Stage) {
                Remove-Item -LiteralPath $claimPath -Force
                Emit ([ordered]@{ status='cleared'; scope=$Scope; stage=$Stage; released=$true })
            } else {
                Emit ([ordered]@{ status='not-matching'; scope=$Scope; stage=$Stage; released=$false })
            }
        }
    }
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
}
