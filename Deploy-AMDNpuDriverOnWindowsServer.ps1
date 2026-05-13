<#
.SYNOPSIS
    Patches and installs the AMD NPU (Ryzen AI XDNA) kernel-mode driver on Windows Server 2025.

.DESCRIPTION
    PowerShell pipeline that makes the AMD consumer-targeted Ryzen AI NPU driver installable
    on Windows Server 2025 by patching the INF ProductType decoration and re-signing the
    catalog with a self-generated certificate.

    Companion to:
      - Deploy-AMDChipsetDriverOnWindowsServer.ps1 (r47)
      - Deploy-AMDGraphicsDriverOnWindowsServer.ps1 (r16)

    Architecture: same 21-phase pipeline (P00-P09 prep, V01-V06 verify, I00-I04 install).

    NPU-SPECIFIC NOTES vs the chipset and graphics sister scripts:
      - Distribution format: ZIP (not EXE) - extracted with 7-Zip (same tooling as
        chipset / graphics sister scripts; uses 7z.exe x for consistent behaviour)
      - URL resolution: 4-tier fallback
          (1) -InstallerUrl explicit URL
          (2) AMD account credential auto-download (-AmdAccountUser / -AmdAccountPassword)
          (3) AMD EULA-gated direct fetch probe
          (4) Local cache (-OfflineZip or sibling .zip)
      - Hardware detection: pnputil PCI HWID + REV byte parsing (PHX/HPT/STX/KRK)
      - NPU driver versioning is INDEPENDENT from Ryzen AI Software versioning.
        Per AMD docs (https://ryzenai.docs.amd.com/en/latest/inst.html, 2026-04-19):
          NPU drivers   : 32.0.203.280 (NPU_RAI1.5_280) or 32.0.203.314 (NPU_RAI1.6.1_314)
          RAI Software  : 1.7.1 (latest, ryzen-ai-lt-1.7.1.exe)
      - Default-when-undetected: Strix Point + NPU driver 32.0.203.314 + RAI Software latest
      - Out of scope: Ryzen AI Software user-mode stack (Python conda env, OGA, VAI EP)
        Users must install Ryzen AI Software separately - guidance provided at end of run.

    SUPPORTED NPU GENERATIONS:
      Phoenix    (PHX) PCI\VEN_1022&DEV_1502&REV_00  Ryzen 7040 series        RAI <= 1.5
      Hawk Point (HPT) PCI\VEN_1022&DEV_1502&REV_00  Ryzen 8040 series        RAI <= 1.5
      Strix      (STX) PCI\VEN_1022&DEV_17F0&REV_00/10/11  Ryzen AI 300       RAI 1.5+
      Strix Halo (STX) PCI\VEN_1022&DEV_17F0&REV_*  Ryzen AI Max 300          RAI 1.5+
      Krackan    (KRK) PCI\VEN_1022&DEV_17F0&REV_20  Ryzen AI 200             RAI 1.6.1+

.PARAMETER Action
    The pipeline action: PrepareVerify (P00-V06), Prepare (P00-P09), Verify (V01-V06),
    Install (I00-I04 after Prepare+Verify), Cleanup (remove cert/policy/drivers/workspace),
    or ListPhases (show phase ID table and exit).

.PARAMETER OnlyPhases
    Comma-separated list of phase IDs to run (e.g. "P05,P06,P08,P09"). When specified,
    only listed phases execute; useful for re-runs after manual edits.

.PARAMETER InstallerUrl
    Explicit URL to download the NPU driver ZIP. Bypasses URL resolution (Tier 1).

.PARAMETER OfflineZip
    Path to a pre-downloaded NPU driver ZIP. Bypasses URL resolution and download (Tier 4).

.PARAMETER AmdAccountUser
    AMD account username/email for auto-download via account.amd.com login (Tier 2).
    When combined with -AmdAccountPassword, the script attempts to authenticate, accept
    the Ryzen AI EULA, and download the driver ZIP automatically.

.PARAMETER AmdAccountPassword
    AMD account password (SecureString). Required if -AmdAccountUser is specified.

.PARAMETER ForceAmdAccountAuth
    Force the script to attempt the AMD account form-based authentication flow (Tier 2).
    Disabled by default since 2026-05-10 verification confirmed account.amd.com is a
    JavaScript-driven SPA that does not respond to PowerShell HTTP form POSTs. Use only
    if AMD has updated their portal or you have evidence the flow can succeed. Manual
    download via -OfflineZip <path> is the recommended pattern.

.PARAMETER NpuOverride
    Force a specific NPU codename: PHX, HPT, STX, or KRK. Useful when detection is
    ambiguous (e.g. Phoenix vs Hawk Point share the same PCI HWID).

.PARAMETER NpuDriverPackage
    Selects which NPU kernel-mode driver package to use. The NPU driver versioning is
    INDEPENDENT from the Ryzen AI Software (user-mode stack) versioning per AMD's
    official documentation at https://ryzenai.docs.amd.com/en/latest/inst.html.

      'NPU_RAI1.5_280'    : NPU driver 32.0.203.280 (older, Phoenix/Hawk Point/Strix/STH/KRK)
      'NPU_RAI1.6.1_314'  : NPU driver 32.0.203.314 (newer, same NPU coverage)
      'latest' (default)  : NPU_RAI1.6.1_314 (the latest documented in AMD docs)

    AMD documents both 280 and 314 as valid drivers for current Ryzen AI Software (1.7.1).
    Pick 'NPU_RAI1.5_280' only if your offline ZIP is the older one.

.PARAMETER RyzenAiSoftwareVersion
    Selects which Ryzen AI Software (user-mode stack) installer to recommend in the
    post-install guidance message. This is INDEPENDENT from -NpuDriverPackage.

      '1.5' / '1.6.1' / '1.7' / '1.7.1' : pin to a specific release
      'latest' (default)                : recommend the latest available (1.7.1 as of
                                          AMD docs 2026-04-19)

    AMD recommends always using the latest Ryzen AI Software for end-user workloads;
    this script's default is therefore 'latest'. The Ryzen AI Software is downloaded
    and installed by the user separately (via ryzen-ai-lt-<ver>.exe), not by this
    script. This parameter only affects the guidance text shown in the I04 post-
    install banner.

.PARAMETER AssumeIfMissing
    If NPU is not detected (e.g. running on EPYC machine for pipeline regression),
    proceed using the default profile (Strix Point + NPU_RAI1.6.1_314 + RAI Software latest).

.PARAMETER AllowWorkstationInstall
    Permit Install-phase actions on Workstation OS (Win11). Discouraged. Default behaviour
    blocks Install on Workstation and runs PrepareVerify only.

.PARAMETER UseTestSigning
    Fall back to bcdedit /set testsigning on instead of the default WDAC supplemental policy.
    Discouraged on Windows Server 2022+ / Windows 11 22H2+.

.PARAMETER CleanWorkRoot
    Delete the workspace directory before starting (forces a fresh download/extract).

.PARAMETER WorkRoot
    Override the default workspace path (C:\AMD-NPU-WS).

.PARAMETER PfxPassword
    Password for the self-signed PFX. Default is empty (lab tool).

.PARAMETER CertValidityYears
    Self-signed cert validity period in years. Default 5.

.EXAMPLE
    # Pipeline soundness check, no system change. Recommended for first-time runs
    # where Tier 4 auto-scan may not find a ZIP in default locations.
    .\Deploy-AMDNpuDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip

.EXAMPLE
    # Pipeline soundness check on a non-NPU host (e.g. AWS EPYC EC2) for regression testing.
    # -AssumeIfMissing forces the default Strix Point profile when no NPU is detected.
    .\Deploy-AMDNpuDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot `
        -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip -AssumeIfMissing

.EXAMPLE
    # Pipeline soundness check WITHOUT -OfflineZip. Will only succeed if a ZIP is
    # found via Tier 4 auto-scan (script dir / ./cache / workspace download dir / ~/Downloads).
    # If no ZIP is cached anywhere, P03 will throw "All 4 download tiers exhausted".
    .\Deploy-AMDNpuDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot

.EXAMPLE
    # Full install on a real NPU host using a manually-downloaded offline ZIP (most reliable).
    # Requires interactive "I AGREE" confirmation at I00 (EULA acknowledgement).
    .\Deploy-AMDNpuDriverOnWindowsServer.ps1 -Action Install -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip

.EXAMPLE
    # Full install via AMD account auto-download (Tier 2). BEST-EFFORT: may break
    # without notice when AMD changes their account.amd.com form layouts.
    .\Deploy-AMDNpuDriverOnWindowsServer.ps1 -Action Install `
        -AmdAccountUser 'user@example.com' `
        -AmdAccountPassword (Read-Host 'AMD password' -AsSecureString)

.EXAMPLE
    # Force a specific NPU codename + driver package, with offline ZIP as the source.
    # NPU driver and Ryzen AI Software versioning are independent: -NpuDriverPackage
    # selects the kernel driver, -RyzenAiSoftwareVersion selects the user-mode stack.
    .\Deploy-AMDNpuDriverOnWindowsServer.ps1 -Action Install `
        -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip `
        -NpuOverride STX `
        -NpuDriverPackage NPU_RAI1.6.1_314 `
        -RyzenAiSoftwareVersion latest

.NOTES
    Version: r1
    Author : Deploy-AMD-Drivers-For-WindowsServer contributors
    License: MIT
    Repo   : https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer

    PowerShell 5.1+ (Desktop or Core), 64-bit, run as Administrator.

    DISCLAIMER:
      - Lab/research tool. AMD does NOT officially support Ryzen AI on Windows Server.
      - This script installs the kernel-mode NPU driver only. Ryzen AI Software (Python
        conda env, ONNX Runtime, Vitis AI EP, OGA models) must be installed separately
        and is unlikely to function on Server 2025 without unofficial workarounds.
      - Self-signed driver chain. WHQL certification is invalidated for replaced drivers.
      - Every run with -Action Install requires accepting AMD's Ryzen AI EULA at
        https://account.amd.com/en/forms/downloads/ryzenai-eula-public-xef.html
#>

#Requires -Version 5.1
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Prepare','Verify','PrepareVerify','Install','All','Cleanup','ListPhases')]
    [string]$Action = 'PrepareVerify',

    [Parameter()]
    [string[]]$OnlyPhases,

    [Parameter()]
    [string]$InstallerUrl,

    [Parameter()]
    [string]$OfflineZip,

    [Parameter()]
    [string]$AmdAccountUser,

    [Parameter()]
    [System.Security.SecureString]$AmdAccountPassword,

    [Parameter()]
    [switch]$ForceAmdAccountAuth,

    [Parameter()]
    [ValidateSet('PHX','HPT','STX','KRK')]
    [string]$NpuOverride,

    [Parameter()]
    [ValidateSet('NPU_RAI1.5_280', 'NPU_RAI1.6.1_314', 'latest')]
    [string]$NpuDriverPackage = 'latest',

    [Parameter()]
    [ValidateSet('1.5', '1.6.1', '1.7', '1.7.1', 'latest')]
    [string]$RyzenAiSoftwareVersion = 'latest',

    [Parameter()]
    [switch]$AssumeIfMissing,

    [Parameter()]
    [switch]$AllowWorkstationInstall,

    [Parameter()]
    [switch]$UseTestSigning,

    [Parameter()]
    [switch]$CleanWorkRoot,

    [Parameter()]
    [string]$WorkRoot = 'C:\AMD-NPU-WS',

    [Parameter()]
    [string]$PfxPassword = '',

    [Parameter()]
    [int]$CertValidityYears = 5,

    [Parameter()]
    [string]$WdacPolicyGuid = ''
)

# =============================================================================
# Mirror parameters into Script scope so functions can reference them via $Script:Foo
# (Without this, functions calling $InstallerUrl etc. rely on PowerShell's implicit
# parent-scope lookup, which works at runtime but trips static analyzers.)
# =============================================================================
$Script:Action                  = $Action
$Script:OnlyPhases              = $OnlyPhases
$Script:InstallerUrl            = $InstallerUrl
$Script:OfflineZip              = $OfflineZip
$Script:AmdAccountUser          = $AmdAccountUser
$Script:AmdAccountPassword      = $AmdAccountPassword
$Script:ForceAmdAccountAuth     = [bool]$ForceAmdAccountAuth
$Script:NpuOverride             = $NpuOverride
$Script:NpuDriverPackage        = $NpuDriverPackage
$Script:RyzenAiSoftwareVersion  = $RyzenAiSoftwareVersion
$Script:AssumeIfMissing         = [bool]$AssumeIfMissing
$Script:AllowWorkstationInstall = [bool]$AllowWorkstationInstall
$Script:UseTestSigning          = [bool]$UseTestSigning
$Script:CleanWorkRoot           = [bool]$CleanWorkRoot
$Script:WorkRoot                = $WorkRoot
$Script:PfxPassword             = $PfxPassword
$Script:CertValidityYears       = $CertValidityYears

# =============================================================================
# Script-scope state
# =============================================================================
$Script:ScriptVersion       = 'npu-2026.05.13-r3'
$Script:ScriptTag           = 'npu-cert-name-r3'
$Script:ScriptName          = 'Deploy-AMDNpuDriverOnWindowsServer'
$Script:RepoUrl             = 'https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer'
$Script:CertSubjectCn       = 'AMD NPU Driver Self-Sign (WS2025 Lab, At Own Risk)'
$Script:WdacPolicyName      = 'AMD-NPU-Driver-SelfSign-Lab'
# Default fixed WDAC Policy GUID (UUID v4). Operators can override via the
# -WdacPolicyGuid parameter, e.g. when cleaning up a legacy deploy whose
# PolicyId differs from the default (pre-r3 deploys generated dynamic GUIDs).
$Script:WdacPolicyGuidDefault = '8B2C4F12-1E9D-4D7B-A4F8-9C7E2B6A53D1'
$Script:WdacPolicyGuid      = if (-not [string]::IsNullOrWhiteSpace($WdacPolicyGuid)) {
    $WdacPolicyGuid.Trim('{','}','(',')',' ')
} else {
    $Script:WdacPolicyGuidDefault
}
$Script:DownloadDir         = Join-Path $WorkRoot 'download'
$Script:ExtractedDir        = Join-Path $WorkRoot 'extracted'
$Script:PatchedDir          = Join-Path $WorkRoot 'patched'
$Script:CertDir             = Join-Path $WorkRoot 'cert'
$Script:PfxPath             = Join-Path $Script:CertDir 'AMD-NPU-Driver-CodeSign.pfx'
$Script:CerPath             = Join-Path $Script:CertDir 'AMD-NPU-Driver-CodeSign.cer'
$Script:WdacXmlPath         = Join-Path $Script:CertDir 'WDAC-Supplemental-NPU.xml'
$Script:WdacBinPath         = Join-Path $Script:CertDir 'WDAC-Supplemental-NPU.cip'
$Script:InventoryCsvPath    = Join-Path $WorkRoot 'inf_inventory.csv'
$Script:InventoryReportPath = Join-Path $WorkRoot 'inf_inventory_report.txt'
$Script:TimestampUrl        = 'http://timestamp.digicert.com'
$Script:HostStartTime       = Get-Date
$Script:ScriptStartTime     = Get-Date

# Sister-script-aligned: per-phase timing and elapsed-tag infrastructure
$Script:CurrentPhaseStart   = $null
$Script:CurrentPhaseId      = $null
$Script:PhaseTimings        = New-Object System.Collections.Generic.List[object]

# Sister-script-aligned: SHA256-based one-line script-identity tag.
# When users report unexpected behaviour, the hash uniquely identifies the
# exact file they ran (immune to filename collisions or partial overwrites).
$Script:ScriptHash = '(unknown)'
try {
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrEmpty($scriptPath)) { $scriptPath = $MyInvocation.MyCommand.Path }
    if ($scriptPath -and (Test-Path -LiteralPath $scriptPath)) {
        $hashFull = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
        $Script:ScriptHash = $hashFull.Substring(0, 12).ToLower()
        $Script:ScriptPath = $scriptPath
    }
} catch {
    $Script:ScriptHash = '(hash-error)'
}
$Script:ScriptShortTag = ('v{0}/{1}' -f $Script:ScriptVersion, $Script:ScriptHash)

# Phase registry (sister-script-aligned: pscustomobject + Invoke-{Group}Phase{NN}_{Name})
$Script:PhaseRegistry = @(
    [pscustomobject]@{ Id='P00'; Name='Initialize';                Group='Prep';   Func='Invoke-PrepPhase00_Initialize'                }
    [pscustomobject]@{ Id='P01'; Name='PrepareWorkspace';          Group='Prep';   Func='Invoke-PrepPhase01_PrepareWorkspace'          }
    [pscustomobject]@{ Id='P02'; Name='AcquireTools';              Group='Prep';   Func='Invoke-PrepPhase02_AcquireTools'              }
    [pscustomobject]@{ Id='P03'; Name='FetchInstaller';            Group='Prep';   Func='Invoke-PrepPhase03_FetchInstaller'            }
    [pscustomobject]@{ Id='P04'; Name='ExtractInstaller';          Group='Prep';   Func='Invoke-PrepPhase04_ExtractInstaller'          }
    [pscustomobject]@{ Id='P05'; Name='AnalyzeInfs';               Group='Prep';   Func='Invoke-PrepPhase05_AnalyzeInfs'               }
    [pscustomobject]@{ Id='P06'; Name='PatchInfs';                 Group='Prep';   Func='Invoke-PrepPhase06_PatchInfs'                 }
    [pscustomobject]@{ Id='P07'; Name='CreateCertificate';         Group='Prep';   Func='Invoke-PrepPhase07_CreateCertificate'         }
    [pscustomobject]@{ Id='P08'; Name='GenerateCatalogs';          Group='Prep';   Func='Invoke-PrepPhase08_GenerateCatalogs'          }
    [pscustomobject]@{ Id='P09'; Name='SignCatalogs';              Group='Prep';   Func='Invoke-PrepPhase09_SignCatalogs'              }
    [pscustomobject]@{ Id='V01'; Name='VerifyArtifacts';           Group='Verify'; Func='Invoke-VerifyPhase01_VerifyArtifacts'         }
    [pscustomobject]@{ Id='V02'; Name='VerifyCertificate';         Group='Verify'; Func='Invoke-VerifyPhase02_VerifyCertificate'       }
    [pscustomobject]@{ Id='V03'; Name='VerifyCatalogs';            Group='Verify'; Func='Invoke-VerifyPhase03_VerifyCatalogs'          }
    [pscustomobject]@{ Id='V04'; Name='VerifyInfs';                Group='Verify'; Func='Invoke-VerifyPhase04_VerifyInfs'              }
    [pscustomobject]@{ Id='V05'; Name='DryRunInstall';             Group='Verify'; Func='Invoke-VerifyPhase05_DryRunInstall'           }
    [pscustomobject]@{ Id='V06'; Name='HardwareImpactAnalysis';    Group='Verify'; Func='Invoke-VerifyPhase06_HardwareImpactAnalysis'  }
    [pscustomobject]@{ Id='I00'; Name='PreInstallReview';          Group='Inst';   Func='Invoke-InstPhase00_PreInstallReview'          }
    [pscustomobject]@{ Id='I01'; Name='TrustCertificate';          Group='Inst';   Func='Invoke-InstPhase01_TrustCertificate'          }
    [pscustomobject]@{ Id='I02'; Name='AuthorizeDriverSigning';    Group='Inst';   Func='Invoke-InstPhase02_AuthorizeDriverSigning'    }
    [pscustomobject]@{ Id='I03'; Name='InstallDrivers';            Group='Inst';   Func='Invoke-InstPhase03_InstallDrivers'            }
    [pscustomobject]@{ Id='I04'; Name='PostInstallVerification';   Group='Inst';   Func='Invoke-InstPhase04_PostInstallVerification'   }
)

# Detected platform state (populated in P00 and P03)
$Script:DetectedPlatform = @{
    OsCaption          = $null
    OsBuild            = $null
    OsProductType      = $null  # 1=Workstation, 3=Server
    OsProfile          = $null  # WS2016 / WS2019 / WS2022 / WS2025
    Inf2CatOsSwitch    = $null  # Server2025_X64 etc
    IsWorkstationOs    = $null
    IsServer2025       = $null
    NpuCodename        = $null
    NpuShortName       = $null
    NpuHardwareId      = $null
    NpuRevision        = $null
    NpuIsDetected      = $false
    NpuDetectionSource = $null
    CpuName            = $null
    # ----- NPU kernel-mode driver (versioning is INDEPENDENT from RAI Software) -----
    NpuDriverPackage   = $null   # e.g. 'NPU_RAI1.6.1_314'  (resolved package id)
    NpuDriverBuild     = $null   # e.g. '32.0.203.314'      (kernel driver build)
    NpuDriverZipName   = $null   # e.g. 'NPU_RAI1.6.1_314_WHQL.zip'
    # ----- Ryzen AI Software (user-mode stack — versioning is INDEPENDENT from driver) -----
    RyzenAiSoftwareVersion = $null  # e.g. '1.7.1' (always the latest unless pinned)
    RyzenAiSoftwareInstaller = $null # e.g. 'ryzen-ai-lt-1.7.1.exe'
    # ----- Compatibility evaluation (driver <-> software) -----
    DriverSoftwareCompatible = $null # bool result of Test-NpuDriverRaiCompatibility
    DriverSoftwareCompatNote = $null # human-readable explanation
    # ----- Download / extraction artefacts -----
    DownloadedZipPath  = $null
    DownloadedZipName  = $null
    SignToolPath       = $null
    Inf2CatPath        = $null
    SevenZipPath       = $null
}

# Phase results
$Script:PhaseResults = @{}

# =============================================================================
# Output helpers - colour-coded console output (sister-script-aligned)
#
# Logging style is unified with the chipset / graphics deployment scripts in
# this repository. Each line is prefixed with [HH:mm:ss] [+X.XXs] markers so
# operators reading concatenated logs from all three pipelines see the same
# format and timing information.
#
# Marker semantics:
#   [*] Cyan     - Step (action being performed)
#   [+] Green    - Ok   (success / positive result)
#   [!] Yellow   - Warn (degraded / suspicious; non-fatal)
#   [X] Red      - Fail (operation failed)
#   [~] DarkGray - Skip (no-op / cached / informational)
#
# Phase entry: Write-PhaseHeader  (Magenta '=' x72) - rendered by dispatcher
# Sub-section: Write-SubHeader    (Cyan      '=' x72) - in-phase Level-1 banner
# Sub-section: Write-SubHeader2   (DarkCyan  '-' x72) - in-phase Level-2 banner
# =============================================================================
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

function Write-SubHeader {
    # In-phase Level-1 sub-banner (Cyan = x72). Used for major sections within
    # a phase (e.g. "NPU platform detection" / "Driver package resolution").
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host (" $Message") -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
}

function Write-SubHeader2 {
    # In-phase Level-2 sub-banner (DarkCyan - x72). Used for finer subsections
    # (e.g. "Section 1: Detected NPU on this host").
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ''
    Write-Host ('-' * 72) -ForegroundColor DarkCyan
    Write-Host (" $Message") -ForegroundColor DarkCyan
    Write-Host ('-' * 72) -ForegroundColor DarkCyan
}

function Write-PhaseHeader {
    # Phase entry banner (Magenta = x72) - rendered by the dispatcher right
    # before each phase function is invoked. Records phase start time so that
    # _LogLine can emit elapsed-tags within the phase.
    param($Id, $Name, $Group)
    $Script:CurrentPhaseStart = Get-Date
    $Script:CurrentPhaseId    = $Id
    $startStr = $Script:CurrentPhaseStart.ToString('HH:mm:ss')
    $line = '=' * 72
    Write-Host ''
    Write-Host $line -ForegroundColor Magenta
    Write-Host (" PHASE {0} - {1,-26} ({2,-6})  start: {3}" -f $Id, $Name, $Group, $startStr) -ForegroundColor Magenta
    Write-Host (" script: {0}" -f $Script:ScriptShortTag) -ForegroundColor DarkGray
    Write-Host $line -ForegroundColor Magenta
}

function Write-PhaseFooter {
    # Phase exit banner. Idempotent: safe to call multiple times for the same
    # phase (only the first call is recorded). Status is one of done/cached/
    # skipped/failed; colour and PhaseTimings entry are derived accordingly.
    param($Id, [ValidateSet('done','cached','skipped','failed')]$Status)

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

# =============================================================================
# Environment detection helpers
# =============================================================================
function Show-PowerShellEnvironment {
    [CmdletBinding()]
    param()
    Write-SubHeader2 'PowerShell environment'
    $psv = $PSVersionTable
    Write-Skip ("PSVersion          : {0}" -f $psv.PSVersion)
    Write-Skip ("PSEdition          : {0}" -f $psv.PSEdition)
    Write-Skip ("PSCompatibleVersions: {0}" -f ($psv.PSCompatibleVersions -join ', '))
    Write-Skip ("CLRVersion         : {0}" -f $psv.CLRVersion)
    Write-Skip ("BuildVersion       : {0}" -f $psv.BuildVersion)
    Write-Skip ("OS                 : {0}" -f $psv.OS)
    Write-Skip ("Platform           : {0}" -f $psv.Platform)

    if ($psv.PSVersion.Major -lt 5) {
        Write-Fail 'PowerShell 5.1 or higher is required.'
        throw 'PowerShell version unsupported.'
    }
    if ($psv.PSVersion.Major -eq 5 -and $psv.PSVersion.Minor -lt 1) {
        Write-Fail 'PowerShell 5.1 or higher is required.'
        throw 'PowerShell version unsupported.'
    }

    if (-not [Environment]::Is64BitProcess) {
        Write-Fail '64-bit PowerShell host is required.'
        throw 'Not running in 64-bit PowerShell.'
    }
}

function Show-OperatingSystemDetail {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    Write-SubHeader2 'Host operating system'

    $os    = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $build = [int]$os.BuildNumber
    $caption = $os.Caption
    $productType = [int]$os.ProductType  # 1=Workstation, 2=DC, 3=Server

    # Profile mapping based on NT build (chipset/graphics scripts share this matrix)
    $profile = $null
    $inf2cat = $null
    if ($build -ge 26100) {
        # Win11 24H2 and Server 2025 share build 26100
        $profile = 'WS2025'
        $inf2cat = 'Server2025_X64'
    } elseif ($build -ge 22631) {
        # Win11 23H2
        $profile = 'WS2022-equiv'
        $inf2cat = 'ServerFE_X64'
    } elseif ($build -ge 22000) {
        # Win11 21H2/22H2
        $profile = 'WS2022-equiv'
        $inf2cat = 'ServerFE_X64'
    } elseif ($build -ge 20348) {
        # Server 2022
        $profile = 'WS2022'
        $inf2cat = 'ServerFE_X64'
    } elseif ($build -ge 19041) {
        # Win10 20H2/21H2/22H2
        $profile = 'WS2019-equiv'
        $inf2cat = 'ServerRS5_X64'
    } elseif ($build -ge 17763) {
        # Server 2019
        $profile = 'WS2019'
        $inf2cat = 'ServerRS5_X64'
    } elseif ($build -ge 14393) {
        # Server 2016
        $profile = 'WS2016'
        $inf2cat = 'Server2016_X64'
    } else {
        $profile = 'Unknown'
        $inf2cat = $null
    }

    Write-Ok ("OS detected     : {0} (build {1})" -f $caption, $build)
    Write-Skip ("Profile applied : {0}" -f $profile)
    Write-Skip ("inf2cat /os: switch : {0}" -f $inf2cat)
    Write-Skip ("ProductType     : {0}  (1=Workstation, 3=Server)" -f $productType)

    $isWorkstation = ($productType -eq 1)
    $isServer2025  = ($productType -eq 3 -and $build -ge 26100)

    if ($isWorkstation -and $build -ge 26100) {
        # WS2025 PRE-MIGRATION PREVIEW MODE banner
        Write-Host ''
        Write-Host '    +-----------------------------------------------------------------+' -ForegroundColor Magenta
        Write-Host '    | WS2025 PRE-MIGRATION PREVIEW MODE                               |' -ForegroundColor Magenta
        Write-Host '    | (Windows 11 24H2 and Windows Server 2025 share NT build 26100)  |' -ForegroundColor Magenta
        Write-Host '    +-----------------------------------------------------------------+' -ForegroundColor Magenta
    }

    return @{
        OsCaption       = $caption
        OsBuild         = $build
        OsProductType   = $productType
        OsProfile       = $profile
        Inf2CatOsSwitch = $inf2cat
        IsWorkstationOs = $isWorkstation
        IsServer2025    = $isServer2025
    }
}

function Test-AdminPrivilege {
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    $current  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    $isAdmin  = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Fail 'This script must run as Administrator.'
        throw 'Not running as Administrator.'
    }
    Write-Ok 'Administrator privileges confirmed.'
    return $true
}

function Set-NetworkProtocol {
    [CmdletBinding()]
    param()
    try {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.SecurityProtocolType]::Tls12 -bor `
            [Net.SecurityProtocolType]::Tls13 -bor `
            [Net.SecurityProtocolType]::Tls11 -bor `
            [Net.SecurityProtocolType]::Tls
        Write-Skip 'TLS protocols enabled: Tls, Tls11, Tls12, Tls13'
    } catch {
        # Tls13 may not exist on PS5.1; degrade gracefully
        try {
            [Net.ServicePointManager]::SecurityProtocol = `
                [Net.SecurityProtocolType]::Tls12 -bor `
                [Net.SecurityProtocolType]::Tls11 -bor `
                [Net.SecurityProtocolType]::Tls
            Write-Skip 'TLS protocols enabled: Tls, Tls11, Tls12 (Tls13 unavailable)'
        } catch {
            Write-Warn2 ("Could not configure TLS protocols: {0}" -f $_.Exception.Message)
        }
    }
}

# =============================================================================
# Phase orchestrator
# =============================================================================
function Invoke-PhaseRunner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$PhaseIds
    )
    foreach ($id in $PhaseIds) {
        $phase = $Script:PhaseRegistry | Where-Object Id -EQ $id | Select-Object -First 1
        if (-not $phase) {
            Write-Fail ("Unknown phase ID: {0}" -f $id)
            throw "Unknown phase: $id"
        }

        # Sister-script-aligned: dispatcher renders the phase entry banner,
        # records phase-start time, and emits a phase-exit footer on both
        # success and failure paths. Phase functions stay focused on their
        # logic; banner/timing concerns are owned here.
        Write-PhaseHeader $phase.Id $phase.Name $phase.Group

        $start = Get-Date
        $errCaught = $null

        try {
            & $phase.Func
            $Script:PhaseResults[$id] = @{
                Status   = 'OK'
                Duration = ((Get-Date) - $start)
                Error    = $null
            }
            Write-PhaseFooter $phase.Id 'done'
        } catch {
            $errCaught = $_
            $Script:PhaseResults[$id] = @{
                Status   = 'FAIL'
                Duration = ((Get-Date) - $start)
                Error    = $errCaught
            }
            Write-Fail ("Phase {0} FAILED: {1}" -f $id, $errCaught.Exception.Message)
            Write-PhaseFooter $phase.Id 'failed'
            throw $errCaught
        }
    }
}

function Get-PhaseListByAction {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([string]$Action)
    # Sister-script-aligned action -> phase mapping:
    #   Prepare       : Prep only
    #   Verify        : Verify only
    #   PrepareVerify : Prep + Verify (no system-state change)
    #   Install       : Inst only (assumes Prep+Verify ran in a prior invocation
    #                   and patched artifacts are still on disk)
    #   All           : Prep + Verify + Inst (full pipeline end-to-end)
    switch ($Action) {
        'PrepareVerify' {
            return ($Script:PhaseRegistry | Where-Object { $_.Group -eq 'Prep' -or $_.Group -eq 'Verify' } | Select-Object -ExpandProperty Id)
        }
        'Prepare' {
            return ($Script:PhaseRegistry | Where-Object Group -EQ 'Prep' | Select-Object -ExpandProperty Id)
        }
        'Verify' {
            return ($Script:PhaseRegistry | Where-Object Group -EQ 'Verify' | Select-Object -ExpandProperty Id)
        }
        'Install' {
            return ($Script:PhaseRegistry | Where-Object Group -EQ 'Inst' | Select-Object -ExpandProperty Id)
        }
        'All' {
            return ($Script:PhaseRegistry | Select-Object -ExpandProperty Id)
        }
        default {
            return @()
        }
    }
}

function Show-PhaseList {
    [CmdletBinding()]
    param()
    # Sister-script-aligned: column order ID -> Name -> Group -> Function,
    # Magenta header, '-' x 70 divider.
    Write-Host ''
    Write-Host ('Registered phases for {0} {1}:' -f $Script:ScriptName, $Script:ScriptVersion) -ForegroundColor Magenta
    Write-Host ('  {0,-5} {1,-30} {2,-6} {3}' -f 'ID','Name','Group','Function') -ForegroundColor Magenta
    Write-Host ('  {0}' -f ('-' * 70)) -ForegroundColor Magenta
    foreach ($p in $Script:PhaseRegistry) {
        Write-Host ('  {0,-5} {1,-30} {2,-6} {3}' -f $p.Id, $p.Name, $p.Group, $p.Func)
    }
    Write-Host ''
    Write-Skip 'Use -OnlyPhases <P05,P06,...> to run a subset.'
    Write-Skip "Use -Action <Prepare|Verify|PrepareVerify|Install|All|Cleanup> to choose a phase group."
}

# =============================================================================
# AMD NPU platform detection (P03 helper)
# =============================================================================
function Get-AmdNpuPlatform {
    <#
    .SYNOPSIS
        Detects the AMD NPU codename (PHX/HPT/STX/KRK) using PCI HWID enumeration.
    .DESCRIPTION
        Translates the AMD-published Python detection logic from quicktest.py
        (https://ryzenai.docs.amd.com/en/latest/inst.html) to PowerShell.

        Uses pnputil /enum-devices /bus PCI /deviceids to get raw HWIDs, then
        regex-matches against known NPU patterns. Phoenix and Hawk Point share
        DEV_1502&REV_00, so CPU name disambiguates them.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$Override,
        [switch]$AssumeIfMissing,
        # NPU driver package selection (independent from Ryzen AI Software version)
        [string]$NpuDriverPackageSelection = 'latest',
        # Ryzen AI Software version selection (independent from NPU driver)
        [string]$RyzenAiSoftwareVersionSelection = 'latest'
    )

    $detected = @{
        NpuCodename             = $null
        NpuShortName            = $null
        HardwareId              = $null
        Revision                = $null
        IsDetected              = $false
        DetectionSource         = $null
        # ----- NPU kernel-mode driver fields (independent from RAI Software) -----
        NpuDriverPackage         = $null
        NpuDriverBuild           = $null
        NpuDriverZipName         = $null
        # ----- Ryzen AI Software fields (independent from NPU driver) -----
        RyzenAiSoftwareVersion   = $null
        RyzenAiSoftwareInstaller = $null
        # ----- Compatibility evaluation (driver <-> software) -----
        DriverSoftwareCompatible = $null
        DriverSoftwareCompatNote = $null
        CpuName                 = $null
        RawDeviceIds            = $null
    }

    # Get CPU name first (needed for PHX/HPT disambiguation)
    try {
        $cpu = (Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).Name
        $detected.CpuName = $cpu
    } catch {
        Write-Warn2 ("Could not read Win32_Processor.Name: {0}" -f $_.Exception.Message)
        $cpu = ''
    }

    # Manual override path
    if ($Override) {
        Write-Warn2 ("NPU override active: {0} (auto-detection skipped)" -f $Override)
        $detected.NpuShortName = $Override
        $detected.DetectionSource = 'override'
        switch ($Override) {
            'PHX' {
                $detected.NpuCodename = 'Phoenix'
                $detected.HardwareId = 'PCI\VEN_1022&DEV_1502&REV_00'
                $detected.Revision   = 'REV_00'
            }
            'HPT' {
                $detected.NpuCodename = 'Hawk Point'
                $detected.HardwareId = 'PCI\VEN_1022&DEV_1502&REV_00'
                $detected.Revision   = 'REV_00'
            }
            'STX' {
                $detected.NpuCodename = 'Strix Point / Strix Halo'
                $detected.HardwareId = 'PCI\VEN_1022&DEV_17F0&REV_00'
                $detected.Revision   = 'REV_00'
            }
            'KRK' {
                $detected.NpuCodename = 'Krackan Point'
                $detected.HardwareId = 'PCI\VEN_1022&DEV_17F0&REV_20'
                $detected.Revision   = 'REV_20'
            }
        }
        $detected.IsDetected = $true
        # Populate NPU driver fields (driver versioning - INDEPENDENT axis)
        $pkgInfo = Get-NpuDriverPackageInfo -PackageSelection $NpuDriverPackageSelection
        $detected.NpuDriverPackage  = $pkgInfo.PackageId
        $detected.NpuDriverBuild    = $pkgInfo.DriverBuild
        $detected.NpuDriverZipName  = $pkgInfo.ZipFilename
        # Populate Ryzen AI Software fields (software versioning - INDEPENDENT axis)
        $swInfo = Get-LatestRyzenAiSoftwareInfo -VersionSelection $RyzenAiSoftwareVersionSelection
        $detected.RyzenAiSoftwareVersion   = $swInfo.ResolvedVersion
        $detected.RyzenAiSoftwareInstaller = $swInfo.InstallerFilename
        # Populate compatibility evaluation (separate axis)
        $compat = Test-NpuDriverRaiCompatibility -NpuDriverBuild $pkgInfo.DriverBuild -RyzenAiSoftwareVersion $swInfo.ResolvedVersion
        $detected.DriverSoftwareCompatible = $compat.IsCompatible
        $detected.DriverSoftwareCompatNote = $compat.Note
        return $detected
    }

    # Run pnputil for PCI device enumeration
    Write-Step 'Enumerating PCI devices via pnputil /enum-devices /bus PCI /deviceids'
    $pnpOutput = $null
    try {
        $pnpOutput = (& pnputil.exe /enum-devices /bus PCI /deviceids 2>&1) -join "`n"
        $detected.RawDeviceIds = $pnpOutput
    } catch {
        Write-Warn2 ("pnputil enumeration failed: {0}" -f $_.Exception.Message)
        $pnpOutput = ''
    }

    # Pattern match - PHX/HPT (DEV_1502)
    if ($pnpOutput -match 'PCI\\VEN_1022&DEV_1502&REV_00') {
        if ($cpu -match '7\d40\b|PRO\s+7\d40\b|7840|7640|7940|7740') {
            $detected.NpuCodename = 'Phoenix'
            $detected.NpuShortName = 'PHX'
        } elseif ($cpu -match '8\d40\b|PRO\s+8\d40\b|8840|8640|8945|8845|8845HS') {
            $detected.NpuCodename = 'Hawk Point'
            $detected.NpuShortName = 'HPT'
        } else {
            # Ambiguous - default to PHX (older silicon, conservative)
            $detected.NpuCodename = 'Phoenix or Hawk Point (ambiguous, assumed PHX)'
            $detected.NpuShortName = 'PHX'
        }
        $detected.HardwareId = 'PCI\VEN_1022&DEV_1502&REV_00'
        $detected.Revision   = 'REV_00'
        $detected.IsDetected = $true
        $detected.DetectionSource = 'pnputil'
    }
    # Pattern match - STX (DEV_17F0&REV_00/10/11)
    elseif ($pnpOutput -match 'PCI\\VEN_1022&DEV_17F0&REV_(00|10|11)') {
        $rev = $Matches[1]
        $detected.NpuCodename = 'Strix Point / Strix Halo'
        $detected.NpuShortName = 'STX'
        $detected.HardwareId   = "PCI\VEN_1022&DEV_17F0&REV_$rev"
        $detected.Revision     = "REV_$rev"
        $detected.IsDetected   = $true
        $detected.DetectionSource = 'pnputil'
    }
    # Pattern match - KRK (DEV_17F0&REV_20)
    elseif ($pnpOutput -match 'PCI\\VEN_1022&DEV_17F0&REV_20') {
        $detected.NpuCodename = 'Krackan Point'
        $detected.NpuShortName = 'KRK'
        $detected.HardwareId   = 'PCI\VEN_1022&DEV_17F0&REV_20'
        $detected.Revision     = 'REV_20'
        $detected.IsDetected   = $true
        $detected.DetectionSource = 'pnputil'
    }
    elseif ($AssumeIfMissing) {
        # Default - Strix Point + latest documented NPU driver + latest RAI Software
        Write-Warn2 'No AMD NPU detected via pnputil. Using default profile (Strix Point + NPU driver 32.0.203.314 + RAI Software latest).'
        $detected.NpuCodename     = 'Strix Point (default - no NPU detected)'
        $detected.NpuShortName    = 'STX'
        $detected.HardwareId      = 'PCI\VEN_1022&DEV_17F0&REV_00'
        $detected.Revision        = 'REV_00'
        $detected.DetectionSource = 'default-strix-driver314-rai-latest'
        # IsDetected stays false to trigger downstream warning banners
    } else {
        Write-Fail 'No AMD NPU detected and -AssumeIfMissing was not specified.'
        Write-Skip 'Pass -AssumeIfMissing to proceed with the default Strix Point profile,'
        Write-Skip 'or pass -NpuOverride <PHX|HPT|STX|KRK> to force a specific platform.'
        throw 'AMD NPU not detected; cannot proceed.'
    }

    # Populate NPU driver fields (kernel driver versioning - INDEPENDENT axis)
    $pkgInfo = Get-NpuDriverPackageInfo -PackageSelection $NpuDriverPackageSelection
    $detected.NpuDriverPackage = $pkgInfo.PackageId
    $detected.NpuDriverBuild   = $pkgInfo.DriverBuild
    $detected.NpuDriverZipName = $pkgInfo.ZipFilename

    # Populate Ryzen AI Software fields (user-mode stack versioning - INDEPENDENT axis,
    # always recommend latest unless explicitly pinned by operator)
    $swInfo = Get-LatestRyzenAiSoftwareInfo -VersionSelection $RyzenAiSoftwareVersionSelection
    $detected.RyzenAiSoftwareVersion   = $swInfo.ResolvedVersion
    $detected.RyzenAiSoftwareInstaller = $swInfo.InstallerFilename

    # Populate compatibility evaluation (driver <-> software, SEPARATE axis from version)
    $compat = Test-NpuDriverRaiCompatibility -NpuDriverBuild $pkgInfo.DriverBuild -RyzenAiSoftwareVersion $swInfo.ResolvedVersion
    $detected.DriverSoftwareCompatible = $compat.IsCompatible
    $detected.DriverSoftwareCompatNote = $compat.Note

    return $detected
}

