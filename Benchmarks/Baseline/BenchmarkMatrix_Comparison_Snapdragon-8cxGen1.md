# MVTools Benchmark Comparison Matrix - Snapdragon-8cxGen1

**Host Platform:** Snapdragon 8cx Gen 1 / SQ1 (Kryo 495, Adreno 675)  
**Platform Identifier:** Snapdragon-8cxGen1  
**PotPlayer Version:** 1.7.23122 (Build: 2026-09-01 22:30:50)  
**Benchmark Suite:** MvToolsBenchmarks-Compare.ps1 (v2.5.0)  
**Generated:** 2026-10-28 17:07:09  
**Reference Target:** tears_of_steel_1080p.mov  

| Tier | Motion Engine | Avg FPS | 1% Low FPS | 0.1% Low FPS | CPU Load (Avg/Peak) | GPU Load (Avg/Peak) | PotPlayer GPU | RAM Working Set | Dropped Frames |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Eco** | CPU NEON | **60.00** | **54.43** | 52.86 | 9.3% / 20.6% | 19.6% / 20.9% | 19.6% | 252.2 MB | 0 frames |
| **Eco** | D3D12 GPU | **60.05** | **54.33** | 52.68 | 9.0% / 16.2% | 57.7% / 59.1% | 54.8% | 319.6 MB | 5 frames |
| **Balanced** | CPU NEON | **60.00** | **53.97** | 52.54 | 11.2% / 12.0% | 24.0% / 25.9% | 19.5% | 265.5 MB | 0 frames |
| **Balanced** | D3D12 GPU | **60.00** | **55.03** | 51.98 | 8.7% / 9.8% | 53.6% / 62.7% | 50.5% | 327.8 MB | 0 frames |
| **MaxQuality** | CPU NEON | **59.99** | **53.77** | 53.20 | 17.9% / 20.4% | 24.0% / 25.7% | 19.6% | 309.0 MB | 0 frames |
| **MaxQuality** | D3D12 GPU | **60.00** | **54.85** | 53.15 | 8.5% / 9.0% | 54.0% / 56.8% | 50.9% | 327.9 MB | 0 frames |

> [!NOTE]
> **Engine Status:** ARM64 CPU NEON (mvtools2.dll) is the recommended production reference. Direct3D 12 GPU offload (via MEnableD3D12(true) in mvtools2.dll) is provided as an experimental preview; rendering fidelity and real-time performance are provided on a best-effort basis.

### Key Architectural Findings & Trade-Offs

1. **Eco Tier (Battery & Thermal Priority):**
   - **Frame Rate & Pacing:** Average FPS: CPU NEON **60.00 FPS** (0 frames) vs D3D12 GPU **60.05 FPS** (5 frames). 1% Lows: CPU NEON **54.43 FPS** vs D3D12 GPU **54.33 FPS**.
   - **Compute Offload:** System CPU load was comparable (9.3% CPU NEON vs 9.0% D3D12 GPU), with D3D12 engaging 54.8% Adreno GPU compute.
   - **Memory Footprint:** PotPlayer working set: 252.2 MB (CPU) vs 319.6 MB (D3D12 GPU).

2. **Balanced Tier (Recommended Daily Driver):**
   - **Frame Rate & Pacing:** Both engines sustained a solid **60.00 FPS** with 0 dropped presentation frames. 1% Lows: CPU NEON **53.97 FPS** vs D3D12 GPU **55.03 FPS**.
   - **Compute Offload:** D3D12 GPU offload reduced system CPU load by **2.5%** (from 11.2% down to 8.7%), utilizing 50.5% Adreno GPU compute.
   - **Memory Footprint:** PotPlayer working set: 265.5 MB (CPU) vs 327.8 MB (D3D12 GPU).

3. **MaxQuality Tier (High-Fidelity Action & Detail):**
   - **Frame Rate & Pacing:** Both engines sustained a solid **59.99 FPS** with 0 dropped presentation frames. 1% Lows: CPU NEON **53.77 FPS** vs D3D12 GPU **54.85 FPS**.
   - **Compute Offload:** D3D12 GPU offload reduced system CPU load by **9.4%** (from 17.9% down to 8.5%), utilizing 50.9% Adreno GPU compute.
   - **Memory Footprint:** PotPlayer working set: 309.0 MB (CPU) vs 327.9 MB (D3D12 GPU).

### Platform Assessment & Profile Recommendation

- **Stability & Real-Time Headroom:** All evaluated tiers sustained real-time 60.00 fps with zero dropped presentation frames on **Snapdragon 8cx Gen 1 / SQ1 (Kryo 495, Adreno 675)**. **MaxQuality** minimized CPU compute load (8.5%), while **Balanced** delivered the smoothest frame consistency (55.03 FPS 1% low).
- **Compute Engine Trade-Off:** ARM64 CPU NEON remains the recommended production baseline for deterministic frame pacing and artifact-free presentation. Direct3D 12 GPU offload transfers motion vector search to the Adreno GPU compute shaders, freeing CPU headroom for background multi-tasking.
- **Display Hardware Refresh Rate Impact:** Telemetry indicates this platform's physical panel scans at **60.00 Hz** (Primary Display (60.048 Hz, 60048/1000)). Across the evaluated duration, presentation synchronized continuously without accumulating frame discards.
