# ==============================================================================
# MVTools2 + Daum PotPlayer 60 fps Automated Setup & Profile Deployment
# Architecture: Windows 11 on ARM64 (Qualcomm Snapdragon) & x86-64 (AMD/Intel)
# Repository: https://github.com/tordona/mvtools (branch: mvtools-d3d12)
# Revision: 2.3.18 (2026-11-09)
# ==============================================================================
<#
.SYNOPSIS
    Automated zero-touch installer and dependency configurator for real-time 
    60 fps video motion interpolation in Daum PotPlayer using native MVTools2.

.DESCRIPTION
    1. Detects system architecture (ARM64 vs. x86-64) and system hardware (Qualcomm Snapdragon vs. Intel/AMD).
    2. Ensures Microsoft Visual C++ 2015-2022 Redistributable runtimes are installed.
    3. Acquires and silently installs official Daum PotPlayer 64-bit from Kakao CDN if not present.
    4. Acquires native 64-bit AviSynth.dll from AviSynth+ official releases and deploys to PotPlayer.
    5. Acquires native MVTools2 binaries (mvtools2.dll with native CPU NEON and D3D12 GPU engine) and deploys to PotPlayer.
    6. Deploys architecture-filtered AviSynth+ profiles:
       - ARM64: Deploys strictly Snapdragon*.avs profiles.
       - x86-64: Deploys strictly non-Snapdragon profiles (Ryzen AI, Intel Core, N100, Generic-x64).
    7. Evaluates hardware topology and auto-configures PotPlayer:
       - Direct3D 11 Video Renderer (DXGI swapchain)
       - DXVA2 Copy-Back (D3D11 hardware decoding on Adreno/Intel/AMD)
       - Pre-configures the recommended Balanced profile in PotPlayer.
    8. If system hardware is not recognized, falls back to the Generic Balanced profile and offers
       interactive 1-step AI Agent prompt generation (copied directly to Windows Clipboard).

.PARAMETER PotPlayerDir
    Path to existing PotPlayer directory. If omitted, checks default Program Files or auto-installs.

.PARAMETER AutoInstall
    Bypasses interactive confirmations and proceeds with automated acquisition.

.PARAMETER ProfileBranch
    Git branch to acquire profiles and releases from. Default: 'mvtools-d3d12'.

.PARAMETER ForceProfile
    Optional override to specify an exact .avs profile name to activate (e.g. 'Snapdragon-X-Balanced.avs').

.PARAMETER Launch
    Automatically launches PotPlayer after setup completes.

.VERSION
    2.3.20
.DATE
    2026-11-09
.NOTES
    Format: SemVer (MAJOR.MINOR.PATCH)
    Revision History:
    - v2.3.20 (2026-11-09): Added 4-pillar quantitative 4K 60 fps feasibility classification rules to prompt generation.
    - v2.3.19 (2026-11-09): Added 4K early return bypass invariant to Copy-AiAgentHardwarePrompt for entry-tier ARM64 SoCs.
    - v2.3.18 (2026-11-09): Fixed Snapdragon 7c Gen 2 detection regression and tightened ARM64 matching rules.
#>

[CmdletBinding()]
param(
    [string]$PotPlayerDir = "",
    [switch]$AutoInstall,
    [string]$MvToolsRepo = "",
    [string]$ProfileBranch = "mvtools-d3d12",
    [string]$ForceProfile = "",
    [switch]$Launch
)

# Installer Semantic Revision
$Script:InstallerVersion = "2.3.18"

# ---------------------------------------------------------
# GLOBAL SECURITY & ENCODING SETUP
# ---------------------------------------------------------
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
} catch {}
try {
    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
} catch {}

$OutputEncoding = [System.Text.Encoding]::UTF8
if ([Console]::OutputEncoding) {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
}

$ScriptDir = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand -and -not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    (Get-Location).Path
}
$RepoRoot = $ScriptDir

