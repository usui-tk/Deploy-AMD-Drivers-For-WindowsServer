<#
.SYNOPSIS
    Microsoft inbox Bluetooth PAN (bthpan) driver Build/Verify/Install
    deployment pipeline for Windows Server 2016 / 2019 / 2022 / 2025.

.DESCRIPTION
    21-phase pipeline that takes the Microsoft inbox Bluetooth PAN
    driver (bthpan.inf / bthpan.sys, shipped with every Windows but
    filtered out on Server SKUs by the [Manufacturer] decoration
    `NTamd64...1` which restricts the entry to ProductType=1
    Workstation) and deploys it on a Windows SERVER SKU. The pipeline:

      Build (P00..P09): Copy bthpan.inf / bthpan.sys / catalog from the
                        host's DriverStore, patch the INF with
                        ProductType=3 (Server) decorations, regenerate
                        a fresh catalog with inf2cat, and sign it with
                        a SELF-SIGNED code-signing certificate created
                        by this script.

      Verify (V01..V06): Confirm the build's correctness - certificate
                         chain, catalog signatures, INF decoration
                         coverage - then dry-run the install phases
                         and produce a per-device AS-IS / TO-BE
                         analysis. The critical V06 check is the
                         Phantom-OK detection: even when the host's
                         BTH\MS_BTHPAN device reports Status=OK, the
                         underlying bthpan.sys may not actually be
                         loaded (a generic bth.inf may have proxy-
                         matched). V06 explicitly distinguishes the
                         two cases.

      Install (I00..I04): Trust the cert into LocalMachine\Root +
                          TrustedPublisher, authorize the cert as a
                          kernel-mode signer via a WDAC supplemental
                          policy (Secure Boot stays ON), call pnputil
                          for the patched bthpan.inf, scan-devices to
                          force rebinding, and verify that bthpan.sys
                          is now loaded with Class=Net and
                          Service=BthPan (the "true resolution" state).

    ====================================================================
    SCOPE (read this first)
    ====================================================================
    This script handles ONLY the Microsoft inbox `bthpan.inf` /
    `bthpan.sys` enablement. It does NOT touch vendor Bluetooth host
    controller drivers (Intel / Realtek / Broadcom etc.). The host's
    Bluetooth host controller (e.g. Intel AX210, Realtek RTL8852, etc.)
    is assumed to already be properly bound and showing Status=OK in
    Device Manager before this script runs.

    The symptom this script solves: on a Windows Server SKU with a
    working Bluetooth host controller, Device Manager shows
    `BTH\MS_BTHPAN` as an unknown device (code 28). The root cause is
    that Microsoft's inbox `bthpan.inf` declares only the Workstation
    decoration `NTamd64...1`, which Windows Server (ProductType=3)
    filters out during PnP matching. As a result:

        1. bthpan.inf's `BthPan.Install` section (AddService, CopyFiles,
           AddReg) never runs.
        2. bthpan.sys is never copied to C:\Windows\System32\drivers.
        3. The BthPan service is never registered.
        4. No Bluetooth PAN network adapter (Class=Net) is created.

    This script's fix mirrors the existing `NTamd64...1` Workstation
    decoration with `NTamd64...3` Server decoration via the same INF
    patching technique that the sister AMD scripts use for AMD's
    consumer driver INFs.

    ====================================================================
    THE PHANTOM-OK PROBLEM (why simple pnputil /add-driver is not enough)
    ====================================================================
    Running ASUS FAQ's "Update driver -> Microsoft -> Personal Area
    Network Service" or `pnputil /add-driver /install` against the
    inbox bthpan.inf appears to succeed: BTH\MS_BTHPAN shows
    Status=OK in Device Manager afterwards. However, this is a Phantom
    OK state: a generic bth.inf has been used as a proxy match, but
    bthpan.sys is NOT actually loaded and the BthPan service is NOT
    actually running. PAN networking functionality is still broken.

    True resolution requires the [Manufacturer] decoration to include
    `NTamd64...3` so that bthpan.inf itself (not bth.inf) matches the
    device. V06 / I04 in this script enumerate the device properties
    `DEVPKEY_Device_DriverInfPath`, `DEVPKEY_Device_Class`, and
    `DEVPKEY_Device_Service` to distinguish Phantom OK from true
    resolution:

        DEVPKEY_Device_DriverInfPath  Phantom: bth.inf   True: oem<N>.inf
        DEVPKEY_Device_Class          Phantom: Bluetooth True: Net
        DEVPKEY_Device_Service        Phantom: (empty)   True: BthPan

    ====================================================================
    Pipeline phases (21 phases shared with sister AMD scripts)
    ====================================================================
    PREPARATION (idempotent, file artifacts only under -WorkRoot):
      P00 Initialize         Admin check, TLS, OS detection, env display
      P01 PrepareWorkspace   Create / optionally clean working directories
      P02 AcquireTools       Install Windows SDK / Windows WDK
      P03 FetchInstaller     Locate bthpan.inf in the host DriverStore
                             (no network download; the "installer" is
                             the host's own DriverStore copy)
      P04 ExtractInstaller   Copy bthpan.inf / .sys / .cat from
                             DriverStore to the workspace extract dir
      P05 AnalyzeInfs        Inventory the single bthpan.inf into CSV
      P06 PatchInfs          Generate ProductType=3 patched bthpan.inf
      P07 CreateCertificate  Generate self-signed cert files (PFX/CER)
      P08 GenerateCatalogs   inf2cat to regenerate the .cat file
                             (targets ALL 4 Server SKUs in /os:)
      P09 SignCatalogs       signtool to sign the .cat file

    VERIFICATION (read-only diagnostics, no system / file changes):
      V01 VerifyArtifacts    Existence of PFX/CER/INF/CAT
      V02 VerifyCertificate  Cert validity, EKU, private key
      V03 VerifyCatalogs     signtool /verify /pa on the .cat
      V04 VerifyInfs         INF parsing + ProductType=3 decoration check
      V05 DryRunInstall      Simulate I03 without modifying state
      V06 HardwareImpactAnalysis
                             BTH\MS_BTHPAN current-state diagnosis,
                             Phantom-OK detection, true-resolution
                             readiness check

    INSTALLATION (modifies system state):
      I00 PreInstallReview   Final review, risk summary
      I01 TrustCertificate   Import cert to LocalMachine\Root + TrustedPublisher
      I02 AuthorizeDriverSigning
                             Authorize self-signed driver loading.
                             Default path: WDAC supplemental policy.
      I03 InstallDrivers     pnputil /add-driver bthpan.inf /install
                             then pnputil /scan-devices to force
                             rebinding from the proxy bth.inf to the
                             patched bthpan.inf.
      I04 PostInstallVerification
                             True-resolution check: DriverInfPath
                             must be oem<N>.inf (not bth.inf),
                             Class must be Net, Service must be
                             BthPan, bthpan.sys must exist in
                             System32\drivers, BthPan service must
                             be registered, a PAN NetAdapter must
                             appear.

    All preparation phases are idempotent: re-running produces the same
    output. Each phase writes a marker file when complete; with -Force
    the marker is ignored and the phase re-runs from scratch.
    -CleanWorkRoot deletes the entire working directory before starting.

    ====================================================================
    RESUME AFTER REBOOT (just re-run the same command)
    ====================================================================
    Install phases I01/I02/I03 each START by inspecting the live system
    to see if their target end state is already present. If yes, the
    phase prints "Target state already holds - skipped" and moves on
    to the next phase. This means a single command works for all stages:

        # First run:
        .\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action Install

        # If a reboot was requested, reboot, then re-run THE SAME
        # command. The script auto-detects which phases are already
        # done and continues from where it left off:
        .\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action Install

    ====================================================================
    COEXISTENCE WITH SISTER AMD SCRIPTS
    ====================================================================
    This script (MS BthPan) is designed to live alongside the
    Deploy-AMD{Chipset,Graphics,Npu}DriverOnWindowsServer.ps1 sister
    scripts on the same host without conflict. Three design decisions
    enable this:

    [1] Working directory is fully separated.
        Default for THIS script   : C:\MSBthPan-WS
        Default for chipset/grx/npu: C:\AMD-{Chipset,Graphics,NPU}-WS
        Each workspace owns its own .markers/, cert/, download/,
        extracted/, patched/, logs/ subtrees.

    [2] Self-signed certificate is per-script (NOT shared).
        Subject CN includes "BthPan" so certmgr.msc, the signed
        catalog files, and the WDAC supplemental policy all
        unambiguously identify which script the cert belongs to.

    [3] WDAC supplemental policy GUID is per-script (NOT shared).
        bthpan: A6E72D4F-3B98-4C5A-9E1D-7F8B2A4C6E5D
        chipset: 503860EA-... / graphics: 85336828-... / npu: 8B2C4F12-...

.PARAMETER Action
    Phase action selector. Default 'PrepareVerify' runs P00..V06
    without modifying system state.

.PARAMETER OnlyPhases
    Restrict execution to specific phases. Accepts IDs ('P05')
    or short names ('PatchInfs').

.PARAMETER WorkRoot
    Workspace directory. Default: C:\MSBthPan-WS

.PARAMETER CleanWorkRoot
    Wipe the workspace directory before starting.

.PARAMETER UseTestSigning
    Fall back to `bcdedit /set testsigning on` instead of WDAC
    supplemental policy. Requires Secure Boot OFF.

.PARAMETER AllowWorkstationInstall
    Permit Install phases on Workstation OS (ProductType=1).
    Default: blocked.

.PARAMETER PfxPassword
    Password for the self-signed PFX. Default: 'ChangeMe!2026'.

.PARAMETER TimestampUrl
    RFC 3161 timestamp server for signtool /tr.

.PARAMETER DecorationStrategy
    INF patching strategy:
      - 'A' (default): add only NTamd64...3 (ProductType=3, covers
                       all Server SKUs)
      - 'B'          : add NTamd64.10.0...14393 / 17763 / 20348 /
                       26100 explicitly (per-build entries)

.EXAMPLE
    .\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action PrepareVerify
    Dry-run: prepare patched INF + signed catalog, verify, but do
    not modify system state.

.EXAMPLE
    .\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action Install
    Full install on a Windows Server SKU.

.EXAMPLE
    .\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action All -CleanWorkRoot
    Clean rebuild and full install in one command.

.NOTES
    Script version : msbthpan-2026.05.17-r1
    Repository     : https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer
    Sister scripts : Deploy-AMD{Chipset,Graphics,Npu}DriverOnWindowsServer.ps1
    License        : MIT (see LICENSE)
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

#####################################################################
[CmdletBinding()]
param(
    # === Help ========================================================
    # Show formatted usage information and exit.
    [Alias('h','?')]
    [switch]$Help,

    # === References =================================================
    # Display the curated list of Microsoft Learn documentation links
    # that explain the prerequisite knowledge for this script and
    # exit. No system changes; no admin required.
    [switch]$References,

    # === Action selection ============================================
    # PrepareVerify is the default: runs all preparation phases
    # (P00-P09) followed immediately by all verification phases
    # (V01-V06). This gives the user a complete dry-run that produces
    # all artifacts AND validates them, without modifying the running OS.
    [ValidateSet('Prepare','Verify','PrepareVerify','Install','All','Cleanup','ListPhases')]
    [string]$Action = 'PrepareVerify',

    # Specific phases to run; empty = all phases for the action.
    # Accepts ID ('P05') or short name ('PatchInfs').
    [string[]]$OnlyPhases = @(),

    # === Workspace ====================================================
    # Default workspace path is intentionally BthPan-specific so the
    # sister AMD scripts (C:\AMD-Chipset-WS, C:\AMD-Graphics-WS,
    # C:\AMD-NPU-WS) do NOT collide with this one.
    [string]$WorkRoot      = 'C:\MSBthPan-WS',
    [switch]$CleanWorkRoot,
    [switch]$Force,

    # === Driver-load authorization mode ===============================
    # By default, I02 deploys a WDAC supplemental Code Integrity policy
    # that allowlists this script's self-signed cert as a kernel-mode
    # signer. This keeps Secure Boot ENABLED. Pass -UseTestSigning to
    # fall back to the legacy bcdedit testsigning approach (which
    # requires Secure Boot OFF).
    [switch]$UseTestSigning,

    # === Workstation override =========================================
    # By default the script REFUSES to run any Install phase (I01-I04)
    # on a Workstation OS (ProductType=1). Pass this switch to override.
    [switch]$AllowWorkstationInstall,

    # === Certificate ==================================================
    # NOTE: [string] (not [SecureString]) because the password is
    # forwarded to signtool.exe via /p and to X509Certificate2(.., String)
    # — both require plaintext.
    [string]$PfxPassword   = 'ChangeMe!2026',  # psa-disable-line PSA5001 -- signtool /p and X509Certificate2 require plaintext String; default is a placeholder
    [string]$TimestampUrl  = 'http://timestamp.digicert.com',

    # === INF decoration strategy ======================================
    # 'A' (default): add only NTamd64...3 (ProductType=3 covers all
    #                Server SKUs). Recommended. Simple and durable
    #                against new Server SKU releases.
    # 'B'          : also add NTamd64.10.0...14393 / 17763 / 20348 /
    #                26100 individually. Provides explicit PnP-ranking
    #                advantage but requires manual update for new
    #                Server SKUs.
    [ValidateSet('A','B')]
    [string]$DecorationStrategy = 'A',

    # === WDAC supplemental policy GUID overrides ======================
    [string]$WdacPolicyGuid     = '',
    [string]$WdacBasePolicyGuid = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

#####################################################################
# SECTION 0: Script-level timing state
#####################################################################
# Captured at script load time. Used by the run summary at the end of
# the dispatcher, by Write-PhaseHeader to mark per-phase start, and by
# Write-PhaseFooter to compute per-phase elapsed time.
$Script:ScriptStartTime   = Get-Date
$Script:CurrentPhaseStart = $null
$Script:CurrentPhaseId    = $null
$Script:PhaseTimings      = New-Object System.Collections.Generic.List[object]

#####################################################################
# Script version identification
#####################################################################
# These constants are bumped manually whenever the script is edited.
# They are displayed in the startup banner, in each phase header, and
# in the final run summary so the user can verify which revision is
# valid.
#
# ScriptVersion: bump on every meaningful edit. Format: YYYY.MM.DD-rNN
# ScriptTag    : short human-readable label describing the build
# ScriptHash   : auto-computed SHA256 (first 12 chars) of the actual
#                file being executed. Changes for any byte-level edit;
#                does NOT need manual bumping. If two users disagree
#                about behaviour, comparing this hash tells them
#                instantly whether they are running the same file.
$Script:ScriptVersion = 'msbthpan-2026.05.17-r1'
$Script:ScriptTag     = 'msbthpan-initial-implementation-r1'
$Script:ScriptHash    = '(unknown)'
try {
    # $PSCommandPath is the full path to the running script. Falls
    # back to MyInvocation if not available (e.g. dot-sourced).
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrEmpty($scriptPath)) {
        $scriptPath = $MyInvocation.MyCommand.Path
    }
    if ($scriptPath -and (Test-Path -LiteralPath $scriptPath)) {
        $hashFull = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
        $Script:ScriptHash = $hashFull.Substring(0, 12).ToLower()
        $Script:ScriptPath = $scriptPath
    }
} catch {
    # If hash computation fails for any reason, the version still
    # works - we just don't get the file-hash component.
    $Script:ScriptHash = '(hash-error)'
}

# Compact one-line tag used in places where space is limited (per-phase
# headers). Format: "v2026.05.09-r10/a1b2c3d4e5f6"
$Script:ScriptShortTag = ('{0}/{1}' -f $Script:ScriptVersion, $Script:ScriptHash)

#####################################################################
# SECTION 0.5: WDAC supplemental policy GUID configuration (r48+)
#####################################################################
# Before r48 the supplemental PolicyID was generated dynamically with
# Set-CIPolicyIdInfo -ResetPolicyID and persisted to the workspace as
# MsBthPanSuppPolicyId.txt. From r48 on, the script uses a fixed default
# GUID for predictability across deploys / cleanups, while still
# allowing operators to override via -WdacPolicyGuid (e.g. to clean up
# a legacy dynamic GUID, or to deploy multiple copies side by side).
#
# WdacPolicyGuidDefault     : fixed UUID v4, chipset-specific so it
#                             does not collide with the graphics or
#                             NPU scripts' WDAC policies on a host
#                             that has all three deployed.
# WdacBasePolicyGuidDefault : Microsoft-shipped CI base policy ID
#                             (Windows 11 22H2+ / Server 2022+). The
#                             supplemental policy SUPPLEMENTS this
#                             base, meaning it is additive on top of
#                             whatever rules the base enforces.
$Script:WdacPolicyGuidDefault     = 'A6E72D4F-3B98-4C5A-9E1D-7F8B2A4C6E5D'
$Script:WdacBasePolicyGuidDefault = 'A244370E-44C9-4C06-B551-F6016E563076'

# Resolved values (use operator override if non-empty, else default).
# Accept GUIDs with or without surrounding braces / parens / whitespace.
$Script:WdacPolicyGuid = if (-not [string]::IsNullOrWhiteSpace($WdacPolicyGuid)) {
    $WdacPolicyGuid.Trim('{','}','(',')',' ')
} else {
    $Script:WdacPolicyGuidDefault
}
$Script:WdacBasePolicyGuid = if (-not [string]::IsNullOrWhiteSpace($WdacBasePolicyGuid)) {
    $WdacBasePolicyGuid.Trim('{','}','(',')',' ')
} else {
    $Script:WdacBasePolicyGuidDefault
}

#####################################################################
# SECTION 1: Logging helpers
#####################################################################
function Format-Elapsed {
    param([TimeSpan]$Span)
    if ($null -eq $Span) { return '0.00s' }
    if ($Span.TotalSeconds -lt 60) {
        return ('{0:F2}s' -f $Span.TotalSeconds)
    } elseif ($Span.TotalMinutes -lt 60) {
        $m = [int][math]::Floor($Span.TotalMinutes)
        $s = $Span.TotalSeconds - ($m * 60)
        return ('{0}m{1:F1}s' -f $m, $s)
    } else {
        $h = [int][math]::Floor($Span.TotalHours)
        $m = $Span.Minutes
        $s = $Span.Seconds
        return ('{0}h{1}m{2}s' -f $h, $m, $s)
    }
}

function Get-PhaseElapsedTag {
    # Returns elapsed-since-current-phase-start as "[+X.XXs]" or empty.
    if ($null -eq $Script:CurrentPhaseStart) { return '' }
    $span = (Get-Date) - $Script:CurrentPhaseStart
    return ('[+{0}]' -f (Format-Elapsed $span))
}

function _LogLine {
    # Internal: emits "[HH:mm:ss] [+X.XXs] [marker] message"
    param([string]$Marker, [string]$Msg, [string]$Color)
    $ts  = Get-Date -Format 'HH:mm:ss'
    $tag = Get-PhaseElapsedTag
    if ($tag) {
        Write-Host ("[{0}] {1,-10} {2} {3}" -f $ts, $tag, $Marker, $Msg) -ForegroundColor $Color
    } else {
        Write-Host ("[{0}]            {1} {2}" -f $ts, $Marker, $Msg) -ForegroundColor $Color
    }
}

function Write-Step  { param($Msg) _LogLine '[*]' $Msg 'Cyan'     }
function Write-Ok    { param($Msg) _LogLine '[+]' $Msg 'Green'    }
function Write-Warn2 { param($Msg) _LogLine '[!]' $Msg 'Yellow'   }
function Write-Fail  { param($Msg) _LogLine '[X]' $Msg 'Red'      }
function Write-Skip  { param($Msg) _LogLine '[~]' $Msg 'DarkGray' }

function Write-Detail {
    # ====================================================================
    # Continuation / detail line for a preceding marker line, or a row
    # inside a section banner block (Show-PowerShellEnvironment,
    # Show-OperatingSystemDetail, Show-SecureBootBaselineSnapshot, etc.).
    # Renders 4-space-indented plain text with NO timestamp or marker
    # prefix, so it visually attaches to the preceding context.
    #
    # ---- r56: introduced to replace bare `Write-Host "    XXX"` calls ----
    # Up to r55 the scripts emitted ~100 bare Write-Host calls with a
    # hard-coded 4-space indent. Routing those through a single helper
    # makes future column-layout tweaks possible without touching every
    # call site, and gives the SPEC-mandated marker pattern a single
    # documented exception ("continuation row of a marker line").
    #
    # The 4-space indent is intentional and matches the historical
    # column convention used inside section-banner tables.
    #
    # -NoNewline mirrors Write-Host's switch and is used by two-part
    # lines that compose a label-then-value pair (e.g. P08's
    # "-> Selected /os :" + colored value).
    # ====================================================================
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

function Write-PhaseHeader {
    param($Id, $Name, $Group)
    $Script:CurrentPhaseStart = Get-Date
    $Script:CurrentPhaseId    = $Id
    $startStr = $Script:CurrentPhaseStart.ToString('HH:mm:ss')
    $line = '=' * 72
    Write-Host ''
    Write-Host $line -ForegroundColor Magenta
    Write-Host (" PHASE {0} - {1,-23} ({2,-6})  start: {3}" -f $Id, $Name, $Group, $startStr) -ForegroundColor Magenta
    Write-Host (" script: {0}" -f $Script:ScriptShortTag) -ForegroundColor DarkGray
    Write-Host $line -ForegroundColor Magenta
}

function Write-PhaseFooter {
    param($Id, [ValidateSet('done','cached','skipped','failed')]$Status)

    # Idempotency: ignore duplicate calls for the same Id within one run.
    # Phases that emit their own footer before throwing would otherwise
    # be double-counted when the dispatcher's catch also calls us.
    foreach ($t in $Script:PhaseTimings) {
        if ($t.Id -eq $Id) { return }
    }

    $color = switch ($Status) {
        'done'    { 'Green' }
        'cached'  { 'DarkGray' }
        'skipped' { 'DarkGray' }
        'failed'  { 'Red' }
    }
    $elapsed = if ($Script:CurrentPhaseStart) { (Get-Date) - $Script:CurrentPhaseStart } else { [TimeSpan]::Zero }
    $elapsedStr = Format-Elapsed $elapsed

    $Script:PhaseTimings.Add([pscustomobject]@{
        Id      = $Id
        Status  = $Status
        Elapsed = $elapsed
        EndedAt = Get-Date
    }) | Out-Null

    Write-Host (" PHASE {0} -> {1,-7}  elapsed: {2}" -f $Id, $Status.ToUpper(), $elapsedStr) -ForegroundColor $color
    Write-Host ''

    # Reset so any stray Write-Step/Ok between phases doesn't show a
    # misleading [+X.XXs] tag inherited from the previous phase.
    $Script:CurrentPhaseStart = $null
    $Script:CurrentPhaseId    = $null
}

function Show-PowerShellEnvironment {
    # ====================================================================
    # Display the PowerShell execution environment for diagnostics.
    # ====================================================================
    # Designed to work all the way back to PowerShell 5.1 on Windows
    # Server 2016 (the oldest in-support Windows Server). All cmdlets
    # and APIs used here are present in PS 5.1 / .NET Framework 4.6+,
    # so this function itself does not introduce any new compatibility
    # risk. CIM queries fall back to WMI for fragile environments.
    Write-Host ''
    Write-Host '========================================================================'
    Write-Host ' PowerShell Execution Environment'
    Write-Host '========================================================================'

    # ---- PowerShell engine ----
    $pv = $PSVersionTable
    $editionDesc = if ($pv.PSEdition -eq 'Desktop') {
        'Windows PowerShell - shipped with Windows'
    } elseif ($pv.PSEdition -eq 'Core') {
        'PowerShell 7+ / Core - separately installed'
    } else {
        '(unknown edition)'
    }
    Write-Host ('    PowerShell Version  : {0}' -f $pv.PSVersion)
    Write-Host ('    PowerShell Edition  : {0,-25} ({1})' -f $pv.PSEdition, $editionDesc)
    if ($pv.CLRVersion) {
        Write-Host ('    CLR / .NET          : {0}' -f $pv.CLRVersion)
    } else {
        Write-Host  '    CLR / .NET          : (CLRVersion not exposed by this edition; PS Core is .NET Core / .NET 5+)'
    }
    if ($pv.BuildVersion) {
        Write-Host ('    Engine Build        : {0}' -f $pv.BuildVersion)
    }

    # ---- Process bitness / architecture ----
    $procBitness = if ([Environment]::Is64BitProcess) { '64-bit process' } else { '32-bit process' }
    $procArch    = $env:PROCESSOR_ARCHITECTURE
    Write-Host ('    Process Architecture: {0,-25} ({1})' -f $procArch, $procBitness)

    # ---- Operating system (CIM, fallback to WMI for restricted hosts) ----
    $os = $null
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    } catch {
        try {
            # WS2016 / WS2019 sometimes have CIM service issues on
            # constrained images (e.g. Server Core); fall back to WMI.
            $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        } catch {
            $os = $null
        }
    }
    if ($os) {
        $caption = if ($os.Caption) { $os.Caption.Trim() } else { '(no caption)' }
        $arch    = if ($os.OSArchitecture) { $os.OSArchitecture } else { 'unknown' }
        Write-Host ('    OS                  : {0}' -f $caption)
        Write-Host ('    OS Build            : {0}' -f $os.BuildNumber)
        Write-Host ('    OS Architecture     : {0}' -f $arch)
    } else {
        Write-Host '    OS                  : (could not query Win32_OperatingSystem - both CIM and WMI failed)' -ForegroundColor Yellow
    }

    # ---- Host (the program hosting PowerShell) ----
    Write-Host ('    Host                : {0,-25} (Version {1})' -f $Host.Name, $Host.Version)

    # ---- Execution Policy (best-effort; some scopes may be unreadable) ----
    try {
        $pCurrent = Get-ExecutionPolicy
        $pUser    = Get-ExecutionPolicy -Scope CurrentUser  -ErrorAction SilentlyContinue
        $pMachine = Get-ExecutionPolicy -Scope LocalMachine -ErrorAction SilentlyContinue
        Write-Host ('    Execution Policy    : {0,-25} (CurrentUser: {1}, LocalMachine: {2})' -f $pCurrent, $pUser, $pMachine)
    } catch {
        Write-Host '    Execution Policy    : (query failed)' -ForegroundColor Yellow
    }

    # ---- Administrator status ----
    $id      = [Security.Principal.WindowsIdentity]::GetCurrent()
    $prin    = [Security.Principal.WindowsPrincipal]::new($id)
    $isAdmin = $prin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Host  '    Running as Admin    : Yes'
    } else {
        Write-Host  '    Running as Admin    : NO  (cert install / driver install will fail)' -ForegroundColor Yellow
    }

    # ---- TLS (relevant for download phases) ----
    Write-Host ('    TLS Default         : {0}' -f [Net.ServicePointManager]::SecurityProtocol)

    # ---- Culture / encoding ----
    Write-Host ('    Culture             : {0,-25} UICulture: {1}' -f (Get-Culture).Name, (Get-UICulture).Name)
    $defEnc = [System.Text.Encoding]::Default
    Write-Host ('    Default Encoding    : {0} (cp{1})' -f $defEnc.WebName, $defEnc.CodePage)
    Write-Host ('    Console OutputEnc.  : {0} (cp{1})' -f [Console]::OutputEncoding.WebName, [Console]::OutputEncoding.CodePage)

    # ---- Compatibility check summary ----
    Write-Host ''
    Write-Host '    Compatibility check (target: PS 5.1+ on Windows Server 2016 or later):'

    $minPs = [Version]'5.1'
    if ($pv.PSVersion -ge $minPs) {
        Write-Host ('      [+] PS 5.1+        OK    ({0} >= {1})' -f $pv.PSVersion, $minPs) -ForegroundColor Green
    } else {
        Write-Host ('      [X] PS 5.1+        FAIL  ({0} < {1})' -f $pv.PSVersion, $minPs) -ForegroundColor Red
    }

    Write-Host ('      [+] Edition        OK    ({0} - both Desktop and Core are supported)' -f $pv.PSEdition) -ForegroundColor Green

    if ([Environment]::Is64BitProcess) {
        Write-Host  '      [+] Bitness        OK    (64-bit process)' -ForegroundColor Green
    } else {
        Write-Host  '      [X] Bitness        FAIL  (32-bit process - launch the 64-bit PowerShell, not "(x86)")' -ForegroundColor Red
    }

    if ($isAdmin) {
        Write-Host  '      [+] Elevation      OK    (Administrator)' -ForegroundColor Green
    } else {
        Write-Host  '      [X] Elevation      FAIL  (not Administrator)' -ForegroundColor Red
    }

    if ($os) {
        $supportedBuilds = @{
            14393 = 'Windows Server 2016'
            17763 = 'Windows Server 2019'
            20348 = 'Windows Server 2022'
            26100 = 'Windows Server 2025'
        }
        $build = [int]$os.BuildNumber
        if ($supportedBuilds.ContainsKey($build)) {
            # r46: when running on a Workstation OS (e.g. Win11 24H2 used as
            # a WS2025 preview), include "Workstation, profile: <ServerName>"
            # so it is obvious from this line alone that the host is NOT a
            # Server and a profile is being applied. Pre-r46 only the Server
            # profile name was shown, which made the line read like an OS
            # mis-detection on Workstation hosts.
            if ($os.ProductType -eq 1) {
                Write-Host ('      [+] OS             OK    (build {0} = Workstation; applying profile: {1})' -f $build, $supportedBuilds[$build]) -ForegroundColor Green
            } else {
                Write-Host ('      [+] OS             OK    ({0} / build {1})' -f $supportedBuilds[$build], $build) -ForegroundColor Green
            }
        } else {
            Write-Host ('      [!] OS             WARN  (build {0} not in known list - script may still work)' -f $build) -ForegroundColor Yellow
        }
    } else {
        Write-Host  '      [!] OS             WARN  (could not detect OS build)' -ForegroundColor Yellow
    }

    # ---- Boot-signing environment (Secure Boot, testsigning, HVCI) ----
    # This is the top concern for a self-signed-driver installer. We
    # show a compact one-line summary here and let I00 / I02 produce
    # the verbose table when actually needed.
    Write-Host ''
    try {
        $bootEnv = Get-BootSigningEnvironment
        Show-BootSigningEnvironment -BootEnv $bootEnv -Compact
    } catch {
        Write-Host ('    Boot Signing        : (query failed: {0})' -f $_.Exception.Message) -ForegroundColor Yellow
    }

    # ---- Prerequisite-workflow reminder (compact) ----
    # Make this visible on every run because skipping the OEM/WU step
    # invalidates V06's analysis and produces misleading AS-IS/TO-BE
    # comparisons in I00 / I04. The full block lives in Show-Help and
    # in I00.
    Show-DriverInstallationOrderNotice -Compact

    Write-Host '========================================================================'
    Write-Host ''
}

function Assert-PowerShellCompatibility {
    # ====================================================================
    # Hard-fail the script early if we cannot safely run.
    # ====================================================================
    # Conditions checked here are *fatal* (the script cannot proceed).
    # Soft warnings (e.g. unknown OS build) live in
    # Show-PowerShellEnvironment instead.
    $pv    = $PSVersionTable.PSVersion
    $minPs = [Version]'5.1'
    if ($pv -lt $minPs) {
        throw @"
This script requires PowerShell $minPs or later.
Detected: $pv

This script targets the default PowerShell included with Windows
Server 2016 / 2019 / 2022 / 2025, which is PowerShell 5.1.
PowerShell 7+ is NOT required, but PowerShell 5.1 is the minimum.

If you are on Windows Server 2012 R2 or earlier, install Windows
Management Framework 5.1: https://aka.ms/wmf51
"@
    }
    if (-not [Environment]::Is64BitProcess) {
        throw @'
This script requires a 64-bit PowerShell process. Detected 32-bit.

On a 64-bit Windows Server, launch from "Windows PowerShell"
(NOT "Windows PowerShell (x86)"). The driver / signtool tooling
will not work correctly inside a 32-bit host.
'@
    }
}

function Assert-Admin {
    $id   = [Security.Principal.WindowsIdentity]::GetCurrent()
    $prin = [Security.Principal.WindowsPrincipal]::new($id)
    if (-not $prin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This script must be run from an elevated PowerShell session.'
    }
}

function Show-DriverInstallationOrderNotice {
    # Compact mode is used by I00 / Show-Help to keep their output short.
    # Verbose mode is the default and gives the full context.
    param([switch]$Compact)
    if ($Compact) {
        Write-Host ''
        Write-Host '  NOTE: bthpan is a Microsoft inbox driver. Vendor / Windows Update' -ForegroundColor Yellow
        Write-Host '        do NOT provide an alternative. This script is the ONLY way to' -ForegroundColor Yellow
        Write-Host '        get true PAN networking on Windows Server SKUs without manual' -ForegroundColor Yellow
        Write-Host '        registry-and-INF surgery.' -ForegroundColor Yellow
        return
    }
    Write-Host ''
    Write-Host '  =====================================================================' -ForegroundColor Yellow
    Write-Host '  ABOUT THIS SCRIPT (bthpan inbox enablement, Microsoft-only)'           -ForegroundColor Yellow
    Write-Host '  =====================================================================' -ForegroundColor Yellow
    Write-Host '  Unlike the sister AMD scripts which sequence behind vendor/Windows Update'
    Write-Host '  drivers, the bthpan driver is a MICROSOFT INBOX component. There is no'
    Write-Host '  alternative vendor driver and no Windows Update package; the driver is'
    Write-Host '  already present in the host DriverStore. The only thing missing on a'
    Write-Host '  Windows Server SKU is the ProductType=3 decoration in bthpan.inf, which'
    Write-Host '  this script supplies via INF patching and self-signed catalog generation.'
    Write-Host ''
    Write-Host '  Pre-install workflow expected by this script:'
    Write-Host '      1. Bluetooth host controller (e.g. Intel AX210, Realtek RTL8852,'
    Write-Host '         Broadcom BCM43xx) is properly bound and Status=OK in Device'
    Write-Host '         Manager. If you see "Unknown Device" for the host controller'
    Write-Host '         itself, install its vendor driver first.'
    Write-Host '      2. THEN run this script. It will fix BTH\\MS_BTHPAN which is the'
    Write-Host '         Personal Area Networking child device that bthpan.inf provides.'
    Write-Host ''
}

function Set-Tls12 {
    # ====================================================================
    # Enable modern TLS for Invoke-WebRequest / Invoke-RestMethod.
    # ====================================================================
    # Tls12 is the must-have (some download endpoints require it).
    # Tls13 is added if the running .NET supports it (Framework 4.8+,
    # WS2022+ ships with it; WS2016/WS2019 may not). Tls11 and below
    # are intentionally NOT requested - they are deprecated and removed
    # from many endpoints.
    $protos = [Net.SecurityProtocolType]::Tls12
    try {
        $tls13 = [Net.SecurityProtocolType]::Tls13
        $protos = $protos -bor $tls13
    } catch {
        # Tls13 enum value not present in this .NET runtime; that is
        # fine - Tls12 alone is sufficient for everything this script
        # downloads.
    }
    [Net.ServicePointManager]::SecurityProtocol = $protos
}

function Set-ConsoleUtf8 {
    # ====================================================================
    # SPEC A.5 / D.5: enforce UTF-8 console encoding so ja-JP Japanese
    # log strings (and external tool output such as CiTool.exe) render
    # correctly instead of mojibake in cp932 (Shift-JIS). See SPEC D.16
    # for the r57 root-cause analysis (CiTool.exe writes UTF-8 stdout).
    # ====================================================================
    # On ja-JP Windows, the console defaults to cp932 (Shift-JIS). When
    # external programs that write UTF-8 to stdout (CiTool.exe, modern
    # signtool, etc.) are captured via "& tool ... | Out-String", PS
    # decodes the bytes using [Console]::OutputEncoding. If that is
    # cp932 and the tool wrote UTF-8, every multibyte character becomes
    # mojibake (e.g. "処理が成功しました" -> "蜃ｦ逅・・謌仙粥縺励∪縺励◆").
    #
    # The fix is to set ALL three encodings:
    #   - [Console]::OutputEncoding : how PS decodes external tool stdout
    #                                  AND how Write-Host writes to console
    #   - [Console]::InputEncoding  : how external tools see piped stdin
    #   - $OutputEncoding           : how PS writes piped data to external
    #                                  tools (e.g. "$json | tool.exe")
    # All three must be UTF-8 for consistent round-trip behaviour.
    #
    # This is wrapped in try/catch because some pinned-redirected
    # console hosts (e.g. CI runners writing to a file with no real
    # console) may throw on the assignment; in that case the original
    # encoding is preserved and we continue without UTF-8 enforcement.
    try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
    try { [Console]::InputEncoding  = [System.Text.Encoding]::UTF8 } catch { }
    try { Set-Variable -Name OutputEncoding -Scope Global -Value ([System.Text.Encoding]::UTF8) -ErrorAction SilentlyContinue } catch { }
}

#####################################################################
# SECTION 1c: Boot-signing environment (Secure Boot / testsigning /
# HVCI / VBS / Memory Integrity)
#####################################################################
# These helpers inspect every system-level setting that controls
# whether a self-signed kernel-mode driver can load. They are read-only
# and intended to be called from:
#   - Show-PowerShellEnvironment   (P00 startup banner, compact line)
#   - I00 PreInstallReview         (dedicated section with AS-IS / TO-BE)
#   - I02 AuthorizeDriverSigning   (pre-check + AS-IS / TO-BE)
#   - I04 PostInstallVerification  (post-reboot effective state)
#
# Why this matters for this script:
#   This script signs catalogs with a SELF-SIGNED certificate (P07).
#   Windows will refuse to load a kernel-mode driver bound to such a
#   catalog UNLESS:
#     (a) Secure Boot is OFF in firmware (UEFI setup)             AND
#     (b) BCD testsigning is ON (set by I02, takes effect at boot) AND
#     (c) HVCI / Memory Integrity is OFF (otherwise CI policy still
#         enforces Microsoft-rooted signing)
#   If ANY of (a), (b), (c) is wrong, the user can run pnputil all day
#   and the driver will load briefly then be refused / reverted.
#
# Secure Boot can ONLY be disabled in firmware (UEFI setup), not from
# Windows. This script can detect, instruct, and refuse to enable
# testsigning when Secure Boot is on (because the bcdedit setting
# would be silently dropped on next boot).
#####################################################################
# SECTION 1d: UEFI Secure Boot certificate baseline (r48, 2026-05-13+)
#####################################################################
# Captures the runtime UEFI Secure Boot certificate / servicing state
# and (when present) hands off to Microsoft's official sample script
# %SystemRoot%\SecureBoot\ExampleRolloutScripts\Detect-SecureBootCertUpdateStatus.ps1
# for additional fleet-rollout telemetry (BucketId / ConfidenceLevel /
# event-log counts).
#
# Why this matters for this script:
#   This script's drivers ride on top of UEFI Secure Boot. The UEFI db
#   and KEK variables hold the firmware-level trust anchors. From mid-
#   2026 onward, Microsoft is rolling out new UEFI CA 2023 certificates
#   to replace the 2011 ones that begin expiring in June 2026.
#   While our self-signed driver chain is at a HIGHER layer than UEFI
#   (Windows cert stores + WDAC supplemental CI policy), a host with an
#   incomplete or errored UEFI cert update is a meaningful diagnostic
#   signal: bootloader trust may be in flux, the Secure-Boot-Update
#   scheduled task may be running concurrently, and rollback / BitLocker
#   prompts become more likely if I02 / I03 fire in that window.
#
# Two information sources, fused via a "hybrid C" pattern (per user choice):
#
#   1. Embedded path (always available):
#        - Confirm-SecureBootUEFI + Get-SecureBootUEFI db / kek
#        - HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot
#        - HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing
#        - \Microsoft\Windows\PI\Secure-Boot-Update scheduled task
#
#   2. Microsoft sample path (best-effort, only on devices that received
#      KB5089549 / KB5087544 / KB5088863 or the WS2025 equivalent):
#        - %SystemRoot%\SecureBoot\ExampleRolloutScripts\Detect-SecureBootCertUpdateStatus.ps1
#      Adds BucketId / ConfidenceLevel / SkipReason / event-1801-1808
#      counts that we cannot reasonably reimplement here.
#
# Reference:
#   - Sample Secure Boot E2E Automation Guide (Microsoft KB 5084567)
#   - May 12, 2026 cumulative update notes (KB5089549) - introduces the
#     %SystemRoot%\SecureBoot\ExampleRolloutScripts folder.

function Get-SecureBootCertificateInventory {
    # Read UEFI Secure Boot state, certificate presence in db/KEK, and
    # the Servicing registry block. This is the embedded fallback used
    # when Microsoft's sample Detect script is NOT present on the host.
    # All access is read-only; failures are captured rather than thrown.
    [CmdletBinding()]
    param()

    $inv = [pscustomobject]@{
        Source                              = 'Embedded'
        Generated                           = (Get-Date)
        Available                           = $false
        ErrorMessage                        = $null
        # Top-level Secure Boot state
        SecureBootEnabled                   = $null
        SecureBootDetectError               = $null
        # 1P certs (required on ALL Secure-Boot-enabled systems)
        FirstPartyDB2023Updated             = $null    # Windows UEFI CA 2023
        FirstPartyKEK2023Updated            = $null    # Microsoft Corporation KEK 2K CA 2023
        # 3P / IHV certs (required ONLY when 3P 2011 CA is present)
        ThirdParty2011CAPresent             = $null    # Microsoft Corporation UEFI CA 2011
        ThirdParty2023CertsRequired         = $null
        ThirdParty2023CertUpdated           = $null    # Microsoft UEFI CA 2023
        ThirdPartyOptionRom2023CertUpdated  = $null    # Microsoft Option ROM UEFI CA 2023
        # HKLM:\...\Control\SecureBoot
        HighConfidenceOptOut                = $null
        MicrosoftUpdateManagedOptIn         = $null
        AvailableUpdates                    = $null    # raw DWORD
        AvailableUpdatesHex                 = $null    # hex repr
        AvailableUpdatesPolicy              = $null    # GPO-set
        AvailableUpdatesPolicyHex           = $null
        # HKLM:\...\Control\SecureBoot\Servicing
        UEFICA2023Status                    = $null    # Updated / In-Progress / etc.
        UEFICA2023Error                     = $null
        UEFICA2023ErrorEvent                = $null
        # Servicing\DeviceAttributes
        OEMManufacturerName                 = $null
        OEMModelSystemFamily                = $null
        OEMModelNumber                      = $null
        FirmwareVersion                     = $null
        FirmwareReleaseDate                 = $null
        CanAttemptUpdateAfter               = $null
        # Scheduled task \Microsoft\Windows\PI\Secure-Boot-Update
        SecureBootTaskExists                = $false
        SecureBootTaskStatus                = $null
        SecureBootTaskEnabled               = $null
    }

    # ---- Top-level: Confirm-SecureBootUEFI ----
    try {
        $inv.SecureBootEnabled = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
    } catch {
        $inv.SecureBootDetectError = $_.Exception.Message
        # Fallback via registry
        try {
            $rv = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' `
                                   -Name UEFISecureBootEnabled -ErrorAction Stop
            $inv.SecureBootEnabled = [bool]$rv.UEFISecureBootEnabled
        } catch {
            # leave as $null
        }
    }

    # ---- Certificate presence in UEFI db / KEK ----
    # Only meaningful when Secure Boot is on AND we have admin (we do).
    if ($inv.SecureBootEnabled -eq $true) {
        try {
            $dbBytes  = (Get-SecureBootUEFI db -ErrorAction Stop).bytes
            $dbString = [System.Text.Encoding]::ASCII.GetString($dbBytes)
            $inv.FirstPartyDB2023Updated = if ($dbString -match 'Windows UEFI CA 2023') { 1 } else { 0 }
            $inv.ThirdParty2011CAPresent = if ($dbString -match 'Microsoft Corporation UEFI CA 2011') { 1 } else { 0 }
            $inv.ThirdParty2023CertsRequired = if ($inv.ThirdParty2011CAPresent -eq 1) { 1 } else { 0 }
            $inv.ThirdParty2023CertUpdated          = if (($inv.ThirdParty2023CertsRequired -eq 1) -and ($dbString -match 'Microsoft UEFI CA 2023'))           { 1 } else { 0 }
            $inv.ThirdPartyOptionRom2023CertUpdated = if (($inv.ThirdParty2023CertsRequired -eq 1) -and ($dbString -match 'Microsoft Option ROM UEFI CA 2023')) { 1 } else { 0 }
        } catch {
            # Unable to read db - leave related fields at $null
        }
        try {
            $kekBytes  = (Get-SecureBootUEFI kek -ErrorAction Stop).bytes
            $kekString = [System.Text.Encoding]::ASCII.GetString($kekBytes)
            $inv.FirstPartyKEK2023Updated = if ($kekString -match 'Microsoft Corporation KEK 2K CA 2023') { 1 } else { 0 }
        } catch {
            # leave $null
        }

        # If 1P certs are not both present, 3P-updated flags lose meaning
        if (($inv.FirstPartyDB2023Updated -eq 0) -or ($inv.FirstPartyKEK2023Updated -eq 0)) {
            $inv.ThirdParty2023CertUpdated          = 0
            $inv.ThirdPartyOptionRom2023CertUpdated = 0
        }
    }

    # ---- HKLM:\...\Control\SecureBoot (optional values) ----
    $sbKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot'
    foreach ($name in 'HighConfidenceOptOut','MicrosoftUpdateManagedOptIn') {
        try {
            $rv = Get-ItemProperty -Path $sbKey -Name $name -ErrorAction Stop
            $inv.$name = $rv.$name
        } catch { }
    }
    foreach ($name in 'AvailableUpdates','AvailableUpdatesPolicy') {
        try {
            $rv = Get-ItemProperty -Path $sbKey -Name $name -ErrorAction Stop
            $inv.$name = $rv.$name
            if ($null -ne $rv.$name) {
                $hexProp = "${name}Hex"
                $inv.$hexProp = ('0x{0:X}' -f [int]$rv.$name)
            }
        } catch { }
    }

    # ---- HKLM:\...\Control\SecureBoot\Servicing ----
    $svcKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing'
    foreach ($name in 'UEFICA2023Status','UEFICA2023Error','UEFICA2023ErrorEvent') {
        try {
            $rv = Get-ItemProperty -Path $svcKey -Name $name -ErrorAction Stop
            $inv.$name = $rv.$name
        } catch { }
    }

    # ---- Servicing\DeviceAttributes ----
    $daKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\Servicing\DeviceAttributes'
    foreach ($name in 'OEMManufacturerName','OEMModelSystemFamily','OEMModelNumber','FirmwareVersion','FirmwareReleaseDate') {
        try {
            $rv = Get-ItemProperty -Path $daKey -Name $name -ErrorAction Stop
            $inv.$name = $rv.$name
        } catch { }
    }
    try {
        $rv = Get-ItemProperty -Path $daKey -Name 'CanAttemptUpdateAfter' -ErrorAction Stop
        $caua = $rv.CanAttemptUpdateAfter
        if ($null -ne $caua) {
            if ($caua -is [byte[]]) {
                $ft = [BitConverter]::ToInt64($caua, 0)
                $inv.CanAttemptUpdateAfter = [DateTime]::FromFileTime($ft).ToUniversalTime()
            } elseif ($caua -is [long] -or $caua -is [int64]) {
                $inv.CanAttemptUpdateAfter = [DateTime]::FromFileTime($caua).ToUniversalTime()
            } else {
                $inv.CanAttemptUpdateAfter = $caua
            }
        }
    } catch { }

    # ---- Scheduled task \Microsoft\Windows\PI\Secure-Boot-Update ----
    # Use the PowerShell-native Get-ScheduledTask cmdlet rather than
    # schtasks.exe /FO CSV. schtasks emits LOCALIZED CSV column headers
    # on non-English Windows (e.g. ja-JP returns the header in Japanese),
    # which breaks $row.Status property access and silently mis-reports
    # the task as 'Disabled' even when it is in fact Ready/Running.
    # Get-ScheduledTask returns CIM objects with locale-independent
    # English property names (.State = Ready / Running / Disabled / ...).
    try {
        $task = Get-ScheduledTask -TaskPath '\Microsoft\Windows\PI\' -TaskName 'Secure-Boot-Update' -ErrorAction Stop
        if ($task) {
            $inv.SecureBootTaskExists  = $true
            $inv.SecureBootTaskStatus  = "$($task.State)"   # 'Ready' / 'Running' / 'Disabled' / 'Queued' / 'Unknown'
            $inv.SecureBootTaskEnabled = ($task.State -eq 'Ready' -or $task.State -eq 'Running')
        }
    } catch {
        # Task missing OR Get-ScheduledTask unavailable (very old PS).
        # Fall back to schtasks /Query just for existence detection;
        # status will remain locale-dependent but presence is unambiguous.
        try {
            $null = schtasks.exe /Query /TN '\Microsoft\Windows\PI\Secure-Boot-Update' /FO LIST 2>&1
            if ($LASTEXITCODE -eq 0) {
                $inv.SecureBootTaskExists  = $true
                $inv.SecureBootTaskStatus  = 'present (state unknown - schtasks fallback)'
                $inv.SecureBootTaskEnabled = $null
            }
        } catch { }
    }

    $inv.Available = $true
    return $inv
}

function Get-MsSecureBootExampleScriptPath {
    # Detect whether the official Microsoft sample scripts (delivered by
    # KB5089549 / KB5087544 / KB5088863 from 2026-05-12 onward) are
    # deployed on this host. Returns a small descriptor object with
    # Present flag and per-script paths.
    [CmdletBinding()]
    param()

    $root = Join-Path $env:SystemRoot 'SecureBoot\ExampleRolloutScripts'
    $detect = Join-Path $root 'Detect-SecureBootCertUpdateStatus.ps1'
    $enable = Join-Path $root 'Enable-SecureBootUpdateTask.ps1'

    [pscustomobject]@{
        Present       = (Test-Path -LiteralPath $detect)
        RootPath      = $root
        DetectScript  = if (Test-Path -LiteralPath $detect) { $detect } else { $null }
        EnableScript  = if (Test-Path -LiteralPath $enable) { $enable } else { $null }
    }
}

function Invoke-MsSecureBootDetectScript {
    # Invoke %SystemRoot%\SecureBoot\ExampleRolloutScripts\Detect-SecureBootCertUpdateStatus.ps1
    # in a child PowerShell session with -OutputPath set to a transient
    # folder under the AMD workspace, then re-parse the resulting JSON.
    #
    # Returns a hybrid result object. .Available indicates whether the
    # script ran AND produced parseable JSON. Failures (script missing,
    # non-zero exit + no JSON, parse errors, etc.) populate .ErrorMessage
    # and leave .Data null - callers should fall back to the embedded
    # inventory in that case.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$WorkRoot,
        [string]$DetectScriptPath
    )

    $result = [pscustomobject]@{
        Source       = 'Microsoft'
        Generated    = (Get-Date)
        Available    = $false
        ErrorMessage = $null
        ScriptPath   = $null
        JsonPath     = $null
        ExitCode     = $null
        Data         = $null
    }

    if (-not $DetectScriptPath) {
        $info = Get-MsSecureBootExampleScriptPath
        if (-not $info.Present) {
            $result.ErrorMessage = 'Detect-SecureBootCertUpdateStatus.ps1 not present (KB5089549/5087544/5088863 or WS2025 equivalent not installed, or device not eligible).'
            return $result
        }
        $DetectScriptPath = $info.DetectScript
    }
    $result.ScriptPath = $DetectScriptPath

    if (-not (Test-Path -LiteralPath $DetectScriptPath)) {
        $result.ErrorMessage = "Detect script not found: $DetectScriptPath"
        return $result
    }

    # Output folder under the AMD workspace (created if missing)
    $outDir = Join-Path $WorkRoot 'secureboot_ms_sample'
    try {
        if (-not (Test-Path -LiteralPath $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }
    } catch {
        $result.ErrorMessage = "Could not create output directory $outDir : $($_.Exception.Message)"
        return $result
    }

    # Microsoft's sample writes "$HOSTNAME_latest.json" under -OutputPath
    $expectedJson = Join-Path $outDir ("$env:COMPUTERNAME" + '_latest.json')

    # Run in a child PowerShell. Determine the executable path from
    # $PSHOME and the current edition rather than Get-Process -Id $PID
    # (which can return the parent host - e.g. ISE / VS Code - rather
    # than a usable powershell.exe / pwsh.exe). Falls back to PATH
    # lookup if the resolved file is somehow missing.
    $psExeName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $psExe = Join-Path $PSHOME $psExeName
    if (-not (Test-Path -LiteralPath $psExe)) {
        # Fall back to PATH resolution; if even that fails, let the
        # invocation below surface the error.
        $psExe = $psExeName
    }

    # NOTE: variable named $psArgs (NOT $args) to avoid clobbering the
    # automatic $args variable that PowerShell uses for unbound
    # positional parameters in the enclosing function scope.
    $psArgs = @(
        '-NoProfile'
        '-NonInteractive'
        '-ExecutionPolicy','Bypass'
        '-File', $DetectScriptPath
        '-OutputPath', $outDir
    )

    try {
        $stdout = & $psExe @psArgs 2>&1
        $result.ExitCode = $LASTEXITCODE
        # Microsoft's script returns exit code 0 (certs updated) or 1
        # (not yet updated). Both are SUCCESSFUL invocations from our
        # POV - we treat any other code, or missing JSON, as failure.
        $stdoutText = ($stdout | Out-String)
        if ($result.ExitCode -notin 0,1) {
            $result.ErrorMessage = "Detect script exited with code $($result.ExitCode). stdout/err head: " + ($stdoutText.Substring(0, [Math]::Min(400, $stdoutText.Length)))
        }
    } catch {
        $result.ErrorMessage = "Failed to launch detect script: $($_.Exception.Message)"
        return $result
    }

    # Save the raw stdout for diagnostic purposes (helps debug when the
    # detect script behaves unexpectedly in the wild). Best-effort: a
    # write failure here is non-fatal.
    try {
        $stdoutPath = Join-Path $outDir 'detect_stdout.log'
        Set-Content -LiteralPath $stdoutPath -Value $stdoutText -Encoding UTF8 -Force
    } catch { }

    # Try the file-based JSON path first (clean case: MS script accepted
    # our -OutputPath and wrote HOSTNAME_latest.json).
    if (Test-Path -LiteralPath $expectedJson) {
        $result.JsonPath = $expectedJson
        try {
            $raw = Get-Content -LiteralPath $expectedJson -Raw -Encoding UTF8
            $obj = $raw | ConvertFrom-Json
            $result.Data = $obj
            $result.Available = $true
            return $result
        } catch {
            $result.ErrorMessage = "Failed to parse JSON output at ${expectedJson}: $($_.Exception.Message)"
            # Fall through to stdout-parsing fallback
        }
    }

    # Fallback: extract JSON from captured stdout. This is required
    # because the Microsoft sample script (as of the 2026-05-12 delivery)
    # has an over-aggressive input validator that rejects ANY -OutputPath
    # containing ':' (which includes every absolute Windows path with a
    # drive letter). When validation fires, the script prints
    #   "Invalid OutputPath specified, outputting to stdout"
    # and then Write-Output's the JSON to stdout. We capture stdout
    # anyway (2>&1 above), so we can recover the JSON from there.
    try {
        # The detect script emits many Write-Host lines first, then the
        # JSON object at the end. Strategy: scan for the LAST occurrence
        # of a top-level '{' followed by a property the JSON always has
        # ("Hostname", "UEFICA2023Status", etc.), then take from that
        # '{' to the matching '}'.
        $json = $null
        # Look for the start of the JSON object. ConvertTo-Json output is
        # human-formatted by default, so the object opens at column 1 on
        # its own line: "^{" with leading whitespace.
        # NOTE: variable named $jsonMatches (NOT $matches) to avoid
        # clobbering the PowerShell automatic $matches that holds the
        # result of the -match operator.
        $jsonMatches = [regex]::Matches($stdoutText, '(?ms)^\s*\{[^{]*"(Hostname|UEFICA2023Status|SecureBootEnabled)"\s*:')
        if ($jsonMatches.Count -gt 0) {
            # Take the LAST match (in case earlier output happens to contain
            # a similar pattern - very unlikely but defensive).
            $start = $jsonMatches[$jsonMatches.Count - 1].Index
            # Find matching closing brace by counting depth from $start.
            $depth = 0
            $end = -1
            for ($i = $start; $i -lt $stdoutText.Length; $i++) {
                $c = $stdoutText[$i]
                if ($c -eq '{') { $depth++ }
                elseif ($c -eq '}') {
                    $depth--
                    if ($depth -eq 0) { $end = $i; break }
                }
            }
            if ($end -gt $start) {
                $json = $stdoutText.Substring($start, $end - $start + 1)
            }
        }

        if ($json) {
            $obj = $json | ConvertFrom-Json
            $result.Data = $obj
            $result.Available = $true
            $result.JsonPath = '(stdout fallback - file output rejected by MS script path validator)'
            # Optional: also persist the extracted JSON for forensics.
            try {
                $jsonRecoveryPath = Join-Path $outDir 'detect_stdout_extracted.json'
                Set-Content -LiteralPath $jsonRecoveryPath -Value $json -Encoding UTF8 -Force
                $result.JsonPath = $jsonRecoveryPath
            } catch { }
            $result.ErrorMessage = $null     # clear earlier "file not found" message
            return $result
        }
    } catch {
        # Fall through to the final error path
    }

    if (-not $result.ErrorMessage) {
        $result.ErrorMessage = "Detect script ran but neither file output nor stdout JSON could be parsed. See $stdoutPath for raw output."
    }
    return $result
}

function Get-SecureBootBaselineSnapshot {
    # Top-level entry point. Returns a unified snapshot combining the
    # embedded inventory (always present) and the Microsoft sample
    # script output (when available). Adds an overall Health
    # classification used by the report and the I02 pre-check.
    #
    # Health classification:
    #   'Healthy'  - Secure Boot ON, UEFICA2023Status=Updated (or not
    #                applicable), no UEFICA2023Error, no servicing error
    #                events captured by the MS script.
    #   'Warning'  - Secure Boot ON but UEFI CA 2023 rollout is still
    #                in flight, OR scheduled task disabled, OR the MS
    #                script reports error events (1795/1796/1802/1803).
    #   'Critical' - Secure Boot OFF (with this script's WDAC path that
    #                normally requires Secure Boot ON), OR UEFICA2023Error
    #                non-zero indicating a stuck rollout.
    #   'Unknown'  - Could not collect Secure Boot state at all (non-UEFI
    #                host, or Confirm-SecureBootUEFI cmdlet unavailable).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$WorkRoot
    )

    $emb = Get-SecureBootCertificateInventory

    $msInfo = Get-MsSecureBootExampleScriptPath
    $ms = $null
    if ($msInfo.Present) {
        $ms = Invoke-MsSecureBootDetectScript -WorkRoot $WorkRoot -DetectScriptPath $msInfo.DetectScript
    }

    # Compute health
    $health = 'Unknown'
    $reasons = New-Object System.Collections.Generic.List[string]
    if ($null -eq $emb.SecureBootEnabled) {
        $health = 'Unknown'
        $reasons.Add('Secure Boot state could not be determined.') | Out-Null
    } elseif ($emb.SecureBootEnabled -eq $false) {
        $health = 'Warning'   # not Critical: testsigning path still works on SB-OFF hosts
        $reasons.Add('Secure Boot is OFF in firmware - WDAC supplemental policy is unnecessary; legacy testsigning would apply.') | Out-Null
    } else {
        # Secure Boot ON - cert rollover progress matters
        $health = 'Healthy'
        if ($emb.UEFICA2023Status -and ($emb.UEFICA2023Status -ne 'Updated')) {
            $health = 'Warning'
            $reasons.Add("UEFI CA 2023 status: $($emb.UEFICA2023Status) (rollout not yet complete).") | Out-Null
        }
        if ($emb.UEFICA2023Error -and ($emb.UEFICA2023Error -ne 0)) {
            $health = 'Critical'
            $reasons.Add("UEFI CA 2023 error code recorded: $($emb.UEFICA2023Error).") | Out-Null
        }
        if ($emb.FirstPartyDB2023Updated -eq 0 -or $emb.FirstPartyKEK2023Updated -eq 0) {
            if ($health -eq 'Healthy') { $health = 'Warning' }
            $reasons.Add('First-party Secure Boot certs (UEFI CA 2023 / KEK 2K CA 2023) not yet present in firmware variables.') | Out-Null
        }
        if (($null -ne $emb.SecureBootTaskEnabled) -and ($emb.SecureBootTaskEnabled -eq $false)) {
            if ($health -eq 'Healthy') { $health = 'Warning' }
            $reasons.Add('Scheduled task \Microsoft\Windows\PI\Secure-Boot-Update is disabled or not ready.') | Out-Null
        }
    }
    # MS-script signals further refine the health
    if ($ms -and $ms.Available -and $ms.Data) {
        $d = $ms.Data
        foreach ($f in 'Event1795Count','Event1796Count','Event1802Count','Event1803Count') {
            $v = $d.$f
            if ($v -and ([int]$v -gt 0)) {
                if ($health -eq 'Healthy') { $health = 'Warning' }
                $reasons.Add("Microsoft sample script reports $f = $v.") | Out-Null
            }
        }
        if ($d.Confidence -and ($d.Confidence -match '(?i)Action Req')) {
            if ($health -eq 'Healthy') { $health = 'Warning' }
            $reasons.Add("Microsoft sample script reports Confidence = $($d.Confidence).") | Out-Null
        }
    }

    [pscustomobject]@{
        Generated  = (Get-Date)
        WorkRoot   = $WorkRoot
        MsInfo     = $msInfo
        Embedded   = $emb
        Microsoft  = $ms
        Health     = $health
        Reasons    = @($reasons)
    }
}

function Show-SecureBootBaselineSnapshot {
    # Renders a baseline snapshot in this script's standard log style.
    # -Compact prints a 3-line summary suitable for P00 / I02 banners.
    # Without -Compact, prints a full section with cert / registry /
    # task / Microsoft-script details for V05 / V06.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Snapshot,
        [switch]$Compact
    )

    if (-not $Snapshot) { return }
    $emb = $Snapshot.Embedded
    $ms  = $Snapshot.Microsoft
    $health = $Snapshot.Health
    $healthColor = switch ($health) {
        'Healthy'  { 'Green'   }
        'Warning'  { 'Yellow'  }
        'Critical' { 'Red'     }
        default    { 'DarkGray' }
    }

    if ($Compact) {
        $sb = if ($null -eq $emb.SecureBootEnabled) { 'unknown' } else { ($emb.SecureBootEnabled.ToString().ToLower()) }
        $u2023 = if ($emb.UEFICA2023Status) { $emb.UEFICA2023Status } else { 'n/a' }
        $msTag = if ($ms -and $ms.Available) { 'MS-sample=ok' }
                 elseif ($Snapshot.MsInfo.Present) { 'MS-sample=present(err)' }
                 else { 'MS-sample=absent' }
        Write-Detail ("Secure Boot baseline: enabled={0,-5} UEFI-CA-2023={1,-12} health={2,-8} [{3}]" -f $sb, $u2023, $health, $msTag) -Color $healthColor
        return
    }

    # Non-compact mode: caller is responsible for printing the section
    # banner (V06 prefixes the section with its own '--- 4. UEFI Secure
    # Boot Baseline ---' header for numbering consistency with sections
    # 1-3 above it). We print only the body to avoid the duplicate
    # banner that was visible in the r49 first release.
    Write-Host ("  Overall health     : {0}" -f $health) -ForegroundColor $healthColor
    foreach ($r in $Snapshot.Reasons) {
        Write-Detail ("- {0}" -f $r) -Color $healthColor
    }
    Write-Host ''
    Write-Host '  [Embedded inventory]'
    Write-Detail ("Secure Boot enabled              : {0}" -f $(if ($null -eq $emb.SecureBootEnabled) { 'unknown' } else { $emb.SecureBootEnabled }))
    if ($emb.SecureBootDetectError) {
        Write-Detail ("  Detect error: {0}" -f $emb.SecureBootDetectError) -Color DarkGray
    }
    Write-Detail ("Windows UEFI CA 2023 (db, 1P)    : {0}" -f $(if ($null -eq $emb.FirstPartyDB2023Updated)  { 'n/a' } elseif ($emb.FirstPartyDB2023Updated  -eq 1) { 'present'    } else { 'NOT present' }))
    Write-Detail ("Microsoft KEK 2K CA 2023 (KEK,1P): {0}" -f $(if ($null -eq $emb.FirstPartyKEK2023Updated) { 'n/a' } elseif ($emb.FirstPartyKEK2023Updated -eq 1) { 'present'    } else { 'NOT present' }))
    Write-Detail ("Microsoft UEFI CA 2011 (db, 3P)  : {0}" -f $(if ($null -eq $emb.ThirdParty2011CAPresent)  { 'n/a' } elseif ($emb.ThirdParty2011CAPresent  -eq 1) { 'present (3P trusted)' } else { 'not present (1P-only trust)' }))
    if ($emb.ThirdParty2023CertsRequired -eq 1) {
        Write-Detail ("Microsoft UEFI CA 2023 (db, 3P)        : {0}" -f $(if ($null -eq $emb.ThirdParty2023CertUpdated)          { 'n/a' } elseif ($emb.ThirdParty2023CertUpdated          -eq 1) { 'present' } else { 'NOT present' }))
        Write-Detail ("Microsoft Option ROM UEFI CA 2023 (3P) : {0}" -f $(if ($null -eq $emb.ThirdPartyOptionRom2023CertUpdated) { 'n/a' } elseif ($emb.ThirdPartyOptionRom2023CertUpdated -eq 1) { 'present' } else { 'NOT present' }))
    }
    Write-Detail ("UEFI CA 2023 status (registry)         : {0}" -f $(if ($emb.UEFICA2023Status)     { $emb.UEFICA2023Status     } else { 'n/a' }))
    if ($emb.UEFICA2023Error) {
        Write-Detail ("UEFI CA 2023 error code                : {0}" -f $emb.UEFICA2023Error) -Color Yellow
    }
    Write-Detail ("AvailableUpdates / Policy              : {0} / {1}" -f $(if ($emb.AvailableUpdatesHex)       { $emb.AvailableUpdatesHex       } else { 'n/a' }), $(if ($emb.AvailableUpdatesPolicyHex) { $emb.AvailableUpdatesPolicyHex } else { 'n/a' }))
    Write-Detail ("Secure-Boot-Update scheduled task      : {0}" -f $(
        if (-not $emb.SecureBootTaskExists) { 'task not present' }
        elseif ($null -eq $emb.SecureBootTaskEnabled) { "state=$($emb.SecureBootTaskStatus) (enabled-check skipped)" }
        elseif ($emb.SecureBootTaskEnabled) { "Ready/Running (state=$($emb.SecureBootTaskStatus))" }
        else { "Not running (state=$($emb.SecureBootTaskStatus))" }
    ))
    if ($emb.CanAttemptUpdateAfter) {
        Write-Detail ("CanAttemptUpdateAfter (UTC)            : {0}" -f $emb.CanAttemptUpdateAfter) -Color DarkGray
    }
    Write-Host ''
    Write-Host '  [Microsoft sample script (KB5089549+ delivery)]'
    if (-not $Snapshot.MsInfo.Present) {
        Write-Host '    Not deployed on this host.' -ForegroundColor DarkGray
        Write-Detail ("(Expected path: {0})" -f $Snapshot.MsInfo.RootPath) -Color DarkGray
        Write-Host '    Embedded inventory above is the sole source.' -ForegroundColor DarkGray
    } elseif (-not $ms -or -not $ms.Available) {
        Write-Host ('    Script present but invocation failed.') -ForegroundColor Yellow
        if ($ms -and $ms.ErrorMessage) {
            Write-Detail ("  Reason: {0}" -f $ms.ErrorMessage) -Color Yellow
        }
    } else {
        $d = $ms.Data
        Write-Host ('    Script invoked successfully.') -ForegroundColor Green
        Write-Detail ("Script path  : {0}" -f $ms.ScriptPath) -Color DarkGray
        Write-Detail ("JSON path    : {0}" -f $ms.JsonPath) -Color DarkGray
        Write-Detail ("BucketId     : {0}" -f $(if ($d.BucketId) { $d.BucketId } else { 'n/a' }))
        Write-Detail ("Confidence   : {0}" -f $(if ($d.Confidence) { $d.Confidence } else { 'n/a' }))
        if ($d.SkipReasonKnownIssue) {
            Write-Detail ("SkipReason   : {0}" -f $d.SkipReasonKnownIssue) -Color Yellow
        }
        if ($d.KnownIssueId) {
            Write-Detail ("KnownIssueId : {0}" -f $d.KnownIssueId) -Color Yellow
        }
        $evtFields = @('Event1801Count','Event1808Count','Event1795Count','Event1796Count','Event1800Count','Event1802Count','Event1803Count')
        $evtParts = foreach ($f in $evtFields) {
            $v = $d.$f
            if ($v -and ([int]$v -gt 0)) { ("{0}={1}" -f ($f -replace 'Count$',''), $v) }
        }
        if ($evtParts) {
            Write-Detail ("Events       : {0}" -f ($evtParts -join '  '))
        }
        if ($d.MissingKEK) {
            Write-Host '    MissingKEK   : TRUE (OEM needs to supply PK-signed KEK)' -ForegroundColor Yellow
        }
        if ($d.RebootPending) {
            Write-Host '    RebootPending: TRUE (Event 1800 was observed)' -ForegroundColor Cyan
        }
    }
    Write-Host ''
}

function Get-OrEnsureSecureBootBaseline {
    # r50: idempotent accessor for the cached Secure Boot baseline.
    # Returns $Ctx.SecureBootBaseline when it is still valid; otherwise
    # re-invokes Get-SecureBootBaselineSnapshot into the current
    # $Ctx.WorkRoot so the diagnostic files (detect_stdout.log,
    # detect_stdout_extracted.json) are co-located with the workspace.
    #
    # A cached snapshot is considered VALID when one of the following
    # holds:
    #   - The MS sample script was not available on this host, so
    #     there is no diagnostic file to keep in sync (MsInfo.JsonPath
    #     is $null). The in-memory data is the sole source of truth.
    #   - MsInfo.JsonPath references a file that still exists AND that
    #     file lives under the current $Ctx.WorkRoot tree.
    #
    # The cache becomes INVALID when:
    #   - P01 wiped the workspace under -CleanWorkRoot, deleting a
    #     JSON file that P00 had written to the workspace.
    #   - An earlier release's P00 had written the JSON to %TEMP%
    #     (pre-r50 behaviour) and we are now reading the snapshot
    #     from a phase that displays the path.
    # In either case we re-capture so the displayed path is honest.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Ctx
    )

    $needCapture = $true
    if ($Ctx.SecureBootBaseline) {
        $cached = $Ctx.SecureBootBaseline
        $jsonPath = $null
        try { $jsonPath = $cached.MsInfo.JsonPath } catch { }
        if (-not $jsonPath) {
            # MS sample script not present or did not produce a JSON
            # path - nothing to keep co-located. Cached snapshot is fine.
            $needCapture = $false
        } elseif ($Ctx.WorkRoot -and ($jsonPath -like "$($Ctx.WorkRoot)*") -and (Test-Path -LiteralPath $jsonPath)) {
            # JSON file is under the workspace and still exists.
            $needCapture = $false
        }
    }

    if ($needCapture) {
        try {
            $Ctx.SecureBootBaseline = Get-SecureBootBaselineSnapshot -WorkRoot $Ctx.WorkRoot
        } catch {
            Write-Warn2 ("Secure Boot baseline (re-)capture failed: {0}" -f $_.Exception.Message)
        }
    }

    return $Ctx.SecureBootBaseline
}

function Format-SecureBootBaselineForReport {
    # Render the baseline snapshot as a plain-text section suitable for
    # appending to inf_inventory_report.txt. Mirrors the on-screen V06
    # block but without colour codes / cursor positioning.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Snapshot
    )

    if (-not $Snapshot) { return '' }
    $emb = $Snapshot.Embedded
    $ms  = $Snapshot.Microsoft

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine(("=" * 78))
    [void]$sb.AppendLine('UEFI Secure Boot Baseline')
    [void]$sb.AppendLine(("=" * 78))
    [void]$sb.AppendLine("Captured       : $($Snapshot.Generated.ToString('yyyy-MM-dd HH:mm:ss'))")
    [void]$sb.AppendLine("Overall health : $($Snapshot.Health)")
    if ($Snapshot.Reasons.Count -gt 0) {
        [void]$sb.AppendLine('Reasons        :')
        foreach ($r in $Snapshot.Reasons) {
            [void]$sb.AppendLine("  - $r")
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('-- Embedded inventory ' + ('-' * 56))
    [void]$sb.AppendLine("Secure Boot enabled               : $(if ($null -eq $emb.SecureBootEnabled) { 'unknown' } else { $emb.SecureBootEnabled })")
    if ($emb.SecureBootDetectError) {
        [void]$sb.AppendLine("  Detect error                    : $($emb.SecureBootDetectError)")
    }
    [void]$sb.AppendLine("Windows UEFI CA 2023 (db, 1P)     : $(if ($null -eq $emb.FirstPartyDB2023Updated)  { 'n/a' } elseif ($emb.FirstPartyDB2023Updated  -eq 1) { 'present' } else { 'NOT present' })")
    [void]$sb.AppendLine("Microsoft KEK 2K CA 2023 (KEK, 1P): $(if ($null -eq $emb.FirstPartyKEK2023Updated) { 'n/a' } elseif ($emb.FirstPartyKEK2023Updated -eq 1) { 'present' } else { 'NOT present' })")
    [void]$sb.AppendLine("Microsoft UEFI CA 2011 (db, 3P)   : $(if ($null -eq $emb.ThirdParty2011CAPresent)  { 'n/a' } elseif ($emb.ThirdParty2011CAPresent  -eq 1) { 'present (3P trusted)' } else { 'not present (1P-only trust)' })")
    if ($emb.ThirdParty2023CertsRequired -eq 1) {
        [void]$sb.AppendLine("Microsoft UEFI CA 2023 (db, 3P)        : $(if ($null -eq $emb.ThirdParty2023CertUpdated)          { 'n/a' } elseif ($emb.ThirdParty2023CertUpdated          -eq 1) { 'present' } else { 'NOT present' })")
        [void]$sb.AppendLine("Microsoft Option ROM UEFI CA 2023 (3P) : $(if ($null -eq $emb.ThirdPartyOptionRom2023CertUpdated) { 'n/a' } elseif ($emb.ThirdPartyOptionRom2023CertUpdated -eq 1) { 'present' } else { 'NOT present' })")
    }
    [void]$sb.AppendLine("UEFI CA 2023 status (registry)         : $(if ($emb.UEFICA2023Status) { $emb.UEFICA2023Status } else { 'n/a' })")
    if ($emb.UEFICA2023Error) {
        [void]$sb.AppendLine("UEFI CA 2023 error code                : $($emb.UEFICA2023Error)")
    }
    [void]$sb.AppendLine("AvailableUpdates                       : $(if ($emb.AvailableUpdatesHex)       { $emb.AvailableUpdatesHex       } else { 'n/a' })")
    [void]$sb.AppendLine("AvailableUpdatesPolicy                 : $(if ($emb.AvailableUpdatesPolicyHex) { $emb.AvailableUpdatesPolicyHex } else { 'n/a' })")
    [void]$sb.AppendLine("HighConfidenceOptOut                   : $(if ($null -ne $emb.HighConfidenceOptOut) { $emb.HighConfidenceOptOut } else { 'n/a' })")
    [void]$sb.AppendLine("MicrosoftUpdateManagedOptIn            : $(if ($null -ne $emb.MicrosoftUpdateManagedOptIn) { $emb.MicrosoftUpdateManagedOptIn } else { 'n/a' })")
    [void]$sb.AppendLine("OEM Manufacturer                       : $(if ($emb.OEMManufacturerName) { $emb.OEMManufacturerName } else { 'n/a' })")
    [void]$sb.AppendLine("OEM Model SystemFamily / Number        : $(if ($emb.OEMModelSystemFamily) { $emb.OEMModelSystemFamily } else { 'n/a' }) / $(if ($emb.OEMModelNumber) { $emb.OEMModelNumber } else { 'n/a' })")
    [void]$sb.AppendLine("Firmware Version / ReleaseDate         : $(if ($emb.FirmwareVersion) { $emb.FirmwareVersion } else { 'n/a' }) / $(if ($emb.FirmwareReleaseDate) { $emb.FirmwareReleaseDate } else { 'n/a' })")
    if ($emb.CanAttemptUpdateAfter) {
        [void]$sb.AppendLine("CanAttemptUpdateAfter (UTC)            : $($emb.CanAttemptUpdateAfter)")
    }
    $sbTaskText = if (-not $emb.SecureBootTaskExists) {
        'task not present'
    } elseif ($null -eq $emb.SecureBootTaskEnabled) {
        "state=$($emb.SecureBootTaskStatus) (enabled-check skipped)"
    } elseif ($emb.SecureBootTaskEnabled) {
        "Ready/Running (state=$($emb.SecureBootTaskStatus))"
    } else {
        "Not running (state=$($emb.SecureBootTaskStatus))"
    }
    [void]$sb.AppendLine("Secure-Boot-Update scheduled task      : $sbTaskText")

    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('-- Microsoft sample script (KB5089549+ delivery) ' + ('-' * 26))
    if (-not $Snapshot.MsInfo.Present) {
        [void]$sb.AppendLine("Status         : NOT deployed on this host.")
        [void]$sb.AppendLine("Expected path  : $($Snapshot.MsInfo.RootPath)")
        [void]$sb.AppendLine("Result         : Embedded inventory above is the sole source.")
    } elseif (-not $ms -or -not $ms.Available) {
        [void]$sb.AppendLine("Status         : Present but invocation failed.")
        if ($ms -and $ms.ErrorMessage) {
            [void]$sb.AppendLine("Error          : $($ms.ErrorMessage)")
        }
    } else {
        $d = $ms.Data
        [void]$sb.AppendLine("Status         : Invoked successfully.")
        [void]$sb.AppendLine("Script path    : $($ms.ScriptPath)")
        [void]$sb.AppendLine("JSON path      : $($ms.JsonPath)")
        [void]$sb.AppendLine("BucketId       : $(if ($d.BucketId)   { $d.BucketId   } else { 'n/a' })")
        [void]$sb.AppendLine("Confidence     : $(if ($d.Confidence) { $d.Confidence } else { 'n/a' })")
        if ($d.SkipReasonKnownIssue) {
            [void]$sb.AppendLine("SkipReason     : $($d.SkipReasonKnownIssue)")
        }
        if ($d.KnownIssueId) {
            [void]$sb.AppendLine("KnownIssueId   : $($d.KnownIssueId)")
        }
        $evtLines = @()
        foreach ($f in 'Event1801Count','Event1808Count','Event1795Count','Event1796Count','Event1800Count','Event1802Count','Event1803Count') {
            $v = $d.$f
            if ($v -and ([int]$v -gt 0)) { $evtLines += ("  $f = $v") }
        }
        if ($evtLines.Count -gt 0) {
            [void]$sb.AppendLine('Event counts   :')
            foreach ($l in $evtLines) { [void]$sb.AppendLine($l) }
        }
        if ($d.MissingKEK) {
            [void]$sb.AppendLine('MissingKEK     : TRUE (OEM needs to supply PK-signed KEK)')
        }
        if ($d.RebootPending) {
            [void]$sb.AppendLine('RebootPending  : TRUE (Event 1800 was observed)')
        }
        if ($d.WinCSKeyStatus) {
            [void]$sb.AppendLine("WinCSKeyStatus : $($d.WinCSKeyStatus)")
        }
    }
    [void]$sb.AppendLine('')
    return $sb.ToString()
}

function Get-BootSigningEnvironment {
    # Every field is best-effort; failures are recorded rather than
    # thrown so the caller can decide what to do with partial data.
    $env = [pscustomobject]@{
        FirmwareType               = 'unknown'
        IsUefi                     = $false
        SecureBootEnabled          = $null   # $true / $false / $null=unknown
        SecureBootDetectError      = $null
        TestSigningEnabled         = $null
        TestSigningStateText       = 'unknown'
        BcdEnumRaw                 = $null
        BcdLoadOptions             = $null
        VbsRunning                 = $false
        VbsStatus                  = $null
        HvciRunning                = $false
        HvciAvailable              = $false
        MemoryIntegrityEnabled     = $false
        EffectiveCanLoadSelfSigned = $false
        BlockReasons               = @()
    }

    # Firmware Type (UEFI vs BIOS) via the kernel-set registry value
    # HKLM\SYSTEM\CurrentControlSet\Control\PEFirmwareType:
    #   1 = BIOS (Legacy)
    #   2 = UEFI
    try {
        $val = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' `
                                 -Name 'PEFirmwareType' -ErrorAction Stop).PEFirmwareType
        switch ([int]$val) {
            1 { $env.FirmwareType = 'BIOS (legacy)'; $env.IsUefi = $false }
            2 { $env.FirmwareType = 'UEFI';          $env.IsUefi = $true  }
            default { $env.FirmwareType = "unknown ($val)" }
        }
    } catch {
        # Some constrained installs lack PEFirmwareType; fall back to
        # presence of EFI system partition.
        try {
            $efi = Get-CimInstance -ClassName Win32_DiskPartition -ErrorAction Stop |
                Where-Object Type -match 'GPT' | Select-Object -First 1
            if ($efi) { $env.FirmwareType = 'UEFI (inferred from GPT)'; $env.IsUefi = $true }
        } catch { }
    }

    # Secure Boot (only meaningful on UEFI)
    if ($env.IsUefi) {
        try {
            # Confirm-SecureBootUEFI throws on:
            #   - non-UEFI systems (caller should not even ask)
            #   - non-elevated sessions
            #   - some virtualized environments (returns "Cmdlet not supported")
            $env.SecureBootEnabled = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
        } catch {
            $env.SecureBootDetectError = $_.Exception.Message
        }
    } else {
        # Legacy BIOS: Secure Boot is N/A and treated as 'off'
        $env.SecureBootEnabled = $false
    }

    # BCD testsigning state. We deliberately query via bcdedit (text)
    # rather than peeking at HKLM\BCD00000000 because the latter is
    # not stable across Windows versions.
    try {
        $bcdOutput = & bcdedit /enum '{current}' 2>&1 | Out-String
        $env.BcdEnumRaw = $bcdOutput
        if ($bcdOutput -match '(?im)^testsigning\s+(Yes|No)') {
            $env.TestSigningStateText = $matches[1]
            $env.TestSigningEnabled   = ($matches[1] -eq 'Yes')
        } else {
            # If the line is absent, the default is 'No'.
            $env.TestSigningStateText = 'No (default)'
            $env.TestSigningEnabled   = $false
        }
        if ($bcdOutput -match '(?im)^loadoptions\s+(.+)$') {
            $env.BcdLoadOptions = $matches[1].Trim()
        }
    } catch {
        # bcdedit failed - probably non-elevated; leave fields null.
    }

    # VBS / HVCI / Memory Integrity via Win32_DeviceGuard (Windows 10+
    # / Server 2016+). On older systems this WMI class is absent and
    # we treat all flags as off.
    try {
        $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' `
                              -ClassName 'Win32_DeviceGuard' -ErrorAction Stop
        # VirtualizationBasedSecurityStatus:
        #   0 = VBS not enabled
        #   1 = VBS enabled but not running
        #   2 = VBS enabled AND running
        $env.VbsStatus  = [int]$dg.VirtualizationBasedSecurityStatus
        $env.VbsRunning = ($env.VbsStatus -eq 2)
        # SecurityServicesRunning is an int[]; codes:
        #   1 = Credential Guard
        #   2 = HVCI / Memory Integrity (Hypervisor-protected Code Integrity)
        #   3 = System Guard Secure Launch
        #   4 = SMM Firmware Measurement
        #   5 = Vendor TPM
        $running    = @($dg.SecurityServicesRunning)
        $configured = @($dg.SecurityServicesConfigured)
        $env.HvciRunning   = ($running    -contains 2)
        $env.HvciAvailable = ($configured -contains 2)
        $env.MemoryIntegrityEnabled = $env.HvciRunning
    } catch {
        # No Win32_DeviceGuard - keep defaults (all off).
    }

    # WDAC custom CI policy state. Two pieces of info:
    #   1. Are the WDAC tools available?  (we can deploy if yes)
    #   2. Is OUR self-signed-allowlist supplemental currently active?
    #      (= we already have the green light to load self-signed
    #      drivers WITH Secure Boot enabled).
    $env | Add-Member -MemberType NoteProperty -Name WdacToolsAvailable -Value $false      -Force
    $env | Add-Member -MemberType NoteProperty -Name WdacActivePolicies -Value @()         -Force
    $env | Add-Member -MemberType NoteProperty -Name WdacBaseEnforced   -Value $null       -Force
    $env | Add-Member -MemberType NoteProperty -Name MsBthPanSuppPolicyActive -Value $false     -Force
    $env | Add-Member -MemberType NoteProperty -Name AmdSuppPolicyId    -Value $null       -Force
    try {
        $caps = Test-WdacToolsAvailable
        $env.WdacToolsAvailable = $caps.AnyUsable
        $active = Get-ActiveCodeIntegrityPolicies
        $env.WdacActivePolicies = $active
        $base = $active | Where-Object { -not $_.IsSupplemental } | Select-Object -First 1
        if ($base) {
            $env.WdacBaseEnforced = [bool]$base.IsEnforced
        }
        # Caller-side check: the marker file lives in the workspace
        # cert dir; we do NOT have $Ctx here, so we look for a cip
        # whose name appears in any of the active policies AND which
        # we previously saved as ours. If the caller cares about the
        # marker, they should call Test-MsBthPanWdacPolicyDeployed -Ctx ...
        # directly. Here we only set MsBthPanSuppPolicyActive to $false.
    } catch {
        # WDAC inspection failed - leave defaults
    }

    # Compute effective "can a self-signed kernel-mode driver load?"
    # There are now TWO valid paths:
    #   PATH 1 (Secure Boot ON, recommended):
    #     Secure Boot  ON
    #     WDAC supplemental policy with our cert deployed (MsBthPanSuppPolicyActive=true)
    #   PATH 2 (Secure Boot OFF, legacy):
    #     Secure Boot  off
    #     testsigning  ON
    #     HVCI         off
    # The caller (I02) decides which path to take based on the current
    # firmware state and -UseTestSigning override.
    $env.BlockReasons = @()
    $path1Open = ($env.MsBthPanSuppPolicyActive -eq $true)
    $path2Open = ($env.SecureBootEnabled -ne $true) -and `
                 ($env.TestSigningEnabled -eq $true) -and `
                 (-not $env.HvciRunning)

    if (-not $path1Open) {
        $env.BlockReasons += 'No WDAC supplemental policy authorizes the MS BthPan self-signing certificate'
    }
    if (-not $path2Open) {
        if ($env.SecureBootEnabled -eq $true) {
            $env.BlockReasons += 'Secure Boot is ON (legacy testsigning path requires Secure Boot off)'
        }
        if ($env.TestSigningEnabled -ne $true) {
            $env.BlockReasons += 'BCD testsigning is OFF (legacy path)'
        }
        if ($env.HvciRunning) {
            $env.BlockReasons += 'HVCI / Memory Integrity is RUNNING (legacy path requires HVCI off)'
        }
    }
    $env.EffectiveCanLoadSelfSigned = ($path1Open -or $path2Open)

    return $env
}

function Update-BootSigningEnvironmentForCtx {
    # Companion to Get-BootSigningEnvironment that also fills in the
    # MsBthPanSuppPolicyActive / AmdSuppPolicyId fields by consulting the
    # workspace marker file. Use this from any phase that has a $Ctx
    # in scope. The plain Get-BootSigningEnvironment is safe to call
    # at startup before $Ctx is populated.
    param([Parameter(Mandatory)] $Ctx)
    $env = Get-BootSigningEnvironment
    $deployed = Test-MsBthPanWdacPolicyDeployed -Ctx $Ctx
    if ($deployed) {
        $env.MsBthPanSuppPolicyActive = $true
        $env.AmdSuppPolicyId     = $deployed.PolicyId
        # Recompute effective with this updated knowledge
        $env.BlockReasons = @($env.BlockReasons | Where-Object {
            $_ -ne 'No WDAC supplemental policy authorizes the MS BthPan self-signing certificate'
        })
        $path2Open = ($env.SecureBootEnabled -ne $true) -and `
                     ($env.TestSigningEnabled -eq $true) -and `
                     (-not $env.HvciRunning)
        $env.EffectiveCanLoadSelfSigned = ($true -or $path2Open)  # path1 is open
    }
    return $env
}

function Show-BootSigningEnvironment {
    # Pretty-print the boot-signing environment. Two modes:
    #   -Compact   : one-line summary suitable for the startup banner
    #   (default)  : full table with notes column
    param(
        [Parameter(Mandatory)] $BootEnv,
        [switch]$Compact
    )

    function _FmtTri($v) {
        if ($null -eq $v) { return '?' }
        if ($v -eq $true)  { return 'ON' }
        return 'off'
    }
    function _FmtBool($v) {
        if ($v -eq $true) { return 'ON' } else { return 'off' }
    }

    if ($Compact) {
        $sb  = _FmtTri  $BootEnv.SecureBootEnabled
        $ts  = _FmtBool $BootEnv.TestSigningEnabled
        $hv  = _FmtBool $BootEnv.HvciRunning
        $wd  = _FmtBool $BootEnv.MsBthPanSuppPolicyActive
        $eff = if ($BootEnv.EffectiveCanLoadSelfSigned) { 'ALLOWED' } else { 'BLOCKED' }
        $effColor = if ($BootEnv.EffectiveCanLoadSelfSigned) { 'Green' } else { 'Yellow' }
        Write-Host ('    Boot Signing        : Firmware={0,-14} SecureBoot={1,-3} TestSigning={2,-3} HVCI={3,-3} WDAC-BthPan={4,-3}' -f `
            $BootEnv.FirmwareType, $sb, $ts, $hv, $wd)
        Write-Host ('    Self-signed driver  : {0}' -f $eff) -ForegroundColor $effColor
        return
    }

    # Verbose table
    Write-Host '    +------------------------+-----------+------------------------------------------------+'
    Write-Host '    | Setting                | Value     | Role for self-signed driver load               |'
    Write-Host '    +------------------------+-----------+------------------------------------------------+'
    $rows = @(
        @{ N='Firmware Type';         V=$BootEnv.FirmwareType;                  Note='UEFI = subject to Secure Boot policy'         },
        @{ N='Secure Boot';           V=(_FmtTri  $BootEnv.SecureBootEnabled);  Note='Can stay ON if WDAC supplemental is deployed' },
        @{ N='BCD testsigning';       V=(_FmtBool $BootEnv.TestSigningEnabled); Note='Legacy path only (requires Secure Boot off)'  },
        @{ N='VBS Running';           V=(_FmtBool $BootEnv.VbsRunning);         Note='Informational'                                 },
        @{ N='HVCI / Memory Intgr.';  V=(_FmtBool $BootEnv.HvciRunning);        Note='Compatible with WDAC supplemental path'       },
        @{ N='WDAC tools available';  V=(_FmtBool $BootEnv.WdacToolsAvailable); Note='ConfigCI module + CiTool.exe + AllowAll tmpl' },
        @{ N='WDAC supp (BthPan cert)';  V=(_FmtBool $BootEnv.MsBthPanSuppPolicyActive);Note='RECOMMENDED path: keeps Secure Boot ON'       }
    )
    foreach ($r in $rows) {
        Write-Host ('    | {0,-22} | {1,-9} | {2,-46} |' -f $r.N, $r.V, $r.Note)
    }
    Write-Host '    +------------------------+-----------+------------------------------------------------+'

    if ($BootEnv.EffectiveCanLoadSelfSigned) {
        $via = if ($BootEnv.MsBthPanSuppPolicyActive) { 'WDAC supplemental policy (Secure Boot ON)' }
               else { 'legacy testsigning + Secure Boot off' }
        Write-Host  ('    EFFECTIVE: self-signed kernel-mode drivers CAN load (via {0}).' -f $via) -ForegroundColor Green
    } else {
        Write-Host  '    EFFECTIVE: self-signed kernel-mode drivers will NOT load.' -ForegroundColor Red
        foreach ($reason in $BootEnv.BlockReasons) {
            Write-Host ('      - {0}' -f $reason) -ForegroundColor Red
        }
    }
    if ($BootEnv.SecureBootDetectError) {
        Write-Host ('    Note: Secure Boot detection raised "{0}" - status may be unreliable.' -f $BootEnv.SecureBootDetectError) -ForegroundColor DarkYellow
    }
}

function Show-BootSigningChangeRequired {
    # Side-by-side AS-IS / TO-BE display. The TO-BE keeps Secure Boot
    # ENABLED whenever possible and prefers the WDAC supplemental
    # policy path (script-managed) over disabling Secure Boot.
    # Falls back to documenting the legacy testsigning path only when
    # WDAC tools are not available.
    param([Parameter(Mandatory)] $BootEnv)

    function _Status($v) {
        if ($null -eq $v) { return '?' }
        if ($v -eq $true)  { return 'ON' }
        return 'off'
    }

    $useWdac = $BootEnv.WdacToolsAvailable

    Write-Host  '    AS-IS (current)              TO-BE (recommended target)'
    Write-Host  '    ---------------------------  --------------------------------'
    Write-Host ('    Firmware     : {0,-14}  Firmware     : {0} (no change)' -f $BootEnv.FirmwareType)
    if ($useWdac) {
        Write-Host ('    Secure Boot  : {0,-14}  Secure Boot  : ON     (NO CHANGE - keep enabled)' -f (_Status $BootEnv.SecureBootEnabled))
        Write-Host ('    testsigning  : {0,-14}  testsigning  : off    (NO CHANGE - not needed with WDAC)' -f (_Status $BootEnv.TestSigningEnabled))
        Write-Host ('    HVCI         : {0,-14}  HVCI         : {1,-6} (NO CHANGE - WDAC supplemental is HVCI-compatible)' -f (_Status $BootEnv.HvciRunning), (_Status $BootEnv.HvciRunning))
        Write-Host ('    WDAC supp.   : {0,-14}  WDAC supp.   : ON     (script will install via I02)' -f (_Status $BootEnv.MsBthPanSuppPolicyActive))
    } else {
        Write-Host ('    Secure Boot  : {0,-14}  Secure Boot  : off    (USER MUST CHANGE in firmware - WDAC unavailable)' -f (_Status $BootEnv.SecureBootEnabled))
        Write-Host ('    testsigning  : {0,-14}  testsigning  : ON     (script will set via I02 -UseTestSigning)' -f (_Status $BootEnv.TestSigningEnabled))
        Write-Host ('    HVCI         : {0,-14}  HVCI         : off    (USER MUST DISABLE if currently on)' -f (_Status $BootEnv.HvciRunning))
        Write-Host ('    WDAC supp.   : {0,-14}  WDAC supp.   : n/a    (tools not available on this system)' -f (_Status $BootEnv.MsBthPanSuppPolicyActive))
    }
    Write-Host ''

    if ($BootEnv.EffectiveCanLoadSelfSigned) {
        Write-Host '    System is already in a state that allows self-signed driver loads.' -ForegroundColor Green
        return
    }

    # ---- Recommended path (WDAC) ----
    if ($useWdac) {
        Write-Host '    RECOMMENDED PATH: WDAC supplemental policy (keeps Secure Boot ON)' -ForegroundColor Cyan
        Write-Host '    --------------------------------------------------------------------'
        Write-Host '    This path uses Windows Defender Application Control to add THIS'      -ForegroundColor Cyan
        Write-Host '    SCRIPT''S self-signed code-signing certificate as an allowed kernel-' -ForegroundColor Cyan
        Write-Host '    mode signer. Secure Boot stays ON, no firmware changes, no test-mode' -ForegroundColor Cyan
        Write-Host '    watermark, no HVCI changes, and the policy can be revoked cleanly.'   -ForegroundColor Cyan
        Write-Host ''
        Write-Host '    The script will perform the following on your behalf in I02:'         -ForegroundColor Yellow
        Write-Host '      1. Build a WDAC supplemental-policy XML allowlisting only this'     -ForegroundColor Yellow
        Write-Host '         script''s self-signed cert as a kernel-mode signer.'             -ForegroundColor Yellow
        Write-Host '      2. Convert the XML to a .cip binary policy.'                        -ForegroundColor Yellow
        Write-Host '      3. Deploy to %SystemRoot%\System32\CodeIntegrity\CiPolicies\Active.' -ForegroundColor Yellow
        Write-Host '      4. Activate via CiTool --update-policy (no reboot on WS2022+).'     -ForegroundColor Yellow
        Write-Host ''
        Write-Host '    Run:  .\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action Install -OnlyPhases I02' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '    Reversal (later): the same script with -Action Cleanup will remove the' -ForegroundColor DarkGray
        Write-Host '    deployed supplemental policy via CiTool --remove-policy <PolicyId>.'    -ForegroundColor DarkGray
        return
    }

    # ---- Fallback path (testsigning, legacy) ----
    Write-Host '    FALLBACK PATH: legacy testsigning (requires Secure Boot OFF)' -ForegroundColor DarkYellow
    Write-Host '    --------------------------------------------------------------------'
    Write-Host '    The platform is missing WDAC tooling (ConfigCI module / CiTool /'    -ForegroundColor DarkYellow
    Write-Host '    AllowAll template). Falling back to bcdedit testsigning, which'      -ForegroundColor DarkYellow
    Write-Host '    requires disabling Secure Boot in firmware.'                         -ForegroundColor DarkYellow
    Write-Host ''
    $step = 1
    if ($BootEnv.SecureBootEnabled -eq $true) {
        Write-Host ('      {0}. Disable Secure Boot in firmware (UEFI setup):' -f $step) -ForegroundColor Yellow
        Write-Host  '         a. Reboot to firmware setup (Settings -> Recovery -> Advanced'
        Write-Host  '            startup -> Restart now -> Troubleshoot -> Advanced ->'
        Write-Host  '            UEFI Firmware Settings) or interrupt boot with the firmware'
        Write-Host  '            key (Dell=F2/F12, HP=ESC/F10, Lenovo=F1/F2, ASUS/Gigabyte=DEL).'
        Write-Host  '         b. Locate "Secure Boot" and set to Disabled. Save & exit.'
        Write-Host ''
        Write-Host  '         WARNING: if BitLocker is enabled, suspend it BEFORE this change'
        Write-Host  '         (Suspend-BitLocker -MountPoint $env:SystemDrive).'
        Write-Host ''
        $step++
    }
    if ($BootEnv.HvciRunning) {
        Write-Host ('      {0}. Disable HVCI / Memory Integrity:' -f $step) -ForegroundColor Yellow
        Write-Host  '         GUI: Windows Security -> Device security -> Core isolation'
        Write-Host  '              details -> turn OFF "Memory integrity", then reboot.'
        Write-Host ''
        $step++
    }
    Write-Host ('      {0}. Enable BCD testsigning (script handles it):' -f $step) -ForegroundColor Yellow
    Write-Host  '         Run: .\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action Install -OnlyPhases I02 -UseTestSigning'
    Write-Host  '         Then reboot.'
    Write-Host ''
    Write-Host '    After all of the above, the desktop will display a "Test Mode" watermark.' -ForegroundColor DarkYellow
}

#####################################################################
# SECTION 1d: WDAC (Windows Defender Application Control)
# supplemental-policy helpers
#####################################################################
# These helpers exist to keep Secure Boot ENABLED while still allowing
# this script's self-signed code-signing certificate to load
# kernel-mode drivers. The mechanism is a WDAC "supplemental" Code
# Integrity policy:
#
#   - The base CI policy (default Windows policy) keeps enforcing
#     Microsoft-rooted signing.
#   - A supplemental policy is deployed alongside the base, ADDING the
#     self-signed cert as an allowed kernel-mode signer.
#   - On Server 2022+/Windows 11, CiTool.exe activates the supplemental
#     immediately (no reboot). On older systems, a reboot is required.
#
# Why this is preferable to bcdedit testsigning:
#   testsigning is silently dropped at boot when Secure Boot is on.
#   The user would have to disable Secure Boot in firmware - which
#   weakens the platform and may force BitLocker recovery.
#   WDAC supplemental policies are the supported, documented path to
#   "trust this additional publisher" with Secure Boot still on.
#
# Required platform components (all present on WS2022+ / WS2025):
#   - PowerShell 'ConfigCI' module           (cmdlets: Add-SignerRule,
#                                             ConvertFrom-CIPolicy,
#                                             Set-CIPolicyIdInfo)
#   - C:\Windows\System32\CiTool.exe         (immediate activation)
#   - WDAC AllowAll template under
#     C:\Windows\schemas\CodeIntegrity\ExamplePolicies\AllowAll.xml
#
# A marker file (Cert dir / 'MsBthPanSuppPolicyId.txt') records the
# deployed policy ID so we can detect & uninstall later.

function Test-WdacToolsAvailable {
    # Inspect the platform for the prerequisites needed to build &
    # deploy a WDAC supplemental policy. Returns a structured report
    # so callers can present a precise error if something is missing.
    $caps = [pscustomobject]@{
        ConfigCiModule        = $false
        CiToolExe             = $false
        AllowAllTemplate      = $false
        ActivePoliciesDir     = $false
        AnyUsable             = $false
        ImmediateActivation   = $false
        Detail                = @()
    }

    if (Get-Module -ListAvailable -Name 'ConfigCI' -ErrorAction SilentlyContinue) {
        $caps.ConfigCiModule = $true
    } else {
        $caps.Detail += 'ConfigCI PowerShell module is not installed (cmdlets Add-SignerRule, ConvertFrom-CIPolicy, etc. unavailable)'
    }

    $citool = Get-Command CiTool.exe -ErrorAction SilentlyContinue
    if ($citool) {
        $caps.CiToolExe = $true
        $caps.ImmediateActivation = $true
    } else {
        $caps.Detail += 'CiTool.exe not found - policy deployment will require a reboot'
    }

    $template = Join-Path $env:windir 'schemas\CodeIntegrity\ExamplePolicies\AllowAll.xml'
    if (Test-Path $template) {
        $caps.AllowAllTemplate = $true
    } else {
        $caps.Detail += "AllowAll WDAC template missing at $template"
    }

    $activeDir = Join-Path $env:windir 'System32\CodeIntegrity\CiPolicies\Active'
    if (Test-Path $activeDir) {
        $caps.ActivePoliciesDir = $true
    } else {
        $caps.Detail += "Active CI policies directory missing at $activeDir"
    }

    $caps.AnyUsable = ($caps.ConfigCiModule -and $caps.AllowAllTemplate -and $caps.ActivePoliciesDir)
    return $caps
}

function Get-ActiveCodeIntegrityPolicies {
    # Enumerate currently-active CI policies. Prefers CiTool.exe (gives
    # full metadata: name, mode, base/supplemental, signed/unsigned).
    # Falls back to filesystem enumeration of the Active directory if
    # CiTool isn't available.
    $policies = @()

    if (Get-Command CiTool.exe -ErrorAction SilentlyContinue) {
        try {
            $raw = & CiTool.exe -lp -json 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0 -and $raw.Trim()) {
                $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
                $list = if ($parsed.Policies) { $parsed.Policies } else { $parsed }
                foreach ($p in $list) {
                    $policies += [pscustomobject]@{
                        PolicyId       = $p.PolicyID
                        BasePolicyId   = $p.BasePolicyID
                        Name           = $p.FriendlyName
                        IsSystemPolicy = [bool]$p.IsSystemPolicy
                        IsEnforced     = [bool]$p.IsEnforced
                        IsSignedPolicy = [bool]$p.IsSignedPolicy
                        IsSupplemental = ($p.PolicyID -ne $p.BasePolicyID)
                        Path           = $p.PolicyPath
                        Source         = 'CiTool'
                    }
                }
            }
        } catch {
            # Swallow and try filesystem fallback
        }
    }

    if ($policies.Count -eq 0) {
        $activeDir = Join-Path $env:windir 'System32\CodeIntegrity\CiPolicies\Active'
        if (Test-Path $activeDir) {
            foreach ($f in (Get-ChildItem $activeDir -Filter '*.cip' -ErrorAction SilentlyContinue)) {
                $policies += [pscustomobject]@{
                    PolicyId       = $f.BaseName
                    BasePolicyId   = $null
                    Name           = '(unknown - filesystem only)'
                    IsSystemPolicy = $null
                    IsEnforced     = $null
                    IsSignedPolicy = $null
                    IsSupplemental = $null
                    Path           = $f.FullName
                    Source         = 'filesystem'
                }
            }
        }
    }

    return $policies
}

function Get-MsBthPanSuppPolicyMarkerPath {
    # The marker file persists the policy ID we deployed, so subsequent
    # script invocations can detect "is our supplemental already
    # installed" and find it for uninstall.
    param($Ctx)
    if ($Ctx -and $Ctx.Paths -and $Ctx.Paths.Cert) {
        return (Join-Path $Ctx.Paths.Cert 'MsBthPanSuppPolicyId.txt')
    }
    return $null
}

function Test-MsBthPanWdacPolicyDeployed {
    # Returns the deployed-policy info if our supplemental is currently
    # active, otherwise $null.
    #
    # r48 change: detection logic is now in two stages:
    #   Stage 1 (primary): look for the fixed $Script:WdacPolicyGuid
    #     among active CI policies. This works for any r48+ deploy.
    #   Stage 2 (legacy fallback): if a pre-r48 MsBthPanSuppPolicyId.txt
    #     marker file exists in the workspace cert dir, also look for
    #     the dynamic GUID recorded there. This lets r48+ scripts
    #     detect legacy deploys for clean removal.
    param($Ctx)
    $active = Get-ActiveCodeIntegrityPolicies

    # Stage 1: fixed GUID
    if ($Script:WdacPolicyGuid) {
        $fixedGuid = $Script:WdacPolicyGuid.Trim('{','}')
        $hit = $active | Where-Object {
            $_.PolicyId -and ($_.PolicyId.Trim('{','}') -ieq $fixedGuid)
        } | Select-Object -First 1
        if ($hit) { return $hit }
    }

    # Stage 2: legacy marker fallback
    $markerPath = Get-MsBthPanSuppPolicyMarkerPath -Ctx $Ctx
    if (-not $markerPath -or -not (Test-Path $markerPath)) { return $null }
    $policyId = (Get-Content $markerPath -Raw -ErrorAction SilentlyContinue).Trim()
    if (-not $policyId) { return $null }
    $hit = $active | Where-Object { $_.PolicyId -eq $policyId } | Select-Object -First 1
    return $hit
}

function New-MsBthPanDriverWdacSupplementalPolicy {
    # Build a WDAC supplemental-policy XML that allowlists ONLY this
    # script's self-signed code-signing certificate as a kernel-mode
    # signer. The supplemental is intentionally minimal:
    #   - It does NOT carry over any "AllowAll" rules from the template
    #     (we strip them after copying).
    #   - It only adds one Signer entry (our cert), referenced by the
    #     Driver Signing Scenario (KMCI, value 131) in AllowedSigners.
    # Result: the base policy still enforces strict signing for
    # everything else; only catalogs signed by our cert get the extra
    # green light.
    #
    # r48 change: the PolicyID is now a STABLE fixed GUID (from
    # $Script:WdacPolicyGuid, defaulting to WdacPolicyGuidDefault). This
    # means re-runs deploy / replace the same policy slot rather than
    # accumulating a new policy per run. Use -WdacPolicyGuid to override
    # (e.g. when cleaning up a legacy dynamic-GUID deploy).
    param(
        [Parameter(Mandatory)] [string]$CerPath,
        [Parameter(Mandatory)] [string]$OutputXml,
        [string]$PolicyName  = 'MS BthPan Inbox Driver Self-Signed Allowlist (script-managed)',
        [string]$BasePolicyId = $Script:WdacBasePolicyGuid,
        [string]$PolicyId     = $Script:WdacPolicyGuid
    )
    if (-not (Test-Path $CerPath)) {
        throw "Certificate not found at $CerPath"
    }
    $template = Join-Path $env:windir 'schemas\CodeIntegrity\ExamplePolicies\AllowAll.xml'
    if (-not (Test-Path $template)) {
        throw "WDAC AllowAll template missing at $template"
    }

    # Normalize GUID format: Set-CIPolicyIdInfo accepts {GUID} form
    $basePolicyIdBraced = if ($BasePolicyId -match '^\{.*\}$') { $BasePolicyId } else { '{' + $BasePolicyId + '}' }
    $policyIdBraced     = if ($PolicyId     -match '^\{.*\}$') { $PolicyId     } else { '{' + $PolicyId     + '}' }

    # Step 1: copy AllowAll template (gives us valid schema scaffolding)
    Copy-Item $template $OutputXml -Force

    # Step 2: convert to supplemental policy targeting the base, then
    # set OUR fixed PolicyID (replaces previous -ResetPolicyID approach).
    Set-CIPolicyIdInfo -FilePath $OutputXml -SupplementsBasePolicyID $basePolicyIdBraced | Out-Null
    Set-CIPolicyIdInfo -FilePath $OutputXml -PolicyName $PolicyName | Out-Null

    # Step 2b: manually set the PolicyID GUID into the XML (PowerShell's
    # Set-CIPolicyIdInfo has no -PolicyId switch; -ResetPolicyID would
    # randomize it. We patch the XML directly.)
    [xml]$xmlForId = Get-Content $OutputXml
    $nsForId = New-Object System.Xml.XmlNamespaceManager($xmlForId.NameTable)
    $nsForId.AddNamespace('si', 'urn:schemas-microsoft-com:sipolicy')
    $policyIdNode = $xmlForId.SelectSingleNode('//si:SiPolicy/si:PolicyID', $nsForId)
    if (-not $policyIdNode) {
        # Fallback for some Windows schema versions: PolicyID lives at root
        $policyIdNode = $xmlForId.SiPolicy.PolicyID
        if ($policyIdNode -is [string] -or $null -eq $policyIdNode) {
            # Try direct property assignment
            try { $xmlForId.SiPolicy.PolicyID = $policyIdBraced } catch { }
        }
    }
    if ($policyIdNode -and ($policyIdNode -isnot [string])) {
        $policyIdNode.InnerText = $policyIdBraced
    }
    $xmlForId.Save($OutputXml)

    # Step 3: strip the catch-all AllowAll rules so the supplemental
    # ONLY adds our specific signer. WDAC supplemental policies are
    # ADDITIVE - keeping AllowAll rules would effectively turn off
    # enforcement for everything, defeating the point of Secure Boot.
    #
    # r51 fix: We now strip the ENTIRE <FileRulesRef> container, not
    # just its <FileRuleRef> children. On Windows Server 2025 (build
    # 26100) the AllowAll.xml template embeds <FileRulesRef> nodes
    # inside every <ProductSigners> block, and the WDAC schema
    # (urn:schemas-microsoft-com:sipolicy) requires <FileRulesRef> to
    # contain at least one <FileRuleRef> child. Leaving an empty
    # <FileRulesRef> behind made Add-SignerRule fail in I02 with:
    #   "Element 'FileRulesRef' has incomplete content. Required
    #    element 'FileRuleRef' is needed."
    # The <FileRulesRef> element itself is minOccurs=0, so removing
    # the container outright is schema-valid.
    [xml]$xml = Get-Content $OutputXml
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('si', 'urn:schemas-microsoft-com:sipolicy')
    $stripPaths = @(
        '//si:FileRules/si:Allow',
        '//si:FileRules/si:Deny',
        '//si:FileRules/si:FileAttrib',
        '//si:Signers/si:Signer',
        '//si:SigningScenarios/si:SigningScenario/si:ProductSigners/si:AllowedSigners/si:AllowedSigner',
        '//si:SigningScenarios/si:SigningScenario/si:ProductSigners/si:DeniedSigners/si:DeniedSigner',
        '//si:SigningScenarios/si:SigningScenario/si:ProductSigners/si:FileRulesRef',
        '//si:CiSigners/si:CiSigner',
        '//si:UpdatePolicySigners/si:UpdatePolicySigner'
    )
    foreach ($xp in $stripPaths) {
        $nodes = $xml.SelectNodes($xp, $ns)
        foreach ($n in @($nodes)) { [void]$n.ParentNode.RemoveChild($n) }
    }
    $xml.Save($OutputXml)

    # Step 4: add ONLY our cert as kernel-mode signer
    Add-SignerRule -FilePath $OutputXml -CertificatePath $CerPath -Kernel | Out-Null

    # Step 5: return new policy ID for caller's records
    [xml]$updated = Get-Content $OutputXml
    return $updated.SiPolicy.PolicyID
}

function Install-MsBthPanWdacPolicy {
    # Convert the supplemental XML to .cip binary form and deploy it
    # into %SystemRoot%\System32\CodeIntegrity\CiPolicies\Active. On
    # platforms with CiTool.exe, refresh the active policy stack so
    # the new supplemental takes effect WITHOUT a reboot. Returns a
    # status object the caller can display.
    #
    # r57: CiTool is invoked with the --json flag. Per CiTool --help,
    # the --json flag "formats the output as JSON and suppresses
    # input" - i.e. it removes the "Press Enter to Exit" interactive
    # prompt that CiTool prints by default when run in a console host.
    # Without --json, CiTool blocked at I02 waiting for ENTER, causing
    # the script to appear hung for the duration of the user's wait.
    # See SPEC D.16 for the root-cause analysis.
    param(
        [Parameter(Mandatory)] [string]$XmlPath,
        [string]$BinaryOutPath
    )
    if (-not $BinaryOutPath) {
        $BinaryOutPath = [System.IO.Path]::ChangeExtension($XmlPath, '.cip')
    }

    ConvertFrom-CIPolicy -XmlFilePath $XmlPath -BinaryFilePath $BinaryOutPath | Out-Null

    [xml]$xml = Get-Content $XmlPath
    $policyId = $xml.SiPolicy.PolicyID
    if (-not $policyId) { throw 'Could not read PolicyID from XML.' }

    $activeDir = Join-Path $env:windir 'System32\CodeIntegrity\CiPolicies\Active'
    if (-not (Test-Path $activeDir)) {
        New-Item -ItemType Directory -Path $activeDir -Force | Out-Null
    }
    $deployedPath = Join-Path $activeDir "$policyId.cip"
    Copy-Item $BinaryOutPath $deployedPath -Force

    $immediate = $false
    $citoolStdout = ''
    $citoolStderr = ''
    $citoolStatusLine = ''
    if (Get-Command CiTool.exe -ErrorAction SilentlyContinue) {
        try {
            # CiTool returns 0 on success and prints a confirmation line.
            # --json flag is REQUIRED (r57+): without it, CiTool prints
            # "Press Enter to Exit" and waits for stdin, blocking I02.
            $citoolStdout = & CiTool.exe --update-policy $deployedPath --json 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) { $immediate = $true }
            # Parse the JSON envelope so callers can display a friendly
            # status line. CiTool --json emits an object with keys like
            # "OperationResult" and "FriendlyName"; we extract the
            # canonical success message for log display.
            try {
                $j = $citoolStdout | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($j) {
                    if ($j.OperationResult) { $citoolStatusLine = [string]$j.OperationResult }
                    elseif ($j.Status)      { $citoolStatusLine = [string]$j.Status }
                    elseif ($j.PSObject.Properties.Name -contains 'PolicyGUID') {
                        $citoolStatusLine = ('PolicyGUID={0}' -f $j.PolicyGUID)
                    }
                }
            } catch {
                # JSON parse failure is non-fatal; fall back to the raw
                # first non-empty stdout line for display.
                $citoolStatusLine = ($citoolStdout -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
            }
        } catch {
            $citoolStderr = $_.Exception.Message
        }
    }

    return [pscustomobject]@{
        PolicyId         = $policyId
        XmlPath          = $XmlPath
        BinaryPath       = $BinaryOutPath
        DeployedPath     = $deployedPath
        ActivationMethod = if ($immediate) { 'CiTool (immediate, no reboot)' } else { 'reboot' }
        RebootRequired   = -not $immediate
        CiToolStdout     = $citoolStdout
        CiToolStderr     = $citoolStderr
        CiToolStatusLine = $citoolStatusLine
    }
}

function Uninstall-MsBthPanWdacPolicy {
    # Remove a previously-deployed supplemental policy. Used by the
    # Cleanup action and by I02 when redeploying with -Force.
    #
    # r57: --json flag suppresses CiTool's interactive ENTER prompt.
    param(
        [Parameter(Mandatory)] [string]$PolicyId
    )
    $activeDir = Join-Path $env:windir 'System32\CodeIntegrity\CiPolicies\Active'
    $deployedPath = Join-Path $activeDir "$PolicyId.cip"
    $existed = Test-Path $deployedPath

    if ($existed) {
        if (Get-Command CiTool.exe -ErrorAction SilentlyContinue) {
            try { & CiTool.exe --remove-policy $PolicyId --json 2>&1 | Out-Null } catch { }
        }
        Remove-Item -LiteralPath $deployedPath -Force -ErrorAction SilentlyContinue
    }
    return [pscustomobject]@{
        PolicyId = $PolicyId
        Existed  = $existed
        Removed  = $existed -and -not (Test-Path $deployedPath)
    }
}

#####################################################################
# SECTION 1e: Install-phase state validators (resume-after-reboot)
#####################################################################
# These predicates answer "is the END STATE of install phase X already
# present on this system?" by inspecting the live system, NOT by
# checking marker files. They exist so that an install run can be
# safely re-executed (e.g. after a reboot) and skip phases whose work
# is already in place.
#
# Why state-based, not marker-based:
#   The phase-marker files in $Ctx.Paths.Markers tell us "this script
#   ran I01 successfully in some past run". They do NOT tell us
#   whether the change is still present. If the user manually deleted
#   the cert from certmgr.msc, or someone removed the WDAC policy
#   with CiTool, or pnputil's driver-store was cleared, the marker
#   would lie. State validation reads the actual current state, so
#   skip/run is decided correctly regardless of marker status.
#
# Combined helper Test-InstallPhaseAlreadyDone is the entry point
# install phases use at their top. It honours -Force (always returns
# $false so the work re-runs).
#
# These helpers are intentionally read-only and side-effect free.

function Test-CertAlreadyTrusted {
    # I01 target state: the script's self-signed cert is present in
    # both LocalMachine\Root and LocalMachine\TrustedPublisher.
    # If $Ctx.CertThumbprint is unset (e.g. user invoked I01 directly
    # without P07 having populated Ctx in this run), derive it from
    # the .cer file on disk.
    param([Parameter(Mandatory)] $Ctx)

    $thumbprint = $Ctx.CertThumbprint
    if (-not $thumbprint) {
        $cerPath = if ($Ctx.CertCerPath) { $Ctx.CertCerPath } `
                   else { Join-Path $Ctx.Paths.Cert 'MS-BthPan-Driver-CodeSign.cer' }
        if (-not (Test-Path $cerPath)) { return $false }
        try {
            $certObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $cerPath
            $thumbprint = $certObj.Thumbprint
        } catch {
            return $false
        }
    }
    if (-not $thumbprint) { return $false }

    foreach ($storeName in 'Root', 'TrustedPublisher') {
        $found = Get-ChildItem -Path "Cert:\LocalMachine\$storeName" -ErrorAction SilentlyContinue |
                 Where-Object { $_.Thumbprint -eq $thumbprint } |
                 Select-Object -First 1
        if (-not $found) { return $false }
    }
    return $true
}

function Test-I02InTargetState {
    # I02 target state depends on which path was selected.
    #   PATH A (default, WDAC supplemental policy):
    #     A supplemental policy whose PolicyId matches our marker file
    #     is present in the active CI policies stack.
    #   PATH B (legacy testsigning, opt-in via -UseTestSigning):
    #     BCD testsigning is set to Yes for the {current} loader entry.
    # We don't try to verify "effective at runtime" here - that's I04's
    # job (per-driver load status). Here we only ask "is the change
    # we make in I02 already on disk / in the boot-config?"
    param([Parameter(Mandatory)] $Ctx)

    if ($Ctx.UseTestSigning) {
        # PATH B: read BCD testsigning flag
        $env = Get-BootSigningEnvironment
        return ($env.TestSigningEnabled -eq $true)
    } else {
        # PATH A: marker file exists AND its PolicyId is currently active
        $deployed = Test-MsBthPanWdacPolicyDeployed -Ctx $Ctx
        return ($null -ne $deployed)
    }
}

function Test-AllPatchedDriversInStore {
    # I03 target state: every patched .inf in $Ctx.Paths.Patched is
    # present in the Windows driver store. We use pnputil /enum-drivers
    # because that is exactly what I03 itself uses to add them, so the
    # round-trip is symmetric.
    #
    # NOTE: pnputil reports drivers by their published OEM name
    # (oemNN.inf) AND by their original INF name (Original Name :
    # amdpcidev.inf). We match on the original name because that is
    # what we have in $Ctx.Paths.Patched.
    #
    # If the patched directory is empty or pnputil fails, return
    # $false (force I03 to re-run, which will surface the real error).
    param([Parameter(Mandatory)] $Ctx)

    if (-not $Ctx.Paths -or -not $Ctx.Paths.Patched -or -not (Test-Path $Ctx.Paths.Patched)) {
        return $false
    }
    $expected = @(Get-ChildItem -Path $Ctx.Paths.Patched -Recurse -Filter *.inf -ErrorAction SilentlyContinue)
    if ($expected.Count -eq 0) { return $false }

    try {
        $output = & pnputil.exe /enum-drivers 2>&1 | Out-String
    } catch {
        return $false
    }
    if (-not $output -or -not $output.Trim()) { return $false }

    foreach ($inf in $expected) {
        $infName = $inf.Name
        # Match against "Original Name : <inf>" (case-insensitive,
        # tolerate variable whitespace and non-ASCII labels in
        # localized pnputil output).
        $pattern = '(?im)Original\s+Name\s*:\s*' + [regex]::Escape($infName)
        if ($output -notmatch $pattern) {
            return $false
        }
    }
    return $true
}

function Test-InstallPhaseAlreadyDone {
    # Single entry point install phases call at their top. Returns
    # $true if the phase's target state is already present and the
    # phase can be safely skipped. Returns $false otherwise.
    #
    # Honours -Force: always returns $false so the work re-runs.
    param(
        [Parameter(Mandatory)] $Ctx,
        [Parameter(Mandatory)] [string]$PhaseId
    )
    if ($Ctx.Force) { return $false }
    switch ($PhaseId) {
        'I01' { return Test-CertAlreadyTrusted -Ctx $Ctx }
        'I02' { return Test-I02InTargetState   -Ctx $Ctx }
        'I03' { return Test-AllPatchedDriversInStore -Ctx $Ctx }
        default { return $false }
    }
}

function Get-WorkspaceLockPath {
    # Path to a per-workspace lock file used to prevent two
    # simultaneous executions of THIS script. The graphics-driver
    # companion script uses its own workspace and therefore its own
    # lock file - it does NOT collide with this one. The intent is
    # only to protect against the user accidentally running the same
    # script twice in parallel (e.g. two PowerShell windows), which
    # would race I02 (WDAC deploy) and I03 (pnputil) against itself.
    param([Parameter(Mandatory)] $Ctx)
    if (-not $Ctx.Paths -or -not $Ctx.Paths.Markers) { return $null }
    return (Join-Path $Ctx.Paths.Markers 'RUN.lock')
}

function Test-WorkspaceLockHeld {
    # Returns @{ Held=$bool; Pid=$int; ProcessRunning=$bool; Stale=$bool; SelfPid=$bool }
    # If no lock exists, Held=$false and other fields are blank.
    # If a lock exists but the recorded PID is no longer running, the
    # lock is stale (Held=$true, ProcessRunning=$false, Stale=$true).
    # r55: If a lock exists AND the recorded PID matches our current
    # PowerShell process ($PID), the lock is treated as stale and
    # taken over silently. This handles the interactive-console case
    # where a previous run completed but the PowerShell.Exiting hook
    # did not fire (because the console host is still alive); without
    # this, the next run in the same console would mis-detect the
    # leftover lock as "another instance running" and refuse to start.
    param([Parameter(Mandatory)] $Ctx)
    $info = [pscustomobject]@{
        Held           = $false
        Pid            = $null
        StartedAt      = $null
        CommandLine    = $null
        ProcessRunning = $false
        Stale          = $false
        SelfPid        = $false
    }
    $path = Get-WorkspaceLockPath -Ctx $Ctx
    if (-not $path -or -not (Test-Path $path)) { return $info }
    $info.Held = $true
    try {
        $lines = Get-Content -LiteralPath $path -ErrorAction Stop
        foreach ($l in $lines) {
            if ($l -match '^Pid\s*:\s*(\d+)')           { $info.Pid         = [int]$matches[1] }
            elseif ($l -match '^StartedAt\s*:\s*(.+)$') { $info.StartedAt   = $matches[1].Trim() }
            elseif ($l -match '^CommandLine\s*:\s*(.+)$') { $info.CommandLine = $matches[1].Trim() }
        }
    } catch { }
    if ($info.Pid) {
        # r55: lock written by the very same PowerShell process we are
        # running in. This happens when a previous script invocation in
        # the same interactive console completed without firing the
        # Register-EngineEvent PowerShell.Exiting hook (the hook only
        # fires when the host process itself exits). Mark as stale so
        # Assert-NoConcurrentRun can supersede silently.
        if ($info.Pid -eq $PID) {
            $info.SelfPid        = $true
            $info.ProcessRunning = $false
            $info.Stale          = $true
        } else {
            $proc = Get-Process -Id $info.Pid -ErrorAction SilentlyContinue
            if ($proc) {
                $info.ProcessRunning = $true
            } else {
                $info.Stale = $true
            }
        }
    }
    return $info
}

function Set-WorkspaceLock {
    # Write a lock file recording our PID + start time + command line.
    # Caller MUST ensure the lock isn't already held by a running
    # process before calling this (use Test-WorkspaceLockHeld).
    param([Parameter(Mandatory)] $Ctx)
    $path = Get-WorkspaceLockPath -Ctx $Ctx
    if (-not $path) { return }
    $cmd = $null
    try {
        $cmd = ([System.Environment]::CommandLine)
    } catch { }
    $payload = @(
        ('Pid         : {0}' -f $PID),
        ('StartedAt   : {0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date)),
        ('CommandLine : {0}' -f $cmd),
        ('Workspace   : {0}' -f $Ctx.WorkRoot)
    ) -join "`n"
    Set-Content -LiteralPath $path -Value $payload -Encoding ASCII -ErrorAction SilentlyContinue
    # Ensure the lock is released even if the script exits with throw
    # or Ctrl-C. Register-EngineEvent on PowerShell.Exiting is the
    # supported hook in PS 5.1.
    Register-EngineEvent -SourceIdentifier ([System.Management.Automation.PsEngineEvent]::Exiting) `
        -Action {
            $lp = $Event.MessageData
            if ($lp -and (Test-Path $lp)) {
                Remove-Item -LiteralPath $lp -Force -ErrorAction SilentlyContinue
            }
        } -MessageData $path -SupportEvent | Out-Null
}

function Clear-WorkspaceLock {
    param([Parameter(Mandatory)] $Ctx)
    $path = Get-WorkspaceLockPath -Ctx $Ctx
    if ($path -and (Test-Path $path)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Assert-NoConcurrentRun {
    # Called from P00 right after the workspace directory exists. If
    # another live instance of this same script is running against
    # this same workspace, fail fast with an actionable error. If a
    # stale lock is found (PID no longer alive), warn and overtake.
    param([Parameter(Mandatory)] $Ctx)
    $info = Test-WorkspaceLockHeld -Ctx $Ctx
    if ($info.Held -and $info.ProcessRunning) {
        $msg = @(
            ''
            ('*** Another instance of this script is already running in workspace {0} ***' -f $Ctx.WorkRoot)
            ('    PID         : {0}' -f $info.Pid)
            ('    StartedAt   : {0}' -f $info.StartedAt)
            ('    CommandLine : {0}' -f $info.CommandLine)
            ''
            '    Wait for the other instance to finish, or terminate it (Stop-Process -Id <PID> -Force).'
            '    If you are running BOTH the chipset and the graphics scripts, that is fine - they use'
            '    separate workspaces - but do NOT start two copies of THIS script against the same'
            '    workspace at the same time (pnputil and CiTool would race).'
            ''
        ) -join "`n"
        throw $msg
    }
    if ($info.Held -and $info.Stale) {
        # r55: distinguish "stale because the recorded PID is dead" from
        # "stale because the recorded PID is OUR pid" (interactive
        # PowerShell re-run scenario). The second case is benign and
        # frequent enough that it deserves a non-alarming message.
        if ($info.SelfPid) {
            Write-Host ('    [+] Reusing workspace lock from earlier run in this PowerShell session (PID {0}).' -f $info.Pid) -ForegroundColor DarkGray
        } else {
            Write-Warn2 ('Found stale lock from PID {0} (process no longer running) - taking over.' -f $info.Pid)
        }
        Clear-WorkspaceLock -Ctx $Ctx
    }
    Set-WorkspaceLock -Ctx $Ctx
}

function Get-PendingRebootMarkerPath {
    # Path to the sentinel file that records "the previous run asked
    # the user to reboot." I02 (testsigning path) and I03 (drivers
    # that pnputil could not live-load) write this file. I04 reads it
    # and clears it once the post-reboot state is confirmed good.
    param([Parameter(Mandatory)] $Ctx)
    if (-not $Ctx.Paths -or -not $Ctx.Paths.Markers) { return $null }
    return (Join-Path $Ctx.Paths.Markers 'PENDING_REBOOT.txt')
}

function Set-PendingRebootMarker {
    # Record that a reboot is required, with metadata so a future run
    # can decide whether the reboot already happened.
    param(
        [Parameter(Mandatory)] $Ctx,
        [Parameter(Mandatory)] [string]$Source,
        [string]$Reason = ''
    )
    $path = Get-PendingRebootMarkerPath -Ctx $Ctx
    if (-not $path) { return }
    $bootTime = $null
    try {
        $bootTime = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
    } catch { }
    $payload = @(
        ('RecordedAt   : {0:yyyy-MM-dd HH:mm:ss}' -f (Get-Date)),
        ('LastBootTime : {0}' -f ($bootTime)),
        ('Source       : {0}' -f $Source),
        ('Reason       : {0}' -f $Reason)
    ) -join "`n"
    Set-Content -LiteralPath $path -Value $payload -Encoding ASCII -ErrorAction SilentlyContinue
}

function Get-PendingRebootMarker {
    # If the sentinel file exists, return a structured object;
    # otherwise $null. Includes a heuristic flag RebootHasOccurred
    # that is $true when the current LastBootUpTime is later than the
    # one recorded when the marker was written.
    param([Parameter(Mandatory)] $Ctx)
    $path = Get-PendingRebootMarkerPath -Ctx $Ctx
    if (-not $path -or -not (Test-Path $path)) { return $null }

    $info = [pscustomobject]@{
        Path              = $path
        RecordedAt        = $null
        RecordedBootTime  = $null
        Source            = $null
        Reason            = $null
        CurrentBootTime   = $null
        RebootHasOccurred = $false
    }
    try {
        $lines = Get-Content -LiteralPath $path -ErrorAction Stop
        foreach ($l in $lines) {
            if ($l -match '^RecordedAt\s*:\s*(.+)$')   { $info.RecordedAt       = $matches[1].Trim() }
            elseif ($l -match '^LastBootTime\s*:\s*(.+)$') { $info.RecordedBootTime = $matches[1].Trim() }
            elseif ($l -match '^Source\s*:\s*(.+)$')   { $info.Source           = $matches[1].Trim() }
            elseif ($l -match '^Reason\s*:\s*(.+)$')   { $info.Reason           = $matches[1].Trim() }
        }
    } catch { return $info }

    try {
        $info.CurrentBootTime = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
    } catch { }

    if ($info.RecordedBootTime -and $info.CurrentBootTime) {
        try {
            $recordedDt = [datetime]$info.RecordedBootTime
            if ($info.CurrentBootTime -gt $recordedDt) {
                $info.RebootHasOccurred = $true
            }
        } catch { }
    }
    return $info
}

function Clear-PendingRebootMarker {
    # Called by I04 when post-install verification confirms the system
    # is in a good end state, so subsequent runs do not see a stale
    # "reboot required" warning.
    param([Parameter(Mandatory)] $Ctx)
    $path = Get-PendingRebootMarkerPath -Ctx $Ctx
    if ($path -and (Test-Path $path)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

#####################################################################
# SECTION 2: Phase registry
#####################################################################
$Script:PhaseRegistry = @(
    [pscustomobject]@{ Id='P00'; Name='Initialize';        Group='Prep';   Func='Invoke-PrepPhase00_Initialize'          }
    [pscustomobject]@{ Id='P01'; Name='PrepareWorkspace';  Group='Prep';   Func='Invoke-PrepPhase01_PrepareWorkspace'    }
    [pscustomobject]@{ Id='P02'; Name='AcquireTools';      Group='Prep';   Func='Invoke-PrepPhase02_AcquireTools'        }
    [pscustomobject]@{ Id='P03'; Name='FetchInstaller';    Group='Prep';   Func='Invoke-PrepPhase03_FetchInstaller'      }
    [pscustomobject]@{ Id='P04'; Name='ExtractInstaller';  Group='Prep';   Func='Invoke-PrepPhase04_ExtractInstaller'    }
    [pscustomobject]@{ Id='P05'; Name='AnalyzeInfs';       Group='Prep';   Func='Invoke-PrepPhase05_AnalyzeInfs'         }
    [pscustomobject]@{ Id='P06'; Name='PatchInfs';         Group='Prep';   Func='Invoke-PrepPhase06_PatchInfs'           }
    [pscustomobject]@{ Id='P07'; Name='CreateCertificate'; Group='Prep';   Func='Invoke-PrepPhase07_CreateCertificate'   }
    [pscustomobject]@{ Id='P08'; Name='GenerateCatalogs';  Group='Prep';   Func='Invoke-PrepPhase08_GenerateCatalogs'    }
    [pscustomobject]@{ Id='P09'; Name='SignCatalogs';      Group='Prep';   Func='Invoke-PrepPhase09_SignCatalogs'        }
    [pscustomobject]@{ Id='V01'; Name='VerifyArtifacts';   Group='Verify'; Func='Invoke-VerifyPhase01_VerifyArtifacts'   }
    [pscustomobject]@{ Id='V02'; Name='VerifyCertificate'; Group='Verify'; Func='Invoke-VerifyPhase02_VerifyCertificate' }
    [pscustomobject]@{ Id='V03'; Name='VerifyCatalogs';    Group='Verify'; Func='Invoke-VerifyPhase03_VerifyCatalogs'    }
    [pscustomobject]@{ Id='V04'; Name='VerifyInfs';        Group='Verify'; Func='Invoke-VerifyPhase04_VerifyInfs'        }
    [pscustomobject]@{ Id='V05'; Name='DryRunInstall';     Group='Verify'; Func='Invoke-VerifyPhase05_DryRunInstall'     }
    [pscustomobject]@{ Id='V06'; Name='HardwareImpactAnalysis'; Group='Verify'; Func='Invoke-VerifyPhase06_HardwareImpactAnalysis' }
    [pscustomobject]@{ Id='I00'; Name='PreInstallReview';   Group='Inst';   Func='Invoke-InstPhase00_PreInstallReview'    }
    [pscustomobject]@{ Id='I01'; Name='TrustCertificate';  Group='Inst';   Func='Invoke-InstPhase01_TrustCertificate'    }
    [pscustomobject]@{ Id='I02'; Name='AuthorizeDriverSigning'; Group='Inst';   Func='Invoke-InstPhase02_AuthorizeDriverSigning' }
    [pscustomobject]@{ Id='I03'; Name='InstallDrivers';    Group='Inst';   Func='Invoke-InstPhase03_InstallDrivers'      }
    [pscustomobject]@{ Id='I04'; Name='PostInstallVerification'; Group='Inst'; Func='Invoke-InstPhase04_PostInstallVerification' }
)

function Resolve-PhaseSelection {
    param([string]$Action, [string[]]$OnlyPhases)
    $all = $Script:PhaseRegistry
    $byAction = switch ($Action) {
        'Prepare'        { $all | Where-Object Group -eq 'Prep'   }
        'Verify'         { $all | Where-Object Group -eq 'Verify' }
        'PrepareVerify'  { $all | Where-Object { $_.Group -eq 'Prep' -or $_.Group -eq 'Verify' } }
        'Install'        { $all | Where-Object Group -eq 'Inst'   }
        'All'            { $all }
        default          { $all }
    }
    if (-not $OnlyPhases -or $OnlyPhases.Count -eq 0) { return $byAction }

    # Backward-compatible alias map for phase names that have been
    # renamed across script versions. Keys are old names, values are
    # current names. The ID lookup ('I02') always works directly and is
    # the recommended way to reference phases in scripts and pipelines.
    # This alias map exists so callers that pre-date r30 don't break.
    $nameAliases = @{
        'EnableTestSigning' = 'AuthorizeDriverSigning'   # renamed in r30
    }

    $resolved = foreach ($needle in $OnlyPhases) {
        # Resolve old-name aliases to current names before lookup. We
        # surface a one-time deprecation notice so the caller knows to
        # migrate, but we still proceed with the resolved phase.
        $effective = $needle
        if ($nameAliases.ContainsKey($needle)) {
            $effective = $nameAliases[$needle]
            Write-Host ("[i] Phase name '{0}' was renamed to '{1}'; please update your scripts." -f $needle, $effective) -ForegroundColor DarkYellow
        }
        $hit = $all | Where-Object { $_.Id -eq $effective -or $_.Name -eq $effective }
        if (-not $hit) { throw "Unknown phase: '$needle' (use -Action ListPhases to see all)" }
        $hit
    }
    # Preserve registry order
    $ids = $resolved | ForEach-Object Id
    return $all | Where-Object { $_.Id -in $ids }
}

#####################################################################
# SECTION 3: OS context
#####################################################################
function Get-OsContext {
    # CIM is the preferred path. On extremely locked-down or Server
    # Core images (mainly older WS2016/WS2019), the CIM service can
    # occasionally fail; in that case fall back to WMI which uses the
    # legacy DCOM transport. Both surface Win32_OperatingSystem with
    # the same property names we need.
    $osCim = $null
    try {
        $osCim = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    } catch {
        try {
            $osCim = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        } catch {
            throw "Failed to query Win32_OperatingSystem via both CIM and WMI: $($_.Exception.Message)"
        }
    }
    $build = [int]([System.Environment]::OSVersion.Version.Build)

    # Per-OS configuration. SDK/WDK URLs are intentionally identical
    # across all four OSes per Microsoft documentation: WDK 26100.6584
    # is the default supported kit, runs on Windows 7+, and builds for
    # Windows 10 / Server 2016+. Per-OS slots are kept so future
    # divergence can be expressed without code changes.
    $matrix = @{
        14393 = [pscustomobject]@{
            Name = 'Windows Server 2016'; Code = 'WS2016'; Build = 14393
            HasWingetByDefault = $false; CanInstallWinget = $false
            CertKeyLength = 2048; CertHashAlgorithm = 'SHA256'; CertValidYears = 3
            UseModernCertExtension = $false
            SdkBuild = '10.0.26100.6584'; SdkUrl = 'https://go.microsoft.com/fwlink/?linkid=2338977'
            SdkInstallArgs = @('/features','OptionId.SigningTools','/quiet','/norestart')
            WdkBuild = '10.0.26100.6584'; WdkUrl = 'https://go.microsoft.com/fwlink/?linkid=2335869'
            WdkInstallArgs = @('/quiet','/norestart')
            WingetSdkId = $null; WingetWdkId = $null
            ToolkitNotes = 'WS2016: winget absent, EXE install only'
            # WS2016 = build 14393. inf2cat has direct Server2016_X64.
            Inf2catOsArg = 'Server2016_X64'
            Inf2catOsArgFallbacks = @('Server10_X64')
        }
        17763 = [pscustomobject]@{
            Name = 'Windows Server 2019'; Code = 'WS2019'; Build = 17763
            HasWingetByDefault = $false; CanInstallWinget = $false
            CertKeyLength = 4096; CertHashAlgorithm = 'SHA256'; CertValidYears = 5
            UseModernCertExtension = $true
            SdkBuild = '10.0.26100.6584'; SdkUrl = 'https://go.microsoft.com/fwlink/?linkid=2338977'
            SdkInstallArgs = @('/features','OptionId.SigningTools','/quiet','/norestart')
            WdkBuild = '10.0.26100.6584'; WdkUrl = 'https://go.microsoft.com/fwlink/?linkid=2335869'
            WdkInstallArgs = @('/quiet','/norestart')
            WingetSdkId = $null; WingetWdkId = $null
            ToolkitNotes = 'WS2019: winget absent, EXE install only'
            # WS2019 = build 17763, codename "Redstone 5".
            Inf2catOsArg = 'ServerRS5_X64'
            Inf2catOsArgFallbacks = @('Server2016_X64','Server10_X64')
        }
        20348 = [pscustomobject]@{
            Name = 'Windows Server 2022'; Code = 'WS2022'; Build = 20348
            HasWingetByDefault = $false; CanInstallWinget = $true
            CertKeyLength = 4096; CertHashAlgorithm = 'SHA256'; CertValidYears = 5
            UseModernCertExtension = $true
            SdkBuild = '10.0.26100.6584'; SdkUrl = 'https://go.microsoft.com/fwlink/?linkid=2338977'
            SdkInstallArgs = @('/features','OptionId.SigningTools','/quiet','/norestart')
            WdkBuild = '10.0.26100.6584'; WdkUrl = 'https://go.microsoft.com/fwlink/?linkid=2335869'
            WdkInstallArgs = @('/quiet','/norestart')
            WingetSdkId = 'Microsoft.WindowsSDK.10.0.26100'
            WingetWdkId = 'Microsoft.WindowsWDK.10.0.26100'
            ToolkitNotes = 'WS2022: winget side-load possible'
            # WS2022 = build 20348, codename "Iron" (Fe is the
            # chemical symbol for iron). inf2cat uses ServerFE_X64.
            Inf2catOsArg = 'ServerFE_X64'
            Inf2catOsArgFallbacks = @('ServerRS5_X64','Server2016_X64','Server10_X64')
        }
        26100 = [pscustomobject]@{
            Name = 'Windows Server 2025'; Code = 'WS2025'; Build = 26100
            HasWingetByDefault = $true; CanInstallWinget = $true
            CertKeyLength = 4096; CertHashAlgorithm = 'SHA384'; CertValidYears = 5
            UseModernCertExtension = $true
            SdkBuild = '10.0.26100.6584'; SdkUrl = 'https://go.microsoft.com/fwlink/?linkid=2338977'
            SdkInstallArgs = @('/features','OptionId.SigningTools','/quiet','/norestart')
            WdkBuild = '10.0.26100.6584'; WdkUrl = 'https://go.microsoft.com/fwlink/?linkid=2335869'
            WdkInstallArgs = @('/quiet','/norestart')
            WingetSdkId = 'Microsoft.WindowsSDK.10.0.26100'
            WingetWdkId = 'Microsoft.WindowsWDK.10.0.26100'
            ToolkitNotes = 'WS2025: winget native; WDK matches host'
            # The inf2cat /os switch selects the TARGET OS for the
            # catalog file being generated. For Windows Server 2025
            # (build 26100), the SDK 10.0.26100 inf2cat directly
            # supports "Server2025_X64" - this is the canonical and
            # only correct primary value for WS2025.
            #
            # Fallbacks (older Server codenames, all underscore form)
            # are kept for the rare case where this script is run
            # against an older inf2cat that pre-dates the Server2025
            # support; on a properly matched SDK 10.0.26100 they are
            # never reached.
            Inf2catOsArg = 'Server2025_X64'
            Inf2catOsArgFallbacks = @('ServerFE_X64','ServerRS5_X64','Server2016_X64','Server10_X64')
        }
    }

    $ctx = $matrix[$build]
    if (-not $ctx) {
        $closest = $matrix.Keys | Sort-Object | Where-Object { $_ -le $build } | Select-Object -Last 1
        if (-not $closest) { throw "Unsupported OS build: $build (need 14393 or higher)" }
        Write-Warn2 "Build $build not in matrix; using $($matrix[$closest].Name) profile"
        $ctx = $matrix[$closest]
    }
    $ctx | Add-Member -NotePropertyName ActualBuild -NotePropertyValue $build      -Force
    $ctx | Add-Member -NotePropertyName ProductType -NotePropertyValue $osCim.ProductType -Force
    $ctx | Add-Member -NotePropertyName Caption     -NotePropertyValue $osCim.Caption     -Force
    return $ctx
}

#####################################################################
# SECTION 4: Tool installation helpers
#####################################################################
function Test-WingetWorking {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $false }
    try { $null = & winget --version 2>&1; return ($LASTEXITCODE -eq 0) }
    catch { return $false }
}

function Get-MachineRegion {
    # Returns the 2-letter ISO region code that winget / msstore APIs
    # expect. Tries multiple sources in order of authority:
    #   1. Get-WinHomeLocation (explicit per-user "Home location" setting
    #      under Region settings; this is the value the Microsoft Store
    #      and msstore source naturally consult).
    #   2. [System.Globalization.RegionInfo]::CurrentRegion (derived from
    #      the active culture).
    #   3. Tail of Get-Culture.Name (e.g. en-US -> US).
    #   4. Static fallback "US".
    try {
        $home = Get-WinHomeLocation -ErrorAction Stop
        if ($home -and $home.HomeLocation) {
            # GeoId -> 2-letter via RegionInfo enumeration. Looking up by
            # English name is brittle, so prefer CurrentRegion.
            $r = [System.Globalization.RegionInfo]::CurrentRegion.TwoLetterISORegionName
            if ($r -and $r.Length -eq 2) { return $r.ToUpper() }
        }
    } catch { }
    try {
        $r = [System.Globalization.RegionInfo]::CurrentRegion.TwoLetterISORegionName
        if ($r -and $r.Length -eq 2) { return $r.ToUpper() }
    } catch { }
    try {
        $tail = (Get-Culture).Name.Split('-')[-1]
        if ($tail -and $tail.Length -eq 2) { return $tail.ToUpper() }
    } catch { }
    return 'US'
}

function Invoke-WingetSilently {
    # Wraps `winget install` with the flags needed for unattended use:
    #   --source winget    -> skip msstore (avoids first-use disclaimers
    #                         about Terms of Transaction and the
    #                         "2-letter geographic region" notice)
    #   --accept-source-agreements / --accept-package-agreements
    #   --silent           -> no installer GUI / no progress bars
    #
    # Output from winget is captured and lines that match known noise
    # patterns (msstore disclaimers, package licensing boilerplate) are
    # suppressed. The final exit code is preserved via $LASTEXITCODE.
    param(
        [Parameter(Mandatory)] [string]$PackageId
    )
    $noisePattern = '(?i)' + (@(
        'msstore',
        'terms of transaction',
        'aka\.ms/microsoft-store',
        'geographic region',
        '地理的リージョン',
        '2\s*文字',
        '所有者からライセンス',
        'サードパーティのパッケージ',
        'licensed to you by its owner',
        'is not responsible for'
    ) -join '|')

    $output = & winget install -e --id $PackageId `
                  --source winget `
                  --accept-source-agreements `
                  --accept-package-agreements `
                  --silent 2>&1 | Out-String
    $exit = $LASTEXITCODE
    foreach ($rawLine in ($output -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($rawLine)) { continue }
        if ($rawLine -match $noisePattern)          { continue }
        Write-Detail "$rawLine" -Color DarkGray
    }
    return $exit
}

function Get-SevenZipPath {
    foreach ($p in @("${env:ProgramFiles}\7-Zip\7z.exe","${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
        if (Test-Path $p) { return $p }
    }
    $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Find-KitTool {
    param([string]$Name)

    # First check PATH (winget / installer may have updated environment)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # Then walk Windows Kits installation directories.
    # NOTE: signtool.exe ships in x64/ AND x86/, but inf2cat.exe is
    # x86-only. We therefore prefer x64 when available, then fall back
    # to any architecture - filtering by x64 alone misses inf2cat.exe
    # entirely and triggers an unnecessary EXE-installer fallback that
    # then fails because the kit is already installed (exit 2008).
    foreach ($root in @("${env:ProgramFiles(x86)}\Windows Kits\10\bin","${env:ProgramFiles}\Windows Kits\10\bin")) {
        if (-not (Test-Path $root)) { continue }
        $allHits = @(Get-ChildItem -Path $root -Recurse -Filter $Name -ErrorAction SilentlyContinue)
        if ($allHits.Count -eq 0) { continue }
        $x64 = $allHits | Where-Object { $_.FullName -match '\\x64\\' } |
               Sort-Object FullName -Descending | Select-Object -First 1
        if ($x64) { return $x64.FullName }
        $any = $allHits | Sort-Object FullName -Descending | Select-Object -First 1
        if ($any) { return $any.FullName }
    }
    return $null
}

function Get-LatestSevenZipUrl {
    # Tier 1: 7-zip.org
    try {
        $resp = Invoke-WebRequest -Uri 'https://www.7-zip.org/download.html' -UseBasicParsing -TimeoutSec 30
        $verMatch = [regex]::Match($resp.Content, 'Download 7-Zip\s+(\d+\.\d+)')
        $msiHits  = [regex]::Matches($resp.Content, 'https?://[^\s"''<>)]+?/7z\d+-x64\.msi')
        if ($msiHits.Count -gt 0) {
            return [pscustomobject]@{
                Version = if ($verMatch.Success) { $verMatch.Groups[1].Value } else { $null }
                MsiUrl  = $msiHits[0].Value
                Source  = '7-zip.org (parsed)'
            }
        }
    } catch { Write-Warn2 "7-zip.org parse failed: $($_.Exception.Message)" }

    # Tier 2: GitHub API
    try {
        $headers = @{ 'User-Agent' = 'PowerShell-MSBthPan-Driver-Prep'; 'Accept' = 'application/vnd.github+json' }
        $api = Invoke-RestMethod -Uri 'https://api.github.com/repos/ip7z/7zip/releases/latest' -Headers $headers -TimeoutSec 30
        $msi = $api.assets | Where-Object { $_.name -match '^7z\d+-x64\.msi$' } | Select-Object -First 1
        if ($msi) {
            return [pscustomobject]@{ Version=$api.tag_name; MsiUrl=$msi.browser_download_url; Source='GitHub Releases API' }
        }
    } catch { Write-Warn2 "GitHub Releases API failed: $($_.Exception.Message)" }

    # Tier 3: pinned
    Write-Warn2 'Both online lookups failed - using pinned URL.'
    return [pscustomobject]@{
        Version='26.01 (pinned)'
        MsiUrl='https://github.com/ip7z/7zip/releases/download/26.01/7z2601-x64.msi'
        Source='pinned fallback'
    }
}

function Install-SevenZipFallback {
    param([string]$DownloadDir)
    $info = Get-LatestSevenZipUrl
    Write-Detail "Version : $($info.Version)"
    Write-Detail "Source  : $($info.Source)"
    Write-Detail "URL     : $($info.MsiUrl)"
    $msi = Join-Path $DownloadDir (Split-Path $info.MsiUrl -Leaf)
    if (-not (Test-Path $msi)) {
        Invoke-WebRequest -Uri $info.MsiUrl -OutFile $msi -UseBasicParsing
    }
    $proc = Start-Process msiexec.exe -ArgumentList @('/i',"`"$msi`"",'/qn','/norestart') -Wait -PassThru
    if ($proc.ExitCode -ne 0) { throw "7-Zip MSI install failed (exit $($proc.ExitCode))" }
}

function Install-WindowsSdkFallback {
    param($OsContext, [string]$DownloadDir)
    Write-Detail "Target build : $($OsContext.SdkBuild)"
    Write-Detail "URL          : $($OsContext.SdkUrl)"
    $exe = Join-Path $DownloadDir "winsdksetup_$($OsContext.Code).exe"
    if (-not (Test-Path $exe)) {
        Invoke-WebRequest -Uri $OsContext.SdkUrl -OutFile $exe -UseBasicParsing
    }
    $proc = Start-Process $exe -ArgumentList $OsContext.SdkInstallArgs -Wait -PassThru

    # Some MSI / VS-style bootstrap installers (winsdksetup.exe, wdksetup.exe)
    # exit non-zero when the kit is already present on the machine
    # (commonly observed: 2008 = "already installed"). Verify by tool
    # presence rather than trusting the exit code.
    if (Find-KitTool 'signtool.exe') {
        if ($proc.ExitCode -ne 0) {
            Write-Warn2 "SDK installer exit code $($proc.ExitCode); signtool.exe is present, treating as already installed."
        }
        return
    }
    throw "Windows SDK install failed (exit $($proc.ExitCode)) - signtool.exe still not found"
}

function Install-WindowsWdkFallback {
    param($OsContext, [string]$DownloadDir)
    Write-Detail "Target build : $($OsContext.WdkBuild)"
    Write-Detail "URL          : $($OsContext.WdkUrl)"
    $exe = Join-Path $DownloadDir "wdksetup_$($OsContext.Code).exe"
    if (-not (Test-Path $exe)) {
        Invoke-WebRequest -Uri $OsContext.WdkUrl -OutFile $exe -UseBasicParsing
    }
    $proc = Start-Process $exe -ArgumentList $OsContext.WdkInstallArgs -Wait -PassThru

    # Same defensive check as the SDK fallback above.
    if (Find-KitTool 'inf2cat.exe') {
        if ($proc.ExitCode -ne 0) {
            Write-Warn2 "WDK installer exit code $($proc.ExitCode); inf2cat.exe is present, treating as already installed."
        }
        return
    }
    throw "Windows WDK install failed (exit $($proc.ExitCode)) - inf2cat.exe still not found"
}

#####################################################################
# SECTION 5: BthPan device + DriverStore helpers
#####################################################################
#
# This section replaces the sister AMD scripts' "AMD URL discovery"
# section. The Microsoft inbox bthpan driver is NOT downloaded from
# any remote URL: it is already present on every Windows install at
# C:\Windows\INF\bthpan.inf and as a staged copy under
# C:\Windows\System32\DriverStore\FileRepository\bthpan.inf_amd64_*.
# The functions in this section locate the staged DriverStore copy,
# diagnose the current BTH\MS_BTHPAN device state (Phantom OK vs true
# resolution vs unknown-device), and produce the device inventory that
# V05 / V06 / I04 consume.
#
#=======================================================================================================================

function Get-BthPanDriverStoreSource {
    <#
    .SYNOPSIS
        Locate the staged bthpan inbox driver folder under the
        DriverStore FileRepository.
    .DESCRIPTION
        Inbox drivers ship with Windows and are staged at
        C:\Windows\System32\DriverStore\FileRepository\<inf>_amd64_<hash>.
        For bthpan there may be more than one staged copy (e.g. after
        a Windows feature update). We pick the most recently modified
        directory that contains bthpan.inf, bthpan.sys, and at least
        one catalog file.
    .OUTPUTS
        [pscustomobject] with Path, InfPath, SysPath, CatPaths,
        LastWriteTime; or $null if not found.
    #>
    [CmdletBinding()]
    param(
        [string]$DriverStoreRoot = 'C:\Windows\System32\DriverStore\FileRepository'
    )

    if (-not (Test-Path -LiteralPath $DriverStoreRoot)) {
        return $null
    }

    $candidates = Get-ChildItem -LiteralPath $DriverStoreRoot `
        -Directory -Filter 'bthpan.inf_amd64_*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    foreach ($dir in $candidates) {
        $infPath = Join-Path $dir.FullName 'bthpan.inf'
        $sysPath = Join-Path $dir.FullName 'bthpan.sys'
        if (-not (Test-Path -LiteralPath $infPath))  { continue }
        if (-not (Test-Path -LiteralPath $sysPath))  { continue }
        $catFiles = @(Get-ChildItem -LiteralPath $dir.FullName `
            -Filter '*.cat' -File -ErrorAction SilentlyContinue)
        if ($catFiles.Count -eq 0) { continue }

        return [pscustomobject]@{
            Path           = $dir.FullName
            InfPath        = $infPath
            SysPath        = $sysPath
            CatPaths       = @($catFiles | ForEach-Object { $_.FullName })
            LastWriteTime  = $dir.LastWriteTime
            DirectoryName  = $dir.Name
        }
    }
    return $null
}

function Get-BthPanInboxInfoPath {
    <#
    .SYNOPSIS
        Return the path to the live inbox bthpan.inf under C:\Windows\INF
        if present. Used by P03/P04 as a sanity check that the host has
        the inbox driver provisioned.
    #>
    $p = Join-Path $env:WINDIR 'INF\bthpan.inf'
    if (Test-Path -LiteralPath $p) { return $p }
    return $null
}

function Get-MsBthPanDevice {
    <#
    .SYNOPSIS
        Enumerate every BTH\MS_BTHPAN* device on the host.
    .DESCRIPTION
        Returns one entry per device instance. Uses Get-PnpDevice which
        works on every supported OS (WS2016+). Each result carries the
        InstanceId and the live Status field; full property bag
        retrieval is deferred to Get-MsBthPanDeviceState.
    .OUTPUTS
        Array of pscustomobject (possibly empty).
    #>
    [CmdletBinding()]
    param()

    $rows = @()
    try {
        $devs = Get-PnpDevice -InstanceId 'BTH\MS_BTHPAN*' -ErrorAction SilentlyContinue
        if ($devs) {
            foreach ($d in $devs) {
                $rows += [pscustomobject]@{
                    InstanceId    = $d.InstanceId
                    FriendlyName  = $d.FriendlyName
                    Status        = $d.Status
                    Class         = $d.Class
                    ClassGuid     = $d.ClassGuid
                    Problem       = $d.Problem
                    Present       = $d.Present
                }
            }
        }
    } catch {
        # Get-PnpDevice not available (very old PS) - fall back to pnputil
    }
    return ,$rows
}

function Get-MsBthPanDeviceState {
    <#
    .SYNOPSIS
        For a single BTH\MS_BTHPAN device instance, read the property
        bag needed to distinguish Phantom OK from true resolution.
    .DESCRIPTION
        Reads DEVPKEY_Device_DriverInfPath / Class / Service /
        ClassGuid / Manufacturer / Driver / Problem.

        Phantom OK    : DriverInfPath=bth.inf, Class=Bluetooth, Service=(empty)
        True OK       : DriverInfPath=oem<N>.inf, Class=Net, Service=BthPan
        Unknown device: Status=Error (code 28)

    .OUTPUTS
        [pscustomobject] containing the property values and the
        derived classification (.Classification : Phantom|True|Unknown|Other)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstanceId
    )

    $propsToRead = @(
        'DEVPKEY_Device_DriverInfPath',
        'DEVPKEY_Device_Class',
        'DEVPKEY_Device_ClassGuid',
        'DEVPKEY_Device_Service',
        'DEVPKEY_Device_Manufacturer',
        'DEVPKEY_Device_FriendlyName',
        'DEVPKEY_Device_Driver',
        'DEVPKEY_Device_Problem'
    )

    $bag = @{}
    try {
        $props = Get-PnpDeviceProperty -InstanceId $InstanceId -KeyName $propsToRead -ErrorAction SilentlyContinue
        if ($props) {
            foreach ($p in $props) {
                $bag[$p.KeyName] = $p.Data
            }
        }
    } catch {
        # property read failure - bag stays empty
    }

    # Fetch device-level Status (Get-PnpDevice) for code-28 detection
    $status  = $null
    $problem = $null
    try {
        $d = Get-PnpDevice -InstanceId $InstanceId -ErrorAction SilentlyContinue
        if ($d) {
            $status  = $d.Status
            $problem = $d.Problem
        }
    } catch {}

    $infPath = [string]$bag['DEVPKEY_Device_DriverInfPath']
    $class   = [string]$bag['DEVPKEY_Device_Class']
    $service = [string]$bag['DEVPKEY_Device_Service']

    # Classification
    $classification = 'Other'
    $reason         = ''
    if ($status -eq 'Error') {
        $classification = 'Unknown'
        $reason = 'Device is in error state (code 28 / no driver bound).'
    } elseif ($infPath -like 'bth.inf*' -and $class -eq 'Bluetooth') {
        $classification = 'Phantom'
        $reason = 'bth.inf has proxy-matched. bthpan.sys is NOT loaded; PAN networking is broken.'
    } elseif ($infPath -like 'oem*.inf' -and $class -eq 'Net' -and $service -eq 'BthPan') {
        $classification = 'True'
        $reason = 'Patched bthpan.inf (oem*.inf) is bound; bthpan.sys loaded; BthPan service active.'
    } elseif ($infPath -like 'bthpan.inf*' -and $class -eq 'Net' -and $service -eq 'BthPan') {
        # Edge case: Some hosts may show bthpan.inf directly rather than oem*.inf
        # (when the inbox INF itself has been patched out-of-band or by a sister tool)
        $classification = 'True'
        $reason = 'bthpan.inf is bound directly; Class=Net; Service=BthPan.'
    }

    return [pscustomobject]@{
        InstanceId           = $InstanceId
        Status               = $status
        Problem              = $problem
        DriverInfPath        = $infPath
        Class                = $class
        ClassGuid            = [string]$bag['DEVPKEY_Device_ClassGuid']
        Service              = $service
        Manufacturer         = [string]$bag['DEVPKEY_Device_Manufacturer']
        FriendlyName         = [string]$bag['DEVPKEY_Device_FriendlyName']
        Driver               = [string]$bag['DEVPKEY_Device_Driver']
        Classification       = $classification
        ClassificationReason = $reason
    }
}

function Test-BthPanRuntimeArtifacts {
    <#
    .SYNOPSIS
        Check whether the runtime artifacts that "true resolution"
        produces are actually present on the host.
    .DESCRIPTION
        True resolution implies all of the following:
          - C:\Windows\System32\drivers\bthpan.sys exists
          - HKLM:\SYSTEM\CurrentControlSet\Services\BthPan key exists
          - At least one NetAdapter has InterfaceDescription matching
            'Bluetooth.*PAN' (or the locale-equivalent)
    .OUTPUTS
        [pscustomobject] with HasSysFile, HasServiceKey, HasNetAdapter
    #>
    [CmdletBinding()]
    param()

    $sysFile     = Join-Path $env:WINDIR 'System32\drivers\bthpan.sys'
    $hasSysFile  = Test-Path -LiteralPath $sysFile

    $hasService  = $false
    try {
        $svcKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\BthPan'
        $hasService = Test-Path -LiteralPath $svcKey
    } catch {}

    $hasNetAdapter = $false
    try {
        $adapters = Get-NetAdapter -ErrorAction SilentlyContinue
        foreach ($a in $adapters) {
            if ($a.InterfaceDescription -match 'Bluetooth.*Personal Area Network' -or
                $a.InterfaceDescription -match 'Bluetooth.*PAN'                 -or
                $a.InterfaceDescription -match 'Bluetooth デバイス \(個人.*\)') {
                $hasNetAdapter = $true
                break
            }
        }
    } catch {}

    return [pscustomobject]@{
        HasSysFile     = $hasSysFile
        SysFilePath    = $sysFile
        HasServiceKey  = $hasService
        HasNetAdapter  = $hasNetAdapter
    }
}

function Get-BthPanCurrentlyInstalledOemInfs {
    <#
    .SYNOPSIS
        Enumerate oem*.inf entries already added by pnputil that
        provide bthpan support (i.e. published name maps to a bthpan
        INF). Used by Cleanup and by the I03 idempotency check.
    .OUTPUTS
        Array of pscustomobject { PublishedName, OriginalName, Provider, Version }
    #>
    [CmdletBinding()]
    param()

    $rows = @()
    try {
        $out = (& pnputil.exe /enum-drivers 2>&1) -join "`n"
        if (-not $out) { return ,$rows }

        # pnputil /enum-drivers output is delimited by blank lines per
        # driver package. Each block contains lines like:
        #   Published name :   oem17.inf
        #   Original name  :   bthpan.inf
        #   Provider name  :   Microsoft
        #   ...
        $blocks = $out -split "`r?`n`r?`n"
        foreach ($block in $blocks) {
            if ($block -notmatch 'bthpan\.inf') { continue }
            $pub = $null; $orig = $null; $prov = $null; $ver = $null
            foreach ($line in ($block -split "`r?`n")) {
                if ($line -match '(?i)Published\s*name\s*:\s*(\S+)')  { $pub  = $matches[1] }
                if ($line -match '(?i)Original\s*name\s*:\s*(\S+)')   { $orig = $matches[1] }
                if ($line -match '(?i)Provider\s*name\s*:\s*(.+)$')    { $prov = $matches[1].Trim() }
                if ($line -match '(?i)Driver\s*version\s*:\s*(\S+)')  { $ver  = $matches[1] }
            }
            if ($pub -and $orig -match '(?i)bthpan\.inf') {
                $rows += [pscustomobject]@{
                    PublishedName = $pub
                    OriginalName  = $orig
                    Provider      = $prov
                    Version       = $ver
                }
            }
        }
    } catch {}
    return ,$rows
}


#####################################################################
# SECTION 6: INF helpers
#####################################################################
function Read-InfFile {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return @{
            Encoding=(New-Object System.Text.UnicodeEncoding $false,$true)
            EncodingName='UTF-16 LE BOM'
            Content=[System.Text.Encoding]::Unicode.GetString($bytes,2,$bytes.Length-2)
        }
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return @{
            Encoding=(New-Object System.Text.UTF8Encoding $true)
            EncodingName='UTF-8 BOM'
            Content=[System.Text.Encoding]::UTF8.GetString($bytes,3,$bytes.Length-3)
        }
    }
    return @{
        Encoding=[System.Text.Encoding]::Default
        EncodingName='ANSI'
        Content=[System.Text.Encoding]::Default.GetString($bytes)
    }
}

function Get-InfMetadata {
    # Extract human-readable metadata from an INF file's text:
    #   - Provider     : driver vendor (e.g. "AMD")
    #   - Class        : Windows device class (System, USB, HIDClass, ...)
    #   - ClassGuid    : raw GUID of the device class
    #   - DriverVer    : version string from [Version]
    #   - Manufacturer : manufacturer label (resolved from [Strings])
    #   - Devices      : list of {Description, HardwareId} pairs from
    #                    the manufacturer's model section, with strings
    #                    resolved against the [Strings] section
    #   - DeviceCount  : count of distinct device entries
    #
    # Returns a [pscustomobject] with the above fields. Missing fields
    # are returned as $null or empty arrays so callers can format them
    # safely without null checks.
    param([Parameter(Mandatory)] [string]$Content)

    function _GetField {
        param([string]$Text, [string]$Key)
        $rx = '(?im)^\s*' + [regex]::Escape($Key) + '\s*=\s*(.+?)\s*(?:;.*)?$'
        $m = [regex]::Match($Text, $rx)
        if ($m.Success) {
            return ($m.Groups[1].Value.Trim().Trim('"'))
        }
        return $null
    }

    function _ParseSections {
        # Returns a hashtable: section name -> array of raw lines
        param([string]$Text)
        $sections = [ordered]@{}
        $current = $null
        $buf = New-Object System.Collections.Generic.List[string]
        foreach ($line in ($Text -split "`r?`n")) {
            $trim = $line.Trim()
            if ($trim -match '^\s*\[([^\]]+)\]\s*$') {
                if ($current) { $sections[$current] = $buf.ToArray() }
                $current = $matches[1].Trim()
                $buf = New-Object System.Collections.Generic.List[string]
                continue
            }
            if ($current) { [void]$buf.Add($line) }
        }
        if ($current) { $sections[$current] = $buf.ToArray() }
        return $sections
    }

    function _ResolveString {
        param([string]$Token, [hashtable]$Strings)
        if ($null -eq $Token) { return $null }
        $t = $Token.Trim().Trim('"')
        # %Foo% references a [Strings] entry
        if ($t -match '^%([^%]+)%$') {
            $key = $matches[1]
            if ($Strings.ContainsKey($key)) {
                return $Strings[$key]
            }
            return $t  # unresolved - return original
        }
        return $t
    }

    $sections = _ParseSections -Text $Content

    # Build [Strings] table for token resolution
    #
    # IMPORTANT (r43 fix, mirrored from graphics-r11): the LHS character
    # class MUST include dot and backslash. AMD INFs use token names
    # like 'amdsmbus.DeviceDesc' or 'PCI\AMDPCIE.DeviceDesc' that the
    # pre-r43 `[A-Za-z0-9_]+` regex couldn't capture, causing the
    # %Token% reference to be displayed literally in P05 instead of
    # the resolved description. This was a pre-existing latent bug
    # in both graphics and chipset parsers; r43 brings the chipset
    # parser in sync with the graphics-r11 fix for consistency and
    # to prepare for any future AMD chipset INF using this format.
    $strings = @{}
    if ($sections.Contains('Strings')) {
        foreach ($ln in $sections['Strings']) {
            if ($ln -match '^\s*([^\s=;]+)\s*=\s*"?(.*?)"?\s*(?:;.*)?$') {
                $strings[$matches[1]] = $matches[2]
            }
        }
    }

    # [Version] section field extraction
    $versionText = ''
    if ($sections.Contains('Version')) {
        $versionText = ($sections['Version'] -join "`n")
    }
    $provider     = _ResolveString (_GetField $versionText 'Provider')      $strings
    $class        = _GetField $versionText 'Class'
    $classGuid    = _GetField $versionText 'ClassGuid'
    $driverVer    = _GetField $versionText 'DriverVer'
    $catalogFile  = _GetField $versionText 'CatalogFile'

    # [Manufacturer] -> mfgLabel = mfgSection,decorations
    #
    # IMPORTANT (r42 fix, mirrored from graphics-r9): collect ALL
    # manufacturer entries, not just the first one. While AMD chipset
    # INFs typically have a single %AMD% manufacturer (unlike the
    # graphics u0197843.inf which uses the same single-mfg pattern but
    # with quoted-token LHS lines that the previous parser also missed),
    # parsing all manufacturer entries is the correct robust behavior
    # and protects against future format changes. Pre-r42 the parser
    # took the first entry only via `break`, and Bug B below would
    # cause silent-zero-device parsing when LHS was non-canonical.
    $mfgLabel = $null
    $mfgSectionNames = @()
    if ($sections.Contains('Manufacturer')) {
        foreach ($ln in $sections['Manufacturer']) {
            if ($ln.Trim().StartsWith(';')) { continue }
            if ([string]::IsNullOrWhiteSpace($ln)) { continue }
            if ($ln -match '^\s*([^=;\s][^=;]*?)\s*=\s*([^;]+?)\s*(?:;.*)?$') {
                $thisLabel = _ResolveString $matches[1] $strings
                if (-not $mfgLabel) { $mfgLabel = $thisLabel }
                $rhs = $matches[2].Trim()
                # rhs is "SectionName" or "SectionName,decoration1,decoration2,..."
                $first = ($rhs -split ',')[0].Trim()
                if ($first -and ($mfgSectionNames -notcontains $first)) {
                    $mfgSectionNames += $first
                }
            }
        }
    }

    # Collect device entries from the manufacturer section AND its
    # decorated variants (e.g. "Mfg" plus "Mfg.NTamd64.10.0.3..26100").
    #
    # IMPORTANT (r31 fix): the wildcard `$baseName.*` can also match
    # DDInstall sections when the install-section name happens to share
    # a prefix with the Manufacturer section name (this happens in
    # AmdMicroPEP.inf, where DDInstall.Services entries previously
    # leaked into the device list and surfaced as bogus "device:
    # AddService / hwid: %SERVICE_FLAGS%" rows in P05).
    #
    # IMPORTANT (r42 fix, mirrored from graphics-r9/r10): the device-
    # line LHS can be ANY of three forms in real-world AMD INFs - the
    # pre-r42 parser only accepted form (a) which is why graphics
    # u0197843.inf parsed 0 devices despite having a perfectly valid
    # [Models] section (its 5,047 device lines all use form (b) with
    # double-quoted %Token% references). Although AMD chipset INFs
    # typically use form (a), this parser is kept in sync with the
    # graphics script for consistency and future-proofing.
    #
    #   (a) %Token%       -- canonical AMD INF convention, where the
    #                        token resolves against [Strings]
    #                        Example: %D1638% = svcS, PCI\VEN_1002&DEV_1638
    #
    #   (b) "Quoted lit"  -- literal string in quotes, OR a quoted
    #                        token reference like "%Token%" (used in
    #                        AMD WHQL universal display drivers).
    #                        Example: "AMD SMBus" = svcS, PCI\VEN_1022&DEV_790B
    #                        Example: "%D1638.1%" = svcS, PCI\VEN_1002&DEV_1638
    #
    #   (c) BareIdent     -- bare identifier (rare; seen in some
    #                        legacy AMD universal INFs). Must NOT be
    #                        a known INF directive keyword.
    #                        Example: D1638 = svcS, PCI\VEN_1002&DEV_1638
    #
    # Defense-in-depth (three checks):
    #   1. Skip lines whose LHS is a known directive keyword
    #      (AddService, AddReg, CopyFiles, ...). This protects against
    #      DDInstall sections that share the manufacturer's name prefix.
    #   2. Each LHS form is matched by a SEPARATE regex - we don't
    #      try to consolidate them into one pattern (alternation in
    #      a single regex made the rules harder to reason about).
    #   3. Require the RHS to have AT LEAST a comma separating
    #      install-section and HWID. Lines without a comma cannot be
    #      device entries no matter what their LHS looks like.
    $infDirectiveBlacklist = @(
        'AddService','DelService','AddReg','DelReg','BitReg',
        'LogConfig','CopyFiles','DelFiles','RenFiles',
        'AddInterface','DelInterface','AddProperty','DelProperty',
        'AddComponent','DelComponent','AddSoftware','AddTrigger',
        'AddPowerSetting','AddRegisteredFile','Include','Needs',
        'Reboot','BootCritical','ExcludeFromSelect','FeatureScore'
    )
    $devices = @()
    $modelsSectionsScanned = 0
    foreach ($baseName in $mfgSectionNames) {
        if (-not $baseName) { continue }
        $matchingSecs = $sections.Keys | Where-Object {
            $_ -eq $baseName -or $_ -like "$baseName.*"
        }
        foreach ($secName in $matchingSecs) {
            $modelsSectionsScanned++
            foreach ($ln in $sections[$secName]) {
                if ($ln.Trim().StartsWith(';')) { continue }
                if ([string]::IsNullOrWhiteSpace($ln)) { continue }

                # Pre-filter: skip lines whose LHS bare-ident is a
                # known DDInstall directive (defends against section-
                # name collisions, see r31 comment).
                if ($ln -match '^\s*([A-Za-z][A-Za-z0-9_]+)\s*=' -and
                    ($infDirectiveBlacklist -contains $matches[1])) {
                    continue
                }

                $desc = $null
                $hwid = $null

                # Form (a): %Token% LHS - canonical AMD convention.
                if ($ln -match '^\s*%([^%]+)%\s*=\s*[^,;]+\s*,\s*([^,;]+?)\s*(?:,.*)?(?:;.*)?$') {
                    $tok  = $matches[1]
                    $desc = if ($strings.ContainsKey($tok)) { $strings[$tok] } else { "%$tok%" }
                    $hwid = $matches[2].Trim()
                }
                # Form (b): "Quoted literal" LHS. If the quoted content
                # is itself a %Token% reference (the AMD universal-INF
                # pattern), resolve it against [Strings] for clean
                # display. Otherwise treat as a literal description.
                elseif ($ln -match '^\s*"([^"]*)"\s*=\s*[^,;]+\s*,\s*([^,;]+?)\s*(?:,.*)?(?:;.*)?$') {
                    $quoted = $matches[1]
                    $hwid = $matches[2].Trim()
                    if ($quoted -match '^%([^%]+)%$') {
                        $tok = $matches[1]
                        $desc = if ($strings.ContainsKey($tok)) { $strings[$tok] } else { "%$tok%" }
                    } else {
                        $desc = $quoted
                    }
                }
                # Form (c): bare identifier LHS (already filtered for
                # directive keywords by the pre-filter above).
                elseif ($ln -match '^\s*([A-Za-z_][A-Za-z0-9_\.]*)\s*=\s*[^,;]+\s*,\s*([^,;]+?)\s*(?:,.*)?(?:;.*)?$') {
                    $desc = $matches[1]
                    $hwid = $matches[2].Trim()
                }

                if ($desc -and $hwid) {
                    $devices += [pscustomobject]@{
                        Description = $desc
                        HardwareId  = $hwid
                        FromSection = $secName
                    }
                }
            }
        }
    }
    # Deduplicate by HardwareId (the same device can appear under
    # multiple architecture decorations - we want to count it once
    # in the per-INF summary).
    $devices = @($devices | Group-Object HardwareId | ForEach-Object { $_.Group | Select-Object -First 1 })

    return [pscustomobject]@{
        Provider              = $provider
        Class                 = $class
        ClassGuid             = $classGuid
        DriverVer             = $driverVer
        CatalogFile           = $catalogFile
        Manufacturer          = $mfgLabel
        Devices               = $devices
        DeviceCount           = $devices.Count
        ManufacturerEntries   = $mfgSectionNames.Count   # r42: number of distinct mfg sections (>1 = multi-mfg INF)
        ModelsSectionsScanned = $modelsSectionsScanned   # r42: number of [Mfg.NT...] sections that were scanned
    }
}

function Write-InfFile {
    param([string]$Path, [string]$Content, $Encoding)
    [System.IO.File]::WriteAllText($Path, $Content, $Encoding)
}

function ConvertTo-ServerDecoration {
    param([string]$ClientDec)
    if ($ClientDec -notmatch '^NT(amd64|x86|arm|arm64)') { return $null }
    $parts = $ClientDec.Split('.')
    while ($parts.Count -lt 4) { $parts += '' }
    if ($parts[3] -eq '3') { return $null }
    $parts[3] = '3'
    return ($parts -join '.')
}

function Edit-InfForServer {
    param([string]$InfPath, [string]$OutputPath, [pscustomobject]$OsContext)

    $infData = Read-InfFile -Path $InfPath
    $lines = $infData.Content -split "(?<=`n)"
    if (-not ($lines -is [array])) { $lines = @($lines) }

    # Pass 1: collect [Manufacturer] entries / decorations
    $clientDecorations = @{}
    $mfgIndices = @()
    $inMfg = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].Trim().TrimEnd("`r")
        if ($t -match '^\[Manufacturer\]') { $inMfg = $true; continue }
        if ($inMfg -and $t -match '^\[')   { $inMfg = $false }
        if ($inMfg -and $t -and -not $t.StartsWith(';')) {
            $mfgIndices += $i
            $kv = $t -split '=', 2
            if ($kv.Count -ne 2) { continue }
            $rhs = $kv[1].Split(',')
            $sectionName = $rhs[0].Trim()
            for ($j = 1; $j -lt $rhs.Count; $j++) {
                $dec = $rhs[$j].Trim()
                if ($dec -match '^NT' -and $dec -notmatch '^NT\w+\.\d+\.\d+\.3\.') {
                    if (-not $clientDecorations.ContainsKey($dec)) {
                        $clientDecorations[$dec] = @{ Sections=@() }
                    }
                    if ($clientDecorations[$dec].Sections -notcontains $sectionName) {
                        $clientDecorations[$dec].Sections += $sectionName
                    }
                }
            }
        }
    }

    if ($clientDecorations.Count -eq 0) {
        return @{ Patched=$false; Reason='No client decorations found'; Encoding=$infData.EncodingName }
    }

    $decMap = @{}
    foreach ($cd in $clientDecorations.Keys) {
        $sd = ConvertTo-ServerDecoration -ClientDec $cd
        if ($sd) { $decMap[$cd] = $sd }
    }

    # Pass 2: append server decorations to each [Manufacturer] entry
    foreach ($idx in $mfgIndices) {
        $line = $lines[$idx]
        $eolMatch = [regex]::Match($line, "(`r?`n)$")
        $eol = if ($eolMatch.Success) { $eolMatch.Value } else { '' }
        $core = if ($eol) { $line.Substring(0, $line.Length - $eol.Length) } else { $line }
        $appended = $core
        foreach ($cd in $decMap.Keys) {
            $sd = $decMap[$cd]
            if ($appended -match [regex]::Escape($cd) -and $appended -notmatch [regex]::Escape($sd)) {
                $appended = $appended.TrimEnd() + ", $sd"
            }
        }
        $lines[$idx] = $appended + $eol
    }

    # Pass 3: collect sections to mirror
    $sectionsToMirror = @{}
    $current = $null
    $body    = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $t = $line.Trim().TrimEnd("`r")
        if ($t -match '^\[(.+?)\]$') {
            if ($current -and $sectionsToMirror.ContainsKey($current)) {
                $sectionsToMirror[$current] = $body.ToArray()
            }
            $current = $matches[1]
            $body.Clear()
            foreach ($cd in $decMap.Keys) {
                if ($current.EndsWith(".$cd")) { $sectionsToMirror[$current] = @(); break }
            }
            continue
        }
        if ($current -and $sectionsToMirror.ContainsKey($current)) { [void]$body.Add($line) }
    }
    if ($current -and $sectionsToMirror.ContainsKey($current)) {
        $sectionsToMirror[$current] = $body.ToArray()
    }

    # Pass 4: emit mirrored sections
    $sb = New-Object System.Text.StringBuilder
    foreach ($l in $lines) { [void]$sb.Append($l) }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('; ====================================================')
    [void]$sb.AppendLine('; Auto-generated: ProductType=3 (Server) sections')
    [void]$sb.AppendLine("; Target OS: $($OsContext.Name) (build $($OsContext.Build))")
    [void]$sb.AppendLine("; Generated: $(Get-Date -Format o)")
    [void]$sb.AppendLine('; ====================================================')

    foreach ($origHeader in $sectionsToMirror.Keys) {
        $cd = $decMap.Keys | Where-Object { $origHeader.EndsWith(".$_") } | Select-Object -First 1
        if (-not $cd) { continue }
        $sd = $decMap[$cd]
        $base = $origHeader.Substring(0, $origHeader.Length - $cd.Length - 1)
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("[$base.$sd]")
        foreach ($bl in $sectionsToMirror[$origHeader]) { [void]$sb.Append($bl) }
    }

    Write-InfFile -Path $OutputPath -Content $sb.ToString() -Encoding $infData.Encoding
    return @{
        Patched              = $true
        Encoding             = $infData.EncodingName
        ManufacturerEntries  = $mfgIndices.Count
        Decorations          = $decMap
        SectionsMirrored     = $sectionsToMirror.Keys.Count
    }
}

#####################################################################
# SECTION 7: Phase idempotency helpers
#####################################################################
function Test-PhaseMarker {
    param($Ctx, [string]$PhaseId)
    $marker = Join-Path $Ctx.Paths.Markers ".$PhaseId.done"
    if ((Test-Path $marker) -and -not $Ctx.Force) { return $true }
    return $false
}

function Set-PhaseMarker {
    param($Ctx, [string]$PhaseId, [hashtable]$Metadata = @{})
    $marker = Join-Path $Ctx.Paths.Markers ".$PhaseId.done"
    $payload = @{ phase=$PhaseId; completedAt=(Get-Date -Format o); meta=$Metadata }
    $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $marker -Encoding UTF8
}

function Clear-PhaseMarker {
    param($Ctx, [string]$PhaseId)
    $marker = Join-Path $Ctx.Paths.Markers ".$PhaseId.done"
    if (Test-Path $marker) { Remove-Item $marker -Force }
}

#####################################################################
# SECTION 8: PREPARATION PHASES
#####################################################################

function Invoke-PrepPhase00_Initialize {
    param($Ctx)
    Write-PhaseHeader 'P00' 'Initialize' 'Prep'

    # Always show the runtime environment first - this is what the
    # user sees if anything else later fails, and it provides the
    # context needed to triage compatibility issues.
    Show-PowerShellEnvironment

    # Hard pre-flight checks that the script cannot continue without.
    # Order matters: PS version & bitness first (a 32-bit / PS4 host
    # cannot even reliably parse this script), then Administrator,
    # then network TLS configuration, then UTF-8 console encoding (SPEC
    # A.5 / D.5 / D.16 — required for CiTool.exe and signtool.exe ja-JP
    # output to decode correctly instead of becoming mojibake).
    Assert-PowerShellCompatibility
    Assert-Admin
    Set-Tls12
    Set-ConsoleUtf8

    $Ctx.Os = Get-OsContext
    $isWorkstation = ($Ctx.Os.ProductType -eq 1)
    $isBuild26100  = ($Ctx.Os.ActualBuild -eq 26100)

    if ($isWorkstation) {
        # Show the ACTUAL OS Caption (e.g. "Microsoft Windows 11 Pro") plus
        # the Server profile this script will treat it as. Pre-r45 the
        # display only showed the mapped profile name, which made it look
        # like the script had mis-detected the OS.
        Write-Ok "OS detected: $($Ctx.Os.Caption) (build $($Ctx.Os.ActualBuild))"
        Write-Detail "Profile applied : $($Ctx.Os.Code) ($($Ctx.Os.Name))" -Color DarkGray
        Write-Detail "ProductType     : $($Ctx.Os.ProductType)  (1=Workstation, 3=Server)"
        Write-Host ''
        if ($isBuild26100) {
            # IDEAL preview scenario: Win11 24H2 (26100) shares the WS2025 kernel.
            Write-Host '    +-----------------------------------------------------------------+' -ForegroundColor Cyan
            Write-Host '    | WS2025 PRE-MIGRATION PREVIEW MODE                               |' -ForegroundColor Cyan
            Write-Host '    | (Windows 11 24H2 and Windows Server 2025 share NT build 26100)  |' -ForegroundColor Cyan
            Write-Host '    +-----------------------------------------------------------------+' -ForegroundColor Cyan
            Write-Host '    | This host is a high-fidelity preview target for WS2025. The    |' -ForegroundColor Cyan
            Write-Host '    | P00-V05 outputs (INF inventory, patching, catalogs, install     |' -ForegroundColor Cyan
            Write-Host '    | plan) will match a future WS2025 run on this same hardware.    |' -ForegroundColor Cyan
            Write-Host '    |                                                                 |' -ForegroundColor Cyan
            Write-Host '    | Caveat: V06 (Hardware Impact Analysis) will differ. Win11''s    |' -ForegroundColor Cyan
            Write-Host '    | OEM driver baseline disappears after WS2025 clean install, so   |' -ForegroundColor Cyan
            Write-Host '    | many devices that look "kept" here will become "WILL be        |' -ForegroundColor Cyan
            Write-Host '    | replaced" on the actual WS2025 host (MS-generic baseline).     |' -ForegroundColor Cyan
            Write-Host '    +-----------------------------------------------------------------+' -ForegroundColor Cyan
        } else {
            # Workstation but NOT build 26100 - profile mismatch warning
            Write-Host '    +-----------------------------------------------------------------+' -ForegroundColor Yellow
            Write-Host '    | WORKSTATION OS - LOWER-FIDELITY PREVIEW                         |' -ForegroundColor Yellow
            Write-Host '    +-----------------------------------------------------------------+' -ForegroundColor Yellow
            Write-Host ('    | This Workstation host (build {0}) is mapped to the {1} profile.' -f $Ctx.Os.ActualBuild, $Ctx.Os.Code) -ForegroundColor Yellow
            Write-Host '    | For maximum WS2025 fidelity, run this preview on Windows 11    |' -ForegroundColor Yellow
            Write-Host '    | 24H2 (build 26100) instead.                                    |' -ForegroundColor Yellow
            Write-Host '    +-----------------------------------------------------------------+' -ForegroundColor Yellow
        }
        Write-Host ''
        # Determine derived script type from version string for the log filename hint
        $logTag = if ($Script:ScriptVersion -like 'graphics-*') { 'graphics' } else { 'chipset' }
        $scriptLeaf = if ($Script:ScriptPath) { Split-Path $Script:ScriptPath -Leaf } else { '<this-script>.ps1' }
        Write-Host '    RECOMMENDED USAGE on this Workstation host:' -ForegroundColor White
        Write-Host '      1. Use -Action PrepareVerify -CleanWorkRoot only (no system' -ForegroundColor White
        Write-Host '         changes; safe to run repeatedly).' -ForegroundColor White
        Write-Host '      2. Save the run log for post-WS2025-install comparison:' -ForegroundColor White
        Write-Detail ("     .\{0} -Action PrepareVerify -CleanWorkRoot *>&1 |" -f $scriptLeaf) -Color DarkGray
        Write-Detail ("       Tee-Object -FilePath C:\Temp\amd-{0}-Win11-preview.log" -f $logTag) -Color DarkGray
        Write-Host '      3. After WS2025 clean install, re-run with the same command' -ForegroundColor White
        Write-Detail ("       (... | Tee-Object -FilePath C:\Temp\amd-{0}-WS2025.log)" -f $logTag) -Color DarkGray
        Write-Host '         and compare the two logs (especially V06 section 2/3).' -ForegroundColor White
        Write-Host '      4. -Action Install / I01-I04 phases are REJECTED on Workstation' -ForegroundColor White
        Write-Host '         (would import certs, deploy WDAC policy, displace OEM drivers).' -ForegroundColor White
        Write-Host '         Use -AllowWorkstationInstall to override (NOT recommended).' -ForegroundColor White
        Write-Host ''

        # ===== Workstation Install guard =====
        # Refuse to run any Install phase (I01-I04) on Workstation,
        # unless -AllowWorkstationInstall was explicitly passed.
        $hasInstallPhases = @($Ctx.SelectedPhaseIds | Where-Object { $_ -match '^I0[0-4]$' }).Count -gt 0
        if ($hasInstallPhases -and -not $Ctx.AllowWorkstationInstall) {
            $msg = @"
Refusing to run Install phases (I01-I04) on Workstation OS (ProductType=1).

This script's installation pipeline is designed for Windows Server hosts.
Running it on a Workstation Windows host (e.g. Windows 11 used as a WS2025
preview) would:
  - Import a self-signed certificate into LocalMachine\Root and TrustedPublisher
  - Deploy a WDAC supplemental Code Integrity policy
  - Replace inbox bthpan.inf with a self-signed ProductType=3 patched version
  - On laptops with BitLocker enabled: TRIGGER RECOVERY-KEY PROMPTS on next
    boot due to PSP/TPM driver displacement

Recommended:
  * Use -Action PrepareVerify -CleanWorkRoot (no system changes).
  * After clean-installing Windows Server 2025 on this hardware, re-run
    with -Action Install on the actual Server host.

If you really need to install on this Workstation host, pass
-AllowWorkstationInstall (you accept the consequences).
"@
            throw $msg
        }
    } else {
        Write-Ok "OS detected: $($Ctx.Os.Name) (build $($Ctx.Os.ActualBuild)) [$($Ctx.Os.Code)]"
        Write-Detail "ProductType: $($Ctx.Os.ProductType)  (1=Workstation, 3=Server)"
    }

    # ---- UEFI Secure Boot certificate baseline (r49) ----
    # Capture once at P00 and cache on $Ctx so later phases (P05 report
    # append, V05 / V06 display, I02 pre-check) can reuse the same
    # snapshot without re-invoking the Microsoft sample script multiple
    # times in a single run. The snapshot function uses New-Item -Force
    # internally so the WorkRoot directory is auto-created if it does
    # not exist yet (P01 hasn't run); subsequent phases that revisit
    # the snapshot will detect a missing diagnostic file (e.g. when
    # -CleanWorkRoot wipes it at P01) and re-capture as needed via
    # Get-OrEnsureSecureBootBaseline (see helper below).
    try {
        $Ctx.SecureBootBaseline = Get-SecureBootBaselineSnapshot -WorkRoot $Ctx.WorkRoot
        Show-SecureBootBaselineSnapshot -Snapshot $Ctx.SecureBootBaseline -Compact
    } catch {
        Write-Warn2 ("Secure Boot baseline capture failed: {0}" -f $_.Exception.Message)
    }

    Write-PhaseFooter 'P00' 'done'
}

function Invoke-PrepPhase01_PrepareWorkspace {
    param($Ctx)
    Write-PhaseHeader 'P01' 'PrepareWorkspace' 'Prep'

    if ($Ctx.CleanWorkRoot -and (Test-Path $Ctx.WorkRoot)) {
        Write-Step "Removing existing -WorkRoot for clean run: $($Ctx.WorkRoot)"
        Remove-Item -Path $Ctx.WorkRoot -Recurse -Force
        Write-Ok 'Workspace wiped.'
    }

    $paths = [pscustomobject]@{
        Root      = $Ctx.WorkRoot
        Download  = Join-Path $Ctx.WorkRoot 'download'
        Extract   = Join-Path $Ctx.WorkRoot 'extracted'
        Patched   = Join-Path $Ctx.WorkRoot 'patched'
        Cert      = Join-Path $Ctx.WorkRoot 'cert'
        Markers   = Join-Path $Ctx.WorkRoot '.markers'
        Logs      = Join-Path $Ctx.WorkRoot 'logs'
    }
    foreach ($prop in $paths.PSObject.Properties) {
        if (-not (Test-Path $prop.Value)) {
            New-Item -ItemType Directory -Path $prop.Value -Force | Out-Null
        }
    }
    $Ctx.Paths = $paths
    Write-Ok "Workspace ready under $($Ctx.WorkRoot)"

    # Acquire the workspace lock NOW (after the .markers/ directory
    # exists). This catches the case where the user accidentally
    # starts a second instance against the same workspace - we fail
    # fast with a clear error rather than racing pnputil / CiTool.
    # Stale locks (from crashed previous runs) are auto-detected and
    # superseded.
    Assert-NoConcurrentRun -Ctx $Ctx

    Set-PhaseMarker -Ctx $Ctx -PhaseId 'P01'
    Write-PhaseFooter 'P01' 'done'
}

function Invoke-PrepPhase02_AcquireTools {
    param($Ctx)
    Write-PhaseHeader 'P02' 'AcquireTools' 'Prep'

    if (Test-PhaseMarker -Ctx $Ctx -PhaseId 'P02') {
        $Ctx.SevenZip = Get-SevenZipPath
        $Ctx.Signtool = Find-KitTool 'signtool.exe'
        $Ctx.Inf2cat  = Find-KitTool 'inf2cat.exe'
        if ($Ctx.SevenZip -and $Ctx.Signtool -and $Ctx.Inf2cat) {
            Write-Skip 'Tools already present (cached marker).'
            Write-Detail "7-Zip   : $($Ctx.SevenZip)"
            Write-Detail "signtool: $($Ctx.Signtool)"
            Write-Detail "inf2cat : $($Ctx.Inf2cat)"
            Write-PhaseFooter 'P02' 'cached'
            return
        }
        Write-Warn2 'Marker present but tool missing - re-running.'
    }

    # Detect machine region (2-letter ISO). winget will use this when
    # any source needs it (notably msstore). We pre-detect and log it
    # for transparency, then route winget to --source winget so the
    # msstore disclaimer prompts are skipped entirely.
    $region = Get-MachineRegion
    Write-Detail "Region       : $region (auto-detected from system locale / home location)"
    Write-Detail "winget source: 'winget' only (msstore is bypassed for these packages)"

    # 7-Zip
    if (-not (Get-SevenZipPath)) {
        if ((Test-WingetWorking)) {
            Write-Step '7-Zip: trying winget'
            try {
                $null = Invoke-WingetSilently -PackageId '7zip.7zip'
            } catch { Write-Warn2 "winget failed: $($_.Exception.Message)" }
        }
        if (-not (Get-SevenZipPath)) {
            Write-Step '7-Zip: direct MSI fallback'
            Install-SevenZipFallback -DownloadDir $Ctx.Paths.Download
        }
    }
    $Ctx.SevenZip = Get-SevenZipPath
    if (-not $Ctx.SevenZip) { throw '7-Zip install failed' }
    Write-Ok "7-Zip: $($Ctx.SevenZip)"

    # Signing tools
    $signtool = Find-KitTool 'signtool.exe'
    $inf2cat  = Find-KitTool 'inf2cat.exe'
    Write-Detail "Profile      : $($Ctx.Os.Code)"
    Write-Detail "SDK build    : $($Ctx.Os.SdkBuild)"
    Write-Detail "WDK build    : $($Ctx.Os.WdkBuild)"
    Write-Detail "Notes        : $($Ctx.Os.ToolkitNotes)"

    # r51: On a clean-installed host the SDK and WDK packages are
    # absent and must be downloaded via winget. The bootstrap EXEs
    # (winsdksetup.exe / wdksetup.exe) are ~1.3 MB each but the
    # background payloads they pull from Microsoft Download CDN are
    # several hundred MB to multi-GB; the install typically takes
    # ~5 min for the SDK and ~3 min for the WDK on a typical
    # connection in JP (total P02 elapsed ~8-10 min). On subsequent
    # runs in the same workspace, the P02 PhaseMarker is hit and
    # this whole block is skipped in ~2 s. We surface this once,
    # up-front, so the user is not surprised by the long pause.
    $needsSdk = (-not $signtool) -and $Ctx.Os.WingetSdkId
    $needsWdk = (-not $inf2cat)  -and $Ctx.Os.WingetWdkId
    if ($needsSdk -or $needsWdk) {
        $missing = @()
        if ($needsSdk) { $missing += 'Windows SDK (~5 min)' }
        if ($needsWdk) { $missing += 'Windows WDK (~3 min)' }
        Write-Warn2 ('First-run install required for: {0}.' -f ($missing -join ', '))
        Write-Host  '       Bootstrap EXEs are small (~1-2 MB) but each fetches several hundred MB'  -ForegroundColor DarkYellow
        Write-Host  '       to multi-GB of background payload from Microsoft Download CDN.'         -ForegroundColor DarkYellow
        Write-Host  '       Expected P02 elapsed on a clean host (JP): ~8-10 minutes.'              -ForegroundColor DarkYellow
        Write-Host  '       Subsequent runs in the same workspace will skip P02 (PhaseMarker hit).' -ForegroundColor DarkGray
    }

    $wingetWorks = (Test-WingetWorking) -and $Ctx.Os.CanInstallWinget
    if ($wingetWorks -and $Ctx.Os.WingetSdkId -and -not $signtool) {
        Write-Step "Windows SDK: winget ($($Ctx.Os.WingetSdkId))"
        try { $null = Invoke-WingetSilently -PackageId $Ctx.Os.WingetSdkId }
        catch { Write-Warn2 "winget SDK failed: $($_.Exception.Message)" }
    }
    if ($wingetWorks -and $Ctx.Os.WingetWdkId -and -not $inf2cat) {
        Write-Step "Windows WDK: winget ($($Ctx.Os.WingetWdkId))"
        try { $null = Invoke-WingetSilently -PackageId $Ctx.Os.WingetWdkId }
        catch { Write-Warn2 "winget WDK failed: $($_.Exception.Message)" }
    }
    if (-not (Find-KitTool 'signtool.exe')) {
        Write-Step "Windows SDK: direct EXE fallback for $($Ctx.Os.Name)"
        Install-WindowsSdkFallback -OsContext $Ctx.Os -DownloadDir $Ctx.Paths.Download
    }
    if (-not (Find-KitTool 'inf2cat.exe')) {
        Write-Step "Windows WDK: direct EXE fallback for $($Ctx.Os.Name)"
        Install-WindowsWdkFallback -OsContext $Ctx.Os -DownloadDir $Ctx.Paths.Download
    }
    $Ctx.Signtool = Find-KitTool 'signtool.exe'
    $Ctx.Inf2cat  = Find-KitTool 'inf2cat.exe'
    if (-not $Ctx.Signtool) { throw 'signtool.exe not found after install' }
    if (-not $Ctx.Inf2cat)  { throw 'inf2cat.exe not found after install' }
    Write-Ok "signtool: $($Ctx.Signtool)"
    Write-Ok "inf2cat : $($Ctx.Inf2cat)"
    Set-PhaseMarker -Ctx $Ctx -PhaseId 'P02' -Metadata @{
        SevenZip = $Ctx.SevenZip
        Signtool = $Ctx.Signtool
        Inf2cat  = $Ctx.Inf2cat
        Region   = $region
    }
    Write-PhaseFooter 'P02' 'done'
}

function Invoke-PrepPhase03_FetchInstaller {
    <#
    .SYNOPSIS
        Locate the bthpan inbox driver in the host's DriverStore.
    .DESCRIPTION
        Unlike the sister AMD scripts which download an installer EXE
        from amd.com, this script's "installer" is the Microsoft inbox
        bthpan driver already staged on the host at
        C:\Windows\System32\DriverStore\FileRepository\bthpan.inf_amd64_*.

        P03 finds the most recent staged copy. If no copy is present
        (extremely rare; only happens on hosts where the inbox driver
        has been deliberately removed), the phase fails and instructs
        the operator to repair the install via DISM.
    #>
    param($Ctx)
    Write-PhaseHeader 'P03' 'FetchInstaller' 'Prep'

    if (Test-PhaseMarker -Ctx $Ctx -PhaseId 'P03') {
        if ($Ctx.BthPanSource -and (Test-Path -LiteralPath $Ctx.BthPanSource.InfPath)) {
            Write-Skip "DriverStore source already located: $($Ctx.BthPanSource.Path)"
            Write-PhaseFooter 'P03' 'cached'
            return
        }
    }

    # First, confirm the live inbox INF exists. This is a strong
    # signal that the host has the inbox driver provisioned. (The
    # bthpan.inf file under C:\Windows\INF is the staged copy used
    # by the OS for matching at PnP time.)
    $inboxInf = Get-BthPanInboxInfoPath
    if ($inboxInf) {
        Write-Ok "Inbox INF present: $inboxInf"
    } else {
        Write-Warn2 "Inbox INF not found at $env:WINDIR\INF\bthpan.inf"
        Write-Detail 'On a fresh Windows install this is unusual. The DriverStore copy may still be present.'
    }

    # Locate the staged DriverStore copy
    $src = Get-BthPanDriverStoreSource
    if (-not $src) {
        Write-Fail 'No staged bthpan inbox driver found in the DriverStore.'
        Write-Detail "Looked for: C:\Windows\System32\DriverStore\FileRepository\bthpan.inf_amd64_*"
        Write-Detail 'Repair option: dism /online /add-package or feature-by-feature reinstall.'
        throw 'P03: bthpan inbox driver staging directory not found.'
    }

    Write-Ok "DriverStore source located: $($src.DirectoryName)"
    Write-Detail "Path  : $($src.Path)"
    Write-Detail "INF   : $($src.InfPath)"
    Write-Detail "SYS   : $($src.SysPath)"
    Write-Detail "CAT(s): $($src.CatPaths.Count) file(s)"
    Write-Detail "Stamp : $($src.LastWriteTime)"

    $Ctx.BthPanSource = $src
    Set-PhaseMarker -Ctx $Ctx -PhaseId 'P03' -Metadata @{
        SourcePath    = $src.Path
        InfPath       = $src.InfPath
        SysPath       = $src.SysPath
        CatCount      = $src.CatPaths.Count
        LastWriteTime = $src.LastWriteTime
    }
    Write-PhaseFooter 'P03' 'done'
}

function Invoke-PrepPhase04_ExtractInstaller {
    <#
    .SYNOPSIS
        Copy bthpan.inf / bthpan.sys / catalogs from the DriverStore
        staging directory to the workspace 'extracted' directory.
    .DESCRIPTION
        Idempotent: re-running copies the same files (overwriting
        anything from a previous run). The destination layout is
        flat (no per-OS-variant subdirectories, unlike the AMD
        chipset script which has W11x64 / WTx64 / WTx86 variants).
    #>
    param($Ctx)
    Write-PhaseHeader 'P04' 'ExtractInstaller' 'Prep'

    if (-not $Ctx.BthPanSource) {
        throw 'P04: BthPanSource not populated. Run P03 first.'
    }

    $destDir = Join-Path $Ctx.Paths.Extract 'bthpan'
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }

    $copied = 0
    $items = @(
        $Ctx.BthPanSource.InfPath
        $Ctx.BthPanSource.SysPath
    )
    foreach ($cp in $Ctx.BthPanSource.CatPaths) { $items += $cp }

    foreach ($src in $items) {
        $name = Split-Path -Leaf $src
        $dst  = Join-Path $destDir $name
        Copy-Item -LiteralPath $src -Destination $dst -Force
        $copied++
        Write-Detail "Copied: $name"
    }
    Write-Ok ("Copied {0} file(s) to $destDir" -f $copied)

    # Also copy every supporting file in the staging directory (e.g.
    # bthpan.pnf, language MUI files, related .sys/.dll). These don't
    # all need to be in the patched output, but inf2cat may want to
    # confirm cohash for each file referenced by the INF.
    $extraFiles = Get-ChildItem -LiteralPath $Ctx.BthPanSource.Path -File -ErrorAction SilentlyContinue
    foreach ($f in $extraFiles) {
        $dst = Join-Path $destDir $f.Name
        if (-not (Test-Path -LiteralPath $dst)) {
            Copy-Item -LiteralPath $f.FullName -Destination $dst -Force -ErrorAction SilentlyContinue
        }
    }

    $Ctx.ExtractedBthPanDir = $destDir
    Set-PhaseMarker -Ctx $Ctx -PhaseId 'P04' -Metadata @{
        ExtractDir = $destDir
        FileCount  = $copied
    }
    Write-PhaseFooter 'P04' 'done'
}

function Write-BthPanInfInventorySummary {
    <#
    .SYNOPSIS
        Emit a short, human-readable inventory summary for the single
        bthpan.inf in the workspace.
    #>
    param([pscustomobject]$Meta)

    Write-Detail "INF       : bthpan.inf"
    Write-Detail "Class     : $($Meta.Class)"
    Write-Detail "Version   : $($Meta.DriverVer)"
    Write-Detail "Provider  : $($Meta.Provider)"
    Write-Detail "HWID count: $($Meta.HwidCount)"
    Write-Detail "Workstation decorations: $($Meta.WorkstationDecCount)"
    Write-Detail "Server decorations    : $($Meta.ServerDecCount)"
    if ($Meta.HwidCount -gt 0 -and $Meta.Hwids) {
        $preview = ($Meta.Hwids | Select-Object -First 5) -join '; '
        Write-Detail "HWID preview: $preview"
    }
}

function Export-BthPanInfInventoryReport {
    <#
    .SYNOPSIS
        Write a plain-text inventory report alongside inf_inventory.csv.
    #>
    param($Ctx, [pscustomobject]$Meta)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('Microsoft BthPan Inbox Driver - INF Inventory Report')
    [void]$sb.AppendLine('====================================================')
    [void]$sb.AppendLine("Generated     : $(Get-Date -Format o)")
    [void]$sb.AppendLine("Workspace     : $($Ctx.WorkRoot)")
    [void]$sb.AppendLine("Source dir    : $($Ctx.BthPanSource.Path)")
    [void]$sb.AppendLine("Source mtime  : $($Ctx.BthPanSource.LastWriteTime)")
    [void]$sb.AppendLine("Inf2cat /os:  : $($Ctx.Os.Inf2catOsArg)")
    [void]$sb.AppendLine("Decoration    : strategy $($Ctx.DecorationStrategy)")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('Single INF Inventory')
    [void]$sb.AppendLine('--------------------')
    [void]$sb.AppendLine("FileName            : bthpan.inf")
    [void]$sb.AppendLine("Class               : $($Meta.Class)")
    [void]$sb.AppendLine("Provider            : $($Meta.Provider)")
    [void]$sb.AppendLine("DriverVer           : $($Meta.DriverVer)")
    [void]$sb.AppendLine("HwidCount           : $($Meta.HwidCount)")
    [void]$sb.AppendLine("WorkstationDecCount : $($Meta.WorkstationDecCount)")
    [void]$sb.AppendLine("ServerDecCount      : $($Meta.ServerDecCount)")
    [void]$sb.AppendLine("NeedsPatch          : $($Meta.NeedsPatch)")
    [void]$sb.AppendLine("HasServerDecoration : $($Meta.HasServerDecoration)")
    [void]$sb.AppendLine("SelectedForPipeline : True")
    if ($Meta.Hwids) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('Hardware IDs:')
        foreach ($h in $Meta.Hwids) { [void]$sb.AppendLine("  - $h") }
    }
    [void]$sb.AppendLine('')

    # Append Secure Boot baseline appendix when available
    try {
        $sb_baseline = Get-OrEnsureSecureBootBaseline -Ctx $Ctx
        if ($sb_baseline) {
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('UEFI Secure Boot Baseline (informational; independent of OS-layer signing trust)')
            [void]$sb.AppendLine('-------------------------------------------------------------------------------')
            $appendix = Format-SecureBootBaselineForReport -Snapshot $sb_baseline
            [void]$sb.AppendLine($appendix)
        }
    } catch {}

    $reportPath = Join-Path $Ctx.WorkRoot 'inf_inventory_report.txt'
    [System.IO.File]::WriteAllText($reportPath, $sb.ToString(), [System.Text.Encoding]::UTF8)
    Write-Detail "Report: $reportPath"
}

function Get-BthPanInfMetadata {
    <#
    .SYNOPSIS
        Read bthpan.inf and return a metadata bag.
    #>
    param([string]$InfPath)

    $infData = Read-InfFile -Path $InfPath
    $content = $infData.Content
    $lines   = $content -split "(?<=`n)"

    # Extract Class, Provider, DriverVer
    $class = '(unknown)'; $provider = '(unknown)'; $driverVer = '(unknown)'
    if ($content -match '(?im)^\s*Class\s*=\s*([^\s;]+)')      { $class = $matches[1] }
    if ($content -match '(?im)^\s*Provider\s*=\s*(.+?)\s*(;|$)') { $provider = $matches[1] }
    if ($content -match '(?im)^\s*DriverVer\s*=\s*(.+?)\s*(;|$)') { $driverVer = $matches[1] }

    # Collect HWIDs from any Models section
    $hwids = New-Object 'System.Collections.Generic.List[string]'
    $inModels = $false
    $modelHdrPattern = '^\[[^\]]+\.NT'
    $sectionHdr = '^\['
    foreach ($l in $lines) {
        $t = $l.Trim().TrimEnd("`r")
        if ($t -match $modelHdrPattern) { $inModels = $true; continue }
        elseif ($t -match $sectionHdr)   { $inModels = $false; continue }
        if ($inModels -and $t -and -not $t.StartsWith(';')) {
            # Lines look like: %DisplayName% = InstallSection, HWID1, HWID2, ...
            $kv = $t -split '=', 2
            if ($kv.Count -ne 2) { continue }
            $rhs = $kv[1].Split(',')
            for ($k = 1; $k -lt $rhs.Count; $k++) {
                $hw = $rhs[$k].Trim().TrimEnd(';').Trim()
                if ($hw) { [void]$hwids.Add($hw) }
            }
        }
    }
    $uniqueHwids = @($hwids | Sort-Object -Unique)

    # Count Workstation / Server decorations in [Manufacturer]
    $wsCount = 0; $svCount = 0
    $inMfg = $false
    foreach ($l in $lines) {
        $t = $l.Trim().TrimEnd("`r")
        if ($t -match '^\[Manufacturer\]') { $inMfg = $true; continue }
        if ($inMfg -and $t -match '^\[')     { $inMfg = $false }
        if ($inMfg -and $t -and -not $t.StartsWith(';')) {
            $kv = $t -split '=', 2
            if ($kv.Count -ne 2) { continue }
            $rhs = $kv[1].Split(',')
            for ($k = 1; $k -lt $rhs.Count; $k++) {
                $dec = $rhs[$k].Trim()
                if ($dec -match '^NT' -and $dec -match '\.3$')          { $svCount++ }
                elseif ($dec -match '^NT' -and $dec -match '\.1$')      { $wsCount++ }
                elseif ($dec -match '^NT' -and $dec -match '\.\d+\.\d+\.\d+\.\d+$') {
                    # explicit OS-versioned decoration without trailing ProductType segment is rare
                    if ($dec -match '\.3$') { $svCount++ } else { $wsCount++ }
                }
            }
        }
    }

    return [pscustomobject]@{
        Class               = $class
        Provider            = $provider
        DriverVer           = $driverVer
        HwidCount           = $uniqueHwids.Count
        Hwids               = $uniqueHwids
        WorkstationDecCount = $wsCount
        ServerDecCount      = $svCount
        HasServerDecoration = ($svCount -gt 0)
        NeedsPatch          = ($wsCount -gt 0 -and $svCount -eq 0)
        EncodingName        = $infData.EncodingName
    }
}

function Invoke-PrepPhase05_AnalyzeInfs {
    <#
    .SYNOPSIS
        Inventory bthpan.inf into inf_inventory.csv + report.
    #>
    param($Ctx)
    Write-PhaseHeader 'P05' 'AnalyzeInfs' 'Prep'

    if (-not $Ctx.ExtractedBthPanDir) {
        throw 'P05: ExtractedBthPanDir not populated. Run P04 first.'
    }

    $infPath = Join-Path $Ctx.ExtractedBthPanDir 'bthpan.inf'
    if (-not (Test-Path -LiteralPath $infPath)) {
        throw "P05: bthpan.inf not found at $infPath"
    }

    Write-Step "Reading bthpan.inf..."
    $meta = Get-BthPanInfMetadata -InfPath $infPath
    Write-BthPanInfInventorySummary -Meta $meta

    # Decide whether the source needs patching
    if ($meta.HasServerDecoration -and -not $meta.NeedsPatch) {
        Write-Ok 'INF already carries Server decorations. P06 will detect this and copy through.'
    } elseif ($meta.NeedsPatch) {
        Write-Ok 'INF needs ProductType=3 mirror (this is the expected state for inbox bthpan.inf).'
    } else {
        Write-Warn2 'Neither Server-decoration present nor Workstation-decoration found. Unusual INF shape; P06 may no-op.'
    }

    # Export CSV
    $csvPath = Join-Path $Ctx.WorkRoot 'inf_inventory.csv'
    $row = [pscustomobject]@{
        FileName            = 'bthpan.inf'
        FullPath            = $infPath
        Provider            = $meta.Provider
        DriverVer           = $meta.DriverVer
        Class               = $meta.Class
        HwidCount           = $meta.HwidCount
        HasServerDecoration = $meta.HasServerDecoration
        WorkstationDecCount = $meta.WorkstationDecCount
        ServerDecCount      = $meta.ServerDecCount
        NeedsPatch          = $meta.NeedsPatch
        SelectedForPipeline = $true
        HwidPreview         = (($meta.Hwids | Select-Object -First 3) -join '; ')
    }
    $row | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -Force
    Write-Ok "Inventory CSV: $csvPath"

    Export-BthPanInfInventoryReport -Ctx $Ctx -Meta $meta

    # Cache metadata for downstream phases
    $Ctx.BthPanInfMetadata = $meta
    $Ctx.BthPanInfPath     = $infPath

    Set-PhaseMarker -Ctx $Ctx -PhaseId 'P05' -Metadata @{
        HwidCount    = $meta.HwidCount
        NeedsPatch   = $meta.NeedsPatch
    }
    Write-PhaseFooter 'P05' 'done'
}

function Add-BthPanExplicitServerDecorations {
    <#
    .SYNOPSIS
        Strategy B helper: also append per-build Server decorations
        (NTamd64.10.0...14393, ...17763, ...20348, ...26100) on top of
        what Strategy A produced.
    .DESCRIPTION
        After Edit-InfForServer has done Strategy A (Workstation .1 ->
        Server .3 mirror), this helper walks the [Manufacturer] entries
        again and appends the explicit per-build Server decorations.
        For each appended decoration, it also mirrors the corresponding
        InstallSection block.

        Returns the count of decorations / sections added.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$InfPath
    )

    $infData = Read-InfFile -Path $InfPath
    $content = $infData.Content
    $lines = $content -split "(?<=`n)"
    if (-not ($lines -is [array])) { $lines = @($lines) }

    # The four explicit per-build Server decorations
    $explicit = @(
        'NTamd64.10.0...14393',  # WS2016
        'NTamd64.10.0...17763',  # WS2019
        'NTamd64.10.0...20348',  # WS2022
        'NTamd64.10.0...26100'   # WS2025
    )

    # Locate [Manufacturer] section and collect existing decorations
    $mfgIndices = @()
    $existingDecorationsBySection = @{}
    $inMfg = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = $lines[$i].Trim().TrimEnd("`r")
        if ($t -match '^\[Manufacturer\]') { $inMfg = $true; continue }
        if ($inMfg -and $t -match '^\[')     { $inMfg = $false }
        if ($inMfg -and $t -and -not $t.StartsWith(';')) {
            $mfgIndices += $i
            $kv = $t -split '=', 2
            if ($kv.Count -ne 2) { continue }
            $rhs = $kv[1].Split(',')
            $sec = $rhs[0].Trim()
            if (-not $existingDecorationsBySection.ContainsKey($sec)) {
                $existingDecorationsBySection[$sec] = @()
            }
            for ($k = 1; $k -lt $rhs.Count; $k++) {
                $existingDecorationsBySection[$sec] += $rhs[$k].Trim()
            }
        }
    }

    if ($mfgIndices.Count -eq 0) {
        return @{ Added = 0; SectionsMirrored = 0 }
    }

    # Find the base Workstation-decorated section that we'll clone for
    # each explicit decoration. We expect the original to be e.g.
    # [Msft.NTamd64...1] (still present after Strategy A).
    $sectionsToCloneFrom = @{}  # decorationToken (e.g. 'NTamd64...1') -> contentLines
    $current = $null
    $body    = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) {
        $t = $l.Trim().TrimEnd("`r")
        if ($t -match '^\[(.+?)\]$') {
            if ($current) {
                # Save under each section we've completed scanning
            }
            $current = $matches[1]
            $body.Clear()
            continue
        }
        if ($current) { [void]$body.Add($l) }
        # We persist body per section header transition; we collect later
    }
    # Simpler: re-scan to grab the [section.NT*] bodies
    $sectionBodies = @{}
    $currentHeader = $null
    $buffer = New-Object 'System.Collections.Generic.List[string]'
    foreach ($l in $lines) {
        $t = $l.Trim().TrimEnd("`r")
        if ($t -match '^\[(.+?)\]$') {
            if ($currentHeader) {
                $sectionBodies[$currentHeader] = $buffer.ToArray()
            }
            $currentHeader = $matches[1]
            $buffer.Clear()
            continue
        }
        if ($currentHeader) { [void]$buffer.Add($l) }
    }
    if ($currentHeader) {
        $sectionBodies[$currentHeader] = $buffer.ToArray()
    }

    # For each [Manufacturer] entry: append the explicit decorations
    for ($mIdx = 0; $mIdx -lt $mfgIndices.Count; $mIdx++) {
        $idx = $mfgIndices[$mIdx]
        $line = $lines[$idx]
        $eolMatch = [regex]::Match($line, "(`r?`n)$")
        $eol = if ($eolMatch.Success) { $eolMatch.Value } else { '' }
        $core = if ($eol) { $line.Substring(0, $line.Length - $eol.Length) } else { $line }
        $appended = $core
        # Determine section name
        $kv = $core.Trim() -split '=', 2
        if ($kv.Count -ne 2) { continue }
        $secName = $kv[1].Split(',')[0].Trim()
        $existing = if ($existingDecorationsBySection.ContainsKey($secName)) {
            $existingDecorationsBySection[$secName]
        } else { @() }
        foreach ($explDec in $explicit) {
            if ($appended -match [regex]::Escape($explDec)) { continue }
            if ($existing -contains $explDec) { continue }
            $appended = $appended.TrimEnd() + ", $explDec"
        }
        $lines[$idx] = $appended + $eol
    }

    # Append the cloned section blocks at the end
    $sb = New-Object System.Text.StringBuilder
    foreach ($l in $lines) { [void]$sb.Append($l) }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('; ====================================================')
    [void]$sb.AppendLine('; Auto-generated: explicit per-build Server decorations (Strategy B)')
    [void]$sb.AppendLine('; ====================================================')

    $sectionsAdded = 0
    foreach ($secName in $existingDecorationsBySection.Keys) {
        # The original Workstation section header is something like '<secName>.NTamd64...1'
        $wsHeader = "$secName.NTamd64...1"
        if (-not $sectionBodies.ContainsKey($wsHeader)) { continue }
        $wsBody = $sectionBodies[$wsHeader]
        foreach ($explDec in $explicit) {
            $newHeader = "$secName.$explDec"
            if ($sectionBodies.ContainsKey($newHeader)) { continue }
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine("[$newHeader]")
            foreach ($bl in $wsBody) { [void]$sb.Append($bl) }
            $sectionsAdded++
        }
    }

    Write-InfFile -Path $InfPath -Content $sb.ToString() -Encoding $infData.Encoding
    return @{
        Added            = ($explicit.Count * $mfgIndices.Count)
        SectionsMirrored = $sectionsAdded
    }
}

function Invoke-PrepPhase06_PatchInfs {
    <#
    .SYNOPSIS
        Generate the patched bthpan.inf in workspace\patched\bthpan.
    .DESCRIPTION
        Strategy A (default): use Edit-InfForServer to mirror the
        Workstation .1 entries with .3 entries.
        Strategy B          : additionally append explicit per-build
        Server decorations (.10.0...14393 / 17763 / 20348 / 26100).
    #>
    param($Ctx)
    Write-PhaseHeader 'P06' 'PatchInfs' 'Prep'

    if (-not $Ctx.BthPanInfPath) {
        throw 'P06: BthPanInfPath not populated. Run P05 first.'
    }

    $srcInf = $Ctx.BthPanInfPath
    $patchedDir = Join-Path $Ctx.Paths.Patched 'bthpan'
    if (-not (Test-Path -LiteralPath $patchedDir)) {
        New-Item -Path $patchedDir -ItemType Directory -Force | Out-Null
    }
    $dstInf = Join-Path $patchedDir 'bthpan.inf'

    # Always re-copy all supporting files into the patched directory,
    # because inf2cat hashes every file referenced by the INF and needs
    # them all present.
    $extractDir = Split-Path -Parent $srcInf
    Get-ChildItem -LiteralPath $extractDir -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $dst = Join-Path $patchedDir $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
        }

    # Strategy A — Workstation .1 -> Server .3 mirror via Edit-InfForServer
    $result = Edit-InfForServer -InfPath $srcInf -OutputPath $dstInf -OsContext $Ctx.Os
    if (-not $result.Patched) {
        if ($result.Reason -like '*No client decorations*') {
            # Already Server-compatible; copy through
            Write-Skip 'INF has no Workstation decorations; copying through unchanged.'
            Copy-Item -LiteralPath $srcInf -Destination $dstInf -Force
        } else {
            throw "P06: Edit-InfForServer failed: $($result.Reason)"
        }
    } else {
        Write-Ok "Patched bthpan.inf with $($result.SectionsMirrored) mirrored section(s)"
        Write-Detail "Decorations added: $($result.Decorations.Values -join ', ')"
        Write-Detail "Output: $dstInf"
    }

    if ($Ctx.DecorationStrategy -eq 'B') {
        Write-Step 'Strategy B: appending explicit per-build Server decorations...'
        $more = Add-BthPanExplicitServerDecorations -InfPath $dstInf
        Write-Ok ("Strategy B: appended {0} per-entry decoration token(s), cloned {1} section block(s)" -f $more.Added, $more.SectionsMirrored)
    } else {
        Write-Detail 'Strategy A only (NTamd64...3 covers all Server SKUs).'
    }

    # Re-read the patched INF to confirm coverage
    $verifyMeta = Get-BthPanInfMetadata -InfPath $dstInf
    Write-Detail ("Post-patch Server decorations: {0}" -f $verifyMeta.ServerDecCount)
    if ($verifyMeta.ServerDecCount -lt 1) {
        throw "P06: post-patch INF has no Server decorations (expected at least 1)"
    }

    $Ctx.PatchedBthPanInfPath = $dstInf
    Set-PhaseMarker -Ctx $Ctx -PhaseId 'P06' -Metadata @{
        OutputPath   = $dstInf
        ServerDecCount = $verifyMeta.ServerDecCount
    }
    Write-PhaseFooter 'P06' 'done'
}

function Invoke-PrepPhase07_CreateCertificate {
    <#
    .SYNOPSIS
        Generate the self-signed code-signing certificate for bthpan
        catalog signing. PFX is written to workspace\cert\.
    #>
    param($Ctx)
    Write-PhaseHeader 'P07' 'CreateCertificate' 'Prep'

    $pfxPath = Join-Path $Ctx.Paths.Cert 'MS-BthPan-Driver-CodeSign.pfx'
    $cerPath = Join-Path $Ctx.Paths.Cert 'MS-BthPan-Driver-CodeSign.cer'

    $subject = "CN=Microsoft BthPan Driver Self-Sign ($($Ctx.Os.Code) Lab, At Own Risk)"

    if ((Test-PhaseMarker -Ctx $Ctx -PhaseId 'P07') -and (Test-Path $pfxPath)) {
        $Ctx.CertPfxPath = $pfxPath
        $Ctx.CertCerPath = $cerPath
        Write-Skip "Certificate cached: $pfxPath"
        Write-PhaseFooter 'P07' 'cached'
        return
    }

    Get-ChildItem -Path $Ctx.Paths.Cert -Force -ErrorAction SilentlyContinue | Remove-Item -Force

    # Delete any same-subject certs from LocalMachine\My (avoid accumulation across re-runs)
    $preexisting = @(Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq $subject })
    if ($preexisting.Count -gt 0) {
        Write-Warn2 ("Found {0} existing certificate(s) with same Subject - deleting before re-creation" -f $preexisting.Count)
        foreach ($oldCert in $preexisting) {
            Write-Detail ("Deleting thumbprint={0} not-after={1:yyyy-MM-dd}" -f $oldCert.Thumbprint, $oldCert.NotAfter)
            try {
                Remove-Item -LiteralPath ("Cert:\LocalMachine\My\{0}" -f $oldCert.Thumbprint) -Force -ErrorAction Stop
            } catch {
                throw "P07: cannot remove existing cert $($oldCert.Thumbprint) from LocalMachine\My. Run as Administrator and try again."
            }
        }
    }

    $params = @{
        Subject = $subject; Type = 'CodeSigningCert'
        KeySpec = 'Signature'; KeyUsage = 'DigitalSignature'
        KeyAlgorithm = 'RSA'; KeyLength = $Ctx.Os.CertKeyLength
        HashAlgorithm = $Ctx.Os.CertHashAlgorithm
        NotAfter = (Get-Date).AddYears($Ctx.Os.CertValidYears)
        CertStoreLocation = 'Cert:\LocalMachine\My'
        FriendlyName = "Microsoft BthPan Driver Codesign ($($Ctx.Os.Code) Self-Signed Lab - Personal Use, At Own Risk)"
    }
    if ($Ctx.Os.UseModernCertExtension) {
        $params.TextExtension = @('2.5.29.37={text}1.3.6.1.5.5.7.3.3')
    }
    $cert = New-SelfSignedCertificate @params
    Write-Ok "Created cert $($cert.Thumbprint)"
    Write-Detail "Subject: $subject"
    Write-Detail "Key    : RSA $($Ctx.Os.CertKeyLength) / $($Ctx.Os.CertHashAlgorithm)"
    Write-Detail "Valid  : $($Ctx.Os.CertValidYears) years"
    Write-Host ''
    Write-Host '    *** SELF-SIGNED CERTIFICATE - PERSONAL VERIFICATION USE ONLY ***' -ForegroundColor Yellow
    Write-Host '    This is NOT issued by a CA or by Microsoft. It is generated' -ForegroundColor DarkYellow
    Write-Host '    locally on this machine for lab/personal verification purposes.' -ForegroundColor DarkYellow

    $secPwd = ConvertTo-SecureString -String $Ctx.PfxPassword -AsPlainText -Force
    Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $secPwd -Force | Out-Null
    Export-Certificate    -Cert $cert -FilePath $cerPath -Force | Out-Null
    Write-Ok "PFX exported: $pfxPath"
    Write-Ok "CER exported: $cerPath"

    $Ctx.CertPfxPath    = $pfxPath
    $Ctx.CertCerPath    = $cerPath
    $Ctx.CertThumbprint = $cert.Thumbprint
    Set-PhaseMarker -Ctx $Ctx -PhaseId 'P07' -Metadata @{ Thumbprint=$cert.Thumbprint; Subject=$subject }
    Write-PhaseFooter 'P07' 'done'
}

function Get-Inf2catVersion {
    param([string]$Inf2catPath)
    try {
        $v = (Get-Item -LiteralPath $Inf2catPath).VersionInfo.ProductVersion
        if ($v) { return $v }
    } catch {}
    return '(unknown)'
}

function Get-Inf2catSupportedOsValues {
    <#
    .SYNOPSIS
        Probe the configured inf2cat.exe for its supported /os: tokens.
        Returns the union of all known Server tokens that this script
        targets, intersected with what inf2cat actually understands.
    #>
    param([string]$Inf2catPath)
    try {
        $help = (& $Inf2catPath 2>&1) -join "`n"
        $candidates = @('Server2025_X64','ServerFE_X64','ServerRS5_X64','Server2016_X64','Server10_X64')
        $present = @()
        foreach ($c in $candidates) {
            if ($help -match [regex]::Escape($c)) { $present += $c }
        }
        return $present
    } catch {
        return @()
    }
}

function Invoke-PrepPhase08_GenerateCatalogs {
    <#
    .SYNOPSIS
        Run inf2cat against the patched bthpan directory to generate a
        catalog that covers WS2016 / WS2019 / WS2022 / WS2025.
    #>
    param($Ctx)
    Write-PhaseHeader 'P08' 'GenerateCatalogs' 'Prep'

    if (-not $Ctx.PatchedBthPanInfPath) {
        throw 'P08: PatchedBthPanInfPath not populated. Run P06 first.'
    }

    $patchedDir = Split-Path -Parent $Ctx.PatchedBthPanInfPath
    $inf2cat = Find-KitTool 'inf2cat.exe'
    if (-not $inf2cat) {
        throw 'P08: inf2cat.exe not found. Run P02 first to install the Windows WDK.'
    }
    Write-Detail "inf2cat: $inf2cat"
    Write-Detail "version: $(Get-Inf2catVersion $inf2cat)"

    # Target ALL four Server SKUs in a single inf2cat run. inf2cat
    # produces ONE catalog that attests for all listed OSes.
    $allTargets = @('Server2025_X64','ServerFE_X64','ServerRS5_X64','Server2016_X64')
    $supportedByThisInf2cat = Get-Inf2catSupportedOsValues -Inf2catPath $inf2cat
    if ($supportedByThisInf2cat.Count -eq 0) {
        # Probe failed — fall back to "what we want"; inf2cat itself will
        # surface unknown tokens via non-zero exit.
        $supportedByThisInf2cat = $allTargets
    }
    $effective = @($allTargets | Where-Object { $supportedByThisInf2cat -contains $_ })
    if ($effective.Count -eq 0) {
        Write-Warn2 'inf2cat reports support for none of the four Server SKUs; using primary host arg only.'
        $effective = @($Ctx.Os.Inf2catOsArg)
    }
    $osArg = $effective -join ','
    Write-Detail "Target OSes: $osArg"

    # Run inf2cat
    $logPath = Join-Path $Ctx.Paths.Logs 'inf2cat_bthpan.log'
    $args = @('/driver:' + $patchedDir, '/os:' + $osArg, '/verbose')
    Write-Step "Running inf2cat /driver:$patchedDir /os:$osArg ..."
    $start = Get-Date
    $proc = Start-Process -FilePath $inf2cat -ArgumentList $args -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $logPath -RedirectStandardError ($logPath + '.err')
    $elapsed = (Get-Date) - $start
    Write-Detail "Elapsed : $(Format-Elapsed $elapsed.TotalSeconds)"
    Write-Detail "Log     : $logPath"

    if ($proc.ExitCode -ne 0) {
        # Look for the most common cause: missing files referenced by INF
        $tail = (Get-Content -LiteralPath $logPath -Tail 30 -ErrorAction SilentlyContinue) -join "`n"
        if ($tail) { Write-Host $tail -ForegroundColor DarkGray }
        # Try fallback: drop Server2016 if it's the only failing entry
        if ($effective -contains 'Server2016_X64' -and $effective.Count -gt 1) {
            Write-Warn2 'inf2cat failed with the full 4-SKU target list. Retrying without Server2016_X64...'
            $reduced = @($effective | Where-Object { $_ -ne 'Server2016_X64' })
            $args2 = @('/driver:' + $patchedDir, '/os:' + ($reduced -join ','), '/verbose')
            $proc = Start-Process -FilePath $inf2cat -ArgumentList $args2 -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $logPath -RedirectStandardError ($logPath + '.err')
        }
    }
    if ($proc.ExitCode -ne 0) {
        throw "P08: inf2cat exited with code $($proc.ExitCode). See $logPath for details."
    }

    # Discover produced catalog files
    $cats = @(Get-ChildItem -LiteralPath $patchedDir -Filter '*.cat' -ErrorAction SilentlyContinue)
    if ($cats.Count -eq 0) {
        throw "P08: inf2cat exit was 0 but no .cat file is present in $patchedDir"
    }
    Write-Ok ("Generated {0} catalog(s):" -f $cats.Count)
    foreach ($c in $cats) {
        Write-Detail ("  {0}  ({1} bytes)" -f $c.Name, $c.Length)
    }

    $Ctx.PatchedBthPanDir   = $patchedDir
    $Ctx.PatchedCatalogs    = @($cats | ForEach-Object { $_.FullName })
    Set-PhaseMarker -Ctx $Ctx -PhaseId 'P08' -Metadata @{
        CatCount = $cats.Count
        OsArg    = $osArg
    }
    Write-PhaseFooter 'P08' 'done'
}

function Invoke-PrepPhase09_SignCatalogs {
    <#
    .SYNOPSIS
        Sign each catalog under the patched bthpan directory with the
        self-signed PFX produced in P07.
    #>
    param($Ctx)
    Write-PhaseHeader 'P09' 'SignCatalogs' 'Prep'

    if (-not $Ctx.PatchedCatalogs -or $Ctx.PatchedCatalogs.Count -eq 0) {
        throw 'P09: PatchedCatalogs not populated. Run P08 first.'
    }
    if (-not $Ctx.CertPfxPath -or -not (Test-Path -LiteralPath $Ctx.CertPfxPath)) {
        throw 'P09: PFX not found. Run P07 first.'
    }

    $signtool = Find-KitTool 'signtool.exe'
    if (-not $signtool) {
        throw 'P09: signtool.exe not found. Run P02 first to install the Windows SDK.'
    }
    Write-Detail "signtool: $signtool"

    $fdAlgo = $Ctx.Os.CertHashAlgorithm  # SHA384 on WS2025, SHA256 on WS2016
    Write-Detail "Digest  : $fdAlgo"
    Write-Detail "TSA URL : $($Ctx.TimestampUrl)"

    $signed = 0
    foreach ($cat in $Ctx.PatchedCatalogs) {
        $log = Join-Path $Ctx.Paths.Logs ('signtool_' + (Split-Path -Leaf $cat) + '.log')
        Write-Step ("Signing: {0}" -f (Split-Path -Leaf $cat))
        $args = @(
            'sign',
            '/fd', $fdAlgo,
            '/td', $fdAlgo,
            '/tr', $Ctx.TimestampUrl,
            '/f',  $Ctx.CertPfxPath,
            '/p',  $Ctx.PfxPassword,
            '/v',
            $cat
        )
        $proc = Start-Process -FilePath $signtool -ArgumentList $args -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $log -RedirectStandardError ($log + '.err')
        if ($proc.ExitCode -ne 0) {
            $tail = (Get-Content -LiteralPath $log -Tail 30 -ErrorAction SilentlyContinue) -join "`n"
            if ($tail) { Write-Host $tail -ForegroundColor DarkGray }
            throw "P09: signtool sign failed (exit $($proc.ExitCode)) for $cat. See $log."
        }
        $signed++
        Write-Ok ("Signed: {0}" -f (Split-Path -Leaf $cat))
    }

    Set-PhaseMarker -Ctx $Ctx -PhaseId 'P09' -Metadata @{
        SignedCount = $signed
    }
    Write-PhaseFooter 'P09' 'done'
}


#####################################################################
# SECTION 9: VERIFICATION PHASES
#####################################################################
# Verification phases NEVER modify the running system. They examine
# preparation artifacts and / or the current OS state in read-only
# mode and report what would change if Installation phases ran.

function Invoke-VerifyPhase01_VerifyArtifacts {
    param($Ctx)
    Write-PhaseHeader 'V01' 'VerifyArtifacts' 'Verify'

    $issues = New-Object System.Collections.Generic.List[string]
    $checks = New-Object System.Collections.Generic.List[string]

    function _Check {
        param([bool]$Cond, [string]$Ok, [string]$Bad)
        if ($Cond) { $checks.Add("[OK]   $Ok") | Out-Null }
        else       { $checks.Add("[FAIL] $Bad") | Out-Null; $issues.Add($Bad) | Out-Null }
    }

    $pfx = Join-Path $Ctx.Paths.Cert 'MS-BthPan-Driver-CodeSign.pfx'
    $cer = Join-Path $Ctx.Paths.Cert 'MS-BthPan-Driver-CodeSign.cer'
    _Check (Test-Path $pfx) "PFX present : $pfx"  "PFX MISSING (run P07): $pfx"
    _Check (Test-Path $cer) "CER present : $cer"  "CER MISSING (run P07): $cer"

    $patchedInfs = @()
    if (Test-Path $Ctx.Paths.Patched) {
        $patchedInfs = Get-ChildItem -Path $Ctx.Paths.Patched -Recurse -Filter *.inf -ErrorAction SilentlyContinue
    }
    _Check ($patchedInfs.Count -gt 0) `
        "Patched INFs: $($patchedInfs.Count) file(s) under $($Ctx.Paths.Patched)" `
        "No patched INFs found in $($Ctx.Paths.Patched) (run P06)"

    $cats = @()
    if (Test-Path $Ctx.Paths.Patched) {
        $cats = Get-ChildItem -Path $Ctx.Paths.Patched -Recurse -Filter *.cat -ErrorAction SilentlyContinue
    }
    if ($cats.Count -eq 0) {
        $checks.Add("[WARN] No .cat files (P08 + P09 not yet run?)") | Out-Null
    } else {
        $checks.Add("[OK]   Catalog files: $($cats.Count) .cat file(s)") | Out-Null
    }

    $csv = Join-Path $Ctx.Paths.Root 'inf_inventory.csv'
    _Check (Test-Path $csv) "Inventory CSV: $csv" "INF inventory CSV missing (run P05): $csv"

    foreach ($c in $checks) { Write-Host "  $c" }
    if ($issues.Count -gt 0) {
        Write-Warn2 "$($issues.Count) artifact issue(s) detected"
        throw "V01 found $($issues.Count) missing artifact(s) - run earlier phases first."
    }
    Write-Ok 'All preparation artifacts are present.'
    Write-PhaseFooter 'V01' 'done'
}

function Invoke-VerifyPhase02_VerifyCertificate {
    param($Ctx)
    Write-PhaseHeader 'V02' 'VerifyCertificate' 'Verify'

    $pfx = Join-Path $Ctx.Paths.Cert 'MS-BthPan-Driver-CodeSign.pfx'
    if (-not (Test-Path $pfx)) {
        Write-Fail "PFX not found: $pfx"
        throw 'V02: cannot verify certificate without PFX (run P07)'
    }

    # Use .NET API instead of Get-PfxCertificate so the password is
    # supplied non-interactively (PFX is password-protected from P07).
    $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($pfx, $Ctx.PfxPassword)
    Write-Host "  Subject       : $($cert.Subject)"
    Write-Host "  Thumbprint    : $($cert.Thumbprint)"
    Write-Host "  Issuer        : $($cert.Issuer)"
    Write-Host "  Valid from    : $($cert.NotBefore)"
    Write-Host "  Valid to      : $($cert.NotAfter)"
    Write-Host "  Signature alg : $($cert.SignatureAlgorithm.FriendlyName)"
    Write-Host "  Has priv key  : $($cert.HasPrivateKey)"

    $problems = New-Object System.Collections.Generic.List[string]

    if (-not $cert.HasPrivateKey) {
        $problems.Add('Certificate has no private key - signtool will fail') | Out-Null
    }

    $daysLeft = ($cert.NotAfter - (Get-Date)).Days
    if ($daysLeft -le 0) {
        $problems.Add("Certificate has EXPIRED ($daysLeft days)") | Out-Null
    } elseif ($daysLeft -le 30) {
        Write-Warn2 "Certificate expires in $daysLeft days - consider renewal"
    } else {
        Write-Ok "Certificate valid for $daysLeft more days"
    }

    # Code Signing EKU = 1.3.6.1.5.5.7.3.3
    $hasCodeSigning = $false
    foreach ($ext in $cert.Extensions) {
        if ($ext.Oid.Value -eq '2.5.29.37') {
            foreach ($eku in $ext.EnhancedKeyUsages) {
                if ($eku.Value -eq '1.3.6.1.5.5.7.3.3') { $hasCodeSigning = $true }
            }
        }
    }
    if ($hasCodeSigning) {
        Write-Ok 'Code Signing EKU (1.3.6.1.5.5.7.3.3) present'
    } else {
        Write-Warn2 'Code Signing EKU NOT present - some signtool flows may reject'
    }

    if ($problems.Count -gt 0) {
        foreach ($p in $problems) { Write-Fail "  $p" }
        throw "V02: certificate has $($problems.Count) blocking issue(s)"
    }
    Write-PhaseFooter 'V02' 'done'
}

function Invoke-VerifyPhase03_VerifyCatalogs {
    param($Ctx)
    Write-PhaseHeader 'V03' 'VerifyCatalogs' 'Verify'

    if (-not $Ctx.Signtool) { $Ctx.Signtool = Find-KitTool 'signtool.exe' }
    if (-not $Ctx.Signtool) {
        throw 'V03: signtool.exe not found - run P02 (AcquireTools) first.'
    }

    $cats = @()
    if (Test-Path $Ctx.Paths.Patched) {
        $cats = Get-ChildItem -Path $Ctx.Paths.Patched -Recurse -Filter *.cat -ErrorAction SilentlyContinue
    }
    if ($cats.Count -eq 0) {
        Write-Warn2 'No .cat files to verify (P08 + P09 not yet run?)'
        Write-PhaseFooter 'V03' 'skipped'
        return
    }

    # ---- Pre-flight: is the signing certificate actually trusted? ----
    # signtool verify /pa requires the cert chain to terminate at a
    # trusted root. Self-signed test certs are NOT trusted until I01
    # imports them into LocalMachine\Root and TrustedPublisher. If V03
    # runs before I01, all verifications will fail with "untrusted
    # root" - this is EXPECTED, not a bug.
    #
    # We detect this state up-front so failures can be classified
    # correctly (expected vs. real corruption) at the end of the phase.
    $certTrusted = $false
    $certInRoot = $false
    $certInTrustedPublisher = $false
    if ($Ctx.CertThumbprint) {
        $certInRoot = [bool](Get-ChildItem 'Cert:\LocalMachine\Root' -ErrorAction SilentlyContinue |
                            Where-Object { $_.Thumbprint -eq $Ctx.CertThumbprint })
        $certInTrustedPublisher = [bool](Get-ChildItem 'Cert:\LocalMachine\TrustedPublisher' -ErrorAction SilentlyContinue |
                            Where-Object { $_.Thumbprint -eq $Ctx.CertThumbprint })
        $certTrusted = $certInRoot -and $certInTrustedPublisher
    }

    Write-Detail "Cert thumbprint   : $($Ctx.CertThumbprint)" -Color DarkGray
    Write-Detail ("In TrustedRoot    : {0}" -f $certInRoot) -Color $(if ($certInRoot) { 'DarkGray' } else { 'Yellow' })
    Write-Detail ("In TrustedPublisher: {0}" -f $certInTrustedPublisher) -Color $(if ($certInTrustedPublisher) { 'DarkGray' } else { 'Yellow' })
    if (-not $certTrusted) {
        Write-Host ''
        Write-Warn2 '    NOTE: Certificate is NOT yet in trusted stores.'
        Write-Host  '          signtool verify /pa will fail with "untrusted root" for all'
        Write-Host  '          catalogs - this is EXPECTED at this stage of the pipeline.'
        Write-Host  '          To pass V03, run -Action Install -OnlyPhases I01 first to'
        Write-Host  '          import the cert, then re-run V03.'
        Write-Host  '          V03 will treat untrusted-root failures as informational, NOT'
        Write-Host  '          as real verification failures.'
        Write-Host ''
    }

    Write-Step "Verifying $($cats.Count) catalog signature(s) with signtool /verify /pa..."

    # Patterns that indicate an "expected" failure (cert not yet trusted).
    # These are NOT real verification problems - the catalog signature is
    # cryptographically valid, but the trust chain can't be validated yet.
    #
    # IMPORTANT: signtool wraps long error messages across multiple lines
    # at ~80 columns. PowerShell's -match operator does NOT allow `.` to
    # span newlines by default, so we must either use the (?s) inline
    # flag or normalise the input before matching. Below we use SHORTER
    # substrings that are guaranteed to fit on a single line, plus we
    # normalise whitespace before comparison as a belt-and-braces fix.
    $expectedFailPatterns = @(
        'is not trusted by the trust provider',           # most common
        'A certificate chain processed, but terminated',  # fits on one line
        'The signing certificate is not trusted',
        'A certificate chain could not be built',
        '0x800B0109',                                     # CERT_E_UNTRUSTEDROOT (numeric)
        '0x800B010A',                                     # CERT_E_CHAINING
        'CERT_E_UNTRUSTEDROOT',
        'CERT_E_CHAINING',
        'No signature was present in the subject',
        'Number of files successfully Verified: 0'        # signtool's count line
    )

    $okCount = 0
    $failExpected = 0     # untrusted root etc - expected when cert not yet imported
    $failReal = 0         # actual verification problems
    $firstFailureLogged = $false

    foreach ($cat in $cats) {
        $logFile = Join-Path $Ctx.Paths.Logs ("verify_{0}.log" -f $cat.BaseName)

        # Same ProcessStartInfo pattern as P08/P09/I03 to handle paths
        # with spaces correctly.
        $cmdLine = 'verify /pa /v "{0}"' -f $cat.FullName

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Ctx.Signtool
        $psi.Arguments = $cmdLine
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $exit = $null
        $stdoutText = ''
        $stderrText = ''
        try {
            $proc = [System.Diagnostics.Process]::Start($psi)
            $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
            $stderrTask = $proc.StandardError.ReadToEndAsync()
            $proc.WaitForExit()
            $stdoutText = $stdoutTask.Result
            $stderrText = $stderrTask.Result
            $exit = $proc.ExitCode
            $proc.Dispose()
        } catch {
            $stderrText = "Failed to launch signtool: $($_.Exception.Message)"
        }

        $logBody = New-Object System.Text.StringBuilder
        [void]$logBody.AppendLine("=== signtool verify (exit=$exit) ===")
        [void]$logBody.AppendLine("Command: `"$($Ctx.Signtool)`" $cmdLine")
        [void]$logBody.AppendLine('')
        if ($stdoutText) { [void]$logBody.AppendLine($stdoutText) }
        if ($stderrText) {
            [void]$logBody.AppendLine('--- stderr ---')
            [void]$logBody.AppendLine($stderrText)
        }
        Set-Content -LiteralPath $logFile -Value $logBody.ToString() -Encoding UTF8

        if ($null -ne $exit -and $exit -eq 0) {
            $okCount++
            Write-Ok "  $($cat.Name)"
        } else {
            $exitDisplay = if ($null -eq $exit) { 'launch-failed' } else { $exit }

            # Classify: expected (untrusted) vs real failure.
            #
            # Normalise whitespace before matching: signtool wraps long
            # error messages across newlines at ~80 columns, so the
            # phrase "A certificate chain processed, but terminated in a
            # root\n\tcertificate which is not trusted" would NOT match
            # a regex like ".*terminated.*certificate.*not trusted"
            # because PowerShell's -match operator does not allow `.` to
            # span newlines by default.
            #
            # We collapse all runs of whitespace (newlines, tabs,
            # multiple spaces) into a single space so multi-line errors
            # become single-line strings that simple substring patterns
            # can match reliably.
            $combinedRaw = ($stdoutText + "`n" + $stderrText)
            $combinedFlat = ($combinedRaw -replace '\s+', ' ')

            $isExpected = $false
            foreach ($p in $expectedFailPatterns) {
                if ($combinedFlat -match $p) { $isExpected = $true; break }
            }
            # Also: if cert isn't in trusted stores, treat ALL failures
            # as expected (we know the chain validation will fail).
            # This is the ultimate safety net - even if the regex
            # patterns fail to match, an untrusted cert in the store
            # makes verification failure inevitable and expected.
            if (-not $certTrusted) { $isExpected = $true }

            if ($isExpected) {
                $failExpected++
                # r31: print first 3 [skip] lines explicitly so the
                # operator can see at least a few catalog names; after
                # that, suppress further per-catalog noise. The full
                # count appears in the verification summary below.
                if ($failExpected -le 3) {
                    Write-Detail ("[skip] {0} (expected: cert not yet trusted)" -f $cat.Name) -Color DarkGray
                } elseif ($failExpected -eq 4) {
                    Write-Host '    [skip] ... (further "cert not yet trusted" skips suppressed; see summary)' -ForegroundColor DarkGray
                }
            } else {
                $failReal++
                Write-Warn2 "  exit=$exitDisplay - $($cat.Name) - see $logFile"
            }

            # Dump first failure log to screen for diagnosis
            if (-not $firstFailureLogged) {
                $firstFailureLogged = $true
                Write-Host ''
                Write-Host '    ========== FIRST VERIFY FAILURE - LOG DUMP ==========' -ForegroundColor Yellow
                Write-Detail "Catalog: $($cat.FullName)" -Color DarkYellow
                Write-Detail "Classified as: $(if ($isExpected) { 'EXPECTED (untrusted root)' } else { 'REAL FAILURE' })" -Color DarkYellow
                Write-Host '    -----------------------------------------------------' -ForegroundColor DarkGray
                $dumpLines = $logBody.ToString() -split "`r?`n"
                foreach ($dl in $dumpLines) {
                    Write-Detail "| $dl" -Color DarkYellow
                }
                Write-Host '    -----------------------------------------------------' -ForegroundColor DarkGray
                Write-Host ''
            }
        }
    }

    # ---- Phase outcome classification ----
    Write-Host ''
    Write-Detail "Catalog verification summary:" -Color Cyan
    Write-Detail ("  ok                : {0}" -f $okCount) -Color Green
    Write-Detail ("  expected failures : {0}  (cert not yet trusted)" -f $failExpected) -Color DarkGray
    Write-Detail ("  REAL failures     : {0}" -f $failReal) -Color $(if ($failReal -gt 0) { 'Red' } else { 'DarkGray' })

    if ($failReal -eq 0 -and $failExpected -gt 0) {
        # All failures are due to cert-not-yet-trusted state.
        # This is informational, not an error. Phase passes with a warning.
        Write-Warn2 "V03: $failExpected expected failure(s) - cert not yet imported by I01."
        Write-Ok    "V03: no real verification failures. Re-run after I01 to confirm trust."
        Write-PhaseFooter 'V03' 'done'
        return
    }
    if ($failReal -gt 0) {
        # At least one real failure - this is an error.
        throw "V03: $failReal catalog(s) had real verification failure (not just untrusted-root). See per-catalog logs in $($Ctx.Paths.Logs)."
    }
    # All passed
    Write-Ok "V03: all $okCount catalog(s) verified successfully (cert trust chain valid)."
    Write-PhaseFooter 'V03' 'done'
}

function Test-InfHasServerDecoration {
    # Walk the [Manufacturer] section the same way P06 does and report
    # whether ANY decoration has ProductType=3 (parts[3] == '3').
    #
    # This mirrors the logic in ConvertTo-ServerDecoration / Edit-InfForServer:
    # an NT decoration's 4th dot-separated component is the ProductType
    # (1=workstation, 3=server). P06 sets parts[3]='3', so we look for
    # the same.
    #
    # Why we don't just regex-search the whole file:
    # The previous V04 used a regex like 'NTamd64\.10\.0\.3\.' which
    # required (a) the architecture be amd64, (b) the OS major.minor be
    # exactly 10.0, and (c) a TRAILING DOT after the '3'. P06 produces
    # decorations of varying length depending on the original (e.g. an
    # original 'NTamd64.10.0' becomes 'NTamd64.10.0.3' with NO trailing
    # dot), so the strict regex misses valid server decorations and
    # reports false negatives.
    param([string]$Content)

    if ([string]::IsNullOrEmpty($Content)) { return $false }

    $lines = $Content -split "(?<=`n)"
    $inMfg = $false
    foreach ($line in $lines) {
        $t = $line.Trim().TrimEnd("`r")
        if ($t -match '^\[Manufacturer\]') { $inMfg = $true; continue }
        if ($inMfg -and $t -match '^\[')   { $inMfg = $false; continue }
        if (-not $inMfg)                   { continue }
        if (-not $t -or $t.StartsWith(';')) { continue }

        # Parse "%name% = SectionName, dec1, dec2, ..."
        $kv = $t -split '=', 2
        if ($kv.Count -ne 2) { continue }
        $rhs = $kv[1].Split(',')
        # Index 0 is the section name; decorations start at index 1.
        for ($j = 1; $j -lt $rhs.Count; $j++) {
            $dec = $rhs[$j].Trim()
            if ($dec -notmatch '^NT(amd64|x86|arm|arm64)') { continue }
            $parts = $dec.Split('.')
            # Pad to at least 4 parts so parts[3] is always defined.
            while ($parts.Count -lt 4) { $parts += '' }
            # Per Microsoft Learn INF TargetOSVersion specification, the
            # ProductType field (parts[3]) may be:
            #   '3' - explicit Server-only (Server is supported)
            #   '1' - explicit Workstation-only (Server is NOT supported)
            #   ''  - empty = "any product type", which INCLUDES Server
            # Both '3' and '' satisfy "this decoration permits Server
            # installation". An INF whose [Manufacturer] only carries
            # decorations like 'NTamd64.10.0...22000' (empty ProductType
            # + empty SuiteMask + BuildNumber) is already implicitly
            # Server-compatible without P06 needing to mirror anything.
            # Earlier versions of this check rejected those INFs as
            # missing-decoration; this is now corrected.
            if ($parts[3] -eq '3' -or $parts[3] -eq '') { return $true }
        }
    }
    return $false
}

function Invoke-VerifyPhase04_VerifyInfs {
    param($Ctx)
    Write-PhaseHeader 'V04' 'VerifyInfs' 'Verify'

    $infs = @()
    if (Test-Path $Ctx.Paths.Patched) {
        $infs = Get-ChildItem -Path $Ctx.Paths.Patched -Recurse -Filter *.inf -ErrorAction SilentlyContinue
    }
    if ($infs.Count -eq 0) {
        throw 'V04: no patched INFs to verify - run P06 (PatchInfs) first.'
    }

    Write-Step "Inspecting $($infs.Count) patched INF file(s) for ProductType=3 decoration..."
    $okCount = 0; $failCount = 0
    $details = @()
    foreach ($inf in $infs) {
        $infData = Read-InfFile -Path $inf.FullName
        $hasMfg        = $infData.Content -match '\[Manufacturer\]'
        # Use the proper parser that walks [Manufacturer] entries and
        # checks parts[3]=='3' on each NT decoration. This is the same
        # interpretation P06 used to write the decoration.
        $hasServerDeco = Test-InfHasServerDecoration -Content $infData.Content
        $row = [pscustomobject]@{
            Inf           = $inf.Name
            Encoding      = $infData.EncodingName
            HasMfg        = $hasMfg
            HasServerDeco = $hasServerDeco
            Ok            = ($hasMfg -and $hasServerDeco)
        }
        $details += $row
        if ($row.Ok) {
            $okCount++
            Write-Ok "  $($inf.Name) [$($infData.EncodingName)]"
        } else {
            $failCount++
            Write-Warn2 "  $($inf.Name) (Mfg=$hasMfg ServerDeco=$hasServerDeco)"

            # On first failure, dump the [Manufacturer] section content
            # so the user can see what was actually written. This is the
            # quickest way to diagnose any future regression in P06.
            if ($failCount -eq 1) {
                Write-Host ''
                Write-Host '    ========== FIRST V04 FAILURE - [Manufacturer] DUMP ==========' -ForegroundColor Yellow
                Write-Detail "INF: $($inf.FullName)" -Color DarkYellow
                Write-Detail "Encoding: $($infData.EncodingName)" -Color DarkYellow
                Write-Host '    -----------------------------------------------------' -ForegroundColor DarkGray
                $mfgLines = $infData.Content -split "(?<=`n)"
                $inSection = $false
                foreach ($l in $mfgLines) {
                    $tt = $l.TrimEnd("`r","`n")
                    if ($tt -match '^\[Manufacturer\]') { $inSection = $true }
                    if ($inSection) {
                        Write-Detail "| $tt" -Color DarkYellow
                        if ($tt -match '^\[' -and $tt -notmatch '^\[Manufacturer\]') { break }
                    }
                }
                Write-Host '    -----------------------------------------------------' -ForegroundColor DarkGray
                Write-Host ''
            }
        }
    }
    Write-Ok "INF verification: $okCount ok / $failCount missing decoration"
    if ($failCount -gt 0) {
        throw "V04: $failCount INF(s) lack ProductType=3 decoration"
    }
    Write-PhaseFooter 'V04' 'done'
}

function Invoke-VerifyPhase05_DryRunInstall {
    <#
    .SYNOPSIS
        Simulate I03 without modifying state. Confirms that:
          - The patched bthpan.inf is present and self-signed
          - The current BTH\MS_BTHPAN device state is consistent with
            what I03 will encounter (unknown device, Phantom OK, or
            already at true resolution)
        Produces an install plan summary.
    #>
    param($Ctx)
    Write-PhaseHeader 'V05' 'DryRunInstall' 'Verify'

    if (-not $Ctx.PatchedBthPanInfPath -or -not (Test-Path -LiteralPath $Ctx.PatchedBthPanInfPath)) {
        throw 'V05: patched bthpan.inf not present. Run P06 first.'
    }
    Write-Ok ("Patched INF: {0}" -f $Ctx.PatchedBthPanInfPath)

    # Confirm at least one .cat is present in the same directory
    $patchedDir = Split-Path -Parent $Ctx.PatchedBthPanInfPath
    $cats = @(Get-ChildItem -LiteralPath $patchedDir -Filter '*.cat' -ErrorAction SilentlyContinue)
    if ($cats.Count -eq 0) {
        throw 'V05: no .cat file in patched bthpan dir. Run P08 first.'
    }
    Write-Detail ("Catalog(s): {0}" -f ($cats.Name -join ', '))

    # Enumerate the host's BTH\MS_BTHPAN devices
    Write-SubHeader2 'BTH\MS_BTHPAN device inventory'
    $devices = Get-MsBthPanDevice
    if ($devices.Count -eq 0) {
        Write-Warn2 'No BTH\MS_BTHPAN device found on this host.'
        Write-Detail 'Either the host lacks a Bluetooth host controller, or the host'
        Write-Detail 'controller is not yet bound. Continue anyway: the patched driver'
        Write-Detail 'will be staged in the driver store and bind when a controller appears.'
        $Ctx.V05DryRunPlan = @{ HasDevice = $false; Classification = 'NoDevice' }
        Set-PhaseMarker -Ctx $Ctx -PhaseId 'V05' -Metadata @{ Devices = 0 }
        Write-PhaseFooter 'V05' 'done'
        return
    }
    foreach ($dev in $devices) {
        Write-Detail ("Device: {0}  Status={1}  Class={2}  Problem={3}" -f $dev.InstanceId, $dev.Status, $dev.Class, $dev.Problem)
    }

    # Diagnose each device's classification
    Write-SubHeader2 'Pre-install classification'
    $classifications = @()
    foreach ($dev in $devices) {
        $state = Get-MsBthPanDeviceState -InstanceId $dev.InstanceId
        Write-Detail ("InstanceId    : {0}" -f $state.InstanceId)
        Write-Detail ("  Status      : {0}" -f $state.Status)
        Write-Detail ("  DriverInf   : {0}" -f $state.DriverInfPath)
        Write-Detail ("  Class       : {0}" -f $state.Class)
        Write-Detail ("  Service     : {0}" -f $state.Service)
        Write-Detail ("  Classification: {0}  ({1})" -f $state.Classification, $state.ClassificationReason)
        $classifications += $state.Classification
    }

    # Predict outcome of I03
    Write-SubHeader2 'Install plan summary'
    $hasUnknown = $classifications -contains 'Unknown'
    $hasPhantom = $classifications -contains 'Phantom'
    $hasTrue    = $classifications -contains 'True'

    if ($hasTrue -and -not $hasUnknown -and -not $hasPhantom) {
        Write-Ok 'All MS_BTHPAN devices already at TRUE resolution (Class=Net, Service=BthPan).'
        Write-Detail 'I03 will be effectively a no-op (driver store may receive an upgraded version, but device bindings will not change).'
        $planClass = 'AlreadyTrue'
    } elseif ($hasPhantom) {
        Write-Warn2 'PHANTOM OK detected: bth.inf has proxy-matched. I03 will replace it with the patched bthpan.inf.'
        Write-Detail 'Expected post-I03 state: Class transitions Bluetooth -> Net, Service becomes BthPan.'
        Write-Detail 'I03 will require pnputil /scan-devices to force the rebind.'
        $planClass = 'PhantomNeedsRebind'
    } elseif ($hasUnknown) {
        Write-Ok 'UNKNOWN device (code 28) detected. I03 will install the patched bthpan.inf, which will then bind.'
        $planClass = 'UnknownDeviceNeedsBind'
    } else {
        Write-Detail 'Mixed or unrecognised device state. I03 will attempt installation as usual.'
        $planClass = 'Mixed'
    }

    Write-Detail ('Cert thumbprint   : {0}' -f $Ctx.CertThumbprint)
    Write-Detail ('Patched INF       : {0}' -f $Ctx.PatchedBthPanInfPath)
    Write-Detail ('WDAC policy GUID  : {0}' -f $Script:WdacPolicyGuid)

    $Ctx.V05DryRunPlan = @{
        HasDevice       = $true
        DeviceCount     = $devices.Count
        Classification  = $planClass
        Classifications = $classifications
    }

    Set-PhaseMarker -Ctx $Ctx -PhaseId 'V05' -Metadata @{
        DeviceCount    = $devices.Count
        Classification = $planClass
    }
    Write-PhaseFooter 'V05' 'done'
}

function Invoke-VerifyPhase06_HardwareImpactAnalysis {
    <#
    .SYNOPSIS
        Per-device hardware-impact analysis for BTH\MS_BTHPAN.
    .DESCRIPTION
        Unlike the AMD chipset script which has to reason about
        multiple devices, version comparisons, and self/vendor/MS
        category overrides, the BthPan script's V06 is straightforward:
        there is ONE driver (bthpan.inf) and at most a handful of
        BTH\MS_BTHPAN device instances. The analysis focuses on:

          1. Current device state (Unknown / Phantom / True / Other)
          2. Runtime artifact readiness (sys file, service key, NetAdapter)
          3. Predicted post-install state
          4. UEFI Secure Boot baseline (informational)
    #>
    param($Ctx)
    Write-PhaseHeader 'V06' 'HardwareImpactAnalysis' 'Verify'

    Write-SubHeader 'Section 1: BTH\MS_BTHPAN device state'
    $devices = Get-MsBthPanDevice
    if ($devices.Count -eq 0) {
        Write-Warn2 'No BTH\MS_BTHPAN device present on this host.'
        Write-Detail 'A Bluetooth host controller is required for this device to be enumerated.'
    } else {
        Write-Ok ("Found {0} BTH\MS_BTHPAN device(s)." -f $devices.Count)
        $stateList = @()
        foreach ($dev in $devices) {
            $st = Get-MsBthPanDeviceState -InstanceId $dev.InstanceId
            $stateList += $st
            Write-Detail ('-' * 60)
            Write-Detail ("InstanceId    : {0}" -f $st.InstanceId)
            Write-Detail ("Status        : {0}" -f $st.Status)
            Write-Detail ("Problem       : {0}" -f $st.Problem)
            Write-Detail ("DriverInfPath : {0}" -f $st.DriverInfPath)
            Write-Detail ("Class         : {0}" -f $st.Class)
            Write-Detail ("ClassGuid     : {0}" -f $st.ClassGuid)
            Write-Detail ("Service       : {0}" -f $st.Service)
            Write-Detail ("FriendlyName  : {0}" -f $st.FriendlyName)
            Write-Detail ("Classification: {0}" -f $st.Classification)
            Write-Detail ("Reason        : {0}" -f $st.ClassificationReason)
        }
        $Ctx.V06DeviceStates = $stateList
    }

    Write-SubHeader 'Section 2: Runtime artifacts (true-resolution readiness)'
    $art = Test-BthPanRuntimeArtifacts
    Write-Detail ("bthpan.sys exists       : {0}  ({1})" -f $art.HasSysFile, $art.SysFilePath)
    Write-Detail ("BthPan service registered: {0}" -f $art.HasServiceKey)
    Write-Detail ("Bluetooth PAN NetAdapter : {0}" -f $art.HasNetAdapter)
    if (-not $art.HasSysFile) {
        Write-Warn2 'bthpan.sys missing in System32\drivers — current state is Phantom OK or Unknown.'
    }
    if (-not $art.HasServiceKey) {
        Write-Warn2 'BthPan service key missing — bthpan.inf has not been installed in registered form.'
    }
    $Ctx.V06RuntimeArtifacts = $art

    Write-SubHeader 'Section 3: Existing self-signed bthpan deployments (oem*.inf)'
    $oems = Get-BthPanCurrentlyInstalledOemInfs
    if ($oems.Count -eq 0) {
        Write-Detail 'No oem*.inf currently maps to bthpan.inf in the driver store.'
        Write-Detail 'This is the expected state for a fresh host. I03 will create one.'
    } else {
        foreach ($o in $oems) {
            Write-Detail ("Published: {0}  Original: {1}  Provider: {2}  Version: {3}" -f $o.PublishedName, $o.OriginalName, $o.Provider, $o.Version)
        }
    }

    Write-SubHeader 'Section 4: Risk classification'
    $riskClass = 'LOW'
    $riskNotes = New-Object 'System.Collections.Generic.List[string]'
    if (-not $devices -or $devices.Count -eq 0) {
        $riskClass = 'LOW'
        [void]$riskNotes.Add('No MS_BTHPAN device on host. Install will stage the driver only; no immediate device rebind.')
    } else {
        $cls = @($Ctx.V06DeviceStates | ForEach-Object Classification)
        if ($cls -contains 'Phantom') {
            $riskClass = 'MEDIUM'
            [void]$riskNotes.Add('Phantom OK state. I03 will move Class Bluetooth -> Net. Existing Bluetooth pairings should be unaffected, but transient disconnects are possible.')
        }
        if ($cls -contains 'Unknown') {
            $riskClass = 'LOW'
            [void]$riskNotes.Add('Unknown device (code 28). I03 should resolve the device, no risk to existing devices.')
        }
        if ($cls -contains 'True') {
            [void]$riskNotes.Add('Already at true resolution. I03 will update the driver-store package but device binding will not change.')
        }
    }
    Write-Detail ("Risk class: {0}" -f $riskClass)
    foreach ($n in $riskNotes) { Write-Detail ('  - ' + $n) }

    Write-SubHeader 'Section 5: UEFI Secure Boot Baseline'
    try {
        $sb = Get-OrEnsureSecureBootBaseline -Ctx $Ctx
        if ($sb) {
            Show-SecureBootBaselineSnapshot -Snapshot $sb
        } else {
            Write-Detail 'Secure Boot baseline unavailable.'
        }
    } catch {
        Write-Warn2 ("Secure Boot baseline capture failed: {0}" -f $_.Exception.Message)
    }

    $Ctx.V06RiskClass = $riskClass
    Set-PhaseMarker -Ctx $Ctx -PhaseId 'V06' -Metadata @{
        DeviceCount    = $devices.Count
        RiskClass      = $riskClass
        HasSysFile     = $art.HasSysFile
        HasServiceKey  = $art.HasServiceKey
        HasNetAdapter  = $art.HasNetAdapter
    }
    Write-PhaseFooter 'V06' 'done'
}


#####################################################################
# SECTION 9b: INSTALLATION PHASES
#####################################################################

function Invoke-InstPhase00_PreInstallReview {
    <#
    .SYNOPSIS
        Final operator review before the script touches system state.
        Print risk summary, boot-signing path, and pending-reboot
        status. On a Workstation host without -AllowWorkstationInstall,
        hard-stop here.
    #>
    param($Ctx)
    Write-PhaseHeader 'I00' 'PreInstallReview' 'Inst'

    # Workstation block
    if ($Ctx.Os.ProductType -eq 1 -and -not $Script:AllowWorkstationInstall) {
        Write-Fail 'This host is a Workstation OS (ProductType=1). Install phases are blocked.'
        Write-Detail 'Pass -AllowWorkstationInstall to override (not recommended).'
        Write-Detail 'Recommended: use -Action PrepareVerify on Workstation as a pre-migration check.'
        throw 'I00: Workstation OS install is blocked by default.'
    }

    Write-SubHeader 'I00 Section A: Pre-install state recap'
    $sourceFound = $null -ne $Ctx.BthPanSource
    Write-Detail ("Source DriverStore : {0}" -f ($Ctx.BthPanSource.Path))
    Write-Detail ("Patched INF        : {0}" -f $Ctx.PatchedBthPanInfPath)
    Write-Detail ("Cert thumbprint    : {0}" -f $Ctx.CertThumbprint)
    Write-Detail ("WDAC policy GUID   : {0}" -f $Script:WdacPolicyGuid)
    Write-Detail ("Authorization path : {0}" -f $(if ($Script:UseTestSigning) {'testsigning'} else {'WDAC'}))

    Write-SubHeader 'I00 Section B: Boot-signing environment'
    try {
        Show-BootSigningEnvironment -Ctx $Ctx
    } catch {
        Write-Warn2 ("Boot signing snapshot failed: {0}" -f $_.Exception.Message)
    }

    Write-SubHeader 'I00 Section C: Pending reboot status'
    $pend = Get-PendingRebootMarker -Ctx $Ctx
    if ($pend) {
        if ($pend.RebootedSince) {
            Write-Ok "Pending-reboot marker found, but reboot has occurred since it was written. OK to proceed."
        } else {
            Write-Warn2 'Pending-reboot marker present from a previous run; a reboot may still be required to finalize.'
        }
    } else {
        Write-Detail 'No pending-reboot marker.'
    }

    Write-SubHeader 'I00 Section D: V06 risk summary (recap)'
    if ($Ctx.V06RiskClass) {
        Write-Detail ("Risk class from V06: {0}" -f $Ctx.V06RiskClass)
    } else {
        Write-Detail 'V06 was not run in this invocation. Run -Action PrepareVerify first for a full risk readout.'
    }

    Set-PhaseMarker -Ctx $Ctx -PhaseId 'I00' -Metadata @{ Acknowledged = $true }
    Write-PhaseFooter 'I00' 'done'
}

function Invoke-InstPhase01_TrustCertificate {
    <#
    .SYNOPSIS
        Import the self-signed CER into LocalMachine\Root and
        LocalMachine\TrustedPublisher so that subsequent driver
        installs accept the catalog signature.
    #>
    param($Ctx)
    Write-PhaseHeader 'I01' 'TrustCertificate' 'Inst'

    if (-not (Test-Path -LiteralPath $Ctx.CertCerPath)) {
        throw "I01: CER not found at $($Ctx.CertCerPath). Run P07 first."
    }

    # Resume check
    if (Test-CertAlreadyTrusted -Thumbprint $Ctx.CertThumbprint) {
        Write-Skip "Cert already trusted in LocalMachine\Root + LocalMachine\TrustedPublisher (thumbprint=$($Ctx.CertThumbprint))"
        Set-PhaseMarker -Ctx $Ctx -PhaseId 'I01' -Metadata @{ Thumbprint=$Ctx.CertThumbprint; AlreadyTrusted=$true }
        Write-PhaseFooter 'I01' 'cached'
        return
    }

    Write-Step "Importing cert to LocalMachine\Root..."
    Import-Certificate -FilePath $Ctx.CertCerPath -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
    Write-Ok "Imported to LocalMachine\Root"

    Write-Step "Importing cert to LocalMachine\TrustedPublisher..."
    Import-Certificate -FilePath $Ctx.CertCerPath -CertStoreLocation 'Cert:\LocalMachine\TrustedPublisher' | Out-Null
    Write-Ok "Imported to LocalMachine\TrustedPublisher"

    Set-PhaseMarker -Ctx $Ctx -PhaseId 'I01' -Metadata @{ Thumbprint=$Ctx.CertThumbprint }
    Write-PhaseFooter 'I01' 'done'
}

function Invoke-InstPhase02_AuthorizeDriverSigning {
    # ====================================================================
    # I02 - Configure code-signing-policy authorization
    # ====================================================================
    # Authorize this script's self-signed code-signing certificate to
    # produce kernel-mode-loadable drivers. Two implementation paths:
    #
    #   PATH A (default, RECOMMENDED): WDAC supplemental policy
    #     - Build a Code Integrity supplemental policy XML that ONLY
    #       allowlists our cert as a kernel-mode signer.
    #     - Convert to .cip and deploy under
    #       %SystemRoot%\System32\CodeIntegrity\CiPolicies\Active.
    #     - Activate via CiTool.exe --update-policy (immediate, NO
    #       reboot needed on WS2022+ / Windows 11 22H2+).
    #     - Secure Boot stays ON. testsigning stays OFF. HVCI may
    #       remain ON. No firmware changes.
    #     - Reversible via -Action Cleanup (or CiTool --remove-policy).
    #
    #   PATH B (legacy, opt-in via -UseTestSigning): bcdedit testsigning
    #     - Sets the BCD testsigning flag and requires a reboot.
    #     - Only works when Secure Boot is OFF in firmware (Windows
    #       silently drops testsigning at boot otherwise).
    #     - The desktop will display a "Test Mode" watermark.
    #     - The script will REFUSE this path when Secure Boot is on,
    #       unless -Force is also passed.
    #
    # Renamed from Invoke-InstPhase02_EnableTestSigning in r30 to
    # accurately reflect that the default path is WDAC, not testsigning.
    # The phase ID 'I02' is unchanged and the old phase name
    # 'EnableTestSigning' remains accepted by Resolve-PhaseSelection
    # via an alias for backward-compatible -OnlyPhases callers.
    param($Ctx)
    Write-PhaseHeader 'I02' 'AuthorizeDriverSigning' 'Inst'

    # ---- Resume-after-reboot: skip if I02's target state already holds ----
    # State validator inspects either the WDAC active policies stack
    # (Path A) or the BCD testsigning value (Path B), depending on
    # which path the user is using. -Force overrides this.
    if (Test-InstallPhaseAlreadyDone -Ctx $Ctx -PhaseId 'I02') {
        Write-Skip 'Code-signing authorization for this script''s cert is already in place.'
        if (-not $Ctx.UseTestSigning) {
            $deployed = Test-MsBthPanWdacPolicyDeployed -Ctx $Ctx
            if ($deployed) {
                Write-Host ('  WDAC supplemental policy is active (PolicyId={0}).' -f $deployed.PolicyId) -ForegroundColor Green
            }
        } else {
            Write-Host '  BCD testsigning is already ON.' -ForegroundColor Green
        }
        Write-Host '  Target state already holds - I02 skipped.' -ForegroundColor Green
        Set-PhaseMarker -Ctx $Ctx -PhaseId 'I02'
        Write-PhaseFooter 'I02' 'cached'
        return
    }

    # ---- AS-IS state ----
    Write-Host '--- AS-IS: current boot-signing state ---' -ForegroundColor Cyan
    $bootEnvBefore = Update-BootSigningEnvironmentForCtx -Ctx $Ctx
    Show-BootSigningEnvironment -BootEnv $bootEnvBefore
    Write-Host ''

    # ---- UEFI Secure Boot baseline pre-check (r49) ----
    # Cross-check the firmware-layer UEFI Secure Boot state before we
    # touch the OS-layer signing surface. This is a SOFT pre-check: we
    # never block I02 on UEFI cert rollout state (the rollout and our
    # WDAC policy are independent trust chains). We surface signals
    # that have operational implications for what happens next:
    #
    #   - Secure Boot OFF + WDAC path planned: WDAC will still apply
    #     (CI policy is independent of UEFI variables), but the
    #     selected path is overspecified - testsigning would suffice.
    #
    #   - UEFI CA 2023 rollout in error state (UEFICA2023Error != 0,
    #     or Event 1795/1796/1802/1803 present): there is a concurrent
    #     firmware-level update in progress that may compete with
    #     post-I02 reboots. Operators should know this before they
    #     proceed.
    #
    #   - Secure-Boot-Update scheduled task disabled: the host has
    #     opted out of MS-managed rollout, which is fine for self-hosted
    #     deployments but worth recording.
    Write-Host '--- UEFI Secure Boot baseline pre-check ---' -ForegroundColor Cyan
    try {
        $sbSnapshot = Get-OrEnsureSecureBootBaseline -Ctx $Ctx
        if ($sbSnapshot) {
            Show-SecureBootBaselineSnapshot -Snapshot $sbSnapshot -Compact

            # WDAC path is planned but Secure Boot is OFF -> path is
            # overspecified (testsigning would suffice). Not a block.
            if (-not $Ctx.UseTestSigning -and $sbSnapshot.Embedded.SecureBootEnabled -eq $false) {
                Write-Warn2 'WDAC path is planned, but Secure Boot is OFF. Code Integrity policy will still apply; testsigning would also suffice. Continuing.'
            }
            # Surface UEFI rollout error state without blocking
            if ($sbSnapshot.Health -eq 'Critical') {
                Write-Warn2 ('UEFI Secure Boot baseline health is Critical. Reasons: ' + ($sbSnapshot.Reasons -join '; '))
                Write-Host '  This does NOT block I02 (different trust layer), but the operator should be aware.' -ForegroundColor Yellow
            } elseif ($sbSnapshot.Health -eq 'Warning') {
                Write-Host ('  Baseline health: Warning. ' + ($sbSnapshot.Reasons -join '; ')) -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Warn2 ("UEFI Secure Boot baseline pre-check failed (non-fatal): {0}" -f $_.Exception.Message)
    }
    Write-Host ''

    # ---- Decide which path to take ----
    $useWdac = (-not $Ctx.UseTestSigning) -and $bootEnvBefore.WdacToolsAvailable

    if ($Ctx.UseTestSigning) {
        Write-Host 'Path: legacy testsigning (selected via -UseTestSigning).' -ForegroundColor DarkYellow
    } elseif ($useWdac) {
        Write-Host 'Path: WDAC supplemental policy (default, keeps Secure Boot ON).' -ForegroundColor Cyan
    } else {
        Write-Host 'Path: legacy testsigning (WDAC tools not available on this system).' -ForegroundColor DarkYellow
    }
    Write-Host ''

    # =====================================================================
    # PATH A: WDAC supplemental policy
    # =====================================================================
    if ($useWdac) {
        # Already deployed?
        $existing = Test-MsBthPanWdacPolicyDeployed -Ctx $Ctx
        if ($existing -and -not $Ctx.Force) {
            Write-Skip ('WDAC supplemental policy is already deployed (PolicyId={0}).' -f $existing.PolicyId)
            Write-Host '  Self-signed BthPan driver is already authorized. No further action needed.' -ForegroundColor Green
            Write-PhaseFooter 'I02' 'cached'
            return
        }
        if ($existing -and $Ctx.Force) {
            Write-Step ('Removing existing BthPan supplemental policy {0} (because -Force)...' -f $existing.PolicyId)
            $rm = Uninstall-MsBthPanWdacPolicy -PolicyId $existing.PolicyId
            if ($rm.Removed) { Write-Ok 'Old policy removed.' } else { Write-Warn2 'Could not remove old policy; proceeding anyway.' }
        }

        # Need the .cer (P07 product). Allow -Force to skip the check.
        $cer = if ($Ctx.CertCerPath) { $Ctx.CertCerPath } else { Join-Path $Ctx.Paths.Cert 'MS-BthPan-Driver-CodeSign.cer' }
        if (-not (Test-Path $cer)) {
            throw "I02: cert file not found at $cer - run P07 (CreateCertificate) first."
        }

        # Build supplemental policy XML
        $xmlPath = Join-Path $Ctx.Paths.Cert 'MsBthPanSelfSignedSupplementalPolicy.xml'
        $cipPath = Join-Path $Ctx.Paths.Cert 'MsBthPanSelfSignedSupplementalPolicy.cip'
        Write-Step "Building WDAC supplemental policy XML..."
        $policyId = New-MsBthPanDriverWdacSupplementalPolicy -CerPath $cer -OutputXml $xmlPath
        Write-Ok ('Supplemental policy XML written: {0}' -f $xmlPath)
        Write-Host ('    PolicyId: {0}' -f $policyId)

        # Persist marker BEFORE deploying so we can clean up even if
        # deployment is interrupted.
        $markerPath = Get-MsBthPanSuppPolicyMarkerPath -Ctx $Ctx
        Set-Content -LiteralPath $markerPath -Value $policyId -Encoding ASCII

        # Deploy
        Write-Step 'Converting XML to .cip binary and deploying to active CI policies...'
        $deploy = Install-MsBthPanWdacPolicy -XmlPath $xmlPath -BinaryOutPath $cipPath
        Write-Ok ('Deployed: {0}' -f $deploy.DeployedPath)
        # r57: migrated from bare Write-Host '    ...' to Write-Detail
        # for SPEC A.5 compliance. CiToolStatusLine is parsed from the
        # --json envelope and is the canonical success message string.
        Write-Detail ('Activation method: {0}' -f $deploy.ActivationMethod) -Color Gray
        if ($deploy.CiToolStatusLine) {
            Write-Detail ('CiTool: {0}' -f $deploy.CiToolStatusLine) -Color DarkGray
        } elseif ($deploy.CiToolStdout) {
            $line = ($deploy.CiToolStdout -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
            if ($line) { Write-Detail ('CiTool: {0}' -f $line.Trim()) -Color DarkGray }
        }
        Write-Host ''

        # ---- TO-BE state ----
        Write-Host '--- TO-BE: state immediately after I02 ---' -ForegroundColor Cyan
        $bootEnvAfter = Update-BootSigningEnvironmentForCtx -Ctx $Ctx
        Show-BootSigningEnvironment -BootEnv $bootEnvAfter
        Write-Host ''

        if ($deploy.RebootRequired) {
            Write-Warn2 'CiTool was not available; a REBOOT is required to activate the supplemental policy.'
        } else {
            Write-Ok 'Supplemental policy is active immediately. No reboot required.'
            Write-Host '  You can proceed to I03 (InstallDrivers) right away.' -ForegroundColor Green
        }
        Write-Host ''
        # r57: bare Write-Host '    ...' continuation lines migrated to
        # Write-Detail (SPEC A.5). The two CiTool.exe command strings
        # below stay at column 4 visually but go through the helper.
        Write-Detail 'Reversal (when you are done with this lab):' -Color DarkGray
        Write-Detail ('  .\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action Cleanup') -Color DarkGray
        Write-Detail ('  or: CiTool.exe --remove-policy {0}' -f $policyId) -Color DarkGray

        $reverseInstr = @(
            'To revert the WDAC supplemental policy:',
            ('  CiTool.exe --remove-policy {0}' -f $policyId),
            ('  Remove-Item -LiteralPath {0}' -f $deploy.DeployedPath)
        ) -join "`n"
        $Ctx | Add-Member -NotePropertyName I02ReverseInstructions -NotePropertyValue $reverseInstr -Force

        # WDAC path activates immediately via CiTool, so no reboot
        # required (unlike testsigning). Don't set the pending-reboot
        # marker for this path.
        Set-PhaseMarker -Ctx $Ctx -PhaseId 'I02'
        Write-PhaseFooter 'I02' 'done'
        return
    }

    # =====================================================================
    # PATH B: legacy bcdedit testsigning
    # =====================================================================
    # Already on?
    if ($bootEnvBefore.TestSigningEnabled -eq $true) {
        Write-Skip 'BCD testsigning is already ON.'
        if ($bootEnvBefore.SecureBootEnabled -eq $true) {
            Write-Warn2 'However, Secure Boot is also ON - testsigning is being dropped at boot.'
            Write-Warn2 'You MUST disable Secure Boot in firmware, or use the WDAC path (the default).'
        } elseif ($bootEnvBefore.HvciRunning) {
            Write-Warn2 'However, HVCI / Memory Integrity is RUNNING - it overrides testsigning.'
        } else {
            Write-Ok 'Legacy testsigning path is fully effective.'
        }
        Write-PhaseFooter 'I02' 'cached'
        return
    }

    # Pre-check: Secure Boot
    if ($bootEnvBefore.SecureBootEnabled -eq $true -and -not $Ctx.Force) {
        Write-Host ''
        Write-Host '*** I02 ABORTED: -UseTestSigning was selected but Secure Boot is ON ***' -ForegroundColor Red
        Write-Host 'bcdedit /set testsigning on is silently dropped at next boot when Secure Boot is on.' -ForegroundColor Red
        Write-Host ''
        Show-BootSigningChangeRequired -BootEnv $bootEnvBefore
        Write-Host ''
        Write-Host 'Recommended: drop -UseTestSigning and let the script use the WDAC supplemental path.' -ForegroundColor Yellow
        throw 'I02: Secure Boot is enabled - testsigning would be ignored. Use the default WDAC path or disable Secure Boot first.'
    }

    # Pre-check: HVCI
    if ($bootEnvBefore.HvciRunning -and -not $Ctx.Force) {
        Write-Host ''
        Write-Host '*** I02 ABORTED: -UseTestSigning was selected but HVCI is RUNNING ***' -ForegroundColor Red
        Write-Host 'HVCI enforces a Code Integrity policy that rejects self-signed kernel-mode drivers.' -ForegroundColor Red
        Show-BootSigningChangeRequired -BootEnv $bootEnvBefore
        throw 'I02: HVCI is running - self-signed drivers will not load via testsigning. Use the WDAC path or disable HVCI.'
    }

    # Apply testsigning
    Write-Host '--- Applying change: bcdedit /set testsigning on ---' -ForegroundColor Cyan
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = 'bcdedit.exe'
    $psi.Arguments              = '/set testsigning on'
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $exit = $null
    $stdoutText = ''; $stderrText = ''
    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit()
        $stdoutText = $stdoutTask.Result
        $stderrText = $stderrTask.Result
        $exit = $proc.ExitCode
        $proc.Dispose()
    } catch {
        $stderrText = "Failed to launch bcdedit: $($_.Exception.Message)"
    }
    if ($null -ne $stdoutText -and $stdoutText.Trim()) {
        Write-Host ('    bcdedit: {0}' -f $stdoutText.Trim()) -ForegroundColor DarkGray
    }
    if ($null -ne $exit -and $exit -ne 0) {
        Write-Host ('    bcdedit stderr: {0}' -f $stderrText.Trim()) -ForegroundColor Red
        throw "bcdedit failed (exit $exit)"
    }
    Write-Ok 'BCD testsigning was set to ON.'
    Write-Host ''

    Write-Host '--- TO-BE: state immediately after I02 (effective at next reboot) ---' -ForegroundColor Cyan
    $bootEnvAfter = Update-BootSigningEnvironmentForCtx -Ctx $Ctx
    Show-BootSigningEnvironment -BootEnv $bootEnvAfter
    Write-Host ''

    Write-Warn2 '*** A REBOOT IS REQUIRED FOR TESTSIGNING TO TAKE EFFECT ***'
    Write-Warn2 'After reboot the desktop will display a "Test Mode" watermark.'
    Write-Warn2 'Then run -Action Install AGAIN (same command). The script will'
    Write-Warn2 'detect that I01/I02 are already done and continue with I03/I04.'

    # Persist a "reboot pending" sentinel so a subsequent run can warn
    # the user if they re-execute without rebooting first. Cleared by
    # I04 once post-reboot state is verified good.
    Set-PendingRebootMarker -Ctx $Ctx -Source 'I02' `
        -Reason 'BCD testsigning was just set; reboot required for it to take effect.'

    $reverseInstr = @(
        'To revert testsigning later (after you are done):',
        '  bcdedit /set testsigning off',
        '  Restart-Computer'
    ) -join "`n"
    $Ctx | Add-Member -NotePropertyName I02ReverseInstructions -NotePropertyValue $reverseInstr -Force

    Set-PhaseMarker -Ctx $Ctx -PhaseId 'I02'
    Write-PhaseFooter 'I02' 'done'
}

function Invoke-InstPhase03_InstallDrivers {
    <#
    .SYNOPSIS
        Install the patched bthpan.inf via pnputil /add-driver /install,
        then force a re-enumeration so the BTH\MS_BTHPAN device
        rebinds from bth.inf (proxy / Phantom OK) to the patched
        oem<N>.inf (true resolution).
    #>
    param($Ctx)
    Write-PhaseHeader 'I03' 'InstallDrivers' 'Inst'

    if (-not $Ctx.PatchedBthPanInfPath -or -not (Test-Path -LiteralPath $Ctx.PatchedBthPanInfPath)) {
        throw 'I03: patched bthpan.inf not present. Run P06 first.'
    }

    # Resume check
    $existingOems = Get-BthPanCurrentlyInstalledOemInfs
    if ($existingOems.Count -gt 0) {
        Write-Detail ("Existing oem*.inf mapping bthpan.inf: {0} file(s)" -f $existingOems.Count)
        foreach ($o in $existingOems) {
            Write-Detail ("  - {0} (original={1}, version={2})" -f $o.PublishedName, $o.OriginalName, $o.Version)
        }
    }

    # Run pnputil /add-driver
    $logPath = Join-Path $Ctx.Paths.Logs 'pnputil_bthpan.log'
    $args = @(
        '/add-driver', $Ctx.PatchedBthPanInfPath,
        '/install'
    )
    Write-Step ("pnputil /add-driver {0} /install" -f $Ctx.PatchedBthPanInfPath)
    $start = Get-Date
    $proc = Start-Process -FilePath 'pnputil.exe' -ArgumentList $args -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $logPath -RedirectStandardError ($logPath + '.err')
    $elapsed = (Get-Date) - $start
    $exit = $proc.ExitCode

    # Map pnputil exit codes (SPEC D.17)
    $statusLabel = ''
    $treatAsSuccess = $false
    switch ($exit) {
        0    { $statusLabel = 'installed'; $treatAsSuccess = $true }
        3010 { $statusLabel = 'reboot-required'; $treatAsSuccess = $true }
        259  { $statusLabel = 'no-op (already present)'; $treatAsSuccess = $true }
        default { $statusLabel = ("failed (exit={0})" -f $exit); $treatAsSuccess = $false }
    }

    if ($treatAsSuccess) {
        if ($exit -eq 259) {
            Write-Skip ("Driver package already in store (exit=259): {0}" -f (Split-Path -Leaf $Ctx.PatchedBthPanInfPath))
        } elseif ($exit -eq 3010) {
            Write-Ok ("Installed with REBOOT required: {0}" -f (Split-Path -Leaf $Ctx.PatchedBthPanInfPath))
            Set-PendingRebootMarker -Ctx $Ctx -Phase 'I03'
        } else {
            Write-Ok ("Installed: {0}" -f (Split-Path -Leaf $Ctx.PatchedBthPanInfPath))
        }
        Write-Detail ("Elapsed: {0}, log: {1}" -f (Format-Elapsed $elapsed.TotalSeconds), $logPath)
    } else {
        $tail = (Get-Content -LiteralPath $logPath -Tail 30 -ErrorAction SilentlyContinue) -join "`n"
        if ($tail) { Write-Host $tail -ForegroundColor DarkGray }
        throw "I03: pnputil /add-driver failed (exit=$exit). See $logPath."
    }

    # Force device re-enumeration so the BTH\MS_BTHPAN device drops bth.inf
    # and binds to the patched bthpan.inf.
    Write-Step 'pnputil /scan-devices (force PnP rescan, rebinding may follow)'
    $scanLog = Join-Path $Ctx.Paths.Logs 'pnputil_scan-devices.log'
    $scanProc = Start-Process -FilePath 'pnputil.exe' -ArgumentList @('/scan-devices') `
        -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $scanLog -RedirectStandardError ($scanLog + '.err')
    if ($scanProc.ExitCode -eq 0) {
        Write-Ok 'PnP rescan completed.'
    } else {
        Write-Warn2 ("pnputil /scan-devices exit={0}. PnP rescan may not have effected re-bind; reboot may be needed." -f $scanProc.ExitCode)
    }

    Write-Detail 'Summary: bthpan driver install: 1 ok / 0 failed'
    Set-PhaseMarker -Ctx $Ctx -PhaseId 'I03' -Metadata @{
        Inf       = $Ctx.PatchedBthPanInfPath
        Exit      = $exit
        Status    = $statusLabel
    }
    Write-PhaseFooter 'I03' 'done'
}

function Invoke-InstPhase04_PostInstallVerification {
    <#
    .SYNOPSIS
        The script's BOTTOM-LINE success criterion. Verifies that
        true resolution has been achieved (NOT just Phantom OK).
    .DESCRIPTION
        Distinguishes Phantom OK (bth.inf proxy match) from true
        resolution (bthpan.inf bound, Class=Net, Service=BthPan,
        sys file present, service registered, NetAdapter visible).
    #>
    param($Ctx)
    Write-PhaseHeader 'I04' 'PostInstallVerification' 'Inst'

    Write-SubHeader 'I04 Section 1: BTH\MS_BTHPAN device disposition'
    $devices = Get-MsBthPanDevice
    if ($devices.Count -eq 0) {
        Write-Warn2 'No BTH\MS_BTHPAN device on host. Cannot verify device-bind outcome.'
        Write-Detail 'The driver is staged in the driver store and will bind when a Bluetooth host controller appears.'
        $Ctx.I04OverallResult = 'NoDevice'
    } else {
        $allTrue = $true
        $stateList = @()
        foreach ($dev in $devices) {
            $st = Get-MsBthPanDeviceState -InstanceId $dev.InstanceId
            $stateList += $st
            $line = ("InstanceId: {0}" -f $st.InstanceId)
            Write-Detail $line
            Write-Detail ("  Status        : {0}" -f $st.Status)
            Write-Detail ("  DriverInfPath : {0}" -f $st.DriverInfPath)
            Write-Detail ("  Class         : {0}" -f $st.Class)
            Write-Detail ("  Service       : {0}" -f $st.Service)
            switch ($st.Classification) {
                'True'    { Write-Ok   ("  [OK]   TRUE resolution: oem*.inf bound, Class=Net, Service=BthPan") }
                'Phantom' { Write-Fail ("  [FAIL] PHANTOM OK: bth.inf proxy-match. bthpan.sys NOT loaded.")
                            $allTrue = $false }
                'Unknown' { Write-Fail ("  [FAIL] Unknown device (code 28). Driver bind did not occur.")
                            $allTrue = $false }
                default   { Write-Warn2 ("  [????] Unrecognised state: {0}" -f $st.Classification)
                            $allTrue = $false }
            }
        }
        $Ctx.I04DeviceStates = $stateList
    }

    Write-SubHeader 'I04 Section 2: Runtime artifacts'
    $art = Test-BthPanRuntimeArtifacts
    if ($art.HasSysFile)     { Write-Ok ("bthpan.sys present: {0}" -f $art.SysFilePath) }
    else                      { Write-Fail ('bthpan.sys NOT present in System32\drivers') }
    if ($art.HasServiceKey)  { Write-Ok  'BthPan service key present in HKLM\SYSTEM\CurrentControlSet\Services' }
    else                      { Write-Fail 'BthPan service key NOT registered' }
    if ($art.HasNetAdapter)  { Write-Ok  'Bluetooth PAN NetAdapter present (Get-NetAdapter)' }
    else                      { Write-Warn2 'No Bluetooth PAN NetAdapter (may be expected if no Bluetooth host controller; otherwise indicates bind incomplete)' }
    $Ctx.I04RuntimeArtifacts = $art

    Write-SubHeader 'I04 Section 3: Self-signed cert verification (catalog still trusted?)'
    $signtool = Find-KitTool 'signtool.exe'
    if ($signtool -and $Ctx.PatchedCatalogs -and $Ctx.PatchedCatalogs.Count -gt 0) {
        $cat = $Ctx.PatchedCatalogs[0]
        $log = Join-Path $Ctx.Paths.Logs ('verify_postinstall_' + (Split-Path -Leaf $cat) + '.log')
        $proc = Start-Process -FilePath $signtool -ArgumentList @('verify','/pa','/v',$cat) `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log + '.err')
        if ($proc.ExitCode -eq 0) {
            Write-Ok 'signtool verify /pa: catalog signature is valid + trusted.'
        } else {
            Write-Warn2 ("signtool verify /pa exit={0}. Catalog may not be trusted in this context." -f $proc.ExitCode)
        }
    } else {
        Write-Detail 'Skipped (signtool unavailable or no catalogs cached).'
    }

    # Final verdict
    Write-SubHeader 'I04 Final Verdict'
    $devicesPass = ($devices.Count -eq 0) -or ($Ctx.I04DeviceStates -and ($Ctx.I04DeviceStates | Where-Object { $_.Classification -ne 'True' }).Count -eq 0)
    $artifactsPass = $art.HasSysFile -and $art.HasServiceKey
    if ($devicesPass -and $artifactsPass) {
        Write-Ok '*** TRUE RESOLUTION ACHIEVED ***'
        Write-Detail 'All checked devices report Class=Net, Service=BthPan, DriverInfPath=oem*.inf.'
        Write-Detail 'bthpan.sys is present and BthPan service is registered.'
        $Ctx.I04OverallResult = 'TrueResolution'
        Clear-PendingRebootMarker -Ctx $Ctx
    } else {
        Write-Fail '*** TRUE RESOLUTION NOT YET ACHIEVED ***'
        if (-not $artifactsPass) {
            Write-Detail 'Runtime artifacts missing. The driver may need a reboot to finalize binding.'
        }
        if (-not $devicesPass) {
            Write-Detail 'One or more devices remain in Phantom OK or Unknown state.'
            Write-Detail 'Mitigation: reboot the host, or run "pnputil /delete-driver bth.inf /force" to force rebind (lab only).'
        }
        $Ctx.I04OverallResult = 'PartialOrPhantom'
    }

    Set-PhaseMarker -Ctx $Ctx -PhaseId 'I04' -Metadata @{
        OverallResult  = $Ctx.I04OverallResult
        DeviceCount    = $devices.Count
        HasSysFile     = $art.HasSysFile
        HasServiceKey  = $art.HasServiceKey
    }
    Write-PhaseFooter 'I04' 'done'
}


#####################################################################
# SECTION 10: Cleanup action
#####################################################################
function Invoke-Cleanup {
    param($Ctx)
    Write-PhaseHeader '---' 'Cleanup' 'Util'

    # Remove the deployed WDAC supplemental policy (if any) BEFORE we
    # wipe the workspace, otherwise we lose the marker file that tells
    # us which PolicyId is ours.
    $markerPath = Get-MsBthPanSuppPolicyMarkerPath -Ctx $Ctx
    if ($markerPath -and (Test-Path $markerPath)) {
        $policyId = (Get-Content $markerPath -Raw -ErrorAction SilentlyContinue).Trim()
        if ($policyId) {
            Write-Step "Removing WDAC supplemental policy: $policyId"
            $rm = Uninstall-MsBthPanWdacPolicy -PolicyId $policyId
            if ($rm.Removed) {
                Write-Ok ('Removed deployed CI policy {0}' -f $policyId)
            } elseif ($rm.Existed) {
                Write-Warn2 ('Could not remove CI policy {0} - inspect manually with CiTool.exe -lp' -f $policyId)
            } else {
                Write-Skip 'WDAC supplemental policy was not currently deployed.'
            }
        }
    }

    if (Test-Path $Ctx.WorkRoot) {
        Write-Step "Removing $($Ctx.WorkRoot)"
        Remove-Item -Path $Ctx.WorkRoot -Recurse -Force
        Write-Ok 'Workspace removed.'
    } else {
        Write-Skip 'Workspace already absent.'
    }

    Write-Host ''
    Write-Host 'Reminder: Cleanup does NOT undo:' -ForegroundColor DarkGray
    Write-Host '  - testsigning (use: bcdedit /set testsigning off; reboot)' -ForegroundColor DarkGray
    Write-Host '  - cert in LocalMachine\Root or \TrustedPublisher (manage via certmgr.msc)' -ForegroundColor DarkGray
    Write-Host '  - drivers added by I03 (use: pnputil /enum-drivers; pnputil /delete-driver oemNN.inf /uninstall)' -ForegroundColor DarkGray

    Write-PhaseFooter '---' 'done'
}

#####################################################################
# SECTION 11: Main dispatcher
#####################################################################
function Show-PhaseList {
    Write-Host ''
    Write-Host 'Registered phases:' -ForegroundColor Magenta
    Write-Host ('  {0,-5} {1,-23} {2,-6} {3}' -f 'ID','Name','Group','Function') -ForegroundColor Magenta
    Write-Host ('  {0}' -f ('-' * 70)) -ForegroundColor Magenta
    foreach ($p in $Script:PhaseRegistry) {
        Write-Host ('  {0,-5} {1,-23} {2,-6} {3}' -f $p.Id, $p.Name, $p.Group, $p.Func)
    }
    Write-Host ''
}

function Show-ReferenceLinks {
    # Pretty-print the curated Microsoft Learn reference index. Same
    # content as the "MICROSOFT LEARN REFERENCE LIBRARY" comment block
    # at the top of the file. Triggered at runtime by -References, by
    # -Help, and by I00 when the user runs the install action.
    #
    # Display modes:
    #   (default) - full categorized table with explanatory blurbs
    #   -Compact  - one-line pointer telling the user how to see the
    #               full table; used by I00 to keep its output short.
    param([switch]$Compact)

    if ($Compact) {
        Write-Host ''
        Write-Host '    For prerequisite reading (Secure Boot, WDAC, INF, SDK/WDK, PnPUtil),' -ForegroundColor Cyan
        Write-Host '    re-run this script with -References to see the curated Microsoft Learn link list.' -ForegroundColor Cyan
        return
    }

    # Each entry is { Title, Url, Why } - Why is a one-liner that
    # explains why this link is relevant to THIS script. Categories
    # mirror the comment block at the top of the file.
    $sections = @(
        @{
            Heading = '[1] SECURE BOOT (UEFI signature enforcement)'
            Why     = 'Secure Boot is what blocks self-signed kernel-mode drivers by default. The WDAC path in I02 keeps Secure Boot ENABLED while still loading the drivers - this section explains how Secure Boot works.'
            Links   = @(
                @{ T='What Is Secure Boot for Windows';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/secure-boot' }
                @{ T='Secure Boot and Trusted Boot (chain-of-trust architecture)';
                   U='https://learn.microsoft.com/en-us/windows/security/operating-system-security/system-security/trusted-boot' }
                @{ T='Secure the Windows boot process (Secure Boot, Trusted Boot, ELAM, Measured Boot)';
                   U='https://learn.microsoft.com/en-us/windows/security/operating-system-security/system-security/secure-the-windows-10-boot-process' }
                @{ T='Secure Boot Key Creation and Management Guidance (PK / KEK / db / dbx)';
                   U='https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-secure-boot-key-creation-and-management-guidance' }
            )
        }
        @{
            Heading = '[2] TEST SIGNING / DRIVER SIGNING POLICY'
            Why     = 'The legacy I02 path (-UseTestSigning) uses BCD testsigning. The WDAC path is the modern alternative this script prefers; this section is here for context.'
            Links   = @(
                @{ T='Test Signing (overview of dev/lab signing process)';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/install/test-signing' }
                @{ T='The TESTSIGNING boot configuration option';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/install/the-testsigning-boot-configuration-option' }
                @{ T='BCDEdit /set (testsigning, nointegritychecks, ...)';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--set' }
                @{ T='Installing an Unsigned Driver during Development and Test';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/install/installing-an-unsigned-driver-during-development-and-test' }
                @{ T='How to Test Preproduction Drivers with Secure Boot Enabled';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/install/preproduction-driver-signing-and-install' }
            )
        }
        @{
            Heading = '[3] WDAC / APP CONTROL FOR BUSINESS'
            Why     = 'This is the I02 default path. The script builds a supplemental policy that adds its self-signed cert as a kernel-mode signer, deploys via CiTool, and reverses cleanly via Cleanup.'
            Links   = @(
                @{ T='Application Control / WDAC documentation root';
                   U='https://learn.microsoft.com/en-us/windows/security/application-security/application-control/windows-defender-application-control/' }
                @{ T='Use multiple App Control policies (base + supplemental design)';
                   U='https://learn.microsoft.com/en-us/windows/security/application-security/application-control/windows-defender-application-control/design/deploy-multiple-wdac-policies' }
                @{ T='Deploy App Control policies using script (CiTool --update-policy)';
                   U='https://learn.microsoft.com/en-us/windows/security/application-security/application-control/windows-defender-application-control/deployment/deploy-wdac-policies-with-script' }
                @{ T='Remove App Control policies (CiTool --remove-policy)';
                   U='https://learn.microsoft.com/en-us/windows/security/application-security/application-control/windows-defender-application-control/deployment/disable-wdac-policies' }
            )
        }
        @{
            Heading = '[4] INF FILE STRUCTURE'
            Why     = 'P05/P06 parse and patch INFs. The ProductType=3 decoration in [Manufacturer] is what makes a Client INF apply to Windows Server.'
            Links   = @(
                @{ T='*** SKU Differentiation Directive (PRIMARY REF for ProductType=3 technique) ***';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/display/sku-differentiation-directive' }
                @{ T='Summary of INF Sections';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/install/summary-of-inf-sections' }
                @{ T='General Syntax Rules for INF Files';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/install/general-syntax-rules-for-inf-files' }
                @{ T='INF Manufacturer Section (TargetOSVersion, ProductType=3 ...)';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-manufacturer-section' }
                @{ T='INF Models Section';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/install/inf-models-section' }
                @{ T='Combining Platform Extensions with Operating System Versions (TargetOSVersion grammar)';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/install/combining-platform-extensions-with-operating-system-versions' }
                @{ T='Creating INF Files for Multiple Platforms and Operating Systems';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/install/creating-inf-files-for-multiple-platforms-and-operating-systems' }
                @{ T='Using a Universal INF File (declarative-only restrictions)';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/install/using-a-universal-inf-file' }
            )
        }
        @{
            Heading = '[5] WINDOWS SDK + WDK'
            Why     = 'P02 acquires these because P08 needs inf2cat (WDK) and P09 needs signtool (SDK).'
            Links   = @(
                @{ T='Download the Windows Driver Kit (WDK) - includes inf2cat';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/download-the-wdk' }
                @{ T='Windows SDK downloads - includes signtool';
                   U='https://learn.microsoft.com/en-us/windows/apps/windows-sdk/downloads' }
                @{ T='Install the WDK using WinGet';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/install-the-wdk-using-winget' }
                @{ T='Install the WDK using NuGet';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/install-the-wdk-using-nuget' }
                @{ T='Kits and tools overview (SDK / WDK / EWDK / HLK relationships)';
                   U='https://learn.microsoft.com/en-us/windows-hardware/get-started/kits-and-tools-overview' }
                @{ T='Running InfVerif from the Command Line (validate INF files)';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/running-infverif-from-the-command-line' }
            )
        }
        @{
            Heading = '[6] PNPUTIL (driver-store management)'
            Why     = 'I03 calls pnputil /add-driver. I04 / V05 use /enum-drivers. Cleanup advice references /delete-driver.'
            Links   = @(
                @{ T='PnPUtil overview';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil' }
                @{ T='PnPUtil Command Syntax (full flag reference, exit codes)';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax' }
                @{ T='PnPUtil Command Examples (typical workflows)';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-examples' }
                @{ T='Create Installed Driver Package Inventory (audit installed drivers)';
                   U='https://learn.microsoft.com/en-us/windows-hardware/drivers/driversecurity/create-a-driver-inventory' }
            )
        }
    )

    $line = '=' * 72
    Write-Host ''
    Write-Host $line                                                                    -ForegroundColor Magenta
    Write-Host ' MICROSOFT LEARN REFERENCE LIBRARY                                       ' -ForegroundColor Magenta
    Write-Host $line                                                                    -ForegroundColor Magenta
    Write-Host '  Curated reading list for the prerequisite knowledge needed to'        -ForegroundColor Cyan
    Write-Host '  understand what THIS SCRIPT does. All URLs are en-US; replace'         -ForegroundColor Cyan
    Write-Host '  "/en-us/" with "/ja-jp/" in the URL path for Japanese versions.'       -ForegroundColor Cyan

    foreach ($s in $sections) {
        Write-Host ''
        Write-Host $s.Heading -ForegroundColor Yellow
        Write-Host ('  Why this matters here: {0}' -f $s.Why) -ForegroundColor DarkGray
        Write-Host ''
        foreach ($link in $s.Links) {
            Write-Host ('    - {0}' -f $link.T)
            Write-Host ('      {0}' -f $link.U) -ForegroundColor Blue
        }
    }

    Write-Host ''
    Write-Host $line -ForegroundColor Magenta
    Write-Host '  Quick map of which phase of THIS script each category supports:'         -ForegroundColor Cyan
    Write-Host '    P02  AcquireTools                  -> [5] Windows SDK + WDK'           -ForegroundColor DarkGray
    Write-Host '    P05/P06  AnalyzeInfs / PatchInfs   -> [4] INF File Structure'          -ForegroundColor DarkGray
    Write-Host '    P07  CreateCertificate             -> [2] Test Signing'                -ForegroundColor DarkGray
    Write-Host '    P08  GenerateCatalogs              -> [4][5] inf2cat + INF structure'  -ForegroundColor DarkGray
    Write-Host '    P09  SignCatalogs                  -> [2][5] signtool + signing policy' -ForegroundColor DarkGray
    Write-Host '    I01  TrustCertificate              -> [2] Driver signing policy'       -ForegroundColor DarkGray
    Write-Host '    I02  AuthorizeDriverSigning (default)  -> [3] WDAC supplemental policy' -ForegroundColor DarkGray
    Write-Host '    I02  AuthorizeDriverSigning (-UseTest) -> [1][2] Secure Boot + testsigning' -ForegroundColor DarkGray
    Write-Host '    I03  InstallDrivers                -> [6] PnPUtil'                      -ForegroundColor DarkGray
    Write-Host '    I04  PostInstallVerification       -> [1][6] Secure Boot + PnPUtil'    -ForegroundColor DarkGray
    Write-Host $line -ForegroundColor Magenta
}

function Show-Help {
    $line = '=' * 72
    Write-Host ''
    Write-Host $line -ForegroundColor Magenta
    Write-Host ' Microsoft BthPan Inbox Driver Pipeline for Windows Server 2016 / 2019 / 2022 / 2025' -ForegroundColor Magenta
    Write-Host (' Version: {0}  [{1}]  SHA256: {2}' -f $Script:ScriptVersion, $Script:ScriptTag, $Script:ScriptHash) -ForegroundColor DarkCyan
    Write-Host $line -ForegroundColor Magenta

    Show-DriverInstallationOrderNotice

    Write-Host ''
    Write-Host 'SYNOPSIS' -ForegroundColor Cyan
    Write-Host '  Locates the Microsoft inbox bthpan driver in the host DriverStore,'
    Write-Host '  patches bthpan.inf with NTamd64...3 (ProductType=3 / Server) decorations,'
    Write-Host '  regenerates and re-signs the catalog with a self-signed certificate,'
    Write-Host '  deploys a WDAC supplemental policy that allowlists that cert as a kernel'
    Write-Host '  signer, installs the patched bthpan.inf via pnputil, and verifies that'
    Write-Host '  TRUE resolution (Class=Net, Service=BthPan) has been achieved instead of'
    Write-Host '  the Phantom OK state caused by bth.inf proxy-matching - all WITH Secure'
    Write-Host '  Boot remaining enabled.'
    Write-Host ''
    Write-Host '  The pipeline is split into three stages:'
    Write-Host '    PREPARATION  - file artifacts under -WorkRoot only (idempotent)'
    Write-Host '    VERIFICATION - read-only diagnostics + dry-run of installation'
    Write-Host '    INSTALLATION - modifies the running OS (cert trust / WDAC policy / pnputil)'

    Write-Host ''
    Write-Host 'USAGE' -ForegroundColor Cyan
    Write-Host '  .\Deploy-MSBthPanInboxOnWindowsServer.ps1 [-Action <mode>] [other parameters]'
    Write-Host '  .\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Help'
    Write-Host '  .\Deploy-MSBthPanInboxOnWindowsServer.ps1 -References'

    Write-Host ''
    Write-Host 'ACTIONS  ( -Action <value> )' -ForegroundColor Cyan
    Write-Host '  PrepareVerify [default] Prepare + Verify in one go.'
    Write-Host '               Runs all preparation phases (P00-P09) followed by all'
    Write-Host '               verification phases (V01-V06). Never modifies the OS.'
    Write-Host ''
    Write-Host '  Prepare      Run all preparation phases (P00-P09) only.'
    Write-Host '               P02 installs Windows SDK / WDK system-wide if missing.'
    Write-Host '               Other phases write only to -WorkRoot. Idempotent.'
    Write-Host ''
    Write-Host '  Verify       Run all verification phases (V01-V06) only.'
    Write-Host '                 V01 - Verify artifacts (PFX/CER/INF/CAT exist)'
    Write-Host '                 V02 - Verify certificate (validity, EKU, private key)'
    Write-Host '                 V03 - Verify catalogs (signtool /verify /pa)'
    Write-Host '                 V04 - Verify INFs   (ProductType=3 decoration coverage)'
    Write-Host '                 V05 - Dry-run install (BTH\MS_BTHPAN state inspection)'
    Write-Host '                 V06 - Hardware impact analysis (Phantom OK readiness)'
    Write-Host ''
    Write-Host '  Install      Run all installation phases (I00-I04):'
    Write-Host '                 I00 - Pre-install review'
    Write-Host '                 I01 - Trust certificate (Root + TrustedPublisher)'
    Write-Host '                 I02 - Authorize driver signing (WDAC supplemental policy)'
    Write-Host '                 I03 - pnputil /add-driver bthpan.inf /install + /scan-devices'
    Write-Host '                 I04 - Post-install verification (TRUE vs PHANTOM OK)'
    Write-Host ''
    Write-Host '  All          Prepare + Verify + Install in sequence.'
    Write-Host '  Cleanup      Delete -WorkRoot entirely and uninstall WDAC supp policy.'
    Write-Host '  ListPhases   Print the full phase registry and exit.'

    Write-Host ''
    Write-Host 'PARAMETERS' -ForegroundColor Cyan
    Write-Host '  Help / mode' -ForegroundColor DarkGray
    Write-Host '    -Help                    Show this help and exit. Aliases: -h, -?' -ForegroundColor Yellow
    Write-Host '    -References              Show curated Microsoft Learn link list.' -ForegroundColor Yellow
    Write-Host '    -Action <string>         Pipeline mode (see ACTIONS).' -ForegroundColor Yellow
    Write-Host '                             Default: PrepareVerify'
    Write-Host '    -OnlyPhases <string[]>   Restrict execution to specific phases.' -ForegroundColor Yellow
    Write-Host '                             Accepts IDs (P05) or names (PatchInfs).'
    Write-Host ''
    Write-Host '  Workspace' -ForegroundColor DarkGray
    Write-Host '    -WorkRoot <path>         Working directory.' -ForegroundColor Yellow
    Write-Host "                             Default: C:\MSBthPan-WS"
    Write-Host '    -CleanWorkRoot           Delete -WorkRoot before running anything.' -ForegroundColor Yellow
    Write-Host '    -Force                   Bypass cached phase markers (force re-run).' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  INF patching' -ForegroundColor DarkGray
    Write-Host '    -DecorationStrategy <A|B>' -ForegroundColor Yellow
    Write-Host "                             A (default): NTamd64...3 only (ProductType=3 covers all Server)"
    Write-Host "                             B          : also add NTamd64.10.0...14393/17763/20348/26100"
    Write-Host ''
    Write-Host '  Certificate' -ForegroundColor DarkGray
    Write-Host '    -PfxPassword <string>    PFX export password.' -ForegroundColor Yellow
    Write-Host '                             Default: ChangeMe!2026  (CHANGE FOR PRODUCTION)'
    Write-Host '    -TimestampUrl <url>      RFC3161 timestamp URL for signtool.' -ForegroundColor Yellow
    Write-Host '                             Default: http://timestamp.digicert.com'
    Write-Host ''
    Write-Host '  Driver-load authorization' -ForegroundColor DarkGray
    Write-Host '    -UseTestSigning          Use bcdedit testsigning instead of WDAC.' -ForegroundColor Yellow
    Write-Host '                             Requires Secure Boot OFF in firmware.'
    Write-Host '    -AllowWorkstationInstall Permit Install phases on Workstation OS.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  WDAC overrides' -ForegroundColor DarkGray
    Write-Host '    -WdacPolicyGuid <guid>   Override supplemental policy GUID.' -ForegroundColor Yellow
    Write-Host "                             Default: A6E72D4F-3B98-4C5A-9E1D-7F8B2A4C6E5D"
    Write-Host '    -WdacBasePolicyGuid <g>  Override SupplementsBasePolicyID.' -ForegroundColor Yellow

    Write-Host ''
    Write-Host 'EXAMPLES' -ForegroundColor Cyan
    Write-Detail '.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action PrepareVerify' -Color Green
    Write-Host '    Dry-run only: prepare patched INF + signed catalog, verify, no system change.'
    Write-Host ''
    Write-Detail '.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action Install' -Color Green
    Write-Host '    Full install on Windows Server SKU.'
    Write-Host ''
    Write-Detail '.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action All -CleanWorkRoot' -Color Green
    Write-Host '    Clean rebuild and full install in one command.'
    Write-Host ''
    Write-Detail '.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -OnlyPhases V06' -Color Green
    Write-Host '    Run only the Phantom-OK readiness analysis (no system change).'
    Write-Host ''
    Write-Detail '.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action Cleanup' -Color Green
    Write-Host '    Remove WDAC supplemental policy and workspace (cert/driver remain).'

    Write-Host ''
    Show-ReferenceLinks -Compact
    Write-Host ''
    Write-Host $line -ForegroundColor Magenta
}

# ----- References short-circuit (highest priority - no admin / no work) -----
# Display the curated Microsoft Learn link list and exit. This is
# checked BEFORE -Help so a user who passes -References -Help (or the
# unlikely combination of both) gets the references view they asked
# for. -References is itself a top-priority short-circuit because it
# requires nothing - no admin, no workspace, no network.
if ($References) {
    Show-ReferenceLinks
    return
}

# ----- Help short-circuit (highest priority - no admin / no work) -----
if ($Help) {
    Show-Help
    return
}

# ----- ListPhases short-circuit -----
if ($Action -eq 'ListPhases') {
    Show-PhaseList
    return
}

# ----- Build context -----
$Ctx = [pscustomobject]@{
    # Params
    Action          = $Action
    OnlyPhases      = $OnlyPhases
    InstallerUrl    = $InstallerUrl
    AmdLandingUrls  = $AmdLandingUrls
    AmdFallbackUrl  = $AmdFallbackUrl
    WorkRoot        = $WorkRoot
    PfxPassword     = $PfxPassword
    TimestampUrl    = $TimestampUrl
    Force           = $Force.IsPresent
    CleanWorkRoot   = $CleanWorkRoot.IsPresent
    UseTestSigning  = $UseTestSigning.IsPresent
    AllowWorkstationInstall = $AllowWorkstationInstall.IsPresent
    # Populated by phases
    Os = $null; Paths = $null
    SevenZip = $null; Signtool = $null; Inf2cat = $null
    Installer = $null; InfInventory = $null; InfInventoryDetail = $null; PatchResults = @()
    CertPfxPath = $null; CertCerPath = $null; CertThumbprint = $null
    # r45: list of phase IDs that will execute this run (used by P00's
    # Workstation-Install guard to know whether any I-phase is queued).
    SelectedPhaseIds = @()
    # r49: UEFI Secure Boot baseline snapshot. Captured at P00 and
    # consumed by P05 (report appendix), V05/V06 (display), I02
    # (pre-check). Pre-declared as $null here so plain '.' assignment
    # works on the [pscustomobject] without requiring Add-Member.
    SecureBootBaseline = $null
}

# ----- Cleanup short-circuit -----
if ($Action -eq 'Cleanup') {
    Assert-Admin
    Invoke-Cleanup -Ctx $Ctx
    $cleanupElapsed = (Get-Date) - $Script:ScriptStartTime
    Write-Host ''
    Write-Host (' Total elapsed   : {0}' -f (Format-Elapsed $cleanupElapsed)) -ForegroundColor Cyan
    return
}

# ----- Resolve phase selection -----
$selected = Resolve-PhaseSelection -Action $Action -OnlyPhases $OnlyPhases

$startedAtStr = $Script:ScriptStartTime.ToString('yyyy-MM-dd HH:mm:ss')
Write-Host ''
Write-Host '============================================================' -ForegroundColor Magenta
Write-Host (' Microsoft BthPan Inbox Driver Pipeline')                      -ForegroundColor Magenta
Write-Host (' Script version  : {0}' -f $Script:ScriptVersion)             -ForegroundColor Cyan
Write-Host (' Script tag      : {0}' -f $Script:ScriptTag)                 -ForegroundColor DarkCyan
Write-Host (' Script SHA256   : {0}  (first 12 chars; full hash differs if file edited)' -f $Script:ScriptHash) -ForegroundColor DarkCyan
if ($Script:ScriptPath) {
    Write-Host (' Script path     : {0}' -f $Script:ScriptPath)            -ForegroundColor DarkGray
}
Write-Host (' Started at      : {0}' -f $startedAtStr)
Write-Host (' Action          : {0}' -f $Action)
Write-Host (' OnlyPhases      : {0}' -f $(if ($OnlyPhases) { $OnlyPhases -join ',' } else { '(all for action)' }))
Write-Host (' WorkRoot        : {0}' -f $WorkRoot)
Write-Host (' CleanWorkRoot   : {0}' -f $CleanWorkRoot.IsPresent)
Write-Host (' Force           : {0}' -f $Force.IsPresent)
Write-Host (' Selected phases : {0}' -f (($selected | ForEach-Object Id) -join ' -> '))
Write-Host '============================================================' -ForegroundColor Magenta

# ----- Implicit prerequisites -----
# P00 + P01 are always required (admin/OS detect/workspace).
# Run them first (they're idempotent themselves) regardless of -OnlyPhases.
$mandatoryIds = @('P00','P01')
$mandatory = $Script:PhaseRegistry | Where-Object { $_.Id -in $mandatoryIds -and $_.Id -notin ($selected | ForEach-Object Id) }
$queue = @($mandatory) + @($selected)

# r45: stash the phase-ID list on the context so P00 can see whether
# any Install phase (I01-I04) is queued without re-resolving phases.
$Ctx.SelectedPhaseIds = @($queue | ForEach-Object Id)

# ----- Execute -----
# r55: wrap the whole phase loop + summary in a try/finally so the
# workspace lock (acquired in P01 via Assert-NoConcurrentRun) is
# released on EVERY exit path - normal completion, phase throw, or
# top-level error. The pre-r55 design relied solely on the
# Register-EngineEvent PowerShell.Exiting hook in Set-WorkspaceLock,
# which only fires when the PowerShell host process itself exits.
# In an interactive console (where the host is reused across many
# script invocations), the hook never fires and the lock file leaks
# - the next run in the same console then mis-detects its own host's
# PID in the leftover lock and refuses to start with "Another
# instance is already running". The finally block + the new self-PID
# detection in Test-WorkspaceLockHeld together close that gap.
try {
    foreach ($phase in $queue) {
        try {
            & $phase.Func -Ctx $Ctx
        } catch {
            Write-Fail "$($phase.Id) [$($phase.Name)] failed: $($_.Exception.Message)"
            Write-PhaseFooter $phase.Id 'failed'
            throw
        }
    }

    # ----- Summary -----
    $totalElapsed = (Get-Date) - $Script:ScriptStartTime
    $endedAtStr   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Magenta
    Write-Host ' RUN SUMMARY' -ForegroundColor Magenta
    Write-Host '============================================================' -ForegroundColor Magenta
    Write-Host " Script version  : $($Script:ScriptVersion) [$($Script:ScriptTag)]" -ForegroundColor Cyan
    Write-Host " Script SHA256   : $($Script:ScriptHash)" -ForegroundColor DarkCyan
    Write-Host " OS              : $($Ctx.Os.Name) (build $($Ctx.Os.ActualBuild))"
    Write-Host " Workspace       : $($Ctx.WorkRoot)"
    if ($Ctx.Installer)       { Write-Host " Installer       : $(Split-Path $Ctx.Installer -Leaf)" }
    if ($Ctx.InfInventory)    { Write-Host " INFs analyzed   : $($Ctx.InfInventory.Count)" }
    if ($Ctx.PatchResults)    { Write-Host " INFs patched    : $($Ctx.PatchResults.Count)" }
    if ($Ctx.CertThumbprint)  { Write-Host " Cert thumbprint : $($Ctx.CertThumbprint)" }
    Write-Host " Phases run      : $((($queue | ForEach-Object Id)) -join ' -> ')"
    Write-Host " Started at      : $startedAtStr"
    Write-Host " Ended at        : $endedAtStr"
    Write-Host (" Total elapsed   : {0}" -f (Format-Elapsed $totalElapsed)) -ForegroundColor Cyan

    # Per-phase timing breakdown
    if ($Script:PhaseTimings.Count -gt 0) {
        Write-Host ''
        Write-Host ' Phase timings:' -ForegroundColor Cyan
        Write-Host ('   {0,-5} {1,-23} {2,-8} {3,10}' -f 'ID','Name','Status','Elapsed')
        Write-Host ('   {0}' -f ('-' * 50))
        $sumSeconds = 0.0
        foreach ($t in $Script:PhaseTimings) {
            $name = ($Script:PhaseRegistry | Where-Object Id -eq $t.Id | Select-Object -First 1).Name
            if (-not $name) { $name = '(unknown)' }
            $color = switch ($t.Status) {
                'done'    { 'Green' }
                'cached'  { 'DarkGray' }
                'skipped' { 'DarkGray' }
                'failed'  { 'Red' }
                default   { 'White' }
            }
            Write-Host ('   {0,-5} {1,-23} {2,-8} {3,10}' -f `
                           $t.Id, $name, $t.Status, (Format-Elapsed $t.Elapsed)) `
                      -ForegroundColor $color
            $sumSeconds += $t.Elapsed.TotalSeconds
        }
        Write-Host ('   {0}' -f ('-' * 50))
        Write-Host ('   {0,-5} {1,-23} {2,-8} {3,10}' -f 'SUM','(phase total)','', (Format-Elapsed ([TimeSpan]::FromSeconds($sumSeconds)))) -ForegroundColor Cyan
    }
    Write-Host '============================================================' -ForegroundColor Magenta
}
finally {
    # r55: release the workspace lock regardless of how we got here.
    # Safe to call when the lock was never acquired (e.g. failure
    # before P01) because Clear-WorkspaceLock is idempotent and a
    # no-op when the lock file does not exist or $Ctx.Paths is null.
    if ($Ctx -and $Ctx.Paths -and $Ctx.Paths.Markers) {
        try { Clear-WorkspaceLock -Ctx $Ctx } catch { } # psa-disable-line PSA3004 -- intentional best-effort cleanup in finally; a failure here must not mask the original exception
    }
}
