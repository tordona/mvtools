<#
.SYNOPSIS
    Generates a side-by-side motion vector field visualization video using MShow,
    comparing 7x7 Exhaustive search (search=3) vs Diamond search (search=2).

.DESCRIPTION
    Renders motion vector arrows directly onto video frames to visually verify
    spatial vector coherence, boundary stability, and lack of spurious vector static.
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

$TempDir = Join-Path $ToolsDir "temp_mshow"
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
    # Step 1: Resolve or generate input 60 fps video
    $SourceAvi = Join-Path $TempDir "source_60fps.avi"
    if ([string]::IsNullOrWhiteSpace($VideoPath) -or -not (Test-Path $VideoPath)) {
        Write-Host "`n[1/3] Generating 1080p 60 fps animated motion test clip (${DurationSeconds} s)..." -ForegroundColor Cyan
        & $FfmpegExe -hide_banner -loglevel error -nostats -f lavfi -i "testsrc2=size=1920x1080:rate=60" -t $DurationSeconds -c:v rawvideo -pix_fmt yuv420p $SourceAvi -y
    } else {
        Write-Host "`n[1/3] Preparing input video into uncompressed VFW AVI format (${DurationSeconds} s)..." -ForegroundColor Cyan
        & $FfmpegExe -hide_banner -loglevel error -nostats -i $VideoPath -t $DurationSeconds -c:v rawvideo -pix_fmt yuv420p $SourceAvi -y
    }

    $SourceAviEscaped = $SourceAvi.Replace('\', '/')
    $MvToolsDll = (Join-Path $ToolsDir "mvtools2.dll").Replace('\', '/')

    # Step 2: Build side-by-side MShow script
    # scale=2 magnifies vector arrows for visual clarity
    # tol=20000 ensures valid motion vectors are not filtered out (tol=0 suppresses vectors)
    $MShowAvs = Join-Path $TempDir "vector_fields.avs"
    @"
LoadPlugin("$MvToolsDll")
src = AviSource("$SourceAviEscaped")
decimated = src.SelectEven()
super = decimated.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=1)

# 1. 7x7 Exhaustive Motion Vectors
f_ex = MAnalyse(super, isb=false, blksize=$BlockSize, blksizev=$BlockSize, search=3, searchparam=3, chroma=false, levels=1)
v_ex = MShow(super, f_ex, scale=2, sil=0, tol=20000, showsad=false).Spline36Resize(960, 540).Subtitle("7x7 Exhaustive (search=3, param=3)", size=24, text_color=`$00FF00)

# 2. Diamond Motion Vectors
f_s2 = MAnalyse(super, isb=false, blksize=$BlockSize, blksizev=$BlockSize, search=2, searchparam=2, chroma=false, levels=1)
v_s2 = MShow(super, f_s2, scale=2, sil=0, tol=20000, showsad=false).Spline36Resize(960, 540).Subtitle("Diamond (search=2, param=2)", size=24, text_color=`$00FFFF)

StackHorizontal(v_ex, v_s2)
"@ | Set-Content -Path $MShowAvs -Encoding ASCII

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
    $OutMp4 = Join-Path $TargetOutputDir "vector_fields_$Timestamp.mp4"

    Write-Host "`n[2/3] Rendering Side-by-Side Vector Field Video (MShow)..." -ForegroundColor Cyan
    $prevPwd = Get-Location
    Set-Location $ToolsDir
    try {
        & $FfmpegExe -hide_banner -nostats -loglevel error -i $MShowAvs -c:v libx264 -preset fast -crf 18 -pix_fmt yuv420p $OutMp4 -y
    } finally {
        Set-Location $prevPwd
    }

    Write-Host "`n[3/3] Vector Field Video Rendered Successfully!" -ForegroundColor Green
    Write-Host "  -> Video File: $OutMp4" -ForegroundColor White
    Write-Host "  -> Layout:     Left: 7x7 Exhaustive Vectors | Right: Diamond Vectors`n" -ForegroundColor Gray

} finally {
    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