# ---------------------------------------------------------
# ELEVATION AUDIT & AUTOMATED UAC RELAUNCH
# ---------------------------------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    # Check if a custom, user-writable PotPlayer directory was supplied
    $needsElevation = $true
    if (-not [string]::IsNullOrWhiteSpace($PotPlayerDir) -and (Test-Path $PotPlayerDir)) {
        $testFile = Join-Path $PotPlayerDir (".perm_test_" + [System.Guid]::NewGuid().ToString("N"))
        try {
            [System.IO.File]::WriteAllText($testFile, "test")
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
            $needsElevation = $false
        } catch {
            $needsElevation = $true
        }
    }

    if ($needsElevation) {
        Write-Host "`n================================================================" -ForegroundColor Yellow
        Write-Host " ADMINISTRATIVE ELEVATION REQUIRED" -ForegroundColor Yellow
        Write-Host " Deploying AviSynth+, MVTools2, and configuring Daum PotPlayer in" -ForegroundColor Gray
        Write-Host " 'Program Files' requires Windows Administrator privileges." -ForegroundColor Gray
        Write-Host "================================================================`n" -ForegroundColor Yellow

        if (-not $AutoInstall) {
            $elevateChoice = Read-Host -Prompt "Relaunch with Administrator privileges (UAC prompt)? [Y/n]"
            if (-not [string]::IsNullOrWhiteSpace($elevateChoice) -and $elevateChoice.Trim() -notmatch '(?i)^y(es)?$') {
                Write-Host "`n[CANCELLED] Setup cannot proceed without write access to Program Files." -ForegroundColor Red
                Write-Host "To complete setup, right-click PowerShell and choose 'Run as Administrator', then run:`n  .\Install-MvToolsPotPlayer.ps1`n" -ForegroundColor Yellow
                return
            }
        }

        Write-Host "Requesting Administrator elevation (UAC prompt)..." -ForegroundColor Cyan

        $scriptPath = $MyInvocation.MyCommand.Path
        if (-not $scriptPath) { $scriptPath = $PSCommandPath }
        if (-not $scriptPath -or -not (Test-Path $scriptPath)) {
            $candidatePath = Join-Path (Get-Location).Path "Install-MvToolsPotPlayer.ps1"
            if (Test-Path $candidatePath) {
                $scriptPath = $candidatePath
            } else {
                # In-memory pipeline execution (e.g. irm ... | iex). Cache to TEMP for elevated execution.
                $repoTarget = if (-not [string]::IsNullOrWhiteSpace($MvToolsRepo)) { $MvToolsRepo } else { "tordona/mvtools" }
                $branchTarget = if (-not [string]::IsNullOrWhiteSpace($ProfileBranch)) { $ProfileBranch } else { "mvtools-d3d12" }
                $tempScript = Join-Path $env:TEMP "Install-MvToolsPotPlayer.ps1"
                $rawScriptUrl = "https://raw.githubusercontent.com/$repoTarget/$branchTarget/Install-MvToolsPotPlayer.ps1"
                try {
                    Write-Host "Caching installer to temporary directory for elevated launch..." -ForegroundColor Gray
                    $wcElevate = New-Object System.Net.WebClient
                    $wcElevate.DownloadFile($rawScriptUrl, $tempScript)
                    $wcElevate.Dispose()
                    if (Test-Path $tempScript) { $scriptPath = $tempScript }
                } catch {
                    Write-Warning "Could not cache installer script from ${rawScriptUrl}: $($_.Exception.Message)"
                }
            }
        }

        $argList = @()
        if ($scriptPath -and (Test-Path $scriptPath)) {
            $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"")
            if ($AutoInstall) { $argList += "-AutoInstall" }
            if ($Launch) { $argList += "-Launch" }
            if ($ForceProfile) { $argList += @("-ForceProfile", "`"$ForceProfile`"") }
            if ($PotPlayerDir) { $argList += @("-PotPlayerDir", "`"$PotPlayerDir`"") }
            if ($MvToolsRepo) { $argList += @("-MvToolsRepo", "`"$MvToolsRepo`"") }
            if ($ProfileBranch -and $ProfileBranch -ne "mvtools-d3d12") { $argList += @("-ProfileBranch", "`"$ProfileBranch`"") }
        } else {
            $repoTarget = if (-not [string]::IsNullOrWhiteSpace($MvToolsRepo)) { $MvToolsRepo } else { "tordona/mvtools" }
            $branchTarget = if (-not [string]::IsNullOrWhiteSpace($ProfileBranch)) { $ProfileBranch } else { "mvtools-d3d12" }
            $remoteCmd = "irm https://raw.githubusercontent.com/$repoTarget/$branchTarget/Install-MvToolsPotPlayer.ps1 | iex"
            $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $remoteCmd)
        }

        try {
            $proc = Start-Process powershell.exe -ArgumentList $argList -WorkingDirectory (Get-Location).Path -Verb RunAs -PassThru
            $proc.WaitForExit()
            exit $proc.ExitCode
        } catch {
            Write-Host "`n[ERROR] Elevation was cancelled or denied: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Please right-click PowerShell and select 'Run as Administrator', then run:`n  .\Install-MvToolsPotPlayer.ps1`n" -ForegroundColor Yellow
            return
        }
    }
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

    return "arm64"
}

# ---------------------------------------------------------
# HELPER: Prompt / Confirm Download Permission
# ---------------------------------------------------------
function Confirm-DownloadPermission {
    param(
        [string]$ItemName,
        [string]$SourceUrl,
        [string]$TargetDir,
        [string]$SizeDesc = "",
        [switch]$Bypass
    )

    if ($Bypass -or $AutoInstall) {
        return $true
    }

    Write-Host "`n------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " [DOWNLOAD REQUIRED] $ItemName" -ForegroundColor Yellow
    Write-Host " Source: $SourceUrl" -ForegroundColor Gray
    Write-Host " Target: $TargetDir" -ForegroundColor Gray
    if ($SizeDesc) { Write-Host " Approx Size: $SizeDesc" -ForegroundColor Gray }
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan

    $prompt = "Do you want to download and install this component now? [Y/n]: "
    $reply = Read-Host -Prompt $prompt
    if ([string]::IsNullOrWhiteSpace($reply) -or $reply.Trim() -match '(?i)^y(es)?$') {
        return $true
    } else {
        Write-Host "  -> Permission declined by user. Skipped.`n" -ForegroundColor DarkYellow
        return $false
    }
}

# ---------------------------------------------------------
# HELPER: Discover Existing 7-Zip CLI Extractor (7z.exe / 7za.exe / 7zr.exe)
# ---------------------------------------------------------
function Find-7ZipExtractor {
    param([string]$TargetPotPlayerDir = "")

    $winDir = if ($env:WINDIR) { $env:WINDIR } else { [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Windows) }

    $searchCandidates = @(
        (Get-Command 7z -ErrorAction SilentlyContinue | Select-Object -First 1).Source,
        (Get-Command 7za -ErrorAction SilentlyContinue | Select-Object -First 1).Source,
        (Get-Command 7zr -ErrorAction SilentlyContinue | Select-Object -First 1).Source,
        (Join-Path $ScriptDir "7z.exe"),
        (Join-Path $ScriptDir "7za.exe"),
        (Join-Path $ScriptDir "7zr.exe"),
        (Join-Path $ScriptDir "7-Zip\7z.exe"),
        (Join-Path $ScriptDir "7-Zip\7zr.exe"),
        (Join-Path $env:LOCALAPPDATA "7-Zip\7z.exe"),
        (Join-Path $env:LOCALAPPDATA "7-Zip\7za.exe"),
        (Join-Path $env:LOCALAPPDATA "7-Zip\7zr.exe"),
        (Join-Path ${env:ProgramFiles} "7-Zip\7z.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "7-Zip\7z.exe"),
        (Join-Path $winDir "7z.exe")
    )

    if (-not [string]::IsNullOrWhiteSpace($TargetPotPlayerDir)) {
        $searchCandidates += (Join-Path $TargetPotPlayerDir "7z.exe")
        $searchCandidates += (Join-Path $TargetPotPlayerDir "7za.exe")
        $searchCandidates += (Join-Path $TargetPotPlayerDir "7zr.exe")
        $searchCandidates += (Join-Path $TargetPotPlayerDir "7-Zip\7z.exe")
        $searchCandidates += (Join-Path $TargetPotPlayerDir "7-Zip\7zr.exe")
    }

    foreach ($cand in $searchCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($cand) -and (Test-Path $cand)) {
            return (Resolve-Path $cand).Path
        }
    }
    return $null
}

# ---------------------------------------------------------
# HELPER: Ensure 7-Zip CLI Extractor is Available (User-Mode Portable)
# ---------------------------------------------------------
function Ensure-7ZipExtractor {
    param([string]$TargetPotPlayerDir = "")

    $existing = Find-7ZipExtractor -TargetPotPlayerDir $TargetPotPlayerDir
    if ($existing) {
        return $existing
    }

    Write-Host "`n[TOOL ACQUISITION] 7-Zip CLI extractor is required for .7z archive decompression." -ForegroundColor Cyan

    $localToolsDir = Join-Path $env:LOCALAPPDATA "7-Zip"
    if (-not (Test-Path $localToolsDir)) {
        New-Item -ItemType Directory -Path $localToolsDir -Force | Out-Null
    }
    $targetExe = Join-Path $localToolsDir "7zr.exe"

    # Priority 1: Standalone portable 7zr.exe (zero-install, user-rights compatible, ~580 KB)
    $zrUrl = $null
    try {
        $headers = @{
            "User-Agent" = "MvToolsSetup/1.0.0"
            "Accept"     = "application/vnd.github.v3+json"
        }
        $zipRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/ip7z/7zip/releases/latest" -Headers $headers -TimeoutSec 10 -ErrorAction Stop
        if ($zipRelease -and $zipRelease.assets) {
            $zrAsset = $zipRelease.assets | Where-Object { $_.name -ieq "7zr.exe" } | Select-Object -First 1
            if ($zrAsset) {
                $zrUrl = $zrAsset.browser_download_url
            }
        }
    } catch {}

    if (-not $zrUrl) {
        $zrUrl = "https://www.7-zip.org/a/7zr.exe"
    }

    if (-not (Confirm-DownloadPermission -ItemName "Portable 7-Zip Standalone Extractor (7zr.exe)" -SourceUrl $zrUrl -TargetDir $targetExe -SizeDesc "~580 KB")) {
        return $null
    }

    try {
        Write-Host "  -> Downloading portable 7-Zip standalone extractor ($zrUrl)..." -ForegroundColor Cyan
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "MvToolsSetup/1.0.0")
        $wc.DownloadFile($zrUrl, $targetExe)
        $wc.Dispose()

        if ((Test-Path $targetExe) -and ((Get-Item $targetExe).Length -gt 0)) {
            Write-Host "  -> Portable 7-Zip CLI ready: $targetExe" -ForegroundColor Green
            return $targetExe
        }
    } catch {
        Write-Warning "Direct 7zr.exe acquisition encountered an issue: $($_.Exception.Message)"
    }

    # Priority 2: User-mode administrative extraction of official MSI package into user profile
    $targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetPotPlayerDir
    $msiUrl = "https://www.7-zip.org/a/" + (if ($targetArch -eq "x64") { "7z2408-x64.msi" } else { "7z2408-arm64.msi" })
    $tempMsi = Join-Path $env:TEMP ("7z_acq_{0}.msi" -f [System.Guid]::NewGuid().ToString("N"))
    $tempUnpack = Join-Path $env:TEMP ("7z_unpack_{0}" -f [System.Guid]::NewGuid().ToString("N"))

    try {
        Write-Host "  -> Attempting user-mode MSI unpack fallback..." -ForegroundColor Cyan
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "MvToolsSetup/1.0.0")
        $wc.DownloadFile($msiUrl, $tempMsi)
        $wc.Dispose()

        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/a `"$tempMsi`" /qn TARGETDIR=`"$tempUnpack`"" -PassThru -Wait
        $extractedExe = Get-ChildItem -Path $tempUnpack -Recurse -File | Where-Object { $_.Name -match '(?i)^7z(r|a)?\.exe$' } | Select-Object -First 1
        if ($extractedExe) {
            Copy-Item -Path (Join-Path $extractedExe.DirectoryName "*") -Destination $localToolsDir -Recurse -Force
            $deployed = Join-Path $localToolsDir $extractedExe.Name
            Write-Host "  -> 7-Zip CLI ready: $deployed" -ForegroundColor Green
            return $deployed
        }
    } catch {
        Write-Warning "User-mode MSI unpack fallback failed: $($_.Exception.Message)"
    } finally {
        if (Test-Path $tempMsi) { Remove-Item $tempMsi -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempUnpack) { Remove-Item $tempUnpack -Recurse -Force -ErrorAction SilentlyContinue }
    }

    return $null
}

# ---------------------------------------------------------
# HELPER: Audit and Ensure Microsoft Visual C++ Redistributable
# ---------------------------------------------------------
function Ensure-VisualCppRedistributable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TargetPotPlayerDir = "",

        [Parameter(Mandatory = $false)]
        [switch]$AutoInstall
    )

    $targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetPotPlayerDir
    $archLabel = $targetArch.ToUpper()

    $expectedMachine = switch ($targetArch) {
        "arm64" { 0xAA64 }
        "x64"   { 0x8664 }
        "x86"   { 0x014C }
        Default { 0 }
    }

    # Core required DLLs for Visual C++ 2015-2022 (v14x) runtimes
    # x64 specifically requires vcruntime140_1.dll for __CxxFrameHandler4
    $requiredDlls = switch ($targetArch) {
        "x64"   { @("vcruntime140.dll", "msvcp140.dll", "vcruntime140_1.dll") }
        Default { @("vcruntime140.dll", "msvcp140.dll") }
    }

    $sysDir = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::System)

    # Local auditor for DLL existence and PE machine architecture match
    $AuditDlls = {
        $missing = @()
        $mismatched = @()
        foreach ($dll in $requiredDlls) {
            $candidatePaths = @((Join-Path $sysDir $dll))
            if (-not [string]::IsNullOrWhiteSpace($TargetPotPlayerDir)) {
                $candidatePaths += (Join-Path $TargetPotPlayerDir $dll)
            }

            $foundValid = $false
            $foundAny = $false
            $lastMachine = 0
            foreach ($cp in $candidatePaths) {
                if (Test-Path $cp) {
                    $foundAny = $true
                    $mach = Get-PeMachine -FilePath $cp
                    $lastMachine = $mach
                    if ($expectedMachine -eq 0 -or $mach -eq $expectedMachine) {
                        $foundValid = $true
                        break
                    }
                }
            }

            if (-not $foundValid) {
                if ($foundAny) {
                    $desc = switch ($lastMachine) {
                        0xAA64 { "ARM64 (0xAA64)" }
                        0x8664 { "x64 (0x8664)" }
                        0x014C { "x86 (0x014C)" }
                        Default { "0x{0:X4}" -f $lastMachine }
                    }
                    $mismatched += "$dll (Incompatible PE Architecture: $desc, expected $archLabel)"
                } else {
                    $missing += $dll
                }
            }
        }
        return @{ Missing = $missing; Mismatched = $mismatched; IsHealthy = (($missing.Count -eq 0) -and ($mismatched.Count -eq 0)) }
    }

    $audit = & $AuditDlls
    if ($audit.IsHealthy) {
        Write-Host "  -> Visual C++ 2015-2022 Redistributable ($archLabel) verified (all required runtime DLLs present: $($requiredDlls -join ", "))." -ForegroundColor Green
        return $true
    }

    # Report diagnostic findings
    Write-Host "`n========================================================================" -ForegroundColor Yellow
    Write-Host " VISUAL C++ RUNTIME PRE-FLIGHT CHECK: MISSING / INCOMPLETE COMPONENTS" -ForegroundColor Yellow
    Write-Host "========================================================================" -ForegroundColor Yellow
    Write-Host " Target Architecture:   $archLabel" -ForegroundColor White
    Write-Host " Required CRT DLLs:     $($requiredDlls -join ", ")" -ForegroundColor Gray
    Write-Host " System Directory:      $sysDir" -ForegroundColor Gray
    if ($audit.Missing.Count -gt 0) {
        Write-Host " Missing DLL(s):        $($audit.Missing -join ", ")" -ForegroundColor Red
    }
    if ($audit.Mismatched.Count -gt 0) {
        Write-Host " Architecture Mismatch: $($audit.Mismatched -join "; ")" -ForegroundColor Red
    }
    Write-Host "------------------------------------------------------------------------" -ForegroundColor Gray
    Write-Host " CAUTION: When Visual C++ Redistributable runtime DLLs are missing, Windows" -ForegroundColor DarkYellow
    Write-Host " dynamic linker fails to load AviSynth.dll (Win32 ERROR_MOD_NOT_FOUND / 126)." -ForegroundColor DarkYellow
    Write-Host " PotPlayer surfaces this as: 'AviSynth.dll not found'." -ForegroundColor DarkYellow
    Write-Host "========================================================================`n" -ForegroundColor Yellow

    # Target Microsoft official permalinks (latest v14x binary compatible family)
    $vcUrl = switch ($targetArch) {
        "arm64" { "https://aka.ms/vc14/vc_redist.arm64.exe" }
        "x64"   { "https://aka.ms/vc14/vc_redist.x64.exe" }
        "x86"   { "https://aka.ms/vc14/vc_redist.x86.exe" }
        Default { "https://aka.ms/vc14/vc_redist.x64.exe" }
    }

    $tempInstaller = Join-Path $env:TEMP ("VC_redist_{0}_{1}.exe" -f $targetArch, [System.Guid]::NewGuid().ToString("N"))
    if (-not (Confirm-DownloadPermission -ItemName "Visual C++ 2015-2022 $archLabel Redistributable" -SourceUrl $vcUrl -TargetDir $tempInstaller -SizeDesc "~15-25 MB" -Bypass:$AutoInstall)) {
        Write-Warning "Visual C++ Redistributable installation declined by user. AviSynth.dll dynamic linking in PotPlayer may fail with 'not found' error."
        return $false
    }

    # Phase 1: Download installer with live stream progress bar
    Write-Host "[1/2] Downloading Official Microsoft Visual C++ ($archLabel) Redistributable..." -ForegroundColor Cyan

    $downloadSuccess = $false
    $client = $null
    $fileStream = $null
    $stream = $null

    try {
        $client = New-Object System.Net.Http.HttpClient
        $response = $client.GetAsync($vcUrl, 1).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "Failed to download VC redistributable from $vcUrl! HTTP status: $($response.StatusCode) $($response.ReasonPhrase)"
        }

        $totalBytes = $response.Content.Headers.ContentLength
        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $fileStream = [System.IO.File]::Create($tempInstaller)

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
            $webClient.Headers.Add("User-Agent", "MvToolsSetup/1.0.0")
            $webClient.DownloadFile($vcUrl, $tempInstaller)
            $webClient.Dispose()
            if ((Test-Path $tempInstaller) -and ((Get-Item $tempInstaller).Length -gt 0)) {
                Write-Host "  [OK] Download complete! (Fallback successful)                                   " -ForegroundColor Green
                $downloadSuccess = $true
            } else {
                throw "Downloaded installer was empty or missing."
            }
        } catch {
            Write-Host "`r  [ERROR] Fallback download failed: $_" -ForegroundColor Red
            if (Test-Path $tempInstaller) { Remove-Item $tempInstaller -Force -ErrorAction SilentlyContinue }
            $downloadSuccess = $false
        }
    }
    finally {
        if ($fileStream) { $fileStream.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($client) { $client.Dispose() }
    }

    if (-not $downloadSuccess -or -not (Test-Path $tempInstaller) -or (Get-Item $tempInstaller).Length -eq 0) {
        Write-Host "`n[FATAL ERROR] Visual C++ Redistributable download failed. Installation aborted.`n" -ForegroundColor Red
        if (Test-Path $tempInstaller) { Remove-Item $tempInstaller -Force -ErrorAction SilentlyContinue }
        return $false
    }

    # Phase 2: Silent installation with animated background spinner
    Write-Host "`n[2/2] Installing Visual C++ ($archLabel) Redistributable silently in the background..." -ForegroundColor Cyan

    $isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $startParams = @{
        FilePath     = $tempInstaller
        ArgumentList = @("/install", "/quiet", "/norestart")
        PassThru     = $true
    }
    if (-not $isElevated) {
        $startParams["Verb"] = "RunAs"
    }

    $exitCode = -1
    try {
        $proc = Start-Process @startParams
        $spinner = @('|', '/', '-', '\')
        $spinIdx = 0
        $watch = [System.Diagnostics.Stopwatch]::StartNew()

        while (-not $proc.HasExited) {
            $char = $spinner[$spinIdx % $spinner.Length]
            $sec = [math]::Round($watch.Elapsed.TotalSeconds)
            Write-Host -NoNewline ("`r  [{0}] Executing official Microsoft installer... ({1}s elapsed)   " -f $char, $sec) -ForegroundColor DarkCyan
            $spinIdx++
            Start-Sleep -Milliseconds 250
            if ($sec -ge 120) {
                Write-Host "`r  [WARNING] Installer has been running for 120 seconds. Waiting for completion...   " -ForegroundColor Yellow
            }
        }
        $exitCode = $proc.ExitCode
        Write-Host "`r  [OK] Installer process exited with code $exitCode (completed in $([math]::Round($watch.Elapsed.TotalSeconds, 1))s)        " -ForegroundColor Green
    }
    catch {
        Write-Host "`r  [ERROR] Failed to launch installer process: $_" -ForegroundColor Red
        if (Test-Path $tempInstaller) { Remove-Item $tempInstaller -Force -ErrorAction SilentlyContinue }
        return $false
    }

    # If exit code indicates another version is already installed (1638), run repair mode to restore any missing DLLs
    if ($exitCode -eq 1638) {
        Write-Host "  -> Another version of VC++ runtime is detected (ExitCode 1638). Executing repair mode..." -ForegroundColor Cyan
        try {
            $repairParams = @{
                FilePath     = $tempInstaller
                ArgumentList = @("/repair", "/quiet", "/norestart")
                Wait         = $true
                PassThru     = $true
            }
            if (-not $isElevated) { $repairParams["Verb"] = "RunAs" }
            $procRepair = Start-Process @repairParams
            try { $exitCode = $procRepair.ExitCode } catch {}
            Write-Host "  -> Repair mode finished with exit code $exitCode" -ForegroundColor Gray
        } catch {
            Write-Warning "Repair mode execution error: $_"
        }
    }

    if (Test-Path $tempInstaller) { Remove-Item $tempInstaller -Force -ErrorAction SilentlyContinue }

    # Re-audit DLLs after installation
    $reAudit = & $AuditDlls
    if ($reAudit.IsHealthy) {
        Write-Host "  -> [SUCCESS] Microsoft Visual C++ 2015-2022 ($archLabel) Redistributable verified healthy!" -ForegroundColor Green
        return $true
    } else {
        if ($exitCode -eq 3010) {
            Write-Host "  -> [WARNING] Installer indicated a system reboot is pending (ExitCode 3010). Some runtime DLLs may be locked until restart." -ForegroundColor Yellow
        } else {
            Write-Warning "Installation finished with code $exitCode, but some runtime DLLs could not be verified: $($reAudit.Missing -join ", ")"
        }
        return $false
    }
}

# ---------------------------------------------------------
# HELPER: Close Active PotPlayer Processes & Utilities
# ---------------------------------------------------------
function Stop-PotPlayerProcesses {
    [CmdletBinding()]
    param()

    $procNames = @("PotPlayer64", "PotPlayerMini64", "PotPlayer", "PotPlayerMini", "DesktopHook64", "DesktopHook", "KakaoUtil64", "KakaoUtil", "KillPotARM64", "KillPot64")
    $runningPot = Get-Process -Name $procNames -ErrorAction SilentlyContinue
    if ($runningPot) {
        Write-Host "`n[PROCESS GUARD] Daum PotPlayer / helper processes are currently running." -ForegroundColor Yellow
        Write-Host "  Closing active processes to allow file updates and prevent DLL locking..." -ForegroundColor Cyan
        $runningPot | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
}

# ---------------------------------------------------------
# HELPER: Discover Existing Daum PotPlayer Installation Directory
# ---------------------------------------------------------
function Get-PotPlayerInstallPath {
    param([string]$ExplicitDir = "")

    if (-not [string]::IsNullOrWhiteSpace($ExplicitDir) -and (Test-Path $ExplicitDir)) {
        if ((Test-Path (Join-Path $ExplicitDir "PotPlayer64.exe")) -or (Test-Path (Join-Path $ExplicitDir "PotPlayerMini64.exe"))) {
            return (Resolve-Path $ExplicitDir).Path
        }
    }

    # 1. Registry Daum / PotPlayer keys
    $regPaths = @(
        "HKLM:\SOFTWARE\DAUM\PotPlayer64",
        "HKCU:\SOFTWARE\DAUM\PotPlayer64",
        "HKCU:\SOFTWARE\Daum\PotPlayer64",
        "HKCU:\SOFTWARE\Daum\PotPlayerMini64",
        "HKLM:\SOFTWARE\DAUM\PotPlayer",
        "HKCU:\SOFTWARE\DAUM\PotPlayer"
    )
    foreach ($regKey in $regPaths) {
        if (Test-Path $regKey) {
            $props = Get-ItemProperty $regKey -ErrorAction SilentlyContinue
            if ($props.ProgramFolder) {
                $f = $props.ProgramFolder.Trim('"')
                if ((Test-Path (Join-Path $f "PotPlayer64.exe")) -or (Test-Path (Join-Path $f "PotPlayerMini64.exe"))) {
                    return (Resolve-Path $f).Path
                }
            }
            if ($props.ProgramPath) {
                $dir = [System.IO.Path]::GetDirectoryName($props.ProgramPath.Trim('"'))
                if ($dir -and ((Test-Path (Join-Path $dir "PotPlayer64.exe")) -or (Test-Path (Join-Path $dir "PotPlayerMini64.exe")))) {
                    return (Resolve-Path $dir).Path
                }
            }
        }
    }

    # 2. Registry App Paths
    $appPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\PotPlayer64.exe",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\PotPlayerMini64.exe"
    )
    foreach ($ap in $appPaths) {
        if (Test-Path $ap) {
            $props = Get-ItemProperty $ap -ErrorAction SilentlyContinue
            if ($props.Path) {
                $f = $props.Path.Trim('"')
                if ((Test-Path (Join-Path $f "PotPlayer64.exe")) -or (Test-Path (Join-Path $f "PotPlayerMini64.exe"))) {
                    return (Resolve-Path $f).Path
                }
            }
            if ($props.'(default)') {
                $dir = [System.IO.Path]::GetDirectoryName($props.'(default)'.Trim('"'))
                if ($dir -and ((Test-Path (Join-Path $dir "PotPlayer64.exe")) -or (Test-Path (Join-Path $dir "PotPlayerMini64.exe")))) {
                    return (Resolve-Path $dir).Path
                }
            }
        }
    }

    # 3. Windows Uninstall registry keys
    $uninstallRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $uninstalls = Get-ItemProperty $uninstallRoots -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "PotPlayer" }
    foreach ($u in $uninstalls) {
        if ($u.InstallLocation) {
            $f = $u.InstallLocation.Trim('"')
            if ((Test-Path (Join-Path $f "PotPlayer64.exe")) -or (Test-Path (Join-Path $f "PotPlayerMini64.exe"))) {
                return (Resolve-Path $f).Path
            }
        }
        if ($u.UninstallString) {
            $dir = [System.IO.Path]::GetDirectoryName($u.UninstallString.Trim('"'))
            if ($dir -and ((Test-Path (Join-Path $dir "PotPlayer64.exe")) -or (Test-Path (Join-Path $dir "PotPlayerMini64.exe")))) {
                return (Resolve-Path $dir).Path
            }
        }
    }

    # 4. Standard filesystem candidate directories
    $searchLocations = @(
        (Join-Path ${env:ProgramFiles} "DAUM\PotPlayer"),
        (Join-Path ${env:ProgramW6432} "DAUM\PotPlayer"),
        (Join-Path ${env:ProgramFiles(x86)} "DAUM\PotPlayer"),
        "C:\Tools\PotPlayer",
        (Join-Path $ScriptDir "PotPlayer")
    )
    foreach ($cand in $searchLocations) {
        if ((Test-Path (Join-Path $cand "PotPlayer64.exe")) -or (Test-Path (Join-Path $cand "PotPlayerMini64.exe"))) {
            return (Resolve-Path $cand).Path
        }
    }

    return $null
}

