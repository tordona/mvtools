# MVTools Benchmark & Comparison Test Suite

Comprehensive automated benchmarking, telemetry collection, and performance analysis suite for **MVTools** on Windows on ARM64 (Qualcomm Snapdragon SoCs) and x64 (AMD Ryzen / Intel Core).

This test suite rigorously measures, validates, and compares motion estimation and 60 fps frame interpolation across performance tiers (**Eco**, **Balanced**, **MaxQuality**) and compute engines (**ARM64 CPU NEON** or **x64 CPU SIMD** via `mvtools2.dll` vs. **Direct3D 12 GPU** via `mvtools2_d3d12.dll`).

> [!WARNING]
> **Experimental Feature Notice (Direct3D 12 GPU Offload):**  
> Direct3D 12 GPU acceleration (`mvtools2_d3d12.dll`) is provided as an **experimental preview**. Rendering fidelity, motion vector precision, and real-time performance are provided on a **best-effort basis and are not guaranteed**. Visual output, frame pacing, and stability may vary across GPU generations, display driver versions, and concurrent desktop swapchain loads. The native **ARM64 CPU NEON / x64 CPU SIMD engine (`mvtools2.dll`)** serves as the production reference.

---

## Suite Architecture & Core Tools

The test suite consists of two complementary PowerShell scripts located in the `Benchmarks/` directory:

```text
Benchmarks/
├── MvToolsBenchmark-Start.ps1      # Automated, reproducible benchmark execution harness
├── MvToolsBenchmarks-Compare.ps1   # Comparative matrix analysis and report generator
├── Baseline/                       # Reference benchmark comparison matrices across platforms
│   ├── BenchmarkMatrix_Comparison_Combined.md
│   ├── BenchmarkMatrix_Comparison_Generic-x64.md
│   ├── BenchmarkMatrix_Comparison_Snapdragon-X-Plus.md
│   ├── BenchmarkMatrix_Comparison_Snapdragon-8cxGen3.md
│   ├── BenchmarkMatrix_Comparison_Snapdragon-8cxGen2.md
│   ├── BenchmarkMatrix_Comparison_Snapdragon-8cxGen1.md
│   ├── BenchmarkMatrix_Comparison_Snapdragon-850.md
│   └── BenchmarkMatrix_Comparison_Snapdragon-7cGen2.md
├── PresentMon-arm64.exe            # Intel PresentMon for ARM64 (DXGI/ETW sub-millisecond frame capture)
├── PresentMon-x64.exe              # Intel PresentMon for x64 (DXGI/ETW sub-millisecond frame capture)
├── PresentMon-LICENSE.txt          # MIT License for Intel PresentMon
└── BenchmarkResults/               # Working directory for local run outputs and raw CSVs
```

| Script | Version | Purpose | Key Output |
| :--- | :---: | :--- | :--- |
| [`MvToolsBenchmark-Start.ps1`](MvToolsBenchmark-Start.ps1) | `v2.5.0` | Executes an isolated PotPlayer run, configures AviSynth profiles, normalizes system load, and records sub-millisecond ETW pacing & resource telemetry. | `report_*.txt`<br>`presentmon_*.csv`<br>`telemetry_*.csv` |
| [`MvToolsBenchmarks-Compare.ps1`](MvToolsBenchmarks-Compare.ps1) | `v2.5.0` | Aggregates individual benchmark runs into a side-by-side comparative matrix (Eco vs. Balanced vs. MaxQuality and CPU vs. GPU), or executes the full 3×2 test matrix automatically. | `BenchmarkMatrix_Comparison_<Platform>.md`<br>`BenchmarkMatrix_Comparison_<Platform>.csv`<br>`BenchmarkMatrix_Comparison_Combined.md` |

---

## Reference Baseline Matrices (`Baseline/`)

Verified baseline benchmark reports and comparative matrices across ARM64 Snapdragon SoC generations and Generic x86-64 hardware are preserved under [`Baseline/`](Baseline/):

