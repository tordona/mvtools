# Big Buck Bunny Motion Interpolation Stress Test Guide

## 1. Reference Video Metadata

* **File Name:** `bbb_sunflower_1080p_30fps_normal.mp4`
* **Local Location:** `D:\devai\benchmarks\bbb_sunflower_1080p_30fps_normal.mp4`
* **Resolution:** 1080p (`1920x1080`)
* **Frame Rate:** `30 fps` progressive (`29.970 / 30.000 fps`)
* **Total Duration:** `10:34` (`634.60 s`, `19,038` frames)
* **Pixel Format:** YUV420P 8-bit (`yuv420p`)
* **SHA-256 Hash:** `ae51005850b0ff757fe60c3dd7a12d754d3cd2397d87d939b55235e457f97658`
* **Upstream Source:** [Blender Foundation BBB Sunflower Edition](https://download.blender.org/demo/movies/BBB/)

---

## 2. Architectural Comparison: Big Buck Bunny vs Tears of Steel

| Property | Tears of Steel (`tears_of_steel_1080p.mov`) | Big Buck Bunny (`bbb_sunflower_1080p_30fps_normal.mp4`) |
| :--- | :--- | :--- |
| **Motion Blur Profile** | Heavy `180°` cinematic optical shutter blur. Fast-moving objects are blurred before capture. | **Zero optical shutter blur.** 3D CGI engine renders razor-sharp boundaries at all speeds. |
| **Edge Frequencies** | Soft textures, low-contrast grading, and shallow depth-of-field background bokeh. | **High spatial frequencies.** Sharp fur outlines, high-contrast tree bark, and thin grass blades. |
| **Tearing Visibility** | Masked by optical blur and soft gradient matching in `MAnalyse`. | **Instantly visible.** Vector mismatches produce sharp, jagged block tears and stepped shears. |
| **Primary Stress Target** | Low-contrast SAD matching, continuous camera drift, real-world noise. | **Block shearing, boundary occlusion, subpixel phase jitter, and search radius limits.** |

---

## 3. High-Stress Test Scenes

| Index | Scene Identifier | Timestamp Range | Frame Range (30 fps) | Primary Artifact Stressed |
| :---: | :--- | :---: | :---: | :--- |
| **1** | **Fast Lateral Tree Pan** | `05:32 – 05:38` | `9,960 – 10,140` | **Horizontal Tearing & Block Shearing** |
| **2** | **Flying Squirrel Aerial Glide** | `07:20 – 07:26` | `13,200 – 13,380` | **Occlusion Halos & Silhouette Warping** |
| **3** | **Bow & Pinecone Launch** | `08:22 – 08:28` | `15,060 – 15,240` | **Search Window Overflow & Macroblock Breakdown** |
| **4** | **Butterfly Flutter & Fur Edges** | `02:15 – 02:21` | `4,050 – 4,230` | **Subpixel Jitter & Non-Rigid Smearing** |
| **5** | **Rodent Scramble & Direction Reversal** | `03:30 – 03:36` | `6,300 – 6,480` | **Vector Incoherence & Acceleration Divergence** |

---

## 4. Scene Details & Failure Mechanisms

### Scene 1: Fast Lateral Tree Pan (`05:32 – 05:38`, Frames `9,960 – 10,140`)
* **Motion Characteristics:** Rapid horizontal camera tracking across vertical tree trunks, rough bark, and tall grass blades.
* **Failure Mechanism:** The camera translates laterally at `20 px` to `45 px` per frame across high-contrast, vertical boundaries.
* **Artifact Manifestation:** If adjacent block rows assign slightly divergent motion vectors or if multi-threaded row slicing (`MTSlicer`) creates boundary desynchronization, vertical tree trunks visibly shear into horizontal slices (tearing).

### Scene 2: Flying Squirrel Aerial Glide (`07:20 – 07:26`, Frames `13,200 – 13,380`)
* **Motion Characteristics:** Large foreground character (Rinky the flying squirrel) gliding across a stationary and drifting background forest canopy.
* **Failure Mechanism:** Massive occlusion regions on the leading and trailing edges of the body.
* **Artifact Manifestation:** Without accurate occlusion masks (`maskmode=2`) and bi-directional vector weighting, the synthesized intermediate frame creates dark, warping ghost halos around the perimeter of the squirrel.

### Scene 3: Bow & Pinecone Launch (`08:22 – 08:28`, Frames `15,060 – 15,240`)
* **Motion Characteristics:** High-velocity projectile launch followed by sudden impact and rapid camera whip-pan.
* **Failure Mechanism:** Pixel displacement per frame exceeds standard motion search radius limits (`searchparam=3`).
* **Artifact Manifestation:** When block matching cannot find a candidate within the search window, SAD thresholds trigger fallback logic. The projectile may blink, shear into disjointed blocks, or dissolve into square noise.

### Scene 4: Butterfly Flutter & Fur Edges (`02:15 – 02:21`, Frames `4,050 – 4,230`)
* **Motion Characteristics:** Thin, non-rigid butterfly wings fluttering near Bunny's ears and fine facial fur.
* **Failure Mechanism:** Block matching assumes rigid 2D planar translation. Deforming wings break rigid block assumptions.
* **Artifact Manifestation:** Exposes subpixel phase jitter (`pel=2`), vector smoothing errors, and scalar vs vector blend inaccuracies in `FlowInterSimple`.

### Scene 5: Rodent Scramble & Direction Reversal (`03:30 – 03:36`, Frames `6,300 – 6,480`)
* **Motion Characteristics:** Sudden change of direction and acceleration as forest animals scramble over branches.
* **Failure Mechanism:** High temporal acceleration breaks linear velocity extrapolation between frames.
* **Artifact Manifestation:** Tests temporal prediction (`temporal=true`) and search mode resilience (Exhaustive `search=3` vs Diamond `search=2` vs Hex2 `search=5`).

---

## 5. Evaluation Script Templates

### Template A: Ground-Truth Reconstruction (PSNR & SSIM)
Evaluates interpolation accuracy against original uncompressed frames via decimation:

```avisynth
# 1. Source Decimation: Discard odd frames to simulate 15 fps or 30 fps
LoadPlugin("Sources/ARM64/Release/mvtools2.dll")
src = LSMASHVideoSource("D:/devai/benchmarks/bbb_sunflower_1080p_30fps_normal.mp4").Trim(9960, 10139)
decimated = src.SelectEven()

# 2. Reconstruct to 30 fps -> 60 fps
super = decimated.MSuper(pel=2, hpad=16, vpad=16, sharp=1)
bvec  = MAnalyse(super, isb=true,  blksize=16, overlap=4, search=3)
fvec  = MAnalyse(super, isb=false, blksize=16, overlap=4, search=3)
synth = decimated.MFlowFps(super, bvec, fvec, num=60, den=1)

# 3. Output only the newly synthesized intermediate frames
synth.SelectOdd()
Prefetch(4)
```

Compare against the ground-truth stream (`src.SelectOdd()`) via FFmpeg:
```powershell
ffmpeg.exe -i synth_odd.avs -i ground_truth_odd.avs -lavfi "[0:v][1:v]psnr;[0:v][1:v]ssim" -f null -
```

---

### Template B: Direct Cross-Build Differential Analysis (Residual Heatmap)
Subtracts frames rendered by Upstream vs `mvtools-d3d12` to amplify pixel-level discrepancies:

```avisynth
# Stream A: Upstream pinterf/mvtools
# Stream B: mvtools-d3d12 (CPU or Direct3D 12 GPU)

# Amplify absolute difference by 8x on luma, centered chroma at 128
Overlay(StreamA, StreamB, mode="Difference")
mt_lut("x 128 - abs 8 *", y=3, u=1, v=1)
```
