[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$TexPath,
    [switch]$StrictOnePage
)

$ErrorActionPreference = 'Stop'
$TexPath = (Resolve-Path -LiteralPath $TexPath).Path
$workDir = Split-Path -Parent $TexPath
$texName = Split-Path -Leaf $TexPath
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($texName)
$pdfPath = Join-Path $workDir "$baseName.pdf"
$logPath = Join-Path $workDir "$baseName.log"
$fitMapPath = Join-Path $workDir 'fit-map.json'

$source = Get-Content -LiteralPath $TexPath -Raw
if ($source -notmatch 'Adnan Ahmed Khan') { throw 'Candidate name is missing from resume.tex.' }
if ($source -notmatch 'khanadnanahmed01@gmail\.com') { throw 'Candidate email is missing from resume.tex.' }

if (Test-Path -LiteralPath $fitMapPath) {
    $fit = Get-Content -LiteralPath $fitMapPath -Raw | ConvertFrom-Json
    if ($fit.status -eq 'must-be-filled-before-resume-tailoring' -or $fit.requirements.Count -eq 0) {
        throw 'fit-map.json has not been completed. Build the canonical evidence map before compiling.'
    }
}

Push-Location $workDir
try {
    $latexmk = Get-Command latexmk -ErrorAction SilentlyContinue
    if ($latexmk) {
        & latexmk -pdf -interaction=nonstopmode -halt-on-error -file-line-error $texName
        if ($LASTEXITCODE -ne 0) { throw "latexmk failed with exit code $LASTEXITCODE" }
    } else {
        $pdflatex = Get-Command pdflatex -ErrorAction SilentlyContinue
        if (-not $pdflatex) { throw 'Neither latexmk nor pdflatex was found on PATH.' }
        & pdflatex -interaction=nonstopmode -halt-on-error -file-line-error $texName
        if ($LASTEXITCODE -ne 0) { throw "pdflatex pass 1 failed with exit code $LASTEXITCODE" }
        & pdflatex -interaction=nonstopmode -halt-on-error -file-line-error $texName
        if ($LASTEXITCODE -ne 0) { throw "pdflatex pass 2 failed with exit code $LASTEXITCODE" }
    }

    if (-not (Test-Path -LiteralPath $pdfPath)) { throw "PDF was not produced: $pdfPath" }
    $pdf = Get-Item -LiteralPath $pdfPath
    if ($pdf.Length -lt 5000) { throw "Generated PDF looks too small ($($pdf.Length) bytes)." }

    if (Test-Path -LiteralPath $logPath) {
        $logText = Get-Content -LiteralPath $logPath -Raw
        if ($logText -match '! LaTeX Error:|Fatal error occurred|Emergency stop') {
            throw 'LaTeX log contains a fatal error.'
        }
        if ($logText -match 'Overfull \\hbox') {
            Write-Warning 'LaTeX reported an overfull hbox. Tighten content before upload if visually significant.'
        }
    }

    $pages = $null
    $pdfinfo = Get-Command pdfinfo -ErrorAction SilentlyContinue
    if ($pdfinfo) {
        $info = (& pdfinfo $pdfPath 2>$null) -join "`n"
        if ($info -match 'Pages:\s+(\d+)') { $pages = [int]$Matches[1] }
    }

    if ($StrictOnePage -and $null -ne $pages -and $pages -ne 1) {
        throw "Strict one-page check failed: generated PDF has $pages pages."
    }
    if ($null -ne $pages -and $pages -gt 1) {
        Write-Warning "Resume is $pages pages. Trim low-priority material."
    }

    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue
    if ($pdftotext) {
        $txtPath = Join-Path $workDir "$baseName.txt"
        & pdftotext -layout $pdfPath $txtPath 2>$null
        if (Test-Path -LiteralPath $txtPath) {
            $txt = Get-Content -LiteralPath $txtPath -Raw
            if ($txt -notmatch 'Adnan Ahmed Khan') { throw 'PDF text extraction did not contain candidate name.' }
            if ($txt -notmatch 'khanadnanahmed01@gmail\.com') { throw 'PDF text extraction did not contain candidate email.' }
        }
    }

    Write-Output $pdfPath
}
finally {
    Pop-Location
}
