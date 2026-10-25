# MVTools Benchmark Comparison Matrix - AMD-Ryzen-AI-5-340

**Host Platform:** AMD Ryzen AI 5 340 (3x Zen 5 + 3x Zen 5c Cores, Radeon 840M RDNA 3.5 @ 2.9 GHz)  
**Platform Identifier:** AMD-Ryzen-AI-5-340  
**PotPlayer Version:** 1.7.23164 (Build: 2026-10-23 02:59:00)  
**Benchmark Suite:** MvToolsBenchmarks-Compare.ps1 (v2.4.1)  
**Generated:** 2026-10-25 13:11:30  
**Reference Target:** tears_of_steel_1080p.mov  

| Tier | Motion Engine | Avg FPS | 1% Low FPS | 0.1% Low FPS | CPU Load (Avg/Peak) | GPU Load (Avg/Peak) | PotPlayer GPU | RAM Working Set | Dropped Frames |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Eco** | CPU SIMD | **59.90** | **52.04** | 50.30 | 10.3% / 13.7% | 41.0% / 43.5% | 40.9% | 286.8 MB | 0 frames |
| **Balanced** | CPU SIMD | **59.90** | **52.23** | 50.87 | 10.7% / 13.2% | 40.8% / 41.3% | 40.8% | 299.2 MB | 0 frames |
| **MaxQuality** | CPU SIMD | **59.89** | **52.36** | 50.89 | 13.5% / 17.6% | 40.4% / 41.0% | 40.4% | 337.5 MB | 0 frames |

> [!NOTE]
> **Engine Status:** x64 CPU SIMD (mvtools2.dll) is the active production motion estimation engine on x64 platforms.

### Key Architectural Findings & Trade-Offs

1. **Eco Tier (Battery & Thermal Priority):**
   - **Frame Rate & Pacing:** Sustained **59.90 FPS** (1% Low: **52.04 FPS**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 10.3% (Peak: 13.7%) on x64 CPU SIMD with working set of 286.8 MB.

2. **Balanced Tier (Recommended Daily Driver):**
   - **Frame Rate & Pacing:** Sustained **59.90 FPS** (1% Low: **52.23 FPS**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 10.7% (Peak: 13.2%) on x64 CPU SIMD with working set of 299.2 MB.

3. **MaxQuality Tier (High-Fidelity Action & Detail):**
   - **Frame Rate & Pacing:** Sustained **59.89 FPS** (1% Low: **52.36 FPS**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 13.5% (Peak: 17.6%) on x64 CPU SIMD with working set of 337.5 MB.

### Platform Assessment & Profile Recommendation

- **Stability & Real-Time Headroom:** All evaluated tiers sustained real-time 60.00 FPS with zero dropped presentation frames on **AMD Ryzen AI 5 340 (3x Zen 5 + 3x Zen 5c Cores, Radeon 840M RDNA 3.5 @ 2.9 GHz)**. **Eco** minimized CPU compute load (10.3%), while **MaxQuality** delivered the smoothest frame consistency (52.36 FPS 1% low).
- **Display Hardware Refresh Rate Impact:** Telemetry indicates this platform's physical panel scans at **59.89 Hz** (Primary Display (60.000 Hz, 60/1)). Across the evaluated duration, presentation synchronized seamlessly without accumulating frame discards.
