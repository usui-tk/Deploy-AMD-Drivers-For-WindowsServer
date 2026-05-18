# Developer Specification (SPEC)

> **Purpose of this document**
>
> This file is the authoritative specification for building and extending the
> four PowerShell scripts in this repository
> (`Deploy-AMDChipsetDriverOnWindowsServer.ps1`,
> `Deploy-AMDGraphicsDriverOnWindowsServer.ps1`,
> `Deploy-AMDNpuDriverOnWindowsServer.ps1`, and
> `Deploy-MSBthPanInboxOnWindowsServer.ps1`). It is written to be picked up
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
> known platform quirks of each of the four scripts. **Part C** documents
> the quality gates (`psa.py`, `TESTING.md`) that any change must pass.
> **Part D** preserves the historical lessons that the current
> implementation already accounts for.

> **Documentation language policy**: This SPEC is maintained in English
> only. Japanese readers should refer to the English SPEC together with
> the Japanese `README.ja.md` for an orientation. See
> `README.md` "Documentation language policy" for the repository-wide
> bilingual policy.

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
  - [A.12 Documentation Language Policy](#a12-documentation-language-policy)
  - [A.13 Development Workflow](#a13-development-workflow)
  - [A.14 UEFI Secure Boot Baseline (cross-script feature)](#a14-uefi-secure-boot-baseline-cross-script-feature)
- [Part B — Script-specific Specifications](#part-b--script-specific-specifications)
  - [B.1 Chipset script (`Deploy-AMDChipsetDriverOnWindowsServer.ps1`)](#b1-chipset-script-deploy-amdchipsetdriveronwindowsserverps1)
  - [B.2 Graphics script (`Deploy-AMDGraphicsDriverOnWindowsServer.ps1`)](#b2-graphics-script-deploy-amdgraphicsdriveronwindowsserverps1)
  - [B.3 NPU script (`Deploy-AMDNpuDriverOnWindowsServer.ps1`)](#b3-npu-script-deploy-amdnpudriveronwindowsserverps1)
  - [B.4 BthPan script (`Deploy-MSBthPanInboxOnWindowsServer.ps1`)](#b4-bthpan-script-deploy-msbthpaninboxonwindowsserverps1)
- [Part C — Quality Gates & Validation Checklist](#part-c--quality-gates--validation-checklist)
- [Part D — Known Pitfalls & Lessons Learned](#part-d--known-pitfalls--lessons-learned)

---

# Part A — Common Specification (reusable across all scripts)

## A.1 Reference Assets

These are the canonical sources of truth. **Pull from these directly; do not re-implement.**

### A.1.1 Reference scripts (phase / banner / log patterns)

```
Deploy-AMDChipsetDriverOnWindowsServer.ps1   (the most mature implementation)
Deploy-AMDGraphicsDriverOnWindowsServer.ps1  (graphics-specific platform detection)
Deploy-AMDNpuDriverOnWindowsServer.ps1       (NPU script with 4-tier installer resolution)
Deploy-MSBthPanInboxOnWindowsServer.ps1      (Microsoft inbox Bluetooth PAN driver enablement)
```

These 21-phase deployment scripts are the canonical source for:

- `Write-PhaseHeader` / `Write-PhaseFooter` / `Format-Elapsed`
- `Write-Step` / `Write-Ok` / `Write-Warn2` / `Write-Fail` / `Write-Skip`
- `Write-Detail` (continuation-line helper; see §A.5)
- `Write-SubHeader` / `Write-SubHeader2` (Level-1 / Level-2 in-phase banners)
- Banner block layout (Magenta `=` × 72, script-tag line, phase entry / exit)
- `Show-PowerShellEnvironment` (P00 environment dump)
- `Show-OperatingSystemDetail` (OS profile / build / inf2cat `/os:` resolution)
- `Test-AdminPrivilege` (hard-fail check on non-elevated session)
- `Set-NetworkProtocol` (TLS hardening)
- `Show-RunSummary` (per-action summary with PhaseTimings + ScriptHash)
- `Resolve-PerDeviceDriverDecision` / `Resolve-PerInfInstallDecision` (category-priority override; see §D.15)

When extending these scripts, **copy these helpers verbatim** from the most recent revision rather than re-implementing them.

### A.1.2 Static analyzer

```
psa.py  (obtained from the canonical artifact repository — see A.11)
```

`psa.py` is a **pure Python** static analyzer (no PowerShell installation required) with a **36-rule** check set spanning `PSA1001`..`PSA9002` plus the project-convention family `PSAP0001`..`PSAP0004`. The repository policy is to validate against the **latest mainline** `psa.py` from the canonical repository (see §A.11 for the rationale and workflow). It is **not** bundled in this repository. It is maintained as a single canonical artifact at:

```
https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer/psa.py
```

It must be:

- Reused as-is (do not fork or modify locally; contribute changes to the canonical repository instead)
- Obtained via `git clone` of `ai-generated-artifacts` **or** direct download of the single file (see A.11)
- Used as the gate before every commit

See A.11 for details.

### A.1.3 Companion specifications

- `README.md` / `README.ja.md` — end-user documentation (installation, quick start, troubleshooting). Both languages maintained.
- `TESTING.md` — physical-hardware validation results (English only)
- `CHANGELOG.md` — chronological per-release change log (English only)
- `CONTRIBUTING.md` — issue / PR conventions (English only)
- `SECURITY.md` — vulnerability reporting (English only)
- `CODE_OF_CONDUCT.md` — community behaviour (English only)

### A.1.4 Workspace path convention

Each script writes to a dedicated workspace path under `C:\Temp\Workspace_<vendor>-<short>\` to guarantee non-collision between scripts. All four workspaces are located under `C:\Temp\Workspace_*` (the script auto-creates `C:\Temp` on demand):

| Script    | Default workspace path                     | Pre-relocation path (deprecated) |
| --------- | ------------------------------------------ | -------------------------------- |
| Chipset   | `C:\Temp\Workspace_AMD-Chipset`            | `C:\AMD-Chipset-WS`              |
| Graphics  | `C:\Temp\Workspace_AMD-Graphics`           | `C:\AMD-Graphics-WS`             |
| NPU       | `C:\Temp\Workspace_AMD-NPU`                | `C:\AMD-NPU-WS`                  |
| BthPan    | `C:\Temp\Workspace_Microsoft-BthPan`       | `C:\MSBthPan-WS`                 |

If a 5th script is added (e.g. ROCm runtime, audio coprocessor), use `C:\Temp\Workspace_<vendor>-<short>\` with the same subdirectory layout (`download\`, `extracted\`, `patched\`, `cert\`, `logs\`, `.markers\`). The `Workspace_` prefix and `<vendor>-<short>` naming scheme keep all workspaces sorted contiguously when `C:\Temp` is listed.

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
| Static gate      | `psa.py` (see A.11) must pass with 0 errors                                        |

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

Format in production:

- ScriptVersion: `<vendor>-<yyyy.MM.dd>-r<NN>`
  (where `<vendor>` is one of `chipset`, `graphics`, `npu`, `msbthpan`)
- ScriptTag:     `<vendor>-<short-kebab-tag>-r<NN>`
  (kebab-cased summary of the revision's primary change)

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
$Script:ScriptShortTag = ('{0}/{1}' -f $Script:ScriptVersion, $Script:ScriptHash)
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
 script: npu-<yyyy.MM.dd>-r<NN>/<hash12>
========================================================================
... phase body output ...
 PHASE P00 -> DONE     elapsed: 0.45s
```

Color: Magenta border + entry line, DarkGray script-tag line. Status colors: Green=DONE, Red=FAILED, DarkGray=CACHED/SKIPPED.

---

## A.4 Phase Architecture (21 phases)

All four scripts share the same 21-phase model. Adding a 5th script means populating the same 21 phase functions; do NOT change phase count or IDs without a strong reason (and a SPEC.md revision).

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
- **1:1 mapping**: each registry entry must have exactly one function definition; `psa.py` (see A.11) flags mismatches.

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

### Continuation / detail lines (Write-Detail)

Some output blocks (section-banner tables in `Show-PowerShellEnvironment`, `Show-OperatingSystemDetail`, `Show-SecureBootBaselineSnapshot`, P03 platform inventory, P05 INF inventory rows, V05 Dry-Run details, V06 hardware-impact rows, I00 review tables, etc.) emit lines that are visually subordinate to a preceding marker line or that fit naturally inside a `===` / `---` banner block. These lines do not need their own timestamp + marker prefix; doing so creates redundant noise and breaks the visual table layout.

For these cases use the dedicated helper:

| Helper          | Indent | Color (default) | Use                                                                                |
| --------------- | ------ | --------------- | ---------------------------------------------------------------------------------- |
| `Write-Detail`  | 4 sp.  | Gray            | Continuation row of a marker line, or interior row of a section-banner block       |

`Write-Detail` is the single sanctioned exception to the "every line has a marker" rule. It always prepends exactly 4 spaces and supports an optional `-Color <ConsoleColor>` parameter (defaulting to `Gray`) and a `-NoNewline` switch for label-then-value composition.

**Forbidden**: bare `Write-Host "    ..."` calls. All such call sites have been migrated to `Write-Detail`. Adding a new bare 4-space `Write-Host` is a SPEC violation and will be rejected in review.

### Banner helpers (Level-0 / Level-1 / Level-2)

| Helper             | Color     | Width     | Use                                                                |
| ------------------ | --------- | --------- | ------------------------------------------------------------------ |
| `Write-PhaseHeader`| Magenta   | `=` × 72  | Phase entry banner (dispatcher only)                               |
| `Write-PhaseFooter`| Status    | (1 line)  | Phase exit footer (dispatcher only)                                |
| `Write-SubHeader`  | Cyan      | `=` × 72  | Level-1 in-phase banner (major section within a phase)             |
| `Write-SubHeader2` | DarkCyan  | `-` × 72  | Level-2 in-phase banner (finer subsection)                         |

### Console encoding

P00 must enforce all THREE console encodings to UTF-8 so that:

1. **Japanese log strings** written via `Write-Host` render correctly on ja-JP Windows (otherwise the default code page is 932 / Shift-JIS and Japanese garbles).
2. **External tool stdout** captured via `& tool ... | Out-String` is decoded as UTF-8. CiTool.exe and modern signtool.exe write UTF-8 on Windows Server 2025, and without this setting their Japanese output renders as mojibake like `蜃ｦ逅・・謌仙粥縺励∪縺励◆` (the UTF-8 byte sequence of `処理が成功しました` interpreted as cp932).
3. **PowerShell-to-native stdin** pipes (`$json | tool.exe`) send UTF-8 bytes to the external tool.

The canonical implementation, defined as a dedicated helper `Set-ConsoleUtf8` and called from P00 immediately after `Set-Tls12` (chipset/graphics) or `Set-NetworkProtocol` (NPU):

```powershell
function Set-ConsoleUtf8 {
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch { }
    try { Set-Variable -Name OutputEncoding -Scope Global -Value ([System.Text.Encoding]::UTF8) -ErrorAction SilentlyContinue } catch { }
}
```

The `try/catch` wrappers handle pinned-redirected console hosts (e.g. CI runners writing to a file with no real console) where the assignment may throw. See SPEC §D.16 for the root-cause analysis (CiTool.exe mojibake on ja-JP WS2025).

### TLS hardening

P00 must enable TLS 1.2 + 1.3 (and degrade gracefully on PS 5.1 without TLS 1.3):

```powershell
[Net.ServicePointManager]::SecurityProtocol = `
    [Net.SecurityProtocolType]::Tls12 -bor `
    [Net.SecurityProtocolType]::Tls13 -bor `
    [Net.SecurityProtocolType]::Tls11 -bor `
    [Net.SecurityProtocolType]::Tls
```

### Run log capture (`-LogFile`)

The four scripts expose a `-LogFile <path>` parameter that activates a script-internal `Start-Transcript` / `Stop-Transcript` pair. This is the canonical mechanism for retaining a run log; it supersedes the legacy `... *>&1 | Tee-Object -FilePath ...` idiom for two reasons:

1. **Coloring preservation.** `Tee-Object` on the outside of the pipeline captures the Write-Host output as the host stream is reduced to the pipeline value stream, which strips the `-ForegroundColor` decoration. `Start-Transcript` does not — the interactive console keeps its color, and the file gets every stream as plain text.
2. **Stream completeness.** `Start-Transcript` captures all of Output / Host / Error / Warning / Verbose / Debug. `Tee-Object` on `*>&1` captures the merged value stream, but does not preserve the per-stream metadata.

Canonical implementation pattern (mirror across all four sister scripts):

```powershell
# Param block (after -WorkRoot, before -PfxPassword)
[string]$LogFile       = '',

# Section 0.25, immediately after $Script:ScriptShortTag is set, before any
# Write-Host call that should be captured.
$Script:LogFileActive = $false
if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
    try {
        $logDir = Split-Path -LiteralPath $LogFile -Parent
        if (-not [string]::IsNullOrWhiteSpace($logDir) -and -not (Test-Path -LiteralPath $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null
        }
        try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
        Start-Transcript -Path $LogFile -Append -Force -ErrorAction Stop | Out-Null
        $Script:LogFileActive = $true
        Register-EngineEvent -SourceIdentifier PowerShell.Exiting -SupportEvent -Action {
            try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
        } | Out-Null
        Write-Host ("[*] Transcript -> {0}" -f $LogFile) -ForegroundColor DarkGreen
    } catch {
        Write-Warning ("Failed to start transcript at '{0}': {1}" -f $LogFile, $_.Exception.Message)
        $Script:LogFileActive = $false
    }
}

# Top-level finally block (must also call this even if the script throws)
finally {
    if ($Script:LogFileActive) {
        try { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null } catch { }
        $Script:LogFileActive = $false
    }
}
```

Required behaviour:

- **Parent directory auto-create**: the script creates the parent of `-LogFile` on demand (`New-Item -ItemType Directory -Force`). `C:\Temp\` is the canonical recommended parent and is auto-created if missing.
- **Append mode**: `Start-Transcript -Path $LogFile -Append -Force` so concurrent re-runs accumulate, not truncate. Operators that want a fresh file must include a timestamp in the filename (see filename convention below) or delete the file beforehand.
- **Defensive pre-stop**: call `Stop-Transcript -ErrorAction SilentlyContinue` before `Start-Transcript` to release any in-flight transcript from a previous run in the same PowerShell host (otherwise `Start-Transcript` fails with "transcription has already been started").
- **Two-tier cleanup**: register a `PowerShell.Exiting` engine event handler as a fallback, in addition to the top-level `finally` block. The handler catches the case where the script bails before reaching the `finally` (e.g. parameter validation error post-Start-Transcript).
- **Failure mode**: a `Start-Transcript` failure must NOT prevent the script from running. Emit a `Write-Warning` and continue with the transcript disabled (`$Script:LogFileActive = $false`).

Recommended filename convention:

```
C:\Temp\<scripttag>_<Action>_<yyyyMMdd-HHmmss>.log
```

Where `<scripttag>` is `amd-chipset` / `amd-graphics` / `amd-npu` / `ms-bthpan`. The timestamp suffix prevents same-Action re-runs from appending to the previous file when that is not desired.

Operators on a ja-JP host with the default cp932 console code page who pipe `-LogFile` output through a downstream tool must still set the consuming tool's file encoding to UTF-8 (the script's `Set-ConsoleUtf8` in P00 enforces UTF-8 for `[Console]::OutputEncoding`, but text editors / `Get-Content` on the captured file may default to cp932 / Shift-JIS).

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
| `-WorkRoot`                  | string   |          | Workspace path override (default: `C:\Temp\Workspace_<vendor>-<short>`) |
| `-LogFile`                   | string   |          | Capture full console transcript via `Start-Transcript`. See §A.5 |
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

### `inf_inventory.csv` (P05 output, all four scripts)

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

### Version policy

The repository validates its PowerShell scripts against the **latest mainline** `psa.py` from the canonical repository. Pinning to a fixed SemVer (e.g. "I tested with `psa.py` 3.3.0") is **not supported** as a development or CI strategy:

- New `psa.py` releases may add opt-in rules (the `PSAPxxxx` family) that surface previously-hidden discipline violations.
- New `psa.py` releases may tighten heuristics for existing rules.
- A previously-clean codebase under an older `psa.py` is **not** evidence of correctness under the current `psa.py`. It must be re-validated.

This SPEC, `TESTING.md`, `CONTRIBUTING.md`, and `README.md` therefore avoid pinning `psa.py` to a specific version number in forward-looking text. References to a specific version are acceptable only in `CHANGELOG.md` (which is rNN/version-by-design and records *which* `psa.py` version produced *which* baseline) and in `psa.py`'s own `CHANGELOG.md`.

#### How to discover the current mainline version

The canonical source of truth for "what is the current `psa.py` version on mainline" is the `VERSION` file sitting next to `psa.py` in the canonical repository:

```
ai-generated-artifacts/scripts/python/powershell-static-analyzer/
├── psa.py        ← __version__ string inside
├── VERSION       ← single ASCII line, no leading 'v', terminating LF
├── SPEC.md
├── CHANGELOG.md
└── README.md
```

Three equivalent retrieval methods (any of them works; pick the one that fits your environment):

```bash
# Method 1 — remote HTTP GET, no clone, no Python (recommended for CI / one-off checks).
LATEST=$(curl -sSL https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/VERSION)
echo "Latest psa.py on mainline: $LATEST"

# Method 2 — already cloned (e.g., sister repository checkout next to this one).
LATEST=$(cat /path/to/ai-generated-artifacts/scripts/python/powershell-static-analyzer/VERSION)

# Method 3 — invoke a local copy of psa.py (requires Python).
LATEST=$(python3 /path/to/psa.py --version | awk '{print $2}')
```

The three methods MUST agree: `psa.py` runs a startup self-check that compares its `__version__` against the sibling `VERSION` file and warns to stderr if they differ.

#### LLM / AI workflow for adopting a new version

When an LLM / AI maintainer (or a human) is about to make changes to **any** of the four PowerShell scripts in this repository, the very first step of the development cycle MUST be:

1. **Fetch the current mainline version**: run Method 1 above to get `LATEST`.
2. **Compare with the local copy actually being used**: read `__version__` from the local `psa.py`, or run `python3 /path/to/local/psa.py --version`. Call this `LOCAL`.
3. **If `LATEST != LOCAL`**:
   1. Replace `psa.py` AND its sibling `VERSION` file from mainline (both files MUST move together):
      ```bash
      curl -sSL https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py -o psa.py
      curl -sSL https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/VERSION -o VERSION
      ```
   2. Read the new entries in the canonical [`psa.py` `CHANGELOG.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/python/powershell-static-analyzer/CHANGELOG.md) and the current canonical [`psa.py` `SPEC.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/python/powershell-static-analyzer/SPEC.md) to understand what changed (new rules, tightened heuristics, schema changes).
   3. Re-evaluate this repository's `.psa.config.json` `enable` list against the latest `psa.py` `SPEC.md`. Newly-added opt-in rules that match the four pipeline scripts' discipline goals SHOULD be enabled (this repository currently opts in to all four PSAPxxxx rules).
   4. Re-run the full static-analysis pass for all four scripts under the new `psa.py`. Treat any new findings as regressions to be addressed in the same change set, not as findings to be deferred.
4. **If `LATEST == LOCAL`**: proceed with the planned change, but still re-run the analyzer on the modified scripts before declaring done.

This workflow makes the "latest mainline" rule machine-actionable: an LLM that has read this section can derive a deterministic sequence of `curl`, comparison, fetch, and re-test steps for any task that touches PowerShell code in this repository.

For the full policy rationale and additional context, see the [psa.py Versioning Policy](https://github.com/usui-tk/ai-generated-artifacts/blob/main/README.md#psapy-versioning-policy) section of the canonical repository's `README.md`.

### Canonical source

`psa.py` is **not bundled in this repository**. It is maintained as a single canonical artifact in a separate repository:

```
Repository : https://github.com/usui-tk/ai-generated-artifacts
Path       : scripts/python/powershell-static-analyzer/psa.py
Raw URL    : https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py
```

Any change to `psa.py` (bug fix, new check, new auto-variable entry, etc.) must be made in that canonical repository. This repository (`Deploy-Drivers-For-WindowsServer`) is one of its **consumers**.

### Setup

Pick one of the two methods below. Both are equivalent in result; the choice is operator preference.

**Method 1 — Clone the canonical repository as a sibling directory** (recommended for ongoing development):

```bash
# From the parent directory of this repository
git clone https://github.com/usui-tk/ai-generated-artifacts.git

# Then, from this repository's root:
python3 ../ai-generated-artifacts/scripts/python/powershell-static-analyzer/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 ../ai-generated-artifacts/scripts/python/powershell-static-analyzer/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
python3 ../ai-generated-artifacts/scripts/python/powershell-static-analyzer/psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
python3 ../ai-generated-artifacts/scripts/python/powershell-static-analyzer/psa.py Deploy-MSBthPanInboxOnWindowsServer.ps1
```

**Method 2 — Download the single file** (recommended for one-shot CI runs):

```bash
# From the repository root (Linux / macOS)
curl -sSLO https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py
python3 psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
python3 psa.py Deploy-MSBthPanInboxOnWindowsServer.ps1
```

```powershell
# Or, from the repository root (Windows PowerShell)
Invoke-WebRequest `
    -Uri  "https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py" `
    -OutFile psa.py
python3 psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
python3 psa.py Deploy-MSBthPanInboxOnWindowsServer.ps1
```

The rest of this SPEC, and `TESTING.md` / `CONTRIBUTING.md`, write `python3 psa.py <script>.ps1` as shorthand. This assumes `psa.py` has been obtained via either method and is accessible on a path of your choice.

### Required gate

Every commit must pass with **0 errors**. Warnings and info entries are
allowed but must match the documented baseline in §A.11.5 below. Any new
warning that is not in the baseline must be triaged and either fixed, given
an inline suppression with a justification (`# psa-disable-line <CODE> -- <reason>`),
or — for genuinely new findings — be added to the baseline in this SPEC.

For automated gating, the recommended CI filter is `--severity error`:

```bash
python3 psa.py --severity error Deploy-AMDChipsetDriverOnWindowsServer.ps1
# Exit code 0 = no errors. Warnings and info do not gate the build.
```

### Rule coverage (36 rules)

`psa.py` ships with a **36-rule** check set grouped into **nine categories**. The PSA8xxx, PSA9xxx, and PSAPxxxx families were added in 3.2.0; PSAP0003 and PSAP0004 were added in 3.3.0. The older PSA1xxx–PSA7xxx families are unchanged in scope. (See the canonical [psa.py `CHANGELOG.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/python/powershell-static-analyzer/CHANGELOG.md) for the full per-version history; this repository validates against the latest mainline — see the Version policy subsection above.)

| Category                                  | Code range            | Examples                                                                                                                                                                                                                                                              |
| ----------------------------------------- | --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Syntax balance                            | `PSA1001`..`PSA1003`  | brace / paren / bracket balance                                                                                                                                                                                                                                       |
| Semantics                                 | `PSA2001`..`PSA2006`  | undefined variable, auto-variable shadowing, `-match` against bare variable, `$null` on the right of `-eq`/`-ne`, assignment / redirection inside conditional                                                                                                         |
| Coding pattern                            | `PSA3001`..`PSA3005`  | `Start-Process -ArgumentList`, trailing backtick before empty line, `-match` against empty string, empty `catch` block, `Start-Transcript -Path` should be `-LiteralPath`                                                                                            |
| Hygiene                                   | `PSA4001`..`PSA4004`  | unfinished markers, trailing whitespace, long line, trailing semicolon                                                                                                                                                                                                |
| Security                                  | `PSA5001`..`PSA5004`  | plain-text password parameter, `Invoke-Expression`, broken hash algorithm, hardcoded `ComputerName`                                                                                                                                                                   |
| Best practice                             | `PSA6001`..`PSA6006`  | non-approved verb, cmdlet alias, plural function noun, `$global:` definition, mandatory parameter with default, switch defaulting to `$true`                                                                                                                          |
| File format                               | `PSA7001`             | missing UTF-8 BOM on `.ps1` (Windows PowerShell 5.1 ja-JP falls back to Shift-JIS / cp932 without BOM)                                                                                                                                                                 |
| Cross-file consistency                    | `PSA8001`             | function body hash drift across files in the same scan — enforces that shared helper functions (`Format-Elapsed`, `Write-Detail`, `Start-DebugTrace` family, etc.) stay byte-for-byte synchronised across the four pipeline scripts                                   |
| Complexity metrics                        | `PSA9001`..`PSA9002`  | function-body length threshold (default off, tunable via `max_function_lines`), external-process invocation without `$LASTEXITCODE` check (default off)                                                                                                              |
| Project / pipeline conventions            | `PSAP0001`..`PSAP0004` | phase function naming convention (`Invoke-(Prep\|Verify\|Inst)PhaseNN_Name`), required script-identifier variables, **new in 3.3.0:** inline `# rNN:` revision-tag comments (`PSAP0003`), end-of-file `REVISION HISTORY` blocks (`PSAP0004`). **All PSAPxxxx rules are off by default**; opt in via `.psa.config.json`. This repository opts in to all four. |

For the authoritative specification of every rule (severity, examples,
suppression guidance), see
`https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/python/powershell-static-analyzer/SPEC.md`
§4.

Exit codes: `0` = clean (or `--severity error` filter passing), `1` =
warnings/info present, `2` = errors. The default `--severity` floor is
`info`.

### Project-local `.psa.config.json` (canonical for this repository)

This repository ships its own `.psa.config.json` at the repository root. It is the **canonical configuration for the four pipeline scripts** and does the following:

1. **Opts in to `PSAP0001`, `PSAP0002`, `PSAP0003`, and `PSAP0004`** so that the 21-phase naming convention (`Invoke-(Prep|Verify|Inst)PhaseNN_DescriptiveName`), the script-identity trio (`$Script:ScriptVersion` / `$Script:ScriptHash` / `$Script:ScriptShortTag`), and the revision-discipline rules (no inline `# rNN:` revision-tag comments, no in-script `REVISION HISTORY` blocks — per-revision history lives exclusively in `CHANGELOG.md`) are all enforced.

2. **Configures `PSA8001` (cross-file function-body drift)** with `psa8001_ignore_functions`, listing roughly 45 function names that are intentionally per-script (phase functions matched via regex `^Invoke-(Prep|Verify|Inst)Phase\d{2}_`, plus per-driver-family helpers such as `Show-Help`, `Show-PhaseList`, `Find-KitTool`, `Expand-AmdInstaller`, etc.). Shared helpers NOT listed there MUST stay byte-for-byte identical across all four scripts.

3. **Disables `PSA4003` (long line)** because the pipeline scripts intentionally use multi-clause `-f` format strings (Show-PowerShellEnvironment table, per-device AS-IS / TO-BE analysis tables) that exceed 120 columns for readability of the resulting console output.

The canonical invocation is therefore:

```bash
python3 path/to/psa.py --config ./.psa.config.json \
    Deploy-AMDChipsetDriverOnWindowsServer.ps1 \
    Deploy-AMDGraphicsDriverOnWindowsServer.ps1 \
    Deploy-AMDNpuDriverOnWindowsServer.ps1 \
    Deploy-MSBthPanInboxOnWindowsServer.ps1
```

All four scripts MUST be passed in a single invocation for PSA8001 cross-file analysis to work. `psa.py` auto-discovers `.psa.config.json` in the current working directory, so when run from the repository root the `--config` flag may be omitted.

### A.11.5 Documented baseline (warnings and info)

This repository has the following **accepted** warning / info baseline
(see [CHANGELOG.md](./CHANGELOG.md) for the most recent verified counts).
Any deviation from these counts must be explained in the commit message
and either added here or fixed.

| Script                                          | Errors | Warnings | Info | Total |
| ----------------------------------------------- | -----: | -------: | ---: | ----: |
| `Deploy-AMDChipsetDriverOnWindowsServer.ps1`    |  **0** |    **0** |  **0** |   **0** |
| `Deploy-AMDGraphicsDriverOnWindowsServer.ps1`   |  **0** |    **0** |  **0** |   **0** |
| `Deploy-AMDNpuDriverOnWindowsServer.ps1`        |  **0** |    **0** |  **0** |   **0** |
| `Deploy-MSBthPanInboxOnWindowsServer.ps1`       |  **0** |    **0** |  **0** |   **0** |

The 2026-05-18 release is the **first revision where the canonical static-analysis baseline is fully clean across all four scripts simultaneously** (with the canonical `.psa.config.json` as documented above).

How the previously-documented findings were resolved in this sync:

| Rule                                       | Prior totals (per script)       | Resolution applied                                                                                                                                                                                                                                                                            |
| ------------------------------------------ | -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `PSA1001` (brace balance, error)           | 1 / 1 / 0 / 0                    | Resolved by the **psa.py 3.2.0 tokenizer fix** (PowerShell `""` double-quote-doubling escape and the `` `` `` double-backtick escape are now handled correctly). No script-side change was required.                                                                                          |
| `PSA2001` (undefined variable, error)      | 7 / 7 / 0 / 2                    | Resolved by **psa.py 3.2.0 scope-qualifier handling** (`$Script:`, `$global:`, `$local:`, `$private:` are now treated as runtime-deferred and never reported as undefined). No script-side change was required.                                                                              |
| `PSA4001` (TODO / FIXME marker, info)      | 1 / 1 / 0 / 1                    | Resolved by **psa.py 3.2.0 marker-matching tightening** (the analyzer now requires a colon or whitespace-then-letter after the marker, and ignores embedded string literals like `"XXX"` inside comments). No script-side change was required.                                                |
| `PSA2002` (unused parameter, w.)           | 0 / 0 / 0 / 3                    | Fixed in an earlier MSBthPan revision: three `$args` shadow assignments at L7556 / L7685 / L8863 (inf2cat / signtool / pnputil invocations) renamed to `$cmdArgs`.                                                                                                                                            |
| `PSA2003` (-match against bare variable)   | 6 / 7 / 4 / 4                    | Annotated inline with `# psa-disable-line PSA2003 -- pattern variable is initialized in the enclosing scope; $null impossible by construction`. Pattern variables are local constants, never `$null`.                                                                                          |
| `PSA3001` (Start-Process -ArgumentList)    | 4 / 3 / 0 / 9                    | Annotated inline with `# psa-disable-line PSA3001 -- Start-Process -ArgumentList is the canonical pattern for invoking signtool/inf2cat/pnputil with explicit args`.                                                                                                                          |
| `PSA3004` (empty `catch`, w.)              | 31 / 31 / 13 / 29                | Annotated inline with `# psa-disable-line PSA3004 -- intentional best-effort cleanup; no error to surface`.                                                                                                                                                                                   |
| `PSA3005` (Start-Transcript -Path, w.)     | 3 / 3 / 3 / 3 (new rule)         | Annotated inline with `# psa-disable-line PSA3005 -- deliberate cascade of -Path vs -LiteralPath variants for transcript-handle fallback`. The `logSetupForms` cascade in `Show-PowerShellEnvironment` legitimately tests both `-Path` and `-LiteralPath` forms.                              |
| `PSA4004` (trailing semicolon, info)       | 31 / 37 / 0 / 31                 | Auto-fixed by mechanical deletion of trailing `;` from end-of-line statements (outside strings / comments only). 98 deletions across the three affected scripts.                                                                                                                              |
| `PSA6003` (plural function noun, w.)       | 14 / 15 / 13 / 16                | Annotated inline with `# psa-disable-line PSA6003 -- compound noun (e.g., Policies, Drivers, Catalogs) is semantically plural for set-returning helpers`. Renaming would be a breaking API change against published pipeline phase names.                                                    |
| `PSA8001` (function-body drift, new)       | n/a (rule new in 3.2.0)          | All shared helper functions are now byte-for-byte identical across the four scripts. Per-script functions (phase functions, `Show-Help`, etc.) are listed in `psa8001_ignore_functions` in `.psa.config.json`. The `[CmdletBinding()] param()` declaration on AMDNpu's `Set-ConsoleUtf8` was removed to match the canonical body in the other three scripts. |
| `PSAP0001` (phase naming, new opt-in)      | n/a (rule new in 3.2.0)          | All 21 phase functions match `Invoke-(Prep\|Verify\|Inst)PhaseNN_DescriptiveName`. The single non-phase function with an `Invoke-` prefix (AMDNpu `Invoke-PhaseRunner`, the phase dispatcher) is annotated `# psa-disable-line PSAP0001 -- ... is the phase dispatcher, not a phase itself`.    |
| `PSAP0002` (script-identifier trio, new)   | n/a (rule new in 3.2.0)          | All four scripts assign `$Script:ScriptVersion`, `$Script:ScriptHash`, and `$Script:ScriptShortTag` early in the SECTION 0 (Constants / Identity) block; this requirement is met by the current mainline and survives the sync.                                                       |

**Note on PSA5001 (plaintext password, error)**: previously reported as 1 / 1 / 3 errors. As of the psa-baseline-sync revision these were all suppressed inline at the `param()` declaration site, because the value flows to `signtool.exe /p` and `X509Certificate2(.., String)` — both of which require a plaintext `String` at the API boundary. The inline justification comments explain the design intent at each site. The 2026-05-18 sync preserves these suppressions unchanged.

### A.11.5b Shared-helper contract (PSA8001-enforced)

PSA8001 (cross-file function-body drift) enforces that **34 helper functions** are byte-for-byte identical across all four pipeline scripts. The current contract surface (see [CHANGELOG.md](./CHANGELOG.md) for the verified baseline):

**Logging primitives (12 functions)**

`Format-Elapsed`, `_LogLine`, `Write-Step`, `Write-Ok`, `Write-Warn2`, `Write-Fail`, `Write-Skip`, `Write-Detail`, `Write-PhaseHeader`, `Write-PhaseFooter`, `Get-PhaseElapsedTag`, `Format-DebugFailure`

**DebugTrace framework (12 functions)**

`_DebugTrace_NextSeq`, `_DebugTrace_Now`, `_DebugTrace_WriteJsonlLine`, `_DebugTrace_RetireFrame`, `Start-DebugTrace`, `Stop-DebugTrace`, `Set-DebugStep`, `Write-DebugFailureReport`, `Enable-DebugTraceFileOutput`, `Disable-DebugTraceFileOutput`, `Get-DebugTraceFileOutputStatus`, `Enable-AutoExportOnPhaseFailure`

**Environment / preflight (5 functions)**

`Set-Tls12`, `Set-ConsoleUtf8`, `Assert-Admin`, `Assert-PowerShellCompatibility`, `Show-PowerShellEnvironment`

**Secure Boot baseline diagnostic helpers (5 functions)**

`Format-SecureBootBaselineForReport`, `Get-SecureBootCertificateInventory`, `Get-MsSecureBootExampleScriptPath`, `Invoke-MsSecureBootDetectScript`, `Export-DebugTraceJson`

**Verifying the contract locally**: run psa.py against all four scripts in a single invocation. Any drift in the 34 functions above will produce a PSA8001 error pointing at the function header. Functions intentionally per-script (phase functions, `Show-Help`, `Show-PhaseList`, `Find-KitTool`, per-driver-family helpers) are listed in `psa8001_ignore_functions` in `.psa.config.json`; functions identical in only 2-3 of the 4 scripts (e.g., AMD-family-only helpers, MSBthPan-only helpers) are not currently enforced because their absence in the 4th script is by design.

When adding a new shared helper that should remain in sync across all four scripts, add it to all four scripts with identical bodies and do NOT add it to `psa8001_ignore_functions`. PSA8001 will then enforce its sync invariant from that point onward.

### A.11.6 Self-quality gates for `psa.py` (consumer-side usage)

Since `psa.py` 3.5.0 the canonical analyzer ships three built-in
**self-quality gates** that consumer repositories — including this one —
SHOULD exercise. The gates are runnable from the command line, exit
non-zero on any violation (suitable for CI), and require no third-party
dependencies beyond a Python 3 interpreter. See the upstream
[SPEC.md §12 "Self-quality gates"](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/python/powershell-static-analyzer/SPEC.md#12-self-quality-gates)
for the normative description; this subsection covers what this
repository, as a consumer, does with each gate.

#### Pillar 2: `--config-check` — validate `.psa.config.json`

Whenever this repository's `.psa.config.json` is edited (adding /
removing rule IDs, changing thresholds, adjusting the
`psa8001_ignore_functions` list, etc.) the editor MUST run:

```bash
python3 /path/to/psa.py --config-check .psa.config.json
```

Expected output on a clean configuration:

```
psa.py config-check report
  target : .psa.config.json
  issues : 0

  config is valid (0 issues found)
```

The check detects (and exits `2` on) every problem before any
PowerShell file is analyzed: unknown top-level keys, unknown rule IDs
in `enable` / `disable`, `enable` ↔ `disable` conflicts, malformed
JSONC, bad `severity` values, non-positive integer thresholds, and
uncompilable regex patterns in `psa8001_ignore_functions`. This is
strictly faster and clearer than discovering the same problem when a
later analyzer run silently ignores an unknown rule code.

#### Pillar 3: `--self-check` — verify `psa.py` is internally consistent

Whenever a new mainline `psa.py` is brought into the workflow per the
A.11 *Version policy* (after fetching the `VERSION` file and comparing
to the locally-used version), run:

```bash
python3 /path/to/psa.py --self-check
```

Expected output on an internally-consistent `psa.py`:

```
psa.py self-check report (SPEC.md ↔ RULES)
  SPEC.md  : /.../scripts/python/powershell-static-analyzer/SPEC.md
  rules    : 36 in RULES, 36 in SPEC.md §4
  SPEC.md and RULES are in sync (no drift detected)
```

A non-zero exit means the local copy of `psa.py` and its sibling
`SPEC.md` disagree on the rule set. The most common cause is having
fetched only `psa.py` (or only `SPEC.md`) instead of the whole
analyzer directory; refetch the entire
`scripts/python/powershell-static-analyzer/` tree from mainline as a
unit.

#### Pillar 1 — `test_psa_rules.py`: informative only

The upstream test suite covers every rule with positive / negative /
edge fixtures and runs unattended. This repository does **not** need
to run it directly: a passing upstream test suite is a precondition
of the upstream release, and the `--self-check` gate above will
detect any deserialization drift between that release and this
repository's view of it. Consumers MAY run
`python3 test_psa_rules.py` for diagnostic purposes (e.g., when
investigating a suspected analyzer bug), but it is not part of the
mandatory CI path for this repository.

#### Activation scenarios

The two consumer-relevant gates are invoked in the following
situations:

| Trigger | Gate to run | Why |
|:---|:---|:---|
| PR touches `.psa.config.json` | `--config-check` | Confirms the schema is still valid and no rule IDs were typoed. Fast (no PowerShell analysis runs). |
| PR refreshes a locally-cached `psa.py` | `--self-check` | Confirms the freshly-fetched `psa.py` and `SPEC.md` are from the same release (catches partial-fetch accidents). |
| Any PR touching PowerShell files | full `psa.py --config .psa.config.json *.ps1` | The normal static-analysis pass (unchanged by the introduction of the new gates). |
| Investigating a suspected `psa.py` false positive / negative | `test_psa_rules.py` (upstream) | Optional, diagnostic. |

These are additive: the existing "Required gate" (zero `errors` and
zero `warnings` across all four pipeline scripts under the canonical
`.psa.config.json`) remains the single hard requirement for landing a
PR. `--config-check` and `--self-check` are **cheap pre-flight
checks** that surface problems earlier than the full analysis pass
would.

### Inline suppression and project-local configuration

Two mechanisms are available for legitimate suppression:

1. **Inline (`# psa-disable-line <CODE> -- <reason>`)** — apply to a single
   line. The reason text is mandatory in this repository's coding style;
   suppressions without a reason will be rejected in code review.

2. **Project config (`.psa.config.json`)** — if a rule needs to be disabled
   for the whole project (for example, after a pre-existing plural-noun naming
   convention is grandfathered), drop a `.psa.config.json` next to the
   scripts:

   ```jsonc
   // .psa.config.json — rationale comments are mandatory
   {
     "disable": ["PSA6003"]
   }
   ```

   `psa.py` auto-discovers `.psa.config.json` in the current working
   directory. No such file is shipped in this repository as of this writing;
   the baseline above represents the unfiltered analyzer output.

### Common false positives and resolutions

| False positive | Resolution |
| -------------- | ---------- |
| `PSA2001` "undefined variable" for `$Script:Foo` set in a different function | Initialize at script load: `$Script:Foo = $null` |
| `PSA2003` "-match against bare `$variable`" where `$variable` is guaranteed non-null | Wrap with `[string]::IsNullOrEmpty($variable)` guard, or refactor to `[regex]::Match()` |
| `PSA3004` (empty `catch`) intentional silent failure | Add `# psa-disable-line PSA3004 -- <reason>` |
| `PSA5001` (plain-text password) where API requires plaintext (signtool / X509Certificate2) | `# psa-disable-line PSA5001 -- <reason>` at the `param()` line |
| `PSA6003` (plural function noun) for pre-existing function names | Disable at project level via `.psa.config.json`, or `# psa-disable-line PSA6003` at the function declaration |

If `psa.py` systematically misclassifies a pattern, raise an issue upstream
in the canonical repository
(`https://github.com/usui-tk/ai-generated-artifacts`) rather than
suppressing locally.

---

## A.12 Documentation Language Policy

### File set

| English      | Japanese       | Bilingual? | Content                                           |
| ------------ | -------------- | ---------- | ------------------------------------------------- |
| `README.md`  | `README.ja.md` | ✅ Yes     | End-user documentation                            |
| `TESTING.md` | (none)         | ❌ EN only | Cloud / physical regression testing               |
| `SPEC.md`    | (none)         | ❌ EN only | Developer specification (this document)           |
| `CHANGELOG.md` | (none)       | ❌ EN only | Chronological per-release change log              |
| `CONTRIBUTING.md` | (none)    | ❌ EN only | How to file issues, propose changes, run tests   |
| `SECURITY.md`     | (none)    | ❌ EN only | Vulnerability reporting and security guarantees   |
| `CODE_OF_CONDUCT.md` | (none) | ❌ EN only | Community behaviour expectations                  |

**Policy rationale**: Only `README.md` is duplicated into Japanese,
because it is the primary entry point for new readers. Specifications,
testing procedures, and release logs are maintained in English only
to avoid synchronization drift. Japanese readers are expected to use
the Japanese `README.ja.md` for orientation and then refer to the
English source-of-truth documents for technical detail.

This policy is applied repository-wide; the same pattern is used by
the sister repository
[`ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts).

### Synchronization rule (README only)

Whenever `README.md` is updated, `README.ja.md` must be updated in the
same commit (or in an immediate follow-up commit referencing the
English commit hash). Maintain parity of:

- Section structure (same H2 / H3 headings)
- Tables (same columns)
- Code blocks (same content; Japanese files may use bilingual comments)
- Examples (same commands; localize the prose around them)

### Style for `README.ja.md`

- Technical terms in English are preserved in their English form (do not translate "phase", "decoration", "WDAC policy", "Workstation", "Server SKU", etc.)
- Particles use full-width forms: 「、」 「。」「・」 not "," "."
- Brackets: 「」 for emphasized terms, ` `` ` for code spans

### Mandatory disclaimer and license sections (both `README.md` and `README.ja.md`)

Each README must include:

1. A top-of-file ⚠️ Disclaimer block (USE AT YOUR OWN RISK, BitLocker warning, no warranty)
2. A bottom-of-file License section (MIT, with note that AMD's redistribution terms apply to AMD binaries downloaded at runtime, not to this repository)

---

## A.13 Development Workflow

### Iteration cycle

```
1. Write or modify code
2. python3 psa.py <script>.ps1            ← gate: 0 errors required
                                            (see A.11 for how to obtain psa.py)
3. Test on real AMD consumer hardware    ← per TESTING.md (chipset/graphics: physical
                                            Ryzen host with target devices; NPU script:
                                            physical Ryzen AI machine — see TESTING.md §3)
4. Update README.md + README.ja.md if behavior changed (per A.12, only the README
   is bilingual; other docs are English only). Update SPEC.md / TESTING.md /
   CHANGELOG.md (all English only) as appropriate.
5. Commit with revision number bump in $Script:ScriptVersion
```

> Because the pipeline targets AMD's consumer Ryzen / Radeon / NPU silicon, testing on non-target hardware (server-class EPYC, virtual machines without the target devices, etc.) cannot exercise the device-bind, driver-upgrade, or post-install verification paths. The Iteration cycle therefore mandates testing on real AMD consumer hardware.

### Revision discipline

Bump the revision number (e.g. `r<N>` → `r<N+1>`) on any commit that changes:

- Phase semantics (any of the 21 phases)
- Output format (CSV columns, log markers, banner layout)
- Parameter set (added / removed / renamed switches)

Cosmetic-only changes (typo fixes in messages, README rewording) do not require a revision bump.

### Where revision history lives

Per-revision change descriptions belong **exclusively** in
`CHANGELOG.md` at the repository root. The PowerShell script body
contains **only** current-behavior comments and current-rationale
references; it does NOT contain:

- End-of-file `REVISION HISTORY` comment blocks (enforced by
  `psa.py` `PSAP0004`).
- Inline `# rNN:` / `# rNN+:` / `# rNN-update:` revision-tag comments
  (enforced by `psa.py` `PSAP0003`).
- `# Before rNN` / `# From rNN on` / `# (rNN+) ...` revision-anchor
  prose. Use "Previously" / "Now" / no-anchor wording instead and
  refer the reader to `CHANGELOG.md` for the chronological context.

The architectural rationale behind each fix (root cause, fix design,
scope, upgrade impact) belongs in **Part D — Known Pitfalls & Lessons
Learned** of this SPEC. CHANGELOG.md cross-references back to Part D
where applicable.

This three-way split — script body for current behaviour, `CHANGELOG.md`
for chronological release log, `SPEC.md` Part D for architectural
rationale — keeps each document focused on a single responsibility
and avoids the "stale revision tag everywhere" problem that LLM-assisted
maintenance is especially vulnerable to.

### Reuse before invention

Before writing any new helper function:

1. Search the existing 4 scripts for an equivalent (`grep -rn 'function <NewName>' .`).
2. If found, copy verbatim from the most recent revision.
3. If not found, add it to the canonical helper section (under "Output helpers" or "Environment helpers" near the top of the file) so future scripts can reuse it.

---

## A.14 UEFI Secure Boot Baseline (cross-script feature)

A cross-cutting feature introduced to give operators consistent insight into the host's UEFI Secure Boot certificate rollout state. The feature is purely informational — UEFI-layer trust is independent of the OS-layer self-signing trust chain these scripts operate on — but it shares vocabulary and presentation across all four scripts so logs are correlatable.

### Function set (7 functions, 6 cross-script-identical + 1 per-script helper)

The first six functions are **byte-identical** across the chipset / graphics / NPU / BthPan scripts so they can be lifted verbatim from any sister and pasted into a new one:

| Function | Role |
|---|---|
| `Get-SecureBootCertificateInventory` | Enumerates db / KEK variables, reads `HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\*` registry keys, queries the `Secure-Boot-Update` scheduled task via `Get-ScheduledTask` (locale-independent). |
| `Get-MsSecureBootExampleScriptPath` | Detects whether `%SystemRoot%\SecureBoot\ExampleRolloutScripts\Detect-SecureBootCertUpdateStatus.ps1` is present on this host. |
| `Invoke-MsSecureBootDetectScript` | Launches the MS sample script as a child PowerShell, captures stdout, falls back to in-stdout JSON extraction when the `-OutputPath` validator rejects absolute Windows paths. |
| `Get-SecureBootBaselineSnapshot` | Top-level entry point. Combines `.Embedded`, `.MsInfo` (with `.Data`, `.JsonPath`, `.ErrorMessage`), `.Health` (`Healthy` / `Warning` / `Critical` / `Unknown`), `.Reasons[]`. |
| `Show-SecureBootBaselineSnapshot` | Console renderer. Supports `-Compact` (one-line for P00 / V05 / I02) and full mode (V06). Callers control banners. |
| `Format-SecureBootBaselineForReport` | Plain-text formatter for the `inf_inventory_report.txt` appendix. |

The seventh function, `Get-OrEnsureSecureBootBaseline`, is **per-script** because state-management patterns differ:

| Script | State holder | Helper signature |
|---|---|---|
| Chipset | `$Ctx` (pscustomobject) | `param([Parameter(Mandatory)] $Ctx)` |
| Graphics | `$Ctx` (pscustomobject) | `param([Parameter(Mandatory)] $Ctx)` |
| NPU | `$Script:DetectedPlatform` (hashtable), `$Script:WorkRoot` | `param()` — accesses script scope directly |
| BthPan | `$Ctx` (pscustomobject) | `param([Parameter(Mandatory)] $Ctx)` (verbatim from chipset) |

The helper's contract is identical: return the cached snapshot when `(.MsInfo.JsonPath -is $null) -or (Test-Path -LiteralPath $JsonPath -and $JsonPath -like "$WorkRoot*")`; otherwise re-invoke into the current workspace. This handles three real-world cases:

1. First-ever run, no workspace exists at P00 time — `Get-SecureBootBaselineSnapshot` creates the workspace dir as a side effect via `New-Item -Force`.
2. `-CleanWorkRoot` specified, P01 wipes the workspace after P00 captured — P05 / V05 / V06 / I02 detect the missing diagnostic file and re-capture.
3. Subsequent run, workspace pre-existing with prior diagnostic file present — helper returns cached snapshot (fast path).

### Integration points (5 sites per script)

| Phase | Action | Trigger |
|---|---|---|
| **P00** | Initial capture + `Show-... -Compact` | Always (first call seeds `$Ctx.SecureBootBaseline` / `$Script:DetectedPlatform.SecureBootBaseline`) |
| **P05** | Re-capture if needed; pass snapshot to `Export-InfInventoryReport` (chipset / graphics) or inline writer (NPU); produce appendix in `inf_inventory_report.txt` | After CSV export, before phase footer |
| **V05** | Re-capture if needed; `Show-... -Compact`; surface `Warning` / `Critical` advisory | After dry-run plan summary |
| **V06** | Re-capture if needed; `Show-...` (full); displayed as Section 4 (chipset / graphics) or Section 5 (NPU, after the Ryzen AI reminder) | After existing sections |
| **I02** | Re-capture if needed; pre-check display; cross-reference with planned WDAC / testsigning path; advisory only (never blocks) | Between AS-IS state display and path decision |

### MS sample script integration

Microsoft's `Detect-SecureBootCertUpdateStatus.ps1` (delivered via KB5089549 on Windows 11, KB5087544 / KB5088863 on Windows 10, WS2025 equivalent since 2026-05-12) is launched as a child PowerShell. Two robustness measures:

- **`-OutputPath` validator bypass**: MS's regex `[<>:"|?*]` rejects every absolute Windows path (because `:` follows the drive letter). When validation fires, the MS script falls back to stdout JSON. Our `Invoke-MsSecureBootDetectScript` always tries the file path first, then extracts JSON from captured stdout (regex-anchored to known keys: `Hostname` / `UEFICA2023Status` / `SecureBootEnabled`).

- **Diagnostic file persistence**: raw stdout is saved to `<WorkRoot>\secureboot_ms_sample\detect_stdout.log`; the recovered JSON to `detect_stdout_extracted.json`.

### Health classification

| Class | Conditions |
|---|---|
| `Healthy` | Secure Boot ON; `UEFICA2023Status` = `Updated` or `Not Applicable`; no `UEFICA2023Error`; scheduled task `Ready` |
| `Warning` | Secure Boot ON; rollout in flight (`NotStarted` / `Started` / `Pending`); OR scheduled task disabled; OR MS sample reports rollout-event diagnostics |
| `Critical` | Secure Boot OFF; OR non-zero `UEFICA2023Error` |
| `Unknown` | None of the diagnostic sources were readable |

I02 surfaces the class but never blocks — UEFI-layer cert rollout is independent of OS-layer signing trust.

### Maintenance rule

When adding a fifth sister script, the 6 cross-script-identical functions are lifted verbatim. The per-script helper is rewritten to match the new script's state-holder pattern. See B.1 / B.2 / B.4 (chipset / graphics / BthPan use `$Ctx`) and B.3 (NPU uses script scope) for the two known patterns.

---

# Part B — Script-specific Specifications

## B.1 Chipset script (`Deploy-AMDChipsetDriverOnWindowsServer.ps1`)

### Identification

- **Current revision**: see [CHANGELOG.md](./CHANGELOG.md) (single source of truth)
- **Workspace**: `C:\Temp\Workspace_AMD-Chipset\`
- **Self-signed cert subject**: `CN=AMD Chipset Driver Self-Sign (WS2025 Lab, At Own Risk)`
- **Self-signed cert files**: `cert\AMD-Chipset-Driver-CodeSign.{pfx,cer}`
- **WDAC policy GUID**: fixed `503860EA-8837-4169-9BC4-19E5AEED721B`; overridable via `-WdacPolicyGuid`. Legacy deploys used a dynamically-generated PolicyId recorded in `cert\AmdSuppPolicyId.txt`.
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

- **P03 / P04**: Multi-strategy installer extraction with three fallback layers (see "AMD 8.x installer architecture" below for the architecture that drives this):
    - **Strategy 1/3**: 7-Zip auto-detect. Works for AMD 6.x and earlier self-extracting EXEs.
    - **Strategy 2/3**: InstallShield `/a` administrative install + recursive `msiexec /a`. Standard path for AMD 8.x+ installers (NSIS outer + InstallShield SFX inner). Emits a per-OS-variant INF-coverage diagnostic post-extraction.
    - **Strategy 3/3**: Launch installer with `/S`, watch `C:\AMD\` for the extraction directory, terminate before install runs. Fragile final fallback retained for unrecognised formats.
- **P05**: INFs are classified by source variant: `W11x64` (Win11) / `WTx64` (Workstation x64) / `WT6A_INF` / `WT64A`. Only the OS-matching variant is selected for the pipeline (per `Get-PreferredAmdSourceVariants`).
- **P06**: PSP driver (`amdpsp.inf`) is **never patched** without an explicit BitLocker warning — see Disclaimer §5.

### Known constraints

- 5-year cert validity (hard-coded in P07).
- Patched drivers retain their AMD-published `DriverDate`; comparing AS-IS vs TO-BE uses `.Date` truncation to avoid timezone false positives (see Part D D.1).

### AMD 8.x installer architecture

Starting with AMD Chipset Software 8.x (first observed in version 8.02.18.557, distributed early 2026), AMD switched the installer bootstrapper to a two-layer wrapper that defeats 7-Zip-based extraction. The script's multi-strategy extraction (introduced for AMD 8.x) is designed against this architecture; the layered structure is documented here so that extraction failures can be diagnosed.

#### Two-layer wrapper structure

The downloaded `amd_chipset_software_*.exe` (~78 MB) is an NSIS self-extracting shell wrapping an InstallShield SFX:

```
amd_chipset_software_8.02.18.557.exe   (~78 MB)
└── Outer layer: NSIS self-extracting EXE
    │   (7-Zip CAN extract this layer)
    │
    ├── AMD_Chipset_Drivers.exe        ← inner installer (~75 MB)
    │   └── Inner layer: InstallShield SFX (ISSetupStream format)
    │       │   (7-Zip CANNOT extract; only InstallShield can: /a switch)
    │       │
    │       ├── AMD_Chipset_Drivers.msi   (parent, ARPSYSTEMCOMPONENT=1)
    │       │
    │       └── Chipset_Software\
    │           ├── AMD-GPIO2-Driver.msi
    │           ├── AMD-PCI-Driver.msi
    │           ├── AMD-PSP-Driver.msi
    │           ├── AMD-SMBus-Driver.msi
    │           ├── ... (35 sub-MSIs total in 8.02.18.557)
    │           └── AMD-WBD-Driver.msi
    │
    └── (auxiliary support files)
```

#### After full extraction: OS-variant directory layout

Each sub-MSI, when expanded via `msiexec /a`, unpacks its driver binaries into three OS-variant subdirectories per driver:

```
<DestinationPath>\AMD\Chipset_Software\Binaries\<DriverName>\
    ├── W11x64\          ← Windows 11 / WS2022 / WS2025 (build >= 22000)
    │   ├── <driver>.inf
    │   ├── <driver>.sys
    │   ├── <driver>.cat
    │   └── ...
    ├── WTx64\           ← Windows 10 / WS2019 / WS2016 (build < 22000, 64-bit)
    │   └── (older driver versions for the same hardware)
    └── WTx86\           ← 32-bit Windows (never applicable to Server SKUs)
        └── (32-bit driver versions; included for completeness)
```

#### OS variant selection logic

`Get-PreferredAmdSourceVariants -OsContext $Ctx.Os` decides which variant subdirectory feeds the P05 / P06 / I03 pipeline. The decision is OS-build-driven, not heuristic:

| Host OS | Build | Base Windows | Preferred variant | Rationale |
| --- | --- | --- | --- | --- |
| Windows Server 2025 | 26100 | Windows 11 24H2 | `W11x64` | Kernel-equivalent to Win11 24H2; supports Pluton / PMF / USB4 / 3D V-Cache |
| Windows Server 2022 | 20348 | Iron-wave | `W11x64` | Closer to W11 ABI than W10 |
| Windows Server 2019 | 17763 | Redstone 5 | `WTx64` | Predates Win11; uses older driver ABI |
| Windows Server 2016 | 14393 | Threshold | `WTx64` | Threshold era = WTx64 by definition |

Other OS contexts fall back to `@('W11x64','WTx64')` (try both). The AMD 8.x extraction unpacks all three variants and lets the pipeline pick; this isolation keeps the extraction layer format-agnostic so future host-OS changes only need updates to `Get-PreferredAmdSourceVariants`.

#### AMD's actual driver registration logic (key finding)

Each sub-MSI's `CustomAction` table stores three OS-specific VBScript binaries as BLOBs in the `Binary` table (key `NewBinary20`):

- `Install_Driver_W11x64` (CustomAction type 7238 = VBScript in Binary)
- `Install_Driver_WTx64`
- `Install_Driver_WTx86`

A separate `GetOSBuildnum_22000` action (type 38, inline VBScript) queries `Win32_OperatingSystem.BuildNumber` and sets MSI property `W11BUILDNUM=1` when build >= 22000. The `InstallExecuteSequence` uses `W11BUILDNUM` to pick which of the three variant scripts to run.

The VBScript itself (extracted from the GPIO2 sub-MSI in 8.02.18.557) contains only:

```vbs
Function Install_Driver_W11x64()
    Set objShell = CreateObject("WScript.Shell")
    Dim StrDir : StrDir = objShell.ExpandEnvironmentStrings("%SYSTEMDRIVE%")
    Dim strcmd : strcmd = StrDir & "\Windows\System32\pnputil.exe" _
        & " /add-driver " _
        & chr(34) & StrDir & "\AMD\Chipset_Software\Binaries\GPIO2 Driver\W11x64\amdgpio2.inf" & chr(34) _
        & " /install"
    iLogMessage "Install_Driver_W11x64 : " & strcmd
    CreateObject("Wscript.Shell").Run strcmd, 0, True
End Function
```

In other words: AMD's chipset installer performs **no hardware detection at all**. It calls `pnputil /add-driver /install` for the OS-appropriate INF and lets the Windows kernel match each INF's `[Manufacturer]` Hardware IDs against the actual PnP device inventory. Devices that don't match remain unmatched; that is the expected behaviour, not a defect of either the AMD installer or this script.

The script's I03 phase reproduces this exact pattern (`pnputil /add-driver <patched.inf> /install`), with the addition of self-signature handling required for Windows Server SKUs.

#### Why 7-Zip fails on the inner layer

The InstallShield SFX wraps the parent MSI and sub-MSIs in an `ISSetupStream`-formatted stream. This format is proprietary to InstallShield and is not a standard archive format. 7-Zip's `PE` handler identifies the EXE wrapper and exits cleanly (exit 0), but extracts only the wrapper's resource section, leaving an empty result tree (no `.msi` / `.inf` files). The only known way to unpack `ISSetupStream` content is via InstallShield's own `/a` administrative-install switch.

7-Zip's failure mode is silent (exit 0 with no payload), which is why the script's `_HasPayload` success criterion guards each strategy with a presence check for `.inf` / `.msi` / `.cab` files rather than relying on the exit code alone.

#### Why /a admin install is safe (no drivers installed at extract time)

Both InstallShield `/a` and `msiexec /a` are designed to extract MSI contents WITHOUT running install-side CustomActions:

- `/a` runs `AdminExecuteSequence`, which is limited to `FileCost`, `InstallFiles`, and similar file-copy operations.
- `/a` does **not** run `InstallExecuteSequence`, where the driver-registration `CustomAction`s live (`Install_Driver_W11x64` etc.).

Empirical verification on AMD 8.02.18.557 (Renoir / WS2025):

- No driver entries appear in `Win32_PnPSignedDriver` after `/a`
- No `C:\AMD\` side-effects
- No sub-installer processes spawn
- Only files are written to `TARGETDIR`; nothing executes

#### 35 sub-MSIs in 8.02.18.557 (informational)

The sub-MSIs ship in the parent MSI's `ISChainPackage` table. Grouped by hardware applicability (Renoir = Zen 2 Mobile, 2020-era CPU; used here as the reference older platform):

| Category | Sub-MSI features (Feature.Name) | Renoir applicability |
| --- | --- | --- |
| Core chipset (always present) | `GPIO2`, `GPIO3` (Promontory), `PCI`, `PSP`, `SMBUS`, `RYZENPPKG`, `I2C`, `UART`, `INTERFACE`, `FILTERUSB` | High |
| Power Management Framework (newer-hw) | `RPMF6000` (6000-series), `PHPMF7040` (7040-series), `TPMF7736` (7736-series), `SPMF8000` (8000-series), `NAIPMF300` / `TAIPMF300` / `AIPMFMAX300` (AI 300 series) | None (Phoenix Point and later only) |
| Sensor Fusion Hub | `SFHDRVR`, `SFHI2C`, `SFH1.1` | Partial |
| Modern platform features | `USB4CM`, `CVAC` (3D V-Cache Optimizer), `MSFT1` / `MSFT2` (Pluton TPM), `HSMP`, `S0I3`, `MAIL` (Mailbox Drv), `UPEP` (Micro-PEP), `APPCOMPATDB`, `AS4ACPI`, `CIR`, `IOV_WT`, `OEMPF` (Provisioning), `PPM`, `WBD` | Low (mostly Phoenix Point and later) |

Older AMD platforms (Renoir, Cezanne) will produce fewer device-driver matches in I04 because most newer-platform sub-MSIs carry INFs whose Hardware IDs don't exist on those CPUs. **This is expected and not a script defect.** On X13 Gen 1 (Ryzen 5 PRO 4650U / Renoir), roughly 5-8 of the 35 driver packages typically match real devices; the remaining packages remain in the driver store but inactive.

---

## B.2 Graphics script (`Deploy-AMDGraphicsDriverOnWindowsServer.ps1`)

### Identification

- **Current revision**: see [CHANGELOG.md](./CHANGELOG.md) (single source of truth)
- **Workspace**: `C:\Temp\Workspace_AMD-Graphics\`
- **Self-signed cert subject**: `CN=AMD Graphics Driver Self-Sign (WS2025 Lab, At Own Risk)`
- **Self-signed cert files**: `cert\AMD-Graphics-Driver-CodeSign.{pfx,cer}`
- **WDAC policy GUID**: fixed `85336828-3080-41C5-81EC-FD587DC090D3`; overridable via `-WdacPolicyGuid`. Legacy deploys used a dynamically-generated PolicyId recorded in `cert\AmdSuppPolicyId.txt`.
- **WDAC SupplementsBasePolicyID**: `{A244370E-44C9-4C06-B551-F6016E563076}` (Windows-shipped default base CI policy); overridable via `-WdacBasePolicyGuid`. A legacy graphics revision used a non-standard `{B355481F-55DA-5D17-C662-07127F674187}` (see Part D D.8).

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

- **Current revision**: see [CHANGELOG.md](./CHANGELOG.md) (single source of truth)
- **Workspace**: `C:\Temp\Workspace_AMD-NPU\`
- **Self-signed cert subject**: `CN=AMD NPU Driver Self-Sign (WS2025 Lab, At Own Risk)`
- **Self-signed cert files**: `cert\AMD-NPU-Driver-CodeSign.{pfx,cer}`
- **WDAC policy name**: `AMD-NPU-Driver-SelfSign-Lab`
- **WDAC policy GUID**: fixed `8B2C4F12-1E9D-4D7B-A4F8-9C7E2B6A53D1` (per-script stable hardcoded value, used to identify the policy across runs for clean removal); overridable via `-WdacPolicyGuid`

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

## B.4 BthPan script (`Deploy-MSBthPanInboxOnWindowsServer.ps1`)

### Identification

- **ScriptVersion**: see [CHANGELOG.md](./CHANGELOG.md) (single source of truth)
- **ScriptTag**: see [CHANGELOG.md](./CHANGELOG.md) (single source of truth)
- **Default workspace**: `C:\Temp\Workspace_Microsoft-BthPan`
- **Cert subject CN**: `Microsoft BthPan Driver Self-Sign (<OsCode> Lab, At Own Risk)` (where `<OsCode>` is `WS2016` / `WS2019` / `WS2022` / `WS2025` depending on the host)
- **Cert filename**: `MS-BthPan-Driver-CodeSign.{pfx,cer}`
- **WDAC supplemental policy XML/CIP filenames**: `MsBthPanSelfSignedSupplementalPolicy.{xml,cip}` (stored in `<workspace>\cert\`)
- **WDAC supplemental policy marker file**: `cert\MsBthPanSuppPolicyId.txt` (records the deployed PolicyId for Cleanup)
- **WDAC supplemental policy GUID** (default, fixed): `A6E72D4F-3B98-4C5A-9E1D-7F8B2A4C6E5D` — newly minted for this script, does not collide with the Chipset (`503860EA-…`), Graphics (`85336828-…`), or NPU (`8B2C4F12-…`) scripts.
- **WDAC supplemental policy name**: `MS-BthPan-Driver-SelfSign-Lab`

### Driver source — DriverStore, not download

Unlike the AMD sister scripts which fetch installers from `drivers.amd.com` or AMD account portals, the BthPan script's driver source is the host's own DriverStore staging directory:

```
C:\Windows\System32\DriverStore\FileRepository\bthpan.inf_amd64_<hash>\
├── bthpan.inf       Microsoft inbox INF (Workstation-decorated only)
├── bthpan.sys       Microsoft-signed binary
├── bthpan.PNF       precompiled INF cache
└── <localized MUI resources>
```

The `Get-BthPanDriverStoreSource` helper enumerates `bthpan.inf_amd64_*` directories under `FileRepository`, filters to those that contain both `bthpan.inf` AND `bthpan.sys` AND at least one `.cat`, and picks the most recently modified directory. On a typical host there is exactly one such directory; multiple copies can appear after a Windows feature update.

**The Microsoft-signed bthpan.sys is never modified.** Only the catalog is re-signed (because the INF has been patched, breaking the original catalog's INF-content hash attestation).

### The root cause this script addresses

Microsoft's inbox `bthpan.inf` declares only the Workstation decoration `NTamd64...1`:

```ini
[Manufacturer]
%MfgName% = Msft,NTamd64...1
```

The fifth segment (`1`) is the ProductType restriction (1 = Workstation, 2 = Domain Controller, 3 = Server). On a Windows Server SKU (ProductType=3), the PnP matcher discards every `Msft.NTamd64...1` entry during HWID resolution. As a result:

1. `bthpan.inf`'s `[BthPan.Install]` section (AddService, CopyFiles, AddReg) never runs.
2. `bthpan.sys` is never copied to `C:\Windows\System32\drivers`.
3. The `BthPan` service is never registered.
4. No Bluetooth PAN network adapter (Class=Net) is ever created.

### Phantom OK vs True Resolution

A particularly subtle failure mode: even on Server SKUs, `BTH\MS_BTHPAN` may show `Status=OK` in Device Manager. This is because the generic `bth.inf` proxy-matches the device. However, `bthpan.sys` is NOT actually loaded and the `BthPan` service is NOT actually running — PAN networking functionality is still completely broken.

V05 / V06 / I04 use `Get-PnpDeviceProperty` to read three DEVPKEY properties and classify the state:

| Property                       | Phantom OK             | True Resolution         | Unknown (code 28) |
| ------------------------------ | ---------------------- | ----------------------- | ----------------- |
| `DEVPKEY_Device_DriverInfPath` | `bth.inf`              | `oem<N>.inf`            | (empty)           |
| `DEVPKEY_Device_Class`         | `Bluetooth`            | `Net`                   | (empty)           |
| `DEVPKEY_Device_Service`       | (empty)                | `BthPan`                | (empty)           |
| Status                         | OK                     | OK                      | Error             |

The script ALSO checks three runtime artifacts (`Test-BthPanRuntimeArtifacts`):

- `C:\Windows\System32\drivers\bthpan.sys` exists
- `HKLM:\SYSTEM\CurrentControlSet\Services\BthPan` registry key exists
- A `NetAdapter` with `InterfaceDescription` matching `Bluetooth.*Personal Area Network` is enumerable via `Get-NetAdapter`

I04 declares `*** TRUE RESOLUTION ACHIEVED ***` only when **all** of the following hold:

1. Every `BTH\MS_BTHPAN*` device classifies as `True` (or device count is zero)
2. `bthpan.sys` is present in `System32\drivers`
3. `BthPan` service key is registered

### INF patching strategy

`Edit-InfForServer` (verbatim from the Chipset script) is used to mirror the Workstation decoration `NTamd64...1` with `NTamd64...3`:

```ini
; Before patching
[Manufacturer]
%MfgName% = Msft,NTamd64...1

; After Strategy A (default)
[Manufacturer]
%MfgName% = Msft,NTamd64...1,NTamd64...3
```

The `ConvertTo-ServerDecoration` helper parses `NTamd64...1` (`NT`+`amd64`+`.`+empty+`.`+empty+`.`+empty+`.`+`1`) into a 4-element array `['NTamd64','','','1']`, sets `parts[3]='3'`, and re-joins to produce `NTamd64...3`. This generates exactly one new server decoration entry which covers all Server SKUs (ProductType=3 is build-agnostic).

**Strategy B (optional)**: `Add-BthPanExplicitServerDecorations` additionally appends four build-explicit decorations:

```ini
[Manufacturer]
%MfgName% = Msft,NTamd64...1,NTamd64...3,NTamd64.10.0...14393,NTamd64.10.0...17763,NTamd64.10.0...20348,NTamd64.10.0...26100
```

This provides a deterministic PnP-ranking tie-break when multiple bthpan packages compete for the binding slot but requires manual update for any future Server SKU build that Microsoft ships.

### Catalog generation — four-SKU simultaneous targeting

P08 invokes `inf2cat` with `/os:Server2025_X64,ServerFE_X64,ServerRS5_X64,Server2016_X64` so that a single signed catalog covers all four Windows Server SKUs. The script first probes the installed `inf2cat.exe` for its supported `/os:` tokens via `Get-Inf2catSupportedOsValues` and intersects the desired list with what inf2cat actually understands. If the full 4-SKU list fails (rare; usually because `Server2016_X64` is not recognised by very old inf2cat builds), the script retries without `Server2016_X64`.

### Phase quirks (differences from sister scripts)

| Phase | BthPan-specific behaviour                                                                                |
| ----- | -------------------------------------------------------------------------------------------------------- |
| P02   | 7-Zip is NOT required (no archive extraction). Only SDK (signtool) + WDK (inf2cat) are needed.           |
| P03   | No network calls. Locates `bthpan.inf_amd64_*` in DriverStore via `Get-BthPanDriverStoreSource`.         |
| P04   | Simple file copy from DriverStore to `workspace\extracted\bthpan\`. No archive extraction.               |
| P05   | Single-row CSV (one INF: `bthpan.inf`). No source-variant disambiguation.                                |
| P06   | Strategy A by default (single `NTamd64...3` mirror); Strategy B optional via `-DecorationStrategy B`.    |
| P08   | Targets all four Server SKUs (`Server2025_X64,ServerFE_X64,ServerRS5_X64,Server2016_X64`) simultaneously.|
| V05   | Diagnoses every `BTH\MS_BTHPAN*` instance; classifies Phantom/True/Unknown.                              |
| V06   | Sections: device disposition, runtime artifacts, existing oem*.inf mappings, risk classification, UEFI Secure Boot baseline. No per-device "AS-IS / TO-BE" matrix (only one driver, one HWID). |
| I03   | After `pnputil /add-driver /install`, runs `pnputil /scan-devices` to force PnP re-evaluation and rebind from `bth.inf` proxy match to patched `oem*.inf`. |
| I04   | Verdict: `*** TRUE RESOLUTION ACHIEVED ***` requires per-device classification + runtime artifact checks. Phantom OK is explicitly flagged as a FAIL. |

### Parameters

The BthPan script intentionally does NOT expose:

- `-InstallerUrl`, `-AmdLandingUrls`, `-AmdFallbackUrl` (Chipset/Graphics-specific — there is no AMD installer to fetch)
- `-OfflineZip`, `-AmdAccountUser`, `-AmdAccountPassword`, `-ForceAmdAccountAuth` (NPU-specific)
- `-NpuOverride`, `-NpuDriverPackage`, `-RyzenAiSoftwareVersion`, `-AssumeIfMissing` (NPU-specific)
- `-CertValidityYears` (hard-coded per OS context: 3 years on WS2016, 5 years on WS2019+)

It DOES expose:

- All common parameters per A.6 (`-Action`, `-OnlyPhases`, `-CleanWorkRoot`, `-AllowWorkstationInstall`, `-UseTestSigning`, `-WorkRoot`, `-PfxPassword`, `-WdacPolicyGuid`, `-WdacBasePolicyGuid`)
- `-Help` / `-h` / `-?` (alias-bound switch)
- `-References` (curated Microsoft Learn link index)
- `-Force` (bypass cached Phase markers)
- `-TimestampUrl` (default `http://timestamp.digicert.com`)
- **`-DecorationStrategy A|B`** — BthPan-specific. A (default): `NTamd64...3` only; B: also adds `NTamd64.10.0...14393 / 17763 / 20348 / 26100` per-build entries.

### Known constraints

- Requires a bound Bluetooth host controller. If the host controller itself is unknown-device, the script's V05 / V06 will still run (and report no `BTH\MS_BTHPAN` device present), but `Install` will not produce a functional outcome until the host controller is bound first.
- `pnputil /scan-devices` after `/add-driver` *usually* triggers an immediate rebind from `bth.inf` to the patched `oem*.inf`. In some cases (observed on WS2025 build 26100.32860), a reboot is required for PnP to fully re-evaluate the device. I04 detects this case and reports `*** TRUE RESOLUTION NOT YET ACHIEVED ***`; re-running the same `-Action Install` command after reboot resolves the binding.
- The script does NOT cover Bluetooth host controller drivers (Intel AX2xx, Realtek RTL88xx, etc.). Vendor host controller drivers must be installed via their respective vendor channels first.
- The script does NOT remove inbox `bthpan.inf` from `C:\Windows\INF\`. The patched `oem*.inf` simply outranks the inbox INF in PnP ranking due to its newer effective decoration (`NTamd64...3` matches ProductType=3 exactly, while inbox `NTamd64...1` is filtered out entirely).

---

# Part C — Quality Gates & Validation Checklist

Every commit to `main` must satisfy the following gates.

## C.1 Static checks

> `psa.py` is not bundled in this repository; obtain it per A.11 before running these checks.

- [ ] `python3 psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1` → 0 errors
- [ ] `python3 psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1` → 0 errors
- [ ] `python3 psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1` → 0 errors
- [ ] `python3 psa.py Deploy-MSBthPanInboxOnWindowsServer.ps1` → 0 errors

## C.2 Functional checks (per affected script)

- [ ] `-Action ListPhases` produces the expected 21-phase table.
- [ ] `-Action PrepareVerify -CleanWorkRoot` on any non-target host (without the target AMD devices) completes without errors using `-AssumeIfMissing` (NPU script) / appropriate platform override (chipset / graphics). Note: this is a pipeline-soundness check only — it does not validate real driver behaviour.
- [ ] `-Action PrepareVerify -CleanWorkRoot` for the BthPan script completes on any Server SKU and produces a single-row `inf_inventory.csv`, even on hosts without a Bluetooth host controller (V05 / V06 will report "No BTH\MS_BTHPAN device on host" but the prepare phases still complete cleanly).
- [ ] `Show-RunSummary` is rendered regardless of exit path (success or failure).
- [ ] `Format-Elapsed` produces correct strings for `0.42s`, `1m2.3s`, `1h2m3s`.

## C.3 Documentation checks

- [ ] If a phase semantic changed: SPEC.md Part B is updated.
- [ ] If a parameter was added / removed / renamed: README.md and README.ja.md Parameters table is updated.
- [ ] If an output format changed: SPEC.md A.9 CSV columns and README.md Output files sections are updated.
- [ ] `README.ja.md` is in sync with `README.md` (see A.12 Documentation Language Policy).
- [ ] `CHANGELOG.md` has a new entry for the release (English only).

## C.4 Cross-script consistency checks

- [ ] All four scripts use `[pscustomobject]@{...}` in `$Script:PhaseRegistry` (not `@{...}`).
- [ ] All four scripts use sister-aligned function naming: `Invoke-{Group}Phase{NN}_{Name}`.
- [ ] All four scripts use the same `-Action` ValidateSet: `'Prepare','Verify','PrepareVerify','Install','All','Cleanup','ListPhases'`.
- [ ] All four scripts use the same marker semantics: `[*]` Cyan / `[+]` Green / `[!]` Yellow / `[X]` Red / `[~]` DarkGray.
- [ ] All four scripts use unique WDAC supplemental policy GUIDs that do NOT collide.

---

# Part D — Known Pitfalls & Lessons Learned

These are documented so that future revisions do not regress on already-fixed issues.

## D.1 Timezone-induced DriverDate false positives

**Symptom**: V05 dry-run plan reported `[UPGRADE]` action on identical drivers because `Win32_PnPSignedDriver.DriverDate` is stored as UTC midnight, but `Get-CimInstance` converts to local time, producing a day-offset on `[datetime]` comparison.

**Fix**: In `Compare-InfDriverVer`, use `.Date` truncation (year/month/day only) on both the current driver date and the patched INF date before comparing.

```powershell
$cdate = if ($CurrentDate) { $CurrentDate.Date } else { $null }
$pdate = if ($PatchedDate) { $PatchedDate.Date } else { $null }
```

Preserved verbatim across chipset / graphics / NPU scripts.

## D.2 Hypothetical filename `NPU_RAI1.7.1_380_WHQL.zip`

**Symptom**: Initial NPU script revisions used `NPU_RAI1.7.1_380_WHQL.zip` as the default filename, mapping it to RAI 1.7.1. However AMD's actual published filename for RAI 1.7.1 is **the same as for RAI 1.6.1**, namely `NPU_RAI1.6.1_314_WHQL.zip` (driver build 32.0.203.314).

**Fix**: NPU driver and Ryzen AI Software are versioned independently. The script now exposes them as two distinct parameters and the default `-NpuDriverPackage latest` resolves to `NPU_RAI1.6.1_314` (the newest documented). Verified against <https://ryzenai.docs.amd.com/en/latest/inst.html> 2026-04-19.

## D.3 `Show-PhaseHeader` vs `Write-PhaseHeader` naming drift (NPU)

**Symptom**: Early NPU revisions used `Show-PhaseHeader` (sister scripts used `Write-PhaseHeader`), and the phase entry banner color was Yellow `#`×78 (sister: Magenta `=`×72). This broke visual consistency across logs from multiple scripts run in sequence.

**Fix**: Sister-script alignment refactor renamed to `Write-PhaseHeader` and adopted Magenta `=`×72 + script-tag DarkGray line. Now identical across all three scripts.

## D.4 NPU — Action `'Install'` semantic drift

**Symptom**: An earlier NPU revision mapped `-Action Install` to "all 21 phases" (full pipeline), while sister scripts mapped it to "Inst phases only" (assumes Prep + Verify already ran).

**Fix**: Sister-script alignment refactor corrected `-Action Install` to Inst-only and added `-Action All` for the full pipeline. Workstation OS guard now fires on both `Install` and `All`.

## D.5 ja-JP console encoding (chcp 932)

**Symptom**: Japanese log strings garble on default ja-JP Windows console (code page 932, Shift-JIS), AND external tool output (CiTool.exe, modern signtool.exe) writing UTF-8 to stdout is mojibake when captured via `& tool | Out-String`.

**Fix**: P00 calls `Set-ConsoleUtf8` which enforces all three encodings ( `[Console]::OutputEncoding`, `[Console]::InputEncoding`, `$OutputEncoding`) to `[System.Text.Encoding]::UTF8`. Operators using `*>&1 | Tee-Object` must also set the file encoding explicitly. See §A.5 for the canonical implementation.

**Pre-fix history**: This SPEC entry was documented from the earliest revisions, but the implementation was missing. `Show-PowerShellEnvironment` displayed `Default Encoding: shift_jis (cp932)` / `Console OutputEnc.: shift_jis (cp932)` but no code path actually set them to UTF-8. The defect surfaced as `CiTool: 蜃ｦ逅・・謌仙粥縺励∪縺励◆` in I02 log output on ja-JP WS2025 hosts. See §D.16 for the full root-cause and verification trail.

## D.6 `-LiteralPath` not supported on `Invoke-WebRequest -OutFile` (PS 5.1)

**Symptom**: When downloading to a path containing `[` or `]`, `Invoke-WebRequest -OutFile` (PS 5.1) wildcard-interprets the path.

**Fix**: Download to a wildcard-free temp filename (`<dir>\.dl_<GUID>.part`), then `Move-Item -LiteralPath` to the real destination. Pattern preserved in NPU script's `Invoke-NpuZipDownload`.

## D.7 Code-signing certificate filename standardization

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
| Chipset | `AMD-Chipset-Driver-CodeSign.{pfx,cer}` | `C:\AMD-Chipset-WS\cert\` |
| Graphics | `AMD-Graphics-Driver-CodeSign.{pfx,cer}` | `C:\AMD-Graphics-WS\cert\` |
| NPU | `AMD-NPU-Driver-CodeSign.{pfx,cer}` | `C:\AMD-NPU-WS\cert\` |

**Upgrade impact on existing deploys**:

- Old `cert\AMD-Driver-CodeSign.{pfx,cer}` files remain on disk untouched after upgrade (Cleanup removes the cert from trust stores by thumbprint, not by filename).
- Running `-Action Install` with the new script will generate a fresh PFX/CER under the new name; the old PFX/CER is then orphaned in the workspace.
- For a clean upgrade, run `-Action Cleanup` on the old script revision **before** upgrading.

## D.8 WDAC supplemental policy GUID standardisation

**Symptom 1 (Chipset / Graphics, before the fix)**: The supplemental policy `PolicyID` was generated dynamically with `Set-CIPolicyIdInfo -ResetPolicyID`, producing a new GUID on every deploy. The GUID was persisted to `<workspace>\cert\AmdSuppPolicyId.txt` so that `Cleanup` could find it later.

This had two downsides:
- A re-deploy did not replace the previous deploy's policy slot — it created a *new* slot with a new GUID, accumulating dormant `<oldGuid>.cip` files in `C:\Windows\System32\CodeIntegrity\CiPolicies\Active\`.
- If `<workspace>\cert\AmdSuppPolicyId.txt` was lost (e.g. workspace deleted manually), `Cleanup` could not locate the deployed policy.

**Symptom 2 (Graphics, before the fix)**: The script used `SupplementsBasePolicyID = '{B355481F-55DA-5D17-C662-07127F674187}'`, a non-standard GUID that does **not** correspond to any Microsoft-shipped CI base policy. Almost certainly a copy-paste artefact from earlier development. The chipset and NPU scripts both correctly used the Windows-default `{A244370E-44C9-4C06-B551-F6016E563076}`. The Graphics supplemental policy was therefore "supplementing" a non-existent base, which Windows may load with a warning or silently ignore.

**Fix**:

1. **Fixed default supplemental policy GUIDs** per script, unique per script so they coexist on a host with all three deployed:
   - Chipset: `503860EA-8837-4169-9BC4-19E5AEED721B`
   - Graphics: `85336828-3080-41C5-81EC-FD587DC090D3`
   - NPU: `8B2C4F12-1E9D-4D7B-A4F8-9C7E2B6A53D1` (pre-existing, unchanged)
2. **Operator override** via `-WdacPolicyGuid <GUID>`, accepted with or without braces. Two use cases:
   - **Legacy cleanup**: read the old PolicyId from `<workspace>\cert\AmdSuppPolicyId.txt` and pass it with `-Action Cleanup -WdacPolicyGuid <oldGuid>` to remove a legacy deploy. The new `Test-AmdWdacPolicyDeployed` also automatically falls back to reading the legacy marker file if the fixed GUID is not active, so unattended Cleanup on a legacy deploy still works without manual GUID lookup.
   - **Side-by-side**: deploy two copies of the same script with different GUIDs (rare).
3. **Graphics-only fix**: default `SupplementsBasePolicyID` corrected from `{B355481F-...}` to the Microsoft standard `{A244370E-...}`. Overridable via `-WdacBasePolicyGuid` for environments with custom base CI policies.
4. **Implementation detail**: PowerShell's `Set-CIPolicyIdInfo` has no `-PolicyId` switch; we patch the `<PolicyID>` element directly in the XML after `Set-CIPolicyIdInfo -SupplementsBasePolicyID …` (no longer pass `-ResetPolicyID`).

**Upgrade impact**: Same as D.7 — for a clean upgrade, run `-Action Cleanup` on the old script revision before deploying the new one. The new script's `Cleanup` action does detect legacy dynamic-GUID policies via the marker-file fallback, so an upgrade-then-cleanup also works (one extra cleanup cycle).

---

## D.9 UEFI Secure Boot baseline feature

**Summary**: A cross-cutting informational feature added to all three scripts that captures the host's UEFI Secure Boot certificate-rollout state and surfaces it at P00 / P05 (report appendix) / V05 (compact) / V06 (full section) / I02 (pre-check). See `A.14 UEFI Secure Boot Baseline` for the full design.

**Iteration history**:

| Phase | Change |
|---|---|
| Initial implementation | 6 core functions + per-script helper + 5 integration points |
| Validation fixes | Three corrective fixes applied before publishing: (a) `schtasks.exe /Query /FO CSV` returns localized headers on ja-JP hosts; replaced with `Get-ScheduledTask` for locale-independent state. (b) MS sample script's `[<>:"|?*]` regex rejects every absolute Windows path; added stdout-JSON fallback. (c) `Show-...` non-compact mode and V06 caller both printed `--- UEFI Secure Boot Baseline ---` banner; removed inner banner so V06 controls section numbering. |
| Polish patch | Removed `%TEMP%` fallback from P00 (diagnostic files always co-locate with `$Ctx.WorkRoot`); added `Get-OrEnsureSecureBootBaseline` helper that re-captures when the cached snapshot's diagnostic file is missing or outside the current workspace. |

**Cross-script symmetry**: The 6 core functions (Get-SecureBootCertificateInventory / Get-MsSecureBootExampleScriptPath / Invoke-MsSecureBootDetectScript / Get-SecureBootBaselineSnapshot / Show-SecureBootBaselineSnapshot / Format-SecureBootBaselineForReport) are byte-identical across the four scripts (chipset / graphics / NPU / BthPan); BthPan reuses the chipset variant verbatim. Only the seventh `Get-OrEnsureSecureBootBaseline` helper differs (chipset/graphics: `param($Ctx)`; NPU: `param()` with script-scope access).

---

## D.10 `Find-Inf2CatPath` x64-filter bug (NPU)

**Summary**: NPU's `Find-Inf2CatPath` delegated to `Find-ToolPath` which filters discovered files to `\x64\` or `\amd64\` directories only. inf2cat.exe ships **exclusively as an x86 binary** under the Windows SDK/WDK tree (Microsoft has never produced an x64 build of this tool), so the filter always returned `$null` and NPU P02 then tried to install the WDK via winget — which itself does not publish the WDK as a winget package. The result was a hard P02 FAILED on every host that had inf2cat installed in the standard location.

**Root cause**: Reuse of a generic `Find-ToolPath` helper whose architecture filter is correct for signtool (which has both x64 and x86 variants) but wrong for inf2cat (x86 only).

**Fix**: Replaced the body of `Find-Inf2CatPath` with an inline `Get-ChildItem ... -Recurse -Filter 'inf2cat.exe'` walk over the SDK bin roots, no architecture filter. Highest `FileVersion` wins. Matches the lookup logic implicit in the chipset / graphics scripts where inf2cat is also found correctly.

**Scope**: NPU-only; chipset and graphics scripts use a different inf2cat discovery path.

---

## D.11 `NpuOverride` `[ValidateSet]` excludes empty string (NPU)

**Summary**: At script load, PowerShell logged `値  は NpuOverride 変数の有効な値ではないため、変数を検証できません` (and English equivalent) from the line `$Script:NpuOverride = $NpuOverride`. The warning fired because `[ValidateSet('PHX','HPT','STX','KRK')]` on `[string]$NpuOverride` rejects the default empty string when the variable is re-evaluated at the script-scope assignment. The warning was non-fatal (the script continued past it) but noisy and confusing.

**Fix**: Added `''` to the ValidateSet: `[ValidateSet('','PHX','HPT','STX','KRK')]`. The empty value represents "no override; auto-detect via Get-AmdNpuPlatform", which matches the prior default behaviour.

**Scope**: NPU-only.

---

## D.12 InstallShield SFX extraction for AMD 8.x+ installers (Chipset)

**Summary**: Starting with AMD Chipset Software 8.x (8.02.18.557, observed May 2026), the installer bootstrapper changed to a two-layer wrapper: an outer NSIS SFX wrapping an inner InstallShield SFX (`ISSetupStream` format). 7-Zip can decode the outer layer but exits cleanly (exit 0) on the inner layer with no payload, so the script's earlier two-strategy extraction (7-Zip + launch-and-watch) silently produced an incomplete result.

**Observed symptom (X13 Gen 1 / Ryzen 5 PRO 4650U / WS2025, May 2026)**: After P04 ExtractInstaller succeeded, P05 AnalyzeInfs reported only 2 INFs in the extract tree (`AmsMailbox.inf` + `AmdAppCompat.inf`) instead of the expected ~32. I04 PostInstallVerify reported 42 unmatched AMD devices in Device Manager.

**Root cause**: The AMD 8.x inner installer is `ISSetupStream`-formatted. 7-Zip's `PE` handler matches the SFX EXE shell and returns exit 0, but only extracts the EXE's resource-section files — none of the 35 sub-MSIs reach the destination tree. Strategy 1's `_HasPayload` guard noticed this and triggered Strategy 2 (launch + watch), which is fragile: AMD's installer aggressively cleans up `C:\AMD\` after extraction, often before the watcher can grab the files.

**Fix**: New Strategy 2/3 inserted between the old 7-Zip and launch-watch strategies. The new strategy:

1. 7-Zips the outer NSIS shell to a staging directory (the outer layer remains 7-Zip-extractable).
2. Locates the inner `AMD_Chipset_Drivers.exe` (InstallShield SFX).
3. Invokes the InstallShield SFX with `/a /s /v"TARGETDIR=... GONOGO=PUBLICGO /qn"`, which extracts the parent MSI plus all 35 sub-MSIs into a staging tree without running any install-side CustomActions.
4. Runs `msiexec /a <sub.msi> TARGETDIR=<final dest>` on each sub-MSI to unpack its INF / SYS / CAT tree into the final destination.
5. Emits a per-OS-variant diagnostic showing INF coverage by `W11x64` / `WTx64` / `WTx86` subdirectory, marking the variant preferred for the host OS as `[PREFERRED]`.

After Strategy 2 succeeds, the existing P05 / P06 / I03 pipeline picks up the full INF tree and selects the OS-appropriate variant via `Get-PreferredAmdSourceVariants` (unchanged from earlier revisions).

**Scope**: Chipset only. Graphics and NPU installers use different formats (Graphics is a WIX BURN bootstrapper, NPU is a plain ZIP) and don't need this strategy.

**Renoir-specific note**: Even with the AMD 8.x fix, X13 Gen 1 will see ~27 of the 35 INF packages remain "no device" because their Hardware IDs target Phoenix Point and later CPUs. The ~5-8 packages that DO match real devices are the meaningful coverage improvement. This is expected and documented in B.1's "35 sub-MSIs" table.

---

## D.13 Workspace lock leaked across runs in the same PowerShell console (Chipset / Graphics)

> **Note**: The error message shown below references the pre-relocation workspace path (`C:\AMD-Chipset-WS`) because that is what an earlier chipset revision emitted at the time. Currently, the equivalent message shows `C:\Temp\Workspace_AMD-Chipset` instead. The mechanism described and the fix are unchanged.

**Symptom**: Running the chipset (or graphics) script with `-Action PrepareVerify` and then immediately re-running it (with the same or a different `-Action`) in the **same interactive PowerShell console** failed at P01 with:

```
*** Another instance of this script is already running in workspace C:\AMD-Chipset-WS ***
    PID         : 3088
    StartedAt   : 2026-05-16 23:38:05
    CommandLine : C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe
```

The PID shown (3088) was the PID of the PowerShell host process itself, not of a second script invocation. The first invocation had already completed cleanly.

**Root cause**: The workspace lock file (`<WorkRoot>\.markers\RUN.lock`) was written by `Set-WorkspaceLock` in P01 with the current `$PID`. Cleanup relied solely on a `Register-EngineEvent -SourceIdentifier PowerShell.Exiting` action; this event only fires when the PowerShell **host process** terminates, not when a script returns. In an interactive console (where the host is reused for many script invocations) the lock therefore leaked. Run 2 then ran `Test-WorkspaceLockHeld`, found the leftover lock with PID=3088, called `Get-Process -Id 3088` (which returned the PowerShell host itself), and incorrectly concluded that "another instance is running".

The Graphics script had the same code pattern with the same defect. The NPU script does not have a workspace lock and is unaffected (it uses script scope rather than `$Ctx.Paths.Markers`).

**Fix**: Two complementary changes (defense-in-depth):

1. **Self-PID detection in `Test-WorkspaceLockHeld`** — if the recorded PID in the lock file equals the current `$PID`, the lock is classified as `Stale` with a new `SelfPid=$true` field. `Assert-NoConcurrentRun` then silently supersedes it with an informational `[+] Reusing workspace lock from earlier run in this PowerShell session` message instead of the loud "stale lock" warning intended for crashed prior runs.

2. **`try { ... } finally { Clear-WorkspaceLock ... }` around the main phase loop** — the existing top-level `foreach ($phase in $queue) { ... }` and the run summary block are now wrapped in `try { ... } finally { ... }`. The `finally` calls `Clear-WorkspaceLock -Ctx $Ctx` so the lock file is removed on every exit path (normal completion, phase throw, top-level error). The inner cleanup uses an intentionally empty `catch { }` annotated with `# psa-disable-line PSA3004 -- intentional best-effort cleanup in finally; a failure here must not mask the original exception`.

The two changes are complementary: `try/finally` prevents the lock from leaking on every exit path going forward; the self-PID detection handles the historic case where a legacy leftover lock is encountered, and any future case where a hard `Stop-Process`/`Ctrl-C` bypasses `finally` entirely.

**Scope**: Chipset and Graphics. The NPU script does not implement a workspace lock and is intentionally exempt — see SPEC §A.1.4 cross-script consistency check rules (the lock is not on the cross-script-mandatory list).

---

## D.14 Per-tool installer logs leaked to workspace root (Chipset)

> **Note**: The workspace paths shown in this section use the legacy layout (`C:\AMD-Chipset-WS\`) because that is the path the bug actually surfaced under originally. Currently, the workspace lives at `C:\Temp\Workspace_AMD-Chipset\` instead; the substring after the workspace root (`installshield-admin.log`, `msiexec-admin-*.log`) is unchanged. See SPEC §A.1.4 for the relocation.

**Symptom**: After running `-Action PrepareVerify` on a clean Windows Server 2025 host, the workspace root (`C:\AMD-Chipset-WS\`) contained the following loose log files alongside the documented subdirectory layout (`download\`, `extracted\`, `patched\`, `cert\`, `logs\`, `.markers\`):

```
C:\AMD-Chipset-WS\installshield-admin.log
C:\AMD-Chipset-WS\msiexec-admin-AMD-AS4-ACPI-Driver.log
C:\AMD-Chipset-WS\msiexec-admin-AMD-Consumer_Infrared-Driver.log
C:\AMD-Chipset-WS\msiexec-admin-AMD-GPIO2-Driver.log
C:\AMD-Chipset-WS\msiexec-admin-AMD-I2C-Driver.log
C:\AMD-Chipset-WS\msiexec-admin-AMD-IOV-WT-Driver.log
C:\AMD-Chipset-WS\msiexec-admin-AMD-PCI-Driver.log
C:\AMD-Chipset-WS\msiexec-admin-AMD-PMF-7736Series-Driver.log
C:\AMD-Chipset-WS\msiexec-admin-AMD-PMF-Ryzen-AI-300-Series-Driver.log
C:\AMD-Chipset-WS\msiexec-admin-AMD-PSP-Driver.log
C:\AMD-Chipset-WS\msiexec-admin-AMD-SBxxxSMBus-Driver.log
C:\AMD-Chipset-WS\msiexec-admin-AMD-UART-Driver.log
C:\AMD-Chipset-WS\msiexec-admin-AMD-USB_Filter-Driver.log
```

The workspace already had a `logs\` subdirectory used by P08 (inf2cat), P09 (signtool), V03 (signtool verify), and I03 (pnputil) — but the InstallShield admin install and the per-sub-MSI msiexec admin installs added for AMD 8.x did not route their logs there.

**Root cause**: `Expand-AmdInstaller_ViaInstallShield` (introduced for AMD 8.x) computed `$parentDir = Split-Path $DestinationPath -Parent`. Because the caller (`Invoke-PrepPhase04_ExtractInstaller`) passed `$Ctx.Paths.Extract` (= `<WorkRoot>\extracted`) as `$DestinationPath`, `$parentDir` resolved to `<WorkRoot>` itself. Both `$isLog` and the per-sub-MSI `$subLog` were then computed as `Join-Path $parentDir <filename>`, dropping every log file in the workspace root.

**Fix**: New optional `[string]$LogDir` parameter on `Expand-AmdInstaller` and `Expand-AmdInstaller_ViaInstallShield`. The downstream function resolves a `$logRoot` variable: if the caller passed a `$LogDir` (and the directory exists or can be created), `$logRoot` is set to `$LogDir`; otherwise `$logRoot` falls back to the legacy `$parentDir` for backwards compatibility. Both `$isLog` and `$subLog` are then computed against `$logRoot`. The caller (`Invoke-PrepPhase04_ExtractInstaller`) was updated to pass `-LogDir $Ctx.Paths.Logs`. Existing P08/P09/V03/I03 log files are unaffected (they already wrote to `$Ctx.Paths.Logs`).

**Effect on workspace layout**:

| File                                  | Pre-fix location | Post-fix location          |
| ------------------------------------- | ---------------- | -------------------------- |
| `installshield-admin.log`             | `<WorkRoot>\`    | `<WorkRoot>\logs\`         |
| `msiexec-admin-<sub-MSI>.log` (×12)   | `<WorkRoot>\`    | `<WorkRoot>\logs\`         |
| `inf2cat_<rel>.log` (existing)        | `<WorkRoot>\logs\` | unchanged                |
| `signtool_<rel>.log` (existing)       | `<WorkRoot>\logs\` | unchanged                |
| `verify_<basename>.log` (existing)    | `<WorkRoot>\logs\` | unchanged                |
| `pnputil_<basename>.log` (existing)   | `<WorkRoot>\logs\` | unchanged                |
| `inf_inventory.csv`                   | `<WorkRoot>\`    | unchanged (documented)     |
| `inf_inventory_report.txt`            | `<WorkRoot>\`    | unchanged (documented)     |
| `secureboot_ms_sample\*` (existing)   | `<WorkRoot>\secureboot_ms_sample\` | unchanged |

**Scope**: Chipset only. Graphics does not use the InstallShield admin install / `msiexec /a` chain (its installer is a WIX BURN bootstrapper which uses a single `msiexec /i` invocation). NPU does not use any installer-level logging at this layer.

---

## D.15 Driver-category priority override (BREAKING) + Write-Detail helper (Chipset / Graphics)

**Summary**: Two coupled changes shipped together in a single commit.

### 1. BREAKING: category-priority override in install decision

**Symptom (before the fix)**: On a clean-installed Windows Server 2025 host where Windows had bound its in-box generic drivers (`machine.inf`, `pci.inf`, `hdaudbus.inf`, `cpu.inf`, `display.inf`, etc.) to AMD hardware, V05 / V06 / I03 routinely classified the patched AMD drivers as `SKIP-newer` and refused to install them. The cause is fundamental: Microsoft generic drivers use **OS-build versioning** (e.g. `10.0.26100.1150`) which numerically dominates AMD's **semantic versioning** (e.g. `1.0.47.1`, `5.43.0.0`). Pure version comparison therefore *never* replaces a Microsoft generic with an AMD-vendor driver.

Reported example from a clean WS2025 install (Renoir / Ryzen 5 PRO 4650U):
- `標準電源管理コントローラー` (Standard Power Management Controller) was bound to MS `machine.inf v10.0.26100.1150`. The patched `AmdMicroPEP.inf v1.0.47.1` was correctly classified as `[C] Self-signed` and the device was in scope, but I03 logged `SKIPPED (current driver is same/newer; skipping to avoid downgrade)`.
- `マルチメディア コントローラー` (Multimedia Controller) had `[?] Unknown` driver and the patched `amdacpbus.inf` was likewise skipped because `Compare-InfDriverVer` returned 0 on the empty version string.

**Fix**: Replaced the pure-version comparison in `Resolve-PerDeviceDriverDecision` and `Resolve-PerInfInstallDecision` with a **category-priority override**:

```
Priority order (high -> low):
  [C] Self-signed (this script's output)   = highest
  [B] Hardware vendor / IHV                = middle
  [A] Microsoft (OS in-box)                = lowest
  [?] Unknown / unsigned                   = treated as lowest
```

Because the TO-BE driver produced by this pipeline is always `[C]` (the patched INFs are signed with the script's own certificate at P07/P09), the rule simplifies to:

- **AS-IS in `[A]` / `[B]` / `[?]`** → TO-BE `[C]` always WINS (install regardless of version comparison).
- **AS-IS in `[C]`** → fall back to version comparison (avoid pointless reinstall of an earlier run's self-signed driver).

This is implemented via `Get-DriverSourceCategory -Provider $cur.Provider -Signer $cur.Signer` called at the start of each decision function; the resulting `.Code` is checked against `'C'` before any `Compare-InfDriverVer` call.

**Why this is a BREAKING change**: Previously the pipeline preserved AMD's official `[B]` Vendor drivers when they were the same or newer than the patched `[C]` Self-signed counterpart. Under the current install-decision logic those `[B]` drivers are also replaced. The operator-facing implication:

- **Pro**: the documented behavior of "AMD self-signed drivers on AMD hardware" is now achievable on a clean Server 2025 install in a single `-Action All` run.
- **Con**: any AMD vendor driver previously installed via Windows Update / OEM site will be overwritten by the script's self-signed version of the *same* underlying driver binaries (only the signature publisher changes). If the operator wanted to preserve a vendor driver, they must run `-Action PrepareVerify` first, inspect V06 Section 2, and decide whether to proceed.

**Documentation implications**: the README's "Self-signed drivers are a LAST-RESORT gap-fill, NOT a primary install path" language continues to apply at the *recommendation* level (operators should still run Windows Update and OEM installers first), but the *script's decision logic* no longer enforces it via version comparison.

**Scope**: Chipset and Graphics. The NPU script does not implement install-decision logic at this layer (`-Action Install` on NPU is gated by EULA acknowledgement and runs `pnputil` directly without per-INF version comparison) and is therefore unaffected.

### 2. Write-Detail helper introduction (log-layout uniformity)

**Symptom**: An audit of the chipset script counted 165 occurrences of bare `Write-Host "    ..."` (4-space indented plain text) and the graphics script 154, used in `Show-PowerShellEnvironment`, `Show-SecureBootBaselineSnapshot`, P03 platform inventory, P04 nested-MSI listing, P05 INF inventory table, V05 Dry-Run output, V06 hardware-impact rows, and I00 review. Each call duplicated the indent string and had no central control over color or alignment, making future column-layout tweaks impossible without touching every call site.

**Fix**: Introduced `Write-Detail` immediately after `Write-Skip` in the output helper section:

```powershell
function Write-Detail {
    param(
        [Parameter(Position=0)][string]$Msg,
        [ConsoleColor]$Color = [ConsoleColor]::Gray,
        [switch]$NoNewline
    )
    if ($NoNewline) {
        Write-Host ("    {0}" -f $Msg) -ForegroundColor $Color -NoNewline
    } else {
        Write-Host ("    {0}" -f $Msg) -ForegroundColor $Color
    }
}
```

A one-off Python conversion script (`convert_writehost.py`) was used to mechanically rewrite the bulk of the call sites, with a handful of multi-line / backtick-continuation cases handled manually. The total per-file edits were ~165 line replacements for the chipset script and ~155 for the graphics script. After conversion, 0 bare 4-space `Write-Host` calls remain outside of `Write-Detail`'s own body.

**Documented as the sanctioned exception**: SPEC §A.5 was updated to list `Write-Detail` as the single approved continuation-line helper. Bare `Write-Host "    ..."` is now a SPEC violation.

**Scope**: Chipset and Graphics. The NPU script did not have the same accretion of bare `Write-Host` indentation patterns (audit count: 0) and was not modified at that revision; a later NPU revision introduces console UTF-8 enforcement and CiTool `--json` but does not change the Write-Host pattern profile.

### 3. psa.py baseline drift after the Write-Detail conversion

The mechanical conversion added ~1 trailing-semicolon info finding per file. Baseline at that point (re-measured later in §D.16 below):

| Script | Errors | Warnings | Info | Total |
| ------ | -----: | -------: | ---: | ----: |
| `Deploy-AMDChipsetDriverOnWindowsServer.ps1`  | **8** | 55 | 32 | 95 |
| `Deploy-AMDGraphicsDriverOnWindowsServer.ps1` | **8** | 56 | 38 | 102 |
| `Deploy-AMDNpuDriverOnWindowsServer.ps1`      | **0** | 30 |  0 | 30 |
| `Deploy-MSBthPanInboxOnWindowsServer.ps1`     | **2** | 61 | 32 | 95 |

---

## D.16 CiTool.exe interactive ENTER prompt + Console UTF-8 enforcement

**Symptom (reported on a clean Windows Server 2025 Datacenter / ja-JP)**: Running `-Action Install` on the chipset and graphics scripts produced a hang of roughly 60-75 seconds in I02 (AuthorizeDriverSigning) between the two log lines:

```
[04:32:43] [+1.17s]   [*] Converting XML to .cip binary and deploying to active CI policies...
[04:33:57] [+1m15.2s] [+] Deployed: C:\WINDOWS\System32\CodeIntegrity\CiPolicies\Active\{503860EA-...}.cip
```

Operators reported that pressing **ENTER** in the console caused immediate progression. Tee-Object log captures showed `CiTool: 蜃ｦ逅・・謌仙粥縺励∪縺励◆` (mojibake) at the boundary.

**Investigation (verification trail, 2026-05-17)**: Standalone `Measure-Command` calls on the cmdlets/tools inside `Install-AmdWdacPolicy` showed:

| Component | Solo elapsed | Prompts? |
|---|---|---|
| `ConvertFrom-CIPolicy -XmlFilePath ... -BinaryFilePath ...` | 0.28 s | NO |
| `& CiTool.exe --update-policy <cip>` | 5.6 s (with ENTER press) | **YES — prints "続行するには、Enter キーを押してください"** |
| `& CiTool.exe` (any subcommand) | varies | **YES — every CiTool invocation prints "Press Enter to Exit"** |

The CiTool.exe `--help` output documents an undocumented-in-MS-docs flag (verified ja-JP, WS2025 build 26100, 2026-05-17):

```
グローバル フラグ
  --json
     出力を json として書式設定し、入力を抑制する
     エイリアス: -j
```

I.e. `--json` (or `-j`) instructs CiTool to emit machine-readable JSON **and** suppress the interactive ENTER prompt. This is the canonical non-interactive mode on Windows 11 / Windows Server 2025.

**Two-part root cause**:

1. **CiTool.exe blocks on stdin without `--json`.** All `CiTool.exe --update-policy <cip>` and `CiTool.exe --remove-policy <id>` invocations in `Install-AmdWdacPolicy` / `Uninstall-AmdWdacPolicy` were missing the flag, so each one stalled until the operator pressed ENTER.
2. **Console encoding stayed at cp932.** SPEC §A.5 / §D.5 mandated `[Console]::OutputEncoding = UTF8` but the implementation only *displayed* the current encoding in `Show-PowerShellEnvironment` and never actually set it. The byproduct was that CiTool's UTF-8 stdout was decoded as cp932 (`処理が成功しました` → `蜃ｦ逅・・謌仙粥縺励∪縺励◆`).

**Fix**:

1. **CiTool `--json` flag applied at all 6 call sites** (3 update + 3 remove across Chipset / Graphics / NPU). Output is parsed with `ConvertFrom-Json`; the canonical status line (`OperationResult` / `Status` / `PolicyGUID`) is extracted for `Write-Detail` display, with a raw-stdout fallback when JSON parsing fails.

2. **`Set-ConsoleUtf8` helper added next to `Set-Tls12` (chipset/graphics) / `Set-NetworkProtocol` (NPU)** and called from P00 immediately after TLS setup. Wraps `[Console]::OutputEncoding` / `InputEncoding` / `$OutputEncoding` assignments in `try/catch` for redirected-host compatibility.

3. **I02 output migrated to `Write-Detail`** for the activation method and CiTool status lines (sweep miss from the prior Write-Detail conversion). Re-classified as a sub-fix under §A.5 compliance.

**Verification commands the operator can run to confirm the fix locally** (no script execution required):

```powershell
# (a) CiTool.exe should NOT print "Press Enter to Exit" when invoked with --json
& CiTool.exe --list-policies --json | Select-Object -First 3

# (b) CiTool.exe stdout should NOT garble (after Set-ConsoleUtf8 has run)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$tmpXml = 'C:\Temp\Workspace_AMD-Chipset\cert\AmdSelfSignedSupplementalPolicy.xml'
$tmpCip = "$env:TEMP\verify_$(Get-Random).cip"
ConvertFrom-CIPolicy -XmlFilePath $tmpXml -BinaryFilePath $tmpCip | Out-Null
Copy-Item $tmpCip "$env:windir\System32\CodeIntegrity\CiPolicies\Active\verify_test.cip" -Force
& CiTool.exe --update-policy "$env:windir\System32\CodeIntegrity\CiPolicies\Active\verify_test.cip" --json
# Expected: clean JSON output, no "Press Enter" prompt, no mojibake
```

**Scope**: All three scripts. The same one-line `--json` addition applies to NPU's `Install-WdacPolicy` / `Remove-WdacPolicy` (parallel-named NPU functions; same intent).

**psa.py baseline impact**: The Set-ConsoleUtf8 + CiTool/JSON parse blocks add a small number of trailing-semicolon `PSA4004` info findings. Re-measure after merge:

| Script | Errors | Warnings | Info | Total | Delta vs prior baseline |
| ------ | -----: | -------: | ---: | ----: | --- |
| `Deploy-AMDChipsetDriverOnWindowsServer.ps1`  | **0** | TBD | TBD | TBD | TBD |
| `Deploy-AMDGraphicsDriverOnWindowsServer.ps1` | **0** | TBD | TBD | TBD | TBD |
| `Deploy-AMDNpuDriverOnWindowsServer.ps1`      | **0** | TBD | TBD | TBD | TBD |

The baseline numbers will be updated to specific values in the commit message of the next CI run that exercises `psa.py` against this revision; the **0 errors** invariant is the only gate.

---

## D.17 pnputil exit=259 reclassification (Chipset / Graphics)

**Symptom**: On a clean Windows Server 2025 install, the chipset script's I03 summary reported `52 ok (2 need reboot) / 3 failed`, but the I04 PostInstallVerification immediately afterwards reported `FAILED: 0` and listed the same three devices under `REBOOT_NEEDED`. The summary classification was inconsistent.

**Affected INFs (chipset only)**: `SMBUSamd.inf`, `AMDInterface.inf`, `AmdMicroPEP.inf`. Each had a sibling copy under a different source path (e.g. `Chipset_Software\SMBus Driver\W11x64\` vs `SMBus Driver\W11x64\` — see SPEC §B.1 "AMD 8.x installer architecture / OS variant selection logic"), so `pnputil.exe /add-driver` was invoked twice with effectively the same package contents. The first call returned `exit=0` (or `3010` for reboot-required) and queued the new driver. The second call returned `exit=259` because the driver store now already contained an equivalent package.

**Investigation (verification trail, 2026-05-17)**: The pnputil logs for the three exit=259 cases on WS2025 read:

```
Microsoft PnP ユーティリティ
ドライバー パッケージの追加:  SMBUSamd.inf
ドライバー パッケージが正常に追加されました。
公開名:         oem35.inf
デバイスのドライバー パッケージは最新の状態です:  PCI\VEN_1022&DEV_790B&SUBSYS_508217AA&REV_51\3&2411e6fe&0&A0
ドライバー パッケージの合計:  1
追加されたドライバー パッケージ:  0
```

I.e. pnputil reports the operation as **successful** (`正常に追加されました`) but did not register a *new* package (`追加されたドライバー パッケージ: 0`) because the device is already on the same-or-better driver. The exit code is `0x103` = `259` = `ERROR_NO_MORE_ITEMS`, used here as a "no-op completion" signal — analogous to `ERROR_ALREADY_EXISTS` in idempotent operations.

**Root cause**: The classification table in `Invoke-InstPhase03_InstallDrivers`:

```powershell
$rebootRequired = ($exit -eq 3010)
$isSuccess      = ($exit -eq 0 -or $exit -eq 3010)   # exit=259 fell into the failure branch
```

mapped exit=259 to `failed`. I04's PostInstallVerification reads the actual device state and correctly inferred `REBOOT_NEEDED` (because the first sibling-INF call had queued the binding), creating the I03/I04 divergence.

**Fix**: Reclassify exit=259 as a third success status:

```powershell
$rebootRequired = ($exit -eq 3010)
$isNoOp         = ($exit -eq 259)
$isSuccess      = ($exit -eq 0 -or $exit -eq 3010 -or $exit -eq 259)

$status = if ($isSuccess -and $rebootRequired) { 'reboot-required' }
          elseif ($isNoOp)                      { 'no-op (already present)' }
          elseif ($isSuccess)                   { 'installed' }
          else                                  { 'failed' }
```

Console output for the no-op branch uses `Write-Skip` (DarkGray, marker `[~]`) — SPEC §A.5 "Skip / cached" semantic — rather than `Write-Ok` to clearly distinguish "package was added to the store and bound" from "package was already in the store, nothing changed."

The I03 summary now reports four categories:

```
Driver install: {ok} ok ({reboot} need reboot, {noop} no-op) / {failed} failed / {skipped} skipped (current newer)
```

**I04 alignment**: PostInstallVerification was already correct (read live device state); no change required.

**Scope**: Chipset and Graphics. The NPU script's I03 path is intentionally simpler (single pnputil invocation per matched device, no sibling-INF iteration) and the exit=259 code path is not currently exercised. NPU is unaffected by this fix, but the same code pattern would apply if a future revision introduces multi-source INF iteration.

**Why exit=259 is NOT a real failure**:

| Exit code | Meaning | Should script treat as |
|---|---|---|
| `0` | Success, driver added & bound (or queued for binding) | Success |
| `3010` (`ERROR_SUCCESS_REBOOT_REQUIRED`) | Success, REBOOT required to bind | Success + REBOOT |
| `259` (`ERROR_NO_MORE_ITEMS`) | Driver package already present in store; no new package added | Success (no-op) |
| any other non-zero | Real failure (signature rejection, ACL, etc.) | Failure |

**Operator-facing implication**: Pre-fix logs that show "3 failed" on chipset Install runs are NOT actually failures — they are duplicate-INF no-ops. The current (post-fix) logs will report the same scenarios as `no-op (already present)` and the failure count will be 0.

---

## Appendix: How to seed a new sister script from this SPEC

If you are creating a 5th script (e.g. `Deploy-AMDRocmRuntimeOnWindowsServer.ps1`):

1. Copy the most recent existing script (the NPU script is the freshest sister-aligned reference) as your starting template.
2. Replace `$Script:ScriptName`, `$Script:ScriptVersion`, `$Script:ScriptTag`, `$Script:CertSubjectCn`, `$Script:WdacPolicyName`, `$Script:WdacPolicyGuid`, `$Script:WorkRoot` with values specific to your new script.
3. Re-implement only the **domain helpers** section (platform detection, installer resolution, INF inventory filter). Reuse all other sections verbatim.
4. Run `python3 psa.py <new-script>.ps1` (see A.11 for setup) until 0 errors.
5. Add B.5 section to this SPEC.md.
6. Add the new script to `README.md` "What's in the box" table, "Parameters" section, "Risk classification" table — and sync `README.ja.md`.
7. Add a physical-hardware validation scenario to `TESTING.md` covering the target AMD consumer devices for your new script.
8. Add a CHANGELOG.md entry for the new script's initial release.

The goal of the strict sister-script convention is exactly this: a new script should be ~80% boilerplate inheritance and ~20% novel logic.
