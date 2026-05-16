# Contributing to Deploy-Drivers-For-WindowsServer

Thanks for considering a contribution! This is a small, focused project; all kinds of contributions are welcome — bug reports, documentation fixes, new INF parsers, additional verification phases, hardware test reports.

## Filing an Issue

Before opening an issue at <https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/issues>:

1. **Search existing issues** to avoid duplicates.
2. **Run `-Action PrepareVerify -CleanWorkRoot`** and capture the full log via `Tee-Object`. Attach the relevant sections (P03 detection, P05 inventory summary, V06 hardware impact) — not the entire 8000+ line log. Redact the cert PFX path / thumbprint if you don't want them public (the thumbprint by itself is not sensitive, but personalising it helps nobody).
3. **State your platform clearly**:
   - Host OS: `(Get-CimInstance Win32_OperatingSystem).Caption` + build
   - CPU: `(Get-CimInstance Win32_Processor).Name`
   - Subsystem: BIOS vendor / model
   - Whether Secure Boot / HVCI / BitLocker is enabled
4. **Include the script versions**: top of each script has `# Version: rNN`.

### Issue templates

**Bug report**:

```
**Environment**
- OS:      Windows Server 2025 (build 26100) / Win11 24H2 / ...
- CPU:     AMD Ryzen 7 PRO 5750GE (Cezanne)
- Script:  Deploy-AMDChipsetDriverOnWindowsServer.ps1 r57
           (or Graphics r25, or NPU r7 — see top-of-file $Script:ScriptVersion)
- Phase:   V06 (or specific phase ID where it fails)

**What happened**
Pasted log excerpt (10-50 lines around the failure):
```
[copy-paste here]
```

**What I expected**
[short description]

**Already tried**
- [ ] Re-ran with `-CleanWorkRoot`
- [ ] Re-ran with a single `-OnlyPhases <ID>`
- [ ] Verified network reachability to amd.com / download.microsoft.com
```

**Feature request**:

```
**Use case**
Why is this needed? Which AMD platform / Windows SKU does it benefit?

**Proposed change**
What phase / function would change? New phase needed, or extend existing?

**Alternatives considered**
Any workaround that exists today?
```

## Pull Requests

### Before opening a PR