function Get-NpuDriverPackageInfo {
    <#
    .SYNOPSIS
        Returns NPU kernel-mode driver package metadata. Selection is based ONLY on the
        operator-supplied -NpuDriverPackage value (or 'latest'). NOT correlated with
        Ryzen AI Software version.
    .DESCRIPTION
        AMD publishes two NPU driver ZIPs on account.amd.com (verified 2026-05-10 against
        https://ryzenai.docs.amd.com/en/latest/inst.html, last updated 2026-04-19):

          NPU_RAI1.5_280     -> driver build 32.0.203.280 (older, all NPU codenames supported)
          NPU_RAI1.6.1_314   -> driver build 32.0.203.314 (newer, all NPU codenames supported)

        These are the ONLY NPU driver ZIPs documented in AMD's Ryzen AI install instructions.
        The version label "RAI1.5" / "RAI1.6.1" in the ZIP filename is a historical naming
        artefact — both ZIPs work with current Ryzen AI Software (1.7.1).

        AMD's own guidance is "Download and Install the NPU driver version: 32.0.203.280 or
        newer" — i.e. either ZIP is acceptable; pick the newer one (314) for new installs.

        If a future RAI release publishes a new ZIP (e.g. NPU_RAI1.8_400_WHQL.zip), update
        this function and the parameter ValidateSet on -NpuDriverPackage.
    .OUTPUTS
        Hashtable with: PackageId, DriverBuild, ZipFilename, EulaUrl, NpuCoverage, ReleaseDate
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('NPU_RAI1.5_280', 'NPU_RAI1.6.1_314', 'latest')]
        [string]$PackageSelection
    )

    $catalog = @{
        'NPU_RAI1.5_280' = @{
            PackageId    = 'NPU_RAI1.5_280'
            DriverBuild  = '32.0.203.280'
            ZipFilename  = 'NPU_RAI1.5_280_WHQL.zip'
            EulaUrl      = 'https://account.amd.com/en/forms/downloads/ryzenai-eula-public-xef.html?filename=NPU_RAI1.5_280_WHQL.zip'
            NpuCoverage  = @('PHX', 'HPT', 'STX', 'STH', 'KRK')
            ReleaseDate  = '2025-05-16'
            Status       = 'older — production driver per AMD docs'
        }
        'NPU_RAI1.6.1_314' = @{
            PackageId    = 'NPU_RAI1.6.1_314'
            DriverBuild  = '32.0.203.314'
            ZipFilename  = 'NPU_RAI1.6.1_314_WHQL.zip'
            EulaUrl      = 'https://account.amd.com/en/forms/downloads/ryzenai-eula-public-xef.html?filename=NPU_RAI1.6.1_314_WHQL.zip'
            NpuCoverage  = @('PHX', 'HPT', 'STX', 'STH', 'KRK')
            ReleaseDate  = '2025 (post-1.6.1 release)'
            Status       = 'newer — recommended for new installs'
        }
    }

    if ($PackageSelection -eq 'latest') {
        # 'latest' resolves to the newest documented package
        return $catalog['NPU_RAI1.6.1_314']
    }
    if ($catalog.ContainsKey($PackageSelection)) {
        return $catalog[$PackageSelection]
    }
    # Should be unreachable due to ValidateSet, but defend anyway
    throw ("Unknown NPU driver package selection: {0}" -f $PackageSelection)
}

