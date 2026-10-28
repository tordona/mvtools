# AI Agent Guide: Generating & Tuning Hardware-Tuned AviSynth+ Profiles

This guide provides a standardized, copy-paste prompt and user workflow for prompting AI coding assistants (such as Google Antigravity, Claude, ChatGPT, or GitHub Copilot) to generate customized, production-ready **Eco**, **Balanced**, and **MaxQuality** AviSynth+ real-time interpolation profiles (`.avs`) for any CPU/SoC platform, along with an automated feedback loop to tune profiles if frame drops occur.

---

## 1. User Instructions: How to Use This Guide

When bringing MVTools2 to a new hardware platform (e.g., AMD Ryzen, Intel Core Ultra, Apple Silicon via Wine/Proton, or a new Qualcomm Snapdragon generation), follow these simple steps:

### Step 1: Collect Your Hardware Details
Before talking to your AI agent, gather three basic pieces of information about your machine:
1. **CPU Model & Core Layout:** 
   * Example: *Intel Core Ultra 7 155H (6 Performance cores, 8 Efficient cores, 2 Low-power E-cores)*.
   * Example: *AMD Ryzen 7 7840U (8 Zen 4 cores / 16 threads)*.
2. **Integrated / Dedicated GPU Model:** 
   * Example: *Intel Arc Graphics (8 Xe cores)* or *Radeon 780M*.
3. **System Memory (RAM):** 
   * Example: *16 GB LPDDR5x* or *32 GB DDR5*.

