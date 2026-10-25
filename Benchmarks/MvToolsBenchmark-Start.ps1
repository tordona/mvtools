<#
.SYNOPSIS
    Portable, Automated Reproducible Benchmark Harness for PotPlayer + MVTools (ARM64 and x64).
.DESCRIPTION
    Fully portable benchmark harness with zero hardcoded paths:
    1. Detects system-installed PotPlayer ('%ProgramFiles%\DAUM\PotPlayer') or local sibling 'PotPlayer'.
    2. Supports automated official native PotPlayer download (ARM64 or x64) and silent installation from Kakao CDN (-AutoInstallPotPlayer).
    3. Audits mvtools2.dll and mvtools2_d3d12.dll version, SHA-256, and PE header linker compile timestamp.
    4. Automatically acquires AviSynth.dll from GitHub releases (AviSynth/AviSynthPlus) when not found locally.
    5. Injects deterministic PotPlayer configuration (D3D11 DXVA, AviSynth profile, subtitler off, audio pitch off, MultipleRunning=0).
    6. Enforces single-instance integrity: verifies and guarantees only one PotPlayer instance runs at any time.
    7. Audits available physical RAM against profile SetMemoryMax requirements (+1024 MB UMA/Player buffer headroom).
    8. Enforces environmental controls (AC power check, High Performance plan, background quiescence).
    9. Verifies overall system CPU and GPU load drops to idle before launching the test.
    10. Integrates optional sibling 'PresentMon.exe' to capture sub-millisecond Average, High, Low, 1% Low FPS, and Dropped Frames.
    11. Runs test, records telemetry (CPU, GPU, RAM, Page Swaps, Instance Count, FPS) to CSV, and generates an audit report.
    12. Restores original configuration, power plan, and network adapters upon exit.
.PARAMETER SkipProcessKill
    Skips terminating background noisy applications (browsers, discord, slack, etc.)
    prior to system idle stabilization.
.PARAMETER AutoInstallPotPlayer
    Automatically downloads and silently installs official native PotPlayer (ARM64 or x64) from Kakao CDN
    if PotPlayer is not detected on the system. Uses active live progress bar and background spinner.
.PARAMETER AutoDownloadMvTools
    Automatically downloads and extracts official MVTools release archives (ARM64 and x64)
    (mvtools2.dll, mvtools2_d3d12.dll) from GitHub releases (pinterf/mvtools on x64, tordona/mvtools on ARM64).
    Version-agnostic asset discovery with live streaming progress and 7-Zip/bsdtar decompression.
.PARAMETER MvToolsRepo
    GitHub repository slug for downloading release packages (default: dynamic - "pinterf/mvtools" on x64, "tordona/mvtools" on ARM64).
.PARAMETER AviSynthRepo
    GitHub repository slug for downloading official AviSynth+ releases (default: "AviSynth/AviSynthPlus").
.VERSION
    2.4.0
.DATE
    2026-10-24
.NOTES
    Format: SemVer (MAJOR.MINOR.PATCH)
    Revision History:
    - v2.4.0 (2026-10-24): Added full cross-architecture support for x64 (AMD/Intel) and ARM64.
                           Dynamic hardware platform detection and mode recommendations (CPU SIMD / Platform vs
                           CPU NEON / SoC). Zero-hardcoded-version asset acquisition via GitHub REST API and
                           HTML asset fallbacks for MVTools, AviSynth+, 7-Zip, and PotPlayer. Architecture-aware
                           AviSynth profile validation and automated acquisition from tordona/mvtools. Strict PE
                           machine validation (0x8664 vs 0xAA64).
    - v2.3.0 (2026-10-19): Added automated GitHub acquisition for MVTools ARM64 and AviSynth+, dual
                           AppData/local PotPlayer INI targeting, binary PE architecture validation,
                           user download confirmations, and background app quiescence prompts.
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
    [Alias("SkipAppKill")]
    [switch]$SkipProcessKill,

    [Parameter(Mandatory = $false)]
    [switch]$IgnoreUsbWarning,

    [Parameter(Mandatory = $false)]
    [Alias("IgnoreMemoryWarning")]
    [switch]$IgnoreRamWarning,

    [Parameter(Mandatory = $false)]
    [switch]$IgnoreBatteryWarning,

    [Parameter(Mandatory = $false)]
    [switch]$MemoryConstrained,

    [Parameter(Mandatory = $false)]
    [switch]$AutoInstallPotPlayer,

    [Parameter(Mandatory = $false)]
    [Alias("DownloadMvTools", "UpdateMvTools")]
    [switch]$AutoDownloadMvTools,

    [Parameter(Mandatory = $false)]
    [string]$MvToolsRepo = "",

    [Parameter(Mandatory = $false)]
    [string]$AviSynthRepo = "AviSynth/AviSynthPlus",

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = ""
)

# Harness Semantic Revision
$Script:HarnessVersion = "2.4.0"

# Initialize TLS 1.2 and System.Net.Http assembly (required for Windows PowerShell 5.1 compatibility)
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
} catch {}
try {
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
} catch {}

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

$ExplicitMvToolsDir = if ($PSBoundParameters.ContainsKey('MvToolsDir') -and -not [string]::IsNullOrWhiteSpace($MvToolsDir)) { $MvToolsDir } else { "" }

# Helper to dynamically discover MVTools binaries across potential locations
function Resolve-MvToolsSearchDirectory {
    param(
        [string]$ExplicitDir = "",
        [string]$TargetPotPlayerDir = "",
        [string]$CurrentScriptDir = "",
        [string]$CurrentRepoRoot = ""
    )
    if (-not [string]::IsNullOrWhiteSpace($ExplicitDir) -and (Test-Path $ExplicitDir)) {
        return (Resolve-Path $ExplicitDir).Path
    }

    # Candidate search paths where mvtools2.dll might already exist:
    $searchCandidates = @(
        $TargetPotPlayerDir,
        (Join-Path $TargetPotPlayerDir "plugins"),
        (Join-Path $TargetPotPlayerDir "AviSynth"),
        $CurrentScriptDir,
        (Join-Path $CurrentScriptDir "plugins")
    )
    foreach ($cand in $searchCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path (Join-Path $cand "mvtools2.dll"))) {
            return (Resolve-Path $cand).Path
        }
    }

    # If mvtools2.dll is not yet found, default to verified PotPlayer directory if valid
    if (-not [string]::IsNullOrWhiteSpace($TargetPotPlayerDir) -and (Test-Path $TargetPotPlayerDir)) {
        return (Resolve-Path $TargetPotPlayerDir).Path
    }

    # Otherwise default to Benchmarks script directory
    return $CurrentScriptDir
}

# ---------------------------------------------------------
# POTPLAYER INI & INSTALLATION TARGET RESOLUTION
# ---------------------------------------------------------
function Test-IsDefaultPotPlayerLocation([string]$Dir) {
    if ([string]::IsNullOrWhiteSpace($Dir)) { return $false }
    try {
        $norm = [System.IO.Path]::GetFullPath($Dir).TrimEnd('\', '/')
        $defaultCandidates = @(
            (Join-Path ${env:ProgramFiles} "DAUM\PotPlayer"),
            (Join-Path ${env:ProgramW6432} "DAUM\PotPlayer"),
            (Join-Path ${env:ProgramFiles(x86)} "DAUM\PotPlayer")
        )
        foreach ($cand in $defaultCandidates) {
            if (-not [string]::IsNullOrWhiteSpace($cand)) {
                $normCand = [System.IO.Path]::GetFullPath($cand).TrimEnd('\', '/')
                if ($norm.Equals($normCand, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $true
                }
            }
        }
    } catch {}
    return $false
}

function Get-PotPlayerIniTargets([string]$PotPlayerDir) {
    if (Test-IsDefaultPotPlayerLocation $PotPlayerDir) {
        $appData = if ($env:APPDATA) { $env:APPDATA } else { [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData) }
        return @(
            (Join-Path $appData "PotPlayer64\PotPlayer64.ini"),
            (Join-Path $appData "PotPlayerMini64\PotPlayerMini64.ini")
        )
    } else {
        return @(
            (Join-Path $PotPlayerDir "PotPlayer64.ini"),
            (Join-Path $PotPlayerDir "PotPlayerMini64.ini")
        )
    }
}

function Initialize-PotPlayerIniFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PotPlayerDir
    )

    $isDefault = Test-IsDefaultPotPlayerLocation $PotPlayerDir
    $iniTargets = Get-PotPlayerIniTargets $PotPlayerDir

    if ($isDefault) {
        Write-Host "  -> Ensuring PotPlayer configuration at default AppData locations..." -ForegroundColor Gray
    } else {
        Write-Host "  -> Ensuring PotPlayer configuration at install location: $PotPlayerDir..." -ForegroundColor Gray
    }

    foreach ($target in $iniTargets) {
        $parentDir = Split-Path $target -Parent
        if (-not (Test-Path $parentDir)) {
            try {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            } catch {
                Write-Warning "Could not create directory '$parentDir': $($_.Exception.Message)"
            }
        }

        if (-not (Test-Path $target)) {
            $leaf = Split-Path $target -Leaf
            $candidateSource = Join-Path $PotPlayerDir $leaf
            $copied = $false

            # 1. Try copying from install directory if an INI exists there
            if ((Test-Path $candidateSource) -and ($candidateSource -ne $target)) {
                try {
                    Copy-Item -Path $candidateSource -Destination $target -Force -ErrorAction Stop
                    Write-Host "     Copied baseline INI to: $target" -ForegroundColor Gray
                    $copied = $true
                } catch {
                    Write-Warning "Could not copy '$candidateSource' to '$target': $($_.Exception.Message)"
                }
            }

            # 2. Try copying from sibling template if present in install dir (e.g. PotPlayer64.ini to PotPlayerMini64.ini)
            if (-not $copied) {
                $altLeaf = if ($leaf -match '(?i)Mini') { "PotPlayer64.ini" } else { "PotPlayerMini64.ini" }
                $altSource = Join-Path $PotPlayerDir $altLeaf
                if ((Test-Path $altSource) -and ($altSource -ne $target)) {
                    try {
                        Copy-Item -Path $altSource -Destination $target -Force -ErrorAction Stop
                        Write-Host "     Copied template INI ($altLeaf) to: $target" -ForegroundColor Gray
                        $copied = $true
                    } catch {}
                }
            }

            # 3. If still not copied, create clean baseline INI
            if (-not (Test-Path $target)) {
                try {
                    $autoIniVal = if ($isDefault) { "0" } else { "1" }
                    $initialContent = "[Settings]`r`nAutoIni=$autoIniVal`r`nMultipleRunning=0`r`n[Positions]`r`nMainWindowState=128`r`n"
                    [System.IO.File]::WriteAllText($target, $initialContent, [System.Text.Encoding]::Unicode)
                    Write-Host "     Created clean baseline INI: $target" -ForegroundColor Gray
                } catch {
                    Write-Warning "Could not initialize baseline INI at '$target': $($_.Exception.Message)"
                }
            }
        }
    }

    return $iniTargets
}

# Resolve PotPlayer directory: check system installed locations, registry, then local sibling
if ([string]::IsNullOrWhiteSpace($PotPlayerDir)) {
    $siblingDir = Join-Path $ScriptDir "PotPlayer"
    $installedDir64 = if ($env:ProgramFiles) { Join-Path ${env:ProgramFiles} "DAUM\PotPlayer" } else { "" }
    $installedDir32 = if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} "DAUM\PotPlayer" } else { "" }

    # Query registry dynamically for user or system PotPlayer installations
    $regPotDir = $null
    $potRegKeys = @(
        "HKCU:\SOFTWARE\Daum\PotPlayer64",
        "HKLM:\SOFTWARE\Daum\PotPlayer64",
        "HKCU:\SOFTWARE\Daum\PotPlayer",
        "HKLM:\SOFTWARE\Daum\PotPlayer"
    )
    foreach ($prk in $potRegKeys) {
        if (Test-Path $prk) {
            $prop = Get-ItemProperty -Path $prk -ErrorAction SilentlyContinue
            if ($prop.ProgramFolder -and ((Test-Path (Join-Path $prop.ProgramFolder "PotPlayer64.exe")) -or (Test-Path (Join-Path $prop.ProgramFolder "PotPlayerMini64.exe")))) {
                $regPotDir = $prop.ProgramFolder
                break
            }
        }
    }

    # Prefer system/default installed PotPlayer if present, then registry, then local sibling
    if ($installedDir64 -and ((Test-Path (Join-Path $installedDir64 "PotPlayer64.exe")) -or (Test-Path (Join-Path $installedDir64 "PotPlayerMini64.exe")))) {
        $PotPlayerDir = $installedDir64
    } elseif ($regPotDir -and ((Test-Path (Join-Path $regPotDir "PotPlayer64.exe")) -or (Test-Path (Join-Path $regPotDir "PotPlayerMini64.exe")))) {
        $PotPlayerDir = $regPotDir
    } elseif ($installedDir32 -and ((Test-Path (Join-Path $installedDir32 "PotPlayer64.exe")) -or (Test-Path (Join-Path $installedDir32 "PotPlayerMini64.exe")))) {
        $PotPlayerDir = $installedDir32
    } elseif ((Test-Path (Join-Path $siblingDir "PotPlayer64.exe")) -or (Test-Path (Join-Path $siblingDir "PotPlayerMini64.exe"))) {
        $PotPlayerDir = $siblingDir
    } else {
        $PotPlayerDir = if ($installedDir64) { $installedDir64 } else { $siblingDir }
    }
}

# Resolve MVTools binary search directory
$MvToolsDir = Resolve-MvToolsSearchDirectory -ExplicitDir $ExplicitMvToolsDir -TargetPotPlayerDir $PotPlayerDir -CurrentScriptDir $ScriptDir -CurrentRepoRoot $RepoRoot

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
    param([string]$TargetPotPlayerDir = "")

    $targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetPotPlayerDir
    $isArm64 = ($targetArch -eq "arm64")

    # Strict architecture pinning: x64 machines must only use PresentMon-x64.exe, ARM64 only PresentMon-arm64.exe
    $candidateList = if ($isArm64) {
        @(
            (Join-Path $ScriptDir "PresentMon-arm64.exe"),
            (Join-Path $ScriptDir "PresentMon.exe"),
            (Get-Command "PresentMon-arm64.exe" -ErrorAction SilentlyContinue).Source,
            (Get-Command "PresentMon.exe" -ErrorAction SilentlyContinue).Source,
            (Join-Path ${env:ProgramFiles} "PresentMon\PresentMon.exe")
        )
    } else {
        @(
            (Join-Path $ScriptDir "PresentMon-x64.exe"),
            (Join-Path $ScriptDir "PresentMon.exe"),
            (Get-Command "PresentMon-x64.exe" -ErrorAction SilentlyContinue).Source,
            (Get-Command "PresentMon.exe" -ErrorAction SilentlyContinue).Source,
            (Join-Path ${env:ProgramFiles} "PresentMon\PresentMon.exe")
        )
    }

    foreach ($p in $candidateList) {
        if (-not [string]::IsNullOrWhiteSpace($p) -and (Test-Path $p)) {
            $machine = Get-PeMachine -FilePath $p
            if ($isArm64 -and ($machine -eq 0xAA64 -or $machine -eq 0)) { return $p }
            if (-not $isArm64 -and ($machine -eq 0x8664 -or $machine -eq 0)) { return $p }
        }
    }
    return $null
}

# ---------------------------------------------------------
# HELPER: Read PE Header Machine Architecture
# ---------------------------------------------------------
function Get-PeMachine {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return 0 }
    $fs = $null
    try {
        $fs = [System.IO.File]::OpenRead($FilePath)
        $br = New-Object System.IO.BinaryReader($fs)
        $fs.Seek(0x3C, [System.IO.SeekOrigin]::Begin) | Out-Null
        $peOffset = $br.ReadInt32()
        $fs.Seek($peOffset + 4, [System.IO.SeekOrigin]::Begin) | Out-Null
        $machine = $br.ReadUInt16()
        $fs.Close()
        $fs = $null
        return $machine
    } catch {
        if ($fs) { $fs.Close() }
        return 0
    }
}

