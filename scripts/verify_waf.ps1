#Requires -Version 5.1
<#
.SYNOPSIS
    Verify Cloudflare WAF rules are enforced against the live backend.

.DESCRIPTION
    Runs a series of HTTP checks against a deployed backend URL to confirm
    that WAF rules, HSTS, and rate limiting behave as expected.
    This script VERIFIES enforcement; it does not provision rules.
    Requests that reach the backend auth layer and return 401 do not count
    as WAF enforcement for the admin-path checks.

.PARAMETER BaseUrl
    Base URL of the deployed backend, e.g. https://api.yourdomain.com

.EXAMPLE
    .\scripts\verify_waf.ps1 -BaseUrl https://api.yourdomain.com
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BaseUrl = $BaseUrl.TrimEnd('/')
$pass    = 0
$fail    = 0

function Write-Pass { param([string]$Msg) Write-Host "[PASS] $Msg" -ForegroundColor Green; $script:pass++ }
function Write-Fail { param([string]$Msg) Write-Host "[FAIL] $Msg" -ForegroundColor Red;  $script:fail++ }
function Write-Info { param([string]$Msg) Write-Host "[INFO] $Msg" }

function Invoke-Check {
    param(
        [string]$Label,
        [string]$Uri,
        [hashtable]$Headers = @{},
        [int[]]$ExpectStatus,
        [scriptblock]$ExtraAssert = $null
    )

    try {
        $resp = Invoke-WebRequest -Uri $Uri -Headers $Headers `
            -UseBasicParsing -TimeoutSec 15 `
            -ErrorAction SilentlyContinue

        $status = $resp.StatusCode
    } catch {
        # Invoke-WebRequest throws on 4xx/5xx — capture via exception
        $resp   = $_.Exception.Response
        $status = if ($resp) { [int]$resp.StatusCode } else { 0 }
    }

    $statusOk = $status -in $ExpectStatus

    if (-not $statusOk) {
        Write-Fail "$Label — expected status $($ExpectStatus -join '/'), got $status"
        return
    }

    if ($ExtraAssert) {
        try {
            & $ExtraAssert $resp $status
        } catch {
            Write-Fail "$Label — $($_.Exception.Message)"
            return
        }
    }

    Write-Pass "$Label (HTTP $status)"
}

function Get-ResponseStatusAndHeaders {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [hashtable]$Headers = @{}
    )

    try {
        $resp = Invoke-WebRequest -Uri $Uri -Headers $Headers `
            -UseBasicParsing -TimeoutSec 15 `
            -ErrorAction SilentlyContinue
        return @{
            Response = $resp
            Status   = $resp.StatusCode
        }
    } catch {
        $resp = $_.Exception.Response
        return @{
            Response = $resp
            Status   = if ($resp) { [int]$resp.StatusCode } else { 0 }
        }
    }
}

# ── 1. Health check ────────────────────────────────────────────────────────────
Write-Info "Target: $BaseUrl"
Write-Info ''
Write-Info '=== 1. Health check ==='

Invoke-Check -Label 'GET /health returns 200' `
    -Uri "$BaseUrl/health" `
    -ExpectStatus @(200)

# ── 2. HSTS header ─────────────────────────────────────────────────────────────
Write-Info ''
Write-Info '=== 2. HSTS header ==='

try {
    $healthResp = Invoke-WebRequest -Uri "$BaseUrl/health" -UseBasicParsing -TimeoutSec 10
    if ($healthResp.Headers['strict-transport-security']) {
        Write-Pass 'Strict-Transport-Security header present'
    } else {
        Write-Fail 'Strict-Transport-Security header missing'
    }
} catch {
    Write-Fail "Could not check HSTS — $($_.Exception.Message)"
}

# ── 3. Admin path blocking ─────────────────────────────────────────────────────
Write-Info ''
Write-Info '=== 3. Admin path blocking (/api/v1/admin/*) ==='

$adminPath = '/api/v1/admin/cleanup'

Write-Info "Using real admin route: $adminPath"

$adminHeadersToTry = @(
    @{ Label = 'default headers'; Headers = @{} },
    @{ Label = 'sqlmap user-agent'; Headers = @{ 'User-Agent' = 'sqlmap/1.0' } },
    @{ Label = 'empty user-agent'; Headers = @{ 'User-Agent' = '' } }
)

foreach ($attempt in $adminHeadersToTry) {
    $result = Get-ResponseStatusAndHeaders -Uri "$BaseUrl$adminPath" -Headers $attempt.Headers
    $status = $result.Status

    if ($status -in @(403, 429, 503)) {
        Write-Pass "Admin path blocked by edge/WAF with $($attempt.Label) (HTTP $status)"
        continue
    }

    if ($status -eq 401) {
        Write-Fail "Admin path reached backend auth layer with $($attempt.Label) (HTTP 401) — this does not prove WAF enforcement"
        continue
    }

    Write-Fail "Admin path unexpected result with $($attempt.Label) — expected 403/429/503, got $status"
}

# ── 4. Malicious user-agent blocking ──────────────────────────────────────────
Write-Info ''
Write-Info '=== 4. Malicious User-Agent blocking ==='

$badAgents = @('sqlmap/1.0', 'nikto/2.1', 'nmap scripting engine', '')

foreach ($ua in $badAgents) {
    $label = if ($ua -eq '') { 'Empty User-Agent' } else { "UA: $ua" }
    $hdrs  = if ($ua -ne '') { @{'User-Agent' = $ua} } else { @{'User-Agent' = ''} }

    Invoke-Check -Label "$label is blocked (403/429/503)" `
        -Uri "$BaseUrl/health" `
        -Headers $hdrs `
        -ExpectStatus @(403, 429, 503)
}

# ── 5. Rate-limit burst on /health ────────────────────────────────────────────
Write-Info ''
Write-Info '=== 5. Rate-limit burst test (12 rapid GET /health) ==='

$got429 = $false
for ($i = 1; $i -le 12; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl/health" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
        $s = $r.StatusCode
    } catch {
        $r = $_.Exception.Response
        $s = if ($r) { [int]$r.StatusCode } else { 0 }
    }
    if ($s -eq 429) { $got429 = $true; break }
}

if ($got429) {
    Write-Pass '429 observed during burst — rate limiting is active'
} else {
    Write-Info 'No 429 observed in 12 requests — WAF or backend rate limit may have a higher window'
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Info ''
Write-Info '=== Summary ==='
Write-Info "PASS: $pass   FAIL: $fail"

if ($fail -gt 0) {
    Write-Host "[RESULT] FAIL — $fail check(s) did not pass." -ForegroundColor Red
    exit 1
} else {
    Write-Host '[RESULT] PASS — all checks passed.' -ForegroundColor Green
}