# ---------------------------------------------------------
# HELPER: Discover Existing Daum PotPlayer Uninstaller Executable
# ---------------------------------------------------------
function Get-PotPlayerUninstallerPath {
    param([string]$InstallDir = "")

    if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
        $cand = Join-Path $InstallDir "uninstall.exe"
        if (Test-Path $cand) { return (Resolve-Path $cand).Path }
    }

    # Check Windows Uninstall registry keys
    $uninstallRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $uninstalls = Get-ItemProperty $uninstallRoots -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "PotPlayer" }
    foreach ($u in $uninstalls) {
        if ($u.UninstallString) {
            $uPath = $u.UninstallString.Trim('"')
            if (Test-Path $uPath) { return (Resolve-Path $uPath).Path }
        }
    }

    # Check Daum registry keys
    $regPaths = @(
        "HKLM:\SOFTWARE\DAUM\PotPlayer64",
        "HKCU:\SOFTWARE\DAUM\PotPlayer64",
        "HKCU:\SOFTWARE\Daum\PotPlayer64",
        "HKLM:\SOFTWARE\DAUM\PotPlayer",
        "HKCU:\SOFTWARE\DAUM\PotPlayer"
    )
    foreach ($regKey in $regPaths) {
        if (Test-Path $regKey) {
            $props = Get-ItemProperty $regKey -ErrorAction SilentlyContinue
            if ($props.ProgramFolder) {
                $uCand = Join-Path $props.ProgramFolder.Trim('"') "uninstall.exe"
                if (Test-Path $uCand) { return (Resolve-Path $uCand).Path }
            }
        }
    }

    # Check standard filesystem locations
    $searchLocations = @(
        (Join-Path ${env:ProgramFiles} "DAUM\PotPlayer\uninstall.exe"),
        (Join-Path ${env:ProgramW6432} "DAUM\PotPlayer\uninstall.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "DAUM\PotPlayer\uninstall.exe"),
        "C:\Tools\PotPlayer\uninstall.exe"
    )
    foreach ($cand in $searchLocations) {
        if (Test-Path $cand) { return (Resolve-Path $cand).Path }
    }

    return $null
}

