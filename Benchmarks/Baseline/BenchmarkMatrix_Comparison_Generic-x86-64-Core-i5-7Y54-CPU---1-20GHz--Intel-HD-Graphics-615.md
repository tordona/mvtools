# MVTools Benchmark Comparison Matrix - Generic-x86-64-Core-i5-7Y54-CPU---1-20GHz--Intel-HD-Graphics-615

**Host Platform:** Generic x86-64 (Intel(R) Core(TM) i5-7Y54 CPU @ 1.20GHz, Intel(R) HD Graphics 615)  
**Platform Identifier:** Generic-x86-64-Core-i5-7Y54-CPU---1-20GHz--Intel-HD-Graphics-615  
**PotPlayer Version:** 1.7.23164 (Build: 2026-10-23 02:59:00)  
**Benchmark Suite:** MvToolsBenchmarks-Compare.ps1 (v2.4.1)  
**Generated:** 2026-10-25 12:37:07  
**Reference Target:** tears_of_steel_1080p.mov  

| Tier | Motion Engine | Avg FPS | 1% Low FPS | 0.1% Low FPS | CPU Load (Avg/Peak) | GPU Load (Avg/Peak) | PotPlayer GPU | RAM Working Set | Dropped Frames |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Eco** | CPU SIMD | **60.00** | **55.29** | 54.00 | 20.9% / 23.2% | 46.1% / 46.7% | 46.0% | 250.0 MB | 0 frames |
| **Balanced** | CPU SIMD | **60.00** | **55.09** | 54.50 | 24.4% / 26.5% | 46.2% / 47.1% | 46.1% | 263.5 MB | 0 frames |
| **MaxQuality** | CPU SIMD | **60.00** | **54.73** | 53.87 | 43.2% / 47.6% | 45.6% / 46.6% | 45.5% | 277.8 MB | 0 frames |

> [!NOTE]
> **Engine Status:** x64 CPU SIMD (mvtools2.dll) is the active production motion estimation engine on x64 platforms.

### Key Architectural Findings & Trade-Offs

1. **Eco Tier (Battery & Thermal Priority):**
   - **Frame Rate & Pacing:** Sustained **60.00 FPS** (1% Low: **55.29 FPS**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 20.9% (Peak: 23.2%) on x64 CPU SIMD with working set of 250.0 MB.

2. **Balanced Tier (Recommended Daily Driver):**
   - **Frame Rate & Pacing:** Sustained **60.00 FPS** (1% Low: **55.09 FPS**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 24.4% (Peak: 26.5%) on x64 CPU SIMD with working set of 263.5 MB.

3. **MaxQuality Tier (High-Fidelity Action & Detail):**
   - **Frame Rate & Pacing:** Sustained **60.00 FPS** (1% Low: **54.73 FPS**, Dropped: 0 frames).
   - **Compute Load:** System CPU averaged 43.2% (Peak: 47.6%) on x64 CPU SIMD with working set of 277.8 MB.

### Platform Assessment & Profile Recommendation

- **Stability & Real-Time Headroom:** All evaluated tiers sustained real-time 60.00 FPS with zero dropped presentation frames on **Generic x86-64 (Intel(R) Core(TM) i5-7Y54 CPU @ 1.20GHz, Intel(R) HD Graphics 615)**. **Eco** minimized CPU compute load (20.9%), while **Eco** delivered the smoothest frame consistency (55.29 FPS 1% low).
- **Display Hardware Refresh Rate Impact:** Telemetry indicates this platform's physical panel scans at **60.02 Hz** (Primary Display (60.022 Hz, 162300000/2704000)). Across the evaluated duration, presentation synchronized seamlessly without accumulating frame discards.
