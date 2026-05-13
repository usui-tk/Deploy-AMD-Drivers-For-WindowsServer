# 開発者向け仕様書 (SPEC)

> **本ドキュメントの目的**
>
> 本ファイルは、本リポジトリ配下の 3 つの PowerShell スクリプト
> (`Deploy-AMDChipsetDriverOnWindowsServer.ps1`、
> `Deploy-AMDGraphicsDriverOnWindowsServer.ps1`、
> `Deploy-AMDNpuDriverOnWindowsServer.ps1`) の構築・拡張のための authoritative
> な仕様書です。新機能を追加する開発者、 4 番目の姉妹スクリプトを作成する
> 開発者、または LLM (Claude) が新しい作業を開始する際に、規約をゼロから
> 再導出することなく、この 1 ファイルを参照することで作業に着手できる
> ことを意図しています。
>
> **最も重要なルール**: **Part A (共通仕様)** に記述されている挙動については、
> 新機能や姉妹スクリプトは必ず既存実装を再利用してください。phase header、
> log marker、環境診断、エラー JSONL フォーマット、`psa.py` 静的解析ツール
> を再設計しないでください。これらは多数のリビジョンを経て hardening
> されており、現実世界のバグ修正を反映しています。書き直しは regression
> を招くだけです。
>
> **Part B** は各スクリプト固有の platform 検出ロジック、INF inventory
> filter、インストーラソース解決の tier 構成、既知の platform 固有挙動を
> 確認するためのリファレンスとして使用してください。**Part C** は変更が
> パスしなければならない品質ゲート (`psa.py`、`TESTING.md`) を文書化
> しています。**Part D** は現在の実装が既に対処している過去の教訓を保存
> しています。

🇬🇧 **English specification is available at [SPEC.md](./SPEC.md).**

---

## 目次

