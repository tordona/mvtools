# MVTools Benchmark Comparison Matrix - Snapdragon-850

**Host Platform:** Snapdragon 850 (Kryo 385, Adreno 630)  
**Platform Identifier:** Snapdragon-850  
**PotPlayer Version:** 1.7.23122 (Build: 2026-09-01 22:30:50)  
**Benchmark Suite:** MvToolsBenchmarks-Compare.ps1 (v2.1.0)  
**Generated:** 2026-10-19 10:32:10  
**Reference Target:** 1080p 24 fps -> 60 fps Interpolation  

| Tier | Motion Engine | Avg FPS | 1% Low FPS | 0.1% Low FPS | CPU Load (Avg/Peak) | GPU Load (Avg/Peak) | PotPlayer GPU | RAM Working Set | Dropped Frames |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Eco** | CPU NEON | **59.99** | **54.09** | 50.27 | 13.0% / 14.1% | 54.0% / 55.3% | 48.1% | 263.0 MB | 25 frames |
| **Balanced** | CPU NEON | **60.00** | **54.09** | 52.26 | 14.9% / 16.2% | 53.3% / 54.6% | 46.9% | 271.9 MB | 0 frames |
| **MaxQuality** | CPU NEON | **60.00** | **53.90** | 50.42 | 14.9% / 15.7% | 53.4% / 54.8% | 47.0% | 276.8 MB | 0 frames |

> [!NOTE]
> **Engine Status:** ARM64 CPU NEON (mvtools2.dll) is the recommended production reference. Direct3D 12 GPU offload (mvtools2_d3d12.dll) is provided as an experimental preview; rendering fidelity and real-time performance are provided on a best-effort basis.

### Key Architectural Findings & Trade-Offs

1. **Eco Tier (Battery & Thermal Priority):**
   - **Configuration:** Full native analysis, 64x32 blocks, pel=1 (integer pixel), Fast block projection (mode=0) | Target: 5 W Fanless Thermal Envelope, Maximum Battery Life, 0 Thermal Throttling
   - **Frame Rate & Pacing:** Sustained **59.99 fps** (1% Low: **54.09 fps**, Dropped: 25 frames).
   - **Compute Load:** System CPU averaged 13.0% (Peak: 14.1%) on native ARM64 NEON with working set of 263.0 MB.

2. **Balanced Tier (Recommended Daily Driver):**
   - **Configuration:** Full native analysis, Dual-pass 32x32 -> 16x16, pel=1 (integer pixel), Fast block projection (mode=0) | Target: Fluid 1080p 60 fps, Refined 16x16 Edges, Stable Thermal Ceiling
   - **Frame Rate & Pacing:** Sustained **60.00 fps** (1% Low: **54.09 fps**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 14.9% (Peak: 16.2%) on native ARM64 NEON with working set of 271.9 MB.

3. **MaxQuality Tier (High-Fidelity Action & Detail):**
   - **Configuration:** Full native analysis, Dual-pass 32x32 -> 16x16, pel=1 (integer pixel), Fast block projection (mode=0) | Target: Highest Quality Motion Flow within 5 W Snapdragon 850 Thermal Budget
   - **Frame Rate & Pacing:** Sustained **60.00 fps** (1% Low: **53.90 fps**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 14.9% (Peak: 15.7%) on native ARM64 NEON with working set of 276.8 MB.

### Platform Assessment & Profile Recommendation

- **Stability & Real-Time Headroom:** On **Snapdragon 850 (Kryo 385, Adreno 630)**, the **Balanced** tier sustained steady 60.00 fps with zero dropped presentation frames. In contrast, higher-complexity passes in [Eco] exceeded real-time presentation budgets resulting in frame drops. **Balanced** is therefore the optimal daily recommendation for this SoC.
