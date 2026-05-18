# Changelog

All notable changes to the four PowerShell scripts in the
**Deploy-Drivers-For-WindowsServer** repository are documented in this file.
This document is the canonical, authoritative log of revision-by-revision
changes; per-script PowerShell files no longer carry inline revision history.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).
This project does not follow strict [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
because each script is bumped on its own revision counter (`rNN`); release
entries below are tagged `Chipset rNN / Graphics rNN / NPU rNN / BthPan rNN`.
Scripts may be bumped together (cross-script consistency releases) or
independently.

> **For design rationale behind individual fixes** (e.g., *why* the workspace
> lock uses `try/finally` + self-PID detection, *why* `inf2cat` is x86-only,
> *why* `[Console]::OutputEncoding` must be forced to UTF-8 in P00):
> see [`SPEC.md`](./SPEC.md) **Part D — Known Pitfalls & Lessons Learned**.
> This `CHANGELOG.md` captures *when* and *what*; SPEC Part D captures *why*.

---

## [Unreleased]

### Changed
- `.psa.config.json` now opts in to the new opt-in revision-discipline
  rules `PSAP0003` (inline `# rNN:` revision-tag comments) and `PSAP0004`
  (end-of-file `REVISION HISTORY` comment blocks) introduced in
  `psa.py` 3.3.0. Both rules report 0 hits across all four scripts at
  the current baseline; the opt-in ensures that any future commit
  re-introducing inline revision tags or in-script history blocks will
  be flagged by the static-analysis gate.

### Verified

The current baseline against `psa.py` 3.3.0 with this updated config:

| Script | Standard rules | + PSAP0003 / PSAP0004 |
|--------|----------------|----------------------|
| `Deploy-AMDChipsetDriverOnWindowsServer.ps1` | 0 / 0 / 0 | 0 / 0 / 0 |
| `Deploy-AMDGraphicsDriverOnWindowsServer.ps1` | 0 / 0 / 0 | 0 / 0 / 0 |
| `Deploy-AMDNpuDriverOnWindowsServer.ps1` | 0 / 0 / 0 | 0 / 0 / 0 |
| `Deploy-MSBthPanInboxOnWindowsServer.ps1` | 0 / 0 / 0 | 0 / 0 / 0 |

No PowerShell source changes are required; this is a configuration-only
change. The four scripts remain at their respective r60 / r28 / r10 /
r10 revisions.

## [2026-05-18] — Chipset r60 / Graphics r28 / NPU r10 / BthPan r10

**Cross-script consistency pass + psa.py 3.2.0 integration.** No new
pipeline features were added; existing functionality is preserved
end-to-end.

### Added
- New `.psa.config.json` at the repository root that opts in to the
  project-pipeline rules (`PSAP0001` phase-naming, `PSAP0002`
  script-identifier presence) and configures `PSA8001`
  (cross-file function-body drift) to ignore the script-specific
  phase functions.

### Changed
- **AMDNpu helper-function parity**. The NPU script (r9 → r10) gained
  the helper functions that had remained un-ported from the BthPan r9
  work: `Write-Detail` (4-space indented continuation rows),
  `Assert-PowerShellCompatibility` (hard-fail pre-flight separated from
  `Show-PowerShellEnvironment` display), and a hash-matched canonical
  `Show-PowerShellEnvironment` (169 lines, the same body used by
  Chipset / Graphics / MSBthPan). The previous AMDNpu-specific
  `Test-AdminPrivilege` and `Set-NetworkProtocol` are renamed to
  `Assert-Admin` and `Set-Tls12` to match the sister scripts.
- **TLS posture (NPU)**. `Set-Tls12` adopts the canonical
  Chipset / Graphics / MSBthPan body (TLS 1.2 + TLS 1.3 when available;
  **TLS 1.0 / 1.1 are intentionally excluded** per RFC 8996). The
  previous AMDNpu body that enabled `Tls10` / `Tls11` has been
  removed as a security regression.
- **AMDNpu** now ships its own NPU-specific
  `Show-DriverInstallationOrderNotice`, plus simplified
  `Get-BootSigningEnvironment` / `Show-BootSigningEnvironment` stubs
  (Secure Boot + testsigning probe only; full WDAC enumeration remains
  in the Chipset / Graphics / MSBthPan family).
- **psa.py 3.2.0 baseline**. Every PowerShell script in the repository
  now passes `psa.py --config .psa.config.json` with
  **0 errors / 0 warnings / 0 info**. This is the first release where
  the canonical static-analysis baseline is fully clean across all four
  scripts simultaneously.
- **Sister-script consistency enforcement**. `PSA8001` (new in
  psa.py 3.2.0) now actively guards **34 shared helper functions**
  across all four scripts.

### Fixed
- `psa.py` 3.2.0 false-positive fixes (silent). Earlier `PSA1001`
  (brace imbalance) and `PSA2001` (undefined-variable) false positives
  in Chipset / Graphics were psa.py tokenizer bugs around PowerShell's
  `""` (double-quote-doubling) escape and `` `` `` (double-backtick)
  escape, plus mis-handling of `$Script:` scope qualifiers as
  references. Fixed in psa.py 3.2.0; no script-side change required.

---

## [2026-05-17] — Chipset r59 / Graphics r27 / NPU r9 / BthPan r9

**Debug Trace Facility + call-site instrumentation.** The four scripts
share a synchronised release. Each crossed an independent revision
counter, but the substantive changes are the same Debug-Trace-and-resume
bundle, lifted from BthPan's r2-through-r9 work and then ported into
each sister script.

### Added
- **Debug Trace Facility (SECTION 1b, ~882 lines per script)**.
  A reusable diagnostic helper with 14 functions
  (`Start-DebugTrace` / `Set-DebugStep` / `Stop-DebugTrace` /
  `Format-DebugFailure` / `Write-DebugFailureReport` /
  file-output / auto-export-on-failure / JSON snapshot). When a phase
  fails, you get a JSONL stream plus a self-contained snapshot JSON
  under `<WorkRoot>\logs\` showing the exact step that failed.
- **Call-site `Set-DebugStep` checkpoints** placed across every
  P/V/I phase function (~92 calls in Chipset / Graphics, 44 in NPU
  due to its smaller phase bodies, 113 in BthPan).
- **`-ExportTraceOnExit` switch** on the top-level param block of
  every script; writes a final JSON snapshot to `<WorkRoot>\logs\` at
  script exit regardless of success/failure.
- **`Resume-CtxFromWorkspace` rehydration helper**. Lets
  `-Action Verify` / `-Action Install -OnlyPhases ...` run against an
  existing populated workspace without first re-running P02-P09.
- **SECTION 0.25** — `-LogFile` auto-relocation under
  `<WorkRoot>\logs\` when the user provides a path outside the
  workspace, with transcript-verified activation.

### Fixed
- **PS 5.1 ja-JP `Split-Path -LiteralPath` AmbiguousParameterSet bug**.
  Every site uses `[System.IO.Path]::GetDirectoryName()` instead.
- **SECTION 1d numbering conflict** in Chipset / Graphics resolved by
  promoting WDAC → 1e and validators → 1f (Secure Boot baseline stays
  as 1d).
- **`logTag` switch-Wildcard unified**; `amd-` prefix stripped in log
  filename hints for cross-script naming consistency.

---

## [Earlier releases — per script]

The entries below track per-script revision history before the
synchronised 2026-05-17 release. Cross-script alignment commits
(where Chipset, Graphics, and NPU/BthPan crossed revisions together)
are marked **[cross-script]**.

### Deploy-AMDChipsetDriverOnWindowsServer.ps1

#### r58 — Workspace relocation **[cross-script: Graphics r26 / NPU r8 / BthPan r2]**
- Relocated workspace from `C:\AMD-Chipset-WS\` to
  `C:\Temp\Workspace_AMD-Chipset\`. The script auto-creates
  `C:\Temp\` on demand.

#### r57 / Graphics r25 / NPU r7 — CiTool non-interactive + UTF-8 console **[cross-script]**
- **Fixed**: `CiTool.exe --update-policy` blocks on
  `Press Enter to Exit` (60-75s wait). Added `--json` flag for
  non-interactive mode (Microsoft's documented behaviour). See
  [SPEC §D.16](./SPEC.md#d16-chipset-r59--graphics-r27--npu-r9--citoolexe-interactive-enter-prompt--console-utf-8-enforcement).
- **Fixed**: ja-JP console mojibake of CiTool UTF-8 output. P00 now
  calls `Set-ConsoleUtf8` which forces `[Console]::OutputEncoding`,
  `[Console]::InputEncoding`, and `$OutputEncoding` to UTF-8.
- **Fixed**: pnputil exit=259 misclassified as `failed`. New
  `no-op (already present)` status surfaced via `Write-Skip [~]`. See
  [SPEC §D.17](./SPEC.md#d17-chipset-r57--graphics-r25--pnputil-exit259-reclassification).
- **Migrated**: I02 bare `Write-Host '    Activation method: ...'`
  to `Write-Detail` for SPEC §A.5 compliance.

#### r56 / Graphics r24 — Driver-category priority override (BREAKING) **[cross-script]**
- **BREAKING**: At install-decision layer the script now ranks
  `[C] Self-signed` outranks `[B]/[A]` in certain device-category
  scenarios. See [SPEC §D.15](./SPEC.md#d15-chipset-r56--graphics-r24--driver-category-priority-override-breaking--write-detail-helper)
  for the full motivation and operator guidance.
- **Added**: `Write-Detail` helper for SPEC A.5 compliance.

#### r55 / Graphics r23 — Workspace lock + log directory fixes **[cross-script]**
- **Fixed**: Workspace lock leaked across runs in the same PowerShell
  console (the lock cleanup relied on `Register-EngineEvent PowerShell.Exiting`
  which never fires inside an interactive console). Fixed by
  (a) self-PID detection in `Test-WorkspaceLockHeld` and
  (b) wrapping the main phase loop in
  `try { ... } finally { Clear-WorkspaceLock ... }`. See
  [SPEC §D.13](./SPEC.md#d13-chipset-r55--graphics-r23--workspace-lock-leaked-across-runs-in-the-same-powershell-console).
- **Fixed (Chipset only)**: r54's `Expand-AmdInstaller_ViaInstallShield`
  dropped `installshield-admin.log` and 12 per-sub-MSI
  `msiexec-admin-*.log` files at the workspace root. Added optional
  `-LogDir` parameter. See
  [SPEC §D.14](./SPEC.md#d14-chipset-r55--per-tool-installer-logs-leaked-to-workspace-root).

#### r54 — AMD Chipset Software 8.x extraction
- **Added**: Two-layer installer architecture support for AMD Chipset
  Software 8.x (8.02.18.557 and later). The installer wraps an
  InstallShield SFX inside an NSIS shell that 7-Zip alone cannot fully
  unpack; r54 adds a dedicated `InstallShield /a + recursive msiexec /a`
  strategy. See
  [SPEC §D.12](./SPEC.md#d12-chipset-r54--installshield-sfx-extraction-for-amd-8x-installers).
- **Added**: Per-OS-variant INF coverage diagnostic
  (`W11x64\` for WS2025/2022; `WTx64\` for WS2019/2016).

#### r52 — Robocopy migration
- **Fixed**: PowerShell `Copy-Item` wildcard quirk in patched-INF
  staging. Replaced with `robocopy` for reliability.

#### r51 — WDAC XML FileRulesRef stripping
- **Fixed**: WDAC supplemental policy XML retained an empty
  `<FileRulesRef>` container after `New-CIPolicy` produced no file
  rules. Now strip the entire `<FileRulesRef>` container.

#### r50 / Graphics r19 / NPU r5 — UEFI Secure Boot baseline polish **[cross-script]**
- **Removed**: `%TEMP%` fallback from P00.
- **Added**: `Get-OrEnsureSecureBootBaseline` helper that re-captures
  when the cached snapshot's diagnostic file is missing.

#### r49 / Graphics r18 / NPU r4 — UEFI Secure Boot baseline (initial) **[cross-script]**
- **Added**: 6 core functions byte-identical across the three scripts
  plus a per-script `Get-OrEnsureSecureBootBaseline` helper and
  5 integration points (P00, P05, V05, V06, I02). See
  [SPEC §A.14](./SPEC.md#a14-uefi-secure-boot-baseline-cross-script-feature)
  and [SPEC §D.9](./SPEC.md#d9-uefi-secure-boot-baseline-feature-chipset-r49r50--graphics-r18r19--npu-r4r5).
- **Three corrective fixes applied during validation**:
  (a) `schtasks.exe /Query /FO CSV` ja-JP-localized headers replaced
  with `Get-ScheduledTask`. (b) MS sample script's `-OutputPath`
  validator regex rejects absolute Windows paths — added stdout-JSON
  fallback. (c) `Show-...` and V06 caller printed duplicate banners —
  removed inner banner.

#### r48 / Graphics r17 / NPU r3 — WDAC + cert standardisation **[cross-script]**
- **Changed**: Code-signing certificate filename standardised to
  `cert\AMD-{Chipset|Graphics|NPU}-Driver-CodeSign.{pfx,cer}`. See
  [SPEC §D.7](./SPEC.md#d7-code-signing-certificate-filename-standardization-chipset-r48--graphics-r17--npu-r3).
- **Changed**: WDAC supplemental policy `PolicyID` standardised to
  per-script fixed GUIDs (previously generated dynamically).
- **Fixed (Graphics only)**: `SupplementsBasePolicyID` corrected from
  non-standard `{B355481F-...}` to Microsoft's
  `{A244370E-44C9-4C06-B551-F6016E563076}`. See
  [SPEC §D.8](./SPEC.md#d8-wdac-supplemental-policy-guid-standardisation-chipset-r48--graphics-r17--npu-pre-existing).

#### r46 — DriverDate timezone fix
- **Fixed**: V05 dry-run plan reported `[UPGRADE]` action on identical
  drivers due to UTC midnight `DriverDate` converted to local time.
  Now compares `.Date` truncation only. See
  [SPEC §D.1](./SPEC.md#d1-chipset-r46--timezone-induced-driverdate-false-positives).
- **Changed**: P05 / P00 compatibility check now shows actual
  `Caption` plus mapped profile side by side.

#### r43 / Graphics r11 — INF Mfg parser sync **[cross-script]**
- **Fixed**: LHS character class in Mfg-section regex differed between
  chipset and graphics parsers; brought into sync.

#### r42 / Graphics r9-r10 — Multi-mfg INF collection **[cross-script]**
- **Fixed**: Collect ALL `[Manufacturer]` sections from a multi-mfg
  INF, not just the first. Diagnostic fields `ManufacturerEntries`
  and `ModelsSectionsScanned` exposed in the INF inventory.

#### r37 — Filter classification refinement
- **Changed**: `MFG_ONLY` bucket boundary refined to include drivers
  with explicit hardware-ID entries even when no Models section
  resolves.

#### r35 — Provider-trust BUGFIX
- **Fixed**: Function previously trusted `Signer` field for "AMD
  hardware running on a Microsoft generic driver" classification.
  Now trusts `Provider` field instead.
- **Added**: `mshdc.inf` to the generic IDE/AHCI host controller
  exclusion list.

#### r34 — Slash-separated header form
- **Changed**: Output header switched to slash-separated form per user
  request.

#### r33 — AMD hardware detection wording
- **Changed**: User-facing description refined to
  `"AMD hardware running on a Microsoft generic driver"`.

#### r32 — Version-aware skip + KEPT_CURRENT disposition
- **Added**: `KEPT_CURRENT` disposition for cases where the patched
  driver would be older than the installed driver. Version-aware
  skip preserves current driver intact.

#### r31 — HWID wildcard scoping
- **Fixed**: HWID lookup wildcard `$baseName.*` could match unrelated
  files. Tightened to literal HWID-string match.

#### r30 — Parameter rename + alias map
- **Changed**: `-EnableTestSigning` renamed to
  `-AuthorizeDriverSigning` (the previous name implied
  `bcdedit /set testsigning on` which is no longer the default
  posture on Windows Server 2022+; the actual posture is WDAC
  supplemental policy).
- **Added**: Alias map so older callers don't break.

### Deploy-AMDGraphicsDriverOnWindowsServer.ps1

Graphics-specific revisions (cross-script entries above also apply):

#### r16 / r47 (Graphics-only) — V05 dedup + version-comparison messaging
- **Fixed**: V05 "would upgrade 1067/1067 matched device(s)" inflation.
  `$matchedDevices` was being appended per INF HWID variant rather
  than per physical device. Fixed by deduplication on physical
  DeviceID.
- **Fixed**: Same-version, newer-date upgrade case formerly produced
  the nonsensical `patched newer (X) than current (X)` message. Now
  displays `patched same version (X) but newer date; PnP ranking
  prefers newer-dated driver`.

#### r14 → r16 — early validation iterations
- Early validation runs on ThinkPad X13 Gen 1 AMD (Win11 24H2 used
  as WS2025 preview).

### Deploy-AMDNpuDriverOnWindowsServer.ps1

#### r8 — Workspace relocation **[cross-script with Chipset r58]**
- Relocated workspace from `C:\AMD-NPU-WS\` to
  `C:\Temp\Workspace_AMD-NPU\`.

#### r5 — Find-Inf2CatPath + NpuOverride fixes
- **Fixed**: `Find-Inf2CatPath` delegated to `Find-ToolPath` which
  filters to `\x64\` or `\amd64\` directories. `inf2cat.exe` ships
  **exclusively as an x86 binary** under the Windows SDK/WDK tree.
  Replaced helper body with x86-aware tree walk. See
  [SPEC §D.10](./SPEC.md#d10-npu-r5--find-inf2catpath-x64-filter-bug).
- **Fixed**: `[ValidateSet]` on `-NpuOverride` rejected the default
  empty string, emitting a noisy warning. Added `''` to the set. See
  [SPEC §D.11](./SPEC.md#d11-npu-r5--npuoverride-validateset-excludes-empty-string).

#### r2 — Sister-script alignment refactor
- **Changed**: Renamed `Show-PhaseHeader` to `Write-PhaseHeader`,
  adopted Magenta `=`×72 + script-tag DarkGray line. Now identical
  across all three scripts. See
  [SPEC §D.3](./SPEC.md#d3-npu-r2--show-phaseheader-vs-write-phaseheader-naming-drift).
- **Changed**: `-Action Install` semantics corrected to Inst-phases
  only; added `-Action All` for the full pipeline. Workstation OS
  guard fires on both `Install` and `All`. See
  [SPEC §D.4](./SPEC.md#d4-npu--action-install-semantic-drift).

#### r1 — Initial NPU script
- **Added**: NPU (Ryzen AI XDNA) driver pipeline (PHX/HPT/STX/KRK
  platforms). Source: AMD Ryzen AI Software ZIP, ~250 MB,
  EULA-gated download. Kernel-mode driver only — does NOT install
  Ryzen AI Software user-mode stack.
- **Known issue carried forward**: Hypothetical filename
  `NPU_RAI1.7.1_380_WHQL.zip` mapping to RAI 1.7.1 was incorrect.
  Fixed in later revisions. See
  [SPEC §D.2](./SPEC.md#d2-npu-r1--hypothetical-filename-npu_rai171_380_whqlzip).

### Deploy-MSBthPanInboxOnWindowsServer.ps1

#### r9 — cosmetic logTag / log-filename fix
- **Fixed**: P00 Workstation-preview "RECOMMENDED USAGE" hint printed
  log filename suggestions of the form
  `C:\Temp\amd-<tag>-Win11-preview.log`. Replaced the binary
  graphics/chipset selector with a `switch -Wildcard` covering
  graphics-* / chipset-* / npu-* / msbthpan-* / default, and removed
  the `amd-` prefix.

#### r8 — validation-completed release
- **Added**: Debug Trace Facility (frame/step model with
  `Start-DebugTrace` / `Set-DebugStep` / `Stop-DebugTrace`,
  JSONL streaming, auto-export on phase failure, `-ExportTraceOnExit`
  final snapshot). This work was later ported into the AMD sister
  scripts in the 2026-05-17 release.
- **Added**: P01 `Resume-CtxFromWorkspace` rehydration helper.
- **Added**: SECTION 0.25 `-LogFile` auto-relocation guard.
- **Fixed**: 7 `$Ctx` properties pre-declared at object creation
  so PowerShell strict-mode property assignment does not raise
  "property does not exist".
- **Fixed**: PS 5.1 `Split-Path -LiteralPath -Parent`
  AmbiguousParameterSet workaround using
  `[System.IO.Path]::GetDirectoryName()`.
- **Fixed**: Ghost-call sweep — I-phase function calls systematically
  cross-checked against function param blocks. Fixed I00
  `Show-BootSigningEnvironment -Ctx → -BootEnv`, I01
  `Test-CertAlreadyTrusted -Thumbprint → -Ctx`, I03
  `Set-PendingRebootMarker -Phase → -Source`.

#### r7 — validation-first build
- **Added**: `InfVerif` integration + `Provider` rewrite (F1) +
  `CatalogFile` injection (F2) + `makecat` fallback (F3) for inbox
  driver re-cataloging.
- **Fixed**: PS 5.1 ja-JP build 26100.32860 `ArgumentException` for
  `@(List[object])` hashtable cast via `.ToArray()`.
- **Changed**: `-Mode` `[ValidateSet]` empty-string removed; not a
  documented InfVerif behaviour.

#### r6 — unblocked P00-P07
- **Fixed**: P00 through P07 unblocked; revealed `inf2cat`
  signability test conflicts (22.9.4 / 22.9.8), addressed in r7
  by `makecat` fallback.

#### r2-r5 — initial debug iterations
- **Fixed**: P03 driver discovery on `bthpan.inf_amd64_*` directory.
- **Fixed**: `$Ctx` property bugs during initial bring-up.
- **Fixed**: `Format-Elapsed` return type.
- **Fixed**: Transcript bind ordering.

#### r1 — Initial BthPan script
- **Added**: Microsoft inbox Bluetooth PAN driver (`bthpan.inf` /
  `bthpan.sys`) enablement pipeline. Source: the host's own
  `C:\Windows\System32\DriverStore\FileRepository\bthpan.inf_amd64_*`
  directory — no remote download required. Single INF, single HWID
  (`BTH\MS_BTHPAN`). Distinguishes Phantom OK (bth.inf proxy match)
  from true resolution (Class=Net, Service=BthPan) on Windows Server.

---

## Cross-script consistency releases

The four scripts have crossed revision counters together during these
synchronised releases:

| Date | Chipset | Graphics | NPU | BthPan | Theme |
|---|---|---|---|---|---|
| 2026-05-18 | r60 | r28 | r10 | r10 | Cross-script consistency pass + psa.py 3.2.0 integration |
| 2026-05-17 | r59 | r27 | r9  | r9  | Debug Trace Facility + call-site instrumentation |
| (Earlier) | r58 | r26 | r8 | r2 | Workspace relocation under `C:\Temp\Workspace_*` |
| (Earlier) | r57 | r25 | r7 | —  | CiTool `--json` + Console UTF-8 enforcement |
| (Earlier) | r56 | r24 | —  | —  | Driver-category priority override (BREAKING) |
| (Earlier) | r55 | r23 | —  | —  | Workspace lock + log directory fixes |
| (Earlier) | r50 | r19 | r5 | —  | UEFI Secure Boot baseline polish |
| (Earlier) | r49 | r18 | r4 | —  | UEFI Secure Boot baseline (initial) |
| (Earlier) | r48 | r17 | r3 | —  | WDAC supplemental policy GUID + cert filename standardisation |
| (Earlier) | r43 | r11 | —  | —  | INF Mfg parser sync |
| (Earlier) | r42 | r9-r10 | — | — | Multi-mfg INF collection |

---

## Discovered bugs and fix history (validation-discovered)

These bugs were found in physical-hardware validation runs and tracked
back to specific revisions. Validation environments include
ThinkCentre M75q Tiny Gen 2 (WS2025) and ThinkPad X13 Gen 1 AMD
(Win11 LTSC 2024).

| Discovery environment | Found-in | Fixed-in | Summary |
|---|---|---|---|
| ThinkPad X13 Gen 1 (Win11 24H2) | Chipset r45 | r46 | Timezone bug in `Compare-InfDriverVer` (UTC midnight `DriverDate` converted to local 09:00, causing same-version to report as "current newer than patched"). See SPEC §D.1. |
| ThinkPad X13 Gen 1 (Win11 24H2) | Chipset r45 / Graphics r14 | r46 / r15 | P05 / P00 displayed `Host OS: Windows Server 2025` even on Workstation hosts. Now shows actual `Caption` plus mapped profile side by side. |
| ThinkPad X13 Gen 1 (Win11 24H2) | Graphics r14 | r16 / r47 | V05 "would upgrade 1067/1067 matched device(s)" inflation. Fixed by deduplication on physical DeviceID. |
| ThinkPad X13 Gen 1 (Win11 24H2) | Graphics r14 | r16 / r47 | Same-version, newer-date upgrade case formerly produced `patched newer (X) than current (X)`. Now displays meaningful diagnostic. |
| Lab (WS2025, ja-JP) | Chipset r49 | r49 polish, r50 | Three corrections during initial Secure Boot baseline rollout: ja-JP-localized `schtasks.exe /FO CSV` headers, MS sample script absolute-path validator rejection, duplicate banner. |
| Lab (WS2025, ja-JP) | Chipset r49 / Graphics r18 / NPU r4 | r50 / r19 / r5 | Polish patch: P00 wrote diagnostic files to `%TEMP%` when the workspace had not been created yet. Replaced with workspace-co-located diagnostics. |
| Lab (WS2025, ja-JP) | NPU r4 | r5 | `Find-Inf2CatPath` filtered to `\x64\` / `\amd64\` directories, but inf2cat.exe is x86-only. P02 always failed. See SPEC §D.10. |
| Lab (WS2025, ja-JP) | NPU r4 | r5 | `[ValidateSet]` on `-NpuOverride` rejected the default empty string. See SPEC §D.11. |
| Clean WS2025 install (interactive console) | Chipset r54 / Graphics r19-r22 | Chipset r55 / Graphics r23 | Workspace lock leaked across runs in the same PowerShell host. See SPEC §D.13. |
| Clean WS2025 install | Chipset r54 | r55 | r54's `Expand-AmdInstaller_ViaInstallShield` dropped `installshield-admin.log` and 12 per-sub-MSI `msiexec-admin-*.log` files at the workspace root. See SPEC §D.14. |

---

## Conventions

- **Revision bump triggers** (per `SPEC.md` A.13 *Revision discipline*):
  changes to phase semantics, output format, or parameter set.
  Cosmetic-only changes (typo fixes, README rewording) do not require
  a bump.
- **Cross-script consistency requirement**: 34 shared helper functions
  must remain byte-identical across all four scripts. Enforced by
  `psa.py` PSA8001 (cross-file function-body drift detection).
- **Where to put what**:
  - **CHANGELOG.md** (this file) — chronological per-release entries
    ("when" and "what").
  - **SPEC.md Part D** — architectural rationale for individual fixes
    ("why" — root cause, fix design, scope, upgrade impact).
  - **PowerShell script comments** — current behaviour and current
    rationale only. Revision tags (`# r##:`, `# r##+: ...`,
    `REVISION HISTORY` blocks, etc.) belong in CHANGELOG.md, not in
    the script body. `PSAP0003` and `PSAP0004` enforce this in CI.
- **Where the historical record lives**: every concrete patch listed
  here can be retrieved from the Git commit history via
  `git log --grep='rNN' --follow <script>.ps1`. This CHANGELOG is the
  human-readable summary; Git is the authoritative byte-level record.
