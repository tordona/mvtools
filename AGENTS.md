# Agent Guidelines & Engineering Rules: MVTools2

## 1. Technical Writing & Unit Standardization Rules

All technical documentation, code comments, AviSynth (`.avs`) profiles, benchmark outputs, and markdown guides must adhere to the following international typographic standards (NIST SP 811 §7.2, BIPM SI §5.4.3, CMOS §10.49, Microsoft Writing Style Guide):

### Spacing and Casing Rules
* **Mandatory Spacing:** A space must always separate a numerical quantity from its unit or unit abbreviation.
  * **Frame Rate:** `60 fps`, `24 fps`, `30 fps`, `120 fps` (never `60fps`, `24fps`).
  * **Rate Transitions:** `1080p 24 fps -> 60 fps`, `24 fps -> 60 fps`.
  * **Power:** `15 W`, `6 W`, `28 W`, `45 W`, `7 W – 15 W`, `~5 W`, `sub-8 W` (never `15W`, `6W`).
  * **Memory / Storage:** `16 GB`, `32 GB`, `64 GB`, `512 MB`, `128 MB`, `24 MB` (never `16GB`, `512MB`).
  * **Time & Latency:** `18 ms`, `5–25 ms`, `< 5.0 ms`, `40–60 s`, `20 s`, `2.0 s`, `5 s Warmup`.
  * **Pixel Dimensions:** `4 px Overlap` (never `4px`).
  * **Bit Depth:** Hyphenate as a compound modifier before nouns: `8-bit`, `10-bit`, `16-bit`, `32-bit` (e.g. `8-bit input`, `16-bit float`). Use `8 bit`, `16 bit` when describing bit depths without a hyphen.
  * **Frequency:** `60 Hz`, `120 Hz`, `3.4 GHz` in prose.
* **Unit Abbreviation Casing:**
  * Use **lowercase `fps`** alongside numbers and in sentences (`sustained 60 fps`, `output at 60.00 fps`).
  * Reserve **uppercase `FPS`** exclusively for the standalone initialism/acronym (Frames Per Second) or table column headers (`Avg FPS`, `1% Low FPS`).

### Critical Preserved Syntax Boundaries (Exceptions)
* **PowerShell Parser Multipliers:** Never modify `/ 1MB`, `/ 1GB`, or `/ 1KB` in `.ps1` arithmetic expressions. In PowerShell, these are compiler numeric literals.
* **Hardware CPUID Strings:** Never modify verbatim CPUID register text strings (e.g., `Intel(R) Core(TM) i5-7Y54 CPU @ 1.20GHz`) or baseline matrix filenames derived from CPUID strings.
* **Percentages:** In American English / computing style (CMOS §9.18), keep the percent sign closed up without a space: `88%`, `100%`, `12%` (not `88 %`).
* **Format Labels & Geometry:** `1080p`, `720p`, `4K`, `2x`, `4x`, and `16:9` are scanning labels, multipliers, and aspect ratios; they remain unspaced.
* **Language Keywords:** AviSynth core function names (`MFlowFps`, `MBlockFps`, `AssumeFPS`, `ChangeFPS`) and script variable names (`$targetFps`, `fps_num`, `fps_den`) must remain intact.

---

## 2. Objective Tone & Communication Rules
* **Zero Marketing Language:** Zero tolerance for promotional superlatives (*breakthrough, flawless, massive, rock-solid, dramatic*) or sensory metaphors (*whisper-quiet, sweet spot, razor-sharp, seamless*).
* Maintain strictly quantitative, empirical, and architectural descriptions.

---

## 3. Version Control & Operational Safety
* **No Unauthorized Commits/Pushes:** Never execute `git commit` or `git push` without explicit user instruction.
* **Local Profiles Untracked:** Keep machine-specific evaluation profiles (`AviSynth/Core-i7-9750H-*.avs` and `AviSynth/Xeon-E3-1535M-v6-*.avs`) strictly untracked.
---

## 4. Bidirectional Profile & Script Synchronization
* **Installer & Guide Parity:** Any modification to prompt generation, profile templates, parameter rules, or architectural invariants in `Install-MvToolsPotPlayer.ps1` (`Copy-AiAgentHardwarePrompt`) must be immediately mirrored in `AIAgentProfileGuide.md` (across both `Documentation/guides/` and `docs/guides/`), and vice-versa.
* **Dual Documentation Trees:** Ensure exact 1:1 file parity between `Documentation/guides/` and `docs/guides/` for all architectural markdown documentation.
