# MVTools Benchmark Comparison Matrix - Snapdragon-8cxGen1

**Host Platform:** Snapdragon 8cx Gen 1 / SQ1 (Kryo 495, Adreno 675)  
**Platform Identifier:** Snapdragon-8cxGen1  
**PotPlayer Version:** 1.7.23122 (Build: 2026-09-01 22:30:50)  
**Benchmark Suite:** MvToolsBenchmarks-Compare.ps1 (v2.1.0)  
**Generated:** 2026-10-19 10:32:10  
**Reference Target:** 1080p 24 fps -> 60 fps Interpolation  

| Tier | Motion Engine | Avg FPS | 1% Low FPS | 0.1% Low FPS | CPU Load (Avg/Peak) | GPU Load (Avg/Peak) | PotPlayer GPU | RAM Working Set | Dropped Frames |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Eco** | CPU NEON | **60.00** | **54.11** | 52.77 | 13.5% / 24.8% | 23.9% / 25.0% | 19.5% | 306.9 MB | 0 frames |
| **Eco** | D3D12 GPU | **60.00** | **54.49** | 52.75 | 18.4% / 83.8% | 63.9% / 68.9% | 61.2% | 323.4 MB | 1 frames |
| **Balanced** | CPU NEON | **60.00** | **54.88** | 52.45 | 15.6% / 20.9% | 23.9% / 25.4% | 19.5% | 322.8 MB | 0 frames |
| **Balanced** | D3D12 GPU | **60.00** | **53.47** | 51.72 | 14.9% / 15.5% | 60.8% / 75.2% | 57.6% | 341.2 MB | 0 frames |
| **MaxQuality** | CPU NEON | **60.00** | **54.26** | 53.10 | 25.7% / 27.0% | 23.9% / 25.6% | 19.5% | 383.2 MB | 0 frames |
| **MaxQuality** | D3D12 GPU | **60.00** | **54.14** | 52.61 | 24.0% / 42.2% | 68.4% / 74.6% | 65.5% | 342.4 MB | 0 frames |

> [!NOTE]
> **Engine Status:** ARM64 CPU NEON (mvtools2.dll) is the recommended production reference. Direct3D 12 GPU offload (mvtools2_d3d12.dll) is provided as an experimental preview; rendering fidelity and real-time performance are provided on a best-effort basis.

### Key Architectural Findings & Trade-Offs

1. **Eco Tier (Battery & Thermal Priority):**
   - **Configuration:** Full native analysis, 32x32 blocks, pel=1 (integer pixel), Fast block projection (mode=0) | Target: 7 W Fanless Thermal Envelope, Maximum Battery Life, 0 Dropped Frames
   - **Frame Rate & Pacing:** Average FPS: CPU NEON **60.00 fps** (0 frames) vs D3D12 GPU **60.00 fps** (1 frames). 1% Lows: CPU NEON **54.11 fps** vs D3D12 GPU **54.49 fps**.
   - **Compute Offload:** CPU NEON operated with lower CPU load (13.5% vs 18.4%), with D3D12 GPU engaging 61.2% Adreno GPU compute.
   - **Memory Footprint:** PotPlayer working set: 306.9 MB (CPU) vs 323.4 MB (D3D12 GPU).

2. **Balanced Tier (Recommended Daily Driver):**
   - **Configuration:** Full native analysis, 16x16 blocks, pel=1 (integer pixel), Pixel-flow synthesis (mode=2) | Target: Fluid 1080p 60 fps, Sharp Edge Tracking, Stable Thermal Ceiling
   - **Frame Rate & Pacing:** Both engines sustained a solid **60.00 fps** with 0 dropped presentation frames. 1% Lows: CPU NEON **54.88 fps** vs D3D12 GPU **53.47 fps**.
   - **Compute Offload:** D3D12 GPU offload reduced system CPU load by **0.7%** (from 15.6% down to 14.9%), utilizing 57.6% Adreno GPU compute.
   - **Memory Footprint:** PotPlayer working set: 322.8 MB (CPU) vs 341.2 MB (D3D12 GPU).

3. **MaxQuality Tier (High-Fidelity Action & Detail):**
   - **Configuration:** Full native analysis, Dual-pass 16x16 -> 8x8, pel=2 (CPU half-pixel) / pel=1 (GPU integer), Pixel-flow synthesis (mode=2) | Target: Highest Achievable Quality within 8cx Thermal Ceiling
   - **Frame Rate & Pacing:** Both engines sustained a solid **60.00 fps** with 0 dropped presentation frames. 1% Lows: CPU NEON **54.26 fps** vs D3D12 GPU **54.14 fps**.
   - **Compute Offload:** D3D12 GPU offload reduced system CPU load by **1.7%** (from 25.7% down to 24.0%), utilizing 65.5% Adreno GPU compute.
   - **Memory Footprint:** PotPlayer working set: 383.2 MB (CPU) vs 342.4 MB (D3D12 GPU).

### Platform Assessment & Profile Recommendation

- **Stability & Real-Time Headroom:** On **Snapdragon 8cx Gen 1 / SQ1 (Kryo 495, Adreno 675)**, the **Balanced** tier sustained steady 60.00 fps with zero dropped presentation frames. In contrast, higher-complexity passes in [Eco] exceeded real-time presentation budgets resulting in frame drops. **Balanced** is therefore the optimal daily recommendation for this SoC.
- **Compute Engine Trade-Off:** ARM64 CPU NEON remains the recommended production baseline for deterministic frame pacing and artifact-free presentation. Direct3D 12 GPU offload transfers motion vector search to the Adreno GPU compute shaders, freeing CPU headroom for background multi-tasking.