# ---------------------------------------------------------
# HELPER: Resolve Target Binary Architecture (ARM64 vs x64 vs x86)
# ---------------------------------------------------------
function Get-TargetBinaryArchitecture {
    param([string]$TargetPotPlayerDir = "")

    # Priority 1: Check PE Machine header of target PotPlayer executable
    if (-not [string]::IsNullOrWhiteSpace($TargetPotPlayerDir)) {
        $potCandidates = @(
            (Join-Path $TargetPotPlayerDir "PotPlayer64.exe"),
            (Join-Path $TargetPotPlayerDir "PotPlayerMini64.exe"),
            (Join-Path $TargetPotPlayerDir "PotPlayer.exe")
        )
        foreach ($pe in $potCandidates) {
            if (Test-Path $pe) {
                $machine = Get-PeMachine -FilePath $pe
                if ($machine -eq 0xAA64) { return "arm64" }
                if ($machine -eq 0x8664) { return "x64" }
                if ($machine -eq 0x014C) { return "x86" }
            }
        }
    }

    # Priority 2: System-wide registry machine architecture
    try {
        $regArch = Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" -Name "PROCESSOR_ARCHITECTURE" -ErrorAction SilentlyContinue
        if ($regArch -match '(?i)ARM64') { return "arm64" }
    } catch {}

    # Priority 3: WMI Processor Architecture (12 = ARM64)
    try {
        $wmiArch = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Architecture
        if ($wmiArch -eq 12) { return "arm64" }
    } catch {}

    # Priority 4: Environment indicators for ARM64
    if ($env:PROCESSOR_ARCHITECTURE -match '(?i)ARM64' -or 
        $env:PROCESSOR_ARCHITEW6432 -match '(?i)ARM64' -or 
        $env:PROCESSOR_IDENTIFIER -match '(?i)ARM|Qualcomm|Snapdragon|Oryon') {
        return "arm64"
    }

    # Priority 5: x64
    if ($env:PROCESSOR_ARCHITECTURE -match '(?i)AMD64|x64') {
        return "x64"
    }

    # Default to ARM64 if not otherwise detected
    return "arm64"
}

# ---------------------------------------------------------
# HELPER: Explicit Download Permission Confirmation
# ---------------------------------------------------------
function Confirm-DownloadPermission {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ItemName,

        [Parameter(Mandatory = $true)]
        [string]$SourceUrl,

        [Parameter(Mandatory = $false)]
        [string]$TargetDir = "",

        [Parameter(Mandatory = $false)]
        [string]$SizeDesc = "",

        [Parameter(Mandatory = $false)]
        [switch]$Bypass
    )

    if ($Bypass -or $script:AutoDownloadMvTools) {
        return $true
    }

    Write-Host "`n========================================================" -ForegroundColor Yellow
    Write-Host " PERMISSION REQUIRED: EXTERNAL FILE DOWNLOAD" -ForegroundColor Yellow
    Write-Host "========================================================" -ForegroundColor Yellow
    Write-Host " Item:        $ItemName" -ForegroundColor White
    Write-Host " Source:      $SourceUrl" -ForegroundColor Cyan
    if (-not [string]::IsNullOrWhiteSpace($SizeDesc)) {
        Write-Host " Size:        $SizeDesc" -ForegroundColor Gray
    }
    if (-not [string]::IsNullOrWhiteSpace($TargetDir)) {
        Write-Host " Destination: $TargetDir" -ForegroundColor Gray
    }
    Write-Host "--------------------------------------------------------" -ForegroundColor Gray

    try {
        Write-Host "Do you want to proceed with downloading this file? [Y/n]: " -NoNewline -ForegroundColor Cyan
        $response = Read-Host
    } catch {
        Write-Host "[ERROR] External file download requires user permission, but unable to prompt host." -ForegroundColor Red
        Write-Host "Aborting download of '$ItemName'.`n" -ForegroundColor Yellow
        return $false
    }

    if ($null -eq $response) {
        Write-Host "  -> No input received (End of stream). Download aborted.`n" -ForegroundColor DarkYellow
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($response) -or $response -match '^(?i)y(es)?$') {
        Write-Host "  -> Permission granted. Proceeding with download...`n" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  -> Permission declined by user. Download aborted.`n" -ForegroundColor DarkYellow
        return $false
    }
}

# ---------------------------------------------------------
# HELPER: Discover Existing 7-Zip CLI Extractor (7z.exe / 7za.exe)
# ---------------------------------------------------------
function Find-7ZipExtractor {
    param([string]$TargetPotPlayerDir = "")

    $winDir = if ($env:WINDIR) { $env:WINDIR } else { [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Windows) }

    $searchCandidates = @(
        (Get-Command 7z -ErrorAction SilentlyContinue | Select-Object -First 1).Source,
        (Get-Command 7za -ErrorAction SilentlyContinue | Select-Object -First 1).Source,
        (Join-Path $ScriptDir "7z.exe"),
        (Join-Path $ScriptDir "7za.exe"),
        (Join-Path $ScriptDir "7-Zip\7z.exe"),
        (Join-Path $env:LOCALAPPDATA "7-Zip\7z.exe"),
        (Join-Path ${env:ProgramFiles} "7-Zip\7z.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "7-Zip\7z.exe"),
        (Join-Path $winDir "7z.exe")
    )

    if (-not [string]::IsNullOrWhiteSpace($TargetPotPlayerDir)) {
        $searchCandidates += (Join-Path $TargetPotPlayerDir "7z.exe")
        $searchCandidates += (Join-Path $TargetPotPlayerDir "7-Zip\7z.exe")
    }

    foreach ($cand in $searchCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path $cand)) {
            return (Resolve-Path $cand).Path
        }
    }
    return $null
}

# ---------------------------------------------------------
# HELPER: Ensure 7-Zip CLI Extractor is Available (Portable Acquisition)
# ---------------------------------------------------------
function Ensure-7ZipExtractor {
    param([string]$TargetPotPlayerDir = "")

    $existing = Find-7ZipExtractor -TargetPotPlayerDir $TargetPotPlayerDir
    if ($existing) {
        return $existing
    }

    Write-Host "`n[TOOL ACQUISITION] 7-Zip CLI extractor (7z.exe) is required for .7z archive decompression." -ForegroundColor Cyan
    Write-Host "  Windows built-in 'tar.exe' does not support LZMA/LZMA2 decompression in .7z packages." -ForegroundColor Yellow

    $targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetPotPlayerDir
    # Dynamically resolve official 7-Zip MSI release package from GitHub (zero hardcoded versions/filenames)
    $msiUrl = $null
    $msiName = $null
    try {
        $headers = @{
            "User-Agent" = "MvToolsBenchmarkHarness/2.3.0"
            "Accept"     = "application/vnd.github.v3+json"
        }
        $zipRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/ip7z/7zip/releases/latest" -Headers $headers -TimeoutSec 10 -ErrorAction Stop
        if ($zipRelease -and $zipRelease.assets) {
            $msiAsset = if ($targetArch -eq "x64") {
                $zipRelease.assets | Where-Object { $_.name -match '(?i)7z.*-x64\.msi$' } | Select-Object -First 1
            } else {
                $zipRelease.assets | Where-Object { $_.name -match '(?i)7z[^\-]*\.msi$' } | Select-Object -First 1
            }
            if ($msiAsset) {
                $msiUrl = $msiAsset.browser_download_url
                $msiName = $msiAsset.name
            }
        }
    } catch {
        # Web release redirect fallback
        try {
            $req = [System.Net.HttpWebRequest]::Create("https://github.com/ip7z/7zip/releases/latest")
            $req.AllowAutoRedirect = $true
            $req.UserAgent = "MvToolsBenchmarkHarness/2.3.0"
            $req.Timeout = 10000
            $resp = $req.GetResponse()
            $finalUrl = $resp.ResponseUri.AbsoluteUri
            $resp.Close()

            $resolvedTag = Split-Path $finalUrl -Leaf
            if ($resolvedTag) {
                $assetsUrl = "https://github.com/ip7z/7zip/releases/expanded_assets/$resolvedTag"
                $assetsReq = [System.Net.HttpWebRequest]::Create($assetsUrl)
                $assetsReq.UserAgent = "MvToolsBenchmarkHarness/2.3.0"
                $assetsReq.Timeout = 10000
                $assetsResp = $assetsReq.GetResponse()
                $stream = $assetsResp.GetResponseStream()
                $reader = [System.IO.StreamReader]::new($stream)
                $html = $reader.ReadToEnd()
                $reader.Close()
                $assetsResp.Close()

                $pattern = if ($targetArch -eq "x64") { 'href="([^"]+/releases/download/[^"]+7z[^\-"]*-x64\.msi)"' } else { 'href="([^"]+/releases/download/[^"]+7z[^\-"]*\.msi)"' }
                if ($html -match $pattern) {
                    $rel = $Matches[1]
                    $msiUrl = if ($rel -notmatch '^https:') { "https://github.com$rel" } else { $rel }
                    $msiName = [System.IO.Path]::GetFileName($msiUrl)
                }
            }
        } catch {}
    }

    if (-not $msiUrl) {
        Write-Host "  [WARNING] Could not resolve official 7-Zip MSI package dynamically from GitHub." -ForegroundColor Yellow
        return $null
    }

    $localToolsDir = Join-Path $env:LOCALAPPDATA "7-Zip"
    if (-not (Test-Path $localToolsDir)) {
        New-Item -ItemType Directory -Path $localToolsDir -Force | Out-Null
    }

    if (-not (Confirm-DownloadPermission -ItemName "Official 7-Zip Portable Extractor ($msiName)" -SourceUrl $msiUrl -TargetDir $localToolsDir -SizeDesc "~2.5 MB")) {
        return $null
    }

    Write-Host "  -> Downloading 7-Zip portable package from GitHub ($msiUrl)..." -ForegroundColor Cyan
    $tempMsi = Join-Path $env:TEMP ("7z_acq_{0}.msi" -f [System.Guid]::NewGuid().ToString("N"))
    $tempUnpack = Join-Path $env:TEMP ("7z_unpack_{0}" -f [System.Guid]::NewGuid().ToString("N"))

    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($msiUrl, $tempMsi)
        $webClient.Dispose()

        Write-Host "  -> Unpacking 7-Zip binaries via Windows Installer engine (user-mode)..." -ForegroundColor Cyan
        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/a `"$tempMsi`" /qn TARGETDIR=`"$tempUnpack`"" -PassThru -Wait
        if ($proc.ExitCode -ne 0) {
            throw "msiexec administrative unpack exited with code $($proc.ExitCode)"
        }

        # Locate extracted 7z.exe and 7z.dll
        $extracted7z = Get-ChildItem -Path $tempUnpack -Recurse -File | Where-Object { $_.Name -ieq "7z.exe" } | Select-Object -First 1
        if (-not $extracted7z) {
            throw "Could not locate 7z.exe inside unpacked 7-Zip package!"
        }

        $sourceDir = $extracted7z.DirectoryName
        Copy-Item -Path (Join-Path $sourceDir "*") -Destination $localToolsDir -Recurse -Force
        $deployedExe = Join-Path $localToolsDir "7z.exe"
        if (Test-Path $deployedExe) {
            Write-Host "  -> 7-Zip CLI extractor ready at: $deployedExe`n" -ForegroundColor Green
            return $deployedExe
        }
    }
    catch {
        Write-Host "  [WARNING] Automated 7-Zip acquisition failed: $_" -ForegroundColor Yellow
        Write-Host "  Please install 7-Zip manually from https://7-zip.org or place 7z.exe in '$localToolsDir'.`n" -ForegroundColor Yellow
    }
    finally {
        if (Test-Path $tempMsi) { Remove-Item $tempMsi -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempUnpack) { Remove-Item $tempUnpack -Recurse -Force -ErrorAction SilentlyContinue }
    }

    return $null
}

# ---------------------------------------------------------
# HELPER: Automated Acquisition & Silent Installation of PotPlayer
# ---------------------------------------------------------
function Install-PotPlayer {
    param(
        [string]$TargetDir = "",
        [bool]$Elevated = $false
    )

    # Initialize TLS 1.2 and System.Net.Http assembly (required for Windows PowerShell 5.1 compatibility)
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    } catch {}
    try {
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    } catch {}

    $targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetDir
    $isArm64 = ($targetArch -eq "arm64")
    $installerName = if ($isArm64) { "PotPlayerSetupARM64.exe" } else { "PotPlayerSetup64.exe" }
    $Url = "https://t1.daumcdn.net/potplayer/PotPlayer/Version/Latest/$installerName"
    $TempInstaller = Join-Path $env:TEMP ("{0}_{1}.exe" -f [System.IO.Path]::GetFileNameWithoutExtension($installerName), [System.Guid]::NewGuid().ToString("N"))

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host (" AUTOMATED POTPLAYER {0} ACQUISITION & SETUP" -f ($targetArch.ToUpper())) -ForegroundColor Cyan
    Write-Host " Source: Kakao Corp Official CDN ($Url)" -ForegroundColor Gray
    Write-Host (" Architecture: Native Windows on {0}" -f ($targetArch.ToUpper())) -ForegroundColor Gray
    Write-Host "========================================================`n" -ForegroundColor Cyan

    $archLabel = $targetArch.ToUpper()
    # Prompt user permission before downloading
    if (-not (Confirm-DownloadPermission -ItemName "PotPlayer $archLabel Official Installer" -SourceUrl $Url -TargetDir $TempInstaller -SizeDesc "~35 MB")) {
        return $null
    }

    # Phase 1: Download with live stream progress
    Write-Host "[1/2] Downloading Official PotPlayer $archLabel Installer..." -ForegroundColor Cyan

    $Client = $null
    $FileStream = $null
    $Stream = $null
    $DownloadSuccess = $false

    try {
        $Client = New-Object System.Net.Http.HttpClient
        # 1 corresponds to HttpCompletionOption.ResponseHeadersRead
        $Response = $Client.GetAsync($Url, 1).GetAwaiter().GetResult()
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
        $FileStream = $null
        $Stream.Close()
        $Stream = $null
        $TotalMb = ($TotalRead / 1MB).ToString("0.0")
        $TotalSec = [math]::Round($Stopwatch.Elapsed.TotalSeconds, 1)
        Write-Host "`r  [OK] Download complete! ($TotalMb MB downloaded in ${TotalSec}s)                              " -ForegroundColor Green
        $DownloadSuccess = $true
    }
    catch {
        Write-Host "`r  [WARNING] Streaming download encountered an issue: $($_.Exception.Message). Attempting WebClient fallback..." -ForegroundColor Yellow
        if ($FileStream) { $FileStream.Dispose(); $FileStream = $null }
        if ($Stream) { $Stream.Dispose(); $Stream = $null }
        if ($Client) { $Client.Dispose(); $Client = $null }

        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($Url, $TempInstaller)
            $webClient.Dispose()
            if ((Test-Path $TempInstaller) -and ((Get-Item $TempInstaller).Length -gt 0)) {
                Write-Host "  [OK] Download complete! (Fallback successful)                                   " -ForegroundColor Green
                $DownloadSuccess = $true
            } else {
                throw "Downloaded file was empty or missing."
            }
        } catch {
            Write-Host "`r  [ERROR] Fallback download failed: $_" -ForegroundColor Red
            if (Test-Path $TempInstaller) { Remove-Item $TempInstaller -Force -ErrorAction SilentlyContinue }
            $DownloadSuccess = $false
        }
    }
    finally {
        if ($FileStream) { $FileStream.Dispose() }
        if ($Stream) { $Stream.Dispose() }
        if ($Client) { $Client.Dispose() }
    }

    # Ensure Phase 1 actually succeeded before attempting Phase 2
    if (-not $DownloadSuccess -or -not (Test-Path $TempInstaller) -or (Get-Item $TempInstaller).Length -eq 0) {
        Write-Host "`n[FATAL ERROR] PotPlayer download was incomplete or failed. Installation aborted.`n" -ForegroundColor Red
        if (Test-Path $TempInstaller) { Remove-Item $TempInstaller -Force -ErrorAction SilentlyContinue }
        return $null
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
        $StableSuccessCount = 0

        while (-not $Process.HasExited) {
            $Char = $Spinner[$SpinIndex % $Spinner.Length]
            $ElapsedSec = [math]::Round($InstallWatch.Elapsed.TotalSeconds)
            Write-Host -NoNewline "`r  [$Char] Unpacking and registering $archLabel components... (${ElapsedSec}s elapsed)   " -ForegroundColor Yellow
            Start-Sleep -Milliseconds 250
            $SpinIndex++

            # Early completion detection: check if core files and uninstaller are fully deployed
            if ($InstallWatch.Elapsed.TotalSeconds -ge 6) {
                $InstalledCandidate = $null
                $CheckList = @()
                if (-not [string]::IsNullOrWhiteSpace($TargetDir)) { $CheckList += $TargetDir }
                $CheckList += @(
                    (Join-Path ${env:ProgramFiles} "DAUM\PotPlayer"),
                    (Join-Path ${env:ProgramW6432} "DAUM\PotPlayer"),
                    (Join-Path ${env:ProgramFiles(x86)} "DAUM\PotPlayer"),
                    (Join-Path $env:LOCALAPPDATA "DAUM\PotPlayer")
                )
                foreach ($chk in $CheckList) {
                    if (-not [string]::IsNullOrWhiteSpace($chk)) {
                        $potBin = Join-Path $chk "PotPlayer64.exe"
                        $potMini = Join-Path $chk "PotPlayerMini64.exe"
                        $potUninst = Join-Path $chk "uninstall.exe"
                        if (((Test-Path $potBin) -or (Test-Path $potMini)) -and (Test-Path $potUninst)) {
                            $InstalledCandidate = $chk
                            break
                        }
                    }
                }

                if ($InstalledCandidate) {
                    $StableSuccessCount++
                    # If core files are verified stable across 8 cycles (2.0s), installer completed unpacking
                    if ($StableSuccessCount -ge 8) {
                        try {
                            if (-not $Process.WaitForExit(3000)) {
                                Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                            }
                        } catch {}
                        break
                    }
                } else {
                    $StableSuccessCount = 0
                }
            }

            # Safety watchdog (180 seconds max)
            if ($InstallWatch.Elapsed.TotalSeconds -gt 180) {
                Write-Warning "`n[TIMEOUT] PotPlayer installation timed out after 180 seconds. Terminating installer process."
                Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
                break
            }
        }

        try { [void]$Process.WaitForExit(2000) } catch {}
        $InstallSec = [math]::Round($InstallWatch.Elapsed.TotalSeconds, 1)

        $ExitCode = 0
        try { $ExitCode = $Process.ExitCode } catch {}

        if ($ExitCode -eq 0 -or $StableSuccessCount -ge 8) {
            Write-Host "`r  [OK] PotPlayer installed successfully in ${InstallSec}s!                                    `n" -ForegroundColor Green
        } else {
            Write-Host "`r  [WARNING] Installer exited with code $ExitCode after ${InstallSec}s. Checking for installed files...`n" -ForegroundColor Yellow
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
        if (-not [string]::IsNullOrWhiteSpace($loc) -and ((Test-Path (Join-Path $loc "PotPlayer64.exe")) -or (Test-Path (Join-Path $loc "PotPlayerMini64.exe")))) {
            try {
                icacls.exe "$loc" /grant "*S-1-5-32-545:(OI)(CI)M" /T /Q | Out-Null
            } catch {}
            Install-MvToolsToPotPlayer -TargetPotPlayerDir $loc -RepoRoot $RepoRoot -ScriptDir $ScriptDir -MvToolsRepo $MvToolsRepo -AviSynthRepo $AviSynthRepo | Out-Null
            Initialize-PotPlayerIniFiles -PotPlayerDir $loc | Out-Null
            return $loc
        }
    }

    return $null
}

