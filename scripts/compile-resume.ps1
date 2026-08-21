[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$TexPath,
    [switch]$StrictOnePage,
    [switch]$AutoCompact
)

$ErrorActionPreference = 'Stop'
$TexPath = (Resolve-Path -LiteralPath $TexPath).Path
$workDir = Split-Path -Parent $TexPath
$texName = Split-Path -Leaf $TexPath
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($texName)
$pdfPath = Join-Path $workDir "$baseName.pdf"
$logPath = Join-Path $workDir "$baseName.log"
$fitMapPath = Join-Path $workDir 'fit-map.json'
$assessmentPath = Join-Path $workDir 'assessment.json'
$tailoringAuditPath = Join-Path $workDir 'tailoring-audit.json'
$jobMetaPath = Join-Path $workDir 'job.json'
$canonicalAuditPath = Join-Path $workDir 'canonical-source.tex'
$artifactPath = Join-Path $workDir 'resume-artifact.json'
$compileLock = $null
try { $compileLock = [IO.File]::Open((Join-Path $workDir '.work-item.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
catch { throw 'Resume transition is busy; rerun session state.' }

function Clear-ResumeClaim {
    $workspace = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $workDir))
    & (Join-Path $PSScriptRoot 'claim-action.ps1') -Action ClearStage -Scope WorkItem -Stage 'resume_pending' -WorkItemDir $workDir -Workspace $workspace | Out-Null
}

try {
$skillRoot = Split-Path -Parent $PSScriptRoot
$profilePath = Join-Path $skillRoot 'profile.yaml'
if (-not (Test-Path -LiteralPath $profilePath)) { throw "Candidate profile not found: $profilePath" }
$profileText = Get-Content -LiteralPath $profilePath -Raw
if ($profileText -notmatch '(?m)^\s*full_name:\s*["'']?([^"''\r\n]+)') { throw 'candidate.full_name missing from profile.yaml.' }
$candidateName = $Matches[1].Trim()
if ($profileText -notmatch '(?m)^\s*email:\s*["'']?([^"''\r\n]+)') { throw 'candidate.email missing from profile.yaml.' }
$candidateEmail = $Matches[1].Trim()

function Convert-ToFilenamePart([string]$Text, [int]$Max = 60) {
    $part = $Text -replace '[^A-Za-z0-9]+','_'
    $part = $part.Trim('_')
    if ([string]::IsNullOrWhiteSpace($part)) { $part = 'Job' }
    if ($part.Length -gt $Max) { $part = $part.Substring(0,$Max).Trim('_') }
    return $part
}

function Invoke-PdfCompile {
    param([string]$Name)
    $latexmk = Get-Command latexmk -ErrorAction SilentlyContinue
    if ($latexmk) {
        & latexmk -pdf -interaction=nonstopmode -halt-on-error -file-line-error $Name
        if ($LASTEXITCODE -eq 0) { return }
        Write-Warning "latexmk failed with exit code $LASTEXITCODE; falling back to two direct pdflatex passes."
    }

    $pdflatex = Get-Command pdflatex -ErrorAction SilentlyContinue
    if (-not $pdflatex) { throw 'Neither a working latexmk nor pdflatex was found on PATH.' }
    & pdflatex -interaction=nonstopmode -halt-on-error -file-line-error $Name
    if ($LASTEXITCODE -ne 0) { throw "pdflatex pass 1 failed with exit code $LASTEXITCODE" }
    & pdflatex -interaction=nonstopmode -halt-on-error -file-line-error $Name
    if ($LASTEXITCODE -ne 0) { throw "pdflatex pass 2 failed with exit code $LASTEXITCODE" }
}

function Get-PdfPageCount([string]$Path) {
    $pdfinfo = Get-Command pdfinfo -ErrorAction SilentlyContinue
    if ($pdfinfo) {
        $info = (& pdfinfo $Path 2>$null) -join "`n"
        if ($info -match 'Pages:\s+(\d+)') { return [int]$Matches[1] }
    }

    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue
    if ($pdftotext) {
        $probe = Join-Path $workDir '.page-count-probe.txt'
        & pdftotext -layout $Path $probe 2>$null
        if (Test-Path -LiteralPath $probe) {
            $raw = [System.IO.File]::ReadAllText($probe)
            Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
            $ff = ($raw.ToCharArray() | Where-Object { [int]$_ -eq 12 }).Count
            if ($ff -gt 0) { return $ff }
            if ($raw.Length -gt 0) { return 1 }
        }
    }
    return $null
}

function Invoke-ControlledCompaction {
    $backup = Join-Path $workDir 'resume.precompact.tex'
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $TexPath -Destination $backup -Force
    }
    $text = Get-Content -LiteralPath $TexPath -Raw
    # Layout-only fallback learned from a successful one-page production run.
    $text = [regex]::Replace($text, '(?m)^\s*\\vfill\s*\r?\n?', '')
    $text = [regex]::Replace($text, 'topsep\s*=\s*[0-9.]+pt', 'topsep=2pt')
    $text = [regex]::Replace($text, 'itemsep\s*=\s*[0-9.]+pt', 'itemsep=2pt')
    Set-Content -LiteralPath $TexPath -Value $text -Encoding UTF8

    try {
        $audit = Get-Content -LiteralPath $tailoringAuditPath -Raw | ConvertFrom-Json
        $audit | Add-Member -NotePropertyName layout_compaction -NotePropertyValue 'auto-compact: removed vfill; itemize topsep/itemsep <= 2pt; factual content unchanged' -Force
        $audit | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tailoringAuditPath -Encoding UTF8
    } catch { }
}

$source = Get-Content -LiteralPath $TexPath -Raw
if ($source -notmatch [regex]::Escape($candidateName)) { throw 'Candidate name from profile.yaml is missing from resume.tex.' }
if ($source -notmatch [regex]::Escape($candidateEmail)) { throw 'Candidate email from profile.yaml is missing from resume.tex.' }

foreach ($required in @($assessmentPath, $fitMapPath, $tailoringAuditPath, $jobMetaPath, $canonicalAuditPath)) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required audit artifact missing: $required" }
}