| Platform / SoC | Baseline Report | Tested Chassis / Target Hardware |
| :--- | :--- | :--- |
| **Combined Overview** | [**`BenchmarkMatrix_Comparison_Combined.md`**](Baseline/BenchmarkMatrix_Comparison_Combined.md) | Multi-platform comparative executive summary |
| **AMD Ryzen AI 5 340** | [**`BenchmarkMatrix_Comparison_AMD-Ryzen-AI-5-340.md`**](Baseline/BenchmarkMatrix_Comparison_AMD-Ryzen-AI-5-340.md) | AMD Ryzen AI 5 340 (3x Zen 5 + 3x Zen 5c @ 15 W TDP, Radeon 840M RDNA 3.5) |
| **Intel Core i7-11850H** | [**`BenchmarkMatrix_Comparison_Intel-Core-i7-11850H.md`**](Baseline/BenchmarkMatrix_Comparison_Intel-Core-i7-11850H.md) | Intel Core i7-11850H (8C/16T @ 45 W TDP, Intel UHD 32EU, 24 MB L3) |
| **Intel Core i5-8259U** | [**`BenchmarkMatrix_Comparison_Intel-Core-i5-8259U.md`**](Baseline/BenchmarkMatrix_Comparison_Intel-Core-i5-8259U.md) | Intel Core i5-8259U (4C/8T @ 28 W TDP, Iris Plus 655, 128 MB eDRAM) |
| **Intel Core i5-1135G7** | [**`BenchmarkMatrix_Comparison_Intel-Core-i5-1135G7.md`**](Baseline/BenchmarkMatrix_Comparison_Intel-Core-i5-1135G7.md) | Intel Core i5-1135G7 (4C/8T @ 12 W TDP, Iris Xe 80EU, 16 GB Dual-Channel) |
| **Intel Core i3-1215U** | [**`BenchmarkMatrix_Comparison_Intel-Core-i3-1215U.md`**](Baseline/BenchmarkMatrix_Comparison_Intel-Core-i3-1215U.md) | Intel Core i3-1215U (2P+4E/8T @ 15 W TDP, Intel UHD 64EU, 16 GB Dual-Channel) |
| **Intel Processor N100** | [**`BenchmarkMatrix_Comparison_Intel-Processor-N100.md`**](Baseline/BenchmarkMatrix_Comparison_Intel-Processor-N100.md) | Intel Processor N100 (4C/4T Gracemont @ 6 W TDP, Intel UHD 24EU, 16 GB Single-Channel) |
| **Intel Core i5-7Y54** | [**`BenchmarkMatrix_Comparison_Core-i5-7Y54.md`**](Baseline/BenchmarkMatrix_Comparison_Core-i5-7Y54.md) | Intel Core i5-7Y54 (2C/4T @ 10 W TDP, Intel HD 615, 8 GB LPDDR3-1866) |
| **Intel Pentium Silver N5030** | [**`BenchmarkMatrix_Comparison_Generic-x64.md`**](Baseline/BenchmarkMatrix_Comparison_Generic-x64.md) | Intel Pentium Silver N5030 @ 1.10 GHz, Intel UHD Graphics 605, 8 GB RAM |
| **Snapdragon X Plus** | [**`BenchmarkMatrix_Comparison_Snapdragon-X-Plus.md`**](Baseline/BenchmarkMatrix_Comparison_Snapdragon-X-Plus.md) | Surface Pro 11th Edition (Qualcomm Oryon, Adreno X1-85) |
| **Snapdragon 8cx Gen 3** | [**`BenchmarkMatrix_Comparison_Snapdragon-8cxGen3.md`**](Baseline/BenchmarkMatrix_Comparison_Snapdragon-8cxGen3.md) | Lenovo ThinkPad X13s (4x Cortex-X1 + 4x A78, Adreno 690) |
| **Snapdragon 8cx Gen 2** | [**`BenchmarkMatrix_Comparison_Snapdragon-8cxGen2.md`**](Baseline/BenchmarkMatrix_Comparison_Snapdragon-8cxGen2.md) | Microsoft Surface Pro X SQ2 (Kryo 495, Adreno 680) |
| **Snapdragon 8cx Gen 1** | [**`BenchmarkMatrix_Comparison_Snapdragon-8cxGen1.md`**](Baseline/BenchmarkMatrix_Comparison_Snapdragon-8cxGen1.md) | Microsoft Surface Pro X SQ1 (Kryo 495, Adreno 675) |
| **Snapdragon 850** | [**`BenchmarkMatrix_Comparison_Snapdragon-850.md`**](Baseline/BenchmarkMatrix_Comparison_Snapdragon-850.md) | Samsung Galaxy Book2 (Kryo 385, Adreno 630, 5 W Fanless) |
| **Snapdragon 7c Gen 2** | [**`BenchmarkMatrix_Comparison_Snapdragon-7cGen2.md`**](Baseline/BenchmarkMatrix_Comparison_Snapdragon-7cGen2.md) | Samsung Galaxy Book Go (Kryo 468, Adreno 618, 4 GB Fanless) |