Set-Alias -Name Install-PotPlayerARM64 -Value Install-PotPlayer -ErrorAction SilentlyContinue

# ---------------------------------------------------------
# HELPER: Discover Latest MVTools Release Asset from GitHub
# ---------------------------------------------------------
function Get-MvToolsLatestReleaseAsset {
    param(
        [string]$RepoSlug = "",
        [string]$ReleaseTag = ""
    )

    $targetArch = Get-TargetBinaryArchitecture
    if ([string]::IsNullOrWhiteSpace($RepoSlug) -or ($RepoSlug -eq "tordona/mvtools" -and $targetArch -eq "x64")) {
        $RepoSlug = if ($targetArch -eq "x64") { "pinterf/mvtools" } else { "tordona/mvtools" }
    }
    if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
        $ReleaseTag = "latest"
    }

    $ReleaseInfo = [ordered]@{
        TagName     = ""
        DownloadUrl = ""
        FileName    = ""
        Size        = 0
        Source      = "GitHubAPI"
    }

    $ApiUrl = if ($ReleaseTag -eq "latest") {
        "https://api.github.com/repos/$RepoSlug/releases/latest"
    } else {
        "https://api.github.com/repos/$RepoSlug/releases/tags/$ReleaseTag"
    }

    try {
        $uaVersion = if ($Script:HarnessVersion) { $Script:HarnessVersion } else { "2.3.0" }
        $headers = @{
            "User-Agent" = "MvToolsBenchmarkHarness/$uaVersion"
            "Accept"     = "application/vnd.github.v3+json"
        }
        $release = Invoke-RestMethod -Uri $ApiUrl -Headers $headers -TimeoutSec 15 -ErrorAction Stop
        if ($release -and $release.assets -and $release.assets.Count -gt 0) {
            $ReleaseInfo.TagName = if ($release.tag_name) { $release.tag_name } else { $ReleaseTag }

            $targetArch = Get-TargetBinaryArchitecture
            if ($targetArch -eq "x64") {
                # x64: match mvtools-*.7z or mvtools-*.zip
                $asset = $release.assets | Where-Object { $_.name -match '(?i)mvtools-.*\.7z$' } | Select-Object -First 1
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)mvtools.*\.7z$' } | Select-Object -First 1
                }
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)\.7z$' } | Select-Object -First 1
                }
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)mvtools.*\.zip$' } | Select-Object -First 1
                }
            } else {
                # ARM64: match arm64 release archives
                $asset = $release.assets | Where-Object { $_.name -match '(?i)arm64.*\.7z$' } | Select-Object -First 1
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)mvtools.*\.7z$' } | Select-Object -First 1
                }
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)\.7z$' } | Select-Object -First 1
                }
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)arm64.*\.zip$' } | Select-Object -First 1
                }
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)\.zip$' } | Select-Object -First 1
                }
            }

            if ($asset) {
                $ReleaseInfo.DownloadUrl = $asset.browser_download_url
                $ReleaseInfo.FileName = $asset.name
                $ReleaseInfo.Size = $asset.size
                return $ReleaseInfo
            }
        }
    } catch {
        Write-Host "  -> GitHub API notice: $($_.Exception.Message)" -ForegroundColor Gray
    }

    # Dynamic web release discovery fallback (zero hardcoded versions/filenames)
    try {
        $webTargetUrl = if ($ReleaseTag -eq "latest") {
            "https://github.com/$RepoSlug/releases/latest"
        } else {
            "https://github.com/$RepoSlug/releases/tag/$ReleaseTag"
        }
        $req = [System.Net.HttpWebRequest]::Create($webTargetUrl)
        $req.AllowAutoRedirect = $true
        $req.UserAgent = "MvToolsBenchmarkHarness/$uaVersion"
        $req.Timeout = 10000
        $resp = $req.GetResponse()
        $finalUrl = $resp.ResponseUri.AbsoluteUri
        $resp.Close()

        $resolvedTag = Split-Path $finalUrl -Leaf
        if (-not [string]::IsNullOrWhiteSpace($resolvedTag)) {
            $ReleaseInfo.TagName = $resolvedTag
            $ReleaseInfo.Source = "GitHubWebDiscovery"

            $assetsUrl = "https://github.com/$RepoSlug/releases/expanded_assets/$resolvedTag"
            $assetsReq = [System.Net.HttpWebRequest]::Create($assetsUrl)
            $assetsReq.UserAgent = "MvToolsBenchmarkHarness/$uaVersion"
            $assetsReq.Timeout = 10000
            $assetsResp = $assetsReq.GetResponse()
            $stream = $assetsResp.GetResponseStream()
            $reader = [System.IO.StreamReader]::new($stream)
            $html = $reader.ReadToEnd()
            $reader.Close()
            $assetsResp.Close()

            $matches = [regex]::Matches($html, 'href="([^"]+/releases/download/[^"]+)"')
            $foundUrls = @()
            foreach ($m in $matches) {
                $rel = $m.Groups[1].Value
                if ($rel -notmatch '^https:') { $rel = "https://github.com$rel" }
                $foundUrls += $rel
            }
            $foundUrls = $foundUrls | Select-Object -Unique

            $selectedUrl = $null
            if ($targetArch -eq "x64") {
                $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)mvtools.*\.7z$' } | Select-Object -First 1
                if (-not $selectedUrl) { $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)\.7z$' } | Select-Object -First 1 }
                if (-not $selectedUrl) { $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)mvtools.*\.zip$' } | Select-Object -First 1 }
            } else {
                $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)arm64.*\.7z$' } | Select-Object -First 1
                if (-not $selectedUrl) { $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)mvtools.*\.7z$' } | Select-Object -First 1 }
                if (-not $selectedUrl) { $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)\.7z$' } | Select-Object -First 1 }
                if (-not $selectedUrl) { $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)arm64.*\.zip$' } | Select-Object -First 1 }
            }

            if ($selectedUrl) {
                $ReleaseInfo.DownloadUrl = $selectedUrl
                $ReleaseInfo.FileName = [System.IO.Path]::GetFileName($selectedUrl)
                return $ReleaseInfo
            }
        }
    } catch {
        Write-Host "  -> GitHub web discovery notice: $($_.Exception.Message)" -ForegroundColor Gray
    }

    return $null
}