$assessment = Get-Content -LiteralPath $assessmentPath -Raw | ConvertFrom-Json
if ($assessment.status -ne 'passed') { throw 'assessment.json has not been marked passed.' }
$gateNames = @('integrity','eligibility','role_family','mandatory_requirements','truth_feasibility')
foreach ($gate in $gateNames) {
    if (-not [bool]$assessment.hard_gates.$gate) { throw "Hard gate not passed: $gate" }
}

$fit = Get-Content -LiteralPath $fitMapPath -Raw | ConvertFrom-Json
if ($fit.status -ne 'complete' -or $fit.requirements.Count -eq 0) { throw 'fit-map.json is incomplete.' }
if ($null -eq $fit.score) { throw 'fit-map.json is missing calibrated score.' }

$tailor = Get-Content -LiteralPath $tailoringAuditPath -Raw | ConvertFrom-Json
if ($tailor.status -ne 'complete') { throw 'tailoring-audit.json is incomplete.' }
if ($tailor.unsupported_terms_added.Count -gt 0) { throw 'tailoring-audit.json reports unsupported terms. Correct the resume before compiling.' }

$jobMeta = Get-Content -LiteralPath $jobMetaPath -Raw | ConvertFrom-Json
$auditHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $canonicalAuditPath).Hash.ToLowerInvariant()
if ($auditHash -ne [string]$jobMeta.canonical_sha256) { throw 'canonical-source.tex does not match the immutable canonical hash recorded at scaffold time.' }

if (Test-Path -LiteralPath $artifactPath) {
    try {
        $existingArtifact = Get-Content -LiteralPath $artifactPath -Raw | ConvertFrom-Json
        $existingPdf = [string]$existingArtifact.path
        $validExisting = (
            [string]$existingArtifact.status -eq 'ready-for-upload' -and
            [string]$existingArtifact.job_id -eq [string]$jobMeta.job_id -and
            -not [string]::IsNullOrWhiteSpace([string]$existingArtifact.filename) -and
            -not [string]::IsNullOrWhiteSpace([string]$existingArtifact.sha256) -and
            -not [string]::IsNullOrWhiteSpace($existingPdf) -and
            (Test-Path -LiteralPath $existingPdf) -and
            (Get-Item -LiteralPath $existingPdf).Length -ge 5000 -and
            [IO.Path]::GetFileName($existingPdf) -eq [string]$existingArtifact.filename -and
            [IO.Path]::GetFullPath([string]$existingArtifact.source_tex) -eq [IO.Path]::GetFullPath($TexPath)
        )
        if ($validExisting) {
            $validExisting = ((Get-FileHash -Algorithm SHA256 -LiteralPath $existingPdf).Hash.ToLowerInvariant() -eq [string]$existingArtifact.sha256)
        }
        if ($validExisting -and $StrictOnePage) {
            $actualPages = Get-PdfPageCount -Path $existingPdf
            if ($null -ne $actualPages) { $validExisting = ($actualPages -eq 1) }
            if ($validExisting -and $null -ne $existingArtifact.pages) { $validExisting = ([int]$existingArtifact.pages -eq 1) }
        }
        if ($validExisting) {
            Clear-ResumeClaim
            Write-Output $existingPdf
            exit 0
        }
    } catch {}
}