---

## AI Agent Profile Generation & Tuning Guide

When bringing MVTools2 to a new hardware platform or validating new profile sets, refer to the comprehensive companion guide:  
👉 [**AI Agent Guide: Generating & Tuning Hardware-Tuned AviSynth+ Profiles**](../Documentation/guides/AIAgentProfileGuide.md)

This companion guide provides:
- **Mode A: Autonomous IDE Agent Workflow:** Zero-copy-paste loop for AI coding assistants (Google Antigravity, Cursor, Windsurf, Copilot) to auto-detect hardware, generate `.avs` profiles, run the benchmark harness, audit PresentMon telemetry, and self-tune parameters in a closed loop.
- **Mode B: Conversational Web Prompt:** Ready-to-use prompt for web LLMs (Gemini, ChatGPT, Claude) with microarchitectural core-pinning laws.
- **Step 4 Telemetry Diagnosis & Tuning Matrix:** Empirical decision tree mapping dropped frames, thread capacity saturation, and thermal throttling back to prescribed `.avs` parameter adjustments.

---

## Revisioning Standard

Both the benchmark test harness and all AviSynth interpolation profiles follow **Semantic Versioning (`MAJOR.MINOR.PATCH`)** coupled with release dates (`YYYY-MM-DD`):

- **AviSynth Profiles (`AviSynth/*.avs`):**
  Embedded in the standardized comment header:
  ```avisynth
  # Revision: 2.1.0 (2026-10-19)
  # Changelog: Coarse 32x32 -> fine 16x16, pinned to 4x Cortex-X1 cores (threads=4), mem_limit=1024, D3D12 toggle
  ```
  - `MAJOR`: Fundamental architectural paradigm shifts (e.g. moving from 0.5x proxy estimation to native 1080p `levels=1`).
  - `MINOR`: SoC-specific core cluster pinning, memory ceiling changes, or adding the Direct3D 12 `USE_GPU` engine toggle.
  - `PATCH`: Parameter fine-tuning, search parameter calibration, or bug fixes.

- **PowerShell Harness Scripts (`Benchmarks/*.ps1`):**
  Embedded via PowerShell Comment-Based Help (`.VERSION`, `.DATE`, `.NOTES`) and exposed via `$Script:HarnessVersion` and `$Script:CompareVersion`:
  - `MAJOR`: Workflow structural changes or report schema format updates.
  - `MINOR`: New telemetry capture modules (e.g., empirical display scanout analysis, VSync drift detection, D3D12 mode injection).
  - `PATCH`: Logic fixes, threshold tightening, and output formatting.

---

## 1. MvToolsBenchmark-Start.ps1

An automated, fully deterministic benchmark harness designed to eliminate noise, thermal throttling variance, and configuration drift.

### The 7-Phase Benchmark Workflow

