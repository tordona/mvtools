<#
.SYNOPSIS
    Portable, Automated Reproducible Benchmark Harness for PotPlayer + MVTools ARM64.
.DESCRIPTION
    Fully portable benchmark harness with zero hardcoded paths:
    1. Detects system-installed PotPlayer ('C:\Program Files\DAUM\PotPlayer') or local sibling 'PotPlayer'.
    2. Supports automated official PotPlayer ARM64 download and silent installation from Kakao CDN (-AutoInstallPotPlayer).
    3. Audits mvtools2.dll and mvtools2_d3d12.dll version, SHA-256, and PE header linker compile timestamp.
    5. Injects deterministic PotPlayer configuration (D3D11 DXVA, AviSynth profile, subtitler off, audio pitch off, MultipleRunning=0).
    6. Enforces single-instance integrity: verifies and guarantees only one PotPlayer instance runs at any time.
    7. Audits available physical RAM against profile SetMemoryMax requirements (+1024 MB UMA/Player buffer headroom).
    8. Enforces environmental controls (AC power check, High Performance plan, background quiescence).
    9. Verifies overall system CPU and GPU load drops to idle before launching the test.
    10. Integrates optional sibling 'PresentMon.exe' to capture sub-millisecond Average, High, Low, 1% Low FPS, and Dropped Frames.
    11. Runs test, records telemetry (CPU, GPU, RAM, Page Swaps, Instance Count, FPS) to CSV, and generates an audit report.
    12. Restores original configuration, power plan, and network adapters upon exit.
.PARAMETER AutoInstallPotPlayer
    Automatically downloads and silently installs official native PotPlayer ARM64 from Kakao CDN
    if PotPlayer is not detected on the system. Uses active live progress bar and background spinner.
.VERSION
    2.2.0
.DATE
    2026-10-19
.NOTES
    Format: SemVer (MAJOR.MINOR.PATCH)
    Revision History:
    - v2.2.0 (2026-10-19): Added automated official PotPlayer ARM64 acquisition and silent installation
                           with live stream download progress (speed, percent, ETA) and animated
                           background installation spinner with elapsed seconds timer and safety watchdog.
    - v2.1.0 (2026-10-19): Added empirical panel scanout ETW analysis, strict integer VSync detection,
                           sub-millisecond render latency tracking on drops, automatic DXGI flip discard
                           classification, and profile revision tracking.
    - v2.0.0 (2026-10-18): Added TopMost=2 window enforcement, USE_GPU dynamic injection, and Win32
                           QueryDisplayConfig pre-flight inspection.
    - v1.0.0 (2026-10-16): Initial portable automated benchmark harness.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [Alias("Video", "File")]
    [string]$VideoPath = "",

    [Parameter(Mandatory = $false)]
    [string]$ExpectedVideoHash = "99486359be7e3681168a0fe94e1cbb0284c48b57b2a3ce7df4fa75e185987a15",

    [Parameter(Mandatory = $false)]
    [switch]$SkipVideoChecksum,

    [Parameter(Mandatory = $false)]
    [Alias("Profile", "Avs", "Script")]
    [string]$AviSynthProfile = "",

    [Parameter(Mandatory = $false)]
    [Alias("Gpu", "Mode")]
    [ValidateSet("Auto", "D3D12", "GPU", "CPU", "NEON", "ProfileDefault", "")]
    [string]$GpuMode = "Auto",

    [Parameter(Mandatory = $false)]
    [Alias("Menu")]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [string]$PotPlayerDir = "",

    [Parameter(Mandatory = $false)]
    [string]$MvToolsDir = "",

    [Parameter(Mandatory = $false)]
    [int]$TestDurationSeconds = 120,

    [Parameter(Mandatory = $false)]
    [int]$WarmupSeconds = 20,

    [Parameter(Mandatory = $false)]
    [int]$BufferHeadroomMb = 1024,

    [Parameter(Mandatory = $false)]
    [double]$TargetIdleCpuPercent = 8.0,

    [Parameter(Mandatory = $false)]
    [double]$TargetIdleGpuPercent = 5.0,

    [Parameter(Mandatory = $false)]
    [int]$IdleStabilitySeconds = 5,

    [Parameter(Mandatory = $false)]
    [int]$IdleTimeoutSeconds = 60,

    [Parameter(Mandatory = $false)]
    [switch]$SkipNetworkDisable,

    [Parameter(Mandatory = $false)]
    [switch]$IgnoreUsbWarning,

    [Parameter(Mandatory = $false)]
    [Alias("IgnoreMemoryWarning")]
    [switch]$IgnoreRamWarning,

    [Parameter(Mandatory = $false)]
    [switch]$MemoryConstrained,

    [Parameter(Mandatory = $false)]
    [switch]$AutoInstallPotPlayer,

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = ""
)

# Harness Semantic Revision
$Script:HarnessVersion = "2.2.0"

# =========================================================
# 0. RESOLVE PORTABLE SCRIPT & REPOSITORY ROOTS
# =========================================================
$ScriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
    $ScriptDir = (Get-Location).Path
}

# Determine repository root (assumes script is in repo root or Benchmarks/ subdirectory)
$RepoRoot = $ScriptDir
if (Test-Path (Join-Path $ScriptDir "..\AviSynth")) {
    $RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
}

# Resolve PotPlayer directory: check sibling folder, then system installed locations
if ([string]::IsNullOrWhiteSpace($PotPlayerDir)) {
    $siblingDir = Join-Path $ScriptDir "PotPlayer"
    $installedDir64 = Join-Path ${env:ProgramFiles} "DAUM\PotPlayer"
    $installedDir32 = Join-Path ${env:ProgramFiles(x86)} "DAUM\PotPlayer"

    if (Test-Path (Join-Path $siblingDir "PotPlayer64.exe")) {
        $PotPlayerDir = $siblingDir
    } elseif (Test-Path (Join-Path $installedDir64 "PotPlayer64.exe")) {
        $PotPlayerDir = $installedDir64
    } elseif (Test-Path (Join-Path $installedDir32 "PotPlayer64.exe")) {
        $PotPlayerDir = $installedDir32
    } else {
        $PotPlayerDir = $siblingDir
    }
}

# Resolve MVTools binary search directory
if ([string]::IsNullOrWhiteSpace($MvToolsDir)) {
    $Candidates = @(
        $PotPlayerDir,
        (Join-Path $PotPlayerDir "plugins"),
        (Join-Path $ScriptDir "plugins"),
        $ScriptDir
    )
    foreach ($c in $Candidates) {
        if (Test-Path (Join-Path $c "mvtools2.dll")) {
            $MvToolsDir = $c
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($MvToolsDir)) {
        $MvToolsDir = $PotPlayerDir
    }
}

# Resolve Output directory
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ScriptDir "BenchmarkResults"
}

# Audit Windows Administrator Elevation Status
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---------------------------------------------------------
# HELPER: Detect USB Drive & Storage Media Characteristics
# ---------------------------------------------------------
function Test-IsUsbDrive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path = $PSScriptRoot
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = (Get-Location).Path
    }

    try {
        $resolvedPath = (Resolve-Path $Path -ErrorAction Stop).Path
    } catch {
        $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    }

    $driveRoot = [System.IO.Path]::GetPathRoot($resolvedPath)
    $driveLetter = $driveRoot.TrimEnd('\').TrimEnd(':')
    if (-not $driveLetter -or $driveLetter.Length -ne 1) {
        return [PSCustomObject]@{
            Path          = $resolvedPath
            DriveLetter   = ""
            FriendlyName  = "Network or Non-Volume Storage"
            BusType       = "Unknown"
            IsUsb         = $false
            IsThumbDrive  = $false
            IsExternalSsd = $false
        }
    }

    $dotNetRemovable = $false
    try {
        $driveInfo = [System.IO.DriveInfo]::new("${driveLetter}:\")
        $dotNetRemovable = ($driveInfo.DriveType -eq [System.IO.DriveType]::Removable)
    } catch {}

    try {
        $partition = Get-Partition -DriveLetter $driveLetter -ErrorAction Stop
        $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop

        $isUsb = ($disk.BusType -eq 'USB')
        $isRemovable = $dotNetRemovable -or ($partition.DriveType -eq 'Removable') -or ($disk.MediaType -match '(?i)Removable')
        $isThumbDrive = $isUsb -and ($isRemovable -or ($disk.MediaType -notmatch '(?i)SSD'))
        $isExternalSsd = $isUsb -and (-not $isRemovable) -and ($disk.MediaType -match '(?i)SSD')

        return [PSCustomObject]@{
            Path          = $resolvedPath
            DriveLetter   = "${driveLetter}:"
            FriendlyName  = $disk.FriendlyName
            BusType       = $disk.BusType
            IsUsb         = $isUsb
            IsThumbDrive  = $isThumbDrive
            IsExternalSsd = $isExternalSsd
        }
    }
    catch {
        # Fallback via .NET DriveInfo if storage cmdlets are unavailable
        return [PSCustomObject]@{
            Path          = $resolvedPath
            DriveLetter   = "${driveLetter}:"
            FriendlyName  = "Drive ${driveLetter}:"
            BusType       = if ($dotNetRemovable) { "USB/Removable" } else { "Unknown" }
            IsUsb         = $dotNetRemovable
            IsThumbDrive  = $dotNetRemovable
            IsExternalSsd = $false
        }
    }
}

# ---------------------------------------------------------
# HELPER: Audit Storage Media Suitability & Warn on USB Flash
# ---------------------------------------------------------
$script:AuditedStorageDrives = @{}

function Confirm-StorageMediaSuitability {
    [CmdletBinding()]
    param(
        [string[]]$Paths,
        [switch]$BypassPrompt
    )

    $usbFlashDrivesFound = @()
    $externalSsdsFound = @()

    foreach ($p in $Paths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $storageInfo = Test-IsUsbDrive -Path $p
        if ($storageInfo.DriveLetter -and -not $script:AuditedStorageDrives.ContainsKey($storageInfo.DriveLetter)) {
            $script:AuditedStorageDrives[$storageInfo.DriveLetter] = $true
            if ($storageInfo.IsThumbDrive) {
                $usbFlashDrivesFound += $storageInfo
            } elseif ($storageInfo.IsExternalSsd) {
                $externalSsdsFound += $storageInfo
            }
        }
    }

    if ($usbFlashDrivesFound.Count -gt 0) {
        Write-Host "`n[WARNING] USB FLASH DRIVE DETECTED!" -ForegroundColor Red
        foreach ($d in $usbFlashDrivesFound) {
            Write-Host "  -> Location:       $($d.Path) ($($d.DriveLetter))" -ForegroundColor Yellow
            Write-Host "  -> Storage Device: $($d.FriendlyName) [Bus: $($d.BusType)]" -ForegroundColor Yellow
        }
        Write-Host "`n  POTENTIAL BENCHMARK IMPACT:" -ForegroundColor Yellow
        Write-Host "  Running benchmarks, PotPlayer, or video decoding from a USB flash thumb drive" -ForegroundColor White
        Write-Host "  can cause severe random I/O read bottlenecks, thermal throttling, and high" -ForegroundColor White
        Write-Host "  latency spikes. This may cause artificial frame drops and adversely affect results." -ForegroundColor White
        Write-Host "  For accurate, reproducible metrics, use an internal NVMe/SSD drive.`n" -ForegroundColor White

        if ($BypassPrompt) {
            Write-Host "  -> -IgnoreUsbWarning flag specified. Continuing benchmark despite USB flash storage...`n" -ForegroundColor DarkYellow
            return $true
        }

        $isInteractiveHost = [Environment]::UserInteractive -and ($Host.UI.RawUI -ne $null) -and (-not [Console]::IsInputRedirected)
        if (-not $isInteractiveHost) {
            Write-Host "[ERROR] USB flash drive detected in non-interactive/redirected execution mode. Aborting benchmark." -ForegroundColor Red
            Write-Host "To allow execution on USB flash media in automated scripts, re-run with -IgnoreUsbWarning.`n" -ForegroundColor Yellow
            exit 1
        }

        Write-Host "Do you want to continue running the benchmark? [y/N]: " -NoNewline -ForegroundColor Cyan
        $userChoice = Read-Host
        if ($userChoice -notmatch '^(?i)y(es)?$') {
            Write-Host "`n[BENCHMARK ABORTED] Execution stopped by user due to USB flash storage detection." -ForegroundColor Red
            Write-Host "Copy the benchmark folder and video file to an internal NVMe/SSD drive and re-run.`n" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "  -> Continuing benchmark on USB drive as confirmed by user...`n" -ForegroundColor DarkYellow
    } elseif ($externalSsdsFound.Count -gt 0) {
        foreach ($d in $externalSsdsFound) {
            Write-Host "[NOTICE] External USB SSD storage detected on $($d.DriveLetter) ($($d.FriendlyName))." -ForegroundColor DarkCyan
        }
    }

    return $true
}

# ---------------------------------------------------------
# HELPER: Find 7-Zip Executable
# ---------------------------------------------------------
# HELPER: Find PresentMon Executable
# ---------------------------------------------------------
function Find-PresentMonExecutable {
    $PossiblePaths = @(
        (Join-Path $ScriptDir "PresentMon.exe"),
        (Join-Path $ScriptDir "PresentMon-arm64.exe"),
        (Join-Path $ScriptDir "PresentMon-x64.exe"),
        (Get-Command "PresentMon.exe" -ErrorAction SilentlyContinue).Source,
        (Get-Command "PresentMon-arm64.exe" -ErrorAction SilentlyContinue).Source,
        (Get-Command "PresentMon-x64.exe" -ErrorAction SilentlyContinue).Source,
        (Join-Path ${env:ProgramFiles} "PresentMon\PresentMon.exe")
    )
    foreach ($p in $PossiblePaths) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path $p)) {
            return $p
        }
    }
    return $null
}

