[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
$checks = @(
    @{ Path = 'canonical\ai-applied-canonical.tex'; Hash = '7491bbe9fad5723e5cf5934fe7330147f404b6033cc2fd8a90b12a9ccbf8e5b2' },
    @{ Path = 'canonical\backend-platform-canonical.tex'; Hash = '3f759810b3945a5ad51a143184449fee383cf6c9c95ef0849b1a2514342961e0' }
)
foreach ($c in $checks) {
    $path = Join-Path $skillRoot $c.Path
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing canonical file: $path" }
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    if ($actual -ne $c.Hash) { throw "Canonical file changed: $path`nExpected: $($c.Hash)`nActual:   $actual" }
    Write-Output "OK $($c.Path) $actual"
}