1. **Run the static analyzer**: `python3 psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1` (and the other two scripts) and confirm 0 errors. The post-r56 / r24 documented baseline in [SPEC.md §A.11.5](./SPEC.md#a115-documented-baseline-warnings-and-info) is 0 errors / 52 warnings / 32 info (chipset), 0 / 53 / 37 (graphics), 0 / 26 / 0 (NPU). Warnings within the baseline are acceptable; any drift must be justified in the PR description. `psa.py` is not bundled in this repository — obtain it per [SPEC.md §A.11](./SPEC.md#a11-static-analysis-with-psapy) (`git clone` of the canonical [`ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts) repo, or single-file `curl` of `psa.py`).
2. **Run `-Action PrepareVerify -CleanWorkRoot`** on a real Windows host with the target AMD consumer devices (see [TESTING.md](./TESTING.md)) and confirm the full P00-V06 pipeline completes without errors. Because this pipeline targets AMD consumer hardware, meaningful PR validation requires physical access to such devices.
3. **Update relevant docs** (`README.md`, `README.ja.md`, `TESTING.md`, `TESTING.ja.md`, `SPEC.md`, `SPEC.ja.md`) if you change user-visible behaviour, phase semantics, output format, or parameter sets. Keep English / Japanese mirrors in the same PR (see [SPEC.md §A.12](./SPEC.md#a12-bilingual-documentation)).
4. **Bump the revision** (`$Script:ScriptVersion` and `$Script:ScriptTag`) when changing phase semantics, output format, parameter set, or install-decision logic (see [SPEC.md §A.13](./SPEC.md#a13-development-workflow)). Cosmetic-only changes (typo fixes in messages, README rewording) do not require a revision bump.
5. **Behaviour-breaking changes** (e.g. the chipset r56 / graphics r24 category-priority override in SPEC §D.15) must be called out in `README.md` §Disclaimer with operator-facing implications, and require an explicit Part D entry in `SPEC.md` describing the symptom, root cause, and rationale.

### Code style

- **PowerShell**: follow the existing style — Verb-Noun cmdlets, `[CmdletBinding()]` for non-trivial functions, `[OutputType(...)]` where it adds clarity, brace on the same line as the opening keyword (`if (cond) {`), 4-space indent, no tabs.
- **Marker / log convention** (see [SPEC.md §A.5](./SPEC.md#a5-logging-conventions)): every event line uses `Write-Step` / `Write-Ok` / `Write-Warn2` / `Write-Fail` / `Write-Skip`. Continuation rows inside a section-banner table use `Write-Detail` (4-space indent, no marker, optional `-Color` / `-NoNewline`). Bare `Write-Host "    XXX"` is a SPEC violation as of chipset r56 / graphics r24.
- **Comments**: explain *why*, not *what*. The "why" is harder to reverse-engineer than the "what".
- **No external dependencies**: keep the scripts standalone. Anything beyond the PowerShell standard library + `winget` for SDK/WDK install needs a strong justification.
- **PowerShell 5.1 compatibility**: the scripts must run on stock Windows PowerShell 5.1 (Desktop edition). Avoid PowerShell 7+ specific syntax (`??`, `?.`, ternary `?:`, etc.). The static analyzer (psa.py) is Python 3 and has no such restriction.

### Testing your change

Minimum smoke test:

```powershell
# 0. (one-time) Obtain psa.py from the canonical repository — see SPEC.md §A.11.
#    Either: git clone https://github.com/usui-tk/ai-generated-artifacts.git ../ai-generated-artifacts
#    Or:     curl -sSLO https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py

# 1. Run static analyzer (Linux / WSL / macOS / Windows with Python 3) on all four scripts
python3 psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
# Expected: 0 errors on all four; warnings/info must match SPEC §A.11.5 baseline.

# 2. PrepareVerify on a Windows test host with the target AMD consumer devices
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot
# NPU script only when physical Ryzen AI hardware is available:
# .\Deploy-AMDNpuDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot `
#     -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip
```

For PRs touching specific phases:

- **P03 (FetchInstaller)** changes: include the `Probe results:` block from a real run and confirm the new URL discovery still works against AMD's current site layout.
- **P05 (AnalyzeInfs) / P06 (PatchInfs)** changes: include a representative INF snippet (anonymised if it contains OEM-specific PNP IDs) showing the before / after of the patch.
- **P07 (CreateCertificate)** changes: confirm `signtool verify /pa /v` (against a freshly-generated catalog after I01) prints an unbroken chain.
- **WDAC policy (I02)** changes: confirm `CiTool -lp` lists the new policy with the expected GUID, and `eventvwr → CodeIntegrity` shows no 3076/3077 events for the patched drivers.
- **Install-decision logic (V05 / V06 / I00 / I03)** changes: include the `[Dry-Run I03] InstallDrivers` block from `-Action PrepareVerify`, the V06 Section 2 "AS-IS / TO-BE Driver Comparison" block, and the I03 per-INF summary line from `-Action Install`. If the change affects `Resolve-PerDeviceDriverDecision` or `Resolve-PerInfInstallDecision`, also describe the category-priority interaction with `Get-DriverSourceCategory` ([A] / [B] / [C] / [?]) and whether existing SPEC §D.15 invariants still hold.
- **Post-install verification (I04)** changes: include the AMD device inventory snapshot post-install showing how many devices bind to `[C] Self-signed` vs `[A]` / `[B]`.

### Commit message convention

Follow the [Conventional Commits](https://www.conventionalcommits.org/) loose form:

```
type(scope): subject in imperative

body explaining why, wrapping at ~72 chars.

Refs: #issue-number  (if applicable)
```

Examples:

- `fix(chipset): correct timezone bug in Compare-InfDriverVer`
- `feat(graphics): add Strix Halo platform detection`
- `docs(testing): add ThinkPad T14s Gen 6 AMD validation result`
- `docs: update psa.py canonical-source references after consolidation`
- `feat(chipset,graphics)!: rank [C] self-signed above [B] vendor in install decision` *(breaking; `!` marker convention from Conventional Commits)*

`type` ∈ `fix`, `feat`, `docs`, `chore`, `refactor`, `test`, `perf`. `scope` ∈ `chipset`, `graphics`, `npu`, `docs`, or empty for repository-wide. (Changes to `psa.py` itself live in the canonical [`ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts) repository and use that repo's commit conventions.)

## Hardware test reports

The two physical-machine validation environments documented in [TESTING.md](./TESTING.md) (ThinkCentre M75q Tiny Gen 2 with Cezanne, ThinkPad X13 Gen 1 AMD with Renoir) cover only a small fraction of the AMD consumer ecosystem. **Test reports from other hardware are highly valuable** and welcome as PRs that extend the TESTING.md tables, or as issues with the `[hardware-report]` label.

When submitting a hardware test report, please include:

- The full V05 / V06 output blocks (these are the most informative for cross-platform analysis)
- Whether `-Action Install` succeeded, and if so, post-install Device Manager screenshots showing `[C] Self-signed` bindings
- Any platform-specific quirks observed (BIOS settings, BitLocker behaviour, etc.)

## Security disclosures

If you discover a security issue (e.g. a way for the self-signed cert to be misused beyond the script's intended trust scope), **do not file a public issue**. Email the repository owner directly via the contact info on their GitHub profile, or use GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) feature.

## License

By contributing, you agree that your contribution will be licensed under the [MIT License](./LICENSE) of this repository.