1. **[1/7] PotPlayer Verification & Automated Acquisition:**
   - Verifies PotPlayer executable integrity or automatically downloads and silently installs official native PotPlayer (`PotPlayerSetupARM64.exe` on ARM64 or `PotPlayerSetup64.exe` on x64 via `-AutoInstallPotPlayer`).
   - Audits required Microsoft Visual C++ 2015-2022 Redistributable runtime libraries (`vcruntime140.dll`, `msvcp140.dll`, and on x64 `vcruntime140_1.dll`) matching target architecture (`0xAA64` ARM64 or `0x8664` x64). If missing or mismatched (which causes PotPlayer to report "AviSynth.dll not found" due to Win32 error 126), prompts for permission or automatically downloads and silently installs from official aka.ms permalinks via `-AutoInstallVcRedist`.
   - Verifies presence of `AviSynth.dll` in PotPlayer's directory. If missing from local system and registry locations, automatically acquires the official release package from GitHub (`AviSynth/AviSynthPlus`, dynamic latest tag) and extracts the native architecture binary (`arm64\bin\AviSynth.dll` or `x64\AviSynth.dll`).
2. **[2/7] PotPlayer Version & Test Asset Integrity Audit:**
   - Detects and records the installed or portable PotPlayer version and PE linker build timestamp (e.g. `1.7.23122 (Build: 2026-09-01 22:30:50)`).
   - Audits the target video's SHA-256 checksum (`99486359be7e3681168a0fe94e1cbb0284c48b57b2a3ce7df4fa75e185987a15`).
   - If missing or corrupted, provides direct download instructions and official Blender Mango URL.
3. **[3/7] MVTools Plugin Presence & PE Linker Audit:**
   - Validates existence of specific plugin binaries (`mvtools2.dll` for CPU NEON/SIMD, `mvtools2_d3d12.dll` for D3D12 GPU mode).
   - If missing (or when `-AutoDownloadMvTools` is specified), automatically queries GitHub Releases (`tordona/mvtools` on ARM64, `pinterf/mvtools` on x64) using dynamic REST API discovery with HTML fallback (zero hardcoded filenames/versions), downloads the latest release archive with live streaming progress, and decompresses binaries using native 7-Zip or Windows bsdtar.
   - Synchronizes MVTools binaries and AviSynth profiles into PotPlayer's application directory. If benchmark profiles are missing, acquires them directly from `tordona/mvtools` repository.
   - Queries and logs FileVersion, ProductVersion, PE Linker Build Date, and SHA-256 hashes.
4. **[4/7] Deterministic Settings Injection & Single-Instance Guarantee:**
   - Injects AviSynth profile with verified absolute DLL paths.
   - Enforces Built-in Direct3D 11 Video Renderer (`VideoRen2=15`) for DXGI swapchain event tracking.
   - Enforces always on top during playback (`TopMost=2`) to prevent foreground occlusion and DWM compositing fallback.
   - Forces fullscreen keep-aspect-ratio presentation, hides playlist dock, detaches side panels, and terminates any duplicate background player instances.
5. **[5/7] Physical RAM & UMA Headroom Verification:**
   Evaluates profile `SetMemoryMax`, allocates 1024 MB UMA/player buffer headroom, triggers GC, and checks available physical RAM. On memory-constrained devices (e.g. 4 GB RAM), surfaces a non-fatal warning and prompts interactively (or bypasses with `-IgnoreRamWarning`) rather than aborting unconditionally.
6. **[6/7] Environmental Stabilization & Load Normalization:**
   - Inspects physical display hardware refresh rate via native Win32 `QueryDisplayConfig`. Surfaces a prominent warning if a non-integer rate (e.g. 59.86 Hz or 59.94 Hz) is detected, explaining that VSync phase drift between the 60.000 fps video clock and panel scanout will artificially inflate dropped frames.
   - Verifies AC power connection (blocks run on battery to avoid dynamic clock downthrottling).
   - Activates Windows High Performance power plan (`8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`).
   - Quiesces noisy background applications (browsers, Discord, Teams, Slack, Steam).
   - Silences network adapters to suppress background Windows Update / telemetry bursts.
   - Idles until System CPU load is $\le 8\%$ and GPU is $\le 5\%$ for 5 consecutive seconds.
7. **[7/7] Telemetry Capture & Tear-Down:**
   - Launches PotPlayer and seeks to 00:01:00.
   - Discards initial warmup period (N seconds) to bypass JIT compilation and pipeline fill.
   - Spawns PresentMon for hardware-level ETW frame presentation timing.
   - Samples second-by-second CPU %, total GPU %, PotPlayer GPU %, working set RAM, and memory page swaps.
   - Restores original PotPlayer INI, network adapters, and power plan on exit.

