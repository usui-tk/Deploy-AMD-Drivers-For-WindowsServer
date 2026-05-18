# Deploy-Drivers-For-WindowsServer

PowerShell pipeline that makes AMD's consumer-targeted Ryzen chipset, Radeon graphics, and Ryzen AI NPU (XDNA) drivers — **plus Microsoft's inbox Bluetooth PAN driver (`bthpan.inf` / `bthpan.sys`)** — installable on Windows Server 2016 / 2019 / 2022 / 2025 by patching the INF `ProductType=3` decoration and re-signing the catalog with a self-generated certificate.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) [![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://learn.microsoft.com/en-us/powershell/) [![Target: Windows Server 2025](https://img.shields.io/badge/Target-Windows%20Server%202025-success.svg)](https://learn.microsoft.com/en-us/windows-server/get-started/windows-server-2025)

> **Read this twice before running anything.** This is a *last-resort, lab-only* tool. AMD does not officially support Windows Server 2025 for consumer Ryzen platforms (e.g. Cezanne / Renoir / Phoenix APUs in Lenovo ThinkCentre Tiny / ThinkPad / mini-PC builds). When official drivers exist, **always prefer those**. This repository exists for the narrow case where official Server-class drivers are unavailable and you are willing to operate a self-signed driver chain on your own hardware, at your own risk.

> **🆘 EXTRA WARNING for the NPU script (`Deploy-AMDNpuDriverOnWindowsServer.ps1`):** The NPU script is **markedly more dangerous and far less mature** than the chipset and graphics scripts. It is **unvalidated on physical NPU hardware** as of this writing, the AMD account auto-download flow is **best-effort and can break without notice** when AMD changes form layouts, and Ryzen AI Software (the user-mode stack required to actually use the NPU) is **officially unsupported on Windows Server 2025 by AMD**. Treat the NPU script as **experimental / research-grade**, not as a production tool. See [Risk classification](#risk-classification-of-the-four-scripts) below.

🇯🇵 **日本語版 README は [README.ja.md](./README.ja.md) を参照してください。**

---

## Table of Contents

- [Why this exists](#why-this-exists)
- [⚠️ Disclaimer (read before running)](#%EF%B8%8F-disclaimer-read-before-running)
- [What's in the box](#whats-in-the-box)
- [What's new](#whats-new)
- [Risk classification of the four scripts](#risk-classification-of-the-four-scripts)
- [Scope of coverage](#scope-of-coverage)
- [Folder layout](#folder-layout)
- [Quick start](#quick-start)
- [BthPan-specific quick start](#bthpan-specific-quick-start)
- [NPU-specific quick start](#npu-specific-quick-start)
- [Pipeline architecture (21 phases)](#pipeline-architecture-21-phases)
- [Parameters (per script)](#parameters-per-script)
- [Output files](#output-files)
- [UEFI Secure Boot baseline](#uefi-secure-boot-baseline)
- [Console output format](#console-output-format)
- [System requirements](#system-requirements)
- [Self-signed certificate: expiry, renewal, and revocation](#self-signed-certificate-expiry-renewal-and-revocation)
- [Disclaimer & at-your-own-risk acknowledgements](#disclaimer--at-your-own-risk-acknowledgements)
- [Troubleshooting](#troubleshooting)
- [Development tools](#development-tools)
- [Developer specification](#developer-specification)
- [File encoding](#file-encoding)
- [References](#references)
- [License](#license)
- [Contributing](#contributing)

Related documents:

- [`CHANGELOG.md`](./CHANGELOG.md) — chronological per-release change log (English only)
- [`SPEC.md`](./SPEC.md) — developer specification (architecture, conventions, design rationale; English only)
- [`TESTING.md`](./TESTING.md) — physical-hardware validation results and regression checklist (English only)
- [`CONTRIBUTING.md`](./CONTRIBUTING.md) — how to file issues, propose changes, and run regression tests (English only)
- [`README.ja.md`](./README.ja.md) — Japanese translation of this document, kept in sync

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

## ⚠️ Disclaimer (read before running)

**USE AT YOUR OWN RISK.** These scripts are provided "AS IS" without warranty of any kind, express or implied. The authors and contributors are not liable for any damages, data loss, BSODs, BitLocker recovery prompts, account suspension, hardware instability, or any other problems — direct or indirect — that may arise from using, modifying, or distributing these scripts.

By running these scripts, you acknowledge that:

* You are solely responsible for verifying that your use complies with AMD's End User License Agreement, Microsoft's Windows Software License Terms, and any applicable laws or regulations
* You understand that patching AMD's INFs and re-signing them with your own certificate makes **you** — not AMD, not Microsoft — the cryptographic publisher of those drivers from Windows' point of view
* You accept that **WHQL certification is invalidated** for any driver this pipeline replaces; if you rely on Microsoft Premier Support for affected hardware, your support contract may not cover issues caused by self-signed drivers
* You will record your **BitLocker recovery keys** before running `-Action Install` on the chipset script (the PSP driver replacement interacts with Platform Security Processor firmware and can trigger recovery prompts on next boot)
* You will review the script source code and understand its behavior before running it in any environment
* For the **NPU script specifically**, you understand it is **experimental / research-grade** — see [Risk classification](#risk-classification-of-the-four-scripts) below

Operate these tools considerately. **Always prefer official AMD Server-supported drivers when they exist.** This repository targets the narrow case where official Server-class drivers are unavailable and you are willing to operate a self-signed driver chain on your own hardware.

For the full at-your-own-risk acknowledgements (BitLocker, anti-cheat software, support implications, cert expiry, etc.), see the [Disclaimer & at-your-own-risk acknowledgements](#disclaimer--at-your-own-risk-acknowledgements) section further down.

---

## What's in the box

| File | Purpose | Maturity |
| --- | --- | --- |
| `Deploy-AMDChipsetDriverOnWindowsServer.ps1` | Chipset driver pipeline (GPIO, SMBus, PSP, MicroPEP, PMF, etc.). Source: AMD Chipset Software ~75 MB EXE, ~67 INFs. | **Stable** — validated on M75q Tiny Gen 2 (WS2025) and X13 Gen 1 AMD (Win11 LTSC 2024). |
| `Deploy-AMDGraphicsDriverOnWindowsServer.ps1` | Graphics driver pipeline (Display, HD Audio, Audio CoProcessor, ACP, USB-C UCSI, etc.). Source: AMD Adrenalin Edition ~600 MB EXE, ~19 INFs (Vega-Polaris Legacy branch) or ~67 INFs (Main Adrenalin branch for Phoenix+). | **Stable** — same validation hosts as chipset. |
| **`Deploy-AMDNpuDriverOnWindowsServer.ps1`** | **NPU (Ryzen AI XDNA) driver pipeline (PHX/HPT/STX/KRK).** Source: AMD Ryzen AI Software ZIP, ~250 MB, EULA-gated download (no public direct URL). Kernel-mode driver only — does NOT install Ryzen AI Software user-mode stack. | **🆘 Experimental / research-grade — NOT production-ready.** No physical-NPU validation runs have been performed. AMD account auto-download is best-effort and may break with AMD form changes. Ryzen AI Software is officially unsupported on Windows Server 2025. |
| `Deploy-MSBthPanInboxOnWindowsServer.ps1` | **Microsoft inbox Bluetooth PAN driver (`bthpan.inf` / `bthpan.sys`) enablement pipeline.** Source: the host's own `C:\Windows\System32\DriverStore\FileRepository\bthpan.inf_amd64_*` directory — **no remote download required.** Single INF, single HWID (`BTH\MS_BTHPAN`). Distinguishes Phantom OK (bth.inf proxy match) from true resolution (Class=Net, Service=BthPan) on Windows Server. | **New** (r1) — initial release. Logic shares the same Phase / Secure Boot / WDAC framework as the AMD scripts; INF patch surface is much smaller (1 INF, 1 HWID). Physical validation on ThinkPad + Intel AX210 + WS2025 build 26100.32860 is the planned first test target. |
| `README.md` | This document (English; the master). |  |
| `README.ja.md` | Japanese translation of `README.md`, kept in sync. |  |
| `SPEC.md` | Developer specification (per-script details, INF parsing strategy, WDAC policy structure). **English only.** |  |
| `TESTING.md` | Physical-hardware validation results. Includes the NPU script's far weaker validation status. **English only.** |  |
| `CHANGELOG.md` | Chronological per-release change log. **English only.** |  |
| `CONTRIBUTING.md` | How to file issues, propose changes, and run regression tests. **English only.** |  |
| `LICENSE` | MIT License. |  |

All four PowerShell scripts share the same 21-phase architecture, the same self-signing model, and the same WDAC authorisation path. They write to separate workspaces (`C:\Temp\Workspace_AMD-Chipset`, `C:\Temp\Workspace_AMD-Graphics`, `C:\Temp\Workspace_AMD-NPU`, `C:\Temp\Workspace_Microsoft-BthPan`) and use separate self-signed certificates + separate WDAC supplemental policy GUIDs so they never collide. From Chipset r59 / Graphics r27 / NPU r9 / BthPan r9, all four workspaces are relocated under `C:\Temp\Workspace_*` for cluster-and-purge convenience; the script auto-creates `C:\Temp` on demand.

---

## What's new

See [CHANGELOG.md](./CHANGELOG.md) for the chronological per-release entry log
(every revision from r1 onward, organised by date and by script). For the
architectural rationale behind individual fixes, see
[SPEC.md Part D](./SPEC.md#part-d--known-pitfalls--lessons-learned).

The latest release at the time of writing is
**Chipset r60 / Graphics r28 / NPU r10 / BthPan r10** (2026-05-18), a
cross-script consistency pass that brings every script to the psa.py
baseline. The Debug Trace Facility (SECTION 1b) introduced in the previous
release (r59 / r27 / r9 / r9, 2026-05-17) remains the headline feature.

As of an [Unreleased] config-only update on the same date, `.psa.config.json`
opts in to the new opt-in revision-discipline rules `PSAP0003` and
`PSAP0004` (introduced in `psa.py` 3.3.0). All four scripts remain at
0 errors / 0 warnings / 0 info under this stricter configuration.

## Risk classification of the four scripts

> This section exists because the NPU script is materially riskier than its sister scripts and operators must understand the difference before running it. The BthPan script is the lowest-risk of the four because its driver source is the host's own DriverStore (no remote download), the INF surface is exactly one file with one HWID, and Microsoft itself signs the inbox driver — only the catalog must be re-signed.

| Aspect | Chipset script (r60) | Graphics script (r28) | **NPU script (r10)** | **BthPan script (r10)** |
| --- | --- | --- | --- | --- |
| **Maturity** | Stable, multiple validation cycles | Stable, multiple validation cycles | **🆘 Experimental — first release, not validated on physical NPU hardware** | **New (r1)** — initial release. Logic shares the proven Phase / Secure Boot / WDAC framework. Single-INF surface is small enough that physical validation is feasible in one session. |
| **Distribution format** | Public EXE direct download | Public EXE direct download | **EULA-gated ZIP, requires AMD account** | **No download** — `bthpan.inf` is already staged at `C:\Windows\System32\DriverStore\FileRepository\bthpan.inf_amd64_*` on every Windows install. |
| **Public download URL** | Yes (direct) | Yes (direct) | **No — requires AMD account login + EULA acceptance per release** | **N/A — driver is on the host.** |
| **AMD account auto-download** | N/A | N/A | **Best-effort; depends on AMD's form HTML staying stable; can break without notice** | **N/A.** |
| **OS support stance** | AMD does not officially support, but drivers run | AMD does not officially support, but drivers run | **Driver loads on Server 2025, but Ryzen AI Software (user-mode stack) does NOT work on Server 2025 per AMD docs** | **Microsoft inbox driver — fully supported by Microsoft on Workstation SKUs.** Filtered out on Server SKUs only because of the `NTamd64...1` ProductType decoration. This script supplies the missing ProductType=3 decoration without touching Microsoft's binary at all. |
| **Hardware availability** | Common (any AMD APU machine) | Common (any AMD GPU/APU machine) | **Limited to Ryzen AI 300 / Ryzen AI Max 300 / Ryzen 7040/8040 series** | Common — any machine with a Bluetooth host controller bound and `BTH\MS_BTHPAN` enumerated. Most ThinkPads, mini-PCs, NUCs ship one. |
| **Test fixtures available in repo** | M75q Tiny Gen 2, X13 Gen 1 AMD | M75q Tiny Gen 2, X13 Gen 1 AMD | **NONE — no physical NPU machine in the maintainer's lab as of this writing** | ThinkPad + Intel AX210 + WS2025 build 26100.32860 (planned first physical validation). |
| **Failure modes specific to this script** | PSP / TPM driver replacement may trigger BitLocker recovery | Display reset on signed-cat install | NPU device may not enumerate; Ryzen AI Software won't work | **Phantom OK trap** — bth.inf may proxy-match and report Status=OK even though bthpan.sys is NOT loaded. V06 / I04 must explicitly distinguish Phantom OK (DriverInfPath=bth.inf, Class=Bluetooth) from true resolution (DriverInfPath=oem*.inf, Class=Net, Service=BthPan). |
| **Recommended use** | Lab + cautious production | Lab + cautious production | **Lab / research only. Do not deploy on production hosts.** | **Lab + cautious production.** Risk is low because the script does not replace any vendor driver — it only enables the Microsoft-published inbox driver on a SKU class where Microsoft chose not to ship it by default. |
| **Recommended Action mode** | `Install` after `PrepareVerify` review | `Install` after `PrepareVerify` review | **`PrepareVerify` ONLY until you can confirm the host is a real NPU machine and you accept that Ryzen AI Software won't function on Server 2025** | `PrepareVerify` first to confirm Phantom-OK vs true-resolution state, then `Install`. |

**Practical rules of thumb for the NPU script**:

1. **Do not run `-Action Install` on a host you cannot afford to roll back.** The cleanup path is implemented but driver-store removal is best-effort and may require manual `pnputil /delete-driver oemNN.inf /force` cleanup.
2. **The Ryzen AI Software user-mode stack** (Python conda env + ONNX Runtime VitisAI EP + OGA) **is officially Windows-11-only.** Even if the kernel driver loads on Server 2025, you will not be able to run inference workloads through the supported stack. Do not expect AI workload functionality on Server 2025; the kernel driver is at most an experiment in driver bring-up.
3. **There are no physical-NPU validation runs yet.** All current verification is static analysis with `psa.py` and code-review of the AMD-published `quicktest.py` detection logic translated to PowerShell. **Real hardware behaviour is unconfirmed.**
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
- **Microsoft inbox Bluetooth PAN** *(BthPan script only)*:
  - **HWID**: `BTH\MS_BTHPAN` — child device exposed by every Microsoft-supported Bluetooth host controller after the host controller binds. Vendor-agnostic (Intel AX2xx, Realtek RTL88xx, MediaTek MT7xxx, Broadcom BCM43xx, etc.).
  - **Prerequisite**: a Bluetooth host controller driver is bound and showing Status=OK in Device Manager. If the host controller itself is unknown-device, install its vendor driver first; this script does NOT cover host controllers.
  - **Symptom this script solves**: on Windows Server SKU, `BTH\MS_BTHPAN` shows as Unknown Device (code 28), or shows Status=OK but with `DriverInfPath=bth.inf` and `Class=Bluetooth` (Phantom OK; `bthpan.sys` is NOT loaded and `BthPan` service is NOT running).
  - **Verified true-resolution criteria**: `DriverInfPath=oem*.inf`, `Class=Net`, `Service=BthPan`, `C:\Windows\System32\drivers\bthpan.sys` present, `BthPan` service registered, a Bluetooth PAN NetAdapter visible to `Get-NetAdapter`.

### Hardware **out of scope**

- **AMD EPYC server chips** (server-class CPUs found in cloud instances, Hetzner AX dedicated, etc.): EPYC uses a different chipset model and ships first-party Server-supported drivers via Microsoft Update. This pipeline targets *consumer* Ryzen, not EPYC.
- **Real-time GPU compute stacks** (ROCm, HIP SDK, OpenCL beyond the user-mode driver shipped in the Adrenalin package): consult AMD's ROCm documentation for Server.
- **Ryzen AI Software user-mode stack** (Python conda env, ONNX Runtime VitisAI Execution Provider, OnnxRuntime GenAI/OGA, Vitis AI Quantizer, Lemonade SDK, etc.): **out of scope of the NPU script.** The NPU script installs the kernel-mode driver only. Ryzen AI Software must be installed separately by the operator from the AMD installer at <https://account.amd.com/en/forms/downloads/xef.html?filename=ryzen-ai-lt-1.7.1.exe>, and per AMD documentation it is officially supported on Windows 11 build >= 22621.3527 only.

---

## Folder layout

Repository structure (after `git clone`):

```
Deploy-Drivers-For-WindowsServer/
├── Deploy-AMDChipsetDriverOnWindowsServer.ps1     Chipset driver pipeline (21 phases)
├── Deploy-AMDGraphicsDriverOnWindowsServer.ps1    Graphics driver pipeline (21 phases)
├── Deploy-AMDNpuDriverOnWindowsServer.ps1         NPU (Ryzen AI XDNA) pipeline (21 phases)
├── Deploy-MSBthPanInboxOnWindowsServer.ps1        Microsoft inbox bthpan pipeline (21 phases)
├── README.md                                      This document (English; master)
├── README.ja.md                                   Japanese translation, kept in sync
├── TESTING.md                                     Physical-hardware validation results (EN only)
├── SPEC.md                                        Developer specification (EN only)
├── CHANGELOG.md                                   Chronological per-release change log (EN only)
├── CONTRIBUTING.md                                Issue / PR guidelines (EN only)
├── SECURITY.md                                    Vulnerability reporting (EN only)
├── CODE_OF_CONDUCT.md                             Community behaviour (EN only)
├── LICENSE                                        MIT License
├── .psa.config.json                               psa.py configuration (PSAP rules opt-in)
├── .gitattributes                                 Git line-ending normalization
└── .gitignore                                     Standard ignores
```

### What the scripts produce

After `-Action PrepareVerify` (or `-Action All`), each script populates its workspace:

```
C:\Temp\Workspace_AMD-Chipset\   (or C:\Temp\Workspace_AMD-Graphics\, C:\Temp\Workspace_AMD-NPU\, C:\Temp\Workspace_Microsoft-BthPan\)
├── download\              AMD installer EXE / NPU driver ZIP
│                          (BthPan: empty — driver source is DriverStore, not downloaded)
├── extracted\             Original INFs and binaries from the EXE / ZIP / DriverStore
│                          (BthPan: extracted\bthpan\bthpan.inf / .sys / .cat)
├── patched\               Patched INFs with mirrored ProductType=3 sections
│                          + generated .cat files + signtool signatures
│                          (BthPan: patched\bthpan\ — single INF directory)
├── cert\                  Self-signed code-signing cert (PFX + CER) +
│                          WDAC supplemental policy XML/CIP
└── inf_inventory.csv / inf_inventory_report.txt
                           P05 inventory and per-INF analysis
                           (BthPan: single-row CSV — exactly one INF)
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
git clone https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer.git
cd Deploy-Drivers-For-WindowsServer

# Option 2: download a release ZIP from
# https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/releases
```

### One-shot dry run (safe; modifies nothing)

```powershell
# In an elevated PowerShell session
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\Deploy-AMDChipsetDriverOnWindowsServer.ps1   -Action PrepareVerify -CleanWorkRoot
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot
.\Deploy-MSBthPanInboxOnWindowsServer.ps1      -Action PrepareVerify -CleanWorkRoot

# NPU script — REQUIRES an offline ZIP (or other download source) to actually run P03.
# On a clean machine without -OfflineZip, P03 will throw "All 4 download tiers exhausted".
# See the NPU-specific quick start below for the full pattern.
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip -AssumeIfMissing
```

`PrepareVerify` runs `P00-P09` (locate / extract source, patch, generate catalog, sign) followed by `V01-V06` (verify artefacts, dry-run install plan, hardware impact analysis). **No system state is modified** — no certs are imported, no WDAC policy is deployed, no drivers are installed. Read the V05 / V06 output to understand exactly what `Install` *would* do.

> **BthPan-specific note**: the BthPan script's P03 (FetchInstaller) does NOT download anything — it locates `bthpan.inf` in the host's own `C:\Windows\System32\DriverStore\FileRepository\bthpan.inf_amd64_*` directory. P03 fails only on hosts where the inbox driver has been deliberately removed (extremely rare).

### Full installation (chipset, graphics, BthPan)

```powershell
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1   -Action Install
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1  -Action Install
.\Deploy-MSBthPanInboxOnWindowsServer.ps1      -Action Install
```

Run on a Windows Server 2025 host. All scripts are idempotent and cleanup-safe (`-Action Cleanup` removes the workspace, the certs from the trust stores, and the deployed WDAC policy).

> **BthPan-specific outcome check**: after the BthPan script's `Install` action completes, I04 (PostInstallVerification) explicitly distinguishes Phantom OK from true resolution. The script prints `*** TRUE RESOLUTION ACHIEVED ***` only when `bthpan.sys` is loaded, `BthPan` service is running, and `BTH\MS_BTHPAN` reports `Class=Net, Service=BthPan, DriverInfPath=oem*.inf`. If you instead see `*** TRUE RESOLUTION NOT YET ACHIEVED ***`, a reboot is the typical fix (PnP rebind sometimes requires a fresh boot).

> **NPU script `Install`**: see [NPU-specific quick start](#npu-specific-quick-start). The `Install` action requires extra preconditions (offline ZIP availability or AMD account credentials) and is **not recommended without physical NPU hardware**.

### Selective phase execution

```powershell
# Just regenerate the patched INFs and catalogs without re-downloading
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action Prepare -OnlyPhases P05,P06,P08,P09

# Run only the cert-trust phase
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action Install -OnlyPhases I01

# Run only the BthPan Phantom-OK readiness analysis (no system change)
.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -OnlyPhases V06

# List all phases the script knows about
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action ListPhases
```

---

## BthPan-specific quick start

> The BthPan script is the simplest of the four to run because the driver source is the host's own DriverStore — no network download, no AMD account, no EULA-gated ZIP.

### Step 1 — confirm the Bluetooth host controller is bound

The BthPan script handles only `BTH\MS_BTHPAN` (the Personal Area Network child device exposed after the Bluetooth host controller is bound). The host controller itself is **out of scope**.

```powershell
# Confirm the host controller is showing Status=OK (NOT "Unknown device").
Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
    Select-Object FriendlyName, Status, InstanceId

# If the host controller (e.g. Intel AX210, Realtek RTL8852, MediaTek MT7921)
# is "Unknown device", install its vendor driver first. The bthpan script
# does NOT install host-controller drivers.
```

### Step 2 — diagnose the current state (no system change)

```powershell
.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -OnlyPhases V06
```

V06 prints the per-instance classification of every `BTH\MS_BTHPAN*` device on the host. Three states are possible:

| Classification | Meaning | Recommended next step |
| --- | --- | --- |
| **Unknown** | Status=Error (code 28). No driver is bound. | Run `-Action Install`. |
| **Phantom** | Status=OK, but `DriverInfPath=bth.inf`, `Class=Bluetooth`, `Service=(empty)`. `bthpan.sys` is **NOT** loaded; PAN networking is broken even though Device Manager looks fine. | Run `-Action Install`. After install, I04 verifies the rebind. |
| **True** | `DriverInfPath=oem*.inf`, `Class=Net`, `Service=BthPan`. `bthpan.sys` is loaded; BthPan service is running. | No action needed. The host is already at true resolution. |

### Step 3 — full installation

```powershell
.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action All -CleanWorkRoot
```

`-Action All` runs all 21 phases (`P00-P09` → `V01-V06` → `I00-I04`) in a single command. I03 includes `pnputil /scan-devices` to force the PnP manager to re-evaluate `BTH\MS_BTHPAN` so it rebinds from `bth.inf` (the Phantom proxy match) to the patched `oem*.inf` (true resolution).

If I04 reports `*** TRUE RESOLUTION NOT YET ACHIEVED ***`, a reboot is the typical fix; sometimes the PnP rebind only takes effect on next boot. Re-run the same command after reboot — the script's resume-after-reboot logic detects the new state and reports `*** TRUE RESOLUTION ACHIEVED ***`.

### Step 4 — decoration strategy choice (advanced)

```powershell
# Strategy A (default): NTamd64...3 only (ProductType=3 covers all Server SKUs).
.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -DecorationStrategy A

# Strategy B: also add NTamd64.10.0...14393 / 17763 / 20348 / 26100 explicitly.
# Provides slightly higher PnP-ranking advantage when a future Microsoft inbox
# update adds Server decorations of its own. Requires manual update for any
# new Server SKU build that ships in the future.
.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -DecorationStrategy B
```

In practice **Strategy A is sufficient** on all four supported Server builds (14393 / 17763 / 20348 / 26100). Strategy B exists for environments where multiple coexisting bthpan packages compete for the binding slot and per-build entries give a deterministic tie-break.

### Step 5 — verify the outcome

```powershell
# bthpan.sys present?
Test-Path C:\Windows\System32\drivers\bthpan.sys

# BthPan service registered + running?
Get-Service BthPan -ErrorAction SilentlyContinue

# Bluetooth PAN NetAdapter visible?
Get-NetAdapter | Where-Object InterfaceDescription -Match 'Bluetooth.*Personal Area Network'

# Device-level state (Class should be Net, Service should be BthPan):
Get-PnpDevice -InstanceId 'BTH\MS_BTHPAN*' |
    Get-PnpDeviceProperty -KeyName DEVPKEY_Device_Class, DEVPKEY_Device_Service, DEVPKEY_Device_DriverInfPath
```

---

## NPU-specific quick start

> **Reminder**: this script is experimental. Read [Risk classification of the four scripts](#risk-classification-of-the-four-scripts) before continuing.

### Step 1 — obtain the NPU driver ZIP (one of the four tiers)

The NPU script supports **four download tiers** in priority order:

| Tier | Method | When to use |
| --- | --- | --- |
| **1** | `-InstallerUrl <url>` explicit URL | You already have a fresh AMD CDN URL (e.g. from an `entitlenow.com` link captured in a browser session). |
| **2** | `-AmdAccountUser <email> -AmdAccountPassword <SecureString> -ForceAmdAccountAuth` | Attempt EULA acceptance flow automatically. **❌ Disabled by default since 2026-05-10 verification found `account.amd.com` is a JavaScript-driven SPA. Use `-ForceAmdAccountAuth` to opt in (expected to fail on the current AMD portal).** See TESTING.md §3.6 for the full verification report. |
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
# Pipeline-soundness check on a host without an NPU device — same as above plus -AssumeIfMissing.
# When P03 detects no NPU device, the script falls back to the default Strix Point profile
# instead of failing. Useful only for testing the pipeline mechanics; produces 0 device bindings
# and provides no validation of real NPU behaviour.
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action PrepareVerify `
    -CleanWorkRoot `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip `
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
| Prep | P01 | PrepareWorkspace | Create `C:\Temp\Workspace_AMD-{Chipset,Graphics,NPU}\` or `C:\Temp\Workspace_Microsoft-BthPan\` (auto-creates `C:\Temp` on demand) |
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

## Parameters (per script)

All four scripts share a common parameter contract for `-Action`, `-OnlyPhases`, `-CleanWorkRoot`, `-AllowWorkstationInstall`, `-UseTestSigning`, `-WorkRoot`, and `-PfxPassword`. The chipset and graphics scripts share additional source-discovery and help switches; the NPU script adds a 4-tier installer source resolution and platform override block; the BthPan script adds a single `-DecorationStrategy A|B` switch and otherwise reuses the common contract.

### Common parameters (chipset, graphics, NPU, BthPan)

| Parameter                  | Default              | Description                                                                                       |
| -------------------------- | -------------------- | ------------------------------------------------------------------------------------------------- |
| `-Action`                  | `PrepareVerify`      | `Prepare` / `Verify` / `PrepareVerify` / `Install` / `All` / `Cleanup` / `ListPhases`             |
| `-OnlyPhases`              | `@()`                | Phase IDs (e.g. `P05`, `P06`, `P08`, `P09`) or short names (e.g. `PatchInfs`); overrides `-Action` |
| `-CleanWorkRoot`           | (off)                | Delete the workspace directory before starting (forces a fresh download/extract/copy)             |
| `-AllowWorkstationInstall` | (off)                | Permit Install-phase actions on Workstation OS (Win11). Discouraged — default blocks Install      |
| `-UseTestSigning`          | (off)                | Fall back to `bcdedit /set testsigning on` instead of WDAC supplemental policy. Discouraged       |
| `-WorkRoot`                | per-script           | Override workspace path (chipset: `C:\Temp\Workspace_AMD-Chipset`, graphics: `C:\Temp\Workspace_AMD-Graphics`, NPU: `C:\Temp\Workspace_AMD-NPU`, BthPan: `C:\Temp\Workspace_Microsoft-BthPan`). r58+ / r26+ / r8+ / r2+: relocated under `C:\Temp\Workspace_*`; the script auto-creates `C:\Temp` on demand |
| `-LogFile`                 | `''` (disabled)      | (r58+ / r26+ / r8+ / r2+) Optional path to capture the full console transcript via `Start-Transcript` / `Stop-Transcript`. The file receives every stream (Output / Host / Error / Warning / Verbose / Debug) as plain text; the interactive console keeps its `Write-Host -ForegroundColor` decoration intact. Recommended over the legacy `... \|*>&1 \| Tee-Object -FilePath ...` idiom, which strips Write-Host coloring. Suggested filename: `C:\Temp\<tag>_<Action>_<yyyyMMdd-HHmmss>.log` |
| `-PfxPassword`             | per-script           | Password for the self-signed PFX (chipset/graphics/BthPan: `'ChangeMe!2026'`, NPU: `''`)          |
| `-WdacPolicyGuid`          | per-script (fixed UUID v4) | Override the fixed WDAC supplemental policy GUID. Default is per-script (chipset: `503860EA-…`, graphics: `85336828-…`, NPU: `8B2C4F12-…`, BthPan: `A6E72D4F-3B98-4C5A-9E1D-7F8B2A4C6E5D`). Used for legacy-deploy cleanup or side-by-side multi-instance deploy |

### Chipset / Graphics-specific parameters

| Parameter           | Default                          | Description                                                                                       |
| ------------------- | -------------------------------- | ------------------------------------------------------------------------------------------------- |
| `-Help` / `-h` / `-?` | (off)                          | Show formatted usage information and exit                                                         |
| `-References`       | (off)                            | Display curated list of Microsoft Learn documentation links and exit                              |
| `-InstallerUrl`     | `''`                             | Explicit URL to the AMD installer EXE — bypasses the URL discovery probe                          |
| `-AmdLandingUrls`   | per-script default array         | Landing pages to scrape for installer EXE URL (override only if AMD changes their site structure) |
| `-AmdFallbackUrl`   | per-script default URL           | Last-resort hard-coded installer URL when landing page scraping fails                             |
| `-Force`            | (off)                            | Force overwrite of existing workspace files (use with care)                                       |
| `-TimestampUrl`     | `http://timestamp.digicert.com`  | RFC 3161 timestamp server for `signtool sign /tr`                                                 |
| `-WdacBasePolicyGuid` | `A244370E-44C9-4C06-B551-F6016E563076` (Windows-shipped base CI policy) | Override the SupplementsBasePolicyID that the WDAC supplemental policy targets. Change only if your environment uses a custom base policy |

> **Note**: The chipset and graphics scripts do not currently expose `-CertValidityYears`; the default 5-year validity is hard-coded. Only the NPU script exposes this as a configurable parameter.

### NPU-specific parameters

| Parameter                | Default               | Description                                                                                                      |
| ------------------------ | --------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `-InstallerUrl`          | (none)                | Tier 1: explicit URL to the NPU driver ZIP                                                                       |
| `-OfflineZip`            | (none)                | Tier 4 priority: path to a pre-downloaded NPU driver ZIP (**recommended pattern**)                                |
| `-AmdAccountUser`        | (none)                | Tier 2: AMD account email for auto-download (BEST-EFFORT — disabled by default)                                  |
| `-AmdAccountPassword`    | (none)                | Tier 2: AMD account password (SecureString)                                                                      |
| `-ForceAmdAccountAuth`   | (off)                 | Opt in to Tier 2 form-based auth (expected to fail against current AMD JS-driven SPA portal)                     |
| `-NpuOverride`           | (none)                | Force a specific NPU codename: `PHX` / `HPT` / `STX` / `KRK`                                                     |
| `-NpuDriverPackage`      | `latest`              | NPU kernel-mode driver package: `NPU_RAI1.5_280` / `NPU_RAI1.6.1_314` / `latest` (resolves to `NPU_RAI1.6.1_314`) |
| `-RyzenAiSoftwareVersion`| `latest`              | Ryzen AI Software (user-mode stack) version recommendation: `1.5` / `1.6.1` / `1.7` / `1.7.1` / `latest`         |
| `-AssumeIfMissing`       | (off)                 | If NPU not detected, proceed using default profile (Strix Point + NPU driver 32.0.203.314 + RAI Software latest) |
| `-CertValidityYears`     | `5`                   | Self-signed cert validity period in years (NPU script only)                                                      |

> **Note** on NPU driver vs Ryzen AI Software versioning: per AMD documentation at <https://ryzenai.docs.amd.com/en/latest/inst.html>, NPU kernel driver and Ryzen AI Software are versioned **independently**. `-NpuDriverPackage` and `-RyzenAiSoftwareVersion` are therefore independent switches; you can combine any driver with any software (e.g. `-NpuDriverPackage NPU_RAI1.6.1_314 -RyzenAiSoftwareVersion 1.7.1`).

### BthPan-specific parameters

| Parameter             | Default | Description                                                                                                |
| --------------------- | ------- | ---------------------------------------------------------------------------------------------------------- |
| `-Help` / `-h` / `-?` | (off)   | Show formatted usage information and exit                                                                  |
| `-References`         | (off)   | Display curated list of Microsoft Learn documentation links and exit                                       |
| `-Force`              | (off)   | Force overwrite of existing workspace files (bypass cached Phase markers)                                  |
| `-TimestampUrl`       | `http://timestamp.digicert.com` | RFC 3161 timestamp server for `signtool sign /tr`                                            |
| `-DecorationStrategy` | `A`     | `A` (default): add only `NTamd64...3` (ProductType=3 covers all Server SKUs). Simple, durable against future Server SKUs. |
|                       |         | `B`: also add `NTamd64.10.0...14393 / 17763 / 20348 / 26100` per-build entries. Useful when explicit PnP-ranking tie-break is required, but needs manual update for any new Server SKU build. |
| `-WdacBasePolicyGuid` | `A244370E-44C9-4C06-B551-F6016E563076` (Windows-shipped base CI policy) | Override the SupplementsBasePolicyID that the WDAC supplemental policy targets |

> **Note**: the BthPan script intentionally does NOT expose `-InstallerUrl` / `-AmdLandingUrls` / `-AmdFallbackUrl` / `-OfflineZip` parameters, because there is no remote installer to fetch — the driver is the host's own `bthpan.inf` from `C:\Windows\System32\DriverStore\FileRepository\bthpan.inf_amd64_*`.

---

## Output files

Each script writes the following artifacts under its workspace (`C:\Temp\Workspace_AMD-{Chipset,Graphics,NPU}\` or `C:\Temp\Workspace_Microsoft-BthPan\`):

| Path (relative to workspace)                | Content                                                                                                          |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `download\<installer>`                      | AMD installer EXE (chipset/graphics) or NPU driver ZIP (NPU); empty for BthPan (no remote source)                |
| `extracted\`                                | Unpacked installer contents (original INFs, SYS, DLL, CAT files); for BthPan: `extracted\bthpan\` with the DriverStore copy |
| `patched\<inf>`                             | Patched INF files with `ProductType=3` decoration mirrors (BthPan: `patched\bthpan\bthpan.inf`)                  |
| `patched\<cat>`                             | Regenerated catalog files (`inf2cat /os:Server2025_X64,...` output)                                              |
| `cert\AMD-Chipset-Driver-CodeSign.pfx` (chipset) / `cert\AMD-Graphics-Driver-CodeSign.pfx` (graphics) / `cert\AMD-NPU-Driver-CodeSign.pfx` (NPU) / `cert\MS-BthPan-Driver-CodeSign.pfx` (BthPan) | Self-signed code-signing certificate (PFX format) |
| `cert\AMD-Chipset-Driver-CodeSign.cer` (chipset) / `cert\AMD-Graphics-Driver-CodeSign.cer` (graphics) / `cert\AMD-NPU-Driver-CodeSign.cer` (NPU) / `cert\MS-BthPan-Driver-CodeSign.cer` (BthPan) | Public certificate (CER format) for trust-store import |
| `cert\AmdSuppPolicyId.txt` (chipset/graphics) / `cert\MsBthPanSuppPolicyId.txt` (BthPan) | Marker file recording the WDAC supplemental PolicyId for later cleanup                   |
| `cert\WDAC-Supplemental-NPU.xml` / `.cip` (NPU) | WDAC supplemental Code Integrity policy (XML source + binary deployed to `C:\Windows\System32\CodeIntegrity\CiPolicies\Active\`) |
| `cert\MsBthPanSelfSignedSupplementalPolicy.xml` / `.cip` (BthPan) | WDAC supplemental Code Integrity policy for BthPan (XML source + binary deployed to `C:\Windows\System32\CodeIntegrity\CiPolicies\Active\`). Uses the BthPan-specific GUID `A6E72D4F-3B98-4C5A-9E1D-7F8B2A4C6E5D`. |
| `inf_inventory.csv`                         | Per-INF inventory from P05 (file name, provider, class, HWID count, decoration status, etc.). BthPan: single-row CSV |
| `inf_inventory_report.txt`                  | Human-readable summary of P05 INF analysis (includes UEFI Secure Boot baseline appendix)                          |
| `logs\inf2cat_bthpan.log` (BthPan) | inf2cat verbose log; useful for diagnosing catalog generation failures                                                |
| `logs\pnputil_bthpan.log` (BthPan) | pnputil add-driver/install output                                                                                     |
| `logs\pnputil_scan-devices.log` (BthPan) | pnputil /scan-devices output (I03 forces PnP rebind)                                                            |

### CSV column conventions

`inf_inventory.csv` follows these conventions across all four scripts:

| Column                | Type   | Meaning                                                                            |
| --------------------- | ------ | ---------------------------------------------------------------------------------- |
| `FileName`            | string | INF filename (e.g. `kipudrv.inf`, `bthpan.inf`)                                    |
| `FullPath`            | string | Absolute path inside the workspace                                                 |
| `Provider`            | string | INF `[Version]` Provider field (e.g. `AdvancedMicroDevicesInc.`, `Microsoft`)      |
| `DriverVer`           | string | INF `DriverVer` line (e.g. `07/08/2025,32.0.203.314`)                              |
| `Class`               | string | Device class (e.g. `Computer`, `Display`, `System`, `Net`)                         |
| `HwidCount`           | int    | Total Hardware IDs referenced in the INF                                           |
| `MatchesTargetNpu`    | bool   | (NPU only) INF references the target NPU PCI HWID pattern                          |
| `MatchedHwidCount`    | int    | Number of HWIDs in this INF that match the target device                           |
| `HasServerDecoration` | bool   | INF already has `ProductType=3` decoration (no patching needed)                    |
| `NeedsPatch`          | bool   | INF has Workstation-only decorations and requires `ProductType=3` mirroring        |
| `SelectedForPipeline` | bool   | INF passes the script's filter and enters the patch/sign pipeline                  |

---

## UEFI Secure Boot baseline

All four scripts (chipset / graphics / NPU / BthPan) capture the host's UEFI Secure Boot certificate rollout state once at P00 and reuse the snapshot throughout the pipeline. This is informational only — the OS-layer self-signing trust chain that these scripts operate on is **independent** of the firmware-layer UEFI Secure Boot certificate database. Operators who run multiple sister scripts on the same host see consistent baseline reporting and can correlate UEFI cert-rollout state with driver-install outcomes.

### What gets captured

The snapshot combines two sources:

1. **Embedded inventory** — direct reads via `Confirm-SecureBootUEFI`, `Get-SecureBootUEFI db/kek` for the five canonical certificates (`Windows UEFI CA 2023`, `Microsoft KEK 2K CA 2023`, `Microsoft UEFI CA 2011`, `Microsoft UEFI CA 2023`, `Microsoft Option ROM UEFI CA 2023`), `HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot{,\Servicing,\Servicing\DeviceAttributes}` registry keys, and the `\Microsoft\Windows\PI\Secure-Boot-Update` scheduled task state (via `Get-ScheduledTask` for locale-independent results on ja-JP hosts).

2. **Microsoft sample script** — when present at `%SystemRoot%\SecureBoot\ExampleRolloutScripts\Detect-SecureBootCertUpdateStatus.ps1` (delivered by KB5089549 on Windows 11, KB5087544 / KB5088863 on Windows 10, and the WS2025 equivalent starting 2026-05-12), the script is launched as a child PowerShell to fetch Microsoft's confidence bucket assessment. A stdout-JSON fallback handles the MS script's input-validator bug that rejects any `-OutputPath` containing `:` (every absolute Windows path).

### Where it's displayed

| Phase | Form | Purpose |
|---|---|---|
| P00 | one-line compact: `Secure Boot baseline: enabled=true UEFI-CA-2023=NotStarted health=Warning [MS-sample=ok]` | Immediate operator awareness |
| P05 | full text appendix at the bottom of `inf_inventory_report.txt` | Change-management documentation |
| V05 | one-line compact `[Dry-Run UEFI Baseline]` block | Pre-commit sanity readout |
| V06 | full multi-section breakdown (Section 4 for chipset/graphics, Section 5 for NPU) | Detailed forensics view |
| I02 | pre-check + cross-reference with planned WDAC / testsigning path | Operator confirmation before touching OS-layer signing |

The same in-memory snapshot is reused across all five sites; the MS sample script is invoked at most once per run.

### Health classification

- **Healthy** — Secure Boot ON, UEFI CA 2023 rollout `Updated` (or not applicable), no rollout errors.
- **Warning** — Secure Boot ON but rollout is in flight (`NotStarted` / `Started` / `Pending`), scheduled task is disabled, or MS sample reports rollout-event diagnostics.
- **Critical** — Secure Boot OFF (planned WDAC path expects ON), or a non-zero `UEFICA2023Error` indicates a stuck rollout.

I02 surfaces the classification but **never blocks** on it (the two trust layers are independent). On `Critical` or `Warning` the operator sees a yellow advisory and decides whether to proceed.

### Diagnostic files

When the MS sample script is invoked, the following files are written under `<WorkRoot>\secureboot_ms_sample\`:

```
detect_stdout.log                  - Raw captured stdout (Write-Host + JSON)
detect_stdout_extracted.json       - Parsed JSON object (BucketId, Confidence, Event1801..1803 counts)
```

These are retained as part of the workspace artefact set and survive subsequent runs unless `-CleanWorkRoot` is passed.

---

## Console output format

Every line written by the scripts follows a structured, time-stamped format that is **identical across all four scripts** (chipset, graphics, NPU, BthPan). This is intentional — operators reading logs from mixed runs see the same vocabulary and visual layout.

### Marker semantics

| Marker | Colour    | Semantic | Example                                                          |
| ------ | --------- | -------- | ---------------------------------------------------------------- |
| `[*]`  | Cyan      | Step     | `[*] Acquiring signtool, inf2cat, and 7-Zip`                     |
| `[+]`  | Green     | Ok       | `[+] Cert thumbprint: A1B2C3D4...`                               |
| `[!]`  | Yellow    | Warn     | `[!] Tier 2 (AMD account auto-download) is disabled by default`  |
| `[X]`  | Red       | Fail     | `[X] Top-level error: AMD NPU not detected`                      |
| `[~]`  | DarkGray  | Skip     | `[~] Inventory CSV: C:\Temp\Workspace_AMD-NPU\inf_inventory.csv` |

Continuation lines that sit inside a section-banner table (PowerShell environment dump, OS profile, Secure Boot baseline, INF inventory rows, V05 / V06 / I00 sub-blocks) are rendered via the `Write-Detail` helper, which emits a 4-space-indented line with no timestamp or marker prefix. This is the single sanctioned exception to the "every line has a marker" rule. Operators reading raw logs should treat any 4-space-indented line as visually subordinate to the most recent marker line above it. (Introduced in chipset r56 / graphics r24; see SPEC §A.5.)

### Sample output (NPU script, P00 → P03)

```
========================================================================
 Deploy-AMDNpuDriverOnWindowsServer
 Version: npu-2026.05.17-r9  [npu-r9-debug-trace-facility-instrumentation-resume-ctx-autolog]  SHA256: e0ca465680db
 Action : PrepareVerify
 Repo   : https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer
========================================================================

========================================================================
 PHASE P00 - Initialize                 (Prep  )  start: 14:23:05
 script: npu-2026.05.17-r9/e0ca465680db
========================================================================
[14:23:05]            [*] Running environment and sanity checks
[14:23:05]            [+] Administrator privileges confirmed.
[14:23:05]            [~] TLS protocols enabled: Tls, Tls11, Tls12, Tls13
[14:23:06] [+0.42s]   [+] OS detected     : Microsoft Windows Server 2025 (build 26100)
[14:23:06] [+0.42s]   [~] Profile applied : WS2025
[14:23:06] [+0.42s]   [~] inf2cat /os: switch : Server2025_X64
 PHASE P00 -> DONE     elapsed: 0.45s

========================================================================
 PHASE P03 - FetchInstaller             (Prep  )  start: 14:23:12
========================================================================
[14:23:12]            [*] Detecting NPU platform and resolving installer source (4-tier fallback)
[14:23:12] [+0.18s]   [+] NPU codename         : Strix Point / Strix Halo
[14:23:12] [+0.18s]   [+] NPU short name       : STX
[14:23:12] [+0.18s]   [+] Hardware ID          : PCI\VEN_1022&DEV_17F0&REV_00
[14:23:12] [+0.18s]   [+] NPU driver package   : NPU_RAI1.6.1_314
[14:23:12] [+0.18s]   [+] NPU driver build     : 32.0.203.314
 PHASE P03 -> DONE     elapsed: 1.23s
```

The phase header banner (`=` × 72, Magenta) is emitted by the dispatcher; phase functions never print their own banner. The `[+X.XXs]` elapsed-tag is reset at each phase entry so it tracks **time inside the current phase**, not total runtime.

---

## Run log capture (`-LogFile`)

From Chipset r59 / Graphics r27 / NPU r9 / BthPan r9, all four scripts expose a `-LogFile <path>` parameter that captures the full console transcript via `Start-Transcript` / `Stop-Transcript`:

```powershell
# Recommended: color is preserved in the console, the file gets every stream as plain text
$ts  = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = "C:\Temp\amd-chipset_PrepareVerify_$ts.log"
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot -LogFile $log
```

Key properties:

- **Console keeps its `Write-Host -ForegroundColor` decoration intact** — unlike the legacy `*>&1 | Tee-Object -FilePath …` idiom, which strips Write-Host coloring on the way through the pipeline.
- **File receives every stream** (Output / Host / Error / Warning / Verbose / Debug) as plain UTF-8 text.
- **Parent directory auto-created** on demand (e.g. `C:\Temp\` is created if missing).
- **Append mode** (`-Append -Force`) — concurrent re-runs accumulate rather than truncate.
- **Idempotent cleanup** — `Stop-Transcript` is invoked from the top-level `finally` block and from a `PowerShell.Exiting` engine event handler as a fallback.

Recommended filename convention:

```
C:\Temp\<scripttag>_<Action>_<yyyyMMdd-HHmmss>.log
```

Examples:

| Script   | Suggested filename                                              |
| -------- | --------------------------------------------------------------- |
| Chipset  | `C:\Temp\amd-chipset_PrepareVerify_20260517-143022.log`         |
| Graphics | `C:\Temp\amd-graphics_Install_20260517-143022.log`              |
| NPU      | `C:\Temp\amd-npu_All_20260517-143022.log`                       |
| BthPan   | `C:\Temp\ms-bthpan_PrepareVerify_20260517-143022.log`           |

### Legacy fallback (`Tee-Object`)

The legacy `*>&1 | Tee-Object` idiom is still supported and may be preferable when the log file needs to be piped further into another tool. Note that **Write-Host coloring is stripped** in this mode (PowerShell's pipeline does not propagate the host stream's color information):

```powershell
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action Install *>&1 |
    Tee-Object -FilePath "C:\Temp\amd-chipset_Install_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
```

If you redirect output to a file (whether via `-LogFile` or `Tee-Object`) on a ja-JP host with the default code page (932 / Shift-JIS), set your file encoding explicitly to UTF-8 to avoid double-encoding of Japanese strings — the scripts call `Set-ConsoleUtf8` in P00 to enforce UTF-8 for `[Console]::OutputEncoding`, but consumers of the captured file (text editors, `Get-Content`, etc.) may still need to be told the file is UTF-8.

---

## System requirements

- **CPU**: For AMD scripts: AMD Ryzen 4000 series or newer (the script's `Get-AmdChipsetPlatform` heuristic recognises 4000 → AI 300, AI Max 300; older silicon may run but is untested). For the NPU script: Ryzen 7040 / 8040 / AI 300 / AI Max 300 / AI 200 series with an integrated NPU. For the BthPan script: any CPU; the prerequisite is a bound Bluetooth host controller (vendor-agnostic — Intel AX2xx, Realtek RTL88xx, MediaTek MT79xx, Broadcom BCM43xx all qualify).
- **OS**: Windows Server 2025 (build 26100) is the production target. Windows 11 24H2 (build 26100) is supported as a *preview* host (see [TESTING.md](./TESTING.md)). Windows Server 2016 / 2019 / 2022 are recognised by the OS profile matrix and inf2cat will pick a corresponding `/os:` switch (e.g. `Server2016_X64`, `ServerRS5_X64`, `ServerFE_X64`). The BthPan script's P08 explicitly targets all four (`Server2025_X64,ServerFE_X64,ServerRS5_X64,Server2016_X64`) in a single inf2cat invocation, so one signed catalog covers all Server SKUs.
- **PowerShell**: 5.1 (Windows PowerShell Desktop) or 7.x (PowerShell Core). The script's `Show-PowerShellEnvironment` phase prints the compatibility matrix it sees.
- **Disk**: ~5 GB on the workspace volume (~7 GB if you also run the NPU script). BthPan workspace is small (<10 MB — single INF/SYS/CAT).
- **Network**: outbound HTTPS to `*.amd.com`, `download.microsoft.com`, `go.microsoft.com`, `aka.ms` (winget), `timestamp.digicert.com` (signing timestamp), and (for the NPU script with Tier 2 download) `account.amd.com` and `*.entitlenow.com`. **The BthPan script needs network access only for timestamp signing** (`timestamp.digicert.com`); no AMD or Microsoft download endpoints are contacted.
- **Privileges**: Administrator on the local machine. No domain rights are required.
- **BthPan-specific**: a Bluetooth host controller bound and showing `Status=OK` in Device Manager (the script's V05 / V06 explicitly checks this before running Install). Without a host controller, the patched bthpan driver is still staged in the driver store but cannot bind to any device.

---

## Self-signed certificate: expiry, renewal, and revocation

The certificate generated in P07 is the **trust anchor** for every patched driver this pipeline installs. It deserves its own section.

### Certificate properties

- **Subject**:
  - `CN=AMD Chipset Driver Self-Sign (WS2025 Lab, At Own Risk)` (chipset)
  - `CN=AMD Graphics Driver Self-Sign (WS2025 Lab, At Own Risk)` (graphics)
  - `CN=AMD NPU Driver Self-Sign (WS2025 Lab, At Own Risk)` (NPU)
  - `CN=Microsoft BthPan Driver Self-Sign (<OsCode> Lab, At Own Risk)` (BthPan; `<OsCode>` is the host OS short name, e.g. `WS2025`)
- **Key**: RSA 4096-bit on WS2019+ / Win11+, RSA 2048-bit on WS2016. SHA-384 signature algorithm on WS2025, SHA-256 on WS2016/2019/2022.
- **EKU**: Code Signing (`1.3.6.1.5.5.7.3.3`).
- **Validity**: **5 years from the day P07 ran** (WS2019+); 3 years on WS2016. Hard-coded in the script.
- **Storage**: PFX in `C:\Temp\Workspace_AMD-{Chipset,Graphics,NPU}\cert\` or `C:\Temp\Workspace_Microsoft-BthPan\cert\`. The PFX is **not** password-protected by default (this is a lab tool; if you need a real password, change `[string]$PfxPassword = ''` in the param block).
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

8. **Driver-category priority override (chipset r56 / graphics r24 — BREAKING change).** From these revisions the script's install-decision logic ranks self-signed drivers ([C]) above hardware-vendor drivers ([B]) and Microsoft generic drivers ([A]), regardless of driver version. On a clean WS2025 install this is exactly the intent — Microsoft's in-box generics will be replaced by AMD-vendor drivers carrying the script's signature. The trade-off is that any AMD-vendor driver already installed via Windows Update or an OEM package will *also* be overwritten by the script's self-signed equivalent (the binaries are the same; only the publisher differs). If you want to preserve a vendor driver, run `-Action PrepareVerify` first, inspect V06 Section 2, and decide whether to proceed. See SPEC §D.15 for the full rationale.

9. **NPU script (`Deploy-AMDNpuDriverOnWindowsServer.ps1`) is markedly higher-risk than its sister scripts.** Specifically:
   - **No physical-NPU validation** has been performed by the maintainers as of this writing. All testing has been static analysis with `psa.py` and code-review of the AMD-published `quicktest.py` detection logic translated to PowerShell.
   - **AMD account auto-download (Tier 2) is best-effort and may break without notice** when AMD updates `account.amd.com` form layouts, CSRF handling, or the entitlenow.com CDN URL scheme. Always prefer Tier 4 (`-OfflineZip`) for reproducible runs.
   - **Ryzen AI Software is officially Windows-11-only per AMD documentation** (build >= 22621.3527). Even if the NPU kernel driver loads on Windows Server 2025, the user-mode stack (Python conda env, ONNX Runtime VitisAI EP, OGA) is not expected to function. **Do not deploy the NPU script in environments expecting AI inference workloads on Server 2025.**
   - **Driver-store cleanup is best-effort.** Removing self-signed NPU drivers from the driver store after `-Action Install` may require manual `pnputil /delete-driver oemNN.inf /force` or use of Driver Store Explorer (Rapr.exe).

10. **No commercial support is offered through this repository.** GitHub Issues at <https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/issues> are best-effort for bug reports and clarification questions. Pull requests are welcome but not guaranteed to be reviewed on any timeline.

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
- File an issue: <https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/issues>

### NPU script "All 4 download tiers exhausted"

This is the most common NPU-script failure. The EULA-gated AMD form requires an authenticated AMD account session that the script cannot fully simulate. Workarounds in priority order:

1. **Manually download** the ZIP from <https://ryzenai.docs.amd.com/en/latest/inst.html#install-npu-drivers>, place it next to the script, re-run with `-OfflineZip .\NPU_RAI*.zip`.
2. **Try `-AmdAccountUser` / `-AmdAccountPassword`** but expect breakage; AMD form structure changes are not announced.
3. **Capture the entitlenow.com URL** from a browser session after manual EULA acceptance, pass via `-InstallerUrl <captured-url>`. The URL has a time-limited hash; download immediately after capture.

### NPU script "No AMD NPU detected via pnputil"

The host has no AMD NPU device. Either:

- This is intentional (pipeline-soundness check on a host without NPU): pass `-AssumeIfMissing` to proceed with the default Strix Point + RAI 1.7.1 profile.
- This was unexpected (you believed you had a Ryzen AI machine): check Device Manager for unbound PCI devices; check Task Manager → Performance for an NPU0 entry; check that the BIOS has not disabled the NPU.

### "V06 shows MS-GENERIC drivers on AMD hardware that the patched INFs don't cover"

CPU cores (`cpu.inf`), PCI Express Root Ports (`pci.inf`), Host CPU Bridges (`machine.inf`), USB xHCI (`usbxhci.inf`), HD Audio Controller (`hdaudbus.inf`) are **all expected to remain on Microsoft generic drivers**. AMD does not ship vendor drivers for these (they're enumerated by core OS subsystems). The "ALERT" message in V06 Section 1 is informational, not an error.

### "I02 deploys WDAC policy but new driver still doesn't load"

Check `eventvwr` → `Applications and Services Logs` → `Microsoft` → `Windows` → `CodeIntegrity` → `Operational` for events 3076 / 3077 / 3091. The Issuer / Subject / Thumbprint of the blocked signature should match your self-signed cert. If they don't match, the WDAC policy isn't deployed correctly — try `CiTool -lp` to list active policies.

### "AMD driver was installed but Device Manager still shows MS generic on the device"

Run `pnputil /scan-devices` to force a re-enumeration. If still bound to MS, the patched INF's HWID may not match the device's PNP ID exactly. Check V06 Section 2 ("WILL be replaced" / "have no patched INF") — if the device falls into the latter category, no patched driver claims that HWID, which is expected for some devices (USB hubs, generic xHCI controllers, etc.).

### "I02 appears to hang for 60+ seconds between 'Converting XML to .cip binary...' and 'Deployed:' lines"

**Pre-r57 / pre-r25 / pre-r6 only.** CiTool.exe was invoked without the `--json` flag and printed "続行するには、Enter キーを押してください" (Press Enter to Exit) to the console, blocking the script on stdin. Pressing ENTER in the active console window resumed the script. This is fixed in chipset r59 / graphics r27 / NPU r9 by passing `--json` to all CiTool.exe invocations, which suppresses the interactive prompt per Microsoft's CiTool design (the `--json` flag documents itself as "出力を json として書式設定し、入力を抑制する"). Upgrade the script and the hang will no longer occur. See SPEC §D.16 for the full root-cause analysis.

### "CiTool log line shows mojibake like '蜃ｦ逅・・謌仙粥縺励∪縺励◆'"

**Pre-r57 / pre-r25 / pre-r6 only.** This is the UTF-8 byte sequence of `処理が成功しました` interpreted as cp932 (Shift-JIS). CiTool.exe writes UTF-8 to stdout, but PowerShell decoded it using the default ja-JP `[Console]::OutputEncoding` (cp932). SPEC §A.5 / §D.5 mandated UTF-8 enforcement at P00 but the implementation was missing. Fixed in chipset r59 / graphics r27 / NPU r9 via `Set-ConsoleUtf8` at P00. See SPEC §D.16.

### "I03 says '3 failed' but I04 says 'Failed: 0' on the same install run"

**Pre-r57 / pre-r25 only.** I03's classification logic treated pnputil `exit=259` (`ERROR_NO_MORE_ITEMS`) as a failure, but I04's PostInstallVerification reads the actual device state and correctly identifies these as `REBOOT_NEEDED` (when a sibling-INF first install already queued the binding) or as no-op (driver package already in store). The exit=259 cases are typically from duplicate-source INFs (e.g. `Chipset_Software\SMBus Driver\W11x64\SMBUSamd.inf` and `SMBus Driver\W11x64\SMBUSamd.inf` are both visited by I03, the second returns 259). Fixed in chipset r57 / graphics r25: the new I03 summary reports four categories — `ok` / `need reboot` / `no-op` / `failed` — and exit=259 maps to the new `no-op (already present)` status (Write-Skip / DarkGray). See SPEC §D.17.

### NPU script "I04 shows the device is bound but Ryzen AI Software won't initialize"

This is the expected outcome on Windows Server 2025. The kernel-mode driver loads, but the Ryzen AI Software user-mode stack (Python conda env, ONNX Runtime VitisAI EP, OGA) is officially Windows-11-only. Do not expect AI workload functionality on Server 2025. Either:

- Use Windows 11 24H2 for actual NPU inference workloads.
- Treat the Server 2025 install as kernel driver bring-up only (lab / research).

---

## Development tools

### `psa.py` — PowerShell Static Analyzer

The PowerShell static analyzer used to validate the pipeline scripts is `psa.py`. It is **maintained as a single canonical artifact** in a separate repository — [`usui-tk/ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts) — under [`scripts/python/powershell-static-analyzer/`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer). This repository does **not** bundle a local copy; obtain `psa.py` via one of the methods below before using it.

A single-file Python 3 static analyzer that catches common PowerShell mistakes the regular parser does not flag.

#### Obtaining `psa.py`

**Method 1 — Clone the canonical repository (recommended for ongoing development)**

```bash
# Clone the canonical repository as a sibling directory to this repo
git clone https://github.com/usui-tk/ai-generated-artifacts.git ../ai-generated-artifacts

# Run from this repository's root
python3 ../ai-generated-artifacts/scripts/python/powershell-static-analyzer/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 ../ai-generated-artifacts/scripts/python/powershell-static-analyzer/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
python3 ../ai-generated-artifacts/scripts/python/powershell-static-analyzer/psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
```

**Method 2 — Download the single file (recommended for one-shot CI runs)**

Linux / macOS (curl):

```bash
curl -sSLO https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py
python3 psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
```

Windows PowerShell (Invoke-WebRequest):

```powershell
Invoke-WebRequest `
    -Uri  "https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py" `
    -OutFile psa.py
python3 psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
```

In the rest of this document and in `SPEC.md` / `TESTING.md` / `CONTRIBUTING.md`, commands of the form `python3 psa.py <script>.ps1` assume that `psa.py` has already been obtained via Method 1 or Method 2 above and is accessible on a path of your choice.

#### Checks performed

`psa.py` v3.2.0 ships with a **34-rule** check set spanning `PSA1001`..`PSA9002` for generic rules plus `PSAP0001`..`PSAP0002` for project / pipeline convention rules, grouped into nine categories:

| Category                       | Code range                | Examples                                                                                                                                                                                                                                       |
| ---                            | ---                       | ---                                                                                                                                                                                                                                            |
| Syntax balance                 | `PSA1001`..`PSA1003`      | brace / paren / bracket balance                                                                                                                                                                                                                |
| Semantics                      | `PSA2001`..`PSA2006`      | undefined variable, auto-variable shadowing, `-match` against bare variable, `$null` on the right of `-eq`/`-ne`, assignment / redirection inside conditional                                                                                  |
| Coding pattern                 | `PSA3001`..`PSA3005`      | `Start-Process -ArgumentList`, trailing backtick before empty line, `-match` against empty string, empty `catch` block, **NEW in 3.2.0:** `Start-Transcript -Path` should be `-LiteralPath`                                                    |
| Hygiene                        | `PSA4001`..`PSA4004`      | unfinished markers (TODO / FIXME / XXX / HACK), trailing whitespace, long line, trailing semicolon                                                                                                                                             |
| Security                       | `PSA5001`..`PSA5004`      | plain-text password parameter, `Invoke-Expression`, broken hash algorithm, hardcoded `ComputerName`                                                                                                                                            |
| Best practice                  | `PSA6001`..`PSA6006`      | non-approved verb, cmdlet alias, plural function noun, `$global:` definition, mandatory parameter with default, switch defaulting to `$true`                                                                                                   |
| File format                    | `PSA7001`                 | missing UTF-8 BOM on `.ps1` (Windows PowerShell 5.1 ja-JP falls back to Shift-JIS / cp932 without BOM)                                                                                                                                          |
| **NEW: Cross-file consistency** | `PSA8001`                 | function body hash drift across files in the same scan — enforces that shared helper functions (`Format-Elapsed`, `Write-Detail`, `Start-DebugTrace` family, etc.) stay byte-for-byte synchronised across the four pipeline scripts            |
| **NEW: Complexity metrics**    | `PSA9001`..`PSA9002`      | function-body length threshold (off by default), external-process invocation without `$LASTEXITCODE` check (off by default)                                                                                                                    |
| **NEW: Project / pipeline conventions** | `PSAP0001`..`PSAP0002` | phase function naming convention (`Invoke-(Prep\|Verify\|Inst)PhaseNN_Name`), required script-identifier variables (`$Script:ScriptVersion` / `$Script:ScriptHash` / `$Script:ScriptShortTag`) — **all PSAPxxxx rules are off by default**; opt in via `.psa.config.json` |

For the authoritative specification of every rule, see [`scripts/python/powershell-static-analyzer/SPEC.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/python/powershell-static-analyzer/SPEC.md) §4 in the [ai-generated-artifacts](https://github.com/usui-tk/ai-generated-artifacts) repository.

#### Repository-specific configuration

This repository ships its own `.psa.config.json` at the repository root. It is the **canonical configuration for the four pipeline scripts** and does three things:

1. **Opts in to `PSAP0001` and `PSAP0002`** so that the 21-phase naming convention (`Invoke-(Prep|Verify|Inst)PhaseNN_DescriptiveName`) and the script-identity trio (`$Script:ScriptVersion` / `ScriptHash` / `ScriptShortTag`) are enforced.

2. **Configures `PSA8001` (cross-file function-body drift)** with `psa8001_ignore_functions`, listing roughly 45 function names that are intentionally per-script (phase functions, per-driver-family helpers, `Show-Help`, etc.). Shared helpers NOT listed there MUST stay byte-for-byte identical across all four scripts.

3. **Disables `PSA4003` (long line)** because the pipeline scripts intentionally use multi-clause `-f` format strings that exceed 120 columns for readability.

Run static analysis against all four pipeline scripts via:

```bash
# From the repository root, after psa.py has been obtained (Method 1 or 2 above)
python3 path/to/psa.py --config ./.psa.config.json \
    Deploy-AMDChipsetDriverOnWindowsServer.ps1 \
    Deploy-AMDGraphicsDriverOnWindowsServer.ps1 \
    Deploy-AMDNpuDriverOnWindowsServer.ps1 \
    Deploy-MSBthPanInboxOnWindowsServer.ps1
```

All four scripts MUST be passed in a single invocation for PSA8001 cross-file analysis to work; with a single file PSA8001 has no peers to compare against and emits nothing. The baseline as of r60 / r28 / r10 / r10 is **0 errors / 0 warnings / 0 info**.

Exit codes: `0` = clean, `1` = warnings only, `2` = errors. Useful in CI:

```yaml
# .github/workflows/lint.yml example (Method 2 — single-file download)
- name: Fetch psa.py from canonical repository
  run: |
    curl -sSLO https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py
- name: Static-analyze PowerShell scripts
  run: |
    python3 psa.py --config ./.psa.config.json \
        Deploy-AMDChipsetDriverOnWindowsServer.ps1 \
        Deploy-AMDGraphicsDriverOnWindowsServer.ps1 \
        Deploy-AMDNpuDriverOnWindowsServer.ps1 \
        Deploy-MSBthPanInboxOnWindowsServer.ps1
```

For the full design rationale, output format reference, and an extended CI integration example, see the canonical README at [`scripts/python/powershell-static-analyzer/README.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/python/powershell-static-analyzer/README.md) in the [ai-generated-artifacts](https://github.com/usui-tk/ai-generated-artifacts) repository.

---

## Developer specification

For the full developer specification — including phase architecture rules, banner / log conventions, parameter naming conventions, CSV / JSONL output format, path-handling rules (`-LiteralPath`), and the quality gates enforced by `psa.py` — see:

- [**SPEC.md**](./SPEC.md) — Developer specification (the authoritative reference for contributors and AI assistants working on this codebase). **English only** per the repository-wide documentation language policy (see SPEC.md §A.12).

`SPEC.md` is structured in three parts:

- **Part A — Common Specification.** Reusable rules across the four scripts (phase architecture, banner / log markers, parameter conventions, error handling, CSV column conventions, path-handling rules). Pick this up first if you are extending any of the four scripts or adding a fifth.
- **Part B — Script-specific Specifications.** One section per script (Chipset / Graphics / NPU) documenting the unique platform-detection logic, INF inventory filters, installer source resolution tiers, and known platform quirks.
- **Part C — Quality Gates & Lessons Learned.** What `psa.py` checks for, what regression tests `TESTING.md` covers, and the historical fixes (e.g. timezone-induced DriverDate false positives in chipset r46) that are baked into the current implementation.

If you are adding a new feature, the recommended workflow is: read `SPEC.md` → read the relevant script's existing `Invoke-*Phase*_*` functions → make changes → run `python3 psa.py <script>.ps1` (after obtaining it per [Development tools](#development-tools)) → update `TESTING.md` with any new regression scenarios.

---

## File encoding

### PowerShell scripts (`*.ps1`)

All `*.ps1` files in this repository are **checked out as UTF-8 with BOM and CRLF line endings** on every platform. This is the canonical encoding for PowerShell 5.1 + 7.x scripts that contain non-ASCII characters (the Japanese log strings inside `Write-Skip` / `Write-Warn2` calls). The `.gitattributes` rule that enforces this is:

```
*.ps1 text working-tree-encoding=UTF-8 eol=crlf
```

A note on git's internal storage: git applies standard text normalization at commit time. The blob inside the repository stores **BOM + LF** (line endings normalized to LF). On `git clone` / `git checkout`, git converts LF back to CRLF for `*.ps1` files thanks to the `eol=crlf` directive, so the file on disk is **BOM + CRLF** — which is what Windows PowerShell expects. The BOM is preserved as content bytes in both forms.

**Caveat for raw downloads**: if you download a `.ps1` file via the GitHub "Raw" button or `curl https://raw.githubusercontent.com/.../*.ps1`, you receive the blob form directly (**BOM + LF**) — git's checkout-time conversion does not apply to raw blob downloads. PowerShell 5.1 and 7.x handle both LF and CRLF in scripts correctly, so the file still executes, but if you need the exact canonical form (BOM + CRLF) you should clone the repository rather than downloading individual raw files. Practical recommendations:

- **For execution on Windows**: clone the repo (`git clone https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer.git`), don't right-click → "Save raw as" individual files.
- **For inspection or quick patching**: raw downloads are fine; PowerShell tolerates LF line endings.
- **For re-publication or mirroring**: if you re-host the scripts elsewhere, regenerate them as BOM + CRLF to match the canonical form.

### Markdown documents (`*.md`)

All `*.md` files (`README.md`, `README.ja.md`, `TESTING.md`, `SPEC.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`) are stored and checked out as **UTF-8 without BOM** with **LF** line endings — the GitHub-native convention for Markdown rendering. The `.gitattributes` rule:

```
*.md text eol=lf
```

If you edit these files on Windows with an editor that auto-injects a BOM into `.md` files (some older Notepad++ versions do this), strip the BOM before committing or let `.gitattributes` normalize on next checkout.

### Console output and the Japanese log strings

The Japanese log strings inside the `.ps1` scripts are designed to render correctly on a ja-JP Windows console that is set to UTF-8 (`chcp 65001`). If your console is at the default ja-JP code page (932 / Shift-JIS), Japanese strings may garble. The scripts include a `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` call in P00 to enforce this, but if you redirect output to a file via `*>&1 | Tee-Object`, set your file encoding explicitly to UTF-8 to avoid double-encoding.

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

- [TESTING.md](./TESTING.md) — Physical-hardware validation results and the NPU script's far weaker validation status. **English only.**
- [SPEC.md](./SPEC.md) — Developer specification. **English only.**
- [CHANGELOG.md](./CHANGELOG.md) — Chronological per-release change log. **English only.**
- [CONTRIBUTING.md](./CONTRIBUTING.md) — How to contribute.
- [README.ja.md](./README.ja.md) — Japanese translation of this document, kept in sync.
- [`psa.py` canonical location (ai-generated-artifacts)](https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer) — PowerShell static analyzer used by this repository's CI gates.

---

## License

[MIT License](./LICENSE). Copyright (c) 2026 contributors.

The MIT licence applies to the **PowerShell scripts and accompanying documentation in this repository only**. The scripts download AMD installer EXEs and Ryzen AI driver ZIPs at runtime and do not redistribute AMD's binaries, INFs, or catalogs. AMD's redistribution terms apply to those files independently.

---

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for issue templates, PR guidelines, and how to run the regression test suite (including `psa.py`).

Issues and pull requests are tracked at: <https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer>

Additional community documents:

- [`CODE_OF_CONDUCT.md`](./CODE_OF_CONDUCT.md) — Expected behaviour when interacting through Issues, Pull Requests, and Security Advisories. Tailored to the safety implications of self-signed kernel-mode drivers.
- [`SECURITY.md`](./SECURITY.md) — How to report security-impacting defects (driver-signing flaws, WDAC policy scope errors, credential exposure). **Do NOT file these as public Issues** — use the private Security Advisory channel instead.
- [`CHANGELOG.md`](./CHANGELOG.md) — Chronological per-release change log (every revision from r1 onward, organised by date and by script).
