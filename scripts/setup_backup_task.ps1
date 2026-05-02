#Requires -Version 5.1
<#
.SYNOPSIS
    Register a Windows Scheduled Task for daily NJ ERP PostgreSQL backup.

.DESCRIPTION
    Creates a local env bootstrap file with instructions, then registers the
    NJ_ERP_Daily_Backup task to run backup_pg.ps1 daily at 02:00.
    Run this once per host. Requires Administrator privileges.

.EXAMPLE
    .\scripts\setup_backup_task.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot    = Split-Path -Parent $PSScriptRoot
$taskName    = 'NJ_ERP_Daily_Backup'
$scriptPath  = Join-Path $repoRoot 'scripts\backup_pg.ps1'
$envBootstrap = Join-Path $repoRoot 'scripts\backup_env_bootstrap.ps1'

# ── 1. Write env bootstrap template ───────────────────────────────────────────
$bootstrapContent = @'
# NJ ERP Daily Backup — environment variables
# Edit this file with the real values, then re-run setup_backup_task.ps1
# DO NOT commit this file to git — it is listed in .gitignore

$env:POSTGRES_USER     = 'postgres'
$env:POSTGRES_DB       = 'nj_erp'
$env:POSTGRES_PASSWORD = 'CHANGE_ME'          # same password as docker-compose
$env:BACKUP_PASSPHRASE = 'CHANGE_ME_AT_LEAST_20_CHARS'
$env:BACKUP_DIR        = 'C:\Backups\NJ_ERP'
'@

Set-Content -Path $envBootstrap -Value $bootstrapContent -Encoding UTF8
Write-Host "[setup] Wrote env bootstrap template: $envBootstrap"
Write-Host '[setup] Fill in the real credentials before the task runs.'

# ── 2. Build the task action ───────────────────────────────────────────────────
$psExe  = (Get-Command powershell.exe).Source
$taskCmd = "-NonInteractive -ExecutionPolicy Bypass -Command `". '$envBootstrap'; & '$scriptPath'`""

$action  = New-ScheduledTaskAction -Execute $psExe -Argument $taskCmd
$trigger = New-ScheduledTaskTrigger -Daily -At '02:00'

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
    -MultipleInstances IgnoreNew

# ── 3. Register (or update) the task ──────────────────────────────────────────
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($existing) {
    Set-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings | Out-Null
    Write-Host "[setup] Updated existing task: $taskName"
} else {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action   $action `
        -Trigger  $trigger `
        -Settings $settings `
        -RunLevel Highest `
        -Description 'Daily encrypted PostgreSQL backup for NJ Stream ERP' | Out-Null
    Write-Host "[setup] Registered new task: $taskName"
}

Write-Host "[setup] Schedule: daily at 02:00, StartWhenAvailable, 30-minute limit"
Write-Host "[setup] DONE — verify with: Get-ScheduledTask -TaskName '$taskName'"
