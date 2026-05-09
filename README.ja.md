# Deploy-AMD-Drivers-For-WindowsServer

AMD のコンシューマー向け Ryzen チップセットドライバ・Radeon グラフィックスドライバを **Windows Server 2025** に install できるように、INF の `ProductType=3` decoration をパッチし、自己生成証明書で catalog を再署名する PowerShell パイプラインです。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://learn.microsoft.com/ja-jp/powershell/)
[![Target: Windows Server 2025](https://img.shields.io/badge/Target-Windows%20Server%202025-success.svg)](https://learn.microsoft.com/ja-jp/windows-server/get-started/windows-server-2025)

> **実行する前に必ず最後まで読んでください。** これは *最後の手段としての lab 専用ツール* です。AMD はコンシューマー向け Ryzen プラットフォーム (例: Lenovo ThinkCentre Tiny / ThinkPad / mini-PC に搭載される Cezanne / Renoir / Phoenix APU 等) において Windows Server 2025 を**公式にサポートしていません**。公式ドライバが利用可能な場合は **必ずそちらを優先**してください。本リポジトリは、公式 Server 向けドライバが提供されない狭い局面で、自己署名ドライバチェーンの運用リスクを自分で受け入れた上で利用するためのものです。

🇬🇧 **English README is at [README.md](./README.md).**

---

## 目次

- [このリポジトリの存在理由](#このリポジトリの存在理由)
- [リポジトリの内容物](#リポジトリの内容物)
- [対応範囲](#対応範囲)
- [Quick Start](#quick-start)
- [パイプラインアーキテクチャ (21 phase)](#パイプラインアーキテクチャ-21-phase)
- [システム要件](#システム要件)
- [自己署名証明書: 有効期限・更新・失効](#自己署名証明書-有効期限更新失効)
- [免責事項・自己責任の確認](#免責事項自己責任の確認)
- [トラブルシューティング](#トラブルシューティング)
- [開発ツール](#開発ツール)
- [参考リンク](#参考リンク)
- [ライセンス](#ライセンス)
- [コントリビューション](#コントリビューション)

---

## このリポジトリの存在理由

コンシューマー向け AMD プラットフォーム (Ryzen 4000 / 5000 / 6000 / 7000 / 8000 mobile / desktop APU、および discrete Vega / Polaris / RDNA Radeon GPU) に Windows Server 2025 をインストールすると、複数の AMD デバイスが **AMD 純正ドライバではなく Microsoft の汎用 in-box ドライバ** (`machine.inf`、`pci.inf`、`hdaudbus.inf`、`display.inf` 等) にバインドされてしまいます。原因は 2 つあります:

1. **AMD の INF ファイルが `[Manufacturer]` decoration に `ProductType=1` (Workstation) 制限を含んでいる**ため、Windows Setup がこれを尊重して Server SKU (`ProductType=3`) ではドライバのバインドを拒否します。
2. **AMD の catalog (.cat) 署名がオリジナルの INF を attest している**ため、INF を編集して Server decoration を追加した時点で署名が無効になり、ドライバが kernel-mode 署名チェックに失敗します。Windows Server 2025 は Secure Boot と HVCI を経由してこれを厳格に enforce します。

本パイプラインは以下の手順で両方の問題を解決します:

- AMD の Workstation `[Manufacturer]` decoration を解析し、**各エントリを `ProductType=3` (Server) で mirror** します (元の Workstation エントリは保持されるため、パッチ後の INF は両 OS 互換になります)。
- `inf2cat /os:Server2025_X64` で新しい `.cat` catalog を生成します。
- **自己生成のコード署名証明書で catalog を署名**し、その証明書を `LocalMachine\Root` + `LocalMachine\TrustedPublisher` に import、さらに **WDAC supplemental Code Integrity policy** で kernel-mode 署名者として認可します (Secure Boot は **ON のまま** — Windows Server 2022+ / Windows 11 22H2+ では `bcdedit /set testsigning on` 不要です)。

---

## リポジトリの内容物

| ファイル | 用途 |
| --- | --- |
| `Deploy-AMDChipsetDriverOnWindowsServer.ps1` | チップセットドライバパイプライン (GPIO、SMBus、PSP、MicroPEP、PMF 等)。ソース: AMD Chipset Software EXE 約 75 MB、INF 約 67 個。 |
| `Deploy-AMDGraphicsDriverOnWindowsServer.ps1` | グラフィックスドライバパイプライン (Display、HD Audio、Audio CoProcessor、ACP、USB-C UCSI 等)。ソース: AMD Adrenalin Edition EXE 約 600 MB、INF 約 19 個 (Vega-Polaris Legacy ブランチ) または約 67 個 (Phoenix 以降の Main Adrenalin ブランチ)。 |
| `README.md` | 英語版ドキュメント。 |
| `README.ja.md` | 本ドキュメント (日本語版)。 |
| `TESTING.md` | クラウド (AWS) でのテスト手順 (EPYC 複数世代対応) および物理ハードウェアでの検証結果。 |
| `CONTRIBUTING.md` | Issue・PR ガイドラインと regression test 手順。 |
| `LICENSE` | MIT License。 |
| `tools/psa.py` | PowerShell の静的解析ツール (CI で利用)。詳細は [開発ツール](#開発ツール) を参照。 |
| `tools/README.md` | psa.py の使い方ガイド。 |

両 PowerShell スクリプトは同じ 21 phase アーキテクチャ、同じ自己署名モデル、同じ WDAC 認可パスを共有します。それぞれ別ワークスペース (`C:\AMD-Chipset-WS` と `C:\AMD-Graphics-WS`)、別の自己署名証明書を使用するため、相互に干渉しません。

---

## 対応範囲

### 対応ハードウェア

- **AMD Ryzen Mobile**: Ryzen 4000 (Renoir)、5000 (Cezanne / Lucienne / Barcelo / Barcelo-R)、6000 (Rembrandt)、7000 (Phoenix / Hawk Point)、8000 (Hawk Point refresh)、AI 300 (Strix Point / Krackan Point)、AI Max 300 (Strix Halo)。
- **AMD Ryzen Desktop APU**: Ryzen 5000G / 5000GE (Cezanne)、7000G / 8000G (Phoenix)。
- **AMD Radeon Graphics**: Vega 6 / 7 / 8 / 11 (内蔵、Renoir → Cezanne → Barcelo)、RDNA 3 (Phoenix 780M / 760M)、RDNA 3.5 (Strix Point)、discrete RX 5000 / 6000 / 7000 / 9000 シリーズ。
- **AMD AM4 / AM5 chipset**: X470、X570、X670/X670E、X870/X870E、B450、B550、B650、B850。
- **AMD ACPI device**: GPIO controller (`AMDI0030`、`AMDF030`)、I2C (`AMD0010`)、Micro PEP (`AMD0004`)、HSMP (`AMDI0097`)、PMF (`AMDI0100` / `AMDI0102`)、SFH (`AMDI0080` / `AMDI0011`)、UART (`AMD0020`)、Wireless Button (`AMDI0051`)、Pluton stub (`MSFT0200` / `MSFT0201`)。

### 対応**しない**ハードウェア

- **AMD NPU / XDNA Compute Accelerator** (`PCI\VEN_1022&DEV_1502`、AI 300 / Hawk Point NPU、Phoenix kipudrv): NPU ドライバは AMD Ryzen AI Software という別 bundle で提供されており、kernel ドライバと user-mode runtime のペアリングが非自明なため、**意図的に対応外**としています。AMD から standalone NPU installer が公開された際にそちらを使用してください。
- **AMD EPYC server chip** (AWS T3a / M5a / M6a / M7a / M8a、Hetzner AX dedicated 等で利用される CPU): EPYC は別の chipset モデルを使用しており、Microsoft Update 経由で first-party Server 対応ドライバが提供されます。本パイプラインは *コンシューマー* Ryzen 向けで、EPYC は対象外です。ただし AWS インスタンスは **パイプライン回帰テスト**には有用です — [TESTING.md](./TESTING.md) を参照してください。
- **リアルタイム GPU compute stack** (ROCm、HIP SDK、Adrenalin パッケージに含まれる user-mode driver 以外の OpenCL): Server 対応については AMD の ROCm ドキュメントを参照してください。

### スクリプトが生成するもの

```
C:\AMD-Chipset-WS\               (または C:\AMD-Graphics-WS\)
├── download\        AMD installer EXE
├── extracted\       EXE から展開された元 INF とバイナリ
├── patched\         ProductType=3 を mirror したパッチ済み INF
│                    + 生成された .cat ファイル + signtool 署名
├── cert\            自己署名コード署名証明書 (PFX + CER)
└── inf_inventory.csv / inf_inventory_report.txt
                     P05 inventory と INF 単位の解析レポート
```

`-Action Install` (もしくは I01-I04 phase) 実行後、スクリプトは以下を deploy します:

- 証明書を `LocalMachine\Root` + `LocalMachine\TrustedPublisher` に import。
- 当該証明書を kernel-mode 署名者として allowlist する **WDAC supplemental Code Integrity policy** を `C:\Windows\System32\CodeIntegrity\CiPolicies\Active\` に deploy。`CiTool --update-policy` で即時有効化されます (Windows Server 2022+ / Windows 11 22H2+ では再起動不要)。
- パッチ済み + 自己署名済みのドライバを `pnputil /add-driver /install` で install。

---

## Quick Start

### 前提条件

- Windows Server 2025 ホスト (build 26100)、または **検証目的のみ** で Windows 11 24H2 (build 26100) (Workstation OS 上では `Install` 系 phase が自動的にブロックされます。`-AllowWorkstationInstall` で override 可能ですが推奨されません。WS2025 移行前検証の workflow は [TESTING.md](./TESTING.md) を参照してください)。
- PowerShell 5.1 以上 (Desktop または Core)、64-bit、管理者権限で起動。
- インターネット接続 (AMD installer のダウンロードと、Windows SDK / WDK の `winget` 経由インストール用)。
- ワークスペースボリュームに約 5 GB の空き容量。

### スクリプトの取得

```powershell
# 方法 1: リポジトリを clone
git clone https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer.git
cd Deploy-AMD-Drivers-For-WindowsServer

# 方法 2: release ZIP を以下からダウンロード
# https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/releases
```

### ワンショット dry-run (システムには変更を加えません)

```powershell
# 管理者権限の PowerShell セッション内で実行
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot
```

`PrepareVerify` は `P00-P09` (download、extract、patch、catalog 生成、署名) を実行した後、`V01-V06` (artifact 検証、dry-run install plan、ハードウェア影響分析) を行います。**システム状態は一切変更されません** — 証明書は import されず、WDAC policy も deploy されず、ドライバも install されません。V05 / V06 の出力を読み、`Install` がどのような変更を加えるかを正確に把握できます。

### フルインストール

```powershell
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Install
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Install
```

Windows Server 2025 ホスト上で実行してください。両スクリプトとも冪等で、cleanup-safe です (`-Action Cleanup` でワークスペース削除、trust store からの証明書削除、deploy された WDAC policy の削除を行います)。

### 特定 phase のみの実行

```powershell
# 再ダウンロードせずパッチ済み INF と catalog だけ再生成
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action Prepare -OnlyPhases P05,P06,P08,P09

# 証明書信頼 phase だけ実行
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action Install -OnlyPhases I01

# 全 phase をリスト表示
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action ListPhases
```

---

## パイプラインアーキテクチャ (21 phase)

| Group | ID | 名称 | 内容 |
| --- | --- | --- | --- |
| Prep | P00 | Initialize | OS 検出、admin/TLS pre-flight、Workstation 上では WS2025 preview-mode banner 表示 |
| Prep | P01 | PrepareWorkspace | `C:\AMD-{Chipset,Graphics}-WS\` を作成 |
| Prep | P02 | AcquireTools | 7-Zip、Windows SDK (signtool)、Windows WDK (inf2cat) を `winget` でインストール、失敗時は直接 EXE fallback |
| Prep | P03 | FetchInstaller | ホストの AMD platform 検出、amd.com から最新 installer URL 解決、ダウンロード |
| Prep | P04 | ExtractInstaller | 7-Zip auto-detect、失敗時は installer をサイレント起動して `C:\AMD\` から harvest |
| Prep | P05 | AnalyzeInfs | 全 INF を inventory 化、source variant (W11x64 / WTx64 / WT6A_INF / WT64A) で分類、ホスト OS の対応 INF を選択 |
| Prep | P06 | PatchInfs | Server decoration を持たない INF について、各 Workstation `[Manufacturer]` エントリを `ProductType=3` で mirror。最初から Server-compatible な INF も patched フォルダにコピーして install パイプラインで処理されるようにする |
| Prep | P07 | CreateCertificate | RSA 4096 / SHA-384 自己署名コード署名証明書を生成 (有効期間 5 年)、PFX と CER で export |
| Prep | P08 | GenerateCatalogs | 各 patched INF フォルダで `inf2cat /os:Server2025_X64` を実行 |
| Prep | P09 | SignCatalogs | 全 catalog で `signtool sign /fd SHA384 /td SHA384 /tr <timestamp-url>` を実行 |
| Verify | V01 | VerifyArtifacts | 証明書 + パッチ済み INF + catalog の存在確認 |
| Verify | V02 | VerifyCertificate | PFX デコード、EKU・有効期間・鍵長の確認 |
| Verify | V03 | VerifyCatalogs | `signtool verify /pa` (I01 で証明書を信頼するまで失敗が想定) |
| Verify | V04 | VerifyInfs | パッチ済み INF を再 parse し、`ProductType=3` decoration の coverage を確認 |
| Verify | V05 | DryRunInstall | `Win32_PnPSignedDriver` を使って I01-I03 をシミュレート、各 install / skip / upgrade 判定を予測、install plan を出力 |
| Verify | V06 | HardwareImpactAnalysis | ホスト上の AMD ハードウェアを enumerate、AS-IS ドライバとパッチ済み TO-BE ドライバを比較、リスク (HIGH / MEDIUM / LOW) 分類 |
| Inst | I00 | PreInstallReview | V06 リスクサマリを表示、operator の確認を要求 |
| Inst | I01 | TrustCertificate | CER を `LocalMachine\Root` + `LocalMachine\TrustedPublisher` に import |
| Inst | I02 | AuthorizeDriverSigning | 当該証明書を kernel-mode 署名者として allowlist する WDAC supplemental policy を build + deploy (デフォルトパス)、`-UseTestSigning` 指定時のみ legacy `bcdedit /set testsigning on` 経路に fallback |
| Inst | I03 | InstallDrivers | 対象 INF 全てに対して `pnputil /add-driver <patched.inf> /install` を実行 |
| Inst | I04 | PostInstallVerification | AMD ハードウェアを再 enumerate、各対象デバイスに `[C] Self-signed` ドライバが bind されたか確認 |

---

## システム要件

- **CPU**: AMD Ryzen 4000 シリーズ以降 (スクリプトの `Get-AmdChipsetPlatform` heuristic は 4000 → AI 300、AI Max 300 を認識します。それより古い silicon でも動作はしますが未検証)。
- **OS**: Windows Server 2025 (build 26100) が production target。Windows 11 24H2 (build 26100) は *preview* host として対応 ([TESTING.md](./TESTING.md) 参照)。Windows Server 2016 / 2019 / 2022 は OS profile matrix で認識され、inf2cat も対応する `/os:` switch (`Server2016_X64`、`ServerRS5_X64`、`ServerFE_X64`) を選択しますが、これらバージョンでの production 利用は本 README の対象外です。
- **PowerShell**: 5.1 (Windows PowerShell Desktop) または 7.x (PowerShell Core)。スクリプトの `Show-PowerShellEnvironment` phase が認識する互換性 matrix を表示します。
- **ディスク**: ワークスペースボリュームに約 5 GB。
- **ネットワーク**: `*.amd.com`、`download.microsoft.com`、`go.microsoft.com`、`aka.ms` (winget)、`timestamp.digicert.com` (署名タイムスタンプ) への outbound HTTPS。
- **権限**: ローカル管理者。ドメイン権限不要。

---

## 自己署名証明書: 有効期限・更新・失効

P07 で生成される証明書は本パイプラインで install する全ドライバの **trust anchor** です。専用セクションで詳しく説明します。

### 証明書のプロパティ

- **Subject**: `CN=AMD Chipset Driver Self-Sign (WS2025 Lab, At Own Risk)` (chipset) または `CN=AMD Graphics Driver Self-Sign (WS2025 Lab, At Own Risk)` (graphics)。
- **鍵**: RSA 4096-bit、SHA-384 署名アルゴリズム。
- **EKU**: Code Signing (`1.3.6.1.5.5.7.3.3`)。
- **有効期間**: **P07 実行日から 5 年**。スクリプトでハードコードされています。
- **保管場所**: PFX を `C:\AMD-{Chipset,Graphics}-WS\cert\AMD-Driver-CodeSign.pfx` に保存。デフォルトでは PFX に**パスワードが設定されていません** (lab ツールという位置付けのため。本格的なパスワードが必要であれば param block の `[string]$PfxPassword = ''` を変更してください)。
- **trust anchor の対象**: `patched\` 配下の全 `.cat` ファイル、WDAC supplemental policy、(I01 経由で) `LocalMachine\Root` + `LocalMachine\TrustedPublisher`。

### 5 年経過後の挙動

証明書が失効すると:

- `.cat` ファイルに埋め込まれた catalog 署名は **失効前にインストールされたファイルに対しては有効なまま**です。これは Windows が署名タイムスタンプ (証明書が有効だった時点で署名されたことの証明) をチェックするためで、boot 時点での証明書の有効性ではありません。WHQL 署名されたドライバが AMD / Microsoft の署名証明書 rotate 後も動作し続けるのと同じ仕組みです。
- ただし、**失効した証明書で新しいパッチ済みドライバを `pnputil /add-driver` で追加することは失敗**します。
- **本スクリプトを再実行することがリカバリパス**です。新しい証明書 (異なる thumbprint、同じ subject) を生成し、catalog を再署名し、新証明書を import します。既にインストール済みのドライバはそのまま動作し続けます。

### 更新手順 (5 年ごと、もしくは漏洩が疑われる場合は即座)

```powershell
# 1. 証明書を rotate して再署名
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Prepare -OnlyPhases P07,P08,P09
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Prepare -OnlyPhases P07,P08,P09

# 2. 新証明書を信頼 (古い証明書は明示的に削除するまで信頼されたまま)
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Install -OnlyPhases I01,I02
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Install -OnlyPhases I01,I02

# 3. 再署名されたドライバを driver store に追加 (既存デバイスを新署名にバインド)
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Install -OnlyPhases I03
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Install -OnlyPhases I03

# 4. 必要に応じて旧証明書を削除
$old = '前回の-OLD-THUMBPRINT'
Get-ChildItem 'Cert:\LocalMachine\Root', 'Cert:\LocalMachine\TrustedPublisher' |
  Where-Object Thumbprint -EQ $old | Remove-Item
```

### 証明書の失効

PFX が漏洩した疑いがある場合、即座に:

```powershell
# 1. Cleanup — trust store から証明書削除、WDAC policy 削除、ドライバ削除
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Cleanup
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Cleanup

# 2. 再起動して WDAC policy unload を確実にする (スクリプトは CiTool --refresh を試みますが、
#    再起動することで kernel に署名権限の残存がないことを保証)
Restart-Computer
```

再起動後、フルパイプラインを再実行して新証明書を生成してください。

### なぜ 5 年? なぜ自己署名?

- **5 年** は Microsoft 自身の kernel-mode 署名証明書の有効期間上限と一致します (実際には 1〜3 年で rotate されますが、最大 5 年で発行)。月次で気にする必要がない程度には長く、漏洩時の影響範囲が無制限にならない程度には短い、という balance。
- **自己署名** にしている理由は、コンシューマー向けドライバを patch する個人の趣味活動に対してコード署名証明書を発行してくれる public CA は存在しないためです。Sectigo / DigiCert 等の EV Code Signing 証明書には法人確認 (年 $300〜600) が必要で、AMD の EULA に違反する可能性のある活動には発行されません。

これは *意図的に* lab ツールです。**本番環境で大規模に deploy する場合は、(a) AMD と直接交渉して Server 対応ドライバを得る、または (b) 適切に管理されたコード署名 CA を使う、のいずれかにすべきです。本自己署名モデルを使うべきではありません。**

---

## 免責事項・自己責任の確認

本スクリプトを実行することは、以下を理解し受諾することを意味します:

1. **無保証**。本スクリプトは MIT License の下で "as is" で提供されます。お使いのハードウェアでの動作、インストール環境への損傷の不在、将来の Windows update での継続サポート、いずれも保証されません。`LICENSE` を参照してください。

2. **発行元はあなた自身**。AMD の INF を patch して自己生成証明書で再署名することは、Windows から見て *AMD でも Microsoft でもなく、あなた自身* がそのドライバの暗号学的発行元になることを意味します。パッチ済みドライバが BSOD・システム不安定・データ損失を引き起こした場合、そのバグはあなたの自己署名証明書に attribute されます。AMD には attribute されません。

3. **AMD の End User License Agreement** はチップセット / グラフィックス installer の再配布を特定の条件下で許可しています。INF を編集して再署名する行為は grey area で、お使いの specific package の AMD EULA を読んだ上でご自身の判断を形成してください。**本リポジトリは、あなたの利用が AMD の terms 下で許可されるかについて何ら立場を取りません。**

4. **Microsoft の Windows Hardware Lab Kit (HLK) 認証は無効化されます**。本パイプラインで置換する全ドライバについて。WHQL 署名ドライバは Microsoft が HLK 通過を attest していますが、自己署名ドライバはそうではありません。当該ハードウェアについて Microsoft Premier Support に依存している場合、自己署名ドライバが原因の問題はサポート契約の対象外になる可能性があります。

5. **BitLocker / TPM / Secure Boot との相互作用**。チップセットスクリプトの PSP ドライバ置換 (`amdpsp.inf`) は Platform Security Processor firmware と相互作用します。BitLocker が有効な system では、PSP ドライバ更新の失敗が次回起動時の BitLocker recovery プロンプト発生を引き起こす可能性があります。**chipset スクリプトで `-Action Install` を実行する前に、必ず BitLocker recovery key を控えてください。**

6. **Anti-cheat ソフトウェア** (Easy Anti-Cheat、BattlEye、Vanguard 等) は自己署名 kernel-mode ドライバを flag する可能性があります。本パイプラインは競技性のあるゲームタイトルでのゲーミングワークロードを想定しておらず、当該用途で利用するとアカウント BAN の可能性があります。

7. **5 年の証明書有効期限は実際に到来します**。production deploy をする場合は 4.5 年目に renewal タスクをカレンダーに登録するか、5 年目以降ドライバインストールが停止することを受け入れてください。

8. **本リポジトリで商用サポートは提供されません**。GitHub Issues (<https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/issues>) はバグ報告と説明要求の best-effort 対応です。Pull request は歓迎しますが、レビューのタイミングは保証されません。

---

## トラブルシューティング

### "OS detected: Windows Server 2025 (build 26100) [WS2025] but ProductType: 1"

Windows 11 24H2 上で実行しています (Win11 24H2 と Windows Server 2025 は NT build 26100 を共有)。スクリプトは意図的に Win11 24H2 を WS2025 profile にマップします (kernel ABI が同一のため)。Workstation OS では `Install` 系 phase がデフォルトでブロックされます。`-Action PrepareVerify` のみを使うか、本当に Win11 上で install したい場合のみ `-AllowWorkstationInstall` を指定してください (警告を先に読んでください)。事前検証 workflow は [TESTING.md](./TESTING.md) を参照してください。

### "P02 で WDK インストールに 2-3 分かかる"

Windows WDK のダウンロードサイズが約 2.5 GB です。マシンごとに一度だけのインストールで、以降の実行ではインストール済みの `inf2cat.exe` を再利用するため、P02 は 1 秒未満で完了します。

### "P03 が 'no AMD installer URL resolved' で失敗する"

AMD は support page を定期的に再構成します。スクリプトは 3〜6 個の候補 URL をプローブし、全てが 0 hits を返す場合は parser が壊れています。回避策:

- `-InstallerUrl https://drivers.amd.com/drivers/...` を渡して URL discovery を skip し、特定バージョンを直接ダウンロード。
- P03 出力の `Probe results:` ブロックを開き、各 URL を手動で訪問して AMD のサイト変更を確認。
- Issue を起票: <https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/issues>

### "V06 で MS-GENERIC ドライバの AMD ハードウェアがパッチ済み INF でカバーされない"

CPU core (`cpu.inf`)、PCI Express ルートポート (`pci.inf`)、ホスト CPU ブリッジ (`machine.inf`)、USB xHCI (`usbxhci.inf`)、HD Audio コントローラー (`hdaudbus.inf`) は **全て Microsoft 汎用ドライバのまま残ることが想定済み**です。これらに対して AMD はベンダードライバを提供していません (core OS subsystem が enumerate するため)。V06 セクション 1 の "ALERT" メッセージは情報提供であってエラーではありません。

### "I02 で WDAC policy が deploy されたが新ドライバが load されない"

`eventvwr` → `アプリケーションとサービスログ` → `Microsoft` → `Windows` → `CodeIntegrity` → `Operational` で event 3076 / 3077 / 3091 を確認してください。block された署名の Issuer / Subject / Thumbprint がご自身の自己署名証明書と一致するはずです。一致しない場合、WDAC policy が正しく deploy されていません。`CiTool -lp` で active policy を listing して確認してください。

### "AMD ドライバが install されたのに Device Manager にはまだ MS 汎用が表示される"

`pnputil /scan-devices` で再 enumeration を強制してください。それでも MS にバインドされたままであれば、パッチ済み INF の HWID がデバイスの PNP ID と完全一致していない可能性があります。V06 セクション 2 ("WILL be replaced" / "have no patched INF") を確認してください。デバイスが後者のカテゴリに入る場合、パッチ済みドライバが当該 HWID を claim していないということで、これは一部のデバイス (USB hub、汎用 xHCI controller 等) では想定通りの挙動です。

---

## 開発ツール

`tools/` ディレクトリにはコントリビューター向けの開発ユーティリティを配置しています。

### `tools/psa.py` — PowerShell 静的解析ツール

PowerShell の通常 parser では検出しにくい誤りをチェックする、シングルファイルの Python 3 静的解析ツールです。`.ps1` ファイルに変更を加えた際、commit 前に実行してください:

```bash
python3 tools/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 tools/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
```

実施チェック:

| Code | 重要度 | 内容 |
| --- | --- | --- |
| C1 | error | 中括弧 `{` `}` のバランス |
| C2 | error | 丸括弧 `(` `)` のバランス |
| C3 | error | 角括弧 `[` `]` のバランス |
| C4 | warning | 未定義変数の参照 (heuristic) |
| C5 | warning | 自動変数の shadowing (`$args`、`$_`、`$matches` 等) |
| C6 | warning | `Start-Process -ArgumentList` (空白を含むパスでは `ProcessStartInfo` 推奨) |
| C7 | warning | bare `$variable` に対する `-match` ($null だと true を返す問題) |
| C8 | info | TODO / FIXME マーカー |
| C9 | warning | 空行直前の trailing backtick (継続行) |
| C10 | warning | 空文字列に対する `-match` (常に true) |

終了コード: `0` = clean、`1` = warnings のみ、`2` = errors。CI で利用可能:

```yaml
# .github/workflows/lint.yml の例
- name: Static-analyze PowerShell scripts
  run: |
    python3 tools/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
    python3 tools/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
```

詳細とルールごとの根拠は [`tools/README.md`](./tools/README.md) を参照してください。

---

## 参考リンク

### Microsoft Learn (日本語版)

- [INF ファイルのセクションとディレクティブ](https://learn.microsoft.com/ja-jp/windows-hardware/drivers/install/inf-file-sections-and-directives)
- [INF Manufacturer セクション (TargetOSVersion / ProductType)](https://learn.microsoft.com/ja-jp/windows-hardware/drivers/install/inf-manufacturer-section)
- [Server SKU と Client SKU でのドライバインストールの違い](https://learn.microsoft.com/ja-jp/windows-hardware/drivers/install/sku-specific-files-and-installation)
- [Inf2Cat コマンドリファレンス](https://learn.microsoft.com/ja-jp/windows-hardware/drivers/devtest/inf2cat)
- [SignTool コマンドリファレンス](https://learn.microsoft.com/ja-jp/windows/win32/seccrypto/signtool)
- [PnPUtil 概要](https://learn.microsoft.com/ja-jp/windows-hardware/drivers/devtest/pnputil)
- [PnPUtil コマンド構文](https://learn.microsoft.com/ja-jp/windows-hardware/drivers/devtest/pnputil-command-syntax)
- [Windows Defender Application Control (WDAC) の概要](https://learn.microsoft.com/ja-jp/windows/security/application-security/application-control/app-control-for-business/wdac)
- [スクリプト (CiTool) で WDAC policy を deploy する](https://learn.microsoft.com/ja-jp/windows/security/application-security/application-control/app-control-for-business/deployment/deploy-wdac-policies-with-script)
- [Windows Driver Kit (WDK) のインストール](https://learn.microsoft.com/ja-jp/windows-hardware/drivers/download-the-wdk)
- [Windows Software Development Kit (SDK) のダウンロード](https://learn.microsoft.com/ja-jp/windows/win32/devnotes/windows-sdk)
- [Windows のドライバ署名要件](https://learn.microsoft.com/ja-jp/windows-hardware/drivers/install/kernel-mode-code-signing-policy--windows-vista-and-later-)

### AMD

- [AMD チップセットドライバ (ダウンロード)](https://www.amd.com/ja/support/category/chipsets)
- [AMD Adrenalin Edition (ダウンロード)](https://www.amd.com/ja/support/category/graphics)

### 本リポジトリ

- [TESTING.md](./TESTING.md) — クラウド (AWS) でのテスト手順 (EPYC 複数世代対応) および物理ハードウェアでの検証結果。
- [CONTRIBUTING.md](./CONTRIBUTING.md) — コントリビューションガイド。
- [README.md](./README.md) — 英語版本ドキュメント。
- [tools/README.md](./tools/README.md) — 開発ツールのドキュメント。

---

## ライセンス

[MIT License](./LICENSE)。Copyright (c) 2026 contributors。

MIT ライセンスは **本リポジトリの PowerShell スクリプトおよび付属ドキュメントのみに適用**されます。スクリプトは実行時に AMD installer EXE をダウンロードしますが、AMD のバイナリ・INF・catalog を再配布はしていません。これらのファイルには AMD の再配布規約が独立に適用されます。

---

## コントリビューション

Issue テンプレート、PR ガイドライン、regression test 実行手順 (`tools/psa.py` の使い方含む) は [CONTRIBUTING.md](./CONTRIBUTING.md) を参照してください。

Issue・Pull Request は以下で受け付けています:
<https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer>
