# tools/

Development utilities for the `Deploy-AMD-Drivers-For-WindowsServer` repository.

---

## `psa.py` — PowerShell Static Analyzer

A single-file Python 3 static analyzer for PowerShell scripts. Catches the classes of bugs that the regular PowerShell parser doesn't flag at parse time, but which routinely break long-running deployment scripts in surprising ways.

### Why a custom analyzer?

Microsoft ships [PSScriptAnalyzer](https://learn.microsoft.com/en-us/powershell/utility-modules/psscriptanalyzer/overview), which is excellent and should be used too. But PSScriptAnalyzer has two limitations for this project:

1. It requires PowerShell 5.1+ to run (chicken-and-egg if your CI doesn't have Windows / PowerShell yet).
2. It catches a different set of issues — primarily style and best-practice violations. It does **not** by default catch unbalanced braces in 8000-line scripts, undefined variable references that are typos, or `-match` against a bare `$variable` that returns true on `$null`.

`psa.py` is a Python script (running anywhere Python 3 runs) that performs a complementary set of checks specifically tuned for this repository's style. It's not a replacement for PSScriptAnalyzer; it's an extra net.

### Usage

```bash
# Analyze one script
python3 tools/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1

# Analyze both in sequence (typical CI invocation)
python3 tools/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1 && \
python3 tools/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
```

Exit codes:
- `0` — clean (no errors, no warnings)
- `1` — warnings only (CI may treat as soft-fail)
- `2` — errors found (CI must fail)

### Output format

```
==== psa.py: PowerShell Static Analyzer ====
File   : Deploy-AMDChipsetDriverOnWindowsServer.ps1
Lines  : 8680
Issues : 0 errors, 9 warnings, 0 info

---- WARNING (9) ----
  [C7] line  2215: -match against bare $noisePattern - $null pattern returns true
  [C6] line  2300: Start-Process -ArgumentList; prefer ProcessStartInfo
  ...
```

Each issue has a check code (C1–C10), severity, line number, and short message.

### Checks implemented

| Code | Severity | What it catches | Why it matters |
| --- | --- | --- | --- |
| **C1** | error | Brace balance: `{` count vs `}` count | A single unmatched brace in an 8000-line script is impossible to debug by eye. The parser reports it as a syntax error at EOF, not at the actual mismatch. psa.py reports both counts so you can `grep -n '^[}]'` and trace. |
| **C2** | error | Paren balance: `(` vs `)` | Same as C1 but for `()`. |
| **C3** | error | Bracket balance: `[` vs `]` | Same as C1 but for `[]`. |
| **C4** | warning | Undefined variable references (heuristic) | Catches typos like `$matchedDeviecs` instead of `$matchedDevices`. Heuristic — false positives possible for `$global:` / `$script:` scoped vars assigned elsewhere. |
| **C5** | warning | Auto-variable shadowing | Assigning to `$args`, `$_`, `$matches`, `$null`, etc. silently breaks PowerShell built-ins. The list of auto-vars is from [about_Automatic_Variables](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables). |
| **C6** | warning | `Start-Process -ArgumentList` (without `-PassThru` / `Wait-Process` etc.) | `Start-Process` is convenient but mishandles paths with spaces, gives a poor exit code path, and drops stderr. Prefer `[System.Diagnostics.Process]::Start([ProcessStartInfo]@{...})` for any script that needs reliability. |
| **C7** | warning | `-match` against bare `$variable` (e.g. `$line -match $pattern`) where `$pattern` could be `$null` | `$line -match $null` is `True` and **assigns `$matches = $null`**. Wrap with `[string]::IsNullOrEmpty($pattern)` before matching. |
| **C8** | info | TODO / FIXME markers | Just a reminder of pending work. Not a failure. |
| **C9** | warning | Trailing backtick before empty line | The PowerShell line-continuation backtick is fragile. If the next line is blank (visible) or has trailing whitespace, the continuation breaks silently. |
| **C10** | warning | `-match` against literal empty string `""` or `''` | `$x -match ""` is **always True** for any string, including empty. Almost always a coding mistake. |

### What the analyzer does NOT check

- Cmdlet existence (would require a PowerShell session)
- Type correctness (PowerShell is dynamically typed; this is shell scripting, not C#)
- Module imports (`Import-Module` resolution)
- Function signature correctness (param types, mandatory parameters)
- Best-practice style violations (covered by PSScriptAnalyzer)

### Running PSScriptAnalyzer alongside

If you have PowerShell 5.1+ available, run both:

```powershell
# In addition to psa.py
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser -Force
Invoke-ScriptAnalyzer -Path Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Severity Warning,Error
Invoke-ScriptAnalyzer -Path Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Severity Warning,Error
```

### Adding a new check

The structure of `psa.py` is intentionally minimal. To add a new check `C11`:

1. Add a function `check_yourthing(text)` that returns a list of dicts with keys `severity`, `code`, `line`, `message`.
2. Call it from `main()` and append to `issues`.
3. Document the new code in the table above and in the main `README.md` development-tools section.

The `strip_strings_and_comments(line)` helper is the standard preamble for any check that wants to ignore content inside `''` / `""` / `# ...` — use it.

### CI integration example

GitHub Actions workflow snippet (Linux runner, no Windows / PowerShell required):

```yaml
name: Lint
on: [push, pull_request]

jobs:
  static-analysis:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.x'
      - name: Run psa.py on chipset script
        run: python3 tools/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
      - name: Run psa.py on graphics script
        run: python3 tools/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
```

### License

`psa.py` is released under the same MIT License as the rest of this repository. See [`../LICENSE`](../LICENSE).
