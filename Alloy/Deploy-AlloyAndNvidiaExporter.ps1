#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deploys Grafana Alloy and nvidia_gpu_exporter on Windows.
    Designed for unattended execution via BigFix.

.DESCRIPTION
    - Downloads and silently installs Grafana Alloy (v1.14.1)
    - Downloads nvidia_gpu_exporter (v1.4.1), installs as a Windows service via WinSW
    - Deploys a templated Alloy config (config.alloy)
    - Opens firewall ports for the Alloy UI (12345) and GPU exporter (9835)
    - Starts both services

    ARCHITECTURE:
    - Alloy scrapes GPU + Windows metrics locally, then pushes via remote-write
      to Prometheus through an nginx reverse proxy (TLS + basic auth).
    - Alloy ships Windows Event Logs to Loki through the same nginx proxy layer.
    - Prometheus stays bound to 127.0.0.1 — nginx handles all external ingress.

.NOTES
    PREREQUISITES:
    - Windows 10/Server 2016+ (amd64)
    - NVIDIA drivers installed (nvidia-smi.exe must be in PATH or standard location)
    - Network access to GitHub releases (or pre-stage binaries on a BigFix relay)
    - nginx reverse proxy configured for Prometheus remote-write and Loki push

    SERVICE WRAPPER:
    - Uses WinSW v2.12.0 (MIT license, actively maintained) instead of NSSM
    - See: https://github.com/winsw/winsw
#>

# ============================================================================
# CONFIGURATION - UPDATE THESE FOR YOUR ENVIRONMENT
# ============================================================================

# Alloy
$AlloyVersion       = "1.14.1"
$AlloyInstallerUrl  = "https://github.com/grafana/alloy/releases/download/v${AlloyVersion}/alloy-installer-windows-amd64.exe"
$AlloyInstallDir    = "$env:ProgramFiles\GrafanaLabs\Alloy"
$AlloyConfigPath    = "$env:ProgramFiles\GrafanaLabs\Alloy\config.alloy"
$AlloyDataDir       = "$env:ProgramData\GrafanaLabs\Alloy\data"

# nvidia_gpu_exporter
$GpuExporterVersion = "1.4.1"
$GpuExporterUrl     = "https://github.com/utkuozdemir/nvidia_gpu_exporter/releases/download/v${GpuExporterVersion}/nvidia_gpu_exporter_${GpuExporterVersion}_windows_x86_64.zip"
$GpuExporterDir     = "$env:ProgramFiles\nvidia_gpu_exporter"
$GpuExporterPort    = 9835
$GpuServiceName     = "nvidia_gpu_exporter"

# WinSW (service wrapper) - v2.12.0 stable, single exe, MIT license
$WinSWVersion       = "2.12.0"
$WinSWUrl           = "https://github.com/winsw/winsw/releases/download/v${WinSWVersion}/WinSW-x64.exe"

# ---------------------------------------------------------------------------
# TELEMETRY ENDPOINTS (nginx reverse proxy)
# Prometheus stays on 127.0.0.1:9090 — nginx proxies inbound writes to it.
# Update these to match your nginx vhost configuration.
# ---------------------------------------------------------------------------
$PrometheusEndpoint  = "https://prometheus-write.yourdomain.com/api/v1/write"
$LokiEndpoint        = "https://loki.yourdomain.com/loki/api/v1/push"

# Basic auth credentials for the nginx proxy layer.
# These should match the htpasswd file configured in your nginx vhost.
$PrometheusAuthUser  = "alloy"
$PrometheusAuthPass  = "CHANGE_ME_PROMETHEUS"
$LokiAuthUser        = "alloy"
$LokiAuthPass        = "CHANGE_ME_LOKI"

# Alloy UI listen address (127.0.0.1 = local only, no external exposure)
$AlloyUIListen       = "127.0.0.1:12345"

# ============================================================================
# LOGGING
# ============================================================================
$LogFile = "$env:ProgramData\GrafanaLabs\deploy-alloy.log"
New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    Add-Content -Path $LogFile -Value $entry
    Write-Host $entry
}

# ============================================================================
# HELPER: Download file with retry
# ============================================================================
function Get-FileWithRetry {
    param([string]$Url, [string]$OutFile, [int]$MaxRetries = 3)
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-Log "Downloading $Url (attempt $i/$MaxRetries)"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($Url, $OutFile)
            Write-Log "Download complete: $OutFile"
            return $true
        } catch {
            Write-Log "Download failed: $_" "WARN"
            Start-Sleep -Seconds (5 * $i)
        }
    }
    Write-Log "All download attempts failed for $Url" "ERROR"
    return $false
}

