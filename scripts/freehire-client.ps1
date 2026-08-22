[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('GET','POST','PATCH')][string]$Method,
    [Parameter(Mandatory=$true)][string]$Path,
    [string]$QueryJson = '{}',
    [string]$BodyJson = '',
    [ValidateSet('none','optional','required')][string]$Auth = 'optional',
    [ValidateSet('free','cached-ai','credit')][string]$CostClass = 'free',
    [string]$Workspace = '',
    [string]$BaseUrl = '',
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml'),
    [ValidateRange(0,8760)][int]$CacheHours = 0,
    [switch]$NoCache
)

$ErrorActionPreference = 'Stop'

function Emit($Value) {
    $Value | ConvertTo-Json -Depth 50 -Compress | Write-Output
}

function Read-JsonSafe([string]$FilePath) {
    if (-not (Test-Path -LiteralPath $FilePath)) { return $null }
    try { return Get-Content -LiteralPath $FilePath -Raw | ConvertFrom-Json } catch { return $null }
}

function Write-JsonAtomic([string]$FilePath, $Value) {
    $parent = Split-Path -Parent $FilePath
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $temp = "$FilePath.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $temp -Encoding UTF8
        [IO.File]::Move($temp, $FilePath, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Parse-Utc($Value) {
    try { return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() }
    catch { return $null }
}

function Profile-Scalar([string]$Name, $Default = $null) {
    if (-not (Test-Path -LiteralPath $ProfilePath)) { return $Default }
    $text = Get-Content -LiteralPath $ProfilePath -Raw
    $pattern = '(?m)^\s*' + [regex]::Escape($Name) + ':\s*["'']?([^\r\n"'']+)'
    if ($text -match $pattern) { return $Matches[1].Trim() }
    return $Default
}

function To-Bool($Value, [bool]$Default = $false) {
    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }
    return [string]$Value -match '^(?i:true|1|yes|on|enabled)$'
}

function Get-Hash([string]$Value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Resolve-Credentials {
    $token = [string][Environment]::GetEnvironmentVariable('FREEHIRE_TOKEN')
    $source = if ($token) { 'FREEHIRE_TOKEN' } else { '' }
    if (-not $token) {
        $token = [string][Environment]::GetEnvironmentVariable('FREEHIRE_API_KEY')
        if ($token) { $source = 'FREEHIRE_API_KEY' }
    }
    $credentialApiUrl = ''
    if (-not $token) {
        $userProfile = [Environment]::GetFolderPath('UserProfile')
        $credentialPath = Join-Path $userProfile '.freehire\creds.json'
        $credentials = Read-JsonSafe $credentialPath
        if ($credentials -and $credentials.token) {
            $token = [string]$credentials.token
            $credentialApiUrl = [string]$credentials.api_url
            $source = 'freehire-cli'
        }
    }
    return [ordered]@{ token=$token; source=$source; api_url=$credentialApiUrl }
}

function Test-AllowedEndpoint([string]$Verb, [string]$Route) {
    $patterns = @{
        GET = @(
            '^agent/jobs/search$', '^jobs/facets$', '^jobs/find$', '^jobs/[^/]+$',
            '^jobs/[^/]+/(similar|copies|apply-form|match|match-analysis)$', '^insights/salary$',
            '^me/(autofill-profile|screening-answers|credits|credits/history|usage|gmail|inbox)$',
            '^me/emails/\d+$', '^me/tracking(/pipeline|/[^/]+)?$'
        )
        POST = @(
            '^market/coverage$', '^me/match-text$', '^jobs/resolve$', '^jobs/[^/]+/apply$',
            '^me/gmail/sync$', '^me/emails$', '^me/emails/\d+/(triage|confirm|reject|application)$'
        )
        PATCH = @('^jobs/[^/]+/track$')
    }
    foreach ($pattern in @($patterns[$Verb])) { if ($Route -match $pattern) { return $true } }
    return $false
}

function Write-Telemetry($Event) {
    if (-not $runtimeRoot) { return }
    $logPath = Join-Path $runtimeRoot 'freehire-api.jsonl'
    $lockPath = Join-Path $runtimeRoot 'freehire-api.lock'
    $lock = $null
    try {
        try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') } catch { return }
        $line = ($Event | ConvertTo-Json -Compress -Depth 8) + [Environment]::NewLine
        [IO.File]::AppendAllText($logPath, $line, [Text.UTF8Encoding]::new($false))
    } finally {
        if ($null -ne $lock) { $lock.Dispose() }
    }
}

$Method = $Method.ToUpperInvariant()
$route = $Path.Trim().TrimStart('/')
if ([string]::IsNullOrWhiteSpace($route) -or $route.Contains('?') -or $route.Contains('..')) { throw 'FreeHire path must be a relative API path without a query string.' }

if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = (Get-Location).Path }
try { $Workspace = (Resolve-Path -LiteralPath $Workspace).Path } catch {}
$runtimeRoot = Join-Path $Workspace '.job-apply-autopilot'
if (-not (Test-Path -LiteralPath $runtimeRoot)) { $runtimeRoot = $null }

$started = [Diagnostics.Stopwatch]::StartNew()
$now = [DateTimeOffset]::UtcNow
$event = [ordered]@{
    timestamp=$now.ToString('o'); method=$Method; path=$route; cost_class=$CostClass
    query_keys=@(); body_hash=$null; cache_hit=$false; latency_ms=0; status='pending'
    auth_used=$false; credential_source=$null; error_code=$null
}

if ($CostClass -eq 'credit') {
    $event.status = 'policy-blocked'; $event.error_code = 'ai-credit-spend-disabled'; $event.latency_ms = $started.ElapsedMilliseconds
    Write-Telemetry $event
    Emit ([ordered]@{status='policy-blocked';data=$null;meta=$null;cached=$false;latency_ms=$event.latency_ms;error_code='ai-credit-spend-disabled'})
    exit 0
}
if (-not (Test-AllowedEndpoint $Method $route)) {
    $event.status = 'policy-blocked'; $event.error_code = 'endpoint-not-zero-credit-allowlisted'; $event.latency_ms = $started.ElapsedMilliseconds
    Write-Telemetry $event
    Emit ([ordered]@{status='policy-blocked';data=$null;meta=$null;cached=$false;latency_ms=$event.latency_ms;error_code='endpoint-not-zero-credit-allowlisted'})
    exit 0
}

$query = try { if ([string]::IsNullOrWhiteSpace($QueryJson)) { [pscustomobject]@{} } else { $QueryJson | ConvertFrom-Json } } catch { throw 'QueryJson is not valid JSON.' }
$queryPairs = [Collections.Generic.List[string]]::new()
foreach ($property in @($query.PSObject.Properties | Sort-Object Name)) {
    $event.query_keys += [string]$property.Name
    $values = if ($property.Value -is [System.Collections.IEnumerable] -and -not ($property.Value -is [string])) { @($property.Value) } else { @($property.Value) }
    foreach ($value in $values) {
        if ($null -eq $value) { continue }
        $rendered = if ($value -is [bool]) { ([string]$value).ToLowerInvariant() } else { [string]$value }
        $queryPairs.Add("$([Uri]::EscapeDataString([string]$property.Name))=$([Uri]::EscapeDataString($rendered))")
    }
}

$body = $null
if ($Method -ne 'GET') {
    $body = if ([string]::IsNullOrWhiteSpace($BodyJson)) { '{}' } else { ($BodyJson | ConvertFrom-Json | ConvertTo-Json -Compress -Depth 50) }
    $event.body_hash = Get-Hash $body
}

$baseUrl = if ($BaseUrl) { $BaseUrl } else { [string](Profile-Scalar 'base_url' 'https://freehire.me/api/v1') }
$credentials = Resolve-Credentials
if (-not $baseUrl -and $credentials.api_url) { $baseUrl = [string]$credentials.api_url }
$baseUrl = $baseUrl.TrimEnd('/')
$uri = "$baseUrl/$route"
if ($queryPairs.Count) { $uri += '?' + ($queryPairs -join '&') }

$headers = @{ Accept='application/json' }
$authenticatedEnabled = To-Bool (Profile-Scalar 'authenticated_enabled' 'true') $true
if ($Auth -ne 'none' -and -not $authenticatedEnabled) {
    if ($Auth -eq 'required') {
        $event.status = 'auth-unavailable'; $event.error_code = 'authenticated-freehire-disabled'; $event.latency_ms = $started.ElapsedMilliseconds
        Write-Telemetry $event
        Emit ([ordered]@{status='auth-unavailable';data=$null;meta=$null;cached=$false;latency_ms=$event.latency_ms;error_code='authenticated-freehire-disabled'})
        exit 0
    }
} elseif ($Auth -ne 'none' -and $credentials.token) {
    $headers.Authorization = "Bearer $($credentials.token)"
    $event.auth_used = $true
    $event.credential_source = $credentials.source
} elseif ($Auth -eq 'required') {
    $event.status = 'auth-unavailable'; $event.error_code = 'missing-freehire-credential'; $event.latency_ms = $started.ElapsedMilliseconds
    Write-Telemetry $event
    Emit ([ordered]@{status='auth-unavailable';data=$null;meta=$null;cached=$false;latency_ms=$event.latency_ms;error_code='missing-freehire-credential'})
    exit 0
}

$cachePath = $null
$cacheLock = $null
if ($runtimeRoot -and -not $NoCache -and $CacheHours -gt 0) {
    $credentialPartition = if ($event.auth_used) { (Get-Hash ([string]$credentials.token)).Substring(0,16) } else { 'public' }
    $cacheKey = Get-Hash "$credentialPartition|$Method|$uri|$body"
    $cachePath = Join-Path $runtimeRoot "cache\freehire\$cacheKey.json"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cachePath) | Out-Null
    $cached = Read-JsonSafe $cachePath
    $cacheExpiry = if ($cached -and $cached.expires_at) { Parse-Utc $cached.expires_at } else { $null }
    if ($cached -and $cacheExpiry -and $cacheExpiry -gt $now) {
        $event.status='cached'; $event.cache_hit=$true; $event.latency_ms=$started.ElapsedMilliseconds
        Write-Telemetry $event
        Emit ([ordered]@{status='ok';data=$cached.data;meta=$cached.meta;cached=$true;latency_ms=$event.latency_ms;error_code=$null})
        exit 0
    }
    $cacheLockPath = "$cachePath.lock"
    try { $cacheLock = [IO.File]::Open($cacheLockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch {
        for ($waitAttempt=0; $waitAttempt -lt 20; $waitAttempt++) {
            Start-Sleep -Milliseconds 100
            $coalesced = Read-JsonSafe $cachePath
            $coalescedExpiry = if ($coalesced -and $coalesced.expires_at) { Parse-Utc $coalesced.expires_at } else { $null }
            if ($coalesced -and $coalescedExpiry -and $coalescedExpiry -gt [DateTimeOffset]::UtcNow) {
                $event.status='cached'; $event.cache_hit=$true; $event.latency_ms=$started.ElapsedMilliseconds
                Write-Telemetry $event
                Emit ([ordered]@{status='ok';data=$coalesced.data;meta=$coalesced.meta;cached=$true;coalesced=$true;latency_ms=$event.latency_ms;error_code=$null})
                exit 0
            }
        }
        try { $cacheLock = [IO.File]::Open($cacheLockPath, 'OpenOrCreate', 'ReadWrite', 'None') } catch {}
        if ($null -eq $cacheLock) {
            $event.status='deferred'; $event.error_code='identical-request-in-flight'; $event.latency_ms=$started.ElapsedMilliseconds
            Write-Telemetry $event
            Emit ([ordered]@{status='deferred';data=$null;meta=$null;cached=$false;coalesced=$true;latency_ms=$event.latency_ms;error_code='identical-request-in-flight'})
            exit 0
        }
    }
}

if ($runtimeRoot) {
    $circuitPath = Join-Path $runtimeRoot 'freehire-circuit.json'
    $circuit = Read-JsonSafe $circuitPath
    $circuitExpiry = if ($circuit -and $circuit.expires_at) { Parse-Utc $circuit.expires_at } else { $null }
    if ($circuitExpiry -and $circuitExpiry -gt $now) {
        if ($null -ne $cacheLock) { $cacheLock.Dispose(); $cacheLock=$null }
        $event.status='rate-limited'; $event.error_code='freehire-circuit-open'; $event.latency_ms=$started.ElapsedMilliseconds
        Write-Telemetry $event
        Emit ([ordered]@{status='rate-limited';data=$null;meta=[ordered]@{retry_after=$circuitExpiry.ToString('o')};cached=$false;latency_ms=$event.latency_ms;error_code='freehire-circuit-open'})
        exit 0
    }
}

try {
    $invoke = @{ Method=$Method; Uri=$uri; Headers=$headers; ErrorAction='Stop' }
    if ($Method -ne 'GET') { $invoke.ContentType='application/json'; $invoke.Body=$body }
    $response = Invoke-RestMethod @invoke
    $hasData = $response -and $response.PSObject.Properties.Name -contains 'data'
    $data = if ($hasData) { $response.data } else { $response }
    $meta = if ($response -and $response.PSObject.Properties.Name -contains 'meta') { $response.meta } else { $null }
    if ($cachePath) {
        Write-JsonAtomic $cachePath ([ordered]@{fetched_at=$now.ToString('o');expires_at=$now.AddHours($CacheHours).ToString('o');data=$data;meta=$meta})
    }
    if ($null -ne $cacheLock) { $cacheLock.Dispose(); $cacheLock=$null }
    $event.status='ok'; $event.latency_ms=$started.ElapsedMilliseconds
    Write-Telemetry $event
    Emit ([ordered]@{status='ok';data=$data;meta=$meta;cached=$false;latency_ms=$event.latency_ms;error_code=$null})
} catch {
    if ($null -ne $cacheLock) { $cacheLock.Dispose(); $cacheLock=$null }
    $statusCode = 0
    try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
    $errorCode = if ($statusCode -eq 401) { 'unauthorized' } elseif ($statusCode -eq 404) { 'not-found' } elseif ($statusCode -eq 429) { 'rate-limited' } elseif ($statusCode) { "http-$statusCode" } else { 'network-error' }
    if ($statusCode -eq 429 -and $runtimeRoot) {
        $minutes = [int](Profile-Scalar 'rate_limit_cooldown_minutes' 15)
        Write-JsonAtomic (Join-Path $runtimeRoot 'freehire-circuit.json') ([ordered]@{reason='http-429';opened_at=$now.ToString('o');expires_at=$now.AddMinutes([Math]::Max(1,$minutes)).ToString('o')})
    }
    $event.status = if ($statusCode -eq 404) { 'not-found' } elseif ($statusCode -eq 429) { 'rate-limited' } else { 'error' }
    $event.error_code=$errorCode; $event.latency_ms=$started.ElapsedMilliseconds
    Write-Telemetry $event
    Emit ([ordered]@{status=$event.status;data=$null;meta=[ordered]@{http_status=$statusCode};cached=$false;latency_ms=$event.latency_ms;error_code=$errorCode})
}
