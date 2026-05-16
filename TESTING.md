# TESTING.md — Physical Hardware Validation Results

This document consolidates the validation results for `Deploy-AMD-Drivers-For-WindowsServer`. Because this repository ships **experimental scripts that target AMD's consumer-class Ryzen chipset / Radeon iGPU / Ryzen AI NPU**, all meaningful validation depends on access to physical AMD consumer hardware. Testing on non-AMD-consumer hardware (server-class EPYC, ARM, Intel, virtual machines without the target devices, etc.) cannot exercise the device-bind, driver-upgrade, or post-install verification paths that this pipeline exists to validate. This document therefore covers only physical-hardware validation:

1. **Validation Result 1: ThinkCentre M75q Tiny Gen 2** (Windows Server 2025 physical / Cezanne Zen 3 — chipset & graphics validated)
2. **Validation Result 2: ThinkPad X13 Gen 1 AMD (2020)** (Windows 11 Enterprise LTSC 2024 / Renoir Zen 2 — chipset & graphics validated)
3. **Validation Result 3 (NPU script)** — **🆘 NOT YET VALIDATED on physical NPU hardware. See [§3](#3-validation-result-3-npu-script--currently-unverified) for the current limited validation status.**

🇯🇵 **Japanese version: see [TESTING.ja.md](./TESTING.ja.md).**

---

## 0. Validation status summary

> Read this before sections 1-3. The three scripts have **very different validation maturity levels**.

| Script | Physical-hardware validation | Real driver install on target HW | Recommended use |
|---|---|---|---|
| **Chipset (r56)** | ✓ M75q Tiny Gen 2, X13 Gen 1 AMD (validated on r55; r56 carries a breaking install-decision change — see note below) | ✓ install completed successfully on M75q (WS2025) | Lab + cautious production |
| **Graphics (r24)** | ✓ M75q Tiny Gen 2, X13 Gen 1 AMD (validated on r23; r24 carries a breaking install-decision change — see note below) | ✓ install completed successfully on M75q (WS2025) | Lab + cautious production |
| **NPU (r6)** | ❌ **none** (no physical NPU machine in maintainer's lab) | ❌ **never executed** | **Experimental / research-grade only. Do not deploy in production.** |

> **Note on r56 / r24 behaviour change**: The category-priority override added in chipset r56 and graphics r24 (see SPEC §D.15) changes the install-decision semantics in a breaking way: self-signed `[C]` drivers now always supersede Microsoft generic `[A]` and vendor `[B]` drivers regardless of version. The pre-r56/r23 physical-hardware validation results below remain *structurally* valid (extraction, patching, signing, WDAC deployment all behave the same), but the **V05/V06/I03 driver-install decisions will differ** — devices that the prior versions classified as `SKIP-newer` are now classified as `INSTALL_UPGRADE`. Re-validation on the M75q Tiny Gen 2 and X13 Gen 1 AMD fixtures is recommended after deploying r56/r24.

The NPU script's verification is currently limited to:

1. **Static analysis** with `psa.py` v3.1.0 (28-rule check set `PSA1001`..`PSA7001`, **0 errors** with a documented baseline of warnings/info — see `SPEC.md` §A.11.5). `psa.py` is maintained as a canonical artifact in the [ai-generated-artifacts](https://github.com/usui-tk/ai-generated-artifacts) repository; obtain it per `SPEC.md` §A.11 before running.
2. **Code review** of the AMD-published `quicktest.py` NPU detection logic translated to PowerShell.
3. **No `-Action Install` execution** has been performed by the maintainers anywhere.
4. **No end-to-end run on physical NPU hardware** has been performed by the maintainers.

If you have a Ryzen AI 300 / Ryzen AI Max 300 / Ryzen 7040 / 8040 series machine and successfully run any phase of the NPU script, please report results via GitHub Issues so the validation gap can be closed.

---

## 1. Validation Result 1: ThinkCentre M75q Tiny Gen 2 (Windows Server 2025)

### 1.1 Hardware specifications

| Item | Value |
|---|---|
| Model | Lenovo ThinkCentre M75q Tiny Gen 2 |
| CPU | AMD Ryzen 7 PRO 5750GE (Cezanne, Zen 3, 8 core / 16 thread, 35 W TDP) |
| iGPU | AMD Radeon Graphics (Vega 8, integrated in Cezanne) |
| **NPU** | **none (Cezanne predates AMD's NPU; XDNA NPU first appears in Phoenix / 7040 series)** |
| Memory | DDR4 SO-DIMM 16–32 GB |
| Storage | M.2 NVMe SSD |
| BIOS | UEFI, Secure Boot configurable |
| TPM | fTPM (via AMD PSP) |

### 1.2 OS configuration

| Item | Value |
|---|---|
| OS | Windows Server 2025 Standard / Datacenter |
| Build | 26100 |
| ProductType | 3 (Server) |
| Secure Boot | ON |
| HVCI | OS default (varies by environment) |
| BitLocker | Optional (when enabled, **secure the recovery key in advance**) |

### 1.3 Validation procedure (chipset + graphics only — no NPU on this host)

```powershell
# Elevated PowerShell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Stage 1: PrepareVerify, V06 review (system unchanged)
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\m75q-chipset-prepareverify.log
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\m75q-graphics-prepareverify.log

# Stage 2: Once V06 risk is acceptable, run Install
# IMPORTANT: secure the BitLocker recovery key beforehand
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Install
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Install

# NPU script: NOT APPLICABLE on Cezanne hardware (no NPU device present)
# M75q has no NPU device, so the NPU script cannot be meaningfully exercised here.
```

### 1.4 Key validation results

#### Chipset script

- **P03 detection**: `Cezanne / Zen 3 / Desktop APU, AM4`
- **P03 download**: `amd_chipset_software_8.02.18.557.exe` (~75 MB)
- **P05 inventory**: 67 INFs detected; 32 W11x64 variant INFs selected
- **P06 patching**: 1 INF patched (`AmdMicroPEP.inf`); 31 INFs already Server-compatible and copied through
- **V06 main upgrade candidates** (varies with the actual OEM driver baseline):
  - AMD GPIO Controller: `oem17.inf v2.2.0.130` → `amdgpio2.inf v2.2.0.136`
  - AMD PSP 10.0 Device: `oem26.inf v5.22.0.0` → `amdpsp.inf v5.43.0.0` (HIGH risk — BitLocker caution)
  - AMD SMBus: `oem12.inf v5.12.0.38` → `SMBUSamd.inf v5.12.0.44`

#### Graphics script

- **P03 detection**: `Cezanne APU, Vega-Polaris Legacy branch`
- **P03 download**: `whql-amd-software-adrenalin-edition-XX.X.X-win11-XXX-vega-polaris.exe` (~600 MB)
- **P05 inventory**: 19 INFs detected; `WT64A` (audio) + `WT6A_INF` (display) variants selected
- **P06 patching**: 1 INF patched (`u0197843.inf`); 18 INFs already Server-compatible and copied through
- **V06 main upgrade candidates**:
  - AMD Audio CoProcessor: `oem70.inf v6.0.0.79` → `amdacpbus.inf v6.0.1.83` (MEDIUM risk)
  - AMD Radeon Graphics: newer version in the AMD package → display upgrade (MEDIUM risk)
  - AMD HD Audio Device: `oem58.inf v10.0.1.30` → `AtihdWT6.inf v10.0.1.30` (date-newer, MEDIUM risk)

#### NPU script

- **Not applicable on this host** (Cezanne has no NPU). The NPU script cannot be meaningfully exercised on hardware that lacks an XDNA NPU device.

#### Soundness checks

- All 21 phases completed successfully (chipset + graphics)
- Self-signed certificate (RSA 4096 / SHA-384, 5-year validity) generated successfully
- 32 catalogs (chipset) + 19 catalogs (graphics) generated by `inf2cat /os:Server2025_X64`
- All catalogs successfully timestamp-signed by `signtool`
- After I03 (Install), Device Manager shows 3 chipset + 3 graphics devices bound to `[C] Self-signed`

### 1.5 Known limitations

- On hosts with BitLocker enabled, a PSP driver upgrade can trigger a recovery prompt at the next boot. **Always have the recovery key available** (Control Panel BitLocker UI, or via Microsoft Account backup).
- Some `ROOT\AMD*` software-only entities (AMDLOG / AMDXE etc.) are added by I03 but never appear in `Win32_PnPSignedDriver` enumeration; V06 Section 1 reports them as "software-only" for information only.
- Successful install is confirmed by the `[B] Vendor` → `[C] Self-signed` transition observed in I04.

---

## 2. Validation Result 2: ThinkPad X13 Gen 1 AMD (2020) — Windows 11 Enterprise LTSC 2024

### 2.1 Hardware specifications

| Item | Value |
|---|---|
| Model | Lenovo ThinkPad X13 Gen 1 (AMD, 2020) |
| CPU | AMD Ryzen 5 PRO 4650U (Renoir, Zen 2, 6 core / 12 thread, 15 W TDP) |
| iGPU | AMD Radeon Graphics (Vega 6, integrated in Renoir) |
| **NPU** | **none (Renoir predates AMD's NPU)** |
| Memory | DDR4 16 GB on-board |
| Storage | M.2 NVMe SSD |
| BIOS | UEFI, Secure Boot toggleable |
| TPM | dTPM (Discrete TPM, e.g. Infineon SLB9670) |

### 2.2 OS configuration (at validation time)

| Item | Value |
|---|---|
| OS | Microsoft Windows 11 Enterprise LTSC 2024 |
| Build | 26100 (24H2 LTSC) |
| ProductType | 1 (Workstation) — runs in **WS2025 PREVIEW MODE** in this script |
| Secure Boot | OFF (toggled off for testing) |
| HVCI | ON |
| BitLocker | OFF (lab use) |

### 2.3 Validation procedure

Windows 11 Enterprise LTSC 2024 shares NT kernel build 26100 with Windows Server 2025, so the script runs in **WS2025 PRE-MIGRATION PREVIEW MODE** (P00 banner declares it explicitly).

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Install phases auto-block on Workstation OS — PrepareVerify only
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\x13gen1-chipset-Win11-preview.log
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\x13gen1-graphics-Win11-preview.log

# NPU script: NOT APPLICABLE (no NPU on Renoir)
```

### 2.4 Key validation results

#### P00 OS detection (Workstation preview)

```
[+] OS detected: Microsoft Windows 11 Enterprise LTSC (build 26100)
    Profile applied : WS2025 (Windows Server 2025)
    ProductType     : 1  (1=Workstation, 3=Server)

    +-----------------------------------------------------------------+
    | WS2025 PRE-MIGRATION PREVIEW MODE                               |
    | (Windows 11 24H2 and Windows Server 2025 share NT build 26100)  |
    +-----------------------------------------------------------------+
```

Install phases auto-block (override with `-AllowWorkstationInstall`, but discouraged).

#### Chipset script

- **P03 detection**: `Renoir / Zen 2 / Mobile`
- **P03 download**: `amd_chipset_software_8.02.18.557.exe` (same as M75q)
- **P05 inventory**: 67 INFs detected; 32 W11x64 variant INFs selected
- **P06 patching**: 1 INF patched (`AmdMicroPEP.inf`)
- **V06 main upgrade candidates** (compared against Win11 OEM drivers):
  - AMD PSP 10.0 Device: `oem144.inf v5.42.0.0` → `amdpsp.inf v5.43.0.0` (HIGH risk)
  - GPIO / I2C / SMBus / MicroPEP — same version (KEEP)

#### Graphics script

- **P03 detection**: `Renoir / Vega-Polaris Legacy`
- **P03 download**: `whql-amd-software-adrenalin-edition-26.1.1-win11-jan-vega-polaris.exe` (~624 MB)
- **P05 inventory**: 19 INFs detected; `WT64A` + `WT6A_INF` variants selected
- **P06 patching**: 1 INF patched (`u0197843.inf`), mirroring 6 decorations
- **V06 upgrade candidates**:
  - AMD Audio CoProcessor: `v6.0.0.79 → v6.0.1.83` (real version upgrade)
  - AMD Radeon Graphics: `v31.0.21923.11000 → v31.0.21924.61` (real version upgrade)
  - AMD HD Audio Device: `v10.0.1.30 → v10.0.1.30` (date-only newer; graphics r16 explicitly displays "same version, but newer date")

#### Soundness checks

- All 21 phases completed (Install phases auto-blocked because the host is Workstation OS)
- All 19 INFs flow through the pipeline
- 19 catalogs + 19 signtool signatures all succeed
- AMD HW detected: AMD Audio CoProcessor, AMD Radeon Graphics, AMD HD Audio Device, AMD GPIO Controller, AMD I2C Controller, AMD Micro PEP, AMD SMBus, AMD PSP 10.0 Device, etc.

### 2.5 Expected delta between Win11 and WS2025 on identical hardware

Comparing Validation Result 1 (M75q + WS2025) and Validation Result 2 (X13 Gen 1 + Win11 24H2): **the script's decision logic is identical between the two OSes because they share kernel build 26100**, but **V06 upgrade candidate counts differ because the existing OEM driver baseline differs**:

| V06 section | M75q (WS2025) | X13 Gen 1 (Win11) |
|---|---|---|
| Detected AMD HW | identical detection logic (HW topology differs by machine) | identical |
| MS-GENERIC count | high (clean WS2025 has bare Server in-box drivers) | lower (Win11 has OEM drivers pre-installed) |
| WILL be replaced count | more (MS generic → AMD vendor swaps are frequent) | fewer (only swap when AMD package is newer than the OEM driver) |
| KEEP (same/newer) count | fewer | more |
| Recommended Install execution | YES (target host) | NO (Workstation OS, auto-blocked) |

In other words, **PrepareVerify on Win11 24H2 functions as pre-migration verification for WS2025**: the patched-INF signatures and catalog structures generated remain valid on WS2025 (same kernel build). The actual install decisions (which devices fall into WILL be replaced) should be re-confirmed on WS2025 after migration.

---

## 3. Validation Result 3 (NPU script) — currently UNVERIFIED

> **🆘 THIS SECTION DOCUMENTS WHAT HAS NOT BEEN VERIFIED.** Do not interpret it as evidence of working behaviour.

### 3.1 What is currently verified for the NPU script

| Verification activity | Status | Evidence |
|---|---|---|
| Static analysis with `psa.py` v3.1.0 (see `SPEC.md` §A.11) | ✅ done | 0 errors / 26 warnings / 0 info — fully baselined (see §A.11.5) |
| Code review of NPU detection logic | ✅ done | `Get-AmdNpuPlatform` is a direct PowerShell port of AMD-published `quicktest.py` |
| Detection on physical NPU machine | ❌ **NOT DONE** | No physical NPU hardware in maintainer's lab as of this writing |
| INF parsing of real NPU driver ZIP | ❌ **NOT DONE** | NPU driver ZIPs (`NPU_RAI*_WHQL.zip`) are EULA-gated; maintainer does not have a verified copy of every RAI version's INF structure |
| `-Action Install` on physical NPU machine | ❌ **NOT DONE** | Same as above |
| Post-install bind to `[C] Self-signed` | ❌ **NOT DONE** | Same as above |
| AMD account auto-download (Tier 2) | ⚠️ **best-effort, unstable** | Implemented from public form structure observation; AMD form changes can break without notice |
| Ryzen AI Software user-mode stack on Server 2025 | ❌ **explicitly unsupported by AMD** | AMD documentation states Win11 24H2 (build >= 22621.3527) only |

> **Note on validation scope**: The validation of this NPU script is fundamentally bottlenecked by access to physical Ryzen AI hardware. Because the script is an experimental tool targeting AMD's consumer-class NPU silicon, no meaningful end-to-end validation can be performed on hardware that lacks the target NPU device. Static analysis and code review are the only verification activities completed; everything that depends on actual device-bind behaviour, INF parsing of real driver ZIPs, or post-install verification remains pending until a physical NPU machine becomes available.

### 3.2 Validation gaps (what should be done before treating the NPU script as production-ready)

1. **Acquire a Ryzen AI hardware test fixture.** Candidates:
   - **ThinkPad T14s Gen 6 AMD** (Ryzen AI 7 PRO 360 / Strix Point) — accessible via Lenovo retail.
   - **ASUS ProArt P16** (Ryzen AI 9 HX 370) — Strix Point with NPU enabled.
   - **HP OmniBook Ultra Flip 14** (Ryzen AI 9 HX 375) — Strix Point.
   - **Mini-PC builds with Ryzen AI Max 300** — limited availability as of 2026.

2. **Run `-Action PrepareVerify` on the fixture** with each of the 4 download tiers:
   - Tier 1: pre-captured `entitlenow.com` URL.
   - Tier 2: `-AmdAccountUser` / `-AmdAccountPassword` with a real AMD account. Confirm or adjust form-parsing regex.
   - Tier 3: probe AMD EULA URL (expected to fall through; document if AMD ever simplifies this).
   - Tier 4: `-OfflineZip` with manually-downloaded ZIPs for RAI 1.5 / 1.6.1 / 1.7 / 1.7.1.

3. **Run `-Action Install` on the fixture** with the recommended workflow:
   - Capture `Get-CimInstance Win32_PnPSignedDriver` before / after.
   - Confirm `[B] Vendor` → `[C] Self-signed` transition for the NPU device.
   - Run `Task Manager → Performance → NPU0` and confirm the device appears.
   - Try `pnputil /enum-drivers` and confirm the patched INF appears under our self-signed cert.

4. **Document the failure modes**:
   - Does Server 2025 ever load the NPU kernel driver successfully? (Per AMD docs, the user-mode stack does not work, but the kernel driver itself is the focus of this script.)
   - Does Cleanup actually remove the driver from the driver store, or does manual `pnputil /delete-driver oemNN.inf /force` remain necessary?
   - What event log entries appear in `CodeIntegrity / Operational` if WDAC blocks anything unexpected?

### 3.3 Recommended invocation patterns and 4-tier evaluation

The 4-tier URL resolution in `Resolve-AmdNpuDriverUrl` (script line 772) controls how P03 obtains the NPU driver ZIP. The behaviour is **not symmetric across all parameter combinations**, so the table below documents the actual outcome of each invocation pattern. Use this when planning runs.

| # | Invocation | Outcome | Path through 4-tier resolver |
|---|---|---|---|
| 1 | `-Action PrepareVerify -CleanWorkRoot -OfflineZip <path>` | ✅ **Recommended for first dry run.** | T4 priority block (line 824) → ZIP copied to workspace → P03 succeeds |
| 2 | `-Action PrepareVerify -CleanWorkRoot -OfflineZip <path> -AssumeIfMissing` | ⚠️ **Pipeline-soundness check only — does NOT validate real NPU behaviour.** | Same as #1 plus default Strix Point profile when no NPU detected |
| 3 | `-Action PrepareVerify -CleanWorkRoot` (no `-OfflineZip`) | ⚠️ **Likely fails on a clean machine.** | T1 skip → T4 priority skip → T2 skip → T3 falls through (HTML form) → T4 auto-scan (script dir, ./cache, workspace, ~/Downloads) → if nothing found, throws |
| 4 | `-Action Install -OfflineZip <path>` | ✅ **Recommended for real-NPU install.** | T4 priority block → I00 prompts for "I AGREE" → I01-I04 |
| 5 | `-Action Install -AmdAccountUser ... -AmdAccountPassword ...` | ⚠️ **Best-effort. AMD form changes can break this without notice.** | T1 skip → T4 priority skip → T2 attempts authenticated download → falls back to T3/T4 on failure |
| 6 | `-Action Install -InstallerUrl <captured-url>` | ✅ Works if the URL is fresh (entitlenow.com URLs expire). | T1 direct download → P03 succeeds |
| 7 | `-Action Install -NpuOverride STX -NpuDriverPackage NPU_RAI1.6.1_314` (no source) | ❌ **Misleading; do not use.** | T1/T2/T3 skip → T4 auto-scan picks up *whatever* `NPU_RAI*_WHQL.zip` is in `~/Downloads` (may not match the override) |

**Why pattern #1 (`PrepareVerify` + `OfflineZip`) is the strongest recommendation**:

- **Deterministic**: the Tier 4 priority block at line 824 short-circuits the resolver immediately. No network calls to AMD, no form-parsing fragility, no race against EULA URL expiry.
- **System-untouched**: `PrepareVerify` runs P00–P09 + V01–V06 only. No certs imported, no WDAC policy deployed, no drivers installed.
- **Reproducible across hosts**: copy the same ZIP to a new machine, get the same P05/P06/V05/V06 output. Critical for CI regression testing.
- **Gives you V05/V06 output**: dry-run install plan and hardware impact analysis are produced even when the host has no NPU device (in which case `-AssumeIfMissing` is needed to bypass detection failure).

**Common pitfall — pattern #7**: switches like `-NpuOverride`, `-NpuDriverPackage`, and `-RyzenAiSoftwareVersion` *modify resolver behaviour but do not provide a download source*. If you specify them without `-OfflineZip` / `-InstallerUrl` / `-AmdAccountUser`, the resolver falls through to Tier 4 auto-scan. Auto-scan picks up whichever `NPU_RAI*_WHQL.zip` it finds first — and that ZIP **may not match the codename or version you tried to override**. The version check happens inside the ZIP's INFs (P05), not against the filename. Always pin the source explicitly.

### 3.4 Pre-flight checklist before running the NPU script anywhere

Even before any of the above gaps are closed, follow this checklist before running the NPU script on **any** host:

- [ ] You have read [§ Risk classification](./README.md#risk-classification-of-the-three-scripts) of the README.
- [ ] You have a Ryzen AI 300 / Ryzen AI Max 300 / Ryzen 7040 / 8040 series CPU (or you accept that detection will fall through to `-AssumeIfMissing` and the run is a pipeline-soundness check only).
- [ ] You have downloaded the appropriate `NPU_RAI*_WHQL.zip` from <https://ryzenai.docs.amd.com/en/latest/inst.html#install-npu-drivers> and placed it next to the script (Tier 4 — recommended).
- [ ] You have read AMD's Ryzen AI EULA at <https://account.amd.com/en/forms/downloads/ryzenai-eula-public-xef.html> and accepted it.
- [ ] You understand that Ryzen AI Software user-mode stack is officially Windows-11-only and **will not give you AI inference on Server 2025**.
- [ ] If running `-Action Install`: you can roll back via `-Action Cleanup` (and you accept that driver-store removal may need manual intervention).
- [ ] If running on a host with BitLocker: you have your recovery key recorded.
- [ ] You will report results to GitHub Issues regardless of success or failure (especially failure — the maintainers need this data to close the validation gap).

### 3.5 Expected NPU script outputs

These are the outputs you should see when the script runs successfully. Deviation indicates a problem.

#### P00 NPU OS-support warning

```
-------------------------------------------------------------------------
 Ryzen AI Software OS support note
-------------------------------------------------------------------------
[!] AMD officially supports Ryzen AI Software ONLY on Windows 11 (build >= 22621.3527).
[!] Windows Server 2025 is NOT in AMD's supported OS matrix.
[!] This script patches the kernel-mode NPU driver to install on Server, but the
[!] user-mode Ryzen AI Software stack (conda env, OGA, Vitis AI EP) will likely
[!] not function on Server 2025 without unofficial workarounds.
```

#### P03 NPU detection (real Strix Point host)

```
[>] Enumerating PCI devices via pnputil /enum-devices /bus PCI /deviceids
[+] CPU              : AMD Ryzen AI 9 HX 370 w/ Radeon 890M
[+] NPU codename     : Strix Point / Strix Halo
[+] NPU short name   : STX
[+] Hardware ID      : PCI\VEN_1022&DEV_17F0&REV_00
[+] Detection source : pnputil
[+] Detected on host : True
[+] Preferred RAI ver: 1.7.1
[+] Recommended drv  : 32.0.203.380
```

#### P03 NPU detection (non-NPU host, with `-AssumeIfMissing`)

```
[>] Enumerating PCI devices via pnputil /enum-devices /bus PCI /deviceids
[!] No AMD NPU detected via pnputil. Using default profile (Strix Point + RAI 1.7.1).
[+] CPU              : (host CPU - no NPU)
[+] NPU codename     : Strix Point (default - no NPU detected)
[+] NPU short name   : STX
[+] Detection source : default-strix-rai1.7.1
[+] Detected on host : False
```

followed by:

```
------------------------------------------------------------------
[!] NPU was NOT detected on the host (proceeding with default profile).
[!] Driver Install (I03) will likely produce 0 device bindings here.
[!] This run is useful for pipeline regression testing only.
------------------------------------------------------------------
```

#### I00 EULA acknowledgement (Install only)

```
+----------------------------------------------------------------+
| AMD RYZEN AI EULA ACCEPTANCE REQUIRED BEFORE INSTALL           |
+----------------------------------------------------------------+
| By proceeding, you confirm:                                    |
| 1. You have accepted the Ryzen AI EULA at:                     |
|    https://account.amd.com/en/forms/downloads/                 |
|    ryzenai-eula-public-xef.html                                |
| 2. You acknowledge Windows Server 2025 is NOT officially       |
|    supported by AMD for Ryzen AI Software (Windows 11 only).   |
| 3. You understand the kernel-mode driver alone does not        |
|    enable AI inference; Ryzen AI SW must be installed manually.|
| 4. You have BitLocker recovery keys recorded if applicable.    |
+----------------------------------------------------------------+

Type "I AGREE" exactly to proceed with install (anything else aborts):
```

#### After Install: Ryzen AI Software guidance banner

```
+================================================================+
| RYZEN AI SOFTWARE (USER-MODE STACK) - INSTALL THIS SEPARATELY |
+================================================================+

This script installed the kernel-mode NPU driver only.
To actually use the NPU for AI inference, install Ryzen AI Software:

  Detected NPU codename : STX
  Recommended RAI ver   : 1.7.1

  PREREQUISITES (per AMD documentation):
    1. Windows 11 build >= 22621.3527 (NOT supported on Server 2025!)
    2. Visual Studio 2022 (with Desktop Development with C++)
    3. cmake >= 3.26
    4. Miniforge (Python distribution); add condabin/Scripts to PATH

  INSTALLATION STEPS:
    1. Download Ryzen AI installer:
       https://account.amd.com/en/forms/downloads/xef.html
       Filename: ryzen-ai-lt-1.7.1.exe
    2. Launch the EXE installer (run as Administrator)...
    3. Verify the install (Miniforge Prompt):
         conda activate ryzen-ai-1.7.1
         cd %RYZEN_AI_INSTALLATION_PATH%\quicktest
         python quicktest.py
```

### 3.6 Tier 2 (AMD account auth flow) verification result — 2026-05-10

The `Invoke-AmdAccountAuthentication` function in `Deploy-AMDNpuDriverOnWindowsServer.ps1` was reviewed against the actual AMD account portal on **2026-05-10** to determine whether the implemented HTTP form POST flow can succeed against the current `account.amd.com` back-end. The verification used only public sources (no real AMD account credentials were used).

#### 3.6.1 Method

| Step | What was checked | How |
|---|---|---|
| 1 | `account.amd.com` rendering model | Web fetch of related AMD portals (`docs.amd.com/auth/login`, `pensandosupport.amd.com`, `fsdz.amd.com`) |
| 2 | EULA URL pattern in current AMD docs | GitHub `amd/ryzen-ai-documentation/blob/main/docs/inst.rst` (latest commit) |
| 3 | Driver-version naming convention | Cross-check between RAI 1.5 / 1.6.1 / 1.7 / 1.7.1 documentation pages on `ryzenai.docs.amd.com` |
| 4 | End-user behavior of the EULA flow | GitHub `amd/RyzenAI-SW#249`, `#328`, and cnx-software.com end-user blog post (Feb 2024) |
| 5 | Existence of public PowerShell/Python automation | Web search for `account.amd.com` automation, AMD account download scripting |

#### 3.6.2 Findings

| # | Finding | Severity | Evidence |
|---|---|---|---|
| F1 | **`account.amd.com` is a JavaScript-driven SPA.** Related AMD portals return `"JavaScript is required"` or `"Loading application"` HTML stubs on direct fetch. | High | Direct probe of `docs.amd.com/auth/login` and `fsdz.amd.com/adfs/ls/...` |
| F2 | **Login forms are not present in the initial HTML payload.** CSRF tokens, form actions, and fields are likely injected by JavaScript at runtime. | High | F1 implies the login form is rendered client-side |
| F3 | **EULA acceptance is interactive.** End users report that they "could not avoid signing the Beta Software EULA" — implying a JS-driven multi-step modal, not a single hidden form POST. | Medium | cnx-software.com testimonial (2024); GitHub #249 (2025) |
| F4 | **Two distinct EULA URL patterns exist** in AMD's documentation. Original code assumed only one. | Medium | `ryzenai-eula-public-xef.html` for NPU drivers vs `xef.html` for RAI Software EXE / NuGet |
| F5 | **The default driver/RAI mapping `1.7.1 → 32.0.203.380` was not real.** AMD's RAI 1.7.1 documentation reuses the 1.6.1 driver (`32.0.203.314`) and there is no `NPU_RAI1.7.1_380_WHQL.zip` publicly listed. The script's own comment admitted this was a "placeholder build until AMD publishes". | Medium | Cross-check of `ryzenai.docs.amd.com/en/latest/inst.html` and `github.com/amd/ryzen-ai-documentation/blob/main/docs/inst.rst` |
| F6 | **No public automation script for AMD account login was found.** Web search returned zero PowerShell/Python implementations that successfully drive the form. | Low | Negative search result; informational |

#### 3.6.3 Conclusion

The `Invoke-AmdAccountAuthentication` function as implemented (HTTP form POST against `https://account.amd.com/en/forms/auth/login.html`) **is highly unlikely to succeed against the current AMD portal**. The portal architecture does not match the assumptions encoded in the function (server-rendered HTML form with hidden CSRF token, simple POST credentials → redirect to authenticated EULA → simple POST EULA accept → redirect to entitlenow.com).

This conclusion was reached without making authenticated requests against AMD's servers — it follows from publicly visible architectural evidence (F1–F3), driver-version inconsistency (F5), and absence of any working public implementation (F6).

#### 3.6.4 Remediation applied to the script

| Change | Description | Location |
|---|---|---|
| C1 | **Tier 2 disabled by default.** The function now returns `$null` immediately unless `-ForceAmdAccountAuth` is passed. | `Invoke-AmdAccountAuthentication` (~line 1170) |
| C2 | **`VERIFIED 2026-05-10` banner** added with explicit "highly unlikely to succeed" warning. | `Invoke-AmdAccountAuthentication` head |
| C3 | **`-ForceAmdAccountAuth` switch** added to `param()` block. Operators who believe AMD has changed their portal can opt in to test. | Top-level `param()` |
| C4 | **Versioning fully separated.** Parameter `-PreferredRyzenAiVersion` (mixed driver + software in one knob) was replaced by two independent parameters: `-NpuDriverPackage` (default `latest` = `NPU_RAI1.6.1_314`) and `-RyzenAiSoftwareVersion` (default `latest` = `1.7.1`). Filename generation now produces `NPU_RAI1.6.1_314_WHQL.zip` matching what AMD actually publishes. Compatibility between A and B is evaluated as a separate axis. | `[string]$NpuDriverPackage = 'latest'`; `[string]$RyzenAiSoftwareVersion = 'latest'`; new functions `Get-NpuDriverPackageInfo`, `Get-LatestRyzenAiSoftwareInfo`, `Test-NpuDriverRaiCompatibility` |
| C5 | **`Get-RecommendedNpuDriverBuild` mapping corrected.** RAI 1.7 / 1.7.1 entries now both return `32.0.203.314` (the real published driver) instead of fictional `329` / `380` builds. Cross-references to AMD docs are added in the function header. | `Get-RecommendedNpuDriverBuild` |
| C6 | **All header `.EXAMPLE` filenames** updated from `NPU_RAI1.7.1_380_WHQL.zip` (fictional) to `NPU_RAI1.6.1_314_WHQL.zip` (verified). | Script header lines ~93, 99, 110, 124, 132 |
| C7 | **Default-Strix profile label** changed from `default-strix-rai1.7.1` to `default-strix-rai1.6.1`. P03 banner reflects the verified driver build. | `Get-AmdNpuPlatform` `$AssumeIfMissing` branch |

#### 3.6.5 What `-ForceAmdAccountAuth` does

When set, the existing form-based POST sequence is attempted unchanged:

```powershell
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action Install `
    -ForceAmdAccountAuth `
    -AmdAccountUser 'you@example.com' `
    -AmdAccountPassword (Read-Host 'AMD password' -AsSecureString)
```

Expected result on the current AMD portal: **failure** at one of the following points (most likely Step 2 or Step 3):

- Step 1 GET EULA page → fetch likely succeeds but no CSRF token in HTML
- Step 2 POST credentials → likely fails (no form actually exists at the documented URL)
- Step 3 GET authenticated EULA → likely succeeds but no acceptance form action found
- Step 4 POST EULA acceptance → likely fails (no form actually exists)

If by some chance AMD has reverted to a server-rendered form, the existing fallback code path handles success; no further changes needed in that case.

#### 3.6.6 Future re-verification

Re-run this verification when:

- AMD announces a new Ryzen AI release (≥ 1.7.2 or 1.8) — driver mapping table may need updates
- A user reports that `-ForceAmdAccountAuth` now succeeds — Tier 2 can be re-enabled by default
- A new EULA URL pattern appears in AMD documentation (a third path beyond the two known)

The verification re-run procedure is the same as in 4.6.1: fetch public AMD pages, cross-check EULA URL patterns in `amd/ryzen-ai-documentation` GitHub repository, and check for end-user reports of successful automation.

### 3.7 Versioning-axis separation verification — 2026-05-10

The NPU script's version-handling logic was redesigned on **2026-05-10** to fully separate the **NPU kernel-mode driver** versioning system from the **Ryzen AI Software (user-mode stack)** versioning system, per AMD's authoritative documentation at <https://ryzenai.docs.amd.com/en/latest/inst.html> (Last updated 2026-04-19).

#### 3.7.1 The two independent versioning systems

AMD's installation guide treats NPU drivers and Ryzen AI Software as fully decoupled artefacts:

| Aspect | NPU kernel-mode driver (axis A) | Ryzen AI Software (axis B) |
|---|---|---|
| What it is | Windows kernel-mode driver bundled in `npu_sw_installer.exe`, providing PCI device binding and firmware loading | User-mode runtime: Python conda environment, ONNX Runtime VitisAI EP, OnnxRuntime GenAI (OGA), AMD Quark quantizer, xrt-smi tool |
| Distribution | EULA-gated ZIP at `account.amd.com/en/forms/downloads/ryzenai-eula-public-xef.html?filename=NPU_RAI*_WHQL.zip` | EULA-gated EXE at `account.amd.com/en/forms/downloads/xef.html?filename=ryzen-ai-lt-*.exe` (note the different EULA URL pattern) |
| Currently published versions (per AMD docs 2026-04-19) | `NPU_RAI1.5_280_WHQL.zip` (driver 32.0.203.280) and `NPU_RAI1.6.1_314_WHQL.zip` (driver 32.0.203.314) | `1.7.1` (latest), with installer `ryzen-ai-lt-1.7.1.exe` and NuGet `1.7.1_nuget_signed.zip` |
| Update cadence | Slow — only when a new firmware/driver pair is released. Backward-compatible with prior RAI Software versions in the supported range. | Frequent — ships new model support, performance improvements, and bug fixes. **AMD recommends always using the latest** for end-user workloads. |
| Operator default in this script | `latest` → `NPU_RAI1.6.1_314` (the newer of the two documented packages) | `latest` → `1.7.1` (auto-resolves to whatever this script currently knows as the latest) |
| Naming inside ZIP filenames | The `RAI1.5` / `RAI1.6.1` token in `NPU_RAI*_WHQL.zip` is a **historical naming artefact** — both ZIPs work with current Ryzen AI Software 1.7.1 | Versioning is its own scheme: `1.5` → `1.6.1` → `1.7` → `1.7.1` |

The crucial point: the `1.6.1` in `NPU_RAI1.6.1_314_WHQL.zip` is **NOT** the Ryzen AI Software version. It is a release-channel label inherited from the original RAI 1.6.1 release window. The same driver ZIP is the recommended driver for RAI Software 1.7.1.

#### 3.7.2 Compatibility evaluation as a separate axis

AMD documents driver-software compatibility in the Ryzen AI Software installation guide. As of RAI 1.7.1 (the current latest):

> "Download and Install the NPU driver version: 32.0.203.280 or newer using the following links" — both `NPU_RAI1.5_280` and `NPU_RAI1.6.1_314` are listed as valid options.

This produces the following compatibility matrix (axis C — derived from axes A + B):

|  | RAI 1.5 | RAI 1.6.1 | RAI 1.7 | RAI 1.7.1 |
|---|---|---|---|---|
| Driver 32.0.203.280 (`NPU_RAI1.5_280`) | ✅ | ✅ | ✅ | ✅ |
| Driver 32.0.203.314 (`NPU_RAI1.6.1_314`) | ✅ | ✅ | ✅ | ✅ |

The minimum driver requirement (`32.0.203.280`) is consistent across all supported RAI Software versions per AMD's documentation. The script's `Test-NpuDriverRaiCompatibility` function encodes this matrix and emits `OK` or `MISMATCH` at P03.

#### 3.7.3 Code-level changes

| Layer | Before | After |
|---|---|---|
| **Operator parameters** | Single `-PreferredRyzenAiVersion <ver>` (mixed driver + software in one knob) | Two independent parameters: `-NpuDriverPackage <NPU_RAI1.5_280 \| NPU_RAI1.6.1_314 \| latest>` and `-RyzenAiSoftwareVersion <1.5 \| 1.6.1 \| 1.7 \| 1.7.1 \| latest>`. Both default to `latest`. |
| **Catalog functions** | `Get-RecommendedNpuDriverBuild $RaiVersion → $build` (incorrect coupling) and `Get-NpuZipFilename $RaiVersion $build → $filename` (string concatenation that produced fictional filenames) | Three independent functions: `Get-NpuDriverPackageInfo` (axis A: returns full package metadata for the documented ZIPs), `Get-LatestRyzenAiSoftwareInfo` (axis B: returns RAI Software metadata with `IsLatest` flag), `Test-NpuDriverRaiCompatibility` (axis C: evaluates the matrix above with `[version]` comparison) |
| **Detected-platform fields** | `RecommendedRaiVer`, `RecommendedDriver` (2 fields, ambiguously coupled) | `NpuDriverPackage`, `NpuDriverBuild`, `NpuDriverZipName` (axis A), `RyzenAiSoftwareVersion`, `RyzenAiSoftwareInstaller` (axis B), `DriverSoftwareCompatible`, `DriverSoftwareCompatNote` (axis C) — 7 fields with explicit axis attribution |
| **P03 banner output** | Single block listing "Preferred RAI ver" and "Recommended drv" | Three labelled blocks: "NPU kernel-mode driver (independent versioning axis)", "Ryzen AI Software (independent versioning axis - always latest unless pinned)", "Driver <-> RAI Software compatibility (separate evaluation axis)" with `OK`/`MISMATCH` status |
| **Post-install guidance (I04)** | Hardcoded fallback to `1.7.1` if RAI version was missing | Reads `RyzenAiSoftwareInstaller` field directly; falls back to `ryzen-ai-lt-1.7.1.exe` only if the field is empty. Explicitly states "NPU driver and Ryzen AI Software are versioned INDEPENDENTLY. Always use the LATEST Ryzen AI Software for end-user workloads." |

#### 3.7.4 Future maintenance

When AMD publishes a new Ryzen AI release, update the script in two places:

1. **If a new NPU driver ZIP is published** (e.g. `NPU_RAI1.8_400_WHQL.zip`): add an entry to the `Get-NpuDriverPackageInfo` catalog and the `-NpuDriverPackage` `ValidateSet`. If the new driver introduces a different minimum-required driver build for current RAI Software, update `Test-NpuDriverRaiCompatibility`.
2. **If a new Ryzen AI Software version is released** (e.g. `1.8.0`): add an entry to the `Get-LatestRyzenAiSoftwareInfo` catalog, update `$latestVersion` to the new version, and add the new value to the `-RyzenAiSoftwareVersion` `ValidateSet`. Cross-check the AMD release notes for any new minimum driver requirement and update `$minimumPerRai` in `Test-NpuDriverRaiCompatibility` accordingly.

The two updates are independent — adding driver support does not require touching software metadata, and vice versa. This is the central design property the redesign achieves.

---

## 4. Summary of validation results

### 4.1 Per-environment matrix

| Item | M75q Tiny Gen 2 | X13 Gen 1 AMD | **Real NPU machine** |
|---|---|---|---|
| Instance / model | ThinkCentre physical | ThinkPad physical | **TBD** |
| OS | WS2025 | Win11 LTSC 2024 | TBD |
| ProductType | 3 | 1 (PREVIEW MODE) | TBD |
| CPU | Ryzen 7 PRO 5750GE (Cezanne) | Ryzen 5 PRO 4650U (Renoir) | Ryzen AI 300 / 7040 / 8040 |
| Has NPU | no | no | **yes** |
| Chipset INFs processed | 32/32 + 3 V06 upgrades | 32/32 + 1 V06 upgrade | n/a (out of scope for NPU script) |
| Graphics INFs processed | 19/19 + 3 V06 upgrades | 19/19 + 3 V06 upgrades | n/a (out of scope for NPU script) |
| NPU script PrepareVerify | n/a (no NPU device) | n/a (no NPU device) | **PENDING** |
| NPU script Install | n/a | n/a (auto-block) | **PENDING** |
| Validation purpose | Pre-production rehearsal (chipset+graphics) | WS2025 pre-migration check | **NPU end-to-end validation** |

### 4.2 Recommended validation patterns

| Scenario | Recommended environment |
|---|---|
| "Real driver install validation" (chipset/graphics) | M75q Gen 2 physical (production target) |
| "Win11 → WS2025 pre-migration evaluation" (chipset/graphics) | X13 Gen 1 physical |
| **"NPU end-to-end validation"** | **Ryzen AI 300 / 7040 / 8040 series host (NOT YET IN MAINTAINER'S LAB — PRs welcome)** |

> **Why no non-AMD-consumer-hardware testing is documented**: This pipeline is an experimental tool for AMD's consumer Ryzen / Radeon / NPU silicon. Validation outcomes are by definition dependent on physical access to those devices. Running the pipeline on server-class EPYC, ARM, Intel, or virtual hosts cannot exercise the device-bind logic (V06), the actual driver upgrade decisions, or the post-install verification path (I04). The maintainers have concluded that "pipeline-soundness only" testing on non-target hardware adds little value relative to the cost of maintaining such infrastructure, and have therefore restricted validation to physical AMD consumer hardware.

---

## 5. Discovered bugs and fix history

The following bugs were found and fixed during the validation runs above:

| Discovery environment | Version | Fix version | Summary |
|---|---|---|---|
| ThinkPad X13 Gen 1 (Win11 24H2) | chipset r45 | r46 | Timezone bug in `Compare-InfDriverVer` (UTC midnight `DriverDate` was converted to local 09:00 by CIM cmdlets, causing the same-version case to be misreported as "current newer than patched"). Fixed by comparing `.Date` (year/month/day truncation) only. |
| ThinkPad X13 Gen 1 (Win11 24H2) | r45 / r14 | r46 / r15 | The P05 / P00 compatibility check displayed `Host OS: Windows Server 2025` even on a Workstation host, which was confusing. Now shows the actual `Caption` plus the mapped profile side by side. |
| ThinkPad X13 Gen 1 (Win11 24H2) | graphics r14 | r16 / r47 | V05 "would upgrade 1067/1067 matched device(s)" inflation. `$matchedDevices` was being appended per INF HWID variant rather than per physical device, inflating counts. Fixed by deduplication on the physical DeviceID. |
| ThinkPad X13 Gen 1 (Win11 24H2) | graphics r14 | r16 / r47 | Same-version, newer-date upgrade case formerly produced the nonsensical `patched newer (X) than current (X)` message. Now displays `patched same version (X) but newer date; PnP ranking prefers newer-dated driver` for clarity. |
| Pipeline review (no field reports) | NPU r1 | (placeholder) | Currently no field-discovered bugs — but **no field reports exist either**, because the NPU script has not been run on physical NPU hardware yet. |
| Lab (Win Server 2025, ja-JP) | chipset r49 (during validation) | r49 published, r50 polish | Three corrections during the initial Secure Boot baseline rollout: (a) `schtasks.exe /FO CSV` headers are ja-JP-localized — replaced with `Get-ScheduledTask`. (b) MS sample script's `-OutputPath` validator regex rejects every absolute Windows path containing `:` — added stdout-JSON extraction fallback. (c) `Show-...` and V06 caller printed a duplicate banner — removed inner banner. |
| Lab (Win Server 2025, ja-JP) | chipset r49 / graphics r18 / NPU r4 | r50 / r19 / r5 | Polish patch: P00 wrote diagnostic files to `%TEMP%` when the workspace had not been created yet, which on `-CleanWorkRoot` runs left stale paths visible in V06. Replaced with consistent workspace-co-located diagnostics via the new `Get-OrEnsureSecureBootBaseline` helper. |
| Lab (Win Server 2025, ja-JP) | NPU r4 | r5 | `Find-Inf2CatPath` filtered to `\x64\` / `\amd64\` directories, but inf2cat.exe is x86-only; P02 always failed with "inf2cat not found" then attempted winget WDK install (also fails — WDK is not on winget). Replaced helper body with x86-aware tree walk. |
| Lab (Win Server 2025, ja-JP) | NPU r4 | r5 | `[ValidateSet]` on `-NpuOverride` rejected the default empty string, emitting a noisy warning on every invocation. Added `''` to the set. |
| Clean Windows Server 2025 install (interactive console) | chipset r54 / graphics r19→r22 | chipset r55 / graphics r23 | Workspace lock leaked across runs in the same PowerShell host. The lock file `<WorkRoot>\.markers\RUN.lock` was written with the current `$PID` but the only cleanup was a `Register-EngineEvent PowerShell.Exiting` action that never fires inside an interactive console. The next run in the same console then saw the leftover lock with PID == its own host PID and was rejected as "another instance is already running". Fixed by (a) self-PID detection in `Test-WorkspaceLockHeld` (treat lock with `Pid==$PID` as stale and overtake silently) and (b) wrapping the main phase loop in `try { ... } finally { Clear-WorkspaceLock ... }` so the lock is released on every exit path. NPU script is unaffected (no workspace lock implemented; see SPEC §D.13). |
| Clean Windows Server 2025 install | chipset r54 | r55 | r54's new `Expand-AmdInstaller_ViaInstallShield` dropped `installshield-admin.log` and 12 per-sub-MSI `msiexec-admin-*.log` files at the workspace root, instead of `<WorkRoot>\logs\` alongside the existing `inf2cat_*.log` / `signtool_*.log` / `verify_*.log` / `pnputil_*.log` files. Root cause: `$parentDir = Split-Path $DestinationPath -Parent` resolved to the workspace root because the caller passed `$Ctx.Paths.Extract` (= `<WorkRoot>\extracted`). Fixed by adding an optional `-LogDir` parameter to both `Expand-AmdInstaller` and `Expand-AmdInstaller_ViaInstallShield`; `Invoke-PrepPhase04_ExtractInstaller` now passes `$Ctx.Paths.Logs`. Chipset only — graphics uses a single `msiexec /i` invocation and is not affected. See SPEC §D.14. |

For full validation logs and the corresponding fix commits, see <https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/commits/main>.

---

## 6. UEFI Secure Boot baseline validation checklist

This is the per-script validation checklist for the cross-script UEFI Secure Boot baseline feature (Chipset r50 / Graphics r19 / NPU r5). All three sister scripts share the same six core functions, so the expected output is uniform across them. Validate on at least one Windows Server 2025 host with KB5089549-equivalent updates installed.

### Per-phase expected output

| Phase | Expected | Actual on test host |
|---|---|---|
| P00 | One-line compact: `Secure Boot baseline: enabled=true UEFI-CA-2023=NotStarted health=Warning [MS-sample=ok]` (values vary by host state) | ✅ |
| P05 | New file `<WorkRoot>\inf_inventory_report.txt` exists and ends with a "UEFI Secure Boot Baseline" appendix block (chipset / graphics: as section after the INF inventory; NPU: at end after the inline inventory) | ✅ |
| V05 | New section: `[Dry-Run UEFI Baseline]` heading followed by one-line compact readout. If `Health` is `Warning` or `Critical`, a yellow advisory line follows | ✅ |
| V06 | New numbered section: "4. UEFI Secure Boot Baseline" (chipset / graphics) or "Section 5: UEFI Secure Boot Baseline" (NPU). Multi-line breakdown showing embedded inventory + MS sample script results (BucketId / Confidence / EventNNNN counts) | ✅ |
| I02 | New pre-check block: `--- UEFI Secure Boot baseline pre-check ---` followed by compact readout and advisory. Never blocks. | (Install phase — run separately) |

### Workspace artefact checklist

| Artefact | Expected location | Purpose |
|---|---|---|
| Raw stdout dump | `<WorkRoot>\secureboot_ms_sample\detect_stdout.log` | Forensics when MS sample script behaves unexpectedly |
| Extracted JSON | `<WorkRoot>\secureboot_ms_sample\detect_stdout_extracted.json` | Parsed `Hostname`, `UEFICA2023Status`, `BucketId`, `Confidence`, `Event1801..1803` |
| Inventory report appendix | `<WorkRoot>\inf_inventory_report.txt` | Persisted snapshot for change-management documentation |

Notes:
- The MS sample script is delivered by KB5089549 (Win 11), KB5087544 / KB5088863 (Win 10), or the WS2025 equivalent (starting 2026-05-12). On unpatched hosts, `[MS-sample=absent]` is expected instead of `[MS-sample=ok]`.
- The diagnostic files survive across runs unless `-CleanWorkRoot` is passed.

### Health-class assertions

| Host state | Expected `health=` value |
|---|---|
| Secure Boot ON, `UEFICA2023Status = Updated` (KB rollout complete) | `Healthy` |
| Secure Boot ON, `UEFICA2023Status = NotStarted / Started / Pending` | `Warning` |
| Secure Boot OFF | `Critical` |
| `UEFICA2023Error` non-zero | `Critical` |
| Secure Boot status unreadable (some firmware quirks) | `Unknown` |

### Cross-script consistency check

Run all three scripts in PrepareVerify mode on the same host with `-CleanWorkRoot`. The captured `BucketId`, `Confidence`, and event counts in V06 should be **identical** across all three scripts (the MS sample script returns deterministic results for the same host state).

---


## 7. r54+ — AMD Chipset Software 8.x extraction diagnostic format

Starting with the Chipset script's r54 revision, the P04 ExtractInstaller phase includes a new "Strategy 2/3" path designed for AMD Chipset Software 8.x (8.02.18.557 and later). This section documents the expected diagnostic output and the validation procedure for the new extraction path.

### 7.1 Why a new strategy was needed

AMD Chipset Software 8.x ships as a two-layer wrapper:

1. **Outer layer**: NSIS self-extracting EXE (7-Zip can extract this).
2. **Inner layer**: InstallShield SFX in `ISSetupStream` format (7-Zip CANNOT extract; only InstallShield's own `/a` admin install can).

Pre-r54 revisions detected the 7-Zip failure on the inner layer and fell back to launching the installer and harvesting from `C:\AMD\`, which is fragile because AMD aggressively cleans up that directory. r54 inserts a dedicated InstallShield-aware strategy between the old 7-Zip strategy and the launch-watch fallback.

See `SPEC.md` §B.1 "AMD 8.x installer architecture (r54+)" for the full architecture.

### 7.2 Expected diagnostic output when Strategy 2 succeeds

When the installer is AMD 8.x, P04 console output should look approximately like the following (truncated for readability):

```
[*] Phase 04 :  P04 ExtractInstaller   (Build group)
[*] Extracting installer (multiple strategies will be attempted)
    Strategy 1/3: 7-Zip auto-detect
[!] 7-Zip auto-detect produced no usable payload (exit 0) - trying next strategy
    Strategy 2/3: InstallShield /a admin install (AMD 8.x+ chain)
      Step 1/3: 7-Zip outer NSIS shell...
      Inner SFX  : C:\AMD-Chipset-WS\is-stage-nsis\AMD_Chipset_Drivers.exe (75.3 MB)
      Step 2/3: InstallShield /a admin install...
      Unpacked   : 36 MSI files (InstallShield exit 0)
      Step 3/3: msiexec /a on 36 sub-MSI(s)...
      msiexec /a : 35 succeeded, 1 failed
      INF total  : 96
      [PREFERRED] W11x64    :  32 INF(s)
      [ skip    ] WTx64     :  32 INF(s)
      [ skip    ] WTx86     :  32 INF(s)
[+]    Extracted via InstallShield admin install chain
[+] Extracted to: C:\AMD-Chipset-WS\extract
```

### 7.3 Validation checklist

When the new path runs successfully, all of these should hold:

| Check | Expected value | How to verify |
| --- | --- | --- |
| InstallShield exit code | `0` (best) or `1` (acceptable if MSI count is correct) | Console line `Unpacked   : NN MSI files (InstallShield exit X)` |
| MSI count | `>= 36` (1 parent + 35 sub-MSIs for 8.02.18.557; future versions may differ) | Same console line |
| msiexec /a success rate | `>= 30` of `36` | Console line `msiexec /a : NN succeeded, M failed` |
| INF total | `>= 80` (varies with version; usually 96 in 8.02.18.557) | Console line `INF total  : NN` |
| PREFERRED variant has non-zero INFs | `[PREFERRED] <variant> : >= 25 INF(s)` | Console line; **this is the critical signal** |
| PREFERRED variant matches host OS | `W11x64` on WS2022/WS2025; `WTx64` on WS2016/WS2019 | Cross-check `$Ctx.Os` from console banner |

### 7.4 Troubleshooting

If the PREFERRED variant shows `0 INF(s)` despite the extraction succeeding, the most likely causes are:

1. **InstallShield /a failed silently**: Check `C:\AMD-Chipset-WS\installshield-admin.log` for MSI errors during the admin install. Look for `Action ended ...` lines with non-zero return values.

2. **msiexec /a failed for the OS-variant sub-MSIs**: Check `C:\AMD-Chipset-WS\msiexec-admin-*.log` for the specific failing sub-MSIs. Each sub-MSI has its own log named after the MSI filename.

3. **AMD changed the directory layout in a future version**: If you are running against a Chipset Software version newer than 8.02.18.557 and the `Binaries\<DriverName>\<OS>\` structure changed, the `Get-AmdSourceVariant` classifier (script line ~5003) may need updating. File a GitHub issue with the directory tree under `C:\AMD-Chipset-WS\extract\`.

### 7.5 Fallback behaviour

If Strategy 2 fails for any reason (caught by the `try { ... } catch` block in `Expand-AmdInstaller`), the script falls through to Strategy 3/3 (launch + watch), preserving the pre-r54 behaviour. The console output in that case will be:

```
[!] InstallShield /a strategy failed: <error message>
    Strategy 3/3: launch installer and harvest from C:\AMD\
```

This is the same fallback path used by pre-r54 revisions and should be considered a regression fallback only.
