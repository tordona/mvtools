# Quick Start Guide: 60fps Playback in Daum PotPlayer

> **Achieve real-time 24fps → 60fps video motion interpolation in Daum PotPlayer on Windows 11 on ARM64 and x86-64 with zero frame drops.**

Choose between the **Automated 1-Click PowerShell Setup** (recommended) or the **Manual Step-by-Step Setup** for your architecture.

---

## Method 1: Automated 1-Click Setup (Recommended)

An automated setup script is provided in the repository to detect your hardware, acquire dependencies, and configure PotPlayer in under 60 seconds.

### What the Automated Script Does:
1. Detects system architecture (ARM64 vs. x86-64) and hardware topology.
2. Installs Microsoft Visual C++ 2015–2022 Redistributable if missing.
3. Downloads and silently installs official Daum PotPlayer 64-bit if not present.
4. Deploys the native `AviSynth.dll` and `mvtools2.dll` directly to PotPlayer.
5. Deploys architecture-filtered profiles (**Snapdragon-only** on ARM64; **AMD/Intel-only** on x86-64).
6. Auto-configures D3D11 Copy-Back hardware decoding, D3D11 Video Renderer, and activates the optimal **Balanced** profile.

### How to Run:
Open PowerShell on your target machine and run:

```powershell
# Clone or download the repository, then run from the repository root:
.\Install-MvToolsPotPlayer.ps1 -AutoInstall -Launch
```

> [!TIP]
> **Unrecognized Hardware?**  
> If the installer detects an unrecognized CPU or GPU model, it automatically pre-configures a functional Generic Balanced profile and offers to copy a pre-filled, hardware-tailored prompt to your clipboard for instant tuning in Google Antigravity, Gemini, ChatGPT, Claude, or Cursor.

---

## Method 2: Manual Setup for Qualcomm Snapdragon (ARM64)

Follow these steps for Snapdragon X Elite / Plus, 8cx Gen 1–3, 850, and 7c Gen 2 devices.

