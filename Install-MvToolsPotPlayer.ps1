# ==============================================================================
# MVTools2 + Daum PotPlayer 60 fps Automated Setup & Profile Deployment
# Architecture: Windows 11 on ARM64 (Qualcomm Snapdragon) & x86-64 (AMD/Intel)
# Repository: https://github.com/tordona/mvtools (branch: mvtools_d3d12)
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
    5. Acquires native MVTools2 binaries (mvtools2.dll, mvtools2_d3d12.dll on ARM64) and deploys to PotPlayer.
    6. Deploys architecture-filtered AviSynth profiles:
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
    Git branch to acquire profiles and releases from. Default: 'mvtools_d3d12'.

.PARAMETER ForceProfile
    Optional override to specify an exact .avs profile name to activate (e.g. 'Snapdragon-X-Plus-MaxQuality.avs').

.PARAMETER Launch
    Automatically launches PotPlayer after setup completes.
#>

[CmdletBinding()]
param(
    [string]$PotPlayerDir = "",
    [switch]$AutoInstall,
    [string]$MvToolsRepo = "",
    [string]$ProfileBranch = "mvtools_d3d12",
    [string]$ForceProfile = "",
    [switch]$Launch
)

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

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ScriptDir)) { $ScriptDir = (Get-Location).Path }
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
                $branchTarget = if (-not [string]::IsNullOrWhiteSpace($ProfileBranch)) { $ProfileBranch } else { "mvtools_d3d12" }
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
            if ($ProfileBranch -and $ProfileBranch -ne "mvtools_d3d12") { $argList += @("-ProfileBranch", "`"$ProfileBranch`"") }
        } else {
            $repoTarget = if (-not [string]::IsNullOrWhiteSpace($MvToolsRepo)) { $MvToolsRepo } else { "tordona/mvtools" }
            $branchTarget = if (-not [string]::IsNullOrWhiteSpace($ProfileBranch)) { $ProfileBranch } else { "mvtools_d3d12" }
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

    $archLabel = $targetArch.ToUpper()
    if (-not (Confirm-DownloadPermission -ItemName "PotPlayer $archLabel Official Installer" -SourceUrl $Url -TargetDir $TempInstaller -SizeDesc "~35 MB")) {
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
    $InstallerArgs = @("/S")
    if (-not [string]::IsNullOrWhiteSpace($TargetDir)) {
        $InstallerArgs += "/D=$TargetDir"
    }

    try {
        $StartParams = @{
            FilePath     = $TempInstaller
            ArgumentList = $InstallerArgs
            PassThru     = $true
        }
        $Process = Start-Process @StartParams
        $Process.WaitForExit()

        if (Test-Path $TempInstaller) { Remove-Item $TempInstaller -Force -ErrorAction SilentlyContinue }

        # Verify installation target
        $verifyLocations = if (-not [string]::IsNullOrWhiteSpace($TargetDir)) { @($TargetDir) } else {
            @(
                (Join-Path ${env:ProgramFiles} "DAUM\PotPlayer"),
                (Join-Path ${env:ProgramW6432} "DAUM\PotPlayer"),
                (Join-Path ${env:ProgramFiles(x86)} "DAUM\PotPlayer")
            )
        }

        foreach ($loc in $verifyLocations) {
            $potExe = Join-Path $loc "PotPlayer64.exe"
            if (Test-Path $potExe) {
                Write-Host "  -> PotPlayer verified at: $loc" -ForegroundColor Green
                return $loc
            }
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
        $gpuDll = $archPool | Where-Object { $_.Name -ieq "mvtools2_d3d12.dll" } | Select-Object -First 1
        $depanDll = $archPool | Where-Object { $_.Name -ieq "DePan.dll" } | Select-Object -First 1
        $depanEstDll = $archPool | Where-Object { $_.Name -ieq "DePanEstimate.dll" } | Select-Object -First 1

        if (-not $cpuDll) {
            throw "Could not locate 'mvtools2.dll' inside the downloaded release archive!"
        }

        $deployDir = if (-not [string]::IsNullOrWhiteSpace($TargetDir)) { $TargetDir } else { $ScriptDir }
        if (-not (Test-Path $deployDir)) {
            New-Item -ItemType Directory -Path $deployDir -Force | Out-Null
        }

        try {
            Copy-Item -Path $cpuDll.FullName -Destination (Join-Path $deployDir "mvtools2.dll") -Force -ErrorAction Stop
            Write-Host ("  -> Deployed mvtools2.dll ({0} CPU SIMD) to: {1}" -f $archLabel, $deployDir) -ForegroundColor Green

            if ($gpuDll) {
                Copy-Item -Path $gpuDll.FullName -Destination (Join-Path $deployDir "mvtools2_d3d12.dll") -Force -ErrorAction Stop
                Write-Host "  -> Deployed mvtools2_d3d12.dll (Direct3D 12 GPU) to: $deployDir" -ForegroundColor Green
            } else {
                Write-Host "  -> mvtools2_d3d12.dll not present in archive (CPU-only build package)." -ForegroundColor Gray
            }

            if ($depanDll) {
                Copy-Item -Path $depanDll.FullName -Destination (Join-Path $deployDir "DePan.dll") -Force -ErrorAction Stop
                Write-Host "  -> Deployed DePan.dll to: $deployDir" -ForegroundColor Green
            }
            if ($depanEstDll) {
                Copy-Item -Path $depanEstDll.FullName -Destination (Join-Path $deployDir "DePanEstimate.dll") -Force -ErrorAction Stop
                Write-Host "  -> Deployed DePanEstimate.dll to: $deployDir" -ForegroundColor Green
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
# HELPER: Deploy Architecture-Filtered AviSynth Profiles
# ---------------------------------------------------------
function Install-ArchitectureFilteredProfiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPotPlayerDir,
        [string]$TargetArch = "arm64",
        [string]$RepoRoot = ".",
        [string]$RepoSlug = "tordona/mvtools",
        [string]$Branch = "mvtools_d3d12"
    )

    $potAvsDir = Join-Path $TargetPotPlayerDir "AviSynth"
    if (-not (Test-Path $potAvsDir)) {
        New-Item -ItemType Directory -Path $potAvsDir -Force | Out-Null
    }

    $isArm64 = ($TargetArch -eq "arm64")
    Write-Host "`n[PROFILES] Deploying $TargetArch AviSynth profiles..." -ForegroundColor Cyan

    $localAvsDir = Join-Path $RepoRoot "AviSynth"
    $deployedCount = 0

    if (Test-Path $localAvsDir) {
        $localProfiles = Get-ChildItem -Path $localAvsDir -Filter "*.avs"
        foreach ($p in $localProfiles) {
            $isSnapdragon = ($p.Name -like "Snapdragon*")
            # Filter rule: ARM64 gets ONLY Snapdragon; x86-64 gets strictly non-Snapdragon
            if (($isArm64 -and $isSnapdragon) -or (-not $isArm64 -and -not $isSnapdragon)) {
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
                "Snapdragon-X-Plus-Eco.avs", "Snapdragon-X-Plus-Balanced.avs", "Snapdragon-X-Plus-MaxQuality.avs",
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
    $potMvToolsD3d12 = "$cleanPotDir/mvtools2_d3d12.dll"

    Get-ChildItem -Path $potAvsDir -Filter "*.avs" | ForEach-Object {
        try {
            $avsContent = [System.IO.File]::ReadAllText($_.FullName)
            $avsContent = $avsContent -replace '(?i)"mvtools2_d3d12\.dll"', "`"$potMvToolsD3d12`""
            $avsContent = $avsContent -replace '(?i)"mvtools2\.dll"', "`"$potMvTools`""
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

    # Match rules for Snapdragon ARM64
    if ($isArm64) {
        if ($combined -match '(?i)X1P|Snapdragon.*X|Oryon') {
            $cand = Join-Path $potAvsDir "Snapdragon-X-Plus-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Snapdragon-X-Plus-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)8cx.*Gen.*3|SQ3') {
            $cand = Join-Path $potAvsDir "Snapdragon-8cxGen3-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Snapdragon-8cxGen3-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)8cx.*Gen.*2|SQ2') {
            $cand = Join-Path $potAvsDir "Snapdragon-8cxGen2-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Snapdragon-8cxGen2-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)8cx|SQ1') {
            $cand = Join-Path $potAvsDir "Snapdragon-8cxGen1-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Snapdragon-8cxGen1-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)850|SD850') {
            $cand = Join-Path $potAvsDir "Snapdragon-850-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Snapdragon-850-Balanced"; IsGeneric = $false } }
        }
        if ($combined -match '(?i)7c') {
            $cand = Join-Path $potAvsDir "Snapdragon-7cGen2-Balanced.avs"
            if (Test-Path $cand) { return @{ Profile = $cand; Name = "Snapdragon-7cGen2-Balanced"; IsGeneric = $false } }
        }

        # Fallback for unrecognized ARM64 hardware
        $fallback = Join-Path $potAvsDir "Snapdragon-X-Plus-Balanced.avs"
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
    $potMvToolsD3d12 = "$cleanPotDir/mvtools2_d3d12.dll"

    $rawAvs = Get-Content -Path $ProfilePath -Raw
    $resolvedAvs = $rawAvs -replace '(?i)"mvtools2_d3d12\.dll"', "`"$potMvToolsD3d12`""
    $resolvedAvs = $resolvedAvs -replace '(?i)"mvtools2\.dll"', "`"$potMvTools`""

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
                "[Settings]`r`nAutoIni=0`r`n[Positions]`r`nMainWindowState=128`r`n" | Set-Content -Path $iniPath -Encoding Unicode
            } catch {}
        }

        if (Test-Path $iniPath) {
            try {
                $lines = Get-Content -Path $iniPath -Encoding Unicode
                $newLines = [System.Collections.Generic.List[string]]::new()
                $inSettings = $false
                $keysToSet = [ordered]@{
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
    $pluginRule = if ($isArm64) {
        '2. Engine & Plugin Hook: MUST support dual-engine ARM64 via ``plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"`` and ``LoadPlugin(plugin_file)``. Hook video via ``src = potplayer_source()``.'
    } else {
        '2. Engine & Plugin Hook: MUST run 100% native CPU SIMD via ``LoadPlugin("mvtools2.dll")`` (DO NOT reference USE_GPU or mvtools2_d3d12.dll on x64). Hook video via ``src = potplayer_source()``.'
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
- Specification (Direct Raw Markdown for AI ingestion): https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/docs/guides/AIAgentProfileGuide.md
- Web Mirror (GitHub UI View): https://github.com/tordona/mvtools/blob/mvtools_d3d12/docs/guides/AIAgentProfileGuide.md

Mandatory Architecture & AviSynth+ 3.x Rules:
1. Multi-Threading: MUST declare ``SetMemoryMax()`` and ``SetFilterMTMode("DEFAULT_MT_MODE", 2)`` at the top BEFORE calling ``potplayer_source()`` (NEVER use legacy ``SetMTMode``).
$pluginRule
3. Function Naming: MUST spell MVTools functions as ``MAnalyse`` (with 's') and specify ``isb=true`` on the backward vector search.
4. Single-Level Geometry: MUST use ``levels=1`` in both MSuper and MAnalyse (``pel=1, hpad=0, vpad=0, sharp=0`` for Eco/Balanced; ``sharp=1`` for MaxQuality).
5. Vector Computation: MUST use ``chroma=false`` in MAnalyse (luma-only search cuts vector compute in half).
6. Frame Synthesis: MUST use ``MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=0, blend=<Blend>)`` with ``blend=false`` for Eco/Balanced, and ``blend=true`` for MaxQuality (DO NOT use MFlowFps for real-time 1080p60).
7. Core Pinning: MUST pin ``threads`` to physical performance cores (``threads <= physical_cores``) and end with ``Prefetch(threads, 4 for Eco, 6 for Balanced/MaxQuality)``.

Please generate the complete 3-tier profile set following these exact rules:
- Profile 1 (Eco): Coarse 32x32 blocks (``blksize=32, blksizev=32, search=2, searchparam=1, blend=false``), lowest CPU wattage.
- Profile 2 (Balanced): Crisp 16x16 blocks (``blksize=16, blksizev=16, search=2, searchparam=2, blend=false``), daily driver.
- Profile 3 (MaxQuality): Overlapping 16x16 blocks (``blksize=16, blksizev=16, overlap=4, overlapv=4, search=2, searchparam=2, sharp=1, blend=true``), maximum edge fidelity.
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
$resolvedPotDir = $PotPlayerDir
if (-not $resolvedPotDir -or -not (Test-Path (Join-Path $resolvedPotDir "PotPlayer64.exe"))) {
    $searchLocations = @(
        (Join-Path ${env:ProgramFiles} "DAUM\PotPlayer"),
        (Join-Path ${env:ProgramW6432} "DAUM\PotPlayer"),
        (Join-Path ${env:ProgramFiles(x86)} "DAUM\PotPlayer"),
        "C:\Tools\PotPlayer",
        (Join-Path $ScriptDir "PotPlayer")
    )
    foreach ($cand in $searchLocations) {
        if (Test-Path (Join-Path $cand "PotPlayer64.exe")) {
            $resolvedPotDir = (Resolve-Path $cand).Path
            break
        }
    }
}

if (-not $resolvedPotDir -or -not (Test-Path (Join-Path $resolvedPotDir "PotPlayer64.exe"))) {
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

# Close any running PotPlayer instances to prevent DLL lock / file in use errors
$runningPot = Get-Process -Name "PotPlayer64", "PotPlayerMini64", "PotPlayer", "PotPlayerMini" -ErrorAction SilentlyContinue
if ($runningPot) {
    Write-Host "`n[PROCESS GUARD] Daum PotPlayer is currently running." -ForegroundColor Yellow
    Write-Host "  Closing PotPlayer to allow binary updates and configuration injection..." -ForegroundColor Cyan
    $runningPot | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

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

# Step 5: Ensure Native MVTools2 Binaries
Write-Host "`n[5/6] Verifying MVTools2 Binaries..." -ForegroundColor Cyan
$potMvToolsDll = Join-Path $resolvedPotDir "mvtools2.dll"
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
                    Start-Process "https://tordona.github.io/mvtools/#/guides/AIAgentProfileGuide"
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
        Write-Host "  -> AI Agent Guide: https://tordona.github.io/mvtools/#/guides/AIAgentProfileGuide" -ForegroundColor Gray
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
$allStagesSuccessful = ($potExe -and $isAviSynthReady -and $isMvToolsReady -and $isVcReady)

if ($allStagesSuccessful) {
    Write-Host "`n================================================================" -ForegroundColor Green
    Write-Host " SETUP COMPLETE! 60 fps Motion Interpolation Ready" -ForegroundColor Green
    Write-Host " PotPlayer Executable: $potExe" -ForegroundColor Gray
    Write-Host " Active Profile:       $($selectedMatch.Name)" -ForegroundColor Gray
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
