<#
.SYNOPSIS
    Generates an amplified 2x2 differential error divergence heatmap video comparing
    MVTools search algorithms (Hex2 and Diamond vs 7x7 Exhaustive reference).

.DESCRIPTION
    Decimates or takes an input video, interpolates with MBlockFps under:
      - 7x7 Exhaustive (search=3, searchparam=3)
      - Hex2 / UMH     (search=5, searchparam=2)
      - Diamond        (search=2, searchparam=1)
    Subtracts candidate outputs from the exhaustive baseline, amplifies localized
    differences with Levels(120, 1.0, 136, 0, 255), and exports a 2x2 comparison
    MP4 video to Benchmarks/BenchmarkResults/.
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$VideoPath = "",

    [Parameter(Mandatory = $false)]
    [int]$DurationSeconds = 5,

    [Parameter(Mandatory = $false)]
    [int]$BlockSize = 16,

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Continue"
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$ToolsDir  = Join-Path $ScriptDir "tools"

$FfmpegExe = Join-Path $ToolsDir "ffmpeg.exe"
if (-not (Test-Path $FfmpegExe)) {
    throw "ffmpeg.exe not found in '$ToolsDir'!"
}

# Ensure tools directory contains AviSynth.dll and mvtools2.dll
if (-not (Test-Path (Join-Path $ToolsDir "AviSynth.dll"))) {
    Copy-Item "C:\Program Files\DAUM\PotPlayer\AviSynth.dll" (Join-Path $ToolsDir "AviSynth.dll") -Force
}
if (-not (Test-Path (Join-Path $ToolsDir "mvtools2.dll"))) {
    Copy-Item (Join-Path $RepoRoot "Release\ARM64\mvtools2.dll") (Join-Path $ToolsDir "mvtools2.dll") -Force
}