# ---------------------------------------------------------
# HELPER: Download & Silently Install Daum PotPlayer
# ---------------------------------------------------------
function Install-PotPlayer {
    param(
        [string]$TargetDir = "",
        [bool]$Elevated = $false
    )

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

    # Check for existing uninstaller / installation record before triggering setup
    $existingUninstaller = Get-PotPlayerUninstallerPath -InstallDir $TargetDir
    $uninstallConfirmed = $false
    if ($existingUninstaller -and (Test-Path $existingUninstaller)) {
        $uninstDir = [System.IO.Path]::GetDirectoryName($existingUninstaller)
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
        Write-Host " [EXISTING POTPLAYER INSTALLATION DETECTED]" -ForegroundColor Yellow
        Write-Host " Location: $uninstDir" -ForegroundColor White
        Write-Host " Uninstaller: $existingUninstaller" -ForegroundColor Gray
        Write-Host "`n NOTE: Daum PotPlayer's official installer cannot silently install" -ForegroundColor Gray
        Write-Host " or upgrade over an existing installation. Attempting silent setup" -ForegroundColor Gray
        Write-Host " without an uninstall will fail." -ForegroundColor Gray
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan

        $prompt = "Do you want to uninstall the existing PotPlayer installation now? [Y/n]: "
        $reply = Read-Host -Prompt $prompt
        if ([string]::IsNullOrWhiteSpace($reply) -or $reply.Trim() -match '(?i)^y(es)?$') {
            $uninstallConfirmed = $true
        }

        if ($uninstallConfirmed) {
            Write-Host "`nSilently uninstalling previous PotPlayer instance..." -ForegroundColor Cyan
            Stop-PotPlayerProcesses
            try {
                # In NSIS, passing _?=$INSTDIR forces the uninstaller to run synchronously and wait
                $uninstParams = @{
                    FilePath     = $existingUninstaller
                    ArgumentList = @("/S", "_?=$uninstDir")
                    PassThru     = $true
                    Wait         = $true
                }
                $uProc = Start-Process @uninstParams
                Start-Sleep -Seconds 2
                Write-Host "  [OK] Previous installation uninstalled successfully." -ForegroundColor Green
            } catch {
                Write-Warning "Could not trigger silent uninstallation: $($_.Exception.Message)"
            }
        } else {
            Write-Host "  -> Uninstallation declined by user. Proceeding with installation attempt..." -ForegroundColor Yellow
        }
    }

    $archLabel = $targetArch.ToUpper()
    if (-not (Confirm-DownloadPermission -ItemName "PotPlayer $archLabel Official Installer" -SourceUrl $Url -TargetDir $TempInstaller -SizeDesc "~35 MB" -Bypass:$AutoInstall)) {
        return $null
    }

    Write-Host "[1/2] Downloading Official PotPlayer $archLabel Installer..." -ForegroundColor Cyan
    $DownloadSuccess = $false
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($Url, $TempInstaller)
        $wc.Dispose()
        if ((Test-Path $TempInstaller) -and ((Get-Item $TempInstaller).Length -gt 0)) {
            Write-Host "  [OK] Download complete!" -ForegroundColor Green
            $DownloadSuccess = $true
        }
    } catch {
        Write-Host "`r  [ERROR] PotPlayer download failed: $_" -ForegroundColor Red
        if (Test-Path $TempInstaller) { Remove-Item $TempInstaller -Force -ErrorAction SilentlyContinue }
        return $null
    }

    Write-Host "`n[2/2] Installing PotPlayer silently in the background..." -ForegroundColor Cyan
    Stop-PotPlayerProcesses

    # In NSIS, /D must be the last argument and should not contain outer quotes
    $InstallerArgStr = if (-not [string]::IsNullOrWhiteSpace($TargetDir)) { "/S /D=$TargetDir" } else { "/S" }

    $installerExitCode = -1
    try {
        $StartParams = @{
            FilePath     = $TempInstaller
            ArgumentList = $InstallerArgStr
            PassThru     = $true
        }
        $Process = Start-Process @StartParams
        $exited = $Process.WaitForExit(120000) # 2-minute safety timeout
        if (-not $exited) {
            Write-Warning "PotPlayer installer timed out after 2 minutes. Terminating process."
            $Process | Stop-Process -Force -ErrorAction SilentlyContinue
        } else {
            $installerExitCode = $Process.ExitCode
        }

        if (Test-Path $TempInstaller) { Remove-Item $TempInstaller -Force -ErrorAction SilentlyContinue }

        # Verify installation target
        $verifiedDir = Get-PotPlayerInstallPath -ExplicitDir $TargetDir
        if ($verifiedDir) {
            Write-Host "  -> PotPlayer verified at: $verifiedDir" -ForegroundColor Green
            return $verifiedDir
        }

        # Fallback check for standard verify locations
        $verifyLocations = if (-not [string]::IsNullOrWhiteSpace($TargetDir)) { @($TargetDir) } else {
            @(
                (Join-Path ${env:ProgramFiles} "DAUM\PotPlayer"),
                (Join-Path ${env:ProgramW6432} "DAUM\PotPlayer"),
                (Join-Path ${env:ProgramFiles(x86)} "DAUM\PotPlayer")
            )
        }

        foreach ($loc in $verifyLocations) {
            if ((Test-Path (Join-Path $loc "PotPlayer64.exe")) -or (Test-Path (Join-Path $loc "PotPlayerMini64.exe"))) {
                Write-Host "  -> PotPlayer verified at: $loc" -ForegroundColor Green
                return $loc
            }
        }

        # Detailed failure diagnostic
        Write-Host "`n[ERROR] Daum PotPlayer silent installation failed (Exit Code: $installerExitCode)." -ForegroundColor Red
        if ($existingUninstaller -and -not $uninstallConfirmed) {
            Write-Host "Kakao's installer failed because an existing PotPlayer installation is still present." -ForegroundColor Yellow
            Write-Host "To resolve this: please uninstall PotPlayer via Windows Settings -> Installed apps," -ForegroundColor Yellow
            Write-Host "or rerun this script and allow uninstallation when prompted.`n" -ForegroundColor Yellow
        } else {
            Write-Host "Please ensure you have administrative permissions and no locked PotPlayer files.`n" -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "Silent PotPlayer installation error: $($_.Exception.Message)"
    }

    return $null
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
        $headers = @{
            "User-Agent" = "MvToolsSetup/1.0.0"
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
        $req.UserAgent = "MvToolsSetup/1.0.0"
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
            $assetsReq.UserAgent = "MvToolsSetup/1.0.0"
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
# HELPER: Automated Acquisition & Setup of AviSynth+
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
        $extractorExe = Ensure-7ZipExtractor -TargetPotPlayerDir $TargetPotPlayerDir
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

        # Locate AviSynth.dll under requested architecture directory
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

        # Verify binary architecture directly from the extracted PE header
        $peMachine = Get-PeMachine -FilePath $targetDll.FullName
        $peArchDesc = switch ($peMachine) {
            0xAA64 { "ARM64 (0xAA64)" }
            0x8664 { "x64 (0x8664)" }
            0x014C { "x86 (0x014C)" }
            default { "Unknown (0x{0:X4})" -f $peMachine }
        }

        $destDll = Join-Path $TargetPotPlayerDir "AviSynth.dll"
        try {
            Copy-Item -Path $targetDll.FullName -Destination $destDll -Force -ErrorAction Stop
            Write-Host "  -> Deployed native AviSynth.dll [$peArchDesc] to: $TargetPotPlayerDir" -ForegroundColor Green
            return $destDll
        } catch {
            Write-Host "  [ERROR] Failed to deploy AviSynth.dll to '$TargetPotPlayerDir': $($_.Exception.Message)" -ForegroundColor Red
            if ($_.Exception -is [System.UnauthorizedAccessException]) {
                Write-Host "  Administrator privileges are required to write to '$TargetPotPlayerDir'." -ForegroundColor Yellow
            }
            return $null
        }
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
# HELPER: Discover Latest MVTools Release Asset from GitHub
# ---------------------------------------------------------
function Get-MvToolsLatestReleaseAsset {
    param(
        [string]$RepoSlug = "",
        [string]$ReleaseTag = "",
        [string]$TargetPotPlayerDir = ""
    )

    $targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetPotPlayerDir
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
        $headers = @{
            "User-Agent" = "MvToolsSetup/1.0.0"
            "Accept"     = "application/vnd.github.v3+json"
        }
        $release = Invoke-RestMethod -Uri $ApiUrl -Headers $headers -TimeoutSec 15 -ErrorAction Stop
        if ($release -and $release.assets -and $release.assets.Count -gt 0) {
            $ReleaseInfo.TagName = if ($release.tag_name) { $release.tag_name } else { $ReleaseTag }

            $targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $TargetPotPlayerDir
            if ($targetArch -eq "x64") {
                # x64: match explicit x64 archives first, then generic non-arm64 fallbacks
                $asset = $release.assets | Where-Object { $_.name -match '(?i)x64.*\.7z$' } | Select-Object -First 1
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)x64.*\.zip$' } | Select-Object -First 1
                }
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)mvtools-.*\.7z$' -and $_.name -notmatch '(?i)arm64' } | Select-Object -First 1
                }
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)mvtools.*\.7z$' -and $_.name -notmatch '(?i)arm64' } | Select-Object -First 1
                }
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)\.7z$' -and $_.name -notmatch '(?i)arm64' } | Select-Object -First 1
                }
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)mvtools.*\.zip$' -and $_.name -notmatch '(?i)arm64' } | Select-Object -First 1
                }
            } else {
                # ARM64: match arm64 release archives
                $asset = $release.assets | Where-Object { $_.name -match '(?i)arm64.*\.7z$' } | Select-Object -First 1
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)arm64.*\.zip$' } | Select-Object -First 1
                }
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)mvtools.*\.7z$' -and $_.name -notmatch '(?i)x64' } | Select-Object -First 1
                }
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)\.7z$' -and $_.name -notmatch '(?i)x64' } | Select-Object -First 1
                }
                if (-not $asset) {
                    $asset = $release.assets | Where-Object { $_.name -match '(?i)\.zip$' -and $_.name -notmatch '(?i)x64' } | Select-Object -First 1
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
        Write-Host "  -> MVTools GitHub API notice: $($_.Exception.Message)" -ForegroundColor Gray
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
        $req.UserAgent = "MvToolsSetup/1.0.0"
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
            $assetsReq.UserAgent = "MvToolsSetup/1.0.0"
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
                $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)x64.*\.7z$' } | Select-Object -First 1
                if (-not $selectedUrl) { $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)x64.*\.zip$' } | Select-Object -First 1 }
                if (-not $selectedUrl) { $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)mvtools.*\.7z$' -and $_ -notmatch '(?i)arm64' } | Select-Object -First 1 }
                if (-not $selectedUrl) { $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)\.7z$' -and $_ -notmatch '(?i)arm64' } | Select-Object -First 1 }
                if (-not $selectedUrl) { $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)mvtools.*\.zip$' -and $_ -notmatch '(?i)arm64' } | Select-Object -First 1 }
            } else {
                $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)arm64.*\.7z$' } | Select-Object -First 1
                if (-not $selectedUrl) { $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)arm64.*\.zip$' } | Select-Object -First 1 }
                if (-not $selectedUrl) { $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)mvtools.*\.7z$' -and $_ -notmatch '(?i)x64' } | Select-Object -First 1 }
                if (-not $selectedUrl) { $selectedUrl = $foundUrls | Where-Object { $_ -match '(?i)\.7z$' -and $_ -notmatch '(?i)x64' } | Select-Object -First 1 }
            }

            if ($selectedUrl) {
                $ReleaseInfo.DownloadUrl = $selectedUrl
                $ReleaseInfo.FileName = [System.IO.Path]::GetFileName($selectedUrl)
                return $ReleaseInfo
            }
        }
    } catch {
        Write-Host "  -> MVTools web discovery notice: $($_.Exception.Message)" -ForegroundColor Gray
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
    $assetInfo = Get-MvToolsLatestReleaseAsset -RepoSlug $RepoSlug -ReleaseTag $ReleaseTag -TargetPotPlayerDir $TargetDir
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
        $depanDll = $archPool | Where-Object { $_.Name -ieq "DePan.dll" } | Select-Object -First 1
        $depanEstDll = $archPool | Where-Object { $_.Name -ieq "DePanEstimate.dll" } | Select-Object -First 1
        $affinityDll = $archPool | Where-Object { $_.Name -ieq "AvsAffinity.dll" } | Select-Object -First 1

        if (-not $cpuDll) {
            throw "Could not locate 'mvtools2.dll' inside the downloaded release archive!"
        }

        $deployDir = if (-not [string]::IsNullOrWhiteSpace($TargetDir)) { $TargetDir } else { $ScriptDir }
        if (-not (Test-Path $deployDir)) {
            New-Item -ItemType Directory -Path $deployDir -Force | Out-Null
        }

        try {
            Copy-Item -Path $cpuDll.FullName -Destination (Join-Path $deployDir "mvtools2.dll") -Force -ErrorAction Stop
            Write-Host ("  -> Deployed unified mvtools2.dll ({0} CPU NEON & D3D12 GPU) to: {1}" -f $archLabel, $deployDir) -ForegroundColor Green

            if ($depanDll) {
                Copy-Item -Path $depanDll.FullName -Destination (Join-Path $deployDir "DePan.dll") -Force -ErrorAction Stop
                Write-Host "  -> Deployed DePan.dll to: $deployDir" -ForegroundColor Green
            }
            if ($depanEstDll) {
                Copy-Item -Path $depanEstDll.FullName -Destination (Join-Path $deployDir "DePanEstimate.dll") -Force -ErrorAction Stop
                Write-Host "  -> Deployed DePanEstimate.dll to: $deployDir" -ForegroundColor Green
            }
            if ($affinityDll) {
                Copy-Item -Path $affinityDll.FullName -Destination (Join-Path $deployDir "AvsAffinity.dll") -Force -ErrorAction Stop
                Write-Host "  -> Deployed AvsAffinity.dll to: $deployDir" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [ERROR] Failed to deploy MVTools binaries to '$deployDir': $($_.Exception.Message)" -ForegroundColor Red
            if ($_.Exception -is [System.UnauthorizedAccessException]) {
                Write-Host "  Administrator privileges are required to write to '$deployDir'." -ForegroundColor Yellow
            }
            return $null
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
# HELPER: Deploy Architecture-Filtered AviSynth+ Profiles
# ---------------------------------------------------------
function Install-ArchitectureFilteredProfiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPotPlayerDir,
        [string]$TargetArch = "arm64",
        [string]$RepoRoot = ".",
        [string]$RepoSlug = "tordona/mvtools",
        [string]$Branch = "mvtools-d3d12"
    )

    $potAvsDir = Join-Path $TargetPotPlayerDir "AviSynth"
    if (-not (Test-Path $potAvsDir)) {
        New-Item -ItemType Directory -Path $potAvsDir -Force | Out-Null
    }

    $isArm64 = ($TargetArch -eq "arm64")
    Write-Host "`n[PROFILES] Deploying $TargetArch AviSynth+ profiles..." -ForegroundColor Cyan

    $localAvsDir = Join-Path $RepoRoot "AviSynth"
    $deployedCount = 0

    if (Test-Path $localAvsDir) {
        $localProfiles = Get-ChildItem -Path $localAvsDir -Filter "*.avs"
        foreach ($p in $localProfiles) {
            $isArm64Profile = ($p.Name -like "Snapdragon*" -or $p.Name -like "*Spark*" -or $p.Name -like "RTX*")
            # Filter rule: ARM64 gets ARM64 profiles; x86-64 gets strictly non-ARM64
            if (($isArm64 -and $isArm64Profile) -or (-not $isArm64 -and -not $isArm64Profile)) {
                Copy-Item -Path $p.FullName -Destination (Join-Path $potAvsDir $p.Name) -Force
                $deployedCount++
            }
        }
    }

    # If no local profiles were deployed, download directly from GitHub
    if ($deployedCount -eq 0) {
        Write-Host "  -> Downloading $TargetArch profiles from $RepoSlug ($Branch)..." -ForegroundColor Cyan
        
        $profileManifest = if ($isArm64) {
            @(
                "RTX-Spark-N1X-Eco.avs", "RTX-Spark-N1X-Balanced.avs", "RTX-Spark-N1X-MaxQuality.avs",
                "Snapdragon-X2-Eco.avs", "Snapdragon-X2-Balanced.avs", "Snapdragon-X2-MaxQuality.avs",
                "Snapdragon-X-Eco.avs", "Snapdragon-X-Balanced.avs", "Snapdragon-X-MaxQuality.avs",
                "Snapdragon-C-Eco.avs", "Snapdragon-C-Balanced.avs", "Snapdragon-C-MaxQuality.avs",
                "Snapdragon-8cxGen3-Eco.avs", "Snapdragon-8cxGen3-Balanced.avs", "Snapdragon-8cxGen3-MaxQuality.avs",
                "Snapdragon-8cxGen2-Eco.avs", "Snapdragon-8cxGen2-Balanced.avs", "Snapdragon-8cxGen2-MaxQuality.avs",
                "Snapdragon-8cxGen1-Eco.avs", "Snapdragon-8cxGen1-Balanced.avs", "Snapdragon-8cxGen1-MaxQuality.avs",
                "Snapdragon-850-Eco.avs", "Snapdragon-850-Balanced.avs", "Snapdragon-850-MaxQuality.avs",
                "Snapdragon-7cGen2-Eco.avs", "Snapdragon-7cGen2-Balanced.avs", "Snapdragon-7cGen2-MaxQuality.avs"
            )
        } else {
            @(
                "Generic-x64-Eco.avs", "Generic-x64-Balanced.avs", "Generic-x64-MaxQuality.avs",
                "RyzenAI-5-340-Eco.avs", "RyzenAI-5-340-Balanced.avs", "RyzenAI-5-340-MaxQuality.avs",
                "Intel-N100-Eco.avs", "Intel-N100-Balanced.avs", "Intel-N100-MaxQuality.avs",
                "Core-i3-1215U-Eco.avs", "Core-i3-1215U-Balanced.avs", "Core-i3-1215U-MaxQuality.avs",
                "Core-i5-1135G7-Eco.avs", "Core-i5-1135G7-Balanced.avs", "Core-i5-1135G7-MaxQuality.avs",
                "Core-i5-8259U-Eco.avs", "Core-i5-8259U-Balanced.avs", "Core-i5-8259U-MaxQuality.avs",
                "Core-i5-7Y54-Eco.avs", "Core-i5-7Y54-Balanced.avs", "Core-i5-7Y54-MaxQuality.avs",
                "Core-i7-11850H-Eco.avs", "Core-i7-11850H-Balanced.avs", "Core-i7-11850H-MaxQuality.avs"
            )
        }

        $wc = New-Object System.Net.WebClient
        try {
            foreach ($pName in $profileManifest) {
                $rawUrl = "https://raw.githubusercontent.com/$RepoSlug/$Branch/AviSynth/$pName"
                $dest = Join-Path $potAvsDir $pName
                try {
                    $wc.DownloadFile($rawUrl, $dest)
                    if (Test-Path $dest) { $deployedCount++ }
                } catch {}
            }
        } finally {
            $wc.Dispose()
        }
    }

    Write-Host "  -> Installed $deployedCount $TargetArch profile(s) into: $potAvsDir" -ForegroundColor Green

    # Bake absolute plugin paths into deployed profiles to make them working-directory agnostic
    $cleanPotDir = $TargetPotPlayerDir.TrimEnd('\/').Replace('\', '/')
    $potMvTools = "$cleanPotDir/mvtools2.dll"
    $potMvToolsD3d12 = $potMvTools
    $potAffinity = "$cleanPotDir/AvsAffinity.dll"

    Get-ChildItem -Path $potAvsDir -Filter "*.avs" | ForEach-Object {
        try {
            $avsContent = [System.IO.File]::ReadAllText($_.FullName)
            # Unified mvtools2.dll
            $avsContent = $avsContent -replace '(?i)"mvtools2\.dll"', "`"$potMvTools`""
            $avsContent = $avsContent -replace '(?i)"AvsAffinity\.dll"', "`"$potAffinity`""
            [System.IO.File]::WriteAllText($_.FullName, $avsContent, [System.Text.Encoding]::ASCII)
        } catch {}
    }

    # Mirror into roaming AppData presets for PotPlayer
    $appData = if ($env:APPDATA) { $env:APPDATA } else { [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData) }
    $appDataAvsDirs = @(
        (Join-Path $appData "PotPlayer64\AviSynth"),
        (Join-Path $appData "PotPlayerMini64\AviSynth")
    )
    foreach ($ad in $appDataAvsDirs) {
        try {
            if (-not (Test-Path $ad)) { New-Item -ItemType Directory -Path $ad -Force | Out-Null }
            Copy-Item -Path (Join-Path $potAvsDir "*.avs") -Destination $ad -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    return $deployedCount
}

# ---------------------------------------------------------
# HELPER: System Hardware Platform & Recommendation Engine
# ---------------------------------------------------------
function Get-SystemHardwareInfo {
    $cpu = $null
    $gpu = $null
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    } catch {}
    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
    } catch {}

    $totalRamGb = 0
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cs -and $cs.TotalPhysicalMemory) {
            $totalRamGb = [math]::Round($cs.TotalPhysicalMemory / 1GB)
        }
    } catch {}

    return [PSCustomObject]@{
        CpuName           = if ($cpu -and $cpu.Name) { $cpu.Name.Trim() } else { "Unknown Processor" }
        NumberOfCores     = if ($cpu -and $cpu.NumberOfCores) { $cpu.NumberOfCores } else { 0 }
        LogicalProcessors = if ($cpu -and $cpu.NumberOfLogicalProcessors) { $cpu.NumberOfLogicalProcessors } else { 0 }
        GpuName           = if ($gpu -and $gpu.Name) { $gpu.Name.Trim() } else { "Unknown Display Adapter" }
        RamGb             = $totalRamGb
    }
}