# ---------------------------------------------------------
# HELPER: Automated Acquisition & Extraction of MVTools Release
# ---------------------------------------------------------
function Install-MvToolsRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TargetDir = "",

        [Parameter(Mandatory = $false)]
        [string]$RepoSlug = "",

        [Parameter(Mandatory = $false)]
        [string]$ReleaseTag = ""
    )

    # Initialize TLS 1.2 and System.Net.Http assembly (required for Windows PowerShell 5.1 compatibility)
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    } catch {}
    try {
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    } catch {}

    $targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetDir
    if ([string]::IsNullOrWhiteSpace($RepoSlug) -or ($RepoSlug -eq "tordona/mvtools" -and $targetArch -eq "x64")) {
        $RepoSlug = if ($targetArch -eq "x64") { "pinterf/mvtools" } else { "tordona/mvtools" }
    }
    if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
        $ReleaseTag = "latest"
    }
    $archLabel = $targetArch.ToUpper()

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host " AUTOMATED MVTOOLS $archLabel ACQUISITION & SETUP" -ForegroundColor Cyan
    Write-Host " Repository: https://github.com/$RepoSlug" -ForegroundColor Gray
    Write-Host " Target Architecture: Windows on $archLabel" -ForegroundColor Gray
    Write-Host "========================================================`n" -ForegroundColor Cyan

    Write-Host ("[1/3] Resolving latest MVTools {0} release package..." -f $archLabel) -ForegroundColor Cyan
    $assetInfo = Get-MvToolsLatestReleaseAsset -RepoSlug $RepoSlug -ReleaseTag $ReleaseTag
    if (-not $assetInfo -or [string]::IsNullOrWhiteSpace($assetInfo.DownloadUrl)) {
        Write-Host "  [ERROR] Could not resolve MVTools $archLabel release asset from $RepoSlug!" -ForegroundColor Red
        return $null
    }
    Write-Host "  -> Release Tag: $($assetInfo.TagName)" -ForegroundColor White
    Write-Host "  -> Asset Name:  $($assetInfo.FileName)" -ForegroundColor White
    Write-Host "  -> Source:      $($assetInfo.Source)" -ForegroundColor Gray
    Write-Host "  -> URL:         $($assetInfo.DownloadUrl)" -ForegroundColor Gray

    # Prompt user permission before downloading
    $sizeDesc = if ($assetInfo.Size -gt 0) { ("{0:N1} MB" -f ($assetInfo.Size / 1MB)) } else { "" }
    $tempArchive = Join-Path $env:TEMP ("mvtools_dl_{0}_{1}" -f [System.Guid]::NewGuid().ToString("N"), $assetInfo.FileName)
    if (-not (Confirm-DownloadPermission -ItemName "MVTools $archLabel Release ($($assetInfo.FileName))" -SourceUrl $assetInfo.DownloadUrl -TargetDir $tempArchive -SizeDesc $sizeDesc)) {
        return $null
    }

    # Phase 2: Download with live stream progress
    Write-Host "`n[2/3] Downloading $($assetInfo.FileName)..." -ForegroundColor Cyan

    $client = $null
    $fileStream = $null
    $stream = $null
    $downloadSuccess = $false

    try {
        $client = New-Object System.Net.Http.HttpClient
        # 1 corresponds to HttpCompletionOption.ResponseHeadersRead
        $response = $client.GetAsync($assetInfo.DownloadUrl, 1).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "HTTP $($response.StatusCode) ($($response.ReasonPhrase)) while accessing $($assetInfo.DownloadUrl)"
        }

        $totalBytes = $response.Content.Headers.ContentLength
        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $fileStream = [System.IO.File]::Create($tempArchive)

        $buffer = New-Object byte[] 65536
        $totalRead = 0
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $lastUiUpdate = [System.Diagnostics.Stopwatch]::StartNew()

        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $read)
            $totalRead += $read

            if ($lastUiUpdate.ElapsedMilliseconds -ge 100 -or $totalRead -eq $totalBytes) {
                $percent = if ($totalBytes -gt 0) { [math]::Round(($totalRead / $totalBytes) * 100) } else { 0 }
                $mbRead = ($totalRead / 1MB).ToString("0.0")
                $mbTotal = if ($totalBytes -gt 0) { ($totalBytes / 1MB).ToString("0.0") } else { "???" }
                $elapsedSec = [math]::Max($stopwatch.Elapsed.TotalSeconds, 0.001)
                $speed = ($totalRead / 1MB / $elapsedSec).ToString("0.0")

                $filledLength = [int](($percent / 100) * 20)
                $arrow = if ($filledLength -gt 0) { ">" } else { "" }
                $bar = ("=" * [math]::Max(0, $filledLength - 1)) + $arrow
                $bar = $bar.PadRight(20, ' ')

                $etaStr = ""
                if ($totalBytes -gt 0 -and ($totalRead / $elapsedSec) -gt 0) {
                    $remainingSec = [math]::Round(($totalBytes - $totalRead) / ($totalRead / $elapsedSec))
                    $etaStr = " [ETA: ${remainingSec}s]"
                }

                Write-Host -NoNewline ("`r  [$bar] $percent% ($mbRead / $mbTotal MB) | $speed MB/s$etaStr   ") -ForegroundColor DarkCyan
                $lastUiUpdate.Restart()
            }
        }

        $fileStream.Close()
        $fileStream = $null
        $stream.Close()
        $stream = $null
        $totalMb = ($totalRead / 1MB).ToString("0.0")
        $totalSec = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
        Write-Host "`r  [OK] Download complete! ($totalMb MB downloaded in ${totalSec}s)                              " -ForegroundColor Green
        $downloadSuccess = $true
    }
    catch {
        Write-Host "`r  [WARNING] Streaming download encountered an issue: $($_.Exception.Message). Attempting WebClient fallback..." -ForegroundColor Yellow
        if ($fileStream) { $fileStream.Dispose(); $fileStream = $null }
        if ($stream) { $stream.Dispose(); $stream = $null }
        if ($client) { $client.Dispose(); $client = $null }

        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($assetInfo.DownloadUrl, $tempArchive)
            $webClient.Dispose()
            if ((Test-Path $tempArchive) -and ((Get-Item $tempArchive).Length -gt 0)) {
                Write-Host "  [OK] Download complete! (Fallback successful)                                   " -ForegroundColor Green
                $downloadSuccess = $true
            } else {
                throw "Downloaded file was empty or missing."
            }
        } catch {
            Write-Host "`r  [ERROR] Fallback download failed: $_" -ForegroundColor Red
            Write-Host "  URL: $($assetInfo.DownloadUrl)" -ForegroundColor Yellow
            Write-Host "  Please ensure the release package exists and is published at https://github.com/$RepoSlug/releases.`n" -ForegroundColor Yellow
            if (Test-Path $tempArchive) { Remove-Item $tempArchive -Force -ErrorAction SilentlyContinue }
            $downloadSuccess = $false
        }
    }
    finally {
        if ($fileStream) { $fileStream.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($client) { $client.Dispose() }
    }

    # Ensure Phase 2 actually succeeded before attempting Phase 3
    if (-not $downloadSuccess -or -not (Test-Path $tempArchive) -or (Get-Item $tempArchive).Length -eq 0) {
        Write-Host "`n[FATAL ERROR] MVTools release download was incomplete or failed. Extraction aborted.`n" -ForegroundColor Red
        if (Test-Path $tempArchive) { Remove-Item $tempArchive -Force -ErrorAction SilentlyContinue }
        return $null
    }

    # Phase 3: Extraction and binary placement
    Write-Host ("`n[3/3] Extracting {0} binaries..." -f $archLabel) -ForegroundColor Cyan

    $tempExtractDir = Join-Path $env:TEMP ("mvtools_extract_{0}" -f [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempExtractDir -Force | Out-Null

    try {
        # Resolve extraction utility: 7-Zip (with automated portable acquisition) or Windows bsdtar for non-7z
        $extractorExe = Ensure-7ZipExtractor -TargetPotPlayerDir $TargetDir
        $extractorType = if ($extractorExe) { "7z" } else { $null }

        if (-not $extractorExe -and $assetInfo.FileName -notmatch '(?i)\.7z$') {
            $winDir = if ($env:WINDIR) { $env:WINDIR } else { [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Windows) }
            $cmdTar = Get-Command tar.exe -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cmdTar) {
                $extractorExe = $cmdTar.Source
                $extractorType = "tar"
            } elseif (Test-Path (Join-Path $winDir "System32\tar.exe")) {
                $extractorExe = Join-Path $winDir "System32\tar.exe"
                $extractorType = "tar"
            }
        }

        if ($extractorType -eq "7z") {
            Write-Host "  -> Decompressing using 7-Zip ($extractorExe)..." -ForegroundColor Gray
            & $extractorExe x "$tempArchive" "-o$tempExtractDir" -y | Out-Null
        } elseif ($extractorType -eq "tar") {
            Write-Host "  -> Decompressing using Windows bsdtar ($extractorExe)..." -ForegroundColor Gray
            & $extractorExe -xf "$tempArchive" -C "$tempExtractDir"
        } elseif ($assetInfo.FileName -match '(?i)\.zip$') {
            Write-Host "  -> Decompressing using PowerShell Expand-Archive..." -ForegroundColor Gray
            Expand-Archive -Path $tempArchive -DestinationPath $tempExtractDir -Force
        } else {
            throw "No suitable decompression utility found! .7z release archives require 7-Zip (Windows tar.exe does not support LZMA/LZMA2)."
        }

        $allExtracted = Get-ChildItem -Path $tempExtractDir -Recurse -File
        $targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetDir

        if ($targetArch -eq "x64") {
            # Priority 1: Binaries under \x64\msvc\ (official upstream pinterf/mvtools layout)
            $archPool = $allExtracted | Where-Object { $_.DirectoryName -match '(?i)[\\/]x64[\\/]msvc([\\/]|$)' }
            if (-not $archPool) {
                # Priority 2: Binaries under \x64\
                $archPool = $allExtracted | Where-Object { $_.DirectoryName -match '(?i)[\\/]x64([\\/]|$)' -and $_.DirectoryName -notmatch '(?i)[\\/]x86([\\/]|$)' }
            }
            if (-not $archPool) {
                $archPool = $allExtracted
            }
        } else {
            # ARM64: Binaries located under an 'ARM64' directory
            $archPool = $allExtracted | Where-Object { $_.DirectoryName -match '(?i)ARM64' }
            if (-not $archPool) {
                $archPool = $allExtracted
            }
        }

        $cpuDll = $archPool | Where-Object { $_.Name -ieq "mvtools2.dll" } | Select-Object -First 1
        $gpuDll = $archPool | Where-Object { $_.Name -ieq "mvtools2_d3d12.dll" } | Select-Object -First 1
        $depanDll = $archPool | Where-Object { $_.Name -ieq "DePan.dll" } | Select-Object -First 1
        $depanEstDll = $archPool | Where-Object { $_.Name -ieq "DePanEstimate.dll" } | Select-Object -First 1

        if (-not $cpuDll) {
            throw "Could not locate 'mvtools2.dll' inside the downloaded release archive!"
        }

        # Destination directory
        $deployDir = if (-not [string]::IsNullOrWhiteSpace($TargetDir)) { $TargetDir } else { $ScriptDir }
        if (-not (Test-Path $deployDir)) {
            New-Item -ItemType Directory -Path $deployDir -Force | Out-Null
        }

        Copy-Item -Path $cpuDll.FullName -Destination (Join-Path $deployDir "mvtools2.dll") -Force
        Write-Host ("  -> Deployed mvtools2.dll ({0} CPU SIMD) to: {1}" -f $archLabel, $deployDir) -ForegroundColor Green

        if ($gpuDll) {
            Copy-Item -Path $gpuDll.FullName -Destination (Join-Path $deployDir "mvtools2_d3d12.dll") -Force
            Write-Host "  -> Deployed mvtools2_d3d12.dll (Direct3D 12 GPU) to: $deployDir" -ForegroundColor Green
        } else {
            Write-Host "  -> mvtools2_d3d12.dll not present in archive (CPU-only build package)." -ForegroundColor Gray
        }

        if ($depanDll) {
            Copy-Item -Path $depanDll.FullName -Destination (Join-Path $deployDir "DePan.dll") -Force
        }
        if ($depanEstDll) {
            Copy-Item -Path $depanEstDll.FullName -Destination (Join-Path $deployDir "DePanEstimate.dll") -Force
        }

        # Deploy AviSynth profiles if present in the release archive
        $avsFiles = $allExtracted | Where-Object { $_.Extension -ieq ".avs" }
        if ($avsFiles -and $avsFiles.Count -gt 0) {
            $avsTargetDirs = @()
            if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
                $avsTargetDirs += (Join-Path $RepoRoot "AviSynth")
            }
            if (-not [string]::IsNullOrWhiteSpace($ScriptDir)) {
                $avsTargetDirs += (Join-Path $ScriptDir "AviSynth")
            }
            if (-not [string]::IsNullOrWhiteSpace($TargetDir)) {
                $avsTargetDirs += (Join-Path $TargetDir "AviSynth")
            }
            foreach ($tDir in ($avsTargetDirs | Select-Object -Unique)) {
                if (-not (Test-Path $tDir)) {
                    New-Item -ItemType Directory -Path $tDir -Force | Out-Null
                }
                foreach ($avs in $avsFiles) {
                    Copy-Item -Path $avs.FullName -Destination (Join-Path $tDir $avs.Name) -Force
                }
                Write-Host "  -> Deployed $($avsFiles.Count) AviSynth profile(s) to: $tDir" -ForegroundColor Green
            }
        }

        # Deploy PresentMon executable if present in archive and missing in Benchmarks
        $pmExe = $allExtracted | Where-Object { $_.Name -match '(?i)^PresentMon.*\.exe$' } | Select-Object -First 1
        if ($pmExe) {
            $pmTarget = Join-Path $ScriptDir $pmExe.Name
            if (-not (Test-Path $pmTarget)) {
                Copy-Item -Path $pmExe.FullName -Destination $pmTarget -Force
                Write-Host "  -> Deployed $($pmExe.Name) to: $ScriptDir" -ForegroundColor Green
            }
        }

        Write-Host ("`n  [OK] MVTools {0} binaries deployed successfully to: {1}`n" -f $archLabel, $deployDir) -ForegroundColor Green
        return $deployDir
    }
    catch {
        Write-Host "  [ERROR] Extraction and deployment failed: $_" -ForegroundColor Red
        return $null
    }
    finally {
        if (Test-Path $tempArchive) { Remove-Item $tempArchive -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempExtractDir) { Remove-Item $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ---------------------------------------------------------
# HELPER: Discover Latest AviSynth+ Release Asset from GitHub
# ---------------------------------------------------------
function Get-AviSynthPlusLatestReleaseAsset {
    param(
        [string]$RepoSlug = "AviSynth/AviSynthPlus",
        [string]$ReleaseTag = "latest"
    )

    $ReleaseInfo = [ordered]@{
        TagName     = ""
        DownloadUrl = ""
        FileName    = ""
        Size        = 0
        Source      = "GitHubAPI"
    }

    $ApiUrl = if ($ReleaseTag -eq "latest") {
        "https://api.github.com/repos/$RepoSlug/releases/latest"
    } else {
        "https://api.github.com/repos/$RepoSlug/releases/tags/$ReleaseTag"
    }

    try {
        $uaVersion = if ($Script:HarnessVersion) { $Script:HarnessVersion } else { "2.3.0" }
        $headers = @{
            "User-Agent" = "MvToolsBenchmarkHarness/$uaVersion"
            "Accept"     = "application/vnd.github.v3+json"
        }
        $release = Invoke-RestMethod -Uri $ApiUrl -Headers $headers -TimeoutSec 15 -ErrorAction Stop
        if ($release -and $release.assets -and $release.assets.Count -gt 0) {
            $ReleaseInfo.TagName = if ($release.tag_name) { $release.tag_name } else { $ReleaseTag }

            # Priority 1: Match filesonly archive ending in .7z (excluding macOS)
            $asset = $release.assets | Where-Object { 
                $_.name -match '(?i)filesonly.*\.7z$' -and $_.name -notmatch '(?i)macOS' 
            } | Select-Object -First 1

            # Priority 2: Any filesonly archive (excluding macOS)
            if (-not $asset) {
                $asset = $release.assets | Where-Object { 
                    $_.name -match '(?i)filesonly' -and $_.name -notmatch '(?i)macOS' 
                } | Select-Object -First 1
            }

            # Priority 3: Any .7z archive (excluding macOS)
            if (-not $asset) {
                $asset = $release.assets | Where-Object { 
                    $_.name -match '(?i)\.7z$' -and $_.name -notmatch '(?i)macOS' 
                } | Select-Object -First 1
            }

            if ($asset) {
                $ReleaseInfo.DownloadUrl = $asset.browser_download_url
                $ReleaseInfo.FileName = $asset.name
                $ReleaseInfo.Size = $asset.size
                return $ReleaseInfo
            }
        }
    } catch {
        Write-Host "  -> AviSynth+ GitHub API notice: $($_.Exception.Message)" -ForegroundColor Gray
    }

    # Dynamic web release discovery fallback (zero hardcoded versions/filenames)
    try {
        $webTargetUrl = if ($ReleaseTag -eq "latest") {
            "https://github.com/$RepoSlug/releases/latest"
        } else {
            "https://github.com/$RepoSlug/releases/tag/$ReleaseTag"
        }
        $req = [System.Net.HttpWebRequest]::Create($webTargetUrl)
        $req.AllowAutoRedirect = $true
        $req.UserAgent = "MvToolsBenchmarkHarness/$uaVersion"
        $req.Timeout = 10000
        $resp = $req.GetResponse()
        $finalUrl = $resp.ResponseUri.AbsoluteUri
        $resp.Close()

        $resolvedTag = Split-Path $finalUrl -Leaf
        if (-not [string]::IsNullOrWhiteSpace($resolvedTag)) {
            $ReleaseInfo.TagName = $resolvedTag
            $ReleaseInfo.Source = "GitHubWebDiscovery"

            $assetsUrl = "https://github.com/$RepoSlug/releases/expanded_assets/$resolvedTag"
            $assetsReq = [System.Net.HttpWebRequest]::Create($assetsUrl)
            $assetsReq.UserAgent = "MvToolsBenchmarkHarness/$uaVersion"
            $assetsReq.Timeout = 10000
            $assetsResp = $assetsReq.GetResponse()
            $stream = $assetsResp.GetResponseStream()
            $reader = [System.IO.StreamReader]::new($stream)
            $html = $reader.ReadToEnd()
            $reader.Close()
            $assetsResp.Close()

            $matches = [regex]::Matches($html, 'href="([^"]+/releases/download/[^"]+)"')
            $foundUrls = @()
            foreach ($m in $matches) {
                $rel = $m.Groups[1].Value
                if ($rel -notmatch '^https:') { $rel = "https://github.com$rel" }
                $foundUrls += $rel
            }
            $foundUrls = $foundUrls | Select-Object -Unique

            $selectedUrl = $foundUrls | Where-Object { 
                $_ -match '(?i)filesonly.*\.7z$' -and $_ -notmatch '(?i)macOS' 
            } | Select-Object -First 1

            if (-not $selectedUrl) {
                $selectedUrl = $foundUrls | Where-Object { 
                    $_ -match '(?i)filesonly' -and $_ -notmatch '(?i)macOS' 
                } | Select-Object -First 1
            }

            if (-not $selectedUrl) {
                $selectedUrl = $foundUrls | Where-Object { 
                    $_ -match '(?i)\.7z$' -and $_ -notmatch '(?i)macOS' 
                } | Select-Object -First 1
            }

            if ($selectedUrl) {
                $ReleaseInfo.DownloadUrl = $selectedUrl
                $ReleaseInfo.FileName = [System.IO.Path]::GetFileName($selectedUrl)
                return $ReleaseInfo
            }
        }
    } catch {
        Write-Host "  -> AviSynth+ web discovery notice: $($_.Exception.Message)" -ForegroundColor Gray
    }

    return $null
}

# ---------------------------------------------------------
# HELPER: Automated Acquisition & Deployment of AviSynth+ Release
# ---------------------------------------------------------
function Install-AviSynthPlusRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPotPlayerDir,

        [Parameter(Mandatory = $false)]
        [string]$RepoSlug = "AviSynth/AviSynthPlus",

        [Parameter(Mandatory = $false)]
        [string]$ReleaseTag = "latest",

        [Parameter(Mandatory = $false)]
        [string]$Arch = ""
    )

    if (-not (Test-Path $TargetPotPlayerDir)) {
        Write-Host "  [ERROR] Target PotPlayer directory '$TargetPotPlayerDir' does not exist." -ForegroundColor Red
        return $null
    }

    # Resolve target architecture dynamically (arm64, x64, x86)
    $targetArch = if (-not [string]::IsNullOrWhiteSpace($Arch)) {
        $Arch.ToLower().Trim()
    } else {
        Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetPotPlayerDir
    }

    # Initialize TLS 1.2 and System.Net.Http assembly (required for Windows PowerShell 5.1 compatibility)
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    } catch {}
    try {
        Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    } catch {}

    Write-Host "`n========================================================" -ForegroundColor Cyan
    Write-Host " AUTOMATED AVISYNTH+ ACQUISITION & SETUP" -ForegroundColor Cyan
    Write-Host " Repository: https://github.com/$RepoSlug" -ForegroundColor Gray
    Write-Host " Target Architecture: $targetArch" -ForegroundColor Gray
    Write-Host " Destination: $TargetPotPlayerDir" -ForegroundColor Gray
    Write-Host "========================================================`n" -ForegroundColor Cyan

    Write-Host "[1/3] Resolving latest AviSynth+ 'filesonly' release package..." -ForegroundColor Cyan
    $assetInfo = Get-AviSynthPlusLatestReleaseAsset -RepoSlug $RepoSlug -ReleaseTag $ReleaseTag
    if (-not $assetInfo -or [string]::IsNullOrWhiteSpace($assetInfo.DownloadUrl)) {
        Write-Host "  [ERROR] Could not resolve AviSynth+ release asset from GitHub ($RepoSlug)." -ForegroundColor Red
        return $null
    }

    Write-Host "  -> Release Tag: $($assetInfo.TagName)" -ForegroundColor White
    Write-Host "  -> Asset Name:  $($assetInfo.FileName)" -ForegroundColor White
    Write-Host "  -> Source:      $($assetInfo.Source)" -ForegroundColor Gray
    Write-Host "  -> URL:         $($assetInfo.DownloadUrl)" -ForegroundColor Gray

    # Prompt user permission before downloading
    $sizeDesc = if ($assetInfo.Size -gt 0) { ("{0:N1} MB" -f ($assetInfo.Size / 1MB)) } else { "" }
    $tempArchive = Join-Path $env:TEMP ("avisynth_dl_{0}_{1}" -f [System.Guid]::NewGuid().ToString("N"), $assetInfo.FileName)
    if (-not (Confirm-DownloadPermission -ItemName "AviSynth+ Release ($($assetInfo.FileName))" -SourceUrl $assetInfo.DownloadUrl -TargetDir $tempArchive -SizeDesc $sizeDesc)) {
        return $null
    }

    # Phase 2: Download with live stream progress
    Write-Host "`n[2/3] Downloading $($assetInfo.FileName)..." -ForegroundColor Cyan

    $client = $null
    $fileStream = $null
    $stream = $null
    $downloadSuccess = $false

    try {
        $client = New-Object System.Net.Http.HttpClient
        # 1 corresponds to HttpCompletionOption.ResponseHeadersRead
        $response = $client.GetAsync($assetInfo.DownloadUrl, 1).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "HTTP $($response.StatusCode) ($($response.ReasonPhrase)) while accessing $($assetInfo.DownloadUrl)"
        }

        $totalBytes = $response.Content.Headers.ContentLength
        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $fileStream = [System.IO.File]::Create($tempArchive)

        $buffer = New-Object byte[] 65536
        $totalRead = 0
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $lastUiUpdate = [System.Diagnostics.Stopwatch]::StartNew()

        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $read)
            $totalRead += $read

            if ($lastUiUpdate.ElapsedMilliseconds -ge 100 -or $totalRead -eq $totalBytes) {
                $percent = if ($totalBytes -gt 0) { [math]::Round(($totalRead / $totalBytes) * 100) } else { 0 }
                $mbRead = ($totalRead / 1MB).ToString("0.0")
                $mbTotal = if ($totalBytes -gt 0) { ($totalBytes / 1MB).ToString("0.0") } else { "???" }
                $elapsedSec = [math]::Max($stopwatch.Elapsed.TotalSeconds, 0.001)
                $speed = ($totalRead / 1MB / $elapsedSec).ToString("0.0")

                $filledLength = [int](($percent / 100) * 20)
                $arrow = if ($filledLength -gt 0) { ">" } else { "" }
                $bar = ("=" * [math]::Max(0, $filledLength - 1)) + $arrow
                $bar = $bar.PadRight(20, ' ')

                $etaStr = ""
                if ($totalBytes -gt 0 -and ($totalRead / $elapsedSec) -gt 0) {
                    $remainingSec = [math]::Round(($totalBytes - $totalRead) / ($totalRead / $elapsedSec))
                    $etaStr = " [ETA: ${remainingSec}s]"
                }

                Write-Host -NoNewline ("`r  [$bar] $percent% ($mbRead / $mbTotal MB) | $speed MB/s$etaStr   ") -ForegroundColor DarkCyan
                $lastUiUpdate.Restart()
            }
        }

        $fileStream.Close()
        $fileStream = $null
        $stream.Close()
        $stream = $null
        $totalMb = ($totalRead / 1MB).ToString("0.0")
        $totalSec = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
        Write-Host "`r  [OK] Download complete! ($totalMb MB downloaded in ${totalSec}s)                              " -ForegroundColor Green
        $downloadSuccess = $true
    }
    catch {
        Write-Host "`r  [WARNING] Streaming download encountered an issue: $($_.Exception.Message). Attempting WebClient fallback..." -ForegroundColor Yellow
        if ($fileStream) { $fileStream.Dispose(); $fileStream = $null }
        if ($stream) { $stream.Dispose(); $stream = $null }
        if ($client) { $client.Dispose(); $client = $null }

        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($assetInfo.DownloadUrl, $tempArchive)
            $webClient.Dispose()
            if ((Test-Path $tempArchive) -and ((Get-Item $tempArchive).Length -gt 0)) {
                Write-Host "  [OK] Download complete! (Fallback successful)                                   " -ForegroundColor Green
                $downloadSuccess = $true
            } else {
                throw "Downloaded file was empty or missing."
            }
        } catch {
            Write-Host "`r  [ERROR] Fallback download failed: $_" -ForegroundColor Red
            if (Test-Path $tempArchive) { Remove-Item $tempArchive -Force -ErrorAction SilentlyContinue }
            $downloadSuccess = $false
        }
    }
    finally {
        if ($fileStream) { $fileStream.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($client) { $client.Dispose() }
    }

    if (-not $downloadSuccess -or -not (Test-Path $tempArchive) -or (Get-Item $tempArchive).Length -eq 0) {
        Write-Host "`n[FATAL ERROR] AviSynth+ release download was incomplete or failed. Extraction aborted.`n" -ForegroundColor Red
        if (Test-Path $tempArchive) { Remove-Item $tempArchive -Force -ErrorAction SilentlyContinue }
        return $null
    }

    # Phase 3: Extraction and AviSynth.dll binary placement
    Write-Host "`n[3/3] Extracting $targetArch AviSynth.dll binary..." -ForegroundColor Cyan

    $tempExtractDir = Join-Path $env:TEMP ("avisynth_extract_{0}" -f [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempExtractDir -Force | Out-Null

    try {
        # Resolve extraction utility: 7-Zip (with automated portable acquisition) or Windows bsdtar for non-7z
        $extractorExe = Ensure-7ZipExtractor -TargetPotPlayerDir $TargetDir
        $extractorType = if ($extractorExe) { "7z" } else { $null }

        if (-not $extractorExe -and $assetInfo.FileName -notmatch '(?i)\.7z$') {
            $winDir = if ($env:WINDIR) { $env:WINDIR } else { [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Windows) }
            $cmdTar = Get-Command tar.exe -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cmdTar) {
                $extractorExe = $cmdTar.Source
                $extractorType = "tar"
            } elseif (-not [string]::IsNullOrWhiteSpace($winDir) -and (Test-Path (Join-Path $winDir "System32\tar.exe"))) {
                $extractorExe = Join-Path $winDir "System32\tar.exe"
                $extractorType = "tar"
            }
        }

        if ($extractorType -eq "7z") {
            Write-Host "  -> Decompressing using 7-Zip ($extractorExe)..." -ForegroundColor Gray
            & $extractorExe x "$tempArchive" "-o$tempExtractDir" -y | Out-Null
        } elseif ($extractorType -eq "tar") {
            Write-Host "  -> Decompressing using Windows bsdtar ($extractorExe)..." -ForegroundColor Gray
            & $extractorExe -xf "$tempArchive" -C "$tempExtractDir"
        } elseif ($assetInfo.FileName -match '(?i)\.zip$') {
            Write-Host "  -> Decompressing using PowerShell Expand-Archive..." -ForegroundColor Gray
            Expand-Archive -Path $tempArchive -DestinationPath $tempExtractDir -Force
        } else {
            throw "No suitable decompression utility found! .7z release archives require 7-Zip (Windows tar.exe does not support LZMA/LZMA2)."
        }

        # Locate AviSynth.dll under the requested architecture directory (arm64\bin\AviSynth.dll for ARM64, x64\AviSynth.dll for x64)
        $allExtracted = Get-ChildItem -Path $tempExtractDir -Recurse -File

        # Priority 1: Exact architecture directory match (e.g., \x64\AviSynth.dll or \arm64\bin\AviSynth.dll)
        if ($targetArch -eq "x64") {
            $targetDll = $allExtracted | Where-Object { 
                $_.Name -ieq "AviSynth.dll" -and 
                $_.DirectoryName -match '(?i)[\\/]x64([\\/]|$)' -and
                $_.DirectoryName -notmatch '(?i)[\\/]x86([\\/]|$)'
            } | Select-Object -First 1
        } else {
            $targetDll = $allExtracted | Where-Object { 
                $_.Name -ieq "AviSynth.dll" -and 
                $_.DirectoryName -match "(?i)[\\/]$([regex]::Escape($targetArch))[\\/]bin" 
            } | Select-Object -First 1
        }

        # Priority 2: Match target arch directory anywhere in directory path
        if (-not $targetDll) {
            $targetDll = $allExtracted | Where-Object { 
                $_.Name -ieq "AviSynth.dll" -and 
                $_.DirectoryName -match "(?i)[\\/]$([regex]::Escape($targetArch))([\\/]|$)" 
            } | Select-Object -First 1
        }

        # Priority 3: Fall back to any AviSynth.dll extracted
        if (-not $targetDll) {
            $targetDll = $allExtracted | Where-Object { $_.Name -ieq "AviSynth.dll" } | Select-Object -First 1
        }

        if (-not $targetDll) {
            throw "Could not locate 'AviSynth.dll' for architecture '$targetArch' inside the downloaded release archive!"
        }

        # Verify binary architecture directly from the extracted PE header (guarantees native machine type)
        $peMachine = Get-PeMachine -FilePath $targetDll.FullName
        $peArchDesc = switch ($peMachine) {
            0xAA64 { "ARM64 (0xAA64)" }
            0x8664 { "x64 (0x8664)" }
            0x014C { "x86 (0x014C)" }
            Default { "Unknown (0x{0:X4})" -f $peMachine }
        }

        $expectedMachine = switch ($targetArch) {
            "arm64" { 0xAA64 }
            "x64"   { 0x8664 }
            "x86"   { 0x014C }
            Default { 0 }
        }

        if ($expectedMachine -ne 0 -and $peMachine -ne $expectedMachine) {
            Write-Host "  [WARNING] Initial candidate '$($targetDll.FullName)' machine ($peArchDesc) does not match expected target architecture '$targetArch'!" -ForegroundColor DarkYellow
            # Search all extracted AviSynth.dll files for the one that has the exact PE machine
            $exactDll = $allExtracted | Where-Object { 
                $_.Name -ieq "AviSynth.dll" -and (Get-PeMachine -FilePath $_.FullName) -eq $expectedMachine 
            } | Select-Object -First 1

            if ($exactDll) {
                $targetDll = $exactDll
                $peMachine = $expectedMachine
                $peArchDesc = switch ($peMachine) {
                    0xAA64 { "ARM64 (0xAA64)" }
                    0x8664 { "x64 (0x8664)" }
                    0x014C { "x86 (0x014C)" }
                }
                Write-Host "  -> Successfully matched alternative candidate with exact PE Machine: $peArchDesc" -ForegroundColor Green
            } else {
                throw "PE Header Verification Failure: Extracted AviSynth.dll machine is $peArchDesc, but expected $targetArch binary! Incompatible binary will cause STATUS_INVALID_IMAGE_FORMAT (0xc000007b)."
            }
        }

        Write-Host "  -> Verified AviSynth.dll PE Machine: $peArchDesc (100% native match for $targetArch)" -ForegroundColor Green

        $destDll = Join-Path $TargetPotPlayerDir "AviSynth.dll"
        Copy-Item -Path $targetDll.FullName -Destination $destDll -Force -ErrorAction Stop
        Write-Host "  -> Deployed AviSynth.dll ($targetArch) to: $destDll" -ForegroundColor Green

        # Deploy built-in AviSynth plugins (e.g., ImageSeq.dll, TimeStretch.dll, etc.) to AviSynth subfolder if present
        $builtInPlugins = $allExtracted | Where-Object { 
            $_.Extension -ieq ".dll" -and 
            $_.DirectoryName -match "(?i)[\\/]$([regex]::Escape($targetArch))[\\/]lib[\\/]avisynth" 
        }
        if ($builtInPlugins -and $builtInPlugins.Count -gt 0) {
            $potAvsSubDir = Join-Path $TargetPotPlayerDir "AviSynth"
            if (-not (Test-Path $potAvsSubDir)) {
                New-Item -ItemType Directory -Path $potAvsSubDir -Force | Out-Null
            }
            foreach ($plug in $builtInPlugins) {
                Copy-Item -Path $plug.FullName -Destination (Join-Path $potAvsSubDir $plug.Name) -Force -ErrorAction SilentlyContinue
            }
            Write-Host "  -> Deployed $($builtInPlugins.Count) built-in AviSynth plugin(s) to: $potAvsSubDir" -ForegroundColor Green
        }

        return $destDll
    }
    catch {
        Write-Host "  [ERROR] AviSynth+ extraction and deployment failed: $_" -ForegroundColor Red
        return $null
    }
    finally {
        if (Test-Path $tempArchive) { Remove-Item $tempArchive -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempExtractDir) { Remove-Item $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

# ---------------------------------------------------------
# HELPER: List Available AviSynth Profiles Across Potential Locations
# ---------------------------------------------------------
function Get-AvailableAviSynthProfiles {
    param(
        [string]$RepoRoot = ".",
        [string]$ScriptDir = ""
    )
    $candidateDirs = @()
    if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $candidateDirs += (Join-Path $RepoRoot "AviSynth")
        $candidateDirs += (Join-Path $RepoRoot "Release\AviSynth")
    }
    if (-not [string]::IsNullOrWhiteSpace($ScriptDir)) {
        $candidateDirs += (Join-Path $ScriptDir "AviSynth")
        $candidateDirs += (Join-Path $ScriptDir "..\AviSynth")
        $candidateDirs += (Join-Path $ScriptDir "..\Release\AviSynth")
    }
    if (-not [string]::IsNullOrWhiteSpace($ScriptDir) -and $ScriptDir -ne $RepoRoot) {
        $candidateDirs += (Join-Path $ScriptDir "AviSynth")
        $candidateDirs += (Join-Path $ScriptDir "..\AviSynth")
        $candidateDirs += (Join-Path $ScriptDir "..\Release\AviSynth")
    }
    if ($candidateDirs.Count -eq 0) {
        $candidateDirs += @(".\AviSynth", "..\AviSynth", "..\Release\AviSynth")
    }

    $seenNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $profiles = @()

    foreach ($d in ($candidateDirs | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($d) -and (Test-Path $d)) {
            $checkFiles = Get-ChildItem -Path $d -Filter "*.avs" -ErrorAction SilentlyContinue
            if ($checkFiles) {
                foreach ($f in $checkFiles) {
                    if ($seenNames.Add($f.Name)) {
                        $content = Get-Content $f.FullName -Raw
                        $tier = if ($f.Name -match '(?i)Eco') { "Eco" }
                                elseif ($f.Name -match '(?i)MaxQuality|Quality') { "MaxQuality" }
                                elseif ($f.Name -match '(?i)Balanced') { "Balanced" }
                                else { "Custom" }

                        # Filter out stock/non-benchmark AviSynth scripts (e.g. ColorBars, TrueMotion stock samples)
                        $isBenchmarkProfile = ($tier -in @("Eco", "Balanced", "MaxQuality")) -or ($content -match '(?i)MAnalyse|MRecalculate|MBlockFPS|USE_GPU|#\s*Hardware:')
                        if (-not $isBenchmarkProfile) {
                            continue
                        }

                        $supportGpu = $content -match '(?i)USE_GPU'
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
                }
            }
        }
    }
    return ,($profiles | Sort-Object Name)
}

# ---------------------------------------------------------
# HELPER: Download AviSynth Profiles Directly from GitHub Repository Tree
# ---------------------------------------------------------
function Install-AviSynthProfilesFromRepo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetDir,
        [string]$RepoSlug = "tordona/mvtools",
        [string]$Branch = "mvtools_d3d12"
    )

    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }

    $apiUrl = "https://api.github.com/repos/$RepoSlug/contents/AviSynth?ref=$Branch"
    $uaVersion = if ($Script:HarnessVersion) { $Script:HarnessVersion } else { "2.3.0" }
    $headers = @{
        "User-Agent" = "MvToolsBenchmarkHarness/$uaVersion"
        "Accept"     = "application/vnd.github.v3+json"
    }

    $fileItems = @()
    try {
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 15 -ErrorAction Stop
        if ($response -is [array]) {
            $fileItems = $response | Where-Object { $_.type -eq "file" -and $_.name -like "*.avs" }
        }
    } catch {
        Write-Host "  -> GitHub API notice: $($_.Exception.Message). Falling back to direct raw file acquisition..." -ForegroundColor Gray
    }

    # If GitHub API was rate limited or empty, fallback to canonical profile manifest
    if (-not $fileItems -or $fileItems.Count -eq 0) {
        $canonicalProfiles = @(
            "Generic-x64-Eco.avs", "Generic-x64-Balanced.avs", "Generic-x64-MaxQuality.avs",
            "Snapdragon-X-Plus-Eco.avs", "Snapdragon-X-Plus-Balanced.avs", "Snapdragon-X-Plus-MaxQuality.avs",
            "Snapdragon-8cxGen3-Eco.avs", "Snapdragon-8cxGen3-Balanced.avs", "Snapdragon-8cxGen3-MaxQuality.avs",
            "Snapdragon-8cxGen2-Eco.avs", "Snapdragon-8cxGen2-Balanced.avs", "Snapdragon-8cxGen2-MaxQuality.avs",
            "Snapdragon-8cxGen1-Eco.avs", "Snapdragon-8cxGen1-Balanced.avs", "Snapdragon-8cxGen1-MaxQuality.avs",
            "Snapdragon-850-Eco.avs", "Snapdragon-850-Balanced.avs", "Snapdragon-850-MaxQuality.avs",
            "Snapdragon-7cGen2-Eco.avs", "Snapdragon-7cGen2-Balanced.avs", "Snapdragon-7cGen2-MaxQuality.avs"
        )
        $fileItems = $canonicalProfiles | ForEach-Object {
            [PSCustomObject]@{
                name         = $_
                download_url = "https://raw.githubusercontent.com/$RepoSlug/$Branch/AviSynth/$_"
            }
        }
    }

    $count = $fileItems.Count
    if (-not (Confirm-DownloadPermission -ItemName "AviSynth Benchmark Profiles ($count profiles from $RepoSlug)" -SourceUrl "https://github.com/$RepoSlug/tree/$Branch/AviSynth" -TargetDir $TargetDir -SizeDesc "~100 KB" -Bypass:$script:AutoDownloadMvTools)) {
        return 0
    }

    Write-Host "  -> Downloading $count AviSynth profile(s) from $RepoSlug ($Branch)..." -ForegroundColor Cyan
    $downloadSuccessCount = 0

    $webClient = New-Object System.Net.WebClient
    try {
        foreach ($f in $fileItems) {
            $destFile = Join-Path $TargetDir $f.name
            $url = if ($f.download_url) { $f.download_url } else { "https://raw.githubusercontent.com/$RepoSlug/$Branch/AviSynth/$($f.name)" }
            try {
                $webClient.DownloadFile($url, $destFile)
                if (Test-Path $destFile) {
                    $downloadSuccessCount++
                }
            } catch {
                Write-Host "     [WARNING] Failed to download $($f.name): $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    } finally {
        $webClient.Dispose()
    }

    return $downloadSuccessCount
}

# ---------------------------------------------------------
# HELPER: Ensure AviSynth Profiles (Directly downloads from tordona/mvtools AviSynth/ tree)
# ---------------------------------------------------------
function Ensure-AviSynthProfiles {
    param(
        [string]$RepoRoot = ".",
        [string]$ScriptDir = "",
        [string]$MvToolsRepo = "tordona/mvtools",
        [string]$ProfileBranch = "mvtools_d3d12",
        [string]$TargetPotPlayerDir = ""
    )

    $targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetPotPlayerDir
    $profiles = Get-AvailableAviSynthProfiles -RepoRoot $RepoRoot -ScriptDir $ScriptDir

    # Check if benchmark profiles suitable for the target architecture are present
    $hasArchProfiles = if ($targetArch -eq "x64") {
        @($profiles | Where-Object { $_.Platform -like "Generic-x64*" -or ($_.Platform -notlike "Snapdragon*" -and $_.Tier -in @("Eco", "Balanced", "MaxQuality")) }).Count -gt 0
    } else {
        @($profiles | Where-Object { $_.Platform -like "Snapdragon*" -or ($_.Platform -notlike "Generic-x64*" -and $_.Tier -in @("Eco", "Balanced", "MaxQuality")) }).Count -gt 0
    }

    if ($profiles -and $profiles.Count -gt 0 -and $hasArchProfiles) {
        return $profiles
    }

    $reason = if (-not $profiles -or $profiles.Count -eq 0) {
        "No .avs profiles found in AviSynth directory!"
    } else {
        "No $targetArch benchmark profiles (e.g. Generic-x64) found in AviSynth directory!"
    }

    Write-Host "`n[MISSING COMPONENT] $reason" -ForegroundColor Yellow
    Write-Host "AviSynth benchmark profiles are required for hardware detection and test execution." -ForegroundColor Gray
    Write-Host "Downloading latest profiles directly from GitHub (tordona/mvtools/tree/$ProfileBranch/AviSynth)..." -ForegroundColor Cyan

    $deployTarget = if (-not [string]::IsNullOrWhiteSpace($ScriptDir)) { 
        Join-Path $ScriptDir "AviSynth"
    } elseif (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        Join-Path $RepoRoot "AviSynth"
    } else { 
        ".\AviSynth" 
    }

    $downloaded = Install-AviSynthProfilesFromRepo -TargetDir $deployTarget -RepoSlug "tordona/mvtools" -Branch $ProfileBranch
    if ($downloaded -gt 0) {
        Write-Host "  -> Successfully deployed $downloaded AviSynth profile(s) to: $deployTarget" -ForegroundColor Green
        # Mirror to RepoRoot\AviSynth if separate
        if (-not [string]::IsNullOrWhiteSpace($RepoRoot) -and (Test-Path $RepoRoot)) {
            $altTarget = Join-Path $RepoRoot "AviSynth"
            if ($altTarget -ne $deployTarget) {
                if (-not (Test-Path $altTarget)) { New-Item -ItemType Directory -Path $altTarget -Force | Out-Null }
                Copy-Item -Path (Join-Path $deployTarget "*.avs") -Destination $altTarget -Force -ErrorAction SilentlyContinue
            }
        }
    }

    $profiles = @(Get-AvailableAviSynthProfiles -RepoRoot $RepoRoot -ScriptDir $ScriptDir)
    if (-not $profiles -or $profiles.Count -eq 0) {
        Write-Warning "No .avs profiles found in AviSynth directory after download attempt!"
    }
    return ,$profiles
}

# ---------------------------------------------------------
# HELPER: Deploy MVTools Binaries, AviSynth.dll, & Profiles to PotPlayer
# ---------------------------------------------------------
function Install-MvToolsToPotPlayer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPotPlayerDir,
        [string]$MvToolsSourceDir = "",
        [string]$RepoRoot = ".",
        [string]$ScriptDir = "",
        [string]$MvToolsRepo = "",
        [string]$AviSynthRepo = "AviSynth/AviSynthPlus"
    )

    if (-not (Test-Path $TargetPotPlayerDir)) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($MvToolsRepo)) {
        $targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetPotPlayerDir
        $MvToolsRepo = if ($targetArch -eq "x64") { "pinterf/mvtools" } else { "tordona/mvtools" }
    }

    Write-Host "`n[SETUP] Deploying MVTools & AviSynth components to PotPlayer: $TargetPotPlayerDir" -ForegroundColor Cyan

    # 1. Resolve source of MVTools binaries (deployed directory or local ScriptDir)
    $candidateDirs = @()
    if (-not [string]::IsNullOrWhiteSpace($MvToolsSourceDir)) { $candidateDirs += $MvToolsSourceDir }
    if (-not [string]::IsNullOrWhiteSpace($ScriptDir)) { $candidateDirs += $ScriptDir }
    if (-not [string]::IsNullOrWhiteSpace($TargetPotPlayerDir)) { $candidateDirs += $TargetPotPlayerDir }

    $resolvedSourceDir = $null
    foreach ($cand in ($candidateDirs | Select-Object -Unique)) {
        if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path (Join-Path $cand "mvtools2.dll"))) {
            $resolvedSourceDir = $cand
            break
        }
    }

    # If MVTools binaries are not found locally, attempt automated acquisition from GitHub
    if (-not $resolvedSourceDir -and -not (Test-Path (Join-Path $TargetPotPlayerDir "mvtools2.dll"))) {
        $hostArch = (Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetPotPlayerDir).ToUpper(); Write-Host "  -> MVTools $hostArch binaries not found locally. Initiating automated acquisition from GitHub ($MvToolsRepo)..." -ForegroundColor Cyan
        $dlDir = Install-MvToolsRelease -TargetDir $TargetPotPlayerDir -RepoSlug $MvToolsRepo
        if ($dlDir -and (Test-Path (Join-Path $TargetPotPlayerDir "mvtools2.dll"))) {
            $resolvedSourceDir = $TargetPotPlayerDir
        }
    }

    # 2. Deploy MVTools DLLs directly into PotPlayer directory
    $deployedCount = 0
    if ($resolvedSourceDir) {
        $binaries = if ($targetArch -eq "x64") { @("mvtools2.dll", "DePan.dll", "DePanEstimate.dll") } else { @("mvtools2.dll", "mvtools2_d3d12.dll", "DePan.dll", "DePanEstimate.dll") }
        foreach ($bin in $binaries) {
            $src = Join-Path $resolvedSourceDir $bin
            $dst = Join-Path $TargetPotPlayerDir $bin
            if ((Test-Path $src) -and ($src -ne $dst)) {
                try {
                    Copy-Item -Path $src -Destination $dst -Force -ErrorAction Stop
                    $deployedCount++
                } catch {
                    Write-Warning "Could not copy $bin to '$TargetPotPlayerDir': $($_.Exception.Message)"
                }
            } elseif (Test-Path $dst) {
                $deployedCount++
            }
        }
        Write-Host "  -> Verified/Installed $deployedCount MVTools binary file(s) in PotPlayer directory." -ForegroundColor Green
    } else {
        Write-Warning "Could not find or acquire MVTools binaries to install into PotPlayer directory."
    }

    # 3. Ensure native AviSynth.dll is present in PotPlayer directory (required for PotPlayer AviSynth engine)
    $targetPotArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetPotPlayerDir
    $expectedMachine = switch ($targetPotArch) {
        "arm64" { 0xAA64 }
        "x64"   { 0x8664 }
        "x86"   { 0x014C }
        Default { 0 }
    }

    $potAviSynthDll = Join-Path $TargetPotPlayerDir "AviSynth.dll"
    $needAviSynthAcquisition = $false

    if (Test-Path $potAviSynthDll) {
        $existingMach = Get-PeMachine -FilePath $potAviSynthDll
        $existingDesc = switch ($existingMach) {
            0xAA64 { "ARM64 (0xAA64)" }
            0x8664 { "x64 (0x8664)" }
            0x014C { "x86 (0x014C)" }
            Default { "0x{0:X4}" -f $existingMach }
        }

        if ($expectedMachine -ne 0 -and $existingMach -ne $expectedMachine) {
            Write-Host "  [WARNING] Existing AviSynth.dll in PotPlayer directory ($existingDesc) does not match required PotPlayer architecture '$targetPotArch'!" -ForegroundColor DarkYellow
            Write-Host "  -> Removing mismatched binary to ensure clean native acquisition..." -ForegroundColor Yellow
            Remove-Item -Path $potAviSynthDll -Force -ErrorAction SilentlyContinue
            $needAviSynthAcquisition = $true
        } else {
            Write-Host "  -> AviSynth.dll verified in PotPlayer directory ($existingDesc)." -ForegroundColor Green
        }
    } else {
        $needAviSynthAcquisition = $true
    }

    if ($needAviSynthAcquisition) {
        $foundAviSynth = $null

        # Check system / environment standard paths dynamically without hardcoded drive letters
        $winDir = if ($env:WINDIR) { $env:WINDIR } else { [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Windows) }
        $systemLocations = @()
        if (-not [string]::IsNullOrWhiteSpace($winDir)) {
            $systemLocations += @(
                (Join-Path $winDir "System32\AviSynth.dll"),
                (Join-Path $winDir "SysWOW64\AviSynth.dll"),
                (Join-Path $winDir "AviSynth.dll")
            )
        }
        if ($env:ProgramFiles) {
            $systemLocations += @(
                (Join-Path ${env:ProgramFiles} "AviSynth+\AviSynth.dll"),
                (Join-Path ${env:ProgramFiles} "AviSynth\AviSynth.dll"),
                (Join-Path ${env:ProgramFiles} "DAUM\PotPlayer\AviSynth.dll")
            )
        }
        if (${env:ProgramFiles(x86)}) {
            $systemLocations += @(
                (Join-Path ${env:ProgramFiles(x86)} "AviSynth+\AviSynth.dll"),
                (Join-Path ${env:ProgramFiles(x86)} "AviSynth\AviSynth.dll"),
                (Join-Path ${env:ProgramFiles(x86)} "DAUM\PotPlayer\AviSynth.dll")
            )
        }
        if ($env:LOCALAPPDATA) {
            $systemLocations += (Join-Path $env:LOCALAPPDATA "Programs\AviSynth\AviSynth.dll")
        }

        # Check PATH command resolution
        $cmdAs = Get-Command AviSynth.dll -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmdAs -and (Test-Path $cmdAs.Source)) {
            $candMach = Get-PeMachine -FilePath $cmdAs.Source
            if ($expectedMachine -eq 0 -or $candMach -eq $expectedMachine) {
                $foundAviSynth = $cmdAs.Source
            }
        }

        # Check standard environment locations
        if (-not $foundAviSynth) {
            foreach ($asLoc in $systemLocations) {
                if (Test-Path $asLoc) {
                    $candMach = Get-PeMachine -FilePath $asLoc
                    if ($expectedMachine -eq 0 -or $candMach -eq $expectedMachine) {
                        $foundAviSynth = $asLoc
                        break
                    }
                }
            }
        }

        # Check Windows Registry for installed AviSynth+ or PotPlayer
        if (-not $foundAviSynth) {
            $regKeys = @(
                "HKLM:\SOFTWARE\AviSynth",
                "HKLM:\SOFTWARE\WOW6432Node\AviSynth",
                "HKCU:\SOFTWARE\AviSynth",
                "HKCU:\SOFTWARE\Daum\PotPlayer64",
                "HKLM:\SOFTWARE\Daum\PotPlayer64",
                "HKCU:\SOFTWARE\Daum\PotPlayer",
                "HKLM:\SOFTWARE\Daum\PotPlayer"
            )
            foreach ($rk in $regKeys) {
                if (Test-Path $rk) {
                    $prop = Get-ItemProperty -Path $rk -ErrorAction SilentlyContinue
                    if ($prop.plugindir) {
                        $cand = Join-Path (Split-Path $prop.plugindir -Parent) "AviSynth.dll"
                        if (Test-Path $cand) {
                            $candMach = Get-PeMachine -FilePath $cand
                            if ($expectedMachine -eq 0 -or $candMach -eq $expectedMachine) {
                                $foundAviSynth = $cand; break
                            }
                        }
                    }
                    if ($prop.ProgramFolder) {
                        $cand = Join-Path $prop.ProgramFolder "AviSynth.dll"
                        if (Test-Path $cand) {
                            $candMach = Get-PeMachine -FilePath $cand
                            if ($expectedMachine -eq 0 -or $candMach -eq $expectedMachine) {
                                $foundAviSynth = $cand; break
                            }
                        }
                    }
                }
            }
        }

        # Check repository or script directory tree
        if (-not $foundAviSynth -and -not [string]::IsNullOrWhiteSpace($RepoRoot) -and (Test-Path $RepoRoot)) {
            $repoDlls = Get-ChildItem -Path $RepoRoot -Filter "AviSynth.dll" -Recurse -Depth 3 -ErrorAction SilentlyContinue
            foreach ($rd in $repoDlls) {
                $candMach = Get-PeMachine -FilePath $rd.FullName
                if ($expectedMachine -eq 0 -or $candMach -eq $expectedMachine) {
                    $foundAviSynth = $rd.FullName
                    break
                }
            }
        }

        if ($foundAviSynth) {
            try {
                Copy-Item -Path $foundAviSynth -Destination $potAviSynthDll -Force -ErrorAction Stop
                $deployedMach = Get-PeMachine -FilePath $potAviSynthDll
                $deployedDesc = switch ($deployedMach) {
                    0xAA64 { "ARM64 (0xAA64)" }
                    0x8664 { "x64 (0x8664)" }
                    0x014C { "x86 (0x014C)" }
                    Default { "0x{0:X4}" -f $deployedMach }
                }
                Write-Host "  -> Installed AviSynth.dll ($deployedDesc) from '$foundAviSynth' to PotPlayer directory." -ForegroundColor Green
            } catch {
                Write-Warning "Could not copy AviSynth.dll to '$TargetPotPlayerDir': $($_.Exception.Message)"
            }
        } else {
            # Not found locally: invoke automated acquisition from GitHub releases
            Write-Host "  -> Native $targetPotArch AviSynth.dll not found locally. Initiating automated acquisition from AviSynthPlus release ($AviSynthRepo)..." -ForegroundColor Cyan
            $installedDll = Install-AviSynthPlusRelease -TargetPotPlayerDir $TargetPotPlayerDir -RepoSlug $AviSynthRepo -Arch $targetPotArch
            if ($installedDll -and (Test-Path $installedDll)) {
                $foundAviSynth = $installedDll
            } else {
                Write-Warning "AviSynth.dll could not be acquired. PotPlayer requires AviSynth.dll to execute .avs scripts. Please ensure AviSynth+ is installed or place AviSynth.dll in '$TargetPotPlayerDir'."
            }
        }
    }

    # 4. Deploy all AviSynth profiles to PotPlayer\AviSynth directory
    $potAvsDir = Join-Path $TargetPotPlayerDir "AviSynth"
    if (-not (Test-Path $potAvsDir)) {
        try {
            New-Item -ItemType Directory -Path $potAvsDir -Force -ErrorAction Stop | Out-Null
        } catch {}
    }
    $avsSourceDirs = @(
        (Join-Path $RepoRoot "AviSynth"),
        (Join-Path $ScriptDir "AviSynth"),
        ".\AviSynth",
        "..\AviSynth",
        "..\Release\AviSynth"
    )
    $avsCount = 0
    $deployedProfiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($avsSrc in ($avsSourceDirs | Select-Object -Unique)) {
        if (Test-Path $avsSrc) {
            $profiles = Get-ChildItem -Path $avsSrc -Filter "*.avs" -ErrorAction SilentlyContinue
            if ($profiles -and $profiles.Count -gt 0) {
                foreach ($p in $profiles) {
                    if ($deployedProfiles.Add($p.Name)) {
                        try {
                            Copy-Item -Path $p.FullName -Destination (Join-Path $potAvsDir $p.Name) -Force -ErrorAction Stop
                            $avsCount++
                        } catch {}
                    }
                }
            }
        }
    }

    $targetPotArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetPotPlayerDir
    $hasArchDeployed = if ($targetPotArch -eq "x64") {
        @($deployedProfiles | Where-Object { $_ -match '(?i)Generic-x64' }).Count -gt 0
    } else {
        @($deployedProfiles | Where-Object { $_ -match '(?i)Snapdragon' }).Count -gt 0
    }

    # If no local profiles found or target architecture profiles missing, ensure profiles via download
    if ($avsCount -eq 0 -or -not $hasArchDeployed) {
        Write-Host "  -> Suitable AviSynth benchmark profiles not found in local directories. Ensuring profiles via repository download..." -ForegroundColor Cyan
        $null = Ensure-AviSynthProfiles -RepoRoot $RepoRoot -ScriptDir $ScriptDir -MvToolsRepo $MvToolsRepo -TargetPotPlayerDir $TargetPotPlayerDir
        foreach ($avsSrc in ($avsSourceDirs | Select-Object -Unique)) {
            if (Test-Path $avsSrc) {
                $profiles = Get-ChildItem -Path $avsSrc -Filter "*.avs" -ErrorAction SilentlyContinue
                if ($profiles -and $profiles.Count -gt 0) {
                    foreach ($p in $profiles) {
                        if ($deployedProfiles.Add($p.Name)) {
                            try {
                                Copy-Item -Path $p.FullName -Destination (Join-Path $potAvsDir $p.Name) -Force -ErrorAction Stop
                                $avsCount++
                            } catch {}
                        }
                    }
                }
            }
        }
    }

    if ($avsCount -gt 0) {
        Write-Host "  -> Installed $avsCount AviSynth profile(s) into: $potAvsDir" -ForegroundColor Green
    }

    return $true
}