$TempDir = Join-Path $ToolsDir "temp_divergence"
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
    # Step 1: Resolve or generate input 60 fps video
    $SourceAvi = Join-Path $TempDir "source_60fps.avi"
    if ([string]::IsNullOrWhiteSpace($VideoPath) -or -not (Test-Path $VideoPath)) {
        Write-Host "`n[1/3] Generating 1080p 60 fps synthetic motion test clip (${DurationSeconds} s)..." -ForegroundColor Cyan
        & $FfmpegExe -hide_banner -loglevel error -nostats -f lavfi -i "testsrc=size=1920x1080:rate=60" -t $DurationSeconds -c:v rawvideo -pix_fmt yuv420p $SourceAvi -y
    } else {
        Write-Host "`n[1/3] Preparing input video into uncompressed VFW AVI format (${DurationSeconds} s)..." -ForegroundColor Cyan
        & $FfmpegExe -hide_banner -loglevel error -nostats -i $VideoPath -t $DurationSeconds -c:v rawvideo -pix_fmt yuv420p $SourceAvi -y
    }

    $SourceAviEscaped = $SourceAvi.Replace('\', '/')
    $MvToolsDll = (Join-Path $ToolsDir "mvtools2.dll").Replace('\', '/')

    # Step 2: Build 2x2 comparison script
    # Downscales each quadrant to 960x540 so combined 2x2 output maintains exact native 1080p (1920x1080)
    $HeatmapAvs = Join-Path $TempDir "divergence_heatmap.avs"
    @"
LoadPlugin("$MvToolsDll")
src = AviSource("$SourceAviEscaped")
decimated = src.SelectEven()

super = decimated.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=1)

# 1. Exhaustive Reference (search=3, searchparam=3)
b_ex = MAnalyse(super, isb=true,  blksize=$BlockSize, blksizev=$BlockSize, search=3, searchparam=3, chroma=false, levels=1)
f_ex = MAnalyse(super, isb=false, blksize=$BlockSize, blksizev=$BlockSize, search=3, searchparam=3, chroma=false, levels=1)
clip_ex = MBlockFps(decimated, super, b_ex, f_ex, num=60, den=1, mode=0, blend=false)

# 2. Hex2 Candidate (search=5, searchparam=2)
b_s5 = MAnalyse(super, isb=true,  blksize=$BlockSize, blksizev=$BlockSize, search=5, searchparam=2, chroma=false, levels=1)
f_s5 = MAnalyse(super, isb=false, blksize=$BlockSize, blksizev=$BlockSize, search=5, searchparam=2, chroma=false, levels=1)
clip_s5 = MBlockFps(decimated, super, b_s5, f_s5, num=60, den=1, mode=0, blend=false)

# 3. Diamond Candidate (search=2, searchparam=1)
b_s2 = MAnalyse(super, isb=true,  blksize=$BlockSize, blksizev=$BlockSize, search=2, searchparam=1, chroma=false, levels=1)
f_s2 = MAnalyse(super, isb=false, blksize=$BlockSize, blksizev=$BlockSize, search=2, searchparam=1, chroma=false, levels=1)
clip_s2 = MBlockFps(decimated, super, b_s2, f_s2, num=60, den=1, mode=0, blend=false)

# 4. Difference Heatmaps (Gray 128 = Exact Match; Black/White = Divergence)
diff_s5 = Subtract(clip_ex, clip_s5).Levels(120, 1.0, 136, 0, 255)
diff_s2 = Subtract(clip_ex, clip_s2).Levels(120, 1.0, 136, 0, 255)

# 5. Format 2x2 Quadrant (960x540 each -> 1920x1080 total)
q_ex   = clip_ex.Spline36Resize(960, 540).Subtitle("1. Exhaustive (7x7 Baseline)", size=24, text_color=`$00FF00)
q_s5   = clip_s5.Spline36Resize(960, 540).Subtitle("2. Hex2 / UMH (search=5)", size=24, text_color=`$00FFFF)
q_d5   = diff_s5.Spline36Resize(960, 540).Subtitle("3. Hex2 Error Delta vs 7x7", size=24, text_color=`$FFFF00)
q_d2   = diff_s2.Spline36Resize(960, 540).Subtitle("4. Diamond Error Delta vs 7x7", size=24, text_color=`$FF8800)

top_row = StackHorizontal(q_ex, q_s5)
bot_row = StackHorizontal(q_d5, q_d2)
StackVertical(top_row, bot_row)
"@ | Set-Content -Path $HeatmapAvs -Encoding ASCII

    # Step 3: Determine output path and render to MP4
    $TargetOutputDir = if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir
    } else {
        Join-Path $ScriptDir "BenchmarkResults"
    }
    if (-not (Test-Path $TargetOutputDir)) {
        New-Item -ItemType Directory -Path $TargetOutputDir -Force | Out-Null
    }

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutMp4 = Join-Path $TargetOutputDir "divergence_heatmap_$Timestamp.mp4"

    Write-Host "`n[2/3] Rendering 2x2 Differential Divergence Heatmap Video..." -ForegroundColor Cyan
    $prevPwd = Get-Location
    Set-Location $ToolsDir
    try {
        & $FfmpegExe -hide_banner -nostats -loglevel error -i $HeatmapAvs -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p $OutMp4 -y

        # Compute Objective Mathematical Divergence Metrics directly from the 2x2 quadrants
        # Quadrant 1 (0:0): Exhaustive Reference
        # Quadrant 2 (960:0): Hex2 Candidate
        # Quadrant 4 (960:540 difference with 128 offset): or compare candidate clips directly
        $metricHex2 = & $FfmpegExe -hide_banner -nostats -i $HeatmapAvs -filter_complex "[0:v]crop=960:540:0:0[ex];[0:v]crop=960:540:960:0[cand];[cand][ex]psnr;[cand][ex]ssim" -f null - 2>&1
        $psnrH2Line = ($metricHex2 | Where-Object { $_ -match 'average:' }) | Select-Object -Last 1
        $ssimH2Line = ($metricHex2 | Where-Object { $_ -match 'All:' }) | Select-Object -Last 1

        $avgPsnrH2 = if ($psnrH2Line -match 'average:([0-9\.]+)') { [double]$Matches[1] } else { 0.0 }
        $minPsnrH2 = if ($psnrH2Line -match 'min:([0-9\.]+)') { [double]$Matches[1] } else { 0.0 }
        $avgSsimH2 = if ($ssimH2Line -match 'All:([0-9\.]+)') { [double]$Matches[1] } else { 0.0 }

        # To evaluate Diamond against Exhaustive:
        # Generate Diamond directly vs Exhaustive
        $diaAvs = Join-Path $TempDir "dia_eval.avs"
        @"
LoadPlugin("$MvToolsDll")
src = AviSource("$SourceAviEscaped")
decimated = src.SelectEven()
super = decimated.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=1)
b_ex = MAnalyse(super, isb=true,  blksize=$BlockSize, blksizev=$BlockSize, search=3, searchparam=3, chroma=false, levels=1)
f_ex = MAnalyse(super, isb=false, blksize=$BlockSize, blksizev=$BlockSize, search=3, searchparam=3, chroma=false, levels=1)
c_ex = MBlockFps(decimated, super, b_ex, f_ex, num=60, den=1, mode=0, blend=false).SelectOdd()