### Step 2: Copy and Customize the Prompt Below
Copy the text in the prompt block in [Section 2: The AI Agent Prompt](#2-the-ai-agent-prompt). Replace the bracketed placeholder:
```text
[INSERT TARGET HARDWARE HERE]
```
with your collected specifications.

### Step 3: Deploy the Generated Files
Your AI agent will generate three files:
* `<Platform>-Eco.avs`
* `<Platform>-Balanced.avs`
* `<Platform>-MaxQuality.avs`

Save these `.avs` files directly into the project's **`AviSynth/`** directory:
```text
AviSynth/<Platform>-Eco.avs
AviSynth/<Platform>-Balanced.avs
AviSynth/<Platform>-MaxQuality.avs
```

### Step 4: Validate with the Automated Benchmark Harness
Run the benchmark harness to verify real-time 60 fps stability and zero frame drops:
```powershell
Set-Location Benchmarks
.\MvToolsBenchmark-Start.ps1 -Profile "<Platform>-Balanced.avs" -TestDurationSeconds 90 -WarmupSeconds 10
```

### Step 5: Tuning Loop (If Frame Drops or Stutter Occur)
If the benchmark reports dropped frames or under 60 fps:
1. Open the generated audit report: `Benchmarks/BenchmarkResults/report_<Profile>_<Timestamp>.txt`.
2. Copy the **`FRAME RATE & PACING TELEMETRY`**, **`PERFORMANCE TELEMETRY SUMMARY`**, and **`MEMORY & PAGING INTEGRITY`** sections.
3. Paste them back to your AI agent with this prompt:
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
[INSERT TARGET HARDWARE HERE: e.g. AMD Ryzen AI 9 HX 370 (4x Zen 5 + 8x Zen 5c, Radeon 890M, 32 GB LPDDR5x)]

---

### Step 1: Architectural Principles & Constraints

1. **Deterministic Filter Pipeline:**
   Every profile must strictly follow this AviSynth+ script structure:
   ```avisynth
   # Hardware Header & MT Configuration
   threads   = <T>
   mem_limit = <M>
   SetMemoryMax(mem_limit)
   SetFilterMTMode("DEFAULT_MT_MODE", 2) # MT_MULTI_INSTANCE required

   # Video source stream
   src = potplayer_source()

   # Load MVTools plugin
   LoadPlugin("mvtools2.dll")

   # 1. Base Motion Super Clip
   super = src.MSuper(levels=<L>, pel=<P>, hpad=<H>, vpad=<V>, sharp=<S>)

   # 2. Motion Vector Search (MAnalyse)
   backward_vec = MAnalyse(super, isb=true,  blksize=<B>, blksizev=<Bv>, search=<Alg>, searchparam=<Rad>, chroma=<C>, ...)
   forward_vec  = MAnalyse(super, isb=false, blksize=<B>, blksizev=<Bv>, search=<Alg>, searchparam=<Rad>, chroma=<C>, ...)

   # 3. Micro-Block Refinement (MRecalculate) - Used in Balanced & MaxQuality
   # Refines coarse vectors down to finer block sizes at object boundaries

   # 4. Motion Interpolation Frame Synthesis (MBlockFps)
   # num=60, den=1 (1080p 24 fps -> 60 fps)
   MBlockFps(src, super, backward_final, forward_final, num=60, den=1, mode=<Mode>, blend=<Blend>, thSCD1=<Th1>, thSCD2=<Th2>)

   # 5. Thread Pool & Lookahead Buffer
   Prefetch(threads, 4)
   ```

2. **Core Topology & Thread Allocation (`threads` & `Prefetch(threads, 4)`):**
   * Never oversaturate CPU cores. The host video player (PotPlayer) requires dedicated CPU headroom for hardware DXVA2/D3D11 decoding, audio decoding, and DWM window presentation.
   * **Homogeneous Cores (e.g. 4C/4T, 8C/16T):**
     * 4-Core CPU: `threads = 2` (Eco), `threads = 3` (Balanced), `threads = 3` or `4` (MaxQuality).
     * 8-Core CPU: `threads = 4` (Eco), `threads = 6` (Balanced), `threads = 6` to `8` (MaxQuality).
   * **Heterogeneous / Hybrid Cores (Intel P+E cores, ARM big.LITTLE / Prime+Gold+Silver, AMD Zen+ZenC):**
     * Restrict `threads` strictly to high-performance cores (P-cores / Gold cores). Never let AviSynth MT worker threads spill onto low-throughput efficiency/silver cores, as the slowest thread stalls the entire frame presentation deadline.
   * Always pass a 4-frame lookahead queue: `Prefetch(threads, 4)`.

3. **Memory Pool Footprint (`SetMemoryMax`):**
   * AviSynth MT spawns `threads` independent filter instances. Keep total memory bounded to prevent Windows Working Set trimming and SSD pagefile swapping:
     * Low-Power / 4-8 GB RAM: `mem_limit = 512` (Eco), `768` (Balanced), `1024` (MaxQuality).
     * Standard Laptop / 16 GB RAM: `mem_limit = 768` (Eco), `1536` (Balanced), `2048` (MaxQuality).
     * High-End / 32+ GB RAM: `mem_limit = 1024` (Eco), `2048` (Balanced), `4096` (MaxQuality).

---

### Step 2: Profile Tier Definitions & Tuning Parameters

#### Tier 1: Eco Profile (`<Platform>-Eco.avs`)
* **Objective:** Ultra-low thermal envelope, battery preservation, zero dropped frames on constrained hardware.
* **MSuper:** `levels=1` (single level; bypasses generating 9 hierarchical pyramid images), `pel=1` (whole-pixel precision), `hpad=0, vpad=0` (eliminates padding cache thrashing), `sharp=0` (bilinear).
* **MAnalyse:** Wide rectangular blocks (`blksize=64, blksizev=32` cuts 1080p block count to ~1,020), `search=2` (hexagonal), `searchparam=1` (radius 1), `chroma=false` (luma-only estimation cuts vector operations by 50%), `levels=1`.
* **Refinement:** None (single-pass analysis).
* **MBlockFps:** `mode=0` (fast block projection), `blend=false` (skips transparency blending), `thSCD1=400, thSCD2=130` (strict scene cut isolation).

#### Tier 2: Balanced Profile (`<Platform>-Balanced.avs`)
* **Objective:** The recommended daily driver. Crisp object edges, zero tearing, fluid 60 fps, modest CPU utilization.
* **MSuper:** `levels=1` (or dynamic), `pel=1` (whole-pixel base), `hpad=0` (or `8`), `vpad=0` (or `8`), `sharp=0` (or `1` bicubic).
* **Coarse Pass:** `blksize=32, blksizev=32` (~2,040 blocks for 1080p), `search=2, searchparam=1` (or `2`), `chroma=false`, `badrange=(-24)`.
* **Refinement (MRecalculate):** Subdivides macro-blocks down to `blksize=16, blksizev=16` around moving edges (`search=2, searchparam=1, chroma=false`).
* **MBlockFps:** `mode=0` (crisp block projection using refined 16x16 grid) or `mode=2` (pixel-flow synthesis if CPU allows), `blend=false` (or `true`), `thSCD1=380, thSCD2=125`.

#### Tier 3: MaxQuality Profile (`<Platform>-MaxQuality.avs`)
* **Objective:** Highest perceptual fidelity, subpixel vector accuracy, seamless occlusion handling for higher-power AC profiles.
* **MSuper:** `pel=2` (half-pixel subpixel interpolation), `hpad=8, vpad=8` (edge protection padding), `sharp=1` (bicubic interpolation).
* **Coarse Pass:** `blksize=32` (or `16`), `search=2, searchparam=2` (radius 2 hexagonal), `chroma=false` (or `true` if CPU has ample vector bandwidth), `badrange=(-24)`.
* **Refinement (MRecalculate):** Refines down to `blksize=16` (or `8`), `searchparam=1`.
* **MBlockFps:** `mode=2` (advanced pixel-flow synthesis with true occlusion masking), `blend=true` (graceful fallback blending across complex motion and scene cuts), `thSCD1=320..350, thSCD2=115..120`.

---

### Step 3: Required Output Format

For the requested platform, output:
1. **Hardware Topology & Budget Analysis:** Summary of core architecture (P/E or big.LITTLE core counts, base/boost clocks, cache hierarchy, thermal limits) justifying the chosen thread counts and parameter choices.
2. **Three Fully Formatted `.avs` Files:**
   * `<Platform>-Eco.avs`
   * `<Platform>-Balanced.avs`
   * `<Platform>-MaxQuality.avs`
   Each file must include a standardized header comment:
   * `# PotPlayer AviSynth 60 fps Interpolation: <Platform> (Profile N: <Tier>)`
   * `# Hardware: <Detailed CPU & iGPU String>`
   * `# Target: <Core Design Goal>`
   * `# Revision: 2.0.0 (<Date>)`

---

### Step 4: Telemetry Diagnosis & Tuning Matrix (When Performance Fails 60 fps)

If the user runs `MvToolsBenchmark-Start.ps1` and returns an audit report showing dropped frames or under 60 fps, diagnose the root cause and adjust parameters strictly according to this matrix:

| Telemetry Symptom in Audit Report | Root Cause Diagnosis | Prescribed Parameter Adjustment |
| :--- | :--- | :--- |
| **Average FPS < 58.0 or Dropped Frames > 0** with high CPU (>85%) | **Compute saturation:** Vector search or pixel synthesis exceeds CPU core capability. | 1. Change `pel=2` $\to$ `pel=1` in `MSuper`.<br>2. Increase block size (e.g. 16x16 $\to$ 32x32, or 32x32 $\to$ 64x32).<br>3. Set `levels=1` in `MSuper` (bypasses 9 pyramid calculations).<br>4. Switch `mode=2` $\to$ `mode=0` in `MBlockFps`. |
| **FPS degrades over time** (starts at 60 fps, drops to 45–50 fps by 60 s) | **Thermal Throttling:** All-core package heat forces CPU clock decay. | 1. **Reduce `threads` by 1 or 2** (e.g. 6 $\to$ 4, or 4 $\to$ 2) to reduce total package power.<br>2. Restrict threads strictly to Performance/Gold cores.<br>3. Set `chroma=false` in `MAnalyse` to cut vector ALU work by 50%. |
| **Severe Microstutter (1% Low < 45 fps)** while Average FPS is near 60 | **Thread Scheduling Contention or Jitter.** | 1. Ensure `Prefetch(threads, 4)` lookahead queue is set.<br>2. If `threads` $\ge$ total physical cores, decrement `threads` by 1 to guarantee CPU headroom for DXVA decoding and DWM presentation. |
| **"WARNING: Active pagefile disk swapping detected"** | **Memory Contention / Trimming:** `SetMemoryMax` is exceeding physical budget or starving Windows. | 1. Reduce `SetMemoryMax(mem_limit)` (e.g. 2048 $\to$ 1024, or 1024 $\to$ 768).<br>2. In 4K or `pel=2` modes, check working set and reduce `threads`. |
| **1–2 dropped frames with Render Latency 0.00 ms** | **VSync Phase Drift (Display Refresh Rate Artifact).** | If the audit report notes *"Non-integer display refresh rate detected... caused by VSync phase drift"*, **do NOT modify the script**. This is a physical display scanout artifact (~59.86 Hz panel clock), not a computational bottleneck. |
````
