# MVTools Benchmark Comparison Matrix - Snapdragon-7cGen2

**Host Platform:** Snapdragon 7c Gen 2 (Kryo 468, Adreno 618)  
**Platform Identifier:** Snapdragon-7cGen2  
**Memory Environment:** Memory-Constrained Hardware (<= 4GB RAM or low physical memory headroom)  
**PotPlayer Version:** 1.7.23122 (Build: 2026-09-01 19:30:50)  
**Benchmark Suite:** MvToolsBenchmarks-Compare.ps1 (v2.1.0)  
**Generated:** 2026-10-19 10:32:10  
**Reference Target:** 1080p 24fps -> 60fps Interpolation  

| Tier | Motion Engine | Avg FPS | 1% Low FPS | 0.1% Low FPS | CPU Load (Avg/Peak) | GPU Load (Avg/Peak) | PotPlayer GPU | RAM Working Set | Dropped Frames |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Eco** | CPU NEON | **60.00** | **54.25** | 51.20 | 11.4% / 12.6% | 51.2% / 52.3% | 42.6% | 260.6 MB | 0 frames |
| **Balanced** | CPU NEON | **60.00** | **53.56** | 52.49 | 12.0% / 13.4% | 51.3% / 52.1% | 42.7% | 258.1 MB | 1 frames |
| **MaxQuality** | CPU NEON | **59.99** | **54.64** | 52.20 | 11.6% / 14.0% | 51.2% / 52.0% | 42.3% | 260.5 MB | 0 frames |

> [!NOTE]
> **Engine Status:** ARM64 CPU NEON (mvtools2.dll) is the recommended production reference. Direct3D 12 GPU offload (mvtools2_d3d12.dll) is provided as an experimental preview; rendering fidelity and real-time performance are provided on a best-effort basis.

> [!NOTE]
> **Memory-Constrained Hardware Notice:** Benchmark telemetry for this platform was captured on a memory-constrained device (Yes (Total RAM: 3767 MB, Available: 1294 MB)). Microstutter metrics (1% and 0.1% Low FPS) and memory working sets should be interpreted with memory pressure in mind.

### Key Architectural Findings & Trade-Offs

1. **Eco Tier (Battery & Thermal Priority):**
   - **Configuration:** 0.5x proxy motion estimation (scaled 2x via MScaleVect), 32x16 blocks, pel=1 (integer pixel), Fast block projection (mode=0) | Target: Ultra-Low Power (~3.0W), Whisper-Cool Fanless Operation, Peak Battery Life
   - **Frame Rate & Pacing:** Sustained **60.00 FPS** (1% Low: **54.25 FPS**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 11.4% (Peak: 12.6%) on native ARM64 NEON with working set of 260.6 MB.

2. **Balanced Tier (Recommended Daily Driver):**
   - **Configuration:** 0.5x proxy motion estimation (scaled 2x via MScaleVect), 16x16 blocks, pel=1 (integer pixel), Fast block projection (mode=0) | Target: Fluid 1080p 60fps, 32x32 Native Motion Vectors, Stable 5W Thermal Ceiling
   - **Frame Rate & Pacing:** Sustained **60.00 FPS** (1% Low: **53.56 FPS**, Dropped: 1 frames).
   - **Compute Load:** System CPU averaged 12.0% (Peak: 13.4%) on native ARM64 NEON with working set of 258.1 MB.

3. **MaxQuality Tier (High-Fidelity Action & Detail):**
   - **Configuration:** 0.5x proxy motion estimation (scaled 2x via MScaleVect), 16x16 blocks, pel=1 (integer pixel), Fast block projection (mode=0) | Target: Highest Achievable Motion Precision at Sustained 60fps (Zero Throttling)
   - **Frame Rate & Pacing:** Sustained **59.99 FPS** (1% Low: **54.64 FPS**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 11.6% (Peak: 14.0%) on native ARM64 NEON with working set of 260.5 MB.

### Platform Assessment & Profile Recommendation

- **Stability & Real-Time Headroom:** On **Snapdragon 7c Gen 2 (Kryo 468, Adreno 618)**, the **Eco** tier sustained steady 60.00 FPS with zero dropped presentation frames. In contrast, higher-complexity passes in [Balanced] exceeded real-time presentation budgets resulting in frame drops. **Eco** is therefore the optimal daily recommendation for this SoC.
- **Memory-Constrained Hardware Headroom:** Benchmarks on this platform were executed on a memory-constrained device. To prevent Windows working-set compression and secondary SSD pagefile swapping during high-motion scenes, utilizing the **Eco** profile or conservative SetMemoryMax configurations is strongly recommended.
