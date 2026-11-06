# AI Agent Profile Tuning & Specification Guide

This guide provides the complete specification, standardized agent prompt, and architectural decision trees for AI coding assistants and developers to generate and iteratively tune production-grade **Eco**, **Balanced**, and **MaxQuality** AviSynth+ real-time 60 fps interpolation profiles (`.avs`) for any x86-64 or ARM64 hardware platform.

> [!TIP]
> **Looking for the Quick Setup?**  
> If you want to generate custom profiles in 1 click without running benchmarks or configuring developer environments, see the **[Custom Profiles Quickstart](guides/GenerateCustomProfiles.md)**.

---

## 1. User Workflows: How to Use This Guide

Depending on your environment and whether you need immediate profile generation or empirical benchmark validation, you can use this guide in two ways:
* **[Mode A: Autonomous IDE Agent (Google Antigravity, Cursor, Windsurf, Claude Code)](#mode-a-autonomous-ide-agent-google-antigravity-cursor-windsurf-claude-code)**: Recommended for developers running within an agentic IDE with terminal and workspace tools.
* **[Mode B: Conversational Web Assistant (Gemini Web, ChatGPT, Claude Web)](#mode-b-conversational-web-assistant-manual-workflow)**: Recommended for quick profile drafting in a web browser session.

> [!TIP]
> **Do I Need to Clone the Repository or Download a Release Archive?**  
> * **No cloning or downloads required** if you simply want to generate custom profiles and use them in PotPlayer. Both Mode A and Mode B can generate tailored profiles anywhere with zero local setup.  
> * **Cloning the repository or extracting a release package is only required** if you want to run the automated benchmark harness (`Benchmarks/MvToolsBenchmark-Start.ps1`, PresentMon ETW logging, and baseline media) for empirical validation and closed-loop self-tuning.

---

### Mode A: Autonomous IDE Agent (Google Antigravity, Cursor, Windsurf, Claude Code)

Tool-enabled IDE agents have direct access to your local workspace, terminal shell, and file system. Workflows are split into two tiers depending on whether you simply want profiles generated, or require full benchmark validation:

#### Option 1: Instant Profile Generation (Zero Clone Required — Recommended Default)
No repository checkout or download is required. The agent reads the raw specification from GitHub, inspects your local hardware, and generates the tailored `.avs` scripts directly into your current directory or PotPlayer folder:

**The 1-Step Generation Prompt:**
```text
Read the specification at:
https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/docs/guides/AIAgentProfileGuide.md

Auto-detect this machine's CPU/GPU hardware using Windows CIM/WMI, and generate the tailored 3-tier AviSynth+ profile set for real-time 24 fps -> 60 fps video motion interpolation in Daum PotPlayer following the exact architectural specifications in that guide.
```

**What the IDE Agent Does Autonomously:**
1. **Hardware Autodetection:** Queries Windows CIM/WMI (`Get-CimInstance Win32_Processor`, `Win32_VideoController`, `Win32_PhysicalMemory`) to detect physical core counts, P/E core topology, L3 cache, DRAM bandwidth, and TDP limits.
2. **Deterministic Script Writing:** Synthesizes `<Platform>-Eco.avs`, `<Platform>-Balanced.avs`, and `<Platform>-MaxQuality.avs` with architecture-specific block sizes, thread counts, memory limits, and core pinning.
3. **Deployment (Optional):** Places the files in your current folder or copies them directly to `C:\Program Files\DAUM\PotPlayer\AviSynth\`.

---

#### Option 2: Closed-Loop Benchmarking & Tuning (Optional — Requires Cloned Repo or Extracted Release)
If you want empirical verification (measuring PresentMon 1% low frame pacing and 0 dropped frames) or need to diagnose and iteratively tune edge-case hardware bottlenecks:

> [!NOTE]
> **Why the Repository or Release Package is Needed for Benchmarking:**  
> The automated test harness (`Benchmarks/MvToolsBenchmark-Start.ps1`), test media clips, and PresentMon telemetry capture reside inside the cloned repository or extracted release package.

**The Closed-Loop Benchmark & Tuning Prompt:**
```text
Verify the current workspace contains .\Benchmarks\MvToolsBenchmark-Start.ps1 (if not, clone https://github.com/tordona/mvtools.git branch mvtools-d3d12). Auto-detect hardware, generate the 3-tier AviSynth+ profiles in AviSynth/, run .\Benchmarks\MvToolsBenchmark-Start.ps1 on Balanced.avs to verify 60 fps stability with 0 drops, and tune parameters according to the Step 4 Diagnosis Matrix if any saturation or drops occur.
```

**What the IDE Agent Does Autonomously in Option 2:**
1. **Automated Benchmark Execution:** Executes `.\Benchmarks\MvToolsBenchmark-Start.ps1` with `-AutoInstallPotPlayer` and `-AutoInstallVcRedist` in the background.
2. **Telemetry & Log Auditing:** Reads `Benchmarks/BenchmarkResults/report_*.txt` and PresentMon frame logs directly from disk.
3. **Closed-Loop Self-Tuning:** If dropped frames, thread capacity saturation (≥ 88%), or thermal throttling are detected, modifies parameters per the [Step 4 Telemetry Diagnosis Matrix](#step-4-telemetry-diagnosis--tuning-matrix-when-performance-fails-60-fps) and re-tests until 60.00 fps / 0 drops is empirically achieved.
4. **Git Version Control:** Commits the validated, tuned profile set.

---

### Mode B: Conversational Web Assistant (Manual Workflow)

When using a web-based AI assistant (e.g. `gemini.google.com`, ChatGPT, or Claude Web):

#### Step 1: Collect Your Hardware Details
Only your **CPU model** is strictly required — the AI assistant can automatically determine core counts, cache sizes, and integrated graphics. Specifying RAM or GPU details is optional:
1. **CPU Model (Required):**
   * Example: *Intel Core i7-11850H (8 Willow Cove cores / 16 threads @ 45 W TDP, 24 MB L3)*.
   * Example: *AMD Ryzen AI 5 340 (3x Zen 5 + 3x Zen 5c cores @ 15 W – 28 W TDP, 16 MB L3)*.
   * Example: *Intel Core i5-8259U (4 Coffee Lake cores / 8 threads @ 28 W TDP, 128 MB eDRAM L4)*.
   * Example: *Intel Core i5-1135G7 (4 Willow Cove cores / 8 threads @ 12 W TDP, Iris Xe 80EU)*.
   * Example: *Intel Core i3-1215U (2 Performance cores, 4 Efficient cores @ 15 W TDP)*.
   * Example: *Intel Processor N100 (4 Gracemont E-cores @ 6 W TDP)*.
   * Example: *Qualcomm Snapdragon X Plus (8 Oryon cores @ 12 W – 28 W TDP, Adreno X1-85)*.
2. **System Memory (RAM) (Optional):**
   * Example: *16 GB Dual-Channel DDR4-3200*, *16 GB Single-Channel DDR4*, or *32 GB LPDDR5x-7500*.
3. **Integrated / Dedicated GPU Model (Optional):**
   * Example: *Intel Iris Xe / Intel UHD Graphics*, *Radeon 840M / 780M*, or *Adreno X1*.

#### Step 2: Copy and Customize the Prompt
Copy the text in the prompt block in [Section 2: The AI Agent Prompt](#_2-the-ai-agent-prompt). Replace the bracketed placeholder:
```text
[INSERT TARGET HARDWARE HERE]
```
with your collected specifications.

#### Step 3: Deploy the Generated Files in PotPlayer
Your AI assistant will generate three files:
* `<Platform>-Eco.avs`
* `<Platform>-Balanced.avs` *(Recommended daily driver)*
* `<Platform>-MaxQuality.avs`

**Option A: Load Directly into PotPlayer (No Clone Required — Recommended):**
1. Save the generated `.avs` files to `C:\Program Files\DAUM\PotPlayer\AviSynth\` (or your personal documents folder).
2. Open PotPlayer, press **`F5`** to open **Preferences**, and navigate to **Video** → **AviSynth**.
3. Under **Load script**, click **Browse** and select your generated `<Platform>-Balanced.avs`.
4. Play any 24 fps / 30 fps video, press **`Tab`** to toggle the On-Screen Display (OSD), and confirm the frame rate reads `XX.XX fps -> 60.00 fps`.

**Option B: Save to Cloned Repository or Extracted Release Package:**
If testing from a cloned repository checkout or extracted release package, save the `.avs` files into `AviSynth/`:
```text
AviSynth/<Platform>-Eco.avs
AviSynth/<Platform>-Balanced.avs
AviSynth/<Platform>-MaxQuality.avs
```

#### Step 4: (Optional) Validate with the Automated Benchmark Harness (Requires Cloned Repo or Release Package)
If you want empirical verification (measuring PresentMon 1% low frame pacing and 0 dropped frames) or need to diagnose stutter:

> [!NOTE]
> **Prerequisite:** Benchmarking requires the cloned repository or extracted release package (`git clone -b mvtools-d3d12 https://github.com/tordona/mvtools.git` or downloaded release archive) because the automated test harness (`Benchmarks/MvToolsBenchmark-Start.ps1`), test media, and PresentMon telemetry capture reside inside `Benchmarks/`.

Run the automated benchmark harness in PowerShell from the repository root or extracted release folder:
```powershell
Set-Location Benchmarks
.\MvToolsBenchmark-Start.ps1 -Profile "..\AviSynth\<Platform>-Balanced.avs" -AutoInstallPotPlayer -AutoInstallVcRedist -TestDurationSeconds 90 -WarmupSeconds 10
```
> [!TIP]
> The `-AutoInstallVcRedist` switch automatically diagnoses, acquires, and silently installs official Microsoft Visual C++ 2015–2022 runtimes if missing, preventing the common PotPlayer error *"AviSynth.dll not found"* (Win32 126).

#### Step 5: (Optional) Tuning Loop (If Frame Drops or Stutter Occur)
If the benchmark reports dropped frames or under 60 fps:
1. Open the generated audit report: `Benchmarks/BenchmarkResults/report_<Profile>_<Timestamp>.txt`.
2. Copy the **`FRAME RATE & PACING TELEMETRY`**, **`PERFORMANCE TELEMETRY SUMMARY`**, and **`MEMORY & PAGING INTEGRITY`** sections.
3. Paste them back to your AI assistant with this prompt:
   ```text
   The benchmark reported performance issues. Analyze this telemetry audit report and tune the <Platform> profiles according to the Step 4 Telemetry Diagnosis & Tuning Matrix in your instructions:
   [PASTE TELEMETRY REPORT SECTIONS HERE]
   ```

---

## 2. The AI Agent Prompt

Copy the text inside the block below and paste it into your AI assistant:

````markdown
You are an expert performance engineer specializing in real-time video processing, AviSynth+ multithreading, and MVTools2 motion interpolation (real-time 24 fps -> 60 fps playback in PotPlayer).

Your task is to generate and iteratively tune a complete, production-grade 3-tier AviSynth+ profile set (`<Platform>-Eco.avs`, `<Platform>-Balanced.avs`, `<Platform>-MaxQuality.avs`) for the following target hardware platform:
[INSERT TARGET HARDWARE HERE: e.g. AMD Ryzen AI 5 340 (3x Zen 5 + 3x Zen 5c, Radeon 840M, 16 GB LPDDR5x) or Intel Core i7-11850H (8 Willow Cove cores / 16 threads @ 45 W, Intel UHD 32EU, 24 MB L3)]

---

### Step 1: Architectural Principles & Constraints

1. **Architecture & Compute Engine Targeting:**
   * **Dual-Engine Execution Model (CPU SIMD vs. Direct3D 12 GPU Offload):**
     Both x86-64 (Intel Core / AMD Ryzen) and ARM64 (Qualcomm Snapdragon) platforms support unified execution via `LoadPlugin("mvtools2.dll")`:
     * **Native CPU SIMD Engine:** Executes 100% on CPU cores using native vector extensions (x86-64 AVX-512 / AVX2 / SSE4.2; ARM64 NEON). On ARM64, this includes an in-process native Windows thread pool fallback (`AvstpFallbackPool`) guaranteeing deterministic slice scheduling without `avstp.dll`.
     * **Direct3D 12 GPU Offload Engine:** Offloads block SAD vector estimation (`motion_search_cs.hlsl`) and frame synthesis / motion compensation warping (`flow_warp.hlsl`) to the graphics processor via `MEnableD3D12(USE_D3D12)`.
   * **Hardware Eligibility Gating (When to Include `USE_D3D12`):**
     Direct3D 12 compute offload requires sufficient shader core density and UMA memory bandwidth to complete within the 16.67 ms presentation deadline:
     * **Eligible Silicon (Include `USE_D3D12 = true/false` Dual-Path Toggle):**
       Include `USE_D3D12` whenever the platform meets ALL of the following:
       1. **GPU Shader Density:** $\ge 32\text{ EUs}$ (Intel Gen 9–12 / Xe / Arc), $\ge 4\text{ CUs}$ (AMD RDNA / Vega), or $\ge\text{Adreno 680}$ (Qualcomm). Examples: AMD Ryzen AI 300 (Radeon 840M/880M/890M), Ryzen 6000/7000/8000 APUs (Radeon 660M/680M/760M/780M), Intel 11th–14th Gen Core / Core Ultra with Iris Xe (80/96 EUs) or Arc Graphics, Qualcomm Snapdragon 8cx Gen 1–3, Snapdragon X Elite/Plus (Adreno X1-85).
       2. **Shader Compute Throughput:** $\ge 600\text{ GFLOPS}$ FP32 sustained compute.
       3. **Memory Bandwidth:** $\ge 35\text{ GB/s}$ UMA memory bandwidth (dual-channel DDR4-3200+, DDR5, or LPDDR5/x).
       4. **Package Thermal Envelope:** Sustained package $\text{TDP} > 10\text{ W}$ (active cooling or adequate heatpipe chassis).
     * **Excluded Silicon (Mandatory 100% Native CPU SIMD — Exclude `USE_D3D12`):**
       Do **NOT** generate `USE_D3D12` or reference `MEnableD3D12` on silicon falling below these thresholds:
       1. **Entry-tier x86-64:** Intel Atom / Celeron / Pentium Silver (e.g. Gemini Lake N5000 / UHD 605 with 18 EUs, N4000 / UHD 600 with 12 EUs), Apollo Lake (HD 500/505), Jasper Lake / Alder Lake-N with $< 32\text{ EUs}$, AMD Mendocino (Radeon 610M, 2 CUs), or fanless packages $\le 6\text{ W – 10 W}$ TDP.
       2. **Entry-tier ARM64:** Qualcomm Snapdragon 7c / 7c Gen 2 (Adreno 618), Snapdragon 850 (Adreno 630).
       *Architectural Reason:* Low-density GPU shader arrays ($< 32\text{ EUs}$ / $< 4\text{ CUs}$) and narrow memory buses cannot evaluate 8,160 blocks within the 16.67 ms frame budget. Adding compute dispatch starves the GPU's hardware video decoder (DXVA2/D3D11) and D3D11 swapchain presentation, triggering queue stalls and severe frame drops. The native CPU SIMD path evaluates coarse 32x32 vectors in 8 ms – 11 ms without contending for GPU resources.
   * **Direct3D 12 GPU Offload Execution Invariants (The GPU Contract):**
     When generating profiles for eligible silicon with `USE_D3D12`, the following kernel constraints are mandatory to guarantee GPU execution without silent CPU fallback or visual distortion:
     1. **Luma-Only Vector Search:** `chroma = false` is required in `MAnalyse` and `MRecalculate`. (`D3D12MotionSearch` strictly gates offload on `!chroma`; setting `chroma = true` silently falls back to CPU SIMD).
     2. **Integer Super Clip:** Set `pel = 1` and `sharp = 0` on GPU offload. This avoids CPU-side subpixel plane construction; Direct3D 12 `FlowWarpCS` executes subpixel bilinear texture sampling directly via GPU hardware texture samplers.
     3. **Unsplit Block Grid in Refinement:** In `MRecalculate`, set `divide = 0`. Unsplit block indexing is required for 1:1 structured buffer alignment in `motion_search_cs.hlsl`.
     4. **Mandatory Zero Overlap on GPU Offload:** NEVER use block overlap (`overlap > 0`) when `USE_D3D12 = true`. Direct3D 12 `FlowWarpCS` (`flow_warp.hlsl`) indexes motion vectors via direct coordinate division (`DTid.x / nBlkSizeX`), requiring a non-overlapping block grid. Non-zero overlap causes spatial vector-to-pixel misalignment and severe geometric warping tearing across the frame. In **MaxQuality**, high tracking fidelity with GPU offload MUST be achieved via **dual-pass coarse-to-fine refinement with `MRecalculate(divide=0)`** (`overlap = 0`), never by setting `overlap > 0` on the GPU. (On pure CPU SIMD fallback, `overlap = 4` is supported via `overlap_size = USE_D3D12 ? 0 : 4`).
     5. **Synthesis Mode Gating by Tier (`synth_mode` / `mode`):**
        * **Eco Tier (`Profile 1: Eco`):** MUST set `synth_mode = 0` (fast 2-stream block projection) across BOTH GPU and CPU. Mode 2 (Dynamic Median with occlusion masking) must NEVER be used on Eco, as running GPU occlusion shaders defeats the sub-8 W power objective.
        * **Balanced Tier (`Profile 2: Balanced`):** MUST set `synth_mode = 0` across BOTH GPU and CPU. Direct native block projection sustains 60 fps with 0 dropped frames without optical flow latency bubbles.
        * **MaxQuality Tier (`Profile 3: MaxQuality`):** Set `synth_mode = USE_D3D12 ? 2 : 0`. Mode 2 engages GPU Dynamic Median with occlusion masking on compute shaders, while cleanly reverting to fast projection (mode=0) on CPU fallback.
     6. **Pixel Bit Depth:** D3D12 compute shaders currently support 8-bit input (`pixelsize_super == 1`).
     7. **Queue-Depth Thread Budgeting:** When `USE_D3D12 = true`, worker threads simply submit command lists to the Direct3D 12 queue (which is serialized by an internal mutex). Set `threads = 2` (Eco, double-buffered), `threads = 3` (Balanced, triple-buffered), or `threads = 4` (MaxQuality, quad-buffered) to avoid command queue lock contention.
     8. **Dynamic Parameter Coupling:** Always provide ternary declarations (`USE_D3D12 ? <GPU_Val> : <CPU_Val>`) for `threads`, `mem_limit`, and `pad_size`. In MaxQuality, also declare `synth_mode = USE_D3D12 ? 2 : 0` and `overlap_size = USE_D3D12 ? 0 : 4`. (In Eco and Balanced, `synth_mode` must be hardcoded to `0`).
     9. **Mandatory `MEnableD3D12` Engine Activation:** Whenever `USE_D3D12` is declared in a script, `MEnableD3D12(USE_D3D12)` **MUST ALWAYS** be invoked immediately following `LoadPlugin("mvtools2.dll")`. Never omit this call. If omitted, setting `USE_D3D12 = true` silently fails to engage the Direct3D 12 compute queue, leaving the engine trapped in CPU SIMD mode with GPU-budgeted parameters.
     10. **Mandatory Conservative Default (`USE_D3D12 = false`):** Generated profiles **MUST ALWAYS** default to `USE_D3D12 = false`. Native CPU SIMD is the production reference baseline that guarantees 0 dropped frames and maximum compatibility across all memory channel configurations and bit depths out-of-the-box. Direct3D 12 GPU offload is an experimental opt-in toggle; the agent must never emit a profile with `USE_D3D12 = true` enabled by default, leaving that as an explicit manual choice for the user.

> [!TIP]
> **Direct3D 12 GPU Offload (`USE_D3D12 = true` — Experimental Preview)**  
> Direct3D 12 GPU offload executes on any supported DirectX 12 Feature Level 11_0+ GPU (AMD Radeon RDNA/Vega $\ge 4\text{ CUs}$, Intel Iris Xe $\ge 32\text{ EUs}$ / Arc, Qualcomm Adreno 680+ / X1-85) via `MEnableD3D12(USE_D3D12)`. When enabled, SAD motion search and flow synthesis are offloaded to DirectCompute shaders, freeing CPU cores for background system tasks and reducing package thermal strain.

2. **Deterministic Filter Pipeline & Strict Variable Ordering:**
   AviSynth+ is an imperative, top-to-bottom interpreted language without variable hoisting. Every profile must strictly follow this sequential execution order:
   ```avisynth
   # 1. Hardware Header & MT Configuration (Resolution-Independent Settings Only)
   USE_D3D12  = false                    # MANDATORY DEFAULT: Always false (CPU SIMD production baseline). User flips to true for GPU offload
   threads    = USE_D3D12 ? <T_GPU> : <T_CPU>  # GPU queue depth (2 for Eco, 3 for Balanced, 4 for MaxQuality) vs CPU cores
   mem_limit  = USE_D3D12 ? <M_GPU> : <M_CPU>
   pel_val    = USE_D3D12 ? 1 : <P_CPU>
   sharp_mode = USE_D3D12 ? 0 : <S_CPU>
   pad_size   = USE_D3D12 ? 8 : 0

   # SYNTHESIS MODE & OVERLAP RULES BY TIER:
   # For Profile 1 (Eco) & Profile 2 (Balanced): synth_mode MUST BE 0 across both GPU and CPU:
   synth_mode = 0
   # For Profile 3 (MaxQuality) ONLY:
   # synth_mode   = USE_D3D12 ? 2 : 0
   # overlap_size = USE_D3D12 ? 0 : 4          # OVERLAP MUST BE 0 ON GPU OFFLOAD
   SetMemoryMax(mem_limit)
   SetFilterMTMode("DEFAULT_MT_MODE", 2) # MT_MULTI_INSTANCE required

   # 2. PotPlayer Video Source Stream (DXVA / Hardware Decoded)
   # CRITICAL: MUST precede all resolution queries; establishes the clip object for Width()
   src = potplayer_source()              # or potplayer_source() for implicit 'last'

   # 3. Dynamic Resolution Adaptation (MUST Immediately Follow Source Initialization)
   # CRITICAL: is_4k must be defined before any blk_* or pad_* expression reads it
   is_4k      = (src.Width() > 2048)
   blk_coarse = is_4k ? 64 : 32          # (or blk_sz = is_4k ? (<B> * 2) : <B>)
   blk_fine   = is_4k ? 32 : 16
   pad_val    = is_4k ? (pad_size * 2) : pad_size

   # 4. Load Plugin & Configure Direct3D 12 Engine
   LoadPlugin("mvtools2.dll")
   MEnableD3D12(USE_D3D12)               # MANDATORY: Must ALWAYS be called whenever USE_D3D12 is declared
   try { LoadPlugin("AvsAffinity.dll") } catch(e) {}

   # 5. Base Motion Super Clip (Single-Level Geometry)
   # levels=1: Single-level eliminates redundant multi-level pyramid generation
   super = src.MSuper(levels=1, pel=pel_val, hpad=pad_val, vpad=pad_val, sharp=sharp_mode)

   # 6. Motion Vector Search (MAnalyse & MRecalculate)
   backward_vec = MAnalyse(super, isb=true,  blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=<Rad>, chroma=false, levels=1)
   forward_vec  = MAnalyse(super, isb=false, blksize=blk_coarse, blksizev=blk_coarse, search=2, searchparam=<Rad>, chroma=false, levels=1)

   # 7. Direct Native 60 fps Frame Synthesis (MBlockFps)
   # Directly warps native frames with 1:1 pixel accuracy; MUST assign to 'last' (or call bare) so PotPlayer receives the interpolated clip (never 'out = MBlockFps')
   last = MBlockFps(src, super, backward_vec, forward_vec, num=60, den=1, mode=synth_mode, blend=<Blend>, thSCD1=<Th1>, thSCD2=<Th2>)

   # 8. Hardware Thread Affinity & Lookahead Buffer
   last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last
   Prefetch(threads, <Lookahead>)
   ```

3. **Core Topology & Thread Allocation Rules (`threads`):**
   * **Direct3D 12 Command Queue Threading (`USE_D3D12 = true`):** When offloading to GPU DirectCompute, worker threads do not perform vector SAD arithmetic; they record and dispatch command lists to the Direct3D 12 direct queue. Because queue submission is internally synchronized via mutex, thread counts represent lookahead queue depth rather than physical cores:
     * **Eco:** `threads = 2` (double-buffered asynchronous submission; minimizes CPU wattage).
     * **Balanced:** `threads = 3` (triple-buffered submission; balances CPU and GPU pipeline concurrency).
     * **MaxQuality:** `threads = 4` (quad-buffered submission; fully saturates GPU compute units without mutex lock contention).
     * On CPU SIMD fallback (`USE_D3D12 = false`), thread counts immediately revert to the physical CPU core budgets detailed below.
   * **Worker Thread Sizing & Physical Core Budgeting:** Never allocate worker threads to SMT / Hyperthreading logical threads (`threads <= physical_cores` or `threads <= physical_p_cores` on hybrid architectures). During heavy SIMD SAD vector loops, SMT causes cache-line thrashing and context-switch stalls. Note that `Prefetch(threads)` controls AviSynth+ thread pool concurrency (worker instance count).
   * **Hardware Thread Affinity (`PinWorkerThreads`):** On hybrid architectures (Intel Alder/Raptor Lake/Core Ultra P+E, AMD Zen 4c/5c, Qualcomm Snapdragon), chain `last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last` immediately prior to `Prefetch(threads, <Lookahead>)`. This confines worker threads strictly to high-IPC Performance cores while leaving audio decoding, DXVA, and D3D11 presentation swapchains free on Efficiency cores. On homogeneous processors (e.g. Intel N100, AMD Ryzen standard CCDs, Snapdragon X Elite/Plus), `PinWorkerThreads()` automatically detects identical efficiency classes and safely evaluates to a no-op without misconfiguring affinity.
   * Leaving logical threads and background cores free guarantees dedicated CPU headroom for hardware DXVA2/D3D11 decoding, audio synchronization, and Windows DWM presentation, preventing dropped frames.
   * **Homogeneous Cores (Intel 8th–11th Gen, Desktop Core, AMD Zen):**
     * 4-Core CPU (e.g. i5-8259U, i5-1135G7): `threads = 3` (Eco), `threads = 4` (Balanced), `threads = 4` (MaxQuality).
     * 6-Core CPU (e.g. i5-8400, i5-10400): `threads = 3` (Eco), `threads = 4` (Balanced), `threads = 6` (MaxQuality).
     * 8-Core CPU (e.g. i7-11850H, 8C/16T): `threads = 4` (Eco), `threads = 6` (Balanced), `threads = 8` (MaxQuality).
   * **Heterogeneous / Hybrid Cores (Intel Alder Lake/Raptor Lake/Core Ultra P+E, AMD Zen 5+Zen 5c, ARM big.LITTLE):**
     * **Intel Hybrid (P+E Cores):** Budget worker threads strictly against high-performance P-cores (`threads <= p_cores`; e.g. on 4P+8E `i7-1260P`, set `threads = 3` for Eco, `threads = 4` for Balanced/MaxQuality; on 6P+8E `Ultra 7 155H`, set `threads = 3` for Eco, `threads = 4` for Balanced, `threads = 5` or `6` for MaxQuality). Never allocate thread counts based on total physical cores or allow worker threads to spill into low-throughput E-cores where the slowest thread stalls the frame presentation deadline.
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

6. **Dynamic Resolution Adaptation & 4K Block Density Law:**
   * Profiles must never hardcode static pixel block sizes without checking source stream dimensions. Because a 4K frame (`3840x2160`) contains $4\times$ the pixel area of 1080p (`8.29M` vs `2.07M` pixels), running fixed 1080p block sizes on 4K causes a catastrophic $4\times$ macroblock count explosion (from `8,160` blocks to `32,400` blocks), saturating the GPU compute queue, CPU thread pool, and UMA memory bus.
   * Every profile must implement runtime resolution detection and proportional block scaling:
     * **Runtime Resolution Detection:**
       ```avisynth
       is_4k = (src.Width() > 2048)
       ```
     * **Single-Pass Profiles (Eco / High-Throughput Balanced):**
       * If base is `32x32` at 1080p: `blk_sz = is_4k ? 64 : 32` (maintains invariant `2,040` blocks).
       * If base is `16x16` at 1080p: `blk_sz = is_4k ? 32 : 16` (maintains invariant `8,160` blocks).
     * **Dual-Pass Coarse-to-Fine Profiles (Balanced / MaxQuality with `MRecalculate`):**
       * `blk_coarse = is_4k ? 64 : 32` (maintains invariant `2,040` coarse blocks).
       * `blk_fine   = is_4k ? 32 : 16` (maintains invariant `8,160` fine blocks).
       * Total evaluated blocks remains strictly invariant at `10,200` blocks across both 1080p and 4K, cutting 4K block search workload by **75%**.
   * **Boundary Padding & Overlap:**
       * Boundary padding scales proportionally: `pad_val = is_4k ? (pad_size * 2) : pad_size` (where `pad_size = USE_D3D12 ? 8 : 0`).
       * Overlap scales proportionally: `overlap_val = is_4k ? (overlap_size * 2) : overlap_size`.
       * **Direct3D 12 Zero-Overlap Invariant:** Overlap is strictly prohibited when Direct3D 12 GPU offload is active (`overlap_size = USE_D3D12 ? 0 : 4`). DirectCompute shaders in `flow_warp.hlsl` index vectors via direct coordinate division (`DTid.x / nBlkSizeX`), requiring a non-overlapping block grid. Non-zero overlap causes spatial vector-to-pixel misalignment and severe visual tearing. When targeting MaxQuality on GPU offload, fine vector tracking MUST be achieved via **dual-pass coarse-to-fine refinement with `MRecalculate(divide=0)`** (`overlap = 0`), never by configuring `overlap > 0` on the GPU.
     * **Proxy-Downscaled Profiles (e.g. Snapdragon 7c Gen 2):**
       * Scale proxy downsampling: `search_scale = is_4k ? 4 : 2` and `scale_val = Float(search_scale)`. The analysis clip remains invariant at $960 \times 540$ (`2,040` blocks) regardless of input resolution.
   * **Mandatory Variable Ordering Invariant (No Forward References):**
     * AviSynth+ is a strictly sequential, top-to-bottom interpreted language without variable hoisting.
     * **Source Clip First:** The video source clip (`src = potplayer_source()`) **MUST ALWAYS** be instantiated before `is_4k = (src.Width() > 2048)` is called. Calling `Width()` before source acquisition raises a fatal error (`no implicit clip "last"` or `unknown function`).
     * **Definition Before Use:** `is_4k` **MUST ALWAYS** be defined before any expression that reads it (e.g. `blk_coarse`, `blk_fine`, `blk_sz`, `pad_val`, `overlap_val`). Referencing `is_4k` before its definition line aborts script evaluation immediately with `Script error: I don't know what "is_4k" means`.
     * **No Resolution Calculations in Header:** Never place `blk_coarse = ... (is_4k ? ...)` in the top hardware configuration section above `potplayer_source()`. Static engine parameters (`threads`, `mem_limit`, `pel_val`, `sharp_mode`) belong in the top block; all dynamic geometric scaling parameters belong immediately after `potplayer_source()`.

7. **Quantitative Subpixel Precision Rules (`pel` & `sharp` in `MSuper`):**
   In `MSuper()`, `pel` controls subpixel motion vector interpolation (1 = integer-pel with 1 subplane; 2 = half-pel with 4 subplanes). In the **MaxQuality** tier:
   * **Mandatory `pel = 1` (Integer Precision Default) — Set `pel_val = 1` if ANY of these conditions are true:**
     1. **Physical Core Ceiling:** `physical_cores < 8` on homogeneous processors (e.g. 4-core or 6-core AMD Ryzen 5 / Intel Core i5).
     2. **Performance Core Ceiling:** `physical_p_cores < 6` on hybrid processors (e.g. Intel 2P+8E `Core Ultra 5 125U`, 4P+8E `Core i7-1260P`).
     3. **Thermal / Package Envelope:** `sustained_tdp < 28 W` (ultrabook U-series, fanless SoCs, or entry-tier silicon like the 8-core Snapdragon X Plus `X1P-42-xxx`).
     4. **Memory Bandwidth:** Single-channel memory (`memory_channels == 1` or bandwidth $< 60\text{ GB/s}$).
     *Sharpening Filter:* Set `sharp_mode = 1` (standard bicubic).
   * **Eligible for `pel = 2` (Half-Pixel Precision) — Set `pel_val = 2` ONLY when ALL of these conditions are met:**
     1. **Core Topology:** `physical_p_cores >= 6` on hybrid CPUs (e.g. 6P+8E `Core i7-13700H`, `Ultra 7 155H`), OR `homogeneous_cores >= 8` with all-core clock $\ge 3.8\text{ GHz}$ (e.g. desktop AMD Ryzen 7/9, 12-core Snapdragon X Elite `X1E-80/84`).
     2. **Thermal / Package Envelope:** `sustained_tdp >= 35 W` (H/HX-series, desktop socket, or active workstation cooling).
     3. **Memory Bandwidth:** Dual-channel DDR5 or 128-bit LPDDR5x ($\ge 100\text{ GB/s}$ UMA memory bandwidth).
     *Sharpening Filter:* Set `sharp_mode = 2` (Wiener 6-tap filter, vectorized via native AVX2 / ARM64 NEON).

---

### Step 2: Profile Tier Definitions & Tuning Parameters

#### Tier 1: Eco Profile (`<Platform>-Eco.avs`)
* **Objective:** Sub-8 W to 10 W package power, low-thermal battery playback, 0 dropped frames.
* **MSuper:** `levels=1` (single-level restriction), `pel=1` (integer-pixel precision), `hpad=pad_val, vpad=pad_val` (where `pad_size = USE_D3D12 ? 8 : 0`), `sharp=0` (bilinear).
* **MAnalyse:** Coarse 32x32 blocks (`blksize=blk_sz, blksizev=blk_sz`, approx. 2,040 blocks total at 1080p), `search=2, searchparam=1` (tight radius-1 hexagonal search), `chroma=false` (luma-only vector search cuts computation by 50%), `levels=1`.
* **MBlockFps:** `mode=0` (fast 2-stream block projection mandatory across BOTH GPU and CPU; never set mode=2 on Eco), `blend=false` (skips transparency blending), `thSCD1=400, thSCD2=130` (robust scene cut protection).
* **Lookahead:** `Prefetch(threads, 4)`.
* **Expected CPU Load:** Typically **3.8% to 12.9%** on modern processors (or < 3% with Direct3D 12 GPU offload).

#### Tier 2: Balanced Profile (`<Platform>-Balanced.avs`)
* **Objective:** Recommended primary profile. Native 1080p 16x16 vector grid (8,160 blocks; 4x density of 32x32), fine-grained vector tracking, zero optical flow latency bubbles, 0 dropped frames.
* **MSuper:** `levels=1`, `pel=1`, `hpad=pad_val, vpad=pad_val` (where `pad_size = USE_D3D12 ? 8 : 0`), `sharp=0`.
* **MAnalyse:** Native 1080p 16x16 blocks (`blksize=blk_sz, blksizev=blk_sz`), `search=2, searchparam=2` (radius-2 hexagonal search captures rapid motion pans), `chroma=false`, `levels=1`.
* **MBlockFps:** `mode=0` (direct native block projection mandatory across BOTH GPU and CPU), `blend=false`, `thSCD1=380, thSCD2=125`.
* **Lookahead:** `Prefetch(threads, 6)`.
* **Expected CPU Load:** Typically **4.5% to 20.8%** on modern processors.

#### Tier 3: MaxQuality Profile (`<Platform>-MaxQuality.avs`)
* **Objective:** Highest visual fidelity, dense sub-block vector grid, directional alpha blending across complex motion and scene cuts.
* **MSuper:** `levels=1`, `pel=pel_val` (`pel_val = USE_D3D12 ? 1 : <pel>` strictly adhering to Step 1.7), `hpad=pad_val, vpad=pad_val`, `sharp=sharp_mode` (`sharp_mode = USE_D3D12 ? 0 : <sharp>`).
* **Motion Vector Architecture:**
  * **Direct3D 12 GPU Offload (`USE_D3D12 = true`):** Dual-pass coarse-to-fine refinement with zero overlap (`overlap = 0`). Start with coarse 32x32 `MAnalyse` (`blk_coarse = is_4k ? 64 : 32`, `search=2, searchparam=2`), followed by fine 16x16 `MRecalculate` (`blk_fine = is_4k ? 32 : 16`, `divide=0`, `overlap=0`, `search=2, searchparam=2`, `chroma=false`). Direct3D 12 `FlowWarpCS` requires non-overlapping blocks; `overlap > 0` causes spatial coordinate misalignment and severe image tearing.
  * **CPU SIMD Fallback (`USE_D3D12 = false`):** Overlapping 16x16 blocks (`blksize=blk_sz, blksizev=blk_sz, overlap=overlap_val, overlapv=overlap_val` with `overlap_size = USE_D3D12 ? 0 : 4`), eliminating block boundary discontinuities via CPU vector interpolation.
* **MBlockFps:** `mode=synth_mode` (`synth_mode = USE_D3D12 ? 2 : 0` — mode 2 Dynamic Median with occlusion masking on GPU; fast projection mode 0 on CPU fallback), `blend=true` (directional alpha blending smooths occlusion/disocclusion edges), `thSCD1=350, thSCD2=115`.
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
   * `# Architecture: <x86-64 AVX-512 / AVX2 or ARM64 NEON / Direct3D 12 GPU Offload>`
   * `# Generator: <Agent Name & Model, e.g. Claude 3.5 Sonnet, ChatGPT-4o, Google Antigravity, or Manual> (AIAgentProfileGuide Rev 2.3.9)`
   * `# Target: <Core Design Goal>`
   * `# Revision: 2.3.9 (2026-11-06)`
   * `# Changelog: Removed query timestamp parameters from prompt helpers, consolidated provenance header, enforced USE_D3D12 = false default`
3. **Execution Order & Variable Integrity Checklist:**
   Before outputting any profile, verify strictly:
   - [ ] Standard header includes `# Generator: <Model> (AIAgentProfileGuide Rev 2.3.9)`.
   - [ ] `USE_D3D12` is set to `false` by default (`USE_D3D12 = false`); never emit `USE_D3D12 = true` as the default.
   - [ ] `potplayer_source()` is invoked before calling `Width()`.
   - [ ] `is_4k = (src.Width() > 2048)` is defined before any `blk_coarse`, `blk_fine`, `blk_sz`, or `pad_val` assignment.
   - [ ] `MEnableD3D12(USE_D3D12)` is invoked immediately after `LoadPlugin("mvtools2.dll")` whenever `USE_D3D12` is declared.
   - [ ] `MBlockFps` is assigned to `last` (e.g. `last = MBlockFps(...)`) or called bare so PotPlayer receives the interpolated clip (never assign to an unused variable like `out =`).
   - [ ] Zero resolution-dependent variable calculations exist in the top hardware configuration block.
   - [ ] Memory limit and thread counts match platform core counts and DRAM bandwidth.
4. **Clean Script Formatting:**
   * Emit standard AviSynth+ syntax with one statement per line. Never collapse statements onto a single line without linebreaks.
   * If splitting multi-argument function calls, use AviSynth+ line continuation (`\` as the first non-whitespace character on subsequent lines).

---

### Step 4: Telemetry Diagnosis & Tuning Matrix (When Performance Fails 60 fps)

If the user runs `MvToolsBenchmark-Start.ps1` and returns an audit report showing dropped frames or under 60 fps, diagnose the root cause and adjust parameters strictly according to this matrix:

| Telemetry Symptom in Audit Report | Root Cause Diagnosis | Prescribed Parameter Adjustment |
| :--- | :--- | :--- |
| **"AviSynth.dll not found"** dialog in PotPlayer (Win32 Error 126 / `ERROR_MOD_NOT_FOUND`) | **Missing Visual C++ 2015–2022 CRT runtimes:** `vcruntime140.dll`, `msvcp140.dll`, or `vcruntime140_1.dll` missing in `System32`. | Instruct the user to run the benchmark with `-AutoInstallVcRedist`, which automatically downloads and silently installs the official Microsoft redistributable from `https://aka.ms/vc14/vc_redist.x64.exe` (or `arm64.exe`). |
| **"WARNING: Thread Capacity Saturation Detected"** or **Swapchain Duplication Suspected** | **Compute Saturation with Swapchain Masking:** AviSynth+ worker threads are pinned near 100% capacity (≥ 88% saturation ratio). PotPlayer's D3D11 swapchain is repeating cached frames to fake a 60 fps presentation rate while the filter pipeline falls behind. | 1. If spare physical cores exist (e.g. `threads < physical_cores`), increment `threads` by 1 to add compute capacity.<br>2. Switch `search=2` → `search=0` (OneTime search) in `MAnalyse` to cut vector search ALU time by 40%.<br>3. Increase macroblock size (e.g. 16x16 → 32x32, or 32x32 → 64x32).<br>4. Ensure `blend=false` and `levels=1`. |
| **Average FPS < 58.0 or Dropped Frames > 0** with high CPU (> 85%) | **Compute saturation:** Vector search density exceeds CPU core capability. | 1. Ensure `levels=1` is set in both `MSuper` and `MAnalyse`.<br>2. If `pel=2` is active, revert `pel=2` → `pel=1` and `sharp=2` → `sharp=1` in `MSuper` to eliminate 3 subpixel planes and cut memory bus traffic.<br>3. Increase block size (e.g. 16x16 → 32x32).<br>4. In MaxQuality, remove `overlap=4` (revert to non-overlapping 16x16).<br>5. Ensure `blend=false` in `MBlockFps`. |
| **FPS degrades over time** (starts at 60 fps, drops to 45–50 fps by 60 s) | **Thermal Throttling:** All-core package heat forces sustained CPU clock decay. | 1. **Reduce `threads` by 1 or 2** (e.g. 6 → 4, or 4 → 3) to lower total package wattage.<br>2. Restrict threads strictly to Performance cores.<br>3. Ensure `chroma=false` in `MAnalyse` to cut vector ALU work by 50%. |
| **Severe Microstutter (1% Low < 45 fps)** while Average FPS is near 60 | **Thread Scheduling Contention or Jitter.** | 1. Ensure `last = FunctionExists("PinWorkerThreads") ? last.PinWorkerThreads() : last` is active on hybrid P/E or ARM64 architectures.<br>2. Increase lookahead queue to `Prefetch(threads, 6)`.<br>3. If `threads >= physical_cores`, decrement `threads` by 1 to guarantee CPU headroom for DXVA decoding and DWM presentation. |
| **"WARNING: Active pagefile disk swapping detected"** | **Memory Contention / Trimming:** `SetMemoryMax` is exceeding physical budget or starving Windows. | 1. Reduce `SetMemoryMax(mem_limit)` (e.g. 1024 → 768, or 768 → 512).<br>2. Ensure single-level geometry `levels=1` is enabled. |
| **1–2 dropped frames with Render Latency < 0.5 ms** | **VSync Phase Drift (Display Refresh Rate Artifact).** | If the audit report notes *"Non-integer display refresh rate detected... caused by VSync phase drift"*, **do NOT modify the script**. This is a physical display scanout artifact (e.g. 60.02 Hz or 60.15 Hz panel clock), not a computational bottleneck. |
````
