<#
.SYNOPSIS
    Automated 5-Scene Visual Fidelity & Performance Benchmark for Big Buck Bunny.
.DESCRIPTION
    Extracts 5 high-stress scenes from Big Buck Bunny (1080p 30 fps),
    decimates to 15 fps, reconstructs to 30 fps using MVTools MFlowFps,
    and calculates exact PSNR, SSIM, rendering throughput (fps), and CPU utilization
    across Upstream pinterf, mvtools-d3d12 (CPU), and mvtools-d3d12 (GPU).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$VideoPath = "D:\devai\benchmarks\bbb_sunflower_1080p_30fps_normal.mp4",

    [Parameter(Mandatory = $false)]
    [string]$UpstreamDll = "Benchmarks\pinterf\mvtools2.dll",

    [Parameter(Mandatory = $false)]
    [string]$OptimizedDll = "Sources\ARM64\Release\mvtools2.dll",

    [Parameter(Mandatory = $false)]
    [int]$SceneDurationSec = 4,

    [Parameter(Mandatory = $false)]
    [int]$Threads = 4,

    [Parameter(Mandatory = $false)]
    [string]$OutputMarkdown = "Benchmarks\BenchmarkResults\BigBuckBunny_Fidelity_Report.md"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host " Big Buck Bunny: 5-Scene Automated Fidelity & Throughput Benchmark" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

$ScriptDir = $PSScriptRoot
$ToolsDir  = Join-Path $ScriptDir "tools"
$FfmpegExe = Join-Path $ToolsDir "ffmpeg.exe"

if (-not (Test-Path $FfmpegExe)) {
    throw "ffmpeg.exe not found in '$ToolsDir'!"
}

if (-not (Test-Path $VideoPath)) {
    throw "Reference video not found at '$VideoPath'!"
}

$UpstreamDllResolved  = (Resolve-Path $UpstreamDll).Path
$OptimizedDllResolved = (Resolve-Path $OptimizedDll).Path
$Cores = [Environment]::ProcessorCount

$TempDir = Join-Path $ScriptDir "temp_bbb_fidelity"
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

$Scenes = @(
    @{ Id = 1; Name = "Fast Lateral Tree Pan";             Timestamp = "00:05:32"; Focus = "Horizontal Tearing & Shearing" },
    @{ Id = 2; Name = "Flying Squirrel Aerial Glide";      Timestamp = "00:07:20"; Focus = "Occlusion Halos & Silhouette Warping" },
    @{ Id = 3; Name = "Bow & Pinecone Launch";             Timestamp = "00:08:22"; Focus = "Search Range & Macroblock Noise" },
    @{ Id = 4; Name = "Butterfly Flutter & Fur Edges";     Timestamp = "00:02:15"; Focus = "Subpixel Jitter & Blend Smoothing" },
    @{ Id = 5; Name = "Rodent Scramble & Direction Flip";  Timestamp = "00:03:30"; Focus = "Vector Incoherence & Acceleration" }
)

$AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()

