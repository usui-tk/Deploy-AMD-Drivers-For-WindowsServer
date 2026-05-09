# Deploy-AMD-Drivers-For-WindowsServer

PowerShell pipeline that makes AMD's consumer-targeted Ryzen chipset, Radeon graphics, and Ryzen AI NPU (XDNA) drivers installable on Windows Server 2025 by patching the INF `ProductType=3` decoration and re-signing the catalog with a self-generated certificate.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) [![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://learn.microsoft.com/en-us/powershell/) [![Target: Windows Server 2025](https://img.shields.io/badge/Target-Windows%20Server%202025-success.svg)](https://learn.microsoft.com/en-us/windows-server/get-started/windows-server-2025)

> **Read this twice before running anything.** This is a *last-resort, lab-only* tool. AMD does not officially support Windows Server 2025 for consumer Ryzen platforms (e.g. Cezanne / Renoir / Phoenix APUs in Lenovo ThinkCentre Tiny / ThinkPad / mini-PC builds). When official drivers exist, **always prefer those**. This repository exists for the narrow case where official Server-class drivers are unavailable and you are willing to operate a self-signed driver chain on your own hardware, at your own risk.

> **🆘 EXTRA WARNING for the NPU script (`Deploy-AMDNpuDriverOnWindowsServer.ps1`):** The NPU script is **markedly more dangerous and far less mature** than the chipset and graphics scripts. It is **unvalidated on physical NPU hardware** as of this writing, the AMD account auto-download flow is **best-effort and can break without notice** when AMD changes form layouts, and Ryzen AI Software (the user-mode stack required to actually use the NPU) is **officially unsupported on Windows Server 2025 by AMD**. Treat the NPU script as **experimental / research-grade**, not as a production tool. See [Risk classification](#risk-classification-of-the-three-scripts) below.

🇯🇵 **日本語版 README は [README.ja.md](./README.ja.md) を参照してください。**

---

## Table of Contents

- [Why this exists](#why-this-exists)
- [What's in the box](#whats-in-the-box)
- [Risk classification of the three scripts](#risk-classification-of-the-three-scripts)
- [Scope of coverage](#scope-of-coverage)
- [Quick start](#quick-start)
- [NPU-specific quick start](#npu-specific-quick-start)
- [Pipeline architecture (21 phases)](#pipeline-architecture-21-phases)
- [System requirements](#system-requirements)
- [Self-signed certificate: expiry, renewal, and revocation](#self-signed-certificate-expiry-renewal-and-revocation)
- [Disclaimer & at-your-own-risk acknowledgements](#disclaimer--at-your-own-risk-acknowledgements)
- [Troubleshooting](#troubleshooting)
- [Development tools](#development-tools)
- [References](#references)
- [License](#license)
- [Contributing](#contributing)

---

## Why this exists

When you install Windows Server 2025 on a consumer-class AMD platform (Ryzen 4000 / 5000 / 6000 / 7000 / 8000 mobile / desktop APU, plus discrete Vega / Polaris / RDNA Radeon GPUs, plus Ryzen AI 300 / AI Max 300 with NPU) several AMD devices end up bound to **Microsoft's generic in-box drivers** (`machine.inf`, `pci.inf`, `hdaudbus.inf`, `display.inf`) or remain unbound entirely (NPU). The reasons are two-fold:

1. **AMD's INF files contain a `ProductType=1` (Workstation) restriction** in the `[Manufacturer]` decoration. Windows Setup honours this and refuses to bind the driver on a Server SKU (`ProductType=3`).
2. **AMD's catalog (.cat) signature attests to the original INF.** Even if you patch the INF to add Server decorations, the signature is invalidated and the driver fails kernel-mode signing checks — which Windows Server 2025 enforces strictly via Secure Boot and HVCI.

This pipeline solves both problems by:

- Parsing AMD's Workstation `[Manufacturer]` decorations and **mirroring each one with `ProductType=3` (Server)**, leaving the original Workstation entries intact (so the patched INF is bi-compatible).
- Generating a fresh `.cat` catalog with `inf2cat /os:Server2025_X64`.
- **Signing the catalog with a self-generated code-signing certificate**, importing the cert into `LocalMachine\Root` + `LocalMachine\TrustedPublisher`, and authorising the cert as a kernel-mode signer via a **WDAC supplemental Code Integrity policy** (which keeps Secure Boot **on** — no `bcdedit /set testsigning on` required on Windows Server 2022+ / Windows 11 22H2+).

---

## What's in the box

| File | Purpose | Maturity |
| --- | --- | --- |
| `Deploy-AMDChipsetDriverOnWindowsServer.ps1` | Chipset driver pipeline (GPIO, SMBus, PSP, MicroPEP, PMF, etc.). Source: AMD Chipset Software ~75 MB EXE, ~67 INFs. | **Stable** — validated on M75q Tiny Gen 2 (WS2025) and X13 Gen 1 AMD (Win11 LTSC 2024). |
| `Deploy-AMDGraphicsDriverOnWindowsServer.ps1` | Graphics driver pipeline (Display, HD Audio, Audio CoProcessor, ACP, USB-C UCSI, etc.). Source: AMD Adrenalin Edition ~600 MB EXE, ~19 INFs (Vega-Polaris Legacy branch) or ~67 INFs (Main Adrenalin branch for Phoenix+). | **Stable** — same validation hosts as chipset. |
| **`Deploy-AMDNpuDriverOnWindowsServer.ps1`** | **NPU (Ryzen AI XDNA) driver pipeline (PHX/HPT/STX/KRK).** Source: AMD Ryzen AI Software ZIP, ~250 MB, EULA-gated download (no public direct URL). Kernel-mode driver only — does NOT install Ryzen AI Software user-mode stack. | **🆘 Experimental / research-grade — NOT production-ready.** No physical-NPU validation runs have been performed. AMD account auto-download is best-effort and may break with AMD form changes. Ryzen AI Software is officially unsupported on Windows Server 2025. |
| `README.md` | This document. |  |
| `README.ja.md` | Japanese translation. |  |
| `TESTING.md` | Cloud (AWS) testing procedure and physical-hardware validation results. Includes the NPU script's far weaker validation status. |  |
| `TESTING.ja.md` | Japanese translation of TESTING.md. |  |
| `CONTRIBUTING.md` | How to file issues, propose changes, and run regression tests. |  |
| `LICENSE` | MIT License. |  |
| `tools/psa.py` | PowerShell static analyzer used in CI to validate the pipeline scripts. See [Development tools](#development-tools). |  |
| `tools/README.md` | psa.py usage guide. |  |

All three PowerShell scripts share the same 21-phase architecture, the same self-signing model, and the same WDAC authorisation path. They write to separate workspaces (`C:\AMD-Chipset-WS`, `C:\AMD-Graphics-WS`, `C:\AMD-NPU-WS`) and use separate self-signed certificates so they never collide.

---

## Risk classification of the three scripts

> This section exists because the NPU script is materially riskier than its sister scripts and operators must understand the difference before running it.

| Aspect | Chipset script (r47) | Graphics script (r16) | **NPU script (r1)** |
| --- | --- | --- | --- |
| **Maturity** | Stable, multiple validation cycles | Stable, multiple validation cycles | **🆘 Experimental — first release, not validated on physical NPU hardware** |
| **Distribution format** | Public EXE direct download | Public EXE direct download | **EULA-gated ZIP, requires AMD account** |
| **Public download URL** | Yes (direct) | Yes (direct) | **No — requires AMD account login + EULA acceptance per release** |
| **AMD account auto-download** | N/A | N/A | **Best-effort; depends on AMD's form HTML staying stable; can break without notice** |
| **OS support stance** | AMD does not officially support, but drivers run | AMD does not officially support, but drivers run | **Driver loads on Server 2025, but Ryzen AI Software (user-mode stack) does NOT work on Server 2025 per AMD docs** |
| **Hardware availability** | Common (any AMD APU machine) | Common (any AMD GPU/APU machine) | **Limited to Ryzen AI 300 / Ryzen AI Max 300 / Ryzen 7040/8040 series** |
| **Test fixtures available in repo** | M75q Tiny Gen 2, X13 Gen 1 AMD | M75q Tiny Gen 2, X13 Gen 1 AMD | **NONE — no physical NPU machine in the maintainer's lab as of this writing** |
| **Inference workload viability on Server 2025** | N/A | Limited (no DirectX) | **Effectively zero — kernel driver alone is insufficient; user-mode VitisAI EP / OGA stack are Windows-11-only per AMD** |
| **Recommended use** | Lab + cautious production | Lab + cautious production | **Lab / research only. Do not deploy on production hosts.** |
| **Recommended Action mode** | `Install` after `PrepareVerify` review | `Install` after `PrepareVerify` review | **`PrepareVerify` ONLY until you can confirm the host is a real NPU machine and you accept that Ryzen AI Software won't function on Server 2025** |

**Practical rules of thumb for the NPU script**:

1. **Do not run `-Action Install` on a host you cannot afford to roll back.** The cleanup path is implemented but driver-store removal is best-effort and may require manual `pnputil /delete-driver oemNN.inf /force` cleanup.
2. **The Ryzen AI Software user-mode stack** (Python conda env + ONNX Runtime VitisAI EP + OGA) **is officially Windows-11-only.** Even if the kernel driver loads on Server 2025, you will not be able to run inference workloads through the supported stack. Do not expect AI workload functionality on Server 2025; the kernel driver is at most an experiment in driver bring-up.
3. **There are no physical-NPU validation runs yet.** All current verification is pipeline-soundness on EPYC EC2 (where the NPU is absent) and code-review of the AMD-published `quicktest.py` detection logic translated to PowerShell. **Real hardware behaviour is unconfirmed.**
4. **AMD's account auto-download flow can break without notice.** AMD periodically updates their `account.amd.com` form structure, CSRF token names, and EULA acceptance endpoint. The script's Tier 2 authentication is best-effort. **Always prefer Tier 4 (`-OfflineZip`)** for reproducible runs.

If after reading the above you still want to run the NPU script: see [NPU-specific quick start](#npu-specific-quick-start).

---

## Scope of coverage

### Hardware in scope

- **AMD Ryzen Mobile**: Ryzen 4000 (Renoir), 5000 (Cezanne / Lucienne / Barcelo / Barcelo-R), 6000 (Rembrandt), 7000 (Phoenix / Hawk Point), 8000 (Hawk Point refresh), AI 300 (Strix Point / Krackan Point), AI Max 300 (Strix Halo).
- **AMD Ryzen Desktop APU**: Ryzen 5000G / 5000GE (Cezanne), 7000G / 8000G (Phoenix).
- **AMD Radeon Graphics**: Vega 6 / 7 / 8 / 11 (integrated, Renoir → Cezanne → Barcelo), RDNA 3 (Phoenix 780M / 760M), RDNA 3.5 (Strix Point), discrete RX 5000 / 6000 / 7000 / 9000 series.
- **AMD AM4 / AM5 chipsets**: X470, X570, X670/X670E, X870/X870E, B450, B550, B650, B850.
- **AMD ACPI devices**: GPIO controllers (`AMDI0030`, `AMDF030`), I2C (`AMD0010`), Micro PEP (`AMD0004`), HSMP (`AMDI0097`), PMF (`AMDI0100` / `AMDI0102`), SFH (`AMDI0080` / `AMDI0011`), UART (`AMD0020`), Wireless Button (`AMDI0051`), Pluton stub (`MSFT0200` / `MSFT0201`).
- **AMD NPU / XDNA Compute Accelerator** *(experimental, NPU script only)*:
  - **Phoenix / Hawk Point** (`PCI\VEN_1022&DEV_1502&REV_00`) — Ryzen 7040 / 8040 / 8040 PRO mobile series. Driver build `32.0.203.280` (RAI 1.5).
  - **Strix Point / Strix Halo** (`PCI\VEN_1022&DEV_17F0&REV_00/10/11`) — Ryzen AI 300 / Ryzen AI Max 300 series. Driver build `32.0.203.314` (RAI 1.6.1) or newer.
  - **Krackan Point** (`PCI\VEN_1022&DEV_17F0&REV_20`) — Ryzen AI 200 series. Driver build `32.0.203.314` (RAI 1.6.1) or newer.

### Hardware **out of scope**

- **AMD EPYC server chips** (CPUs found in AWS T3a / M5a / M6a / M7a / M8a, Hetzner AX dedicated, etc.): EPYC uses a different chipset model and ships first-party Server-supported drivers via Microsoft Update. This pipeline targets *consumer* Ryzen, not EPYC. AWS instances are nonetheless useful for **pipeline regression testing** — see [TESTING.md](./TESTING.md).
- **Real-time GPU compute stacks** (ROCm, HIP SDK, OpenCL beyond the user-mode driver shipped in the Adrenalin package): consult AMD's ROCm documentation for Server.
- **Ryzen AI Software user-mode stack** (Python conda env, ONNX Runtime VitisAI Execution Provider, OnnxRuntime GenAI/OGA, Vitis AI Quantizer, Lemonade SDK, etc.): **out of scope of the NPU script.** The NPU script installs the kernel-mode driver only. Ryzen AI Software must be installed separately by the operator from the AMD installer at <https://account.amd.com/en/forms/downloads/xef.html?filename=ryzen-ai-lt-1.7.1.exe>, and per AMD documentation it is officially supported on Windows 11 build >= 22621.3527 only.

### What the scripts produce

```
C:\AMD-Chipset-WS\               (or C:\AMD-Graphics-WS\, or C:\AMD-NPU-WS\)
├── download\        AMD installer EXE / NPU driver ZIP
├── extracted\       Original INFs and binaries from the EXE / ZIP
├── patched\         Patched INFs with mirrored ProductType=3 sections
│                    + generated .cat files + signtool signatures
├── cert\            Self-signed code-signing cert (PFX + CER) +
│                    WDAC supplemental policy XML/CIP (NPU + others)
└── inf_inventory.csv / inf_inventory_report.txt
                     P05 inventory and per-INF analysis
```

After `-Action Install` (or phases I01-I04), the script also deploys:

- The cert to `LocalMachine\Root` + `LocalMachine\TrustedPublisher`.
- A **WDAC supplemental Code Integrity policy** to `C:\Windows\System32\CodeIntegrity\CiPolicies\Active\` that allowlists this specific cert as a kernel-mode signer. This is activated immediately via `CiTool --update-policy` (no reboot required on Windows Server 2022+ / Windows 11 22H2+).
- The patched + self-signed drivers via `pnputil /add-driver /install`.

---

## Quick start

### Prerequisites

- Windows Server 2025 host (build 26100), or Windows 11 24H2 (build 26100) for **preview-only verification** (the script will block `Install` phases on Workstation OS unless `-AllowWorkstationInstall` is passed; see [TESTING.md](./TESTING.md) for the WS2025 pre-migration verification workflow).
- PowerShell 5.1 or higher (Desktop or Core), 64-bit, running as Administrator.
- Internet connectivity (for AMD installer download and Windows SDK / WDK installation via `winget`).
- ~5 GB free disk space on the workspace volume (~7 GB if you also run the NPU script — Ryzen AI ZIPs are ~250 MB plus extracted contents).

### Get the scripts

```powershell
# Option 1: clone the repository
git clone https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer.git
cd Deploy-AMD-Drivers-For-WindowsServer

# Option 2: download a release ZIP from
# https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/releases
```

### One-shot dry run (safe; modifies nothing)

```powershell
# In an elevated PowerShell session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot

# NPU script — REQUIRES an offline ZIP (or other download source) to actually run P03.
# On a clean machine without -OfflineZip, P03 will throw "All 4 download tiers exhausted".
# See the NPU-specific quick start below for the full pattern.
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot `
    -OfflineZip .\NPU_RAI1.7.1_380_WHQL.zip -AssumeIfMissing
```

`PrepareVerify` runs `P00-P09` (download, extract, patch, generate catalog, sign) followed by `V01-V06` (verify artefacts, dry-run install plan, hardware impact analysis). **No system state is modified** — no certs are imported, no WDAC policy is deployed, no drivers are installed. Read the V05 / V06 output to understand exactly what `Install` *would* do.

### Full installation (chipset and graphics)

```powershell
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Install
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Install
```

Run on a Windows Server 2025 host. Both scripts are idempotent and cleanup-safe (`-Action Cleanup` removes the workspace, the certs from the trust stores, and the deployed WDAC policy).

> **NPU script `Install`**: see [NPU-specific quick start](#npu-specific-quick-start). The `Install` action requires extra preconditions (offline ZIP availability or AMD account credentials) and is **not recommended without physical NPU hardware**.

### Selective phase execution

```powershell
# Just regenerate the patched INFs and catalogs without re-downloading
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action Prepare -OnlyPhases P05,P06,P08,P09

# Run only the cert-trust phase
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action Install -OnlyPhases I01

# List all phases the script knows about
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action ListPhases
```

---

## NPU-specific quick start

> **Reminder**: this script is experimental. Read [Risk classification of the three scripts](#risk-classification-of-the-three-scripts) before continuing.

### Step 1 — obtain the NPU driver ZIP (one of the four tiers)

The NPU script supports **four download tiers** in priority order:

| Tier | Method | When to use |
| --- | --- | --- |
| **1** | `-InstallerUrl <url>` explicit URL | You already have a fresh AMD CDN URL (e.g. from an `entitlenow.com` link captured in a browser session). |
| **2** | `-AmdAccountUser <email> -AmdAccountPassword <SecureString> -ForceAmdAccountAuth` | Attempt EULA acceptance flow automatically. **❌ Disabled by default since 2026-05-10 verification found `account.amd.com` is a JavaScript-driven SPA. Use `-ForceAmdAccountAuth` to opt in (expected to fail on the current AMD portal).** See TESTING.md §4.6 for the full verification report. |
| **3** | EULA-gated direct fetch probe | Automatic; almost always falls through (AMD requires JS-driven submission). |
| **4** ★ | `-OfflineZip <path>` or sibling `NPU_RAI*_WHQL.zip` in the script directory | **Recommended.** Manually download the ZIP once, place it next to the script. Reproducible across runs. |

For Tier 4, manually download the ZIP from the AMD documentation page:

- <https://ryzenai.docs.amd.com/en/latest/inst.html#install-npu-drivers>
- Click the appropriate driver link for your detected NPU (e.g. NPU Driver 32.0.203.314 for STX/KRK, RAI 1.6.1).
- Sign in to your AMD account, accept the EULA, save the ZIP locally (typical filename: `NPU_RAI1.6.1_314_WHQL.zip`).

### Step 2 — dry run (no system state modified)

The recommended pattern is **`-Action PrepareVerify` + `-OfflineZip`**. With `-OfflineZip`, the 4-tier resolution short-circuits at the Tier 4 priority block (line 824 of the script) and your local ZIP is used immediately — no AMD network calls, no form-parsing fragility.

```powershell
# RECOMMENDED — pipeline soundness check, system state UNCHANGED.
# OfflineZip is taken from the Tier 4 priority block immediately; no AMD network calls.
# On a real NPU host (Ryzen AI 300 / AI Max 300 / 7040 / 8040 series):
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action PrepareVerify `
    -CleanWorkRoot `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip
```

```powershell
# RECOMMENDED for AWS EPYC pipeline regression — same as above plus -AssumeIfMissing.
# When P03 detects no NPU device, the script falls back to the default Strix Point profile
# instead of failing. Useful only for testing the pipeline mechanics; produces 0 device bindings.
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action PrepareVerify `
    -CleanWorkRoot `
    -OfflineZip .\NPU_RAI1.7.1_380_WHQL.zip `
    -AssumeIfMissing                            # default Strix Point + RAI 1.7.1
```

```powershell
# DISCOURAGED — pipeline check WITHOUT -OfflineZip on a clean machine.
# This command will:
#   Tier 1 (-InstallerUrl)            : skipped (not provided)
#   Tier 4 priority (-OfflineZip)     : skipped (not provided)
#   Tier 2 (AMD account auto-download): skipped (no credentials)
#   Tier 3 (EULA-gated direct probe)  : almost always falls through (HTML form)
#   Tier 4 auto-scan                  : checks script dir, ./cache, workspace, ~/Downloads
# If -CleanWorkRoot has wiped the workspace AND no NPU_RAI*_WHQL.zip is in any of the
# auto-scan locations, P03 will throw "All 4 download tiers exhausted".
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot
```

### Step 3 — install (only if you have real NPU hardware AND have read all warnings)

```powershell
# RECOMMENDED — full install using a manually-downloaded offline ZIP.
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action Install `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip
# I00 will require you to type "I AGREE" to acknowledge:
#   1) AMD Ryzen AI EULA acceptance
#   2) Ryzen AI Software being officially Windows-11-only
#   3) Kernel-mode driver only (user-mode stack must be installed separately)
#   4) BitLocker recovery keys recorded
```

After successful installation, the script prints a guidance block reminding you that **Ryzen AI Software (Python conda env, OGA, Vitis AI EP) must be installed separately** from <https://account.amd.com/en/forms/downloads/xef.html?filename=ryzen-ai-lt-1.7.1.exe>, and that this user-mode stack is officially supported on Windows 11 build >= 22621.3527 only — **not on Windows Server 2025**.

### Useful NPU-specific switches

The NPU script tracks **two independent versioning axes** plus a **separate compatibility evaluation axis**, per AMD's [Ryzen AI Software installation documentation](https://ryzenai.docs.amd.com/en/latest/inst.html):

| Axis | Parameter | Default | What it controls |
|---|---|---|---|
| **A. NPU kernel-mode driver** | `-NpuDriverPackage` | `latest` (= `NPU_RAI1.6.1_314`) | Which NPU driver ZIP package the script targets. AMD currently publishes only two: `NPU_RAI1.5_280` (driver 32.0.203.280) and `NPU_RAI1.6.1_314` (driver 32.0.203.314). Both cover all NPU codenames (PHX/HPT/STX/STH/KRK). Driver versioning evolves slowly. |
| **B. Ryzen AI Software (user-mode stack)** | `-RyzenAiSoftwareVersion` | `latest` (= `1.7.1`) | Which Ryzen AI Software version is referenced in the post-install guidance (you install the EXE separately). AMD recommends **always using the latest** for end-user workloads. |
| **C. Compatibility evaluation** | (automatic) | n/a | Computed from A + B at P03. Currently AMD documents that all RAI versions require driver `≥ 32.0.203.280`, so both `280` and `314` are compatible with RAI `1.5` through `1.7.1`. |

Switches in column A and B are **independent**. They do not need to share a version label; e.g. `-NpuDriverPackage NPU_RAI1.6.1_314 -RyzenAiSoftwareVersion 1.7.1` is a valid, AMD-supported combination (newer driver + latest RAI Software).

These switches **modify behaviour but do not provide a download source** by themselves. Always combine them with `-OfflineZip`, `-InstallerUrl`, or `-AmdAccountUser`/`-AmdAccountPassword -ForceAmdAccountAuth` (Tier 4 / Tier 1 / Tier 2 respectively).

```powershell
# Force a specific NPU codename (when CPU name detection is ambiguous; e.g. PHX vs HPT).
# Combine with -OfflineZip for predictable behaviour:
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action PrepareVerify `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip `
    -NpuOverride STX                            # PHX | HPT | STX | KRK

# Pin a specific NPU driver package (axis A). Note: -NpuDriverPackage selects which
# package the script reasons about. Your -OfflineZip must match the same package.
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action Install `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip `
    -NpuDriverPackage NPU_RAI1.6.1_314          # NPU_RAI1.5_280 | NPU_RAI1.6.1_314 | latest

# Pin a specific Ryzen AI Software version (axis B). Default 'latest' is recommended.
# This affects only the post-install guidance message - the user installs the
# Ryzen AI Software EXE separately via the AMD download page.
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action Install `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip `
    -RyzenAiSoftwareVersion latest              # 1.5 | 1.6.1 | 1.7 | 1.7.1 | latest

# AMD account auto-download (Tier 2 — DISABLED by default since 2026-05-10 verification.
# Pass -ForceAmdAccountAuth to opt in. Expected to fail on current AMD SPA portal.)
$cred = Get-Credential -UserName 'you@example.com' -Message 'AMD account password'
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action Install `
    -ForceAmdAccountAuth `
    -AmdAccountUser $cred.UserName `
    -AmdAccountPassword $cred.Password
```

> **Common pitfall**: running `-Action Install -NpuOverride STX -NpuDriverPackage NPU_RAI1.6.1_314` **without** specifying any download source will fall through to Tier 4 auto-scan and silently use whatever `NPU_RAI*_WHQL.zip` happens to be in `~/Downloads` — which may or may not match the package you specified. **Always pin the source explicitly**.

---

## Pipeline architecture (21 phases)

| Group | ID | Name | What it does |
| --- | --- | --- | --- |
| Prep | P00 | Initialize | OS detection, admin/TLS pre-flight, WS2025-preview-mode banner if Workstation; the NPU script also prints a Ryzen-AI-Software OS-support warning |
| Prep | P01 | PrepareWorkspace | Create `C:\AMD-{Chipset,Graphics,NPU}-WS\` |
| Prep | P02 | AcquireTools | Install 7-Zip, Windows SDK (signtool) and Windows WDK (inf2cat) via `winget`, fall back to direct EXE |
| Prep | P03 | FetchInstaller | Detect host AMD platform; resolve the latest installer URL from amd.com (chipset/graphics) or run the 4-tier resolution (NPU); download |
| Prep | P04 | ExtractInstaller | 7-Zip extraction; the NPU script also handles nested ZIP detection |
| Prep | P05 | AnalyzeInfs | Inventory every INF, classify by source variant (W11x64 / WTx64 / WT6A_INF / WT64A; for NPU: PHX/HPT vs STX/KRK), and select those in scope for the host OS / NPU |
| Prep | P06 | PatchInfs | For INFs lacking Server decorations, mirror each Workstation `[Manufacturer]` entry with `ProductType=3`; copy already-Server-compatible INFs to the patched folder so they reach the install pipeline |
| Prep | P07 | CreateCertificate | Self-sign a 4096-bit RSA / SHA-384 code-signing cert (5-year validity), exported as PFX and CER |
| Prep | P08 | GenerateCatalogs | `inf2cat /os:Server2025_X64` for each patched INF folder |
| Prep | P09 | SignCatalogs | `signtool sign /fd SHA384 /td SHA384 /tr <timestamp-url>` on every catalog |
| Verify | V01 | VerifyArtifacts | Confirm cert + patched INFs + catalogs all exist |
| Verify | V02 | VerifyCertificate | Decode the PFX, check EKU, validity, key length |
| Verify | V03 | VerifyCatalogs | `signtool verify /pa` (expected to fail until I01 trusts the cert) |
| Verify | V04 | VerifyInfs | Re-parse patched INFs and confirm `ProductType=3` decoration coverage |
| Verify | V05 | DryRunInstall | Simulate I01-I03 against `Win32_PnPSignedDriver`; predict every install / skip / upgrade decision; produce the install plan |
| Verify | V06 | HardwareImpactAnalysis | Enumerate AMD hardware on this host, compare AS-IS drivers against TO-BE patched drivers, classify upgrade risk (HIGH / MEDIUM / LOW); the NPU script also reminds the operator about the Ryzen AI Software user-mode stack |
| Inst | I00 | PreInstallReview | Print the V06 risk summary; require operator acknowledgement (NPU script: also requires explicit `I AGREE` for the Ryzen AI EULA) |
| Inst | I01 | TrustCertificate | Import CER into `LocalMachine\Root` + `LocalMachine\TrustedPublisher` |
| Inst | I02 | AuthorizeDriverSigning | Build + deploy the WDAC supplemental policy that allowlists this cert as a kernel-mode signer (default path); fall back to `bcdedit /set testsigning on` only if `-UseTestSigning` is passed |
| Inst | I03 | InstallDrivers | `pnputil /add-driver <patched.inf> /install` for every in-scope INF |
| Inst | I04 | PostInstallVerification | Re-enumerate AMD hardware, confirm `[C] Self-signed` driver bound to each target device; the NPU script also displays Ryzen AI Software user-mode stack installation guidance |

---

## System requirements

- **CPU**: AMD Ryzen 4000 series or newer (the script's `Get-AmdChipsetPlatform` heuristic recognises 4000 → AI 300, AI Max 300; older silicon may run but is untested). For the NPU script: Ryzen 7040 / 8040 / AI 300 / AI Max 300 / AI 200 series with an integrated NPU.
- **OS**: Windows Server 2025 (build 26100) is the production target. Windows 11 24H2 (build 26100) is supported as a *preview* host (see [TESTING.md](./TESTING.md)). Windows Server 2016 / 2019 / 2022 are recognised by the OS profile matrix and inf2cat will pick a corresponding `/os:` switch (e.g. `Server2016_X64`, `ServerRS5_X64`, `ServerFE_X64`), but production usage on those versions is out of scope for this README.
- **PowerShell**: 5.1 (Windows PowerShell Desktop) or 7.x (PowerShell Core). The script's `Show-PowerShellEnvironment` phase prints the compatibility matrix it sees.
- **Disk**: ~5 GB on the workspace volume (~7 GB if you also run the NPU script).
- **Network**: outbound HTTPS to `*.amd.com`, `download.microsoft.com`, `go.microsoft.com`, `aka.ms` (winget), `timestamp.digicert.com` (signing timestamp), and (for the NPU script with Tier 2 download) `account.amd.com` and `*.entitlenow.com`.
- **Privileges**: Administrator on the local machine. No domain rights are required.

---

## Self-signed certificate: expiry, renewal, and revocation

The certificate generated in P07 is the **trust anchor** for every patched driver this pipeline installs. It deserves its own section.

### Certificate properties

- **Subject**:
  - `CN=AMD Chipset Driver Self-Sign (WS2025 Lab, At Own Risk)` (chipset)
  - `CN=AMD Graphics Driver Self-Sign (WS2025 Lab, At Own Risk)` (graphics)
  - `CN=AMD NPU Driver Self-Sign (WS2025 Lab, At Own Risk)` (NPU)
- **Key**: RSA 4096-bit, SHA-384 signature algorithm.
- **EKU**: Code Signing (`1.3.6.1.5.5.7.3.3`).
- **Validity**: **5 years from the day P07 ran**. Hard-coded in the script.
- **Storage**: PFX in `C:\AMD-{Chipset,Graphics,NPU}-WS\cert\`. The PFX is **not** password-protected by default (this is a lab tool; if you need a real password, change `[string]$PfxPassword = ''` in the param block).
- **Trust anchor for**: every `.cat` file under `patched\`, the WDAC supplemental policy, and (via I01) `LocalMachine\Root` + `LocalMachine\TrustedPublisher`.

### What happens at year 5

After the certificate expires:

- The catalog signatures embedded in `.cat` files **remain valid for files installed before expiry**, because Windows checks the signing timestamp (which proves the signature was made while the cert was valid) — *not* the cert's current validity at boot. This is identical to how every WHQL-signed driver works long after the AMD / Microsoft signing cert has rotated.
- However, **adding new patched drivers** with the expired cert via `pnputil /add-driver` will fail.
- **Re-running this script** after expiry is the recovery path. It generates a *new* cert (different thumbprint, same subject), re-signs the catalogs, and re-imports the new cert. Existing installed drivers are untouched and continue to work.

### Renewal procedure (every 5 years, or sooner if compromised)

```powershell
# 1. Roll the cert and re-sign everything
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Prepare -OnlyPhases P07,P08,P09
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Prepare -OnlyPhases P07,P08,P09
.\Deploy-AMDNpuDriverOnWindowsServer.ps1      -Action Prepare -OnlyPhases P07,P08,P09

# 2. Trust the new cert (the old one stays trusted until you remove it)
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Install -OnlyPhases I01,I02
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Install -OnlyPhases I01,I02
.\Deploy-AMDNpuDriverOnWindowsServer.ps1      -Action Install -OnlyPhases I01,I02

# 3. Add the freshly-signed drivers to the store (binds existing devices to the new sig)
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Install -OnlyPhases I03
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Install -OnlyPhases I03
.\Deploy-AMDNpuDriverOnWindowsServer.ps1      -Action Install -OnlyPhases I03

# 4. Optionally remove the old cert
$old = 'OLD-THUMBPRINT-FROM-PREVIOUS-RUN'
Get-ChildItem 'Cert:\LocalMachine\Root', 'Cert:\LocalMachine\TrustedPublisher' |
  Where-Object Thumbprint -EQ $old | Remove-Item
```

### Revoking the cert

If you suspect the PFX has leaked, immediately:

```powershell
# 1. Cleanup — removes cert from trust stores, deletes WDAC policy, removes drivers
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Cleanup
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Cleanup
.\Deploy-AMDNpuDriverOnWindowsServer.ps1      -Action Cleanup

# 2. Reboot to ensure WDAC policy unload (the script attempts a CiTool --refresh, but a
#    reboot guarantees no residual signing-authority is in the kernel)
Restart-Computer
```

After reboot, re-run the full pipeline to generate a new cert.

### Why 5 years? Why self-signed?

- **5 years** matches the upper bound for Microsoft's own kernel-mode signing certs (rotated every 1-3 years, but issued for up to 5). Long enough that you don't think about it monthly; short enough that a leaked cert has bounded blast radius.
- **Self-signed** because no public CA issues code-signing certs for arbitrary hobbyists patching consumer drivers. EV Code Signing certs from Sectigo / DigiCert require business verification (~$300-600/year) and won't issue if the patching activity violates AMD's EULA.

This is *intentionally* a lab tool. **If you are deploying this in production at scale, you should either: (a) negotiate Server-class drivers from AMD directly, or (b) use a properly managed code-signing CA, not this self-signed model.**

---

## Disclaimer & at-your-own-risk acknowledgements

By running these scripts, you acknowledge:

1. **No warranty.** The scripts are provided "as is" under MIT License. There is no guarantee that they will work on your hardware, will not damage your installation, or will be supported in future Windows updates. See `LICENSE`.

2. **You are the publisher of record.** Patching AMD's INFs and re-signing them with your own certificate makes *you* — not AMD, not Microsoft — the cryptographic publisher of those drivers from Windows' point of view. If a patched driver causes a BSOD, system instability, or data loss, the bug is attributed to your self-signed cert, not to AMD.

3. **AMD's End User License Agreement** for the chipset / graphics / Ryzen AI installers permits redistribution under specific terms. Re-signing modified INFs is a grey area; you should read AMD's EULA for your specific package and form your own judgement. **This repository takes no position on whether your use is permitted under AMD's terms.** For Ryzen AI specifically, the EULA must be accepted at <https://account.amd.com/en/forms/downloads/ryzenai-eula-public-xef.html> before downloading; the NPU script's I00 phase requires explicit `I AGREE` confirmation that this acceptance has occurred.

4. **Microsoft's Windows Hardware Lab Kit (HLK) certification is invalidated** for any driver this pipeline replaces. WHQL-signed drivers carry Microsoft's attestation that they passed HLK; self-signed drivers do not. If you rely on Microsoft Premier Support for the affected hardware, your support contract may not cover issues caused by self-signed drivers.

5. **BitLocker, TPM, and Secure Boot interactions.** The chipset script's PSP driver replacement (`amdpsp.inf`) interacts with Platform Security Processor firmware. On systems with BitLocker enabled, a failed PSP driver upgrade can trigger BitLocker recovery prompts on next boot. **Always have your BitLocker recovery key recorded before running `-Action Install` on the chipset script.**

6. **Anti-cheat software (Easy Anti-Cheat, BattlEye, Vanguard, etc.)** may flag self-signed kernel-mode drivers. This pipeline is not intended for gaming workloads on competitive titles and may result in account bans if used as such.

7. **The 5-year cert expiry is real.** Schedule a renewal task in your calendar for year 4.5 of any production deployment, or accept that drivers stop installing in year 5.

8. **NPU script (`Deploy-AMDNpuDriverOnWindowsServer.ps1`) is markedly higher-risk than its sister scripts.** Specifically:
   - **No physical-NPU validation** has been performed by the maintainers as of this writing. All testing has been pipeline-soundness on EPYC EC2 hosts (where no NPU is present) and code-review of the AMD-published `quicktest.py` detection logic translated to PowerShell.
   - **AMD account auto-download (Tier 2) is best-effort and may break without notice** when AMD updates `account.amd.com` form layouts, CSRF handling, or the entitlenow.com CDN URL scheme. Always prefer Tier 4 (`-OfflineZip`) for reproducible runs.
   - **Ryzen AI Software is officially Windows-11-only per AMD documentation** (build >= 22621.3527). Even if the NPU kernel driver loads on Windows Server 2025, the user-mode stack (Python conda env, ONNX Runtime VitisAI EP, OGA) is not expected to function. **Do not deploy the NPU script in environments expecting AI inference workloads on Server 2025.**
   - **Driver-store cleanup is best-effort.** Removing self-signed NPU drivers from the driver store after `-Action Install` may require manual `pnputil /delete-driver oemNN.inf /force` or use of Driver Store Explorer (Rapr.exe).

9. **No commercial support is offered through this repository.** GitHub Issues at <https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/issues> are best-effort for bug reports and clarification questions. Pull requests are welcome but not guaranteed to be reviewed on any timeline.

---

## Troubleshooting

### "OS detected: Windows Server 2025 (build 26100) [WS2025] but ProductType: 1"

You are running on Windows 11 24H2 (which shares NT build 26100 with Windows Server 2025). The script intentionally maps Win11 24H2 to the WS2025 profile because they share kernel ABI. `Install` phases are blocked on Workstation OS by default; use `-Action PrepareVerify` only, or pass `-AllowWorkstationInstall` if you really want to install on Win11 (read the warnings first). See [TESTING.md](./TESTING.md) for the pre-migration verification workflow.

### "P02 takes 2-3 minutes to install the WDK"

The Windows WDK download is ~2.5 GB. This is a one-time install per machine. Subsequent runs reuse the installed `inf2cat.exe` and complete P02 in under a second.

### "P03 fails with 'no AMD installer URL resolved'"

AMD periodically reorganises their support pages. The script probes 3-6 candidate URLs; if all return 0 hits, the parser broke. Workarounds:

- Pass `-InstallerUrl https://drivers.amd.com/drivers/...` to skip URL discovery and download a specific version.
- Open the `Probe results:` block in P03 output and visit each URL manually to confirm AMD's site changed.
- File an issue: <https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/issues>

### NPU script "All 4 download tiers exhausted"

This is the most common NPU-script failure. The EULA-gated AMD form requires an authenticated AMD account session that the script cannot fully simulate. Workarounds in priority order:

1. **Manually download** the ZIP from <https://ryzenai.docs.amd.com/en/latest/inst.html#install-npu-drivers>, place it next to the script, re-run with `-OfflineZip .\NPU_RAI*.zip`.
2. **Try `-AmdAccountUser` / `-AmdAccountPassword`** but expect breakage; AMD form structure changes are not announced.
3. **Capture the entitlenow.com URL** from a browser session after manual EULA acceptance, pass via `-InstallerUrl <captured-url>`. The URL has a time-limited hash; download immediately after capture.

### NPU script "No AMD NPU detected via pnputil"

The host has no AMD NPU device. Either:

- This is intentional (AWS EPYC pipeline regression run): pass `-AssumeIfMissing` to proceed with the default Strix Point + RAI 1.7.1 profile.
- This was unexpected (you believed you had a Ryzen AI machine): check Device Manager for unbound PCI devices; check Task Manager → Performance for an NPU0 entry; check that the BIOS has not disabled the NPU.

### "V06 shows MS-GENERIC drivers on AMD hardware that the patched INFs don't cover"

CPU cores (`cpu.inf`), PCI Express Root Ports (`pci.inf`), Host CPU Bridges (`machine.inf`), USB xHCI (`usbxhci.inf`), HD Audio Controller (`hdaudbus.inf`) are **all expected to remain on Microsoft generic drivers**. AMD does not ship vendor drivers for these (they're enumerated by core OS subsystems). The "ALERT" message in V06 Section 1 is informational, not an error.

### "I02 deploys WDAC policy but new driver still doesn't load"

Check `eventvwr` → `Applications and Services Logs` → `Microsoft` → `Windows` → `CodeIntegrity` → `Operational` for events 3076 / 3077 / 3091. The Issuer / Subject / Thumbprint of the blocked signature should match your self-signed cert. If they don't match, the WDAC policy isn't deployed correctly — try `CiTool -lp` to list active policies.

### "AMD driver was installed but Device Manager still shows MS generic on the device"

Run `pnputil /scan-devices` to force a re-enumeration. If still bound to MS, the patched INF's HWID may not match the device's PNP ID exactly. Check V06 Section 2 ("WILL be replaced" / "have no patched INF") — if the device falls into the latter category, no patched driver claims that HWID, which is expected for some devices (USB hubs, generic xHCI controllers, etc.).

### NPU script "I04 shows the device is bound but Ryzen AI Software won't initialize"

This is the expected outcome on Windows Server 2025. The kernel-mode driver loads, but the Ryzen AI Software user-mode stack (Python conda env, ONNX Runtime VitisAI EP, OGA) is officially Windows-11-only. Do not expect AI workload functionality on Server 2025. Either:

- Use Windows 11 24H2 for actual NPU inference workloads.
- Treat the Server 2025 install as kernel driver bring-up only (lab / research).

---

## Development tools

The `tools/` directory contains development utilities for contributors.

### `tools/psa.py` — PowerShell Static Analyzer

A single-file Python 3 static analyzer that catches common PowerShell mistakes the regular parser does not flag. Run it before committing any change to the `.ps1` files:

```bash
python3 tools/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 tools/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
python3 tools/psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
```

Checks performed:

| Code | Severity | Description |
| --- | --- | --- |
| C1 | error | Brace balance (`{` vs `}`) |
| C2 | error | Paren balance (`(` vs `)`) |
| C3 | error | Bracket balance (`[` vs `]`) |
| C4 | warning | Undefined variable references (heuristic) |
| C5 | warning | Auto-variable shadowing (`$args`, `$_`, `$matches`, etc.) |
| C6 | warning | `Start-Process -ArgumentList` (prefer `ProcessStartInfo` for spaces-in-path) |
| C7 | warning | `-match` against bare `$variable` (returns true if `$null`) |
| C8 | info | TODO / FIXME markers |
| C9 | warning | Trailing backtick before empty line |
| C10 | warning | `-match` against empty string (always true) |

Exit codes: `0` = clean, `1` = warnings only, `2` = errors. Useful in CI:

```yaml
# .github/workflows/lint.yml example
- name: Static-analyze PowerShell scripts
  run: |
    python3 tools/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
    python3 tools/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
    python3 tools/psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
```

See [`tools/README.md`](./tools/README.md) for more details and the rationale for each rule.

---

## References

### Microsoft Learn

- [INF File Sections and Directives](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-file-sections-and-directives)
- [INF Manufacturer Section (TargetOSVersion / ProductType)](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-manufacturer-section)
- [Differences in Driver Installation Between Server and Client SKUs](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/sku-specific-files-and-installation)
- [Inf2Cat command reference](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/inf2cat)
- [SignTool command reference](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool)
- [PnPUtil overview](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil)
- [PnPUtil Command Syntax](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax)
- [Windows Defender Application Control (WDAC) overview](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/wdac)
- [Deploy WDAC policies with script (CiTool)](https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/deployment/deploy-wdac-policies-with-script)
- [Windows Driver Kit (WDK) installation](https://learn.microsoft.com/en-us/windows-hardware/drivers/download-the-wdk)
- [Windows Software Development Kit (SDK) downloads](https://learn.microsoft.com/en-us/windows/win32/devnotes/windows-sdk)
- [Driver signing requirements for Windows](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/kernel-mode-code-signing-policy--windows-vista-and-later-)

### AMD

- [AMD Chipset Drivers (download)](https://www.amd.com/en/support/category/chipsets)
- [AMD Adrenalin Edition (download)](https://www.amd.com/en/support/category/graphics)
- [AMD Ryzen AI Software (installation guide)](https://ryzenai.docs.amd.com/en/latest/inst.html)
- [AMD Ryzen AI Software (release notes)](https://ryzenai.docs.amd.com/en/latest/relnotes.html)
- [AMD Ryzen AI Software (supported configurations)](https://ryzenai.docs.amd.com/en/latest/relnotes.html#supported-configurations)
- [AMD RyzenAI-SW (GitHub examples and source)](https://github.com/amd/RyzenAI-SW)
- [AMD RyzenAI-SW (latest releases)](https://github.com/amd/RyzenAI-SW/releases)

### This repository

- [TESTING.md](./TESTING.md) — Cloud (AWS) testing procedure with multi-generation EPYC instance options, physical-hardware validation results, and the NPU script's far weaker validation status.
- [TESTING.ja.md](./TESTING.ja.md) — Japanese translation of TESTING.md.
- [CONTRIBUTING.md](./CONTRIBUTING.md) — How to contribute.
- [README.ja.md](./README.ja.md) — Japanese translation of this document.
- [tools/README.md](./tools/README.md) — Development tools documentation.

---

## License

[MIT License](./LICENSE). Copyright (c) 2026 contributors.

The MIT licence applies to the **PowerShell scripts and accompanying documentation in this repository only**. The scripts download AMD installer EXEs and Ryzen AI driver ZIPs at runtime and do not redistribute AMD's binaries, INFs, or catalogs. AMD's redistribution terms apply to those files independently.

---

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for issue templates, PR guidelines, and how to run the regression test suite (including `tools/psa.py`).

Issues and pull requests are tracked at: <https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer>
