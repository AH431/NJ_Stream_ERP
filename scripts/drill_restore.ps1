#Requires -Version 5.1
<#
.SYNOPSIS
    Automated restore drill — backs up, restores into an isolated container,
    runs SQL smoke checks, and reports PASS or FAIL.

.DESCRIPTION
    Validates the full backup/restore pipeline end-to-end without touching
    the live production container.

.PARAMETER SkipBackup
    Skip the backup step and use the most recent .pgdump.gpg already in BACKUP_DIR.

.EXAMPLE
    .\scripts\drill_restore.ps1

.EXAMPLE
    .\scripts\drill_restore.ps1 -SkipBackup
#>

param(
    [switch]$SkipBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$drillContainer = 'nj-erp-postgres-drill'
$drillStarted   = $false
$startTime      = Get-Date
$repoRoot       = Split-Path -Parent $PSScriptRoot

function Write-Drill { param([string]$Msg) Write-Host "[drill] $Msg" }
function Fail {
    param([string]$Msg)
    Write-Host "[drill] FAIL: $Msg" -ForegroundColor Red
    exit 1
}
function Remove-DrillContainerIfExists {
    param([string]$ContainerName)

    $existingContainers = & docker ps -a --format '{{.Names}}'
    if ($LASTEXITCODE -ne 0) {
        Fail 'Failed to query Docker containers.'
    }

    if ($existingContainers -contains $ContainerName) {
        & docker rm -f $ContainerName *> $null
        if ($LASTEXITCODE -ne 0) {
            Fail "Failed to remove existing container '$ContainerName'."
        }
    }
}

# ── 1. Validate required env vars ─────────────────────────────────────────────
$required = @('POSTGRES_USER', 'POSTGRES_DB', 'POSTGRES_PASSWORD', 'BACKUP_PASSPHRASE', 'BACKUP_DIR')
foreach ($var in $required) {
    $envItem = Get-Item -Path "Env:$var" -ErrorAction SilentlyContinue
    $envValue = if ($envItem) { $envItem.Value } else { $null }
    if ([string]::IsNullOrWhiteSpace($envValue)) {
        Fail "Required environment variable '$var' is not set."
    }
}

$DB_USER = $env:POSTGRES_USER
$DB_NAME = $env:POSTGRES_DB
$DB_PASS = $env:POSTGRES_PASSWORD

# ── 2. Optionally run backup ───────────────────────────────────────────────────
if (-not $SkipBackup) {
    Write-Drill 'Running backup...'
    & "$repoRoot\scripts\backup_pg.ps1"
    if ($LASTEXITCODE -ne 0) { Fail 'backup_pg.ps1 failed.' }
}

# ── 3. Find most recent .pgdump.gpg ───────────────────────────────────────────
$latestBackup = Get-ChildItem -Path $env:BACKUP_DIR -Filter '*.pgdump.gpg' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $latestBackup) {
    Fail "No .pgdump.gpg files found in BACKUP_DIR: $($env:BACKUP_DIR)"
}

Write-Drill "Using backup: $($latestBackup.FullName)"

# ── 4. Start isolated drill container ─────────────────────────────────────────
Write-Drill "Starting isolated drill container: $drillContainer"

# Remove any leftover container from a previous failed drill
Remove-DrillContainerIfExists -ContainerName $drillContainer

docker run -d `
    --name $drillContainer `
    -e "POSTGRES_USER=$DB_USER" `
    -e "POSTGRES_DB=$DB_NAME" `
    -e "POSTGRES_PASSWORD=$DB_PASS" `
    postgres:16-alpine

if ($LASTEXITCODE -ne 0) { Fail 'Failed to start drill container.' }
$drillStarted = $true

# ── 5. Wait for pg_isready ────────────────────────────────────────────────────
Write-Drill 'Waiting for pg_isready...'
$deadline = (Get-Date).AddSeconds(60)
$ready = $false
while ((Get-Date) -lt $deadline) {
    docker exec $drillContainer pg_isready -U $DB_USER -d $DB_NAME 2>$null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ready) { Fail 'Drill container did not become ready in time.' }
Write-Drill 'Drill container is ready.'

# ── 6. Restore into drill container ───────────────────────────────────────────
Write-Drill 'Restoring backup into drill container...'
$env:POSTGRES_CONTAINER = $drillContainer
try {
    & "$repoRoot\scripts\restore_pg.ps1" `
        -BackupFile $latestBackup.FullName `
        -DropAndRecreate `
        -Force
    if ($LASTEXITCODE -ne 0) { Fail 'restore_pg.ps1 failed.' }
} finally {
    Remove-Item -Path Env:POSTGRES_CONTAINER -ErrorAction SilentlyContinue
}

# ── 7. SQL smoke checks ───────────────────────────────────────────────────────
Write-Drill 'Running SQL smoke checks...'

function Invoke-DrillQuery {
    param([string]$Query, [string]$Label)
    $result = docker exec `
        -e "PGPASSWORD=$DB_PASS" `
        $drillContainer `
        psql -U $DB_USER -d $DB_NAME -t -A -c $Query
    if ($LASTEXITCODE -ne 0) {
        Fail "SQL check failed [$Label]: exit $LASTEXITCODE"
    }
    return $result.Trim()
}

$custCount = Invoke-DrillQuery "SELECT COUNT(*) FROM customers" 'customers count'
Write-Drill "  customers: $custCount row(s)"

$activeUsers = Invoke-DrillQuery "SELECT COUNT(*) FROM users WHERE is_active = true" 'active users'
Write-Drill "  active users: $activeUsers"

$coreTables = @('users', 'customers', 'products', 'quotations', 'sales_orders',
                'inventory_items', 'processed_operations', 'audit_logs')
foreach ($tbl in $coreTables) {
    $count = Invoke-DrillQuery "SELECT COUNT(*) FROM $tbl" "table $tbl"
    Write-Drill "  ${tbl}: $count row(s)"
}

# ── 8. Tear down drill container ──────────────────────────────────────────────
Write-Drill 'Tearing down drill container...'
Remove-DrillContainerIfExists -ContainerName $drillContainer
$drillStarted = $false

# ── 9. Report ─────────────────────────────────────────────────────────────────
$duration = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
Write-Drill "Backup file : $($latestBackup.FullName)"
Write-Drill "Duration    : ${duration}s"
Write-Host '[drill] PASS' -ForegroundColor Green