### Prerequisites (ARM64)
1. **Microsoft Visual C++ 2015–2022 ARM64 Redistributable:**  
   [Download Official vc_redist.arm64.exe](https://aka.ms/vs/17/release/vc_redist.arm64.exe) *(Prevents "AviSynth.dll not found" error)*.
2. **Daum PotPlayer 64-bit (ARM64):**  
   [Official Website (potplayer.tv)](https://potplayer.tv/) or [Direct ARM64 Installer](https://t1.daumcdn.net/potplayer/PotPlayer/Version/Latest/PotPlayerSetupARM64.exe). Default path: `C:\Program Files\DAUM\PotPlayer\`.
3. **AviSynth+ ARM64 Core (`AviSynth.dll`):**  
   Download [AviSynth+ Releases](https://github.com/AviSynth/AviSynthPlus/releases) (`files_only.7z` or `.zip`). Extract **`arm64\bin\AviSynth.dll`** directly into:
   ```text
   C:\Program Files\DAUM\PotPlayer\AviSynth.dll
   ```

### Step 1: Place MVTools2 Binaries (ARM64)
1. Navigate to the [Latest MVTools2 Release](https://github.com/tordona/mvtools/releases/latest).
2. Download **`mvtools2-arm64-v...zip`** under Assets.
3. Extract **`mvtools2.dll`** (and optionally `mvtools2_d3d12.dll` for GPU testing) directly into:
   ```text
   C:\Program Files\DAUM\PotPlayer\
   ```

### Step 2: Configure Hardware Decoding (Adreno VPU)
1. Open PotPlayer and press **`F5`** to open **Preferences**.
2. Navigate to **Filter Control** → **Video Decoder** → click **Built-in Video Codec/DXVA Settings**.
3. Check **Use DXVA**.
4. Under **Hardware acceleration (DXVA) settings**:
   * Set **DXVA2 Copy-Back:** to **`D3D11`** or **`Auto (Recommended)`**.
   * Set **Resolution limit:** to **`Always Use`**.
   * Enable hardware acceleration checkboxes for **AV1** *(Snapdragon X)*, **H.265/HEVC**, **H.264/AVC1**, and **VP9**.
5. Click **Apply**.

### Step 3: Configure Direct3D 11 Video Renderer
1. In Preferences (**`F5`**), navigate to **Video**.
2. Set **Video Renderer** to **`Direct3D 11 Video Renderer`**.
3. Under D3D11 settings, set **Present:** to **`Auto`** or **`Flip Exhaustive`**.
4. Click **Apply**.

### Step 4: Enable AviSynth & Apply Snapdragon Profile
1. In Preferences (**`F5`**), navigate to **Video** → **AviSynth**.
2. Check the box **AviSynth**.
3. Copy and paste the profile for your chipset from the [Snapdragon Profile Library](profiles/README.md) or use this universal starter script:

```avisynth
# ==============================================================================
# MVTools2 60fps Balanced Script (Qualcomm Snapdragon ARM64)
# ==============================================================================
USE_GPU = false

plugin_file = USE_GPU ? "mvtools2_d3d12.dll" : "mvtools2.dll"
threads     = USE_GPU ? 4 : 6
mem_limit   = USE_GPU ? 1536 : 2048

SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

potplayer_source()

LoadPlugin(plugin_file)

super = MSuper(pel=1, hpad=8, vpad=8, sharp=1)

backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))

backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

MFlowFps(super, backward_fine, forward_fine, num=60, den=1, mask=2, ml=100.0, blend=false)

Prefetch(threads, 4)
```

4. Click **Apply** and **OK**.

---

## Method 3: Manual Setup for x86-64 (AMD Ryzen & Intel Core)

Follow these steps for standard x86-64 PCs and laptops.

### Prerequisites (x86-64)
1. **Microsoft Visual C++ 2015–2022 x64 Redistributable:**  
   [Download Official vc_redist.x64.exe](https://aka.ms/vs/17/release/vc_redist.x64.exe).
2. **Daum PotPlayer 64-bit (x64):**  
   [Official Website (potplayer.tv)](https://potplayer.tv/) or [Direct 64-bit Installer](https://t1.daumcdn.net/potplayer/PotPlayer/Version/Latest/PotPlayerSetup64.exe). Default path: `C:\Program Files\DAUM\PotPlayer\`.
3. **AviSynth+ x64 Core (`AviSynth.dll`):**  
   Download [AviSynth+ Releases](https://github.com/AviSynth/AviSynthPlus/releases) (`files_only.7z` or `.zip`). Extract **`x64\AviSynth.dll`** directly into:
   ```text
   C:\Program Files\DAUM\PotPlayer\AviSynth.dll
   ```

### Step 1: Place MVTools2 Binaries (x86-64)
1. Navigate to the [Latest MVTools2 Release](https://github.com/tordona/mvtools/releases/latest).
2. Download **`mvtools2-x64-v...zip`** under Assets.
3. Extract **`mvtools2.dll`** directly into:
   ```text
   C:\Program Files\DAUM\PotPlayer\
   ```

### Step 2: Configure Hardware Decoding & Video Renderer
1. Open PotPlayer and press **`F5`**.
2. **Video Decoder:** Navigate to **Filter Control** → **Video Decoder** → **Built-in Video Codec/DXVA Settings**:
   * Check **Use DXVA**.
   * Set **DXVA2 Copy-Back:** to **`D3D11`** or **`Auto (Recommended)`**.
   * Enable hardware acceleration for **H.265/HEVC**, **H.264/AVC1**, **VP9**, and **AV1** (if supported by Intel Arc/Iris or AMD RDNA).
3. **Video Renderer:** Navigate to **Video** → set **Video Renderer** to **`Direct3D 11 Video Renderer`**.

### Step 3: Enable AviSynth & Apply x86-64 Profile
1. Navigate to **Video** → **AviSynth** and check **AviSynth**.
2. Paste the script for your CPU tier from the [x86-64 Profile Section](profiles/README.md#part-ii-x86-64-hardware-profiles) or use this universal x86-64 script:

```avisynth
# ==============================================================================
# MVTools2 60fps Balanced Script (x86-64 AMD Ryzen / Intel Core)
# ==============================================================================
threads   = 4
mem_limit = 1024

SetMemoryMax(mem_limit)
SetFilterMTMode("DEFAULT_MT_MODE", 2)

potplayer_source()

LoadPlugin("mvtools2.dll")

super = MSuper(pel=1, hpad=8, vpad=8, sharp=1)

backward_coarse = MAnalyse(super, isb=true,  blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))
forward_coarse  = MAnalyse(super, isb=false, blksize=32, blksizev=32, search=2, searchparam=2, chroma=false, plevel=0, badrange=(-24))

backward_fine = MRecalculate(super, backward_coarse, blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)
forward_fine  = MRecalculate(super, forward_coarse,  blksize=16, blksizev=16, search=2, searchparam=1, chroma=false)

MFlowFps(super, backward_fine, forward_fine, num=60, den=1, mask=2, ml=100.0, blend=false)

Prefetch(threads, 4)
```

3. Click **Apply** and **OK**.

---

## Verification & Diagnostics

1. Play any **23.976 fps**, **24 fps**, or **29.97 fps** video file in PotPlayer.
2. During playback, press **`Tab`** on your keyboard to toggle the on-screen display (OSD).
3. Verify:
   * **Input:** `23.976 fps` (or source framerate)
   * **Output:** `59.940 fps` or `60.000 fps`
   * **Frame Drops:** `0`

---

## Troubleshooting & FAQ

| Symptom | Probable Cause | Recommended Resolution |
| :--- | :--- | :--- |
| **"AviSynth.dll not found" error** | Missing Visual C++ runtime or missing `AviSynth.dll`. | 1. Install [Visual C++ ARM64](https://aka.ms/vs/17/release/vc_redist.arm64.exe) (or [Visual C++ x64](https://aka.ms/vs/17/release/vc_redist.x64.exe)).<br>2. Ensure `AviSynth.dll` is placed in `C:\Program Files\DAUM\PotPlayer\`. |
| **"LoadPlugin: unable to find mvtools2.dll"** | `mvtools2.dll` is not in PotPlayer's working directory. | Verify `mvtools2.dll` is placed in `C:\Program Files\DAUM\PotPlayer\`, or specify the absolute path: `LoadPlugin("C:\Program Files\DAUM\PotPlayer\mvtools2.dll")`. |
| **Audio out of sync or stuttering** | Video decoder is set to software decode, saturating CPU. | Verify that **DXVA2 Copy-Back (D3D11)** is active in Video Decoder settings. |
| **Occasional micro-stutters** | System thermal throttle or high resolution load. | Switch from `MaxQuality` to `Balanced` or `Eco` profile in the [Profile Library](profiles/README.md). |
| **Direct3D 12 GPU offload testing (ARM64)** | Wanting to benchmark experimental DirectCompute GPU mode. | Set `USE_GPU = true` at the top of the Snapdragon script and ensure `mvtools2_d3d12.dll` is in `C:\Program Files\DAUM\PotPlayer\`. |
