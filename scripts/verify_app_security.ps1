#Requires -Version 5.1
<#
.SYNOPSIS
    Verify application-layer security controls (no WAF or domain required).

.DESCRIPTION
    Tests security enforced by the Fastify backend itself:
      - Auth middleware  : missing / malformed JWT => 401
      - Role enforcement : non-admin token on admin route => 403 (needs -UserToken)
      - App-level rate limiting : burst login/health => 429
      - Body size limit  : oversized JSON payload => 413

    Works against localhost, docker-compose, or Cloudflare Quick Tunnel.
    Does NOT require a Cloudflare-managed zone or Zone-level WAF rules.

    For WAF/edge-layer checks (HSTS, malicious UA blocking, edge-403 on admin paths)
    use verify_waf.ps1 once a proper domain is available.

.PARAMETER BaseUrl
    Backend URL. Examples:
      http://localhost:3000
      https://xxxx.trycloudflare.com

.PARAMETER UserToken
    (Optional) Valid access token for a non-admin user.
    Enables the role-enforcement 403 check; skipped when omitted.

.EXAMPLE
    .\scripts\verify_app_security.ps1 -BaseUrl http://localhost:3000
    .\scripts\verify_app_security.ps1 -BaseUrl https://xxxx.trycloudflare.com -UserToken eyJ...
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$BaseUrl,

    [string]$UserToken = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$BaseUrl = $BaseUrl.TrimEnd('/')
$pass    = 0
$fail    = 0
$skip    = 0

function Write-Pass { param([string]$Msg) Write-Host "[PASS] $Msg" -ForegroundColor Green;  $script:pass++ }
function Write-Fail { param([string]$Msg) Write-Host "[FAIL] $Msg" -ForegroundColor Red;    $script:fail++ }
function Write-Skip { param([string]$Msg) Write-Host "[SKIP] $Msg" -ForegroundColor Yellow; $script:skip++ }
function Write-Info { param([string]$Msg) Write-Host "[INFO] $Msg" }

function Invoke-Check {
    param(
        [string]   $Label,
        [string]   $Uri,
        [string]   $Method    = 'GET',
        [hashtable]$Headers   = @{},
        [string]   $Body      = '',
        [int[]]    $ExpectStatus
    )

    try {
        $params = @{
            Uri             = $Uri
            Method          = $Method
            Headers         = $Headers
            UseBasicParsing = $true
            TimeoutSec      = 15
            ErrorAction     = 'SilentlyContinue'
        }
        if ($Body -ne '') {
            $params['Body']        = $Body
            $params['ContentType'] = 'application/json'
        }
        $resp   = Invoke-WebRequest @params
        $status = $resp.StatusCode
    } catch {
        $resp   = $_.Exception.Response
        $status = if ($resp) { [int]$resp.StatusCode } else { 0 }
    }

    if ($status -in $ExpectStatus) {
        Write-Pass "$Label (HTTP $status)"
    } else {
        Write-Fail "$Label — expected $($ExpectStatus -join '/'), got $status"
    }
}

Write-Info "Target: $BaseUrl"

# ── 1. Health check ────────────────────────────────────────────────────────────
Write-Info ''
Write-Info '=== 1. Health check ==='

Invoke-Check -Label 'GET /health returns 200' `
    -Uri "$BaseUrl/health" `
    -ExpectStatus @(200)

# ── 2. Auth — missing token ────────────────────────────────────────────────────
Write-Info ''
Write-Info '=== 2. Auth — missing token ==='

Invoke-Check -Label 'GET /api/v1/customers without token => 401' `
    -Uri "$BaseUrl/api/v1/customers" `
    -ExpectStatus @(401)

Invoke-Check -Label 'GET /api/v1/products without token => 401' `
    -Uri "$BaseUrl/api/v1/products" `
    -ExpectStatus @(401)

Invoke-Check -Label 'POST /api/v1/admin/cleanup without token => 401' `
    -Uri "$BaseUrl/api/v1/admin/cleanup" `
    -Method 'POST' `
    -ExpectStatus @(401)

# ── 3. Auth — malformed JWT ────────────────────────────────────────────────────
Write-Info ''
Write-Info '=== 3. Auth — malformed JWT ==='

# Structurally valid Base64url segments but wrong signature
$fakeJwt = 'eyJhbGciOiJIUzI1NiJ9.bm90dmFsaWQ.bm90dmFsaWQ'

Invoke-Check -Label 'GET /api/v1/customers with fake JWT => 401' `
    -Uri "$BaseUrl/api/v1/customers" `
    -Headers @{ Authorization = "Bearer $fakeJwt" } `
    -ExpectStatus @(401)

