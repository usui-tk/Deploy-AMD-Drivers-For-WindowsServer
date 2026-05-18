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

Form-based issue templates are provided in [`.github/ISSUE_TEMPLATE/`](./.github/ISSUE_TEMPLATE/). When you open a new issue at <https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/issues/new/choose>, GitHub presents the following choices:

| Template | When to use |
|---|---|
| 🐛 **Bug report** | A script does something wrong — a phase fails, output is malformed, a parameter behaves unexpectedly, etc. |
| ✨ **Feature request** | New phase, parameter, platform support, or sister script proposal. |
| 🔧 **Hardware validation report** | You ran the scripts on real hardware (success or failure) and want to share results so the maintainer can close validation gaps in `TESTING.md`. |
| 📖 **Documentation issue** | Factual error, broken anchor link, EN/JA mismatch, missing information in `README.md` / `SPEC.md` / `TESTING.md` / etc. |
| 🛡️ Security advisory (private) | **Not a public Issue** — opens a private Security Advisory thread. See [`SECURITY.md`](./SECURITY.md). |

Blank issues are disabled — please pick the closest template even if not a perfect fit.

## Pull Requests

### Before opening a PR

1. **Run the static analyzer**: `python3 psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1 --config .psa.config.json` (and the other three scripts) and confirm **0 errors / 0 warnings / 0 info** with the repository-shipped `.psa.config.json`. The configuration opts in to the project-pipeline rules (PSAP0001 phase-naming, PSAP0002 script-identifier presence) and explicitly excludes the script-specific phase functions from the cross-file consistency check (PSA8001). The two opt-in revision-discipline rules PSAP0003 (`# rNN:` inline tag detection) and PSAP0004 (`REVISION HISTORY` block detection) must also be clean if enabled. Any drift from the baseline must be justified in the PR description. `psa.py` is not bundled in this repository — obtain it per [SPEC.md §A.11](./SPEC.md#a11-static-analysis-with-psapy) (`git clone` of the canonical [`ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts) repo, or single-file `curl` of `psa.py`).
   - **Recommended pre-flight checks** (cheap, no PowerShell file is analyzed; see [SPEC.md §A.11.6](./SPEC.md#a116-self-quality-gates-for-psapy-consumer-side-usage)):
      - If your PR edits `.psa.config.json`, run `python3 psa.py --config-check .psa.config.json` first and confirm `issues : 0`. This catches typoed rule IDs, unknown top-level keys, type errors, and bad regex patterns before the full analysis pass.
      - If your PR refreshes a locally-cached `psa.py` (i.e., re-fetches from mainline per the §A.11 *Version policy*), run `python3 psa.py --self-check` first and confirm `SPEC.md and RULES are in sync`. This catches partial-fetch accidents (e.g., having an old `SPEC.md` next to a new `psa.py`).
2. **Run `-Action PrepareVerify -CleanWorkRoot`** on a real Windows host with the target AMD consumer devices (see [TESTING.md](./TESTING.md)) and confirm the full P00-V06 pipeline completes without errors. Because this pipeline targets AMD consumer hardware, meaningful PR validation requires physical access to such devices.
3. **Update relevant docs** when you change user-visible behaviour, phase semantics, output format, or parameter sets. Per the repository-wide documentation language policy (see [SPEC.md §A.12](./SPEC.md#a12-documentation-language-policy)):
   - `README.md` is the **English master**; `README.ja.md` is its Japanese translation and **must be kept in sync** in the same PR.
   - `SPEC.md`, `TESTING.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` are **English only** — there are no Japanese counterparts to update.
4. **Add a CHANGELOG.md entry** under a new version section (or extend the "Unreleased" section if one is open) describing the change in a single bullet. The CHANGELOG follows the [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) format; entries go under `Added` / `Changed` / `Fixed` / `Removed` etc. **Do not put revision history into the script body** — the static-analyzer rules PSAP0003 (inline `# rNN:` tags) and PSAP0004 (end-of-file `REVISION HISTORY` blocks) detect this anti-pattern; CHANGELOG.md is the single source of truth for chronological history.
5. **Bump the revision** (`$Script:ScriptVersion` and `$Script:ScriptTag`) when changing phase semantics, output format, parameter set, or install-decision logic (see [SPEC.md §A.13](./SPEC.md#a13-development-workflow)). Cosmetic-only changes (typo fixes in messages, README rewording) do not require a revision bump.
6. **Behaviour-breaking changes** (e.g. the category-priority override in SPEC §D.15) must be called out in `README.md` §Disclaimer with operator-facing implications, and require an explicit Part D entry in `SPEC.md` describing the symptom, root cause, and rationale.

### Code style

- **PowerShell**: follow the existing style — Verb-Noun cmdlets, `[CmdletBinding()]` for non-trivial functions, `[OutputType(...)]` where it adds clarity, brace on the same line as the opening keyword (`if (cond) {`), 4-space indent, no tabs.
- **Marker / log convention** (see [SPEC.md §A.5](./SPEC.md#a5-logging-conventions)): every event line uses `Write-Step` / `Write-Ok` / `Write-Warn2` / `Write-Fail` / `Write-Skip`. Continuation rows inside a section-banner table use `Write-Detail` (4-space indent, no marker, optional `-Color` / `-NoNewline`). Bare `Write-Host "    XXX"` is a SPEC violation.
- **Comments**: explain *why*, not *what*. The "why" is harder to reverse-engineer than the "what".
- **No external dependencies**: keep the scripts standalone. Anything beyond the PowerShell standard library + `winget` for SDK/WDK install needs a strong justification.
- **PowerShell 5.1 compatibility**: the scripts must run on stock Windows PowerShell 5.1 (Desktop edition). Avoid PowerShell 7+ specific syntax (`??`, `?.`, ternary `?:`, etc.). The static analyzer (psa.py) is Python 3 and has no such restriction.

### Testing your change

Minimum smoke test:

```powershell
# 0. (one-time) Obtain psa.py from the canonical repository — see SPEC.md §A.11.
#    Either: git clone https://github.com/usui-tk/ai-generated-artifacts.git ../ai-generated-artifacts
#    Or:     curl -sSLO https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py

# 0a. (recommended; only if .psa.config.json was edited in this PR)
#     Validate the schema of .psa.config.json before running the analyzer.
python3 psa.py --config-check .psa.config.json
# Expected: "issues : 0" — see SPEC §A.11.6.

# 0b. (recommended; only if psa.py was refreshed from mainline in this PR)
#     Verify the freshly-fetched psa.py and SPEC.md are from the same release.
python3 psa.py --self-check
# Expected: "SPEC.md and RULES are in sync (no drift detected)" — see SPEC §A.11.6.

# 1. Run static analyzer (Linux / WSL / macOS / Windows with Python 3) on all four scripts
python3 psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
python3 psa.py Deploy-MSBthPanInboxOnWindowsServer.ps1
# Expected: 0 errors on all four; warnings/info must match SPEC §A.11.5 baseline.

# 2. PrepareVerify on a Windows test host with the target AMD consumer devices
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot
.\Deploy-MSBthPanInboxOnWindowsServer.ps1     -Action PrepareVerify -CleanWorkRoot
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