# ============================================================================
# STEP 1: INSTALL GRAFANA ALLOY (silent)
# ============================================================================
Write-Log "===== STEP 1: Grafana Alloy ====="

$tempDir = Join-Path $env:TEMP "alloy-deploy-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$alloyInstaller = Join-Path $tempDir "alloy-installer.exe"

# Check if Alloy is already installed at the expected version
$alloyBin = Join-Path $AlloyInstallDir "alloy-windows-amd64.exe"
$alreadyInstalled = $false
if (Test-Path $alloyBin) {
    try {
        $verOutput = & $alloyBin --version 2>&1 | Out-String
        if ($verOutput -match $AlloyVersion) {
            Write-Log "Alloy v${AlloyVersion} already installed, skipping download."
            $alreadyInstalled = $true
        }
    } catch {
        Write-Log "Could not determine existing Alloy version, proceeding with install."
    }
}

if (-not $alreadyInstalled) {
    if (-not (Get-FileWithRetry -Url $AlloyInstallerUrl -OutFile $alloyInstaller)) {
        Write-Log "FATAL: Cannot download Alloy installer." "ERROR"
        exit 1
    }

    Write-Log "Running Alloy silent installer..."
    $installArgs = @(
        "/S"
        "/D=$AlloyInstallDir"
        "/CONFIG=`"$AlloyConfigPath`""
        "/DISABLEREPORTING=yes"
    )
    $proc = Start-Process -FilePath $alloyInstaller -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Write-Log "Alloy installer exited with code $($proc.ExitCode)" "ERROR"
        exit 1
    }
    Write-Log "Alloy installed successfully."
}

# ============================================================================
# STEP 2: INSTALL NVIDIA GPU EXPORTER + WinSW
# ============================================================================
Write-Log "===== STEP 2: nvidia_gpu_exporter ====="

# Check nvidia-smi is available
$nvidiaSmi = $null
$nvidiaSmiPaths = @(
    "nvidia-smi.exe",
    "C:\Windows\System32\nvidia-smi.exe",
    "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
)
foreach ($p in $nvidiaSmiPaths) {
    if (Get-Command $p -ErrorAction SilentlyContinue) {
        $nvidiaSmi = $p
        break
    }
    if (Test-Path $p) {
        $nvidiaSmi = $p
        break
    }
}

if (-not $nvidiaSmi) {
    Write-Log "WARNING: nvidia-smi.exe not found. GPU exporter will be installed but may not function until NVIDIA drivers are present." "WARN"
} else {
    Write-Log "Found nvidia-smi at: $nvidiaSmi"
}

# Stop and uninstall existing service if present (for upgrades)
$winswExe = Join-Path $GpuExporterDir "${GpuServiceName}.exe"
$existingSvc = Get-Service -Name $GpuServiceName -ErrorAction SilentlyContinue
if ($existingSvc) {
    Write-Log "Removing existing $GpuServiceName service for upgrade..."
    if ($existingSvc.Status -eq "Running") {
        if (Test-Path $winswExe) {
            & $winswExe stop 2>&1 | Out-Null
        } else {
            Stop-Service -Name $GpuServiceName -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 3
    }
    if (Test-Path $winswExe) {
        & $winswExe uninstall 2>&1 | Out-Null
    } else {
        sc.exe delete $GpuServiceName 2>&1 | Out-Null
    }
    Start-Sleep -Seconds 2
    Write-Log "Existing service removed."
}

# Download and extract GPU exporter
New-Item -ItemType Directory -Path $GpuExporterDir -Force | Out-Null

$gpuZip = Join-Path $tempDir "nvidia_gpu_exporter.zip"
if (-not (Get-FileWithRetry -Url $GpuExporterUrl -OutFile $gpuZip)) {
    Write-Log "FATAL: Cannot download nvidia_gpu_exporter." "ERROR"
    exit 1
}

Write-Log "Extracting nvidia_gpu_exporter..."
Expand-Archive -Path $gpuZip -DestinationPath $GpuExporterDir -Force
Write-Log "Extracted to $GpuExporterDir"

# Find the exporter binary
$gpuExporterExe = Get-ChildItem -Path $GpuExporterDir -Recurse -Filter "nvidia_gpu_exporter.exe" |
    Select-Object -First 1 -ExpandProperty FullName

if (-not $gpuExporterExe) {
    Write-Log "FATAL: nvidia_gpu_exporter.exe not found after extraction." "ERROR"
    exit 1
}

# Download WinSW and rename to match service name
if (-not (Get-FileWithRetry -Url $WinSWUrl -OutFile $winswExe)) {
    Write-Log "FATAL: Cannot download WinSW." "ERROR"
    exit 1
}
Write-Log "WinSW v${WinSWVersion} downloaded to $winswExe"

# Create WinSW XML config
$winswXmlPath = Join-Path $GpuExporterDir "${GpuServiceName}.xml"
$logDir = Join-Path $GpuExporterDir "logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$winswXml = @"
<service>
  <id>${GpuServiceName}</id>
  <n>NVIDIA GPU Prometheus Exporter</n>
  <description>Exports NVIDIA GPU metrics via nvidia-smi for Prometheus scraping (port ${GpuExporterPort})</description>
  <executable>${gpuExporterExe}</executable>
  <arguments>--web.listen-address=:${GpuExporterPort}</arguments>
  <startmode>Automatic</startmode>

  <!-- Logging: roll by size, keep 3 files at 5 MB each -->
  <logpath>${logDir}</logpath>
  <log mode="roll-by-size">
    <sizeThreshold>5120</sizeThreshold>
    <keepFiles>3</keepFiles>
  </log>

  <!-- Restart policy on failure -->
  <onfailure action="restart" delay="10 sec" />
  <onfailure action="restart" delay="30 sec" />
  <onfailure action="none" />
  <resetfailure>1 hour</resetfailure>

  <!-- Graceful shutdown timeout -->
  <stoptimeout>15 sec</stoptimeout>
</service>
"@

Set-Content -Path $winswXmlPath -Value $winswXml -Encoding UTF8
Write-Log "WinSW service config written to $winswXmlPath"

# Install via WinSW
Write-Log "Installing $GpuServiceName as a Windows service via WinSW..."
$installOutput = & $winswExe install 2>&1 | Out-String
Write-Log $installOutput
Write-Log "$GpuServiceName service installed."

# ============================================================================
# STEP 3: DEPLOY ALLOY CONFIG
# ============================================================================
Write-Log "===== STEP 3: Alloy configuration ====="

$hostname = $env:COMPUTERNAME

$alloyConfig = @"
// ============================================================================
// Grafana Alloy configuration - Windows deployment
// Generated by BigFix deployment script
// Host: ${hostname}
//
// ARCHITECTURE:
//   Alloy (this agent) scrapes metrics locally, then pushes outbound to
//   Prometheus and Loki via nginx reverse proxy. No inbound scrape ports
//   are required from the central Prometheus instance.
//
//   [nvidia_gpu_exporter :9835] --scrape--> [Alloy] --remote-write/HTTPS-->
//     [nginx proxy] --> [Prometheus 127.0.0.1:9090]
//
//   [Windows Event Logs] --collect--> [Alloy] --push/HTTPS-->
//     [nginx proxy] --> [Loki]
// ============================================================================

// ---------------------------------------------------------------------------
// PROMETHEUS SCRAPE: nvidia_gpu_exporter (localhost only)
// ---------------------------------------------------------------------------
prometheus.scrape "nvidia_gpu" {
    targets = [{
        "__address__" = "localhost:${GpuExporterPort}",
    }]

    forward_to      = [prometheus.remote_write.default.receiver]
    scrape_interval = "30s"
    job_name        = "nvidia_gpu"
}

// ---------------------------------------------------------------------------
// PROMETHEUS SCRAPE: Windows Exporter (integrated into Alloy)
// ---------------------------------------------------------------------------
prometheus.exporter.windows "default" {
    enabled_collectors = [
        "cpu",
        "cs",
        "logical_disk",
        "memory",
        "net",
        "os",
        "service",
        "system",
        "time",
    ]
}

prometheus.scrape "windows_exporter" {
    targets    = prometheus.exporter.windows.default.targets
    forward_to = [prometheus.remote_write.default.receiver]

    scrape_interval = "60s"
    job_name        = "windows_exporter"
}

// ---------------------------------------------------------------------------
// PROMETHEUS REMOTE WRITE (outbound push through nginx proxy)
// ---------------------------------------------------------------------------
prometheus.remote_write "default" {
    endpoint {
        url = "${PrometheusEndpoint}"

        basic_auth {
            username = "${PrometheusAuthUser}"
            password = "${PrometheusAuthPass}"
        }

        tls_config {
            // If using a private CA or self-signed cert on nginx, specify:
            // ca_file = "C:\\ProgramData\\GrafanaLabs\\Alloy\\certs\\ca.pem"

            // Set to true ONLY for testing with self-signed certs:
            // insecure_skip_verify = true
        }

        queue_config {
            capacity             = 10000
            max_shards           = 5
            max_samples_per_send = 2000
        }
    }

    external_labels = {
        "hostname" = "${hostname}",
    }
}

// ---------------------------------------------------------------------------
// WINDOWS EVENT LOG -> LOKI (outbound push through nginx proxy)
// ---------------------------------------------------------------------------
loki.source.windowsevent "application" {
    eventlog_name = "Application"
    forward_to    = [loki.process.windows_events.receiver]
}

loki.source.windowsevent "system" {
    eventlog_name = "System"
    forward_to    = [loki.process.windows_events.receiver]
}

loki.process "windows_events" {
    stage.labels {
        values = {
            "source"   = "source",
            "level"    = "level",
            "event_id" = "event_id",
        }
    }

    stage.static_labels {
        values = {
            "hostname" = "${hostname}",
            "job"      = "windows_eventlog",
            "os"       = "windows",
        }
    }

    forward_to = [loki.write.default.receiver]
}

loki.write "default" {
    endpoint {
        url = "${LokiEndpoint}"

        basic_auth {
            username = "${LokiAuthUser}"
            password = "${LokiAuthPass}"
        }

        tls_config {
            // If using a private CA or self-signed cert on nginx, specify:
            // ca_file = "C:\\ProgramData\\GrafanaLabs\\Alloy\\certs\\ca.pem"

            // Set to true ONLY for testing with self-signed certs:
            // insecure_skip_verify = true
        }
    }
}
"@

Write-Log "Writing Alloy config to $AlloyConfigPath"
New-Item -ItemType Directory -Path (Split-Path $AlloyConfigPath) -Force | Out-Null
Set-Content -Path $AlloyConfigPath -Value $alloyConfig -Encoding UTF8
Write-Log "Config written."

# ============================================================================
# STEP 4: FIREWALL RULES
# ============================================================================
Write-Log "===== STEP 4: Firewall rules ====="

# Note: Only the Alloy UI and GPU exporter need local listening ports.
# The GPU exporter only needs to be reachable from localhost (Alloy scrapes it).
# We still create the rule in case you want to test from another host, scoped
# to Domain/Private profiles only.

$fwRules = @(
    @{ Name = "Grafana Alloy UI";    Port = 12345;            Description = "Grafana Alloy HTTP UI (local diagnostics)" },
    @{ Name = "NVIDIA GPU Exporter"; Port = $GpuExporterPort; Description = "nvidia_gpu_exporter Prometheus metrics (scraped locally by Alloy)" }
)

foreach ($rule in $fwRules) {
    $existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Log "Firewall rule '$($rule.Name)' already exists, skipping."
    } else {
        New-NetFirewallRule `
            -DisplayName $rule.Name `
            -Description $rule.Description `
            -Direction Inbound `
            -Action Allow `
            -Protocol TCP `
            -LocalPort $rule.Port `
            -Profile Domain,Private | Out-Null
        Write-Log "Created firewall rule: $($rule.Name) (TCP/$($rule.Port))"
    }
}

