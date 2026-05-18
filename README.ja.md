# Deploy-Drivers-For-WindowsServer

AMD のコンシューマー向け Ryzen チップセットドライバ・Radeon グラフィックスドライバ・Ryzen AI NPU (XDNA) ドライバ、 **および Microsoft inbox Bluetooth PAN ドライバ (`bthpan.inf` / `bthpan.sys`)** を **Windows Server 2016 / 2019 / 2022 / 2025** に install できるように、 INF の `ProductType=3` decoration をパッチし、 自己生成証明書で catalog を再署名する PowerShell パイプラインです。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) [![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://learn.microsoft.com/ja-jp/powershell/) [![Target: Windows Server 2025](https://img.shields.io/badge/Target-Windows%20Server%202025-success.svg)](https://learn.microsoft.com/ja-jp/windows-server/get-started/windows-server-2025)

> **実行する前に必ず最後まで読んでください。** これは *最後の手段としての lab 専用ツール* です。AMD はコンシューマー向け Ryzen プラットフォーム (例: Lenovo ThinkCentre Tiny / ThinkPad / mini-PC に搭載される Cezanne / Renoir / Phoenix APU 等) において Windows Server 2025 を**公式にサポートしていません**。公式ドライバが利用可能な場合は **必ずそちらを優先**してください。本リポジトリは、公式 Server 向けドライバが提供されない狭い局面で、自己署名ドライバチェーンの運用リスクを自分で受け入れた上で利用するためのものです。

> **🆘 NPU スクリプト (`Deploy-AMDNpuDriverOnWindowsServer.ps1`) に関する追加警告:** NPU スクリプトは、チップセット・グラフィックススクリプトと比べて **明らかに危険性が高く、成熟度も大きく劣ります**。**物理 NPU ハードウェアでの検証は本ドキュメント執筆時点で未実施**であり、AMD アカウント自動ダウンロードフローは AMD のフォーム構造変更で**予告なく動作しなくなる**可能性があります。さらに NPU を実際に利用するために必要な Ryzen AI Software (user-mode stack) は **AMD 公式に Windows Server 2025 でサポートされていません**。NPU スクリプトは **実験的・研究用途**のみと位置付けてください。本番運用ツールではありません。詳細は[4 スクリプトのリスク分類](#4-スクリプトのリスク分類)を参照してください。

🇬🇧 **English README is at [README.md](./README.md).**

---

## 目次

- [このリポジトリの存在理由](#このリポジトリの存在理由)
- [⚠️ 免責事項（実行前にお読みください）](#%EF%B8%8F-免責事項実行前にお読みください)
- [リポジトリの内容物](#リポジトリの内容物)
- [新着情報](#新着情報)
- [4 スクリプトのリスク分類](#4-スクリプトのリスク分類)
- [対応範囲](#対応範囲)
- [リポジトリ構成](#リポジトリ構成)
- [Quick Start](#quick-start)
- [BthPan スクリプト固有の Quick Start](#bthpan-スクリプト固有の-quick-start)
- [NPU スクリプト固有の Quick Start](#npu-スクリプト固有の-quick-start)
- [パイプラインアーキテクチャ (21 phase)](#パイプラインアーキテクチャ-21-phase)
- [パラメータ一覧（スクリプト別）](#パラメータ一覧スクリプト別)
- [出力ファイル](#出力ファイル)
- [UEFI Secure Boot ベースライン](#uefi-secure-boot-ベースライン)
- [コンソール出力フォーマット](#コンソール出力フォーマット)
- [システム要件](#システム要件)
- [自己署名証明書: 有効期限・更新・失効](#自己署名証明書-有効期限更新失効)
- [免責事項・自己責任の確認](#免責事項自己責任の確認)
- [トラブルシューティング](#トラブルシューティング)
- [開発ツール](#開発ツール)
- [開発者向け仕様書](#開発者向け仕様書)
- [ファイルエンコーディング](#ファイルエンコーディング)
- [参考リンク](#参考リンク)
- [ライセンス](#ライセンス)
- [コントリビューション](#コントリビューション)

関連ドキュメント:

- [`CHANGELOG.md`](./CHANGELOG.md) — 時系列のリリースノート（英語のみ、 r1 以降の全リビジョン）
- [`SPEC.md`](./SPEC.md) — 開発者向け仕様書（アーキテクチャ、規約、設計判断の根拠。 **英語のみ**）
- [`TESTING.md`](./TESTING.md) — 物理ハードウェアでの検証結果と回帰テストチェックリスト（**英語のみ**）
- [`CONTRIBUTING.md`](./CONTRIBUTING.md) — Issue の起票・PR の作成・回帰テストの実行方法（**英語のみ**）
- [`README.md`](./README.md) — 本ドキュメントの英語マスター版

---

## このリポジトリの存在理由

コンシューマー向け AMD プラットフォーム (Ryzen 4000 / 5000 / 6000 / 7000 / 8000 mobile / desktop APU、discrete Vega / Polaris / RDNA Radeon GPU、および Ryzen AI 300 / AI Max 300 シリーズの NPU) に Windows Server 2025 をインストールすると、複数の AMD デバイスが **AMD 純正ドライバではなく Microsoft の汎用 in-box ドライバ** (`machine.inf`、`pci.inf`、`hdaudbus.inf`、`display.inf` 等) にバインドされてしまうか、(NPU の場合) 全くバインドされない状態になります。原因は 2 つあります:

1. **AMD の INF ファイルが `[Manufacturer]` decoration に `ProductType=1` (Workstation) 制限を含んでいる**ため、Windows Setup がこれを尊重して Server SKU (`ProductType=3`) ではドライバのバインドを拒否します。
2. **AMD の catalog (.cat) 署名がオリジナルの INF を attest している**ため、INF を編集して Server decoration を追加した時点で署名が無効になり、ドライバが kernel-mode 署名チェックに失敗します。Windows Server 2025 は Secure Boot と HVCI を経由してこれを厳格に enforce します。

本パイプラインは以下の手順で両方の問題を解決します:

- AMD の Workstation `[Manufacturer]` decoration を解析し、**各エントリを `ProductType=3` (Server) で mirror** します (元の Workstation エントリは保持されるため、パッチ後の INF は両 OS 互換になります)。
- `inf2cat /os:Server2025_X64` で新しい `.cat` catalog を生成します。
- **自己生成のコード署名証明書で catalog を署名**し、その証明書を `LocalMachine\Root` + `LocalMachine\TrustedPublisher` に import、さらに **WDAC supplemental Code Integrity policy** で kernel-mode 署名者として認可します (Secure Boot は **ON のまま** — Windows Server 2022+ / Windows 11 22H2+ では `bcdedit /set testsigning on` 不要です)。

---

## ⚠️ 免責事項（実行前にお読みください）

**自己責任でご利用ください。** 本スクリプトは "AS IS" で提供され、 明示・黙示を問わず、 いかなる種類の保証もありません。 作者およびコントリビュータは、 本スクリプトの使用・改変・配布から直接的または間接的に生じる、 損害、 データ消失、 BSOD、 BitLocker recovery prompt、 アカウント停止、 ハードウェア不安定化、 その他いかなる問題に対しても、 一切責任を負いません。

本スクリプトを実行することにより、 以下を了承したものとみなします:

* AMD End User License Agreement、 Microsoft Windows Software License Terms、 および適用される法令・規制に対する遵守は、 利用者の単独責任である
* AMD の INF をパッチし自己生成証明書で再署名する行為により、 Windows から見た当該ドライバの暗号学的 publisher は AMD でも Microsoft でもなく、 **利用者自身**となる
* 本パイプラインが置換するドライバは **WHQL 認証が無効化される**こと。 対象ハードウェアで Microsoft Premier Support を頼っている場合、 自己署名ドライバ起因の問題はサポート契約の対象外となる可能性がある
* Chipset スクリプトで `-Action Install` を実行する前に **BitLocker 回復キーを記録**する (PSP driver の置換は Platform Security Processor firmware と相互作用し、 次回起動時に回復プロンプトが表示される可能性がある)
* 実行環境を問わず、 スクリプトのソースコードを確認し動作を理解した上で実行する
* **NPU スクリプトに関しては特に**、 実験的・研究用途のツールであることを了承する — 詳細は[4 スクリプトのリスク分類](#4-スクリプトのリスク分類)を参照

本ツールは慎重に運用してください。 **AMD 公式の Server サポート対象ドライバが存在する場合は、 そちらを優先してください**。 本リポジトリは、 公式 Server クラスドライバが提供されておらず、 自己署名ドライバチェーンを自身のハードウェアで運用するリスクを受容できる、 という狭いケースを対象としています。

BitLocker、 アンチチートソフト、 サポート影響、 証明書有効期限などを含む、 完全な自己責任の確認事項は、 後述の[免責事項・自己責任の確認](#免責事項自己責任の確認)を参照してください。

---

## リポジトリの内容物

| ファイル | 用途 | 成熟度 |
| --- | --- | --- |
| `Deploy-AMDChipsetDriverOnWindowsServer.ps1` | チップセットドライバパイプライン (GPIO、 SMBus、 PSP、 MicroPEP、 PMF 等)。 ソース: AMD Chipset Software EXE 約 75 MB、 INF 約 67 個。 | **安定版** — M75q Tiny Gen 2 (WS2025) と X13 Gen 1 AMD (Win11 LTSC 2024) で検証済み。 |
| `Deploy-AMDGraphicsDriverOnWindowsServer.ps1` | グラフィックスドライバパイプライン (Display、 HD Audio、 Audio CoProcessor、 ACP、 USB-C UCSI 等)。 ソース: AMD Adrenalin Edition EXE 約 600 MB、 INF 約 19 個 (Vega-Polaris Legacy ブランチ) または約 67 個 (Phoenix 以降の Main Adrenalin ブランチ)。 | **安定版** — チップセットスクリプトと同一の検証ホストで検証済み。 |
| **`Deploy-AMDNpuDriverOnWindowsServer.ps1`** | **NPU (Ryzen AI XDNA) ドライバパイプライン (PHX/HPT/STX/KRK)。** ソース: AMD Ryzen AI Software ZIP 約 250 MB、 EULA gate あり (公開直接 URL なし)。 kernel-mode driver のみ install — Ryzen AI Software user-mode stack は対象外。 | **🆘 実験的・研究用途 — 本番運用不可。** 物理 NPU ハードウェアでの検証は未実施。 AMD アカウント自動ダウンロードは best-effort で AMD 側のフォーム変更で破綻する可能性。 Ryzen AI Software は Windows Server 2025 公式非サポート。 |
| `Deploy-MSBthPanInboxOnWindowsServer.ps1` | **Microsoft inbox Bluetooth PAN ドライバ (`bthpan.inf` / `bthpan.sys`) 有効化パイプライン。** ソース: ホスト自身の `C:\Windows\System32\DriverStore\FileRepository\bthpan.inf_amd64_*` ディレクトリ — **リモートダウンロード不要**。 単一 INF・ 単一 HWID (`BTH\MS_BTHPAN`)。 Phantom OK (bth.inf による代理マッチ) と真の解消 (Class=Net、 Service=BthPan) を Windows Server 上で明示的に区別します。 | **新規** (r1) — 初版リリース。 Phase / Secure Boot / WDAC フレームワークは AMD スクリプトと同一を verbatim 継承。 INF パッチ対象が 1 ファイル・ 1 HWID と非常に小さい。 ThinkPad + Intel AX210 + WS2025 build 26100.32860 が第一の物理検証ターゲット予定。 |
| `README.md` | 英語版ドキュメント (マスター)。 |  |
| `README.ja.md` | 本ドキュメント (日本語版、 `README.md` と同期翻訳)。 |  |
| `SPEC.md` | 開発者向け仕様書 (スクリプト別詳細、 INF パース戦略、 WDAC policy 構造)。 **英語のみ。** |  |
| `TESTING.md` | 物理ハードウェアでの検証結果。 NPU スクリプトの極めて限定的な検証状況も記載。 **英語のみ。** |  |
| `CHANGELOG.md` | 時系列のリリースノート (r1 以降の全リビジョン)。 **英語のみ。** |  |
| `CONTRIBUTING.md` | Issue・PR ガイドラインと regression test 手順。 **英語のみ。** |  |
| `LICENSE` | MIT License。 |  |

4 つの PowerShell スクリプトは同じ 21 phase アーキテクチャ、 同じ自己署名モデル、 同じ WDAC 認可パスを共有します。 それぞれ別ワークスペース (`C:\Temp\Workspace_AMD-Chipset`、 `C:\Temp\Workspace_AMD-Graphics`、 `C:\Temp\Workspace_AMD-NPU`、 `C:\Temp\Workspace_Microsoft-BthPan`)、 別の自己署名証明書、 別の WDAC supplemental policy GUID を使用するため、 相互に干渉しません。 Chipset r59 / Graphics r27 / NPU r9 / BthPan r9 から、 4 つのワークスペースはすべて `C:\Temp\Workspace_*` 配下に再配置されています (クラスタ管理および一括削除を容易化する目的)。 `C:\Temp` がない場合はスクリプトが自動作成します。

---

## 新着情報

リリース毎の変更履歴は [CHANGELOG.md](./CHANGELOG.md) (英語のみ) を参照してください。
r1 以降のすべてのリビジョンが日付順・スクリプト別にまとめられています。
個別の修正の **設計判断の根拠** については [SPEC.md Part D](./SPEC.md#part-d--known-pitfalls--lessons-learned) (英語のみ) を参照ください。

現時点の最新リリースは **Chipset r60 / Graphics r28 / NPU r10 / BthPan r10**
(2026-05-18) で、 4 スクリプトを psa.py ベースラインに揃えるクロススクリプト整合パスです。 前回リリース (r59 / r27 / r9 / r9、 2026-05-17) で導入された Debug Trace Facility (SECTION 1b) が現時点のヘッドライン機能となります。

同日付の [Unreleased] 設定更新により、 `.psa.config.json` は新規追加された opt-in リビジョン規律ルール `PSAP0003` および `PSAP0004` (`psa.py` 3.3.0 で追加) も opt-in しています。 4 スクリプトはこの厳格化された設定下でも 0 errors / 0 warnings / 0 info を維持します。

## 4 スクリプトのリスク分類

> NPU スクリプトは姉妹スクリプトと比較して明らかにリスクが高いため、 実行前にこのセクションを必ず理解する必要があります。 BthPan スクリプトは 4 スクリプト中で最もリスクが低い: ドライバソースはホスト自身の DriverStore (リモートダウンロードなし)、 INF surface はちょうど 1 ファイル・ 1 HWID、 ドライババイナリ自体は Microsoft が署名済みで、 再署名するのは catalog のみだからです。

| 項目 | チップセットスクリプト (r59) | グラフィックススクリプト (r27) | **NPU スクリプト (r9)** | **BthPan スクリプト (r9)** |
| --- | --- | --- | --- | --- |
| **成熟度** | 安定版、 複数の検証サイクル完了 | 安定版、 複数の検証サイクル完了 | **🆘 実験的 — 初版、 物理 NPU ハードウェアでの検証は未実施** | **新規 (r1)** — 初版リリース。 Phase / Secure Boot / WDAC フレームワークは検証済 verbatim 継承。 単一 INF surface が小さく、 1 セッションで物理検証が完結可能。 |
| **配布形態** | 公開 EXE 直接ダウンロード | 公開 EXE 直接ダウンロード | **EULA gate ZIP、 AMD アカウント必須** | **ダウンロード不要** — `bthpan.inf` はホスト自身の `C:\Windows\System32\DriverStore\FileRepository\bthpan.inf_amd64_*` に既に staging 済み。 |
| **公開ダウンロード URL** | あり (直接) | あり (直接) | **なし — リリースごとに AMD アカウントログインと EULA 受諾が必須** | **該当なし — ドライバはホスト上に存在。** |
| **AMD アカウント自動ダウンロード** | 該当なし | 該当なし | **best-effort、 AMD のフォーム HTML 構造に依存し予告なく破綻する可能性** | **該当なし。** |
| **OS サポートスタンス** | AMD 非公式サポートだがドライバは動作 | AMD 非公式サポートだがドライバは動作 | **kernel driver は Server 2025 で load するが、 AMD ドキュメント上 Ryzen AI Software (user-mode stack) は Server 2025 で動作しない** | **Microsoft inbox driver — Workstation SKU では Microsoft 公式にフルサポート。** Server SKU でフィルタアウトされるのは `NTamd64...1` ProductType decoration が原因のみ。 本スクリプトは Microsoft のバイナリには一切手を加えず、 不足している ProductType=3 decoration のみ供給します。 |
| **ハードウェア入手性** | 一般的 (任意の AMD APU マシン) | 一般的 (任意の AMD GPU/APU マシン) | **限定的 (Ryzen AI 300 / Ryzen AI Max 300 / Ryzen 7040/8040 シリーズのみ)** | 一般的 — Bluetooth host controller が bind 済みで `BTH\MS_BTHPAN` が enumeration されるすべてのマシン。 ほとんどの ThinkPad・ mini-PC・ NUC が該当。 |
| **リポジトリ内のテストフィクスチャ** | M75q Tiny Gen 2、 X13 Gen 1 AMD | M75q Tiny Gen 2、 X13 Gen 1 AMD | **なし — メンテナーの lab に物理 NPU マシンが本ドキュメント執筆時点で存在しない** | ThinkPad + Intel AX210 + WS2025 build 26100.32860 (初回物理検証予定)。 |
| **本スクリプト固有の失敗モード** | PSP / TPM driver 置換による BitLocker 回復プロンプト | 署名済 cat install 時の display reset | NPU device が enumeration されない / Ryzen AI Software が動作しない | **Phantom OK トラップ** — bth.inf が代理マッチして Status=OK を報告するが `bthpan.sys` は **load されていない**。 V06 / I04 は Phantom OK (DriverInfPath=bth.inf、 Class=Bluetooth) と真の解消 (DriverInfPath=oem*.inf、 Class=Net、 Service=BthPan) を明示的に区別。 |
| **推奨用途** | Lab + 慎重な production | Lab + 慎重な production | **Lab / 研究用途のみ。 production ホストには deploy しないこと。** | **Lab + 慎重な production。** ベンダードライバを置換するわけではなく、 Microsoft が publish した inbox driver を Microsoft が同梱対象外と判断した SKU クラスで有効化するだけのため、 リスクは低い。 |
| **推奨 Action モード** | `PrepareVerify` でレビュー後に `Install` | `PrepareVerify` でレビュー後に `Install` | **物理 NPU ハードウェアの存在を確認し、 Ryzen AI Software が Server 2025 で動作しないことを受け入れるまでは `PrepareVerify` のみ** | まず `PrepareVerify` で Phantom-OK と真の解消状態を確認し、 その後 `Install`。 |

**NPU スクリプトを使う際の実践的な経験則**:

1. **ロールバックできないホストでは `-Action Install` を実行しないでください。** Cleanup パスは実装されていますが、driver store からの削除は best-effort で、`pnputil /delete-driver oemNN.inf /force` による手動 cleanup が必要となるケースがあります。
2. **Ryzen AI Software user-mode stack** (Python conda env + ONNX Runtime VitisAI EP + OGA) は **AMD 公式に Windows 11 only** です。Server 2025 で kernel driver が load しても、サポートされたスタックで推論ワークロードを実行することはできません。Server 2025 上で AI ワークロード機能性を期待しないでください。kernel driver は driver bring-up の実験以上のものではありません。
3. **物理 NPU 検証は未完了です。** 現時点での全ての検証は `psa.py` による静的解析と、AMD 公開の `quicktest.py` 検出ロジックを PowerShell に翻訳したコードのレビューに留まります。**実機での挙動は未確認**です。
4. **AMD のアカウント自動ダウンロードフローは予告なく破綻する可能性があります。** AMD は `account.amd.com` のフォーム構造、CSRF token 名、EULA 受諾エンドポイントを定期的に更新します。スクリプトの Tier 2 認証は best-effort です。**再現性が必要な実行は常に Tier 4 (`-OfflineZip`) を優先**してください。

上記を読んだ上でなお NPU スクリプトを実行したい場合: [NPU スクリプト固有の Quick Start](#npu-スクリプト固有の-quick-start) を参照してください。

---

## 対応範囲

### 対応ハードウェア

- **AMD Ryzen Mobile**: Ryzen 4000 (Renoir)、5000 (Cezanne / Lucienne / Barcelo / Barcelo-R)、6000 (Rembrandt)、7000 (Phoenix / Hawk Point)、8000 (Hawk Point refresh)、AI 300 (Strix Point / Krackan Point)、AI Max 300 (Strix Halo)。
- **AMD Ryzen Desktop APU**: Ryzen 5000G / 5000GE (Cezanne)、7000G / 8000G (Phoenix)。
- **AMD Radeon Graphics**: Vega 6 / 7 / 8 / 11 (内蔵、Renoir → Cezanne → Barcelo)、RDNA 3 (Phoenix 780M / 760M)、RDNA 3.5 (Strix Point)、discrete RX 5000 / 6000 / 7000 / 9000 シリーズ。
- **AMD AM4 / AM5 chipset**: X470、X570、X670/X670E、X870/X870E、B450、B550、B650、B850。
- **AMD ACPI device**: GPIO controller (`AMDI0030`、`AMDF030`)、I2C (`AMD0010`)、Micro PEP (`AMD0004`)、HSMP (`AMDI0097`)、PMF (`AMDI0100` / `AMDI0102`)、SFH (`AMDI0080` / `AMDI0011`)、UART (`AMD0020`)、Wireless Button (`AMDI0051`)、Pluton stub (`MSFT0200` / `MSFT0201`)。
- **AMD NPU / XDNA Compute Accelerator** *(実験的、NPU スクリプトのみ)*:
  - **Phoenix / Hawk Point** (`PCI\VEN_1022&DEV_1502&REV_00`) — Ryzen 7040 / 8040 / 8040 PRO mobile シリーズ。ドライバ build `32.0.203.280` (RAI 1.5)。
  - **Strix Point / Strix Halo** (`PCI\VEN_1022&DEV_17F0&REV_00/10/11`) — Ryzen AI 300 / Ryzen AI Max 300 シリーズ。ドライバ build `32.0.203.314` (RAI 1.6.1) 以降。
  - **Krackan Point** (`PCI\VEN_1022&DEV_17F0&REV_20`) — Ryzen AI 200 シリーズ。ドライバ build `32.0.203.314` (RAI 1.6.1) 以降。
- **Microsoft inbox Bluetooth PAN** *(BthPan スクリプトのみ)*:
  - **HWID**: `BTH\MS_BTHPAN` — Microsoft サポート対象の Bluetooth host controller が bind した後、 そのすべての controller が公開する子デバイス。 ベンダー非依存 (Intel AX2xx、 Realtek RTL88xx、 MediaTek MT7xxx、 Broadcom BCM43xx 等すべて該当)。
  - **前提**: Bluetooth host controller のドライバが bind 済みで Device Manager 上 Status=OK を表示していること。 host controller 自体が Unknown device の場合は先にベンダードライバをインストールしてください。 本スクリプトは host controller には対応しません。
  - **本スクリプトが解消する症状**: Windows Server SKU 上で `BTH\MS_BTHPAN` が Unknown Device (code 28) として表示される、 または Status=OK でも `DriverInfPath=bth.inf` ・ `Class=Bluetooth` (Phantom OK; `bthpan.sys` は **load されておらず**、 `BthPan` service も起動していない) となっているケース。
  - **真の解消基準**: `DriverInfPath=oem*.inf`、 `Class=Net`、 `Service=BthPan`、 `C:\Windows\System32\drivers\bthpan.sys` が存在、 `BthPan` service が登録済、 Bluetooth PAN NetAdapter が `Get-NetAdapter` で visible になっていること。

### 対応**しない**ハードウェア

- **AMD EPYC server chip** (サーバー級 CPU。クラウドインスタンスや Hetzner AX dedicated 等で利用される): EPYC は別の chipset モデルを使用しており、Microsoft Update 経由で first-party Server 対応ドライバが提供されます。本パイプラインは *コンシューマー* Ryzen 向けで、EPYC は対象外です。
- **リアルタイム GPU compute stack** (ROCm、HIP SDK、Adrenalin パッケージに含まれる user-mode driver 以外の OpenCL): Server 対応については AMD の ROCm ドキュメントを参照してください。
- **Ryzen AI Software user-mode stack** (Python conda env、ONNX Runtime VitisAI Execution Provider、OnnxRuntime GenAI/OGA、Vitis AI Quantizer、Lemonade SDK 等): **NPU スクリプトの対象外。** NPU スクリプトは kernel-mode driver のみ install します。Ryzen AI Software は <https://account.amd.com/en/forms/downloads/xef.html?filename=ryzen-ai-lt-1.7.1.exe> から AMD インストーラを取得し、operator が別途インストールする必要があります。AMD ドキュメントによれば公式サポート OS は Windows 11 build >= 22621.3527 のみです。

---

## リポジトリ構成

`git clone` 直後のリポジトリ構成:

```
Deploy-Drivers-For-WindowsServer/
├── Deploy-AMDChipsetDriverOnWindowsServer.ps1     Chipset ドライバパイプライン (21 phase)
├── Deploy-AMDGraphicsDriverOnWindowsServer.ps1    Graphics ドライバパイプライン (21 phase)
├── Deploy-AMDNpuDriverOnWindowsServer.ps1         NPU (Ryzen AI XDNA) パイプライン (21 phase)
├── Deploy-MSBthPanInboxOnWindowsServer.ps1        Microsoft inbox bthpan パイプライン (21 phase)
├── README.md                                      本ドキュメント (英語版マスター)
├── README.ja.md                                   本ドキュメント (日本語版、 README.md と同期)
├── TESTING.md                                     物理ハードウェアでの検証結果 (英語のみ)
├── SPEC.md                                        開発者向け仕様書 (英語のみ)
├── CHANGELOG.md                                   時系列のリリースノート (英語のみ)
├── CONTRIBUTING.md                                Issue / PR ガイドライン (英語のみ)
├── SECURITY.md                                    脆弱性報告 (英語のみ)
├── CODE_OF_CONDUCT.md                             コミュニティ行動規範 (英語のみ)
├── LICENSE                                        MIT License
├── .psa.config.json                               psa.py の設定 (PSAP ルール opt-in)
├── .gitattributes                                 Git 改行コード正規化設定
└── .gitignore                                     標準 ignore 設定
```

### スクリプトが生成するもの

`-Action PrepareVerify` (もしくは `-Action All`) 実行後、 各スクリプトは workspace に以下を生成します:

```
C:\Temp\Workspace_AMD-Chipset\   (または C:\Temp\Workspace_AMD-Graphics\・C:\Temp\Workspace_AMD-NPU\・C:\Temp\Workspace_Microsoft-BthPan\)
├── download\              AMD installer EXE / NPU ドライバ ZIP
│                          (BthPan: 空 — ドライバソースは DriverStore のため未使用)
├── extracted\             EXE / ZIP / DriverStore から展開された元 INF とバイナリ
│                          (BthPan: extracted\bthpan\bthpan.inf / .sys / .cat)
├── patched\               ProductType=3 を mirror したパッチ済み INF
│                          + 生成された .cat ファイル + signtool 署名
│                          (BthPan: patched\bthpan\ — 単一 INF ディレクトリ)
├── cert\                  自己署名コード署名証明書 (PFX + CER) +
│                          WDAC supplemental policy XML/CIP
└── inf_inventory.csv / inf_inventory_report.txt
                           P05 inventory と INF 単位の解析レポート
                           (BthPan: 1 行のみ — INF は 1 ファイル)
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
- ワークスペースボリュームに約 5 GB の空き容量 (NPU スクリプトを併用する場合は約 7 GB — Ryzen AI ZIP は約 250 MB、展開後を含めて)。

### スクリプトの取得

```powershell
# 方法 1: リポジトリを clone
git clone https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer.git
cd Deploy-Drivers-For-WindowsServer

# 方法 2: release ZIP を以下からダウンロード
# https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/releases
```

### ワンショット dry-run (システムには変更を加えません)

```powershell
# 管理者権限の PowerShell セッション内で実行
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\Deploy-AMDChipsetDriverOnWindowsServer.ps1   -Action PrepareVerify -CleanWorkRoot
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot
.\Deploy-MSBthPanInboxOnWindowsServer.ps1      -Action PrepareVerify -CleanWorkRoot

# NPU スクリプト — 実機実行には OfflineZip (もしくはその他のダウンロードソース) が必須。
# クリーン環境で -OfflineZip 未指定の場合、 P03 で "All 4 download tiers exhausted" と throw する。
# 詳細パターンは下記の NPU スクリプト固有の Quick Start を参照。
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip -AssumeIfMissing
```

`PrepareVerify` は `P00-P09` (ソース取得・ 展開・ パッチ・ catalog 生成・ 署名) を実行した後、 `V01-V06` (artifact 検証・ dry-run install plan・ ハードウェア影響分析) を行います。 **システム状態は一切変更されません** — 証明書は import されず、 WDAC policy も deploy されず、 ドライバも install されません。 V05 / V06 の出力を読み、 `Install` がどのような変更を加えるかを正確に把握できます。

> **BthPan スクリプト固有の注意**: BthPan スクリプトの P03 (FetchInstaller) は何もダウンロードしません — ホスト自身の `C:\Windows\System32\DriverStore\FileRepository\bthpan.inf_amd64_*` ディレクトリから `bthpan.inf` を locate するのみです。 P03 が失敗するのは inbox driver が意図的に削除されているホスト (極めて稀) のみです。

### フルインストール (chipset・ graphics・ BthPan)

```powershell
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1   -Action Install
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1  -Action Install
.\Deploy-MSBthPanInboxOnWindowsServer.ps1      -Action Install
```

Windows Server 2025 ホスト上で実行してください。 すべてのスクリプトは冪等で、 cleanup-safe です (`-Action Cleanup` でワークスペース削除、 trust store からの証明書削除、 deploy された WDAC policy の削除を行います)。

> **BthPan スクリプト固有の成否判定**: BthPan スクリプトの `Install` 完了後、 I04 (PostInstallVerification) は Phantom OK と真の解消を明示的に区別します。 `bthpan.sys` が load されかつ `BthPan` サービスが稼働中、 `BTH\MS_BTHPAN` が `Class=Net・Service=BthPan・DriverInfPath=oem*.inf` を報告する場合のみ、 スクリプトは `*** TRUE RESOLUTION ACHIEVED ***` と表示します。 代わりに `*** TRUE RESOLUTION NOT YET ACHIEVED ***` と表示された場合、 再起動が典型的な解決策です (PnP rebind は次回起動時にしか効かないケースがあります)。

> **NPU スクリプトの `Install`**: [NPU スクリプト固有の Quick Start](#npu-スクリプト固有の-quick-start) を参照してください。 `Install` アクションには追加の前提条件 (offline ZIP の所有もしくは AMD アカウント認証情報) が必要で、 **物理 NPU ハードウェアなしでの実行は推奨されません**。

### 特定 phase のみの実行

```powershell
# 再ダウンロードせずパッチ済み INF と catalog だけ再生成
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action Prepare -OnlyPhases P05,P06,P08,P09

# 証明書信頼 phase だけ実行
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action Install -OnlyPhases I01

# BthPan の Phantom-OK readiness 解析のみを実行 (システム変更なし)
.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -OnlyPhases V06

# 全 phase をリスト表示
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action ListPhases
```

---

## BthPan スクリプト固有の Quick Start

> BthPan スクリプトは 4 スクリプト中最も実行が簡単です。 ドライバソースがホスト自身の DriverStore であり、 ネットワークダウンロード・ AMD アカウント・ EULA-gated ZIP のいずれも不要だからです。

### Step 1 — Bluetooth host controller が bind されていることを確認

BthPan スクリプトが扱うのは `BTH\MS_BTHPAN` (Bluetooth host controller bind 後に公開される Personal Area Network 子デバイス) のみです。 host controller 自体は **本スクリプトの対象外**です。

```powershell
# host controller が "Unknown device" ではなく Status=OK になっていることを確認。
Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue |
    Select-Object FriendlyName, Status, InstanceId

# host controller (例: Intel AX210・ Realtek RTL8852・ MediaTek MT7921 等) が
# "Unknown device" の場合、 先にベンダードライバをインストールしてください。
# 本スクリプトは host controller のドライバは扱いません。
```

### Step 2 — 現在状態を診断 (システム変更なし)

```powershell
.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -OnlyPhases V06
```

V06 はホスト上のすべての `BTH\MS_BTHPAN*` デバイスインスタンスについて per-instance 分類を出力します。 3 種類の状態があります:

| 分類 | 意味 | 推奨される次の操作 |
| --- | --- | --- |
| **Unknown** | Status=Error (code 28)。 ドライバが bind されていない。 | `-Action Install` を実行。 |
| **Phantom** | Status=OK だが `DriverInfPath=bth.inf`・ `Class=Bluetooth`・ `Service=(空)`。 `bthpan.sys` は **load されておらず**、 Device Manager は問題なく見えても PAN networking は機能していない。 | `-Action Install` を実行。 install 後、 I04 が rebind を検証。 |
| **True** | `DriverInfPath=oem*.inf`・ `Class=Net`・ `Service=BthPan`。 `bthpan.sys` は load 済、 BthPan サービスは稼働中。 | 操作不要。 既に真の解消状態にあります。 |

### Step 3 — フルインストール

```powershell
.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -Action All -CleanWorkRoot
```

`-Action All` は 21 phase すべて (`P00-P09` → `V01-V06` → `I00-I04`) を 1 コマンドで実行します。 I03 には `pnputil /scan-devices` が含まれており、 PnP マネージャに `BTH\MS_BTHPAN` の再評価を強制し、 `bth.inf` (Phantom 代理マッチ) からパッチ済み `oem*.inf` (真の解消) への rebind を発生させます。

I04 が `*** TRUE RESOLUTION NOT YET ACHIEVED ***` を報告した場合、 再起動が典型的な解決策です。 PnP rebind は次回起動時にしか効かない場合があります。 同じコマンドを再実行すると、 スクリプトの resume-after-reboot ロジックが新しい状態を検出し、 `*** TRUE RESOLUTION ACHIEVED ***` と報告するはずです。

### Step 4 — Decoration 戦略の選択 (上級者向け)

```powershell
# 戦略 A (デフォルト): NTamd64...3 のみ追加 (ProductType=3 はすべての Server SKU をカバー)。
.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -DecorationStrategy A

# 戦略 B: NTamd64.10.0...14393 / 17763 / 20348 / 26100 も明示的に追加。
# 将来 Microsoft inbox update で Server decoration が追加された場合に、
# わずかに高い PnP-ranking 優位性を提供。 将来の新 Server SKU build には手動更新が必要。
.\Deploy-MSBthPanInboxOnWindowsServer.ps1 -DecorationStrategy B
```

実運用では **戦略 A で十分**です (対応する 4 Server build 14393・ 17763・ 20348・ 26100 すべてをカバー)。 戦略 B は複数の bthpan パッケージが bind スロットを競合しており、 per-build エントリで確定的な tie-break が必要な環境のために存在します。

### Step 5 — 結果検証

```powershell
# bthpan.sys がコピーされたか?
Test-Path C:\Windows\System32\drivers\bthpan.sys

# BthPan サービスが登録・稼働中か?
Get-Service BthPan -ErrorAction SilentlyContinue

# Bluetooth PAN NetAdapter が visible か?
Get-NetAdapter | Where-Object InterfaceDescription -Match 'Bluetooth.*Personal Area Network'

# デバイスレベルの状態 (Class=Net・ Service=BthPan が期待される):
Get-PnpDevice -InstanceId 'BTH\MS_BTHPAN*' |
    Get-PnpDeviceProperty -KeyName DEVPKEY_Device_Class, DEVPKEY_Device_Service, DEVPKEY_Device_DriverInfPath
```

---

## NPU スクリプト固有の Quick Start

> **再掲**: 本スクリプトは実験的です。 続行前に [4 スクリプトのリスク分類](#4-スクリプトのリスク分類) を必ず読んでください。

### Step 1 — NPU ドライバ ZIP を取得 (4 つのいずれかの Tier)

NPU スクリプトは優先順位の高い順に **4 段階のダウンロード方式 (Tier)** を実装しています:

| Tier | 方式 | 利用シーン |
| --- | --- | --- |
| **1** | `-InstallerUrl <url>` で URL を明示 | ブラウザセッションで AMD CDN URL (例: `entitlenow.com` のリンク) を取得済みの場合。 |
| **2** | `-AmdAccountUser <email> -AmdAccountPassword <SecureString> -ForceAmdAccountAuth` | EULA 受諾フローを自動実行させたい場合。**❌ 2026-05-10 の検証で `account.amd.com` が JavaScript-driven SPA であることが確認されたため、デフォルト無効化済み。`-ForceAmdAccountAuth` で opt-in 可能 (現状の AMD ポータルでは失敗が想定されます)。** 詳細な検証レポートは `TESTING.md` §3.6 (英語のみ) を参照してください。 |
| **3** | EULA-gated 直接 fetch probe | 自動。ほぼ常にフォールスルーします (AMD は JS-driven submission を要求するため)。 |
| **4** ★ | `-OfflineZip <path>` もしくはスクリプトディレクトリ直下の `NPU_RAI*_WHQL.zip` | **推奨。** ZIP を一度手動でダウンロードし、スクリプト隣に配置。実行間で再現性あり。 |

Tier 4 用の手動ダウンロード手順:

- AMD ドキュメントページ: <https://ryzenai.docs.amd.com/en/latest/inst.html#install-npu-drivers>
- 検出された NPU 用の適切なドライバリンクをクリック (例: STX/KRK には NPU Driver 32.0.203.314、RAI 1.6.1)。
- AMD アカウントでサインインし EULA を受諾、ZIP を手元に保存 (典型的なファイル名: `NPU_RAI1.6.1_314_WHQL.zip`)。

### Step 2 — Dry-run (システムには変更を加えません)

推奨パターンは **`-Action PrepareVerify` + `-OfflineZip`** の組合せです。`-OfflineZip` を指定すると 4-tier resolution はスクリプト 824 行目の Tier 4 priority block で短絡判定し、ローカル ZIP が即座に使用されます — AMD 側へのネットワーク呼び出し無し、フォーム解析の脆弱性無し。

```powershell
# 推奨 — パイプライン健全性検証、システム未変更。
# OfflineZip は Tier 4 priority block で即座に確定 (AMD ネットワーク呼び出し無し)。
# 実機 NPU ホスト (Ryzen AI 300 / AI Max 300 / 7040 / 8040 シリーズ):
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action PrepareVerify `
    -CleanWorkRoot `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip
```

```powershell
# NPU 不在ホストでのパイプライン健全性チェック用 — 上記に -AssumeIfMissing を追加。
# P03 で NPU デバイス未検出時、エラーで停止せず default Strix Point profile で続行。
# パイプライン機構の検証のみで有効 (デバイスバインドは 0 件になり、実 NPU 挙動の検証にはならない)。
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action PrepareVerify `
    -CleanWorkRoot `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip `
    -AssumeIfMissing                            # default Strix Point + RAI 1.7.1
```

```powershell
# 非推奨 — クリーン環境で -OfflineZip 無しのパイプライン検証実行。
# このコマンドの内部挙動:
#   Tier 1 (-InstallerUrl)            : skip (未指定)
#   Tier 4 priority (-OfflineZip)     : skip (未指定)
#   Tier 2 (AMD アカウント自動 DL)    : skip (認証情報無し)
#   Tier 3 (EULA-gated direct probe)  : ほぼ常にフォールスルー (HTML フォーム返却)
#   Tier 4 auto-scan                  : スクリプトディレクトリ・./cache・workspace・~/Downloads を検索
# -CleanWorkRoot でワークスペースが削除済みかつ NPU_RAI*_WHQL.zip が auto-scan の
# どのロケーションにも無ければ、P03 で "All 4 download tiers exhausted" と throw する。
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot
```

### Step 3 — Install (実機 NPU を持ち、上記の警告を全て理解した場合のみ)

```powershell
# 推奨 — 手動ダウンロード済み offline ZIP を使ったフルインストール。
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action Install `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip
# I00 で以下の確認のため "I AGREE" の入力が要求されます:
#   1) AMD Ryzen AI EULA の受諾
#   2) Ryzen AI Software が公式に Windows 11 only であること
#   3) kernel-mode driver のみ install (user-mode stack は別途要 install)
#   4) BitLocker recovery key 控え済み
```

インストール成功後、スクリプトは guidance ブロックを表示し、**Ryzen AI Software (Python conda env、OGA、Vitis AI EP) は別途 <https://account.amd.com/en/forms/downloads/xef.html?filename=ryzen-ai-lt-1.7.1.exe> から install する必要がある**こと、user-mode stack は AMD 公式に Windows 11 build >= 22621.3527 only サポート (Windows Server 2025 ではサポートされない) であることを再度通知します。

### NPU 固有の便利オプション

NPU スクリプトは AMD 公式 [Ryzen AI Software インストールドキュメント](https://ryzenai.docs.amd.com/en/latest/inst.html) に従い、**2 つの独立したバージョニング軸**と、それらを評価する **互換性軸 (別軸)** を扱います:

| 軸 | パラメータ | デフォルト | 制御内容 |
|---|---|---|---|
| **A. NPU カーネルモードドライバ** | `-NpuDriverPackage` | `latest` (= `NPU_RAI1.6.1_314`) | スクリプトが対象とする NPU ドライバ ZIP パッケージ。AMD は現状 2 種類のみ公開: `NPU_RAI1.5_280` (driver 32.0.203.280) と `NPU_RAI1.6.1_314` (driver 32.0.203.314)。両者とも全 NPU コードネーム (PHX/HPT/STX/STH/KRK) をカバー。ドライババージョニングはゆっくり進化します。 |
| **B. Ryzen AI Software (ユーザーモードスタック)** | `-RyzenAiSoftwareVersion` | `latest` (= `1.7.1`) | post-install ガイダンスで言及される Ryzen AI Software バージョン (EXE は別途インストール)。AMD は **エンドユーザーワークロードでは常に最新版** を推奨。 |
| **C. 互換性評価** | (自動) | n/a | P03 で A + B から自動算出。現状 AMD は全 RAI バージョンが driver `≥ 32.0.203.280` を要求していることを文書化しているため、`280` および `314` の両方が RAI `1.5`〜`1.7.1` と互換。 |

A 列と B 列のスイッチは **独立** です。バージョンラベルを揃える必要はなく、例えば `-NpuDriverPackage NPU_RAI1.6.1_314 -RyzenAiSoftwareVersion 1.7.1` は AMD 公認の有効な組合せ (新しいドライバ + 最新 RAI Software) です。

これらのスイッチは **挙動を変更するだけで、ZIP のダウンロードソースを提供しません**。常に `-OfflineZip`、`-InstallerUrl`、または `-AmdAccountUser`/`-AmdAccountPassword -ForceAmdAccountAuth` (それぞれ Tier 4 / Tier 1 / Tier 2) と組み合わせて使用してください。

```powershell
# 特定 NPU codename を強制 (CPU 名検出が曖昧な場合。例: PHX vs HPT)
# 動作を予測可能にするため -OfflineZip と組合せて利用:
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action PrepareVerify `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip `
    -NpuOverride STX                            # PHX | HPT | STX | KRK

# 特定 NPU ドライバパッケージを pin (axis A)。注意: -NpuDriverPackage はスクリプトが
# どのパッケージを前提にロジックを組み立てるかを制御するので、-OfflineZip は同じパッケージ
# のものを指定する必要があります。
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action Install `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip `
    -NpuDriverPackage NPU_RAI1.6.1_314          # NPU_RAI1.5_280 | NPU_RAI1.6.1_314 | latest

# 特定 Ryzen AI Software バージョンを pin (axis B)。デフォルト 'latest' を推奨。
# このパラメータは post-install guidance メッセージにのみ影響します — Ryzen AI Software
# EXE は AMD ダウンロードページから別途ユーザーがインストールします。
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action Install `
    -OfflineZip .\NPU_RAI1.6.1_314_WHQL.zip `
    -RyzenAiSoftwareVersion latest              # 1.5 | 1.6.1 | 1.7 | 1.7.1 | latest

# AMD アカウント自動ダウンロード (Tier 2 — 2026-05-10 検証によりデフォルト無効化済み。
# opt-in する場合は -ForceAmdAccountAuth を指定。現状の AMD SPA ポータルでは失敗が想定されます。)
$cred = Get-Credential -UserName 'you@example.com' -Message 'AMD アカウントパスワード'
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action Install `
    -ForceAmdAccountAuth `
    -AmdAccountUser $cred.UserName `
    -AmdAccountPassword $cred.Password
```

> **よくある落とし穴**: `-Action Install -NpuOverride STX -NpuDriverPackage NPU_RAI1.6.1_314` を **ダウンロードソース未指定で** 実行すると、Tier 4 auto-scan にフォールスルーし、`~/Downloads` に偶然ある `NPU_RAI*_WHQL.zip` を黙って利用してしまいます — 指定したパッケージと一致するかどうかは保証されません。**常にソースを明示的に固定してください**。

---

## パイプラインアーキテクチャ (21 phase)

| Group | ID | 名称 | 内容 |
| --- | --- | --- | --- |
| Prep | P00 | Initialize | OS 検出、admin/TLS pre-flight、Workstation 上では WS2025 preview-mode banner 表示。NPU スクリプトでは Ryzen AI Software OS サポート警告も表示 |
| Prep | P01 | PrepareWorkspace | `C:\Temp\Workspace_AMD-{Chipset,Graphics,NPU}\` または `C:\Temp\Workspace_Microsoft-BthPan\` を作成 (`C:\Temp` がない場合は自動作成) |
| Prep | P02 | AcquireTools | 7-Zip、Windows SDK (signtool)、Windows WDK (inf2cat) を `winget` でインストール、失敗時は直接 EXE fallback |
| Prep | P03 | FetchInstaller | ホストの AMD platform 検出、amd.com から最新 installer URL 解決 (chipset/graphics)、もしくは 4-tier 解決 (NPU)、ダウンロード |
| Prep | P04 | ExtractInstaller | 7-Zip による展開。NPU スクリプトはネスト ZIP の検出にも対応 |
| Prep | P05 | AnalyzeInfs | 全 INF を inventory 化、source variant (W11x64 / WTx64 / WT6A_INF / WT64A、NPU では PHX/HPT vs STX/KRK) で分類、ホスト OS / NPU の対応 INF を選択 |
| Prep | P06 | PatchInfs | Server decoration を持たない INF について、各 Workstation `[Manufacturer]` エントリを `ProductType=3` で mirror。最初から Server-compatible な INF も patched フォルダにコピーして install パイプラインで処理されるようにする |
| Prep | P07 | CreateCertificate | RSA 4096 / SHA-384 自己署名コード署名証明書を生成 (有効期間 5 年)、PFX と CER で export |
| Prep | P08 | GenerateCatalogs | 各 patched INF フォルダで `inf2cat /os:Server2025_X64` を実行 |
| Prep | P09 | SignCatalogs | 全 catalog で `signtool sign /fd SHA384 /td SHA384 /tr <timestamp-url>` を実行 |
| Verify | V01 | VerifyArtifacts | 証明書 + パッチ済み INF + catalog の存在確認 |
| Verify | V02 | VerifyCertificate | PFX デコード、EKU・有効期間・鍵長の確認 |
| Verify | V03 | VerifyCatalogs | `signtool verify /pa` (I01 で証明書を信頼するまで失敗が想定) |
| Verify | V04 | VerifyInfs | パッチ済み INF を再 parse し、`ProductType=3` decoration の coverage を確認 |
| Verify | V05 | DryRunInstall | `Win32_PnPSignedDriver` を使って I01-I03 をシミュレート、各 install / skip / upgrade 判定を予測、install plan を出力 |
| Verify | V06 | HardwareImpactAnalysis | ホスト上の AMD ハードウェアを enumerate、AS-IS ドライバとパッチ済み TO-BE ドライバを比較、リスク (HIGH / MEDIUM / LOW) 分類。NPU スクリプトでは Ryzen AI Software user-mode stack 関連の通知も表示 |
| Inst | I00 | PreInstallReview | V06 リスクサマリを表示、operator の確認を要求 (NPU スクリプトでは Ryzen AI EULA への明示的 `I AGREE` 入力も要求) |
| Inst | I01 | TrustCertificate | CER を `LocalMachine\Root` + `LocalMachine\TrustedPublisher` に import |
| Inst | I02 | AuthorizeDriverSigning | 当該証明書を kernel-mode 署名者として allowlist する WDAC supplemental policy を build + deploy (デフォルトパス)、`-UseTestSigning` 指定時のみ legacy `bcdedit /set testsigning on` 経路に fallback |
| Inst | I03 | InstallDrivers | 対象 INF 全てに対して `pnputil /add-driver <patched.inf> /install` を実行 |
| Inst | I04 | PostInstallVerification | AMD ハードウェアを再 enumerate、各対象デバイスに `[C] Self-signed` ドライバが bind されたか確認。NPU スクリプトでは Ryzen AI Software user-mode stack インストール guidance も表示 |

---

## パラメータ一覧（スクリプト別）

4 スクリプトは `-Action`、 `-OnlyPhases`、 `-CleanWorkRoot`、 `-AllowWorkstationInstall`、 `-UseTestSigning`、 `-WorkRoot`、 `-PfxPassword` を共通パラメータコントラクトとして共有します。 Chipset / Graphics スクリプトはこれに加えて source-discovery と help 用のスイッチを共有、 NPU スクリプトは 4-tier installer 解決と platform override ブロックを追加します。

### 共通パラメータ (Chipset / Graphics / NPU)

| パラメータ                  | デフォルト           | 説明                                                                                              |
| -------------------------- | -------------------- | ------------------------------------------------------------------------------------------------- |
| `-Action`                  | `PrepareVerify`      | `Prepare` / `Verify` / `PrepareVerify` / `Install` / `All` / `Cleanup` / `ListPhases`             |
| `-OnlyPhases`              | `@()`                | Phase ID (例: `P05`、 `P06`、 `P08`、 `P09`) または short name (例: `PatchInfs`); `-Action` を上書き |
| `-CleanWorkRoot`           | (off)                | workspace を実行前に削除 (download/extract を再取得)                                              |
| `-AllowWorkstationInstall` | (off)                | Workstation OS (Win11) での Install phase 実行を許可。 デフォルトは block される (非推奨スイッチ) |
| `-UseTestSigning`          | (off)                | WDAC 補助 policy ではなく `bcdedit /set testsigning on` にフォールバック (非推奨)                 |
| `-WorkRoot`                | スクリプト別         | workspace path を上書き (Chipset: `C:\Temp\Workspace_AMD-Chipset`、 Graphics: `C:\Temp\Workspace_AMD-Graphics`、 NPU: `C:\Temp\Workspace_AMD-NPU`、 BthPan: `C:\Temp\Workspace_Microsoft-BthPan`)。 r58+ / r26+ / r8+ / r2+: `C:\Temp\Workspace_*` 配下に再配置済み。 `C:\Temp` がない場合はスクリプトが自動作成 |
| `-LogFile`                 | `''` (無効)         | (r58+ / r26+ / r8+ / r2+) コンソール出力全体を `Start-Transcript` / `Stop-Transcript` でファイルにキャプチャするためのオプションパス。 ファイル側は全ストリーム (Output / Host / Error / Warning / Verbose / Debug) をプレーンテキストで受け取り、 インタラクティブコンソール側は `Write-Host -ForegroundColor` の色装飾を維持する。 レガシーな `... \|*>&1 \| Tee-Object -FilePath ...` イディオムは Write-Host の色情報がパイプ経由で削除されるが、 こちらは色を保持できるため推奨。 推奨ファイル名: `C:\Temp\<tag>_<Action>_<yyyyMMdd-HHmmss>.log` |
| `-PfxPassword`             | スクリプト別         | 自己署名 PFX のパスワード (Chipset / Graphics: `'ChangeMe!2026'`、 NPU: `''`)                     |
| `-WdacPolicyGuid`          | スクリプト別 (固定 UUID v4) | WDAC 補助 policy GUID を上書き。 デフォルトはスクリプト別 (Chipset: `503860EA-…`、 Graphics: `85336828-…`、 NPU: `8B2C4F12-…`)。 レガシー deploy のクリーンアップ、 または並列複数 deploy で使用 |

### Chipset / Graphics 固有パラメータ

| パラメータ          | デフォルト                       | 説明                                                                                                |
| ------------------- | -------------------------------- | --------------------------------------------------------------------------------------------------- |
| `-Help` / `-h` / `-?` | (off)                          | フォーマット済みの使用方法情報を表示して終了                                                        |
| `-References`       | (off)                            | 関連 Microsoft Learn ドキュメントリンクの一覧を表示して終了                                          |
| `-InstallerUrl`     | `''`                             | AMD インストーラ EXE の URL を明示指定 — URL 探索 probe を bypass                                    |
| `-AmdLandingUrls`   | スクリプト別デフォルト array     | インストーラ EXE URL を scrape するための landing page (AMD のサイト構造変更時のみ override)         |
| `-AmdFallbackUrl`   | スクリプト別デフォルト URL       | landing page の scraping が失敗した時の last-resort ハードコード URL                                 |
| `-Force`            | (off)                            | 既存 workspace ファイルの強制上書き (要注意)                                                        |
| `-TimestampUrl`     | `http://timestamp.digicert.com`  | `signtool sign /tr` 用 RFC 3161 タイムスタンプサーバ                                                |
| `-WdacBasePolicyGuid` | `A244370E-44C9-4C06-B551-F6016E563076` (Windows 標準 base CI policy) | WDAC 補助 policy が target とする SupplementsBasePolicyID を上書き。 カスタム base policy を使用している環境でのみ変更 |

> **Note**: Chipset / Graphics スクリプトは現状 `-CertValidityYears` を公開していません — デフォルトの 5 年有効期間はハードコードされています。 設定可能なパラメータとして公開しているのは NPU スクリプトのみです。

### NPU 固有パラメータ

| パラメータ               | デフォルト            | 説明                                                                                                              |
| ------------------------ | --------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `-InstallerUrl`          | (なし)                | Tier 1: NPU ドライバ ZIP の URL を明示指定                                                                         |
| `-OfflineZip`            | (なし)                | Tier 4 優先: 事前ダウンロード済み NPU ドライバ ZIP のパス (**推奨パターン**)                                       |
| `-AmdAccountUser`        | (なし)                | Tier 2: AMD アカウントメール (BEST-EFFORT — デフォルト無効)                                                       |
| `-AmdAccountPassword`    | (なし)                | Tier 2: AMD アカウントパスワード (SecureString)                                                                    |
| `-ForceAmdAccountAuth`   | (off)                 | Tier 2 のフォームベース認証を opt-in (現状の AMD JS-driven SPA ポータルに対してはほぼ失敗が予想される)             |
| `-NpuOverride`           | (なし)                | NPU codename を強制: `PHX` / `HPT` / `STX` / `KRK`                                                                |
| `-NpuDriverPackage`      | `latest`              | NPU kernel-mode driver パッケージ: `NPU_RAI1.5_280` / `NPU_RAI1.6.1_314` / `latest` (`NPU_RAI1.6.1_314` に解決される) |
| `-RyzenAiSoftwareVersion`| `latest`              | Ryzen AI Software (user-mode stack) 推奨バージョン: `1.5` / `1.6.1` / `1.7` / `1.7.1` / `latest`                  |
| `-AssumeIfMissing`       | (off)                 | NPU 未検出時にデフォルトプロファイル (Strix Point + NPU driver 32.0.203.314 + RAI Software latest) で続行         |
| `-CertValidityYears`     | `5`                   | 自己署名証明書の有効期間 (年、 NPU スクリプトのみ)                                                                |

> **Note**: NPU ドライバ と Ryzen AI Software のバージョニング軸は **独立**です (AMD ドキュメント <https://ryzenai.docs.amd.com/en/latest/inst.html> 参照)。 `-NpuDriverPackage` と `-RyzenAiSoftwareVersion` は独立スイッチなので、 任意の driver × software 組み合わせが可能 (例: `-NpuDriverPackage NPU_RAI1.6.1_314 -RyzenAiSoftwareVersion 1.7.1`)。

---

## 出力ファイル

各スクリプトは workspace (`C:\AMD-{Chipset,Graphics,NPU}-WS\`) 配下に以下のアーティファクトを書き出します:

| パス (workspace からの相対)                  | 内容                                                                                                          |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `download\<installer>`                       | AMD インストーラ EXE (Chipset/Graphics) または NPU ドライバ ZIP (NPU)                                          |
| `extracted\`                                 | 展開済みインストーラ内容 (元 INF、 SYS、 DLL、 CAT ファイル)                                                  |
| `patched\<inf>`                              | `ProductType=3` decoration を mirror したパッチ済み INF                                                       |
| `patched\<cat>`                              | 再生成された catalog ファイル (`inf2cat /os:Server2025_X64` 出力)                                              |
| `cert\AMD-Chipset-Driver-CodeSign.pfx` (Chipset) / `cert\AMD-Graphics-Driver-CodeSign.pfx` (Graphics) / `cert\AMD-NPU-Driver-CodeSign.pfx` (NPU) | 自己署名コード署名証明書 (PFX 形式) |
| `cert\AMD-Chipset-Driver-CodeSign.cer` (Chipset) / `cert\AMD-Graphics-Driver-CodeSign.cer` (Graphics) / `cert\AMD-NPU-Driver-CodeSign.cer` (NPU) | 公開証明書 (CER 形式、 trust-store import 用)   |
| `cert\AmdSuppPolicyId.txt` (Chipset/Graphics) | 動的に生成された WDAC supplemental PolicyId をクリーンアップ用に記録するマーカーファイル                       |
| `cert\WDAC-Supplemental-NPU.xml` / `.cip` (NPU) | WDAC 補助 Code Integrity policy (XML ソース + バイナリ、 `C:\Windows\System32\CodeIntegrity\CiPolicies\Active\` に deploy) |
| `cert\MsBthPanSelfSignedSupplementalPolicy.xml` / `.cip` (BthPan) | BthPan 用 WDAC 補助 Code Integrity policy (XML ソース + バイナリ、 `C:\Windows\System32\CodeIntegrity\CiPolicies\Active\` に deploy)。 BthPan 固有 GUID `A6E72D4F-3B98-4C5A-9E1D-7F8B2A4C6E5D` を使用。 |
| `inf_inventory.csv`                          | P05 で生成される INF 単位 inventory (ファイル名、 provider、 class、 HWID 数、 decoration ステータス等)        |
| `inf_inventory_report.txt`                   | P05 INF 解析の人間可読サマリ                                                                                  |

### CSV カラム規約

`inf_inventory.csv` は 4 スクリプトで以下のカラム規約に従います:

| カラム                | 型     | 意味                                                                            |
| --------------------- | ------ | ------------------------------------------------------------------------------- |
| `FileName`            | string | INF ファイル名 (例: `kipudrv.inf`)                                              |
| `FullPath`            | string | workspace 内の絶対パス                                                          |
| `Provider`            | string | INF `[Version]` Provider フィールド (例: `AdvancedMicroDevicesInc.`)            |
| `DriverVer`           | string | INF `DriverVer` 行 (例: `07/08/2025,32.0.203.314`)                              |
| `Class`               | string | デバイスクラス (例: `Computer`、 `Display`、 `System`)                          |
| `HwidCount`           | int    | INF が参照する Hardware ID の総数                                               |
| `MatchesTargetNpu`    | bool   | (NPU 限定) INF がターゲット NPU の PCI HWID パターンを参照しているか            |
| `MatchedHwidCount`    | int    | このINF のうちターゲットデバイスにマッチする HWID 数                            |
| `HasServerDecoration` | bool   | INF が既に `ProductType=3` decoration を持つ (パッチ不要)                       |
| `NeedsPatch`          | bool   | INF が Workstation のみの decoration を持ち `ProductType=3` mirror が必要       |
| `SelectedForPipeline` | bool   | スクリプトの filter を通過し、 パッチ/署名パイプラインに入る INF                |

---

## UEFI Secure Boot ベースライン

4 つのスクリプト (Chipset / Graphics / NPU / BthPan) すべては、 ホストの UEFI Secure Boot 証明書ロールアウト状態を P00 で 1 回キャプチャし、 パイプライン全体でそのスナップショットを再利用します。 これは情報提供のみが目的で、 これらスクリプトが操作する OS レイヤの自己署名信頼チェーンは、 ファームウェアレイヤの UEFI Secure Boot 証明書データベースから**独立**しています。 複数の姉妹スクリプトを同じホストで実行する operator は一貫したベースライン情報を確認でき、 UEFI 証明書ロールアウト状況とドライバインストール結果を相関分析できます。

### キャプチャされる内容

スナップショットは 2 つのソースを統合します:

1. **組み込みインベントリ** — `Confirm-SecureBootUEFI`、 `Get-SecureBootUEFI db/kek` で 5 つの正規証明書 (`Windows UEFI CA 2023`、 `Microsoft KEK 2K CA 2023`、 `Microsoft UEFI CA 2011`、 `Microsoft UEFI CA 2023`、 `Microsoft Option ROM UEFI CA 2023`) を直接読み取り。 `HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot{,\Servicing,\Servicing\DeviceAttributes}` レジストリキーと、 `\Microsoft\Windows\PI\Secure-Boot-Update` スケジュールタスクの状態 (ja-JP ホスト上で locale 非依存に動作させるため `Get-ScheduledTask` を使用) を取得。

2. **Microsoft サンプルスクリプト** — `%SystemRoot%\SecureBoot\ExampleRolloutScripts\Detect-SecureBootCertUpdateStatus.ps1` に配備されている場合 (Windows 11 では KB5089549、 Windows 10 では KB5087544 / KB5088863、 WS2025 は 2026-05-12 以降の同等パッチで配信)、 子 PowerShell として起動し、 Microsoft の confidence bucket 判定を取得。 MS スクリプトの入力検証バグ (`:` を含む `-OutputPath` を拒否する。 つまりあらゆる Windows 絶対パスが拒否される) を回避するため stdout-JSON フォールバックを実装。

### 表示箇所

| Phase | 表示形式 | 目的 |
|---|---|---|
| P00 | 1行コンパクト: `Secure Boot baseline: enabled=true UEFI-CA-2023=NotStarted health=Warning [MS-sample=ok]` | operator の即時認知 |
| P05 | `inf_inventory_report.txt` 末尾のテキスト形式アペンディックス | 変更管理ドキュメント |
| V05 | 1行コンパクト `[Dry-Run UEFI Baseline]` ブロック | コミット前の sanity 確認 |
| V06 | 詳細マルチセクション内訳 (Chipset / Graphics は Section 4、 NPU は Section 5) | 詳細フォレンジック |
| I02 | 事前チェック + 計画している WDAC / testsigning パスとの相互参照 | OS レイヤ署名操作前の operator 確認 |

5 箇所すべてで同一のメモリ上スナップショットを再利用し、 MS サンプルスクリプトの呼び出しは 1 ラン当たり最大 1 回に制限されます。

### 健全性判定

- **Healthy** — Secure Boot ON、 UEFI CA 2023 ロールアウトが `Updated` (または対象外)、 ロールアウトエラーなし。
- **Warning** — Secure Boot ON だがロールアウトが進行中 (`NotStarted` / `Started` / `Pending`)、 スケジュールタスクが無効、 または MS サンプルがロールアウトイベント診断を報告。
- **Critical** — Secure Boot OFF (計画した WDAC パスは ON を前提)、 または `UEFICA2023Error` 非ゼロでロールアウトがスタック状態。

I02 では判定結果を提示しますが、 **判定を理由にブロックすることはありません** (両信頼レイヤは独立)。 `Critical` または `Warning` では黄色の advisory が表示され、 operator が続行可否を判断します。

### 診断ファイル

MS サンプルスクリプトが起動された場合、 `<WorkRoot>\secureboot_ms_sample\` 配下に以下のファイルが生成されます:

```
detect_stdout.log                  - キャプチャした raw stdout (Write-Host + JSON)
detect_stdout_extracted.json       - パース済みJSONオブジェクト (BucketId / Confidence / Event1801..1803 カウント)
```

これらはワークスペース成果物の一部として保持され、 `-CleanWorkRoot` を指定しない限り後続ランでも残ります。

---

## コンソール出力フォーマット

スクリプトが出力する全行は、 構造化・タイムスタンプ付きフォーマットに従い、 **4 スクリプト (Chipset / Graphics / NPU / BthPan) で完全に同一**です。 これは意図的な設計で、 複数スクリプトのログを混在して読む operator が同じ語彙とビジュアルレイアウトを認識できるようにするためです。

### マーカーの意味

| マーカー | 色        | 用途     | 例                                                                  |
| -------- | --------- | -------- | ------------------------------------------------------------------- |
| `[*]`    | Cyan      | Step     | `[*] Acquiring signtool, inf2cat, and 7-Zip`                        |
| `[+]`    | Green     | Ok       | `[+] Cert thumbprint: A1B2C3D4...`                                  |
| `[!]`    | Yellow    | Warn     | `[!] Tier 2 (AMD account auto-download) is disabled by default`     |
| `[X]`    | Red       | Fail     | `[X] Top-level error: AMD NPU not detected`                         |
| `[~]`    | DarkGray  | Skip     | `[~] Inventory CSV: C:\Temp\Workspace_AMD-NPU\inf_inventory.csv`     |

セクションバナーテーブル内の継続行 (PowerShell 環境ダンプ、 OS プロファイル、 Secure Boot ベースライン、 INF インベントリ行、 V05/V06/I00 サブブロック等) は `Write-Detail` ヘルパー経由で出力されます。 これはタイムスタンプとマーカー接頭辞を持たない 4 スペースインデント行で、 「すべての行にマーカーを付ける」 規約の唯一の許容例外です。 ログを読む operator は、 4 スペースインデント行を直前のマーカー行の従属的な継続行として扱ってください。 (チップセット r56 / グラフィックス r24 で導入。 SPEC §A.5 参照。)

### サンプル出力 (NPU スクリプト、 P00 → P03)

```
========================================================================
 Deploy-AMDNpuDriverOnWindowsServer
 Version: npu-2026.05.17-r9  [npu-r9-debug-trace-facility-instrumentation-resume-ctx-autolog]  SHA256: e0ca465680db
 Action : PrepareVerify
 Repo   : https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer
========================================================================

========================================================================
 PHASE P00 - Initialize                 (Prep  )  start: 14:23:05
 script: npu-2026.05.17-r9/e0ca465680db
========================================================================
[14:23:05]            [*] Running environment and sanity checks
[14:23:05]            [+] Administrator privileges confirmed.
[14:23:05]            [~] TLS protocols enabled: Tls, Tls11, Tls12, Tls13
[14:23:06] [+0.42s]   [+] OS detected     : Microsoft Windows Server 2025 (build 26100)
[14:23:06] [+0.42s]   [~] Profile applied : WS2025
[14:23:06] [+0.42s]   [~] inf2cat /os: switch : Server2025_X64
 PHASE P00 -> DONE     elapsed: 0.45s

========================================================================
 PHASE P03 - FetchInstaller             (Prep  )  start: 14:23:12
========================================================================
[14:23:12]            [*] Detecting NPU platform and resolving installer source (4-tier fallback)
[14:23:12] [+0.18s]   [+] NPU codename         : Strix Point / Strix Halo
[14:23:12] [+0.18s]   [+] NPU short name       : STX
[14:23:12] [+0.18s]   [+] Hardware ID          : PCI\VEN_1022&DEV_17F0&REV_00
[14:23:12] [+0.18s]   [+] NPU driver package   : NPU_RAI1.6.1_314
[14:23:12] [+0.18s]   [+] NPU driver build     : 32.0.203.314
 PHASE P03 -> DONE     elapsed: 1.23s
```

Phase header banner (`=` × 72、 Magenta) は dispatcher が出力し、 phase 関数自身は banner を出しません。 `[+X.XXs]` の elapsed-tag は各 phase エントリで reset され、 **当該 phase 内の経過時間** (スクリプト全体の経過ではない) を表します。

---

## 実行ログのキャプチャ (`-LogFile`)

Chipset r59 / Graphics r27 / NPU r9 / BthPan r9 から、 4 つのスクリプトすべてに `-LogFile <path>` パラメータが追加され、 `Start-Transcript` / `Stop-Transcript` 経由でコンソール出力全体をファイルにキャプチャできます:

```powershell
# 推奨: コンソール側は色情報を維持、 ファイル側は全ストリームをプレーンテキストで取得
$ts  = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = "C:\Temp\amd-chipset_PrepareVerify_$ts.log"
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot -LogFile $log
```

主な特性:

- **コンソールは `Write-Host -ForegroundColor` による色装飾を維持** — レガシーな `*>&1 | Tee-Object -FilePath …` イディオムは Write-Host の色情報がパイプ経由で削除されますが、 `-LogFile` ではそれが起きません。
- **ファイル側は全ストリーム (Output / Host / Error / Warning / Verbose / Debug) を UTF-8 プレーンテキストで受信**。
- **親ディレクトリは自動作成** (例: `C:\Temp\` がない場合は作成されます)。
- **Append モード** (`-Append -Force`) — 連続再実行はファイルに追記されます (truncate されません)。
- **クリーンアップは冪等** — `Stop-Transcript` は最上位の `finally` block と `PowerShell.Exiting` engine event handler の両方から呼ばれます。

推奨ファイル命名規則:

```
C:\Temp\<scripttag>_<Action>_<yyyyMMdd-HHmmss>.log
```

例:

| スクリプト | 推奨ファイル名                                                 |
| ---------- | -------------------------------------------------------------- |
| Chipset    | `C:\Temp\amd-chipset_PrepareVerify_20260517-143022.log`        |
| Graphics   | `C:\Temp\amd-graphics_Install_20260517-143022.log`             |
| NPU        | `C:\Temp\amd-npu_All_20260517-143022.log`                      |
| BthPan     | `C:\Temp\ms-bthpan_PrepareVerify_20260517-143022.log`          |

### レガシー fallback (`Tee-Object`)

レガシーな `*>&1 | Tee-Object` イディオムも引き続きサポートされており、 ログファイルを後段のツールにパイプで渡したい場合に有用です。 ただし **Write-Host の色情報はストリップされる** ことに注意 (PowerShell のパイプラインは host stream の色情報を伝搬しません):

```powershell
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action Install *>&1 |
    Tee-Object -FilePath "C:\Temp\amd-chipset_Install_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
```

ja-JP host でデフォルトのコードページ (932 / Shift-JIS) のまま `-LogFile` あるいは `Tee-Object` で出力をファイルへリダイレクトする場合は、 ファイルエンコーディングを明示的に UTF-8 として扱ってください (二重エンコーディング防止)。 スクリプトは P00 で `Set-ConsoleUtf8` を呼び出して `[Console]::OutputEncoding` を UTF-8 に強制しますが、 キャプチャされたファイルを読むツール (テキストエディタ、 `Get-Content` 等) 側でも UTF-8 として認識させる必要があります。

---

## システム要件

- **CPU**: AMD Ryzen 4000 シリーズ以降 (スクリプトの `Get-AmdChipsetPlatform` heuristic は 4000 → AI 300、AI Max 300 を認識します。それより古い silicon でも動作はしますが未検証)。NPU スクリプト用には Ryzen 7040 / 8040 / AI 300 / AI Max 300 / AI 200 シリーズ (NPU 内蔵) が必要。
- **OS**: Windows Server 2025 (build 26100) が production target。Windows 11 24H2 (build 26100) は *preview* host として対応 ([TESTING.md](./TESTING.md) 参照)。Windows Server 2016 / 2019 / 2022 は OS profile matrix で認識され、inf2cat も対応する `/os:` switch (`Server2016_X64`、`ServerRS5_X64`、`ServerFE_X64`) を選択しますが、これらバージョンでの production 利用は本 README の対象外です。
- **PowerShell**: 5.1 (Windows PowerShell Desktop) または 7.x (PowerShell Core)。スクリプトの `Show-PowerShellEnvironment` phase が認識する互換性 matrix を表示します。
- **ディスク**: ワークスペースボリュームに約 5 GB (NPU スクリプトを併用する場合は約 7 GB)。
- **ネットワーク**: `*.amd.com`、`download.microsoft.com`、`go.microsoft.com`、`aka.ms` (winget)、`timestamp.digicert.com` (署名タイムスタンプ) への outbound HTTPS。NPU スクリプトの Tier 2 を使う場合はさらに `account.amd.com` および `*.entitlenow.com`。
- **権限**: ローカル管理者。ドメイン権限不要。

---

## 自己署名証明書: 有効期限・更新・失効

P07 で生成される証明書は本パイプラインで install する全ドライバの **trust anchor** です。専用セクションで詳しく説明します。

### 証明書のプロパティ

- **Subject**:
  - `CN=AMD Chipset Driver Self-Sign (WS2025 Lab, At Own Risk)` (chipset)
  - `CN=AMD Graphics Driver Self-Sign (WS2025 Lab, At Own Risk)` (graphics)
  - `CN=AMD NPU Driver Self-Sign (WS2025 Lab, At Own Risk)` (NPU)
- **鍵**: RSA 4096-bit、SHA-384 署名アルゴリズム。
- **EKU**: Code Signing (`1.3.6.1.5.5.7.3.3`)。
- **有効期間**: **P07 実行日から 5 年**。スクリプトでハードコードされています。
- **保管場所**: PFX を `C:\AMD-{Chipset,Graphics,NPU}-WS\cert\` に保存。デフォルトでは PFX に**パスワードが設定されていません** (lab ツールという位置付けのため。本格的なパスワードが必要であれば param block の `[string]$PfxPassword = ''` を変更してください)。
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
.\Deploy-AMDNpuDriverOnWindowsServer.ps1      -Action Prepare -OnlyPhases P07,P08,P09

# 2. 新証明書を信頼 (古い証明書は明示的に削除するまで信頼されたまま)
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Install -OnlyPhases I01,I02
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Install -OnlyPhases I01,I02
.\Deploy-AMDNpuDriverOnWindowsServer.ps1      -Action Install -OnlyPhases I01,I02

# 3. 再署名されたドライバを driver store に追加 (既存デバイスを新署名にバインド)
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Install -OnlyPhases I03
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Install -OnlyPhases I03
.\Deploy-AMDNpuDriverOnWindowsServer.ps1      -Action Install -OnlyPhases I03

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
.\Deploy-AMDNpuDriverOnWindowsServer.ps1      -Action Cleanup

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

3. **AMD の End User License Agreement** はチップセット / グラフィックス / Ryzen AI installer の再配布を特定の条件下で許可しています。INF を編集して再署名する行為は grey area で、お使いの specific package の AMD EULA を読んだ上でご自身の判断を形成してください。**本リポジトリは、あなたの利用が AMD の terms 下で許可されるかについて何ら立場を取りません。** Ryzen AI に関しては、ダウンロード前に <https://account.amd.com/en/forms/downloads/ryzenai-eula-public-xef.html> で EULA 受諾が必須です。NPU スクリプトの I00 phase は明示的な `I AGREE` 確認入力を要求し、この受諾が完了していることを確認します。

4. **Microsoft の Windows Hardware Lab Kit (HLK) 認証は無効化されます**。本パイプラインで置換する全ドライバについて。WHQL 署名ドライバは Microsoft が HLK 通過を attest していますが、自己署名ドライバはそうではありません。当該ハードウェアについて Microsoft Premier Support に依存している場合、自己署名ドライバが原因の問題はサポート契約の対象外になる可能性があります。

5. **BitLocker / TPM / Secure Boot との相互作用**。チップセットスクリプトの PSP ドライバ置換 (`amdpsp.inf`) は Platform Security Processor firmware と相互作用します。BitLocker が有効な system では、PSP ドライバ更新の失敗が次回起動時の BitLocker recovery プロンプト発生を引き起こす可能性があります。**chipset スクリプトで `-Action Install` を実行する前に、必ず BitLocker recovery key を控えてください。**

6. **Anti-cheat ソフトウェア** (Easy Anti-Cheat、BattlEye、Vanguard 等) は自己署名 kernel-mode ドライバを flag する可能性があります。本パイプラインは競技性のあるゲームタイトルでのゲーミングワークロードを想定しておらず、当該用途で利用するとアカウント BAN の可能性があります。

7. **5 年の証明書有効期限は実際に到来します**。production deploy をする場合は 4.5 年目に renewal タスクをカレンダーに登録するか、5 年目以降ドライバインストールが停止することを受け入れてください。

8. **ドライバカテゴリ優先度オーバーライド (チップセット r56 / グラフィックス r24 — 破壊的変更)**。 これらのリビジョン以降、 スクリプトのインストール判定ロジックは自己署名ドライバ ([C]) をハードウェアベンダードライバ ([B]) およびマイクロソフト汎用ドライバ ([A]) より優先しま す。ドライバのバージョン値に関係ありません。 クリーンインストール直後の WS2025 ではこれが意図した動作です — マイクロソフトの in-box 汎用ドライバはスクリプトの署名を持つ AMD ベンダードライバに置き換えられます。 トレードオフは、 Windows Update や OEM パッケージで既にインストール済みの AMD ベンダードライバ**も**、 スクリプトの自己署名版で上書きされる点です (バイナリは同じで、 発行者署名のみが異なります)。 ベンダードライバを保持したい場合は、 まず `-Action PrepareVerify` を実行し V06 Section 2 を確認した上で続行を判断してください。 詳細な理論的根拠は SPEC §D.15 を参照してください。

9. **NPU スクリプト (`Deploy-AMDNpuDriverOnWindowsServer.ps1`) は姉妹スクリプトと比較して明らかにリスクが高いです。** 具体的には:
   - **物理 NPU での検証は本ドキュメント執筆時点でメンテナーによって実施されていません。** 全ての検証は `psa.py` による静的解析と、AMD 公開の `quicktest.py` 検出ロジックを PowerShell に翻訳したコードのレビューに留まっています。
   - **AMD アカウント自動ダウンロード (Tier 2) は best-effort で予告なく破綻する可能性があります**。AMD は `account.amd.com` のフォーム構造、CSRF token 名、entitlenow.com CDN URL スキーム等を更新します。再現性のある実行は常に Tier 4 (`-OfflineZip`) を優先してください。
   - **Ryzen AI Software は AMD ドキュメント上 Windows 11 only です** (build >= 22621.3527)。Windows Server 2025 で NPU kernel driver が load しても、user-mode stack (Python conda env、ONNX Runtime VitisAI EP、OGA) は動作することが期待できません。**Server 2025 で AI 推論ワークロードを期待する環境では NPU スクリプトを deploy しないでください。**
   - **Driver store cleanup は best-effort です。** `-Action Install` 後の自己署名 NPU ドライバの driver store からの削除は、`pnputil /delete-driver oemNN.inf /force` の手動実行や Driver Store Explorer (Rapr.exe) の利用が必要となるケースがあります。

10. **本リポジトリで商用サポートは提供されません**。GitHub Issues (<https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/issues>) はバグ報告と説明要求の best-effort 対応です。Pull request は歓迎しますが、レビューのタイミングは保証されません。

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
- Issue を起票: <https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/issues>

### NPU スクリプト "All 4 download tiers exhausted"

NPU スクリプトで最も頻発する失敗ケースです。EULA-gated AMD フォームはスクリプトで完全にシミュレートできない認証付き AMD アカウントセッションを必要とします。優先度の高い順の回避策:

1. **手動ダウンロード**: <https://ryzenai.docs.amd.com/en/latest/inst.html#install-npu-drivers> から ZIP を取得、スクリプト隣に配置、`-OfflineZip .\NPU_RAI*.zip` で再実行。
2. **`-AmdAccountUser` / `-AmdAccountPassword` を試す**: ただし破綻が予想されます。AMD のフォーム構造変更は告知されません。
3. **手動 EULA 受諾後にブラウザで entitlenow.com URL を捕捉**し、`-InstallerUrl <captured-url>` で渡す。URL に時間制限のある hash が含まれているため、捕捉直後に即時実行してください。

### NPU スクリプト "No AMD NPU detected via pnputil"

ホストに AMD NPU デバイスが存在しません。次のいずれかです:

- 想定通り (NPU 不在ホストでのパイプライン健全性チェック実行): `-AssumeIfMissing` で default Strix Point + RAI 1.7.1 profile に進めます。
- 想定外 (Ryzen AI マシンを所有しているはず): Device Manager で unbound PCI デバイスを確認、Task Manager → Performance に NPU0 エントリがあるか確認、BIOS で NPU が disabled になっていないか確認。

### "V06 で MS-GENERIC ドライバの AMD ハードウェアがパッチ済み INF でカバーされない"

CPU core (`cpu.inf`)、PCI Express ルートポート (`pci.inf`)、ホスト CPU ブリッジ (`machine.inf`)、USB xHCI (`usbxhci.inf`)、HD Audio コントローラー (`hdaudbus.inf`) は **全て Microsoft 汎用ドライバのまま残ることが想定済み**です。これらに対して AMD はベンダードライバを提供していません (core OS subsystem が enumerate するため)。V06 セクション 1 の "ALERT" メッセージは情報提供であってエラーではありません。

### "I02 で WDAC policy が deploy されたが新ドライバが load されない"

`eventvwr` → `アプリケーションとサービスログ` → `Microsoft` → `Windows` → `CodeIntegrity` → `Operational` で event 3076 / 3077 / 3091 を確認してください。block された署名の Issuer / Subject / Thumbprint がご自身の自己署名証明書と一致するはずです。一致しない場合、WDAC policy が正しく deploy されていません。`CiTool -lp` で active policy を listing して確認してください。

### "AMD ドライバが install されたのに Device Manager にはまだ MS 汎用が表示される"

`pnputil /scan-devices` で再 enumeration を強制してください。それでも MS にバインドされたままであれば、パッチ済み INF の HWID がデバイスの PNP ID と完全一致していない可能性があります。V06 セクション 2 ("WILL be replaced" / "have no patched INF") を確認してください。デバイスが後者のカテゴリに入る場合、パッチ済みドライバが当該 HWID を claim していないということで、これは一部のデバイス (USB hub、汎用 xHCI controller 等) では想定通りの挙動です。

### "I02 で 'Converting XML to .cip binary...' から 'Deployed:' まで 60 秒以上 hang する"

**r57 / r25 / r6 より前のリビジョンのみ。** CiTool.exe を `--json` フラグなしで呼び出していたため、 console に「続行するには、 Enter キーを押してください」を表示して stdin 入力を待ち、 script が hang していました。 active console window で ENTER を押下すると進行を再開します。 これはチップセット r59 / グラフィックス r27 / NPU r9 で修正済みで、 すべての CiTool.exe 呼び出しに `--json` を付与しました。 これは Microsoft の CiTool 設計における正規の非対話モードフラグで、 ヘルプ出力にも「出力を json として書式設定し、 入力を抑制する」と明記されています。 スクリプトをアップグレードすれば hang は発生しなくなります。 根本原因の解析と検証は SPEC §D.16 を参照してください。

### "CiTool ログ行が '蜃ｦ逅・・謌仙粥縺励∪縺励◆' のような文字化けで表示される"

**r57 / r25 / r6 より前のリビジョンのみ。** これは「処理が成功しました」 という UTF-8 バイト列を cp932 (Shift-JIS) として解釈した結果の文字化けです。 CiTool.exe は stdout に UTF-8 を書きますが、 PowerShell はそれを ja-JP の規定値である `[Console]::OutputEncoding` (cp932) でデコードしてしまいました。 SPEC §A.5 / §D.5 では P00 での UTF-8 強制が規定されていましたが、 実装が抜けていました。 チップセット r59 / グラフィックス r27 / NPU r9 にて、 P00 内の `Set-ConsoleUtf8` で修正されています。 詳細は SPEC §D.16 を参照してください。

### "同一の Install 実行で I03 が '3 failed' と報告するが I04 では 'Failed: 0' になる"

**r57 / r25 より前のリビジョンのみ。** I03 の分類ロジックは pnputil `exit=259` (`ERROR_NO_MORE_ITEMS`) を failure として扱っていましたが、 I04 PostInstallVerification は実際のデバイス状態を読んで、 これらを `REBOOT_NEEDED` (同じ INF を別パスから呼び出した最初の install で binding が既に queue されている場合) または no-op (ドライバパッケージが driver store に既に存在) として正しく識別していました。 exit=259 のケースは、 通常は重複ソースの INF (例: `Chipset_Software\SMBus Driver\W11x64\SMBUSamd.inf` と `SMBus Driver\W11x64\SMBUSamd.inf` の両方を I03 が呼び出し、 2 回目で 259 が返る) によるものです。 チップセット r57 / グラフィックス r25 で修正済み: 新しい I03 サマリーは `ok` / `need reboot` / `no-op` / `failed` の 4 カテゴリを報告し、 exit=259 は新しい `no-op (already present)` ステータス (Write-Skip / DarkGray) にマップされます。 詳細は SPEC §D.17 を参照してください。

### NPU スクリプト "I04 でデバイスは bind されたが Ryzen AI Software が initialize しない"

これは Windows Server 2025 上での想定通りの挙動です。kernel-mode driver は load しますが、Ryzen AI Software user-mode stack (Python conda env、ONNX Runtime VitisAI EP、OGA) は AMD 公式に Windows 11 only です。Server 2025 上で AI ワークロード機能性を期待しないでください。次のいずれかにしてください:

- 実際の NPU 推論ワークロードには Windows 11 24H2 を使用する。
- Server 2025 への install は kernel driver bring-up のみと位置付ける (lab / 研究)。

---

## 開発ツール

### `psa.py` — PowerShell 静的解析ツール

PowerShell パイプラインスクリプトの検証に利用する PowerShell 静的解析ツール `psa.py` は、 **単一の正本 (canonical artifact)** として別レポジトリ [`usui-tk/ai-generated-artifacts`](https://github.com/usui-tk/ai-generated-artifacts) の [`scripts/python/powershell-static-analyzer/`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer) で管理しています。 本レポジトリにはローカルコピーを同梱**していません**。 利用前に以下のいずれかの方法で `psa.py` を取得してください。

PowerShell の通常 parser では検出しにくい誤りをチェックする、シングルファイルの Python 3 静的解析ツールです。

#### `psa.py` の取得方法

**方法 1 — 正本レポジトリを clone する (継続的な開発で推奨)**

```bash
# 本レポジトリと並列のディレクトリに clone
git clone https://github.com/usui-tk/ai-generated-artifacts.git ../ai-generated-artifacts

# 本レポジトリのルートから実行
python3 ../ai-generated-artifacts/scripts/python/powershell-static-analyzer/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 ../ai-generated-artifacts/scripts/python/powershell-static-analyzer/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
python3 ../ai-generated-artifacts/scripts/python/powershell-static-analyzer/psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
```

**方法 2 — 単一ファイルをダウンロードする (one-shot な CI 実行で推奨)**

Linux / macOS (curl):

```bash
curl -sSLO https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py
python3 psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
```

Windows PowerShell (Invoke-WebRequest):

```powershell
Invoke-WebRequest `
    -Uri  "https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py" `
    -OutFile psa.py
python3 psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
python3 psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1
```

本ドキュメントおよび `SPEC.md` / `TESTING.md` / `CONTRIBUTING.md` における `python3 psa.py <script>.ps1` 形式のコマンドは、 上記の方法 1 もしくは方法 2 で `psa.py` を取得済みで、 任意のパスからアクセス可能であることを前提としています。

#### 実施チェック

`psa.py` v3.2.0 は `PSA1001`〜`PSA9002` の汎用ルールに加え、 プロジェクト・パイプライン規約ルール `PSAP0001`〜`PSAP0002` を含む **34 ルール体系** を 9 カテゴリに分けて実装しています:

| カテゴリ                                | コード範囲                | 例                                                                                                                                                                                                                                              |
| --------------------------------------- | ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 構文の整合性                            | `PSA1001`〜`PSA1003`      | 中括弧 / 丸括弧 / 角括弧のバランス                                                                                                                                                                                                              |
| 意味解析                                | `PSA2001`〜`PSA2006`      | 未定義変数、 自動変数の shadowing、 bare `$variable` に対する `-match`、 `$null` を `-eq`/`-ne` の右辺に置く問題、 条件式内の代入 / リダイレクト                                                                                                |
| コーディングパターン                    | `PSA3001`〜`PSA3005`      | `Start-Process -ArgumentList`、 空行直前の trailing backtick、 空文字列に対する `-match`、 空 `catch` ブロック、 **3.2.0 新規:** `Start-Transcript -Path` ではなく `-LiteralPath` を使うべき                                                    |
| 衛生                                    | `PSA4001`〜`PSA4004`      | 未完了マーカー (TODO / FIXME / XXX / HACK)、 行末空白、 長い行、 行末セミコロン                                                                                                                                                                 |
| セキュリティ                            | `PSA5001`〜`PSA5004`      | 平文パスワードパラメーター、 `Invoke-Expression`、 壊れたハッシュアルゴリズム、 `ComputerName` ハードコード                                                                                                                                     |
| ベストプラクティス                      | `PSA6001`〜`PSA6006`      | 非承認動詞、 コマンドレットエイリアス、 複数形名詞の関数名、 `$global:` 定義、 必須パラメーターのデフォルト値、 `$true` がデフォルトのスイッチパラメーター                                                                                      |
| ファイルフォーマット                    | `PSA7001`                 | `.ps1` の UTF-8 BOM 欠落 (BOM が無いと Windows PowerShell 5.1 ja-JP は Shift-JIS / cp932 にフォールバック)                                                                                                                                      |
| **新規: ファイル間整合性**              | `PSA8001`                 | 同一スキャン対象内における function body のハッシュ drift 検出 — 共有ヘルパー関数 (`Format-Elapsed`、 `Write-Detail`、 `Start-DebugTrace` ファミリ等) が 4 つのパイプラインスクリプト間で byte レベルで同期しつづけることを enforce              |
| **新規: 複雑度メトリクス**              | `PSA9001`〜`PSA9002`      | 関数行数の閾値超過 (デフォルト OFF、 `max_function_lines` で調整可)、 `$LASTEXITCODE` チェック無しの外部プロセス呼出し (デフォルト OFF)                                                                                                          |
| **新規: プロジェクト・パイプライン規約** | `PSAP0001`〜`PSAP0002`    | phase 関数命名規約 (`Invoke-(Prep\|Verify\|Inst)PhaseNN_Name`)、 必須スクリプト識別子変数 (`$Script:ScriptVersion` / `$Script:ScriptHash` / `$Script:ScriptShortTag`) の存在。 **PSAPxxxx ルールはすべてデフォルト OFF**; `.psa.config.json` で opt-in する |

各ルールの正規仕様は、[ai-generated-artifacts](https://github.com/usui-tk/ai-generated-artifacts) レポジトリの [`scripts/python/powershell-static-analyzer/SPEC.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/python/powershell-static-analyzer/SPEC.md) §4 (英語のみ) を参照。

#### 本レポジトリ専用の `.psa.config.json`

本レポジトリではルート直下に専用の `.psa.config.json` を同梱しています。 これは **4 つのパイプラインスクリプトに対する正規の設定** であり、 以下 3 点を実施します:

1. **`PSAP0001` および `PSAP0002` を opt-in**。 21 phase 命名規約 (`Invoke-(Prep|Verify|Inst)PhaseNN_DescriptiveName`) およびスクリプト識別子の三連 (`$Script:ScriptVersion` / `ScriptHash` / `ScriptShortTag`) の存在を強制。

2. **`PSA8001` (ファイル間 function body drift) の設定**。 `psa8001_ignore_functions` でスクリプト固有な関数 (phase 関数 (regex 一括)、 各ドライバファミリ固有のヘルパー、 `Show-Help` 等) 約 45 個を除外。 ここに記載されていない共有ヘルパーは 4 スクリプト間で byte 一致が必須。

3. **`PSA4003` (長い行) を無効化**。 パイプラインスクリプトは意図的に多句 `-f` フォーマット文字列 (Show-PowerShellEnvironment テーブル、 デバイス別 AS-IS / TO-BE 解析テーブル) を使用しており、 出力可読性のため 120 桁超過を許容しています。

4 つのスクリプトに対する正規の静的解析実行コマンドは下記のとおりです:

```bash
# レポジトリルートから (psa.py は方法 1 または 2 で取得済みであること)
python3 path/to/psa.py --config ./.psa.config.json \
    Deploy-AMDChipsetDriverOnWindowsServer.ps1 \
    Deploy-AMDGraphicsDriverOnWindowsServer.ps1 \
    Deploy-AMDNpuDriverOnWindowsServer.ps1 \
    Deploy-MSBthPanInboxOnWindowsServer.ps1
```

PSA8001 のファイル間解析を動作させるため、 4 つのスクリプトはすべて単一の `psa.py` 呼出しで渡す必要があります (1 ファイルだけ渡しても、 比較対象のピアが居ないため PSA8001 は何も emit しません)。 r60 / r28 / r10 / r10 時点でのベースラインは **0 errors / 0 warnings / 0 info**。

終了コード: `0` = clean、 `1` = warnings のみ、 `2` = errors。 CI で利用可能:

```yaml
# .github/workflows/lint.yml の例 (方法 2 — 単一ファイル DL 方式)
- name: Fetch psa.py from canonical repository
  run: |
    curl -sSLO https://raw.githubusercontent.com/usui-tk/ai-generated-artifacts/main/scripts/python/powershell-static-analyzer/psa.py
- name: Static-analyze PowerShell scripts
  run: |
    python3 psa.py --config ./.psa.config.json \
        Deploy-AMDChipsetDriverOnWindowsServer.ps1 \
        Deploy-AMDGraphicsDriverOnWindowsServer.ps1 \
        Deploy-AMDNpuDriverOnWindowsServer.ps1 \
        Deploy-MSBthPanInboxOnWindowsServer.ps1
```

設計上の根拠、 出力フォーマットの詳細、 CI 統合例の拡張版は、 正本側の README [`scripts/python/powershell-static-analyzer/README.md`](https://github.com/usui-tk/ai-generated-artifacts/blob/main/scripts/python/powershell-static-analyzer/README.md) (リポジトリ: [ai-generated-artifacts](https://github.com/usui-tk/ai-generated-artifacts)) を参照してください。

---

## 開発者向け仕様書

phase アーキテクチャのルール、 banner / log の規約、 パラメータ命名規約、 CSV / JSONL 出力フォーマット、 path-handling ルール (`-LiteralPath`)、 `psa.py` が enforce する品質ゲート — これら開発者向けの完全な仕様書は以下を参照してください:

- [**SPEC.md**](./SPEC.md) — 開発者向け仕様書 (本コードベースの拡張やコントリビューション、 AI アシスタント連携の authoritative reference)。 リポジトリ共通のドキュメント言語ポリシー (SPEC.md §A.12 参照) により **英語のみ** で維持されています。

`SPEC.md` は 3 つの Part 構成です:

- **Part A — 共通仕様。** 4 スクリプト共通のルール (phase アーキテクチャ、 banner / log マーカー、 パラメータ規約、 エラーハンドリング、 CSV カラム規約、 path-handling ルール)。 既存スクリプトを拡張する場合や 5 番目のスクリプトを追加する場合は、 まずここを読んでください。
- **Part B — スクリプト固有仕様。** Chipset / Graphics / NPU 各スクリプトのユニークな platform 検出ロジック、 INF inventory filter、 インストーラソース解決の tier 構成、 既知の platform 固有挙動を、 1 スクリプトにつき 1 セクションで documentation。
- **Part C — 品質ゲートと教訓。** `psa.py` のチェック項目、 `TESTING.md` がカバーする回帰テスト、 現実装に焼き込まれている historical fix (例: chipset r46 の timezone 起因 DriverDate 誤検知) のリスト。

新機能を追加する際の推奨ワークフローは: `SPEC.md` を読む → 対象スクリプトの既存 `Invoke-*Phase*_*` 関数を読む → 変更を加える → `python3 psa.py <script>.ps1` を実行 (取得方法は [開発ツール](#開発ツール) を参照) → 新規回帰シナリオがあれば `TESTING.md` を更新、 です。

---

## ファイルエンコーディング

### PowerShell スクリプト (`*.ps1`)

本リポジトリ内の `*.ps1` ファイルは、 すべてのプラットフォームで **UTF-8 with BOM + CRLF 改行で checkout される**よう設定されています。 これは非 ASCII 文字 (`Write-Skip` / `Write-Warn2` 等の呼び出しに含まれる日本語ログ文字列) を含む PowerShell 5.1 + 7.x スクリプトの正規エンコーディングです。 これを強制する `.gitattributes` のルール:

```
*.ps1 text working-tree-encoding=UTF-8 eol=crlf
```

git 内部ストレージの補足: git は commit 時に標準的なテキスト正規化を適用します。 リポジトリ内の blob には **BOM + LF** (改行を LF に正規化) として保存され、 `git clone` / `git checkout` 時には `.gitattributes` の `eol=crlf` ディレクティブによって LF が CRLF に再変換されます。 結果として、 ディスク上のファイルは **BOM + CRLF** となり、 これは Windows PowerShell が期待する形式です。 BOM は両形式でコンテンツバイトとして保持されます。

**Raw ダウンロードに関する注意**: GitHub の「Raw」ボタンや `curl https://raw.githubusercontent.com/.../*.ps1` で `.ps1` ファイルを直接ダウンロードする場合、 受け取るのは blob 形式そのまま (**BOM + LF**) です — git の checkout 時変換は raw blob ダウンロードには適用されません。 PowerShell 5.1 / 7.x はスクリプト内の LF と CRLF を共に正しく扱うため、 ファイル自体は正常に実行されますが、 正規形式 (BOM + CRLF) が必要な場合は個別の raw ファイルダウンロードではなくリポジトリのクローンを行ってください。 実用上の推奨:

- **Windows 上で実行する場合**: リポジトリをクローン (`git clone https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer.git`)。 右クリック → 「Save raw as」での個別ダウンロードは避ける。
- **内容確認やクイックパッチ用途**: raw ダウンロードで OK。 PowerShell は LF 改行を許容します。
- **再公開・ミラーする場合**: スクリプトを別の場所で再ホストする際は、 正規形式と一致するよう BOM + CRLF で再生成してください。

### Markdown ドキュメント (`*.md`)

`*.md` ファイル全般 (`README.md`、 `README.ja.md`、 `TESTING.md`、 `SPEC.md`、 `CHANGELOG.md`、 `CONTRIBUTING.md`、 `SECURITY.md`、 `CODE_OF_CONDUCT.md`) は **UTF-8 without BOM** で **LF** 改行を使用 — GitHub ネイティブの Markdown レンダリング規約に合わせています。 `.gitattributes` のルール:

```
*.md text eol=lf
```

Windows のエディタが `.md` ファイルに自動で BOM を挿入する場合 (一部の古い Notepad++ など) は、 commit 前に BOM を除去するか、 `.gitattributes` の正規化に任せて次回 checkout 時に解消してください。

### コンソール出力と日本語ログ文字列

`.ps1` スクリプト内の日本語ログ文字列は、 UTF-8 (`chcp 65001`) に設定された ja-JP Windows コンソールで正しくレンダリングされるよう設計されています。 コンソールが ja-JP のデフォルトコードページ (932 / Shift-JIS) のままだと日本語が文字化けする可能性があります。 スクリプトは P00 で `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8` を呼び出してこれを強制しますが、 `*>&1 | Tee-Object` 等で出力をファイルへリダイレクトする場合は、 二重エンコーディングを避けるためファイルエンコーディングを明示的に UTF-8 に設定してください。

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
- [AMD Ryzen AI Software (インストールガイド)](https://ryzenai.docs.amd.com/en/latest/inst.html)
- [AMD Ryzen AI Software (リリースノート)](https://ryzenai.docs.amd.com/en/latest/relnotes.html)
- [AMD Ryzen AI Software (サポート構成)](https://ryzenai.docs.amd.com/en/latest/relnotes.html#supported-configurations)
- [AMD RyzenAI-SW (GitHub examples and source)](https://github.com/amd/RyzenAI-SW)
- [AMD RyzenAI-SW (latest releases)](https://github.com/amd/RyzenAI-SW/releases)

### 本リポジトリ

- [TESTING.md](./TESTING.md) — 物理ハードウェアでの検証結果および NPU スクリプトの極めて限定的な検証状況。 **英語のみ。**
- [SPEC.md](./SPEC.md) — 開発者向け仕様書。 **英語のみ。**
- [CHANGELOG.md](./CHANGELOG.md) — 時系列のリリースノート。 **英語のみ。**
- [CONTRIBUTING.md](./CONTRIBUTING.md) — コントリビューションガイド。
- [README.md](./README.md) — 英語版本ドキュメント (マスター)。
- [`psa.py` 正本配置場所 (ai-generated-artifacts)](https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer) — 本レポジトリの CI gate で利用する PowerShell 静的解析ツール。

---

## ライセンス

[MIT License](./LICENSE)。Copyright (c) 2026 contributors。

MIT ライセンスは **本リポジトリの PowerShell スクリプトおよび付属ドキュメントのみに適用**されます。スクリプトは実行時に AMD installer EXE / Ryzen AI ドライバ ZIP をダウンロードしますが、AMD のバイナリ・INF・catalog を再配布はしていません。これらのファイルには AMD の再配布規約が独立に適用されます。

---

## コントリビューション

Issue テンプレート、PR ガイドライン、regression test 実行手順 (`psa.py` の使い方含む) は [CONTRIBUTING.md](./CONTRIBUTING.md) を参照してください。

Issue・Pull Request は以下で受け付けています: <https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer>

その他のコミュニティドキュメント:

- [`CODE_OF_CONDUCT.md`](./CODE_OF_CONDUCT.md) — Issue・Pull Request・Security Advisory でやり取りする際に期待される行動規範。 自己署名カーネルモードドライバの安全性への影響を踏まえた内容になっています
- [`SECURITY.md`](./SECURITY.md) — セキュリティに影響する欠陥 (ドライバ署名の欠陥、 WDAC policy scope エラー、 認証情報露出 等) の報告方法。 **公開 Issue として起票しないでください** — プライベートな Security Advisory チャネルを利用してください
- [`CHANGELOG.md`](./CHANGELOG.md) — 時系列のリリースノート（英語版のみ、 r1 以降のすべてのリビジョン）