function Get-LatestRyzenAiSoftwareInfo {
    <#
    .SYNOPSIS
        Returns metadata about the Ryzen AI Software (user-mode stack) for a given version
        or 'latest'. Independent from NPU kernel driver versioning.
    .DESCRIPTION
        Ryzen AI Software is the user-mode runtime (Python conda environment, ONNX Runtime
        VitisAI EP, OnnxRuntime GenAI/OGA, Vitis AI Quantizer, etc). Its versioning is
        completely separate from the NPU kernel driver — installing RAI Software 1.7.1 does
        NOT update the NPU driver, and updating the NPU driver does NOT update RAI Software.

        AMD's recommendation for RAI Software is "always use the latest" because it ships
        new model support, performance improvements, and bug fixes for end-user inference
        workloads. By contrast, the NPU kernel driver is updated less often and only when
        a new firmware/driver pair is released.

        Source of truth: https://ryzenai.docs.amd.com/en/latest/inst.html (currently 1.7.1).

        When AMD publishes a new RAI release (1.7.2, 1.8, etc.), update the catalog below.
    .OUTPUTS
        Hashtable with: Version, InstallerFilename, InstallerEulaUrl, NuGetFilename,
        NuGetEulaUrl, DefaultInstallPath, DefaultCondaEnv, IsLatest, ReleaseNotesUrl
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('1.5', '1.6.1', '1.7', '1.7.1', 'latest')]
        [string]$VersionSelection
    )

    $latestVersion = '1.7.1'  # update when AMD publishes a new RAI release

    $catalog = @{
        '1.5' = @{
            Version            = '1.5'
            InstallerFilename  = 'ryzen-ai-1.5.0.exe'
            DefaultInstallPath = 'C:\Program Files\RyzenAI\1.5.0'
            DefaultCondaEnv    = 'ryzen-ai-1.5.0'
        }
        '1.6.1' = @{
            Version            = '1.6.1'
            InstallerFilename  = 'ryzen-ai-1.6.1.exe'
            DefaultInstallPath = 'C:\Program Files\RyzenAI\1.6.1'
            DefaultCondaEnv    = 'ryzen-ai-1.6.1'
        }
        '1.7' = @{
            Version            = '1.7'
            InstallerFilename  = 'ryzen-ai-lt-1.7.0.exe'
            DefaultInstallPath = 'C:\Program Files\RyzenAI\1.7.0'
            DefaultCondaEnv    = 'ryzen-ai-1.7.0'
        }
        '1.7.1' = @{
            Version            = '1.7.1'
            InstallerFilename  = 'ryzen-ai-lt-1.7.1.exe'
            NuGetFilename      = '1.7.1_nuget_signed.zip'
            DefaultInstallPath = 'C:\Program Files\RyzenAI\1.7.1'
            DefaultCondaEnv    = 'ryzen-ai-1.7.1'
        }
    }

    $resolveVersion = if ($VersionSelection -eq 'latest') { $latestVersion } else { $VersionSelection }
    if (-not $catalog.ContainsKey($resolveVersion)) {
        throw ("Unknown Ryzen AI Software version: {0}" -f $resolveVersion)
    }

    $info = $catalog[$resolveVersion]
    # Augment with derived fields
    $info['InstallerEulaUrl'] = ('https://account.amd.com/en/forms/downloads/xef.html?filename={0}' -f $info['InstallerFilename'])
    if ($info.ContainsKey('NuGetFilename')) {
        $info['NuGetEulaUrl']  = ('https://account.amd.com/en/forms/downloads/xef.html?filename={0}' -f $info['NuGetFilename'])
    }
    $info['IsLatest']         = ($resolveVersion -eq $latestVersion)
    $info['ResolvedVersion']  = $resolveVersion
    $info['ReleaseNotesUrl']  = ('https://ryzenai.docs.amd.com/en/{0}/relnotes.html' -f $resolveVersion)

    return $info
}

function Test-NpuDriverRaiCompatibility {
    <#
    .SYNOPSIS
        Evaluates whether a given NPU kernel-mode driver build is compatible with a given
        Ryzen AI Software version. This is a SEPARATE evaluation axis from version selection.
    .DESCRIPTION
        AMD's compatibility statement is documented per Ryzen AI Software release. As of
        AMD docs 2026-04-19 (RAI 1.7.1):

            "Download and Install the NPU driver version: 32.0.203.280 or newer"

        Therefore, for RAI 1.7.1, both 32.0.203.280 and 32.0.203.314 are compatible.
        For older RAI releases (1.6.1 and earlier), the same driver minimum applies in
        practice; AMD does not publish a different minimum.

        The compatibility matrix below is conservative — it only allows combinations that
        AMD explicitly documents. Future releases may tighten or relax these rules; check
        the AMD release notes for the target RAI version.
    .OUTPUTS
        Hashtable with: IsCompatible (bool), Note (string), MinimumDriverBuild, ReferenceUrl
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$NpuDriverBuild,
        [Parameter(Mandatory)][string]$RyzenAiSoftwareVersion
    )

    # Per AMD docs, the minimum driver requirement is the same across all current RAI
    # releases. If AMD documents a new minimum in a future release, add an entry here.
    $minimumPerRai = @{
        '1.5'   = '32.0.203.280'
        '1.6.1' = '32.0.203.280'
        '1.7'   = '32.0.203.280'
        '1.7.1' = '32.0.203.280'
    }

    if (-not $minimumPerRai.ContainsKey($RyzenAiSoftwareVersion)) {
        return @{
            IsCompatible       = $false
            Note               = ("Unknown RAI Software version '{0}'; cannot evaluate compatibility." -f $RyzenAiSoftwareVersion)
            MinimumDriverBuild = $null
            ReferenceUrl       = 'https://ryzenai.docs.amd.com/en/latest/inst.html'
        }
    }

    $minimum = $minimumPerRai[$RyzenAiSoftwareVersion]
    # Compare driver build numbers as 4-part System.Version
    try {
        $current = [version]$NpuDriverBuild
        $minVer  = [version]$minimum
        $isOk    = $current -ge $minVer
    } catch {
        return @{
            IsCompatible       = $false
            Note               = ("Could not parse driver build '{0}' as a version." -f $NpuDriverBuild)
            MinimumDriverBuild = $minimum
            ReferenceUrl       = ('https://ryzenai.docs.amd.com/en/{0}/inst.html' -f $RyzenAiSoftwareVersion)
        }
    }

    if ($isOk) {
        return @{
            IsCompatible       = $true
            Note               = ("Driver {0} satisfies the minimum requirement ({1}) for Ryzen AI Software {2}." -f $NpuDriverBuild, $minimum, $RyzenAiSoftwareVersion)
            MinimumDriverBuild = $minimum
            ReferenceUrl       = ('https://ryzenai.docs.amd.com/en/{0}/inst.html' -f $RyzenAiSoftwareVersion)
        }
    } else {
        return @{
            IsCompatible       = $false
            Note               = ("Driver {0} is older than the minimum required ({1}) for Ryzen AI Software {2}. Install a newer driver." -f $NpuDriverBuild, $minimum, $RyzenAiSoftwareVersion)
            MinimumDriverBuild = $minimum
            ReferenceUrl       = ('https://ryzenai.docs.amd.com/en/{0}/inst.html' -f $RyzenAiSoftwareVersion)
        }
    }
}
# =============================================================================
# NPU driver URL resolution & download (P03 implementation)
# 4-tier fallback strategy:
#   Tier 1: -InstallerUrl explicit URL (highest priority)
#   Tier 2: -AmdAccountUser/-AmdAccountPassword auto-download via account.amd.com
#   Tier 3: AMD EULA-gated direct fetch probe (typically fails but kept for future-proofing)
#   Tier 4: -OfflineZip or local cache (script-sibling .zip, $WorkRoot\download\*.zip)
# =============================================================================

function Resolve-AmdNpuDriverUrl {
    <#
    .SYNOPSIS
        Resolves the NPU driver ZIP source using the 4-tier fallback strategy.
    .OUTPUTS
        Hashtable with:
          - SourceType: 'ExplicitUrl' | 'AmdAuthenticated' | 'EulaGatedDirect' | 'LocalCache'
          - LocalPath  : path to a downloaded or pre-existing ZIP on disk
          - SourceUrl  : the URL that was fetched (or null for LocalCache)
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][hashtable]$NpuPlatform,
        [string]$ExplicitInstallerUrl,
        [string]$ExplicitOfflineZip,
        [string]$AmdAccountUser,
        [System.Security.SecureString]$AmdAccountPassword
    )

    # NPU driver ZIP filename comes directly from the resolved package metadata.
    # NpuDriverZipName is populated in Get-AmdNpuPlatform via Get-NpuDriverPackageInfo
    # (independent of Ryzen AI Software version).
    if ([string]::IsNullOrEmpty($NpuPlatform.NpuDriverZipName)) {
        throw 'Resolve-AmdNpuDriverUrl: NpuPlatform.NpuDriverZipName is empty; Get-AmdNpuPlatform was not called or produced an incomplete result.'
    }
    $expectedZipName = $NpuPlatform.NpuDriverZipName

    $downloadDir = $Script:DownloadDir
    if (-not (Test-Path $downloadDir)) {
        New-Item -Path $downloadDir -ItemType Directory -Force | Out-Null
    }

    # ------------------------------------------------------------------------
    # Tier 1: -InstallerUrl explicit URL
    # ------------------------------------------------------------------------
    if (-not [string]::IsNullOrEmpty($ExplicitInstallerUrl)) {
        Write-SubHeader 'Tier 1: Explicit -InstallerUrl provided'
        Write-Step ("Source URL: {0}" -f $ExplicitInstallerUrl)
        $localZipPath = Join-Path $downloadDir $expectedZipName
        try {
            $result = Invoke-NpuZipDownload -Url $ExplicitInstallerUrl -OutFile $localZipPath
            if ($result) {
                return @{
                    SourceType = 'ExplicitUrl'
                    LocalPath  = $localZipPath
                    SourceUrl  = $ExplicitInstallerUrl
                }
            }
        } catch {
            Write-Fail ("Tier 1 download failed: {0}" -f $_.Exception.Message)
        }
        Write-Warn2 'Tier 1 failed. Falling through to next tier.'
    }

    # ------------------------------------------------------------------------
    # Tier 4 (priority before Tier 2/3): -OfflineZip path
    # ------------------------------------------------------------------------
    if (-not [string]::IsNullOrEmpty($ExplicitOfflineZip)) {
        Write-SubHeader 'Tier 4 (offline): -OfflineZip provided'
        if (Test-Path $ExplicitOfflineZip) {
            Write-Ok ("Using offline ZIP: {0}" -f $ExplicitOfflineZip)
            $cachedPath = Join-Path $downloadDir (Split-Path $ExplicitOfflineZip -Leaf)
            try {
                Copy-Item -Path $ExplicitOfflineZip -Destination $cachedPath -Force
            } catch {
                # If copy fails (same file etc), use original
                $cachedPath = $ExplicitOfflineZip
            }
            return @{
                SourceType = 'LocalCache'
                LocalPath  = $cachedPath
                SourceUrl  = $null
            }
        } else {
            Write-Fail ("Specified -OfflineZip path does not exist: {0}" -f $ExplicitOfflineZip)
        }
    }

    # ------------------------------------------------------------------------
    # Tier 2: AMD account auto-download (if credentials provided)
    # ------------------------------------------------------------------------
    if (-not [string]::IsNullOrEmpty($AmdAccountUser) -and $AmdAccountPassword) {
        Write-SubHeader 'Tier 2: AMD account auto-download'
        Write-Step ("Account user: {0}" -f $AmdAccountUser)
        Write-Warn2 'NOTE: Tier 2 attempts to authenticate against account.amd.com,'
        Write-Warn2 '      accept the Ryzen AI EULA, and fetch the ZIP via dynamic URL.'
        Write-Warn2 '      AMD periodically changes form layouts; if this fails, use Tier 1 or 4.'
        try {
            $authResult = Invoke-AmdAccountAuthentication `
                -Username $AmdAccountUser `
                -Password $AmdAccountPassword `
                -DriverFilename $expectedZipName

            if ($authResult -and $authResult.DownloadUrl) {
                $localZipPath = Join-Path $downloadDir $expectedZipName
                Write-Ok ("Resolved authenticated download URL")
                $result = Invoke-NpuZipDownload `
                    -Url $authResult.DownloadUrl `
                    -OutFile $localZipPath `
                    -WebSession $authResult.Session
                if ($result) {
                    return @{
                        SourceType = 'AmdAuthenticated'
                        LocalPath  = $localZipPath
                        SourceUrl  = $authResult.DownloadUrl
                    }
                }
            }
        } catch {
            Write-Fail ("Tier 2 authenticated download failed: {0}" -f $_.Exception.Message)
        }
        Write-Warn2 'Tier 2 failed. Falling through to next tier.'
    }

    # ------------------------------------------------------------------------
    # Tier 3: AMD EULA-gated direct fetch probe
    # ------------------------------------------------------------------------
    Write-SubHeader 'Tier 3: AMD EULA-gated direct fetch probe'
    $eulaUrl = "https://account.amd.com/en/forms/downloads/ryzenai-eula-public-xef.html?filename=$expectedZipName"
    Write-Step ("Probing: {0}" -f $eulaUrl)
    Write-Skip 'NOTE: This URL is normally a HTML form page that requires JS-driven submission.'
    Write-Skip '      The probe will likely receive HTML rather than ZIP bytes; falls through.'

    try {
        $head = Invoke-WebRequest -Uri $eulaUrl -Method Head -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        $contentType = $head.Headers['Content-Type']
        if ($contentType -match 'application/(zip|octet-stream)') {
            Write-Ok ("EULA-gated URL responded with Content-Type: {0}" -f $contentType)
            $localZipPath = Join-Path $downloadDir $expectedZipName
            $dl = Invoke-NpuZipDownload -Url $eulaUrl -OutFile $localZipPath
            if ($dl) {
                return @{
                    SourceType = 'EulaGatedDirect'
                    LocalPath  = $localZipPath
                    SourceUrl  = $eulaUrl
                }
            }
        } else {
            Write-Skip ("Probe Content-Type: {0} (not a ZIP, expected behaviour)" -f $contentType)
        }
    } catch {
        Write-Skip ("Probe failed (expected for EULA-gated form): {0}" -f $_.Exception.Message)
    }

    # ------------------------------------------------------------------------
    # Tier 4 fallback: scan for sibling ZIP files
    # ------------------------------------------------------------------------
    Write-SubHeader 'Tier 4 (auto-scan): looking for local ZIP cache'

    $searchPaths = @(
        $PSScriptRoot,                                                # script directory
        (Join-Path $PSScriptRoot 'cache'),                            # ./cache subdirectory
        $downloadDir,                                                 # workspace download dir
        (Join-Path $env:USERPROFILE 'Downloads')                      # user Downloads
    ) | Where-Object { -not [string]::IsNullOrEmpty($_) -and (Test-Path $_) } | Select-Object -Unique

    foreach ($searchPath in $searchPaths) {
        Write-Skip ("Scanning: {0}" -f $searchPath)

        # First preference: exact filename match
        $exactMatch = Get-ChildItem -Path $searchPath -Filter $expectedZipName -File -ErrorAction SilentlyContinue
        if ($exactMatch) {
            Write-Ok ("Found exact match: {0}" -f $exactMatch.FullName)
            $localZipPath = Join-Path $downloadDir $expectedZipName
            try {
                if ($exactMatch.FullName -ne $localZipPath) {
                    Copy-Item -Path $exactMatch.FullName -Destination $localZipPath -Force
                }
            } catch {
                $localZipPath = $exactMatch.FullName
            }
            return @{
                SourceType = 'LocalCache'
                LocalPath  = $localZipPath
                SourceUrl  = $null
            }
        }

        # Second preference: any NPU_RAI*_WHQL.zip
        $patternMatch = Get-ChildItem -Path $searchPath -Filter 'NPU_RAI*_WHQL.zip' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($patternMatch) {
            Write-Ok ("Found pattern match (newest): {0}" -f $patternMatch.FullName)
            Write-Warn2 ("Note: filename does not match expected '{0}' for current platform." -f $expectedZipName)
            Write-Warn2 '      Verify the version is compatible with your NPU codename before proceeding.'
            $localZipPath = Join-Path $downloadDir $patternMatch.Name
            try {
                if ($patternMatch.FullName -ne $localZipPath) {
                    Copy-Item -Path $patternMatch.FullName -Destination $localZipPath -Force
                }
            } catch {
                $localZipPath = $patternMatch.FullName
            }
            return @{
                SourceType = 'LocalCache'
                LocalPath  = $localZipPath
                SourceUrl  = $null
            }
        }
    }

    # ------------------------------------------------------------------------
    # All tiers exhausted
    # ------------------------------------------------------------------------
    Write-Fail 'All 4 download tiers exhausted; no NPU driver ZIP could be obtained.'
    Write-Host ''
    Write-Warn2 'How to obtain the NPU driver ZIP manually:'
    Write-Host ''
    Write-Host '  1. Visit AMD Ryzen AI installation guide:' -ForegroundColor White
    Write-Host '     https://ryzenai.docs.amd.com/en/latest/inst.html#install-npu-drivers' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  2. Click the link for your target Ryzen AI version (e.g. NPU Driver 32.0.203.314):' -ForegroundColor White
    Write-Host ('     {0}' -f "https://account.amd.com/en/forms/downloads/ryzenai-eula-public-xef.html?filename=$expectedZipName") -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  3. Sign in to your AMD account, accept the Ryzen AI EULA, and download.' -ForegroundColor White
    Write-Host ''
    Write-Host '  4. Re-run this script with one of:' -ForegroundColor White
    Write-Host ("     -OfflineZip <path>  (e.g. -OfflineZip .\{0})" -f $expectedZipName) -ForegroundColor Cyan
    Write-Host '     -InstallerUrl <url> (the dynamically-generated download URL after EULA accept)' -ForegroundColor Cyan
    Write-Host '     -AmdAccountUser <email> -AmdAccountPassword <SecureString>' -ForegroundColor Cyan
    Write-Host ''
    throw 'NPU driver ZIP could not be located via any tier.'
}

function Invoke-NpuZipDownload {
    <#
    .SYNOPSIS
        Downloads a ZIP from a URL with progress reporting and basic content-type validation.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile,
        [Microsoft.PowerShell.Commands.WebRequestSession]$WebSession
    )

    Write-Step ("Downloading: {0}" -f $Url)
    Write-Skip ("Output file: {0}" -f $OutFile)

    # Force fresh download
    if (Test-Path $OutFile) {
        Remove-Item $OutFile -Force
    }

    $start = Get-Date
    try {
        $iwrParams = @{
            Uri             = $Url
            OutFile         = $OutFile
            UseBasicParsing = $true
            TimeoutSec      = 600
            ErrorAction     = 'Stop'
        }
        if ($WebSession) {
            $iwrParams.WebSession = $WebSession
        }
        Invoke-WebRequest @iwrParams
    } catch {
        Write-Fail ("Download failed: {0}" -f $_.Exception.Message)
        return $false
    }

    if (-not (Test-Path $OutFile)) {
        Write-Fail 'Download completed but file is missing.'
        return $false
    }

    $size = (Get-Item $OutFile).Length
    if ($size -lt 1MB) {
        Write-Warn2 ("Downloaded file is suspiciously small: {0} bytes" -f $size)
        Write-Skip 'Inspecting first 256 bytes for HTML/error content...'
        $head = [System.IO.File]::ReadAllBytes($OutFile) | Select-Object -First 256
        $headText = -join ($head | ForEach-Object { [char]$_ })
        if ($headText -match '(?i)<html|<!DOCTYPE') {
            Write-Fail 'Downloaded content appears to be HTML rather than ZIP bytes.'
            Write-Fail 'This typically means EULA acceptance is required (use Tier 2 or 4).'
            Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
            return $false
        }
    }

    # Verify ZIP magic bytes (PK\x03\x04)
    $bytes = New-Object byte[] 4
    $fs = [System.IO.File]::OpenRead($OutFile)
    try {
        $null = $fs.Read($bytes, 0, 4)
    } finally {
        $fs.Close()
    }
    if (-not ($bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B)) {
        Write-Fail 'Downloaded file is not a valid ZIP (missing PK magic bytes).'
        Remove-Item $OutFile -Force -ErrorAction SilentlyContinue
        return $false
    }

    $duration = ((Get-Date) - $start).TotalSeconds
    $sizeMB = [Math]::Round($size / 1MB, 2)
    $rateMBps = if ($duration -gt 0) { [Math]::Round($sizeMB / $duration, 2) } else { 0 }
    Write-Ok ("Downloaded {0} MB in {1:n1}s ({2} MB/s)" -f $sizeMB, $duration, $rateMBps)
    return $true
}