function Match-HardwareProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPotPlayerDir,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$HardwareInfo,
        [string]$TargetArch = "arm64"
    )

    $potAvsDir = Join-Path $TargetPotPlayerDir "AviSynth"
    $availableProfiles = Get-ChildItem -Path $potAvsDir -Filter "*.avs" -ErrorAction SilentlyContinue

    $combined = "$($HardwareInfo.CpuName) $($HardwareInfo.GpuName)"
    $isArm64 = ($TargetArch -eq "arm64")

    # Match rules for Windows on ARM64
    if ($isArm64) {
        if ($combined -match '(?i)N1X|Spark|RTX.*Spark') {
            $cand = Join-Path $potAvsDir "RTX-Spark-N1X-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "RTX-Spark-N1X-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)\bSnapdragon\s+X2\b|X2[EP]|Adreno\s*X2') {
            $cand = Join-Path $potAvsDir "Snapdragon-X2-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Snapdragon-X2-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)\bSnapdragon\s+X\b|X1[EP]|Oryon|X\s*(?:Elite|Plus)') {
            $cand = Join-Path $potAvsDir "Snapdragon-X-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Snapdragon-X-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)8cx.*Gen.*3|SC8280|SQ3') {
            $cand = Join-Path $potAvsDir "Snapdragon-8cxGen3-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Snapdragon-8cxGen3-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)8cx.*Gen.*2|SQ2') {
            $cand = Join-Path $potAvsDir "Snapdragon-8cxGen2-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Snapdragon-8cxGen2-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)8cx|SC8180|SQ1') {
            $cand = Join-Path $potAvsDir "Snapdragon-8cxGen1-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Snapdragon-8cxGen1-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)\b850\b|SD850') {
            $cand = Join-Path $potAvsDir "Snapdragon-850-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Snapdragon-850-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)\b7c\b|SC7[12]80') {
            $cand = Join-Path $potAvsDir "Snapdragon-7cGen2-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Snapdragon-7cGen2-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)\bSnapdragon\s+C\b|Adreno\s*(?:A)?643') {
            $cand = Join-Path $potAvsDir "Snapdragon-C-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Snapdragon-C-Balanced"; IsGeneric = $false } }
        }

        # Fallback for unrecognized ARM64 hardware
        $fallback = Join-Path $potAvsDir "Snapdragon-X-Balanced.avs"
        if (-not (Test-Path $fallback)) {
            $fallback = ($availableProfiles | Select-Object -First 1).FullName
        }
        return @{ Profile = $fallback; Name = (Split-Path $fallback -LeafBase); IsGeneric = $true }
    }
    else {
        # Match rules for x86-64 hardware
        if ($combined -match '(?i)340|Ryzen.*AI') {
            $cand = Join-Path $potAvsDir "RyzenAI-5-340-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "RyzenAI-5-340-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)11850H') {
            $cand = Join-Path $potAvsDir "Core-i7-11850H-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Core-i7-11850H-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)1135G7') {
            $cand = Join-Path $potAvsDir "Core-i5-1135G7-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Core-i5-1135G7-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)8259U') {
            $cand = Join-Path $potAvsDir "Core-i5-8259U-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Core-i5-8259U-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)7Y54') {
            $cand = Join-Path $potAvsDir "Core-i5-7Y54-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Core-i5-7Y54-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)1215U') {
            $cand = Join-Path $potAvsDir "Core-i3-1215U-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Core-i3-1215U-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)N100') {
            $cand = Join-Path $potAvsDir "Intel-N100-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Intel-N100-Balanced"; IsGeneric = $false } }
        }

        # Fallback for unrecognized x86-64 hardware
        $fallback = Join-Path $potAvsDir "Generic-x64-Balanced.avs"
        if (-not (Test-Path $fallback)) {
            $fallback = ($availableProfiles | Select-Object -First 1).FullName
        }
        return @{ Profile = $fallback; Name = "Generic-x64-Balanced"; IsGeneric = $true }
    }
}

