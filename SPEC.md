# Developer Specification (SPEC)

> **Purpose of this document**
>
> This file is the authoritative specification for building and extending the
> three PowerShell scripts in this repository
> (`Deploy-AMDChipsetDriverOnWindowsServer.ps1`,
> `Deploy-AMDGraphicsDriverOnWindowsServer.ps1`, and
> `Deploy-AMDNpuDriverOnWindowsServer.ps1`). It is written to be picked up
> directly by a human contributor or an LLM (Claude) at the start of a new
> feature or sister-script project so that conventions do not have to be
> re-derived from scratch.
>
> **The single most important rule**: when a piece of behavior is described
> in **Part A (Common Spec)**, any new feature or sister script MUST reuse
> the existing implementation referenced there. Do not re-design phase
> headers, log markers, environment diagnostics, error JSONL formats, or the
> `psa.py` static analyzer. These have been hardened through many revisions
> and reflect real-world bug fixes; rewriting them invites regressions.
>
> Use **Part B** as the per-script reference for the unique platform
> detection, INF inventory filter, installer source resolution tier, and
> known platform quirks of each of the three scripts. **Part C** documents
> the quality gates (`psa.py`, `TESTING.md`) that any change must pass.
> **Part D** preserves the historical lessons that the current
> implementation already accounts for.

🇯🇵 **日本語版仕様書は [SPEC.ja.md](./SPEC.ja.md) を参照してください。**

---

## Table of Contents

