# Contributing to Deploy-AMD-Drivers-For-WindowsServer

Thanks for considering a contribution! This is a small, focused project; all kinds of contributions are welcome — bug reports, documentation fixes, new INF parsers, additional verification phases, hardware test reports.

## Filing an Issue

Before opening an issue at <https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/issues>:

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
- Script:  Deploy-AMDChipsetDriverOnWindowsServer.ps1 r47
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

1. **Run the static analyzer**: `python3 tools/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1` and confirm 0 errors. Warnings are acceptable but should be justified in the PR description.
2. **Run `-Action PrepareVerify -CleanWorkRoot`** on at least one host (real or AWS EC2 — see [TESTING.md](./TESTING.md)) and confirm the full P00-V06 pipeline completes without errors.
3. **Update relevant docs** (`README.md`, `README.ja.md`, `TESTING.md`) if you change user-visible behaviour or add new switches.
4. **Bump the version comment** at the top of the script (`# Version: rNN+1`) when the change is non-trivial.

### Code style

- **PowerShell**: follow the existing style — Verb-Noun cmdlets, `[CmdletBinding()]` for non-trivial functions, `[OutputType(...)]` where it adds clarity, brace on the same line as the opening keyword (`if (cond) {`), 4-space indent, no tabs.
- **Comments**: explain *why*, not *what*. The "why" is harder to reverse-engineer than the "what".
- **No external dependencies**: keep the scripts standalone. Anything beyond the PowerShell standard library + `winget` for SDK/WDK install needs a strong justification.
- **PowerShell 5.1 compatibility**: the scripts must run on stock Windows PowerShell 5.1 (Desktop edition). Avoid PowerShell 7+ specific syntax (`??`, `?.`, ternary `?:`, etc.). The static analyzer (psa.py) is Python 3 and has no such restriction.

### Testing your change

Minimum smoke test:

```powershell
# 1. Run static analyzer (Linux / WSL / macOS / Windows with Python 3)
python3 tools/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 tools/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1

# 2. PrepareVerify on a Windows test host
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot

# 3. (Optional) Re-run on AWS for environment-independent confirmation
#    See TESTING.md section 1 for the AWS multi-generation EPYC setup
```

For PRs touching specific phases:

- **P03 (FetchInstaller)** changes: include the `Probe results:` block from a real run and confirm the new URL discovery still works against AMD's current site layout.
- **P05 (AnalyzeInfs) / P06 (PatchInfs)** changes: include a representative INF snippet (anonymised if it contains OEM-specific PNP IDs) showing the before / after of the patch.
- **P07 (CreateCertificate)** changes: confirm `signtool verify /pa /v` (against a freshly-generated catalog after I01) prints an unbroken chain.
- **WDAC policy (I02)** changes: confirm `CiTool -lp` lists the new policy with the expected GUID, and `eventvwr → CodeIntegrity` shows no 3076/3077 events for the patched drivers.

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
- `docs(testing): expand AWS EPYC matrix with M8a Turin`
- `chore(tools): bump psa.py auto-var list to include $PSCmdlet`

`type` ∈ `fix`, `feat`, `docs`, `chore`, `refactor`, `test`, `perf`. `scope` ∈ `chipset`, `graphics`, `tools`, `docs`, or empty for repository-wide.

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
