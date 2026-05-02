#Requires -Version 5.1
<#
.SYNOPSIS
    Validates the production docker compose stack locally.

.DESCRIPTION
    Creates an ephemeral .env.test-prod file with safe local values, then:
      1. Builds docker-compose.prod.yml
      2. Starts postgres and waits for health
      3. Runs the migrate profile
      4. Starts backend
      5. Polls /health and verifies headers
      6. Tears everything down unless -KeepRunning is set
#>

param(
    [switch]$KeepRunning
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $repoRoot '.env.test-prod'
$composeArgs = @('-f', 'docker-compose.prod.yml', '--env-file', '.env.test-prod')
$healthUrl = 'http://127.0.0.1:3000/health'
$deadline = (Get-Date).AddSeconds(120)
$keepEnvFile = $false
$lastHealthError = $null

function Write-Step {
    param([string]$Message)
    Write-Host "[smoke] $Message"
}

function Invoke-Compose {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & docker compose @composeArgs @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed: $($Arguments -join ' ')"
    }
}

function Wait-ForContainerHealth {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,
        [int]$TimeoutSeconds = 120
    )

    $containerDeadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $status = docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' $ContainerName 2>$null
        if ($LASTEXITCODE -eq 0 -and $status -eq 'healthy') {
            Write-Step "$ContainerName is healthy."
            return
        }

        if ($LASTEXITCODE -eq 0 -and $status -eq 'running') {
            Write-Step "$ContainerName is running without a health status yet."
        }

        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $containerDeadline)

    throw "Timed out waiting for container health: $ContainerName"
}

function Assert-HealthEndpoint {
    do {
        try {
            $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -eq 200 -and $response.Content -match '"status"\s*:\s*"ok"') {
                $headers = $response.Headers
                if (-not $headers['x-content-type-options']) {
                    throw 'Missing x-content-type-options header.'
                }
                if (-not $headers['x-frame-options']) {
                    throw 'Missing x-frame-options header.'
                }

                Write-Step 'Health endpoint is ready and security headers are present.'
                return
            }

            $lastHealthError = "Unexpected response: $($response.StatusCode) $($response.Content)"
        } catch {
            $lastHealthError = $_.Exception.Message
        }

        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for health endpoint. Last error: $lastHealthError"
}

$envContent = @"
POSTGRES_DB=nj_erp_prod_test
POSTGRES_USER=postgres
POSTGRES_PASSWORD=prod-test-password
DATABASE_URL=postgresql://postgres:prod-test-password@postgres:5432/nj_erp_prod_test
JWT_SECRET=prod-test-jwt-secret-for-smoke
JWT_ACCESS_EXPIRES_IN=3600
JWT_REFRESH_EXPIRES_IN=2592000
COMPANY_NAME=NJ Stream
PORT=3000
BACKEND_BIND_ADDRESS=127.0.0.1
"@

Push-Location $repoRoot
try {
    Set-Content -Path $envFile -Value $envContent -Encoding ASCII
    $keepEnvFile = $true
    Write-Step 'Wrote .env.test-prod.'

    Invoke-Compose -Arguments @('build')

    Write-Step 'Starting postgres.'
    Invoke-Compose -Arguments @('up', '-d', 'postgres')
    Wait-ForContainerHealth -ContainerName 'nj-erp-postgres'

    Write-Step 'Running migrate profile.'
    Invoke-Compose -Arguments @('--profile', 'migrate', 'run', '--rm', 'migrate')

    Write-Step 'Starting backend.'
    Invoke-Compose -Arguments @('up', '-d', 'backend')
    Assert-HealthEndpoint

    Write-Host '[smoke] PASS'
} catch {
    Write-Error "[smoke] FAIL: $($_.Exception.Message)"
    exit 1
} finally {
    if (-not $KeepRunning) {
        Write-Step 'Tearing down containers and volumes.'
        & docker compose @composeArgs down -v --remove-orphans
    } else {
        Write-Step 'Keeping containers running for manual inspection.'
    }

    if ($keepEnvFile -and (Test-Path $envFile)) {
        Remove-Item -LiteralPath $envFile -Force -ErrorAction SilentlyContinue
    }

    Pop-Location
}
