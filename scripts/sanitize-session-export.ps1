[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InputPath,
    [Parameter(Mandatory=$true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$inputResolved = (Resolve-Path -LiteralPath $InputPath).Path
$outputFull = [IO.Path]::GetFullPath($OutputPath)
if ($inputResolved -eq $outputFull) { throw 'OutputPath must differ from InputPath; raw exports are never overwritten.' }

function Redact-String([string]$Value) {
    if ($null -eq $Value) { return $null }
    $redacted = $Value
    $redacted = $redacted -replace '(?i)\bBearer\s+[A-Za-z0-9._~+\-/]+=*', 'Bearer [REDACTED]'
    $redacted = $redacted -replace '(?i)([?&](?:token|code|key|signature|sig|auth|session|ticket)=)[^&#\s]+', '$1[REDACTED]'
    $redacted = $redacted -replace '(?i)\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b', '[REDACTED_EMAIL]'
    $redacted = $redacted -replace '(?<![A-Za-z0-9])\+?\d[\d\s().\-]{7,}\d(?![A-Za-z0-9])', '[REDACTED_PHONE]'
    return $redacted
}

function Redact-Value($Value, [string]$PropertyName = '') {
    if ($null -eq $Value) { return $null }
    if ($PropertyName -match '(?i)^(authorization|cookie|set-cookie|password|secret|api[_-]?key|access[_-]?token|refresh[_-]?token|id[_-]?token)$') { return '[REDACTED]' }
    if ($Value -is [string]) { return Redact-String $Value }
    if ($Value -is [Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $Value.Keys) { $copy[[string]$key] = Redact-Value $Value[$key] ([string]$key) }
        return $copy
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { Redact-Value $_ })
    }
    if ($Value -is [psobject] -and $Value.PSObject.Properties.Count -gt 0) {
        $copy = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) { $copy[$property.Name] = Redact-Value $property.Value $property.Name }
        return $copy
    }
    return $Value
}

$parsed = Get-Content -LiteralPath $inputResolved -Raw | ConvertFrom-Json -Depth 100
$sanitized = Redact-Value $parsed
$parent = Split-Path -Parent $outputFull
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$temp = "$outputFull.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
try {
    $sanitized | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $temp -Encoding UTF8
    [IO.File]::Move($temp, $outputFull, $true)
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}
[ordered]@{ status='sanitized'; input=$inputResolved; output=$outputFull } | ConvertTo-Json -Compress