---

### Parameter Reference: MvToolsBenchmark-Start.ps1

| Parameter | Aliases | Type | Default | Description |
| :--- | :--- | :---: | :---: | :--- |
| `-VideoPath` | `Video`, `File` | `string` | `"tears_of_steel_1080p.mov"` | Path to target video file. Auto-discovers test MOV in script directory if omitted. |
| `-AviSynthProfile` | `Profile`, `Avs`, `Script` | `string` | `""` | Profile to load. Accepts full path, filename, partial name (e.g. `X-Plus-Balanced`), or tier keyword (`Eco`, `Balanced`, `MaxQuality`). |
| `-GpuMode` | `Gpu`, `Mode` | `string` | `"Auto"` | Compute engine selection: `Auto` (hardware recommended), `D3D12` / `GPU`, `CPU` / `NEON` / `SIMD`, or `ProfileDefault`. |
| `-Interactive` | `Menu` | `switch` | `$false` | Launches console interactive menu listing all available platform profiles with hardware badges and engine prompts. |
| `-TestDurationSeconds` | | `int` | `120` | Total duration of the test run in seconds. |
| `-WarmupSeconds` | | `int` | `20` | Initial duration discarded from telemetry to allow cache and pipeline fill. |
| `-BufferHeadroomMb` | | `int` | `1024` | Required free RAM buffer above `SetMemoryMax` before test is permitted to run. |
| `-ExpectedVideoHash` | | `string` | `994863...` | Expected SHA-256 hash for target video clip validation. |
| `-SkipVideoChecksum` | | `switch` | `$false` | Bypasses SHA-256 check when benchmarking arbitrary unverified video files. |
| `-SkipNetworkDisable` | | `switch` | `$false` | Prevents disabling network adapters during the benchmark. |
| `-SkipProcessKill` | `SkipAppKill` | `switch` | `$false` | Skips prompt and termination of background applications (browsers, discord, slack, etc.) prior to test. |
| `-IgnoreUsbWarning` | | `switch` | `$false` | Bypasses interactive confirmation when running from USB flash storage. |
| `-IgnoreRamWarning` | `IgnoreMemoryWarning` | `switch` | `$false` | Bypasses interactive confirmation when physical RAM headroom is below recommended levels on memory-constrained devices. |
| `-IgnoreBatteryWarning` | | `switch` | `$false` | Bypasses fatal error when device is running on battery power (allows testing on battery without AC connected). |
| `-MemoryConstrained` | | `switch` | `$false` | Explicitly tags the test run as conducted on a memory-constrained device (also auto-detected if total RAM <= 4.5 GB or free RAM is below headroom). |
| `-AutoInstallPotPlayer` | | `switch` | `$false` | Automatically downloads and silently installs official native PotPlayer (`PotPlayerSetupARM64.exe` or `PotPlayerSetup64.exe`) from Kakao CDN if not found on the machine. |
| `-AutoInstallVcRedist` | `AutoInstallVC`, `InstallVcRedist` | `switch` | `$false` | Automatically downloads and silently installs official Microsoft Visual C++ 2015-2022 Redistributables (`VC_redist.arm64.exe` or `VC_redist.x64.exe`) via aka.ms permalinks if required runtime DLLs are missing or architecture-mismatched. |
| `-AutoDownloadMvTools` | `DownloadMvTools`, `UpdateMvTools` | `switch` | `$false` | Automatically downloads and extracts latest official MVTools binaries (`mvtools2.dll`, `mvtools2_d3d12.dll`) and AviSynth profiles from GitHub releases (`tordona/mvtools` on ARM64, `pinterf/mvtools` on x64). Missing binaries or missing `.avs` profiles also trigger automated acquisition. |
| `-MvToolsRepo` | | `string` | `"tordona/mvtools"` (ARM64)<br>`"pinterf/mvtools"` (x64) | GitHub repository slug for downloading release packages (default dynamically resolves based on target architecture). |
| `-AviSynthRepo` | | `string` | `"AviSynth/AviSynthPlus"` | GitHub repository slug for downloading official AviSynth+ releases. If `AviSynth.dll` is missing, the harness automatically downloads the latest release archive and extracts `arm64\bin\AviSynth.dll` or `x64\AviSynth.dll`. |
| `-OutputDir` | | `string` | `"BenchmarkResults"` | Directory where report TXT and CSV telemetry are saved. |

