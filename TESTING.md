# TESTING.md — Physical Hardware Validation Results

This document consolidates the validation results for `Deploy-Drivers-For-WindowsServer`. Because this repository ships **experimental scripts that target AMD's consumer-class Ryzen chipset / Radeon iGPU / Ryzen AI NPU**, all meaningful validation depends on access to physical AMD consumer hardware. Testing on non-AMD-consumer hardware (server-class EPYC, ARM, Intel, virtual machines without the target devices, etc.) cannot exercise the device-bind, driver-upgrade, or post-install verification paths that this pipeline exists to validate. This document therefore covers only physical-hardware validation:

1. **Validation Result 1: ThinkCentre M75q Tiny Gen 2** (Windows Server 2025 physical / Cezanne Zen 3 — chipset & graphics validated)
2. **Validation Result 2: ThinkPad X13 Gen 1 AMD (2020)** (Windows 11 Enterprise LTSC 2024 / Renoir Zen 2 — chipset & graphics validated)
3. **Validation Result 3 (NPU script)** — **🆘 NOT YET VALIDATED on physical NPU hardware. See [§3](#3-validation-result-3-npu-script--currently-unverified) for the current limited validation status.**
4. **Validation Result 4 (BthPan script)** — ⏳ **PLANNED.** ThinkPad + Intel AX210 + Windows Server 2025 build 26100.32860 is the first physical-validation target. See [§4](#4-validation-result-4-bthpan-script--planned) for the planned test sequence.

> **Documentation language policy**: This document is maintained in
> English only. See `README.md` and `README.ja.md` for the bilingual
> entry-point documentation; for the repository-wide language policy
> see `SPEC.md` §A.12.

---

## 0. Validation status summary

> Read this before sections 1-3. The four scripts have **very different validation maturity levels**.

| Script | Physical-hardware validation | Real driver install on target HW | Recommended use |
|---|---|---|---|
| **Chipset (r59)** | ✓ M75q Tiny Gen 2, X13 Gen 1 AMD (validated on r55; r56 added a breaking install-decision change; r57 fixed CiTool ENTER-prompt hang + pnputil exit=259; r58 added -LogFile and workspace relocation; r59 adds Debug Trace Facility + call-site instrumentation — see note below) | ✓ install completed successfully on M75q (WS2025) | Lab + cautious production |
| **Graphics (r27)** | ✓ M75q Tiny Gen 2, X13 Gen 1 AMD (validated on r23; r24 added a breaking install-decision change; r25 fixed CiTool ENTER-prompt hang + pnputil exit=259; r26 added -LogFile and workspace relocation; r27 adds Debug Trace Facility + call-site instrumentation — see note below) | ✓ install completed successfully on M75q (WS2025) | Lab + cautious production |
| **NPU (r9)** | ❌ **none** (no physical NPU machine in maintainer's lab) | ❌ **never executed** | **Experimental / research-grade only. Do not deploy in production.** |
| **BthPan (r9)** | ⏳ **planned** — ThinkPad + Intel AX210 + Windows Server 2025 build 26100.32860 is the first target (see §4 below) | ❌ **not yet executed** | New script; physical validation pending. Logic shares the proven Phase / Secure Boot / WDAC framework from the Chipset script (Edit-InfForServer, Get-OsContext, Resolve-PhaseSelection, etc. are verbatim-inherited from Chipset r57). |

> **Note on the category-priority override** (see SPEC §D.15): The
> category-priority override changes the install-decision semantics
> in a breaking way for chipset and graphics: self-signed `[C]` drivers
> now always supersede Microsoft generic `[A]` and vendor `[B]` drivers
> regardless of version. Earlier physical-hardware validation results
> below remain *structurally* valid (extraction, patching, signing,
> WDAC deployment all behave the same), but the **V05 / V06 / I03
> driver-install decisions will differ** — devices that earlier
> revisions classified as `SKIP-newer` are now classified as
> `INSTALL_UPGRADE`. Re-validation on the M75q Tiny Gen 2 and X13 Gen 1
> AMD fixtures is recommended after upgrading.
>
> **Note on the CiTool / UTF-8 / pnputil operational fixes**
> (see SPEC §D.5 / §D.16 / §D.17, and the regression scenarios in
> [§9](#9-regression-scenarios-citool--utf-8--pnputil) below).
> Three operational issues were identified on a clean WS2025 install
> and fixed:
>
> 1. CiTool.exe was invoked without `--json` and blocked at I02 on
>    "Press Enter to Exit" stdin prompt (SPEC §D.16);
> 2. Console encoding was never set to UTF-8 so CiTool's ja-JP stdout
>    displayed as mojibake (SPEC §D.5 / §D.16);
> 3. pnputil exit=259 (`ERROR_NO_MORE_ITEMS`) was misclassified as
>    failure in the I03 summary, diverging from I04's correct
>    REBOOT_NEEDED / no-op recognition (SPEC §D.17).
>
> These fixes do NOT alter the structural pipeline behaviour validated
> on the M75q / X13 Gen 1 AMD fixtures (extraction, patching, signing,
> WDAC deployment all behave the same). The user-visible improvements
> are: I02 no longer hangs ~60-75 s waiting for ENTER; the CiTool log
> line reads `処理が成功しました` instead of mojibake; the I03 summary
> reports `no-op (already present)` instead of mis-counted failures.
> See [CHANGELOG.md](./CHANGELOG.md) for the release in which each fix
> landed.

The NPU script's verification is currently limited to:

1. **Static analysis** with `psa.py` v3.3.0 (36-rule check set including the PSA8xxx cross-file consistency / PSA9xxx complexity / PSAPxxxx project-convention families — `PSAP0001`..`PSAP0004`, **0 errors / 0 warnings / 0 info** with the repository-shipped `.psa.config.json` — see `SPEC.md` §A.11.5). `psa.py` is maintained as a canonical artifact in the [ai-generated-artifacts](https://github.com/usui-tk/ai-generated-artifacts) repository; obtain it per `SPEC.md` §A.11 before running.
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
# r58+ / r26+ recommended: use -LogFile to keep console colors while capturing the run.
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot `
    -LogFile "C:\Temp\m75q-amd-chipset_PrepareVerify_$ts.log"
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot `
    -LogFile "C:\Temp\m75q-amd-graphics_PrepareVerify_$ts.log"

# Legacy fallback (Write-Host coloring is stripped from the captured file):
#   .\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot *>&1 |
#     Tee-Object "C:\Temp\m75q-amd-chipset_PrepareVerify_$ts.log"

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
# r58+ / r26+ recommended: use -LogFile to keep console colors while capturing the run.
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot `
    -LogFile "C:\Temp\x13gen1-amd-chipset_PrepareVerify_Win11-preview_$ts.log"
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot `
    -LogFile "C:\Temp\x13gen1-amd-graphics_PrepareVerify_Win11-preview_$ts.log"

# Legacy fallback (Write-Host coloring is stripped from the captured file):
#   .\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot *>&1 |
#     Tee-Object "C:\Temp\x13gen1-amd-chipset_PrepareVerify_Win11-preview_$ts.log"

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
| Static analysis with `psa.py` v3.3.0 with the repository-shipped `.psa.config.json` (see `SPEC.md` §A.11) | ✅ done | 0 errors / 0 warnings / 0 info — fully clean baseline as of r60 / r28 / r10 / r10 (see §A.11.5) |
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

- [ ] You have read [§ Risk classification](./README.md#risk-classification-of-the-four-scripts) of the README.
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

## 4. Validation Result 4 (BthPan script) — planned

> The BthPan script (r10) is brand-new; physical validation has not yet been performed. This section documents the planned first physical-validation run.

### 4.1 Planned target hardware

| Item | Value |
|---|---|
| Model | Lenovo ThinkPad (specific SKU TBD; any model with bound Intel AX210) |
| Bluetooth host controller | Intel AX210 (`USB\VID_8087&PID_0032`, also seen as `USB\VID_8087&PID_0033`) |
| Host controller driver source | Intel published `Bluetooth_22.x.x.x_64UWD-RetailWHCK.zip` (vendor-signed; loads on Server with no patching) |
| OS | Windows Server 2025 (build 26100.32860 — the first WS2025 GA build) |
| ProductType | 3 (Server) |
| Disk | NVMe (free space >5 GB for workspace; BthPan workspace is small ~10 MB) |

### 4.2 Pre-validation state (expected on a fresh WS2025 install)

After installing the Intel AX210 host controller driver via its vendor installer, `BTH\MS_BTHPAN` should appear in Device Manager. The expected starting state is **one of**:

- **Unknown Device (code 28)**: `BTH\MS_BTHPAN` enumerated but no driver bound. This is the cleanest case for I04 to verify true resolution against.
- **Phantom OK**: `BTH\MS_BTHPAN` showing Status=OK, with `DriverInfPath=bth.inf`, `Class=Bluetooth`, `Service=(empty)`. This is the trickier case the script is specifically designed to detect.

V06 will diagnose and print the actual starting classification.

### 4.3 Planned test commands

```powershell
# Stage 0: confirm host controller is bound
Get-PnpDevice -Class Bluetooth | Select-Object FriendlyName, Status, InstanceId

# Stage 1: diagnosis only (no system change)
.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot

# Read V05 + V06 output carefully. Confirm:
#   - V05 reports the device count and classification
#   - V06 risk class is LOW (BthPan default; only MEDIUM if Phantom OK detected)
#   - Patched bthpan.inf is at C:\Temp\Workspace_Microsoft-BthPan\patched\bthpan\bthpan.inf
#   - inf2cat catalog targets Server2025_X64 + ServerFE_X64 + ServerRS5_X64 + Server2016_X64

# Stage 2: full install
.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action Install

# Expected I03 output:
#   pnputil /add-driver bthpan.inf /install   -> exit=0 (or 3010 if reboot needed)
#   pnputil /scan-devices                     -> exit=0

# Expected I04 output:
#   [OK]   TRUE resolution: oem*.inf bound, Class=Net, Service=BthPan
#   *** TRUE RESOLUTION ACHIEVED ***

# If I04 reports `*** TRUE RESOLUTION NOT YET ACHIEVED ***`:
#   Reboot, then re-run the same command. The script's resume-after-reboot
#   logic should detect the now-correct binding and confirm true resolution.
```

### 4.4 Verification commands to run after install

```powershell
# Runtime artifacts
Test-Path C:\Windows\System32\drivers\bthpan.sys           # expected: True
Get-Service BthPan                                          # expected: present, Status=Running or Stopped
(Get-Service BthPan).StartType                              # expected: Manual (default)

# Device-level binding
$dev = Get-PnpDevice -InstanceId 'BTH\MS_BTHPAN*'
$dev | Get-PnpDeviceProperty -KeyName DEVPKEY_Device_DriverInfPath, DEVPKEY_Device_Class, DEVPKEY_Device_Service
# Expected:
#   DriverInfPath = oem<N>.inf  (e.g. oem17.inf)
#   Class         = Net
#   Service       = BthPan

# NetAdapter visibility
Get-NetAdapter | Where-Object InterfaceDescription -Match 'Bluetooth.*Personal Area Network'
# Expected: one NetAdapter present, MediaType=Bluetooth

# Self-signed catalog still trusted
signtool verify /pa /v C:\Temp\Workspace_Microsoft-BthPan\patched\bthpan\bthpan.cat
# Expected: "Successfully verified"

# WDAC supplemental policy active
CiTool --list-policies --json | ConvertFrom-Json |
    Select-Object -ExpandProperty Policies |
    Where-Object PolicyID -eq '{A6E72D4F-3B98-4C5A-9E1D-7F8B2A4C6E5D}'
# Expected: one Policy returned, IsActive=True
```

### 4.5 Pass/Fail criteria

The validation run is considered PASS only if **all** of the following hold:

1. P03 locates the DriverStore source without errors (`bthpan.inf_amd64_*` directory exists)
2. P06 generates a patched bthpan.inf with at least one server decoration (`ServerDecCount >= 1`)
3. P08 generates a signed catalog targeting all four Server SKUs
4. I01 imports the cert into LocalMachine\Root + LocalMachine\TrustedPublisher without error
5. I02 deploys the WDAC supplemental policy with the BthPan-specific GUID `A6E72D4F-…`
6. I03 returns exit 0 (or 3010 with subsequent reboot)
7. I04 reports `*** TRUE RESOLUTION ACHIEVED ***`
8. Post-install verification commands in §4.4 all return their expected values

### 4.6 Strategy A vs Strategy B test plan

Once §4.5 PASS is achieved with the default Strategy A, the planned regression test sequence is:

1. **Strategy B run** — `-DecorationStrategy B -CleanWorkRoot`. Confirm that the patched INF gains four additional `NTamd64.10.0...XXXXX` entries in `[Manufacturer]` and four corresponding mirrored InstallSection blocks. Confirm the same `*** TRUE RESOLUTION ACHIEVED ***` outcome.
2. **Cleanup test** — `-Action Cleanup`. Confirm the workspace is removed, WDAC supplemental policy is uninstalled, and re-running V06 reports the system has returned to its pre-install state (Phantom OK or Unknown Device).
3. **Resume-after-reboot test** — simulate the I03 reboot scenario by running `-Action Install` on a Phantom OK host where PnP does not immediately rebind. After reboot, re-run `-Action Install` and confirm the resume-after-reboot logic correctly detects the now-true-resolution state and reports cached/skip for I01/I02/I03 + still runs I04 for the verdict.

### 4.7 Known unknowns to be resolved by this validation

- How reliably does `pnputil /scan-devices` cause an immediate rebind from `bth.inf` (Phantom proxy) to the patched `oem*.inf`, vs requiring a reboot?
- Are there any DEVPKEY values that differ between Strategy A and Strategy B-installed devices? (Expected: no — both should produce identical Class/Service/DriverInfPath, only the PnP ranking score differs.)
- Does Strategy B's per-build decoration actually improve PnP ranking over Strategy A, or is it functionally indistinguishable?

---

## 5. Summary of validation results

### 5.1 Per-environment matrix

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

### 5.2 Recommended validation patterns

| Scenario | Recommended environment |
|---|---|
| "Real driver install validation" (chipset/graphics) | M75q Gen 2 physical (production target) |
| "Win11 → WS2025 pre-migration evaluation" (chipset/graphics) | X13 Gen 1 physical |
| **"NPU end-to-end validation"** | **Ryzen AI 300 / 7040 / 8040 series host (NOT YET IN MAINTAINER'S LAB — PRs welcome)** |

> **Why no non-AMD-consumer-hardware testing is documented**: This pipeline is an experimental tool for AMD's consumer Ryzen / Radeon / NPU silicon. Validation outcomes are by definition dependent on physical access to those devices. Running the pipeline on server-class EPYC, ARM, Intel, or virtual hosts cannot exercise the device-bind logic (V06), the actual driver upgrade decisions, or the post-install verification path (I04). The maintainers have concluded that "pipeline-soundness only" testing on non-target hardware adds little value relative to the cost of maintaining such infrastructure, and have therefore restricted validation to physical AMD consumer hardware.

---

## 6. Discovered bugs and fix history

The complete per-bug discovery-and-fix history is consolidated in
[`CHANGELOG.md`](./CHANGELOG.md), under "Discovered bugs and fix history
(validation-discovered)". That table maps each validation-discovered bug
to the script revision where it was found and the revision where it was
fixed, with cross-references to the relevant SPEC.md Part D section for
root-cause analysis.

For full validation logs and the corresponding fix commits, see
<https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/commits/main>.

---

## 7. UEFI Secure Boot baseline validation checklist

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

Run all four scripts in PrepareVerify mode on the same host with `-CleanWorkRoot`. The captured `BucketId`, `Confidence`, and event counts in V06 should be **identical** across all four scripts (the MS sample script returns deterministic results for the same host state).

---


## 8. AMD Chipset Software 8.x extraction diagnostic format

This section documents the expected diagnostic output and the
validation procedure for AMD's two-layer Chipset Software 8.x
(8.02.18.557 and later) extraction path. The extraction strategy and
its historical evolution are described in
[SPEC §D.12](./SPEC.md#d12-chipset-r54--installshield-sfx-extraction-for-amd-8x-installers);
the revision in which this strategy was introduced is logged in
[CHANGELOG.md](./CHANGELOG.md).

### 8.1 Why a new strategy was needed

AMD Chipset Software 8.x ships as a two-layer wrapper:

1. **Outer layer**: NSIS self-extracting EXE (7-Zip can extract this).
2. **Inner layer**: InstallShield SFX in `ISSetupStream` format (7-Zip CANNOT extract; only InstallShield's own `/a` admin install can).

Earlier revisions detected the 7-Zip failure on the inner layer and fell back to launching the installer and harvesting from `C:\AMD\`, which is fragile because AMD aggressively cleans up that directory. The current pipeline inserts a dedicated InstallShield-aware strategy between the old 7-Zip strategy and the launch-watch fallback.

See `SPEC.md` §B.1 "AMD 8.x installer architecture (r54+)" for the full architecture.

### 8.2 Expected diagnostic output when Strategy 2 succeeds

When the installer is AMD 8.x, P04 console output should look approximately like the following (truncated for readability):

```
[*] Phase 04 :  P04 ExtractInstaller   (Build group)
[*] Extracting installer (multiple strategies will be attempted)
    Strategy 1/3: 7-Zip auto-detect
[!] 7-Zip auto-detect produced no usable payload (exit 0) - trying next strategy
    Strategy 2/3: InstallShield /a admin install (AMD 8.x+ chain)
      Step 1/3: 7-Zip outer NSIS shell...
      Inner SFX  : C:\Temp\Workspace_AMD-Chipset\is-stage-nsis\AMD_Chipset_Drivers.exe (75.3 MB)
      Step 2/3: InstallShield /a admin install...
      Unpacked   : 36 MSI files (InstallShield exit 0)
      Step 3/3: msiexec /a on 36 sub-MSI(s)...
      msiexec /a : 35 succeeded, 1 failed
      INF total  : 96
      [PREFERRED] W11x64    :  32 INF(s)
      [ skip    ] WTx64     :  32 INF(s)
      [ skip    ] WTx86     :  32 INF(s)
[+]    Extracted via InstallShield admin install chain
[+] Extracted to: C:\Temp\Workspace_AMD-Chipset\extract
```

### 8.3 Validation checklist

When the new path runs successfully, all of these should hold:

| Check | Expected value | How to verify |
| --- | --- | --- |
| InstallShield exit code | `0` (best) or `1` (acceptable if MSI count is correct) | Console line `Unpacked   : NN MSI files (InstallShield exit X)` |
| MSI count | `>= 36` (1 parent + 35 sub-MSIs for 8.02.18.557; future versions may differ) | Same console line |
| msiexec /a success rate | `>= 30` of `36` | Console line `msiexec /a : NN succeeded, M failed` |
| INF total | `>= 80` (varies with version; usually 96 in 8.02.18.557) | Console line `INF total  : NN` |
| PREFERRED variant has non-zero INFs | `[PREFERRED] <variant> : >= 25 INF(s)` | Console line; **this is the critical signal** |
| PREFERRED variant matches host OS | `W11x64` on WS2022/WS2025; `WTx64` on WS2016/WS2019 | Cross-check `$Ctx.Os` from console banner |

### 8.4 Troubleshooting

If the PREFERRED variant shows `0 INF(s)` despite the extraction succeeding, the most likely causes are:

1. **InstallShield /a failed silently**: Check `C:\Temp\Workspace_AMD-Chipset\installshield-admin.log` for MSI errors during the admin install. Look for `Action ended ...` lines with non-zero return values.

2. **msiexec /a failed for the OS-variant sub-MSIs**: Check `C:\Temp\Workspace_AMD-Chipset\msiexec-admin-*.log` for the specific failing sub-MSIs. Each sub-MSI has its own log named after the MSI filename.

3. **AMD changed the directory layout in a future version**: If you are running against a Chipset Software version newer than 8.02.18.557 and the `Binaries\<DriverName>\<OS>\` structure changed, the `Get-AmdSourceVariant` classifier (script line ~5003) may need updating. File a GitHub issue with the directory tree under `C:\Temp\Workspace_AMD-Chipset\extract\`.

### 8.5 Fallback behaviour

If Strategy 2 fails for any reason (caught by the `try { ... } catch` block in `Expand-AmdInstaller`), the script falls through to Strategy 3/3 (launch + watch), preserving the legacy behaviour from earlier revisions. The console output in that case will be:

```
[!] InstallShield /a strategy failed: <error message>
    Strategy 3/3: launch installer and harvest from C:\AMD\
```

This is the legacy fallback path used by earlier revisions and should be considered a regression fallback only.

---

## 9. Regression scenarios: CiTool / UTF-8 / pnputil

These regression scenarios validate the three operational fixes for
the CiTool interactive-prompt, ja-JP UTF-8 console encoding, and the
pnputil exit=259 reclassification (root causes in SPEC §D.5 / §D.16 /
§D.17; release information in [CHANGELOG.md](./CHANGELOG.md)). All
three can be exercised on the same WS2025 install used for §1
(M75q Tiny Gen 2) without re-imaging.

### 9.1 CiTool ENTER-prompt hang (SPEC §D.16)

**Pre-fix symptom**: I02 stalls ~60-75 s between the two log lines below; pressing ENTER in the active console resumes the script:

```
[*] Converting XML to .cip binary and deploying to active CI policies...
[+] Deployed: ...
```

**Regression test**: After running `-Action Install -OnlyPhases I02` with the new revision:

| Observation | Pre-fix | Post-fix |
|---|---|---|
| Wall-clock elapsed for I02 | 60-75 s with ENTER input ~mid-phase | < 10 s end-to-end, no input required |
| Stdin requirement | Operator must press ENTER once per CiTool invocation (I02 + Cleanup) | No stdin interaction |
| CiTool stdout in log | `処理は成功しました\n続行するには、Enter キーを押してください` (literal) OR mojibake under cp932 | Clean JSON envelope, no "Press Enter" line |

**Pass criterion**: I02 completes without any stdin interaction; the operator can walk away from the console.

**Verification commands (operator can run in any elevated PS console)**:

```powershell
# This is a SAFE no-input test: CiTool --list-policies --json prints JSON and exits
# WITHOUT the "Press Enter to Exit" prompt. Without --json, it prints the prompt
# and blocks on stdin.
& CiTool.exe --list-policies --json | ConvertFrom-Json | Select-Object -First 3
```

If this returns control to the prompt immediately, the `--json` mechanism is functioning on this host.

### 9.2 Console UTF-8 enforcement (SPEC §D.5 / §D.16)

**Pre-fix symptom**: I02 log line reads:

```
CiTool: 蜃ｦ逅・・謌仙粥縺励∪縺励◆
```

(The UTF-8 byte sequence of `処理が成功しました` decoded as cp932.)

**Regression test**: With the fixed revision, the same line reads:

```
CiTool: 処理は成功しました
```

OR (when the CiTool `--json` parse extracts the canonical OperationResult):

```
CiTool: Success
```

**Pass criterion**: No CJK mojibake in any CiTool, signtool, or pnputil stdout captured in the run log.

**Verification commands**:

```powershell
# (a) Confirm the three encodings are UTF-8 after P00 has run.
# Run AFTER any phase of the script has executed.
[Console]::OutputEncoding.WebName   # expected: utf-8
[Console]::InputEncoding.WebName    # expected: utf-8
$OutputEncoding.WebName             # expected: utf-8

# (b) Confirm CiTool's ja-JP stdout decodes correctly.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$stdout = & CiTool.exe --list-policies --json 2>&1 | Out-String
$stdout | Select-String '"OperationResult"' -CaseSensitive
# Expected: a line like  "OperationResult": "Success"
# NOT mojibake.
```

### 9.3 pnputil exit=259 reclassification (SPEC §D.17)

**Pre-fix symptom (chipset)**: On a clean WS2025 install, I03 final summary reports:

```
Driver install: 52 ok (2 need reboot) / 3 failed / 0 skipped (current newer)
```

but I04 PostInstallVerification immediately reports `FAILED: 0`. The three "failed" cases were duplicate-source INFs (`SMBUSamd.inf`, `AMDInterface.inf`, `AmdMicroPEP.inf`) where the second invocation returned exit=259 because the driver package was already in the store.

**Regression test**: With the fixed revision, the same I03 run reports:

```
Driver install: 52 ok (2 need reboot, 3 no-op) / 0 failed / 0 skipped (current newer)
```

And the I03 per-INF lines previously rendered as `[!]   exit=259 (see ...)` now render as `[~]   no-op (driver store already up-to-date)`.

**Pass criterion**:
1. I03 failure count is 0 on a clean install (modulo any genuine pnputil errors).
2. I04 `FAILED` count matches I03 `failed` count (both should be 0 or both should be the same non-zero number).
3. Devices that earlier showed under both "I03: 3 failed" AND "I04: REBOOT_NEEDED" now show only under "I04: REBOOT_NEEDED" with the corresponding I03 entries marked `no-op`.

**Verification command (post-install state inspection)**:

```powershell
# Compare I03 install result count vs I04 device classification
# Read the persisted I03 results
$ws = 'C:\Temp\Workspace_AMD-Chipset'
# I03 writes to install_results.csv if Export-Csv is wired in (otherwise check console log)
# Easier: re-run the script and compare summary line vs Section 1 of I04.
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action Install -OnlyPhases I04
# Expected: "FAILED : 0 device(s)" and no devices in the [FAILED] sub-list.
```

### 9.4 Combined regression checklist

When validating these fixes on the M75q Tiny Gen 2 or X13 Gen 1 AMD fixtures:

| # | Check | Pass criterion |
|---|---|---|
| 1 | Banner shows the script version string (e.g., `chipset-YYYY.MM.DD-rNN`) at script startup | ✓ correct version string |
| 2 | P00 log emits `[~] Console encoding set to UTF-8` (NPU only) or simply does not display mojibake later | ✓ no cp932 indicator in CiTool output |
| 3 | I02 completes in < 10 s WITHOUT operator stdin input | ✓ no hang at "Converting XML to .cip binary..." |
| 4 | I02 final line includes `Activation method: CiTool (immediate, no reboot)` rendered via `Write-Detail` (4-space indent, Gray) | ✓ visually subordinate to the preceding `[+] Deployed:` marker line |
| 5 | I03 final summary line includes a `, N no-op` segment for chipset / graphics | ✓ matches the new 5-tuple format |
| 6 | I04 `FAILED` count = I03 `failed` count | ✓ both 0 on the clean-install scenario |
| 7 | All ja-JP strings in the log are readable (no `蜃ｦ`, `謌仙` etc.) | ✓ no mojibake |