function Invoke-AmdAccountAuthentication {
    <#
    .SYNOPSIS
        Attempts to authenticate against account.amd.com and return a download session for the
        specified Ryzen AI driver ZIP.
    .DESCRIPTION
        AMD's download flow is a multi-step HTML form sequence:
          1. POST credentials to login endpoint, receive session cookies
          2. GET the EULA acceptance form for the target filename
          3. POST EULA acceptance to receive a time-limited dynamic download URL
          4. Optionally follow Location header / poll for download readiness

        VERIFICATION RESULT (2026-05-10):
        Public-facing pages on account.amd.com / docs.amd.com return HTML payloads that
        require JavaScript to render and submit forms (consistent with Salesforce
        Lightning / SPA architecture). Direct PowerShell HTTP form POST is therefore
        unlikely to succeed for the following reasons:

          * Login forms are likely XHR-driven; CSRF tokens are dynamically injected
            by JS and not present in the initial HTML response.
          * Session state may include JS-managed bearer tokens or specific Origin/
            Referer headers that PowerShell's WebRequestSession does not replicate.
          * Multi-step OAuth/SAML redirects may be involved between login.html and
            forms/downloads/ (no public documentation of the back-end auth provider).
          * EULA acceptance for Ryzen AI is interactive ("sign the Beta Software EULA"
            per AMD Ryzen AI on-boarding documentation and end-user reports).

        End-user evidence:
          * github.com/amd/RyzenAI-SW#249 confirms AMD account login is required
          * github.com/amd/RyzenAI-SW#328 confirms users still hit interactive forms
          * No publicly available PowerShell/Python implementation has been found
            that drives this flow successfully.

        IMPLEMENTATION DECISION:
        This function is retained as a best-effort fallback only. It will print an
        explicit "verification result" banner and return $null without attempting
        the request unless -ForceAmdAccountAuth is set. The default code path is
        Tier 4 (-OfflineZip) per the verified-working pattern in TESTING.md §4.3.

        If AMD changes their account portal to expose an HTTP-form-friendly endpoint
        in the future, remove the early-return below and re-enable the form posts.
    .OUTPUTS
        Hashtable with keys: DownloadUrl (string), Session (WebRequestSession), or $null on failure.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Username,
        [Parameter(Mandatory)][System.Security.SecureString]$Password,
        [Parameter(Mandatory)][string]$DriverFilename
    )

    Write-Step 'Initiating AMD account authentication flow...'
    Write-Warn2 '------------------------------------------------------------'
    Write-Warn2 'VERIFIED 2026-05-10: account.amd.com is a JavaScript-driven SPA.'
    Write-Warn2 'PowerShell HTTP form POST is highly unlikely to succeed against'
    Write-Warn2 'this back-end. Tier 4 (-OfflineZip) is the recommended path.'
    Write-Warn2 '------------------------------------------------------------'

    if (-not $Script:ForceAmdAccountAuth) {
        Write-Fail 'Tier 2 (AMD account auto-download) is disabled by default since 2026-05-10.'
        Write-Skip 'Pass -ForceAmdAccountAuth to attempt anyway (best-effort, expected to fail).'
        Write-Skip 'Recommended: download the ZIP manually and use -OfflineZip <path>.'
        return $null
    }

    Write-Warn2 '-ForceAmdAccountAuth specified; attempting form-based auth (will likely fail).'

    # Convert SecureString -> plaintext (necessary for HTTP form post)
    $cred = New-Object System.Net.NetworkCredential('', $Password)
    $plainPassword = $cred.Password

    # Step 1: Establish a web session and visit the public EULA page
    $eulaUrl = "https://account.amd.com/en/forms/downloads/ryzenai-eula-public-xef.html?filename=$DriverFilename"
    $loginUrl = 'https://account.amd.com/en/forms/auth/login.html'
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $session.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36'

    try {
        Write-Skip ("Step 1: GET {0}" -f $eulaUrl)
        $eulaPage = Invoke-WebRequest -Uri $eulaUrl `
            -WebSession $session `
            -UseBasicParsing `
            -TimeoutSec 30 `
            -ErrorAction Stop

        Write-Skip ("EULA page returned {0} bytes, HTTP {1}" -f $eulaPage.RawContentLength, $eulaPage.StatusCode)

        # Look for login form action / hidden CSRF tokens
        $csrfMatch = [regex]::Match($eulaPage.Content, 'name="(?:_csrf|csrf_token|authenticity_token)"\s+value="([^"]+)"')
        $csrfToken = if ($csrfMatch.Success) { $csrfMatch.Groups[1].Value } else { $null }

        if ($csrfToken) {
            Write-Skip 'CSRF token discovered (length redacted)'
        } else {
            Write-Skip 'No CSRF token in EULA page; proceeding without one'
        }
    } catch {
        Write-Warn2 ("Step 1 failed: {0}" -f $_.Exception.Message)
        return $null
    }

    # Step 2: POST credentials to login endpoint
    try {
        Write-Skip ("Step 2: POST credentials to {0}" -f $loginUrl)
        $loginBody = @{
            'email'      = $Username
            'password'   = $plainPassword
            'rememberMe' = 'false'
        }
        if ($csrfToken) {
            $loginBody['_csrf'] = $csrfToken
        }

        $loginResp = Invoke-WebRequest -Uri $loginUrl `
            -Method Post `
            -Body $loginBody `
            -WebSession $session `
            -UseBasicParsing `
            -TimeoutSec 30 `
            -ErrorAction Stop

        # Check for typical login failure markers
        if ($loginResp.Content -match '(?i)invalid (?:email|password|credentials)|login failed|authentication failed') {
            Write-Fail 'AMD account authentication failed (invalid credentials or form change).'
            return $null
        }

        if ($loginResp.StatusCode -ne 200 -and $loginResp.StatusCode -ne 302) {
            Write-Fail ("Unexpected login response: HTTP {0}" -f $loginResp.StatusCode)
            return $null
        }
        Write-Ok ("Login response: HTTP {0}" -f $loginResp.StatusCode)
    } catch {
        Write-Fail ("Step 2 (login POST) failed: {0}" -f $_.Exception.Message)
        Write-Skip 'AMD may have updated their login endpoint structure.'
        return $null
    } finally {
        # Clear plaintext password from local scope ASAP
        $plainPassword = $null
    }

    # Step 3: Re-fetch EULA page authenticated, find the download form
    try {
        Write-Skip ("Step 3: Re-fetch EULA page authenticated")
        $eulaAuth = Invoke-WebRequest -Uri $eulaUrl `
            -WebSession $session `
            -UseBasicParsing `
            -TimeoutSec 30 `
            -ErrorAction Stop

        # Look for the EULA accept form action and any required fields
        $formActionMatch = [regex]::Match($eulaAuth.Content, '<form[^>]+action="([^"]+)"[^>]*>')
        if (-not $formActionMatch.Success) {
            Write-Warn2 'Could not locate EULA acceptance form action.'
            return $null
        }
        $formAction = $formActionMatch.Groups[1].Value
        if ($formAction -notmatch '^https?://') {
            $formAction = 'https://account.amd.com' + $formAction
        }
        Write-Skip ("EULA form action: {0}" -f $formAction)

        # Re-extract CSRF token from authenticated page
        $csrfMatch2 = [regex]::Match($eulaAuth.Content, 'name="(?:_csrf|csrf_token|authenticity_token)"\s+value="([^"]+)"')
        $csrfToken2 = if ($csrfMatch2.Success) { $csrfMatch2.Groups[1].Value } else { $null }

        # Step 4: POST EULA acceptance
        Write-Skip 'Step 4: POST EULA acceptance'
        $acceptBody = @{
            'filename'      = $DriverFilename
            'accept_eula'   = '1'
            'accept_terms'  = 'on'
        }
        if ($csrfToken2) {
            $acceptBody['_csrf'] = $csrfToken2
        }

        $acceptResp = Invoke-WebRequest -Uri $formAction `
            -Method Post `
            -Body $acceptBody `
            -WebSession $session `
            -UseBasicParsing `
            -TimeoutSec 60 `
            -MaximumRedirection 0 `
            -ErrorAction SilentlyContinue

        $location = $null
        if ($acceptResp -and $acceptResp.Headers.ContainsKey('Location')) {
            $location = $acceptResp.Headers['Location']
        } elseif ($acceptResp -and $acceptResp.Content -match 'href="(https?://[^"]*\.zip[^"]*)"') {
            $location = $Matches[1]
        }

        if (-not $location) {
            # Try matching entitlenow.com pattern (AMD's CDN)
            if ($acceptResp -and $acceptResp.Content -match 'https?://[\w\.\-]*entitlenow\.com/[^"\s]+\.zip[^"\s]*') {
                $location = $Matches[0]
            }
        }

        if (-not $location) {
            Write-Warn2 'Could not extract download URL from EULA acceptance response.'
            Write-Skip 'AMD may use JS-driven URL generation or has changed the response structure.'
            return $null
        }

        Write-Ok ('Resolved authenticated download URL (entitlenow.com CDN)')
        return @{
            DownloadUrl = $location
            Session     = $session
        }
    } catch {
        Write-Fail ("Step 3/4 (EULA accept) failed: {0}" -f $_.Exception.Message)
        return $null
    }
}
# =============================================================================
# Tool acquisition (Windows SDK signtool, Windows WDK inf2cat, 7-Zip) — Phase P02
# Same toolchain as chipset/graphics sister scripts for maintenance parity.
# =============================================================================

function Test-CommandExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Find-ToolPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$ToolFilename,
        [Parameter(Mandatory)][string[]]$SearchRoots
    )
    foreach ($root in $SearchRoots) {
        if (-not (Test-Path $root)) { continue }
        $hit = Get-ChildItem -Path $root -Filter $ToolFilename -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\x64\\' -or $_.FullName -match '\\amd64\\' } |
            Sort-Object @{Expression={$_.VersionInfo.FileVersion};Descending=$true}, LastWriteTime -Descending |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    return $null
}

function Find-SignToolPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $roots = @(
        'C:\Program Files (x86)\Windows Kits\10\bin',
        'C:\Program Files\Windows Kits\10\bin',
        'C:\Program Files (x86)\Windows Kits\11\bin',
        'C:\Program Files\Windows Kits\11\bin'
    )
    return Find-ToolPath -ToolFilename 'signtool.exe' -SearchRoots $roots
}

function Find-Inf2CatPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $roots = @(
        'C:\Program Files (x86)\Windows Kits\10\bin',
        'C:\Program Files\Windows Kits\10\bin',
        'C:\Program Files (x86)\Windows Kits\11\bin'
    )
    return Find-ToolPath -ToolFilename 'inf2cat.exe' -SearchRoots $roots
}

function Find-SevenZipPath {
    <#
    .SYNOPSIS
        Locates 7z.exe in the standard 7-Zip install paths or on PATH.
    .NOTES
        Same lookup strategy as the chipset and graphics sister scripts.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Standard install paths (in priority order)
    $candidates = @(
        'C:\Program Files\7-Zip\7z.exe',
        'C:\Program Files (x86)\7-Zip\7z.exe',
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe"
    )
    foreach ($p in $candidates) {
        if (-not [string]::IsNullOrEmpty($p) -and (Test-Path $p)) {
            return $p
        }
    }
    # Fall back to PATH lookup
    $cmd = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    return $null
}

function Install-RequiredTools {
    <#
    .SYNOPSIS
        Ensures Windows SDK (signtool), Windows WDK (inf2cat), and 7-Zip are available.
    .DESCRIPTION
        Same toolchain as the chipset and graphics sister scripts. 7-Zip is required
        for ZIP extraction in P04 to maintain parity with the EXE / nested-CAB extraction
        flows used by the chipset and graphics scripts.
    #>
    [CmdletBinding()]
    param()

    Write-SubHeader2 'Step 1/3: signtool.exe (Windows SDK)'
    $signtool = Find-SignToolPath
    if ($signtool) {
        Write-Ok ("signtool found: {0}" -f $signtool)
    } else {
        Write-Warn2 'signtool not found. Installing Windows SDK via winget...'
        try {
            $wingetCmd = Get-Command winget -ErrorAction Stop
            $procArgs = '--id Microsoft.WindowsSDK --silent --accept-package-agreements --accept-source-agreements --disable-interactivity'
            $proc = Start-Process -FilePath $wingetCmd.Source `
                -ArgumentList ('install ' + $procArgs).Split(' ') `
                -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Ok 'Windows SDK installed via winget.'
            } else {
                Write-Warn2 ("winget exit code: {0}; checking for signtool again..." -f $proc.ExitCode)
            }
        } catch {
            Write-Warn2 ("winget unavailable or failed: {0}" -f $_.Exception.Message)
            Write-Warn2 'Manually install Windows 10/11 SDK from:'
            Write-Warn2 '  https://learn.microsoft.com/en-us/windows-hardware/drivers/download-the-wdk'
        }
        $signtool = Find-SignToolPath
        if (-not $signtool) {
            throw 'signtool.exe not found after install attempt.'
        }
        Write-Ok ("signtool now available at: {0}" -f $signtool)
    }

    Write-SubHeader2 'Step 2/3: inf2cat.exe (Windows WDK)'
    $inf2cat = Find-Inf2CatPath
    if ($inf2cat) {
        Write-Ok ("inf2cat found: {0}" -f $inf2cat)
    } else {
        Write-Warn2 'inf2cat not found. Installing Windows WDK via winget (~2.5 GB)...'
        try {
            $wingetCmd = Get-Command winget -ErrorAction Stop
            $procArgs = '--id Microsoft.WindowsWDK --silent --accept-package-agreements --accept-source-agreements --disable-interactivity'
            $proc = Start-Process -FilePath $wingetCmd.Source `
                -ArgumentList ('install ' + $procArgs).Split(' ') `
                -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Ok 'Windows WDK installed via winget.'
            } else {
                Write-Warn2 ("winget exit code: {0}; checking for inf2cat again..." -f $proc.ExitCode)
            }
        } catch {
            Write-Warn2 ("winget unavailable or failed: {0}" -f $_.Exception.Message)
            Write-Warn2 'Manually install Windows 10/11 WDK from:'
            Write-Warn2 '  https://learn.microsoft.com/en-us/windows-hardware/drivers/download-the-wdk'
        }
        $inf2cat = Find-Inf2CatPath
        if (-not $inf2cat) {
            throw 'inf2cat.exe not found after install attempt.'
        }
        Write-Ok ("inf2cat now available at: {0}" -f $inf2cat)
    }

    Write-SubHeader2 'Step 3/3: 7z.exe (7-Zip)'
    $sevenZip = Find-SevenZipPath
    if ($sevenZip) {
        Write-Ok ("7-Zip found: {0}" -f $sevenZip)
    } else {
        Write-Warn2 '7-Zip not found. Installing via winget...'
        try {
            $wingetCmd = Get-Command winget -ErrorAction Stop
            $procArgs = '--id 7zip.7zip --silent --accept-package-agreements --accept-source-agreements --disable-interactivity'
            $proc = Start-Process -FilePath $wingetCmd.Source `
                -ArgumentList ('install ' + $procArgs).Split(' ') `
                -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Ok '7-Zip installed via winget.'
            } else {
                Write-Warn2 ("winget exit code: {0}; checking for 7-Zip again..." -f $proc.ExitCode)
            }
        } catch {
            Write-Warn2 ("winget unavailable or failed: {0}" -f $_.Exception.Message)
            Write-Warn2 'Manually install 7-Zip from:'
            Write-Warn2 '  https://www.7-zip.org/'
        }
        $sevenZip = Find-SevenZipPath
        if (-not $sevenZip) {
            throw '7z.exe not found after install attempt.'
        }
        Write-Ok ("7-Zip now available at: {0}" -f $sevenZip)
    }

    return @{
        SignTool = $signtool
        Inf2Cat  = $inf2cat
        SevenZip = $sevenZip
    }
}

# =============================================================================
# ZIP extraction (P04) - NPU specific, using 7-Zip for parity with sister scripts
# =============================================================================
function Expand-AmdNpuPackage {
    <#
    .SYNOPSIS
        Extracts the NPU driver ZIP using 7-Zip, handling potential nested ZIPs.
    .DESCRIPTION
        Uses 7z.exe x (extract with full paths) for consistency with the chipset and
        graphics sister scripts. 7-Zip handles ZIP, ZIPX, embedded CAB and other formats
        that PowerShell's native Expand-Archive does not, and produces deterministic
        output across PowerShell versions.
    .PARAMETER ZipPath
        Path to the source ZIP archive.
    .PARAMETER DestinationDir
        Directory to extract into (will be cleaned and recreated).
    .PARAMETER SevenZipPath
        Full path to 7z.exe (resolved by Find-SevenZipPath in P02).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$ZipPath,
        [Parameter(Mandatory)][string]$DestinationDir,
        [Parameter(Mandatory)][string]$SevenZipPath
    )

    if (-not (Test-Path $ZipPath)) {
        throw "ZIP file not found: $ZipPath"
    }
    if (-not (Test-Path $SevenZipPath)) {
        throw "7-Zip executable not found at: $SevenZipPath"
    }

    Write-Step ("Extracting (7-Zip): {0}" -f $ZipPath)
    Write-Skip ("Destination       : {0}" -f $DestinationDir)
    Write-Skip ("7-Zip executable  : {0}" -f $SevenZipPath)

    # Clean destination
    if (Test-Path $DestinationDir) {
        Remove-Item -Path $DestinationDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -Path $DestinationDir -ItemType Directory -Force | Out-Null

    # Run 7z.exe x with full paths, overwrite, no progress, no echo
    #   x       - extract with full paths
    #   -y      - assume yes on all queries
    #   -bso0   - disable standard-output messages (we still capture warnings/errors)
    #   -bsp0   - disable progress output
    #   -o<dir> - output directory (no space after -o per 7-Zip syntax)
    $sevenZipArgs = @(
        'x'
        $ZipPath
        ('-o' + $DestinationDir)
        '-y'
        '-bsp0'
    )
    $start = Get-Date
    $stdout = & $SevenZipPath @sevenZipArgs 2>&1
    $exitCode = $LASTEXITCODE
    $duration = ((Get-Date) - $start).TotalSeconds

    foreach ($line in $stdout) {
        if ($line -match '(?i)error|warning') {
            Write-Warn2 ("    {0}" -f $line)
        } else {
            Write-Skip ("    {0}" -f $line)
        }
    }

    # 7-Zip exit codes:
    #   0 = no error, 1 = warning (non-fatal), 2 = fatal error,
    #   7 = command-line error, 8 = out of memory, 255 = user cancel
    if ($exitCode -eq 0) {
        Write-Ok ("Initial extraction complete ({0:n1}s)." -f $duration)
    } elseif ($exitCode -eq 1) {
        Write-Warn2 ("7-Zip reported non-fatal warnings (exit {0}); continuing." -f $exitCode)
    } else {
        Write-Fail ("7-Zip extraction failed (exit code {0})." -f $exitCode)
        throw ("7-Zip extraction failed with exit code {0}" -f $exitCode)
    }

    # Inspect for nested ZIP files (some RAI 1.6+ packages ship nested)
    $nestedZips = Get-ChildItem -Path $DestinationDir -Filter '*.zip' -Recurse -File -ErrorAction SilentlyContinue
    if ($nestedZips) {
        foreach ($nz in $nestedZips) {
            Write-Step ("Nested ZIP detected: {0}" -f $nz.Name)
            $nestedDest = Join-Path $nz.DirectoryName ($nz.BaseName + '_extracted')
            $nestedArgs = @(
                'x'
                $nz.FullName
                ('-o' + $nestedDest)
                '-y'
                '-bsp0'
            )
            $nestedStdout = & $SevenZipPath @nestedArgs 2>&1
            $nestedExit = $LASTEXITCODE
            foreach ($line in $nestedStdout) {
                Write-Skip ("    {0}" -f $line)
            }
            if ($nestedExit -le 1) {
                Write-Skip ("Nested ZIP extracted to: {0}" -f $nestedDest)
            } else {
                Write-Warn2 ("Nested ZIP extraction failed (exit {0}); continuing." -f $nestedExit)
            }
        }
    }

    # Inventory the contents
    $infs   = Get-ChildItem -Path $DestinationDir -Filter '*.inf' -Recurse -File -ErrorAction SilentlyContinue
    $cats   = Get-ChildItem -Path $DestinationDir -Filter '*.cat' -Recurse -File -ErrorAction SilentlyContinue
    $syss   = Get-ChildItem -Path $DestinationDir -Filter '*.sys' -Recurse -File -ErrorAction SilentlyContinue
    $exes   = Get-ChildItem -Path $DestinationDir -Filter '*.exe' -Recurse -File -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Skip ("INF files : {0}" -f $infs.Count)
    foreach ($i in $infs) {
        Write-Skip ("    {0}  ({1:n0} bytes)" -f $i.Name, $i.Length)
    }
    Write-Skip ("CAT files : {0}" -f $cats.Count)
    Write-Skip ("SYS files : {0}" -f $syss.Count)
    Write-Skip ("EXE files : {0}" -f $exes.Count)

    if ($infs.Count -eq 0) {
        throw 'No .inf files found in extracted package. Aborting.'
    }

    return @{
        InfFiles     = $infs
        CatFiles     = $cats
        SysFiles     = $syss
        ExeFiles     = $exes
        ExtractedDir = $DestinationDir
    }
}

# =============================================================================
# INF parser core (P05/P06) — same logic as chipset r47, NPU-tuned
# =============================================================================
function Read-InfFileLines {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory)][string]$Path)
    # Try UTF-8 first, fall back to ASCII / Default for legacy INF encodings
    try {
        return [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
    } catch {
        try {
            return [System.IO.File]::ReadAllLines($Path)
        } catch {
            Write-Warn2 ("Could not read INF as UTF-8 or default: {0}" -f $Path)
            return @()
        }
    }
}

function Read-InfManufacturer {
    <#
    .SYNOPSIS
        Parses the [Manufacturer] section of an INF file.
    .DESCRIPTION
        Returns metadata about the manufacturer decorations:
          - HasServerDecoration  : INF already has ProductType=3 mirror entries
          - WorkstationEntries   : list of [Manufacturer] decorations without ProductType=3
          - HwidEntries          : extracted Hardware IDs from each decoration block
    .OUTPUTS
        Hashtable per the description above.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$InfPath)

    $lines = Read-InfFileLines -Path $InfPath
    $result = @{
        InfPath                 = $InfPath
        InfName                 = Split-Path $InfPath -Leaf
        ManufacturerSectionLines = @()
        ManufacturerDecorations  = @()  # array of strings like "AMD, NTamd64.10.0...26100"
        WorkstationDecorations   = @()  # subset that lacks ProductType=3
        ServerDecorations        = @()  # subset that has ProductType=3 (.3 suffix)
        HwidEntries              = @()
        HasServerDecoration      = $false
        DriverVer                = $null
        Provider                 = $null
        Class                    = $null
        ClassGuid                = $null
        SectionLineRanges        = @{}  # hash: section name -> @{Start; End}
    }

    if (-not $lines) { return $result }

    # First pass: build section index
    $currentSection = $null
    $sectionStart = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        # Skip comments
        $stripped = ($line -split ';', 2)[0].Trim()
        if ($stripped -match '^\[([^\]]+)\]$') {
            if ($currentSection) {
                $result.SectionLineRanges[$currentSection] = @{ Start = $sectionStart; End = ($i - 1) }
            }
            $currentSection = $Matches[1].Trim()
            $sectionStart = $i + 1
        }
    }
    if ($currentSection) {
        $result.SectionLineRanges[$currentSection] = @{ Start = $sectionStart; End = ($lines.Count - 1) }
    }

    # [Version] section parse
    if ($result.SectionLineRanges.ContainsKey('Version')) {
        $vRange = $result.SectionLineRanges['Version']
        for ($i = $vRange.Start; $i -le $vRange.End; $i++) {
            $line = $lines[$i].Trim()
            $stripped = ($line -split ';', 2)[0].Trim()
            if ($stripped -match '^DriverVer\s*=\s*(.+)$') {
                $result.DriverVer = $Matches[1].Trim()
            } elseif ($stripped -match '^Provider\s*=\s*(.+)$') {
                $result.Provider = $Matches[1].Trim()
            } elseif ($stripped -match '^Class\s*=\s*(.+)$') {
                $result.Class = $Matches[1].Trim()
            } elseif ($stripped -match '^ClassGuid\s*=\s*(.+)$') {
                $result.ClassGuid = $Matches[1].Trim()
            }
        }
    }

    # [Manufacturer] section parse
    if (-not $result.SectionLineRanges.ContainsKey('Manufacturer')) {
        return $result
    }
    $mRange = $result.SectionLineRanges['Manufacturer']
    for ($i = $mRange.Start; $i -le $mRange.End; $i++) {
        $line = $lines[$i]
        $result.ManufacturerSectionLines += $line
        $stripped = ($line -split ';', 2)[0].Trim()
        if ([string]::IsNullOrEmpty($stripped)) { continue }
        # Format: %ManufacturerName%=ManufacturerSection,decoration1,decoration2,...
        if ($stripped -match '^%[^%]+%\s*=\s*([^,]+)(?:,(.+))?$') {
            $sectionName = $Matches[1].Trim()
            $decorations = @()
            if ($Matches[2]) {
                $decorations = $Matches[2].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            }
            foreach ($dec in $decorations) {
                # Build full section name: e.g. "AMD.NTamd64.10.0...26100" or "AMD.NTamd64.10.0...26100.3"
                $fullSection = "$sectionName.$dec"
                $result.ManufacturerDecorations += $dec

                # Detect ProductType=3 decoration (ends in .3 after the build number)
                if ($dec -match '\.3$') {
                    $result.ServerDecorations += $dec
                    $result.HasServerDecoration = $true
                } else {
                    $result.WorkstationDecorations += $dec
                }

                # Find HWIDs in the decorated section
                if ($result.SectionLineRanges.ContainsKey($fullSection)) {
                    $hwidRange = $result.SectionLineRanges[$fullSection]
                    for ($j = $hwidRange.Start; $j -le $hwidRange.End; $j++) {
                        $hwidLine = $lines[$j]
                        $hwidStripped = ($hwidLine -split ';', 2)[0].Trim()
                        if ([string]::IsNullOrEmpty($hwidStripped)) { continue }
                        # Format: %DeviceDesc% = InstallSection, HWID
                        if ($hwidStripped -match '^%[^%]+%\s*=\s*[^,]+,\s*(.+)$') {
                            $hwidPart = $Matches[1].Trim()
                            # May have additional HWIDs separated by commas
                            $hwids = $hwidPart.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                            foreach ($hwid in $hwids) {
                                $result.HwidEntries += [pscustomobject]@{
                                    Decoration = $dec
                                    DecoratedSection = $fullSection
                                    HardwareId = $hwid
                                    LineNumber = $j + 1  # 1-indexed for human display
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return $result
}

function Add-ProductType3Decoration {
    <#
    .SYNOPSIS
        Patches an INF file to add ProductType=3 (Server) decorations mirroring existing
        Workstation entries in the [Manufacturer] section.
    .DESCRIPTION
        - Reads the original INF
        - For each Workstation decoration (e.g. "NTamd64.10.0...26100"), creates a Server
          mirror by appending ".3" (e.g. "NTamd64.10.0...26100.3") to [Manufacturer]
        - Duplicates the original [<sec>.<decoration>] block as [<sec>.<decoration>.3]
        - Writes the patched INF to a new path
    .OUTPUTS
        Hashtable with: Patched (bool), MirroredCount (int), OutputPath (string)
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$InputInfPath,
        [Parameter(Mandatory)][string]$OutputInfPath
    )

    $result = @{
        Patched       = $false
        MirroredCount = 0
        OutputPath    = $OutputInfPath
        Reason        = $null
    }

    $lines = Read-InfFileLines -Path $InputInfPath
    if (-not $lines -or $lines.Count -eq 0) {
        $result.Reason = 'Could not read INF file.'
        return $result
    }

    $inf = Read-InfManufacturer -InfPath $InputInfPath

    # Already has Server decorations? Just copy the file unchanged.
    if ($inf.HasServerDecoration -and $inf.WorkstationDecorations.Count -eq 0) {
        Write-Skip ("INF already has only Server decorations: {0}" -f (Split-Path $InputInfPath -Leaf))
        Copy-Item -Path $InputInfPath -Destination $OutputInfPath -Force
        $result.Reason = 'AlreadyServerCompatible'
        $result.Patched = $true
        return $result
    }

    # Workstation decorations exist — mirror them
    if ($inf.WorkstationDecorations.Count -eq 0) {
        $result.Reason = 'No [Manufacturer] decorations found.'
        Copy-Item -Path $InputInfPath -Destination $OutputInfPath -Force
        return $result
    }

    # Build new [Manufacturer] section content
    $newLines = New-Object 'System.Collections.Generic.List[string]'
    $manufacturerRange = $inf.SectionLineRanges['Manufacturer']

    # Write everything before [Manufacturer]
    if ($manufacturerRange.Start -gt 0) {
        for ($i = 0; $i -lt ($manufacturerRange.Start - 1); $i++) {
            $newLines.Add($lines[$i])
        }
    }
    $newLines.Add('[Manufacturer]')

    # Rewrite [Manufacturer] entries with appended .3 mirrors
    for ($i = $manufacturerRange.Start; $i -le $manufacturerRange.End; $i++) {
        $line = $lines[$i]
        $stripped = ($line -split ';', 2)[0].Trim()
        if ([string]::IsNullOrEmpty($stripped)) {
            $newLines.Add($line)
            continue
        }
        if ($stripped -match '^(%[^%]+%\s*=\s*)([^,]+)(?:,(.+))?$') {
            $prefix = $Matches[1]
            $sectionName = $Matches[2].Trim()
            $existingDecorations = @()
            if ($Matches[3]) {
                $existingDecorations = $Matches[3].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            }
            # Mirror each Workstation decoration with .3 if not already present
            $mirroredDecorations = @($existingDecorations)
            foreach ($dec in $existingDecorations) {
                if ($dec -match '\.3$') { continue }
                $mirror = "$dec.3"
                if ($mirroredDecorations -notcontains $mirror) {
                    $mirroredDecorations += $mirror
                    $result.MirroredCount++
                }
            }
            $newLine = "$prefix$sectionName"
            if ($mirroredDecorations.Count -gt 0) {
                $newLine += ',' + ($mirroredDecorations -join ',')
            }
            $newLines.Add($newLine)
        } else {
            $newLines.Add($line)
        }
    }

    # Write everything after [Manufacturer] up to where decorated sections start
    # We need to also duplicate each [Section.decoration] block as [Section.decoration.3]
    $afterManufacturerStart = $manufacturerRange.End + 1
    $duplicateBlocks = New-Object 'System.Collections.Generic.List[string]'

    # Identify which sections need duplication
    foreach ($section in $inf.SectionLineRanges.Keys) {
        # Only mirror sections that look like "<Mfgr>.NT*" or "<Mfgr>.NTamd64*" decoration sections
        # (skip InstallSection blocks like "<HWID>" which are referenced from these decorated sections)
        $matchedDecoration = $null
        foreach ($dec in $inf.WorkstationDecorations) {
            if ($section.EndsWith('.' + $dec)) {
                $matchedDecoration = $dec
                break
            }
        }
        if (-not $matchedDecoration) { continue }

        # Build the .3 mirror
        $mirroredSectionName = "$section.3"
        if ($inf.SectionLineRanges.ContainsKey($mirroredSectionName)) { continue }  # already exists

        $blockRange = $inf.SectionLineRanges[$section]
        $duplicateBlocks.Add('')
        $duplicateBlocks.Add("[$mirroredSectionName]")
        $duplicateBlocks.Add(';')
        $duplicateBlocks.Add('; ProductType=3 (Server) mirror auto-generated by Deploy-AMDNpuDriverOnWindowsServer.ps1')
        $duplicateBlocks.Add(';')
        for ($i = $blockRange.Start; $i -le $blockRange.End; $i++) {
            $duplicateBlocks.Add($lines[$i])
        }
    }

    # Write everything after [Manufacturer]
    for ($i = $afterManufacturerStart; $i -lt $lines.Count; $i++) {
        $newLines.Add($lines[$i])
    }
    # Append duplicate blocks at end
    foreach ($l in $duplicateBlocks) {
        $newLines.Add($l)
    }

    # Write output INF (use ASCII to preserve compatibility with inf2cat parser)
    $outputDir = Split-Path $OutputInfPath -Parent
    if (-not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllLines($OutputInfPath, $newLines.ToArray(), [System.Text.Encoding]::Unicode)

    $result.Patched = $true
    $result.Reason = ('Mirrored {0} decoration(s) with ProductType=3' -f $result.MirroredCount)
    return $result
}

function Test-InfProductTypeCoverage {
    <#
    .SYNOPSIS
        Verifies that a patched INF has ProductType=3 decorations for the expected build.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$InfPath,
        [int]$ExpectedBuild = 26100
    )
    $inf = Read-InfManufacturer -InfPath $InfPath
    $result = @{
        InfName            = $inf.InfName
        HasServerForBuild  = $false
        ServerDecorations  = $inf.ServerDecorations
        WorkstationOnly    = ($inf.WorkstationDecorations.Count -gt 0 -and $inf.ServerDecorations.Count -eq 0)
        Provider           = $inf.Provider
        DriverVer          = $inf.DriverVer
    }
    foreach ($srv in $inf.ServerDecorations) {
        $serverPattern = ('{0}\.3$' -f $ExpectedBuild)
        if ($srv -match $serverPattern) {
            $result.HasServerForBuild = $true
            break
        }
    }
    return $result
}
# =============================================================================
# Self-signed code-signing certificate (P07)
# =============================================================================
function New-SelfSignedCodeSigningCert {
    <#
    .SYNOPSIS
        Generates a self-signed code-signing certificate for NPU driver catalogs.
    .DESCRIPTION
        - RSA 4096-bit, SHA-384 signature
        - EKU: Code Signing (1.3.6.1.5.5.7.3.3)
        - Validity: $CertValidityYears (default 5)
        - Stored in CurrentUser\My (transient), exported to PFX/CER
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$PfxPath,
        [Parameter(Mandatory)][string]$CerPath,
        [string]$PfxPassword = '',
        [int]$ValidityYears = 5
    )

    $expiry = (Get-Date).AddYears($ValidityYears)

    Write-Step ('Creating self-signed cert: CN={0}' -f $Subject)
    Write-Skip ('Key       : RSA 4096-bit / SHA-384')
    Write-Skip ('EKU       : Code Signing (1.3.6.1.5.5.7.3.3)')
    Write-Skip ('Validity  : {0} years (until {1:yyyy-MM-dd})' -f $ValidityYears, $expiry)

    $params = @{
        Subject           = "CN=$Subject"
        Type              = 'CodeSigningCert'
        KeyUsage          = 'DigitalSignature'
        TextExtension     = @('2.5.29.37={text}1.3.6.1.5.5.7.3.3')
        KeyAlgorithm      = 'RSA'
        KeyLength         = 4096
        HashAlgorithm     = 'SHA384'
        CertStoreLocation = 'Cert:\CurrentUser\My'
        NotAfter          = $expiry
        FriendlyName      = $Subject
    }

    $cert = New-SelfSignedCertificate @params
    if (-not $cert) {
        throw 'New-SelfSignedCertificate returned null.'
    }

    $certDir = Split-Path $PfxPath -Parent
    if (-not (Test-Path $certDir)) {
        New-Item -Path $certDir -ItemType Directory -Force | Out-Null
    }

    # Export PFX
    $pfxSecure = if ([string]::IsNullOrEmpty($PfxPassword)) {
        ConvertTo-SecureString -String 'placeholder' -AsPlainText -Force
    } else {
        ConvertTo-SecureString -String $PfxPassword -AsPlainText -Force
    }
    if ([string]::IsNullOrEmpty($PfxPassword)) {
        # Empty password: export with placeholder, then re-encode without password
        Export-PfxCertificate -Cert $cert -FilePath $PfxPath -Password $pfxSecure -Force | Out-Null
    } else {
        Export-PfxCertificate -Cert $cert -FilePath $PfxPath -Password $pfxSecure -Force | Out-Null
    }

    # Export CER (public)
    Export-Certificate -Cert $cert -FilePath $CerPath -Force | Out-Null

    Write-Ok ('Cert thumbprint: {0}' -f $cert.Thumbprint)
    Write-Skip ('PFX exported   : {0}' -f $PfxPath)
    Write-Skip ('CER exported   : {0}' -f $CerPath)

    return @{
        Cert       = $cert
        Thumbprint = $cert.Thumbprint
        PfxPath    = $PfxPath
        CerPath    = $CerPath
        Expiry     = $expiry
    }
}

# =============================================================================
# inf2cat / signtool wrappers (P08 / P09)
# =============================================================================
function Invoke-Inf2Cat {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Inf2CatPath,
        [Parameter(Mandatory)][string]$DriverDir,
        [Parameter(Mandatory)][string]$OsSwitch
    )

    Write-Step ('inf2cat /driver:"{0}" /os:{1}' -f $DriverDir, $OsSwitch)
    $start = Get-Date
    $stdout = & $Inf2CatPath /driver:$DriverDir /os:$OsSwitch 2>&1
    $exitCode = $LASTEXITCODE
    $duration = ((Get-Date) - $start).TotalSeconds

    foreach ($line in $stdout) {
        Write-Skip ("    {0}" -f $line)
    }

    return @{
        ExitCode = $exitCode
        Duration = $duration
        Output   = $stdout
        Success  = ($exitCode -eq 0)
    }
}

function Invoke-SignTool {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$SignToolPath,
        [Parameter(Mandatory)][string]$CatPath,
        [Parameter(Mandatory)][string]$PfxPath,
        [string]$PfxPassword = '',
        [string]$TimestampUrl = 'http://timestamp.digicert.com',
        [string]$HashAlgo = 'SHA384'
    )

    $signArgs = @(
        'sign'
        '/fd', $HashAlgo
        '/td', $HashAlgo
        '/tr', $TimestampUrl
        '/f', $PfxPath
    )
    if (-not [string]::IsNullOrEmpty($PfxPassword)) {
        $signArgs += '/p'
        $signArgs += $PfxPassword
    }
    $signArgs += $CatPath

    $start = Get-Date
    $stdout = & $SignToolPath @signArgs 2>&1
    $exitCode = $LASTEXITCODE
    $duration = ((Get-Date) - $start).TotalSeconds

    foreach ($line in $stdout) {
        Write-Skip ("    {0}" -f $line)
    }

    return @{
        ExitCode = $exitCode
        Duration = $duration
        Output   = $stdout
        Success  = ($exitCode -eq 0)
    }
}

function Test-CatalogSignature {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$SignToolPath,
        [Parameter(Mandatory)][string]$CatPath
    )

    $stdout = & $SignToolPath verify /pa /v $CatPath 2>&1
    $exitCode = $LASTEXITCODE

    return @{
        ExitCode = $exitCode
        Output   = $stdout
        Success  = ($exitCode -eq 0)
    }
}

# =============================================================================
# WDAC supplemental policy (I02)
# =============================================================================
function New-WdacSupplementalPolicy {
    <#
    .SYNOPSIS
        Generates a WDAC supplemental Code Integrity policy that allowlists the self-signed
        code-signing cert as a kernel-mode signer.
    .DESCRIPTION
        Uses New-CIPolicy + Add-SignerRule + ConvertFrom-CIPolicy. The policy is
        Allow-by-default with our cert as additional kernel-mode signer.
        Deployment via CiTool --update-policy avoids the need for a reboot on
        Windows Server 2022+ / Windows 11 22H2+.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$CerPath,
        [Parameter(Mandatory)][string]$XmlOutputPath,
        [Parameter(Mandatory)][string]$BinOutputPath,
        [Parameter(Mandatory)][string]$PolicyName,
        [Parameter(Mandatory)][string]$PolicyGuid
    )

    Write-Step ('Building WDAC supplemental policy XML: {0}' -f $XmlOutputPath)

    # Start with the AllowAll template
    $allowAllTemplate = "$env:windir\schemas\CodeIntegrity\ExamplePolicies\AllowAll.xml"
    if (-not (Test-Path $allowAllTemplate)) {
        # Older systems may not have the template - try alternate path
        $allowAllTemplate = "$env:windir\schemas\CodeIntegrity\ExamplePolicies\AllowMicrosoft.xml"
    }
    if (-not (Test-Path $allowAllTemplate)) {
        throw "WDAC AllowAll/AllowMicrosoft template not found in $env:windir\schemas\CodeIntegrity\ExamplePolicies\"
    }

    Copy-Item -Path $allowAllTemplate -Destination $XmlOutputPath -Force

    # Add our cert as a signer rule (kernel + user mode allow)
    Add-SignerRule -FilePath $XmlOutputPath -CertificatePath $CerPath -Kernel -User
    Set-CIPolicyIdInfo -FilePath $XmlOutputPath -PolicyName $PolicyName -PolicyId $PolicyGuid -SupplementsBasePolicyID '{A244370E-44C9-4C06-B551-F6016E563076}' -ErrorAction SilentlyContinue

    # Set as supplemental policy
    Set-RuleOption -FilePath $XmlOutputPath -Option 0  # Enabled:UMCI
    Set-RuleOption -FilePath $XmlOutputPath -Option 16 # Enabled:Update Policy No Reboot

    # Convert to binary .cip
    Write-Step ('ConvertFrom-CIPolicy -> {0}' -f $BinOutputPath)
    ConvertFrom-CIPolicy -XmlFilePath $XmlOutputPath -BinaryFilePath $BinOutputPath | Out-Null

    return @{
        XmlPath    = $XmlOutputPath
        BinPath    = $BinOutputPath
        PolicyName = $PolicyName
        PolicyGuid = $PolicyGuid
    }
}

function Install-WdacPolicy {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$BinPath,
        [Parameter(Mandatory)][string]$PolicyGuid
    )

    $citool = Get-Command CiTool.exe -ErrorAction SilentlyContinue
    if ($citool) {
        Write-Step ('CiTool --update-policy "{0}"' -f $BinPath)
        $stdout = & $citool.Source --update-policy $BinPath 2>&1
        $exitCode = $LASTEXITCODE
        foreach ($line in $stdout) {
            Write-Skip ("    {0}" -f $line)
        }
        return @{
            ExitCode = $exitCode
            Output   = $stdout
            Success  = ($exitCode -eq 0)
            Method   = 'CiTool'
        }
    } else {
        # Older systems: copy CIP to active policy folder
        $activeDir = "$env:windir\System32\CodeIntegrity\CiPolicies\Active"
        if (-not (Test-Path $activeDir)) {
            New-Item -Path $activeDir -ItemType Directory -Force | Out-Null
        }
        $dest = Join-Path $activeDir ('{' + $PolicyGuid + '}.cip')
        Copy-Item -Path $BinPath -Destination $dest -Force
        Write-Warn2 'CiTool not available; copied .cip to Active policy directory.'
        Write-Warn2 'A reboot may be required for the policy to take effect.'
        return @{
            ExitCode = 0
            Output   = @('Copied to Active dir')
            Success  = $true
            Method   = 'FileCopy'
        }
    }
}

function Remove-WdacPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PolicyGuid)
    $citool = Get-Command CiTool.exe -ErrorAction SilentlyContinue
    if ($citool) {
        Write-Step ('CiTool --remove-policy {{{0}}}' -f $PolicyGuid)
        & $citool.Source --remove-policy ('{' + $PolicyGuid + '}') 2>&1 | ForEach-Object { Write-Skip ("    {0}" -f $_) }
    }
    # Also delete from Active dir if present
    $activePath = "$env:windir\System32\CodeIntegrity\CiPolicies\Active\{$PolicyGuid}.cip"
    if (Test-Path $activePath) {
        try {
            Remove-Item -Path $activePath -Force
            Write-Ok ('Removed: {0}' -f $activePath)
        } catch {
            Write-Warn2 ("Could not delete WDAC policy file: {0}" -f $_.Exception.Message)
        }
    }
}

# =============================================================================
# Driver install / cert trust (I01 / I03 / I04)
# =============================================================================
function Add-CertToTrustStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CerPath
    )

    Write-Step ('Importing cert to LocalMachine\Root')
    Import-Certificate -FilePath $CerPath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null

    Write-Step ('Importing cert to LocalMachine\TrustedPublisher')
    Import-Certificate -FilePath $CerPath -CertStoreLocation Cert:\LocalMachine\TrustedPublisher | Out-Null

    Write-Ok 'Cert successfully imported to LocalMachine trust stores.'
}

function Remove-CertFromTrustStore {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Thumbprint)
    foreach ($store in @('Cert:\LocalMachine\Root','Cert:\LocalMachine\TrustedPublisher')) {
        $cert = Get-ChildItem $store | Where-Object Thumbprint -EQ $Thumbprint
        if ($cert) {
            try {
                $cert | Remove-Item -Force
                Write-Ok ('Removed cert from {0}' -f $store)
            } catch {
                Write-Warn2 ("Could not remove cert from {0}: {1}" -f $store, $_.Exception.Message)
            }
        }
    }
}

function Install-PatchedDriver {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$InfPath
    )

    Write-Step ('pnputil /add-driver "{0}" /install' -f $InfPath)
    $stdout = & pnputil.exe /add-driver $InfPath /install 2>&1
    $exitCode = $LASTEXITCODE

    foreach ($line in $stdout) {
        Write-Skip ("    {0}" -f $line)
    }

    return @{
        ExitCode = $exitCode
        Output   = $stdout
        Success  = ($exitCode -eq 0 -or $exitCode -eq 259 -or $exitCode -eq 3010)
    }
}

# =============================================================================
# Driver version comparison (chipset r46 timezone fix preserved)
# =============================================================================
function ConvertFrom-DriverVerString {
    <#
    .SYNOPSIS
        Parses an INF DriverVer string into structured date + version.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$DriverVerString)

    $result = @{
        Date    = $null
        Version = $null
        Raw     = $DriverVerString
    }
    # Format: MM/DD/YYYY,Version (e.g. "07/08/2025,10.0.1.30")
    if ($DriverVerString -match '^(\d{1,2})/(\d{1,2})/(\d{4})\s*,\s*(.+)$') {
        try {
            $result.Date = [datetime]::ParseExact(
                ('{0:D2}/{1:D2}/{2}' -f [int]$Matches[1], [int]$Matches[2], $Matches[3]),
                'MM/dd/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
        } catch {
            # ignore
        }
        $vstr = $Matches[4].Trim()
        try {
            $result.Version = [version]$vstr
        } catch {
            $result.Version = $vstr
        }
    }
    return $result
}

function Compare-InfDriverVer {
    <#
    .SYNOPSIS
        Compares an installed driver's date/version (from Win32_PnPSignedDriver) vs a
        patched INF's DriverVer line.
    .NOTES
        Preserves chipset r46 fix: Win32_PnPSignedDriver.DriverDate is stored as UTC
        midnight; CIM cmdlets convert to local time. Comparing .Date truncates to
        year/month/day to avoid timezone-induced false positives.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [datetime]$CurrentDate,
        $CurrentVersion,
        [datetime]$PatchedDate,
        $PatchedVersion
    )
    # Use .Date (year/month/day truncation) to avoid timezone mismatch
    $cdate = if ($CurrentDate) { $CurrentDate.Date } else { $null }
    $pdate = if ($PatchedDate) { $PatchedDate.Date } else { $null }

    # Version comparison
    $vCmp = 0
    try {
        $cv = if ($CurrentVersion -is [version]) { $CurrentVersion } else { [version]$CurrentVersion }
        $pv = if ($PatchedVersion -is [version]) { $PatchedVersion } else { [version]$PatchedVersion }
        $vCmp = $cv.CompareTo($pv)
    } catch {
        $vCmp = 0  # treat as equal if not parseable
    }

    if ($vCmp -lt 0) {
        return 'UpgradePatched'  # patched newer than current
    }
    if ($vCmp -gt 0) {
        return 'CurrentNewer'
    }
    # versions equal — compare dates
    if ($cdate -and $pdate) {
        if ($pdate -gt $cdate) {
            return 'SameVersionPatchedDateNewer'   # PnP ranking prefers newer date
        }
        if ($pdate -lt $cdate) {
            return 'SameVersionCurrentDateNewer'
        }
    }
    return 'Identical'
}
# =============================================================================
# Phase implementations P00 - P09 (Prep)
# =============================================================================

function Invoke-PrepPhase00_Initialize {
    [CmdletBinding()]
    param()
    Write-Step 'Running environment and sanity checks'

    Show-PowerShellEnvironment
    Test-AdminPrivilege | Out-Null
    Set-NetworkProtocol

    $os = Show-OperatingSystemDetail
    $Script:DetectedPlatform.OsCaption       = $os.OsCaption
    $Script:DetectedPlatform.OsBuild         = $os.OsBuild
    $Script:DetectedPlatform.OsProductType   = $os.OsProductType
    $Script:DetectedPlatform.OsProfile       = $os.OsProfile
    $Script:DetectedPlatform.Inf2CatOsSwitch = $os.Inf2CatOsSwitch
    $Script:DetectedPlatform.IsWorkstationOs = $os.IsWorkstationOs
    $Script:DetectedPlatform.IsServer2025    = $os.IsServer2025

    # NPU-specific OS support warning
    Write-Host ''
    Write-SubHeader2 'Ryzen AI Software OS support note'
    Write-Warn2 'AMD officially supports Ryzen AI Software ONLY on Windows 11 (build >= 22621.3527).'
    Write-Warn2 'Windows Server 2025 is NOT in AMD''s supported OS matrix.'
    Write-Warn2 'This script patches the kernel-mode NPU driver to install on Server, but the'
    Write-Warn2 'user-mode Ryzen AI Software stack (conda env, OGA, Vitis AI EP) will likely'
    Write-Warn2 'not function on Server 2025 without unofficial workarounds.'
    Write-Host ''
}

function Invoke-PrepPhase01_PrepareWorkspace {
    [CmdletBinding()]
    param()

    if ($Script:CleanWorkRoot -and (Test-Path $Script:WorkRoot)) {
        Write-Step ("CleanWorkRoot: removing {0}" -f $Script:WorkRoot)
        Remove-Item -Path $Script:WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    foreach ($dir in @($Script:WorkRoot, $Script:DownloadDir, $Script:ExtractedDir, $Script:PatchedDir, $Script:CertDir)) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
            Write-Skip ("Created: {0}" -f $dir)
        } else {
            Write-Skip ("Existing: {0}" -f $dir)
        }
    }
    Write-Ok ("Workspace ready at: {0}" -f $Script:WorkRoot)
}

function Invoke-PrepPhase02_AcquireTools {
    [CmdletBinding()]
    param()
    Write-Step 'Acquiring signtool, inf2cat, and 7-Zip'
    $tools = Install-RequiredTools
    $Script:DetectedPlatform.SignToolPath = $tools.SignTool
    $Script:DetectedPlatform.Inf2CatPath  = $tools.Inf2Cat
    $Script:DetectedPlatform.SevenZipPath = $tools.SevenZip
}

function Invoke-PrepPhase03_FetchInstaller {
    [CmdletBinding()]
    param()
    Write-Step 'Detecting NPU platform and resolving installer source (4-tier fallback)'

    # ----- detect NPU platform
    Write-SubHeader2 'NPU platform detection'
    $npu = Get-AmdNpuPlatform `
        -Override $Script:NpuOverride `
        -AssumeIfMissing:$Script:AssumeIfMissing `
        -NpuDriverPackageSelection $Script:NpuDriverPackage `
        -RyzenAiSoftwareVersionSelection $Script:RyzenAiSoftwareVersion

    $Script:DetectedPlatform.NpuCodename             = $npu.NpuCodename
    $Script:DetectedPlatform.NpuShortName            = $npu.NpuShortName
    $Script:DetectedPlatform.NpuHardwareId           = $npu.HardwareId
    $Script:DetectedPlatform.NpuRevision             = $npu.Revision
    $Script:DetectedPlatform.NpuIsDetected           = $npu.IsDetected
    $Script:DetectedPlatform.NpuDetectionSource      = $npu.DetectionSource
    $Script:DetectedPlatform.CpuName                 = $npu.CpuName
    # NPU driver fields (independent axis)
    $Script:DetectedPlatform.NpuDriverPackage        = $npu.NpuDriverPackage
    $Script:DetectedPlatform.NpuDriverBuild          = $npu.NpuDriverBuild
    $Script:DetectedPlatform.NpuDriverZipName        = $npu.NpuDriverZipName
    # Ryzen AI Software fields (independent axis)
    $Script:DetectedPlatform.RyzenAiSoftwareVersion  = $npu.RyzenAiSoftwareVersion
    $Script:DetectedPlatform.RyzenAiSoftwareInstaller = $npu.RyzenAiSoftwareInstaller
    # Compatibility evaluation (separate axis)
    $Script:DetectedPlatform.DriverSoftwareCompatible = $npu.DriverSoftwareCompatible
    $Script:DetectedPlatform.DriverSoftwareCompatNote = $npu.DriverSoftwareCompatNote

    Write-Ok ('CPU                  : {0}' -f $npu.CpuName)
    Write-Ok ('NPU codename         : {0}' -f $npu.NpuCodename)
    Write-Ok ('NPU short name       : {0}' -f $npu.NpuShortName)
    Write-Ok ('Hardware ID          : {0}' -f $npu.HardwareId)
    Write-Ok ('Detection source     : {0}' -f $npu.DetectionSource)
    Write-Ok ('Detected on host     : {0}' -f $npu.IsDetected)
    Write-Host ''
    Write-Step '----- NPU kernel-mode driver (independent versioning axis) -----'
    Write-Ok ('NPU driver package   : {0}' -f $npu.NpuDriverPackage)
    Write-Ok ('NPU driver build     : {0}' -f $npu.NpuDriverBuild)
    Write-Ok ('NPU driver ZIP name  : {0}' -f $npu.NpuDriverZipName)
    Write-Host ''
    Write-Step '----- Ryzen AI Software (independent versioning axis - always latest unless pinned) -----'
    Write-Ok ('RAI Software version : {0}' -f $npu.RyzenAiSoftwareVersion)
    Write-Ok ('RAI Software EXE     : {0}' -f $npu.RyzenAiSoftwareInstaller)
    Write-Host ''
    Write-Step '----- Driver <-> RAI Software compatibility (separate evaluation axis) -----'
    if ($npu.DriverSoftwareCompatible) {
        Write-Ok ('Compatibility        : OK')
    } else {
        Write-Warn2 ('Compatibility        : MISMATCH')
    }
    Write-Skip ('Note                 : {0}' -f $npu.DriverSoftwareCompatNote)

    if (-not $npu.IsDetected) {
        Write-Host ''
        Write-Warn2 '------------------------------------------------------------------'
        Write-Warn2 'NPU was NOT detected on the host (proceeding with default profile).'
        Write-Warn2 'Driver Install (I03) will likely produce 0 device bindings here.'
        Write-Warn2 'This run is useful for pipeline regression testing only.'
        Write-Warn2 '------------------------------------------------------------------'
        Write-Host ''
    }

    # ----- resolve and download package
    Write-SubHeader2 'NPU driver package resolution & download'
    $resolved = Resolve-AmdNpuDriverUrl `
        -NpuPlatform $npu `
        -ExplicitInstallerUrl $Script:InstallerUrl `
        -ExplicitOfflineZip $Script:OfflineZip `
        -AmdAccountUser $Script:AmdAccountUser `
        -AmdAccountPassword $Script:AmdAccountPassword

    if (-not $resolved) {
        throw 'Could not resolve NPU driver package source.'
    }

    $Script:DetectedPlatform.DownloadedZipPath = $resolved.LocalPath
    $Script:DetectedPlatform.DownloadedZipName = Split-Path $resolved.LocalPath -Leaf
    $Script:DetectedPlatform.DownloadSourceType = $resolved.SourceType
    $Script:DetectedPlatform.DownloadSourceUrl  = $resolved.SourceUrl

    Write-Host ''
    Write-Ok ('Source type   : {0}' -f $resolved.SourceType)
    Write-Ok ('Local ZIP path: {0}' -f $resolved.LocalPath)
    if ($resolved.SourceUrl) {
        Write-Ok ('Source URL    : {0}' -f $resolved.SourceUrl)
    }
    $size = (Get-Item $resolved.LocalPath).Length
    Write-Ok ('Size          : {0:n1} MB' -f ($size / 1MB))
}