# ---------------------------------------------------------
# HELPER: Ensure PotPlayer Shortcuts Have Correct Working Directory
# ---------------------------------------------------------
function Set-PotPlayerShortcutWorkingDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPotPlayerDir
    )
    if (-not (Test-Path $TargetPotPlayerDir)) { return }

    $shortcutDirs = @(
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\PotPlayer",
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Daum",
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\PotPlayer"),
        (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Daum"),
        (Join-Path $env:PUBLIC "Desktop"),
        (Join-Path $env:USERPROFILE "Desktop")
    )

    try {
        $wscript = New-Object -ComObject WScript.Shell
        foreach ($dir in $shortcutDirs) {
            if (Test-Path $dir) {
                Get-ChildItem -Path $dir -Filter "*PotPlayer*.lnk" -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        $sc = $wscript.CreateShortcut($_.FullName)
                        if ($sc.TargetPath -match '(?i)PotPlayer.*\.exe' -and $sc.WorkingDirectory -ne $TargetPotPlayerDir) {
                            $sc.WorkingDirectory = $TargetPotPlayerDir
                            $sc.Save()
                            Write-Host "  -> Fixed shortcut working directory: $($_.Name)" -ForegroundColor Green
                        }
                    } catch {}
                }
            }
        }
    } catch {}
}

# ---------------------------------------------------------
# HELPER: Configure PotPlayer Settings & Active Profile
# ---------------------------------------------------------
function Set-PotPlayerActiveProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPotPlayerDir,
        [Parameter(Mandatory = $true)]
        [string]$ProfilePath
    )

    if (-not (Test-Path $ProfilePath)) {
        Write-Warning "Profile path does not exist: $ProfilePath"
        return $false
    }

    $cleanPotDir = $TargetPotPlayerDir.TrimEnd('\/').Replace('\', '/')
    $potMvTools = "$cleanPotDir/mvtools2.dll"
    $potMvToolsD3d12 = $potMvTools
    $potAffinity = "$cleanPotDir/AvsAffinity.dll"

    $rawAvs = Get-Content -Path $ProfilePath -Raw
    # Unified mvtools2.dll
    $resolvedAvs = $rawAvs -replace '(?i)"mvtools2\.dll"', "`"$potMvTools`""
    $resolvedAvs = $resolvedAvs -replace '(?i)"AvsAffinity\.dll"', "`"$potAffinity`""

    Set-PotPlayerShortcutWorkingDirectory -TargetPotPlayerDir $TargetPotPlayerDir

    $scriptLines = $resolvedAvs -split "\r?\n"
    $potScriptValue = $scriptLines -join ([char]2 + [char]1)

    $appData = if ($env:APPDATA) { $env:APPDATA } else { [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData) }
    $iniTargets = @(
        (Join-Path $appData "PotPlayer64\PotPlayer64.ini"),
        (Join-Path $appData "PotPlayerMini64\PotPlayerMini64.ini"),
        (Join-Path $TargetPotPlayerDir "PotPlayer64.ini"),
        (Join-Path $TargetPotPlayerDir "PotPlayerMini64.ini")
    )

    $configuredCount = 0
    foreach ($iniPath in ($iniTargets | Select-Object -Unique)) {
        $parent = Split-Path $iniPath -Parent
        if (-not (Test-Path $parent)) {
            try { New-Item -ItemType Directory -Path $parent -Force | Out-Null } catch {}
        }

        if (-not (Test-Path $iniPath)) {
            try {
                "[Settings]`r`nAutoIni=0`r`nAutoDownloadFile=0`r`nCheckAutoUpdate=0`r`n[Positions]`r`nMainWindowState=128`r`n" | Set-Content -Path $iniPath -Encoding Unicode
            } catch {}
        }

        if (Test-Path $iniPath) {
            try {
                $lines = Get-Content -Path $iniPath -Encoding Unicode
                $newLines = [System.Collections.Generic.List[string]]::new()
                $inSettings = $false
                $keysToSet = [ordered]@{
                    "AutoDownloadFile"       = "0"     # Disable automatic download of update files
                    "CheckAutoUpdate"        = "0"     # Disable checking for auto updates
                    "VideoRen2"              = "15"    # Direct3D 11 Video Renderer
                    "UseSelfDxva"            = "1001"  # D3D11 Copy-Back Hardware Decode
                    "AvisynthUse"            = "1"     # Enable AviSynth processing
                    "AvisynthSource"         = "1"     # Enable potplayer_source()
                    "AvisynthUseProgressive" = "0"     # Progressive
                    "AvisynthScript"         = $potScriptValue
                }
                $applied = @{}
                foreach ($k in $keysToSet.Keys) { $applied[$k] = $false }

                foreach ($line in $lines) {
                    if ($line -match '^\s*\[Settings\]') {
                        $inSettings = $true
                        $newLines.Add($line)
                        continue
                    } elseif ($line -match '^\s*\[') {
                        if ($inSettings) {
                            foreach ($k in $keysToSet.Keys) {
                                if (-not $applied[$k]) {
                                    $newLines.Add("$k=$($keysToSet[$k])")
                                    $applied[$k] = $true
                                }
                            }
                            $inSettings = $false
                        }
                        $newLines.Add($line)
                        continue
                    }

                    if ($inSettings) {
                        $matchedKey = $null
                        foreach ($k in $keysToSet.Keys) {
                            if ($line -match "^\s*$([regex]::Escape($k))\s*=") {
                                $matchedKey = $k
                                break
                            }
                        }
                        if ($matchedKey) {
                            $newLines.Add("$matchedKey=$($keysToSet[$matchedKey])")
                            $applied[$matchedKey] = $true
                        } else {
                            $newLines.Add($line)
                        }
                    } else {
                        $newLines.Add($line)
                    }
                }

                if ($inSettings) {
                    foreach ($k in $keysToSet.Keys) {
                        if (-not $applied[$k]) {
                            $newLines.Add("$k=$($keysToSet[$k])")
                            $applied[$k] = $true
                        }
                    }
                }

                [System.IO.File]::WriteAllLines($iniPath, $newLines, [System.Text.Encoding]::Unicode)
                $configuredCount++
            } catch {
                Write-Warning "Could not write settings to '$iniPath': $($_.Exception.Message)"
            }
        }
    }

    return ($configuredCount -gt 0)
}

# ---------------------------------------------------------
# HELPER: Generate Hardware-Tuned AI Agent Prompt to Clipboard
# ---------------------------------------------------------
function Copy-AiAgentHardwarePrompt {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$HardwareInfo,
        [string]$TargetArch = "arm64"
    )

    $isArm64 = ($TargetArch -eq "arm64")
    $archDesc = if ($isArm64) { "Windows 11 on ARM64 (AArch64)" } else { "Windows 11 x86-64" }
    $gpuName = if ($HardwareInfo.GpuName) { $HardwareInfo.GpuName } else { "" }
    $isLowEndGpu = ($gpuName -match '(?i)600|605|610|615|618|630|610M|HD Graphics|Basic Display')
    $pluginRule = if (-not $isLowEndGpu) {
        '2. Engine & Plugin Hook: Direct3D 12-eligible hardware (>= 32 EUs / >= 4 CUs / Adreno 680+, TDP > 10 W on x64 or ARM64) MUST load unified binary via ``LoadPlugin("mvtools2.dll")``, optional companion ``try { LoadPlugin("AvsAffinity.dll") } catch(e) {}``, and activate Direct3D 12 compute mode via ``MEnableD3D12(USE_D3D12)`` immediately following LoadPlugin with dual-path parameterization (MANDATORY: always default to USE_D3D12 = false; never emit USE_D3D12 = true by default). Low-end / entry-tier silicon (< 32 EUs / < 600 GFLOPS or TDP <= 10 W, e.g. N5000 / UHD 600/605, Snapdragon 7c/850) runs 100% native CPU SIMD without D3D12. Hook video via ``src = potplayer_source()``.'
    } else {
        '2. Engine & Plugin Hook: Entry-tier silicon with < 32 EUs / < 600 GFLOPS or TDP <= 10 W MUST run 100% native CPU SIMD via ``LoadPlugin("mvtools2.dll")`` and optional companion ``try { LoadPlugin("AvsAffinity.dll") } catch(e) {}`` (DO NOT reference USE_D3D12 or MEnableD3D12 on low-end silicon). Hook video via ``src = potplayer_source()``.'
    }

    $promptText = @"