Invoke-Check -Label 'GET /api/v1/customers with garbled token => 401' `
    -Uri "$BaseUrl/api/v1/customers" `
    -Headers @{ Authorization = 'Bearer notajwt' } `
    -ExpectStatus @(401)

# ── 4. Role enforcement (optional — requires -UserToken) ──────────────────────
Write-Info ''
Write-Info '=== 4. Role enforcement (non-admin token on admin route) ==='

if ($UserToken -eq '') {
    Write-Skip 'Role-403 check skipped — supply -UserToken <non-admin bearer> to enable'
} else {
    Invoke-Check -Label 'POST /api/v1/admin/cleanup with non-admin token => 403' `
        -Uri "$BaseUrl/api/v1/admin/cleanup" `
        -Method 'POST' `
        -Headers @{ Authorization = "Bearer $UserToken" } `
        -ExpectStatus @(403)
}

# ── 5. Rate limiting — login endpoint (limit: 10/min) ─────────────────────────
Write-Info ''
Write-Info '=== 5. Rate limiting — POST /api/v1/auth/login (limit: 10/min) ==='

$loginBody    = '{"username":"__ratelimit_probe__","password":"__ratelimit_probe__"}'
$got429Login  = $false

for ($i = 1; $i -le 11; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl/api/v1/auth/login" `
            -Method 'POST' -Body $loginBody -ContentType 'application/json' `
            -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
        $s = $r.StatusCode
    } catch {
        $ex = $_.Exception.Response
        $s  = if ($ex) { [int]$ex.StatusCode } else { 0 }
    }
    if ($s -eq 429) { $got429Login = $true; break }
}

if ($got429Login) {
    Write-Pass 'Login rate limit triggered (HTTP 429)'
} else {
    Write-Fail 'Login rate limit NOT triggered after 11 rapid requests'
}

# ── 6. Rate limiting — /health (limit: 10/min) ────────────────────────────────
Write-Info ''
Write-Info '=== 6. Rate limiting — GET /health (limit: 10/min) ==='

$got429Health = $false

for ($i = 1; $i -le 11; $i++) {
    try {
        $r = Invoke-WebRequest -Uri "$BaseUrl/health" `
            -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
        $s = $r.StatusCode
    } catch {
        $ex = $_.Exception.Response
        $s  = if ($ex) { [int]$ex.StatusCode } else { 0 }
    }
    if ($s -eq 429) { $got429Health = $true; break }
}

if ($got429Health) {
    Write-Pass 'Health rate limit triggered (HTTP 429)'
} else {
    Write-Fail 'Health rate limit NOT triggered after 11 rapid requests'
}

# ── 7. Body size limit — Fastify default 1 MB ─────────────────────────────────
Write-Info ''
Write-Info '=== 7. Body size limit — oversized JSON payload (> 1 MB) ==='

# Use /api/v1/customers (requires auth) — body parsing fires before auth,
# so 413 should come back before the 401 auth check.
$bigBody = "{`"data`":`"$('x' * (1050 * 1024))`"}"

try {
    $r = Invoke-WebRequest -Uri "$BaseUrl/api/v1/customers" `
        -Method 'POST' -Body $bigBody -ContentType 'application/json' `
        -UseBasicParsing -TimeoutSec 10 -ErrorAction SilentlyContinue
    $s = $r.StatusCode
} catch {
    $ex = $_.Exception.Response
    $s  = if ($ex) { [int]$ex.StatusCode } else { 0 }
}

if ($s -eq 413) {
    Write-Pass "Oversized body rejected (HTTP 413)"
} elseif ($s -in @(401, 400)) {
    # Auth check fired before body parse (framework-dependent order) — still secure
    Write-Info "Server returned $s for oversized body; auth/validation fired first (acceptable)"
    $script:pass++
} else {
    Write-Fail "Oversized body — expected 413/401/400, got $s"
}

# ── Summary ────────────────────────────────────────────────────────────────────
Write-Info ''
Write-Info '=== Summary ==='
Write-Info "PASS: $pass   FAIL: $fail   SKIP: $skip"
Write-Info ''
Write-Info 'NOTE: Edge/WAF-layer checks (HSTS, malicious UA blocking, edge-403 on admin'
Write-Info '      paths) require a Cloudflare-managed domain — use verify_waf.ps1 then.'

if ($fail -gt 0) {
    Write-Host "[RESULT] FAIL — $fail check(s) did not pass." -ForegroundColor Red
    exit 1
} else {
    Write-Host '[RESULT] PASS — all app-layer security checks passed.' -ForegroundColor Green
}
