#Requires -Version 5.1
<#
.SYNOPSIS
    Guarded DB migration with backup, DB/API change log, and automatic rollback.
.DESCRIPTION
    Runs a PostgreSQL backup, records pre/post table row counts, captures pending
    migration files and API route changes from git, then runs backend db:migrate.

    If migration fails or post-migration row counts drop for existing tables,
    the script restores the pre-migration backup automatically.

    Log output:
      LOG\db\<yyyy-MM-dd>.md

    Prerequisites:
      - Docker Desktop and nj-erp-postgres running
      - GPG available in PATH
      - Existing backup env vars used by scripts\backup_pg.ps1 / restore_pg.ps1
      - DATABASE_URL or POSTGRES_USER + POSTGRES_DB + POSTGRES_PASSWORD
.EXAMPLE
    .\scripts\migrate_with_log.ps1
.EXAMPLE
    .\scripts\migrate_with_log.ps1 -AllowRowCountDrop
#>

param(
    [switch]$AllowRowCountDrop,
    [switch]$SkipBackup,
    [switch]$SkipRollback
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $repoRoot 'packages\backend'
$logDir = Join-Path $repoRoot 'LOG\db'
$logPath = Join-Path $logDir "$(Get-Date -Format 'yyyy-MM-dd').md"
$runId = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupFile = $null

function Write-Step {
    param([string]$Message)
    Write-Host "[migrate-guard] $Message"
}

function Ensure-LogFile {
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    if (-not (Test-Path $logPath)) {
        $date = Get-Date -Format 'yyyy-MM-dd'
        @"
# DB Migration Log - $date

This file is append-only. `scripts\migrate_with_log.ps1` records guarded migration runs here.

"@ | Set-Content -Path $logPath -Encoding UTF8
    }
}

function Append-Log {
    param([string]$Text)
    Add-Content -Path $logPath -Value $Text -Encoding UTF8
}

function Resolve-DbName {
    if ($env:POSTGRES_DB) { return $env:POSTGRES_DB }
    if ($env:DATABASE_URL) {
        $uri = [System.Uri]::new($env:DATABASE_URL)
        return $uri.AbsolutePath.TrimStart('/')
    }
    throw 'Set POSTGRES_DB or DATABASE_URL.'
}

function Resolve-DbUser {
    if ($env:POSTGRES_USER) { return $env:POSTGRES_USER }
    if ($env:DATABASE_URL) {
        $uri = [System.Uri]::new($env:DATABASE_URL)
        return [System.Uri]::UnescapeDataString($uri.UserInfo.Split(':', 2)[0])
    }
    throw 'Set POSTGRES_USER or DATABASE_URL.'
}

function Resolve-DbPassword {
    if ($env:POSTGRES_PASSWORD) { return $env:POSTGRES_PASSWORD }
    if ($env:DATABASE_URL) {
        $uri = [System.Uri]::new($env:DATABASE_URL)
        return [System.Uri]::UnescapeDataString($uri.UserInfo.Split(':', 2)[1])
    }
    throw 'Set POSTGRES_PASSWORD or DATABASE_URL.'
}

function Get-TableCounts {
    $dbName = Resolve-DbName
    $dbUser = Resolve-DbUser
    $dbPass = Resolve-DbPassword
    $containerName = if ($env:POSTGRES_CONTAINER) { $env:POSTGRES_CONTAINER } else { 'nj-erp-postgres' }

    $query = @"
SELECT table_name
FROM information_schema.tables
WHERE table_schema='public'
  AND table_type='BASE TABLE'
ORDER BY table_name;
"@

    $tablesRaw = docker exec -e "PGPASSWORD=$dbPass" $containerName `
        psql -U $dbUser -d $dbName -t -A -c $query
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to list database tables.'
    }

    $counts = [ordered]@{}
    foreach ($table in ($tablesRaw -split "`n")) {
        $name = $table.Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $escapedName = $name.Replace('"', '""')
        $countQuery = "SELECT COUNT(*)::bigint FROM public.""$escapedName"";"
        $countRaw = docker exec -e "PGPASSWORD=$dbPass" $containerName `
            psql -U $dbUser -d $dbName -t -A -c $countQuery
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to count table: $name"
        }
        $counts[$name] = [int64]($countRaw.Trim())
    }
    return $counts
}

function Format-CountsMarkdown {
    param([System.Collections.IDictionary]$Counts)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('| Table | Rows |')
    $lines.Add('|---|---:|')
    foreach ($key in $Counts.Keys) {
        $lines.Add("| `$key` | $($Counts[$key]) |")
    }
    return ($lines -join [Environment]::NewLine)
}

function Get-ChangedApiFiles {
    $files = git -C $repoRoot diff --name-only HEAD -- packages/backend/src/routes packages/backend/src/app.ts 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($files -join ''))) {
        return @('No uncommitted API route changes detected.')
    }
    return $files
}

function Get-MigrationFiles {
    $files = Get-ChildItem -Path (Join-Path $backendDir 'drizzle') -Filter '*.sql' -File |
        Sort-Object Name |
        Select-Object -ExpandProperty Name
    if (-not $files -or $files.Count -eq 0) {
        return @('No migration SQL files found.')
    }
    return $files
}

function Get-LatestBackupFile {
    if ([string]::IsNullOrWhiteSpace($env:BACKUP_DIR)) {
        throw 'BACKUP_DIR is required to locate backup files.'
    }
    $latest = Get-ChildItem -Path $env:BACKUP_DIR -Filter '*.pgdump.gpg' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) {
        throw "No .pgdump.gpg backup found in BACKUP_DIR: $($env:BACKUP_DIR)"
    }
    return $latest.FullName
}

function Invoke-Rollback {
    param([string]$Reason)
    if ($SkipRollback) {
        Append-Log "`n**Rollback skipped**: $Reason`n"
        Write-Step "Rollback skipped: $Reason"
        return
    }
    if ([string]::IsNullOrWhiteSpace($backupFile)) {
        throw "Rollback requested but no backup file is available. Reason: $Reason"
    }

    Append-Log "`n**Rollback started**: $Reason`n"
    Write-Step "Rollback started: $Reason"
    & "$repoRoot\scripts\restore_pg.ps1" -BackupFile $backupFile -DropAndRecreate -Force
    if ($LASTEXITCODE -ne 0) {
        Append-Log "`n**Rollback failed**. Manual restore required from: `$backupFile`n"
        throw 'Rollback restore failed.'
    }
    Append-Log "`n**Rollback completed** from `$backupFile`.`n"
}