I need a hardware-tailored AviSynth+ profile set for real-time 24 fps -> 60 fps video motion interpolation in Daum PotPlayer using MVTools2.

My Target Hardware Specifications:
- CPU: $($HardwareInfo.CpuName)
- Core Topology: $($HardwareInfo.NumberOfCores) physical cores / $($HardwareInfo.LogicalProcessors) logical threads
- GPU: $($HardwareInfo.GpuName)
- Memory: $($HardwareInfo.RamGb) GB System RAM
- Platform Architecture: $archDesc

Specification & Reference Guide:
- Quickstart Guide: https://tordona.github.io/mvtools/#/guides/GenerateCustomProfiles
- Technical Specification (Live Origin Fetch): https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/docs/guides/AIAgentProfileGuide.md
- Web Mirror (GitHub UI View): https://github.com/tordona/mvtools/blob/mvtools-d3d12/docs/guides/AIAgentProfileGuide.md

Mandatory Architecture & AviSynth+ 3.x Rules:
1. Multi-Threading: MUST declare ``SetMemoryMax()`` and ``SetFilterMTMode("DEFAULT_MT_MODE", 2)`` at the top BEFORE calling ``potplayer_source()`` (NEVER use legacy ``SetMTMode``).
$pluginRule
3. Function Naming: MUST spell MVTools functions as ``MAnalyse`` (with 's') and specify ``isb=true`` on the backward vector search.
4. Single-Level Geometry & Quantitative Subpixel Rules: MUST use ``levels=1`` in both MSuper and MAnalyse (``pel=1, hpad=pad_val, vpad=pad_val, sharp=0`` with ``pad_size = USE_D3D12 ? 8 : 0``). For MaxQuality: use ``pel=1, sharp=1`` by default; set ``pel=2, sharp=2`` (Wiener filter) ONLY if platform meets ALL quantitative criteria: >= 8 physical homogeneous cores (or >= 6 Performance cores on hybrid), sustained TDP >= 35 W, and dual-channel memory; otherwise strictly default to ``pel=1, sharp=1`` (when USE_D3D12=true, strictly pel=1 with hardware bilinear sampler).
5. Vector Computation: MUST use ``chroma=false`` in MAnalyse and MRecalculate (luma-only search cuts vector compute in half and is required for D3D12 compute offload).
6. Frame Synthesis: MUST use ``last = MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=<Mode>, blend=<Blend>)`` (assign to 'last' so PotPlayer receives the interpolated clip; never assign to an unused variable like 'out ='; DO NOT use MFlowFps for real-time 60 fps interpolation). Mode gating: Eco (Profile 1) and Balanced (Profile 2) MUST set ``mode=0`` across BOTH GPU and CPU (never mode=2 on Eco/Balanced). MaxQuality (Profile 3) sets ``mode=2`` (GPU Dynamic Median with occlusion masking) when USE_D3D12=true, and ``mode=0`` on CPU fallback (USE_D3D12 ? 2 : 0).
7. Direct3D 12 Zero-Overlap Invariant: Direct3D 12 GPU offload (USE_D3D12=true) strictly requires zero block overlap (overlap=0). Shaders in flow_warp.hlsl index vectors via direct coordinate division (DTid.x / nBlkSizeX); non-zero overlap causes coordinate misalignment and severe image tearing. When USE_D3D12=true, MaxQuality MUST use dual-pass coarse-to-fine refinement with ``MRecalculate(divide=0)`` and zero overlap (coarse 32x32 MAnalyse -> fine 16x16 MRecalculate with overlap=0). Overlap is ONLY permitted on CPU SIMD fallback (``overlap_sz = USE_D3D12 ? 0 : (is_4k ? 8 : 4)``).
8. Thread Allocation & P-Core Budgeting: MUST size worker threads to match available physical Performance cores without exceeding them (``threads <= physical_p_cores``; for hybrid Intel P+E or AMD Zen 5/5c CPUs, budget threads strictly against P-cores, never total physical cores or E-cores; e.g. 4P+8E -> threads=3 to 4, 6P+8E -> threads=3 to 5), chaining ``last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last`` immediately prior to ``Prefetch(threads, 4 for Eco, 6 for Balanced/MaxQuality)``. When USE_D3D12=true, thread count represents GPU queue lookahead depth (threads=2 for Eco, 3 for Balanced, 4 for MaxQuality).
9. Dynamic 4K Resolution Adaptation & Feasibility Classification: MUST declare ``is_4k = (src.Width() > 2048)`` strictly AFTER ``src = potplayer_source()`` and BEFORE any block size calculations. Classify 4K feasibility:
   - Tier A (Supported: VPU >= 4K 60 fps, UMA >= 50 GB/s, P-Cores >= 4): Scale block sizes by 2x (coarse 64x64 -> fine 32x32, 8,160 blocks) to preserve macroblock count invariance. On 4K, force pel=1, sharp=0, blend=false, and size mem_limit=1280.
   - Tier B (Constrained: 25-45 GB/s or 4 E-cores): Limit 4K to single-pass coarse blocks (blk_sz = is_4k ? 64 : 32, mode=0, blend=false).
   - Tier C (Unsupported: VPU capped at 4K 30 fps, UMA < 20 GB/s, or <= 2 P-Cores on <= 7 W TDP): Dynamically bypass 4K streams via ``if (src.Width() > 2048) { return src }`` immediately after ``potplayer_source()`` to preserve smooth native playback. NEVER place resolution-dependent expressions above ``potplayer_source()``.
10. Clean Script Formatting: MUST emit standard AviSynth+ syntax with one statement per line. Never collapse multiple statements onto a single line without linebreaks.
11. Standard Header & AI Provenance: MUST format every profile header with standard metadata comments including ``# Generator: <Agent Name & Model> (AIAgentProfileGuide Rev 2.3.12)`` (e.g. Claude 3.5 Sonnet, ChatGPT-4o, Google Antigravity).

Generate the complete 3-tier profile set following these exact rules:
- Profile 1 (Eco): Coarse blocks (``blk_sz = is_4k ? 64 : 32, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=1, mode=0, blend=false``), lowest package power.
- Profile 2 (Balanced): Crisp blocks (``blk_sz = is_4k ? 32 : 16, blksize=blk_sz, blksizev=blk_sz, search=2, searchparam=2, mode=0, blend=false``), daily driver.
- Profile 3 (MaxQuality): Dual-pass coarse-to-fine refinement for GPU offload (coarse 32x32 MAnalyse -> fine 16x16 MRecalculate with divide=0, overlap=0, search=2, searchparam=2; overlap strictly prohibited on GPU offload). CPU fallback uses overlap (overlap_sz = USE_D3D12 ? 0 : (is_4k ? 8 : 4)). Synthesis mode sets mode=2 on GPU and mode=0 on CPU (synth_mode = USE_D3D12 ? 2 : 0, blend=true). Evaluate quantitative pel rules for pel=1 vs pel=2.
"@

    try {
        Set-Clipboard -Value $promptText -ErrorAction Stop
        Write-Host "`n  [COPIED] Hardware-tailored prompt copied to your clipboard!" -ForegroundColor Green
        Write-Host "  You can paste it directly into Antigravity, Gemini, ChatGPT, Claude, or Cursor.`n" -ForegroundColor Cyan
    } catch {
        # Fallback if Set-Clipboard cmdlet fails in older PowerShell versions
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.Clipboard]::SetText($promptText)
            Write-Host "`n  [COPIED] Hardware-tailored prompt copied to your clipboard!" -ForegroundColor Green
        } catch {
            Write-Host "`n[PROMPT READY] Please copy the following prompt for your AI Agent:" -ForegroundColor Yellow
            Write-Host "------------------------------------------------------------" -ForegroundColor Gray
            Write-Host $promptText -ForegroundColor Cyan
            Write-Host "------------------------------------------------------------`n" -ForegroundColor Gray
        }
    }
}

# =========================================================
# MAIN INSTALLATION WORKFLOW
# =========================================================
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " MVTools2 + Daum PotPlayer 60 fps Automated Setup" -ForegroundColor Cyan
Write-Host " https://tordona.github.io/mvtools/" -ForegroundColor Gray
Write-Host "================================================================`n" -ForegroundColor Cyan

# Step 1: Detect Architecture
$targetArch = Get-TargetBinaryArchitecture -TargetPotPlayerDir $PotPlayerDir
$archUpper = $targetArch.ToUpper()
Write-Host "[1/6] Detecting System Architecture..." -ForegroundColor Cyan
Write-Host "  -> Active Platform: $archUpper" -ForegroundColor Green

# Step 2: Resolve or Install PotPlayer
Write-Host "`n[2/6] Verifying Daum PotPlayer Installation..." -ForegroundColor Cyan

# Close active PotPlayer processes early to avoid locked files during verification / installation
Stop-PotPlayerProcesses

$resolvedPotDir = Get-PotPlayerInstallPath -ExplicitDir $PotPlayerDir

if (-not $resolvedPotDir) {
    Write-Host "  -> Daum PotPlayer 64-bit not found locally." -ForegroundColor Yellow
    $resolvedPotDir = Install-PotPlayer -TargetDir ""
    if (-not $resolvedPotDir) {
        Write-Host "`n[SETUP ABORTED] Daum PotPlayer could not be installed or located." -ForegroundColor Red
        return
    }
} else {
    Write-Host "  -> Found PotPlayer: $resolvedPotDir" -ForegroundColor Green
}

# Step 3: Ensure Visual C++ Redistributable
Write-Host "`n[3/6] Auditing Microsoft Visual C++ $archUpper Runtimes..." -ForegroundColor Cyan
$isVcReady = Ensure-VisualCppRedistributable -TargetPotPlayerDir $resolvedPotDir -AutoInstall:$AutoInstall

# Secondary process guard to ensure PotPlayer remained closed before binary injection
Stop-PotPlayerProcesses

# Step 4: Ensure Native AviSynth.dll
Write-Host "`n[4/6] Verifying Native AviSynth.dll in PotPlayer..." -ForegroundColor Cyan
$potAviSynthDll = Join-Path $resolvedPotDir "AviSynth.dll"
$expectedMachine = if ($targetArch -eq "arm64") { 0xAA64 } else { 0x8664 }
$needAviSynth = $true

if (Test-Path $potAviSynthDll) {
    $mach = Get-PeMachine -FilePath $potAviSynthDll
    if ($mach -eq $expectedMachine) {
        Write-Host ("  -> Verified native AviSynth.dll (0x{0:X4}) in PotPlayer directory." -f $mach) -ForegroundColor Green
        $needAviSynth = $false
    } else {
        Write-Host ("  [WARNING] Existing AviSynth.dll architecture mismatched (0x{0:X4} vs expected 0x{1:X4}). Re-installing..." -f $mach, $expectedMachine) -ForegroundColor Yellow
        Remove-Item $potAviSynthDll -Force -ErrorAction SilentlyContinue
    }
}

if ($needAviSynth) {
    $null = Install-AviSynthPlusRelease -TargetPotPlayerDir $resolvedPotDir -Arch $targetArch
    if (Test-Path $potAviSynthDll) {
        $mach = Get-PeMachine -FilePath $potAviSynthDll
        if ($mach -eq $expectedMachine) {
            Write-Host ("  [OK] Successfully deployed and verified native AviSynth.dll (0x{0:X4})!" -f $mach) -ForegroundColor Green
        } else {
            Write-Warning ("AviSynth.dll PE machine (0x{0:X4}) does not match expected target architecture (0x{1:X4})." -f $mach, $expectedMachine)
        }
    } else {
        Write-Error "Failed to install AviSynth.dll into $resolvedPotDir! Video interpolation will fail without this library."
    }
}

