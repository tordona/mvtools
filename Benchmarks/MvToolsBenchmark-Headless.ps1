<#
.SYNOPSIS
    Automated Headless Comparative Benchmark Harness for MVTools2.
.DESCRIPTION
    Runs an unconstrained throughput comparison between a Baseline MVTools2 DLL
    and an Optimized MVTools2 DLL using synthetic 1080p 24 fps -> 60 fps interpolation.
    Outputs a structured markdown and console table comparing rendering throughput (fps),
    total elapsed time, and speedup multipliers across both CPU and Direct3D 12 GPU paths.
.PARAMETER BaselineDll
    Path to the reference/baseline mvtools2.dll.
.PARAMETER OptimizedDll
    Path to the newly optimized mvtools2.dll.
.PARAMETER FrameCount
    Number of frames to render per test run (default: 100 frames).
.PARAMETER Threads
    Number of AviSynth prefetch worker threads (default: 4).
.PARAMETER OutputMarkdown
    Path to write the comparison Markdown report.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$BaselineDll = "Benchmarks\tools\mvtools2.dll",

    [Parameter(Mandatory = $false)]
    [string]$OptimizedDll = "Sources\ARM64\Release\mvtools2.dll",

    [Parameter(Mandatory = $false)]
    [int]$FrameCount = 100,

    [Parameter(Mandatory = $false)]
    [int]$Threads = 4,

    [Parameter(Mandatory = $false)]
    [string]$OutputMarkdown = "Benchmarks\BenchmarkResults\Headless_Throughput_Comparison.md"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host " MVTools2 Headless Synthetic Benchmark Harness" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

# 1. Resolve FFmpeg executable (prefer tools\ffmpeg.exe with native ARM64 AviSynth+ support)
$toolsDir = (Resolve-Path (Join-Path $PSScriptRoot "tools")).Path
$localFfmpeg = Join-Path $toolsDir "ffmpeg.exe"
if (Test-Path $localFfmpeg) {
    $ffmpegExe = $localFfmpeg
} else {
    $systemFfmpeg = Get-Command "ffmpeg.exe" -ErrorAction SilentlyContinue
    if ($systemFfmpeg) {
        $ffmpegExe = $systemFfmpeg.Source
    }
}

if (-not $ffmpegExe) {
    throw "ffmpeg.exe was not found in Benchmarks\tools\ or PATH. Please install FFmpeg with AviSynth support."
}

# Resolve DLL defaults if needed
if (-not (Test-Path $BaselineDll)) {
    $altBaseline = "Benchmarks\Baseline_DLL\mvtools2.dll"
    if (Test-Path $altBaseline) {
        $BaselineDll = $altBaseline
    }
}

if (-not (Test-Path $OptimizedDll)) {
    $altOpt = "Sources\x64\Release\mvtools2.dll"
    if (Test-Path $altOpt) {
        $OptimizedDll = $altOpt
    }
}

Write-Host "[*] FFmpeg binary: $ffmpegExe" -ForegroundColor Gray
Write-Host "[*] Baseline DLL:  $BaselineDll (Exists: $(Test-Path $BaselineDll))" -ForegroundColor Gray
Write-Host "[*] Optimized DLL: $OptimizedDll (Exists: $(Test-Path $OptimizedDll))" -ForegroundColor Gray

$tempDir = Join-Path $PSScriptRoot "temp_bench"
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
}

