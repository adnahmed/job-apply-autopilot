function Normalize-JobText([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return (($Value.ToLowerInvariant() -replace '&', ' and ' -replace '[^a-z0-9]+', ' ').Trim() -replace '\s+', ' ')
}

function Normalize-JobCompany([string]$Value) {
    $normalized = Normalize-JobText $Value
    do {
        $before = $normalized
        $normalized = ($normalized -replace '\s+(private limited|pvt ltd|pvt limited|limited|ltd|llc|incorporated|inc|corporation|corp|gmbh|plc|company|co)$', '').Trim()
    } while ($normalized -ne $before)
    return $normalized
}

function Get-JobTokens([string]$Value, [switch]$Title) {
    $stop = @('a','an','and','at','for','in','of','on','the','to','with')
    if ($Title) { $stop += @('hiring','job','opening','position','role','remote','onsite','on-site') }
    return @((Normalize-JobText $Value).Split(' ', [StringSplitOptions]::RemoveEmptyEntries) |
        Where-Object { $_.Length -gt 1 -and $_ -notin $stop } | Sort-Object -Unique)
}

function Get-TokenSimilarity([string[]]$Left, [string[]]$Right) {
    if ($Left.Count -eq 0 -or $Right.Count -eq 0) { return 0.0 }
    $intersection = @($Left | Where-Object { $_ -in $Right }).Count
    $union = @($Left + $Right | Sort-Object -Unique).Count
    if ($union -eq 0) { return 0.0 }
    return [double]$intersection / [double]$union
}

function Get-PostedDay($Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
    try { return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).UtcDateTime.ToString('yyyy-MM-dd') }
    catch { return ([string]$Value).Substring(0, [Math]::Min(10, ([string]$Value).Length)) }
}

function Get-JobIdentity($Job) {
    $description = if ($Job.PSObject.Properties.Name -contains 'description') { [string]$Job.description } else { '' }
    $posted = if ($Job.PSObject.Properties.Name -contains 'posted_at') { $Job.posted_at } else { $null }
    $external = if ($Job.PSObject.Properties.Name -contains 'external_id') { [string]$Job.external_id } else { '' }
    $url = if ($Job.PSObject.Properties.Name -contains 'source_url' -and $Job.source_url) { [string]$Job.source_url } elseif ($Job.PSObject.Properties.Name -contains 'job_url') { [string]$Job.job_url } else { '' }
    return [ordered]@{
        job_id = [string]$Job.job_id
        company_key = Normalize-JobCompany ([string]$Job.company)
        title_tokens = @(Get-JobTokens ([string]$Job.title) -Title)
        location_key = Normalize-JobText ([string]$Job.location)
        description_tokens = @(Get-JobTokens $description)
        posted_day = Get-PostedDay $posted
        external_id = Normalize-JobText $external
        source_url = $url.Trim().ToLowerInvariant()
    }
}

function Test-JobIdentityMatch($LeftJob, $RightJob) {
    $left = Get-JobIdentity $LeftJob
    $right = Get-JobIdentity $RightJob
    if ($left.external_id -and $right.external_id -and $left.external_id -eq $right.external_id) {
        return [ordered]@{ matched=$true; reason='external-id'; title_similarity=1.0; description_similarity=1.0 }
    }
    if ($left.source_url -and $right.source_url -and $left.source_url -eq $right.source_url) {
        return [ordered]@{ matched=$true; reason='source-url'; title_similarity=1.0; description_similarity=1.0 }
    }
    if (-not $left.company_key -or $left.company_key -ne $right.company_key) {
        return [ordered]@{ matched=$false; reason='company-different'; title_similarity=0.0; description_similarity=0.0 }
    }
    $titleSimilarity = Get-TokenSimilarity $left.title_tokens $right.title_tokens
    $descriptionSimilarity = Get-TokenSimilarity $left.description_tokens $right.description_tokens
    $sameDay = ($left.posted_day -and $right.posted_day -and $left.posted_day -eq $right.posted_day)
    $locationCompatible = (-not $left.location_key -or -not $right.location_key -or $left.location_key -eq $right.location_key)
    $descriptionsMissing = ($left.description_tokens.Count -eq 0 -or $right.description_tokens.Count -eq 0)
    $matched = $locationCompatible -and $titleSimilarity -ge 0.50 -and (
        $descriptionSimilarity -ge 0.45 -or $sameDay -or ($descriptionsMissing -and $titleSimilarity -ge 0.85)
    )
    return [ordered]@{
        matched = [bool]$matched
        reason = if ($matched) { 'semantic-fingerprint' } else { 'fingerprint-different' }
        title_similarity = [math]::Round($titleSimilarity, 3)
        description_similarity = [math]::Round($descriptionSimilarity, 3)
        same_posted_day = [bool]$sameDay
    }
}
