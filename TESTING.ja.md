# TESTING.ja.md — 物理ハードウェア検証結果

本ドキュメントは `Deploy-AMD-Drivers-For-WindowsServer` の検証結果を集約したものです。本レポジトリは **AMD のコンシューマー向け Ryzen チップセット / Radeon iGPU / Ryzen AI NPU をターゲットとした実験的スクリプト** を公開しているため、意味のある検証は対象 AMD コンシューマー向けハードウェアへの物理アクセスに依存します。AMD コンシューマー向け以外のハードウェア (サーバー級 EPYC、ARM、Intel、対象デバイスが存在しない仮想マシンなど) でのテストでは、本パイプラインが本来検証すべきデバイスバインド・ドライバアップグレード・post-install verification の経路を一切実行できません。したがって本ドキュメントは物理ハードウェア検証のみを取り扱います:

1. **検証結果 1: ThinkCentre M75q Tiny Gen 2** (Windows Server 2025 物理機 / Cezanne Zen 3 — チップセット・グラフィックス検証済み)
2. **検証結果 2: ThinkPad X13 Gen 1 AMD (2020)** (Windows 11 Enterprise LTSC 2024 / Renoir Zen 2 — チップセット・グラフィックス検証済み)
3. **検証結果 3 (NPU スクリプト)** — **🆘 物理 NPU ハードウェアでの検証は未実施。現状の限定的な検証状況については [§3](#3-検証結果-3-npu-スクリプト--現時点で未検証) を参照してください。**

🇬🇧 **English version: see [TESTING.md](./TESTING.md).**

---

## 0. 検証ステータスサマリ

> セクション 1〜3 を読む前にこのセクションを必ず確認してください。3 つのスクリプトは **検証成熟度が大きく異なります**。

| スクリプト | 物理ハードウェア検証 | ターゲット HW 上での実ドライバインストール | 推奨用途 |
|---|---|---|---|
| **Chipset (r56)** | ✓ M75q Tiny Gen 2、X13 Gen 1 AMD (r55 で検証済み; r56 はインストール判定の破壊的変更あり — 下の注記参照) | ✓ M75q (WS2025) でインストール成功 | Lab + 慎重な production |
| **Graphics (r24)** | ✓ M75q Tiny Gen 2、X13 Gen 1 AMD (r23 で検証済み; r24 はインストール判定の破壊的変更あり — 下の注記参照) | ✓ M75q (WS2025) でインストール成功 | Lab + 慎重な production |
| **NPU (r6)** | ❌ **なし** (メンテナーの lab に物理 NPU マシンが存在しない) | ❌ **未実行** | **実験的・研究用途のみ。本番環境への deploy は不可。** |

NPU スクリプトの検証は現時点で以下に限定されています:

1. **静的解析** を `psa.py` v3.1.0 (28 ルール体系 `PSA1001`〜`PSA7001`) で実施 (**errors 0** + warnings / info はベースライン化 — `SPEC.ja.md` §A.11.5 参照)。 `psa.py` は [ai-generated-artifacts](https://github.com/usui-tk/ai-generated-artifacts) レポジトリで canonical artifact として管理されているため、 実行前に `SPEC.ja.md` §A.11 の手順で取得してください。
2. **コードレビュー** — AMD 公開の `quicktest.py` の NPU 検出ロジックを PowerShell に翻訳した実装をレビュー。
3. **`-Action Install` の実行はメンテナーによって一切行われていません。**
4. **物理 NPU ハードウェアでのエンドツーエンド実行はメンテナーによって一切行われていません。**

Ryzen AI 300 / Ryzen AI Max 300 / Ryzen 7040 / 8040 シリーズのマシンをお持ちで、NPU スクリプトのいずれかの phase を実行された場合は、検証ギャップを埋めるため GitHub Issues に結果を報告いただけると幸いです。

---

## 1. 検証結果 1: ThinkCentre M75q Tiny Gen 2 (Windows Server 2025)

### 1.1 ハードウェア仕様

| 項目 | 値 |
|---|---|
| 機種 | Lenovo ThinkCentre M75q Tiny Gen 2 |
| CPU | AMD Ryzen 7 PRO 5750GE (Cezanne、Zen 3、8 core / 16 thread、35 W TDP) |
| iGPU | AMD Radeon Graphics (Vega 8、Cezanne 内蔵) |
| **NPU** | **なし (Cezanne は AMD NPU 登場前。XDNA NPU は Phoenix / 7040 シリーズで初登場)** |
| メモリ | DDR4 SO-DIMM 16〜32 GB |
| ストレージ | M.2 NVMe SSD |
| BIOS | UEFI、Secure Boot 切替可 |
| TPM | fTPM (AMD PSP 経由) |

### 1.2 OS 構成

| 項目 | 値 |
|---|---|
| OS | Windows Server 2025 Standard / Datacenter |
| Build | 26100 |
| ProductType | 3 (Server) |
| Secure Boot | ON |
| HVCI | OS デフォルト (環境による) |
| BitLocker | オプション (有効化する場合は **事前にリカバリキーを保管**) |

### 1.3 検証手順 (chipset + graphics のみ — このホストには NPU 無し)

```powershell
# 管理者権限の PowerShell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Stage 1: PrepareVerify、V06 レビュー (システム未変更)
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\m75q-chipset-prepareverify.log
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\m75q-graphics-prepareverify.log

# Stage 2: V06 リスクが許容できる場合に Install を実行
# 重要: 事前に BitLocker リカバリキーを保管
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Install
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Install

# NPU スクリプト: Cezanne ハードウェアでは適用対象外 (NPU デバイス無し)
# M75q には NPU デバイスが存在しないため、NPU スクリプトは意味のある検証ができない。
```

### 1.4 主要な検証結果

#### Chipset スクリプト

- **P03 検出**: `Cezanne / Zen 3 / Desktop APU、AM4`
- **P03 ダウンロード**: `amd_chipset_software_8.02.18.557.exe` (約 75 MB)
- **P05 inventory**: 67 INF 検出、32 個の W11x64 variant INF を選択
- **P06 patching**: 1 INF パッチ (`AmdMicroPEP.inf`)、31 INF は既に Server 互換でそのまま流す
- **V06 主要アップグレード候補** (実 OEM ドライバベースラインにより変動):
  - AMD GPIO Controller: `oem17.inf v2.2.0.130` → `amdgpio2.inf v2.2.0.136`
  - AMD PSP 10.0 Device: `oem26.inf v5.22.0.0` → `amdpsp.inf v5.43.0.0` (HIGH risk — BitLocker 注意)
  - AMD SMBus: `oem12.inf v5.12.0.38` → `SMBUSamd.inf v5.12.0.44`

#### Graphics スクリプト

- **P03 検出**: `Cezanne APU、Vega-Polaris Legacy ブランチ`
- **P03 ダウンロード**: `whql-amd-software-adrenalin-edition-XX.X.X-win11-XXX-vega-polaris.exe` (約 600 MB)
- **P05 inventory**: 19 INF 検出、`WT64A` (audio) + `WT6A_INF` (display) variant を選択
- **P06 patching**: 1 INF パッチ (`u0197843.inf`)、18 INF は既に Server 互換でそのまま流す
- **V06 主要アップグレード候補**:
  - AMD Audio CoProcessor: `oem70.inf v6.0.0.79` → `amdacpbus.inf v6.0.1.83` (MEDIUM risk)
  - AMD Radeon Graphics: AMD パッケージの新バージョンへ → display アップグレード (MEDIUM risk)
  - AMD HD Audio Device: `oem58.inf v10.0.1.30` → `AtihdWT6.inf v10.0.1.30` (日付のみ新しい、MEDIUM risk)

#### NPU スクリプト

- **このホストでは適用対象外** (Cezanne には NPU 無し)。XDNA NPU デバイスを欠くハードウェア上では、NPU スクリプトを意味的に実行することはできません。

#### 健全性チェック

- 全 21 phase が成功 (chipset + graphics)
- 自己署名証明書 (RSA 4096 / SHA-384、5 年有効) 生成成功
- 32 catalog (chipset) + 19 catalog (graphics) を `inf2cat /os:Server2025_X64` で生成
- 全 catalog が `signtool` でタイムスタンプ署名成功
- I03 (Install) 後、Device Manager で 3 chipset + 3 graphics デバイスが `[C] Self-signed` にバインド

### 1.5 既知の制約

- BitLocker 有効ホストでは PSP ドライバアップグレード時に次回起動でリカバリプロンプトが発生する可能性。**事前に必ずリカバリキーを取得**してください (コントロールパネルの BitLocker UI または Microsoft アカウントバックアップから)。
- 一部の `ROOT\AMD*` ソフトウェア専用エンティティ (AMDLOG / AMDXE 等) は I03 で追加されるが `Win32_PnPSignedDriver` の enumeration には現れません。V06 セクション 1 で「software-only」として情報表示されます。
- インストール成功は I04 で観測される `[B] Vendor` → `[C] Self-signed` 遷移により確認されます。

---

## 2. 検証結果 2: ThinkPad X13 Gen 1 AMD (2020) — Windows 11 Enterprise LTSC 2024

### 2.1 ハードウェア仕様

| 項目 | 値 |
|---|---|
| 機種 | Lenovo ThinkPad X13 Gen 1 (AMD、2020) |
| CPU | AMD Ryzen 5 PRO 4650U (Renoir、Zen 2、6 core / 12 thread、15 W TDP) |
| iGPU | AMD Radeon Graphics (Vega 6、Renoir 内蔵) |
| **NPU** | **なし (Renoir は AMD NPU 登場前)** |
| メモリ | DDR4 16 GB on-board |
| ストレージ | M.2 NVMe SSD |
| BIOS | UEFI、Secure Boot 切替可 |
| TPM | dTPM (Discrete TPM、例: Infineon SLB9670) |

### 2.2 OS 構成 (検証時点)

| 項目 | 値 |
|---|---|
| OS | Microsoft Windows 11 Enterprise LTSC 2024 |
| Build | 26100 (24H2 LTSC) |
| ProductType | 1 (Workstation) — 本スクリプトでは **WS2025 PREVIEW MODE** で動作 |
| Secure Boot | OFF (テストのため一時的に OFF) |
| HVCI | ON |
| BitLocker | OFF (lab 利用) |

### 2.3 検証手順

Windows 11 Enterprise LTSC 2024 は Windows Server 2025 と同じ NT カーネル build 26100 を共有するため、スクリプトは **WS2025 PRE-MIGRATION PREVIEW MODE** で動作します (P00 banner で明示的に通知)。

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Workstation OS では Install 系 phase が自動ブロックされる — PrepareVerify のみ
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\x13gen1-chipset-Win11-preview.log
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\x13gen1-graphics-Win11-preview.log

# NPU スクリプト: 適用対象外 (Renoir に NPU 無し)
```

### 2.4 主要な検証結果

#### P00 OS 検出 (Workstation preview)

```
[+] OS detected: Microsoft Windows 11 Enterprise LTSC (build 26100)
    Profile applied : WS2025 (Windows Server 2025)
    ProductType     : 1  (1=Workstation, 3=Server)

    +-----------------------------------------------------------------+
    | WS2025 PRE-MIGRATION PREVIEW MODE                               |
    | (Windows 11 24H2 and Windows Server 2025 share NT build 26100)  |
    +-----------------------------------------------------------------+
```

Install 系 phase は自動ブロック (`-AllowWorkstationInstall` で override 可能ですが非推奨)。

#### Chipset スクリプト

- **P03 検出**: `Renoir / Zen 2 / Mobile`
- **P03 ダウンロード**: `amd_chipset_software_8.02.18.557.exe` (M75q と同じ)
- **P05 inventory**: 67 INF 検出、32 個の W11x64 variant INF 選択
- **P06 patching**: 1 INF パッチ (`AmdMicroPEP.inf`)
- **V06 主要アップグレード候補** (Win11 OEM ドライバ比):
  - AMD PSP 10.0 Device: `oem144.inf v5.42.0.0` → `amdpsp.inf v5.43.0.0` (HIGH risk)
  - GPIO / I2C / SMBus / MicroPEP — 同バージョン (KEEP)

#### Graphics スクリプト

- **P03 検出**: `Renoir / Vega-Polaris Legacy`
- **P03 ダウンロード**: `whql-amd-software-adrenalin-edition-26.1.1-win11-jan-vega-polaris.exe` (約 624 MB)
- **P05 inventory**: 19 INF 検出、`WT64A` + `WT6A_INF` variant 選択
- **P06 patching**: 1 INF パッチ (`u0197843.inf`)、6 decoration を mirror
- **V06 アップグレード候補**:
  - AMD Audio CoProcessor: `v6.0.0.79 → v6.0.1.83` (実バージョンアップ)
  - AMD Radeon Graphics: `v31.0.21923.11000 → v31.0.21924.61` (実バージョンアップ)
  - AMD HD Audio Device: `v10.0.1.30 → v10.0.1.30` (日付のみ新しい、graphics r16 では「同バージョンだが日付新」と明示表示)

#### 健全性チェック

- 全 21 phase 完走 (Workstation OS のため Install 系 phase は自動ブロック)
- 19 INF 全てがパイプラインを通過
- 19 catalog + 19 signtool 署名が全て成功
- 検出 AMD HW: AMD Audio CoProcessor、AMD Radeon Graphics、AMD HD Audio Device、AMD GPIO Controller、AMD I2C Controller、AMD Micro PEP、AMD SMBus、AMD PSP 10.0 Device 等

### 2.5 同一ハードウェア上での Win11 と WS2025 の期待される差分

検証結果 1 (M75q + WS2025) と検証結果 2 (X13 Gen 1 + Win11 24H2) を比較すると、**両 OS は kernel build 26100 を共有するためスクリプトの判定ロジックは同一**ですが、**既存 OEM ドライバベースラインの差により V06 アップグレード候補数が異なります**:

| V06 セクション | M75q (WS2025) | X13 Gen 1 (Win11) |
|---|---|---|
| 検出 AMD HW | 検出ロジックは同一 (HW トポロジは機種毎に異なる) | 同一 |
| MS-GENERIC 数 | 多い (clean WS2025 は素の Server in-box ドライバのみ) | 少ない (Win11 には OEM ドライバが pre-install 済み) |
| WILL be replaced 数 | 多い (MS generic → AMD vendor 置換が頻発) | 少ない (AMD パッケージが OEM ドライバより新しい場合のみ置換) |
| KEEP (same/newer) 数 | 少ない | 多い |
| Install 推奨実行 | YES (production target) | NO (Workstation OS、自動ブロック) |

つまり、**Win11 24H2 上での PrepareVerify は WS2025 への pre-migration 検証として機能**します。生成されるパッチ済 INF 署名・catalog 構造は WS2025 上でも有効 (kernel build 同一)。実際の install 判定 (どのデバイスが WILL be replaced に入るか) は WS2025 移行後に再確認すべきです。

---

## 3. 検証結果 3 (NPU スクリプト) — 現時点で未検証

> **🆘 このセクションは「未検証である事項」を文書化しています。** 動作する証拠としては解釈しないでください。

### 3.1 NPU スクリプトについて現時点で検証済みの項目

| 検証活動 | ステータス | 根拠 |
|---|---|---|
| `psa.py` v3.1.0 での静的解析 (`SPEC.ja.md` §A.11 参照) | ✅ 完了 | errors 0 / warnings 26 / info 0 — 全件ベースライン化済み (§A.11.5 参照) |
| NPU 検出ロジックのコードレビュー | ✅ 完了 | `Get-AmdNpuPlatform` は AMD 公開の `quicktest.py` を PowerShell に直接ポート |
| 物理 NPU マシンでの検出 | ❌ **未実施** | 本ドキュメント作成時点でメンテナーの lab に物理 NPU ハードウェアが無い |
| 実 NPU ドライバ ZIP の INF パース | ❌ **未実施** | NPU ドライバ ZIP (`NPU_RAI*_WHQL.zip`) は EULA gate のため、メンテナーは全 RAI バージョンの INF 構造を検証済みのコピーで保有していない |
| 物理 NPU マシンでの `-Action Install` | ❌ **未実施** | 同上 |
| Post-install での `[C] Self-signed` バインド確認 | ❌ **未実施** | 同上 |
| AMD アカウント自動ダウンロード (Tier 2) | ⚠️ **best-effort、不安定** | 公開フォーム構造観察を元に実装。AMD のフォーム変更で予告なく破綻する可能性 |
| Windows Server 2025 上の Ryzen AI Software user-mode stack | ❌ **AMD 公式に未サポート** | AMD ドキュメントにて Windows 11 24H2 (build >= 22621.3527) のみと明記 |

> **検証範囲についての注記**: 本 NPU スクリプトの検証は、物理 Ryzen AI ハードウェアへのアクセスという根本的なボトルネックに制約されています。本スクリプトは AMD のコンシューマー向け NPU シリコンを対象とした実験的ツールであるため、対象 NPU デバイスを欠くハードウェア上ではエンドツーエンドな検証は一切実施できません。完了している検証活動は静的解析とコードレビューのみであり、実際のデバイスバインド挙動・実 ZIP の INF パース・post-install verification に依存する全ての検証は、物理 NPU マシンが利用可能になるまで pending です。

### 3.2 検証ギャップ (NPU スクリプトを production-ready 扱いする前に行うべきこと)

1. **Ryzen AI ハードウェアテストフィクスチャの取得。** 候補:
   - **ThinkPad T14s Gen 6 AMD** (Ryzen AI 7 PRO 360 / Strix Point) — Lenovo の小売経由で入手可能。
   - **ASUS ProArt P16** (Ryzen AI 9 HX 370) — Strix Point with NPU 有効化済み。
   - **HP OmniBook Ultra Flip 14** (Ryzen AI 9 HX 375) — Strix Point。
   - **Ryzen AI Max 300 搭載 mini-PC** — 2026 年時点では入手性が限定的。

2. **フィクスチャ上で `-Action PrepareVerify` を 4 つのダウンロード Tier 全てで実行**:
   - Tier 1: 事前取得済みの `entitlenow.com` URL。
   - Tier 2: `-AmdAccountUser` / `-AmdAccountPassword` を実 AMD アカウントで実行。フォームパース regex を確認・調整。
   - Tier 3: AMD EULA URL probe (フォールスルー想定。AMD が将来この経路を simplify した場合は記録)。
   - Tier 4: `-OfflineZip` を RAI 1.5 / 1.6.1 / 1.7 / 1.7.1 の手動ダウンロード ZIP で実行。

3. **フィクスチャ上で `-Action Install` を推奨ワークフローで実行**:
   - 前後で `Get-CimInstance Win32_PnPSignedDriver` を取得・比較。
   - NPU デバイスの `[B] Vendor` → `[C] Self-signed` 遷移を確認。
   - `Task Manager → Performance → NPU0` でデバイス表示を確認。
   - `pnputil /enum-drivers` でパッチ済 INF が自己署名証明書下に表示されることを確認。

4. **失敗モードを文書化**:
   - Server 2025 で NPU kernel driver が実際に load するか? (AMD ドキュメントによれば user-mode stack は動作しないが、本スクリプトの focus である kernel driver 自体はどうか)
   - Cleanup が driver store からドライバを実際に削除するか、それとも `pnputil /delete-driver oemNN.inf /force` の手動実行が必要か?
   - WDAC が予期せず何かをブロックした場合に `CodeIntegrity / Operational` イベントログにどのようなエントリが出るか?

### 3.3 推奨される実行パターンと 4-tier 評価

`Resolve-AmdNpuDriverUrl` (スクリプト 772 行目) の 4-tier URL resolution が P03 の NPU ドライバ ZIP 取得方法を制御します。挙動は **全てのパラメータ組合せで対称ではない**ため、各実行パターンの実際の結果を以下の表に文書化しています。実行計画時の参照に活用してください。

| # | 実行コマンド | 結果 | 4-tier resolver の経由経路 |
|---|---|---|---|
| 1 | `-Action PrepareVerify -CleanWorkRoot -OfflineZip <path>` | ✅ **初回 dry-run の推奨パターン。** | T4 priority block (824 行目) → ZIP がワークスペースにコピー → P03 成功 |
| 2 | `-Action PrepareVerify -CleanWorkRoot -OfflineZip <path> -AssumeIfMissing` | ⚠️ **パイプライン健全性のチェックのみ — 実 NPU 挙動は検証されない。** | #1 と同じ + NPU 未検出時に default Strix Point profile で続行 |
| 3 | `-Action PrepareVerify -CleanWorkRoot` (`-OfflineZip` 無し) | ⚠️ **クリーン環境では失敗する可能性大。** | T1 skip → T4 priority skip → T2 skip → T3 フォールスルー (HTML フォーム) → T4 auto-scan (スクリプトディレクトリ・./cache・workspace・~/Downloads) → 何も見つからなければ throw |
| 4 | `-Action Install -OfflineZip <path>` | ✅ **実機 NPU インストールの推奨パターン。** | T4 priority block → I00 で "I AGREE" 入力 → I01-I04 |
| 5 | `-Action Install -AmdAccountUser ... -AmdAccountPassword ...` | ⚠️ **best-effort。AMD のフォーム変更で予告なく破綻する可能性。** | T1 skip → T4 priority skip → T2 認証付きダウンロード試行 → 失敗時 T3/T4 にフォールバック |
| 6 | `-Action Install -InstallerUrl <captured-url>` | ✅ URL が fresh であれば動作 (entitlenow.com URL は時間経過で失効)。 | T1 直接ダウンロード → P03 成功 |
| 7 | `-Action Install -NpuOverride STX -NpuDriverPackage NPU_RAI1.6.1_314` (ソース無し) | ❌ **誤解を招くため使用しないこと。** | T1/T2/T3 skip → T4 auto-scan が `~/Downloads` 内の任意の `NPU_RAI*_WHQL.zip` を拾う (override 指定と一致するとは限らない) |

**パターン #1 (`PrepareVerify` + `OfflineZip`) が最も強く推奨される理由**:

- **決定論的**: 824 行目の Tier 4 priority block で resolver が即座に短絡判定。AMD へのネットワーク呼び出し無し、フォーム解析の脆弱性無し、EULA URL 失効との競合無し。
- **システム未変更**: `PrepareVerify` は P00–P09 + V01–V06 のみ実行。証明書 import 無し、WDAC policy deploy 無し、ドライバインストール無し。
- **ホスト間で再現性あり**: 同じ ZIP を別マシンにコピーすれば、同じ P05/P06/V05/V06 出力が得られる。CI 回帰テストに必須。
- **V05/V06 出力が取得可能**: ホストに NPU デバイスが存在しない場合でも (検出失敗を回避するため `-AssumeIfMissing` が必要) 、dry-run install plan と hardware impact analysis が出力されます。

**よくある落とし穴 — パターン #7**: `-NpuOverride`、`-NpuDriverPackage`、`-RyzenAiSoftwareVersion` といったスイッチは *resolver の挙動を変更するだけで、ダウンロードソースは提供しません*。`-OfflineZip` / `-InstallerUrl` / `-AmdAccountUser` を併用しないとリゾルバは Tier 4 auto-scan にフォールスルーします。auto-scan は最初に発見した `NPU_RAI*_WHQL.zip` を拾うため、その ZIP が **指定した codename / バージョンと一致するとは限りません**。バージョンチェックは ZIP 内の INF (P05) で行われ、ファイル名では判定されません。**常にソースを明示的に固定してください**。

### 3.4 NPU スクリプトを実行する前のチェックリスト

上記ギャップが埋まる前であっても、**任意のホスト**で NPU スクリプトを実行する前に以下のチェックリストに従ってください:

- [ ] README の [§ リスク分類](./README.ja.md#3-スクリプトのリスク分類) を読了済み。
- [ ] Ryzen AI 300 / Ryzen AI Max 300 / Ryzen 7040 / 8040 シリーズの CPU を持っている (もしくは検出が `-AssumeIfMissing` にフォールスルーすることを認識し、その実行がパイプライン健全性チェックのみであることを了承済み)。
- [ ] 適切な `NPU_RAI*_WHQL.zip` を <https://ryzenai.docs.amd.com/en/latest/inst.html#install-npu-drivers> からダウンロードし、スクリプト隣に配置済み (Tier 4 — 推奨)。
- [ ] AMD の Ryzen AI EULA を <https://account.amd.com/en/forms/downloads/ryzenai-eula-public-xef.html> で読了し受諾済み。
- [ ] Ryzen AI Software user-mode stack が AMD 公式に Windows 11 only であり、**Server 2025 では AI 推論ができない**ことを理解済み。
- [ ] `-Action Install` を実行する場合: `-Action Cleanup` でロールバック可能であることを確認済み (driver store 削除に手動介入が必要となる可能性も了承済み)。
- [ ] BitLocker 有効ホストで実行する場合: リカバリキー取得済み。
- [ ] 成功・失敗のいずれの場合も結果を GitHub Issues に報告する意思がある (特に失敗の場合 — メンテナーは検証ギャップを埋めるためにこのデータを必要としている)。

### 3.5 期待される NPU スクリプト出力

以下はスクリプトが正常動作する場合に期待される出力です。これと異なる場合は問題が発生しています。

#### P00 NPU OS-support warning

```
-------------------------------------------------------------------------
 Ryzen AI Software OS support note
-------------------------------------------------------------------------
[!] AMD officially supports Ryzen AI Software ONLY on Windows 11 (build >= 22621.3527).
[!] Windows Server 2025 is NOT in AMD's supported OS matrix.
[!] This script patches the kernel-mode NPU driver to install on Server, but the
[!] user-mode Ryzen AI Software stack (conda env, OGA, Vitis AI EP) will likely
[!] not function on Server 2025 without unofficial workarounds.
```

#### P03 NPU 検出 (実 Strix Point ホスト)

```
[>] Enumerating PCI devices via pnputil /enum-devices /bus PCI /deviceids
[+] CPU              : AMD Ryzen AI 9 HX 370 w/ Radeon 890M
[+] NPU codename     : Strix Point / Strix Halo
[+] NPU short name   : STX
[+] Hardware ID      : PCI\VEN_1022&DEV_17F0&REV_00
[+] Detection source : pnputil
[+] Detected on host : True
[+] Preferred RAI ver: 1.7.1
[+] Recommended drv  : 32.0.203.380
```

#### P03 NPU 検出 (NPU 不在ホスト、`-AssumeIfMissing` 付き)

```
[>] Enumerating PCI devices via pnputil /enum-devices /bus PCI /deviceids
[!] No AMD NPU detected via pnputil. Using default profile (Strix Point + RAI 1.7.1).
[+] CPU              : (ホストの CPU - NPU 無し)
[+] NPU codename     : Strix Point (default - no NPU detected)
[+] NPU short name   : STX
[+] Detection source : default-strix-rai1.7.1
[+] Detected on host : False
```

続いて:

```
------------------------------------------------------------------
[!] NPU was NOT detected on the host (proceeding with default profile).
[!] Driver Install (I03) will likely produce 0 device bindings here.
[!] This run is useful for pipeline regression testing only.
------------------------------------------------------------------
```

#### I00 EULA 受諾確認 (Install 時のみ)

```
+----------------------------------------------------------------+
| AMD RYZEN AI EULA ACCEPTANCE REQUIRED BEFORE INSTALL           |
+----------------------------------------------------------------+
| By proceeding, you confirm:                                    |
| 1. You have accepted the Ryzen AI EULA at:                     |
|    https://account.amd.com/en/forms/downloads/                 |
|    ryzenai-eula-public-xef.html                                |
| 2. You acknowledge Windows Server 2025 is NOT officially       |
|    supported by AMD for Ryzen AI Software (Windows 11 only).   |
| 3. You understand the kernel-mode driver alone does not        |
|    enable AI inference; Ryzen AI SW must be installed manually.|
| 4. You have BitLocker recovery keys recorded if applicable.    |
+----------------------------------------------------------------+

Type "I AGREE" exactly to proceed with install (anything else aborts):
```

#### Install 後: Ryzen AI Software guidance バナー

```
+================================================================+
| RYZEN AI SOFTWARE (USER-MODE STACK) - INSTALL THIS SEPARATELY |
+================================================================+

This script installed the kernel-mode NPU driver only.
To actually use the NPU for AI inference, install Ryzen AI Software:

  Detected NPU codename : STX
  Recommended RAI ver   : 1.7.1

  PREREQUISITES (per AMD documentation):
    1. Windows 11 build >= 22621.3527 (NOT supported on Server 2025!)
    2. Visual Studio 2022 (with Desktop Development with C++)
    3. cmake >= 3.26
    4. Miniforge (Python distribution); add condabin/Scripts to PATH

  INSTALLATION STEPS:
    1. Download Ryzen AI installer:
       https://account.amd.com/en/forms/downloads/xef.html
       Filename: ryzen-ai-lt-1.7.1.exe
    2. Launch the EXE installer (run as Administrator)...
    3. Verify the install (Miniforge Prompt):
         conda activate ryzen-ai-1.7.1
         cd %RYZEN_AI_INSTALLATION_PATH%\quicktest
         python quicktest.py
```

### 3.6 Tier 2 (AMD アカウント認証フロー) 動作確認結果 — 2026-05-10

`Deploy-AMDNpuDriverOnWindowsServer.ps1` 内の `Invoke-AmdAccountAuthentication` 関数について、現状の `account.amd.com` バックエンドに対して実装済みの HTTP form POST フローが成功しうるかどうかを **2026-05-10** に検証しました。検証は公開情報のみを利用しています (実 AMD アカウント資格情報は使用していません)。

#### 3.6.1 検証手法

| Step | 確認項目 | 方法 |
|---|---|---|
| 1 | `account.amd.com` のレンダリングモデル | 関連 AMD ポータル (`docs.amd.com/auth/login`、`pensandosupport.amd.com`、`fsdz.amd.com`) を web fetch |
| 2 | 現状の AMD docs における EULA URL パターン | GitHub `amd/ryzen-ai-documentation/blob/main/docs/inst.rst` (最新コミット) |
| 3 | ドライババージョン命名規則 | `ryzenai.docs.amd.com` 上の RAI 1.5 / 1.6.1 / 1.7 / 1.7.1 ドキュメント間のクロスチェック |
| 4 | EULA フローのエンドユーザー挙動 | GitHub `amd/RyzenAI-SW#249`、`#328`、cnx-software.com エンドユーザーブログ記事 (Feb 2024) |
| 5 | 公開されている PowerShell/Python 自動化の有無 | `account.amd.com` 自動化、AMD アカウントダウンロードスクリプティングに関する Web 検索 |

#### 3.6.2 検出事項

| # | 検出事項 | 重大度 | 根拠 |
|---|---|---|---|
| F1 | **`account.amd.com` は JavaScript-driven SPA**。関連 AMD ポータルは直接 fetch すると `"JavaScript is required"` または `"Loading application"` HTML stub を返却。 | 高 | `docs.amd.com/auth/login` および `fsdz.amd.com/adfs/ls/...` の直接プローブ |
| F2 | **ログインフォームは初期 HTML payload に存在しない**。CSRF トークン、フォームアクション、フィールドはランタイムに JavaScript で注入される模様。 | 高 | F1 から、ログインフォームがクライアントサイドレンダリングされていることが導かれる |
| F3 | **EULA 受諾はインタラクティブ**。エンドユーザー証言「Beta Software EULA への署名を回避できなかった」は、単一の隠れフォーム POST ではなく JS 駆動のマルチステップモーダルを示唆。 | 中 | cnx-software.com 証言 (2024)、GitHub #249 (2025) |
| F4 | **AMD ドキュメント上 EULA URL パターンが 2 種類存在**。元コードは 1 種類のみと仮定していた。 | 中 | NPU ドライバ用 `ryzenai-eula-public-xef.html` vs RAI Software EXE / NuGet 用 `xef.html` |
| F5 | **デフォルト driver/RAI マッピング `1.7.1 → 32.0.203.380` が架空**。AMD の RAI 1.7.1 ドキュメントは 1.6.1 driver (`32.0.203.314`) を再利用しており、`NPU_RAI1.7.1_380_WHQL.zip` は公開リストに存在せず。スクリプト自身のコメントが「AMD 公開までの placeholder build」と認めていた。 | 中 | `ryzenai.docs.amd.com/en/latest/inst.html` および `github.com/amd/ryzen-ai-documentation/blob/main/docs/inst.rst` のクロスチェック |
| F6 | **AMD アカウントログインの公開自動化スクリプトが見つからず**。Web 検索で PowerShell/Python の成功事例ゼロ。 | 低 | 否定的な検索結果、参考情報 |

#### 3.6.3 結論

実装済みの `Invoke-AmdAccountAuthentication` 関数 (`https://account.amd.com/en/forms/auth/login.html` への HTTP form POST) は **現状の AMD ポータルに対して成功する見込みが極めて低い** 。ポータルアーキテクチャは関数が前提とする仕様 (server-rendered HTML form with hidden CSRF token、simple POST credentials → 認証済み EULA へリダイレクト → simple POST EULA accept → entitlenow.com へリダイレクト) と整合していません。

この結論は AMD サーバへの認証付きリクエストを行わずとも、公開可視のアーキテクチャ証拠 (F1〜F3)、driver-version 不整合 (F5)、動作する公開実装の不在 (F6) から導かれます。

#### 3.6.4 スクリプトに適用された改修

| 変更 | 内容 | 適用箇所 |
|---|---|---|
| C1 | **Tier 2 をデフォルト無効化**。`-ForceAmdAccountAuth` を渡さない限り関数は即座に `$null` を返す。 | `Invoke-AmdAccountAuthentication` (約 1170 行目) |
| C2 | **`VERIFIED 2026-05-10` バナー** を追加。「成功する見込みが極めて低い」旨を明示警告。 | `Invoke-AmdAccountAuthentication` 冒頭 |
| C3 | **`-ForceAmdAccountAuth` スイッチ** を `param()` ブロックに追加。AMD がポータルを変更したと operator が考える場合、opt-in で試行可能。 | トップレベル `param()` |
| C4 | **バージョニングを完全分離**。単一パラメータ `-PreferredRyzenAiVersion` (driver と software を 1 つのスイッチで混在管理) を、独立した 2 パラメータに分離: `-NpuDriverPackage` (default `latest` = `NPU_RAI1.6.1_314`) と `-RyzenAiSoftwareVersion` (default `latest` = `1.7.1`)。ファイル名生成は AMD が実際に公開する `NPU_RAI1.6.1_314_WHQL.zip` を生成。A 軸と B 軸の互換性は別軸で評価。 | `[string]$NpuDriverPackage = 'latest'`、`[string]$RyzenAiSoftwareVersion = 'latest'`、新規関数 `Get-NpuDriverPackageInfo`、`Get-LatestRyzenAiSoftwareInfo`、`Test-NpuDriverRaiCompatibility` |
| C5 | **`Get-RecommendedNpuDriverBuild` マッピングを修正**。RAI 1.7 / 1.7.1 のエントリは両方とも実存する `32.0.203.314` (公開済みドライバ) を返すように変更。架空の `329` / `380` を排除。AMD docs へのクロスリファレンスを関数ヘッダに追加。 | `Get-RecommendedNpuDriverBuild` |
| C6 | **全ヘッダの `.EXAMPLE` ファイル名** を `NPU_RAI1.7.1_380_WHQL.zip` (架空) から `NPU_RAI1.6.1_314_WHQL.zip` (verified) に更新。 | スクリプトヘッダ 約 93、99、110、124、132 行目 |
| C7 | **Default-Strix プロファイルラベル** を `default-strix-rai1.7.1` から `default-strix-rai1.6.1` に変更。P03 バナーは verified driver build を反映。 | `Get-AmdNpuPlatform` の `$AssumeIfMissing` 分岐 |

#### 3.6.5 `-ForceAmdAccountAuth` の挙動

設定すると、既存の form ベース POST シーケンスがそのまま試行されます:

```powershell
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
    -Action Install `
    -ForceAmdAccountAuth `
    -AmdAccountUser 'you@example.com' `
    -AmdAccountPassword (Read-Host 'AMD password' -AsSecureString)
```

現状の AMD ポータルでの想定結果: **失敗** (以下のいずれかのポイントで、可能性が高いのは Step 2 または Step 3):

- Step 1 EULA ページ GET → fetch は成功するが HTML に CSRF トークン無し
- Step 2 認証情報 POST → 失敗 (ドキュメント記載の URL に実際のフォームが存在しない)
- Step 3 認証済み EULA GET → fetch は成功するが受諾フォーム action が見つからず
- Step 4 EULA 受諾 POST → 失敗 (実際のフォームが存在しない)

万一 AMD が server-rendered form に戻していた場合、既存のフォールバックコードパスが成功を処理するため、その場合の追加変更は不要です。

#### 3.6.6 将来の再検証タイミング

以下のいずれかの条件で、本検証の再実施を推奨します:

- AMD が新規 Ryzen AI リリース (≥ 1.7.2 または 1.8) を発表 — driver マッピングテーブル更新が必要となる可能性
- ユーザーから `-ForceAmdAccountAuth` の成功報告 — Tier 2 をデフォルト有効に再変更可能
- AMD ドキュメントに新しい EULA URL パターンが出現 (既知 2 種類以外)

再検証手順は 4.6.1 と同じ: 公開 AMD ページの fetch、`amd/ryzen-ai-documentation` GitHub リポジトリでの EULA URL パターン照合、自動化成功のエンドユーザー報告のチェック。

### 3.7 バージョニング軸分離の検証 — 2026-05-10

NPU スクリプトのバージョン管理ロジックは **2026-05-10** に再設計し、**NPU カーネルモードドライバ** のバージョニング体系と **Ryzen AI Software (ユーザーモードスタック)** のバージョニング体系を完全に分離しました。AMD 公式ドキュメント <https://ryzenai.docs.amd.com/en/latest/inst.html> (Last updated 2026-04-19) に準拠しています。

#### 3.7.1 2 つの独立したバージョニング体系

AMD のインストールガイドは NPU ドライバと Ryzen AI Software を完全に切り離された artefact として扱っています:

| 観点 | NPU カーネルモードドライバ (axis A) | Ryzen AI Software (axis B) |
|---|---|---|
| 実体 | `npu_sw_installer.exe` に同梱される Windows カーネルモードドライバ。PCI デバイスバインディングとファームウェアロードを担当 | ユーザーモードランタイム: Python conda 環境、ONNX Runtime VitisAI EP、OnnxRuntime GenAI (OGA)、AMD Quark quantizer、xrt-smi tool |
| 配布 | EULA gate 付き ZIP: `account.amd.com/en/forms/downloads/ryzenai-eula-public-xef.html?filename=NPU_RAI*_WHQL.zip` | EULA gate 付き EXE: `account.amd.com/en/forms/downloads/xef.html?filename=ryzen-ai-lt-*.exe` (異なる EULA URL パターンに注意) |
| 現在公開されているバージョン (AMD docs 2026-04-19 時点) | `NPU_RAI1.5_280_WHQL.zip` (driver 32.0.203.280) と `NPU_RAI1.6.1_314_WHQL.zip` (driver 32.0.203.314) | `1.7.1` (最新)、installer `ryzen-ai-lt-1.7.1.exe` および NuGet `1.7.1_nuget_signed.zip` |
| 更新ペース | 遅め — 新しいファームウェア/ドライバペアがリリースされた時のみ。サポート範囲内の旧 RAI Software バージョンとは後方互換 | 頻繁 — 新モデルサポート、性能改善、バグ修正をリリース。**AMD はエンドユーザーワークロードでは常に最新版を推奨**。 |
| 本スクリプトでの operator デフォルト | `latest` → `NPU_RAI1.6.1_314` (公開済 2 パッケージのうち新しい方) | `latest` → `1.7.1` (現時点でスクリプトが認識する最新版に自動解決) |
| ZIP ファイル名内の命名 | `NPU_RAI*_WHQL.zip` 内の `RAI1.5` / `RAI1.6.1` トークンは **歴史的な命名アーティファクト** — どちらの ZIP も現行 Ryzen AI Software 1.7.1 で動作 | バージョニングは独自体系: `1.5` → `1.6.1` → `1.7` → `1.7.1` |

重要なポイント: `NPU_RAI1.6.1_314_WHQL.zip` の `1.6.1` は **Ryzen AI Software のバージョンではありません**。元 RAI 1.6.1 リリース時期に由来するリリースチャネルラベルです。同じドライバ ZIP が RAI Software 1.7.1 用の推奨ドライバとして引き続き使用されます。

#### 3.7.2 互換性評価を別軸として確立

AMD は Ryzen AI Software インストールガイドでドライバ-ソフトウェア互換性を文書化しています。RAI 1.7.1 (現時点最新) では以下の通り:

> "Download and Install the NPU driver version: 32.0.203.280 or newer using the following links" — `NPU_RAI1.5_280` および `NPU_RAI1.6.1_314` の両方が valid options として明示。

これから導かれる互換性マトリクス (axis C — axis A + B から導出):

|  | RAI 1.5 | RAI 1.6.1 | RAI 1.7 | RAI 1.7.1 |
|---|---|---|---|---|
| Driver 32.0.203.280 (`NPU_RAI1.5_280`) | ✅ | ✅ | ✅ | ✅ |
| Driver 32.0.203.314 (`NPU_RAI1.6.1_314`) | ✅ | ✅ | ✅ | ✅ |

最小ドライバ要件 (`32.0.203.280`) は AMD ドキュメント上、サポートされる全 RAI Software バージョンで一貫しています。スクリプトの `Test-NpuDriverRaiCompatibility` 関数がこのマトリクスを符号化し、P03 で `OK` または `MISMATCH` を出力します。

#### 3.7.3 コードレベルの変更

| レイヤ | 変更前 | 変更後 |
|---|---|---|
| **operator パラメータ** | 単一の `-PreferredRyzenAiVersion <ver>` (driver と software を 1 つのスイッチで混在) | 独立した 2 パラメータ: `-NpuDriverPackage <NPU_RAI1.5_280 \| NPU_RAI1.6.1_314 \| latest>` と `-RyzenAiSoftwareVersion <1.5 \| 1.6.1 \| 1.7 \| 1.7.1 \| latest>`。両方とも default `latest`。 |
| **カタログ関数** | `Get-RecommendedNpuDriverBuild $RaiVersion → $build` (誤った結合) と `Get-NpuZipFilename $RaiVersion $build → $filename` (架空ファイル名を生成する文字列連結) | 独立した 3 関数: `Get-NpuDriverPackageInfo` (axis A: 文書化済 ZIP の完全パッケージメタデータを返す)、`Get-LatestRyzenAiSoftwareInfo` (axis B: `IsLatest` フラグ付き RAI Software メタデータを返す)、`Test-NpuDriverRaiCompatibility` (axis C: 上記マトリクスを `[version]` 比較で評価) |
| **検出済プラットフォームフィールド** | `RecommendedRaiVer`、`RecommendedDriver` (2 フィールド、不明瞭な結合) | `NpuDriverPackage`、`NpuDriverBuild`、`NpuDriverZipName` (axis A)、`RyzenAiSoftwareVersion`、`RyzenAiSoftwareInstaller` (axis B)、`DriverSoftwareCompatible`、`DriverSoftwareCompatNote` (axis C) — 軸帰属を明示した 7 フィールド |
| **P03 バナー出力** | "Preferred RAI ver" と "Recommended drv" を並べた単一ブロック | ラベル付き 3 ブロック: "NPU kernel-mode driver (independent versioning axis)"、"Ryzen AI Software (independent versioning axis - always latest unless pinned)"、"Driver <-> RAI Software compatibility (separate evaluation axis)" を `OK` / `MISMATCH` ステータス付きで出力 |
| **post-install guidance (I04)** | RAI バージョンが空の場合 `1.7.1` にハードコード fallback | `RyzenAiSoftwareInstaller` フィールドを直接参照。フィールドが空の時のみ `ryzen-ai-lt-1.7.1.exe` に fallback。「NPU driver と Ryzen AI Software は INDEPENDENTLY にバージョン管理されます。エンドユーザーワークロードでは常に LATEST Ryzen AI Software を利用してください」を明示 |

#### 3.7.4 将来のメンテナンス

AMD が新しい Ryzen AI リリースを公開した際、スクリプトを 2 箇所更新します:

1. **新しい NPU ドライバ ZIP が公開された場合** (例: `NPU_RAI1.8_400_WHQL.zip`): `Get-NpuDriverPackageInfo` カタログと `-NpuDriverPackage` の `ValidateSet` にエントリを追加。新しいドライバが現行 RAI Software に異なる最小要件を導入する場合は `Test-NpuDriverRaiCompatibility` も更新。
2. **新しい Ryzen AI Software バージョンがリリースされた場合** (例: `1.8.0`): `Get-LatestRyzenAiSoftwareInfo` カタログにエントリを追加し、`$latestVersion` を新バージョンに更新、 `-RyzenAiSoftwareVersion` の `ValidateSet` にも追加。AMD release notes で新しい最小ドライバ要件をクロスチェックし、必要に応じて `Test-NpuDriverRaiCompatibility` の `$minimumPerRai` を更新。

この 2 つの更新は独立しています — ドライバサポート追加にソフトウェアメタデータの変更は不要で、その逆も同様です。これが本再設計が達成する中心的な設計特性です。

---

## 4. 検証結果まとめ

### 4.1 環境別マトリクス

| 項目 | M75q Tiny Gen 2 | X13 Gen 1 AMD | **実 NPU マシン** |
|---|---|---|---|
| インスタンス / 機種 | ThinkCentre 物理機 | ThinkPad 物理機 | **TBD** |
| OS | WS2025 | Win11 LTSC 2024 | TBD |
| ProductType | 3 | 1 (PREVIEW MODE) | TBD |
| CPU | Ryzen 7 PRO 5750GE (Cezanne) | Ryzen 5 PRO 4650U (Renoir) | Ryzen AI 300 / 7040 / 8040 |
| NPU 搭載 | なし | なし | **あり** |
| Chipset INF 処理数 | 32/32 + 3 V06 アップグレード | 32/32 + 1 V06 アップグレード | 該当なし (NPU スクリプトの対象外) |
| Graphics INF 処理数 | 19/19 + 3 V06 アップグレード | 19/19 + 3 V06 アップグレード | 該当なし (NPU スクリプトの対象外) |
| NPU スクリプト PrepareVerify | 該当なし (NPU デバイス無し) | 該当なし (NPU デバイス無し) | **PENDING** |
| NPU スクリプト Install | 該当なし | 該当なし (自動ブロック) | **PENDING** |
| 検証目的 | 本番リハーサル (chipset+graphics) | WS2025 pre-migration チェック | **NPU end-to-end 検証** |

### 4.2 推奨検証パターン

| シナリオ | 推奨環境 |
|---|---|
| 「実ドライバインストール検証」(chipset/graphics) | M75q Gen 2 物理機 (production target) |
| 「Win11 → WS2025 pre-migration 評価」(chipset/graphics) | X13 Gen 1 物理機 |
| **「NPU end-to-end 検証」** | **Ryzen AI 300 / 7040 / 8040 シリーズホスト (メンテナーの lab には未配備 — PR 歓迎)** |

> **AMD コンシューマー向け以外のハードウェアでのテストを文書化していない理由**: 本パイプラインは AMD のコンシューマー向け Ryzen / Radeon / NPU シリコンを対象とした実験的ツールです。検証結果は本質的にこれらのデバイスへの物理アクセスに依存します。サーバー級 EPYC、ARM、Intel、仮想ホスト等で本パイプラインを実行しても、デバイスバインドロジック (V06) や実際のドライバアップグレード判定、post-install verification 経路 (I04) を一切実行できません。メンテナーは、対象外ハードウェア上での「パイプライン健全性のみ」のテストは、それを維持するコストに対して価値が限定的であると判断し、検証を物理 AMD コンシューマー向けハードウェアに限定する方針を採用しています。

---

## 5. 発見されたバグと修正履歴

以下のバグは上記検証実行中に発見・修正されました:

| 発見環境 | バージョン | 修正バージョン | 概要 |
|---|---|---|---|
| ThinkPad X13 Gen 1 (Win11 24H2) | chipset r45 | r46 | `Compare-InfDriverVer` のタイムゾーンバグ (UTC 真夜中の `DriverDate` が CIM コマンドレットでローカル 09:00 に変換され、同バージョンケースが「current が patched より新しい」と誤報告)。`.Date` (年月日切り捨て) のみで比較するよう修正。 |
| ThinkPad X13 Gen 1 (Win11 24H2) | r45 / r14 | r46 / r15 | P05 / P00 互換性チェックが Workstation ホストでも `Host OS: Windows Server 2025` と表示し混乱を招いた。実 `Caption` とマップ後 profile を並列表示するよう修正。 |
| ThinkPad X13 Gen 1 (Win11 24H2) | graphics r14 | r16 / r47 | V05 で「would upgrade 1067/1067 matched device(s)」のような件数膨張。`$matchedDevices` が物理デバイス単位ではなく INF HWID variant 単位で append されていた。物理 DeviceID で重複排除するよう修正。 |
| ThinkPad X13 Gen 1 (Win11 24H2) | graphics r14 | r16 / r47 | 同バージョン・新日付アップグレードケースで `patched newer (X) than current (X)` という意味不明なメッセージが出ていた。明確化のため `patched same version (X) but newer date; PnP ranking prefers newer-dated driver` 表示に修正。 |
| パイプラインレビュー (フィールド報告無し) | NPU r1 | (placeholder) | 現時点で発見されたフィールドバグ無し — ただし **フィールド報告自体が存在しない** (NPU スクリプトはまだ物理 NPU ハードウェア上で実行されていない)。 |
| Lab (Win Server 2025, ja-JP) | chipset r49 (検証中) | r49 公開、 r50 polish | Secure Boot baseline 初版展開時に 3 件補正: (a) `schtasks.exe /FO CSV` ヘッダが ja-JP localized — `Get-ScheduledTask` に置換。 (b) MS サンプルスクリプトの `-OutputPath` バリデータ正規表現が `:` を含む全 Windows 絶対パスを拒否 — stdout JSON 抽出フォールバックを追加。 (c) `Show-...` と V06 呼び出し側がバナーを二重出力 — 内側バナー削除。 |
| Lab (Win Server 2025, ja-JP) | chipset r49 / graphics r18 / NPU r4 | r50 / r19 / r5 | Polish patch: ワークスペース未作成時に P00 が診断ファイルを `%TEMP%` に書き出し、 `-CleanWorkRoot` ランで stale パスが V06 に表示されていた。 新規 `Get-OrEnsureSecureBootBaseline` helper でワークスペース配下に一貫配置するよう修正。 |
| Lab (Win Server 2025, ja-JP) | NPU r4 | r5 | `Find-Inf2CatPath` が `\x64\` / `\amd64\` ディレクトリのみフィルタするが、 inf2cat.exe は x86 のみ。 P02 が常に「inf2cat not found」で失敗し winget での WDK インストールも失敗 (WDK は winget パッケージ非提供)。 helper の関数体を x86 対応ツリーウォークに置換。 |
| Lab (Win Server 2025, ja-JP) | NPU r4 | r5 | `-NpuOverride` の `[ValidateSet]` がデフォルトの空文字列を拒否し、 起動毎にノイジーな警告を出力。 set に `''` を追加。 |
| Windows Server 2025 クリーンインストール (対話型コンソール) | chipset r54 / graphics r19→r22 | chipset r55 / graphics r23 | 同一の PowerShell ホスト内での連続 run で workspace lock がリーク。 ロックファイル `<WorkRoot>\.markers\RUN.lock` は現在の `$PID` で書き込まれるが、 解放は `Register-EngineEvent PowerShell.Exiting` アクションにのみ依存していた。 このイベントは対話型コンソール内では発火しない。 そのため、 同じコンソールでの次の run が leftover lock の PID をホスト自身の PID と一致するものとして検出し、 「別インスタンスが動作中」として拒否されていた。 修正: (a) `Test-WorkspaceLockHeld` での自 PID 検出 (`Pid==$PID` のロックは stale 扱いで silent 引き継ぎ)、 (b) メインフェーズループを `try { ... } finally { Clear-WorkspaceLock ... }` で wrap し、 あらゆる exit path でロック解放を保証。 NPU スクリプトには workspace lock が実装されていないため影響なし (SPEC §D.13 参照)。 |
| Windows Server 2025 クリーンインストール | chipset r54 | r55 | r54 で新規追加された `Expand-AmdInstaller_ViaInstallShield` が `installshield-admin.log` と 12 個のサブ MSI ごとの `msiexec-admin-*.log` ファイルを workspace ルートに drop していた (既存の `inf2cat_*.log` / `signtool_*.log` / `verify_*.log` / `pnputil_*.log` のように `<WorkRoot>\logs\` に集約されていなかった)。 Root cause: `$parentDir = Split-Path $DestinationPath -Parent` が workspace ルートに resolve されていた (caller が `$Ctx.Paths.Extract` (= `<WorkRoot>\extracted`) を渡していたため)。 修正: `Expand-AmdInstaller` および `Expand-AmdInstaller_ViaInstallShield` にオプショナル `-LogDir` パラメータを追加し、 `Invoke-PrepPhase04_ExtractInstaller` から `$Ctx.Paths.Logs` を渡すよう変更。 Chipset のみ — Graphics は単一の `msiexec /i` invocation を使用しており影響なし。 SPEC §D.14 参照。 |

詳細な検証ログと修正コミットは <https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/commits/main> を参照してください。

---

## 6. UEFI Secure Boot ベースライン検証チェックリスト

UEFI Secure Boot ベースライン機能 (Chipset r50 / Graphics r19 / NPU r5) の各スクリプト共通検証チェックリスト。 3 つの姉妹スクリプトは 6 コア関数を共有するため、 期待出力は 3 スクリプト間で統一されている。 KB5089549 同等のパッチが適用された Windows Server 2025 ホストで少なくとも 1 回は検証すること。

### Phase 別の期待出力

| Phase | 期待値 | テストホストでの結果 |
|---|---|---|
| P00 | 1 行コンパクト: `Secure Boot baseline: enabled=true UEFI-CA-2023=NotStarted health=Warning [MS-sample=ok]` (値はホスト状態によって変化) | ✅ |
| P05 | 新ファイル `<WorkRoot>\inf_inventory_report.txt` が存在し、 末尾に「UEFI Secure Boot Baseline」アペンディックスブロック (Chipset / Graphics: INF インベントリ後にセクション追加。 NPU: インラインインベントリ後に追加) | ✅ |
| V05 | 新セクション: `[Dry-Run UEFI Baseline]` ヘッダの後にコンパクト readout。 `Health` が `Warning` または `Critical` の場合は黄色 advisory が続く | ✅ |
| V06 | 新番号付きセクション: 「4. UEFI Secure Boot Baseline」 (Chipset / Graphics) または「Section 5: UEFI Secure Boot Baseline」 (NPU)。 組み込みインベントリ + MS サンプルスクリプト結果 (BucketId / Confidence / EventNNNN カウント) を含むマルチライン内訳 | ✅ |
| I02 | 新事前チェックブロック: `--- UEFI Secure Boot baseline pre-check ---` の後にコンパクト readout と advisory。 ブロックしない。 | (Install フェーズ — 別途実行) |

### ワークスペース成果物チェックリスト

| 成果物 | 期待される配置 | 用途 |
|---|---|---|
| Raw stdout dump | `<WorkRoot>\secureboot_ms_sample\detect_stdout.log` | MS サンプルスクリプトが予期せぬ動作を示す際のフォレンジック |
| 抽出 JSON | `<WorkRoot>\secureboot_ms_sample\detect_stdout_extracted.json` | パース済み `Hostname`、 `UEFICA2023Status`、 `BucketId`、 `Confidence`、 `Event1801..1803` |
| インベントリレポートアペンディックス | `<WorkRoot>\inf_inventory_report.txt` | 変更管理ドキュメント向けに永続化されたスナップショット |

注意事項:
- MS サンプルスクリプトは KB5089549 (Win 11)、 KB5087544 / KB5088863 (Win 10)、 WS2025 同等 (2026-05-12 以降) で配信される。 未パッチホストでは `[MS-sample=ok]` ではなく `[MS-sample=absent]` が期待される。
- 診断ファイルは `-CleanWorkRoot` を指定しない限り後続ランでも残存する。

### 健全性クラスのアサーション

| ホスト状態 | 期待される `health=` 値 |
|---|---|
| Secure Boot ON、 `UEFICA2023Status = Updated` (KB ロールアウト完了) | `Healthy` |
| Secure Boot ON、 `UEFICA2023Status = NotStarted / Started / Pending` | `Warning` |
| Secure Boot OFF | `Critical` |
| `UEFICA2023Error` 非ゼロ | `Critical` |
| Secure Boot 状態取得不能 (一部ファームウェア固有挙動) | `Unknown` |

### スクリプト間整合性チェック

同じホストで `-CleanWorkRoot` 付きで 3 スクリプトすべてを PrepareVerify モードで実行。 V06 でキャプチャされる `BucketId`、 `Confidence`、 イベントカウントは **3 スクリプト間で同一** になるべき (MS サンプルスクリプトは同じホスト状態に対して決定論的な結果を返す)。

---


## 7. r54+ — AMD Chipset Software 8.x 展開診断フォーマット

Chipset スクリプト r54 リビジョン以降、 P04 ExtractInstaller phase は AMD Chipset Software 8.x (8.02.18.557 以降) 向けに新しい "Strategy 2/3" パスを含む。 本章は新しい展開パスの期待される診断出力と検証手順を記載する。

### 7.1 新しい strategy が必要となった理由

AMD Chipset Software 8.x は 2 層構造の wrapper として配布される:

1. **外殻 (Outer layer)**: NSIS 自己展開 EXE (7-Zip で展開可能)。
2. **内殻 (Inner layer)**: `ISSetupStream` フォーマットの InstallShield SFX (7-Zip では展開不可、 InstallShield 自身の `/a` 管理者インストールのみで展開可能)。

r54 以前のリビジョンは内殻での 7-Zip 失敗を検知してインストーラを起動し `C:\AMD\` から file を回収する fallback に流れていたが、 AMD はこのディレクトリを積極的にクリーンアップするため脆弱だった。 r54 は旧 7-Zip 戦略と launch-watch fallback の間に専用の InstallShield-aware strategy を挿入する。

完全なアーキテクチャは `SPEC.ja.md` §B.1 "AMD 8.x インストーラアーキテクチャ (r54+)" を参照。

### 7.2 Strategy 2 が成功した場合に期待される診断出力

インストーラが AMD 8.x である場合、 P04 console output は以下のような形式となる（可読性のため省略）:

```
[*] Phase 04 :  P04 ExtractInstaller   (Build group)
[*] Extracting installer (multiple strategies will be attempted)
    Strategy 1/3: 7-Zip auto-detect
[!] 7-Zip auto-detect produced no usable payload (exit 0) - trying next strategy
    Strategy 2/3: InstallShield /a admin install (AMD 8.x+ chain)
      Step 1/3: 7-Zip outer NSIS shell...
      Inner SFX  : C:\AMD-Chipset-WS\is-stage-nsis\AMD_Chipset_Drivers.exe (75.3 MB)
      Step 2/3: InstallShield /a admin install...
      Unpacked   : 36 MSI files (InstallShield exit 0)
      Step 3/3: msiexec /a on 36 sub-MSI(s)...
      msiexec /a : 35 succeeded, 1 failed
      INF total  : 96
      [PREFERRED] W11x64    :  32 INF(s)
      [ skip    ] WTx64     :  32 INF(s)
      [ skip    ] WTx86     :  32 INF(s)
[+]    Extracted via InstallShield admin install chain
[+] Extracted to: C:\AMD-Chipset-WS\extract
```

### 7.3 検証チェックリスト

新しいパスが正常に動作した場合、以下のすべてが成立すべきである:

| チェック項目 | 期待値 | 検証方法 |
| --- | --- | --- |
| InstallShield exit code | `0` (理想) または `1` (MSI count が正しければ許容) | console 行 `Unpacked   : NN MSI files (InstallShield exit X)` |
| MSI count | `>= 36` (8.02.18.557 では parent 1 + sub 35。 将来バージョンで差異あり) | 同上 |
| msiexec /a 成功率 | `36` 中 `>= 30` | console 行 `msiexec /a : NN succeeded, M failed` |
| INF total | `>= 80` (バージョンにより変動、 8.02.18.557 では通常 96) | console 行 `INF total  : NN` |
| PREFERRED variant が非ゼロの INF を持つ | `[PREFERRED] <variant> : >= 25 INF(s)` | console 行 — **これが critical signal** |
| PREFERRED variant が host OS と一致 | WS2022/WS2025 では `W11x64`、 WS2016/WS2019 では `WTx64` | console banner の `$Ctx.Os` とクロスチェック |

### 7.4 トラブルシューティング

PREFERRED variant が `0 INF(s)` を示す一方で展開自体は成功している場合、考えられる原因は:

1. **InstallShield /a が silent に失敗**: `C:\AMD-Chipset-WS\installshield-admin.log` の admin install 時の MSI error を確認。 `Action ended ...` 行で非ゼロの return value を探す。

2. **OS-variant sub-MSI に対する msiexec /a が失敗**: `C:\AMD-Chipset-WS\msiexec-admin-*.log` で具体的な失敗 sub-MSI を確認。 各 sub-MSI は MSI ファイル名にちなんだ独自の log を持つ。

3. **AMD が将来バージョンでディレクトリレイアウトを変更**: 8.02.18.557 より新しい Chipset Software に対して実行し、 `Binaries\<DriverName>\<OS>\` 構造が変わった場合は、 `Get-AmdSourceVariant` 分類器 (script の ~5003 行目) の更新が必要となる可能性がある。 `C:\AMD-Chipset-WS\extract\` 配下のディレクトリツリーを添えて GitHub issue を起票してほしい。

### 7.5 Fallback 動作

何らかの理由で Strategy 2 が失敗した場合 (`Expand-AmdInstaller` の `try { ... } catch` ブロックで捕捉)、 スクリプトは Strategy 3/3 (launch + watch) に流れる。 これは r54 以前の動作を保持するためである。 その場合の console output は:

```
[!] InstallShield /a strategy failed: <error message>
    Strategy 3/3: launch installer and harvest from C:\AMD\
```

これは r54 以前のリビジョンが使用していたのと同じ fallback パスであり、 regression fallback として扱うべきである。