# Step 5: Ensure Native MVTools2 & Companion Binaries
Write-Host "`n[5/6] Verifying MVTools2 & Companion Binaries..." -ForegroundColor Cyan
$potMvToolsDll = Join-Path $resolvedPotDir "mvtools2.dll"
$potAvsAffinityDll = Join-Path $resolvedPotDir "AvsAffinity.dll"
$needMvTools = $true

if (Test-Path $potMvToolsDll) {
    $mach = Get-PeMachine -FilePath $potMvToolsDll
    if ($mach -eq $expectedMachine) {
        Write-Host ("  -> Verified native mvtools2.dll (0x{0:X4}) in PotPlayer directory." -f $mach) -ForegroundColor Green
        $needMvTools = $false
    } else {
        Write-Host ("  [WARNING] Existing mvtools2.dll architecture mismatched (0x{0:X4} vs expected 0x{1:X4}). Re-installing..." -f $mach, $expectedMachine) -ForegroundColor Yellow
        Remove-Item $potMvToolsDll -Force -ErrorAction SilentlyContinue
    }
}

if ($needMvTools) {
    $null = Install-MvToolsRelease -TargetDir $resolvedPotDir -RepoSlug $MvToolsRepo
    if (Test-Path $potMvToolsDll) {
        $mach = Get-PeMachine -FilePath $potMvToolsDll
        if ($mach -eq $expectedMachine) {
            Write-Host ("  [OK] Successfully deployed and verified native mvtools2.dll (0x{0:X4})!" -f $mach) -ForegroundColor Green
        } else {
            Write-Warning ("mvtools2.dll PE machine (0x{0:X4}) does not match expected target architecture (0x{1:X4})." -f $mach, $expectedMachine)
        }
    } else {
        Write-Error "Failed to install mvtools2.dll into $resolvedPotDir! Video interpolation will fail without this binary."
    }
}

# Deploy local build artifacts of AvsAffinity.dll if present
$localAffinity = @(
    (Join-Path $RepoRoot "$targetArch\Release\AvsAffinity.dll"),
    (Join-Path $RepoRoot "AvsAffinity\$targetArch\Release\AvsAffinity.dll"),
    (Join-Path $PSScriptRoot "$targetArch\Release\AvsAffinity.dll"),
    (Join-Path $PSScriptRoot "AvsAffinity\$targetArch\Release\AvsAffinity.dll")
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($localAffinity -and -not (Test-Path $potAvsAffinityDll)) {
    try {
        Copy-Item -Path $localAffinity -Destination $potAvsAffinityDll -Force -ErrorAction SilentlyContinue
    } catch {}
}

if (Test-Path $potAvsAffinityDll) {
    $machAff = Get-PeMachine -FilePath $potAvsAffinityDll
    if ($machAff -eq $expectedMachine) {
        Write-Host ("  -> Verified native AvsAffinity.dll (0x{0:X4}) in PotPlayer directory." -f $machAff) -ForegroundColor Green
    }
}

# Step 6: Deploy Architecture-Filtered Profiles & Configure PotPlayer
Write-Host "`n[6/6] Deploying Profiles & Applying Configuration..." -ForegroundColor Cyan
Install-ArchitectureFilteredProfiles -TargetPotPlayerDir $resolvedPotDir -TargetArch $targetArch -RepoRoot $RepoRoot -Branch $ProfileBranch | Out-Null

$hw = Get-SystemHardwareInfo
Write-Host "`n------------------------------------------------------------" -ForegroundColor Cyan
Write-Host " HARDWARE TELEMETRY AUDIT" -ForegroundColor Cyan
Write-Host " Processor:  $($hw.CpuName)" -ForegroundColor Gray
Write-Host " Topology:   $($hw.NumberOfCores) Physical Cores / $($hw.LogicalProcessors) Logical Threads" -ForegroundColor Gray
Write-Host " Graphics:   $($hw.GpuName)" -ForegroundColor Gray
Write-Host " System RAM: $($hw.RamGb) GB" -ForegroundColor Gray
Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

# Select Active Profile
$selectedMatch = $null
if (-not [string]::IsNullOrWhiteSpace($ForceProfile)) {
    # Backward compatibility shim for legacy Snapdragon-X-Plus profile names
    if ($ForceProfile -match '(?i)Snapdragon-X-Plus-(Eco|Balanced|MaxQuality)(\.avs)?$') {
        $ForceProfile = "Snapdragon-X-$($Matches[1]).avs"
    }
    $forcedPath = Join-Path (Join-Path $resolvedPotDir "AviSynth") $ForceProfile
    if (Test-Path $forcedPath) {
        $selectedMatch = @{ Profile = $forcedPath; Name = $ForceProfile; IsGeneric = $false }
        Write-Host "  -> User forced profile: $ForceProfile" -ForegroundColor Cyan
    }
}

if (-not $selectedMatch) {
    $selectedMatch = Match-HardwareProfile -TargetPotPlayerDir $resolvedPotDir -HardwareInfo $hw -TargetArch $targetArch
}

# Apply Settings
$configSuccess = Set-PotPlayerActiveProfile -TargetPotPlayerDir $resolvedPotDir -ProfilePath $selectedMatch.Profile
if ($configSuccess) {
    Write-Host "  [OK] Pre-configured PotPlayer with: $($selectedMatch.Name)" -ForegroundColor Green
    Write-Host "  [OK] Activated Direct3D 11 Video Renderer" -ForegroundColor Green
    Write-Host "  [OK] Activated DXVA2 Copy-Back (D3D11 Hardware Decoding)" -ForegroundColor Green
} else {
    Write-Warning "Could not auto-inject PotPlayer configuration. Please select profile in PotPlayer Preferences (F5)."
}

# Handle Unrecognized Hardware Notice
$userRequestedLaunch = $false
if ($selectedMatch.IsGeneric) {
    Write-Host "`n============================================================" -ForegroundColor Yellow
    Write-Host " [NOTICE] Specific Hardware Profile Not Found" -ForegroundColor Yellow
    Write-Host " System Hardware: $($hw.CpuName)" -ForegroundColor Gray
    Write-Host " Configured Fallback: $($selectedMatch.Name)" -ForegroundColor Gray
    Write-Host " While functional, this profile is not optimized for your exact" -ForegroundColor Gray
    Write-Host " core topology, power ceiling, or thermal limits." -ForegroundColor Gray
    Write-Host "============================================================" -ForegroundColor Yellow

    if (-not $AutoInstall) {
        Write-Host "`nWould you like to tune a custom profile set for your hardware?" -ForegroundColor Cyan
        Write-Host "  [1] Finish & Open PotPlayer (Recommended - Use fallback profile)" -ForegroundColor White
        Write-Host "  [2] Generate custom profiles via AI Agent (Auto-copies hardware prompt & opens guide)" -ForegroundColor White
        Write-Host "  [3] View the AI Agent Tuning Guide in browser" -ForegroundColor White

        $choice = Read-Host -Prompt "`nSelect option [1-3] (Default: 1)"
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

        switch ($choice.Trim()) {
            "1" {
                $userRequestedLaunch = $true
            }
            "2" {
                Copy-AiAgentHardwarePrompt -HardwareInfo $hw -TargetArch $targetArch
                try {
                    Start-Process "https://tordona.github.io/mvtools/#/guides/GenerateCustomProfiles"
                } catch {}
            }
            "3" {
                try {
                    Start-Process "https://tordona.github.io/mvtools/#/guides/AIAgentProfileGuide"
                } catch {}
            }
            Default {
                Write-Host "  -> Proceeding with fallback profile: $($selectedMatch.Name)" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "  -> Custom Profiles Quickstart: https://tordona.github.io/mvtools/#/guides/GenerateCustomProfiles" -ForegroundColor Gray
        Write-Host "  -> Technical Specification: https://tordona.github.io/mvtools/#/guides/AIAgentProfileGuide" -ForegroundColor Gray
    }
}

# Verify overall installation health across all stages
$potExeCandidates = @(
    (Join-Path $resolvedPotDir "PotPlayer64.exe"),
    (Join-Path $resolvedPotDir "PotPlayerMini64.exe"),
    (Join-Path $resolvedPotDir "PotPlayer.exe"),
    (Join-Path $resolvedPotDir "PotPlayerMini.exe")
)
$potExe = $potExeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

$isAviSynthReady = (Test-Path $potAviSynthDll) -and ((Get-PeMachine -FilePath $potAviSynthDll) -eq $expectedMachine)
$isMvToolsReady = (Test-Path $potMvToolsDll) -and ((Get-PeMachine -FilePath $potMvToolsDll) -eq $expectedMachine)
$isAffinityReady = (Test-Path $potAvsAffinityDll) -and ((Get-PeMachine -FilePath $potAvsAffinityDll) -eq $expectedMachine)
$allStagesSuccessful = ($potExe -and $isAviSynthReady -and $isMvToolsReady -and $isVcReady)

if ($allStagesSuccessful) {
    Write-Host "`n================================================================" -ForegroundColor Green
    Write-Host " SETUP COMPLETE! 60 fps Motion Interpolation Ready" -ForegroundColor Green
    Write-Host " PotPlayer Executable: $potExe" -ForegroundColor Gray
    Write-Host " Active Profile:       $($selectedMatch.Name)" -ForegroundColor Gray
    if ($isAffinityReady) {
        Write-Host " Core Affinity:        AvsAffinity.dll [Active]" -ForegroundColor Gray
    }
    Write-Host "================================================================`n" -ForegroundColor Green

    $shouldLaunch = $Launch -or $userRequestedLaunch
    if ($shouldLaunch) {
        Write-Host "Launching Daum PotPlayer...`n" -ForegroundColor Cyan
        Start-Process $potExe -WorkingDirectory $resolvedPotDir
    } elseif (-not $AutoInstall) {
        Write-Host "Would you like to launch Daum PotPlayer now?" -ForegroundColor Cyan
        Write-Host "  [1] Launch PotPlayer (Default)" -ForegroundColor White
        Write-Host "  [2] Exit" -ForegroundColor White

        $launchChoice = Read-Host -Prompt "`nSelect option [1-2] (Default: 1)"
        if ([string]::IsNullOrWhiteSpace($launchChoice) -or $launchChoice.Trim() -in @("1", "y", "yes")) {
            Write-Host "`nLaunching Daum PotPlayer...`n" -ForegroundColor Cyan
            Start-Process $potExe -WorkingDirectory $resolvedPotDir
        } else {
            Write-Host "`nSetup complete. You can launch PotPlayer anytime from your Start Menu or Desktop.`n" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "`n================================================================" -ForegroundColor Red
    Write-Host " SETUP INCOMPLETE: One or more components failed verification" -ForegroundColor Red
    if (-not $potExe) { Write-Host "  - PotPlayer executable was not found." -ForegroundColor Yellow }
    if (-not $isAviSynthReady) { Write-Host "  - AviSynth.dll is missing or has architecture mismatch." -ForegroundColor Yellow }
    if (-not $isMvToolsReady) { Write-Host "  - mvtools2.dll is missing or has architecture mismatch." -ForegroundColor Yellow }
    if (-not $isVcReady) { Write-Host "  - Microsoft Visual C++ 2015-2022 runtime is incomplete or missing." -ForegroundColor Yellow }
    Write-Host "================================================================`n" -ForegroundColor Red
}
