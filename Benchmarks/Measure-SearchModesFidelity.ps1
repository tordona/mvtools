<#
.SYNOPSIS
    Automated frame-accurate objective fidelity test (PSNR & SSIM) comparing
    MVTools motion search modes (Exhaustive vs Hex2 vs Diamond).

.DESCRIPTION
    Decimates a 60 fps progressive input video by 2 (to 30 fps), reconstructs
    missing intermediate frames to 60 fps using MVTools MBlockFps with each search mode,
    and calculates exact PSNR and SSIM against the ground-truth original frames
    via FFmpeg dual-input filtering (-lavfi "[0:v][1:v]psnr;[0:v][1:v]ssim").
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$VideoPath = "",

    [Parameter(Mandatory = $false)]
    [int]$DurationSeconds = 5,

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

$TempDir = Join-Path $ToolsDir "temp_fidelity"
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

try {
    # Step 1: Resolve or generate input 60 fps video
    $SourceAvi = Join-Path $TempDir "source_60fps.avi"
    if ([string]::IsNullOrWhiteSpace($VideoPath) -or -not (Test-Path $VideoPath)) {
        Write-Host "`n[1/4] Generating standard 1080p 60 fps synthetic motion test clip (${DurationSeconds} s)..." -ForegroundColor Cyan
        & $FfmpegExe -hide_banner -loglevel error -nostats -f lavfi -i "testsrc=size=1920x1080:rate=60" -t $DurationSeconds -c:v rawvideo -pix_fmt yuv420p $SourceAvi -y
    } else {
        Write-Host "`n[1/4] Preparing input video into uncompressed VFW AVI format (${DurationSeconds} s)..." -ForegroundColor Cyan
        & $FfmpegExe -hide_banner -loglevel error -nostats -i $VideoPath -t $DurationSeconds -c:v rawvideo -pix_fmt yuv420p $SourceAvi -y
    }

    $SourceAviEscaped = $SourceAvi.Replace('\', '/')

    # Step 2: Write Ground-Truth odd frames extractor script
    $GroundTruthAvs = Join-Path $TempDir "ground_truth.avs"
    @"
AviSource("$SourceAviEscaped").SelectOdd()
"@ | Set-Content -Path $GroundTruthAvs -Encoding ASCII

    $MvToolsDll = (Join-Path $ToolsDir "mvtools2.dll").Replace('\', '/')

    # Step 3: Function to benchmark an arbitrary search mode
    function Measure-SearchMode {
        param(
            [string]$ModeName,
            [int]$SearchType,
            [int]$SearchParam
        )

        Write-Host "  -> Evaluating $ModeName (search=$SearchType, searchparam=$SearchParam)..." -ForegroundColor Yellow

        $InterpAvs = Join-Path $TempDir "interp_${SearchType}_${SearchParam}.avs"
        $SourceAviEscaped = $SourceAvi.Replace('\', '/')
        @"
LoadPlugin("$MvToolsDll")
src = AviSource("$SourceAviEscaped")
decimated = src.SelectEven()
super = decimated.MSuper(levels=1, pel=1, hpad=0, vpad=0, sharp=1)
bvec  = MAnalyse(super, isb=true,  blksize=16, blksizev=16, search=$SearchType, searchparam=$SearchParam, chroma=false, levels=1)
fvec  = MAnalyse(super, isb=false, blksize=16, blksizev=16, search=$SearchType, searchparam=$SearchParam, chroma=false, levels=1)
synth = MBlockFps(decimated, super, bvec, fvec, num=60, den=1, mode=0, blend=false)
synth.SelectOdd()
"@ | Set-Content -Path $InterpAvs -Encoding ASCII

        # Run dual-stream FFmpeg in tools directory so AviSynth.dll resolves locally
        $prevPwd = Get-Location
        Set-Location $ToolsDir
        try {
            $output = & $FfmpegExe -hide_banner -nostats -i $InterpAvs -i $GroundTruthAvs -lavfi "[0:v][1:v]psnr;[0:v][1:v]ssim" -f null - 2>&1
        } finally {
            Set-Location $prevPwd
        }

        # Parse PSNR average and SSIM All
        $psnrLine = ($output | Where-Object { $_ -match 'average:' }) | Select-Object -Last 1
        $ssimLine = ($output | Where-Object { $_ -match 'All:' }) | Select-Object -Last 1

        $avgPsnr = if ($psnrLine -match 'average:([0-9\.]+)') { [double]$Matches[1] } else { 0.0 }
        $avgSsim = if ($ssimLine -match 'All:([0-9\.]+)') { [double]$Matches[1] } else { 0.0 }

        return [PSCustomObject]@{
            Mode       = $ModeName
            Search     = $SearchType
            Param      = $SearchParam
            AvgPsnrDb  = $avgPsnr
            AvgSsim    = $avgSsim
        }
    }

    Write-Host "`n[2/4] Measuring Objective Reconstruction Fidelity..." -ForegroundColor Cyan
    $results = @()
    $results += Measure-SearchMode -ModeName "7x7 Exhaustive" -SearchType 3 -SearchParam 3
    $results += Measure-SearchMode -ModeName "Hex2 (UMH)"     -SearchType 5 -SearchParam 2
    $results += Measure-SearchMode -ModeName "Diamond (Rad2)" -SearchType 2 -SearchParam 2
    $results += Measure-SearchMode -ModeName "Diamond (Rad1)" -SearchType 2 -SearchParam 1

    # Step 4: Display Output Summary Table & Save to File
    Write-Host "`n[3/4] OBJECTIVE FIDELITY RESULTS (Higher is Better):" -ForegroundColor Green
    $baselinePsnr = ($results | Where-Object { $_.Search -eq 3 }).AvgPsnrDb

    $formatted = $results | ForEach-Object {
        $deltaDb = [math]::Round($_.AvgPsnrDb - $baselinePsnr, 3)
        $deltaStr = if ($_.Search -eq 3) { "Baseline (0.000 dB)" } elseif ($deltaDb -ge 0) { "+$deltaDb dB" } else { "$deltaDb dB" }
        [PSCustomObject]@{
            "Search Algorithm" = $_.Mode
            "search"           = $_.Search
            "searchparam"      = $_.Param
            "PSNR (dB)"        = $_.AvgPsnrDb.ToString("F3")
            "Delta vs 7x7"     = $deltaStr
            "SSIM"             = $_.AvgSsim.ToString("F6")
        }
    }

    $formatted | Format-Table -AutoSize

    # Determine output directory (default: Benchmarks/BenchmarkResults)
    $TargetOutputDir = if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
        $OutputDir
    } else {
        Join-Path $ScriptDir "BenchmarkResults"
    }
    if (-not (Test-Path $TargetOutputDir)) {
        New-Item -ItemType Directory -Path $TargetOutputDir -Force | Out-Null
    }

    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $CsvPath = Join-Path $TargetOutputDir "fidelity_searchmodes_$Timestamp.csv"
    $MdPath  = Join-Path $TargetOutputDir "fidelity_searchmodes_$Timestamp.md"

    # Export to CSV
    $csvData = $results | ForEach-Object {
        $deltaDb = [math]::Round($_.AvgPsnrDb - $baselinePsnr, 3)
        [PSCustomObject]@{
            SearchAlgorithm      = $_.Mode
            Search               = $_.Search
            SearchParam          = $_.Param
            AvgPsnrDb            = [math]::Round($_.AvgPsnrDb, 3)
            DeltaVsExhaustiveDb  = $deltaDb
            AvgSsim              = [math]::Round($_.AvgSsim, 6)
        }
    }
    $csvData | Export-Csv -Path $CsvPath -NoTypeInformation

    # Export to Markdown Summary
    $clipDesc = if ([string]::IsNullOrWhiteSpace($VideoPath)) { "Synthetic Motion Test Clip (1080p 60 fps)" } else { (Split-Path $VideoPath -Leaf) }
    $mdContent = @"
# Objective Search Mode Fidelity Evaluation Report

- **Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
- **Test Clip:** $clipDesc
- **Duration Tested:** $DurationSeconds s
- **Resolution:** 1080p (Native 16x16 Blocks, levels=1)

| Search Algorithm | ``search`` | ``searchparam`` | Average PSNR (dB) | Delta vs 7x7 Exhaustive | Global SSIM |
| :--- | :---: | :---: | :---: | :---: | :---: |
"@

    foreach ($row in $formatted) {
        $mdContent += "`n| $($row.'Search Algorithm') | $($row.search) | $($row.searchparam) | $($row.'PSNR (dB)') dB | $($row.'Delta vs 7x7') | $($row.SSIM) |"
    }

    $mdContent += "`n"
    [System.IO.File]::WriteAllText($MdPath, $mdContent, [System.Text.Encoding]::UTF8)

    Write-Host "[4/4] Results written to disk:" -ForegroundColor Green
    Write-Host "  -> CSV Report:      $CsvPath" -ForegroundColor White
    Write-Host "  -> Markdown Report: $MdPath`n" -ForegroundColor White

} finally {
    if (Test-Path $TempDir) {
        Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
