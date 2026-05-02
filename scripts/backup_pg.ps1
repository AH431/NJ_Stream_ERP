#Requires -Version 5.1
<#
.SYNOPSIS
    NJ Stream ERP — PostgreSQL backup (Docker + GPG symmetric encryption)
.DESCRIPTION
    Reads credentials from POSTGRES_USER/POSTGRES_DB/POSTGRES_PASSWORD (preferred)
    or DATABASE_URL (fallback). Runs pg_dump inside the Docker container, copies
    the dump to a host temp file, then GPG-encrypts it into BACKUP_DIR.

    Output: BACKUP_DIR\<yyyyMMdd_HHmmss>.pgdump.gpg

    Prerequisites:
      - Docker Desktop running with the PostgreSQL container active
      - Gpg4win (GnuPG 2.1+) installed and 'gpg' in PATH
      - Environment variables set (see DESCRIPTION)
.EXAMPLE
    $env:POSTGRES_USER     = 'postgres'
    $env:POSTGRES_DB       = 'nj_erp'
    $env:POSTGRES_PASSWORD = 'strong-password-here'
    $env:BACKUP_PASSPHRASE = 'at-least-twenty-characters'
    $env:BACKUP_DIR        = 'C:\Backups\NJ_ERP'
    .\scripts\backup_pg.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Helper ───────────────────────────────────────────────────────────────────
function Invoke-Step {
    param([string]$Label, [scriptblock]$Action)
    Write-Host "[backup] $Label"
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "Step failed: $Label (exit code $LASTEXITCODE)"
    }
}

# ─── 1. Resolve credentials ───────────────────────────────────────────────────
if ($env:POSTGRES_USER -and $env:POSTGRES_DB -and $env:POSTGRES_PASSWORD) {
    $DB_USER = $env:POSTGRES_USER
    $DB_NAME = $env:POSTGRES_DB
    $DB_PASS = $env:POSTGRES_PASSWORD
} elseif ($env:DATABASE_URL) {
    try {
        $uri     = [System.Uri]::new($env:DATABASE_URL)
        $parts   = $uri.UserInfo.Split(':', 2)
        $DB_USER = [System.Uri]::UnescapeDataString($parts[0])
        $DB_PASS = [System.Uri]::UnescapeDataString($parts[1])
        $DB_NAME = $uri.AbsolutePath.TrimStart('/')
    } catch {
        Write-Error "Failed to parse DATABASE_URL: $_"
        exit 1
    }
} else {
    Write-Error "Set POSTGRES_USER + POSTGRES_DB + POSTGRES_PASSWORD, or DATABASE_URL."
    exit 1
}

# ─── 2. Validate remaining required vars ──────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($env:BACKUP_PASSPHRASE)) {
    Write-Error "BACKUP_PASSPHRASE is not set."
    exit 1
}
if ($env:BACKUP_PASSPHRASE.Length -lt 20) {
    Write-Error "BACKUP_PASSPHRASE must be at least 20 characters."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($env:BACKUP_DIR)) {
    Write-Error "BACKUP_DIR is not set."
    exit 1
}

$containerName = if ($env:POSTGRES_CONTAINER) { $env:POSTGRES_CONTAINER } else { 'nj-erp-postgres' }

# ─── 3. Verify container is running ───────────────────────────────────────────
$containerRunning = docker inspect --format '{{.State.Running}}' $containerName 2>&1
if ($LASTEXITCODE -ne 0 -or $containerRunning -ne 'true') {
    Write-Error "Container '$containerName' is not running. Start it with: docker compose up -d"
    exit 1
}
Write-Host "[backup] Container '$containerName' is running."

# ─── 4. Build paths ───────────────────────────────────────────────────────────
$timestamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
$dumpFileName   = "${timestamp}.pgdump"
$gpgFileName    = "${dumpFileName}.gpg"
$containerTmp   = "/tmp/${dumpFileName}"
$hostTmpPath    = Join-Path $env:TEMP $dumpFileName
$finalPath      = Join-Path $env:BACKUP_DIR $gpgFileName

if (-not (Test-Path $env:BACKUP_DIR)) {
    New-Item -ItemType Directory -Path $env:BACKUP_DIR -Force | Out-Null
    Write-Host "[backup] Created BACKUP_DIR: $($env:BACKUP_DIR)"
}

Write-Host "[backup] DB=$DB_NAME  user=$DB_USER  output=$finalPath"

# ─── 5. Execute backup ────────────────────────────────────────────────────────
try {
    Invoke-Step "pg_dump inside container → $containerTmp" {
        docker exec `
            -e "PGPASSWORD=$DB_PASS" `
            $containerName `
            pg_dump -U $DB_USER -d $DB_NAME -Fc -f $containerTmp
    }

    Invoke-Step "docker cp → $hostTmpPath" {
        docker cp "${containerName}:${containerTmp}" $hostTmpPath
    }

    Invoke-Step "GPG encrypt → $gpgFileName" {
        gpg --batch --yes `
            --pinentry-mode loopback `
            --symmetric `
            --cipher-algo AES256 `
            --passphrase $env:BACKUP_PASSPHRASE `
            --output $finalPath `
            $hostTmpPath
    }

    $sizeMB = [math]::Round((Get-Item $finalPath).Length / 1MB, 2)
    Write-Host "[backup] SUCCESS: $finalPath ($sizeMB MB)"

} catch {
    Write-Error "[backup] FAILED: $($_.Exception.Message)"
    exit 1
} finally {
    if (Test-Path $hostTmpPath) {
        Remove-Item $hostTmpPath -Force -ErrorAction SilentlyContinue
    }
    # Direct rm — no bash needed in Alpine
    docker exec $containerName rm -f $containerTmp 2>$null
}