---

### Usage Examples: MvToolsBenchmark-Start.ps1

#### Example 1: Interactive Menu (Select Profile & Engine Interactively)
```powershell
powershell -ExecutionPolicy Bypass -File "./Benchmarks/MvToolsBenchmark-Start.ps1" -Interactive
```

#### Example 2: Run Recommended Profile with Direct3D 12 GPU Compute
```powershell
powershell -ExecutionPolicy Bypass -File "./Benchmarks/MvToolsBenchmark-Start.ps1" -GpuMode D3D12
```

#### Example 3: Select by Tier Keyword on Detected Platform
```powershell
# Automatically resolves to Snapdragon-X-Plus-MaxQuality.avs on Snapdragon X Plus host
powershell -ExecutionPolicy Bypass -File "./Benchmarks/MvToolsBenchmark-Start.ps1" -Profile MaxQuality -GpuMode CPU
```

#### Example 4: Quick 30-Second Verification Run (5 s Warmup)
```powershell
powershell -ExecutionPolicy Bypass -File "./Benchmarks/MvToolsBenchmark-Start.ps1" -Profile Balanced -GpuMode D3D12 -WarmupSeconds 5 -TestDurationSeconds 30 -SkipNetworkDisable
```

---

## 2. MvToolsBenchmarks-Compare.ps1

The comparative aggregation tool that parses individual audit reports and transforms them into side-by-side matrices comparing performance across tiers (**Eco vs. Balanced vs. MaxQuality**) and compute engines (**ARM64 CPU NEON / x64 CPU SIMD vs. Direct3D 12 GPU**).

### Features
- **Automatic Log Parsing:** Extracts frame rate pacing (`Avg FPS`, `1% Low FPS`, `0.1% Low FPS`, `Dropped Frames`) and resource load (`CPU %`, `GPU %`, `PotPlayer GPU %`, `RAM MB`).
- **Deduplication:** Groups results by `(Tier, Mode)` and keeps the most recent valid run for each configuration.
- **Multiple Output Formats:** Produces colorized console tables, GitHub Flavored Markdown (`.md`), and spreadsheet-ready CSV (`.csv`).
- **Dynamic Chipset-Agnostic Architectural Analysis:** Dynamically extracts the active profile configuration (540p proxy vs. native 1080p, block refinement, subpixel precision, synthesis mode), computes measured CPU/GPU compute deltas and frame pacing, and generates platform-specific recommendations based on real benchmark telemetry.
- **Batch Matrix Execution (`-RunMatrix`):** Sequentially runs all 6 permutations back-to-back under identical environmental conditions, then displays the final comparison matrix.

---

### Parameter Reference: MvToolsBenchmarks-Compare.ps1