function Invoke-PrepPhase04_ExtractInstaller {
    [CmdletBinding()]
    param()

    if (-not $Script:DetectedPlatform.DownloadedZipPath) {
        throw 'No downloaded ZIP path; P03 did not complete successfully.'
    }
    if (-not $Script:DetectedPlatform.SevenZipPath) {
        throw 'No 7-Zip path; P02 did not complete successfully.'
    }

    $extracted = Expand-AmdNpuPackage `
        -ZipPath $Script:DetectedPlatform.DownloadedZipPath `
        -DestinationDir $Script:ExtractedDir `
        -SevenZipPath $Script:DetectedPlatform.SevenZipPath

    $Script:DetectedPlatform.ExtractedInfFiles = $extracted.InfFiles
    $Script:DetectedPlatform.ExtractedCatFiles = $extracted.CatFiles
    $Script:DetectedPlatform.ExtractedSysFiles = $extracted.SysFiles
    $Script:DetectedPlatform.ExtractedExeFiles = $extracted.ExeFiles
}

function Invoke-PrepPhase05_AnalyzeInfs {
    [CmdletBinding()]
    param()
    Write-Step 'Inventorying INFs and filtering for target NPU'

    $infs = $Script:DetectedPlatform.ExtractedInfFiles
    if (-not $infs -or $infs.Count -eq 0) {
        throw 'No INF files to analyze; P04 did not extract any.'
    }

    Write-Ok ('Found {0} INF file(s) in extracted package.' -f $infs.Count)

    $inventory = New-Object 'System.Collections.Generic.List[psobject]'
    foreach ($inf in $infs) {
        Write-Step ('Parsing: {0}' -f $inf.Name)
        $parsed = Read-InfManufacturer -InfPath $inf.FullName

        # Determine if this INF claims an HWID matching our target NPU
        $matchesTarget = $false
        $matchedHwids = @()
        $targetPattern = $null
        switch ($Script:DetectedPlatform.NpuShortName) {
            'PHX' { $targetPattern = 'VEN_1022&DEV_1502' }
            'HPT' { $targetPattern = 'VEN_1022&DEV_1502' }
            'STX' { $targetPattern = 'VEN_1022&DEV_17F0' }
            'KRK' { $targetPattern = 'VEN_1022&DEV_17F0' }
        }
        if (-not [string]::IsNullOrEmpty($targetPattern)) {
            foreach ($hwidEntry in $parsed.HwidEntries) {
                if ($hwidEntry.HardwareId -match $targetPattern) {
                    $matchesTarget = $true
                    $matchedHwids += $hwidEntry.HardwareId
                }
            }
        }

        $hwidPreview = if ($parsed.HwidEntries.Count -gt 0) {
            $parsed.HwidEntries | Select-Object -First 3 | ForEach-Object { $_.HardwareId } | Out-String
        } else { '(none)' }

        $entry = [pscustomobject]@{
            FileName             = $inf.Name
            FullPath             = $inf.FullName
            Provider             = $parsed.Provider
            DriverVer            = $parsed.DriverVer
            Class                = $parsed.Class
            HwidCount            = $parsed.HwidEntries.Count
            MatchesTargetNpu     = $matchesTarget
            MatchedHwidCount     = $matchedHwids.Count
            HasServerDecoration  = $parsed.HasServerDecoration
            WorkstationDecCount  = $parsed.WorkstationDecorations.Count
            ServerDecCount       = $parsed.ServerDecorations.Count
            NeedsPatch           = ($parsed.WorkstationDecorations.Count -gt 0)
            SelectedForPipeline  = $matchesTarget   # primary filter
            HwidPreview          = $hwidPreview.Trim()
        }
        $inventory.Add($entry)
    }

    Write-Host ''
    Write-SubHeader2 'INF inventory'
    $fmt = "{0,-30} {1,-12} {2,-7} {3,-9} {4,-9} {5,-9} {6,-7}"
    Write-Host ($fmt -f 'INF', 'Provider', 'Class', 'HWIDs', 'Matches', 'NeedsPatch', 'Select')
    Write-Host ($fmt -f '-' * 30, '-' * 12, '-' * 7, '-' * 9, '-' * 9, '-' * 9, '-' * 7)
    foreach ($e in $inventory) {
        $providerShort = if ($e.Provider) { $e.Provider.Substring(0, [Math]::Min(11, $e.Provider.Length)) } else { '-' }
        $classShort = if ($e.Class) { $e.Class.Substring(0, [Math]::Min(6, $e.Class.Length)) } else { '-' }
        Write-Host ($fmt -f $e.FileName, $providerShort, $classShort, $e.HwidCount, $e.MatchedHwidCount, $e.NeedsPatch, $e.SelectedForPipeline)
    }

    # CSV export
    $inventory | Export-Csv -Path $Script:InventoryCsvPath -NoTypeInformation -Encoding UTF8
    Write-Skip ("Inventory CSV: {0}" -f $Script:InventoryCsvPath)

    $selected = $inventory | Where-Object SelectedForPipeline
    Write-Host ''
    Write-Ok ('Total INFs        : {0}' -f $inventory.Count)
    Write-Ok ('Selected (matches): {0}' -f $selected.Count)
    Write-Ok ('Need patch (Wstn) : {0}' -f (($inventory | Where-Object NeedsPatch).Count))

    if ($selected.Count -eq 0) {
        Write-Warn2 'No INFs matched the target NPU codename. Pipeline will copy all INFs through anyway (will not bind).'
        # In that case, select all so they reach P06/P08/P09
        foreach ($e in $inventory) { $e.SelectedForPipeline = $true }
    }

    $Script:DetectedPlatform.InfInventory = $inventory
}

function Invoke-PrepPhase06_PatchInfs {
    [CmdletBinding()]
    param()
    Write-Step 'Mirroring Workstation [Manufacturer] decorations as ProductType=3'

    $inventory = $Script:DetectedPlatform.InfInventory
    if (-not $inventory) {
        throw 'No INF inventory; P05 did not complete.'
    }

    $patched   = 0
    $copied    = 0
    $failed    = 0
    foreach ($e in $inventory | Where-Object SelectedForPipeline) {
        $outPath = Join-Path $Script:PatchedDir $e.FileName
        Write-Step ('Processing: {0}' -f $e.FileName)
        try {
            $r = Add-ProductType3Decoration -InputInfPath $e.FullPath -OutputInfPath $outPath
            if ($r.Patched -and $r.MirroredCount -gt 0) {
                Write-Ok ('  Mirrored {0} decoration(s) -> {1}' -f $r.MirroredCount, $outPath)
                $patched++
            } elseif ($r.Patched) {
                Write-Skip ('  Already Server-compatible, copied to {0}' -f $outPath)
                $copied++
            } else {
                Write-Warn2 ('  No patch applied: {0}' -f $r.Reason)
                $failed++
            }

            # Also copy associated .cat / .sys / .pdb / etc to patched dir (sibling files)
            $sourceDir = Split-Path $e.FullPath -Parent
            Get-ChildItem -Path $sourceDir -File | Where-Object {
                $_.Extension -in @('.cat','.sys','.dll','.pdb','.man','.cab','.exe','.bin','.xml','.json')
            } | ForEach-Object {
                $destFile = Join-Path $Script:PatchedDir $_.Name
                if (-not (Test-Path $destFile)) {
                    Copy-Item -Path $_.FullName -Destination $destFile -Force
                }
            }
        } catch {
            Write-Fail ('  Patch failed: {0}' -f $_.Exception.Message)
            $failed++
        }
    }

    Write-Host ''
    Write-Ok ('Patched          : {0} INF(s)' -f $patched)
    Write-Ok ('Server-compat copy: {0} INF(s)' -f $copied)
    Write-Ok ('Failed           : {0} INF(s)' -f $failed)
}

function Invoke-PrepPhase07_CreateCertificate {
    [CmdletBinding()]
    param()

    $cert = New-SelfSignedCodeSigningCert `
        -Subject $Script:CertSubjectCn `
        -PfxPath $Script:PfxPath `
        -CerPath $Script:CerPath `
        -PfxPassword $PfxPassword `
        -ValidityYears $CertValidityYears

    $Script:DetectedPlatform.Cert = $cert
}

