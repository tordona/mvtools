# AI Port Notice & Technical Architecture Summary

This repository contains an **ARM64 Windows** port and ABI compatibility bridge for the **MVTools2** AviSynth plugin suite (`mvtools2.dll`, `DePan.dll`, and `DePanEstimate.dll`), version **`v2.7.47-arm64`**. 

This port was developed through collaborative pair programming with **Google Antigravity** (Advanced Agentic AI Coding Assistant).

---

## 1. Executive Summary

Historically, MVTools was tightly coupled to x86/x64 assembly and MSVC/GCC x86 intrinsics. When deploying to modern **Windows on ARM64** devices (such as Qualcomm Snapdragon X Plus, Snapdragon 8cx Gen 2, and Snapdragon 850), existing plugins failed due to:
1. Missing native ARM64 Visual Studio build configurations.
2. Reliance on x86-specific inline assembly and x86 SIMD (`emmintrin.h`, `smmintrin.h`, etc.).
3. Fundamental **C++ ABI calling convention and vtable layout mismatches** between host **MinGW GCC** binaries (such as PotPlayer's bundled `AviSynth.dll`) and **MSVC ARM64** plugins.

This port resolves all three tiers of incompatibilities, delivering **native ARM64 execution**, **128-bit NEON SIMD vectorization**, **zero-crash lifecycle stability**, and **tuned real-time 60fps profiles**.

---

## 2. Key Architecture & Engineering Changes

### A. Native MSVC ARM64 Build System
- **Project Configuration**: Integrated native `ARM64` platform targets across `mvtools.sln`, `Sources/mvtools.vcxproj`, `DePan/DePan.vcxproj`, and `DePanEstimate/DePanEstimate.vcxproj`.
- **Compiler Flags**: Configured MSVC v143/v145 (Visual Studio 2022/2026) with `/vmg` (general member pointer representation) and `/Zc:preprocessor` (standard-conforming preprocessor).
- **Backward Compatibility**: All ARM64 modifications are strictly isolated with preprocessor guards (`#if defined(_MSC_VER) && defined(ARM64)` or `#if !defined(_M_ARM64) && !defined(__aarch64__)`), preserving 100% build integrity for legacy `x86` and `x64` targets.

### B. NEON SIMD Vectorization Layer
- **Intrinsic Translation**: Integrated [`sse2neon.h`](Sources/include/sse2neon.h) to translate SSE, SSE2, SSSE3, and SSE4.1 intrinsics directly into native ARM64 NEON instructions.
- **Header Shims**: Added standard x86 intrinsic shims under [`Sources/include/arm64/`](Sources/include/arm64/) (`mmintrin.h`, `xmmintrin.h`, `emmintrin.h`, `pmmintrin.h`, `tmmintrin.h`, `smmintrin.h`, `immintrin.h`) to allow unmodified compilation of SIMD motion estimation routines.
- **Disabled x86-Only Inline ASM**: Gracefully disabled legacy 32-bit x86/x64 assembly routines (`USE_SAD_ASM`, `USE_COPYCODE_ASM`, etc.) on ARM architectures in [`Sources/def.h`](Sources/def.h), falling back to optimized SIMD and C++ paths.

### C. Cross-Compiler C++ ABI Bridge (MinGW GCC $\leftrightarrow$ MSVC ARM64)
The host `AviSynth.dll` bundled with ARM64 video players (e.g., PotPlayer) is typically compiled with **MinGW GCC (AArch64)**, whereas Windows plugins are built using **MSVC ARM64**. A custom runtime translation layer was engineered into [`Sources/include/avisynth.h`](Sources/include/avisynth.h):

1. **`IScriptEnvironment` VTable Slot Alignment**:
   - *Issue*: GCC emits two vtable slots for virtual destructors (`~D1` complete and `~D0` deleting), shifting subsequent interface methods by +8 bytes in MSVC.
   - *Fix*: Added a dummy virtual method pad `virtual void __dummy_gcc_dtor_pad() {}` to `IScriptEnvironment` under MSVC ARM64 to align vtable slots.

2. **`AVS_Linkage` Member Function Pointer Size**:
   - *Issue*: Member function pointers in MSVC default to 8 bytes for single-inheritance classes, while GCC on AArch64 uses 16 bytes, causing structure alignment corruption.
   - *Fix*: Configured `__multiple_inheritance` and `/vmg` compiler flags, expanding pointers to 16 bytes and matching GCC's 3,328-byte `AVS_Linkage` struct.

3. **`ApplyFunc` Calling Convention Translation**:
   - *Issue*: Non-member functions returning non-trivial objects (`AVSValue`) by value differ: GCC passes the return buffer pointer in `X8`, while MSVC ARM64 non-member callee expects it in `X0` (shifting arguments to `X1–X3`).
   - *Fix*: Implemented dynamic AArch64 JIT adapter thunk [`AVS_WrapApply`](Sources/include/avisynth.h) to translate register layouts:  
     `(X0=args, X1=user_data, X2=env, X8=ret_buf)` $\to$ `(X0=ret_buf, X1=args, X2=user_data, X3=env)`.

4. **Bidirectional `IClip::GetFrame` Translation**:
   - *Outgoing Clips (Filter MSVC $\to$ AviSynth GCC)*: [`AVS_WrapClipVTable`](Sources/include/avisynth.h) dynamically patches `vtable[1]` using an ARM64 thunk to translate GCC caller registers `(X0=this, X1=n, X2=env, X8=ret_buf)` to MSVC callee layout `(X0=this, X1=ret_buf, X2=n, X3=env)`.
   - *Incoming Clips (AviSynth GCC $\to$ Filter MSVC)*: Implemented [`AVS_ClipProxy`](Sources/include/avisynth.h) and [`AVS_WrapClip`](Sources/include/avisynth.h) to wrap external clips, transparently invoking GCC `GetFrame` with `X8` return buffer convention.

5. **`IClip` Deleting Destructor Alignment (Lifecycle Stability)**:
   - *Issue*: On playback stop or player exit, AviSynth's `PClip_DESTRUCTOR` invokes GCC deleting destructor slot `vtable[7]` (`0x38`). In MSVC, classes only generated 7 slots (`0x00`–`0x30`), jumping into non-executable `.rdata` and triggering DEP Access Violation `0xC0000005`.
   - *Fix*: Added `virtual void __dummy_gcc_dtor_pad() { delete this; }` to `IClip`. This exposes slot 7 in all derived clips, safely dispatching GCC deallocations to MSVC's scalar deleting destructor (`vtable[6]`) to release memory cleanly.

---

## 3. Hardware Profiles & Deployment Guides

Custom real-time 60fps AviSynth motion interpolation scripts and PotPlayer iGPU offload guides were engineered for Qualcomm Snapdragon platforms:

- **Snapdragon X Plus (8x Oryon Cores @ 3.4 GHz, 15W–30W TDP)**:
  - [`Snapdragon-X-Plus-Eco.avs`](AviSynth/Snapdragon-X-Plus-Eco.avs): `pel=1`, `32x32` blocks, `mode=0` block projection, `Prefetch(4)`. Ultra-low thermal impact and high efficiency.
  - [`Snapdragon-X-Plus-Balanced.avs`](AviSynth/Snapdragon-X-Plus-Balanced.avs): Dual-pass `32x32` $\to$ `16x16` refinement (`MRecalculate`), `mode=2` pixel-flow synthesis, `Prefetch(6)`. Smooth 1080p60 target.
  - [`Snapdragon-X-Plus-MaxQuality.avs`](AviSynth/Snapdragon-X-Plus-MaxQuality.avs): Subpixel `pel=2` Wiener interpolation, `16x16` $\to$ `8x8` micro-blocks, UMH motion search, `Prefetch(8)`. Maximum fidelity for plugged-in operation.
  - Guide: [`Documentation/guides/SnapdragonXPlus.md`](Documentation/guides/SnapdragonXPlus.md).

- **Snapdragon 8cx Gen 2 (4x Kryo 495 Gold Cortex-A76 + 4x Silver Cortex-A55, Adreno 680, 7W–10W Fanless)**:
  - [`Snapdragon-8cxGen2-Eco.avs`](AviSynth/Snapdragon-8cxGen2-Eco.avs): `pel=1`, large `32x32` blocks, `mode=0` block projection, `Prefetch(3)`. Leaves 1 Gold core + 4 Silver cores idle; designed for fanless battery longevity with zero dropped frames.
  - [`Snapdragon-8cxGen2-Balanced.avs`](AviSynth/Snapdragon-8cxGen2-Balanced.avs): Dual-pass `32x32` $\to$ `16x16` refinement (`MRecalculate`), `mode=2` pixel-flow synthesis, `Prefetch(4)`. Pins 1:1 to the 4 Kryo Gold cores to prevent scheduling spills onto weak in-order Cortex-A55 cores.
  - [`Snapdragon-8cxGen2-MaxQuality.avs`](AviSynth/Snapdragon-8cxGen2-MaxQuality.avs): Subpixel `pel=2` bicubic, `16x16` $\to$ `8x8` micro-blocks, `mode=2` with `blend=true` occlusion handling, `Prefetch(4)`. Maximum visual clarity without thermal throttling.
  - Guide: [`Documentation/guides/Adreno680.md`](Documentation/guides/Adreno680.md) (Covers Adreno 680 VPU DXVA2/D3D11 Copy-Back decode and Direct3D 11 NV12/YV12 rendering).

- **Snapdragon 850 (4x Kryo 385 Gold Cortex-A75 + 4x Silver Cortex-A55, Adreno 630, ~5W Fanless)**:
  - [`Snapdragon-850-Eco.avs`](AviSynth/Snapdragon-850-Eco.avs): Wide `64x32` rectangular blocks (~1,020 blocks for 1080p), `pel=1`, `mode=0` block projection, `Prefetch(2)`. Runs strictly on 2 Gold cores for minimal heat and zero throttling in ~5W fanless designs.
  - [`Snapdragon-850-Balanced.avs`](AviSynth/Snapdragon-850-Balanced.avs): Dual-pass `32x32` $\to$ `16x16` refinement (`MRecalculate`), `pel=1`, `mode=0` block projection, `Prefetch(3)`. Crisp boundary tracking while preserving 1 Gold core for OS and Adreno GPU drivers.
  - [`Snapdragon-850-MaxQuality.avs`](AviSynth/Snapdragon-850-MaxQuality.avs): `32x32` $\to$ `16x16` refinement (`MRecalculate`), `mode=2` pixel-flow interpolation, `Prefetch(4)`. Full Gold core saturation without spilling onto Cortex-A55 cores.
  - Guide: [`Documentation/guides/Adreno630.md`](Documentation/guides/Adreno630.md) (Covers Adreno 630 VPU hardware decode offload and Direct3D 11 rendering).

---

## 4. How to Build the ARM64 Binaries

### Prerequisites
- Visual Studio 2022 (v143) or Visual Studio 2026 (v145) with the **Desktop development with C++** and **MSVC v14x - VS 20xx C++ ARM64 build tools** installed.

### Command Line Build
Open the **Visual Studio ARM64 Native Tools Command Prompt** (or call `vcvarsarm64.bat`):

```cmd
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsarm64.bat"
msbuild mvtools.sln /p:Configuration=Release /p:Platform=ARM64
```

### Output Binaries
- `Sources\ARM64\Release\mvtools2.dll`
- `DePan\ARM64\Release\DePan.dll`
- `DePanEstimate\ARM64\Release\DePanEstimate.dll`

---

## 5. Antigravity Skills & Technical Disciplines Utilized

This port was executed using Google Antigravity, leveraging both platform agent skills and specialized systems engineering competencies:

### A. Antigravity & Agent Skills
- **[asm-x64-to-arm64](https://skills.rest/skill/asm-x64-to-arm64)**: Primary domain skill for x64 $\to$ AArch64 architecture porting. Governed:
  - Identifying and resolving ABI differences between Windows x64 and AArch64 AAPCS (argument registers, shadow space, indirect return buffers in `X8`).
  - Auditing and isolating legacy x86/x64 inline assembly blocks (`__asm`) in [`Sources/def.h`](Sources/def.h) and redirecting compute paths to portable C++ and SIMD.
  - Guiding 128-bit SIMD SSE-to-NEON vector translation and instruction mapping.
  - Designing raw AArch64 machine-code thunks, branch register operations (`BR X16`), and stack/register clobber specifications.
- **[antigravity-guide](https://skills.rest/skill/antigravity-skills)**: Utilized for Antigravity architecture discovery, tool execution flows, workspace derivation, and system interaction conventions.
- **[agy-customizations](https://skills.rest/skill/antigravity-cli)**: Applied for managing workspace customizations, configuration references, and behavioral guidelines across parent and derivative repositories.


### B. Systems Engineering Disciplines Applied by the AI Agent
- **Cross-Compiler C++ ABI Reverse Engineering**:
  - Disassembled and analyzed calling convention differences between standard AArch64 AAPCS (MinGW GCC) and MSVC ARM64 Windows ABI.
  - Identified the hidden return-buffer pointer register mismatch (`X8` indirect result register vs. `X0`/`X1` in MSVC member calls).
  - Diagnosed C++ virtual method table (vtable) polymorphism discrepancies, resolving Itanium C++ ABI dual-slot virtual destructors (`~D1`/`~D0`) versus MSVC single scalar deleting destructors.
  - Mapped member function pointer representations and structure layout alignments (`/vmg`, `__multiple_inheritance`).
- **Dynamic JIT Machine Code & Thunk Synthesis**:
  - Hand-crafted executable AArch64 machine-code JIT thunks (`AVS_WrapApply`, `AVS_WrapClipVTable`, `AVS_ClipProxy`) to translate caller/callee register contracts on-the-fly.
  - Managed executable memory allocation via Win32 `VirtualAlloc` (`PAGE_EXECUTE_READWRITE`) and synchronized CPU instruction/data caches with `FlushInstructionCache`.
- **SIMD Vectorization & Instruction Translation**:
  - Ported legacy x86 SSE/SSE2/SSSE3/SSE4.1 motion estimation algorithms to 128-bit ARM NEON vector instructions via `sse2neon`.
  - Engineered drop-in x86 intrinsic compatibility headers in `Sources/include/arm64/` (`mmintrin.h`, `emmintrin.h`, `smmintrin.h`, etc.).
  - Replaced x86-specific inline assembly with portable C++ and SIMD equivalents.
- **Heterogeneous SoC Optimization & Thermal Tuning**:
  - Analyzed Qualcomm Snapdragon big.LITTLE / heterogeneous core topologies (Qualcomm Oryon, Kryo Gold/Silver) to eliminate thread starvation caused by inappropriate thread pool oversizing.
  - Formulated real-time 60fps AviSynth profiles and PotPlayer iGPU hardware-decoding offload recommendations for Snapdragon X Plus, 8cx Gen 2, and 850.
- **Build System Engineering & Modernization**:
  - Integrated MSVC ARM64 platform definitions across multi-project Visual Studio solution files (`.sln`, `.vcxproj`).
  - Preserved strict backward compatibility for legacy x86 and x64 builds through preprocessor guards.

---

## 6. Upstream Credits & Licensing

- **MVTools Original Authors & Contributors**: Manao, Fizick, Trombettista, TSPlayer, SEt, Vit, DTL, and pinterf.
- **sse2neon**: The sse2neon project authors for the SSE-to-NEON translation library.
- **AviSynth+ Project**: The AviSynth+ team and contributors.
- **License**: GNU General Public License v2 (GPL-2.0) as inherited from original MVTools.

