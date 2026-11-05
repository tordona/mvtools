# Custom AviSynth Profiles: Quick Generation Guide using AI Agents

This guide enables you to generate a custom 3-tier AviSynth+ interpolation profile set (`<Platform>-Eco.avs`, `<Platform>-Balanced.avs`, `<Platform>-MaxQuality.avs`) tailored to your exact CPU, GPU, and RAM in seconds using an AI coding assistant or web chatbot for real-time 60 fps video playback in Daum PotPlayer.

> [!NOTE]
> **No Git Cloning or Downloads Required:**  
> You do not need to clone the repository or install developer tools to generate custom profiles. Choose either **[Option 1: In an AI-Enabled IDE](#option-1-in-an-ai-enabled-ide-1-click-setup)** (for Cursor, Windsurf, Claude Code, or Google Antigravity) or **[Option 2: In a Web AI Assistant](#option-2-in-a-web-ai-assistant-chatgpt-claude-gemini)** (for browser chat) below.

---

## Option 1: In an AI-Enabled IDE (1-Click Setup)

If you use an agentic IDE (Google Antigravity, Cursor, Windsurf, Claude Code, or GitHub Copilot):

Paste this single instruction into your IDE agent:

```text
Read https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/docs/guides/AIAgentProfileGuide.md (append current Unix epoch timestamp as query parameter ?t=... when requesting). Auto-detect this machine's CPU/GPU hardware using Windows CIM/WMI, and generate the tailored 3-tier AviSynth profile set (<Platform>-Eco.avs, <Platform>-Balanced.avs, <Platform>-MaxQuality.avs) following the Step 1 & Step 2 architectural constraints.
```

### What the IDE Agent Does Autonomously:
1. **Hardware Autodetection:** Queries Windows CIM/WMI (`Get-CimInstance Win32_Processor`, `Win32_VideoController`, `Win32_PhysicalMemory`) to detect your physical core count, P/E core topology, L3 cache, DRAM bandwidth, and sustained TDP limits.
2. **Deterministic Script Writing:** Synthesizes `<Platform>-Eco.avs`, `<Platform>-Balanced.avs`, and `<Platform>-MaxQuality.avs` with architecture-specific block sizes, thread counts, memory limits, and core pinning.
3. **Deployment (Optional):** Places the files in your current directory or copies them directly into `C:\Program Files\DAUM\PotPlayer\AviSynth\`.

---

## Option 2: In a Web AI Assistant (ChatGPT, Claude, Gemini)

If you use a web chatbot in your browser (ChatGPT, Claude, Gemini, or Microsoft Copilot):

### Step 1: Copy the Prompt Template

> [!TIP]
> **Only the CPU model is required.** The AI assistant already knows its core architecture, cache topology, and integrated graphics engine. If you do not know your RAM or GPU, simply delete those lines or leave them blank.

Copy the prompt below, enter your CPU model, and paste it into your AI assistant:

```text
Please fetch the latest specification from:
https://raw.githubusercontent.com/tordona/mvtools/mvtools-d3d12/docs/guides/AIAgentProfileGuide.md?t=1
(Mandatory: Replace ?t=1 with the current Unix epoch timestamp or any random number when fetching the URL to guarantee an un-cached origin response).

Please generate a 3-tier AviSynth+ profile set (<Platform>-Eco.avs, <Platform>-Balanced.avs, <Platform>-MaxQuality.avs) for real-time 24 fps -> 60 fps video motion interpolation in Daum PotPlayer following the exact architectural specifications in that guide. Include `# Generator: <Your Model Name>` and `# Specification: AIAgentProfileGuide Rev 2.3.7` in each profile header.

Target Hardware:
- CPU (Required): [e.g. AMD Ryzen 7 7840U / Intel Core i7-12700H / Snapdragon X Plus]
- RAM (Optional): [e.g. 16 GB]
- GPU (Optional): [e.g. Radeon 780M / Intel Iris Xe / Adreno X1-85]
```

### Step 2: Save the Generated Profile Files
Your AI assistant will generate three scripts:
* `<Platform>-Eco.avs` (Low power, lowest battery drain)
* `<Platform>-Balanced.avs` (Recommended daily driver, fine-grained vector density)
* `<Platform>-MaxQuality.avs` (Highest fidelity coarse-to-fine refinement)

Save these files to your computer (e.g. into `C:\Program Files\DAUM\PotPlayer\AviSynth\` or your Documents folder).

---

## How to Load and Verify in PotPlayer

1. Open **Daum PotPlayer** and press **`F5`** to open **Preferences**.
2. Navigate to **Video** → **AviSynth**.
3. Check the box for **AviSynth script**.
4. Under **Load script**, click **Browse** and select your generated `<Platform>-Balanced.avs`.
5. Click **Apply**, then **OK**.
6. Play any 24 fps or 30 fps video, press **`Tab`** to toggle the On-Screen Display (OSD), and confirm the playback line reads `XX.XX fps -> 60.00 fps`.

---

## Advanced Benchmarking & Profile Tuning

If you experience dropped frames or want empirical verification with PresentMon ETW frame logging:
* See the **[AI Agent Profile Tuning & Specification Guide](guides/AIAgentProfileGuide.md)**.
* Learn how to run `Benchmarks/MvToolsBenchmark-Start.ps1` from the repository or extracted release package, capture frame pacing data, and use the Telemetry Diagnosis Matrix for closed-loop tuning.
