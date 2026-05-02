#Requires -Version 5.1
<#
.SYNOPSIS
    NJ Stream ERP — PostgreSQL restore (GPG decrypt + Docker pg_restore)
.DESCRIPTION
    Decrypts a <timestamp>.pgdump.gpg file, copies it into the Docker container,
    and restores it via pg_restore.

    Default mode: pg_restore -c (drops and recreates objects inside the existing DB).
    Use -DropAndRecreate for a full DROP DATABASE / CREATE DATABASE before restore,
    which guarantees a clean state when the default mode hits FK constraint errors.

    Requires explicit confirmation (type YES) unless -Force is passed.
.PARAMETER BackupFile
    Full path to the .pgdump.gpg file to restore. Required.
.PARAMETER DropAndRecreate
    Drop and recreate the database before restoring. More destructive but guarantees
    a clean slate. Use when pg_restore -c fails due to schema drift or FK conflicts.
.PARAMETER Force
    Skip the interactive confirmation prompt. Intended for CI/automation only.
.EXAMPLE
    .\scripts\restore_pg.ps1 -BackupFile 'C:\Backups\NJ_ERP\20260430_120000.pgdump.gpg'
.EXAMPLE
    .\scripts\restore_pg.ps1 -BackupFile '...\20260430_120000.pgdump.gpg' -DropAndRecreate -Force
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$BackupFile,

    [switch]$DropAndRecreate,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Helper ───────────────────────────────────────────────────────────────────
function Invoke-Step {
    param([string]$Label, [scriptblock]$Action)
    Write-Host "[restore] $Label"
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "Step failed: $Label (exit code $LASTEXITCODE)"
    }
}

# ─── 1. Validate backup file ──────────────────────────────────────────────────
if (-not (Test-Path $BackupFile)) {
    Write-Error "Backup file not found: $BackupFile"
    exit 1
}
if ($BackupFile -notmatch '\.pgdump\.gpg$') {
    Write-Error "Backup file must end in .pgdump.gpg — got: $BackupFile"
    exit 1
}

# ─── 2. Resolve credentials ───────────────────────────────────────────────────
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

if ([string]::IsNullOrWhiteSpace($env:BACKUP_PASSPHRASE)) {
    Write-Error "BACKUP_PASSPHRASE is not set."
    exit 1
}

$containerName = if ($env:POSTGRES_CONTAINER) { $env:POSTGRES_CONTAINER } else { 'nj-erp-postgres' }

# ─── 3. Verify container is running ───────────────────────────────────────────
$containerRunning = docker inspect --format '{{.State.Running}}' $containerName 2>&1
if ($LASTEXITCODE -ne 0 -or $containerRunning -ne 'true') {
    Write-Error "Container '$containerName' is not running. Start it with: docker compose up -d"
    exit 1
}

# ─── 4. Safety confirmation ───────────────────────────────────────────────────
$mode = if ($DropAndRecreate) { 'DROP + RECREATE (destructive)' } else { 'pg_restore -c (clean in place)' }
Write-Warning '============================================================'
Write-Warning " RESTORE WILL OVERWRITE DATABASE: '$DB_NAME'"
Write-Warning " Container : $containerName"
Write-Warning " Backup    : $BackupFile"
Write-Warning " Mode      : $mode"
Write-Warning '============================================================'

if (-not $Force) {
    $confirm = Read-Host 'Type YES to continue'
    if ($confirm -ne 'YES') {
        Write-Host '[restore] Cancelled.'
        exit 0
    }
}

# ─── 5. Build paths ───────────────────────────────────────────────────────────
$gpgFileName  = Split-Path $BackupFile -Leaf          # 20260430_120000.pgdump.gpg
$dumpFileName = $gpgFileName -replace '\.gpg$', ''   # 20260430_120000.pgdump
$hostTmpPath  = Join-Path $env:TEMP $dumpFileName
$containerTmp = "/tmp/$dumpFileName"

Write-Host "[restore] Restoring '$DB_NAME' from: $BackupFile"

# ─── 6. Execute restore ───────────────────────────────────────────────────────
try {
    Invoke-Step "GPG decrypt → $hostTmpPath" {
        gpg --batch --yes `
            --pinentry-mode loopback `
            --passphrase $env:BACKUP_PASSPHRASE `
            --output $hostTmpPath `
            --decrypt $BackupFile
    }

    Invoke-Step "docker cp → container:$containerTmp" {
        docker cp $hostTmpPath "${containerName}:${containerTmp}"
    }

    if ($DropAndRecreate) {
        # Terminate active connections so DROP DATABASE can proceed
        Write-Host '[restore] Terminating connections to database...'
        docker exec `
            -e "PGPASSWORD=$DB_PASS" `
            $containerName `
            psql -U $DB_USER -d postgres `
            -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DB_NAME' AND pid <> pg_backend_pid();"
        # $LASTEXITCODE intentionally not checked — zero rows is fine

        Invoke-Step "DROP DATABASE $DB_NAME" {
            docker exec `
                -e "PGPASSWORD=$DB_PASS" `
                $containerName `
                psql -U $DB_USER -d postgres `
                -c "DROP DATABASE IF EXISTS $DB_NAME;"
        }

        Invoke-Step "CREATE DATABASE $DB_NAME" {
            docker exec `
                -e "PGPASSWORD=$DB_PASS" `
                $containerName `
                psql -U $DB_USER -d postgres `
                -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
        }

        # Fresh DB — no -c flag (nothing to drop)
        Invoke-Step "pg_restore into fresh database" {
            docker exec `
                -e "PGPASSWORD=$DB_PASS" `
                $containerName `
                pg_restore -U $DB_USER -d $DB_NAME -Fc `
                    -x --no-owner --exit-on-error `
                    $containerTmp
        }
    } else {
        # Default: drop and recreate objects within the existing database
        Invoke-Step "pg_restore -c (clean in place)" {
            docker exec `
                -e "PGPASSWORD=$DB_PASS" `
                $containerName `
                pg_restore -U $DB_USER -d $DB_NAME -Fc `
                    -c -x --no-owner --exit-on-error `
                    $containerTmp
        }
    }

    Write-Host "[restore] SUCCESS: '$DB_NAME' restored from $BackupFile"
    Write-Host '[restore] Next step (local):  cd packages\backend && npm run db:migrate'
    Write-Host '[restore] Next step (prod):   docker compose -f docker-compose.prod.yml --env-file .env.production run --rm migrate'

} catch {
    Write-Error "[restore] FAILED: $($_.Exception.Message)"
    exit 1
} finally {
    if (Test-Path $hostTmpPath) {
        Remove-Item $hostTmpPath -Force -ErrorAction SilentlyContinue
    }
    # Direct rm — no bash needed in Alpine
    docker exec $containerName rm -f $containerTmp 2>$null
}