| Parameter | Type | Default | Description |
| :--- | :--- | :---: | :--- |
| `-ResultsDir` | `string` | `"BenchmarkResults"` | Path containing benchmark report files (`report_*.txt`). |
| `-RunMatrix` | `switch` | `$false` | Executes all 6 permutations (Eco/Balanced/MaxQuality × CPU/D3D12) sequentially before compiling the report. |
| `-DurationSeconds` | `int` | `30` | Duration per run when executing `-RunMatrix`. |
| `-WarmupSeconds` | `int` | `10` | Warmup seconds discarded per run when executing `-RunMatrix`. |
| `-OutputMarkdown` | `string` | `"BenchmarkMatrix_Comparison_<Platform>.md"` | Path to save the Markdown comparison table. By default, auto-names with the platform key to prevent cross-platform file overwrites. |
| `-OutputCsv` | `string` | `"BenchmarkMatrix_Comparison_<Platform>.csv"` | Path to save the CSV comparison table. By default, auto-names with the platform key to prevent cross-platform file overwrites. |
| `-FilterPlatform` | `string` | `""` | Substring to filter reports by platform (e.g. `Generic-x64`, `Snapdragon-X-Plus`, `Snapdragon-8cxGen3`). When executing with `-RunMatrix`, automatically forwards `-Profile <FilterPlatform>-<Tier>`. |
| `-PotPlayerDir` | `string` | `""` | Custom PotPlayer installation or portable directory, forwarded across all matrix permutations executed under `-RunMatrix`. |
| `-MvToolsRepo` | `string` | `""` | GitHub repository slug for release acquisition, forwarded across all matrix permutations executed under `-RunMatrix`. |
| `-IgnoreRamWarning` | `switch` | `$false` | Bypasses interactive RAM headroom confirmation across all matrix runs on memory-constrained devices. |
| `-IgnoreUsbWarning` | `switch` | `$false` | Bypasses interactive confirmation when running matrix benchmarks from USB flash storage. |
| `-MemoryConstrained` | `switch` | `$false` | Forwards the memory-constrained tag across all matrix permutations executed under `-RunMatrix`. |
| `-AutoInstallPotPlayer` | `switch` | `$false` | Automatically downloads and silently installs official native PotPlayer (ARM64 or x64) if missing before running matrix benchmarks. |
| `-AutoInstallVcRedist` | `switch` | `$false` | Forwards automated Microsoft Visual C++ 2015-2022 Redistributable acquisition and silent installation across all matrix permutations executed under `-RunMatrix`. |
| `-AutoDownloadMvTools` | `switch` | `$false` | Automatically downloads and deploys latest official MVTools binaries (from `tordona/mvtools` on ARM64 or `pinterf/mvtools` on x64) if missing before running matrix benchmarks. |
| `-SkipProcessKill` | `switch` | `$false` | Bypasses background app termination prompt across all matrix permutations executed under `-RunMatrix`. |

---

### Usage Examples: MvToolsBenchmarks-Compare.ps1

#### Example 1: View Comparison Matrix from Existing Benchmark Runs
```powershell
powershell -ExecutionPolicy Bypass -File "./Benchmarks/MvToolsBenchmarks-Compare.ps1"
```

#### Example 2: Execute Fresh Test Matrix (3×2 on ARM64, 3×1 on x64; 60 Seconds per Permutation)
```powershell
powershell -ExecutionPolicy Bypass -File "./Benchmarks/MvToolsBenchmarks-Compare.ps1" -RunMatrix -DurationSeconds 60 -WarmupSeconds 10
```
> [!NOTE]
> On ARM64 platforms, `-RunMatrix` tests both CPU NEON and D3D12 GPU modes across Eco, Balanced, and MaxQuality tiers (6 permutations). On x64 platforms, `-RunMatrix` automatically restricts execution to CPU SIMD mode (3 permutations), bypassing Direct3D 12 acceleration tests.

#### Example 3: Filter by Platform and Output to Custom Location
```powershell
powershell -ExecutionPolicy Bypass -File "./Benchmarks/MvToolsBenchmarks-Compare.ps1" -FilterPlatform "Snapdragon-X-Plus" -OutputMarkdown "C:\Reports\XPlus_Matrix.md"
```

---

## Output Metrics & Interpretation Guide

When analyzing the comparison matrix, focus on the following key performance indicators:

### 1. Motion Fluidity & Pacing
- **Average FPS:** Target is solid **60.00 fps**. Any lower indicates dropped or skipped frames.
- **1% Low FPS (Microstutter Indicator):**
  - **≥ 52.0 fps:** Stable presentation; frame time variance is within ±2.5 ms.
  - **< 45.0 fps:** Visible stutter; frame rendering variance exceeds display refresh sync windows.
  - *Observation:* ARM64 CPU NEON typically achieves tighter 1% Lows ($53-54\text{ FPS}$) than D3D12 GPU because it avoids command queue contention with PotPlayer's Direct3D 11 presentation swapchain.
- **Dropped Frames:** In Windows DWM Composed Flip mode, PotPlayer presents directly to the desktop window manager swapchain. Clean runs present zero dropped presentation frames.

