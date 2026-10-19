# MVTools Benchmark Comparison Matrix - Snapdragon-X-Plus

**Host Platform:** Snapdragon X Plus (Qualcomm Oryon CPU, Adreno X1 GPU)  
**Platform Identifier:** Snapdragon-X-Plus  
**PotPlayer Version:** 1.7.23122 (Build: 2026-09-01 22:30:50)  
**Benchmark Suite:** MvToolsBenchmarks-Compare.ps1 (v2.1.0)  
**Generated:** 2026-10-19 10:32:10  
**Reference Target:** 1080p 24fps -> 60fps Interpolation  

| Tier | Motion Engine | Avg FPS | 1% Low FPS | 0.1% Low FPS | CPU Load (Avg/Peak) | GPU Load (Avg/Peak) | PotPlayer GPU | RAM Working Set | Dropped Frames |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Eco** | CPU NEON | **60.00** | **53.09** | 51.98 | 6.2% / 7.1% | 25.8% / 26.4% | 21.7% | 341.4 MB | 0 frames |
| **Eco** | D3D12 GPU | **60.00** | **55.09** | 53.05 | 6.1% / 7.2% | 73.3% / 78.9% | 70.5% | 323.6 MB | 0 frames |
| **Balanced** | CPU NEON | **60.04** | **52.72** | 50.91 | 7.7% / 8.5% | 25.2% / 26.7% | 22.3% | 387.9 MB | 3 frames |
| **Balanced** | D3D12 GPU | **60.00** | **52.48** | 52.19 | 7.5% / 10.3% | 71.7% / 76.0% | 69.9% | 376.5 MB | 21 frames |
| **MaxQuality** | CPU NEON | **60.00** | **53.58** | 52.72 | 13.8% / 15.5% | 25.4% / 26.0% | 21.6% | 511.6 MB | 19 frames |
| **MaxQuality** | D3D12 GPU | **60.00** | **54.19** | 52.18 | 10.5% / 11.3% | 78.9% / 83.3% | 77.4% | 455.0 MB | 0 frames |

> [!NOTE]
> **Engine Status:** ARM64 CPU NEON (mvtools2.dll) is the recommended production reference. Direct3D 12 GPU offload (mvtools2_d3d12.dll) is provided as an experimental preview; rendering fidelity and real-time performance are provided on a best-effort basis.

### Key Architectural Findings & Trade-Offs

1. **Eco Tier (Battery & Thermal Priority):**
   - **Configuration:** Full native analysis, 32x32 blocks, pel=1 (integer pixel), Fast block projection (mode=0) | Target: Ultra-low CPU usage, zero dropped frames, cool & quiet / battery saver
   - **Frame Rate & Pacing:** Both engines sustained a solid **60.00 FPS** with 0 dropped presentation frames. 1% Lows: CPU NEON **53.09 FPS** vs D3D12 GPU **55.09 FPS**.
   - **Compute Offload:** System CPU load was comparable (6.2% CPU NEON vs 6.1% D3D12 GPU), with D3D12 engaging 70.5% Adreno GPU compute.
   - **Memory Footprint:** PotPlayer working set: 341.4 MB (CPU) vs 323.6 MB (D3D12 GPU).

2. **Balanced Tier (Recommended Daily Driver):**
   - **Configuration:** Full native analysis, Dual-pass 32x32 -> 16x16, pel=1 (integer pixel), Pixel-flow synthesis (mode=2) | Target: Sweet spot between fluid motion, sharp edges, and efficient power draw
   - **Frame Rate & Pacing:** Average FPS: CPU NEON **60.04 FPS** (3 frames) vs D3D12 GPU **60.00 FPS** (21 frames). 1% Lows: CPU NEON **52.72 FPS** vs D3D12 GPU **52.48 FPS**.
   - **Compute Offload:** System CPU load was comparable (7.7% CPU NEON vs 7.5% D3D12 GPU), with D3D12 engaging 69.9% Adreno GPU compute.
   - **Memory Footprint:** PotPlayer working set: 387.9 MB (CPU) vs 376.5 MB (D3D12 GPU).

3. **MaxQuality Tier (High-Fidelity Action & Detail):**
   - **Configuration:** Full native analysis, Dual-pass 16x16 -> 8x8 (CPU) / 32x32 -> 16x16 (GPU), pel=2 (subpixel Wiener/bicubic), Pixel-flow synthesis (mode=2) | Target: Highest visual fidelity, subpixel precision, rock-solid sustained 60fps
   - **Frame Rate & Pacing:** Average FPS: CPU NEON **60.00 FPS** (19 frames) vs D3D12 GPU **60.00 FPS** (0 frames). 1% Lows: CPU NEON **53.58 FPS** vs D3D12 GPU **54.19 FPS**.
   - **Compute Offload:** D3D12 GPU offload reduced system CPU load by **3.3%** (from 13.8% down to 10.5%), utilizing 77.4% Adreno GPU compute.
   - **Memory Footprint:** PotPlayer working set: 511.6 MB (CPU) vs 455.0 MB (D3D12 GPU).

### Platform Assessment & Profile Recommendation

- **Stability & Real-Time Headroom:** On **Snapdragon X Plus (Qualcomm Oryon CPU, Adreno X1 GPU)**, the **Eco** tier sustained steady 60.00 FPS with zero dropped presentation frames. In contrast, higher-complexity passes in [Balanced, MaxQuality] exceeded real-time presentation budgets resulting in frame drops. **Eco** is therefore the optimal daily recommendation for this SoC.
- **Compute Engine Trade-Off:** ARM64 CPU NEON remains the recommended production baseline for deterministic frame pacing and artifact-free presentation. Direct3D 12 GPU offload transfers motion vector search to the Adreno GPU compute shaders, freeing CPU headroom for background multi-tasking.