# ---------------------------------------------------------
# HELPER: Automated Acquisition & Silent Installation of PotPlayer ARM64
# ---------------------------------------------------------
function Install-PotPlayerARM64 {
    param(
        [string]$TargetDir = "",
        [bool]$Elevated = $false
    )

    $Url = "https://t1.daumcdn.net/potplayer/PotPlayer/Version/Latest/PotPlayerSetupARM64.exe"
    $TempInstaller = Join-Path $env:TEMP ("PotPlayerSetupARM64_{0}.exe" -f [System.Guid]::NewGuid().ToString("N"))

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host " AUTOMATED POTPLAYER ARM64 ACQUISITION & SETUP" -ForegroundColor Cyan
    Write-Host " Source: Kakao Corp Official CDN ($Url)" -ForegroundColor Gray
    Write-Host " Architecture: Native Windows on ARM64" -ForegroundColor Gray
    Write-Host "========================================================`n" -ForegroundColor Cyan

    # Phase 1: Download with live stream progress
    Write-Host "[1/2] Downloading Official PotPlayer ARM64 Installer..." -ForegroundColor Cyan

    $Client = [System.Net.Http.HttpClient]::new()
    $FileStream = $null
    $Stream = $null
    try {
        $Response = $Client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if (-not $Response.IsSuccessStatusCode) {
            throw "Failed to download PotPlayer installer from CDN! HTTP status: $($Response.StatusCode) $($Response.ReasonPhrase)"
        }

        $TotalBytes = $Response.Content.Headers.ContentLength
        $Stream = $Response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $FileStream = [System.IO.File]::Create($TempInstaller)

        $Buffer = New-Object byte[] 65536
        $TotalRead = 0
        $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $LastUiUpdate = [System.Diagnostics.Stopwatch]::StartNew()

        while (($Read = $Stream.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
            $FileStream.Write($Buffer, 0, $Read)
            $TotalRead += $Read

            if ($LastUiUpdate.ElapsedMilliseconds -ge 100 -or $TotalRead -eq $TotalBytes) {
                $Percent = if ($TotalBytes -gt 0) { [math]::Round(($TotalRead / $TotalBytes) * 100) } else { 0 }
                $MbRead = ($TotalRead / 1MB).ToString("0.0")
                $MbTotal = if ($TotalBytes -gt 0) { ($TotalBytes / 1MB).ToString("0.0") } else { "???" }
                $ElapsedSec = [math]::Max($Stopwatch.Elapsed.TotalSeconds, 0.001)
                $Speed = ($TotalRead / 1MB / $ElapsedSec).ToString("0.0")

                $FilledLength = [int](($Percent / 100) * 20)
                $Arrow = if ($FilledLength -gt 0) { ">" } else { "" }
                $Bar = ("=" * [math]::Max(0, $FilledLength - 1)) + $Arrow
                $Bar = $Bar.PadRight(20, ' ')

                $EtaStr = ""
                if ($TotalBytes -gt 0 -and ($TotalRead / $ElapsedSec) -gt 0) {
                    $RemainingSec = [math]::Round(($TotalBytes - $TotalRead) / ($TotalRead / $ElapsedSec))
                    $EtaStr = " [ETA: ${RemainingSec}s]"
                }

                Write-Host -NoNewline ("`r  [$Bar] $Percent% ($MbRead / $MbTotal MB) | $Speed MB/s$EtaStr   ") -ForegroundColor DarkCyan
                $LastUiUpdate.Restart()
            }
        }

        $FileStream.Close()
        $Stream.Close()
        $TotalMb = ($TotalRead / 1MB).ToString("0.0")
        $TotalSec = [math]::Round($Stopwatch.Elapsed.TotalSeconds, 1)
        Write-Host "`r  [OK] Download complete! ($TotalMb MB downloaded in ${TotalSec}s)                              " -ForegroundColor Green
    }
    catch {
        Write-Host "`r  [ERROR] Download failed: $_" -ForegroundColor Red
        if ($FileStream) { $FileStream.Dispose() }
        if ($Stream) { $Stream.Dispose() }
        $Client.Dispose()
        if (Test-Path $TempInstaller) { Remove-Item $TempInstaller -Force -ErrorAction SilentlyContinue }
        return $null
    }
    finally {
        $Client.Dispose()
    }

    # Phase 2: Silent installation with animated spinner & live timer
    Write-Host "`n[2/2] Installing PotPlayer silently in the background..." -ForegroundColor Cyan

    $InstallerArgs = @("/S")
    if (-not [string]::IsNullOrWhiteSpace($TargetDir)) {
        # NSIS requires /D=<path> without surrounding quotes
        $InstallerArgs += "/D=$TargetDir"
    }

    try {
        $StartParams = @{
            FilePath     = $TempInstaller
            ArgumentList = $InstallerArgs
            PassThru     = $true
        }
        if (-not $Elevated) {
            $StartParams["Verb"] = "RunAs"
        }

        $Process = Start-Process @StartParams
        $Spinner = @('|', '/', '-', '\')
        $SpinIndex = 0
        $InstallWatch = [System.Diagnostics.Stopwatch]::StartNew()

        while (-not $Process.HasExited) {
            $Char = $Spinner[$SpinIndex % $Spinner.Length]
            $ElapsedSec = [math]::Round($InstallWatch.Elapsed.TotalSeconds)
            Write-Host -NoNewline "`r  [$Char] Unpacking and registering ARM64 components... (${ElapsedSec}s elapsed)   " -ForegroundColor Yellow
            Start-Sleep -Milliseconds 250
            $SpinIndex++

            # Safety watchdog (180 seconds max)
            if ($InstallWatch.Elapsed.TotalSeconds -gt 180) {
                Write-Warning "`n[TIMEOUT] PotPlayer installation timed out after 180 seconds. Terminating installer process."
                Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                break
            }
        }

        $Process.WaitForExit()
        $InstallSec = [math]::Round($InstallWatch.Elapsed.TotalSeconds, 1)

        if ($Process.ExitCode -eq 0) {
            Write-Host "`r  [OK] PotPlayer installed successfully in ${InstallSec}s!                                    `n" -ForegroundColor Green
        } else {
            Write-Host "`r  [WARNING] Installer exited with code $($Process.ExitCode) after ${InstallSec}s. Checking for installed files...`n" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "`r  [ERROR] Failed to execute installer: $_" -ForegroundColor Red
        return $null
    }
    finally {
        Remove-Item $TempInstaller -Force -ErrorAction SilentlyContinue
    }

    # Resolve installed location
    $CheckLocations = @()
    if (-not [string]::IsNullOrWhiteSpace($TargetDir)) {
        $CheckLocations += $TargetDir
    }
    $CheckLocations += @(
        (Join-Path ${env:ProgramFiles} "DAUM\PotPlayer"),
        (Join-Path ${env:ProgramW6432} "DAUM\PotPlayer"),
        (Join-Path ${env:ProgramFiles(x86)} "DAUM\PotPlayer"),
        (Join-Path $env:LOCALAPPDATA "DAUM\PotPlayer")
    )

    foreach ($loc in $CheckLocations) {
        if (-not [string]::IsNullOrWhiteSpace($loc) -and (Test-Path (Join-Path $loc "PotPlayer64.exe"))) {
            return $loc
        }
    }

    return $null
}

# ---------------------------------------------------------
# HELPER: System Hardware Platform & Recommendation Engine
# ---------------------------------------------------------
function Get-SystemPlatformRecommendation {
    param([string]$RepoRoot = ".")
    $cpuName = ""
    $gpuName = ""
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpu -and $cpu.Name) { $cpuName = $cpu.Name.Trim() }
    } catch {}
    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gpu -and $gpu.Name) { $gpuName = $gpu.Name.Trim() }
    } catch {}

    $combined = "$cpuName $gpuName"
    $profiles = Get-AvailableAviSynthProfiles -RepoRoot $RepoRoot

    # Baseline hardware detection rules
    $platform = "Snapdragon-X-Plus"
    $platformLabel = "Snapdragon X Plus (Qualcomm Oryon CPU, Adreno X1 GPU)"

    if ($combined -match '(?i)X\s*Plus|X1P') {
        $platform = "Snapdragon-X-Plus"
        $platformLabel = "Snapdragon X Plus (Qualcomm Oryon CPU, Adreno X1 GPU)"
    } elseif ($combined -match '(?i)X\s*Elite|X1E') {
        # Dynamically check if dedicated X-Elite profiles exist in AviSynth/
        $hasElite = $profiles | Where-Object { $_.Platform -match '(?i)X[-_]?Elite' } | Select-Object -First 1
        $platform = if ($hasElite) { $hasElite.Platform } else { "Snapdragon-X-Plus" }
        $platformLabel = "Snapdragon X Elite (Qualcomm Oryon CPU, Adreno X1 GPU)"
    } elseif ($combined -match '(?i)8cx\s*Gen\s*3|SC8280|8180X') {
        $platform = "Snapdragon-8cxGen3"
        $platformLabel = "Snapdragon 8cx Gen 3 (Kryo Cortex-X1/A78, Adreno 690)"
    } elseif ($combined -match '(?i)8cx\s*Gen\s*2|SQ2') {
        $platform = "Snapdragon-8cxGen2"
        $platformLabel = "Snapdragon 8cx Gen 2 / SQ2 (Kryo 495, Adreno 680)"
    } elseif ($combined -match '(?i)8cx|SQ1') {
        $platform = "Snapdragon-8cxGen1"
        $platformLabel = "Snapdragon 8cx Gen 1 / SQ1 (Kryo 495, Adreno 675)"
    } elseif ($combined -match '(?i)850|SD850') {
        $platform = "Snapdragon-850"
        $platformLabel = "Snapdragon 850 (Kryo 385, Adreno 630)"
    } elseif ($combined -match '(?i)7c') {
        $platform = "Snapdragon-7cGen2"
        $platformLabel = "Snapdragon 7c Gen 2 (Kryo 468, Adreno 618)"
    } else {
        # Dynamic discovery for new or unlisted hardware profiles
        # Match against profile platform names or embedded '# Hardware:' docstrings
        $matchedProfile = $null
        foreach ($p in $profiles) {
            $platToken = $p.Platform -replace '(?i)^Snapdragon[-_]?', ''
            if (-not [string]::IsNullOrWhiteSpace($platToken) -and $combined -match [regex]::Escape($platToken)) {
                $matchedProfile = $p
                break
            }
            if ($p.HardwareDesc -and ($combined -match [regex]::Escape($p.HardwareDesc) -or $p.HardwareDesc -match [regex]::Escape($cpuName))) {
                $matchedProfile = $p
                break
            }
        }
        if ($matchedProfile) {
            $platform = $matchedProfile.Platform
            $platformLabel = if ($matchedProfile.HardwareDesc) { $matchedProfile.HardwareDesc } else { "$($matchedProfile.Platform) ($cpuName)" }
        } else {
            $platformLabel = "Generic Hardware ($cpuName $gpuName)"
        }
    }

    # Dynamic recommendation resolution: check if a Balanced profile exists for this platform
    $recProfileName = "$platform-Balanced.avs"
    $hasRec = $profiles | Where-Object { $_.Name -ieq $recProfileName } | Select-Object -First 1
    if (-not $hasRec) {
        # Fall back to any profile belonging to this platform
        $platProfile = $profiles | Where-Object { $_.Platform -ieq $platform } | Select-Object -First 1
        if ($platProfile) {
            $recProfileName = $platProfile.Name
        } elseif ($profiles.Count -gt 0) {
            $recProfileName = $profiles[0].Name
        }
    }

    return [PSCustomObject]@{
        PlatformKey        = $platform
        PlatformLabel      = $platformLabel
        CpuName            = $cpuName
        GpuName            = $gpuName
        RecommendedProfile = $recProfileName
        RecommendedGpuMode = "CPU"
    }
}

# ---------------------------------------------------------
# HELPER: List Available AviSynth Profiles
# ---------------------------------------------------------
function Get-AvailableAviSynthProfiles {
    param([string]$RepoRoot = ".")
    $avsDir = Join-Path $RepoRoot "AviSynth"
    if (-not (Test-Path $avsDir)) { return @() }
    
    $files = Get-ChildItem -Path $avsDir -Filter "*.avs" | Sort-Object Name
    $profiles = @()
    foreach ($f in $files) {
        $content = Get-Content $f.FullName -Raw
        $supportGpu = $content -match '(?i)USE_GPU'
        $tier = if ($f.Name -match '(?i)Eco') { "Eco" }
                elseif ($f.Name -match '(?i)MaxQuality|Quality') { "MaxQuality" }
                elseif ($f.Name -match '(?i)Balanced') { "Balanced" }
                else { "Custom" }

        $platform = $f.Name -replace '(?i)[-_](Balanced|Eco|MaxQuality|Custom)\.avs$', ''
        if ($platform -ieq $f.Name) {
            $platform = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        }

        $hwDesc = ""
        if ($content -match '(?m)^\s*#\s*Hardware:\s*(.+)$') {
            $hwDesc = $Matches[1].Trim()
        }

        $profiles += [PSCustomObject]@{
            Name         = $f.Name
            FullName     = $f.FullName
            Platform     = $platform
            Tier         = $tier
            SupportsGpu  = $supportGpu
            HardwareDesc = $hwDesc
        }
    }
    return $profiles
}