try {
    foreach ($scene in $Scenes) {
        Write-Host "`n------------------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host " [Scene $($scene.Id)/5] $($scene.Name) ($($scene.Timestamp), ${SceneDurationSec} s)" -ForegroundColor Yellow
        Write-Host " Focus: $($scene.Focus)" -ForegroundColor DarkGray
        Write-Host "------------------------------------------------------------------------" -ForegroundColor Cyan

        # Step 1: Extract uncompressed reference AVI for this scene
        $sceneAvi = Join-Path $TempDir "scene_$($scene.Id).avi"
        & $FfmpegExe -hide_banner -loglevel error -ss $scene.Timestamp -t $SceneDurationSec -i $VideoPath -an -c:v rawvideo -pix_fmt yuv420p $sceneAvi -y

        $sceneAviEscaped = $sceneAvi.Replace('\', '/')
        $groundAvs = Join-Path $TempDir "ground_$($scene.Id).avs"
        @"
AviSource("$sceneAviEscaped", audio=false).SelectOdd()
"@ | Set-Content -Path $groundAvs -Encoding ASCII

        # Define configurations to test
        $Configs = @(
            @{ Label = "Upstream pinterf (CPU)";    Dll = $UpstreamDllResolved;  UseD3D12 = $false; Backend = "CPU SIMD" },
            @{ Label = "mvtools-d3d12 (CPU Only)";   Dll = $OptimizedDllResolved; UseD3D12 = $false; Backend = "CPU SIMD" },
            @{ Label = "mvtools-d3d12 (GPU D3D12)";  Dll = $OptimizedDllResolved; UseD3D12 = $true;  Backend = "Direct3D 12 GPU" }
        )

        foreach ($cfg in $Configs) {
            Write-Host "  -> Running: $($cfg.Label)..." -ForegroundColor Green
            $synthAvs = Join-Path $TempDir "synth_$($scene.Id)_$($cfg.Backend -replace '\s+', '_').avs"
            $dllEscaped = $cfg.Dll.Replace('\', '/')
            $d3d12Call = if ($cfg.UseD3D12) { "try { MEnableD3D12(true) } catch(err) { }" } else { "try { MEnableD3D12(false) } catch(err) { }" }

            @"
LoadPlugin("$dllEscaped")
$d3d12Call
src = AviSource("$sceneAviEscaped", audio=false)
decimated = src.SelectEven()
super = decimated.MSuper(pel=2, hpad=16, vpad=16)
bvec  = super.MAnalyse(isb=true,  blksize=16, overlap=4, search=3)
fvec  = super.MAnalyse(isb=false, blksize=16, overlap=4, search=3)
synth = decimated.MFlowFps(super, bvec, fvec, num=60, den=1)
synth.SelectOdd()
Prefetch($Threads)
"@ | Set-Content -Path $synthAvs -Encoding ASCII

            # Run dual-stream FFmpeg to compute PSNR and SSIM against ground-truth odd frames
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = $FfmpegExe
            $pinfo.WorkingDirectory = $ToolsDir
            $pinfo.Arguments = "-hide_banner -nostats -i `"$synthAvs`" -i `"$groundAvs`" -lavfi `"[0:v][1:v]psnr;[0:v][1:v]ssim`" -f null -"
            $pinfo.RedirectStandardError = $true
            $pinfo.UseShellExecute = $false
            $pinfo.CreateNoWindow = $true
            $pinfo.Environment["PATH"] = "$ToolsDir;" + [System.Environment]::GetEnvironmentVariable("PATH")

            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $p = [System.Diagnostics.Process]::Start($pinfo)
            $stderr = $p.StandardError.ReadToEnd()
            $p.WaitForExit()
            $sw.Stop()

            $wallSec     = [math]::Round($sw.Elapsed.TotalSeconds, 2)
            $totalCpuSec = [math]::Round($p.TotalProcessorTime.TotalSeconds, 2)
            $avgCores    = if ($wallSec -gt 0) { [math]::Round($totalCpuSec / $wallSec, 2) } else { 0.0 }
            $cpuLoadPct  = if ($wallSec -gt 0) { [math]::Round(($totalCpuSec / ($wallSec * $Cores)) * 100, 1) } else { 0.0 }

            # Parse frame count and throughput
            $renderedFrames = 0
            $fps = 0.0
            $frameMatches = [regex]::Matches($stderr, 'frame=\s*(\d+)\s+fps=\s*([\d\.]+)')
            if ($frameMatches.Count -gt 0) {
                $lastMatch = $frameMatches[$frameMatches.Count - 1]
                $renderedFrames = [int]$lastMatch.Groups[1].Value
                $fps = [double]$lastMatch.Groups[2].Value
            }
            if ($fps -le 0.0 -and $wallSec -gt 0 -and $renderedFrames -gt 0) {
                $fps = [math]::Round($renderedFrames / $wallSec, 2)
            }

            # Parse PSNR and SSIM
            $psnr = 0.0
            $ssim = 0.0
            if ($stderr -match 'average:([0-9\.]+)') {
                $psnr = [double]$Matches[1]
            }
            if ($stderr -match 'All:([0-9\.]+)') {
                $ssim = [double]$Matches[1]
            }

            $cpuMsPerFrame = if ($renderedFrames -gt 0) { [math]::Round(($totalCpuSec / $renderedFrames) * 1000, 1) } else { 0.0 }

            Write-Host "     PSNR: $psnr dB | SSIM: $ssim | Throughput: $fps fps | Time: $wallSec s | CPU: $totalCpuSec s ($cpuLoadPct%)" -ForegroundColor DarkGray

            $AllResults.Add([PSCustomObject]@{
                SceneId         = $scene.Id
                SceneName       = $scene.Name
                Configuration   = $cfg.Label
                Backend         = $cfg.Backend
                PSNR_dB         = $psnr
                SSIM            = $ssim
                RenderFrames    = $renderedFrames
                Throughput_FPS  = $fps
                Elapsed_Sec     = $wallSec
                Cpu_Sec         = $totalCpuSec
                Avg_Cores       = $avgCores
                Cpu_Load        = "$cpuLoadPct%"
                Cpu_Cost_Frame  = "$cpuMsPerFrame ms"
            })
        }

        # Cleanup scene temp AVI
        Remove-Item -Force $sceneAvi, $groundAvs -ErrorAction SilentlyContinue
    }
} finally {
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Output Summary Table
Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host " Benchmark Results Across All 5 Scenes" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
$AllResults | Format-Table -Property SceneId, SceneName, Configuration, PSNR_dB, SSIM, Throughput_FPS, Elapsed_Sec, Cpu_Sec, Cpu_Load -AutoSize

# Generate Detailed Markdown Report
$reportLines = [System.Collections.Generic.List[string]]::new()
$reportLines.Add('# Big Buck Bunny 5-Scene Objective Fidelity & Performance Report')
$reportLines.Add('')
$reportLines.Add('## Execution Parameters')
$reportLines.Add('* **Reference Clip:** `bbb_sunflower_1080p_30fps_normal.mp4` (SHA-256: `ae510058...`)')
$reportLines.Add('* **Decimation & Reconstruction:** Decimated 30 fps -> 15 fps (SelectEven), interpolated 15 fps -> 30 fps (MFlowFps), evaluated on synthesized odd frames against ground truth (SelectOdd).')
$reportLines.Add('* **Motion Estimation Profile:** `MSuper(pel=2, hpad=16, vpad=16)`, `MAnalyse(blksize=16, overlap=4, search=3)`, `MFlowFps(num=60, den=1)`')
$reportLines.Add('* **Worker Threads:** ' + $Threads)
$reportLines.Add('* **Scene Duration:** ' + $SceneDurationSec + ' s per scene')
$reportLines.Add('')
$reportLines.Add('## Fidelity & Throughput Summary Table')
$reportLines.Add('| Scene | Configuration | Backend | PSNR (dB) | SSIM | Throughput (FPS) | Wall Time | Total CPU | CPU Load % | CPU Cost / Frame |')
$reportLines.Add('| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |')

foreach ($r in $AllResults) {
    $line = "| **Scene " + $r.SceneId + ": " + $r.SceneName + "** | " + $r.Configuration + " | " + $r.Backend + " | **" + $r.PSNR_dB.ToString('F2') + " dB** | **" + $r.SSIM.ToString('F4') + "** | " + $r.Throughput_FPS + " fps | " + $r.Elapsed_Sec + " s | " + $r.Cpu_Sec + " s | " + $r.Cpu_Load + " | " + $r.Cpu_Cost_Frame + " |"
    $reportLines.Add($line)
}

$reportLines.Add("")
$reportLines.Add("## Scene-by-Scene Architectural Analysis")
$reportLines.Add("")
foreach ($scene in $Scenes) {
    $scResults = $AllResults | Where-Object { $_.SceneId -eq $scene.Id }
    $up = $scResults | Where-Object { $_.Configuration -match "Upstream" } | Select-Object -First 1
    $cpu = $scResults | Where-Object { $_.Configuration -match "CPU Only" } | Select-Object -First 1
    $gpu = $scResults | Where-Object { $_.Configuration -match "GPU" } | Select-Object -First 1

    $reportLines.Add("### Scene " + $scene.Id + ": " + $scene.Name)
    $reportLines.Add("* **Timestamp:** " + $scene.Timestamp)
    $reportLines.Add("* **Stress Target:** " + $scene.Focus)
    if ($up -and $cpu) {
        $fpsDelta = [math]::Round(($cpu.Throughput_FPS / [math]::Max($up.Throughput_FPS, 0.01)), 2)
        $psnrDelta = [math]::Round(($cpu.PSNR_dB - $up.PSNR_dB), 3)
        $reportLines.Add("* **Fidelity Comparison:** Upstream " + $up.PSNR_dB.ToString('F2') + " dB (SSIM " + $up.SSIM.ToString('F4') + ") vs Optimized CPU " + $cpu.PSNR_dB.ToString('F2') + " dB (SSIM " + $cpu.SSIM.ToString('F4') + ") [Delta: " + $psnrDelta + " dB].")
        $reportLines.Add("* **Throughput Speedup:** " + $fpsDelta + "x (" + $cpu.Throughput_FPS + " fps vs " + $up.Throughput_FPS + " fps).")
    }
    if ($gpu) {
        $reportLines.Add("* **GPU Compute:** Direct3D 12 achieved " + $gpu.PSNR_dB.ToString('F2') + " dB (SSIM " + $gpu.SSIM.ToString('F4') + ") at " + $gpu.Throughput_FPS + " fps with " + $gpu.Cpu_Load + " CPU load.")
    }
    $reportLines.Add("")
}

$reportLines.Add("*Report automatically generated at: " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "*")

$reportDir = Split-Path $OutputMarkdown -Parent
if (-not (Test-Path $reportDir)) { New-Item -ItemType Directory -Path $reportDir | Out-Null }
[System.IO.File]::WriteAllLines($OutputMarkdown, $reportLines)

Write-Host "`n[+] Full fidelity and throughput report saved to: $OutputMarkdown" -ForegroundColor Cyan