### 2. Compute Load & Efficiency
- **System CPU Load % vs. PotPlayer GPU %:**
  - **ARM64 CPU NEON (`mvtools2.dll`):** Average CPU load is $\sim 12-16\%$ across 8 Oryon cores; GPU load stays at $\sim 19-25\%$ (presentation and display composition only).
  - **Direct3D 12 GPU (`mvtools2_d3d12.dll`):** Offloads motion search into Adreno GPU compute queues ($\sim 72-75\%$ GPU load), freeing CPU compute resources for background multi-tasking. *(Note: D3D12 GPU execution is an experimental preview; rendering fidelity and real-time performance are best-effort).*
- **PotPlayer Working Set (RAM):**
  - **Eco Tier:** $\sim 315\text{ MB}$ (540p proxy clip reduces cache lines and DRAM pressure).
  - **Balanced Tier:** $\sim 384\text{ MB}$ (Full 1080p motion search).
  - **MaxQuality Tier:** $\sim 507\text{ MB}$ (Sub-pixel `pel=2` multi-level pyramid).

---

## Prerequisites & Setup

1. **Host Operating System:** Windows 11 on ARM64 (Qualcomm Snapdragon X Elite, Snapdragon X Plus, Snapdragon 8cx Gen 3/2/1, 850, or 7c) or Windows 10/11 on x64 (AMD Ryzen, Intel Core).
2. **Administrator Privileges (Recommended):**
   - Windows Event Tracing for Windows (ETW) Direct3D presentation hooks require elevation for PresentMon to record sub-millisecond frame intervals and 1% Lows.
   - Launch PowerShell with **Run as Administrator**.
3. **Reference Video Asset:**
   - Place `tears_of_steel_1080p.mov` in the `Benchmarks/` directory.
   - If missing, download from [Blender Mango Open Movie Project](https://mango.blender.org/download/).
   - Verified SHA-256: `99486359be7e3681168a0fe94e1cbb0284c48b57b2a3ce7df4fa75e185987a15`.
4. **PotPlayer Software & Licensing Notice:**
   - **Proprietary Freeware:** PotPlayer is proprietary freeware owned and maintained by **Kakao Corp.**
   - **No Redistribution Permitted:** Under **Article 3 (Obligations of the User), Section 2** of the PotPlayer EULA, users are strictly prohibited from redistributing, hosting, bundling, mirroring, or transferring the software in part or in its entirety. As such, PotPlayer binaries are **not** bundled or tracked in this Git repository.
   - **How to Obtain PotPlayer Officially:**
     - Official Website: [https://potplayer.tv](https://potplayer.tv)
     - Official Direct Native ARM64 Installer: [PotPlayerSetupARM64.exe](https://t1.daumcdn.net/potplayer/PotPlayer/Version/Latest/PotPlayerSetupARM64.exe)
   - **Supported Setup Modes:**
     - **Mode 0 (Automated Acquisition - Recommended):** Pass `-AutoInstallPotPlayer` or confirm the prompt when missing. The harness directly streams `PotPlayerSetupARM64.exe` from Kakao CDN with a live progress bar and installs silently via an animated background spinner loop.
     - **Mode 1 (Default System Installation):** Run the official installer. The harness automatically detects `C:\Program Files\DAUM\PotPlayer`.
     - **Mode 2 (Local Sibling Directory):** Copy your official portable PotPlayer folder into `Benchmarks/PotPlayer/`.
     - **Mode 3 (Custom Path CLI):** Pass `-PotPlayerDir "D:\Custom\PotPlayer"` when executing `MvToolsBenchmark-Start.ps1`.
5. **Intel® PresentMon Licensing & Attribution:**
   - **Open Source:** Intel PresentMon is open-source software licensed under the **MIT License**.
   - **Copyright:** Copyright (C) 2017-2024 Intel Corporation.
   - **Official Project Repository:** [GameTechDev/PresentMon](https://github.com/GameTechDev/PresentMon)
   - **License File:** The complete MIT license text is preserved in [`Benchmarks/PresentMon-LICENSE.txt`](PresentMon-LICENSE.txt).
   - **Redistribution Rights:** Unlike proprietary software, the MIT License explicitly permits redistribution and inclusion of the binary and associated documentation provided that the copyright and permission notices are retained.