Push-Location $workDir
try {
    Invoke-PdfCompile -Name $texName
    if (-not (Test-Path -LiteralPath $pdfPath)) { throw "PDF was not produced: $pdfPath" }

    $pages = Get-PdfPageCount -Path $pdfPath
    if ($StrictOnePage -and $null -ne $pages -and $pages -ne 1 -and $AutoCompact) {
        Write-Warning "Generated resume has $pages pages; applying one controlled compact-layout fallback."
        Invoke-ControlledCompaction
        Invoke-PdfCompile -Name $texName
        $pages = Get-PdfPageCount -Path $pdfPath
    }

    $pdf = Get-Item -LiteralPath $pdfPath
    if ($pdf.Length -lt 5000) { throw "Generated PDF looks too small ($($pdf.Length) bytes)." }

    if (Test-Path -LiteralPath $logPath) {
        $logText = Get-Content -LiteralPath $logPath -Raw
        if ($logText -match '! LaTeX Error:|Fatal error occurred|Emergency stop') { throw 'LaTeX log contains a fatal error.' }
        if ($logText -match 'Overfull \\hbox') { Write-Warning 'LaTeX reported an overfull hbox. Tighten content before upload if visually significant.' }
    }

    if ($StrictOnePage -and $null -ne $pages -and $pages -ne 1) { throw "Strict one-page check failed after allowed fallback: generated PDF has $pages pages." }
    if ($StrictOnePage -and $null -eq $pages) { Write-Warning 'Could not determine page count because neither pdfinfo nor pdftotext was usable.' }

    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue
    if ($pdftotext) {
        $txtPath = Join-Path $workDir "$baseName.txt"
        & pdftotext -layout $pdfPath $txtPath 2>$null
        if (Test-Path -LiteralPath $txtPath) {
            $txt = Get-Content -LiteralPath $txtPath -Raw
            if ($txt -notmatch [regex]::Escape($candidateName)) { throw 'PDF text extraction did not contain candidate name.' }
            if ($txt -notmatch [regex]::Escape($candidateEmail)) { throw 'PDF text extraction did not contain candidate email.' }
        }
    }

    $companyPart = Convert-ToFilenamePart ([string]$jobMeta.company) 40
    $rolePart = Convert-ToFilenamePart ([string]$jobMeta.title) 65
    $candidatePart = Convert-ToFilenamePart $candidateName 50
    $applicationFilename = "${candidatePart}_${companyPart}_${rolePart}.pdf"
    $applicationPdf = Join-Path $workDir $applicationFilename
    Copy-Item -LiteralPath $pdfPath -Destination $applicationPdf -Force
    $artifactHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $applicationPdf).Hash.ToLowerInvariant()

    $artifact = [ordered]@{
        job_id = [string]$jobMeta.job_id
        company = [string]$jobMeta.company
        title = [string]$jobMeta.title
        filename = $applicationFilename
        path = $applicationPdf
        sha256 = $artifactHash
        pages = $pages
        source_tex = $TexPath
        generic_compile_pdf = $pdfPath
        created_at = (Get-Date).ToUniversalTime().ToString('o')
        status = 'ready-for-upload'
    }
    $artifactTemp = "$artifactPath.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $artifact | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $artifactTemp -Encoding UTF8
        [IO.File]::Move($artifactTemp, $artifactPath, $true)
    } finally {
        if (Test-Path -LiteralPath $artifactTemp) { Remove-Item -LiteralPath $artifactTemp -Force -ErrorAction SilentlyContinue }
    }

    Clear-ResumeClaim
    Write-Output $applicationPdf
}
finally {
    Pop-Location
}
} finally {
    if ($null -ne $compileLock) { $compileLock.Dispose() }
}
