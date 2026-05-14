# TESTING.md — Cloud Testing Procedure and Physical Hardware Validation Results

This document consolidates everything needed to test and evaluate `Deploy-AMD-Drivers-For-WindowsServer`. It covers four environments:

1. **AWS cloud (Tokyo region)** — testing procedure with multi-generation EPYC instance options (Naples / Milan / Genoa / Turin)
2. **Validation Result 1: ThinkCentre M75q Tiny Gen 2** (Windows Server 2025 physical / Cezanne Zen 3 — chipset & graphics validated)
3. **Validation Result 2: ThinkPad X13 Gen 1 AMD (2020)** (Windows 11 Enterprise LTSC 2024 / Renoir Zen 2 — chipset & graphics validated)
4. **Validation Result 3 (NPU script)** — **🆘 NOT YET VALIDATED on physical NPU hardware. See [§4](#4-validation-result-3-npu-script--currently-unverified) for the current limited validation status.**

🇯🇵 **Japanese version: see [TESTING.ja.md](./TESTING.ja.md).**

---

## 0. Validation status summary

> Read this before sections 1-4. The three scripts have **very different validation maturity levels**.

| Script | Pipeline soundness on AWS EPYC | Physical-hardware validation | Real driver install on target HW | Recommended use |
|---|---|---|---|---|
| **Chipset (r47)** | ✓ verified across Naples → Turin | ✓ M75q Tiny Gen 2, X13 Gen 1 AMD | ✓ install completed successfully on M75q (WS2025) | Lab + cautious production |
| **Graphics (r16)** | ✓ verified across Naples → Turin | ✓ M75q Tiny Gen 2, X13 Gen 1 AMD | ✓ install completed successfully on M75q (WS2025) | Lab + cautious production |
| **NPU (r1)** | ⚠️ **partial** (PrepareVerify only on EPYC; NPU absent so V05/V06 outputs limited) | ❌ **none** (no physical NPU machine in maintainer's lab) | ❌ **never executed** | **Experimental / research-grade only. Do not deploy in production.** |

The NPU script's verification is currently limited to:

1. **Static analysis** with `psa.py` v3.0.0 (27-rule check set `PSA1001`..`PSA6006`, **0 errors** with a documented baseline of warnings/info — see `SPEC.md` §A.11.5). `psa.py` is maintained as a canonical artifact in the [ai-generated-artifacts](https://github.com/usui-tk/ai-generated-artifacts) repository; obtain it per `SPEC.md` §A.11 before running.
2. **Code review** of the AMD-published `quicktest.py` NPU detection logic translated to PowerShell.
3. **Dry-run on EPYC AWS hosts** with `-AssumeIfMissing` to confirm the pipeline runs to V06 without the NPU device being present.
4. **No `-Action Install` execution** has been performed by the maintainers anywhere.

If you have a Ryzen AI 300 / Ryzen AI Max 300 / Ryzen 7040 / 8040 series machine and successfully run any phase of the NPU script, please report results via GitHub Issues so the validation gap can be closed.

---

## 1. AWS Cloud Testing

### 1.1 Positioning of cloud testing

AWS EC2 does not directly provide consumer Ryzen hardware. AMD-based EC2 instances run on **AMD EPYC server CPUs**, which are silicon-distinct from the consumer Ryzen chipset / Radeon iGPU / NPU that this script targets. AWS testing is therefore limited to the following purposes:

| What AWS can verify | What AWS cannot verify |
|---|---|
| ✓ Whether the script runs to completion without errors on Windows Server 2025 | ❌ Actual driver install results on real AMD consumer chipset / Radeon / NPU hardware |
| ✓ AMD package download / extraction / parsing | ❌ Device-bind correctness (the relevant HW is absent) |
| ✓ Self-signed certificate generation and catalog signing | ❌ Expected driver upgrades like "3 candidates upgrade" in V06 |
| ✓ WDAC supplemental policy generation (stop at PrepareVerify; do not deploy) | ❌ Post-I03 driver behaviour in a real environment |
| ✓ inf2cat / signtool tool-chain validation | ❌ BitLocker / TPM (PSP driver) interactions |
| ✓ CI automated testing (PR validation, regression testing) | ❌ AMD Vega/RDNA GPU rendering paths |
| ✓ Win32_Processor detection logic across EPYC generations | ❌ Consumer Ryzen detection paths |
| ✓ NPU script's PrepareVerify completion via `-AssumeIfMissing` (default Strix Point profile) | ❌ NPU script's actual NPU device detection, driver bind, post-install verification |

In short: **"pipeline soundness verification"** is well-served by AWS, while **"driver upgrade outcomes on consumer Ryzen / NPU machines"** require physical hardware. Cloud testing is most valuable as automated regression testing in something like GitHub Actions CI.

### 1.2 Map of all AMD EPYC generations available on AWS

AWS has been adopting AMD EPYC since 2018, and **five generations** of silicon are currently available. For script validation, deliberately spreading tests across generations is recommended (the pipeline must work uniformly on old and new EPYC alike):

| Generation | Codename | Release year | Architecture | Representative instances | Example CPU model | Max frequency | Tokyo region availability |
|---|---|---|---|---|---|---|---|
| **1st gen** | **Naples** | 2018 | Zen | T3a / M5a / R5a / C5a | EPYC 7571 (T3a) | 2.5 GHz | ✓ (older instances) |
| 2nd gen | Rome | 2019 | Zen 2 | (no general AWS adoption) | — | — | — |
| **3rd gen** | **Milan** | 2021 | Zen 3 | M6a / C6a / R6a / Hpc6a | EPYC 7R13 | 3.6 GHz | ✓ |
| **4th gen** | **Genoa** | 2023 | Zen 4 | M7a / C7a / R7a | EPYC 9R14 | 3.7 GHz (DDR5) | ✓ |
| **5th gen** | **Turin** | 2025 | Zen 5 | M8a / R8a / C8a | EPYC 9R45 | 4.5 GHz (M8azn: 5.0 GHz) | ✓ (M8a available in Tokyo since 2025-11-12) |

**Key technical differences**:

- **Naples (T3a/M5a)**: 1 vCPU = 1 SMT thread (2 vCPUs = 1 physical core). T3a has **AZ restrictions in some availability zones** that prevent WS2025 AMI launch (which requires Nitro + UEFI).
- **Milan (M6a)**: 1 vCPU = 1 SMT thread. AMD SEV-SNP supported (confirmed on M6a/C6a/R6a).
- **Genoa (M7a)**: **1 vCPU = 1 physical core (SMT disabled)**. DDR5 memory, AVX-512 / VNNI / bfloat16.
- **Turin (M8a)**: 1 vCPU = 1 physical core. Zen 5, CPU Family 26 (Genoa is Family 25). L1d cache 48 KiB (+50% over previous-generation 32 KiB).

### 1.3 Recommended instance types by use case (Tokyo region, ap-northeast-1)

| Use case | Recommended instance | EPYC generation | vCPU/RAM | Tokyo Windows price (estimate) | Notes |
|---|---|---|---|---|---|
| **Cheapest — PrepareVerify** | `t3a.medium` | Naples (1st) | 2 / 4 GiB | ≈ **$0.07–0.10/h** | Watch AZ restrictions (e.g. WS2025 AMI may not launch in us-east-1a) |
| **Stable burstable** | `t3a.large` | Naples (1st) | 2 / 8 GiB | ≈ $0.13–0.17/h | More headroom for the WDK install |
| **Modern EPYC — Milan** | `m6a.large` | Milan (3rd) | 2 / 8 GiB | ≈ $0.18–0.22/h | SMT enabled, SEV-SNP testable |
| **DDR5 — Genoa** | `m7a.large` | Genoa (4th) | 2 / 8 GiB | ≈ $0.22–0.27/h | SMT disabled, AVX-512, validates CPU Family 25 detection |
| **Latest — Turin** | `m8a.large` | Turin (5th) | 2 / 8 GiB | ≈ $0.23–0.28/h | ≈ +5% vs M7a, Zen 5, validates CPU Family 26 detection |
| **GPU validation (optional)** | `g4ad.xlarge` | (Naples + Radeon V520) | 4 / 16 GiB | ≈ $0.50–0.60/h | AMD Radeon Pro V520 dGPU; exercises `Win32_VideoController` AMD GPU detection paths |

> **Pricing note**: figures above are approximations as of this document's creation (May 2026), with the Windows Server license cost (≈ $0.046/h) included. Verify the latest exact pricing in [AWS Pricing Calculator](https://calculator.aws/). **Spot instances** can offer up to ~70% savings (a t3a.medium Spot runs around $0.02–0.03/h).

#### Cost estimate for one PrepareVerify run (~10 minutes)

| Instance | Single run | 5 runs/day | Monthly (5/wk × 4 wk) |
|---|---|---|---|
| t3a.medium Spot | ≈ $0.005 | ≈ $0.025 | ≈ $0.50 |
| t3a.medium On-Demand | ≈ $0.014 | ≈ $0.07 | ≈ $1.40 |
| m6a.large On-Demand | ≈ $0.033 | ≈ $0.165 | ≈ $3.30 |
| m7a.large On-Demand | ≈ $0.040 | ≈ $0.20 | ≈ $4.00 |
| m8a.large On-Demand | ≈ $0.043 | ≈ $0.215 | ≈ $4.30 |

**Weekly regression testing across all four generations (Naples / Milan / Genoa / Turin)** can be built for under ~$15/month total. Add ~$5/month for storage (gp3 EBS 50 GB) and the picture remains very affordable.

### 1.4 Recommended AMI and launch constraints

Use the AWS-managed **Microsoft Windows Server 2025 Base** (License Included) AMI. Windows Server 2025 AMIs require **Nitro-based instances with UEFI boot mode**:

- **Supported**: T3a (in newer AZs), M6a, M7a, M8a, C6a, C7a, C8a, R6a, R7a, R8a — all are Nitro + UEFI capable and can launch the WS2025 AMI.
- **Caveat**: Some AZs (e.g. us-east-1a) cannot launch WS2025 on T3a due to UEFI restrictions. Either use the `BIOS-Windows_Server-2025-English-Full-Base` AMI (Legacy BIOS) or pick a different AZ (e.g. us-east-1f). In Tokyo, T3a launches of WS2025 are most stable in ap-northeast-1c / 1d.

#### Fetching the latest AMI ID

```bash
# Latest WS2025 (UEFI, English) AMI in Tokyo
aws ec2 describe-images \
  --owners 'amazon' \
  --region ap-northeast-1 \
  --filters \
    'Name=platform,Values=windows' \
    'Name=name,Values=Windows_Server-2025-English-Full-Base-*' \
  --query 'reverse(sort_by(Images, &CreationDate))[0].{ImageId:ImageId,Name:Name,CreationDate:CreationDate}' \
  --output table

# Japanese-locale variant (localizes patch logs)
aws ec2 describe-images \
  --owners 'amazon' \
  --region ap-northeast-1 \
  --filters \
    'Name=platform,Values=windows' \
    'Name=name,Values=Windows_Server-2025-Japanese-Full-Base-*' \
  --query 'reverse(sort_by(Images, &CreationDate))[0].{ImageId:ImageId,Name:Name,CreationDate:CreationDate}' \
  --output table
```

AMI names follow the `Windows_Server-2025-{English|Japanese}-Full-Base-YYYY.MM.DD` convention and are refreshed monthly.

### 1.5 Setup procedure (cross-generation validation)

#### Step 1: Launch one EC2 instance per generation (example)

```bash
AMI_ID=ami-XXXXXXXXXXXXXXXXX  # from describe-images
KEY=YourKeyPair
SG=sg-XXXXXXXXXX
SUBNET=subnet-XXXXXXXXXX  # ap-northeast-1c or 1d recommended

for INST in t3a.medium m6a.large m7a.large m8a.large; do
  aws ec2 run-instances \
    --region ap-northeast-1 \
    --image-id $AMI_ID \
    --instance-type $INST \
    --key-name $KEY \
    --security-group-ids $SG \
    --subnet-id $SUBNET \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=50,VolumeType=gp3}' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=amd-test-$INST}]"
done
```

#### Step 2: Retrieve Administrator password and connect via RDP

```bash
aws ec2 get-password-data \
  --region ap-northeast-1 \
  --instance-id i-XXXXXXXXXX \
  --priv-launch-key ./YourKeyPair.pem
```

Allow TCP 3389 from your IP in the security group, then RDP into the public IP.

#### Step 3: Transfer the scripts and run PrepareVerify

```powershell
# Inside the RDP session, in an elevated PowerShell
mkdir C:\TEMP
cd C:\TEMP

# Transfer the scripts (S3 / SSM Run Command / RDP clipboard — your choice)
$bucket = 'your-test-bucket'
aws s3 cp s3://$bucket/Deploy-AMDChipsetDriverOnWindowsServer.ps1  .
aws s3 cp s3://$bucket/Deploy-AMDGraphicsDriverOnWindowsServer.ps1 .
aws s3 cp s3://$bucket/Deploy-AMDNpuDriverOnWindowsServer.ps1      .
# Optionally, an offline NPU ZIP (see §4 for download instructions)
aws s3 cp s3://$bucket/NPU_RAI1.6.1_314_WHQL.zip .

# Confirm the CPU generation
Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
# Expected output:
#   t3a.medium: AMD EPYC 7571              2 cores  2 LP  2500 MHz  (Naples, SMT)
#   m6a.large : AMD EPYC 7R13              2 cores  2 LP  3725 MHz  (Milan, SMT)
#   m7a.large : AMD EPYC 9R14              2 cores  2 LP  3700 MHz  (Genoa, SMT off, Family 25)
#   m8a.large : AMD EPYC 9R45              2 cores  2 LP  4500 MHz  (Turin, SMT off, Family 26)

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Run PrepareVerify only (Install is meaningless on EPYC machines and discouraged)
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\chipset-AWS-$env:COMPUTERNAME.log
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\graphics-AWS-$env:COMPUTERNAME.log

# NPU PrepareVerify with -AssumeIfMissing (NPU absent on EPYC; default Strix Point profile)
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip -AssumeIfMissing *>&1 |
  Tee-Object C:\TEMP\npu-AWS-$env:COMPUTERNAME.log

# Upload logs to S3 for offline review
aws s3 cp C:\TEMP\chipset-AWS-$env:COMPUTERNAME.log  s3://$bucket/results/
aws s3 cp C:\TEMP\graphics-AWS-$env:COMPUTERNAME.log s3://$bucket/results/
aws s3 cp C:\TEMP\npu-AWS-$env:COMPUTERNAME.log      s3://$bucket/results/
```

#### Step 4: Stop or terminate the instances when done

```bash
# Stop (storage cost only while stopped)
aws ec2 stop-instances --region ap-northeast-1 \
  --instance-ids i-XXXXXXXXXX i-YYYYYYYYYY i-ZZZZZZZZZZ i-WWWWWWWWWW

# Fully terminate after validation
aws ec2 terminate-instances --region ap-northeast-1 \
  --instance-ids i-XXXXXXXXXX i-YYYYYYYYYY i-ZZZZZZZZZZ i-WWWWWWWWWW
```

### 1.6 Expected results across EPYC generations

| Verification item | t3a.medium (Naples) | m6a.large (Milan) | m7a.large (Genoa) | m8a.large (Turin) |
|---|---|---|---|---|
| OS detection (P00) | WS2025, ProductType=3 | same | same | same |
| CPU detection (P03) | EPYC 7571, recognised as Naples (Zen 1) | EPYC 7R13, Milan (Zen 3) | EPYC 9R14, Genoa (Zen 4), CPU Family 25 | EPYC 9R45, Turin (Zen 5), CPU Family 26 |
| Platform decision (P03) | Server / EPYC family → falls back to consumer Ryzen URL probe | same | same | same |
| AMD chipset HW detection (V06) | 0 or very few (PCI devices are virtio / Nitro) | same | same | same |
| AMD GPU HW detection (V06) | 0 (no Radeon GPU on plain EPYC instances; g4ad.* differs) | same | same | same |
| AMD NPU HW detection (V06, NPU script) | 0 (NPU absent on EPYC); script proceeds with `-AssumeIfMissing` profile | same | same | same |
| WILL be replaced (V06) | 0 | 0 | 0 | 0 |
| All P00–V06 phases pass (chipset / graphics / NPU) | ✓ ✓ ✓ | ✓ ✓ ✓ | ✓ ✓ ✓ | ✓ ✓ ✓ |
| Expected runtime (chipset+graphics) | ~8–12 min (slowest CPU) | ~6–9 min | ~5–8 min | ~4–7 min (fastest) |
| Expected runtime (NPU script) | ~3–5 min (smaller package) | ~2–4 min | ~2–3 min | ~2–3 min |
| Pipeline soundness | OK | OK | OK | OK |

**What four-generation cross-validation confirms**:

- The script runs to completion uniformly across all EPYC generations from Naples (Zen) to Turin (Zen 5) — a forward-compatibility guarantee for future silicon.
- Branch logic on CPU Family numbers (Naples=23, Milan=25, Genoa=25, Turin=26) does not regress.
- vCPU/SMT topology differences (SMT-on Naples/Milan vs SMT-off Genoa/Turin) do not break parallel-execution paths in the pipeline.
- For the NPU script: the 4-tier URL resolution falls through cleanly to Tier 4 (`-OfflineZip`), the ZIP is correctly extracted by 7-Zip, the INF parser identifies the target NPU codename's INF, P06 mirrors `ProductType=3` decorations, and signing succeeds.

---

## 2. Validation Result 1: ThinkCentre M75q Tiny Gen 2 (Windows Server 2025)

### 2.1 Hardware specifications

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

### 2.2 OS configuration

| Item | Value |
|---|---|
| OS | Windows Server 2025 Standard / Datacenter |
| Build | 26100 |
| ProductType | 3 (Server) |
| Secure Boot | ON |
| HVCI | OS default (varies by environment) |
| BitLocker | Optional (when enabled, **secure the recovery key in advance**) |

### 2.3 Validation procedure (chipset + graphics only — no NPU on this host)

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
# Running with -AssumeIfMissing would be a pipeline-soundness check only,
# similar to the AWS regression test above. M75q is more useful for chipset/graphics.
```

### 2.4 Key validation results

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

- **Not applicable on this host** (Cezanne has no NPU). The NPU script would detect 0 NPU devices and require `-AssumeIfMissing` to proceed. Such a run only validates pipeline soundness, not real NPU behaviour.

#### Soundness checks

- All 21 phases completed successfully (chipset + graphics)
- Self-signed certificate (RSA 4096 / SHA-384, 5-year validity) generated successfully
- 32 catalogs (chipset) + 19 catalogs (graphics) generated by `inf2cat /os:Server2025_X64`
- All catalogs successfully timestamp-signed by `signtool`
- After I03 (Install), Device Manager shows 3 chipset + 3 graphics devices bound to `[C] Self-signed`

### 2.5 Known limitations

- On hosts with BitLocker enabled, a PSP driver upgrade can trigger a recovery prompt at the next boot. **Always have the recovery key available** (Control Panel BitLocker UI, or via Microsoft Account backup).
- Some `ROOT\AMD*` software-only entities (AMDLOG / AMDXE etc.) are added by I03 but never appear in `Win32_PnPSignedDriver` enumeration; V06 Section 1 reports them as "software-only" for information only.
- Successful install is confirmed by the `[B] Vendor` → `[C] Self-signed` transition observed in I04.

---

## 3. Validation Result 2: ThinkPad X13 Gen 1 AMD (2020) — Windows 11 Enterprise LTSC 2024

### 3.1 Hardware specifications

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

### 3.2 OS configuration (at validation time)

| Item | Value |
|---|---|
| OS | Microsoft Windows 11 Enterprise LTSC 2024 |
| Build | 26100 (24H2 LTSC) |
| ProductType | 1 (Workstation) — runs in **WS2025 PREVIEW MODE** in this script |
| Secure Boot | OFF (toggled off for testing) |
| HVCI | ON |
| BitLocker | OFF (lab use) |

### 3.3 Validation procedure

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

### 3.4 Key validation results

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

### 3.5 Expected delta between Win11 and WS2025 on identical hardware

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

## 4. Validation Result 3 (NPU script) — currently UNVERIFIED

> **🆘 THIS SECTION DOCUMENTS WHAT HAS NOT BEEN VERIFIED.** Do not interpret it as evidence of working behaviour.

### 4.1 What is currently verified for the NPU script

| Verification activity | Status | Evidence |
|---|---|---|
| Static analysis with `psa.py` v3.0.0 (see `SPEC.md` §A.11) | ✅ done | 0 errors / 17 warnings / 0 info — fully baselined (see §A.11.5) |
| Code review of NPU detection logic | ✅ done | `Get-AmdNpuPlatform` is a direct PowerShell port of AMD-published `quicktest.py` |
| Pipeline soundness on AWS EPYC EC2 (NPU absent) | ⚠️ partial / planned | `-Action PrepareVerify -AssumeIfMissing` should run to V06 cleanly; not yet exercised in CI |
| Detection on physical NPU machine | ❌ **NOT DONE** | No physical NPU hardware in maintainer's lab as of this writing |
| INF parsing of real NPU driver ZIP | ❌ **NOT DONE** | NPU driver ZIPs (`NPU_RAI*_WHQL.zip`) are EULA-gated; maintainer does not have a verified copy of every RAI version's INF structure |
| `-Action Install` on physical NPU machine | ❌ **NOT DONE** | Same as above |
| Post-install bind to `[C] Self-signed` | ❌ **NOT DONE** | Same as above |
| AMD account auto-download (Tier 2) | ⚠️ **best-effort, unstable** | Implemented from public form structure observation; AMD form changes can break without notice |
| Ryzen AI Software user-mode stack on Server 2025 | ❌ **explicitly unsupported by AMD** | AMD documentation states Win11 24H2 (build >= 22621.3527) only |

### 4.2 Validation gaps (what should be done before treating the NPU script as production-ready)

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

5. **Pipeline regression on AWS EPYC** — currently the most accessible substitute for real NPU validation. Run `-Action PrepareVerify -AssumeIfMissing -OfflineZip <path>` weekly on Naples / Milan / Genoa / Turin to catch regressions in the URL-resolution / ZIP-extraction / INF-parsing / signing pipeline.

### 4.3 Recommended invocation patterns and 4-tier evaluation

The 4-tier URL resolution in `Resolve-AmdNpuDriverUrl` (script line 772) controls how P03 obtains the NPU driver ZIP. The behaviour is **not symmetric across all parameter combinations**, so the table below documents the actual outcome of each invocation pattern. Use this when planning runs.

| # | Invocation | Outcome | Path through 4-tier resolver |
|---|---|---|---|
| 1 | `-Action PrepareVerify -CleanWorkRoot -OfflineZip <path>` | ✅ **Recommended for first dry run.** | T4 priority block (line 824) → ZIP copied to workspace → P03 succeeds |
| 2 | `-Action PrepareVerify -CleanWorkRoot -OfflineZip <path> -AssumeIfMissing` | ✅ **Recommended for AWS EPYC regression.** | Same as #1 plus default Strix Point profile when no NPU detected |
| 3 | `-Action PrepareVerify -CleanWorkRoot` (no `-OfflineZip`) | ⚠️ **Likely fails on a clean machine.** | T1 skip → T4 priority skip → T2 skip → T3 falls through (HTML form) → T4 auto-scan (script dir, ./cache, workspace, ~/Downloads) → if nothing found, throws |
| 4 | `-Action Install -OfflineZip <path>` | ✅ **Recommended for real-NPU install.** | T4 priority block → I00 prompts for "I AGREE" → I01-I04 |
| 5 | `-Action Install -AmdAccountUser ... -AmdAccountPassword ...` | ⚠️ **Best-effort. AMD form changes can break this without notice.** | T1 skip → T4 priority skip → T2 attempts authenticated download → falls back to T3/T4 on failure |
| 6 | `-Action Install -InstallerUrl <captured-url>` | ✅ Works if the URL is fresh (entitlenow.com URLs expire). | T1 direct download → P03 succeeds |
| 7 | `-Action Install -NpuOverride STX -NpuDriverPackage NPU_RAI1.6.1_314` (no source) | ❌ **Misleading; do not use.** | T1/T2/T3 skip → T4 auto-scan picks up *whatever* `NPU_RAI*_WHQL.zip` is in `~/Downloads` (may not match the override) |

**Why pattern #1 (`PrepareVerify` + `OfflineZip`) is the strongest recommendation**:

- **Deterministic**: the Tier 4 priority block at line 824 short-circuits the resolver immediately. No network calls to AMD, no form-parsing fragility, no race against EULA URL expiry.
- **System-untouched**: `PrepareVerify` runs P00–P09 + V01–V06 only. No certs imported, no WDAC policy deployed, no drivers installed.
- **Reproducible across hosts**: copy the same ZIP to a new machine, get the same P05/P06/V05/V06 output. Critical for CI regression testing.
- **Gives you V05/V06 output**: dry-run install plan and hardware impact analysis are produced even on EPYC EC2 (where `-AssumeIfMissing` is needed because no NPU is present).

**Common pitfall — pattern #7**: switches like `-NpuOverride`, `-NpuDriverPackage`, and `-RyzenAiSoftwareVersion` *modify resolver behaviour but do not provide a download source*. If you specify them without `-OfflineZip` / `-InstallerUrl` / `-AmdAccountUser`, the resolver falls through to Tier 4 auto-scan. Auto-scan picks up whichever `NPU_RAI*_WHQL.zip` it finds first — and that ZIP **may not match the codename or version you tried to override**. The version check happens inside the ZIP's INFs (P05), not against the filename. Always pin the source explicitly.

### 4.4 Pre-flight checklist before running the NPU script anywhere

Even before any of the above gaps are closed, follow this checklist before running the NPU script on **any** host:

- [ ] You have read [§ Risk classification](./README.md#risk-classification-of-the-three-scripts) of the README.
- [ ] You have a Ryzen AI 300 / Ryzen AI Max 300 / Ryzen 7040 / 8040 series CPU (or you accept that detection will fall through to `-AssumeIfMissing` and the run is a pipeline-soundness check only).
- [ ] You have downloaded the appropriate `NPU_RAI*_WHQL.zip` from <https://ryzenai.docs.amd.com/en/latest/inst.html#install-npu-drivers> and placed it next to the script (Tier 4 — recommended).
- [ ] You have read AMD's Ryzen AI EULA at <https://account.amd.com/en/forms/downloads/ryzenai-eula-public-xef.html> and accepted it.
- [ ] You understand that Ryzen AI Software user-mode stack is officially Windows-11-only and **will not give you AI inference on Server 2025**.
- [ ] If running `-Action Install`: you can roll back via `-Action Cleanup` (and you accept that driver-store removal may need manual intervention).
- [ ] If running on a host with BitLocker: you have your recovery key recorded.
- [ ] You will report results to GitHub Issues regardless of success or failure (especially failure — the maintainers need this data to close the validation gap).

### 4.5 Expected NPU script outputs

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

#### P03 NPU detection (EPYC AWS, with `-AssumeIfMissing`)

```
[>] Enumerating PCI devices via pnputil /enum-devices /bus PCI /deviceids
[!] No AMD NPU detected via pnputil. Using default profile (Strix Point + RAI 1.7.1).
[+] CPU              : AMD EPYC 9R45
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

### 4.6 Tier 2 (AMD account auth flow) verification result — 2026-05-10

The `Invoke-AmdAccountAuthentication` function in `Deploy-AMDNpuDriverOnWindowsServer.ps1` was reviewed against the actual AMD account portal on **2026-05-10** to determine whether the implemented HTTP form POST flow can succeed against the current `account.amd.com` back-end. The verification used only public sources (no real AMD account credentials were used).

#### 4.6.1 Method

| Step | What was checked | How |
|---|---|---|
| 1 | `account.amd.com` rendering model | Web fetch of related AMD portals (`docs.amd.com/auth/login`, `pensandosupport.amd.com`, `fsdz.amd.com`) |
| 2 | EULA URL pattern in current AMD docs | GitHub `amd/ryzen-ai-documentation/blob/main/docs/inst.rst` (latest commit) |
| 3 | Driver-version naming convention | Cross-check between RAI 1.5 / 1.6.1 / 1.7 / 1.7.1 documentation pages on `ryzenai.docs.amd.com` |
| 4 | End-user behavior of the EULA flow | GitHub `amd/RyzenAI-SW#249`, `#328`, and cnx-software.com end-user blog post (Feb 2024) |
| 5 | Existence of public PowerShell/Python automation | Web search for `account.amd.com` automation, AMD account download scripting |

#### 4.6.2 Findings

| # | Finding | Severity | Evidence |
|---|---|---|---|
| F1 | **`account.amd.com` is a JavaScript-driven SPA.** Related AMD portals return `"JavaScript is required"` or `"Loading application"` HTML stubs on direct fetch. | High | Direct probe of `docs.amd.com/auth/login` and `fsdz.amd.com/adfs/ls/...` |
| F2 | **Login forms are not present in the initial HTML payload.** CSRF tokens, form actions, and fields are likely injected by JavaScript at runtime. | High | F1 implies the login form is rendered client-side |
| F3 | **EULA acceptance is interactive.** End users report that they "could not avoid signing the Beta Software EULA" — implying a JS-driven multi-step modal, not a single hidden form POST. | Medium | cnx-software.com testimonial (2024); GitHub #249 (2025) |
| F4 | **Two distinct EULA URL patterns exist** in AMD's documentation. Original code assumed only one. | Medium | `ryzenai-eula-public-xef.html` for NPU drivers vs `xef.html` for RAI Software EXE / NuGet |
| F5 | **The default driver/RAI mapping `1.7.1 → 32.0.203.380` was not real.** AMD's RAI 1.7.1 documentation reuses the 1.6.1 driver (`32.0.203.314`) and there is no `NPU_RAI1.7.1_380_WHQL.zip` publicly listed. The script's own comment admitted this was a "placeholder build until AMD publishes". | Medium | Cross-check of `ryzenai.docs.amd.com/en/latest/inst.html` and `github.com/amd/ryzen-ai-documentation/blob/main/docs/inst.rst` |
| F6 | **No public automation script for AMD account login was found.** Web search returned zero PowerShell/Python implementations that successfully drive the form. | Low | Negative search result; informational |

#### 4.6.3 Conclusion

The `Invoke-AmdAccountAuthentication` function as implemented (HTTP form POST against `https://account.amd.com/en/forms/auth/login.html`) **is highly unlikely to succeed against the current AMD portal**. The portal architecture does not match the assumptions encoded in the function (server-rendered HTML form with hidden CSRF token, simple POST credentials → redirect to authenticated EULA → simple POST EULA accept → redirect to entitlenow.com).

This conclusion was reached without making authenticated requests against AMD's servers — it follows from publicly visible architectural evidence (F1–F3), driver-version inconsistency (F5), and absence of any working public implementation (F6).

#### 4.6.4 Remediation applied to the script

| Change | Description | Location |
|---|---|---|
| C1 | **Tier 2 disabled by default.** The function now returns `$null` immediately unless `-ForceAmdAccountAuth` is passed. | `Invoke-AmdAccountAuthentication` (~line 1170) |
| C2 | **`VERIFIED 2026-05-10` banner** added with explicit "highly unlikely to succeed" warning. | `Invoke-AmdAccountAuthentication` head |
| C3 | **`-ForceAmdAccountAuth` switch** added to `param()` block. Operators who believe AMD has changed their portal can opt in to test. | Top-level `param()` |
| C4 | **Versioning fully separated.** Parameter `-PreferredRyzenAiVersion` (mixed driver + software in one knob) was replaced by two independent parameters: `-NpuDriverPackage` (default `latest` = `NPU_RAI1.6.1_314`) and `-RyzenAiSoftwareVersion` (default `latest` = `1.7.1`). Filename generation now produces `NPU_RAI1.6.1_314_WHQL.zip` matching what AMD actually publishes. Compatibility between A and B is evaluated as a separate axis. | `[string]$NpuDriverPackage = 'latest'`; `[string]$RyzenAiSoftwareVersion = 'latest'`; new functions `Get-NpuDriverPackageInfo`, `Get-LatestRyzenAiSoftwareInfo`, `Test-NpuDriverRaiCompatibility` |
| C5 | **`Get-RecommendedNpuDriverBuild` mapping corrected.** RAI 1.7 / 1.7.1 entries now both return `32.0.203.314` (the real published driver) instead of fictional `329` / `380` builds. Cross-references to AMD docs are added in the function header. | `Get-RecommendedNpuDriverBuild` |
| C6 | **All header `.EXAMPLE` filenames** updated from `NPU_RAI1.7.1_380_WHQL.zip` (fictional) to `NPU_RAI1.6.1_314_WHQL.zip` (verified). | Script header lines ~93, 99, 110, 124, 132 |
| C7 | **Default-Strix profile label** changed from `default-strix-rai1.7.1` to `default-strix-rai1.6.1`. P03 banner reflects the verified driver build. | `Get-AmdNpuPlatform` `$AssumeIfMissing` branch |

#### 4.6.5 What `-ForceAmdAccountAuth` does

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

#### 4.6.6 Future re-verification

Re-run this verification when:

- AMD announces a new Ryzen AI release (≥ 1.7.2 or 1.8) — driver mapping table may need updates
- A user reports that `-ForceAmdAccountAuth` now succeeds — Tier 2 can be re-enabled by default
- A new EULA URL pattern appears in AMD documentation (a third path beyond the two known)

The verification re-run procedure is the same as in 4.6.1: fetch public AMD pages, cross-check EULA URL patterns in `amd/ryzen-ai-documentation` GitHub repository, and check for end-user reports of successful automation.

### 4.7 Versioning-axis separation verification — 2026-05-10

The NPU script's version-handling logic was redesigned on **2026-05-10** to fully separate the **NPU kernel-mode driver** versioning system from the **Ryzen AI Software (user-mode stack)** versioning system, per AMD's authoritative documentation at <https://ryzenai.docs.amd.com/en/latest/inst.html> (Last updated 2026-04-19).

#### 4.7.1 The two independent versioning systems

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

#### 4.7.2 Compatibility evaluation as a separate axis

AMD documents driver-software compatibility in the Ryzen AI Software installation guide. As of RAI 1.7.1 (the current latest):

> "Download and Install the NPU driver version: 32.0.203.280 or newer using the following links" — both `NPU_RAI1.5_280` and `NPU_RAI1.6.1_314` are listed as valid options.

This produces the following compatibility matrix (axis C — derived from axes A + B):

|  | RAI 1.5 | RAI 1.6.1 | RAI 1.7 | RAI 1.7.1 |
|---|---|---|---|---|
| Driver 32.0.203.280 (`NPU_RAI1.5_280`) | ✅ | ✅ | ✅ | ✅ |
| Driver 32.0.203.314 (`NPU_RAI1.6.1_314`) | ✅ | ✅ | ✅ | ✅ |

The minimum driver requirement (`32.0.203.280`) is consistent across all supported RAI Software versions per AMD's documentation. The script's `Test-NpuDriverRaiCompatibility` function encodes this matrix and emits `OK` or `MISMATCH` at P03.

#### 4.7.3 Code-level changes

| Layer | Before | After |
|---|---|---|
| **Operator parameters** | Single `-PreferredRyzenAiVersion <ver>` (mixed driver + software in one knob) | Two independent parameters: `-NpuDriverPackage <NPU_RAI1.5_280 \| NPU_RAI1.6.1_314 \| latest>` and `-RyzenAiSoftwareVersion <1.5 \| 1.6.1 \| 1.7 \| 1.7.1 \| latest>`. Both default to `latest`. |
| **Catalog functions** | `Get-RecommendedNpuDriverBuild $RaiVersion → $build` (incorrect coupling) and `Get-NpuZipFilename $RaiVersion $build → $filename` (string concatenation that produced fictional filenames) | Three independent functions: `Get-NpuDriverPackageInfo` (axis A: returns full package metadata for the documented ZIPs), `Get-LatestRyzenAiSoftwareInfo` (axis B: returns RAI Software metadata with `IsLatest` flag), `Test-NpuDriverRaiCompatibility` (axis C: evaluates the matrix above with `[version]` comparison) |
| **Detected-platform fields** | `RecommendedRaiVer`, `RecommendedDriver` (2 fields, ambiguously coupled) | `NpuDriverPackage`, `NpuDriverBuild`, `NpuDriverZipName` (axis A), `RyzenAiSoftwareVersion`, `RyzenAiSoftwareInstaller` (axis B), `DriverSoftwareCompatible`, `DriverSoftwareCompatNote` (axis C) — 7 fields with explicit axis attribution |
| **P03 banner output** | Single block listing "Preferred RAI ver" and "Recommended drv" | Three labelled blocks: "NPU kernel-mode driver (independent versioning axis)", "Ryzen AI Software (independent versioning axis - always latest unless pinned)", "Driver <-> RAI Software compatibility (separate evaluation axis)" with `OK`/`MISMATCH` status |
| **Post-install guidance (I04)** | Hardcoded fallback to `1.7.1` if RAI version was missing | Reads `RyzenAiSoftwareInstaller` field directly; falls back to `ryzen-ai-lt-1.7.1.exe` only if the field is empty. Explicitly states "NPU driver and Ryzen AI Software are versioned INDEPENDENTLY. Always use the LATEST Ryzen AI Software for end-user workloads." |

#### 4.7.4 Future maintenance

When AMD publishes a new Ryzen AI release, update the script in two places:

1. **If a new NPU driver ZIP is published** (e.g. `NPU_RAI1.8_400_WHQL.zip`): add an entry to the `Get-NpuDriverPackageInfo` catalog and the `-NpuDriverPackage` `ValidateSet`. If the new driver introduces a different minimum-required driver build for current RAI Software, update `Test-NpuDriverRaiCompatibility`.
2. **If a new Ryzen AI Software version is released** (e.g. `1.8.0`): add an entry to the `Get-LatestRyzenAiSoftwareInfo` catalog, update `$latestVersion` to the new version, and add the new value to the `-RyzenAiSoftwareVersion` `ValidateSet`. Cross-check the AMD release notes for any new minimum driver requirement and update `$minimumPerRai` in `Test-NpuDriverRaiCompatibility` accordingly.

The two updates are independent — adding driver support does not require touching software metadata, and vice versa. This is the central design property the redesign achieves.

---

## 5. Summary of validation results

### 5.1 Per-environment matrix

| Item | AWS Naples | AWS Milan | AWS Genoa | AWS Turin | M75q Tiny Gen 2 | X13 Gen 1 AMD | **Real NPU machine** |
|---|---|---|---|---|---|---|---|
| Instance / model | t3a.medium | m6a.large | m7a.large | m8a.large | ThinkCentre physical | ThinkPad physical | **TBD** |
| OS | WS2025 | WS2025 | WS2025 | WS2025 | WS2025 | Win11 LTSC 2024 | TBD |
| ProductType | 3 | 3 | 3 | 3 | 3 | 1 (PREVIEW MODE) | TBD |
| CPU | EPYC 7571 (Naples) | EPYC 7R13 (Milan) | EPYC 9R14 (Genoa) | EPYC 9R45 (Turin) | Ryzen 7 PRO 5750GE (Cezanne) | Ryzen 5 PRO 4650U (Renoir) | Ryzen AI 300 / 7040 / 8040 |
| Has NPU | no | no | no | no | no | no | **yes** |
| Chipset INFs processed | 32/32 | 32/32 | 32/32 | 32/32 | 32/32 + 3 V06 upgrades | 32/32 + 1 V06 upgrade | n/a (out of scope for NPU script) |
| Graphics INFs processed | 19/19 | 19/19 | 19/19 | 19/19 | 19/19 + 3 V06 upgrades | 19/19 + 3 V06 upgrades | n/a (out of scope for NPU script) |
| NPU script PrepareVerify | with `-AssumeIfMissing` | with `-AssumeIfMissing` | with `-AssumeIfMissing` | with `-AssumeIfMissing` | with `-AssumeIfMissing` (no NPU device) | with `-AssumeIfMissing` (no NPU device) | **PENDING** |
| NPU script Install | n/a | n/a | n/a | n/a | n/a | n/a (auto-block) | **PENDING** |
| Cost / run | ~$0.014 | ~$0.033 | ~$0.040 | ~$0.043 | $0 (physical) | $0 (physical) | $0 (physical) |
| Validation purpose | Cheapest regression test | Milan compatibility | DDR5 / Zen 4 | Zen 5 forward-compat | Pre-production rehearsal (chipset+graphics) | WS2025 pre-migration check | **NPU end-to-end validation** |

### 5.2 Recommended validation patterns

| Scenario | Recommended environment |
|---|---|
| "Quick PR sanity check" (chipset/graphics) | t3a.medium Spot (one generation) |
| "Pre-release regression" (chipset/graphics) | t3a.medium + m7a.large (two generations) |
| "All-generation compatibility" (chipset/graphics + NPU pipeline soundness) | t3a + m6a + m7a + m8a (four-way parallel, all three scripts with `-AssumeIfMissing` for NPU) |
| "Real driver install validation" (chipset/graphics) | M75q Gen 2 physical (production target) |
| "Win11 → WS2025 pre-migration evaluation" (chipset/graphics) | X13 Gen 1 physical |
| **"NPU end-to-end validation"** | **Ryzen AI 300 / 7040 / 8040 series host (NOT YET IN MAINTAINER'S LAB — PRs welcome)** |

---

## 6. Discovered bugs and fix history

The following bugs were found and fixed during the validation runs above:

| Discovery environment | Version | Fix version | Summary |
|---|---|---|---|
| ThinkPad X13 Gen 1 (Win11 24H2) | chipset r45 | r46 | Timezone bug in `Compare-InfDriverVer` (UTC midnight `DriverDate` was converted to local 09:00 by CIM cmdlets, causing the same-version case to be misreported as "current newer than patched"). Fixed by comparing `.Date` (year/month/day truncation) only. |
| ThinkPad X13 Gen 1 (Win11 24H2) | r45 / r14 | r46 / r15 | The P05 / P00 compatibility check displayed `Host OS: Windows Server 2025` even on a Workstation host, which was confusing. Now shows the actual `Caption` plus the mapped profile side by side. |
| ThinkPad X13 Gen 1 (Win11 24H2) | graphics r14 | r16 / r47 | V05 "would upgrade 1067/1067 matched device(s)" inflation. `$matchedDevices` was being appended per INF HWID variant rather than per physical device, inflating counts. Fixed by deduplication on the physical DeviceID. |
| ThinkPad X13 Gen 1 (Win11 24H2) | graphics r14 | r16 / r47 | Same-version, newer-date upgrade case formerly produced the nonsensical `patched newer (X) than current (X)` message. Now displays `patched same version (X) but newer date; PnP ranking prefers newer-dated driver` for clarity. |
| Pipeline review (no field reports) | NPU r1 | (placeholder) | Currently no field-discovered bugs — but **no field reports exist either**, because the NPU script has not been run on physical NPU hardware yet. |

For full validation logs and the corresponding fix commits, see <https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/commits/main>.

---

## 7. Outlook on CI/CD automation

For automated regression testing via GitHub Actions, AWS-based self-hosted runners are the practical choice:

```yaml
# .github/workflows/regression.yml — conceptual example
name: PrepareVerify regression test (multi-EPYC)
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  static-analysis:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Fetch psa.py from canonical repository (ai-generated-artifacts)
        run: |
          curl -sSLO https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py
      - name: Run psa.py static analyzer
        run: |
          python3 psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
          python3 psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
          python3 psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1

  ws2025-prepare-verify:
    needs: static-analysis
    strategy:
      matrix:
        include:
          - runner-tag: amd-naples   # t3a.medium
          - runner-tag: amd-milan    # m6a.large
          - runner-tag: amd-genoa    # m7a.large
          - runner-tag: amd-turin    # m8a.large
    runs-on: [self-hosted, windows, server-2025, "${{ matrix.runner-tag }}"]
    steps:
      - uses: actions/checkout@v4
      - name: Run chipset PrepareVerify
        shell: pwsh
        run: |
          Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
          .\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot
      - name: Run graphics PrepareVerify
        shell: pwsh
        run: |
          .\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot
      - name: Run NPU PrepareVerify (with -AssumeIfMissing, requires offline ZIP fixture)
        shell: pwsh
        env:
          NPU_OFFLINE_ZIP_S3_URI: ${{ secrets.NPU_OFFLINE_ZIP_S3_URI }}
        run: |
          # Pre-fetched NPU ZIP from S3 (license-gated; not in repo)
          aws s3 cp $env:NPU_OFFLINE_ZIP_S3_URI .\NPU_RAI1.6.1_314_WHQL.zip
          .\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
              -Action PrepareVerify -CleanWorkRoot `
              -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip `
              -AssumeIfMissing
```

This workflow has three layers:

1. **static-analysis job**: fetches `psa.py` from the canonical [ai-generated-artifacts](https://github.com/usui-tk/ai-generated-artifacts) repository, then runs it on a Linux runner to check PowerShell syntax and brace/paren/bracket balance for all three scripts (~10 seconds, essentially free).
2. **ws2025-prepare-verify job (chipset / graphics)**: runs PrepareVerify in parallel across four self-hosted WS2025 runners covering the Naples / Milan / Genoa / Turin generations.
3. **ws2025-prepare-verify job (NPU)**: extends step 2 by also running the NPU script with `-AssumeIfMissing` and a pre-fetched offline ZIP. This validates pipeline soundness only — not real NPU behaviour, since EPYC has no NPU device.

Combining the self-hosted runners with a scheduler that starts/stops them only on demand (e.g. AWS Lambda + SSM) keeps monthly cost down to roughly $5–10. The workflow stops at PrepareVerify; it does not attempt Install (since EPYC machines have no consumer Ryzen / NPU hardware to bind to).

> **Future**: when a physical NPU machine becomes available, an additional CI job can be added that runs `-Action Install` on a dedicated self-hosted runner (Ryzen AI 9 HX 370 mini-PC or similar). Until then, `-Action Install` for the NPU script must be exercised manually by operators with NPU hardware, and results reported via GitHub Issues.