- [Part A — Common Specification (reusable across all scripts)](#part-a--common-specification-reusable-across-all-scripts)
  - [A.1 Reference Assets](#a1-reference-assets)
  - [A.2 Source File Format](#a2-source-file-format)
  - [A.3 Banner & Version Identification](#a3-banner--version-identification)
  - [A.4 Phase Architecture (21 phases)](#a4-phase-architecture-21-phases)
  - [A.5 Logging Conventions](#a5-logging-conventions)
  - [A.6 Parameter Conventions](#a6-parameter-conventions)
  - [A.7 Path Handling Rules](#a7-path-handling-rules)
  - [A.8 Error & Diagnostic Conventions](#a8-error--diagnostic-conventions)
  - [A.9 CSV Column Conventions](#a9-csv-column-conventions)
  - [A.10 Environment Evaluation (Phase P00)](#a10-environment-evaluation-phase-p00)
  - [A.11 Static Analysis with psa.py](#a11-static-analysis-with-psapy)
  - [A.12 Bilingual Documentation](#a12-bilingual-documentation)
  - [A.13 Development Workflow](#a13-development-workflow)
- [Part B — Script-specific Specifications](#part-b--script-specific-specifications)
  - [B.1 Chipset script (`Deploy-AMDChipsetDriverOnWindowsServer.ps1`)](#b1-chipset-script-deploy-amdchipsetdriveronwindowsserverps1)
  - [B.2 Graphics script (`Deploy-AMDGraphicsDriverOnWindowsServer.ps1`)](#b2-graphics-script-deploy-amdgraphicsdriveronwindowsserverps1)
  - [B.3 NPU script (`Deploy-AMDNpuDriverOnWindowsServer.ps1`)](#b3-npu-script-deploy-amdnpudriveronwindowsserverps1)
- [Part C — Quality Gates & Validation Checklist](#part-c--quality-gates--validation-checklist)
- [Part D — Known Pitfalls & Lessons Learned](#part-d--known-pitfalls--lessons-learned)

---

# Part A — Common Specification (reusable across all scripts)

## A.1 Reference Assets

These are the canonical sources of truth. **Pull from these directly; do not re-implement.**

### A.1.1 Reference scripts (phase / banner / log patterns)

```
Deploy-AMDChipsetDriverOnWindowsServer.ps1   (the most mature implementation; canonical r47)
Deploy-AMDGraphicsDriverOnWindowsServer.ps1  (graphics-specific platform detection; r16)
Deploy-AMDNpuDriverOnWindowsServer.ps1       (NPU script with 4-tier installer resolution; r2)
```

These 21-phase deployment scripts are the canonical source for:

- `Write-PhaseHeader` / `Write-PhaseFooter` / `Format-Elapsed`
- `Write-Step` / `Write-Ok` / `Write-Warn2` / `Write-Fail` / `Write-Skip`
- `Write-SubHeader` / `Write-SubHeader2` (Level-1 / Level-2 in-phase banners)
- Banner block layout (Magenta `=` × 72, script-tag line, phase entry / exit)
- `Show-PowerShellEnvironment` (P00 environment dump)
- `Show-OperatingSystemDetail` (OS profile / build / inf2cat `/os:` resolution)
- `Test-AdminPrivilege` (hard-fail check on non-elevated session)
- `Set-NetworkProtocol` (TLS hardening)
- `Show-RunSummary` (per-action summary with PhaseTimings + ScriptHash)

When extending these scripts, **copy these helpers verbatim** from the most recent revision rather than re-implementing them.

### A.1.2 Static analyzer

```
tools/psa.py
```

`psa.py` is a **pure Python** static analyzer (no PowerShell installation required) with 10 checks (C1–C10). It must be:

- Reused as-is (do not fork or modify without coordinating with upstream)
- Placed under `tools/psa.py` in any sister-script repo
- Used as the gate before every commit

See A.11 for details.

### A.1.3 Companion specifications

- `README.md` / `README.ja.md` — end-user documentation (installation, quick start, troubleshooting)
- `TESTING.md` / `TESTING.ja.md` — cloud (AWS EPYC EC2) regression testing procedure + physical-hardware validation results
- `CONTRIBUTING.md` — issue / PR conventions

### A.1.4 Workspace path convention

Each script writes to a dedicated workspace path under `C:\AMD-<short>-WS\` to guarantee non-collision between scripts:

| Script    | Default workspace path       |
| --------- | ---------------------------- |
| Chipset   | `C:\AMD-Chipset-WS`          |
| Graphics  | `C:\AMD-Graphics-WS`         |
| NPU       | `C:\AMD-NPU-WS`              |

If a 4th script is added (e.g. ROCm runtime, audio coprocessor), use `C:\AMD-<short>-WS\` with the same subdirectory layout (`download\`, `extracted\`, `patched\`, `cert\`).

---

## A.2 Source File Format

| Attribute        | Value                                                                              |
| ---------------- | ---------------------------------------------------------------------------------- |
| Encoding         | UTF-8 with BOM (`utf-8-bom`)                                                       |
| Line endings     | CRLF                                                                               |
| Tab style        | 4 spaces (no actual tab characters)                                                |
| PowerShell ver   | 5.1 minimum; 7.x supported                                                         |
| Required attrs   | `#Requires -Version 5.1` and `#Requires -RunAsAdministrator` at the top of each .ps1 |
| `param()` block  | Top-of-file `param()` with `[CmdletBinding()]`; mirror to `$Script:Foo` immediately |
| Static gate      | `tools/psa.py` must pass with 0 errors                                             |

### File structure (top-to-bottom)

```
1.  Header comment block (.SYNOPSIS / .DESCRIPTION / .PARAMETER / .EXAMPLE / .NOTES)
2.  #Requires directives
3.  [CmdletBinding()] + param() block
4.  Mirror params to $Script:Foo
5.  Script-scope state ($Script:ScriptVersion, $Script:ScriptTag, $Script:ScriptHash, ...)
6.  $Script:PhaseRegistry = @( [pscustomobject]@{ Id=...; Name=...; Group=...; Func=... }, ... )
7.  $Script:DetectedPlatform = @{ ... } (populated in P00/P03)
8.  $Script:PhaseResults = @{}
9.  Output helpers (Format-Elapsed, _LogLine, Write-Step/Ok/Warn2/Fail/Skip, Write-SubHeader, Write-PhaseHeader/Footer)
10. Environment helpers (Show-PowerShellEnvironment, Show-OperatingSystemDetail, Test-AdminPrivilege, Set-NetworkProtocol)
11. Phase orchestrator (Invoke-PhaseRunner, Get-PhaseListByAction, Show-PhaseList)
12. Domain helpers (script-specific: AMD platform detection, INF parser, installer resolution, etc.)
13. Phase implementations: Invoke-PrepPhase00_Initialize ... Invoke-InstPhase04_PostInstallVerification
14. Cleanup action (Invoke-Cleanup)
15. Main entry point (Invoke-MainEntryPoint)
16. Top-level try/finally dispatcher that prints Show-RunSummary regardless of exit path
```

---

## A.3 Banner & Version Identification

### Version string format

```powershell
$Script:ScriptVersion = '<short-name>-YYYY.MM.DD-rNN'
$Script:ScriptTag     = '<short-kebab-tag-describing-the-revision>'
```

Examples in production:

- `chipset-2026.05.09-r47` / tag `chipset-dedupe-matched-devices-r47`
- `graphics-2026.05.09-r16` / tag `graphics-dedupe-matched-devices-r16`
- `npu-2026.05.10-r2` / tag `npu-sister-aligned-r2`

### Self-fingerprint via SHA256

The script must hash its own file at startup and expose the first 12 hex chars. This appears in every phase header so logs are reproducible across script versions:

```powershell
$Script:ScriptHash = '(unknown)'
try {
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrEmpty($scriptPath)) { $scriptPath = $MyInvocation.MyCommand.Path }
    if ($scriptPath -and (Test-Path -LiteralPath $scriptPath)) {
        $hashFull = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
        $Script:ScriptHash = $hashFull.Substring(0, 12).ToLower()
    }
} catch {
    $Script:ScriptHash = '(hash-error)'
}
$Script:ScriptShortTag = ('v{0}/{1}' -f $Script:ScriptVersion, $Script:ScriptHash)
```

### Main entry banner

```
========================================================================
 <Script Display Name>
 Version: <ScriptVersion>  [<ScriptTag>]  SHA256: <ScriptHash>
 Action : <Action>
 Repo   : <RepoUrl>
========================================================================
```

Color: Cyan border, DarkCyan version / repo lines, White Action line. Width: 72 chars.

### Phase header / footer banner

Emitted by the dispatcher (`Invoke-PhaseRunner`), **never** by phase functions:

```
========================================================================
 PHASE P00 - Initialize                 (Prep  )  start: 14:23:05
 script: vnpu-2026.05.10-r2/09129eebb04b
========================================================================
... phase body output ...
 PHASE P00 -> DONE     elapsed: 0.45s
```

Color: Magenta border + entry line, DarkGray script-tag line. Status colors: Green=DONE, Red=FAILED, DarkGray=CACHED/SKIPPED.

---

## A.4 Phase Architecture (21 phases)

All three scripts share the same 21-phase model. Adding a 4th script means populating the same 21 phase functions; do NOT change phase count or IDs without a strong reason (and a SPEC.md revision).

### Numbering rules

```
P00 - P09   Prep phases   (10 phases, may extend if absolutely required)
V01 - V06   Verify phases (6 phases)
I00 - I04   Inst phases   (5 phases)
```

### Phase registry format (mandatory)

```powershell
$Script:PhaseRegistry = @(
    [pscustomobject]@{ Id='P00'; Name='Initialize';     Group='Prep';   Func='Invoke-PrepPhase00_Initialize' }
    [pscustomobject]@{ Id='P01'; Name='PrepareWorkspace'; Group='Prep'; Func='Invoke-PrepPhase01_PrepareWorkspace' }
    # ...
)
```

- **Type**: `[pscustomobject]@{...}` (plain `@{...}` hashtable is NOT acceptable — sister-script alignment).
- **Function naming**: `Invoke-{Prep|Verify|Inst}Phase{NN}_{Name}` (underscore, group-prefix style).
- **1:1 mapping**: each registry entry must have exactly one function definition; `psa.py` flags mismatches.

### Phase groups (semantic)

| Group  | Meaning                                                       |
| ------ | ------------------------------------------------------------- |
| Prep   | Acquisition & preparation of artifacts. No system-state change |
| Verify | Validation of artifacts + dry-run install plan. No system-state change |
| Inst   | Apply changes to host system (cert trust, WDAC policy, drivers) |

### Phase entry/exit contract

- The dispatcher renders `Write-PhaseHeader` before invoking the function and `Write-PhaseFooter` after.
- Phase functions never call `Write-PhaseHeader`/`Write-PhaseFooter` themselves.
- Phase functions may call `Write-SubHeader` (Cyan, Level-1) or `Write-SubHeader2` (DarkCyan, Level-2) for in-phase sectioning.

### Phase timing summary

Each phase result is recorded in `$Script:PhaseTimings` (`Add` of a `pscustomobject` with `Id`, `Status`, `Elapsed`, `EndedAt`). `Show-RunSummary` (run unconditionally in `finally`) prints the full table.

---

## A.5 Logging Conventions

### Markers (color-coded)

| Marker | Color    | Function       | Semantic            |
| ------ | -------- | -------------- | ------------------- |
| `[*]`  | Cyan     | `Write-Step`   | Action being taken  |
| `[+]`  | Green    | `Write-Ok`     | Success / positive  |
| `[!]`  | Yellow   | `Write-Warn2`  | Degraded / non-fatal|
| `[X]`  | Red      | `Write-Fail`   | Failure             |
| `[~]`  | DarkGray | `Write-Skip`   | No-op / cached      |

### Line format

```
[HH:mm:ss] [+X.XXs]   [marker] <message>
[HH:mm:ss]            [marker] <message>   ← when not inside a phase, no elapsed-tag
```

- `HH:mm:ss` is the current wall-clock time (host TZ).
- `[+X.XXs]` is the elapsed time since `$Script:CurrentPhaseStart` (reset on every phase entry).
- The marker / color combination is the only acceptable styling. Do not invent new markers (e.g. `[i]`, `[>]`, `[?]`); they break the visual scan pattern.

### Banner helpers (Level-0 / Level-1 / Level-2)

| Helper             | Color     | Width     | Use                                                                |
| ------------------ | --------- | --------- | ------------------------------------------------------------------ |
| `Write-PhaseHeader`| Magenta   | `=` × 72  | Phase entry banner (dispatcher only)                               |
| `Write-PhaseFooter`| Status    | (1 line)  | Phase exit footer (dispatcher only)                                |
| `Write-SubHeader`  | Cyan      | `=` × 72  | Level-1 in-phase banner (major section within a phase)             |
| `Write-SubHeader2` | DarkCyan  | `-` × 72  | Level-2 in-phase banner (finer subsection)                         |

### Console encoding

P00 must enforce `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` so that Japanese log strings render correctly on ja-JP Windows. (Without this, the default code page is 932 / Shift-JIS and Japanese garbles.)

### TLS hardening

P00 must enable TLS 1.2 + 1.3 (and degrade gracefully on PS 5.1 without TLS 1.3):

```powershell
[Net.ServicePointManager]::SecurityProtocol = `
    [Net.SecurityProtocolType]::Tls12 -bor `
    [Net.SecurityProtocolType]::Tls13 -bor `
    [Net.SecurityProtocolType]::Tls11 -bor `
    [Net.SecurityProtocolType]::Tls
```

---

## A.6 Parameter Conventions

### Common switches (use these names verbatim)

| Switch                       | Type     | Required | Description                                                       |
| ---------------------------- | -------- | -------- | ----------------------------------------------------------------- |
| `-Action`                    | string   | ✓        | `Prepare`/`Verify`/`PrepareVerify`/`Install`/`All`/`Cleanup`/`ListPhases` |
| `-OnlyPhases`                | string[] |          | Comma-separated phase IDs; overrides `-Action`-derived list       |
| `-CleanWorkRoot`             | switch   |          | Delete the workspace before starting                              |
| `-AllowWorkstationInstall`   | switch   |          | Permit Install on Workstation OS (default: blocked)               |
| `-UseTestSigning`            | switch   |          | Fall back to bcdedit testsigning (default: WDAC policy)           |
| `-WorkRoot`                  | string   |          | Workspace path override                                           |
| `-PfxPassword`               | string   |          | Self-signed PFX password (lab default: empty)                     |
| `-CertValidityYears`         | int      |          | Self-signed cert validity (default: 5)                            |

### Action -> Phase mapping (sister-script aligned)

```
Prepare       : Prep only
Verify        : Verify only
PrepareVerify : Prep + Verify    (default; no system-state change)
Install       : Inst only        (assumes Prep + Verify already ran)
All           : Prep + Verify + Inst   (full pipeline)
Cleanup       : (short-circuit, runs Invoke-Cleanup)
ListPhases    : (short-circuit, runs Show-PhaseList)
```

### Mutual exclusion

- `-OnlyPhases` overrides `-Action`-derived phase list.
- `-UseTestSigning` is mutually exclusive with the default WDAC policy path; warn if both states attempt to apply.
- NPU script's `-OfflineZip` takes priority over `-InstallerUrl` for Tier 4 short-circuit.

---

## A.7 Path Handling Rules

### The wildcard-interpretation hazard

PowerShell's `*-Path` cmdlets interpret `[`, `]`, `?`, `*` in paths as wildcards by default. INF filenames sometimes contain `[` (e.g. `oem_[stx].inf`), and AMD installer ZIPs can extract into paths with brackets. Always use `-LiteralPath` on:

```powershell
Test-Path -LiteralPath $path
Get-Item -LiteralPath $path
Remove-Item -LiteralPath $path
Copy-Item -LiteralPath $src -Destination $dst
Move-Item -LiteralPath $src -Destination $dst
Get-FileHash -LiteralPath $path
[System.IO.File]::ReadAllLines($path)  ← .NET APIs ignore wildcards by definition
```

### Cmdlets that do NOT support `-LiteralPath`

- `Invoke-WebRequest -OutFile` (PowerShell 5.1) does NOT accept `-LiteralPath`; the path is wildcard-interpreted. Workaround: download to a wildcard-free temp path (e.g. `<dir>\.dl_<GUID>.part`), then `Move-Item -LiteralPath` to the real destination.
- `Export-PfxCertificate`, `Export-Certificate`: take `-FilePath` (wildcard-safe in practice; AMD-CodeSign filenames have no brackets, so this is acceptable).

### Sanitization of derived filenames

When generating filenames from INF Provider strings or driver versions, strip / replace these characters: `/ \ : * ? " < > | [ ]`. Use:

```powershell
$safe = $raw -replace '[\/\\:*?"<>\|\[\]]', '_'
```

---

## A.8 Error & Diagnostic Conventions

### Three-tier diagnostic output

1. **Console**: marker-prefixed lines via `Write-Step/Ok/Warn2/Fail/Skip` (see A.5).
2. **CSV**: per-phase machine-readable artefacts under workspace (see A.9).
3. **Run summary**: `Show-RunSummary` (always runs in `finally`) prints PhaseTimings + total elapsed + ScriptHash.

### Failure category classification

Phase results in `$Script:PhaseResults` are tagged with one of:

| Status  | Meaning                                                                            |
| ------- | ---------------------------------------------------------------------------------- |
| `OK`    | Phase completed successfully                                                       |
| `FAIL`  | Phase raised an exception (caught by `Invoke-PhaseRunner`)                         |
| `SKIP`  | Phase was not selected by `-Action` / `-OnlyPhases` (displayed only in summary)    |

When `-Action Install` (or `All`) reaches the top-level try/catch with `$Script:TopLevelException`, the dispatcher exits with code `1`; otherwise `0`.

### Stack trace surface

On top-level exception, render the `.ScriptStackTrace` via `Write-Skip` lines so the user can copy the trace for issue reporting:

```powershell
foreach ($line in ($_.ScriptStackTrace -split "`n")) {
    Write-Skip ("    {0}" -f $line.TrimEnd())
}
```

---

## A.9 CSV Column Conventions

### `inf_inventory.csv` (P05 output, all three scripts)

| Column                | Type   | Notes                                                          |
| --------------------- | ------ | -------------------------------------------------------------- |
| `FileName`            | string | Required                                                       |
| `FullPath`            | string | Required                                                       |
| `Provider`            | string | From `[Version]` Provider                                      |
| `DriverVer`           | string | From `[Version]` DriverVer                                     |
| `Class`               | string | Device class                                                   |
| `HwidCount`           | int    | Total HWIDs in the INF                                         |
| `MatchesTargetNpu`    | bool   | NPU script only                                                |
| `MatchedHwidCount`    | int    | NPU script only (count of HWIDs matching target platform)      |
| `HasServerDecoration` | bool   | INF already has `ProductType=3`                                |
| `WorkstationDecCount` | int    | Workstation decoration count                                   |
| `ServerDecCount`      | int    | Server decoration count                                        |
| `NeedsPatch`          | bool   | `WorkstationDecCount > 0 -and ServerDecCount == 0`             |
| `SelectedForPipeline` | bool   | Pipeline filter pass-through                                   |
| `HwidPreview`         | string | First 3 HWIDs joined for human readability                     |

### CSV encoding

- Encoding: UTF-8 (no BOM).
- Quoting: PowerShell's default `Export-Csv -NoTypeInformation` behavior.
- Delimiter: `,` (comma).
- Line ending: CRLF (PowerShell default on Windows).

---

## A.10 Environment Evaluation (Phase P00)

P00 runs unconditionally and gathers the inputs that all downstream phases depend on:

### Step 0: PowerShell environment

`Show-PowerShellEnvironment` dumps:

- `PSVersion`, `PSEdition`, `PSCompatibleVersions`
- `CLRVersion`, `BuildVersion`, `OS`, `Platform`

Then hard-fails if `<5.1` or if not 64-bit.

### Step 1: Administrator privileges

`Test-AdminPrivilege` throws if not running elevated.

### Step 2: TLS hardening

`Set-NetworkProtocol` enables TLS 1.2 + 1.3 (degrades to TLS 1.2 on PS 5.1).

### Step 3: OS profile resolution

`Show-OperatingSystemDetail` resolves OS build → inf2cat `/os:` switch:

| Build  | Profile         | inf2cat /os:       |
| ------ | --------------- | ------------------ |
| 26100  | WS2025          | Server2025_X64     |
| 22631  | WS2022-equiv    | ServerFE_X64       |
| 22000  | WS2022-equiv    | ServerFE_X64       |
| 20348  | WS2022          | ServerFE_X64       |
| 19041  | WS2019-equiv    | ServerRS5_X64      |
| 17763  | WS2019          | ServerRS5_X64      |
| 14393  | WS2016          | Server2016_X64     |

### Step 4: ProductType detection

`ProductType = 1` (Workstation) emits the "WS2025 PRE-MIGRATION PREVIEW MODE" banner on build 26100. `ProductType = 3` (Server) proceeds without it.

---

## A.11 Static Analysis with psa.py

### Setup

```bash
# From repo root
python3 tools/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 tools/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
python3 tools/psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
```

### Required gate

Every commit must pass with **0 errors**. Warnings are allowed but should be triaged and either fixed or annotated as false positives.

### Check coverage (C1–C10)

| Code | Severity | Description                                                              |
| ---- | -------- | ------------------------------------------------------------------------ |
| C1   | error    | Brace balance (`{` vs `}`)                                               |
| C2   | error    | Paren balance (`(` vs `)`)                                               |
| C3   | error    | Bracket balance (`[` vs `]`)                                             |
| C4   | warning  | Undefined variable references (heuristic)                                |
| C5   | warning  | Auto-variable shadowing (`$args`, `$_`, `$matches`, etc.)                |
| C6   | warning  | `Start-Process -ArgumentList` (prefer `ProcessStartInfo` for spaces)     |
| C7   | warning  | `-match` against bare `$variable` (returns true if `$null`)              |
| C8   | info     | TODO / FIXME markers                                                     |
| C9   | warning  | Trailing backtick before empty line                                      |
| C10  | warning  | `-match` against empty string (always true)                              |

Exit codes: `0` = clean, `1` = warnings only, `2` = errors. Useful in CI.

### Known false positives

`C7 -match against bare $var` warnings inside null-guard blocks (e.g. `if ($var) { ... -match $var }`) are false positives — the guard already excludes the null case. These can be left as warnings.

---

## A.12 Bilingual Documentation

### File set

| English      | Japanese     | Content                                       |
| ------------ | ------------ | --------------------------------------------- |
| `README.md`  | `README.ja.md` | End-user documentation                       |
| `TESTING.md` | `TESTING.ja.md` | Cloud / physical regression testing         |
| `SPEC.md`    | `SPEC.ja.md`   | Developer specification (this document)     |

### Synchronization rule

Whenever the English version is updated, the Japanese version must be updated in the same commit (or in an immediate follow-up commit referencing the English commit hash). Maintain parity of:

- Section structure (same H2 / H3 headings)
- Tables (same columns)
- Code blocks (same content; Japanese files may use bilingual comments)
- Examples (same commands; localize the prose around them)

### Style for Japanese files

- Technical terms in English are preserved in their English form (do not translate "phase", "decoration", "WDAC policy", "Workstation", "Server SKU", etc.)
- Particles use full-width forms: 「、」 「。」「・」 not "," "."
- Brackets: 「」 for emphasized terms, ` `` ` for code spans

### Mandatory disclaimer and license sections

Each README must include:

1. A top-of-file ⚠️ Disclaimer block (USE AT YOUR OWN RISK, BitLocker warning, no warranty)
2. A bottom-of-file License section (MIT, with note that AMD's redistribution terms apply to AMD binaries downloaded at runtime, not to this repository)

---

## A.13 Development Workflow

### Iteration cycle

```
1. Write or modify code
2. python3 tools/psa.py <script>.ps1     ← gate: 0 errors required
3. Test on AWS EPYC EC2 (pipeline-only)  ← per TESTING.md §3
4. Test on real AMD hardware             ← per TESTING.md §4 (if available)
5. Update README (en + ja) + SPEC (en + ja) if behavior changed
6. Commit with revision number bump in $Script:ScriptVersion
```

### Revision discipline

Bump the revision number (e.g. `r47` → `r48`) on any commit that changes:

- Phase semantics (any of the 21 phases)
- Output format (CSV columns, log markers, banner layout)
- Parameter set (added / removed / renamed switches)

Cosmetic-only changes (typo fixes in messages, README rewording) do not require a revision bump.

### Reuse before invention

Before writing any new helper function:

1. Search the existing 3 scripts for an equivalent (`grep -rn 'function <NewName>' .`).
2. If found, copy verbatim from the most recent revision.
3. If not found, add it to the canonical helper section (under "Output helpers" or "Environment helpers" near the top of the file) so future scripts can reuse it.

---

# Part B — Script-specific Specifications

## B.1 Chipset script (`Deploy-AMDChipsetDriverOnWindowsServer.ps1`)

### Identification

- **Current revision**: `chipset-2026.05.13-r48` (tag: `chipset-cert-name-wdac-guid-r48`)
- **Workspace**: `C:\AMD-Chipset-WS\`
- **Self-signed cert subject**: `CN=AMD Chipset Driver Self-Sign (WS2025 Lab, At Own Risk)`
- **Self-signed cert files**: `cert\AMD-Chipset-Driver-CodeSign.{pfx,cer}` (r48+; pre-r48 used `AMD-Driver-CodeSign.{pfx,cer}`)
- **WDAC policy GUID** (r48+): fixed `503860EA-8837-4169-9BC4-19E5AEED721B`; overridable via `-WdacPolicyGuid`. Pre-r48 deploys used a dynamically-generated PolicyId recorded in `cert\AmdSuppPolicyId.txt`.
- **WDAC SupplementsBasePolicyID**: `{A244370E-44C9-4C06-B551-F6016E563076}` (Windows-shipped default base CI policy); overridable via `-WdacBasePolicyGuid`

### Inputs

- AMD Chipset Software installer EXE (~75 MB), discovered via probe of <https://www.amd.com/en/support/category/chipsets>
- Optional: `-InstallerUrl <url>` to bypass URL discovery
- Optional: `-AmdLandingUrls` / `-AmdFallbackUrl` for URL discovery override (used when AMD reorganises their support pages)

### Platform-detection logic

`Get-AmdChipsetPlatform` heuristic translates CPU name (`Win32_Processor.Name`) to a platform codename:

| CPU pattern                       | Codename       | Family    |
| --------------------------------- | -------------- | --------- |
| `Ryzen.*4\d00U?\b`                | Renoir         | 4000      |
| `Ryzen.*5\d00U?\b`                | Cezanne        | 5000      |
| `Ryzen.*5\d25\b`                  | Barcelo        | 5000      |
| `Ryzen.*5\d35\b`                  | Barcelo-R      | 5000      |
| `Ryzen.*6\d00U?\b`                | Rembrandt      | 6000      |
| `Ryzen.*7\d40\b`                  | Phoenix        | 7000      |
| `Ryzen.*8\d40\b`                  | Hawk Point     | 8000      |
| `Ryzen AI 3\d0`                   | Strix Point    | AI 300    |
| `Ryzen AI Max 3\d0`               | Strix Halo     | AI Max 300|

### Phase quirks

- **P03 / P04**: Installer EXE is extracted via 7-Zip; if extraction fails, fall back to launching the EXE silently and harvesting from `C:\AMD\`.
- **P05**: INFs are classified by source variant: `W11x64` (Win11) / `WTx64` (Workstation x64) / `WT6A_INF` / `WT64A`. Only the OS-matching variant is selected for the pipeline.
- **P06**: PSP driver (`amdpsp.inf`) is **never patched** without an explicit BitLocker warning — see Disclaimer §5.

### Known constraints

- 5-year cert validity (hard-coded in P07).
- Patched drivers retain their AMD-published `DriverDate`; comparing AS-IS vs TO-BE uses `.Date` truncation to avoid timezone false positives (see Part D D.1).

---

## B.2 Graphics script (`Deploy-AMDGraphicsDriverOnWindowsServer.ps1`)

### Identification

- **Current revision**: `graphics-2026.05.13-r17` (tag: `graphics-cert-name-wdac-guid-r17`)
- **Workspace**: `C:\AMD-Graphics-WS\`
- **Self-signed cert subject**: `CN=AMD Graphics Driver Self-Sign (WS2025 Lab, At Own Risk)`
- **Self-signed cert files**: `cert\AMD-Graphics-Driver-CodeSign.{pfx,cer}` (r17+; pre-r17 used `AMD-Driver-CodeSign.{pfx,cer}`)
- **WDAC policy GUID** (r17+): fixed `85336828-3080-41C5-81EC-FD587DC090D3`; overridable via `-WdacPolicyGuid`. Pre-r17 deploys used a dynamically-generated PolicyId recorded in `cert\AmdSuppPolicyId.txt`.
- **WDAC SupplementsBasePolicyID** (r17+): `{A244370E-44C9-4C06-B551-F6016E563076}` (Windows-shipped default base CI policy); overridable via `-WdacBasePolicyGuid`. Pre-r17 used a non-standard `{B355481F-55DA-5D17-C662-07127F674187}` (see Part D D.8).

### Inputs

- AMD Adrenalin Edition installer EXE (~600 MB), discovered via probe of <https://www.amd.com/en/support/category/graphics>
- Two branches: Vega-Polaris Legacy (~19 INFs) and Main Adrenalin (~67 INFs for Phoenix+).
- Optional: `-InstallerUrl <url>` to bypass URL discovery
- Optional: `-AmdLandingUrls` / `-AmdFallbackUrl` for URL discovery override

### Platform-detection logic

`Get-AmdGraphicsPlatform` uses `Win32_VideoController` enumeration first, then CPU name (for integrated GPUs). Branch selection (Vega-Polaris Legacy vs Main Adrenalin) is based on the GPU PCI Device ID range.

### Phase quirks

- **P03**: AMD periodically reorganises their support pages; probe failures emit detailed candidate URL list and fall back to `-InstallerUrl`.
- **P05**: HD Audio (`hdaudio.inf`), Audio CoProcessor (`acp.inf`), USB-C UCSI (`ucsi.inf`), and Display (`display.inf`) INFs are all included by default; some are conditionally skipped based on Win32_VideoController vendor.

### Known constraints

- HDMI Audio (`hdaudio.inf`) provider names vary across Adrenalin branches; the INF inventory filter uses Class = `MEDIA` rather than provider name for stability.

---

## B.3 NPU script (`Deploy-AMDNpuDriverOnWindowsServer.ps1`)

### Identification

- **Current revision**: `npu-2026.05.13-r3` (tag: `npu-cert-name-r3`)
- **Workspace**: `C:\AMD-NPU-WS\`
- **Self-signed cert subject**: `CN=AMD NPU Driver Self-Sign (WS2025 Lab, At Own Risk)`
- **Self-signed cert files**: `cert\AMD-NPU-Driver-CodeSign.{pfx,cer}` (r3+; pre-r3 used `AMD-NPU-CodeSign.{pfx,cer}`)
- **WDAC policy name**: `AMD-NPU-Driver-SelfSign-Lab`
- **WDAC policy GUID**: fixed `8B2C4F12-1E9D-4D7B-A4F8-9C7E2B6A53D1` (per-script stable hardcoded value, used to identify the policy across runs for clean removal); overridable via `-WdacPolicyGuid` (r3+)

### Inputs (4-tier resolution)

```
Tier 1 ★ : -InstallerUrl <url>                        explicit URL
Tier 2   : -AmdAccountUser/-AmdAccountPassword         account.amd.com auto-download (BEST-EFFORT, disabled by default)
Tier 3   : EULA-gated direct fetch probe               typically falls through
Tier 4 ★ : -OfflineZip <path>  OR  sibling NPU_RAI*_WHQL.zip  RECOMMENDED
```

Tier 4 (`-OfflineZip`) is the recommended pattern because account.amd.com is a JavaScript-driven SPA (verified 2026-05-10) and Tier 2 is unlikely to succeed without browser-based form interaction.

### NPU codename detection (PCI HWID + REV byte)

`Get-AmdNpuPlatform` uses `pnputil /enum-devices /bus PCI /deviceids` and matches against:

| Codename       | Short | PCI HWID                                   | CPU disambiguator      |
| -------------- | ----- | ------------------------------------------ | ---------------------- |
| Phoenix        | PHX   | `PCI\VEN_1022&DEV_1502&REV_00`             | Ryzen 7040 / `7\d40\b` |
| Hawk Point     | HPT   | `PCI\VEN_1022&DEV_1502&REV_00`             | Ryzen 8040 / `8\d40\b` |
| Strix Point    | STX   | `PCI\VEN_1022&DEV_17F0&REV_00/10/11`       | Ryzen AI 300 / AI Max 300 |
| Krackan Point  | KRK   | `PCI\VEN_1022&DEV_17F0&REV_20`             | Ryzen AI 200           |

Phoenix and Hawk Point share `DEV_1502&REV_00`; CPU name (`Win32_Processor.Name`) disambiguates them.

### Independent versioning axes (driver vs Ryzen AI Software)

NPU kernel driver versioning is **completely independent** from Ryzen AI Software versioning. AMD documents:

- **NPU drivers**: 32.0.203.280 (`NPU_RAI1.5_280_WHQL.zip`) or 32.0.203.314 (`NPU_RAI1.6.1_314_WHQL.zip`)
- **Ryzen AI Software**: 1.5 / 1.6.1 / 1.7 / 1.7.1 (latest)

Both NPU driver ZIPs work with current RAI 1.7.1. AMD recommends "always use the latest RAI Software" but does not couple the driver version.

The script exposes this as two independent parameters:

- `-NpuDriverPackage <NPU_RAI1.5_280 | NPU_RAI1.6.1_314 | latest>`
- `-RyzenAiSoftwareVersion <1.5 | 1.6.1 | 1.7 | 1.7.1 | latest>`

Compatibility evaluation is a **separate** axis (`Test-NpuDriverRaiCompatibility`) that asserts driver build >= minimum for the chosen RAI version (currently `32.0.203.280` for all RAI versions).

### Phase quirks

- **P00**: Emits NPU-specific OS support warning ("Ryzen AI Software is Windows-11-only per AMD docs").
- **P03**: Runs 4-tier installer resolution before NPU detection (because resolution determines the ZIP filename to download, which is independent of the host's NPU codename).
- **I00**: Requires explicit `I AGREE` confirmation for AMD Ryzen AI EULA (not optional).
- **I04**: Displays Ryzen AI Software guidance with installer download URL, prereqs, and verification steps (Miniforge + conda env + `quicktest.py`).

### Known constraints

- `account.amd.com` is a JavaScript-driven SPA; PowerShell form-POST authentication (Tier 2) is documented as best-effort and will likely fail. Always prefer Tier 4 (`-OfflineZip`).
- Ryzen AI Software (user-mode stack) is officially Windows-11-only; on Server 2025 the kernel driver loads but inference workloads may fail at the user-mode layer.

---

# Part C — Quality Gates & Validation Checklist

Every commit to `main` must satisfy the following gates.

## C.1 Static checks

- [ ] `python3 tools/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1` → 0 errors
- [ ] `python3 tools/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1` → 0 errors
- [ ] `python3 tools/psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1` → 0 errors

## C.2 Functional checks (per affected script)

- [ ] `-Action ListPhases` produces the expected 21-phase table.
- [ ] `-Action PrepareVerify -CleanWorkRoot` on AWS EPYC EC2 (or any non-target host) completes without errors using `-AssumeIfMissing` (NPU script) / appropriate platform override (chipset / graphics).
- [ ] `Show-RunSummary` is rendered regardless of exit path (success or failure).
- [ ] `Format-Elapsed` produces correct strings for `0.42s`, `1m2.3s`, `1h2m3s`.

## C.3 Documentation checks

- [ ] If a phase semantic changed: SPEC.md Part B is updated.
- [ ] If a parameter was added / removed / renamed: README.md and README.ja.md Parameters table is updated.
- [ ] If an output format changed: SPEC.md A.9 CSV columns and README.md Output files sections are updated.
- [ ] Japanese mirrors (`README.ja.md`, `TESTING.ja.md`, `SPEC.ja.md`) are in sync with English versions.

## C.4 Cross-script consistency checks

- [ ] All three scripts use `[pscustomobject]@{...}` in `$Script:PhaseRegistry` (not `@{...}`).
- [ ] All three scripts use sister-aligned function naming: `Invoke-{Group}Phase{NN}_{Name}`.
- [ ] All three scripts use the same `-Action` ValidateSet: `'Prepare','Verify','PrepareVerify','Install','All','Cleanup','ListPhases'`.
- [ ] All three scripts use the same marker semantics: `[*]` Cyan / `[+]` Green / `[!]` Yellow / `[X]` Red / `[~]` DarkGray.

---

# Part D — Known Pitfalls & Lessons Learned

These are documented so that future revisions do not regress on already-fixed issues.

## D.1 Chipset r46 — Timezone-induced DriverDate false positives

**Symptom**: V05 dry-run plan reported `[UPGRADE]` action on identical drivers because `Win32_PnPSignedDriver.DriverDate` is stored as UTC midnight, but `Get-CimInstance` converts to local time, producing a day-offset on `[datetime]` comparison.

**Fix**: In `Compare-InfDriverVer`, use `.Date` truncation (year/month/day only) on both the current driver date and the patched INF date before comparing.

```powershell
$cdate = if ($CurrentDate) { $CurrentDate.Date } else { $null }
$pdate = if ($PatchedDate) { $PatchedDate.Date } else { $null }
```

Preserved verbatim across chipset / graphics / NPU scripts.

## D.2 NPU r1 — Hypothetical filename `NPU_RAI1.7.1_380_WHQL.zip`

**Symptom**: Initial NPU script revisions used `NPU_RAI1.7.1_380_WHQL.zip` as the default filename, mapping it to RAI 1.7.1. However AMD's actual published filename for RAI 1.7.1 is **the same as for RAI 1.6.1**, namely `NPU_RAI1.6.1_314_WHQL.zip` (driver build 32.0.203.314).

**Fix**: NPU driver and Ryzen AI Software are versioned independently. The script now exposes them as two distinct parameters and the default `-NpuDriverPackage latest` resolves to `NPU_RAI1.6.1_314` (the newest documented). Verified against <https://ryzenai.docs.amd.com/en/latest/inst.html> 2026-04-19.

## D.3 NPU r2 — `Show-PhaseHeader` vs `Write-PhaseHeader` naming drift

**Symptom**: Early NPU revisions used `Show-PhaseHeader` (sister scripts used `Write-PhaseHeader`), and the phase entry banner color was Yellow `#`×78 (sister: Magenta `=`×72). This broke visual consistency across logs from multiple scripts run in sequence.

**Fix**: Sister-script alignment refactor (r2) renamed to `Write-PhaseHeader` and adopted Magenta `=`×72 + script-tag DarkGray line. Now identical across all three scripts.

## D.4 NPU — Action `'Install'` semantic drift

**Symptom**: NPU r1 mapped `-Action Install` to "all 21 phases" (full pipeline), while sister scripts mapped it to "Inst phases only" (assumes Prep + Verify already ran).

**Fix**: Sister-script alignment refactor (r2) corrected `-Action Install` to Inst-only and added `-Action All` for the full pipeline. Workstation OS guard now fires on both `Install` and `All`.

## D.5 ja-JP console encoding (chcp 932)

**Symptom**: Japanese log strings garble on default ja-JP Windows console (code page 932, Shift-JIS).

**Fix**: P00 enforces `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`. Operators using `*>&1 | Tee-Object` must also set the file encoding explicitly.

## D.6 `-LiteralPath` not supported on `Invoke-WebRequest -OutFile` (PS 5.1)

**Symptom**: When downloading to a path containing `[` or `]`, `Invoke-WebRequest -OutFile` (PS 5.1) wildcard-interprets the path.

**Fix**: Download to a wildcard-free temp filename (`<dir>\.dl_<GUID>.part`), then `Move-Item -LiteralPath` to the real destination. Pattern preserved in NPU script's `Invoke-NpuZipDownload`.

## D.7 Code-signing certificate filename standardization (Chipset r48 / Graphics r17 / NPU r3)

**Symptom**: Before the cross-script alignment commit, the three scripts used inconsistent code-signing certificate filenames:

| Script | Pre-fix filename | Reason for inconsistency |
| --- | --- | --- |
| Chipset | `cert\AMD-Driver-CodeSign.{pfx,cer}` | Original NPU-less repo where "AMD-Driver" was unambiguous |
| Graphics | `cert\AMD-Driver-CodeSign.{pfx,cer}` | Copy-pasted from chipset, same generic name |
| NPU | `cert\AMD-NPU-CodeSign.{pfx,cer}` | Authored later with a more specific name, but inconsistent with the older two |

This caused two operational problems:

1. **Side-by-side ambiguity**: A host running all three scripts had two `AMD-Driver-CodeSign.{pfx,cer}` files in different workspaces (`C:\AMD-Chipset-WS\cert\` and `C:\AMD-Graphics-WS\cert\`). Operators inspecting `Cert:\LocalMachine\Root` saw two unrelated certs with provider strings that didn't immediately reveal which script created them.
2. **Sister-script symmetry violation**: SPEC §A.1.4 mandates per-script `C:\AMD-<short>-WS\` workspace isolation. The cert filenames should follow the same per-script-prefix convention.

**Fix**: All three scripts standardised to `cert\AMD-{Chipset|Graphics|NPU}-Driver-CodeSign.{pfx,cer}`:

| Script | Post-fix filename | Path |
| --- | --- | --- |
| Chipset r48 | `AMD-Chipset-Driver-CodeSign.{pfx,cer}` | `C:\AMD-Chipset-WS\cert\` |
| Graphics r17 | `AMD-Graphics-Driver-CodeSign.{pfx,cer}` | `C:\AMD-Graphics-WS\cert\` |
| NPU r3 | `AMD-NPU-Driver-CodeSign.{pfx,cer}` | `C:\AMD-NPU-WS\cert\` |

**Upgrade impact on existing deploys**:

- Old `cert\AMD-Driver-CodeSign.{pfx,cer}` files remain on disk untouched after upgrade (Cleanup removes the cert from trust stores by thumbprint, not by filename).
- Running `-Action Install` with the new script will generate a fresh PFX/CER under the new name; the old PFX/CER is then orphaned in the workspace.
- For a clean upgrade, run `-Action Cleanup` on the old script revision **before** upgrading.

## D.8 WDAC supplemental policy GUID standardisation (Chipset r48 / Graphics r17 / NPU pre-existing)

**Symptom 1 (Chipset r47, Graphics r16 and earlier)**: The supplemental policy `PolicyID` was generated dynamically with `Set-CIPolicyIdInfo -ResetPolicyID`, producing a new GUID on every deploy. The GUID was persisted to `<workspace>\cert\AmdSuppPolicyId.txt` so that `Cleanup` could find it later.

This had two downsides:
- A re-deploy did not replace the previous deploy's policy slot — it created a *new* slot with a new GUID, accumulating dormant `<oldGuid>.cip` files in `C:\Windows\System32\CodeIntegrity\CiPolicies\Active\`.
- If `<workspace>\cert\AmdSuppPolicyId.txt` was lost (e.g. workspace deleted manually), `Cleanup` could not locate the deployed policy.

**Symptom 2 (Graphics r16 and earlier only)**: The script used `SupplementsBasePolicyID = '{B355481F-55DA-5D17-C662-07127F674187}'`, a non-standard GUID that does **not** correspond to any Microsoft-shipped CI base policy. Almost certainly a copy-paste artefact from earlier development. The chipset and NPU scripts both correctly used the Windows-default `{A244370E-44C9-4C06-B551-F6016E563076}`. The Graphics supplemental policy was therefore "supplementing" a non-existent base, which Windows may load with a warning or silently ignore.

**Fix (r48 / r17 / r3)**:

1. **Fixed default supplemental policy GUIDs** per script, unique per script so they coexist on a host with all three deployed:
   - Chipset: `503860EA-8837-4169-9BC4-19E5AEED721B`
   - Graphics: `85336828-3080-41C5-81EC-FD587DC090D3`
   - NPU: `8B2C4F12-1E9D-4D7B-A4F8-9C7E2B6A53D1` (pre-existing, unchanged)
2. **Operator override** via `-WdacPolicyGuid <GUID>`, accepted with or without braces. Two use cases:
   - **Legacy cleanup**: read the old PolicyId from `<workspace>\cert\AmdSuppPolicyId.txt` and pass it with `-Action Cleanup -WdacPolicyGuid <oldGuid>` to remove a pre-r48/r17 deploy. The new `Test-AmdWdacPolicyDeployed` also automatically falls back to reading the legacy marker file if the fixed GUID is not active, so unattended Cleanup on a legacy deploy still works without manual GUID lookup.
   - **Side-by-side**: deploy two copies of the same script with different GUIDs (rare).
3. **Graphics-only fix**: default `SupplementsBasePolicyID` corrected from `{B355481F-...}` to the Microsoft standard `{A244370E-...}`. Overridable via `-WdacBasePolicyGuid` for environments with custom base CI policies.
4. **Implementation detail**: PowerShell's `Set-CIPolicyIdInfo` has no `-PolicyId` switch; we patch the `<PolicyID>` element directly in the XML after `Set-CIPolicyIdInfo -SupplementsBasePolicyID …` (no longer pass `-ResetPolicyID`).

**Upgrade impact**: Same as D.7 — for a clean upgrade, run `-Action Cleanup` on the old script revision before deploying the new one. The new script's `Cleanup` action does detect legacy dynamic-GUID policies via the marker-file fallback, so an upgrade-then-cleanup also works (one extra cleanup cycle).

---

## Appendix: How to seed a new sister script from this SPEC

If you are creating a 4th script (e.g. `Deploy-AMDRocmRuntimeOnWindowsServer.ps1`):

1. Copy the most recent existing script (NPU r3 is the freshest sister-aligned reference) as your starting template.
2. Replace `$Script:ScriptName`, `$Script:ScriptVersion`, `$Script:ScriptTag`, `$Script:CertSubjectCn`, `$Script:WdacPolicyName`, `$Script:WdacPolicyGuid`, `$Script:WorkRoot` with values specific to your new script.
3. Re-implement only the **domain helpers** section (platform detection, installer resolution, INF inventory filter). Reuse all other sections verbatim.
4. Run `python3 tools/psa.py <new-script>.ps1` until 0 errors.
5. Add B.4 section to this SPEC.md (and SPEC.ja.md).
6. Add the new script to `README.md` "What's in the box" table, "Parameters" section, "Risk classification" table.
7. Add an AWS EPYC EC2 regression test scenario to `TESTING.md`.

The goal of the strict sister-script convention is exactly this: a new script should be ~80% boilerplate inheritance and ~20% novel logic.
