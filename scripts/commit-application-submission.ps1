[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][string]$ReservationId,
    [Parameter(Mandatory=$true)][string]$Proof,
    [string]$ProofKind = ''
)

$ErrorActionPreference = 'Stop'
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
$guardScript = Join-Path $PSScriptRoot 'application-send-guard.ps1'

function Write-Result($Value) {
    Write-Output ($Value | ConvertTo-Json -Depth 8 -Compress)
}

# Attempt 1: MarkSubmitted with the reservation and proof
$attempt1Args = @(
    '-WorkItemDir', $WorkItemDir,
    '-Action', 'MarkSubmitted',
    '-ReservationId', $ReservationId,
    '-Proof', $Proof
)
if ($ProofKind) { $attempt1Args += '-ProofKind', $ProofKind }

try {
    $result1 = & $guardScript @attempt1Args
    $result1Obj = $result1 | ConvertFrom-Json
    if ($result1Obj.status -in @('submitted','already-submitted')) {
        Write-Result ([ordered]@{ status = 'submitted' })
        exit 0
    }
}
catch {
    # Ignore and proceed to recovery
}

# Recovery: Check status
$statusArgs = @('-WorkItemDir', $WorkItemDir, '-Action', 'Status')
try {
    $statusResult = & $guardScript @statusArgs
    $statusObj = $statusResult | ConvertFrom-Json
    if ($statusObj.status -eq 'submitted') {
        Write-Result ([ordered]@{ status = 'submitted' })
        exit 0
    }
}
catch {
    # Ignore and proceed to retry
}

# Retry MarkSubmitted exactly one more time with same reservation and proof
try {
    $resultRetry = & $guardScript @attempt1Args
    $resultRetryObj = $resultRetry | ConvertFrom-Json
    if ($resultRetryObj.status -in @('submitted','already-submitted')) {
        Write-Result ([ordered]@{ status = 'submitted' })
        exit 0
    }
}
catch {
    # Ignore and proceed to final fallback
}

# Final fallback: MarkAmbiguous
$ambiguousArgs = @(
    '-WorkItemDir', $WorkItemDir,
    '-Action', 'MarkAmbiguous',
    '-ReservationId', $ReservationId,
    '-Proof', $Proof
)
if ($ProofKind) { $ambiguousArgs += '-ProofKind', $ProofKind }

try {
    & $guardScript @ambiguousArgs
}
catch {
    # Ignore - we still return verification-required
}

Write-Result ([ordered]@{ status = 'verification-required' })