# ============================================================================
# STEP 5: START SERVICES
# ============================================================================
Write-Log "===== STEP 5: Starting services ====="

# Start GPU exporter
Write-Log "Starting $GpuServiceName service..."
& $winswExe start 2>&1 | Out-Null
Start-Sleep -Seconds 3

$gpuSvc = Get-Service -Name $GpuServiceName -ErrorAction SilentlyContinue
if ($gpuSvc -and $gpuSvc.Status -eq "Running") {
    Write-Log "$GpuServiceName is running."
} else {
    Write-Log "$GpuServiceName may not have started. Check logs at $logDir" "WARN"
}

# Restart Alloy to pick up new config
Write-Log "Restarting Alloy service..."
Restart-Service -Name "Alloy" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

$alloySvc = Get-Service -Name "Alloy" -ErrorAction SilentlyContinue
if ($alloySvc -and $alloySvc.Status -eq "Running") {
    Write-Log "Alloy is running."
} else {
    Write-Log "Alloy may not have started. Check Windows Event Viewer > Application > Grafana Alloy" "WARN"
}

# ============================================================================
# CLEANUP
# ============================================================================
Write-Log "Cleaning up temp directory..."
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Log "===== Deployment complete ====="
Write-Log "Alloy UI (local):  http://localhost:12345"
Write-Log "GPU metrics:       http://localhost:${GpuExporterPort}/metrics"
Write-Log "Prom remote-write: ${PrometheusEndpoint}"
Write-Log "Loki push:         ${LokiEndpoint}"
Write-Log "Log file:          $LogFile"

exit 0