function Test-RowLoss {
    param(
        [System.Collections.IDictionary]$Before,
        [System.Collections.IDictionary]$After
    )

    $losses = New-Object System.Collections.Generic.List[string]
    foreach ($table in $Before.Keys) {
        if (-not $After.Contains($table)) {
            $losses.Add("Table removed: $table")
            continue
        }
        if ([int64]$After[$table] -lt [int64]$Before[$table]) {
            $losses.Add("$table rows dropped from $($Before[$table]) to $($After[$table])")
        }
    }
    return $losses
}

Ensure-LogFile

Append-Log @"
## Run $runId

- Started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')
- Operator: $env:USERNAME
- Host: $env:COMPUTERNAME
- Allow row count drop: $AllowRowCountDrop
- Skip backup: $SkipBackup
- Skip rollback: $SkipRollback

### API Changes
$(($apiFiles = Get-ChangedApiFiles) | ForEach-Object { "- `$_" } | Out-String)
### Migration Files
$(($migrationFiles = Get-MigrationFiles) | ForEach-Object { "- `$_" } | Out-String)
"@

try {
    Write-Step 'Collecting pre-migration table counts.'
    $beforeCounts = Get-TableCounts
    Append-Log "### Pre-Migration Row Counts`n$(Format-CountsMarkdown $beforeCounts)`n"

    if (-not $SkipBackup) {
        Write-Step 'Running encrypted PostgreSQL backup.'
        & "$repoRoot\scripts\backup_pg.ps1"
        if ($LASTEXITCODE -ne 0) {
            throw 'backup_pg.ps1 failed.'
        }
        $backupFile = Get-LatestBackupFile
        Append-Log "### Backup`n- File: `$backupFile`n"
    } else {
        $backupFile = Get-LatestBackupFile
        Append-Log "### Backup`n- Skipped new backup. Rollback candidate: `$backupFile`n"
    }

    Write-Step 'Running backend db:migrate.'
    Push-Location $backendDir
    try {
        npm.cmd run db:migrate
        if ($LASTEXITCODE -ne 0) {
            throw 'npm.cmd run db:migrate failed.'
        }
    } finally {
        Pop-Location
    }

    Write-Step 'Collecting post-migration table counts.'
    $afterCounts = Get-TableCounts
    Append-Log "### Post-Migration Row Counts`n$(Format-CountsMarkdown $afterCounts)`n"

    $losses = Test-RowLoss -Before $beforeCounts -After $afterCounts
    if ($losses.Count -gt 0 -and -not $AllowRowCountDrop) {
        Append-Log "### Data Loss Check`n$(($losses | ForEach-Object { "- $_" }) -join [Environment]::NewLine)`n"
        Invoke-Rollback -Reason "Row count loss detected: $($losses -join '; ')"
        throw 'Migration rolled back because row count loss was detected.'
    }

    if ($losses.Count -gt 0) {
        Append-Log "### Data Loss Check`n- Row count dropped but was allowed by -AllowRowCountDrop.`n$(($losses | ForEach-Object { "- $_" }) -join [Environment]::NewLine)`n"
    } else {
        Append-Log "### Data Loss Check`n- PASS: no row count drops for pre-existing tables.`n"
    }

    Append-Log "- Finished at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')`n- Status: PASS`n"
    Write-Step 'Migration guard completed: PASS.'
} catch {
    $message = $_.Exception.Message
    Append-Log "### Failure`n- $message`n"
    if ($message -notmatch 'rolled back' -and -not [string]::IsNullOrWhiteSpace($backupFile)) {
        Invoke-Rollback -Reason $message
    }
    Append-Log "- Finished at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')`n- Status: FAIL`n"
    Write-Error $message
    exit 1
}