# ---------------------------------------------------------
# HELPER: System Hardware Platform & Recommendation Engine
# ---------------------------------------------------------
function Get-SystemPlatformRecommendation {
    param(
        [string]$RepoRoot = ".",
        [string]$ScriptDir = "",
        [string]$MvToolsRepo = "",
        [string]$TargetPotPlayerDir = ""
    )

    $targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetPotPlayerDir
    if ([string]::IsNullOrWhiteSpace($MvToolsRepo)) {
        $MvToolsRepo = if ($targetArch -eq "x64") { "pinterf/mvtools" } else { "tordona/mvtools" }
    }
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
    $profiles = Ensure-AviSynthProfiles -RepoRoot $RepoRoot -ScriptDir $ScriptDir -MvToolsRepo $MvToolsRepo -TargetPotPlayerDir $TargetPotPlayerDir

    if ($targetArch -eq "x64") {
        # High-quality string matching and dynamic discovery for specific x64 hardware profiles (Core-i5-7Y54, RyzenAI, etc.)
        $matchedProfile = $null
        $bestMatchScore = 0

        foreach ($p in $profiles) {
            if ($p.Platform -like "Generic-x64*" -or $p.Platform -like "Snapdragon*") { continue }

            $score = 0
            $platNorm = ($p.Platform -creplace '(?<=[a-z])(?=[A-Z])', '-')
            $tokens = $platNorm -split '[-_]'

            # 1. Exact model token match with word boundaries (e.g. "i5-7Y54", "7Y54", "340")
            if ($p.Platform -match '[a-zA-Z0-9]+-[a-zA-Z0-9]+' -and $combined -match "(?i)\b$([regex]::Escape($Matches[0]))\b") {
                $score += 100
            }
            foreach ($t in $tokens) {
                if ($t.Length -ge 2) {
                    if ($t -match '\d' -and $combined -match "(?i)\b$([regex]::Escape($t))\b") {
                        # High-value model digit token (e.g. "7Y54", "i5", "340")
                        $score += 30
                    } elseif ($t.Length -ge 4 -and $combined -match "(?i)\b$([regex]::Escape($t))\b") {
                        # Descriptive token (e.g. "Core", "Ryzen")
                        $score += 10
                    }
                }
            }

            # 2. Flexible multi-token regex across the platform name (tolerant of spaces, hyphens, (R), (TM))
            $platRegex = ($tokens | ForEach-Object { [regex]::Escape($_) }) -join '[\s\-_]*(?:\((?:R|TM)\))?[\s\-_]*'
            if ($combined -match "(?i)$platRegex") {
                $score += 50
            }

            # 3. Hardware description title match
            if ($p.HardwareDesc) {
                $hwTitle = ($p.HardwareDesc -replace '\s*\(.*$', '').Trim()
                $cleanCpu = ($cpuName -replace '\((?:R|TM)\)', '' -replace '\s+CPU\b', '' -replace '\s*@.*$', '').Trim() -replace '\s+', ' '
                if ($hwTitle -and ($combined -match "(?i)$([regex]::Escape($hwTitle))" -or ($cleanCpu -and $cleanCpu -match "(?i)$([regex]::Escape($hwTitle))") -or ($cleanCpu -and $hwTitle -match "(?i)$([regex]::Escape($cleanCpu))"))) {
                    $score += 60
                }
            }

            if ($score -gt $bestMatchScore) {
                $bestMatchScore = $score
                $matchedProfile = $p
            }
        }
        if ($matchedProfile -and $bestMatchScore -ge 30) {
            $platform = $matchedProfile.Platform
            $platformLabel = if ($matchedProfile.HardwareDesc) { $matchedProfile.HardwareDesc } else { "$($matchedProfile.Platform) ($cpuName)" }
        } else {
            $platform = "Generic-x64"
            $platformLabel = "Generic x86-64 ($cpuName, $gpuName)"
        }
    } else {
        # Baseline ARM64 hardware detection rules
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
        } elseif ($combined -match '(?i)\b7c\b') {
            $platform = "Snapdragon-7cGen2"
            $platformLabel = "Snapdragon 7c Gen 2 (Kryo 468, Adreno 618)"
        } else {
            # Dynamic discovery for new or unlisted ARM64 hardware profiles
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
                $platform = "Snapdragon-X-Plus"
                $platformLabel = "Generic ARM64 ($cpuName $gpuName)"
            }
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
# HELPER: Resolve Profile Path (Supports Name, Tier, Partial, Path)
# ---------------------------------------------------------
function Resolve-AviSynthProfilePath {
    param(
        [string]$InputProfile,
        [string]$RepoRoot = ".",
        [string]$RecommendedName = "",
        [string]$PlatformKey = "",
        [string]$ScriptDir = "",
        [string]$MvToolsRepo = ""
    )

    if ([string]::IsNullOrWhiteSpace($MvToolsRepo)) {
        $targetArch = Get-TargetBinaryArchitecture
        $MvToolsRepo = if ($targetArch -eq "x64") { "pinterf/mvtools" } else { "tordona/mvtools" }
    }

    $profiles = Ensure-AviSynthProfiles -RepoRoot $RepoRoot -ScriptDir $ScriptDir -MvToolsRepo $MvToolsRepo

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

        # 5. Partial name substring match (prioritizing current platform if available)
        if (-not [string]::IsNullOrWhiteSpace($PlatformKey)) {
            $match = $profiles | Where-Object { $_.Platform -ieq $PlatformKey -and $_.Name -like "*$InputProfile*" } | Select-Object -First 1
            if ($match) { return $match.FullName }
        }
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
        [string]$CurrentGpuMode,
        [string]$ScriptDir = "",
        [string]$MvToolsRepo = ""
    )

    if ([string]::IsNullOrWhiteSpace($MvToolsRepo)) {
        $targetArch = Get-TargetBinaryArchitecture
        $MvToolsRepo = if ($targetArch -eq "x64") { "pinterf/mvtools" } else { "tordona/mvtools" }
    }

    $profiles = Ensure-AviSynthProfiles -RepoRoot $RepoRoot -ScriptDir $ScriptDir -MvToolsRepo $MvToolsRepo
    if (-not $profiles -or $profiles.Count -eq 0) {
        Write-Warning "No .avs profiles found in AviSynth directory!"
        return @{ ProfilePath = $CurrentProfile; GpuMode = $CurrentGpuMode }
    }

    $targetArch = Get-TargetBinaryArchitecture
    Write-Host "`n========================================================================" -ForegroundColor Cyan
    Write-Host " HARDWARE DETECTION & RECOMMENDATION ENGINE" -ForegroundColor Cyan
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "  -> CPU:            $($Recommendation.CpuName)" -ForegroundColor White
    Write-Host "  -> GPU:            $($Recommendation.GpuName)" -ForegroundColor White
    if ($targetArch -eq "arm64") {
        Write-Host "  -> Detected SoC:   $($Recommendation.PlatformLabel)" -ForegroundColor Yellow
    } else {
        Write-Host "  -> Detected Platform: $($Recommendation.PlatformLabel)" -ForegroundColor Yellow
    }
    Write-Host "  -> Recommended:    $($Recommendation.RecommendedProfile)" -ForegroundColor Green
    $suggestedModeLabel = if ($Recommendation.RecommendedGpuMode -eq "CPU") {
        if ($targetArch -eq "arm64") { "CPU NEON" } else { "CPU SIMD" }
    } else {
        "$($Recommendation.RecommendedGpuMode) GPU"
    }
    Write-Host "  -> Suggested Mode: $suggestedModeLabel (Optimum 1% low frame time stability)" -ForegroundColor Green
    Write-Host "========================================================================`n" -ForegroundColor Cyan

    Write-Host "Available AviSynth Profiles:" -ForegroundColor Yellow
    $recIndex = 1
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $p = $profiles[$i]
        $isRec = ($p.Name -ieq $Recommendation.RecommendedProfile)
        if ($isRec) { $recIndex = $i + 1 }
        $badge = if ($isRec) { " [RECOMMENDED FOR YOUR HARDWARE]" } else { "" }
        $color = if ($isRec) { "Green" } elseif ($p.Platform -eq $Recommendation.PlatformKey) { "White" } else { "Gray" }
        $d3dTag = if ($targetArch -ne "x64" -and $p.SupportsGpu) { " [D3D12/CPU]" } else { " [CPU-Only]" }
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
    $targetArch = Get-TargetBinaryArchitecture
    if ($targetArch -ne "x64" -and $selectedProfile.SupportsGpu) {
        Write-Host "`nSelect Motion Vector Acceleration Engine:" -ForegroundColor Yellow
        $cpuEngineName = if ((Get-TargetBinaryArchitecture) -eq "arm64") { "ARM64 CPU NEON" } else { "x64 CPU SIMD" }; Write-Host ("  [1] {0} (mvtools2.dll)         [RECOMMENDED: Highest 1% Low FPS, rock-solid pacing]" -f $cpuEngineName) -ForegroundColor Green
        Write-Host "  [2] Direct3D 12 GPU (mvtools2_d3d12.dll)  [EXPERIMENTAL PREVIEW: CPU offload, performance/quality not guaranteed]" -ForegroundColor Cyan
        Write-Host "Select Acceleration Mode [1-2] (Press Enter for default [1]): " -NoNewline -ForegroundColor Cyan
        $modeChoice = Read-Host
        if ($modeChoice -eq "2") {
            $selectedGpuMode = "D3D12"
            Write-Host "  Selected Acceleration: Direct3D 12 GPU Compute" -ForegroundColor Cyan
        } else {
            $selectedGpuMode = "CPU"
            Write-Host ("  Selected Acceleration: {0}" -f $cpuEngineName) -ForegroundColor Green
        }
    } else {
        $selectedGpuMode = "CPU"
        $hostEngineName = if ((Get-TargetBinaryArchitecture) -eq "arm64") { "ARM64 CPU NEON" } else { "x64 CPU SIMD" }; Write-Host "  Note: Profile '$($selectedProfile.Name)' is CPU-specialized (running on $hostEngineName)." -ForegroundColor Gray
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
        $allPotProcs = Get-Process -Name "PotPlayer64", "PotPlayerMini64", "PotPlayer" -ErrorAction SilentlyContinue
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
    $procs = Get-Process -Name "PotPlayer64", "PotPlayerMini64", "PotPlayer" -ErrorAction SilentlyContinue
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
        (Join-Path $Dir "PotPlayerMini64.exe"),
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
        [Alias("IniPath")]
        [string[]]$IniPaths = @(),
        [string]$ProfilePath,
        [string]$PotPlayerDir = "",
        [string]$MvToolsDir = "",
        [string]$GpuModeChoice = ""
    )

    if (-not $IniPaths -or $IniPaths.Count -eq 0) {
        if (-not [string]::IsNullOrWhiteSpace($PotPlayerDir)) {
            $IniPaths = Get-PotPlayerIniTargets $PotPlayerDir
        } else {
            Write-Error "No INI paths or PotPlayerDir provided to Set-PotPlayerSettings."
            return $false
        }
    }

    if ([string]::IsNullOrWhiteSpace($PotPlayerDir) -and $IniPaths.Count -gt 0) {
        $PotPlayerDir = Split-Path $IniPaths[0] -Parent
    }

    $isDefault = Test-IsDefaultPotPlayerLocation $PotPlayerDir
    Write-Host "  -> Auditing and enforcing deterministic PotPlayer configuration across $($IniPaths.Count) target(s)..." -ForegroundColor Yellow

    # Prepare multi-line AviSynth preset file (use PotPlayer\AviSynth if writable, otherwise ScriptDir\AviSynth)
    $AvsDir = Join-Path $PotPlayerDir "AviSynth"
    $canWriteAvsDir = $true
    try {
        if (-not (Test-Path $AvsDir)) {
            New-Item -ItemType Directory -Path $AvsDir -Force | Out-Null
        }
        $testAvs = Join-Path $AvsDir (".perm_test_" + [Guid]::NewGuid().ToString("N"))
        [System.IO.File]::WriteAllText($testAvs, "test")
        Remove-Item $testAvs -Force -ErrorAction SilentlyContinue
    } catch {
        $canWriteAvsDir = $false
    }

    if (-not $canWriteAvsDir) {
        $AvsDir = Join-Path $ScriptDir "AviSynth"
        if (-not (Test-Path $AvsDir)) {
            New-Item -ItemType Directory -Path $AvsDir -Force | Out-Null
        }
    }
    $TargetAvs = Join-Path $AvsDir "BenchmarkProfile.avs"

    $CpuDll = if ($MvToolsDir) { (Join-Path $MvToolsDir "mvtools2.dll").Replace('\', '/') } else { "mvtools2.dll" }
    $GpuDll = if ($MvToolsDir) { (Join-Path $MvToolsDir "mvtools2_d3d12.dll").Replace('\', '/') } else { "mvtools2_d3d12.dll" }

    $RawAvs = Get-Content -Path $ProfilePath -Raw

    # Dynamically inject or override USE_GPU if specified
    $activeGpu = $false
    $targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $PotPlayerDir
    if ($targetArch -eq "x64") {
        # On x64 platforms, mvtools2_d3d12.dll is not available; always enforce CPU SIMD
        if ($RawAvs -match '(?m)^\s*USE_GPU\s*=') {
            $RawAvs = $RawAvs -replace '(?m)^\s*USE_GPU\s*=.*$', 'USE_GPU = false'
        }
        $activeGpu = $false
    } elseif ($RawAvs -match '(?m)^\s*USE_GPU\s*=') {
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

    $engineLabel = if ((Get-TargetBinaryArchitecture) -eq "arm64") { "ARM64 CPU NEON (mvtools2.dll)" } else { "x64 CPU SIMD (mvtools2.dll)" }
    $script:ActiveMotionEngine = if ($activeGpu) {
        "Direct3D 12 GPU (mvtools2_d3d12.dll)"
    } else {
        $engineLabel
    }

    # Substitute relative DLL paths with verified absolute paths
    $ResolvedAvs = $RawAvs -replace '(?i)"mvtools2_d3d12\.dll"', "`"$GpuDll`""
    $ResolvedAvs = $RawAvs -replace '(?i)"mvtools2\.dll"', "`"$CpuDll`""
    if ($targetArch -eq "x64") {
        $ResolvedAvs = $ResolvedAvs -replace '(?i)"mvtools2_d3d12\.dll"', "`"$CpuDll`""
    }

    # Write without BOM using ASCII encoding so AviSynth parses line 1 cleanly
    [System.IO.File]::WriteAllText($TargetAvs, $ResolvedAvs, [System.Text.Encoding]::ASCII)
    Write-Host "     Generated multi-line AviSynth profile: $TargetAvs" -ForegroundColor Gray
    Write-Host "     Active Acceleration Engine: $script:ActiveMotionEngine" -ForegroundColor Cyan

    # Also save under canonical profile name in PotPlayer's AviSynth directory so it appears in the player's preset list
    $profileLeafName = Split-Path $ProfilePath -Leaf
    $canonicalPotAvs = Join-Path $AvsDir $profileLeafName
    try {
        [System.IO.File]::WriteAllText($canonicalPotAvs, $ResolvedAvs, [System.Text.Encoding]::ASCII)
    } catch {}

    # If running from default location, also deploy profile presets into AppData AviSynth directories
    if ($isDefault) {
        $appData = if ($env:APPDATA) { $env:APPDATA } else { [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData) }
        $appDataAvsDirs = @(
            (Join-Path $appData "PotPlayer64\AviSynth"),
            (Join-Path $appData "PotPlayerMini64\AviSynth")
        )
        foreach ($adAvs in $appDataAvsDirs) {
            try {
                if (-not (Test-Path $adAvs)) { New-Item -ItemType Directory -Path $adAvs -Force | Out-Null }
                [System.IO.File]::WriteAllText((Join-Path $adAvs "BenchmarkProfile.avs"), $ResolvedAvs, [System.Text.Encoding]::ASCII)
                [System.IO.File]::WriteAllText((Join-Path $adAvs $profileLeafName), $ResolvedAvs, [System.Text.Encoding]::ASCII)
            } catch {}
        }
    }

    # Encode multi-line AviSynth script for PotPlayer's internal script editor using native \x02\x01 delimiters
    $scriptLines = $ResolvedAvs -split "\r?\n"
    $PotPlayerScriptValue = $scriptLines -join ([char]2 + [char]1)

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
            "AutoIni"               = if ($isDefault) { "0" } else { "1" }
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
            "AvisynthDelayUse"      = "0"      # No audio sync delay
            "AvisynthUseProgressive"= "0"      # Standard progressive processing
            "UseSelfDxva"           = "1001"   # D3D11 DXVA Hardware Decode
            "SubShow"               = "0"      # Subtitles OFF (prevents rasterizer jitter)
            "TopMost"               = "2"      # On top while playing (prevents foreground occlusion)
            "DX11ResizeMode"        = "25"     # Bilinear/Bicubic D3D11 GPU resize
            "AudioPitchUse"         = "0"      # Audio time-stretching off
            "D3DFullScreenUi"       = "0"      # Overlay UI off during fullscreen
            "AvisynthScript"        = $PotPlayerScriptValue
        }
    }

    $allSuccess = $true

    foreach ($IniPath in $IniPaths) {
        if (-not (Test-Path $IniPath)) {
            $pDir = Split-Path $IniPath -Parent
            if (-not (Test-Path $pDir)) {
                try { New-Item -ItemType Directory -Path $pDir -Force | Out-Null } catch {}
            }
            try {
                $autoVal = if ($isDefault) { "0" } else { "1" }
                "[Settings]`r`nAutoIni=$autoVal`r`nMultipleRunning=0`r`n[Positions]`r`nMainWindowState=128`r`n" | Set-Content -Path $IniPath -Encoding Unicode
            } catch {}
        }

        # Backup original INI if no backup exists
        $BakPath = "$IniPath.bak"
        if (-not (Test-Path $BakPath) -and (Test-Path $IniPath)) {
            try {
                Copy-Item -Path $IniPath -Destination $BakPath -Force -ErrorAction Stop
                Write-Host "     Created backup: $BakPath" -ForegroundColor Gray
            } catch {
                Write-Warning "Could not backup PotPlayer configuration file: $($_.Exception.Message)"
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

        try {
            $UpdatedLines | Set-Content -Path $IniPath -Encoding Unicode -ErrorAction Stop
            Write-Host "  -> Settings Enforced in: $IniPath ($ChangesCount adjustments made)." -ForegroundColor Green
        } catch {
            Write-Warning "Could not write settings to '$IniPath': $($_.Exception.Message)"
            $allSuccess = $false
        }
    }

    if ($allSuccess) {
        Write-Host "  -> Target script injected cleanly across all configuration files: $(Split-Path $ProfilePath -Leaf)" -ForegroundColor Green
    }
    return $allSuccess
}

function Restore-PotPlayerSettings {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [Alias("IniPath")]
        [string[]]$IniPaths = @()
    )

    foreach ($IniPath in $IniPaths) {
        if ([string]::IsNullOrWhiteSpace($IniPath)) { continue }
        $BakPath = "$IniPath.bak"
        if (Test-Path $BakPath) {
            try {
                Move-Item -Path $BakPath -Destination $IniPath -Force -ErrorAction Stop
                Write-Host "  -> Restored original PotPlayer configuration ($IniPath)." -ForegroundColor Green
            } catch {
                Write-Warning "Could not restore PotPlayer configuration backup for '$IniPath': $($_.Exception.Message)"
            }
        }
    }

    $cleanupDirs = @($ScriptDir)
    foreach ($p in $IniPaths) {
        if (-not [string]::IsNullOrWhiteSpace($p)) {
            $parent = Split-Path $p -Parent
            if ($parent -and -not ($cleanupDirs -contains $parent)) {
                $cleanupDirs += $parent
            }
        }
    }
    foreach ($dir in $cleanupDirs) {
        $avsCand = Join-Path $dir "AviSynth\BenchmarkProfile.avs"
        if (Test-Path $avsCand) {
            Remove-Item $avsCand -Force -ErrorAction SilentlyContinue
        }
    }
}

# =========================================================
# MAIN EXECUTION FLOW
# =========================================================

# Resolve dynamic default for MvToolsRepo if not explicitly specified
if ([string]::IsNullOrWhiteSpace($MvToolsRepo)) {
    $scriptArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $PotPlayerDir
    $MvToolsRepo = if ($scriptArch -eq "x64") { "pinterf/mvtools" } else { "tordona/mvtools" }
}

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
$PotExe = if (Test-Path (Join-Path $PotPlayerDir "PotPlayer64.exe")) {
    Join-Path $PotPlayerDir "PotPlayer64.exe"
} elseif (Test-Path (Join-Path $PotPlayerDir "PotPlayerMini64.exe")) {
    Join-Path $PotPlayerDir "PotPlayerMini64.exe"
} else {
    Join-Path $PotPlayerDir "PotPlayer64.exe"
}

if (-not (Test-Path $PotExe)) {
    Write-Host "`n[1/7] PotPlayer Instance Not Detected at: $PotPlayerDir" -ForegroundColor Yellow

    $TargetInstallDir = if ($PotPlayerDir -ne (Join-Path $ScriptDir "PotPlayer")) { $PotPlayerDir } else { "" }
    $InstalledPath = Install-PotPlayer -TargetDir $TargetInstallDir -Elevated $IsAdmin
        if ($InstalledPath -is [array]) {
            $InstalledPath = ($InstalledPath | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
        }
    if ($InstalledPath -and ((Test-Path (Join-Path $InstalledPath "PotPlayer64.exe")) -or (Test-Path (Join-Path $InstalledPath "PotPlayerMini64.exe")))) {
        $PotPlayerDir = $InstalledPath
        $PotExe = if (Test-Path (Join-Path $PotPlayerDir "PotPlayer64.exe")) {
            Join-Path $PotPlayerDir "PotPlayer64.exe"
        } else {
            Join-Path $PotPlayerDir "PotPlayerMini64.exe"
        }
        Write-Host "  -> PotPlayer verified at: $PotExe" -ForegroundColor Green
        if ([string]::IsNullOrWhiteSpace($ExplicitMvToolsDir)) {
            $MvToolsDir = Resolve-MvToolsSearchDirectory -ExplicitDir "" -TargetPotPlayerDir $PotPlayerDir -CurrentScriptDir $ScriptDir -CurrentRepoRoot $RepoRoot
        }
    } else {
        Write-Host "`n[FATAL ERROR] PotPlayer instance was not found at: '$PotPlayerDir'!" -ForegroundColor Red
        Write-Host ""
        Write-Host "LICENSE & DOWNLOAD NOTICE:" -ForegroundColor Yellow
        Write-Host "PotPlayer is proprietary freeware developed by Kakao Corp. Its license prohibits redistribution." -ForegroundColor White
        Write-Host "Users must obtain PotPlayer directly from official channels:" -ForegroundColor White
        Write-Host "  Official Portal: https://potplayer.tv" -ForegroundColor Cyan
        $detectArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $PotPlayerDir
        $officialDlUrl = if ($detectArch -eq "arm64") { "https://t1.daumcdn.net/potplayer/PotPlayer/Version/Latest/PotPlayerSetupARM64.exe" } else { "https://t1.daumcdn.net/potplayer/PotPlayer/Version/Latest/PotPlayerSetup64.exe" }
        Write-Host ("  Official Direct {0} Installer: {1}" -f $detectArch.ToUpper(), $officialDlUrl) -ForegroundColor Cyan
        $progFilesDisplay = if ($env:ProgramFiles) { (Join-Path ${env:ProgramFiles} "DAUM\PotPlayer") } else { "%ProgramFiles%\DAUM\PotPlayer" }
        Write-Host "Setup options:" -ForegroundColor Yellow
        Write-Host ("  1. Run with -AutoInstallPotPlayer to automatically download and silently install {0} release, OR" -f $detectArch.ToUpper()) -ForegroundColor White
        Write-Host "  2. Install PotPlayer to default directory ('$progFilesDisplay'), OR" -ForegroundColor White
        Write-Host "  3. Copy your official portable PotPlayer folder into '$PotPlayerDir', OR" -ForegroundColor White
        Write-Host "  4. Specify your custom path via -PotPlayerDir '<path>'.`n" -ForegroundColor White
        exit 1
    }
} else {
    Write-Host "`n[1/7] Using existing PotPlayer instance at: $PotPlayerDir" -ForegroundColor Green
}

# Deploy MVTools plugins, AviSynth.dll, and all .avs profiles into PotPlayer directory
Install-MvToolsToPotPlayer -TargetPotPlayerDir $PotPlayerDir -MvToolsSourceDir $MvToolsDir -RepoRoot $RepoRoot -ScriptDir $ScriptDir -MvToolsRepo $MvToolsRepo -AviSynthRepo $AviSynthRepo | Out-Null

# Initialize and resolve PotPlayer configuration target files (AppData for default install, local for non-default)
$PotIniTargets = Initialize-PotPlayerIniFiles -PotPlayerDir $PotPlayerDir
$PotIni = $PotIniTargets[0]


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
$PlatformRec = Get-SystemPlatformRecommendation -RepoRoot $RepoRoot -ScriptDir $ScriptDir -MvToolsRepo $MvToolsRepo -TargetPotPlayerDir $TargetPotPlayerDir

$ChosenProfilePath = $null
$ChosenGpuMode = $GpuMode

$isConsoleHost = [Environment]::UserInteractive -and ($Host.UI.RawUI -ne $null)
if ($Interactive -or ([string]::IsNullOrWhiteSpace($AviSynthProfile) -and $isConsoleHost)) {
    $interactiveResult = Select-ProfileAndModeInteractive -RepoRoot $RepoRoot -Recommendation $PlatformRec -CurrentProfile $AviSynthProfile -CurrentGpuMode $GpuMode -ScriptDir $ScriptDir -MvToolsRepo $MvToolsRepo
    $ChosenProfilePath = $interactiveResult.ProfilePath
    $ChosenGpuMode = $interactiveResult.GpuMode
} else {
    $ChosenProfilePath = Resolve-AviSynthProfilePath -InputProfile $AviSynthProfile -RepoRoot $RepoRoot -RecommendedName $PlatformRec.RecommendedProfile -PlatformKey $PlatformRec.PlatformKey -ScriptDir $ScriptDir -MvToolsRepo $MvToolsRepo
    if ($ChosenGpuMode -eq "Auto" -or [string]::IsNullOrWhiteSpace($ChosenGpuMode)) {
        $ChosenGpuMode = $PlatformRec.RecommendedGpuMode
    }
    $targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $PotPlayerDir
    if ($targetArch -eq "x64" -and ($ChosenGpuMode -in @("GPU", "D3D12"))) {
        Write-Warning "Direct3D 12 GPU offload ('mvtools2_d3d12.dll') is not available on x64 platforms. Overriding engine selection to CPU SIMD mode."
        $ChosenGpuMode = "CPU"
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
if ([string]::IsNullOrWhiteSpace($ExplicitMvToolsDir)) {
    $MvToolsDir = Resolve-MvToolsSearchDirectory -ExplicitDir "" -TargetPotPlayerDir $PotPlayerDir -CurrentScriptDir $ScriptDir -CurrentRepoRoot $RepoRoot
}
Write-Host "`n[3/7] Auditing MVTools Plugins in: $MvToolsDir..." -ForegroundColor Yellow
$MvToolsCpuPath = Join-Path $MvToolsDir "mvtools2.dll"
$MvToolsGpuPath = Join-Path $MvToolsDir "mvtools2_d3d12.dll"

# Check if binaries are missing or if automated download was requested
$cpuMissing = -not (Test-Path $MvToolsCpuPath)
$gpuNeededAndMissing = ($targetArch -ne "x64") -and ($ResolvedGpuMode -in @("GPU", "D3D12")) -and (-not (Test-Path $MvToolsGpuPath))

if ($AutoDownloadMvTools -or $cpuMissing -or $gpuNeededAndMissing) {
    $targetDir = if (-not [string]::IsNullOrWhiteSpace($MvToolsDir)) { $MvToolsDir } else { $ScriptDir }
        # Verify targetDir is writable; if not (e.g. Program Files without elevation), fallback to ScriptDir
        try {
            $testFile = Join-Path $targetDir (".write_test_" + [Guid]::NewGuid().ToString("N"))
            [System.IO.File]::WriteAllText($testFile, "test")
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Directory '$targetDir' is not writable without elevation. Deploying to '$ScriptDir' instead."
            $targetDir = $ScriptDir
        }

        $dlResult = Install-MvToolsRelease -TargetDir $targetDir -RepoSlug $MvToolsRepo
        if ($dlResult -is [array]) {
            $dlResult = ($dlResult | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
        }
        if ($dlResult) {
            $MvToolsDir = $dlResult
            $MvToolsCpuPath = Join-Path $MvToolsDir "mvtools2.dll"
            $MvToolsGpuPath = Join-Path $MvToolsDir "mvtools2_d3d12.dll"
            # Ensure newly acquired binaries and profiles are synced to PotPlayer
            Install-MvToolsToPotPlayer -TargetPotPlayerDir $PotPlayerDir -MvToolsSourceDir $MvToolsDir -RepoRoot $RepoRoot -ScriptDir $ScriptDir -MvToolsRepo $MvToolsRepo -AviSynthRepo $AviSynthRepo | Out-Null
        }
    }

# Assert that required MVTools binaries exist
if (-not (Test-Path $MvToolsCpuPath)) {
    Write-Host "`n[FATAL ERROR] Required MVTools CPU binary 'mvtools2.dll' not found in '$MvToolsDir'!" -ForegroundColor Red
    Write-Host "Please build or place 'mvtools2.dll' in '$MvToolsDir', or pass -AutoDownloadMvTools to fetch from GitHub releases.`n" -ForegroundColor Yellow
    exit 1
}

if ($targetArch -ne "x64" -and ($ResolvedGpuMode -eq "GPU" -or $ResolvedGpuMode -eq "D3D12")) {
    if (-not (Test-Path $MvToolsGpuPath)) {
        Write-Host "`n[FATAL ERROR] Direct3D 12 GPU mode requested, but 'mvtools2_d3d12.dll' was not found in '$MvToolsDir'!" -ForegroundColor Red
        Write-Host "Please build or place 'mvtools2_d3d12.dll' in '$MvToolsDir', or pass -AutoDownloadMvTools to fetch from GitHub releases.`n" -ForegroundColor Yellow
        exit 1
    }
}

$CpuMeta = Get-MvToolsMetadata -DllPath $MvToolsCpuPath
$GpuMeta = if ($targetArch -ne "x64") { Get-MvToolsMetadata -DllPath $MvToolsGpuPath } else { $null }

if ($CpuMeta) {
    $cpuEngineTag = if ((Get-TargetBinaryArchitecture -TargetPotPlayerDir $PotPlayerDir) -eq "arm64") { "CPU/NEON" } else { "CPU/SIMD" }
    Write-Host "  -> mvtools2.dll ($cpuEngineTag):" -ForegroundColor White
    Write-Host "     Version: $($CpuMeta.FileVersion) | Product: $($CpuMeta.ProductVersion)" -ForegroundColor Gray
    Write-Host "     PE Linker Build Date: $($CpuMeta.PeBuildDate)" -ForegroundColor Gray
    Write-Host "     SHA-256: $($CpuMeta.SHA256)" -ForegroundColor Gray
}

if ($targetArch -ne "x64" -and $GpuMeta) {
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
$SettingsReady = Set-PotPlayerSettings -IniPaths $PotIniTargets -ProfilePath $ProfileFullPath -PotPlayerDir $PotPlayerDir -MvToolsDir $MvToolsDir -GpuModeChoice $ResolvedGpuMode
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
            Restore-PotPlayerSettings -IniPaths $PotIniTargets
            exit 1
        }

        Write-Host "Do you want to continue running the benchmark? [y/N]: " -NoNewline -ForegroundColor Cyan
        $userChoice = Read-Host
        if ($userChoice -notmatch '^(?i)y(es)?$') {
            Write-Host "`n[BENCHMARK ABORTED] Execution stopped by user due to low memory headroom.`n" -ForegroundColor Red
            Restore-PotPlayerSettings -IniPaths $PotIniTargets
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
        if ($IgnoreBatteryWarning) {
            Write-Warning "Device is running on battery power ($($Battery.EstimatedChargeRemaining)%). Benchmark continuing (-IgnoreBatteryWarning specified), but battery clock throttling may affect results."
        } else {
            Write-Host "`n[FATAL ERROR] Device is running on battery power!" -ForegroundColor Red
            Write-Host "Connect AC adapter for reproducible benchmarking without battery clock throttling.`n" -ForegroundColor Yellow
            Restore-PotPlayerSettings -IniPaths $PotIniTargets
            exit 1
        }
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
$runningNoisy = @()
foreach ($p in $NoisyProcesses) {
    if (Get-Process -Name $p -ErrorAction SilentlyContinue) {
        $runningNoisy += $p
    }
}

if ($runningNoisy.Count -gt 0) {
    $shouldKill = $true
    if (-not $SkipProcessKill) {
        $isInteractiveHost = [Environment]::UserInteractive -and ($Host.UI.RawUI -ne $null) -and (-not [Console]::IsInputRedirected)
        if ($isInteractiveHost) {
            Write-Host "`n[WARNING] Active Background Applications Detected!" -ForegroundColor Yellow
            Write-Host "  The following background application(s) are currently running: $($runningNoisy -join ', ')" -ForegroundColor Yellow
            Write-Host "  Terminating background applications prevents CPU/GPU spikes during the benchmark." -ForegroundColor White
            Write-Host "  Do you want to terminate these background applications? [Y/n]: " -NoNewline -ForegroundColor Cyan
            $choice = Read-Host
            if ($choice -match '^\s*(?i)n(o)?\s*$') {
                $shouldKill = $false
                Write-Host "  -> Skipping background application termination as requested by user.`n" -ForegroundColor DarkYellow
            } else {
                $shouldKill = $true
            }
        }
    } else {
        $shouldKill = $false
        Write-Host "  -> Skipping background application termination (-SkipProcessKill specified)." -ForegroundColor DarkYellow
    }

    if ($shouldKill) {
        $KilledCount = 0
        foreach ($p in $runningNoisy) {
            $found = Get-Process -Name $p -ErrorAction SilentlyContinue
            if ($found) {
                Stop-Process -Name $p -Force -ErrorAction SilentlyContinue
                $KilledCount++
            }
        }
        Write-Host "  -> Quiesced $KilledCount background process group(s)." -ForegroundColor Green
    }
} else {
    Write-Host "  -> Background apps audit: Clean (no active noisy processes detected)." -ForegroundColor Green
}

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
    Version:        $(if ($targetArch -ne "x64" -and $GpuMeta) { $GpuMeta.FileVersion } else { "N/A" })
    PE Build Date:  $(if ($targetArch -ne "x64" -and $GpuMeta) { $GpuMeta.PeBuildDate } else { "N/A" })
    SHA-256:        $(if ($targetArch -ne "x64" -and $GpuMeta) { $GpuMeta.SHA256 } else { "N/A" })
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
    Restore-PotPlayerSettings -IniPaths $PotIniTargets

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