function Invoke-PrepPhase08_GenerateCatalogs {
    [CmdletBinding()]
    param()

    if (-not $Script:DetectedPlatform.Inf2CatPath) {
        throw 'inf2cat path not resolved; P02 did not complete.'
    }

    $r = Invoke-Inf2Cat `
        -Inf2CatPath $Script:DetectedPlatform.Inf2CatPath `
        -DriverDir $Script:PatchedDir `
        -OsSwitch $Script:DetectedPlatform.Inf2CatOsSwitch

    if (-not $r.Success) {
        Write-Fail ('inf2cat exit code: {0}' -f $r.ExitCode)
        throw 'inf2cat failed.'
    }

    $cats = Get-ChildItem -Path $Script:PatchedDir -Filter '*.cat' -File
    Write-Ok ('Generated {0} catalog file(s):' -f $cats.Count)
    foreach ($c in $cats) {
        Write-Skip ('  {0}' -f $c.Name)
    }
    $Script:DetectedPlatform.PatchedCatFiles = $cats
}

function Invoke-PrepPhase09_SignCatalogs {
    [CmdletBinding()]
    param()

    if (-not $Script:DetectedPlatform.SignToolPath) {
        throw 'signtool path not resolved; P02 did not complete.'
    }

    $cats = Get-ChildItem -Path $Script:PatchedDir -Filter '*.cat' -File
    if ($cats.Count -eq 0) {
        throw 'No catalogs to sign.'
    }

    $signed = 0
    $failed = 0
    foreach ($c in $cats) {
        Write-Step ('Signing: {0}' -f $c.Name)
        $r = Invoke-SignTool `
            -SignToolPath $Script:DetectedPlatform.SignToolPath `
            -CatPath $c.FullName `
            -PfxPath $Script:PfxPath `
            -PfxPassword $PfxPassword `
            -TimestampUrl $Script:TimestampUrl `
            -HashAlgo 'SHA384'
        if ($r.Success) {
            $signed++
            Write-Ok ('  Signed OK ({0:n1}s)' -f $r.Duration)
        } else {
            $failed++
            Write-Fail ('  Sign FAILED (exit {0})' -f $r.ExitCode)
        }
    }
    Write-Ok ('Signed: {0} catalog(s); Failed: {1}' -f $signed, $failed)
    if ($failed -gt 0) {
        throw 'Some catalogs failed to sign.'
    }
}
# =============================================================================
# Phase implementations V01 - V06 (Verify)
# =============================================================================

function Invoke-VerifyPhase01_VerifyArtifacts {
    [CmdletBinding()]
    param()
    Write-Step 'Verifying cert + patched INFs + catalogs all exist'

    $ok = $true

    if (-not (Test-Path $Script:PfxPath)) {
        Write-Fail ('Missing PFX: {0}' -f $Script:PfxPath)
        $ok = $false
    } else {
        Write-Ok ('PFX present: {0}' -f $Script:PfxPath)
    }
    if (-not (Test-Path $Script:CerPath)) {
        Write-Fail ('Missing CER: {0}' -f $Script:CerPath)
        $ok = $false
    } else {
        Write-Ok ('CER present: {0}' -f $Script:CerPath)
    }

    $infs = Get-ChildItem -Path $Script:PatchedDir -Filter '*.inf' -File -ErrorAction SilentlyContinue
    Write-Ok ('Patched INFs: {0}' -f $infs.Count)
    if ($infs.Count -eq 0) { $ok = $false }

    $cats = Get-ChildItem -Path $Script:PatchedDir -Filter '*.cat' -File -ErrorAction SilentlyContinue
    Write-Ok ('Catalogs    : {0}' -f $cats.Count)
    if ($cats.Count -eq 0) { $ok = $false }

    if (-not $ok) { throw 'V01 detected missing artifacts.' }
}

function Invoke-VerifyPhase02_VerifyCertificate {
    [CmdletBinding()]
    param()
    Write-Step 'Checking EKU, key length, and validity period'

    $pfxSecure = ConvertTo-SecureString -String 'placeholder' -AsPlainText -Force
    $cert = $null
    try {
        if ([string]::IsNullOrEmpty($PfxPassword)) {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Script:PfxPath, '', 'Exportable,PersistKeySet')
        } else {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Script:PfxPath, $PfxPassword, 'Exportable,PersistKeySet')
        }
    } catch {
        Write-Warn2 ('Could not load with placeholder password; trying empty: {0}' -f $_.Exception.Message)
        try {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Script:PfxPath)
        } catch {
            throw "Could not load PFX: $($_.Exception.Message)"
        }
    }

    Write-Ok ('Subject     : {0}' -f $cert.Subject)
    Write-Ok ('Thumbprint  : {0}' -f $cert.Thumbprint)
    Write-Ok ('NotBefore   : {0:yyyy-MM-dd}' -f $cert.NotBefore)
    Write-Ok ('NotAfter    : {0:yyyy-MM-dd} ({1} days from now)' -f $cert.NotAfter, [Math]::Round(($cert.NotAfter - (Get-Date)).TotalDays))
    Write-Ok ('Sig algo    : {0}' -f $cert.SignatureAlgorithm.FriendlyName)

    $rsaPub = $cert.PublicKey.Key
    if ($rsaPub) {
        Write-Ok ('Key size    : {0} bits' -f $rsaPub.KeySize)
    }

    # Check EKU = Code Signing
    $hasCodeSigningEku = $false
    foreach ($ext in $cert.Extensions) {
        if ($ext.Oid.Value -eq '2.5.29.37') {
            $eku = $ext -as [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]
            if ($eku) {
                foreach ($oid in $eku.EnhancedKeyUsages) {
                    if ($oid.Value -eq '1.3.6.1.5.5.7.3.3') {
                        $hasCodeSigningEku = $true
                        break
                    }
                }
            }
        }
    }
    if ($hasCodeSigningEku) {
        Write-Ok 'EKU         : Code Signing (1.3.6.1.5.5.7.3.3) PRESENT'
    } else {
        Write-Warn2 'EKU         : Code Signing NOT present!'
    }
}

function Invoke-VerifyPhase03_VerifyCatalogs {
    [CmdletBinding()]
    param()
    Write-Step 'Running signtool verify /pa on each catalog'
    Write-Skip 'NOTE: Verification will FAIL until I01 imports the cert into trust stores.'
    Write-Skip '      That failure is expected here.'

    $cats = Get-ChildItem -Path $Script:PatchedDir -Filter '*.cat' -File
    $ok = 0; $fail = 0
    foreach ($c in $cats) {
        $r = Test-CatalogSignature -SignToolPath $Script:DetectedPlatform.SignToolPath -CatPath $c.FullName
        if ($r.Success) {
            $ok++
            Write-Skip ('  {0} OK' -f $c.Name)
        } else {
            $fail++
            Write-Skip ('  {0} not yet trusted (expected)' -f $c.Name)
        }
    }
    Write-Ok ('Verify pass : {0}' -f $ok)
    Write-Ok ('Verify fail : {0}  (expected before I01)' -f $fail)
}

function Invoke-VerifyPhase04_VerifyInfs {
    [CmdletBinding()]
    param()
    Write-Step 'Verifying ProductType=3 decoration coverage'

    $build = $Script:DetectedPlatform.OsBuild
    $infs = Get-ChildItem -Path $Script:PatchedDir -Filter '*.inf' -File
    $covered = 0; $uncovered = 0
    foreach ($inf in $infs) {
        $r = Test-InfProductTypeCoverage -InfPath $inf.FullName -ExpectedBuild $build
        if ($r.HasServerForBuild) {
            $covered++
            Write-Skip ('  {0,-30}  Server-decorated for build {1}' -f $r.InfName, $build)
        } else {
            $uncovered++
            if ($r.WorkstationOnly) {
                Write-Warn2 ('  {0,-30}  Workstation-only (no .3 decoration)' -f $r.InfName)
            } else {
                Write-Skip ('  {0,-30}  No build-{1} decoration (no Manufacturer entries?)' -f $r.InfName, $build)
            }
        }
    }
    Write-Ok ('INFs with build-{0} ProductType=3: {1}' -f $build, $covered)
    Write-Ok ('INFs without              : {0}' -f $uncovered)
}

function Invoke-VerifyPhase05_DryRunInstall {
    [CmdletBinding()]
    param()
    # V05 produces an install plan that the user can review before any system
    # state is mutated. The plan is structured to match the chipset / graphics
    # script conventions:
    #   * Group A: patched INFs whose HWIDs match a device on this host
    #     (i.e. INFs that WILL bind to a real device on Install)
    #   * Group B: patched INFs with no matching device on this host
    #     (i.e. INFs that will be added to the driver store but bind to
    #     nothing - "driver-store-only")
    # NPU normally has only 1 device, so Group B is usually empty, but keeping
    # the same layout means operators reading mixed logs from chipset /
    # graphics / NPU runs get a uniform mental model.
    Write-Host ''
    Write-Step 'Simulating Installation phases I01 / I02 / I03 - NO system changes will be made.'

    $patched = Get-ChildItem -Path $Script:PatchedDir -Filter '*.inf' -File
    if ($patched.Count -eq 0) {
        Write-Warn2 'No patched INFs to evaluate.'
        return
    }

    $current = @(Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue)
    Write-Skip ('Current Win32_PnPSignedDriver entries: {0}' -f $current.Count)

    # ----- Build install plan records (per patched INF) -----
    $plan = New-Object 'System.Collections.Generic.List[psobject]'
    foreach ($infFile in $patched) {
        $parsed = Read-InfManufacturer -InfPath $infFile.FullName
        $action = '[ADD]'
        $notes  = ''

        # Find any current driver bound to one of the patched INF's HWIDs
        $matchedCurrent = $null
        foreach ($entry in $parsed.HwidEntries) {
            $hwid = $entry.HardwareId
            $cur = $current | Where-Object {
                ($_.HardwareID -and $_.HardwareID -join '|' -match [regex]::Escape($hwid)) -or
                ($_.CompatID   -and $_.CompatID   -join '|' -match [regex]::Escape($hwid))
            } | Select-Object -First 1
            if ($cur) {
                $matchedCurrent = $cur
                break
            }
        }

        if ($matchedCurrent) {
            $cur = $matchedCurrent
            try { $curVer = [version]$cur.DriverVersion } catch { $curVer = $null }
            $curDate = if ($cur.DriverDate) { $cur.DriverDate.Date } else { $null }
            $patchedVerInfo = ConvertFrom-DriverVerString -DriverVerString $parsed.DriverVer
            $cmp = Compare-InfDriverVer `
                -CurrentDate $curDate `
                -CurrentVersion $curVer `
                -PatchedDate $patchedVerInfo.Date `
                -PatchedVersion $patchedVerInfo.Version
            switch ($cmp) {
                'UpgradePatched' {
                    $action = '[UPGRADE]'
                    $notes  = ('AS-IS {0} -> TO-BE {1}' -f $cur.DriverVersion, $parsed.DriverVer)
                }
                'CurrentNewer' {
                    $action = '[DOWNGRADE]'
                    $notes  = ('AS-IS {0} newer than TO-BE {1}; pnputil will refuse downgrade' -f $cur.DriverVersion, $parsed.DriverVer)
                }
                'SameVersionPatchedDateNewer' {
                    $action = '[UPGRADE]'
                    $notes  = ('same version {0} but TO-BE date is newer; PnP ranking prefers newer-dated driver' -f $cur.DriverVersion)
                }
                'SameVersionCurrentDateNewer' {
                    $action = '[KEEP]'
                    $notes  = ('same version {0}; AS-IS date newer' -f $cur.DriverVersion)
                }
                'Identical' {
                    $action = '[KEEP]'
                    $notes  = ('identical to AS-IS ({0})' -f $cur.DriverVersion)
                }
            }
        } else {
            $action = '[ADD]'
            $notes  = 'no AS-IS driver bound to this HWID; TO-BE will install fresh'
        }

        $plan.Add([pscustomobject]@{
            Inf            = $infFile.Name
            Action         = $action
            DriverVer      = $parsed.DriverVer
            Notes          = $notes
            MatchedCurrent = [bool]$matchedCurrent
            AsIsDeviceName = if ($matchedCurrent) { $matchedCurrent.DeviceName } else { $null }
            AsIsProvider   = if ($matchedCurrent) { $matchedCurrent.DriverProviderName } else { $null }
            AsIsVersion    = if ($matchedCurrent) { $matchedCurrent.DriverVersion } else { $null }
        })
    }
    $Script:DetectedPlatform.InstallPlan = $plan

    # ----- Render plan in two groups (sister-aligned: Group A / Group B) -----
    $groupA = $plan | Where-Object MatchedCurrent
    $groupB = $plan | Where-Object { -not $_.MatchedCurrent }

    Write-Host ''
    Write-Host ('  --- Group A: INFs targeting AMD HARDWARE on this machine ({0} INF) ---' -f $groupA.Count) -ForegroundColor White
    if ($groupA.Count -eq 0) {
        Write-Host '       (no INF in this group; the host has no NPU device that matches a patched INF)' -ForegroundColor DarkGray
    } else {
        $fmt = '    {0,-32}  {1,-24}  {2,-12}  {3}'
        Write-Host ($fmt -f 'Patched INF (TO-BE)', 'TO-BE DriverVer', 'Action', 'Notes') -ForegroundColor Gray
        Write-Host ($fmt -f ('-' * 32), ('-' * 24), ('-' * 12), ('-' * 40)) -ForegroundColor DarkGray
        foreach ($r in $groupA) {
            $color = switch ($r.Action) {
                '[UPGRADE]'   { 'Yellow' }
                '[ADD]'       { 'Green' }
                '[KEEP]'      { 'DarkGray' }
                '[DOWNGRADE]' { 'Red' }
                default       { 'White' }
            }
            $verPreview = if ($r.DriverVer) { $r.DriverVer.Substring(0, [Math]::Min(23, $r.DriverVer.Length)) } else { '-' }
            Write-Host ($fmt -f $r.Inf, $verPreview, $r.Action, $r.Notes) -ForegroundColor $color
        }
    }

    Write-Host ''
    Write-Host ('  --- Group B: INFs with NO matching device (driver-store-only, {0} INF) ---' -f $groupB.Count) -ForegroundColor White
    if ($groupB.Count -eq 0) {
        Write-Host '       (no INF in this group; every patched INF binds to a host device)' -ForegroundColor DarkGray
    } else {
        Write-Host '       (these INFs will be added to the driver store but bind to no current device)' -ForegroundColor DarkGray
        $fmt = '    {0,-32}  {1,-24}  {2,-12}  {3}'
        Write-Host ($fmt -f 'Patched INF (TO-BE)', 'TO-BE DriverVer', 'Action', 'Notes') -ForegroundColor Gray
        Write-Host ($fmt -f ('-' * 32), ('-' * 24), ('-' * 12), ('-' * 40)) -ForegroundColor DarkGray
        foreach ($r in $groupB) {
            $verPreview = if ($r.DriverVer) { $r.DriverVer.Substring(0, [Math]::Min(23, $r.DriverVer.Length)) } else { '-' }
            Write-Host ($fmt -f $r.Inf, $verPreview, $r.Action, $r.Notes) -ForegroundColor Green
        }
    }

    # ----- Summary counts (sister-aligned action labels) -----
    Write-Host ''
    $cAdd       = ($plan | Where-Object Action -EQ '[ADD]').Count
    $cUpgrade   = ($plan | Where-Object Action -EQ '[UPGRADE]').Count
    $cKeep      = ($plan | Where-Object Action -EQ '[KEEP]').Count
    $cDowngrade = ($plan | Where-Object Action -EQ '[DOWNGRADE]').Count
    Write-Ok ('Plan summary: {0} INF total -> [ADD] {1}  [UPGRADE] {2}  [KEEP] {3}  [DOWNGRADE] {4}' -f `
        $plan.Count, $cAdd, $cUpgrade, $cKeep, $cDowngrade)
    if ($cDowngrade -gt 0) {
        Write-Warn2 ('{0} INF would attempt a downgrade; pnputil normally refuses these.' -f $cDowngrade)
    }
}

