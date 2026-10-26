# Quick Start Guide: 60fps Playback in Daum PotPlayer

> **Achieve real-time 24fps → 60fps video motion interpolation on Windows 11 on ARM64 with zero frame drops.**

This step-by-step guide walks you through setting up **Daum PotPlayer**, **AviSynth+**, and **MVTools2** on your Qualcomm Snapdragon device.

---

## Prerequisites & Required Runtimes

Before configuring PotPlayer, install the necessary runtimes and core binaries.

### 1. Microsoft Visual C++ 2015–2022 Redistributable (ARM64)
Both `AviSynth.dll` and `mvtools2.dll` depend on the Microsoft Visual C++ ARM64 runtime (`msvcp140.dll`, `vcruntime140.dll`, `vcruntime140_1.dll`). Without this, Windows fails to dynamically link the libraries, and PotPlayer will report *"AviSynth.dll not found"*.
* **Download:** [**Microsoft Visual C++ 2015–2022 ARM64 Redistributable (Official Microsoft Link)**](https://aka.ms/vs/17/release/vc_redist.arm64.exe)
* Run the installer and restart PotPlayer if it was already open.

### 2. Daum PotPlayer (64-bit ARM64)
* **Download:** [**Daum PotPlayer 64-bit**](https://potplayer.daum.net/)
* Install using default settings. The default installation path is:
  ```text
  C:\Program Files\DAUM\PotPlayer\
  ```

### 3. AviSynth+ ARM64 Core (`AviSynth.dll`)
PotPlayer requires the native 64-bit ARM64 `AviSynth.dll` engine to process video filter scripts.
1. Download the latest release from the [**AviSynth+ GitHub Releases**](https://github.com/AviSynth/AviSynthPlus/releases) (e.g. `AviSynthPlus_..._files_only.7z` or `.zip`).
2. Open the archive, locate **`arm64\bin\AviSynth.dll`**, and copy it directly into your PotPlayer installation folder:
   ```text
   C:\Program Files\DAUM\PotPlayer\AviSynth.dll
   ```

---

## Step 1: Download & Place MVTools2 Binaries

1. Navigate to the [**MVTools2 GitHub Releases**](https://github.com/tordona/mvtools/releases/latest).
2. Under **Assets**, download the ARM64 release archive:  
   **`mvtools2-arm64-v...zip`**
3. Open the downloaded `.zip` archive. You will see:
   * **`mvtools2.dll`** — *Production Reference Engine* (pure ARM64 NEON SIMD vector acceleration).
   * **`mvtools2_d3d12.dll`** — *Experimental Direct3D 12 GPU DirectCompute Engine*.
4. Copy **`mvtools2.dll`** (and optionally `mvtools2_d3d12.dll` if testing GPU offload) directly into your PotPlayer folder:
   ```text
   C:\Program Files\DAUM\PotPlayer\
   ```
   *(Windows will display an Administrator permission prompt: click **Continue** to paste into Program Files).*

> [!TIP]
> **Why place DLLs directly in PotPlayer's directory?**  
> PotPlayer runs from `C:\Program Files\DAUM\PotPlayer\`. Placing both `AviSynth.dll` and `mvtools2.dll` here ensures that `LoadPlugin("mvtools2.dll")` resolves immediately in PotPlayer's working directory with zero path errors.

---

## Step 2: Configure Hardware Video Decoding (D3D11 Copy-Back)

By default, software decoding consumes substantial CPU time on 4K/1080p HEVC/AV1 streams. Configuring **D3D11 Copy-Back** shifts video decoding entirely to the Qualcomm Adreno Video Processing Unit (VPU), freeing 100% of Oryon / Kryo CPU capacity for motion estimation.

1. Open **PotPlayer** and press **`F5`** to open **Preferences**.
2. In the left panel, navigate to:  
   **Filter Control** → **Video Decoder**.
3. Click the **Built-in Video Codec/DXVA Settings** button.
4. Configure the following options:
   * Check **Use DXVA**.
   * Under **Hardware acceleration (DXVA) settings**:
     * Set **DXVA2 Copy-Back:** to **`D3D11`** or **`Auto (Recommended)`**.
     * Set **Resolution limit:** to **`Always Use`**.
     * Ensure hardware acceleration checkboxes are enabled for **AV1** *(Snapdragon X)*, **H.265/HEVC**, **H.264/AVC1**, and **VP9**.
5. Click **Apply**.

> [!IMPORTANT]
> **Why Copy-Back is Required:**  
> AviSynth filters process raw uncompressed frame buffers via `potplayer_source()`. Standard native DXVA keeps surfaces locked inside the GPU presentation pipeline. **D3D11 Copy-Back** decodes video inside the Adreno VPU and maps uncompressed frames directly into shared memory with zero CPU overhead.

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
   **Video** → **AviSynth**.
2. Check the box **AviSynth**.
3. Select your hardware platform from the [**AviSynth Profile Library**](profiles/README.md) or use this universal **Balanced** starter script:

```avisynth
# ==============================================================================
# MVTools2 60fps Balanced Interpolation Script (Snapdragon ARM64)
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

4. Paste the script into the text area in the AviSynth settings page.
5. Click **Apply** and **OK**.

---

## Step 5: Verification & Playback Diagnostics

1. Open any **23.976 fps**, **24 fps**, or **29.97 fps** video file in PotPlayer.
2. During playback, press **`Tab`** on your keyboard to toggle the on-screen display (OSD).
3. Verify the following parameters:
   * **Input:** `23.976 fps` (or source file framerate)
   * **Output:** `59.940 fps` or `60.000 fps`
   * **Frame Drops:** `0`
4. If playback is completely smooth and frame drops stay at 0, your installation is complete!

---

## Troubleshooting & Best Practices

| Symptom | Probable Cause | Recommended Resolution |
| :--- | :--- | :--- |
| **"AviSynth.dll not found" error** | Missing Visual C++ ARM64 runtime or missing `AviSynth.dll`. | 1. Install [Visual C++ 2015–2022 ARM64 Redistributable](https://aka.ms/vs/17/release/vc_redist.arm64.exe).<br>2. Ensure `arm64\bin\AviSynth.dll` is placed in `C:\Program Files\DAUM\PotPlayer\`. |
| **"LoadPlugin: unable to find mvtools2.dll"** | `mvtools2.dll` is not in PotPlayer's working directory. | Verify `mvtools2.dll` is placed in `C:\Program Files\DAUM\PotPlayer\`, or specify the absolute path: `LoadPlugin("C:\Program Files\DAUM\PotPlayer\mvtools2.dll")`. |
| **Audio out of sync or stuttering** | Video decoder is set to software decode, saturating CPU. | Re-check **Step 2** and verify that **DXVA2 Copy-Back (D3D11)** is active. |
| **Occasional micro-stutters** | System thermal throttle or high resolution load. | Switch from `MaxQuality` to `Balanced` or `Eco` profile in the [Profile Library](profiles/README.md). |
| **Direct3D 12 GPU offload testing** | Wanting to benchmark experimental DirectCompute GPU mode. | Set `USE_GPU = true` at the top of the `.avs` script and ensure `mvtools2_d3d12.dll` is in `C:\Program Files\DAUM\PotPlayer\`. |