- [Part A — 共通仕様 (3 スクリプト全体で再利用可能)](#part-a--共通仕様-3-スクリプト全体で再利用可能)
  - [A.1 リファレンス資産](#a1-リファレンス資産)
  - [A.2 ソースファイル形式](#a2-ソースファイル形式)
  - [A.3 Banner とバージョン識別](#a3-banner-とバージョン識別)
  - [A.4 Phase アーキテクチャ (21 phases)](#a4-phase-アーキテクチャ-21-phases)
  - [A.5 ロギング規約](#a5-ロギング規約)
  - [A.6 パラメータ規約](#a6-パラメータ規約)
  - [A.7 Path Handling ルール](#a7-path-handling-ルール)
  - [A.8 エラーと診断の規約](#a8-エラーと診断の規約)
  - [A.9 CSV カラム規約](#a9-csv-カラム規約)
  - [A.10 環境評価 (Phase P00)](#a10-環境評価-phase-p00)
  - [A.11 psa.py による静的解析](#a11-psapy-による静的解析)
  - [A.12 多言語ドキュメンテーション](#a12-多言語ドキュメンテーション)
  - [A.13 開発ワークフロー](#a13-開発ワークフロー)
- [Part B — スクリプト固有仕様](#part-b--スクリプト固有仕様)
  - [B.1 Chipset スクリプト (`Deploy-AMDChipsetDriverOnWindowsServer.ps1`)](#b1-chipset-スクリプト-deploy-amdchipsetdriveronwindowsserverps1)
  - [B.2 Graphics スクリプト (`Deploy-AMDGraphicsDriverOnWindowsServer.ps1`)](#b2-graphics-スクリプト-deploy-amdgraphicsdriveronwindowsserverps1)
  - [B.3 NPU スクリプト (`Deploy-AMDNpuDriverOnWindowsServer.ps1`)](#b3-npu-スクリプト-deploy-amdnpudriveronwindowsserverps1)
- [Part C — 品質ゲートと検証チェックリスト](#part-c--品質ゲートと検証チェックリスト)
- [Part D — 既知の落とし穴と教訓](#part-d--既知の落とし穴と教訓)

---

# Part A — 共通仕様 (3 スクリプト全体で再利用可能)

## A.1 リファレンス資産

以下は共通ロジックの正本です。 **これらから直接取得し、 再実装しないでください。**

### A.1.1 リファレンススクリプト (phase / banner / log パターン)

```
Deploy-AMDChipsetDriverOnWindowsServer.ps1   (最も成熟した実装、 正本 r47)
Deploy-AMDGraphicsDriverOnWindowsServer.ps1  (graphics 固有の platform 検出、 r16)
Deploy-AMDNpuDriverOnWindowsServer.ps1       (4-tier installer 解決を持つ NPU script、 r2)
```

これら 3 つの 21-phase デプロイスクリプトは、 以下の正本です:

- `Write-PhaseHeader` / `Write-PhaseFooter` / `Format-Elapsed`
- `Write-Step` / `Write-Ok` / `Write-Warn2` / `Write-Fail` / `Write-Skip`
- `Write-SubHeader` / `Write-SubHeader2` (Level-1 / Level-2 in-phase banner)
- Banner block レイアウト (Magenta `=` × 72、 script-tag 行、 phase entry / exit)
- `Show-PowerShellEnvironment` (P00 環境ダンプ)
- `Show-OperatingSystemDetail` (OS profile / build / inf2cat `/os:` 解決)
- `Test-AdminPrivilege` (非昇格セッションで hard-fail)
- `Set-NetworkProtocol` (TLS hardening)
- `Show-RunSummary` (PhaseTimings + ScriptHash 付き action 単位 summary)

これらスクリプトを拡張する際は、 最新リビジョンから **これらの helper を verbatim でコピー** してください。

### A.1.2 静的解析ツール

```
tools/psa.py
```

`psa.py` は **pure Python** 静的解析ツール (PowerShell インストール不要) で、 10 個のチェック (C1–C10) を持ちます。 以下を遵守してください:

- as-is で再利用 (上流と協調しないままの fork や改変は不可)
- 姉妹スクリプトリポジトリの `tools/psa.py` 配下に配置
- 全 commit 前のゲートとして使用

詳細は A.11 を参照してください。

### A.1.3 関連仕様書

- `README.md` / `README.ja.md` — エンドユーザー向けドキュメント (インストール、 quick start、 トラブルシューティング)
- `TESTING.md` / `TESTING.ja.md` — クラウド (AWS EPYC EC2) 回帰テスト手順 + 物理ハードウェア検証結果
- `CONTRIBUTING.md` — Issue / PR 規約

### A.1.4 Workspace path 規約

各スクリプトは、 スクリプト間の衝突を防ぐため、 専用の workspace path `C:\AMD-<short>-WS\` 配下に書き込みます:

| スクリプト | デフォルト workspace path     |
| ---------- | ---------------------------- |
| Chipset    | `C:\AMD-Chipset-WS`          |
| Graphics   | `C:\AMD-Graphics-WS`         |
| NPU        | `C:\AMD-NPU-WS`              |

4 番目のスクリプト (例: ROCm runtime、 audio coprocessor) を追加する場合は、 同じサブディレクトリレイアウト (`download\`、 `extracted\`、 `patched\`、 `cert\`) で `C:\AMD-<short>-WS\` を使用してください。

---

## A.2 ソースファイル形式

| 属性             | 値                                                                              |
| ---------------- | ------------------------------------------------------------------------------ |
| エンコーディング | UTF-8 with BOM (`utf-8-bom`)                                                   |
| 改行コード       | CRLF                                                                           |
| インデント       | スペース 4 個 (実 tab 文字は使用しない)                                        |
| PowerShell バージョン | 5.1 最低要件、 7.x サポート                                                |
| 必須属性         | 各 .ps1 ファイル先頭に `#Requires -Version 5.1` および `#Requires -RunAsAdministrator` |
| `param()` block  | top-of-file の `param()` に `[CmdletBinding()]`、 直後に `$Script:Foo` へ mirror |
| 静的ゲート       | `tools/psa.py` を errors 0 でパス                                              |

### ファイル構造 (top-to-bottom)

```
1.  ヘッダコメントブロック (.SYNOPSIS / .DESCRIPTION / .PARAMETER / .EXAMPLE / .NOTES)
2.  #Requires ディレクティブ
3.  [CmdletBinding()] + param() block
4.  パラメータを $Script:Foo へ mirror
5.  Script-scope state ($Script:ScriptVersion、 $Script:ScriptTag、 $Script:ScriptHash、...)
6.  $Script:PhaseRegistry = @( [pscustomobject]@{ Id=...; Name=...; Group=...; Func=... }, ... )
7.  $Script:DetectedPlatform = @{ ... } (P00/P03 で populate)
8.  $Script:PhaseResults = @{}
9.  Output helpers (Format-Elapsed、 _LogLine、 Write-Step/Ok/Warn2/Fail/Skip、 Write-SubHeader、 Write-PhaseHeader/Footer)
10. Environment helpers (Show-PowerShellEnvironment、 Show-OperatingSystemDetail、 Test-AdminPrivilege、 Set-NetworkProtocol)
11. Phase orchestrator (Invoke-PhaseRunner、 Get-PhaseListByAction、 Show-PhaseList)
12. Domain helpers (スクリプト固有: AMD platform 検出、 INF parser、 installer 解決等)
13. Phase 実装: Invoke-PrepPhase00_Initialize ... Invoke-InstPhase04_PostInstallVerification
14. Cleanup action (Invoke-Cleanup)
15. Main entry point (Invoke-MainEntryPoint)
16. Show-RunSummary を exit path にかかわらず必ず実行する top-level try/finally dispatcher
```

---

## A.3 Banner とバージョン識別

### バージョン文字列フォーマット

```powershell
$Script:ScriptVersion = '<short-name>-YYYY.MM.DD-rNN'
$Script:ScriptTag     = '<short-kebab-tag-describing-the-revision>'
```

本番運用中の例:

- `chipset-2026.05.09-r47` / tag `chipset-dedupe-matched-devices-r47`
- `graphics-2026.05.09-r16` / tag `graphics-dedupe-matched-devices-r16`
- `npu-2026.05.10-r2` / tag `npu-sister-aligned-r2`

### SHA256 による self-fingerprint

スクリプトは起動時に自身のファイルをハッシュし、 最初の 12 桁 hex を露出する必要があります。 これは全 phase header に出力され、 スクリプトバージョン間でログが再現可能となります:

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

色: Cyan 枠、 DarkCyan version / repo 行、 White Action 行。 幅: 72 文字。

### Phase header / footer banner

dispatcher (`Invoke-PhaseRunner`) が出力します。 phase 関数は **絶対に**自分自身で出力してはいけません:

```
========================================================================
 PHASE P00 - Initialize                 (Prep  )  start: 14:23:05
 script: vnpu-2026.05.10-r2/09129eebb04b
========================================================================
... phase 本体の出力 ...
 PHASE P00 -> DONE     elapsed: 0.45s
```

色: Magenta 枠 + entry 行、 DarkGray script-tag 行。 ステータス色: Green=DONE、 Red=FAILED、 DarkGray=CACHED/SKIPPED。

---

## A.4 Phase アーキテクチャ (21 phases)

3 スクリプトとも同じ 21-phase モデルを共有しています。 4 番目のスクリプトを追加するということは、 同じ 21 phase 関数を populate することを意味します — 強い理由 (および SPEC.md 改訂) なしに phase count や ID を変更しないでください。

### Numbering ルール

```
P00 - P09   Prep phases   (10 phases、 絶対必要なら拡張可)
V01 - V06   Verify phases (6 phases)
I00 - I04   Inst phases   (5 phases)
```

### Phase registry フォーマット (必須)

```powershell
$Script:PhaseRegistry = @(
    [pscustomobject]@{ Id='P00'; Name='Initialize';     Group='Prep';   Func='Invoke-PrepPhase00_Initialize' }
    [pscustomobject]@{ Id='P01'; Name='PrepareWorkspace'; Group='Prep'; Func='Invoke-PrepPhase01_PrepareWorkspace' }
    # ...
)
```

- **型**: `[pscustomobject]@{...}` (plain `@{...}` hashtable は NG — 姉妹スクリプト整合のため)。
- **関数命名**: `Invoke-{Prep|Verify|Inst}Phase{NN}_{Name}` (underscore + group-prefix スタイル)。
- **1:1 マッピング**: 各 registry エントリは正確に 1 つの関数定義を持つ必要があります。 `psa.py` がミスマッチを検出します。

### Phase グループ (semantic)

| グループ | 意味                                                                          |
| -------- | ----------------------------------------------------------------------------- |
| Prep     | アーティファクトの取得・準備。 システム状態は変更しない                       |
| Verify   | アーティファクト検証 + dry-run install plan。 システム状態は変更しない        |
| Inst     | ホストシステムに変更を適用 (cert trust、 WDAC policy、 drivers)              |

### Phase entry/exit コントラクト

- dispatcher は関数呼び出しの前に `Write-PhaseHeader` を、 後に `Write-PhaseFooter` を出力します。
- Phase 関数は `Write-PhaseHeader` / `Write-PhaseFooter` を自分自身で呼び出してはいけません。
- Phase 関数は in-phase サブセクションのために `Write-SubHeader` (Cyan、 Level-1) または `Write-SubHeader2` (DarkCyan、 Level-2) を呼び出してかまいません。

### Phase timing summary

各 phase 結果は `$Script:PhaseTimings` に記録されます (`Id`、 `Status`、 `Elapsed`、 `EndedAt` を持つ `pscustomobject` を `Add`)。 `Show-RunSummary` (`finally` で無条件実行) が完全なテーブルを出力します。

---

## A.5 ロギング規約

### マーカー (color-coded)

| マーカー | 色       | 関数            | 意味                |
| -------- | -------- | --------------- | ------------------- |
| `[*]`    | Cyan     | `Write-Step`    | 実行中のアクション  |
| `[+]`    | Green    | `Write-Ok`      | 成功 / 肯定的結果   |
| `[!]`    | Yellow   | `Write-Warn2`   | 警告 / 致命的でない |
| `[X]`    | Red      | `Write-Fail`    | 失敗                |
| `[~]`    | DarkGray | `Write-Skip`    | no-op / cached      |

### 行フォーマット

```
[HH:mm:ss] [+X.XXs]   [marker] <message>
[HH:mm:ss]            [marker] <message>   ← phase の外側にいる時は elapsed-tag なし
```

- `HH:mm:ss` は現在の wall-clock 時刻 (ホスト TZ)。
- `[+X.XXs]` は `$Script:CurrentPhaseStart` からの経過時間 (各 phase entry で reset)。
- マーカー / 色の組み合わせは唯一許可されたスタイル。 新しいマーカー (例: `[i]`、 `[>]`、 `[?]`) を導入してはいけません — 視認スキャンパターンが崩れます。

### Banner helpers (Level-0 / Level-1 / Level-2)

| Helper             | 色        | 幅        | 用途                                                                |
| ------------------ | --------- | --------- | ------------------------------------------------------------------- |
| `Write-PhaseHeader`| Magenta   | `=` × 72  | Phase entry banner (dispatcher のみ)                                |
| `Write-PhaseFooter`| ステータス| (1 行)    | Phase exit footer (dispatcher のみ)                                 |
| `Write-SubHeader`  | Cyan      | `=` × 72  | Level-1 in-phase banner (phase 内の主要セクション)                  |
| `Write-SubHeader2` | DarkCyan  | `-` × 72  | Level-2 in-phase banner (より細かいサブセクション)                  |

### コンソールエンコーディング

P00 では `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` を強制し、 日本語ログ文字列が ja-JP Windows コンソールで正しくレンダリングされるようにする必要があります。 (これがないと、 デフォルトコードページは 932 / Shift-JIS で、 日本語が文字化けします。)

### TLS hardening

P00 では TLS 1.2 + 1.3 を有効化する必要があります (PS 5.1 で TLS 1.3 が利用不可な場合は graceful degrade):

```powershell
[Net.ServicePointManager]::SecurityProtocol = `
    [Net.SecurityProtocolType]::Tls12 -bor `
    [Net.SecurityProtocolType]::Tls13 -bor `
    [Net.SecurityProtocolType]::Tls11 -bor `
    [Net.SecurityProtocolType]::Tls
```

---

## A.6 パラメータ規約

### 共通スイッチ (この名前を verbatim で使用)

| スイッチ                     | 型       | 必須 | 説明                                                                |
| ---------------------------- | -------- | ---- | ------------------------------------------------------------------- |
| `-Action`                    | string   | ✓    | `Prepare`/`Verify`/`PrepareVerify`/`Install`/`All`/`Cleanup`/`ListPhases` |
| `-OnlyPhases`                | string[] |      | カンマ区切り phase ID。 `-Action` 由来のリストを上書き              |
| `-CleanWorkRoot`             | switch   |      | 実行前に workspace を削除                                            |
| `-AllowWorkstationInstall`   | switch   |      | Workstation OS での Install を許可 (デフォルト: ブロック)            |
| `-UseTestSigning`            | switch   |      | bcdedit testsigning にフォールバック (デフォルト: WDAC policy)        |
| `-WorkRoot`                  | string   |      | Workspace path 上書き                                                |
| `-PfxPassword`               | string   |      | 自己署名 PFX パスワード (ラボデフォルト: 空)                         |
| `-CertValidityYears`         | int      |      | 自己署名証明書有効期間 (デフォルト: 5)                               |

### Action -> Phase マッピング (姉妹スクリプト整合)

```
Prepare       : Prep のみ
Verify        : Verify のみ
PrepareVerify : Prep + Verify    (デフォルト、 システム状態変更なし)
Install       : Inst のみ        (Prep + Verify が事前実行済みと仮定)
All           : Prep + Verify + Inst   (full pipeline)
Cleanup       : (short-circuit、 Invoke-Cleanup を実行)
ListPhases    : (short-circuit、 Show-PhaseList を実行)
```

### 相互排他

- `-OnlyPhases` は `-Action` 由来の phase リストを上書きします。
- `-UseTestSigning` はデフォルトの WDAC policy パスと相互排他 — 両方の状態が適用される場合は警告。
- NPU script の `-OfflineZip` は `-InstallerUrl` より優先で Tier 4 short-circuit。

---

## A.7 Path Handling ルール

### wildcard 解釈ハザード

PowerShell の `*-Path` cmdlet はデフォルトでパス中の `[`、 `]`、 `?`、 `*` を wildcard として解釈します。 INF ファイル名にはしばしば `[` が含まれ (例: `oem_[stx].inf`)、 AMD インストーラ ZIP がブラケットを含むパスに展開されることもあります。 以下では常に `-LiteralPath` を使ってください:

```powershell
Test-Path -LiteralPath $path
Get-Item -LiteralPath $path
Remove-Item -LiteralPath $path
Copy-Item -LiteralPath $src -Destination $dst
Move-Item -LiteralPath $src -Destination $dst
Get-FileHash -LiteralPath $path
[System.IO.File]::ReadAllLines($path)  ← .NET API は定義上 wildcard を無視
```

### `-LiteralPath` をサポートしない cmdlet

- `Invoke-WebRequest -OutFile` (PowerShell 5.1) は `-LiteralPath` を受け付けません — パスは wildcard 解釈されます。 回避策: wildcard なし一時パス (例: `<dir>\.dl_<GUID>.part`) にダウンロードし、 `Move-Item -LiteralPath` で本来の宛先へ移動。
- `Export-PfxCertificate`、 `Export-Certificate`: `-FilePath` を受け取る (実運用で wildcard-safe。 AMD-CodeSign ファイル名にブラケットはないので許容)。

### 派生ファイル名の sanitize

INF Provider 文字列やドライババージョンからファイル名を生成する際は、 以下の文字を strip / replace してください: `/ \ : * ? " < > | [ ]`。 使用例:

```powershell
$safe = $raw -replace '[\/\\:*?"<>\|\[\]]', '_'
```

---

## A.8 エラーと診断の規約

### 3-tier 診断出力

1. **コンソール**: `Write-Step/Ok/Warn2/Fail/Skip` 経由のマーカー前置行 (A.5 参照)。
2. **CSV**: workspace 配下の phase 単位 machine-readable アーティファクト (A.9 参照)。
3. **Run summary**: `Show-RunSummary` (`finally` で必ず実行) が PhaseTimings + 総 elapsed + ScriptHash を出力。

### 失敗カテゴリ分類

`$Script:PhaseResults` の phase 結果は以下のいずれかでタグ付けされます:

| ステータス | 意味                                                                            |
| ---------- | ------------------------------------------------------------------------------- |
| `OK`       | Phase 正常終了                                                                  |
| `FAIL`     | Phase が例外を発生させた (`Invoke-PhaseRunner` でキャッチ)                      |
| `SKIP`     | `-Action` / `-OnlyPhases` で選択されなかった (summary 表示のみ)                 |

`-Action Install` (または `All`) で top-level try/catch が `$Script:TopLevelException` を持って到達した場合、 dispatcher は exit code `1` で終了します。 それ以外は `0`。

### スタックトレースの可視化

top-level 例外時は、 ユーザーが Issue 報告にトレースをコピーできるよう、 `.ScriptStackTrace` を `Write-Skip` 行で出力します:

```powershell
foreach ($line in ($_.ScriptStackTrace -split "`n")) {
    Write-Skip ("    {0}" -f $line.TrimEnd())
}
```

---

## A.9 CSV カラム規約

### `inf_inventory.csv` (P05 出力、 3 スクリプト共通)

| カラム                | 型     | 注記                                                            |
| --------------------- | ------ | --------------------------------------------------------------- |
| `FileName`            | string | 必須                                                            |
| `FullPath`            | string | 必須                                                            |
| `Provider`            | string | `[Version]` Provider から                                       |
| `DriverVer`           | string | `[Version]` DriverVer から                                      |
| `Class`               | string | デバイスクラス                                                  |
| `HwidCount`           | int    | INF 内の総 HWID 数                                              |
| `MatchesTargetNpu`    | bool   | NPU script 専用                                                 |
| `MatchedHwidCount`    | int    | NPU script 専用 (target platform にマッチする HWID 数)          |
| `HasServerDecoration` | bool   | INF が既に `ProductType=3` を持つ                                |
| `WorkstationDecCount` | int    | Workstation decoration 数                                       |
| `ServerDecCount`      | int    | Server decoration 数                                            |
| `NeedsPatch`          | bool   | `WorkstationDecCount > 0 -and ServerDecCount == 0`              |
| `SelectedForPipeline` | bool   | パイプライン filter 通過                                        |
| `HwidPreview`         | string | 最初の 3 HWID を連結 (人間可読)                                 |

### CSV エンコーディング

- エンコーディング: UTF-8 (BOM なし)。
- 引用: PowerShell `Export-Csv -NoTypeInformation` デフォルト挙動。
- 区切り文字: `,` (カンマ)。
- 改行コード: CRLF (Windows での PowerShell デフォルト)。

---

## A.10 環境評価 (Phase P00)

P00 は無条件で実行され、 全 downstream phase が依存する入力を収集します:

### Step 0: PowerShell 環境

`Show-PowerShellEnvironment` が以下をダンプ:

- `PSVersion`、 `PSEdition`、 `PSCompatibleVersions`
- `CLRVersion`、 `BuildVersion`、 `OS`、 `Platform`

そして `<5.1` または 64-bit でない場合は hard-fail。

### Step 1: Administrator 特権

`Test-AdminPrivilege` が非昇格実行時に throw。

### Step 2: TLS hardening

`Set-NetworkProtocol` が TLS 1.2 + 1.3 を有効化 (PS 5.1 では TLS 1.2 に degrade)。

### Step 3: OS profile 解決

`Show-OperatingSystemDetail` が OS build を inf2cat `/os:` switch に解決:

| Build  | Profile         | inf2cat /os:       |
| ------ | --------------- | ------------------ |
| 26100  | WS2025          | Server2025_X64     |
| 22631  | WS2022-equiv    | ServerFE_X64       |
| 22000  | WS2022-equiv    | ServerFE_X64       |
| 20348  | WS2022          | ServerFE_X64       |
| 19041  | WS2019-equiv    | ServerRS5_X64      |
| 17763  | WS2019          | ServerRS5_X64      |
| 14393  | WS2016          | Server2016_X64     |

### Step 4: ProductType 検出

`ProductType = 1` (Workstation) は build 26100 上で「WS2025 PRE-MIGRATION PREVIEW MODE」banner を出力。 `ProductType = 3` (Server) はそのまま進行。

---

## A.11 psa.py による静的解析

### Setup

```bash
# リポジトリルートから
python3 tools/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 tools/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
python3 tools/psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
```

### 必須ゲート

全 commit は **errors 0** でパスする必要があります。 警告は許可されますが、 トリアージして fix するか false positive として注釈してください。

### チェックカバレッジ (C1–C10)

| Code | 重要度  | 説明                                                                     |
| ---- | ------- | ------------------------------------------------------------------------ |
| C1   | error   | Brace balance (`{` vs `}`)                                               |
| C2   | error   | Paren balance (`(` vs `)`)                                               |
| C3   | error   | Bracket balance (`[` vs `]`)                                             |
| C4   | warning | 未定義変数参照 (ヒューリスティック)                                      |
| C5   | warning | Auto-variable shadowing (`$args`、 `$_`、 `$matches` 等)                 |
| C6   | warning | `Start-Process -ArgumentList` (スペース含むパスでは `ProcessStartInfo` 推奨) |
| C7   | warning | 裸 `$variable` への `-match` (`$null` の場合 true を返す)                 |
| C8   | info    | TODO / FIXME マーカー                                                    |
| C9   | warning | 末尾 backtick の後に空行                                                  |
| C10  | warning | 空文字列への `-match` (常に true)                                         |

Exit code: `0` = clean、 `1` = warnings のみ、 `2` = errors。 CI で有用。

### 既知の false positive

null-guard ブロック内 (例: `if ($var) { ... -match $var }`) の `C7 -match against bare $var` 警告は false positive — guard が既に null ケースを除外しています。 warnings のままで OK です。

---

## A.12 多言語ドキュメンテーション

### ファイルセット

| 英語版       | 日本語版       | 内容                                          |
| ------------ | -------------- | --------------------------------------------- |
| `README.md`  | `README.ja.md` | エンドユーザー向けドキュメント                |
| `TESTING.md` | `TESTING.ja.md` | クラウド / 物理 ハードウェア回帰テスト       |
| `SPEC.md`    | `SPEC.ja.md`   | 開発者向け仕様書 (本ドキュメント)             |

### 同期ルール

英語版を更新したら、 同 commit (または英語版 commit hash を参照する直後の follow-up commit) で日本語版も更新する必要があります。 以下のパリティを保ってください:

- セクション構造 (同じ H2 / H3 見出し)
- テーブル (同じカラム)
- コードブロック (同じ内容、 日本語ファイルは bilingual comment 可)
- 例 (同じコマンド、 周囲の散文をローカライズ)

### 日本語版のスタイル

- 英語の技術用語は英語のまま保持 ("phase"、 "decoration"、 "WDAC policy"、 "Workstation"、 "Server SKU" 等は訳さない)
- 助詞は全角形を使用: 「、」 「。」「・」 (半角の "," "." ではない)
- 括弧: 強調用語に「」、 コードスパンには ` `` ` を使用

### 必須の disclaimer / license セクション

各 README には以下を含める必要があります:

1. 先頭の ⚠️ 免責事項ブロック (USE AT YOUR OWN RISK、 BitLocker 警告、 no warranty)
2. 末尾の License セクション (MIT、 AMD のリディストリビューション規約は本リポジトリではなく runtime ダウンロードされる AMD バイナリに適用される旨の注記)

---

## A.13 開発ワークフロー

### イテレーションサイクル

```
1. コードを書く / 修正する
2. python3 tools/psa.py <script>.ps1     ← ゲート: errors 0 必須
3. AWS EPYC EC2 でテスト (pipeline-only)  ← TESTING.md §3 準拠
4. 実物の AMD ハードウェアでテスト        ← TESTING.md §4 準拠 (利用可能なら)
5. 挙動が変わったら README (en + ja) + SPEC (en + ja) 更新
6. $Script:ScriptVersion のリビジョン番号を bump して commit
```

### リビジョン規律

以下のいずれかを変える commit はリビジョン番号を bump (例: `r47` → `r48`):

- Phase semantic (21 phase のいずれか)
- 出力フォーマット (CSV カラム、 log マーカー、 banner layout)
- パラメータセット (スイッチの追加 / 削除 / リネーム)

外観のみの変更 (メッセージの typo 修正、 README の言い回し変更) はリビジョン bump 不要です。

### 発明より再利用

新規 helper 関数を書く前に:

1. 既存 3 スクリプトに同等のものがないか検索 (`grep -rn 'function <NewName>' .`)。
2. 見つかったら最新リビジョンから verbatim でコピー。
3. 見つからなければ、 ファイル先頭付近の正規 helper セクション (「Output helpers」または「Environment helpers」配下) に追加して、 将来のスクリプトが再利用できるようにする。

---

# Part B — スクリプト固有仕様

## B.1 Chipset スクリプト (`Deploy-AMDChipsetDriverOnWindowsServer.ps1`)

### 識別

- **現リビジョン**: `chipset-2026.05.13-r48` (tag: `chipset-cert-name-wdac-guid-r48`)
- **Workspace**: `C:\AMD-Chipset-WS\`
- **自己署名証明書 subject**: `CN=AMD Chipset Driver Self-Sign (WS2025 Lab, At Own Risk)`
- **自己署名証明書ファイル**: `cert\AMD-Chipset-Driver-CodeSign.{pfx,cer}` (r48+; pre-r48 は `AMD-Driver-CodeSign.{pfx,cer}` を使用)
- **WDAC policy GUID** (r48+): 固定値 `503860EA-8837-4169-9BC4-19E5AEED721B`; `-WdacPolicyGuid` で上書き可能。 Pre-r48 deploy は動的生成 PolicyId を `cert\AmdSuppPolicyId.txt` に記録していた。
- **WDAC SupplementsBasePolicyID**: `{A244370E-44C9-4C06-B551-F6016E563076}` (Windows 標準 base CI policy); `-WdacBasePolicyGuid` で上書き可能

### 入力

- AMD Chipset Software インストーラ EXE (~75 MB)、 <https://www.amd.com/en/support/category/chipsets> を probe して発見
- オプション: `-InstallerUrl <url>` で URL 探索を bypass
- オプション: `-AmdLandingUrls` / `-AmdFallbackUrl` で URL 探索を上書き (AMD がサポートページを再構成した時に使用)

### Platform 検出ロジック

`Get-AmdChipsetPlatform` ヒューリスティックが CPU 名 (`Win32_Processor.Name`) を platform codename に変換:

| CPU パターン                      | Codename       | Family    |
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

### Phase 固有挙動

- **P03 / P04**: インストーラ EXE は 7-Zip で展開。 失敗時はインストーラを silent 起動して `C:\AMD\` から収集する fallback。
- **P05**: INF を source variant で分類: `W11x64` (Win11) / `WTx64` (Workstation x64) / `WT6A_INF` / `WT64A`。 OS に合致する variant のみをパイプライン対象に選択。
- **P06**: PSP driver (`amdpsp.inf`) は **明示的な BitLocker 警告なしには絶対にパッチしない** — Disclaimer §5 参照。

### 既知の制約

- 5 年の証明書有効期間 (P07 でハードコード)。
- パッチ済みドライバは AMD 公開の `DriverDate` を保持。 AS-IS vs TO-BE 比較は timezone 起因の false positive を避けるため `.Date` truncation を使用 (Part D D.1 参照)。

---

## B.2 Graphics スクリプト (`Deploy-AMDGraphicsDriverOnWindowsServer.ps1`)

### 識別

- **現リビジョン**: `graphics-2026.05.13-r17` (tag: `graphics-cert-name-wdac-guid-r17`)
- **Workspace**: `C:\AMD-Graphics-WS\`
- **自己署名証明書 subject**: `CN=AMD Graphics Driver Self-Sign (WS2025 Lab, At Own Risk)`
- **自己署名証明書ファイル**: `cert\AMD-Graphics-Driver-CodeSign.{pfx,cer}` (r17+; pre-r17 は `AMD-Driver-CodeSign.{pfx,cer}` を使用)
- **WDAC policy GUID** (r17+): 固定値 `85336828-3080-41C5-81EC-FD587DC090D3`; `-WdacPolicyGuid` で上書き可能。 Pre-r17 deploy は動的生成 PolicyId を `cert\AmdSuppPolicyId.txt` に記録していた。
- **WDAC SupplementsBasePolicyID** (r17+): `{A244370E-44C9-4C06-B551-F6016E563076}` (Windows 標準 base CI policy); `-WdacBasePolicyGuid` で上書き可能。 Pre-r17 は非標準値 `{B355481F-55DA-5D17-C662-07127F674187}` を使用していた (Part D D.8 参照)。

### 入力

- AMD Adrenalin Edition インストーラ EXE (~600 MB)、 <https://www.amd.com/en/support/category/graphics> を probe して発見
- 2 つのブランチ: Vega-Polaris Legacy (~19 INF) と Main Adrenalin (~67 INF for Phoenix+)。
- オプション: `-InstallerUrl <url>` で URL 探索を bypass
- オプション: `-AmdLandingUrls` / `-AmdFallbackUrl` で URL 探索を上書き

### Platform 検出ロジック

`Get-AmdGraphicsPlatform` がまず `Win32_VideoController` を enumerate、 次に CPU 名を確認 (integrated GPU 用)。 ブランチ選択 (Vega-Polaris Legacy vs Main Adrenalin) は GPU PCI Device ID 範囲に基づく。

### Phase 固有挙動

- **P03**: AMD は定期的にサポートページを再構成 — probe 失敗時は候補 URL リストを詳細に出力し、 `-InstallerUrl` にフォールバック。
- **P05**: HD Audio (`hdaudio.inf`)、 Audio CoProcessor (`acp.inf`)、 USB-C UCSI (`ucsi.inf`)、 Display (`display.inf`) INF はデフォルトで含む。 一部は Win32_VideoController のベンダーに基づき条件的に skip。

### 既知の制約

- HDMI Audio (`hdaudio.inf`) の provider 名は Adrenalin ブランチ間で異なる。 INF inventory filter は安定性のため provider 名でなく Class = `MEDIA` を使用。

---

## B.3 NPU スクリプト (`Deploy-AMDNpuDriverOnWindowsServer.ps1`)

### 識別

- **現リビジョン**: `npu-2026.05.13-r3` (tag: `npu-cert-name-r3`)
- **Workspace**: `C:\AMD-NPU-WS\`
- **自己署名証明書 subject**: `CN=AMD NPU Driver Self-Sign (WS2025 Lab, At Own Risk)`
- **自己署名証明書ファイル**: `cert\AMD-NPU-Driver-CodeSign.{pfx,cer}` (r3+; pre-r3 は `AMD-NPU-CodeSign.{pfx,cer}` を使用)
- **WDAC policy 名**: `AMD-NPU-Driver-SelfSign-Lab`
- **WDAC policy GUID**: 固定値 `8B2C4F12-1E9D-4D7B-A4F8-9C7E2B6A53D1` (スクリプト別に stable な hardcoded value、 実行間で policy を識別してクリーン削除する用途); `-WdacPolicyGuid` で上書き可能 (r3+)

### 入力 (4-tier 解決)

```
Tier 1 ★ : -InstallerUrl <url>                            明示 URL
Tier 2   : -AmdAccountUser/-AmdAccountPassword             account.amd.com 自動 DL (BEST-EFFORT、 デフォルト無効)
Tier 3   : EULA-gated 直接 fetch probe                     通常はフォールスルー
Tier 4 ★ : -OfflineZip <path>  または sibling NPU_RAI*_WHQL.zip   RECOMMENDED
```

Tier 4 (`-OfflineZip`) が推奨パターンです。 account.amd.com は JavaScript 駆動の SPA (2026-05-10 検証済み)、 Tier 2 はブラウザベースのフォーム操作なしでは成功しにくいためです。

### NPU codename 検出 (PCI HWID + REV byte)

`Get-AmdNpuPlatform` が `pnputil /enum-devices /bus PCI /deviceids` を使用し、 以下にマッチ:

| Codename       | Short | PCI HWID                                   | CPU 区別子              |
| -------------- | ----- | ------------------------------------------ | ---------------------- |
| Phoenix        | PHX   | `PCI\VEN_1022&DEV_1502&REV_00`             | Ryzen 7040 / `7\d40\b` |
| Hawk Point     | HPT   | `PCI\VEN_1022&DEV_1502&REV_00`             | Ryzen 8040 / `8\d40\b` |
| Strix Point    | STX   | `PCI\VEN_1022&DEV_17F0&REV_00/10/11`       | Ryzen AI 300 / AI Max 300 |
| Krackan Point  | KRK   | `PCI\VEN_1022&DEV_17F0&REV_20`             | Ryzen AI 200           |

Phoenix と Hawk Point は `DEV_1502&REV_00` を共有。 CPU 名 (`Win32_Processor.Name`) で区別。

### 独立バージョニング軸 (driver vs Ryzen AI Software)

NPU kernel driver versioning は Ryzen AI Software versioning と **完全に独立**です。 AMD のドキュメント:

- **NPU drivers**: 32.0.203.280 (`NPU_RAI1.5_280_WHQL.zip`) または 32.0.203.314 (`NPU_RAI1.6.1_314_WHQL.zip`)
- **Ryzen AI Software**: 1.5 / 1.6.1 / 1.7 / 1.7.1 (latest)

両方の NPU driver ZIP は現行 RAI 1.7.1 で動作。 AMD は「常に最新の RAI Software を使用」を推奨していますが、 driver バージョンとは coupling していません。

スクリプトはこれを 2 つの独立パラメータで公開:

- `-NpuDriverPackage <NPU_RAI1.5_280 | NPU_RAI1.6.1_314 | latest>`
- `-RyzenAiSoftwareVersion <1.5 | 1.6.1 | 1.7 | 1.7.1 | latest>`

互換性評価は **別の**軸 (`Test-NpuDriverRaiCompatibility`) で、 driver build >= 選択 RAI バージョンの最小値 (現状 全 RAI バージョンで `32.0.203.280`) を assert。

### Phase 固有挙動

- **P00**: NPU 固有の OS サポート警告 (「Ryzen AI Software は AMD ドキュメント上 Windows 11 only」) を出力。
- **P03**: NPU 検出の前に 4-tier installer 解決を実行 (解決によりダウンロードする ZIP ファイル名が決まり、 これはホストの NPU codename とは独立のため)。
- **I00**: AMD Ryzen AI EULA への明示的な `I AGREE` 確認を要求 (オプションではない)。
- **I04**: インストーラ DL URL、 前提条件、 検証ステップ (Miniforge + conda env + `quicktest.py`) を含む Ryzen AI Software guidance を表示。

### 既知の制約

- `account.amd.com` は JavaScript 駆動 SPA。 PowerShell の form-POST 認証 (Tier 2) は best-effort と文書化されており、 失敗が予想される。 常に Tier 4 (`-OfflineZip`) を優先してください。
- Ryzen AI Software (user-mode stack) は公式に Windows-11-only。 Server 2025 では kernel driver は load するが、 user-mode 層で推論ワークロードが失敗する可能性。

---

# Part C — 品質ゲートと検証チェックリスト

`main` への全 commit は以下のゲートを満たす必要があります。

## C.1 静的チェック

- [ ] `python3 tools/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1` → errors 0
- [ ] `python3 tools/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1` → errors 0
- [ ] `python3 tools/psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1` → errors 0

## C.2 機能チェック (影響を受けたスクリプトに対して)

- [ ] `-Action ListPhases` が期待される 21-phase テーブルを出力。
- [ ] `-Action PrepareVerify -CleanWorkRoot` が AWS EPYC EC2 (またはターゲットでないホスト) で `-AssumeIfMissing` (NPU script) / 適切な platform override (chipset / graphics) を使ってエラーなく完了。
- [ ] `Show-RunSummary` が exit path に関わらずレンダリングされる (成功 / 失敗どちらでも)。
- [ ] `Format-Elapsed` が `0.42s`、 `1m2.3s`、 `1h2m3s` に対して正しい文字列を生成する。

## C.3 ドキュメンテーションチェック

- [ ] Phase semantic が変わった場合: SPEC.md Part B を更新。
- [ ] パラメータが追加 / 削除 / リネームされた場合: README.md と README.ja.md のパラメータテーブルを更新。
- [ ] 出力フォーマットが変わった場合: SPEC.md A.9 CSV カラムと README.md 出力ファイルセクションを更新。
- [ ] 日本語ミラー (`README.ja.md`、 `TESTING.ja.md`、 `SPEC.ja.md`) が英語版と同期している。

## C.4 スクリプト間整合性チェック

- [ ] 3 スクリプトとも `$Script:PhaseRegistry` で `[pscustomobject]@{...}` を使用 (`@{...}` ではない)。
- [ ] 3 スクリプトとも姉妹スクリプト整合の関数命名を使用: `Invoke-{Group}Phase{NN}_{Name}`。
- [ ] 3 スクリプトとも同じ `-Action` ValidateSet を使用: `'Prepare','Verify','PrepareVerify','Install','All','Cleanup','ListPhases'`。
- [ ] 3 スクリプトとも同じマーカー semantic を使用: `[*]` Cyan / `[+]` Green / `[!]` Yellow / `[X]` Red / `[~]` DarkGray。

---

# Part D — 既知の落とし穴と教訓

これらは、 既に修正済みの issue で将来のリビジョンが regression しないよう文書化されています。

## D.1 Chipset r46 — timezone 起因の DriverDate 誤検知

**症状**: V05 dry-run plan が同一ドライバに対して `[UPGRADE]` action を報告。 `Win32_PnPSignedDriver.DriverDate` は UTC midnight で保存されるが、 `Get-CimInstance` がローカル時刻に変換するため、 `[datetime]` 比較で日付オフセットが発生していた。

**修正**: `Compare-InfDriverVer` で、 現ドライバ日付とパッチ済 INF 日付の両方で比較前に `.Date` truncation (year/month/day のみ) を使用。

```powershell
$cdate = if ($CurrentDate) { $CurrentDate.Date } else { $null }
$pdate = if ($PatchedDate) { $PatchedDate.Date } else { $null }
```

3 スクリプト (Chipset / Graphics / NPU) で verbatim で保持。

## D.2 NPU r1 — 架空ファイル名 `NPU_RAI1.7.1_380_WHQL.zip`

**症状**: 初期の NPU script リビジョンは `NPU_RAI1.7.1_380_WHQL.zip` をデフォルトファイル名として使用、 これを RAI 1.7.1 にマッピングしていた。 しかし AMD が実際に RAI 1.7.1 で公開するファイル名は **RAI 1.6.1 と同じ**、 すなわち `NPU_RAI1.6.1_314_WHQL.zip` (driver build 32.0.203.314)。

**修正**: NPU driver と Ryzen AI Software は独立にバージョニング。 スクリプトは現在これら 2 つを別パラメータで公開し、 デフォルトの `-NpuDriverPackage latest` は `NPU_RAI1.6.1_314` (最新の documented) に解決される。 <https://ryzenai.docs.amd.com/en/latest/inst.html> 2026-04-19 版に対して検証済み。

## D.3 NPU r2 — `Show-PhaseHeader` vs `Write-PhaseHeader` 命名 drift

**症状**: 初期 NPU リビジョンは `Show-PhaseHeader` を使用 (姉妹スクリプトは `Write-PhaseHeader`)、 phase entry banner 色は Yellow `#`×78 (姉妹: Magenta `=`×72) であった。 これにより複数スクリプトを連続実行したログでの視覚的整合が崩れた。

**修正**: 姉妹スクリプト整合 refactor (r2) で `Write-PhaseHeader` にリネーム、 Magenta `=`×72 + script-tag DarkGray 行を採用。 現在 3 スクリプト全てで同一。

## D.4 NPU — Action `'Install'` semantic drift

**症状**: NPU r1 は `-Action Install` を「全 21 phase」(full pipeline) にマッピングしていたが、 姉妹スクリプトは「Inst phases のみ」 (Prep + Verify が事前実行済みと仮定) にマッピング。

**修正**: 姉妹スクリプト整合 refactor (r2) で `-Action Install` を Inst-only に修正し、 full pipeline 用に `-Action All` を新設。 Workstation OS guard も `Install` と `All` の両方で発動するように修正。

## D.5 ja-JP コンソールエンコーディング (chcp 932)

**症状**: ja-JP Windows コンソールのデフォルト (コードページ 932、 Shift-JIS) で日本語ログ文字列が文字化け。

**修正**: P00 で `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` を強制。 `*>&1 | Tee-Object` を使う operator は、 ファイルエンコーディングも明示的に設定する必要がある。

## D.6 `Invoke-WebRequest -OutFile` の `-LiteralPath` 非対応 (PS 5.1)

**症状**: `[` または `]` を含むパスへダウンロードする際、 `Invoke-WebRequest -OutFile` (PS 5.1) がパスを wildcard 解釈する。

**修正**: wildcard なし temp ファイル名 (`<dir>\.dl_<GUID>.part`) にダウンロードし、 `Move-Item -LiteralPath` で本来の宛先へ移動。 NPU script の `Invoke-NpuZipDownload` でパターン保持。

## D.7 コード署名証明書ファイル名規約の統一 (Chipset r48 / Graphics r17 / NPU r3)

**症状**: スクリプト間整合の commit 以前、 3 スクリプトは以下のように一貫性のないコード署名証明書ファイル名を使用していました:

| スクリプト | 修正前ファイル名 | 不整合の経緯 |
| --- | --- | --- |
| Chipset | `cert\AMD-Driver-CodeSign.{pfx,cer}` | NPU が存在しなかった時期のリポジトリで「AMD-Driver」が一意だった |
| Graphics | `cert\AMD-Driver-CodeSign.{pfx,cer}` | Chipset からコピペされ、 同じ汎用名のまま |
| NPU | `cert\AMD-NPU-CodeSign.{pfx,cer}` | 後発のため特化した名前にしたが、 古い 2 つと不整合 |

これにより 2 つの運用上の問題が発生していました:

1. **並列実行時の曖昧性**: 3 スクリプト全てを実行したホストでは、 異なる workspace (`C:\AMD-Chipset-WS\cert\` と `C:\AMD-Graphics-WS\cert\`) に 2 つの `AMD-Driver-CodeSign.{pfx,cer}` が存在する状況になります。 `Cert:\LocalMachine\Root` を確認した operator は、 provider 文字列を見ただけではどのスクリプトが作成した cert か即座にわからない。
2. **姉妹スクリプト対称性違反**: SPEC §A.1.4 はスクリプト別 `C:\AMD-<short>-WS\` workspace 分離を mandatory としています。 cert ファイル名も同じくスクリプト別 prefix 規約に従うべき。

**修正**: 3 スクリプト全てを `cert\AMD-{Chipset|Graphics|NPU}-Driver-CodeSign.{pfx,cer}` に標準化:

| スクリプト | 修正後ファイル名 | パス |
| --- | --- | --- |
| Chipset r48 | `AMD-Chipset-Driver-CodeSign.{pfx,cer}` | `C:\AMD-Chipset-WS\cert\` |
| Graphics r17 | `AMD-Graphics-Driver-CodeSign.{pfx,cer}` | `C:\AMD-Graphics-WS\cert\` |
| NPU r3 | `AMD-NPU-Driver-CodeSign.{pfx,cer}` | `C:\AMD-NPU-WS\cert\` |

**既存 deploy へのアップグレード影響**:

- 旧 `cert\AMD-Driver-CodeSign.{pfx,cer}` ファイルはアップグレード後も disk 上に残置 (Cleanup はファイル名でなく thumbprint で trust store から cert を除去するため)。
- 新スクリプトで `-Action Install` を実行すると新名で PFX/CER が生成され、 旧 PFX/CER は workspace 内で孤立。
- クリーンなアップグレードには、 アップグレード**前**に旧スクリプトリビジョンで `-Action Cleanup` を実行。

## D.8 WDAC supplemental policy GUID 標準化 (Chipset r48 / Graphics r17 / NPU は既存仕様維持)

**症状 1 (Chipset r47、 Graphics r16 以前)**: supplemental policy `PolicyID` は `Set-CIPolicyIdInfo -ResetPolicyID` で動的に生成され、 deploy のたびに新しい GUID が作られていました。 GUID は `<workspace>\cert\AmdSuppPolicyId.txt` に記録し、 後で `Cleanup` で参照していました。

これには 2 つの不都合がありました:
- 再 deploy は前の deploy の policy slot を**置き換えず**、 新しい slot を作る — `C:\Windows\System32\CodeIntegrity\CiPolicies\Active\` に休眠状態の `<oldGuid>.cip` が蓄積。
- `<workspace>\cert\AmdSuppPolicyId.txt` が失われた場合 (例: workspace を手動削除)、 `Cleanup` がデプロイ済み policy を特定できない。

**症状 2 (Graphics r16 以前のみ)**: スクリプトが `SupplementsBasePolicyID = '{B355481F-55DA-5D17-C662-07127F674187}'` を使用していました。 この GUID は Microsoft 出荷の CI base policy のいずれにも対応しない **非標準値**で、 開発初期のコピペ artefact がほぼ確実です。 Chipset と NPU スクリプトはどちらも Windows デフォルトの `{A244370E-44C9-4C06-B551-F6016E563076}` を正しく使用。 Graphics の supplemental policy は存在しない base を「supplement」する状態で、 Windows は警告付きで load するか silently 無視している可能性。

**修正 (r48 / r17 / r3)**:

1. **スクリプト別の固定 supplemental policy GUID** — 3 スクリプト全てを deploy したホストで共存可能なよう個別値:
   - Chipset: `503860EA-8837-4169-9BC4-19E5AEED721B`
   - Graphics: `85336828-3080-41C5-81EC-FD587DC090D3`
   - NPU: `8B2C4F12-1E9D-4D7B-A4F8-9C7E2B6A53D1` (既存値を維持)
2. **operator 上書き** via `-WdacPolicyGuid <GUID>`、 braces 付き / なしどちらも受理。 2 つのユースケース:
   - **レガシークリーンアップ**: 旧 PolicyId を `<workspace>\cert\AmdSuppPolicyId.txt` から読み、 `-Action Cleanup -WdacPolicyGuid <oldGuid>` で pre-r48 / r17 deploy を削除。 新しい `Test-AmdWdacPolicyDeployed` は、 固定 GUID が active でない場合に legacy marker file を自動 fallback で参照するため、 manual GUID lookup なしで unattended Cleanup も動作。
   - **並列複数 deploy**: 同じスクリプトを別 GUID で複数 deploy (稀)。
3. **Graphics 固有修正**: デフォルト `SupplementsBasePolicyID` を `{B355481F-...}` から Microsoft 標準 `{A244370E-...}` へ修正。 カスタム base CI policy を使う環境向けに `-WdacBasePolicyGuid` で上書き可能。
4. **実装詳細**: PowerShell の `Set-CIPolicyIdInfo` には `-PolicyId` スイッチがないため、 `Set-CIPolicyIdInfo -SupplementsBasePolicyID …` を実行後 (`-ResetPolicyID` は使わない) に XML 内の `<PolicyID>` 要素を直接 patch。

**アップグレード影響**: D.7 と同様 — クリーンなアップグレードには、 旧スクリプトリビジョンで `-Action Cleanup` を実行してから新版を deploy。 新スクリプトの `Cleanup` action は marker-file fallback で legacy 動的 GUID policy も検出するため、 「アップグレード後に Cleanup」も動作 (cleanup サイクルが 1 回追加)。

---

## Appendix: 本 SPEC から新規姉妹スクリプトを seed する方法

4 番目のスクリプト (例: `Deploy-AMDRocmRuntimeOnWindowsServer.ps1`) を作成する場合:

1. 最新の既存スクリプト (NPU r3 が最も新しい姉妹整合 reference) を出発テンプレートとしてコピー。
2. `$Script:ScriptName`、 `$Script:ScriptVersion`、 `$Script:ScriptTag`、 `$Script:CertSubjectCn`、 `$Script:WdacPolicyName`、 `$Script:WdacPolicyGuid`、 `$Script:WorkRoot` を新スクリプト固有の値に置換。
3. **domain helpers** セクション (platform 検出、 installer 解決、 INF inventory filter) のみ再実装。 他のセクションは全て verbatim で再利用。
4. `python3 tools/psa.py <new-script>.ps1` を errors 0 になるまで実行。
5. SPEC.md (および SPEC.ja.md) に B.4 セクションを追加。
6. `README.md` の「リポジトリの内容物」テーブル、 「パラメータ」セクション、 「リスク分類」テーブルに新スクリプトを追加。
7. AWS EPYC EC2 回帰テストシナリオを `TESTING.md` に追加。

厳格な姉妹スクリプト規約の目的はまさにこれです: 新スクリプトは ~80% のボイラープレート継承 + ~20% の新規ロジック、 となるよう設計されています。