function Invoke-VerifyPhase06_HardwareImpactAnalysis {
    [CmdletBinding()]
    param()
    # V06 reports the planned hardware impact of the I03 install. It is
    # structured to mirror the chipset / graphics V06 layout while accounting
    # for NPU's single-device characteristic:
    #
    #   Section 1: AS-IS - hardware enumeration on this host (current state)
    #   Section 2: AS-IS / TO-BE driver comparison (per-device delta)
    #   Section 3: Risk classification (NPU-specific: HIGH / MEDIUM / LOW)
    #   Section 4: Ryzen AI Software user-mode stack reminder
    #
    # The "WILL be replaced" / "WILL NOT be replaced" / "Already up to date"
    # terminology is borrowed directly from the chipset / graphics V06 so
    # operators reading multiple deployment logs see consistent vocabulary.

    # ------------------------------------------------------------------
    # Section 1: AS-IS hardware enumeration
    # ------------------------------------------------------------------
    Write-SubHeader2 'Section 1: AS-IS - NPU hardware enumeration on this host'
    $current = $null
    if ($Script:DetectedPlatform.NpuIsDetected) {
        Write-Ok ('NPU codename       : {0}' -f $Script:DetectedPlatform.NpuCodename)
        Write-Ok ('Hardware ID        : {0}' -f $Script:DetectedPlatform.NpuHardwareId)
        Write-Ok ('Revision           : {0}' -f $Script:DetectedPlatform.NpuRevision)

        # Look up the actual current driver bound to this device
        $hwidPattern = if ($Script:DetectedPlatform.NpuHardwareId) {
            $Script:DetectedPlatform.NpuHardwareId.Replace('\','\\')
        } else { $null }
        if (-not [string]::IsNullOrEmpty($hwidPattern)) {
            $current = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object {
                ($_.HardwareID -and ($_.HardwareID -join '|') -match $hwidPattern)
            } | Select-Object -First 1
        }
        if ($current) {
            Write-Ok ('AS-IS driver name  : {0}' -f $current.DeviceName)
            Write-Ok ('AS-IS DriverVer    : {0}' -f $current.DriverVersion)
            $dateStr = if ($current.DriverDate) { '{0:yyyy-MM-dd}' -f $current.DriverDate } else { '(unknown)' }
            Write-Ok ('AS-IS DriverDate   : {0}' -f $dateStr)
            Write-Ok ('AS-IS Provider     : {0}' -f $current.DriverProviderName)
        } else {
            Write-Warn2 'AS-IS driver       : (none bound to NPU device, or device unbound)'
            Write-Skip 'This is common on a freshly installed Windows Server 2025 - the NPU appears'
            Write-Skip 'as an unknown PCI device until the AMD / Microsoft driver is installed.'
        }
    } else {
        Write-Warn2 'NPU was NOT detected on this host (running with -AssumeIfMissing default profile).'
        Write-Warn2 'V06 cannot evaluate device-bind impact without a real NPU device present.'
    }

    # ------------------------------------------------------------------
    # Section 2: AS-IS / TO-BE driver comparison (sister-aligned)
    # ------------------------------------------------------------------
    Write-Host ''
    Write-SubHeader2 'Section 2: AS-IS / TO-BE driver comparison (version-aware)'
    if ($Script:DetectedPlatform.InstallPlan) {
        $plan       = $Script:DetectedPlatform.InstallPlan
        $matched    = $plan | Where-Object MatchedCurrent
        $unmatched  = $plan | Where-Object { -not $_.MatchedCurrent }
        $willReplace      = $matched | Where-Object Action -in '[UPGRADE]','[ADD]'
        $willNotReplace   = $matched | Where-Object Action -EQ '[KEEP]'
        $willDowngrade    = $matched | Where-Object Action -EQ '[DOWNGRADE]'

        # Summary header
        if ($matched.Count -eq 0 -and $unmatched.Count -gt 0) {
            Write-Skip 'No AS-IS driver to compare against; every TO-BE INF will be a fresh install.'
        }

        # Group: WILL be replaced (UPGRADE)
        if ($willReplace.Count -gt 0) {
            Write-Warn2 ('{0,3} device(s) WILL be replaced (TO-BE is newer or same-version-newer-date)' -f $willReplace.Count)
            foreach ($p in $willReplace) {
                Write-Host ''
                Write-Host ('    INF: {0}' -f $p.Inf) -ForegroundColor White
                Write-Host ('      AS-IS: {0,-12}  Provider={1}' -f $p.AsIsVersion, $p.AsIsProvider) -ForegroundColor DarkGray
                Write-Host ('      TO-BE: {0,-12}  Provider=Self-signed (this script)' -f $p.DriverVer) -ForegroundColor Yellow
                Write-Host ('      Note : {0}' -f $p.Notes) -ForegroundColor DarkGray
            }
        } else {
            Write-Skip '  0 device(s) WILL be replaced'
        }

        # Group: WILL NOT be replaced (KEEP)
        if ($willNotReplace.Count -gt 0) {
            Write-Host ''
            Write-Skip ('{0,3} device(s) WILL NOT be replaced (already up to date)' -f $willNotReplace.Count)
            foreach ($p in $willNotReplace) {
                Write-Skip ('      - {0}: AS-IS={1} (TO-BE same or older)' -f $p.Inf, $p.AsIsVersion)
            }
        }

        # Group: DOWNGRADE attempt
        if ($willDowngrade.Count -gt 0) {
            Write-Host ''
            Write-Fail ('{0,3} device(s) WILL ATTEMPT DOWNGRADE (pnputil normally refuses)' -f $willDowngrade.Count)
            foreach ($p in $willDowngrade) {
                Write-Fail ('      - {0}: AS-IS={1} -> TO-BE={2}' -f $p.Inf, $p.AsIsVersion, $p.DriverVer)
            }
        }

        # Group: fresh install (Group B)
        if ($unmatched.Count -gt 0) {
            Write-Host ''
            Write-Ok ('{0,3} INF(s) will install fresh (no AS-IS driver bound to HWID)' -f $unmatched.Count)
            foreach ($p in $unmatched) {
                Write-Ok ('      - {0}: TO-BE={1}' -f $p.Inf, $p.DriverVer)
            }
        }
    } else {
        Write-Warn2 'No install plan available; run V05 (DryRunInstall) first.'
    }

    # ------------------------------------------------------------------
    # Section 3: Risk classification (NPU-specific)
    # ------------------------------------------------------------------
    Write-Host ''
    Write-SubHeader2 'Section 3: Risk classification of planned actions'
    if ($Script:DetectedPlatform.InstallPlan) {
        $plan = $Script:DetectedPlatform.InstallPlan
        $adds       = $plan | Where-Object Action -EQ '[ADD]'
        $upgrades   = $plan | Where-Object Action -EQ '[UPGRADE]'
        $keeps      = $plan | Where-Object Action -EQ '[KEEP]'
        $downgrades = $plan | Where-Object Action -EQ '[DOWNGRADE]'

        # Summary first (sister-aligned action labels)
        Write-Ok ('[ADD]       : {0} INF(s)' -f $adds.Count)
        Write-Ok ('[UPGRADE]   : {0} INF(s)' -f $upgrades.Count)
        Write-Ok ('[KEEP]      : {0} INF(s)' -f $keeps.Count)
        if ($downgrades.Count -gt 0) {
            Write-Fail ('[DOWNGRADE] : {0} INF(s)  (pnputil will refuse)' -f $downgrades.Count)
        }

        Write-Host ''
        if ($adds.Count -gt 0) {
            Write-Warn2 '[HIGH RISK]   Fresh install of NPU kernel-mode driver.'
            Write-Warn2 '              Reason: An unbound device will be claimed by a self-signed driver.'
            Write-Warn2 '                      Ryzen AI Software depends on the exact driver build version.'
            foreach ($p in $adds) {
                Write-Skip ('                - {0} ({1})' -f $p.Inf, $p.DriverVer)
            }
        }
        if ($upgrades.Count -gt 0) {
            Write-Warn2 '[MEDIUM RISK] Upgrade of NPU driver.'
            Write-Warn2 '              Reason: Cross-RAI-version upgrades may break Ryzen AI Software API.'
            Write-Warn2 '                      e.g. RAI 1.5 -> 1.6+ broke OGA API (0.7 -> 0.9.2).'
            foreach ($p in $upgrades) {
                Write-Skip ('                - {0}: {1}' -f $p.Inf, $p.Notes)
            }
        }
        if ($keeps.Count -gt 0 -and $adds.Count -eq 0 -and $upgrades.Count -eq 0) {
            Write-Ok '[LOW RISK]    No driver state change; existing AS-IS drivers will be retained.'
        }
    }

    # ------------------------------------------------------------------
    # Section 4: Ryzen AI Software reminder (NPU-specific)
    # ------------------------------------------------------------------
    Write-Host ''
    Write-SubHeader2 'Section 4: Ryzen AI Software (user-mode stack) reminder'
    Write-Warn2 'This script installs the kernel-mode NPU driver only. To actually USE the NPU,'
    Write-Warn2 'you must separately install Ryzen AI Software, which is OFFICIALLY supported'
    Write-Warn2 'on Windows 11 only (build >= 22621.3527).'
    Write-Skip 'NPU driver and Ryzen AI Software are versioned INDEPENDENTLY (per AMD docs).'
    Write-Skip 'See the I04 post-install guidance for installer download URLs.'
}

# =============================================================================
# Phase implementations I00 - I04 (Install)
# =============================================================================

function Invoke-InstPhase00_PreInstallReview {
    [CmdletBinding()]
    param()
    Write-Step 'Showing pre-install review for operator acknowledgement'

    if ($Script:DetectedPlatform.IsWorkstationOs -and -not $Script:AllowWorkstationInstall) {
        Write-Warn2 ''
        Write-Warn2 'Install phases are blocked on Workstation OS by default.'
        Write-Warn2 'Use -AllowWorkstationInstall to override (discouraged).'
        Write-Warn2 'Skipping I00-I04.'
        Write-Warn2 ''
        throw 'Install blocked on Workstation OS.'
    }

    Write-Host ''
    Write-Host '+----------------------------------------------------------------+' -ForegroundColor Yellow
    Write-Host '| AMD RYZEN AI EULA ACCEPTANCE REQUIRED BEFORE INSTALL           |' -ForegroundColor Yellow
    Write-Host '+----------------------------------------------------------------+' -ForegroundColor Yellow
    Write-Host '|                                                                |' -ForegroundColor Yellow
    Write-Host '| By proceeding, you confirm:                                    |' -ForegroundColor Yellow
    Write-Host '| 1. You have accepted the Ryzen AI EULA at:                     |' -ForegroundColor Yellow
    Write-Host '|    https://account.amd.com/en/forms/downloads/                 |' -ForegroundColor Yellow
    Write-Host '|    ryzenai-eula-public-xef.html                                |' -ForegroundColor Yellow
    Write-Host '| 2. You acknowledge Windows Server 2025 is NOT officially       |' -ForegroundColor Yellow
    Write-Host '|    supported by AMD for Ryzen AI Software (Windows 11 only).   |' -ForegroundColor Yellow
    Write-Host '| 3. You understand the kernel-mode driver alone does not        |' -ForegroundColor Yellow
    Write-Host '|    enable AI inference; Ryzen AI SW must be installed manually.|' -ForegroundColor Yellow
    Write-Host '| 4. You have BitLocker recovery keys recorded if applicable.    |' -ForegroundColor Yellow
    Write-Host '|                                                                |' -ForegroundColor Yellow
    Write-Host '+----------------------------------------------------------------+' -ForegroundColor Yellow
    Write-Host ''

    $confirm = Read-Host 'Type "I AGREE" exactly to proceed with install (anything else aborts)'
    if ($confirm -ne 'I AGREE') {
        throw 'Install aborted by operator (EULA acknowledgement not given).'
    }
    Write-Ok 'Operator acknowledged. Proceeding with install phases.'
}

function Invoke-InstPhase01_TrustCertificate {
    [CmdletBinding()]
    param()
    Add-CertToTrustStore -CerPath $Script:CerPath
}

function Invoke-InstPhase02_AuthorizeDriverSigning {
    [CmdletBinding()]
    param()
    Write-Step 'Building and deploying WDAC supplemental Code Integrity policy'

    if ($Script:UseTestSigning) {
        Write-Warn2 'UseTestSigning specified; falling back to bcdedit /set testsigning on'
        Write-Warn2 'A reboot is required for testsigning mode to take effect.'
        & bcdedit /set testsigning on 2>&1 | ForEach-Object { Write-Skip ("    {0}" -f $_) }
        return
    }

    $wdac = New-WdacSupplementalPolicy `
        -CerPath $Script:CerPath `
        -XmlOutputPath $Script:WdacXmlPath `
        -BinOutputPath $Script:WdacBinPath `
        -PolicyName $Script:WdacPolicyName `
        -PolicyGuid $Script:WdacPolicyGuid

    $r = Install-WdacPolicy -BinPath $wdac.BinPath -PolicyGuid $Script:WdacPolicyGuid
    if (-not $r.Success) {
        throw 'WDAC policy deployment failed.'
    }
    Write-Ok ('WDAC policy deployed via {0}' -f $r.Method)
}

function Invoke-InstPhase03_InstallDrivers {
    [CmdletBinding()]
    param()
    Write-Step 'Running pnputil /add-driver /install for each patched INF'

    $infs = Get-ChildItem -Path $Script:PatchedDir -Filter '*.inf' -File
    $ok = 0; $fail = 0
    foreach ($inf in $infs) {
        $r = Install-PatchedDriver -InfPath $inf.FullName
        if ($r.Success) {
            $ok++
            Write-Ok ('  {0} OK (exit {1})' -f $inf.Name, $r.ExitCode)
        } else {
            $fail++
            Write-Warn2 ('  {0} FAILED (exit {1})' -f $inf.Name, $r.ExitCode)
        }
    }
    Write-Ok ('Install OK: {0}; FAILED: {1}' -f $ok, $fail)

    # Force enumeration
    Write-Step 'pnputil /scan-devices'
    & pnputil.exe /scan-devices 2>&1 | ForEach-Object { Write-Skip ("    {0}" -f $_) }
}

function Invoke-InstPhase04_PostInstallVerification {
    [CmdletBinding()]
    param()

    if ($Script:DetectedPlatform.NpuHardwareId) {
        $hwidEscaped = [regex]::Escape($Script:DetectedPlatform.NpuHardwareId)
        $bound = $null
        if (-not [string]::IsNullOrEmpty($hwidEscaped)) {
            $bound = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object {
                $_.HardwareID -and ($_.HardwareID -join '|') -match $hwidEscaped
            } | Select-Object -First 1
        }

        if ($bound) {
            Write-Ok ('Bound device : {0}' -f $bound.DeviceName)
            Write-Ok ('Driver ver   : {0}' -f $bound.DriverVersion)
            Write-Ok ('Driver date  : {0:yyyy-MM-dd}' -f $bound.DriverDate)
            Write-Ok ('Provider     : {0}' -f $bound.DriverProviderName)

            if ($bound.DriverProviderName -match 'AMD') {
                Write-Ok '[C] Self-signed AMD NPU driver successfully bound.'
            } else {
                Write-Warn2 'Driver provider is not AMD; check Device Manager for binding.'
            }
        } else {
            Write-Warn2 'No driver appears bound to the target NPU HWID yet.'
            Write-Warn2 'Try: Device Manager -> rescan; or pnputil /scan-devices.'
        }
    } else {
        Write-Skip 'NPU HWID not known; skipping post-install bind check.'
    }
}

# =============================================================================
# Cleanup action
# =============================================================================
function Invoke-Cleanup {
    [CmdletBinding()]
    param()
    Write-SubHeader 'Cleanup: remove cert, WDAC policy, drivers, workspace'

    # 1. Remove cert from trust stores (if PFX is still around to compute thumbprint)
    if (Test-Path $Script:PfxPath) {
        try {
            $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($Script:PfxPath)
            Remove-CertFromTrustStore -Thumbprint $cert.Thumbprint
        } catch {
            Write-Warn2 ("Could not load PFX to compute thumbprint: {0}" -f $_.Exception.Message)
        }
    }
    # Also scan for any cert with our subject CN in case PFX is gone
    foreach ($store in @('Cert:\LocalMachine\Root','Cert:\LocalMachine\TrustedPublisher')) {
        Get-ChildItem $store -ErrorAction SilentlyContinue | Where-Object {
            $_.Subject -match [regex]::Escape($Script:CertSubjectCn)
        } | ForEach-Object {
            try {
                Remove-Item $_.PSPath -Force
                Write-Ok ('Removed cert (by subject) from {0}: {1}' -f $store, $_.Thumbprint)
            } catch {
                Write-Warn2 ("Could not remove cert by subject from {0}: {1}" -f $store, $_.Exception.Message)
            }
        }
    }

    # 2. Remove WDAC policy
    Remove-WdacPolicy -PolicyGuid $Script:WdacPolicyGuid

    # 3. Remove drivers from driver store (best-effort, by published name pattern)
    Write-Step 'pnputil /enum-drivers - searching for our self-signed AMD NPU drivers...'
    try {
        $stdout = & pnputil.exe /enum-drivers 2>&1
        $publishedName = $null
        $providerHit = $false
        foreach ($line in $stdout) {
            if ($line -match 'Published Name\s*:\s*(oem\d+\.inf)') {
                $publishedName = $Matches[1]
                $providerHit = $false
            } elseif ($line -match 'Driver provider name|Driver Provider Name') {
                if ($line -match 'AMD') {
                    $providerHit = $true
                }
            } elseif ($line -match '^\s*$' -and $publishedName -and $providerHit) {
                # End of one entry; not deleting blindly - just report
                Write-Skip ('  Candidate for deletion: {0}' -f $publishedName)
                # NOTE: actual deletion is risky without thumbprint match. Leaving manual.
                $publishedName = $null
                $providerHit = $false
            }
        }
        Write-Warn2 'Driver store entries are NOT deleted automatically (would require thumbprint matching).'
        Write-Warn2 'Use Driver Store Explorer (Rapr.exe) or pnputil /delete-driver oemNN.inf /force manually.'
    } catch {
        Write-Warn2 ("Driver enumeration failed: {0}" -f $_.Exception.Message)
    }

    # 4. Remove workspace
    if (Test-Path $WorkRoot) {
        Write-Step ('Removing workspace: {0}' -f $WorkRoot)
        try {
            Remove-Item -Path $WorkRoot -Recurse -Force
            Write-Ok 'Workspace removed.'
        } catch {
            Write-Warn2 ("Could not remove workspace: {0}" -f $_.Exception.Message)
        }
    }
    Write-Ok 'Cleanup complete.'
}

# =============================================================================
# Ryzen AI Software user-mode stack guidance (post-install)
# =============================================================================
function Show-RyzenAiSoftwareGuidance {
    [CmdletBinding()]
    param()
    Write-Host ''
    Write-Host '+================================================================+' -ForegroundColor Cyan
    Write-Host '| RYZEN AI SOFTWARE (USER-MODE STACK) - INSTALL THIS SEPARATELY |' -ForegroundColor Cyan
    Write-Host '+================================================================+' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'This script installed the kernel-mode NPU driver only.' -ForegroundColor White
    Write-Host 'To actually use the NPU for AI inference, install Ryzen AI Software:' -ForegroundColor White
    Write-Host ''
    Write-Host ('  Detected NPU codename       : {0}' -f $Script:DetectedPlatform.NpuShortName) -ForegroundColor Gray
    Write-Host ('  Installed NPU driver build  : {0} (kernel-mode, this script)' -f $Script:DetectedPlatform.NpuDriverBuild) -ForegroundColor Gray
    Write-Host ('  Recommended RAI Software    : {0} (user-mode stack, install separately)' -f $Script:DetectedPlatform.RyzenAiSoftwareVersion) -ForegroundColor Gray
    Write-Host '  Note: NPU driver and Ryzen AI Software are versioned INDEPENDENTLY.' -ForegroundColor Gray
    Write-Host '        Always use the LATEST Ryzen AI Software for end-user workloads.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  PREREQUISITES (per AMD documentation):' -ForegroundColor Yellow
    Write-Host '    1. Windows 11 build >= 22621.3527 (NOT supported on Server 2025!)' -ForegroundColor Yellow
    Write-Host '    2. Visual Studio 2022 (with Desktop Development with C++)' -ForegroundColor Yellow
    Write-Host '    3. cmake >= 3.26' -ForegroundColor Yellow
    Write-Host '    4. Miniforge (Python distribution); add condabin/Scripts to PATH' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  INSTALLATION STEPS:' -ForegroundColor White
    Write-Host '    1. Download Ryzen AI Software installer (user-mode stack):' -ForegroundColor White
    $raiInstaller = if ($Script:DetectedPlatform.RyzenAiSoftwareInstaller) { $Script:DetectedPlatform.RyzenAiSoftwareInstaller } else { 'ryzen-ai-lt-1.7.1.exe' }
    $raiVer       = if ($Script:DetectedPlatform.RyzenAiSoftwareVersion)   { $Script:DetectedPlatform.RyzenAiSoftwareVersion }   else { '1.7.1' }
    Write-Host ('       https://account.amd.com/en/forms/downloads/xef.html?filename={0}' -f $raiInstaller) -ForegroundColor Cyan
    Write-Host ("       Filename: {0}" -f $raiInstaller) -ForegroundColor Cyan
    Write-Host ''
    Write-Host '    2. Launch the EXE installer (run as Administrator):' -ForegroundColor White
    Write-Host '       - Accept the EULA' -ForegroundColor White
    Write-Host ('       - Default install dir: C:\Program Files\RyzenAI\{0}' -f $raiVer) -ForegroundColor White
    Write-Host ('       - Default conda env name: ryzen-ai-{0}' -f $raiVer) -ForegroundColor White
    Write-Host ''
    Write-Host '    3. Verify the install (Miniforge Prompt):' -ForegroundColor White
    Write-Host ("         conda activate ryzen-ai-{0}" -f $raiVer) -ForegroundColor Cyan
    Write-Host '         cd %RYZEN_AI_INSTALLATION_PATH%\quicktest' -ForegroundColor Cyan
    Write-Host '         python quicktest.py' -ForegroundColor Cyan
    Write-Host '         # Open Task Manager -> Performance -> NPU; should see utilization' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  COMPONENTS INCLUDED IN RYZEN AI SOFTWARE:' -ForegroundColor White
    Write-Host '    - Vitis AI Execution Provider for ONNX Runtime (VitisAIExecutionProvider)' -ForegroundColor Gray
    Write-Host '    - OnnxRuntime GenAI (OGA) for hybrid CNN/LLM execution' -ForegroundColor Gray
    Write-Host '    - AMD Quark quantizer (PyTorch/ONNX)' -ForegroundColor Gray
    Write-Host '    - Whisper.cpp / Stable Diffusion / LLM hybrid runtime examples' -ForegroundColor Gray
    Write-Host '    - xrt-smi NPU management tool' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  DOCUMENTATION & EXAMPLES:' -ForegroundColor White
    Write-Host '    Full installation guide:  https://ryzenai.docs.amd.com/en/latest/inst.html' -ForegroundColor Cyan
    Write-Host '    Release notes:            https://ryzenai.docs.amd.com/en/latest/relnotes.html' -ForegroundColor Cyan
    Write-Host '    GitHub examples:          https://github.com/amd/RyzenAI-SW' -ForegroundColor Cyan
    Write-Host '    Latest releases:          https://github.com/amd/RyzenAI-SW/releases' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  IMPORTANT - Server 2025 caveat:' -ForegroundColor Magenta
    if ($Script:DetectedPlatform.IsServer2025) {
        Write-Host '    You are on Windows Server 2025. AMD does NOT support Ryzen AI Software here.' -ForegroundColor Magenta
        Write-Host '    The kernel driver this script installed will load, but the user-mode' -ForegroundColor Magenta
        Write-Host '    Python/ONNX Runtime stack may fail to initialize on Server SKU.' -ForegroundColor Magenta
        Write-Host '    For inference workloads, consider using Windows 11 24H2 instead.' -ForegroundColor Magenta
    } else {
        Write-Host '    You are NOT on Windows Server 2025; Ryzen AI Software install should be' -ForegroundColor Magenta
        Write-Host '    straightforward following the steps above.' -ForegroundColor Magenta
    }
    Write-Host ''
    Write-Host '+================================================================+' -ForegroundColor Cyan
    Write-Host ''
}

# =============================================================================
# Final summary (run at end of every Action) - sister-script-aligned
# =============================================================================
function Show-RunSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Action)

    $totalElapsed = (Get-Date) - $Script:ScriptStartTime
    $endedAtStr   = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Magenta
    Write-Host ' RUN SUMMARY' -ForegroundColor Magenta
    Write-Host ('=' * 72) -ForegroundColor Magenta
    Write-Host (" Script version  : {0} [{1}]" -f $Script:ScriptVersion, $Script:ScriptTag) -ForegroundColor Cyan
    Write-Host (" Script SHA256   : {0}" -f $Script:ScriptHash) -ForegroundColor DarkCyan
    Write-Host (" Action          : {0}" -f $Action) -ForegroundColor White
    Write-Host (" Started         : {0:yyyy-MM-dd HH:mm:ss}" -f $Script:HostStartTime) -ForegroundColor Gray
    Write-Host (" Ended           : {0}" -f $endedAtStr) -ForegroundColor Gray
    Write-Host (" Duration        : {0}" -f (Format-Elapsed $totalElapsed)) -ForegroundColor Gray
    Write-Host (" Workspace       : {0}" -f $WorkRoot) -ForegroundColor Gray
    if ($Script:DetectedPlatform.NpuShortName) {
        Write-Host (" NPU             : {0} ({1})" -f $Script:DetectedPlatform.NpuCodename, $Script:DetectedPlatform.NpuShortName) -ForegroundColor Gray
    }
    if ($Script:DetectedPlatform.NpuDriverPackage) {
        Write-Host (" NPU driver pkg  : {0} (build {1})" -f $Script:DetectedPlatform.NpuDriverPackage, $Script:DetectedPlatform.NpuDriverBuild) -ForegroundColor Gray
    }
    if ($Script:DetectedPlatform.RyzenAiSoftwareVersion) {
        Write-Host (" RAI Software    : {0} (separate user-mode install)" -f $Script:DetectedPlatform.RyzenAiSoftwareVersion) -ForegroundColor Gray
    }

    Write-Host ''
    Write-Host ('-' * 72) -ForegroundColor DarkCyan
    Write-Host ' Phase results' -ForegroundColor DarkCyan
    Write-Host ('-' * 72) -ForegroundColor DarkCyan
    $fmt = "{0,-5} {1,-7} {2,-30} {3,-8} {4,-12}"
    Write-Host ($fmt -f 'ID', 'Group', 'Name', 'Status', 'Duration') -ForegroundColor Gray
    Write-Host ($fmt -f ('-' * 4), ('-' * 5), ('-' * 28), ('-' * 6), ('-' * 10)) -ForegroundColor DarkGray
    $sumSeconds = 0.0
    foreach ($p in $Script:PhaseRegistry) {
        $r = $Script:PhaseResults[$p.Id]
        if (-not $r) {
            Write-Host ($fmt -f $p.Id, $p.Group, $p.Name, 'SKIP', '-') -ForegroundColor DarkGray
        } else {
            $color = switch ($r.Status) {
                'OK'   { 'Green' }
                'FAIL' { 'Red' }
                default { 'Gray' }
            }
            $sumSeconds += $r.Duration.TotalSeconds
            $statusLabel = switch ($r.Status) {
                'OK'   { 'DONE' }
                'FAIL' { 'FAILED' }
                default { $r.Status }
            }
            $durStr = Format-Elapsed $r.Duration
            Write-Host ($fmt -f $p.Id, $p.Group, $p.Name, $statusLabel, $durStr) -ForegroundColor $color
        }
    }
    Write-Host ($fmt -f ('-' * 4), ('-' * 5), ('-' * 28), ('-' * 6), ('-' * 10)) -ForegroundColor DarkGray
    Write-Host ($fmt -f '', '', 'Sum of executed phases', '', (Format-Elapsed ([TimeSpan]::FromSeconds($sumSeconds)))) -ForegroundColor White
    Write-Host ('=' * 72) -ForegroundColor Magenta
    Write-Host ''
}
# =============================================================================
# Main entry point / orchestrator
# =============================================================================

function Invoke-MainEntryPoint {
    [CmdletBinding()]
    param()

    # Banner (sister-script-aligned: include ScriptTag and ScriptHash)
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host (" {0}" -f $Script:ScriptName) -ForegroundColor Cyan
    Write-Host (" Version: {0}  [{1}]  SHA256: {2}" -f $Script:ScriptVersion, $Script:ScriptTag, $Script:ScriptHash) -ForegroundColor DarkCyan
    Write-Host (" Action : {0}" -f $Action) -ForegroundColor White
    Write-Host (" Repo   : {0}" -f $Script:RepoUrl) -ForegroundColor DarkCyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host ''

    # ListPhases short-circuit
    if ($Action -eq 'ListPhases') {
        Show-PhaseList
        return
    }

    # Cleanup short-circuit
    if ($Action -eq 'Cleanup') {
        # Best-effort: even Cleanup needs admin + TLS for cert removal
        try { Test-AdminPrivilege | Out-Null } catch { throw }
        Set-NetworkProtocol
        Invoke-Cleanup
        return
    }

    # Resolve which phases to run
    $phaseIds = $null
    if ($Script:OnlyPhases -and $Script:OnlyPhases.Count -gt 0) {
        # Honor explicit -OnlyPhases override (split commas, trim, dedupe)
        $phaseIds = @()
        foreach ($entry in $Script:OnlyPhases) {
            foreach ($id in ($entry -split ',')) {
                $trimmed = $id.Trim()
                if (-not [string]::IsNullOrEmpty($trimmed)) {
                    $phaseIds += $trimmed
                }
            }
        }
        $phaseIds = $phaseIds | Select-Object -Unique
        Write-Warn2 ('-OnlyPhases override active: running {0} phase(s)' -f $phaseIds.Count)
        Write-Skip ('  Phases: {0}' -f ($phaseIds -join ', '))
    } else {
        $phaseIds = Get-PhaseListByAction -Action $Action
    }

    if (-not $phaseIds -or $phaseIds.Count -eq 0) {
        throw "No phases resolved for Action='$Action'."
    }

    # Block Install / All on Workstation OS unless explicitly allowed
    # (handled by I00 itself, but we also short-circuit here for clarity).
    # 'All' is the sister-script-aligned full-pipeline action that includes
    # I phases, so it must trigger the same Workstation gate as 'Install'.
    if ($Action -eq 'Install' -or $Action -eq 'All') {
        # Quick OS detect to know if we should warn upfront
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $productType = [int]$os.ProductType
            if ($productType -eq 1 -and -not $Script:AllowWorkstationInstall) {
                Write-Warn2 ''
                Write-Warn2 '------------------------------------------------------------------'
                Write-Warn2 ('Action={0} on Workstation OS detected.' -f $Action)
                Write-Warn2 'I00 will block install phases. Use -AllowWorkstationInstall to'
                Write-Warn2 'override (discouraged), or use Action=PrepareVerify on Win11 hosts.'
                Write-Warn2 '------------------------------------------------------------------'
                Write-Warn2 ''
            }
        } catch {
            # Non-fatal: let phase runner handle it
        }
    }

    # Execute the resolved phase list
    Invoke-PhaseRunner -PhaseIds $phaseIds

    # Post-Install / Post-All: show Ryzen AI Software guidance to the operator
    if ($Action -eq 'Install' -or $Action -eq 'All') {
        $allInstallPhasesOk = $true
        foreach ($id in @('I01','I02','I03','I04')) {
            $r = $Script:PhaseResults[$id]
            if (-not $r -or $r.Status -ne 'OK') {
                $allInstallPhasesOk = $false
                break
            }
        }
        if ($allInstallPhasesOk) {
            Show-RyzenAiSoftwareGuidance
        }
    }
}

# =============================================================================
# Top-level dispatch with try/finally for guaranteed run summary
# =============================================================================
$Script:TopLevelException = $null
try {
    Invoke-MainEntryPoint
}
catch {
    $Script:TopLevelException = $_
    Write-Host ''
    Write-Fail ('Top-level error: {0}' -f $_.Exception.Message)
    if ($_.ScriptStackTrace) {
        Write-Skip 'Stack trace:'
        foreach ($line in ($_.ScriptStackTrace -split "`n")) {
            Write-Skip ("    {0}" -f $line.TrimEnd())
        }
    }
}
finally {
    # Always print run summary (except on ListPhases, which has nothing to summarize)
    if ($Action -ne 'ListPhases') {
        try {
            Show-RunSummary -Action $Action
        } catch {
            Write-Warn2 ('Could not render run summary: {0}' -f $_.Exception.Message)
        }
    }

    # Final exit code: non-zero if there was an exception
    if ($Script:TopLevelException) {
        Write-Host ''
        Write-Fail 'Script terminated with errors. See messages above.'
        exit 1
    } else {
        Write-Host ''
        Write-Ok 'Script completed successfully.'
        exit 0
    }
}
