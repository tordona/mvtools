# Quick Start Guide: 60fps Playback in Daum PotPlayer

> **Achieve real-time 24fps $\to$ 60fps video motion interpolation on Windows on ARM64 and x64 with zero frame drops.**

This guide walks you through setting up **Daum PotPlayer**, **AviSynth+**, and **MVTools2** in under 3 minutes.

---

## Prerequisites

1. **Operating System:** Windows 11 on ARM64 (Snapdragon X Elite, X Plus, 8cx, 850, 7c) or Windows 10/11 x64 (Intel Core / AMD Ryzen).
2. **Media Player:** [Daum PotPlayer 64-bit](https://potplayer.daum.net/) (ARM64 or x64).
3. **AviSynth Engine:** [AviSynth+ 64-bit](https://github.com/AviSynth/AviSynthPlus/releases) installed.

---

## Step 1: Download & Install MVTools2 Binaries

1. Navigate to the [**Latest GitHub Release**](https://github.com/tordona/mvtools/releases/latest).
2. Download the binary package for your architecture:
   * **Windows on ARM64:** Download `mvtools2-arm64-v...zip` containing:
     * `mvtools2.dll` — *Production Reference Engine* (pure ARM64 NEON SIMD).
     * `mvtools2_d3d12.dll` — *Experimental Direct3D 12 DirectCompute GPU Engine*.
   * **Windows x64:** Download `mvtools2-x64-v...zip`.
3. Extract the DLL file into your AviSynth+ 64-bit autoload plugins folder:
   ```text
   C:\Program Files\AviSynth+\plugins64\
   ```
   *(Or keep it in a known folder such as `C:\Tools\mvtools2.dll` to load explicitly via `LoadPlugin`)*.

---

## Step 2: Configure Hardware Video Decoding (D3D11 Copy-Back)

By default, software decoding consumes substantial CPU time on 4K/1080p HEVC/AV1 streams. Configuring **D3D11 Copy-Back** shifts video decoding entirely to the Qualcomm Adreno Video Processing Unit (VPU) or Intel/AMD iGPU, freeing 100% of CPU capacity for motion estimation.

1. Open **PotPlayer** and press **`F5`** to open **Preferences**.
2. In the left panel, navigate to:  
   **Filter Control** $\to$ **Video Decoder**.
3. Click the **Built-in Video Codec/DXVA Settings** button.
4. Configure the following:
   * Check **Use DXVA**.
   * Under **Hardware acceleration (DXVA) settings**:
     * Set **DXVA2 Copy-Back:** to **`D3D11`** or **`Auto (Recommended)`**.
     * Set **Resolution limit:** to **`Always Use`**.
     * Ensure hardware acceleration checkboxes are enabled for **AV1**, **H.265/HEVC**, **H.264/AVC1**, and **VP9**.
5. Click **Apply**.

> [!IMPORTANT]
> **Why Copy-Back is Required:**  
> AviSynth filters process raw uncompressed frame buffers via `potplayer_source()`. Standard native DXVA keeps surfaces locked inside the GPU presentation pipeline. **D3D11 Copy-Back** decodes video inside the hardware VPU and maps uncompressed frames directly into shared memory with zero CPU overhead.

---

## Step 3: Configure Direct3D 11 Video Renderer

1. In PotPlayer Preferences (**`F5`**), navigate to:  
   **Video**.
2. Set **Video Renderer** to **`Direct3D 11 Video Renderer`** (or *Built-in Direct3D 11 Video Renderer*).
3. Under **D3D11 Video Renderer settings**:
   * Set **Present:** to **`Auto`** or **`Flip Exhaustive`**.
4. Click **Apply**.

---

## Step 4: Enable AviSynth & Load Profile

1. In PotPlayer Preferences (**`F5`**), navigate to:  
   **Video** $\to$ **AviSynth**.
2. Check the box **AviSynth**.
3. Select your hardware platform from the [**AviSynth Profile Library**](profiles/README.md) or use this universal **Balanced** starter script:

```avisynth
# ==============================================================================
# MVTools2 60fps Balanced Interpolation Script
# ==============================================================================
USE_GPU = false

plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
threads     = USE_GPU ? 4 : 6
mem_limit   = USE_GPU ? 1536 : 2048

SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

potplayer_source()

LoadPlugin(plugin_file)

# 1. Single-level super clip (conserves memory bandwidth)
super = MSuper(pel=1, hpad=8, vpad=8, sharp=1)

# 2. Coarse global motion vector estimation
backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))

# 3. Fine motion refinement
backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

# 4. Pixel synthesis and interpolation to 60fps
MFlowFps(super, backward_fine, forward_fine, num=60, den=1, mask=2, ml=100.0, blend=false)

Prefetch(threads, 4)
```

4. Paste the script into the large text area in the AviSynth settings page.
5. Click **Apply** and **OK**.

---

## Step 5: Verification & Playback Diagnostics

1. Open any **23.976 fps**, **24 fps**, or **29.97 fps** video file in PotPlayer.
2. During playback, press **`Tab`** on your keyboard to toggle the on-screen display (OSD).
3. Verify the following parameters:
   * **Input:** `... fps` (Original file framerate)
   * **Output:** `59.940 fps` or `60.000 fps`
   * **Frame Drops:** `0`
4. If playback is completely smooth and frame drops stay at 0, your installation is complete!

---

## Troubleshooting & Best Practices

| Symptom | Probable Cause | Recommended Resolution |
| :--- | :--- | :--- |
| **Audio out of sync or stuttering** | Video decoder is set to software decode, saturating CPU. | Re-check **Step 2** and verify that **DXVA2 Copy-Back (D3D11)** is active. |
| **Occasional micro-stutters** | System thermal throttle or high resolution load. | Switch from `MaxQuality` to `Balanced` or `Eco` profile in [Profile Library](profiles/README.md). |
| **Direct3D 12 GPU offload testing** | Wanting to benchmark experimental DirectCompute GPU mode. | Set `USE_GPU = true` at the top of the `.avs` script and place `mvtools2_d3d12.dll` in your plugin path. |
| **AviSynth failed to load plugin** | Missing Visual C++ redistributable or path mismatch. | Ensure the latest Microsoft Visual C++ ARM64/x64 Redistributable is installed and supply the full path in `LoadPlugin("C:\\Path\\To\\mvtools2.dll")`. |
