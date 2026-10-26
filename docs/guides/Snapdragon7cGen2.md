# PotPlayer & AviSynth 60fps Configuration Guide: Snapdragon 7c Gen 2

> **Hardware Target:** Qualcomm Snapdragon 7c Gen 2 (SC7180)  
> **Integrated GPU:** Qualcomm Adreno 618  
> **Test Device:** Samsung Galaxy Book Go (14", Fanless Passive 5W Chassis)  
> **CPU Topology:** 2x Kryo 468 Gold (Cortex-A76 @ 2.55 GHz) + 6x Kryo 468 Silver (Cortex-A55 @ 1.80 GHz)

---

## 1. Overview & Thermal Strategy

The **Samsung Galaxy Book Go** is a lightweight, completely fanless Windows on ARM64 laptop with a nominal package thermal design power (TDP) of **5 Watts**. 

Under full 1080p video playback, software decoding alone on the 2 Gold cores can consume up to 2.5–3.0W. If MVTools full-resolution 1080p motion search is added, total system power spikes past 7W, quickly causing **thermal throttling down to approx. 1.2 GHz** within 10–20 seconds and dropping frame rates from 60 fps to 8–12 fps.

To achieve continuous, sustained 60 fps without thermal throttling:
1. **Adreno 618 Hardware Decoding:** Offload H.264/HEVC decode entirely to the Adreno VPU via D3D11 / DXVA2 Copy-Back (reducing CPU decode load to 0%).
2. **Dynamic 0.5x Proxy Analysis (`MScaleVect`):** Perform motion estimation on an aspect-ratio-aware 0.5× proxy plane (cutting 75% of pixel comparisons and DRAM bandwidth), then scale vectors 2× up to native source dimensions.
3. **Native 1080p Warp (`MBlockFps mode=0`):** Synthesize new frames directly from the uncompressed 1080p source clip, ensuring **zero loss of spatial resolution or sharpness**.
4. **Strict Core Pinning (`Prefetch(2)`):** Limit worker threads to 2 so execution stays strictly on the high-performance Kryo 468 Gold cores, completely avoiding stalls from the slow in-order Cortex-A55 Silver cores.

---

## 2. Step-by-Step PotPlayer Setup

### Step 1: Hardware Video Decoder (Adreno 618 VPU)
1. Open **PotPlayer** and press **`F5`** for **Preferences**.
2. Navigate to **Filter Control** → **Video Decoder**.
3. Click the **Built-in Video Codec/DXVA Settings** button.
4. Check **Use DXVA**.
5. Under **Hardware acceleration (DXVA) settings**:
   - Check **Prioritize D3D11 DXVA** *(Recommended)* or set **DXVA2 Copy-Back:** to **`Auto (Recommended)`** / **`Always Use`**.
   - Set **Resolution limit:** to **`Always Use`**.
   - Confirm hardware acceleration is active for **H.264/AVC1**, **H.265/HEVC**, and **VP9**.
6. Click **Apply**.

---

### Step 2: Video Renderer (Direct3D 11 Pipeline)
1. In **Preferences (`F5`)**, navigate to the main **Video** page *(do NOT use the sub-page Video → Resize)*.
2. Set **Video Renderer** to:
   - **`Built-in Direct3D 11 Video Renderer`** *(Recommended)*
3. **GPU Scaling Algorithm:**
   - Under **Video Output Settings**, directly below **Direct3D Presentation**, locate the **`Resizer:`** dropdown.
   - Select **`Shader Bilinear`** *(lowest GPU power / battery saver)* or **`Shader Bicubic(A = -0.6)`** *(crisp 1080p presentation)*.  
   *(GPU shader units execute scaling operations without consuming CPU cycles).*
4. Click **Apply**.

---

### Step 3: Colorspace Pass-Through (Zero CPU YUV Conversion)
1. In **Preferences (`F5`)**, navigate to:  
   **Video** → **Colorspaces**.
2. Under **Supported Colorspaces / YCbCr <-> RGB conversion**, ensure **Output color space** is set to **`Auto (Recommended)`** (or native planar YUV: **`NV12`** / **`YV12`**). Do **NOT** select `RGB 32` or `ARGB 32`.
3. Verify that **High quality YUY2/RGB24/32 conversion** is **Unchecked** *(prevents software color space conversion overhead on Gold cores)*.
4. In the format list, ensure native planar YUV formats are prioritized:
   - **`NV12`**
   - **`YV12`**
5. Click **Apply**.

---

### Step 4: Load Snapdragon 7c Gen 2 AviSynth Profile
1. In **Preferences (`F5`)**, navigate to **Video** → **AviSynth**.
2. Check **Enable AviSynth processing**.
3. Check **Add "potplayer_source()"**.
4. Check **Buffer (back/ahead)** and configure buffer limits:
   - **Buffer Back** (first box): Set to **`10`** to **`12`** frames.
   - **Buffer Ahead** (second box): Set to **`16`** to **`20`** frames.
5. Under **Load script:**, browse and select your preferred Snapdragon 7c Gen 2 profile:
   - [**`Snapdragon-7cGen2-Balanced.avs`**](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-7cGen2-Balanced.avs) *(Recommended for daily 60fps watching)*
   - [**`Snapdragon-7cGen2-Eco.avs`**](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-7cGen2-Eco.avs) *(For whisper-cool, ultra-long battery life, 3.0W)*
   - [**`Snapdragon-7cGen2-MaxQuality.avs`**](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-7cGen2-MaxQuality.avs) *(Hierarchical pyramid search for fast action scenes)*
6. Click **Apply** and **OK**.

---

## 3. Profiles Comparison for Galaxy Book Go

| Feature | Eco Profile | Balanced Profile *(Recommended)* | MaxQuality Profile |
| :--- | :--- | :--- | :--- |
| **Search Block Size** | 32×16 at 540p (64×32 at 1080p) | 16×16 at 540p (32×32 at 1080p) | 16×16 at 540p (32×32 at 1080p) |
| **Total Blocks** | 510 blocks | 2,040 blocks | 2,040 blocks |
| **Search Algorithm** | Hexagonal (radius 1) | Hexagonal (radius 1) | Hexagonal (radius 2) |
| **Pyramid Levels** | `levels=1` (Level 0 only) | `levels=1` (Level 0 only) | `levels=1` (Level 0 only) |
| **Outlier Filter** | Off | Off | `badrange=(-24)` |
| **Frame Synthesis** | Native 1080p `mode=0` | Native 1080p `mode=0` | Native 1080p `mode=0` |
| **Worker Threads** | `Prefetch(2, 4)` | `Prefetch(2, 4)` | `Prefetch(2, 4)` |
| **Memory Limit** | 384 MB | 512 MB | 512 MB |
| **Package Power** | **2.8W – 3.2W** | **3.4W – 3.8W** | **4.2W – 4.7W** |
| **Thermal Headroom** | Maximum (>15°C margin) | High (>10°C margin) | Sustained at 5W ceiling |

---

## 4. Why `Prefetch(2)` is Critical on Snapdragon 7c Gen 2

The Snapdragon 7c Gen 2 features an asymmetric **2+6 big.LITTLE** topology:
- **2x Kryo 468 Gold:** Based on ARM Cortex-A76 (out-of-order execution, wide decode, high IPC).
- **6x Kryo 468 Silver:** Based on ARM Cortex-A55 (in-order execution, narrow pipeline, approx. 25–30% of the IPC of A76).

> [!CAUTION]
> **Never set `Prefetch` ≥ 3 on this chip.**
> When AviSynth spawns more than 2 worker threads, Windows thread scheduler places worker threads onto the Cortex-A55 Silver cores. Because an A55 core takes 3.5× longer to complete a frame than an A76 core, the lookahead buffer stalls waiting for the slow thread, dropping the display output from 60 fps to approx. 15 fps.

---

## 5. Summary Configuration Checklist

| Setting | Location in Preferences (`F5`) | Recommended Value |
| :--- | :--- | :--- |
| **Hardware Video Decoding** | Filter Control → Video Decoder → Built-in Video Codec/DXVA Settings | `Use DXVA` checked |
| **Hardware Decode Mode** | Filter Control → Video Decoder → Built-in Video Codec/DXVA Settings | `Prioritize D3D11 DXVA` or `DXVA2 Copy-Back` |
| **Codecs Accelerated** | Filter Control → Video Decoder → Built-in Video Codec/DXVA Settings | `H.264/AVC1`, `H.265/HEVC`, `VP9` |
| **Video Renderer** | Video | `Built-in Direct3D 11 Video Renderer` |
| **Output Colorspace** | Video → Colorspaces | `Auto (Recommended)` / native `NV12` / `YV12` |
| **AviSynth Processing** | Video → AviSynth | `Enable AviSynth processing` checked |
| **Buffer (back/ahead)** | Video → AviSynth | `10-12` (Back) / `16-20` (Ahead) |
| **AviSynth Script** | Video → AviSynth | [`Snapdragon-7cGen2-Balanced.avs`](https://raw.githubusercontent.com/tordona/mvtools/mvtools_d3d12/AviSynth/Snapdragon-7cGen2-Balanced.avs) |

---

## 6. Verification & OSD Diagnostic

To confirm that the Adreno 618 hardware decoder and 60fps AviSynth processing are active during playback:

1. Play a video in PotPlayer.
2. Press **`Tab`** to toggle the On-Screen Display (OSD).
3. Confirm the following real-time metrics:
   - **Video Codec:** Displays **`D3D11 Native/CopyBack`** or **`DXVA2`** *(confirming GPU decode)*.
   - **Video Output:** Shows **`Direct3D 11 Video Renderer`**.
   - **Frame Rate:** Displays **`XX fps -> 60.00 fps`**.
   - **CPU Usage:** Stays stably low on the 2 Kryo 468 Gold cores.