# ---------------------------------------------------------
# HELPER: Resolve Profile Path (Supports Name, Tier, Partial, Path)
# ---------------------------------------------------------
function Resolve-AviSynthProfilePath {
    param(
        [string]$InputProfile,
        [string]$RepoRoot = ".",
        [string]$RecommendedName = "",
        [string]$PlatformKey = ""
    )

    $profiles = Get-AvailableAviSynthProfiles -RepoRoot $RepoRoot

    if (-not [string]::IsNullOrWhiteSpace($InputProfile)) {
        # 1. Exact path match
        if (Test-Path $InputProfile) {
            return (Resolve-Path $InputProfile).Path
        }

        # 2. Match in AviSynth dir
        $candidateInDir = Join-Path $RepoRoot "AviSynth\$InputProfile"
        if (Test-Path $candidateInDir) { return (Resolve-Path $candidateInDir).Path }
        if (Test-Path "$candidateInDir.avs") { return (Resolve-Path "$candidateInDir.avs").Path }

        # 3. If user provided a tier name (e.g. "Balanced", "Eco", "MaxQuality"), prioritize detected platform
        if (-not [string]::IsNullOrWhiteSpace($PlatformKey) -and $InputProfile -match '^(Balanced|Eco|MaxQuality)$') {
            $platformMatch = $profiles | Where-Object { $_.Platform -ieq $PlatformKey -and $_.Tier -ieq $InputProfile } | Select-Object -First 1
            if ($platformMatch) { return $platformMatch.FullName }
        }

        # 4. Filename exact match
        $match = $profiles | Where-Object { $_.Name -ieq $InputProfile -or $_.Name -ieq "$InputProfile.avs" } | Select-Object -First 1
        if ($match) { return $match.FullName }

        # 5. Partial name substring match
        $match = $profiles | Where-Object { $_.Name -like "*$InputProfile*" } | Select-Object -First 1
        if ($match) { return $match.FullName }
    }

    # Fallback to recommended profile
    if (-not [string]::IsNullOrWhiteSpace($RecommendedName)) {
        $match = $profiles | Where-Object { $_.Name -ieq $RecommendedName } | Select-Object -First 1
        if ($match) { return $match.FullName }
    }

    if ($profiles.Count -gt 0) {
        return $profiles[0].FullName
    }
    return $null
}

# ---------------------------------------------------------
# HELPER: Interactive Profile & GPU Mode Selector
# ---------------------------------------------------------
function Select-ProfileAndModeInteractive {
    param(
        [string]$RepoRoot,
        [PSCustomObject]$Recommendation,
        [string]$CurrentProfile,
        [string]$CurrentGpuMode
    )

    $profiles = Get-AvailableAviSynthProfiles -RepoRoot $RepoRoot
    if ($profiles.Count -eq 0) {
        Write-Warning "No .avs profiles found in AviSynth directory!"
        return @{ ProfilePath = $CurrentProfile; GpuMode = $CurrentGpuMode }
    }

    Write-Host "`n========================================================================" -ForegroundColor Cyan
    Write-Host " HARDWARE DETECTION & RECOMMENDATION ENGINE" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "  -> CPU:            $($Recommendation.CpuName)" -ForegroundColor White
    Write-Host "  -> GPU:            $($Recommendation.GpuName)" -ForegroundColor White
    Write-Host "  -> Detected SoC:   $($Recommendation.PlatformLabel)" -ForegroundColor Yellow
    Write-Host "  -> Recommended:    $($Recommendation.RecommendedProfile)" -ForegroundColor Green
    Write-Host "  -> Suggested Mode: $($Recommendation.RecommendedGpuMode) NEON (Optimum 1% low frame time stability)" -ForegroundColor Green
    Write-Host "========================================================================`n" -ForegroundColor Cyan

    Write-Host "Available AviSynth Profiles:" -ForegroundColor Yellow
    $recIndex = 1
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $p = $profiles[$i]
        $isRec = ($p.Name -ieq $Recommendation.RecommendedProfile)
        if ($isRec) { $recIndex = $i + 1 }
        $badge = if ($isRec) { " [RECOMMENDED FOR YOUR HARDWARE]" } else { "" }
        $color = if ($isRec) { "Green" } elseif ($p.Platform -eq $Recommendation.PlatformKey) { "White" } else { "Gray" }
        $d3dTag = if ($p.SupportsGpu) { " [D3D12/CPU]" } else { " [CPU-Only]" }
        Write-Host ("  [{0,2}] {1,-35} ({2,-10}){3}{4}" -f ($i + 1), $p.Name, $p.Tier, $d3dTag, $badge) -ForegroundColor $color
    }

    Write-Host ""
    $prompt = "Select Profile [1-$($profiles.Count)] (Press Enter for default [$recIndex]): "
    Write-Host $prompt -NoNewline -ForegroundColor Cyan
    $choice = Read-Host

    $selectedProfile = $null
    if ([string]::IsNullOrWhiteSpace($choice)) {
        $selectedProfile = $profiles[$recIndex - 1]
    } else {
        $idx = 0
        if ([int]::TryParse($choice.Trim(), [ref]$idx) -and $idx -ge 1 -and $idx -le $profiles.Count) {
            $selectedProfile = $profiles[$idx - 1]
        } else {
            Write-Host "  Invalid selection; using recommended profile [$recIndex]." -ForegroundColor DarkYellow
            $selectedProfile = $profiles[$recIndex - 1]
        }
    }
    Write-Host "  Selected: $($selectedProfile.Name)" -ForegroundColor Green

    # GPU Mode selection
    $selectedGpuMode = $CurrentGpuMode
    if ($selectedProfile.SupportsGpu) {
        Write-Host "`nSelect Motion Vector Acceleration Engine:" -ForegroundColor Yellow
        Write-Host "  [1] ARM64 CPU NEON (mvtools2.dll)         [RECOMMENDED: Highest 1% Low FPS, rock-solid pacing]" -ForegroundColor Green
        Write-Host "  [2] Direct3D 12 GPU (mvtools2_d3d12.dll)  [EXPERIMENTAL PREVIEW: CPU offload, performance/quality not guaranteed]" -ForegroundColor Cyan
        Write-Host "Select Acceleration Mode [1-2] (Press Enter for default [1]): " -NoNewline -ForegroundColor Cyan
        $modeChoice = Read-Host
        if ($modeChoice -eq "2") {
            $selectedGpuMode = "D3D12"
            Write-Host "  Selected Acceleration: Direct3D 12 GPU Compute" -ForegroundColor Cyan
        } else {
            $selectedGpuMode = "CPU"
            Write-Host "  Selected Acceleration: ARM64 CPU NEON" -ForegroundColor Green
        }
    } else {
        $selectedGpuMode = "CPU"
        Write-Host "  Note: Profile '$($selectedProfile.Name)' is CPU-specialized (running on ARM64 CPU NEON)." -ForegroundColor Gray
    }

    return @{
        ProfilePath = $selectedProfile.FullName
        GpuMode     = $selectedGpuMode
    }
}

# ---------------------------------------------------------
# HELPER: Parse AviSynth Profile SetMemoryMax
# ---------------------------------------------------------
function Get-AviSynthMemoryRequirement([string]$ProfilePath, [string]$GpuModeChoice = "") {
    if (-not (Test-Path $ProfilePath)) { return 1024 }
    $content = Get-Content -Path $ProfilePath -Raw
    if ($content -match 'mem_limit\s*=\s*USE_GPU\s*\?\s*(\d+)\s*:\s*(\d+)') {
        $gpuMem = [int]$Matches[1]
        $cpuMem = [int]$Matches[2]
        if ($GpuModeChoice -match '(?i)D3D12|GPU') { return $gpuMem }
        if ($GpuModeChoice -match '(?i)CPU|NEON') { return $cpuMem }
        if ($content -match '(?m)^\s*USE_GPU\s*=\s*true') { return $gpuMem }
        return $cpuMem
    }
    if ($content -match '(?i)SetMemoryMax\s*\(\s*(\d+)\s*\)') {
        return [int]$Matches[1]
    }
    return 1024
}