b_s2 = MAnalyse(super, isb=true,  blksize=$BlockSize, blksizev=$BlockSize, search=2, searchparam=1, chroma=false, levels=1)
f_s2 = MAnalyse(super, isb=false, blksize=$BlockSize, blksizev=$BlockSize, search=2, searchparam=1, chroma=false, levels=1)
c_s2 = MBlockFps(decimated, super, b_s2, f_s2, num=60, den=1, mode=0, blend=false).SelectOdd()

StackHorizontal(c_ex, c_s2)
"@ | Set-Content -Path $diaAvs -Encoding ASCII

        $metricDia = & $FfmpegExe -hide_banner -nostats -i $diaAvs -filter_complex "[0:v]crop=in_w/2:in_h:0:0[ex];[0:v]crop=in_w/2:in_h:in_w/2:0[s2];[s2][ex]psnr;[s2][ex]ssim" -f null - 2>&1
        $psnrD2Line = ($metricDia | Where-Object { $_ -match 'average:' }) | Select-Object -Last 1
        $ssimD2Line = ($metricDia | Where-Object { $_ -match 'All:' }) | Select-Object -Last 1

        $avgPsnrD2 = if ($psnrD2Line -match 'average:([0-9\.]+)') { [double]$Matches[1] } else { 0.0 }
        $minPsnrD2 = if ($psnrD2Line -match 'min:([0-9\.]+)') { [double]$Matches[1] } else { 0.0 }
        $avgSsimD2 = if ($ssimD2Line -match 'All:([0-9\.]+)') { [double]$Matches[1] } else { 0.0 }

    } finally {
        Set-Location $prevPwd
    }

    Write-Host "`n[3/3] OBJECTIVE DIVERGENCE METRICS (Vs 7x7 Exhaustive Baseline):" -ForegroundColor Green

    $divergenceMetrics = @(
        [PSCustomObject]@{
            "Candidate Search Mode" = "Hex2 / UMH (search=5, param=2)"
            "Convergence PSNR (dB)" = $avgPsnrH2.ToString("F3")
            "Worst-Case Frame PSNR" = $minPsnrH2.ToString("F3")
            "SSIM vs Exhaustive"    = $avgSsimH2.ToString("F6")
            "Visual Outlier Risk"   = if ($minPsnrH2 -ge 35.0) { "Low" } else { "High" }
        },
        [PSCustomObject]@{
            "Candidate Search Mode" = "Diamond (search=2, param=1)"
            "Convergence PSNR (dB)" = $avgPsnrD2.ToString("F3")
            "Worst-Case Frame PSNR" = $minPsnrD2.ToString("F3")
            "SSIM vs Exhaustive"    = $avgSsimD2.ToString("F6")
            "Visual Outlier Risk"   = if ($minPsnrD2 -ge 35.0) { "Low" } else { "High" }
        }
    )
    $divergenceMetrics | Format-Table -AutoSize

    Write-Host "Divergence Heatmap MP4 Video:" -ForegroundColor Green
    Write-Host "  -> Video File: $OutMp4" -ForegroundColor White
    Write-Host "  -> Layout:     Top-Left: Exhaustive Reference | Top-Right: Hex2" -ForegroundColor Gray
    Write-Host "                 Bottom-Left: Hex2 Error Delta  | Bottom-Right: Diamond Error Delta`n" -ForegroundColor Gray

} finally {
    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