function Run-HeadlessRun {
    param(
        [string]$Label,
        [string]$DllPath,
        [bool]$UseD3D12 = $false
    )

    $resolvedDll = (Resolve-Path $DllPath).Path
    $sanitizedLabel = $Label -replace '[^a-zA-Z0-9_]', '_'
    $avsFile = Join-Path $tempDir "$sanitizedLabel.avs"

    $d3d12Line = if ($UseD3D12) { "try { MEnableD3D12(true) } catch(err) { }" } else { "try { MEnableD3D12(false) } catch(err) { }" }

    $avsContent = @"
LoadPlugin("$($resolvedDll -replace '\\', '/')")
$d3d12Line
ColorBarsHD(width=1920, height=1080).AssumeFPS(24, 1).ConvertToYV12().Trim(0, $($FrameCount - 1))
super = MSuper(pel=2, hpad=16, vpad=16)
bvec  = MAnalyse(super, isb=true,  blksize=16, overlap=4, search=3)
fvec  = MAnalyse(super, isb=false, blksize=16, overlap=4, search=3)
MFlowFps(super, bvec, fvec, num=60, den=1)
Prefetch($Threads)
"@

    Set-Content -Path $avsFile -Value $avsContent -Encoding Ascii

    $backendDesc = if ($UseD3D12) { "Direct3D 12 GPU" } else { "CPU SIMD" }
    Write-Host "`n[*] Running benchmark: $Label [$backendDesc]" -ForegroundColor Yellow
    Write-Host "    DLL: $resolvedDll" -ForegroundColor DarkGray
    Write-Host "    Frames: $FrameCount | Threads: $Threads | Resolution: 1080p 24 fps -> 60 fps"

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $ffmpegExe
    $processInfo.WorkingDirectory = $toolsDir
    $processInfo.Arguments = "-hide_banner -loglevel info -i `"$avsFile`" -f null -max_muxing_queue_size 1024 -"
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.Environment["PATH"] = "$toolsDir;" + [System.Environment]::GetEnvironmentVariable("PATH")

    $p = [System.Diagnostics.Process]::Start($processInfo)
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    $sw.Stop()

    $elapsedSec = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    $fps = 0.0
    $renderedFrames = 0

    # Find the LAST reported frame count and fps in FFmpeg's progress output
    $matches = [regex]::Matches($stderr, 'frame=\s*(\d+)\s+fps=\s*([\d\.]+)')
    if ($matches.Count -gt 0) {
        $lastMatch = $matches[$matches.Count - 1]
        $renderedFrames = [int]$lastMatch.Groups[1].Value
        $fps = [double]$lastMatch.Groups[2].Value
    }

    # Fallback to high-precision wall-clock calculation if FFmpeg reports 0.0 fps
    if ($fps -le 0.0 -and $elapsedSec -gt 0.0 -and $renderedFrames -gt 0) {
        $fps = [math]::Round($renderedFrames / $elapsedSec, 2)
    }

    $totalCpuSec = [math]::Round($p.TotalProcessorTime.TotalSeconds, 2)
    $cores = [Environment]::ProcessorCount
    $avgCores = if ($elapsedSec -gt 0) { [math]::Round($totalCpuSec / $elapsedSec, 2) } else { 0.0 }
    $cpuLoadPct = if ($elapsedSec -gt 0) { [math]::Round(($totalCpuSec / ($elapsedSec * $cores)) * 100, 1) } else { 0.0 }
    $cpuMsPerFrame = if ($renderedFrames -gt 0) { [math]::Round(($totalCpuSec / $renderedFrames) * 1000, 1) } else { 0.0 }

    Write-Host "    Rendered $renderedFrames frames in $elapsedSec s (Throughput: $fps fps | CPU Time: $totalCpuSec s | Avg Cores: $avgCores | Load: $cpuLoadPct%)" -ForegroundColor Green

    return [PSCustomObject]@{
        Label          = $Label
        Backend        = $backendDesc
        DllPath        = $resolvedDll
        RenderedFrames = $renderedFrames
        ElapsedSec     = $elapsedSec
        RenderFps      = $fps
        CpuSec         = $totalCpuSec
        AvgCores       = $avgCores
        CpuLoad        = "$cpuLoadPct%"
        CpuMsPerFrame  = "$cpuMsPerFrame ms"
    }
}

$results = @()

# 1. Baseline CPU
if (Test-Path $BaselineDll) {
    $results += Run-HeadlessRun -Label "Baseline (CPU)" -DllPath $BaselineDll -UseD3D12 $false
}

# 2. Optimized CPU
if (Test-Path $OptimizedDll) {
    $results += Run-HeadlessRun -Label "Optimized (CPU)" -DllPath $OptimizedDll -UseD3D12 $false
}

# 3. Baseline GPU (D3D12)
if (Test-Path $BaselineDll) {
    $results += Run-HeadlessRun -Label "Baseline (GPU D3D12)" -DllPath $BaselineDll -UseD3D12 $true
}

# 4. Optimized GPU (D3D12)
if (Test-Path $OptimizedDll) {
    $results += Run-HeadlessRun -Label "Optimized (GPU D3D12)" -DllPath $OptimizedDll -UseD3D12 $true
}

# Summary Table Output
Write-Host "`n========================================================================" -ForegroundColor Cyan
Write-Host " Benchmark Results Summary" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

$results | Format-Table -Property Label, Backend, RenderedFrames, ElapsedSec, RenderFps, CpuSec, AvgCores, CpuLoad, CpuMsPerFrame -AutoSize

# Generate Structured Markdown Report
if ($results.Count -ge 2) {
    $baseCpu = $results | Where-Object { $_.Label -eq "Baseline (CPU)" } | Select-Object -First 1
    $baseFps = if ($baseCpu -and $baseCpu.RenderFps -gt 0) { $baseCpu.RenderFps } else { $results[0].RenderFps }

    $reportLines = [System.Collections.Generic.List[string]]::new()
    $reportLines.Add("# MVTools2 Headless Benchmark Report")
    $reportLines.Add("")
    $reportLines.Add("## Execution Parameters")
    $reportLines.Add("* **Resolution & Transition:** 1080p 24 fps -> 60 fps")
    $reportLines.Add("* **Interpolation Filter:** MFlowFps (BlockSize=16, 4 px Overlap, Pel=2, Search=3)")
    $reportLines.Add("* **Worker Threads:** $Threads")
    $reportLines.Add("* **Input Source Frames:** $FrameCount")
    $reportLines.Add("")
    $reportLines.Add("## Throughput & CPU Utilization Comparison")
    $reportLines.Add("| Configuration | Compute Backend | Rendered Frames | Elapsed Time | Throughput (FPS) | Relative Speedup | Total CPU Time | Avg Active Cores | CPU Load % | CPU Cost / Frame |")
    $reportLines.Add("| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |")

    foreach ($res in $results) {
        $speedup = if ($baseFps -gt 0) { [math]::Round($res.RenderFps / $baseFps, 2) } else { 1.0 }
        $reportLines.Add("| $($res.Label) | $($res.Backend) | $($res.RenderedFrames) | $($res.ElapsedSec) s | $($res.RenderFps) fps | **${speedup}x** | $($res.CpuSec) s | $($res.AvgCores) | $($res.CpuLoad) | $($res.CpuMsPerFrame) |")
    }

    $reportLines.Add("")
    $reportLines.Add("*Report generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')*")

    $reportDir = Split-Path $OutputMarkdown -Parent
    if (-not (Test-Path $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir | Out-Null
    }
    [System.IO.File]::WriteAllLines($OutputMarkdown, $reportLines)
    Write-Host "`n[+] Markdown comparison saved to: $OutputMarkdown" -ForegroundColor Cyan
}

# Cleanup
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