# ---------------------------------------------------------
# HELPER: Read PE Header Linker Build Timestamp
# ---------------------------------------------------------
function Get-PeBuildDate([string]$FilePath) {
    try {
        if (-not (Test-Path $FilePath)) { return "Not Found" }
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        $peOffset = [System.BitConverter]::ToInt32($bytes, 0x3C)
        $timeDateStamp = [System.BitConverter]::ToUInt32($bytes, $peOffset + 8)
        $epoch = [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
        return $epoch.AddSeconds($timeDateStamp).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
    } catch {
        return (Get-Item $FilePath).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    }
}

# ---------------------------------------------------------
# HELPER: Inspect MVTools Binary Metadata
# ---------------------------------------------------------
function Get-MvToolsMetadata([string]$DllPath) {
    if (-not (Test-Path $DllPath)) { return $null }
    $item = Get-Item $DllPath
    $ver = $item.VersionInfo
    $sha256 = (Get-FileHash -Path $DllPath -Algorithm SHA256).Hash
    $buildDate = Get-PeBuildDate -FilePath $DllPath

    return [PSCustomObject]@{
        Name           = $item.Name
        FullPath       = $item.FullName
        FileVersion    = $ver.FileVersion
        ProductVersion = $ver.ProductVersion
        PeBuildDate    = $buildDate
        LastWriteTime  = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        SHA256         = $sha256
        SizeBytes      = $item.Length
    }
}




# ---------------------------------------------------------
# HELPER: Inspect Display Hardware Refresh Rate (Win32 QueryDisplayConfig)
# ---------------------------------------------------------
function Get-DisplayRefreshInfo {
    try {
        if (-not ([System.Management.Automation.PSTypeName]'DisplayQueryHelper').Type) {
            $code = @'
using System;
using System.Runtime.InteropServices;

public class DisplayQueryHelper {
    public const uint QDC_ONLY_SPECIFIED_PATHS = 0x00000002;

    [StructLayout(LayoutKind.Sequential)]
    public struct LUID {
        public uint LowPart;
        public int HighPart;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_RATIONAL {
        public uint Numerator;
        public uint Denominator;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_SOURCE_INFO {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_TARGET_INFO {
        public LUID adapterId;
        public uint id;
        public uint modeInfoIdx;
        public uint outputTechnology;
        public uint rotation;
        public uint scaling;
        public DISPLAYCONFIG_RATIONAL refreshRate;
        public uint scanLineOrdering;
        public bool targetAvailable;
        public uint statusFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_PATH_INFO {
        public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
        public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
        public uint flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DISPLAYCONFIG_MODE_INFO {
        public uint infoType;
        public uint id;
        public LUID adapterId;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 64)]
        public byte[] modeInfo;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAYCONFIG_TARGET_DEVICE_NAME {
        public uint type;
        public uint size;
        public LUID adapterId;
        public uint id;
        public uint flags;
        public uint outputTechnology;
        public ushort edidManufactureId;
        public ushort edidProductCodeId;
        public uint connectorInstance;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string monitorFriendlyDeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string monitorDevicePath;
    }

    [DllImport("user32.dll")]
    public static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPathArrayElements, out uint numModeInfoArrayElements);

    [DllImport("user32.dll")]
    public static extern int QueryDisplayConfig(uint flags, ref uint numPathArrayElements, [Out] DISPLAYCONFIG_PATH_INFO[] pathInfoArray, ref uint numModeInfoArrayElements, [Out] DISPLAYCONFIG_MODE_INFO[] modeInfoArray, IntPtr currentTopologyId);

    [DllImport("user32.dll")]
    public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_TARGET_DEVICE_NAME deviceName);

    public class DisplayResult {
        public string MonitorName;
        public uint Numerator;
        public uint Denominator;
        public double RefreshRateHz;
        public double RoundedHz;
        public bool IsIntegerRate;
        public string RationalString;
    }

    public static DisplayResult QueryPrimaryDisplay() {
        uint pathCount = 0;
        uint modeCount = 0;
        int status = GetDisplayConfigBufferSizes(QDC_ONLY_SPECIFIED_PATHS, out pathCount, out modeCount);
        if (status != 0) return null;

        DISPLAYCONFIG_PATH_INFO[] paths = new DISPLAYCONFIG_PATH_INFO[pathCount];
        DISPLAYCONFIG_MODE_INFO[] modes = new DISPLAYCONFIG_MODE_INFO[modeCount];

        status = QueryDisplayConfig(QDC_ONLY_SPECIFIED_PATHS, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
        if (status != 0 || pathCount == 0) return null;

        for (int i = 0; i < pathCount; i++) {
            var target = paths[i].targetInfo;
            if (target.refreshRate.Denominator > 0) {
                double hz = (double)target.refreshRate.Numerator / target.refreshRate.Denominator;
                string name = "Primary Display";
                try {
                    DISPLAYCONFIG_TARGET_DEVICE_NAME dev = new DISPLAYCONFIG_TARGET_DEVICE_NAME();
                    dev.type = 2;
                    dev.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_TARGET_DEVICE_NAME));
                    dev.adapterId = target.adapterId;
                    dev.id = target.id;
                    if (DisplayConfigGetDeviceInfo(ref dev) == 0 && !string.IsNullOrEmpty(dev.monitorFriendlyDeviceName)) {
                        name = dev.monitorFriendlyDeviceName;
                    }
                } catch {}

                double rounded = Math.Round(hz);
                bool isInt = Math.Abs(hz - rounded) < 0.0001 && (target.refreshRate.Denominator == 0 || target.refreshRate.Numerator % target.refreshRate.Denominator == 0);

                return new DisplayResult {
                    MonitorName = name,
                    Numerator = target.refreshRate.Numerator,
                    Denominator = target.refreshRate.Denominator,
                    RefreshRateHz = hz,
                    RoundedHz = rounded,
                    IsIntegerRate = isInt,
                    RationalString = target.refreshRate.Numerator + "/" + target.refreshRate.Denominator
                };
            }
        }
        return null;
    }
}
'@
            Add-Type -TypeDefinition $code -ErrorAction Stop
        }

        $res = [DisplayQueryHelper]::QueryPrimaryDisplay()
        if ($res) {
            return [PSCustomObject]@{
                MonitorName     = $res.MonitorName
                Numerator       = $res.Numerator
                Denominator     = $res.Denominator
                RefreshRateHz   = [math]::Round($res.RefreshRateHz, 4)
                RoundedHz       = [int]$res.RoundedHz
                IsIntegerRate   = $res.IsIntegerRate
                RationalString  = $res.RationalString
                DetectionMethod = "QueryDisplayConfig"
            }
        }
    } catch {}

    # Fallback to WMI / CIM VideoController
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gpu -and $gpu.CurrentRefreshRate) {
        $wmiHz = [double]$gpu.CurrentRefreshRate
        $rounded = [math]::Round($wmiHz)
        $isInt = ($wmiHz -gt 0) -and ($wmiHz % 1.0 -eq 0.0)
        return [PSCustomObject]@{
            MonitorName     = if ($gpu.Name) { $gpu.Name } else { "Display Adapter" }
            Numerator       = [uint32]$wmiHz
            Denominator     = 1
            RefreshRateHz   = $wmiHz
            RoundedHz       = [int]$rounded
            IsIntegerRate   = $isInt
            RationalString  = "$wmiHz/1"
            DetectionMethod = "Win32_VideoController"
        }
    }

    # Default fallback
    return [PSCustomObject]@{
        MonitorName     = "Standard Display"
        Numerator       = 60
        Denominator     = 1
        RefreshRateHz   = 60.0
        RoundedHz       = 60
        IsIntegerRate   = $true
        RationalString  = "60/1"
        DetectionMethod = "DefaultAssumption"
    }
}

# ---------------------------------------------------------
# HELPER: Real-Time System Telemetry Query
# ---------------------------------------------------------
function Get-SystemMetrics {
    param([int]$PotProcessId = 0)

    try {
        $counters = @(
            '\Processor Information(_Total)\% Processor Utility',
            '\GPU Engine(*)\Utilization Percentage',
            '\Memory\Available MBytes',
            '\Memory\Pages/sec'
        )
        $samples = (Get-Counter -Counter $counters -ErrorAction SilentlyContinue).CounterSamples
        
        $cpuVal = ($samples | Where-Object { $_.Path -match 'Processor Information' }).CookedValue
        $gpuTotalVal = ($samples | Where-Object { $_.Path -match 'GPU Engine' } | Measure-Object -Property CookedValue -Sum).Sum
        $availRamVal = ($samples | Where-Object { $_.Path -match 'Available MBytes' }).CookedValue
        $pagesSecVal = ($samples | Where-Object { $_.Path -match 'Pages/sec' }).CookedValue

        $potGpuVal = 0
        if ($PotProcessId -gt 0) {
            $potGpuVal = ($samples | Where-Object { $_.InstanceName -match "^pid_${PotProcessId}_" } | Measure-Object -Property CookedValue -Sum).Sum
        }

        # Check instance count
        $allPotProcs = Get-Process -Name "PotPlayer64", "PotPlayer" -ErrorAction SilentlyContinue
        $potCount = if ($allPotProcs) { $allPotProcs.Count } else { 0 }

        return [PSCustomObject]@{
            CpuPercent      = [math]::Round([math]::Max(0, [double]$cpuVal), 1)
            GpuTotalPercent = [math]::Round([math]::Max(0, [double]$gpuTotalVal), 1)
            PotGpuPercent   = [math]::Round([math]::Max(0, [double]$potGpuVal), 1)
            AvailRamMb      = [math]::Round([math]::Max(0, [double]$availRamVal), 0)
            PagesPerSec     = [math]::Round([math]::Max(0, [double]$pagesSecVal), 1)
            PotInstances    = $potCount
        }
    } catch {
        return [PSCustomObject]@{
            CpuPercent      = 0.0
            GpuTotalPercent = 0.0
            PotGpuPercent   = 0.0
            AvailRamMb      = 0
            PagesPerSec     = 0.0
            PotInstances    = 0
        }
    }
}

# ---------------------------------------------------------
# HELPER: Enforce Single-Instance Purity
# ---------------------------------------------------------
function Ensure-SinglePotPlayerInstance([int]$TargetPid = 0) {
    $procs = Get-Process -Name "PotPlayer64", "PotPlayer" -ErrorAction SilentlyContinue
    if (-not $procs) { return $true }

    if ($TargetPid -eq 0) {
        Write-Host "  -> Terminating $($procs.Count) pre-existing PotPlayer instance(s) to guarantee single-instance purity..." -ForegroundColor Yellow
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        return $true
    } else {
        $extraneous = $procs | Where-Object { $_.Id -ne $TargetPid }
        if ($extraneous) {
            Write-Host "  -> Multiple instances detected! Terminating $($extraneous.Count) extraneous instance(s)..." -ForegroundColor DarkYellow
            $extraneous | Stop-Process -Force -ErrorAction SilentlyContinue
            return $false
        }
        return $true
    }
}

# ---------------------------------------------------------
# HELPER: Parse PresentMon Frame Rate Metrics
# ---------------------------------------------------------
function Get-PresentMonMetrics([string]$CsvPath) {
    if (-not (Test-Path $CsvPath)) { return $null }
    $rows = Import-Csv -Path $CsvPath -ErrorAction SilentlyContinue
    if (-not $rows -or $rows.Count -lt 10) { return $null }

    $frameTimesMs = @()
    $displayIntervalsMs = @()
    $renderTimesMs = @()
    $dropRenderTimesMs = @()
    $droppedCount = 0

    foreach ($r in $rows) {
        # Filter for PotPlayer application if present in multi-process/named capture
        if ($r.Application -and $r.Application -notmatch '(?i)PotPlayer') {
            continue
        }

        $ms = 0.0
        # Parse msBetweenPresents (v1 format: msBetweenPresents; v2 format: MsBetweenPresents)
        $valStr = if ($r.msBetweenPresents) { $r.msBetweenPresents } else { $r.MsBetweenPresents }
        if ($valStr -and [double]::TryParse($valStr, [ref]$ms) -and $ms -gt 1.0) {
            $frameTimesMs += $ms
        }

        # Parse msUntilRenderComplete (rendering latency to DXGI queue)
        $renderMs = 0.0
        $renderStr = if ($r.msUntilRenderComplete) { $r.msUntilRenderComplete } else { $r.MsUntilRenderComplete }
        $hasRender = ($renderStr -and [double]::TryParse($renderStr, [ref]$renderMs))
        if ($hasRender) {
            $renderTimesMs += $renderMs
        }

        if ($r.Dropped -eq "1") {
            $droppedCount++
            if ($hasRender) {
                $dropRenderTimesMs += $renderMs
            }
        } else {
            # Parse msBetweenDisplayChange for displayed frames to determine true physical scanout rate
            $dispMs = 0.0
            $dispStr = if ($r.msBetweenDisplayChange) { $r.msBetweenDisplayChange } else { $r.MsBetweenDisplayChange }
            if ($dispStr -and [double]::TryParse($dispStr, [ref]$dispMs) -and $dispMs -gt 5.0) {
                $displayIntervalsMs += $dispMs
            }
        }
    }

    if ($frameTimesMs.Count -lt 5) { return $null }

    $totalFrames = $frameTimesMs.Count
    $totalTimeSec = ($frameTimesMs | Measure-Object -Sum).Sum / 1000.0
    $avgFps = [math]::Round($totalFrames / $totalTimeSec, 2)

    $minFrameTime = ($frameTimesMs | Measure-Object -Minimum).Minimum
    $maxFrameTime = ($frameTimesMs | Measure-Object -Maximum).Maximum

    $highFps = [math]::Round(1000.0 / $minFrameTime, 2)
    $lowFps = [math]::Round(1000.0 / $maxFrameTime, 2)

    # Sort descending: largest frame times (worst micro-stutter) at the top
    $sortedDescending = $frameTimesMs | Sort-Object -Descending
    $idx1Pct = [math]::Min($sortedDescending.Count - 1, [math]::Max(0, [int][math]::Floor($sortedDescending.Count * 0.01)))
    $idx01Pct = [math]::Min($sortedDescending.Count - 1, [math]::Max(0, [int][math]::Floor($sortedDescending.Count * 0.001)))

    $time1Pct = $sortedDescending[$idx1Pct]
    $time01Pct = $sortedDescending[$idx01Pct]

    $fps1PctLow = [math]::Round(1000.0 / $time1Pct, 2)
    $fps01PctLow = [math]::Round(1000.0 / $time01Pct, 2)

    # Calculate empirical hardware scanout from msBetweenDisplayChange
    $empiricalScanoutHz = 0.0
    $avgScanoutMs = 0.0
    if ($displayIntervalsMs.Count -gt 10) {
        $avgScanoutMs = ($displayIntervalsMs | Measure-Object -Average).Average
        if ($avgScanoutMs -gt 0) {
            $empiricalScanoutHz = [math]::Round(1000.0 / $avgScanoutMs, 4)
        }
    }

    $avgRenderTimeMs = if ($renderTimesMs.Count -gt 0) { [math]::Round(($renderTimesMs | Measure-Object -Average).Average, 3) } else { 0.0 }
    $avgDropRenderTimeMs = if ($dropRenderTimesMs.Count -gt 0) { [math]::Round(($dropRenderTimesMs | Measure-Object -Average).Average, 3) } else { 0.0 }

    # Detect VSync phase drift: drops occur with render completion well under VSync deadline (<5.0ms)
    $isVsyncDrift = ($droppedCount -gt 0 -and $droppedCount -lt [math]::Max(10, [int]($totalFrames * 0.05)) -and $avgDropRenderTimeMs -lt 5.0 -and ($empiricalScanoutHz -gt 0 -and [math]::Abs($empiricalScanoutHz - 60.0) -gt 0.02))

    # In Windows on ARM DWM Composed: Flip mode, PresentMon marks 100% of frames Dropped=1
    # because DWM display completion ETW events are handled through internal composition pipelines.
    $reportedDropped = if ($droppedCount -eq $totalFrames) {
        "0 (DWM Composed: Flip presentation)"
    } else {
        "$droppedCount frames"
    }

    return [PSCustomObject]@{
        TotalFrames         = $totalFrames
        AvgFps              = $avgFps
        HighFps             = $highFps
        LowFps              = $lowFps
        Fps1PctLow          = $fps1PctLow
        Fps01PctLow         = $fps01PctLow
        DroppedFrames       = $reportedDropped
        RawDroppedCount     = $droppedCount
        EmpiricalScanoutHz  = $empiricalScanoutHz
        AvgScanoutMs        = [math]::Round($avgScanoutMs, 4)
        AvgRenderTimeMs     = $avgRenderTimeMs
        AvgDropRenderTimeMs = $avgDropRenderTimeMs
        IsVsyncDrift        = $isVsyncDrift
    }
}

# ---------------------------------------------------------
# HELPER: Target Video Download Guidance
# ---------------------------------------------------------
function Show-VideoDownloadInstructions([string]$DestinationDir = "") {
    if ([string]::IsNullOrWhiteSpace($DestinationDir)) {
        $DestinationDir = $ScriptDir
    }
    $targetPath = Join-Path $DestinationDir "tears_of_steel_1080p.mov"
    Write-Host "`n------------------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host " REFERENCE VIDEO DOWNLOAD INSTRUCTIONS" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "The standard reproducible benchmark requires the Blender open movie clip:" -ForegroundColor White
    Write-Host "  File Name: tears_of_steel_1080p.mov" -ForegroundColor Yellow
    Write-Host "  Expected SHA-256 Checksum: 99486359be7e3681168a0fe94e1cbb0284c48b57b2a3ce7df4fa75e185987a15" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Download Steps:" -ForegroundColor Yellow
    Write-Host "  1. Visit the official Blender Mango Open Movie download page:" -ForegroundColor White
    Write-Host "     https://mango.blender.org/download/" -ForegroundColor Cyan
    Write-Host "  2. Under the video download options, select and download the 1080p release:" -ForegroundColor White
    Write-Host "     'Tears of Steel - 1080p' (approx. 560-600 MB .mov)" -ForegroundColor White
    Write-Host "  3. Save or rename the downloaded file to:" -ForegroundColor White
    Write-Host "     $targetPath" -ForegroundColor Green
    Write-Host "------------------------------------------------------------------------`n" -ForegroundColor Cyan
}

# ---------------------------------------------------------
# HELPER: Target Video SHA-256 Checksum Audit
# ---------------------------------------------------------
function Test-VideoChecksum {
    param(
        [string]$VideoPath,
        [string]$ExpectedHash = "99486359be7e3681168a0fe94e1cbb0284c48b57b2a3ce7df4fa75e185987a15",
        [switch]$SkipCheck
    )

    if (-not (Test-Path $VideoPath)) {
        Write-Host "`n[FATAL ERROR] Target video not found: '$VideoPath'!" -ForegroundColor Red
        Show-VideoDownloadInstructions -DestinationDir (Split-Path $VideoPath -Parent)
        return $false
    }

    $videoLeaf = Split-Path $VideoPath -Leaf

    if ($SkipCheck) {
        Write-Host "  -> Skipping video checksum verification as requested (-SkipVideoChecksum)." -ForegroundColor Gray
        $script:VideoSha256 = "Skipped"
        $script:VideoChecksumStatus = "Skipped by user flag (-SkipVideoChecksum)"
        return $true
    }

    Write-Host "  -> Auditing target video SHA-256 checksum ($videoLeaf)..." -ForegroundColor Yellow
    $actualHash = (Get-FileHash -Path $VideoPath -Algorithm SHA256).Hash.ToLower()
    $expectedLower = if ($ExpectedHash) { $ExpectedHash.Trim().ToLower() } else { "" }

    $script:VideoSha256 = $actualHash

    # If it is the tears_of_steel reference clip or a specific ExpectedHash was requested
    if ($videoLeaf -match '(?i)tears_of_steel' -or -not [string]::IsNullOrWhiteSpace($expectedLower)) {
        if ($actualHash -eq $expectedLower) {
            Write-Host "  -> Video Integrity Verified ($videoLeaf): $actualHash" -ForegroundColor Green
            $script:VideoChecksumStatus = "Verified Match ($actualHash)"
            return $true
        } else {
            Write-Host "`n[FATAL ERROR] Target video SHA-256 checksum mismatch!" -ForegroundColor Red
            Write-Host "  Target File: $VideoPath" -ForegroundColor Red
            Write-Host "  Expected:    $expectedLower" -ForegroundColor Red
            Write-Host "  Actual:      $actualHash" -ForegroundColor Red
            Write-Host "The video file appears corrupted, truncated, or modified." -ForegroundColor Yellow
            Show-VideoDownloadInstructions -DestinationDir (Split-Path $VideoPath -Parent)
            $script:VideoChecksumStatus = "MISMATCH (Expected: $expectedLower, Found: $actualHash)"
            return $false
        }
    } else {
        Write-Host "  -> Custom video clip detected ($videoLeaf). SHA-256: $actualHash" -ForegroundColor Gray
        $script:VideoChecksumStatus = "Custom Video ($actualHash)"
        return $true
    }
}

# ---------------------------------------------------------
# HELPER: Detect PotPlayer Binary Version & Linker Build Date
# ---------------------------------------------------------
function Get-PotPlayerVersionInfo([string]$Dir) {
    if (-not (Test-Path $Dir)) {
        return [PSCustomObject]@{
            DisplayString = "Unknown (Directory Not Found)"
            Version       = "Unknown"
            BuildDate     = "Unknown"
            ExePath       = ""
            DllPath       = ""
        }
    }

    $dllCandidates = @(
        (Join-Path $Dir "PotPlayer64.dll"),
        (Join-Path $Dir "PotPlayer.dll")
    )
    $exeCandidates = @(
        (Join-Path $Dir "PotPlayer64.exe"),
        (Join-Path $Dir "PotPlayer.exe")
    )

    $targetDll = $dllCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    $targetExe = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    $rawVersion = ""
    $buildDate = "Unknown"

    if ($targetDll) {
        $buildDate = Get-PeBuildDate -FilePath $targetDll
        $vi = (Get-Item $targetDll).VersionInfo
        if ($vi.FileVersion -and $vi.FileVersion -ne "0, 0, 0, 0") {
            $rawVersion = $vi.FileVersion
        } elseif ($vi.ProductVersion -and $vi.ProductVersion -ne "0.0.0.0") {
            $rawVersion = $vi.ProductVersion
        }
    }

    if ([string]::IsNullOrWhiteSpace($rawVersion) -and $targetExe) {
        if ($buildDate -eq "Unknown") {
            $buildDate = Get-PeBuildDate -FilePath $targetExe
        }
        $vi = (Get-Item $targetExe).VersionInfo
        if ($vi.FileVersion -and $vi.FileVersion -ne "0, 0, 0, 0") {
            $rawVersion = $vi.FileVersion
        } elseif ($vi.ProductVersion -and $vi.ProductVersion -ne "0.0.0.0") {
            $rawVersion = $vi.ProductVersion
        }
    }

    # Format version string: e.g. "1, 7, 23122, 0" -> "1.7.23122"
    $formattedVersion = if (-not [string]::IsNullOrWhiteSpace($rawVersion)) {
        $parts = $rawVersion -split "[,.]\s*" | Where-Object { $_ -ne "" }
        if ($parts.Count -ge 4 -and $parts[3] -eq "0") {
            ($parts[0..2] -join ".")
        } else {
            ($parts -join ".")
        }
    } else {
        "Unknown"
    }

    $display = if ($formattedVersion -ne "Unknown" -and $buildDate -ne "Unknown") {
        "$formattedVersion (Build: $buildDate)"
    } elseif ($formattedVersion -ne "Unknown") {
        $formattedVersion
    } elseif ($buildDate -ne "Unknown") {
        "Build $buildDate"
    } else {
        "Unknown"
    }

    return [PSCustomObject]@{
        DisplayString = $display
        Version       = $formattedVersion
        BuildDate     = $buildDate
        DllPath       = $targetDll
        ExePath       = $targetExe
    }
}

# ---------------------------------------------------------
# HELPER: Verify and Enforce PotPlayer Settings
# ---------------------------------------------------------
function Set-PotPlayerSettings {
    param(
        [string]$IniPath,
        [string]$ProfilePath,
        [string]$PotPlayerDir = "",
        [string]$MvToolsDir = "",
        [string]$GpuModeChoice = ""
    )

    if (-not (Test-Path $IniPath)) {
        Write-Error "PotPlayer INI file not found: $IniPath"
        return $false
    }

    Write-Host "  -> Auditing and enforcing deterministic PotPlayer configuration..." -ForegroundColor Yellow

    # Backup original INI if no backup exists
    $BakPath = "$IniPath.bak"
    if (-not (Test-Path $BakPath)) {
        Copy-Item -Path $IniPath -Destination $BakPath -Force
        Write-Host "     Created backup: $BakPath" -ForegroundColor Gray
    }

    if ([string]::IsNullOrWhiteSpace($PotPlayerDir)) {
        $PotPlayerDir = Split-Path $IniPath -Parent
    }

    # Prepare multi-line AviSynth preset file in PotPlayer\AviSynth\
    $AvsDir = Join-Path $PotPlayerDir "AviSynth"
    if (-not (Test-Path $AvsDir)) {
        New-Item -ItemType Directory -Path $AvsDir -Force | Out-Null
    }
    $TargetAvs = Join-Path $AvsDir "BenchmarkProfile.avs"

    $CpuDll = if ($MvToolsDir) { (Join-Path $MvToolsDir "mvtools2.dll").Replace('\', '/') } else { "mvtools2.dll" }
    $GpuDll = if ($MvToolsDir) { (Join-Path $MvToolsDir "mvtools2_d3d12.dll").Replace('\', '/') } else { "mvtools2_d3d12.dll" }

    $RawAvs = Get-Content -Path $ProfilePath -Raw

    # Dynamically inject or override USE_GPU if specified
    $activeGpu = $false
    if ($RawAvs -match '(?m)^\s*USE_GPU\s*=') {
        if ($GpuModeChoice -match '(?i)D3D12|GPU') {
            $RawAvs = $RawAvs -replace '(?m)^\s*USE_GPU\s*=.*$', 'USE_GPU = true'
            $activeGpu = $true
        } elseif ($GpuModeChoice -match '(?i)CPU|NEON') {
            $RawAvs = $RawAvs -replace '(?m)^\s*USE_GPU\s*=.*$', 'USE_GPU = false'
            $activeGpu = $false
        } else {
            # ProfileDefault or Auto fallback: inspect current value in script
            if ($RawAvs -match '(?m)^\s*USE_GPU\s*=\s*true') {
                $activeGpu = $true
            }
        }
    } elseif ($RawAvs -match '(?i)mvtools2_d3d12') {
        $activeGpu = $true
    }

    $script:ActiveMotionEngine = if ($activeGpu) {
        "Direct3D 12 GPU (mvtools2_d3d12.dll)"
    } else {
        "ARM64 CPU NEON (mvtools2.dll)"
    }

    # Substitute relative DLL paths with verified absolute paths
    $ResolvedAvs = $RawAvs -replace '(?i)"mvtools2_d3d12\.dll"', "`"$GpuDll`""
    $ResolvedAvs = $ResolvedAvs -replace '(?i)"mvtools2\.dll"', "`"$CpuDll`""

    # Write without BOM using ASCII encoding so AviSynth parses line 1 cleanly
    [System.IO.File]::WriteAllText($TargetAvs, $ResolvedAvs, [System.Text.Encoding]::ASCII)
    Write-Host "     Generated multi-line AviSynth profile: $TargetAvs" -ForegroundColor Gray
    Write-Host "     Active Acceleration Engine: $script:ActiveMotionEngine" -ForegroundColor Cyan

    $ImportScript = "Import(`"$($TargetAvs.Replace('\', '/'))`")"

    # Mandatory Benchmark Baseline by INI Section
    $SectionSettings = [ordered]@{
        "Positions" = [ordered]@{
            "VideoWindowState1"     = "0"    # Playlist subwindow closed/hidden
            "VideoWindowState2"     = "0"    # Control box subwindow closed/hidden
            "PlayListWindowVisible" = "0"    # Playlist explicitly hidden
            "ChatWindowVisible"     = "0"    # Chat explicitly hidden
            "IsZoomFull"            = "0"    # Fullscreen Keep Aspect Ratio (0 = No crop/stretch, proper scaling)
            "MainWindowState"       = "128"  # Fullscreen maximized state flag
        }
        "Settings" = [ordered]@{
            "AttachWindowIndex"     = "0"      # Detach/close side panel (playlist dock)
            "UseSideWindow"         = "0"      # Disable side docking window
            "StartScreenSize"       = "4"      # Start screen size: Fullscreen
            "PlayScreenSize"        = "5"      # Playback screen size: Fullscreen
            "PlayScreenSizeFirst"   = "1"      # Force fullscreen size on playback start
            "PlayScreenRatio"       = "0"      # Default Display Aspect Ratio (preserves native video geometry)
            "FullScreenFitMode"     = "0"      # AR Mode in Fullscreen Mode: 0 = Keep Aspect Ratio (Recommended)
            "FullScreenFitOverride" = "0"      # Fullscreen Override AR: 0 = Default Display AR
            "ScreenFitMode"         = "0"      # Windowed AR Mode: 0 = Keep Aspect Ratio
            "ScreenRatio"           = "0"      # Windowed Override AR: 0 = Default Display AR
            "ScreenFitBySize"       = "0"      # Adjust AR to Window Size: 0 = Disabled (Strict native AR, no stretch)
            "MultipleRunning"       = "0"      # Enforce single instance
            "VideoRen2"             = "15"     # Built-in Direct3D 11 Video Renderer (DXGI swapchain for PresentMon)
            "AvisynthUse"           = "1"      # AviSynth enabled
            "AvisynthSource"        = "1"      # AviSynth source filter enabled
            "UseSelfDxva"           = "1001"   # D3D11 DXVA Hardware Decode
            "SubShow"               = "0"      # Subtitles OFF (prevents rasterizer jitter)
            "TopMost"               = "2"      # On top while playing (prevents foreground occlusion)
            "DX11ResizeMode"        = "25"     # Bilinear/Bicubic D3D11 GPU resize
            "AudioPitchUse"         = "0"      # Audio time-stretching off
            "D3DFullScreenUi"       = "0"      # Overlay UI off during fullscreen
            "AvisynthScript"        = $ImportScript
        }
    }

    $IniLines = Get-Content -Path $IniPath -Encoding Unicode
    $UpdatedLines = [System.Collections.Generic.List[string]]::new()
    $CurrentSection = ""
    $ExistingSections = @{}
    $AppliedKeys = @{}
    $ChangesCount = 0

    foreach ($sec in $SectionSettings.Keys) {
        foreach ($k in $SectionSettings[$sec].Keys) {
            $AppliedKeys["$sec.$k"] = $false
        }
    }

    foreach ($line in $IniLines) {
        if ($line -match '^\s*\[([^\]]+)\]') {
            # Entering new section: flush missing keys from prior section
            if (-not [string]::IsNullOrWhiteSpace($CurrentSection) -and $SectionSettings.Contains($CurrentSection)) {
                foreach ($k in $SectionSettings[$CurrentSection].Keys) {
                    if (-not $AppliedKeys["$CurrentSection.$k"]) {
                        $targetVal = $SectionSettings[$CurrentSection][$k]
                        [void]$UpdatedLines.Add("$k=$targetVal")
                        $AppliedKeys["$CurrentSection.$k"] = $true
                        $ChangesCount++
                        Write-Host "     [ADDED] [$CurrentSection] $k=$targetVal" -ForegroundColor DarkYellow
                    }
                }
            }
            $CurrentSection = $Matches[1].Trim()
            $ExistingSections[$CurrentSection] = $true
            [void]$UpdatedLines.Add($line)
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($CurrentSection) -and $SectionSettings.Contains($CurrentSection)) {
            $matchedKey = $null
            foreach ($k in $SectionSettings[$CurrentSection].Keys) {
                if ($line -match "^\s*$([regex]::Escape($k))\s*=(.*)$") {
                    $matchedKey = $k
                    $currentVal = $Matches[1]
                    $targetVal = $SectionSettings[$CurrentSection][$k]
                    if ($k -ne "AvisynthScript" -and $currentVal -ne $targetVal) {
                        Write-Host "     [FIXED] [$CurrentSection] $($k): '$currentVal' -> '$targetVal'" -ForegroundColor DarkYellow
                        $ChangesCount++
                    }
                    [void]$UpdatedLines.Add("$k=$targetVal")
                    $AppliedKeys["$CurrentSection.$k"] = $true
                    break
                }
            }
            if ($matchedKey) { continue }
        }

        [void]$UpdatedLines.Add($line)
    }

    # Flush missing keys for the final section
    if (-not [string]::IsNullOrWhiteSpace($CurrentSection) -and $SectionSettings.Contains($CurrentSection)) {
        foreach ($k in $SectionSettings[$CurrentSection].Keys) {
            if (-not $AppliedKeys["$CurrentSection.$k"]) {
                $targetVal = $SectionSettings[$CurrentSection][$k]
                [void]$UpdatedLines.Add("$k=$targetVal")
                $AppliedKeys["$CurrentSection.$k"] = $true
                $ChangesCount++
                Write-Host "     [ADDED] [$CurrentSection] $k=$targetVal" -ForegroundColor DarkYellow
            }
        }
    }

    # Append any sections that didn't exist in the file at all
    foreach ($sec in $SectionSettings.Keys) {
        if (-not $ExistingSections.ContainsKey($sec)) {
            [void]$UpdatedLines.Add("[$sec]")
            foreach ($k in $SectionSettings[$sec].Keys) {
                $targetVal = $SectionSettings[$sec][$k]
                [void]$UpdatedLines.Add("$k=$targetVal")
                $AppliedKeys["$sec.$k"] = $true
                $ChangesCount++
                Write-Host "     [ADDED] [$sec] $k=$targetVal" -ForegroundColor DarkYellow
            }
        }
    }

    $UpdatedLines | Set-Content -Path $IniPath -Encoding Unicode
    Write-Host "  -> Settings Enforced ($ChangesCount adjustments made). Target script injected: $(Split-Path $ProfilePath -Leaf)" -ForegroundColor Green
    return $true
}

function Restore-PotPlayerSettings([string]$IniPath) {
    $BakPath = "$IniPath.bak"
    if (Test-Path $BakPath) {
        Move-Item -Path $BakPath -Destination $IniPath -Force
        Write-Host "  -> Restored original PotPlayer configuration." -ForegroundColor Green
    }
    $TargetAvs = Join-Path (Split-Path $IniPath -Parent) "AviSynth\BenchmarkProfile.avs"
    if (Test-Path $TargetAvs) {
        Remove-Item $TargetAvs -Force -ErrorAction SilentlyContinue
    }
}

# =========================================================
# MAIN EXECUTION FLOW
# =========================================================

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " PORTABLE POTPLAYER & MVTOOLS BENCHMARK HARNESS (v$Script:HarnessVersion)" -ForegroundColor Cyan
Write-Host "========================================================`n" -ForegroundColor Cyan

# ---------------------------------------------------------
# PRE-FLIGHT: AUDIT USB FLASH STORAGE DETECTION (METHOD 1)
# ---------------------------------------------------------
Confirm-StorageMediaSuitability -Paths @($ScriptDir, $VideoPath) -BypassPrompt:$IgnoreUsbWarning | Out-Null

# Check for PresentMon sibling
$PresentMonExe = Find-PresentMonExecutable
if ($PresentMonExe) {
    if ($IsAdmin) {
        Write-Host "[PRESENTMON READY] -> Full frame time distributions, High/Low/Avg FPS, and dropped frames enabled." -ForegroundColor Green
        Write-Host "  Binary: $PresentMonExe (Administrator privileges verified | MIT License: Benchmarks/PresentMon-LICENSE.txt)" -ForegroundColor Gray
    } else {
        Write-Host "[PRESENTMON FOUND] -> Binary: $PresentMonExe" -ForegroundColor Yellow
        Write-Warning "PowerShell is NOT running as Administrator! Windows ETW requires elevated privileges for PresentMon to capture Direct3D/DXGI frame events. To record High/Low/Avg FPS and 1% lows, launch PowerShell with 'Run as Administrator'."
    }
} else {
    Write-Host "[INFO] PresentMon.exe not found. To enable High/Low/Avg FPS and 1% low pacing, place 'PresentMon.exe' in '$ScriptDir'." -ForegroundColor DarkCyan
}

# ---------------------------------------------------------
# STEP 1: VERIFY OR ACQUIRE POTPLAYER INSTANCE
# ---------------------------------------------------------
$PotExe = Join-Path $PotPlayerDir "PotPlayer64.exe"

if (-not (Test-Path $PotExe)) {
    Write-Host "`n[1/7] PotPlayer Instance Not Detected at: $PotPlayerDir" -ForegroundColor Yellow

    # Check if automated acquisition is requested or should be offered
    $ShouldInstall = $AutoInstallPotPlayer
    if (-not $ShouldInstall -and $Host.UI -and $Host.UI.RawUI) {
        Write-Host "`n[MISSING COMPONENT] PotPlayer instance was not found!" -ForegroundColor Yellow
        Write-Host "PotPlayer is required for deterministic real-time video playback and frame pacing telemetry." -ForegroundColor Gray
        Write-Host "Official Kakao CDN: https://t1.daumcdn.net/potplayer/PotPlayer/Version/Latest/PotPlayerSetupARM64.exe`n" -ForegroundColor DarkCyan

        $Prompt = Read-Host "Would you like to automatically download and install official PotPlayer ARM64 now? [Y/n]"
        if ([string]::IsNullOrWhiteSpace($Prompt) -or $Prompt.Trim().ToLower() -eq 'y') {
            $ShouldInstall = $true
        }
    }

    if ($ShouldInstall) {
        $TargetInstallDir = if ($PotPlayerDir -ne (Join-Path $ScriptDir "PotPlayer")) { $PotPlayerDir } else { "" }
        $InstalledPath = Install-PotPlayerARM64 -TargetDir $TargetInstallDir -Elevated $IsAdmin
        if ($InstalledPath -and (Test-Path (Join-Path $InstalledPath "PotPlayer64.exe"))) {
            $PotPlayerDir = $InstalledPath
            $PotExe = Join-Path $PotPlayerDir "PotPlayer64.exe"
            Write-Host "  -> PotPlayer verified at: $PotExe" -ForegroundColor Green
        } else {
            Write-Host "`n[FATAL ERROR] Automated PotPlayer installation did not produce a valid PotPlayer64.exe!" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "`n[FATAL ERROR] PotPlayer instance was not found at: '$PotPlayerDir'!" -ForegroundColor Red
        Write-Host ""
        Write-Host "LICENSE & DOWNLOAD NOTICE:" -ForegroundColor Yellow
        Write-Host "PotPlayer is proprietary freeware developed by Kakao Corp. Its license prohibits redistribution." -ForegroundColor White
        Write-Host "Users must obtain PotPlayer directly from official channels:" -ForegroundColor White
        Write-Host "  Official Portal: https://potplayer.tv" -ForegroundColor Cyan
        Write-Host "  Official Direct ARM64 Installer: https://t1.daumcdn.net/potplayer/PotPlayer/Version/Latest/PotPlayerSetupARM64.exe" -ForegroundColor Cyan
        Write-Host "Setup options:" -ForegroundColor Yellow
        Write-Host "  1. Run with -AutoInstallPotPlayer to automatically download and silently install ARM64 release, OR" -ForegroundColor White
        Write-Host "  2. Install PotPlayer to default directory ('C:\Program Files\DAUM\PotPlayer'), OR" -ForegroundColor White
        Write-Host "  3. Copy your official portable PotPlayer folder into '$PotPlayerDir', OR" -ForegroundColor White
        Write-Host "  4. Specify your custom path via -PotPlayerDir 'C:\Path\To\PotPlayer'.`n" -ForegroundColor White
        exit 1
    }
} else {
    Write-Host "`n[1/7] Using existing PotPlayer instance at: $PotPlayerDir" -ForegroundColor Green
}

$PotIni = Join-Path $PotPlayerDir "PotPlayer64.ini"
if (-not (Test-Path $PotIni)) {
    Write-Host "  -> Initializing clean baseline PotPlayer64.ini in: $PotPlayerDir" -ForegroundColor Gray
    "[Settings]`r`nMultipleRunning=0`r`n" | Set-Content -Path $PotIni -Encoding Unicode
}


# ---------------------------------------------------------
# RESOLVE VIDEO INPUT
# ---------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($VideoPath)) {
    $defaultVideo = Join-Path $ScriptDir "tears_of_steel_1080p.mov"
    if (Test-Path $defaultVideo) {
        $VideoPath = $defaultVideo
    } else {
        $foundVideo = Get-ChildItem -Path $ScriptDir -Include "*.mov", "*.mp4", "*.mkv" -Recurse | Select-Object -First 1
        if ($foundVideo) {
            $VideoPath = $foundVideo.FullName
        }
    }
}

if ([string]::IsNullOrWhiteSpace($VideoPath) -or -not (Test-Path $VideoPath)) {
    Write-Host "`n[FATAL ERROR] Target video not found: '$VideoPath'!" -ForegroundColor Red
    Show-VideoDownloadInstructions -DestinationDir $ScriptDir
    exit 1
}
$VideoFullPath = (Resolve-Path $VideoPath).Path
Confirm-StorageMediaSuitability -Paths @($VideoFullPath) -BypassPrompt:$IgnoreUsbWarning | Out-Null

# ---------------------------------------------------------
# HARDWARE DETECTION & PROFILE / GPU MODE SELECTION
# ---------------------------------------------------------
$PlatformRec = Get-SystemPlatformRecommendation -RepoRoot $RepoRoot

$ChosenProfilePath = $null
$ChosenGpuMode = $GpuMode

$isConsoleHost = [Environment]::UserInteractive -and ($Host.UI.RawUI -ne $null)
if ($Interactive -or ([string]::IsNullOrWhiteSpace($AviSynthProfile) -and $isConsoleHost)) {
    $interactiveResult = Select-ProfileAndModeInteractive -RepoRoot $RepoRoot -Recommendation $PlatformRec -CurrentProfile $AviSynthProfile -CurrentGpuMode $GpuMode
    $ChosenProfilePath = $interactiveResult.ProfilePath
    $ChosenGpuMode = $interactiveResult.GpuMode
} else {
    $ChosenProfilePath = Resolve-AviSynthProfilePath -InputProfile $AviSynthProfile -RepoRoot $RepoRoot -RecommendedName $PlatformRec.RecommendedProfile -PlatformKey $PlatformRec.PlatformKey
    if ($ChosenGpuMode -eq "Auto" -or [string]::IsNullOrWhiteSpace($ChosenGpuMode)) {
        $ChosenGpuMode = $PlatformRec.RecommendedGpuMode
    }
}

if ([string]::IsNullOrWhiteSpace($ChosenProfilePath) -or -not (Test-Path $ChosenProfilePath)) {
    Write-Host "`n[FATAL ERROR] Could not resolve a valid AviSynth profile!" -ForegroundColor Red
    exit 1
}

$ProfileFullPath = (Resolve-Path $ChosenProfilePath).Path
$ResolvedGpuMode = $ChosenGpuMode

Write-Host "`n[BENCHMARK CONFIGURATION]" -ForegroundColor Green
Write-Host "  -> Profile:          $(Split-Path $ProfileFullPath -Leaf)" -ForegroundColor White
Write-Host "  -> Requested Engine: $ResolvedGpuMode" -ForegroundColor White
Write-Host "  -> Platform:         $($PlatformRec.PlatformLabel)" -ForegroundColor Gray

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ProfileName = [System.IO.Path]::GetFileNameWithoutExtension($ProfileFullPath)
$CsvLog = Join-Path $OutputDir "telemetry_${ProfileName}_$Timestamp.csv"
$PresentMonCsv = Join-Path $OutputDir "presentmon_${ProfileName}_$Timestamp.csv"
$PresentMonErrLog = Join-Path $OutputDir "presentmon_err_${ProfileName}_$Timestamp.log"
$ReportLog = Join-Path $OutputDir "report_${ProfileName}_$Timestamp.txt"

# ---------------------------------------------------------
# STEP 2: AUDIT POTPLAYER VERSION & TEST ASSETS
# ---------------------------------------------------------
Write-Host "`n[2/7] Auditing PotPlayer Version & Test Asset Integrity..." -ForegroundColor Yellow
$PotPlayerInfo = Get-PotPlayerVersionInfo -Dir $PotPlayerDir
Write-Host "  -> PotPlayer Version: $($PotPlayerInfo.DisplayString)" -ForegroundColor Green

$VideoChecksumPassed = Test-VideoChecksum -VideoPath $VideoFullPath -ExpectedHash $ExpectedVideoHash -SkipCheck:$SkipVideoChecksum
if (-not $VideoChecksumPassed) {
    exit 1
}

# ---------------------------------------------------------
# STEP 3: MVTOOLS BINARY VALIDATION & BUILD DATE AUDIT
# ---------------------------------------------------------
Write-Host "`n[3/7] Auditing MVTools Plugins in: $MvToolsDir..." -ForegroundColor Yellow
$MvToolsCpuPath = Join-Path $MvToolsDir "mvtools2.dll"
$MvToolsGpuPath = Join-Path $MvToolsDir "mvtools2_d3d12.dll"

# Assert that required MVTools binaries exist
if (-not (Test-Path $MvToolsCpuPath)) {
    Write-Host "`n[FATAL ERROR] Required MVTools CPU binary 'mvtools2.dll' not found in '$MvToolsDir'!" -ForegroundColor Red
    Write-Host "Please build or place 'mvtools2.dll' in '$MvToolsDir'.`n" -ForegroundColor Yellow
    exit 1
}

if ($ResolvedGpuMode -eq "GPU" -or $ResolvedGpuMode -eq "D3D12") {
    if (-not (Test-Path $MvToolsGpuPath)) {
        Write-Host "`n[FATAL ERROR] Direct3D 12 GPU mode requested, but 'mvtools2_d3d12.dll' was not found in '$MvToolsDir'!" -ForegroundColor Red
        Write-Host "Please build or place 'mvtools2_d3d12.dll' in '$MvToolsDir'.`n" -ForegroundColor Yellow
        exit 1
    }
}

$CpuMeta = Get-MvToolsMetadata -DllPath $MvToolsCpuPath
$GpuMeta = Get-MvToolsMetadata -DllPath $MvToolsGpuPath

if ($CpuMeta) {
    Write-Host "  -> mvtools2.dll (CPU/NEON):" -ForegroundColor White
    Write-Host "     Version: $($CpuMeta.FileVersion) | Product: $($CpuMeta.ProductVersion)" -ForegroundColor Gray
    Write-Host "     PE Linker Build Date: $($CpuMeta.PeBuildDate)" -ForegroundColor Gray
    Write-Host "     SHA-256: $($CpuMeta.SHA256)" -ForegroundColor Gray
}

if ($GpuMeta) {
    Write-Host "  -> mvtools2_d3d12.dll (Direct3D 12 GPU - Experimental Preview):" -ForegroundColor White
    Write-Host "     Version: $($GpuMeta.FileVersion) | Product: $($GpuMeta.ProductVersion)" -ForegroundColor Gray
    Write-Host "     PE Linker Build Date: $($GpuMeta.PeBuildDate)" -ForegroundColor Gray
    Write-Host "     SHA-256: $($GpuMeta.SHA256)" -ForegroundColor Gray
} else {
    Write-Host "  -> mvtools2_d3d12.dll: Not found in $MvToolsDir (CPU-only execution)" -ForegroundColor Gray
}

# ---------------------------------------------------------
# STEP 4: POTPLAYER SETTINGS VERIFICATION & SINGLE-INSTANCE
# ---------------------------------------------------------
Write-Host "`n[4/7] Verifying & Injecting Deterministic Configuration..." -ForegroundColor Yellow
$SettingsReady = Set-PotPlayerSettings -IniPath $PotIni -ProfilePath $ProfileFullPath -PotPlayerDir $PotPlayerDir -MvToolsDir $MvToolsDir -GpuModeChoice $ResolvedGpuMode
if (-not $SettingsReady) {
    Write-Host "`n[FATAL ERROR] Failed to configure PotPlayer settings.`n" -ForegroundColor Red
    exit 1
}

# Guarantee single instance purity before proceeding
Ensure-SinglePotPlayerInstance -TargetPid 0 | Out-Null

# ---------------------------------------------------------
# STEP 5: MEMORY HEADROOM & FREE RAM AUDIT
# ---------------------------------------------------------
Write-Host "`n[5/7] Auditing Physical RAM Headroom..." -ForegroundColor Yellow
$ScriptRamRequirementMb = Get-AviSynthMemoryRequirement -ProfilePath $ProfileFullPath -GpuModeChoice $ResolvedGpuMode
$TotalRequiredRamMb = $ScriptRamRequirementMb + $BufferHeadroomMb

# Trigger garbage collection to reclaim inactive working sets
[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()

$OsInfo = Get-CimInstance Win32_OperatingSystem
$CurrentFreeRamMb = [math]::Round($OsInfo.FreePhysicalMemory / 1KB, 0)
$TotalPhysicalRamMb = [math]::Round($OsInfo.TotalVisibleMemorySize / 1KB, 0)

Write-Host "  -> System Total RAM: $TotalPhysicalRamMb MB" -ForegroundColor Gray
Write-Host "  -> Script SetMemoryMax: $ScriptRamRequirementMb MB" -ForegroundColor Gray
Write-Host "  -> Required Free RAM: $TotalRequiredRamMb MB (Script + $BufferHeadroomMb MB Player/GPU UMA headroom)" -ForegroundColor Gray
$RamColor = if ($CurrentFreeRamMb -ge $TotalRequiredRamMb) { "Green" } else { "Red" }
Write-Host "  -> Available Free RAM: $CurrentFreeRamMb MB" -ForegroundColor $RamColor

# Determine if device is memory-constrained (<= 4.5GB RAM, low headroom, or explicit switch)
$isMemoryConstrained = $MemoryConstrained.IsPresent -or ($TotalPhysicalRamMb -le 4608) -or ($CurrentFreeRamMb -lt $TotalRequiredRamMb)
$script:IsMemoryConstrained = $isMemoryConstrained
$script:TotalPhysicalRamMb = $TotalPhysicalRamMb
$script:InitialFreeRamMb = $CurrentFreeRamMb
$script:MemoryConstrainedTag = if ($isMemoryConstrained) {
    "Yes (Total RAM: $TotalPhysicalRamMb MB, Available: $CurrentFreeRamMb MB)"
} else {
    "No (Total RAM: $TotalPhysicalRamMb MB, Available: $CurrentFreeRamMb MB)"
}

if ($isMemoryConstrained) {
    Write-Host "  -> Device Classification: Memory-Constrained Hardware ($TotalPhysicalRamMb MB Total RAM)" -ForegroundColor DarkYellow
}

if ($CurrentFreeRamMb -lt $TotalRequiredRamMb) {
    Write-Host "`n[WARNING] Low Physical RAM Headroom Detected!" -ForegroundColor Yellow
    Write-Host "  -> Available Free RAM: $CurrentFreeRamMb MB | Recommended Free RAM: $TotalRequiredRamMb MB" -ForegroundColor Yellow
    Write-Host "  POTENTIAL BENCHMARK IMPACT:" -ForegroundColor Yellow
    Write-Host "  Insufficient physical RAM can cause Windows memory compression and SSD pagefile swapping," -ForegroundColor White
    Write-Host "  introducing hard latency spikes (5-25ms) that may artificially skew 60fps frame pacing." -ForegroundColor White
    Write-Host "  On memory-constrained devices (e.g. 4GB RAM), benchmarks can proceed but results should" -ForegroundColor White
    Write-Host "  be evaluated with memory pressure in mind.`n" -ForegroundColor White

    if ($IgnoreRamWarning) {
        Write-Host "  -> -IgnoreRamWarning flag specified. Continuing benchmark despite low memory headroom...`n" -ForegroundColor DarkYellow
    } else {
        $isInteractiveHost = [Environment]::UserInteractive -and ($Host.UI.RawUI -ne $null) -and (-not [Console]::IsInputRedirected)
        if (-not $isInteractiveHost) {
            Write-Host "[ERROR] Low RAM headroom detected in non-interactive/redirected execution mode. Aborting benchmark." -ForegroundColor Red
            Write-Host "To allow execution on memory-constrained devices in automated scripts, re-run with -IgnoreRamWarning.`n" -ForegroundColor Yellow
            Restore-PotPlayerSettings -IniPath $PotIni
            exit 1
        }

        Write-Host "Do you want to continue running the benchmark? [y/N]: " -NoNewline -ForegroundColor Cyan
        $userChoice = Read-Host
        if ($userChoice -notmatch '^(?i)y(es)?$') {
            Write-Host "`n[BENCHMARK ABORTED] Execution stopped by user due to low memory headroom.`n" -ForegroundColor Red
            Restore-PotPlayerSettings -IniPath $PotIni
            exit 1
        }
        Write-Host "  -> Continuing benchmark despite low memory headroom as confirmed by user...`n" -ForegroundColor DarkYellow
    }
}

# ---------------------------------------------------------
# STEP 6: ENVIRONMENTAL CONTROLS & SYSTEM LOAD NORMALIZATION
# ---------------------------------------------------------
Write-Host "`n[6/7] Enforcing Environmental Controls & Idle Normalization..." -ForegroundColor Yellow

# Display Hardware Refresh Rate Inspection
$script:DisplayInfo = Get-DisplayRefreshInfo
if ($script:DisplayInfo.IsIntegerRate) {
    Write-Host "  -> Display Refresh Rate: $($script:DisplayInfo.RefreshRateHz.ToString('N2')) Hz ($($script:DisplayInfo.RationalString)) on '$($script:DisplayInfo.MonitorName)' [Integer / Zero-Drift Compatible]" -ForegroundColor Green
} else {
    $hzDiff = [math]::Abs(60.0 - $script:DisplayInfo.RefreshRateHz)
    $driftIntervalSec = if ($hzDiff -gt 0.001) { [math]::Round(1.0 / $hzDiff, 1) } else { 999.0 }
    $expectedDrops = if ($driftIntervalSec -gt 0) { [math]::Max(1, [math]::Round(($TestDurationSeconds - $WarmupSeconds) / $driftIntervalSec)) } else { 0 }

    Write-Host "`n[WARNING] Non-Integer Display Refresh Rate Detected: $($script:DisplayInfo.RefreshRateHz.ToString('N3')) Hz ($($script:DisplayInfo.RationalString))!" -ForegroundColor Yellow
    Write-Host "  Display Device: $($script:DisplayInfo.MonitorName)" -ForegroundColor Yellow
    Write-Host "  POTENTIAL BENCHMARK IMPACT (VSYNC PHASE DRIFT):" -ForegroundColor Yellow
    Write-Host "  The AviSynth interpolation profile outputs frames at strictly 60.000 FPS." -ForegroundColor White
    Write-Host "  Because your display scans at $($script:DisplayInfo.RefreshRateHz.ToString('N3')) Hz (not a whole number like 60, 100, 120, 144 Hz)," -ForegroundColor White
    Write-Host "  an excess frame accumulates in the presentation queue every ~$driftIntervalSec seconds." -ForegroundColor White
    Write-Host "  The DXGI compositor will discard this excess frame (~$expectedDrops drops per $($TestDurationSeconds - $WarmupSeconds)s run) to maintain audio sync," -ForegroundColor White
    Write-Host "  artificially inflating dropped frames despite 0% compute or GPU lag." -ForegroundColor White
    Write-Host "  RECOMMENDED ACTION:" -ForegroundColor Yellow
    Write-Host "  To achieve true 0 dropped frames, set your display refresh rate to an integer 60.00 Hz" -ForegroundColor White
    Write-Host "  in Windows Settings -> System -> Display -> Advanced display, or benchmark on an external 60/120/144 Hz monitor.`n" -ForegroundColor White
}

# AC Power Check
$Battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue
if ($Battery) {
    $IsAcOnline = (Get-CimInstance -Namespace "root\wmi" -ClassName "BatteryStatus" -ErrorAction SilentlyContinue).PowerOnline
    if ($IsAcOnline -eq $false) {
        Write-Host "`n[FATAL ERROR] Device is running on battery power!" -ForegroundColor Red
        Write-Host "Connect AC adapter for reproducible benchmarking without battery clock throttling.`n" -ForegroundColor Yellow
        Restore-PotPlayerSettings -IniPath $PotIni
        exit 1
    }
    $Charge = $Battery.EstimatedChargeRemaining
    Write-Host "  -> AC Connected. Battery: $Charge%" -ForegroundColor Green
    if ($Charge -lt 90) {
        Write-Warning "Battery is < 90%. Internal battery charging heat may affect sustained performance."
    }
}

# Power Plan (Save & switch to High Performance)
$ActiveSchemeRaw = (powercfg /getactivescheme)
$OriginalSchemeGuid = ([regex]::Match($ActiveSchemeRaw, '(?i)[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}')).Value
$HighPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
powercfg /setactive $HighPerfGuid
Write-Host "  -> Switched to High Performance mode." -ForegroundColor Green

# Kill Background Apps
$NoisyProcesses = @("chrome", "msedge", "firefox", "brave", "opera", "teams", "ms-teams", "slack", "discord", "onedrive", "dropbox", "spotify", "steam")
$KilledCount = 0
foreach ($p in $NoisyProcesses) {
    $found = Get-Process -Name $p -ErrorAction SilentlyContinue
    if ($found) {
        Stop-Process -Name $p -Force -ErrorAction SilentlyContinue
        $KilledCount++
    }
}
Write-Host "  -> Quiesced $KilledCount background processes." -ForegroundColor Green

# Disable Network
$DisabledAdapters = @()
if (-not $SkipNetworkDisable) {
    $Adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.InterfaceDescription -match "Wi-Fi|Wireless|Ethernet" }
    foreach ($adapter in $Adapters) {
        Write-Host "  -> Silencing adapter: $($adapter.Name)" -ForegroundColor Gray
        Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue
        $DisabledAdapters += $adapter.Name
    }
}

# System Load Normalization (Wait until overall CPU <= Target & GPU <= Target)
Write-Host "  -> Waiting for system load stabilization (Target: CPU <= $TargetIdleCpuPercent%, GPU <= $TargetIdleGpuPercent% for $IdleStabilitySeconds s)..." -ForegroundColor Gray

$StableCount = 0
$IdleWatch = [System.Diagnostics.Stopwatch]::StartNew()

while ($IdleWatch.Elapsed.TotalSeconds -lt $IdleTimeoutSeconds) {
    $metrics = Get-SystemMetrics
    $curCpu = $metrics.CpuPercent
    $curGpu = $metrics.GpuTotalPercent

    if ($curCpu -le $TargetIdleCpuPercent -and $curGpu -le $TargetIdleGpuPercent) {
        $StableCount++
        Write-Host "     [STABILIZING $StableCount/$IdleStabilitySeconds s] CPU: $curCpu% | GPU: $curGpu%" -ForegroundColor DarkGreen
        if ($StableCount -ge $IdleStabilitySeconds) {
            break
        }
    } else {
        $StableCount = 0
        Write-Host "     [WAITING FOR IDLE] CPU: $curCpu% (Target: <=$TargetIdleCpuPercent%) | GPU: $curGpu% (Target: <=$TargetIdleGpuPercent%)" -ForegroundColor DarkGray
    }
    Start-Sleep -Seconds 1
}

if ($StableCount -ge $IdleStabilitySeconds) {
    Write-Host "  -> System Idle Verified: CPU and GPU stabilized cleanly." -ForegroundColor Green
} else {
    Write-Warning "System load did not fully stabilize within $IdleTimeoutSeconds s (Last: CPU $curCpu%, GPU $curGpu%). Proceeding with test."
}

# ---------------------------------------------------------
# STEP 7: RUN TEST & RECORD TELEMETRY
# ---------------------------------------------------------
Write-Host "`n[7/7] Executing Test Run ($TestDurationSeconds s total, $WarmupSeconds s warmup)..." -ForegroundColor Yellow

try {
    $PotArgs = "`"$VideoFullPath`" /seek=00:01:00 /play"
    $PotProcess = Start-Process -FilePath $PotExe -WorkingDirectory $PotPlayerDir -ArgumentList $PotArgs -PassThru

    Write-Host "  -> PotPlayer launched (PID: $($PotProcess.Id))." -ForegroundColor Green
    
    # Enforce strictly only this instance runs
    Ensure-SinglePotPlayerInstance -TargetPid $PotProcess.Id | Out-Null

    # Allow window subsystem initialization
    Start-Sleep -Milliseconds 1500

    $RemainingWarmup = [math]::Max(0, $WarmupSeconds - 2)
    Write-Host "  -> Discarding initial $WarmupSeconds s warmup window ($RemainingWarmup s remaining)..." -ForegroundColor Gray
    if ($RemainingWarmup -gt 0) {
        Start-Sleep -Seconds $RemainingWarmup
    }

    # Launch PresentMon if available
    $PresentMonProcess = $null
    $SampleWindow = $TestDurationSeconds - $WarmupSeconds
    if ($PresentMonExe) {
        Write-Host "  -> Launching PresentMon session to capture frame times..." -ForegroundColor Green
        $PmTargetName = [System.IO.Path]::GetFileName($PotExe)
        $PmArgs = @(
            "--process_name", "$PmTargetName",
            "--output_file", "$PresentMonCsv",
            "--timed", "$SampleWindow",
            "--no_console_stats",
            "--terminate_after_timed",
            "--v1_metrics",
            "--stop_existing_session"
        )
        $PresentMonProcess = Start-Process -FilePath $PresentMonExe -ArgumentList $PmArgs -PassThru -WindowStyle Hidden -RedirectStandardError $PresentMonErrLog
    }

    Write-Host "  -> Logging telemetry samples to $CsvLog..." -ForegroundColor Green
    $Samples = @()
    $InstanceAnomalies = 0

    for ($i = 0; $i -lt $SampleWindow; $i++) {
        # Verify single-instance status each second
        $isSingle = Ensure-SinglePotPlayerInstance -TargetPid $PotProcess.Id
        if (-not $isSingle) { $InstanceAnomalies++ }

        $metrics = Get-SystemMetrics -PotProcessId $PotProcess.Id
        $MemMb = 0
        try {
            $pinfo = Get-Process -Id $PotProcess.Id -ErrorAction Stop
            $MemMb = [math]::Round($pinfo.WorkingSet64 / 1MB, 1)
        } catch {}

        $Samples += [PSCustomObject]@{
            Second          = $i + 1
            SystemCpuPct    = $metrics.CpuPercent
            SystemGpuPct    = $metrics.GpuTotalPercent
            PotPlayerGpuPct = $metrics.PotGpuPercent
            PotPlayerMemMb  = $MemMb
            AvailableRamMb  = $metrics.AvailRamMb
            PageSwapsPerSec = $metrics.PagesPerSec
            PotInstances    = $metrics.PotInstances
        }

        Start-Sleep -Seconds 1
    }

    $Samples | Export-Csv -Path $CsvLog -NoTypeInformation

    # Wait for PresentMon to flush if it was running
    if ($PresentMonProcess -and -not $PresentMonProcess.HasExited) {
        Write-Host "  -> Finalizing PresentMon session..." -ForegroundColor Gray
        $PresentMonProcess.WaitForExit(10000) | Out-Null
    }

    # Summarize Metrics
    $AvgCpu = [math]::Round(($Samples | Measure-Object -Property SystemCpuPct -Average).Average, 1)
    $PeakCpu = [math]::Round(($Samples | Measure-Object -Property SystemCpuPct -Maximum).Maximum, 1)
    $AvgGpu = [math]::Round(($Samples | Measure-Object -Property SystemGpuPct -Average).Average, 1)
    $PeakGpu = [math]::Round(($Samples | Measure-Object -Property SystemGpuPct -Maximum).Maximum, 1)
    $AvgPotGpu = [math]::Round(($Samples | Measure-Object -Property PotPlayerGpuPct -Average).Average, 1)
    $AvgMem = [math]::Round(($Samples | Measure-Object -Property PotPlayerMemMb -Average).Average, 1)
    $MinAvailRam = ($Samples | Measure-Object -Property AvailableRamMb -Minimum).Minimum
    $PeakPageSwaps = ($Samples | Measure-Object -Property PageSwapsPerSec -Maximum).Maximum
    $AvgPageSwaps = [math]::Round(($Samples | Measure-Object -Property PageSwapsPerSec -Average).Average, 1)

    $PagingStatus = if ($PeakPageSwaps -gt 5) {
        "WARNING: Active pagefile disk swapping detected (Peak: $PeakPageSwaps/s)! Results may be skewed by memory contention."
    } else {
        "Clean (Zero/minimal disk swapping: Peak $PeakPageSwaps/s, Avg $AvgPageSwaps/s)"
    }

    $InstanceStatus = if ($InstanceAnomalies -eq 0) {
        "Verified (Strictly 1 single instance: PID $($PotProcess.Id))"
    } else {
        "WARNING: $InstanceAnomalies duplicate instance anomaly events intercepted and resolved."
    }

    # Parse PresentMon Frame Rate Results if available
    $FpsReportSection = ""
    $PmData = Get-PresentMonMetrics -CsvPath $PresentMonCsv
    if ($PmData) {
        $scanoutLine = if ($PmData.EmpiricalScanoutHz -gt 0) {
            "`n- Physical Panel Scanout: $($PmData.EmpiricalScanoutHz.ToString('N2')) Hz ($($PmData.AvgScanoutMs.ToString('N3')) ms scanout interval)"
        } else { "" }

        $dropClassLine = ""
        if ($PmData.RawDroppedCount -gt 0) {
            if ($PmData.IsVsyncDrift) {
                $driftSec = [math]::Round(1.0 / [math]::Abs(60.0 - $PmData.EmpiricalScanoutHz), 1)
                $dropClassLine = "`n- Drop Classification:    VSync Phase Drift / DXGI Flip Discard (Render latency on drops: $($PmData.AvgDropRenderTimeMs.ToString('N2')) ms; zero compute lag). Physical panel ($($PmData.EmpiricalScanoutHz.ToString('N2')) Hz) runs slower than video presentation (60.00 FPS), causing 1 excess frame every ~$driftSec s to be discarded by the DXGI swapchain to preserve audio sync."
            } else {
                $dropClassLine = "`n- Drop Classification:    Compute / Pipeline Latency Stall (Render latency on drops: $($PmData.AvgDropRenderTimeMs.ToString('N2')) ms)."
            }
        }

        $refreshNotice = ""
        if (($script:DisplayInfo -and -not $script:DisplayInfo.IsIntegerRate) -or $PmData.IsVsyncDrift) {
            $effectiveHz = if ($PmData.EmpiricalScanoutHz -gt 0) { $PmData.EmpiricalScanoutHz } else { $script:DisplayInfo.RefreshRateHz }
            $hzDiff = [math]::Abs(60.0 - $effectiveHz)
            $driftIntervalSec = if ($hzDiff -gt 0.001) { [math]::Round(1.0 / $hzDiff, 1) } else { 999.0 }
            $expectedDrops = if ($driftIntervalSec -gt 0) { [math]::Max(1, [math]::Round($SampleWindow / $driftIntervalSec)) } else { 0 }
            $refreshNotice = "`n- Refresh Pacing Notice: Non-integer display refresh rate ($($effectiveHz.ToString('N2')) Hz) detected. Periodic frame drops (~$expectedDrops drops expected per $SampleWindow s run) are caused by VSync phase drift between the 60.000 FPS video clock and monitor scanout, rather than compute or GPU bottlenecks."
        }
        $FpsReportSection = @"
5. FRAME RATE & PACING TELEMETRY (via PresentMon)
- Total Frames Presented: $($PmData.TotalFrames) frames
- Average Frame Rate:     $($PmData.AvgFps) fps
- Highest (Peak) FPS:     $($PmData.HighFps) fps
- Lowest (Min) FPS:       $($PmData.LowFps) fps
- 1% Low FPS (Microstutter): $($PmData.Fps1PctLow) fps
- 0.1% Low FPS:           $($PmData.Fps01PctLow) fps
- Dropped Frames:         $($PmData.DroppedFrames)$refreshNotice$scanoutLine$dropClassLine
"@
        if (Test-Path $PresentMonErrLog) { Remove-Item $PresentMonErrLog -Force -ErrorAction SilentlyContinue }
    } elseif ($PresentMonExe) {
        $AdminNotice = if (-not $IsAdmin) {
            "Windows ETW kernel trace sessions require Administrator elevation. Please launch PowerShell using 'Run as Administrator' to capture Direct3D/DXGI frame events."
        } else {
            "PresentMon executed at '$PresentMonExe' for PotPlayer (PID $($PotProcess.Id)), but no frame presentation events were captured. Ensure the video renderer is actively presenting frames to the display."
        }
        $errDetail = ""
        if (Test-Path $PresentMonErrLog) {
            $rawErr = (Get-Content -Path $PresentMonErrLog -Raw -ErrorAction SilentlyContinue)
            if (-not [string]::IsNullOrWhiteSpace($rawErr)) {
                $errDetail = "`n- Diagnostic Output: " + ($rawErr.Trim() -replace "`r?`n", " ")
            }
        }
        $FpsReportSection = @"
5. FRAME RATE & PACING TELEMETRY (via PresentMon)
- Status: PresentMon metrics not available.
- Executable: $PresentMonExe
- Note: $AdminNotice$errDetail
"@
    } else {
        $FpsReportSection = @"
5. FRAME RATE & PACING TELEMETRY
- Status: PresentMon executable not found.
- Note: Place 'PresentMon.exe' in '$ScriptDir' to record sub-millisecond High/Low/Avg FPS and 1% Lows.
"@
    }

    $ProfileRevision = "1.0.0"
    if (Test-Path $ProfileFullPath) {
        $avsHead = Get-Content -Path $ProfileFullPath -TotalCount 15 -ErrorAction SilentlyContinue
        foreach ($line in $avsHead) {
            if ($line -match '(?i)^\s*#\s*Revision:\s*([^\r\n]+)') {
                $ProfileRevision = $Matches[1].Trim()
                break
            }
        }
    }

    $Report = @"
================================================================================
 REPRODUCIBLE BENCHMARK AUDIT REPORT (Harness v$Script:HarnessVersion)
 Generated: $Timestamp
================================================================================

1. TEST ENVIRONMENT & INPUTS
- Benchmark Harness: MvToolsBenchmark-Start.ps1 (v$Script:HarnessVersion)
- Target Video: $VideoFullPath
- Target Video SHA-256: $script:VideoSha256
- Video Asset Integrity: $script:VideoChecksumStatus
- AviSynth Profile: $(Split-Path $ProfileFullPath -Leaf) (Revision: $ProfileRevision)
- Active Motion Engine: $script:ActiveMotionEngine
- Host Platform: $($PlatformRec.PlatformLabel)
- Memory-Constrained Device: $script:MemoryConstrainedTag
- Display Device: $(if ($script:DisplayInfo) { "$($script:DisplayInfo.MonitorName) ($($script:DisplayInfo.RefreshRateHz.ToString('N3')) Hz, $($script:DisplayInfo.RationalString))" } else { "N/A" })
- Display Refresh Status: $(if ($script:DisplayInfo) { if ($script:DisplayInfo.IsIntegerRate) { "Integer Rate ($($script:DisplayInfo.RoundedHz) Hz - Zero VSync Drift)" } else { "Non-Integer / Fractional Rate ($($script:DisplayInfo.RefreshRateHz.ToString('N3')) Hz - VSync Phase Drift Expected)" } } else { "N/A" })
- PotPlayer Instance: $PotPlayerDir (PID: $($PotProcess.Id))
- PotPlayer Version: $($PotPlayerInfo.DisplayString)
- Active Duration: $SampleWindow s (Post-$WarmupSeconds s warmup)

2. ASSET & BINARY INTEGRITY AUDIT
- PotPlayer Version: $($PotPlayerInfo.DisplayString)
- Video Checksum: $script:VideoChecksumStatus
- mvtools2.dll:
    Version:        $($CpuMeta.FileVersion)
    PE Build Date:  $($CpuMeta.PeBuildDate)
    SHA-256:        $($CpuMeta.SHA256)
- mvtools2_d3d12.dll (Direct3D 12 GPU - Experimental Preview):
    Version:        $(if ($GpuMeta) { $GpuMeta.FileVersion } else { "N/A" })
    PE Build Date:  $(if ($GpuMeta) { $GpuMeta.PeBuildDate } else { "N/A" })
    SHA-256:        $(if ($GpuMeta) { $GpuMeta.SHA256 } else { "N/A" })
- PresentMon Telemetry Engine: $(if ($PresentMonExe) { "$PresentMonExe (Intel PresentMon, MIT License: Benchmarks/PresentMon-LICENSE.txt)" } else { "Not Present" })

3. DETERMINISTIC POTPLAYER CONFIGURATION ENFORCED
- Acceleration Mode: $script:ActiveMotionEngine (Requested: $ResolvedGpuMode)
- D3D11 DXVA Hardware Decode: UseSelfDxva=1001 (Forced)
- Video Renderer: Direct3D 11 (Bilinear/Bicubic DX11ResizeMode=25)
- AviSynth Subsystem: AvisynthUse=1, AvisynthSource=1 (Forced)
- Subtitles: Disabled (SubShow=0)
- Always on Top: Enforced on playback (TopMost=2)
- Fullscreen & Aspect Ratio: Enforced Keep AR (FullScreenFitMode=0, FullScreenFitOverride=0, ScreenFitMode=0, ScreenFitBySize=0, IsZoomFull=0, MainWindowState=128)
- Playlist & Side Panels: Hidden on open (AttachWindowIndex=0, UseSideWindow=0, VideoWindowState1=0, PlayListWindowVisible=0)
- Single-Instance Mode: MultipleRunning=0 (Forced)
- Single-Instance Status: $InstanceStatus

4. MEMORY & PAGING INTEGRITY
- Total System Physical RAM: $script:TotalPhysicalRamMb MB
- Initial Available RAM: $script:InitialFreeRamMb MB
- Memory-Constrained Classification: $script:MemoryConstrainedTag
- Profile SetMemoryMax: $ScriptRamRequirementMb MB
- Buffer & UMA Headroom: $BufferHeadroomMb MB
- Min Available RAM During Run: $MinAvailRam MB
- Page Swapping Status: $PagingStatus

$FpsReportSection

6. PERFORMANCE TELEMETRY SUMMARY
- Average System CPU Load: $AvgCpu% (Peak: $PeakCpu%)
- Average System GPU Load: $AvgGpu% (Peak: $PeakGpu%)
- Average PotPlayer GPU Load: $AvgPotGpu%
- Average PotPlayer Working Set: $AvgMem MB

Telemetry CSV: $CsvLog
PresentMon CSV: $(if (Test-Path $PresentMonCsv) { $PresentMonCsv } else { "N/A" })
================================================================================
"@
    Write-Host "`n$Report" -ForegroundColor Cyan
    $Report | Out-File -FilePath $ReportLog -Encoding UTF8

} finally {
    # ---------------------------------------------------------
    # TEARDOWN & RESTORATION (Guaranteed execution)
    # ---------------------------------------------------------
    Write-Host "`n[CLEANUP] Restoring System Environment & Configuration..." -ForegroundColor Yellow

    # Stop PresentMon if running
    if ($PresentMonProcess -and -not $PresentMonProcess.HasExited) {
        Write-Host "  -> Stopping PresentMon session..." -ForegroundColor Gray
        Stop-Process -Id $PresentMonProcess.Id -Force -ErrorAction SilentlyContinue
    }

    # Stop PotPlayer
    if ($PotProcess -and -not $PotProcess.HasExited) {
        Write-Host "  -> Terminating PotPlayer test process..." -ForegroundColor Gray
        Stop-Process -Id $PotProcess.Id -Force -ErrorAction SilentlyContinue
    }

    # Ensure any stray instances are cleaned
    Ensure-SinglePotPlayerInstance -TargetPid 0 | Out-Null

    # Restore PotPlayer original INI
    Restore-PotPlayerSettings -IniPath $PotIni

    # Restore Power Scheme
    if ($OriginalSchemeGuid) {
        powercfg /setactive $OriginalSchemeGuid
        Write-Host "  -> Restored original power plan ($OriginalSchemeGuid)." -ForegroundColor Green
    }

    # Re-enable Network
    foreach ($adapter in $DisabledAdapters) {
        Write-Host "  -> Re-enabling adapter: $adapter" -ForegroundColor Green
        Enable-NetAdapter -Name $adapter -Confirm:$false -ErrorAction SilentlyContinue
    }

    Write-Host "Benchmark Run Completed Cleanly.`n" -ForegroundColor Cyan
}
