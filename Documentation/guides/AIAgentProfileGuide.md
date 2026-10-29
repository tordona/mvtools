# AI Agent Guide: Generating & Tuning Hardware-Tuned AviSynth+ Profiles

This guide provides the complete specification, standardized agent prompt, and architectural decision trees for AI coding assistants and developers to generate and iteratively tune production-grade **Eco**, **Balanced**, and **MaxQuality** AviSynth+ real-time 60 fps interpolation profiles (`.avs`) for any x86-64 or ARM64 hardware platform.

---

## 1. User Workflows: How to Use This Guide

Depending on your environment, you can use this guide in two ways:
* **[Mode A: Autonomous IDE Agent (Google Antigravity, Cursor, Windsurf, Claude Code)](#mode-a-autonomous-ide-agent-zero-copy-paste-recommended)**: Recommended for developers running within an agentic IDE with terminal and workspace tools. Zero copy-pasting; the agent executes the entire end-to-end loop autonomously.
* **[Mode B: Conversational Web Assistant (Gemini Web, ChatGPT, Claude Web)](#mode-b-conversational-web-assistant-manual-workflow)**: Recommended for quick profile drafting in a browser session. Copy the standardized prompt, paste your hardware specs, deploy the files manually, and paste back benchmark audit reports if tuning is needed.

---

### Mode A: Autonomous IDE Agent (Zero Copy-Paste, Recommended)

Tool-enabled IDE agents have direct access to your local workspace, terminal shell, and file system. Instead of manually copying prompts or telemetry reports, you can instruct your agent with a single instruction:

#### The 1-Step Prompt:
```text
Read docs/guides/AIAgentProfileGuide.md (or https://github.com/tordona/mvtools/blob/mvtools-d3d12/docs/guides/AIAgentProfileGuide.md). Auto-detect this machine's CPU/GPU hardware, generate the 3-tier AviSynth profile set in AviSynth/, run the benchmark harness on Balanced.avs to verify 60 fps stability with 0 drops, and tune parameters according to the Step 4 Diagnosis Matrix if any saturation or drops occur.
```

#### What the IDE Agent Does Autonomously:
1. **Hardware Autodetection:** Queries Windows CIM/WMI (`Get-CimInstance Win32_Processor`, `Win32_VideoController`, `Win32_PhysicalMemory`) to detect physical core counts, P/E core topology, L3 cache, DRAM channels, and TDP limits.
2. **Deterministic Script Writing:** Synthesizes `<Platform>-Eco.avs`, `<Platform>-Balanced.avs`, and `<Platform>-MaxQuality.avs` directly into `AviSynth/` following the Step 1 & Step 2 architectural constraints.
3. **Automated Benchmark Execution:** Executes `.\Benchmarks\MvToolsBenchmark-Start.ps1` with `-AutoInstallPotPlayer` and `-AutoInstallVcRedist` in the background.
4. **Telemetry & Log Auditing:** Reads the resulting `Benchmarks/BenchmarkResults/report_*.txt` and PresentMon frame logs directly from disk.
5. **Closed-Loop Self-Tuning:** If dropped frames, thread capacity saturation (≥ 88%), or thermal throttling are detected, the agent references the [Step 4 Telemetry Diagnosis Matrix](#step-4-telemetry-diagnosis--tuning-matrix-when-performance-fails-60-fps), modifies the `.avs` scripts in-place, and re-tests until 60.00 fps / 0 drops is empirically achieved.
6. **Git Version Control:** Verifies syntax, formats line endings, GPG-signs, and commits the validated profile set.

---

### Mode B: Conversational Web Assistant (Manual Workflow)

When using a web-based AI assistant (e.g. `gemini.google.com`, ChatGPT, or Claude Web):

#### Step 1: Collect Your Hardware Details
Gather three basic pieces of information about your machine:
1. **CPU Model, Core Layout & TDP:** 
   * Example: *Intel Core i7-11850H (8 Willow Cove cores / 16 threads @ 45 W TDP, 24 MB L3)*.
   * Example: *AMD Ryzen AI 5 340 (3x Zen 5 + 3x Zen 5c cores @ 15 W – 28 W TDP, 16 MB L3)*.
   * Example: *Intel Core i5-8259U (4 Coffee Lake cores / 8 threads @ 28 W TDP, 128 MB eDRAM L4)*.
   * Example: *Intel Core i5-1135G7 (4 Willow Cove cores / 8 threads @ 12 W TDP, Iris Xe 80EU)*.
   * Example: *Intel Core i3-1215U (2 Performance cores, 4 Efficient cores @ 15 W TDP)*.
   * Example: *Intel Processor N100 (4 Gracemont E-cores @ 6 W TDP)*.
   * Example: *Qualcomm Snapdragon X Plus (8 Oryon cores @ 12 W – 28 W TDP, Adreno X1-85)*.
2. **Integrated / Dedicated GPU Model:** 
   * Example: *Intel Iris Xe / Intel UHD Graphics*, *Radeon 840M / 780M*, or *Adreno X1*.
3. **System Memory (RAM):** 
   * Example: *16 GB Dual-Channel DDR4-3200*, *16 GB Single-Channel DDR4*, or *32 GB LPDDR5x-7500*.

#### Step 2: Copy and Customize the Prompt
Copy the text in the prompt block in [Section 2: The AI Agent Prompt](#2-the-ai-agent-prompt). Replace the bracketed placeholder:
```text
[INSERT TARGET HARDWARE HERE]
```
with your collected specifications.

#### Step 3: Deploy the Generated Files
Your AI assistant will generate three files:
* `<Platform>-Eco.avs`
* `<Platform>-Balanced.avs`
* `<Platform>-MaxQuality.avs`

Save these `.avs` files directly into the project's **`AviSynth/`** directory:
```text
AviSynth/<Platform>-Eco.avs
AviSynth/<Platform>-Balanced.avs
AviSynth/<Platform>-MaxQuality.avs
```

#### Step 4: Validate with the Automated Benchmark Harness
Run the automated benchmark harness to verify real-time 60 fps stability and zero frame drops:
```powershell
Set-Location Benchmarks
.\MvToolsBenchmark-Start.ps1 -Profile "<Platform>-Balanced.avs" -AutoInstallPotPlayer -AutoInstallVcRedist -TestDurationSeconds 90 -WarmupSeconds 10
```
> [!TIP]
> The `-AutoInstallVcRedist` switch automatically diagnoses, acquires, and silently installs official Microsoft Visual C++ 2015–2022 runtimes if missing, preventing the common PotPlayer error *"AviSynth.dll not found"* (Win32 126).

#### Step 5: Tuning Loop (If Frame Drops or Stutter Occur)
If the benchmark reports dropped frames or under 60 fps:
1. Open the generated audit report: `Benchmarks/BenchmarkResults/report_<Profile>_<Timestamp>.txt`.
2. Copy the **`FRAME RATE & PACING TELEMETRY`**, **`PERFORMANCE TELEMETRY SUMMARY`**, and **`MEMORY & PAGING INTEGRITY`** sections.
3. Paste them back to your AI assistant with this prompt:
   ```text
   The benchmark reported performance issues. Please analyze this telemetry audit report and tune the <Platform> profiles according to the Step 4 Telemetry Diagnosis & Tuning Matrix in your instructions:
   [PASTE TELEMETRY REPORT SECTIONS HERE]
   ```


---

## 2. The AI Agent Prompt

Copy the text inside the block below and paste it into your AI assistant:

````markdown
You are an expert performance engineer specializing in real-time video processing, AviSynth+ multithreading, and MVTools2 motion interpolation (1080p 24 fps -> 60 fps real-time playback in PotPlayer).

Your task is to generate and iteratively tune a complete, production-grade 3-tier AviSynth profile set (`<Platform>-Eco.avs`, `<Platform>-Balanced.avs`, `<Platform>-MaxQuality.avs`) for the following target hardware platform:
[INSERT TARGET HARDWARE HERE: e.g. AMD Ryzen AI 5 340 (3x Zen 5 + 3x Zen 5c, Radeon 840M, 16 GB LPDDR5x) or Intel Core i7-11850H (8 Willow Cove cores / 16 threads @ 45 W, Intel UHD 32EU, 24 MB L3)]

---

### Step 1: Architectural Principles & Constraints

1. **Architecture & Compute Engine Targeting:**
   * **x86-64 Platforms (Intel Core / AMD Ryzen):**
     * Active engine: Native x64 AVX-512 / AVX2 CPU SIMD via `mvtools2.dll`.
     * **Do NOT generate dead `USE_GPU` code or reference `mvtools2-d3d12.dll` on x64 platforms.** `mvtools2-d3d12.dll` is an ARM64-only binary. x64 platforms run 100% native CPU SIMD.
   * **ARM64 Platforms (Qualcomm Snapdragon):**
     * Supports dual-engine execution: Native ARM64 CPU NEON (`mvtools2.dll`) or Direct3D 12 GPU offload (`mvtools2-d3d12.dll`) via `USE_GPU = false/true`.

2. **Deterministic Filter Pipeline:**
   Every profile must strictly follow this AviSynth+ script structure:
   ```avisynth
   # Hardware Header & MT Configuration
   threads   = <T>
   mem_limit = <M>
   SetMemoryMax(mem_limit)
   SetFilterMTMode("DEFAULT_MT_MODE", 2) # MT_MULTI_INSTANCE required

   # Full PotPlayer video source stream (DXVA hardware decoded)
   src = potplayer_source()

   # Load Native MVTools2 plugin
   LoadPlugin("mvtools2.dll")

   # 1. Base Motion Super Clip (Single-Level Geometry)
   # levels=1: Single-level eliminates redundant multi-level pyramid generation
   super = src.MSuper(levels=1, pel=<P>, hpad=<H>, vpad=<V>, sharp=<S>)

   # 2. Motion Vector Search (MAnalyse)
   # levels=1: Single-level search matching super's levels=1
   backward_vec = MAnalyse(super, isb=true,  blksize=<B>, blksizev=<Bv>, search=2, searchparam=<Rad>, chroma=false, levels=1)
   forward_vec  = MAnalyse(super, isb=false, blksize=<B>, blksizev=<Bv>, search=2, searchparam=<Rad>, chroma=false, levels=1)

   # 3. Direct Native 60 fps Frame Synthesis (MBlockFps)
   # Directly warps native frames with 1:1 pixel accuracy
   MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=<Mode>, blend=<Blend>, thSCD1=<Th1>, thSCD2=<Th2>)

   # 4. Core Pinning & Lookahead Buffer
   Prefetch(threads, <Lookahead>)
   ```

3. **Core Topology & Thread Allocation Rules (`threads`):**
   * **The Physical Core Pinning Law:** Never allocate worker threads to SMT / Hyperthreading logical threads (`threads <= physical_cores`). During heavy SIMD SAD vector loops, SMT causes cache-line thrashing and context-switch stalls.
   * Leaving logical threads and background cores free guarantees dedicated CPU headroom for hardware DXVA2/D3D11 decoding, audio synchronization, and Windows DWM presentation, preventing dropped frames.
   * **Homogeneous Cores (Intel 8th–11th Gen, Desktop Core, AMD Zen):**
     * 4-Core CPU (e.g. i5-8259U, i5-1135G7): `threads = 3` (Eco), `threads = 4` (Balanced), `threads = 4` (MaxQuality).
     * 6-Core CPU (e.g. i5-8400, i5-10400): `threads = 3` (Eco), `threads = 4` (Balanced), `threads = 6` (MaxQuality).
     * 8-Core CPU (e.g. i7-11850H, 8C/16T): `threads = 4` (Eco), `threads = 6` (Balanced), `threads = 8` (MaxQuality).
   * **Heterogeneous / Hybrid Cores (Intel Alder Lake/Raptor Lake P+E, AMD Zen 5+Zen 5c, ARM big.LITTLE):**
     * **Intel Hybrid (P+E Cores):** Pin worker threads strictly to high-performance P-cores (e.g. on 2P+4E `i3-1215U`, set `threads = 3`). Never let AviSynth worker threads spill into low-throughput E-cores where the slowest thread stalls the frame presentation deadline.
     * **AMD Zen 5 + Zen 5c (Kraken Point / Strix Point):** Both Zen 5 and Zen 5c share the unified 16 MB L3 cache with full AVX-512 support. Set `threads = 3` (Eco, P-cores only), `threads = 4` (Balanced), `threads = 6` (MaxQuality, all physical cores).
     * **Ultra-Low-Power E-Core Clusters (e.g. Intel N100 4C/4T Gracemont):** `threads = 3` (Eco), `threads = 4` (Balanced & MaxQuality).

4. **Lookahead Queue Sizing (`Prefetch(threads, Lookahead)`):**
   * **Eco Tier:** `Prefetch(threads, 4)` (4 lookahead frames).
   * **Balanced & MaxQuality Tiers:** `Prefetch(threads, 6)` (or `8` on 8-core CPUs).
   * A deeper lookahead queue (6–8 frames) absorbs transient Windows DWM/audio scheduling spikes, locking 1% Low frame rates above **52.0–55.5 fps**.

5. **Lean Memory Ceiling (`SetMemoryMax`):**
   * Because single-level search (`levels=1`) eliminates redundant pyramid buffers, memory requirements are streamlined to preserve UMA DRAM bandwidth for integrated graphics:
     * **Eco:** `mem_limit = 512`
     * **Balanced:** `mem_limit = 768` (or `1024` on 32 GB systems)
     * **MaxQuality:** `mem_limit = 1024` (or `1536` on 8-core systems)

---

### Step 2: Profile Tier Definitions & Tuning Parameters

#### Tier 1: Eco Profile (`<Platform>-Eco.avs`)
* **Objective:** Sub-8 W to 10 W package power, low-thermal battery playback, 0 dropped frames.
* **MSuper:** `levels=1` (single-level restriction), `pel=1` (integer-pixel precision), `hpad=0, vpad=0` (zero padding overhead), `sharp=0` (bilinear).
* **MAnalyse:** Coarse 32x32 blocks (`blksize=32, blksizev=32`, approx. 2,040 blocks total), `search=2, searchparam=1` (tight radius-1 hexagonal search), `chroma=false` (luma-only vector search cuts computation by 50%), `levels=1`.
* **MBlockFps:** `mode=0` (fast 2-stream block projection), `blend=false` (skips transparency blending), `thSCD1=400, thSCD2=130` (robust scene cut protection).
* **Lookahead:** `Prefetch(threads, 4)`.
* **Expected CPU Load:** Typically **3.8% to 12.9%** on modern processors.

#### Tier 2: Balanced Profile (`<Platform>-Balanced.avs`)
* **Objective:** Recommended primary profile. Native 1080p 16x16 vector grid (8,160 blocks; 4x density of 32x32), fine-grained vector tracking, zero optical flow latency bubbles, 0 dropped frames.
* **MSuper:** `levels=1`, `pel=1`, `hpad=0, vpad=0`, `sharp=0`.
* **MAnalyse:** Native 1080p 16x16 blocks (`blksize=16, blksizev=16`), `search=2, searchparam=2` (radius-2 hexagonal search captures rapid motion pans), `chroma=false`, `levels=1`.
* **MBlockFps:** `mode=0` (direct native block projection), `blend=false`, `thSCD1=380, thSCD2=125`.
* **Lookahead:** `Prefetch(threads, 6)`.
* **Expected CPU Load:** Typically **4.5% to 20.8%** on modern processors.

#### Tier 3: MaxQuality Profile (`<Platform>-MaxQuality.avs`)
* **Objective:** Highest visual fidelity, dense 4 px overlapping vector grid (14,151 blocks), directional alpha blending across complex motion and scene cuts.
* **MSuper:** `levels=1`, `pel=1`, `hpad=0, vpad=0`, `sharp=1` (bicubic subpixel sharpness enhances fine detail edge contrast).
* **MAnalyse:** Overlapping 16x16 blocks (`blksize=16, blksizev=16, overlap=4, overlapv=4`), `search=2, searchparam=2`, `chroma=false`, `levels=1`. Overlap completely eliminates block boundary discontinuities and contour edge tearing.
* **MBlockFps:** `mode=0`, `blend=true` (directional alpha blending smooths occlusion/disocclusion edges), `thSCD1=350, thSCD2=115`.
* **Lookahead:** `Prefetch(threads, 6)` (or `8` on 8-core CPUs).
* **Expected CPU Load:** Typically **6.5% to 28.1%** on modern processors.

---

### Step 3: Required Output Format

For the requested platform, output:
1. **Hardware Topology & Budget Analysis:** Summary of core architecture (physical vs logical cores, P/E distribution, L3 cache size, memory channel bandwidth, and sustained TDP limits) justifying the chosen thread counts and parameter choices.
2. **Three Fully Formatted `.avs` Files:**
   * `<Platform>-Eco.avs`
   * `<Platform>-Balanced.avs`
   * `<Platform>-MaxQuality.avs`
   Each file must include a standardized header comment:
   * `# PotPlayer AviSynth 60 fps Interpolation: <Platform> (Profile N: <Tier>)`
   * `# Hardware: <Detailed CPU & iGPU String>`
   * `# Memory: <RAM size, channel configuration, and bandwidth>`
   * `# Architecture: <Native 1080p x86-64 AVX-512 / AVX2 or ARM64 NEON>`
   * `# Target: <Core Design Goal>`
   * `# Revision: 2.0.0 (<Date>)`

---

### Step 4: Telemetry Diagnosis & Tuning Matrix (When Performance Fails 60 fps)

If the user runs `MvToolsBenchmark-Start.ps1` and returns an audit report showing dropped frames or under 60 fps, diagnose the root cause and adjust parameters strictly according to this matrix:

| Telemetry Symptom in Audit Report | Root Cause Diagnosis | Prescribed Parameter Adjustment |
| :--- | :--- | :--- |
| **"AviSynth.dll not found"** dialog in PotPlayer (Win32 Error 126 / `ERROR_MOD_NOT_FOUND`) | **Missing Visual C++ 2015–2022 CRT runtimes:** `vcruntime140.dll`, `msvcp140.dll`, or `vcruntime140_1.dll` missing in `System32`. | Instruct the user to run the benchmark with `-AutoInstallVcRedist`, which automatically downloads and silently installs the official Microsoft redistributable from `https://aka.ms/vc14/vc_redist.x64.exe` (or `arm64.exe`). |
| **"WARNING: Thread Capacity Saturation Detected"** or **Swapchain Duplication Suspected** | **Compute Saturation with Swapchain Masking:** AviSynth worker threads are pinned near 100% capacity (≥ 88% saturation ratio). PotPlayer's D3D11 swapchain is repeating cached frames to fake a 60 fps presentation rate while the filter pipeline falls behind. | 1. If spare physical cores exist (e.g. `threads < physical_cores`), increment `threads` by 1 to add compute capacity.<br>2. Switch `search=2` → `search=0` (OneTime search) in `MAnalyse` to cut vector search ALU time by 40%.<br>3. Increase macroblock size (e.g. 16x16 → 32x32, or 32x32 → 64x32).<br>4. Ensure `blend=false` and `levels=1`. |
| **Average FPS < 58.0 or Dropped Frames > 0** with high CPU (>85%) | **Compute saturation:** Vector search density exceeds CPU core capability. | 1. Ensure `levels=1` is set in both `MSuper` and `MAnalyse`.<br>2. Increase block size (e.g. 16x16 → 32x32).<br>3. In MaxQuality, remove `overlap=4` (revert to non-overlapping 16x16).<br>4. Ensure `blend=false` in `MBlockFps`. |
| **FPS degrades over time** (starts at 60 fps, drops to 45–50 fps by 60 s) | **Thermal Throttling:** All-core package heat forces sustained CPU clock decay. | 1. **Reduce `threads` by 1 or 2** (e.g. 6 → 4, or 4 → 3) to lower total package wattage.<br>2. Restrict threads strictly to Performance cores.<br>3. Ensure `chroma=false` in `MAnalyse` to cut vector ALU work by 50%. |
| **Severe Microstutter (1% Low < 45 fps)** while Average FPS is near 60 | **Thread Scheduling Contention or Jitter.** | 1. Increase lookahead queue to `Prefetch(threads, 6)`.<br>2. If `threads >= physical_cores`, decrement `threads` by 1 to guarantee CPU headroom for DXVA decoding and DWM presentation. |
| **"WARNING: Active pagefile disk swapping detected"** | **Memory Contention / Trimming:** `SetMemoryMax` is exceeding physical budget or starving Windows. | 1. Reduce `SetMemoryMax(mem_limit)` (e.g. 1024 → 768, or 768 → 512).<br>2. Ensure single-level geometry `levels=1` is enabled. |
| **1–2 dropped frames with Render Latency <0.5 ms** | **VSync Phase Drift (Display Refresh Rate Artifact).** | If the audit report notes *"Non-integer display refresh rate detected... caused by VSync phase drift"*, **do NOT modify the script**. This is a physical display scanout artifact (e.g. 60.02 Hz or 60.15 Hz panel clock), not a computational bottleneck. |
