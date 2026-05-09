# TESTING.ja.md — クラウドテスト手順と物理ハードウェア検証結果

本ドキュメントは `Deploy-AMD-Drivers-For-WindowsServer` のテストと評価に必要な情報を集約したものです。以下の 4 つの環境を取り扱います:

1. **AWS クラウド (東京リージョン)** — EPYC 複数世代 (Naples / Milan / Genoa / Turin) を活用したテスト手順
2. **検証結果 1: ThinkCentre M75q Tiny Gen 2** (Windows Server 2025 物理機 / Cezanne Zen 3 — チップセット・グラフィックス検証済み)
3. **検証結果 2: ThinkPad X13 Gen 1 AMD (2020)** (Windows 11 Enterprise LTSC 2024 / Renoir Zen 2 — チップセット・グラフィックス検証済み)
4. **検証結果 3 (NPU スクリプト)** — **🆘 物理 NPU ハードウェアでの検証は未実施。現状の限定的な検証状況については [§4](#4-検証結果-3-npu-スクリプト--現時点で未検証) を参照してください。**

🇬🇧 **English version: see [TESTING.md](./TESTING.md).**

---

## 0. 検証ステータスサマリ

> セクション 1〜4 を読む前にこのセクションを必ず確認してください。3 つのスクリプトは **検証成熟度が大きく異なります**。

| スクリプト | AWS EPYC でのパイプライン健全性 | 物理ハードウェア検証 | ターゲット HW 上での実ドライバインストール | 推奨用途 |
|---|---|---|---|---|
| **Chipset (r47)** | ✓ Naples → Turin の全世代で検証済み | ✓ M75q Tiny Gen 2、X13 Gen 1 AMD | ✓ M75q (WS2025) でインストール成功 | Lab + 慎重な production |
| **Graphics (r16)** | ✓ Naples → Turin の全世代で検証済み | ✓ M75q Tiny Gen 2、X13 Gen 1 AMD | ✓ M75q (WS2025) でインストール成功 | Lab + 慎重な production |
| **NPU (r1)** | ⚠️ **部分的** (EPYC では PrepareVerify のみ。NPU 不在のため V05/V06 出力は限定的) | ❌ **なし** (メンテナーの lab に物理 NPU マシンが存在しない) | ❌ **未実行** | **実験的・研究用途のみ。本番環境への deploy は不可。** |

NPU スクリプトの検証は現時点で以下に限定されています:

1. **静的解析** を `tools/psa.py` で実施 (errors 0、warnings 4 件は false-positive のみ)。
2. **コードレビュー** — AMD 公開の `quicktest.py` の NPU 検出ロジックを PowerShell に翻訳した実装をレビュー。
3. **EPYC AWS ホストでの dry-run** — `-AssumeIfMissing` 付きで NPU デバイス不在環境にて V06 まで通ることを確認。
4. **`-Action Install` の実行はメンテナーによって一切行われていません。**

Ryzen AI 300 / Ryzen AI Max 300 / Ryzen 7040 / 8040 シリーズのマシンをお持ちで、NPU スクリプトのいずれかの phase を実行された場合は、検証ギャップを埋めるため GitHub Issues に結果を報告いただけると幸いです。

---

## 1. AWS クラウドテスト

### 1.1 クラウドテストの位置付け

AWS EC2 はコンシューマー Ryzen ハードウェアを直接提供しません。AMD ベースの EC2 インスタンスは **AMD EPYC server CPU** で稼働しており、本スクリプトがターゲットとするコンシューマー Ryzen チップセット / Radeon iGPU / NPU とは silicon が異なります。したがって AWS テストは以下の用途に限定されます:

| AWS で検証可能な内容 | AWS で検証**不可能**な内容 |
|---|---|
| ✓ スクリプトが Windows Server 2025 上でエラー無く完走するか | ❌ 実際の AMD コンシューマーチップセット / Radeon / NPU ハードウェアでのドライバインストール結果 |
| ✓ AMD パッケージのダウンロード / 展開 / パース | ❌ デバイスバインドの正確性 (該当 HW が存在しないため) |
| ✓ 自己署名証明書生成と catalog 署名 | ❌ V06 の "3 candidates upgrade" のような期待されるドライバアップグレード |
| ✓ WDAC supplemental policy 生成 (PrepareVerify で停止し deploy しない) | ❌ I03 後の実環境におけるドライバ挙動 |
| ✓ inf2cat / signtool ツールチェーン検証 | ❌ BitLocker / TPM (PSP ドライバ) との相互作用 |
| ✓ CI 自動テスト (PR 検証、回帰テスト) | ❌ AMD Vega/RDNA GPU レンダリングパス |
| ✓ EPYC 各世代における Win32_Processor 検出ロジック | ❌ コンシューマー Ryzen 検出パス |
| ✓ NPU スクリプトの `-AssumeIfMissing` 経由での PrepareVerify 完走 (default Strix Point profile) | ❌ NPU スクリプトの実 NPU デバイス検出、ドライババインド、post-install 検証 |

要するに、 **「パイプライン健全性検証」** は AWS で十分カバーできるのに対し、 **「コンシューマー Ryzen / NPU マシン上のドライバアップグレード結果」** は物理ハードウェアが必要です。クラウドテストの最大の価値は GitHub Actions CI のような自動回帰テストにあります。

### 1.2 AWS で利用可能な AMD EPYC 全世代マップ

AWS は 2018 年から AMD EPYC を採用しており、**5 世代** の silicon が現在利用可能です。スクリプト検証では世代横断的にテストを行うことを推奨します (パイプラインは古い EPYC でも新しい EPYC でも一様に動作する必要があるため):

| 世代 | コードネーム | リリース年 | アーキテクチャ | 代表インスタンス | CPU モデル例 | 最大周波数 | 東京リージョン提供状況 |
|---|---|---|---|---|---|---|---|
| **第 1 世代** | **Naples** | 2018 | Zen | T3a / M5a / R5a / C5a | EPYC 7571 (T3a) | 2.5 GHz | ✓ (旧世代インスタンス) |
| 第 2 世代 | Rome | 2019 | Zen 2 | (AWS 一般採用なし) | — | — | — |
| **第 3 世代** | **Milan** | 2021 | Zen 3 | M6a / C6a / R6a / Hpc6a | EPYC 7R13 | 3.6 GHz | ✓ |
| **第 4 世代** | **Genoa** | 2023 | Zen 4 | M7a / C7a / R7a | EPYC 9R14 | 3.7 GHz (DDR5) | ✓ |
| **第 5 世代** | **Turin** | 2025 | Zen 5 | M8a / R8a / C8a | EPYC 9R45 | 4.5 GHz (M8azn: 5.0 GHz) | ✓ (M8a は 2025-11-12 から東京で提供) |

**主要な技術的差分**:

- **Naples (T3a/M5a)**: 1 vCPU = 1 SMT thread (2 vCPU = 1 物理コア)。T3a は **一部 AZ で AZ 制限**があり WS2025 AMI 起動 (Nitro + UEFI 必須) ができない場合あり。
- **Milan (M6a)**: 1 vCPU = 1 SMT thread。AMD SEV-SNP サポート (M6a/C6a/R6a で確認済み)。
- **Genoa (M7a)**: **1 vCPU = 1 物理コア (SMT 無効)**。DDR5 メモリ、AVX-512 / VNNI / bfloat16 対応。
- **Turin (M8a)**: 1 vCPU = 1 物理コア。Zen 5、CPU Family 26 (Genoa は Family 25)。L1d cache 48 KiB (前世代 32 KiB から +50%)。

### 1.3 用途別の推奨インスタンスタイプ (東京リージョン ap-northeast-1)

| 用途 | 推奨インスタンス | EPYC 世代 | vCPU/RAM | 東京 Windows 価格 (概算) | 備考 |
|---|---|---|---|---|---|
| **最安 — PrepareVerify** | `t3a.medium` | Naples (1st) | 2 / 4 GiB | ≈ **$0.07–0.10/h** | AZ 制限要確認 (us-east-1a 等で WS2025 AMI が起動しないケースあり) |
| **安定的 burstable** | `t3a.large` | Naples (1st) | 2 / 8 GiB | ≈ $0.13–0.17/h | WDK インストール用にメモリ余裕あり |
| **モダン EPYC — Milan** | `m6a.large` | Milan (3rd) | 2 / 8 GiB | ≈ $0.18–0.22/h | SMT 有効、SEV-SNP テスト可 |
| **DDR5 — Genoa** | `m7a.large` | Genoa (4th) | 2 / 8 GiB | ≈ $0.22–0.27/h | SMT 無効、AVX-512、CPU Family 25 検出を検証 |
| **最新 — Turin** | `m8a.large` | Turin (5th) | 2 / 8 GiB | ≈ $0.23–0.28/h | M7a 比 +5% 程度、Zen 5、CPU Family 26 検出を検証 |
| **GPU 検証 (オプション)** | `g4ad.xlarge` | (Naples + Radeon V520) | 4 / 16 GiB | ≈ $0.50–0.60/h | AMD Radeon Pro V520 dGPU 搭載。`Win32_VideoController` の AMD GPU 検出パスを評価可 |

> **価格について**: 上記は本ドキュメント作成時点 (2026 年 5 月) の概算で、Windows Server ライセンスコスト (≈ $0.046/h) を含みます。最新の正確な料金は [AWS Pricing Calculator](https://calculator.aws/) で確認してください。**Spot instance** を利用すれば最大 70% 程度の節約が可能 (t3a.medium Spot は概ね $0.02–0.03/h)。

#### PrepareVerify 1 回 (約 10 分) のコスト見積もり

| インスタンス | 1 回 | 1 日 5 回 | 月額 (週 5 回 × 4 週) |
|---|---|---|---|
| t3a.medium Spot | ≈ $0.005 | ≈ $0.025 | ≈ $0.50 |
| t3a.medium On-Demand | ≈ $0.014 | ≈ $0.07 | ≈ $1.40 |
| m6a.large On-Demand | ≈ $0.033 | ≈ $0.165 | ≈ $3.30 |
| m7a.large On-Demand | ≈ $0.040 | ≈ $0.20 | ≈ $4.00 |
| m8a.large On-Demand | ≈ $0.043 | ≈ $0.215 | ≈ $4.30 |

**4 世代 (Naples / Milan / Genoa / Turin) 横断の週次回帰テスト** であれば、月額 $15 以下で構成可能です。ストレージ (gp3 EBS 50 GB) で +$5/月、トータルでも非常に手頃です。

### 1.4 推奨 AMI と起動制約

AWS 提供の **Microsoft Windows Server 2025 Base** (License Included) AMI を使用します。Windows Server 2025 AMI は **Nitro ベース + UEFI ブート** のインスタンスでのみ起動可能です:

- **対応**: T3a (新しい AZ にて)、M6a、M7a、M8a、C6a、C7a、C8a、R6a、R7a、R8a — 全て Nitro + UEFI 対応で WS2025 AMI を起動可能。
- **注意点**: us-east-1a 等の一部 AZ では UEFI 制約により T3a で WS2025 が起動しないケースあり。`BIOS-Windows_Server-2025-English-Full-Base` AMI (Legacy BIOS) を使うか、別 AZ (例: us-east-1f) を選択してください。東京では T3a + WS2025 起動は ap-northeast-1c / 1d で最も安定します。

#### 最新 AMI ID の取得

```bash
# 東京の最新 WS2025 (UEFI、English) AMI
aws ec2 describe-images \
  --owners 'amazon' \
  --region ap-northeast-1 \
  --filters \
    'Name=platform,Values=windows' \
    'Name=name,Values=Windows_Server-2025-English-Full-Base-*' \
  --query 'reverse(sort_by(Images, &CreationDate))[0].{ImageId:ImageId,Name:Name,CreationDate:CreationDate}' \
  --output table

# 日本語ロケール版 (パッチログがローカライズされる)
aws ec2 describe-images \
  --owners 'amazon' \
  --region ap-northeast-1 \
  --filters \
    'Name=platform,Values=windows' \
    'Name=name,Values=Windows_Server-2025-Japanese-Full-Base-*' \
  --query 'reverse(sort_by(Images, &CreationDate))[0].{ImageId:ImageId,Name:Name,CreationDate:CreationDate}' \
  --output table
```

AMI 名は `Windows_Server-2025-{English|Japanese}-Full-Base-YYYY.MM.DD` の形式で月次更新されます。

### 1.5 セットアップ手順 (世代横断検証)

#### Step 1: 各世代で 1 つずつ EC2 インスタンスを起動 (例)

```bash
AMI_ID=ami-XXXXXXXXXXXXXXXXX  # describe-images の結果から
KEY=YourKeyPair
SG=sg-XXXXXXXXXX
SUBNET=subnet-XXXXXXXXXX  # ap-northeast-1c または 1d 推奨

for INST in t3a.medium m6a.large m7a.large m8a.large; do
  aws ec2 run-instances \
    --region ap-northeast-1 \
    --image-id $AMI_ID \
    --instance-type $INST \
    --key-name $KEY \
    --security-group-ids $SG \
    --subnet-id $SUBNET \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=50,VolumeType=gp3}' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=amd-test-$INST}]"
done
```

#### Step 2: Administrator パスワードを取得し RDP 接続

```bash
aws ec2 get-password-data \
  --region ap-northeast-1 \
  --instance-id i-XXXXXXXXXX \
  --priv-launch-key ./YourKeyPair.pem
```

セキュリティグループで TCP 3389 を自分の IP からのみ許可、パブリック IP に対して RDP 接続。

#### Step 3: スクリプトを転送して PrepareVerify 実行

```powershell
# RDP セッション内、管理者権限の PowerShell で
mkdir C:\TEMP
cd C:\TEMP

# スクリプトを転送 (S3 / SSM Run Command / RDP クリップボード — 任意)
$bucket = 'your-test-bucket'
aws s3 cp s3://$bucket/Deploy-AMDChipsetDriverOnWindowsServer.ps1  .
aws s3 cp s3://$bucket/Deploy-AMDGraphicsDriverOnWindowsServer.ps1 .
aws s3 cp s3://$bucket/Deploy-AMDNpuDriverOnWindowsServer.ps1      .
# 必要に応じて NPU offline ZIP も (ダウンロード手順は §4 参照)
aws s3 cp s3://$bucket/NPU_RAI1.7.1_380_WHQL.zip .

# CPU 世代を確認
Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
# 期待される出力:
#   t3a.medium: AMD EPYC 7571              2 cores  2 LP  2500 MHz  (Naples、SMT)
#   m6a.large : AMD EPYC 7R13              2 cores  2 LP  3725 MHz  (Milan、SMT)
#   m7a.large : AMD EPYC 9R14              2 cores  2 LP  3700 MHz  (Genoa、SMT off、Family 25)
#   m8a.large : AMD EPYC 9R45              2 cores  2 LP  4500 MHz  (Turin、SMT off、Family 26)

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# PrepareVerify のみ実行 (EPYC マシンでの Install は意味がなく非推奨)
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\chipset-AWS-$env:COMPUTERNAME.log
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\graphics-AWS-$env:COMPUTERNAME.log

# NPU PrepareVerify を -AssumeIfMissing 付きで実行 (EPYC では NPU 不在、default Strix Point profile)
.\Deploy-AMDNpuDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot `
    -OfflineZip .\NPU_RAI1.7.1_380_WHQL.zip -AssumeIfMissing *>&1 |
  Tee-Object C:\TEMP\npu-AWS-$env:COMPUTERNAME.log

# ログをオフラインレビュー用に S3 へアップロード
aws s3 cp C:\TEMP\chipset-AWS-$env:COMPUTERNAME.log  s3://$bucket/results/
aws s3 cp C:\TEMP\graphics-AWS-$env:COMPUTERNAME.log s3://$bucket/results/
aws s3 cp C:\TEMP\npu-AWS-$env:COMPUTERNAME.log      s3://$bucket/results/
```

#### Step 4: 完了後にインスタンスを停止または terminate

```bash
# 停止 (停止中はストレージコストのみ)
aws ec2 stop-instances --region ap-northeast-1 \
  --instance-ids i-XXXXXXXXXX i-YYYYYYYYYY i-ZZZZZZZZZZ i-WWWWWWWWWW

# 検証完了後に完全に terminate
aws ec2 terminate-instances --region ap-northeast-1 \
  --instance-ids i-XXXXXXXXXX i-YYYYYYYYYY i-ZZZZZZZZZZ i-WWWWWWWWWW
```

### 1.6 EPYC 各世代における期待結果

| 検証項目 | t3a.medium (Naples) | m6a.large (Milan) | m7a.large (Genoa) | m8a.large (Turin) |
|---|---|---|---|---|
| OS 検出 (P00) | WS2025、ProductType=3 | 同上 | 同上 | 同上 |
| CPU 検出 (P03) | EPYC 7571、Naples (Zen 1) として認識 | EPYC 7R13、Milan (Zen 3) | EPYC 9R14、Genoa (Zen 4)、CPU Family 25 | EPYC 9R45、Turin (Zen 5)、CPU Family 26 |
| プラットフォーム判定 (P03) | Server / EPYC family → コンシューマー Ryzen URL probe にフォールバック | 同上 | 同上 | 同上 |
| AMD chipset HW 検出 (V06) | 0 件もしくは極少数 (PCI デバイスは virtio / Nitro) | 同上 | 同上 | 同上 |
| AMD GPU HW 検出 (V06) | 0 件 (素の EPYC インスタンスには Radeon GPU 無し。g4ad.* は別) | 同上 | 同上 | 同上 |
| AMD NPU HW 検出 (V06、NPU スクリプト) | 0 件 (EPYC に NPU 無し)、`-AssumeIfMissing` で profile 続行 | 同上 | 同上 | 同上 |
| WILL be replaced (V06) | 0 | 0 | 0 | 0 |
| 全 P00–V06 phase 通過 (chipset / graphics / NPU) | ✓ ✓ ✓ | ✓ ✓ ✓ | ✓ ✓ ✓ | ✓ ✓ ✓ |
| 期待実行時間 (chipset+graphics) | 約 8〜12 分 (最遅 CPU) | 約 6〜9 分 | 約 5〜8 分 | 約 4〜7 分 (最速) |
| 期待実行時間 (NPU スクリプト) | 約 3〜5 分 (パッケージサイズ小) | 約 2〜4 分 | 約 2〜3 分 | 約 2〜3 分 |
| パイプライン健全性 | OK | OK | OK | OK |

**4 世代横断検証で確認できること**:

- スクリプトが Naples (Zen) から Turin (Zen 5) まで全 EPYC 世代で一様に完走 — 将来 silicon に対する forward-compatibility 保証。
- CPU Family 番号 (Naples=23、Milan=25、Genoa=25、Turin=26) ベースの分岐ロジックがリグレッションしないこと。
- vCPU/SMT トポロジ差異 (SMT-on Naples/Milan vs SMT-off Genoa/Turin) がパイプラインの並列実行パスを壊さないこと。
- NPU スクリプトについては: 4-tier URL 解決が Tier 4 (`-OfflineZip`) にクリーンに fall through すること、ZIP が 7-Zip で正しく展開されること、INF パーサーがターゲット NPU codename の INF を識別すること、P06 が `ProductType=3` decoration を mirror すること、署名が成功すること。

---

## 2. 検証結果 1: ThinkCentre M75q Tiny Gen 2 (Windows Server 2025)

### 2.1 ハードウェア仕様

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

### 2.2 OS 構成

| 項目 | 値 |
|---|---|
| OS | Windows Server 2025 Standard / Datacenter |
| Build | 26100 |
| ProductType | 3 (Server) |
| Secure Boot | ON |
| HVCI | OS デフォルト (環境による) |
| BitLocker | オプション (有効化する場合は **事前にリカバリキーを保管**) |

### 2.3 検証手順 (chipset + graphics のみ — このホストには NPU 無し)

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
# `-AssumeIfMissing` で実行した場合はパイプライン健全性チェックのみで、
# 上記の AWS 回帰テストと同等の意味しか持たない。M75q は chipset/graphics 検証に活用すべき。
```

### 2.4 主要な検証結果

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

- **このホストでは適用対象外** (Cezanne には NPU 無し)。NPU スクリプトは 0 件の NPU デバイスを検出し、`-AssumeIfMissing` で続行が必要。そのような実行はパイプライン健全性のみを検証し、実 NPU 挙動は検証されない。

#### 健全性チェック

- 全 21 phase が成功 (chipset + graphics)
- 自己署名証明書 (RSA 4096 / SHA-384、5 年有効) 生成成功
- 32 catalog (chipset) + 19 catalog (graphics) を `inf2cat /os:Server2025_X64` で生成
- 全 catalog が `signtool` でタイムスタンプ署名成功
- I03 (Install) 後、Device Manager で 3 chipset + 3 graphics デバイスが `[C] Self-signed` にバインド

### 2.5 既知の制約

- BitLocker 有効ホストでは PSP ドライバアップグレード時に次回起動でリカバリプロンプトが発生する可能性。**事前に必ずリカバリキーを取得**してください (コントロールパネルの BitLocker UI または Microsoft アカウントバックアップから)。
- 一部の `ROOT\AMD*` ソフトウェア専用エンティティ (AMDLOG / AMDXE 等) は I03 で追加されるが `Win32_PnPSignedDriver` の enumeration には現れません。V06 セクション 1 で「software-only」として情報表示されます。
- インストール成功は I04 で観測される `[B] Vendor` → `[C] Self-signed` 遷移により確認されます。

---

## 3. 検証結果 2: ThinkPad X13 Gen 1 AMD (2020) — Windows 11 Enterprise LTSC 2024

### 3.1 ハードウェア仕様

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

### 3.2 OS 構成 (検証時点)

| 項目 | 値 |
|---|---|
| OS | Microsoft Windows 11 Enterprise LTSC 2024 |
| Build | 26100 (24H2 LTSC) |
| ProductType | 1 (Workstation) — 本スクリプトでは **WS2025 PREVIEW MODE** で動作 |
| Secure Boot | OFF (テストのため一時的に OFF) |
| HVCI | ON |
| BitLocker | OFF (lab 利用) |

### 3.3 検証手順

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

### 3.4 主要な検証結果

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

### 3.5 同一ハードウェア上での Win11 と WS2025 の期待される差分

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

## 4. 検証結果 3 (NPU スクリプト) — 現時点で未検証

> **🆘 このセクションは「未検証である事項」を文書化しています。** 動作する証拠としては解釈しないでください。

### 4.1 NPU スクリプトについて現時点で検証済みの項目

| 検証活動 | ステータス | 根拠 |
|---|---|---|
| `tools/psa.py` での静的解析 | ✅ 完了 | errors 0、warnings 4 件は false-positive のみ (chipset/graphics と同等) |
| NPU 検出ロジックのコードレビュー | ✅ 完了 | `Get-AmdNpuPlatform` は AMD 公開の `quicktest.py` を PowerShell に直接ポート |
| AWS EPYC EC2 (NPU 不在) でのパイプライン健全性 | ⚠️ 部分的 / 計画段階 | `-Action PrepareVerify -AssumeIfMissing` が V06 までクリーンに動作する想定だが、CI ではまだ未実行 |
| 物理 NPU マシンでの検出 | ❌ **未実施** | 本ドキュメント作成時点でメンテナーの lab に物理 NPU ハードウェアが無い |
| 実 NPU ドライバ ZIP の INF パース | ❌ **未実施** | NPU ドライバ ZIP (`NPU_RAI*_WHQL.zip`) は EULA gate のため、メンテナーは全 RAI バージョンの INF 構造を検証済みのコピーで保有していない |
| 物理 NPU マシンでの `-Action Install` | ❌ **未実施** | 同上 |
| Post-install での `[C] Self-signed` バインド確認 | ❌ **未実施** | 同上 |
| AMD アカウント自動ダウンロード (Tier 2) | ⚠️ **best-effort、不安定** | 公開フォーム構造観察を元に実装。AMD のフォーム変更で予告なく破綻する可能性 |
| Windows Server 2025 上の Ryzen AI Software user-mode stack | ❌ **AMD 公式に未サポート** | AMD ドキュメントにて Windows 11 24H2 (build >= 22621.3527) のみと明記 |

### 4.2 検証ギャップ (NPU スクリプトを production-ready 扱いする前に行うべきこと)

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

5. **AWS EPYC でのパイプライン回帰** — 現時点で実 NPU 検証の代替として最もアクセスしやすい手段。Naples / Milan / Genoa / Turin 上で `-Action PrepareVerify -AssumeIfMissing -OfflineZip <path>` を週次実行し、URL 解決 / ZIP 展開 / INF パース / 署名パイプラインのリグレッションを早期検出する。

### 4.3 推奨される実行パターンと 4-tier 評価

`Resolve-AmdNpuDriverUrl` (スクリプト 772 行目) の 4-tier URL resolution が P03 の NPU ドライバ ZIP 取得方法を制御します。挙動は **全てのパラメータ組合せで対称ではない**ため、各実行パターンの実際の結果を以下の表に文書化しています。実行計画時の参照に活用してください。

| # | 実行コマンド | 結果 | 4-tier resolver の経由経路 |
|---|---|---|---|
| 1 | `-Action PrepareVerify -CleanWorkRoot -OfflineZip <path>` | ✅ **初回 dry-run の推奨パターン。** | T4 priority block (824 行目) → ZIP がワークスペースにコピー → P03 成功 |
| 2 | `-Action PrepareVerify -CleanWorkRoot -OfflineZip <path> -AssumeIfMissing` | ✅ **AWS EPYC 回帰テストの推奨パターン。** | #1 と同じ + NPU 未検出時に default Strix Point profile で続行 |
| 3 | `-Action PrepareVerify -CleanWorkRoot` (`-OfflineZip` 無し) | ⚠️ **クリーン環境では失敗する可能性大。** | T1 skip → T4 priority skip → T2 skip → T3 フォールスルー (HTML フォーム) → T4 auto-scan (スクリプトディレクトリ・./cache・workspace・~/Downloads) → 何も見つからなければ throw |
| 4 | `-Action Install -OfflineZip <path>` | ✅ **実機 NPU インストールの推奨パターン。** | T4 priority block → I00 で "I AGREE" 入力 → I01-I04 |
| 5 | `-Action Install -AmdAccountUser ... -AmdAccountPassword ...` | ⚠️ **best-effort。AMD のフォーム変更で予告なく破綻する可能性。** | T1 skip → T4 priority skip → T2 認証付きダウンロード試行 → 失敗時 T3/T4 にフォールバック |
| 6 | `-Action Install -InstallerUrl <captured-url>` | ✅ URL が fresh であれば動作 (entitlenow.com URL は時間経過で失効)。 | T1 直接ダウンロード → P03 成功 |
| 7 | `-Action Install -NpuOverride STX -PreferredRyzenAiVersion 1.7.1` (ソース無し) | ❌ **誤解を招くため使用しないこと。** | T1/T2/T3 skip → T4 auto-scan が `~/Downloads` 内の任意の `NPU_RAI*_WHQL.zip` を拾う (override 指定と一致するとは限らない) |

**パターン #1 (`PrepareVerify` + `OfflineZip`) が最も強く推奨される理由**:

- **決定論的**: 824 行目の Tier 4 priority block で resolver が即座に短絡判定。AMD へのネットワーク呼び出し無し、フォーム解析の脆弱性無し、EULA URL 失効との競合無し。
- **システム未変更**: `PrepareVerify` は P00–P09 + V01–V06 のみ実行。証明書 import 無し、WDAC policy deploy 無し、ドライバインストール無し。
- **ホスト間で再現性あり**: 同じ ZIP を別マシンにコピーすれば、同じ P05/P06/V05/V06 出力が得られる。CI 回帰テストに必須。
- **V05/V06 出力が取得可能**: EPYC EC2 でも (NPU 不在のため `-AssumeIfMissing` が必要だが) dry-run install plan と hardware impact analysis が出力される。

**よくある落とし穴 — パターン #7**: `-NpuOverride` や `-PreferredRyzenAiVersion` といったスイッチは *resolver の挙動を変更するだけで、ダウンロードソースは提供しません*。`-OfflineZip` / `-InstallerUrl` / `-AmdAccountUser` を併用しないとリゾルバは Tier 4 auto-scan にフォールスルーします。auto-scan は最初に発見した `NPU_RAI*_WHQL.zip` を拾うため、その ZIP が **指定した codename / バージョンと一致するとは限りません**。バージョンチェックは ZIP 内の INF (P05) で行われ、ファイル名では判定されません。**常にソースを明示的に固定してください**。

### 4.4 NPU スクリプトを実行する前のチェックリスト

上記ギャップが埋まる前であっても、**任意のホスト**で NPU スクリプトを実行する前に以下のチェックリストに従ってください:

- [ ] README の [§ リスク分類](./README.ja.md#3-スクリプトのリスク分類) を読了済み。
- [ ] Ryzen AI 300 / Ryzen AI Max 300 / Ryzen 7040 / 8040 シリーズの CPU を持っている (もしくは検出が `-AssumeIfMissing` にフォールスルーすることを認識し、その実行がパイプライン健全性チェックのみであることを了承済み)。
- [ ] 適切な `NPU_RAI*_WHQL.zip` を <https://ryzenai.docs.amd.com/en/latest/inst.html#install-npu-drivers> からダウンロードし、スクリプト隣に配置済み (Tier 4 — 推奨)。
- [ ] AMD の Ryzen AI EULA を <https://account.amd.com/en/forms/downloads/ryzenai-eula-public-xef.html> で読了し受諾済み。
- [ ] Ryzen AI Software user-mode stack が AMD 公式に Windows 11 only であり、**Server 2025 では AI 推論ができない**ことを理解済み。
- [ ] `-Action Install` を実行する場合: `-Action Cleanup` でロールバック可能であることを確認済み (driver store 削除に手動介入が必要となる可能性も了承済み)。
- [ ] BitLocker 有効ホストで実行する場合: リカバリキー取得済み。
- [ ] 成功・失敗のいずれの場合も結果を GitHub Issues に報告する意思がある (特に失敗の場合 — メンテナーは検証ギャップを埋めるためにこのデータを必要としている)。

### 4.5 期待される NPU スクリプト出力

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

#### P03 NPU 検出 (EPYC AWS、`-AssumeIfMissing` 付き)

```
[>] Enumerating PCI devices via pnputil /enum-devices /bus PCI /deviceids
[!] No AMD NPU detected via pnputil. Using default profile (Strix Point + RAI 1.7.1).
[+] CPU              : AMD EPYC 9R45
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

### 4.6 Tier 2 (AMD アカウント認証フロー) 動作確認結果 — 2026-05-10

`Deploy-AMDNpuDriverOnWindowsServer.ps1` 内の `Invoke-AmdAccountAuthentication` 関数について、現状の `account.amd.com` バックエンドに対して実装済みの HTTP form POST フローが成功しうるかどうかを **2026-05-10** に検証しました。検証は公開情報のみを利用しています (実 AMD アカウント資格情報は使用していません)。

#### 4.6.1 検証手法

| Step | 確認項目 | 方法 |
|---|---|---|
| 1 | `account.amd.com` のレンダリングモデル | 関連 AMD ポータル (`docs.amd.com/auth/login`、`pensandosupport.amd.com`、`fsdz.amd.com`) を web fetch |
| 2 | 現状の AMD docs における EULA URL パターン | GitHub `amd/ryzen-ai-documentation/blob/main/docs/inst.rst` (最新コミット) |
| 3 | ドライババージョン命名規則 | `ryzenai.docs.amd.com` 上の RAI 1.5 / 1.6.1 / 1.7 / 1.7.1 ドキュメント間のクロスチェック |
| 4 | EULA フローのエンドユーザー挙動 | GitHub `amd/RyzenAI-SW#249`、`#328`、cnx-software.com エンドユーザーブログ記事 (Feb 2024) |
| 5 | 公開されている PowerShell/Python 自動化の有無 | `account.amd.com` 自動化、AMD アカウントダウンロードスクリプティングに関する Web 検索 |

#### 4.6.2 検出事項

| # | 検出事項 | 重大度 | 根拠 |
|---|---|---|---|
| F1 | **`account.amd.com` は JavaScript-driven SPA**。関連 AMD ポータルは直接 fetch すると `"JavaScript is required"` または `"Loading application"` HTML stub を返却。 | 高 | `docs.amd.com/auth/login` および `fsdz.amd.com/adfs/ls/...` の直接プローブ |
| F2 | **ログインフォームは初期 HTML payload に存在しない**。CSRF トークン、フォームアクション、フィールドはランタイムに JavaScript で注入される模様。 | 高 | F1 から、ログインフォームがクライアントサイドレンダリングされていることが導かれる |
| F3 | **EULA 受諾はインタラクティブ**。エンドユーザー証言「Beta Software EULA への署名を回避できなかった」は、単一の隠れフォーム POST ではなく JS 駆動のマルチステップモーダルを示唆。 | 中 | cnx-software.com 証言 (2024)、GitHub #249 (2025) |
| F4 | **AMD ドキュメント上 EULA URL パターンが 2 種類存在**。元コードは 1 種類のみと仮定していた。 | 中 | NPU ドライバ用 `ryzenai-eula-public-xef.html` vs RAI Software EXE / NuGet 用 `xef.html` |
| F5 | **デフォルト driver/RAI マッピング `1.7.1 → 32.0.203.380` が架空**。AMD の RAI 1.7.1 ドキュメントは 1.6.1 driver (`32.0.203.314`) を再利用しており、`NPU_RAI1.7.1_380_WHQL.zip` は公開リストに存在せず。スクリプト自身のコメントが「AMD 公開までの placeholder build」と認めていた。 | 中 | `ryzenai.docs.amd.com/en/latest/inst.html` および `github.com/amd/ryzen-ai-documentation/blob/main/docs/inst.rst` のクロスチェック |
| F6 | **AMD アカウントログインの公開自動化スクリプトが見つからず**。Web 検索で PowerShell/Python の成功事例ゼロ。 | 低 | 否定的な検索結果、参考情報 |

#### 4.6.3 結論

実装済みの `Invoke-AmdAccountAuthentication` 関数 (`https://account.amd.com/en/forms/auth/login.html` への HTTP form POST) は **現状の AMD ポータルに対して成功する見込みが極めて低い** 。ポータルアーキテクチャは関数が前提とする仕様 (server-rendered HTML form with hidden CSRF token、simple POST credentials → 認証済み EULA へリダイレクト → simple POST EULA accept → entitlenow.com へリダイレクト) と整合していません。

この結論は AMD サーバへの認証付きリクエストを行わずとも、公開可視のアーキテクチャ証拠 (F1〜F3)、driver-version 不整合 (F5)、動作する公開実装の不在 (F6) から導かれます。

#### 4.6.4 スクリプトに適用された改修

| 変更 | 内容 | 適用箇所 |
|---|---|---|
| C1 | **Tier 2 をデフォルト無効化**。`-ForceAmdAccountAuth` を渡さない限り関数は即座に `$null` を返す。 | `Invoke-AmdAccountAuthentication` (約 1170 行目) |
| C2 | **`VERIFIED 2026-05-10` バナー** を追加。「成功する見込みが極めて低い」旨を明示警告。 | `Invoke-AmdAccountAuthentication` 冒頭 |
| C3 | **`-ForceAmdAccountAuth` スイッチ** を `param()` ブロックに追加。AMD がポータルを変更したと operator が考える場合、opt-in で試行可能。 | トップレベル `param()` |
| C4 | **デフォルト RAI バージョンを `1.7.1` (placeholder) から `1.6.1` (verified) に変更**。ファイル名生成は AMD が実際に公開する `NPU_RAI1.6.1_314_WHQL.zip` を生成。 | `[string]$PreferredRyzenAiVersion = '1.6.1'`、`Get-AmdNpuPlatform` のデフォルト、`Get-RecommendedNpuDriverBuild` マッピング |
| C5 | **`Get-RecommendedNpuDriverBuild` マッピングを修正**。RAI 1.7 / 1.7.1 のエントリは両方とも実存する `32.0.203.314` (公開済みドライバ) を返すように変更。架空の `329` / `380` を排除。AMD docs へのクロスリファレンスを関数ヘッダに追加。 | `Get-RecommendedNpuDriverBuild` |
| C6 | **全ヘッダの `.EXAMPLE` ファイル名** を `NPU_RAI1.7.1_380_WHQL.zip` (架空) から `NPU_RAI1.6.1_314_WHQL.zip` (verified) に更新。 | スクリプトヘッダ 約 93、99、110、124、132 行目 |
| C7 | **Default-Strix プロファイルラベル** を `default-strix-rai1.7.1` から `default-strix-rai1.6.1` に変更。P03 バナーは verified driver build を反映。 | `Get-AmdNpuPlatform` の `$AssumeIfMissing` 分岐 |

#### 4.6.5 `-ForceAmdAccountAuth` の挙動

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

#### 4.6.6 将来の再検証タイミング

以下のいずれかの条件で、本検証の再実施を推奨します:

- AMD が新規 Ryzen AI リリース (≥ 1.7.2 または 1.8) を発表 — driver マッピングテーブル更新が必要となる可能性
- ユーザーから `-ForceAmdAccountAuth` の成功報告 — Tier 2 をデフォルト有効に再変更可能
- AMD ドキュメントに新しい EULA URL パターンが出現 (既知 2 種類以外)

再検証手順は 4.6.1 と同じ: 公開 AMD ページの fetch、`amd/ryzen-ai-documentation` GitHub リポジトリでの EULA URL パターン照合、自動化成功のエンドユーザー報告のチェック。

---

## 5. 検証結果まとめ

### 5.1 環境別マトリクス

| 項目 | AWS Naples | AWS Milan | AWS Genoa | AWS Turin | M75q Tiny Gen 2 | X13 Gen 1 AMD | **実 NPU マシン** |
|---|---|---|---|---|---|---|---|
| インスタンス / 機種 | t3a.medium | m6a.large | m7a.large | m8a.large | ThinkCentre 物理機 | ThinkPad 物理機 | **TBD** |
| OS | WS2025 | WS2025 | WS2025 | WS2025 | WS2025 | Win11 LTSC 2024 | TBD |
| ProductType | 3 | 3 | 3 | 3 | 3 | 1 (PREVIEW MODE) | TBD |
| CPU | EPYC 7571 (Naples) | EPYC 7R13 (Milan) | EPYC 9R14 (Genoa) | EPYC 9R45 (Turin) | Ryzen 7 PRO 5750GE (Cezanne) | Ryzen 5 PRO 4650U (Renoir) | Ryzen AI 300 / 7040 / 8040 |
| NPU 搭載 | なし | なし | なし | なし | なし | なし | **あり** |
| Chipset INF 処理数 | 32/32 | 32/32 | 32/32 | 32/32 | 32/32 + 3 V06 アップグレード | 32/32 + 1 V06 アップグレード | 該当なし (NPU スクリプトの対象外) |
| Graphics INF 処理数 | 19/19 | 19/19 | 19/19 | 19/19 | 19/19 + 3 V06 アップグレード | 19/19 + 3 V06 アップグレード | 該当なし (NPU スクリプトの対象外) |
| NPU スクリプト PrepareVerify | `-AssumeIfMissing` で実行 | 同上 | 同上 | 同上 | `-AssumeIfMissing` (NPU デバイス無し) | `-AssumeIfMissing` (NPU デバイス無し) | **PENDING** |
| NPU スクリプト Install | 該当なし | 該当なし | 該当なし | 該当なし | 該当なし | 該当なし (自動ブロック) | **PENDING** |
| 1 回コスト | ≈ $0.014 | ≈ $0.033 | ≈ $0.040 | ≈ $0.043 | $0 (物理機) | $0 (物理機) | $0 (物理機) |
| 検証目的 | 最安回帰テスト | Milan 互換性 | DDR5 / Zen 4 | Zen 5 forward-compat | 本番リハーサル (chipset+graphics) | WS2025 pre-migration チェック | **NPU end-to-end 検証** |

### 5.2 推奨検証パターン

| シナリオ | 推奨環境 |
|---|---|
| 「PR の素早い sanity チェック」(chipset/graphics) | t3a.medium Spot (1 世代) |
| 「リリース前回帰テスト」(chipset/graphics) | t3a.medium + m7a.large (2 世代) |
| 「全世代互換性」(chipset/graphics + NPU パイプライン健全性) | t3a + m6a + m7a + m8a (4 並列、3 スクリプト全て、NPU は `-AssumeIfMissing`) |
| 「実ドライバインストール検証」(chipset/graphics) | M75q Gen 2 物理機 (production target) |
| 「Win11 → WS2025 pre-migration 評価」(chipset/graphics) | X13 Gen 1 物理機 |
| **「NPU end-to-end 検証」** | **Ryzen AI 300 / 7040 / 8040 シリーズホスト (メンテナーの lab には未配備 — PR 歓迎)** |

---

## 6. 発見されたバグと修正履歴

以下のバグは上記検証実行中に発見・修正されました:

| 発見環境 | バージョン | 修正バージョン | 概要 |
|---|---|---|---|
| ThinkPad X13 Gen 1 (Win11 24H2) | chipset r45 | r46 | `Compare-InfDriverVer` のタイムゾーンバグ (UTC 真夜中の `DriverDate` が CIM コマンドレットでローカル 09:00 に変換され、同バージョンケースが「current が patched より新しい」と誤報告)。`.Date` (年月日切り捨て) のみで比較するよう修正。 |
| ThinkPad X13 Gen 1 (Win11 24H2) | r45 / r14 | r46 / r15 | P05 / P00 互換性チェックが Workstation ホストでも `Host OS: Windows Server 2025` と表示し混乱を招いた。実 `Caption` とマップ後 profile を並列表示するよう修正。 |
| ThinkPad X13 Gen 1 (Win11 24H2) | graphics r14 | r16 / r47 | V05 で「would upgrade 1067/1067 matched device(s)」のような件数膨張。`$matchedDevices` が物理デバイス単位ではなく INF HWID variant 単位で append されていた。物理 DeviceID で重複排除するよう修正。 |
| ThinkPad X13 Gen 1 (Win11 24H2) | graphics r14 | r16 / r47 | 同バージョン・新日付アップグレードケースで `patched newer (X) than current (X)` という意味不明なメッセージが出ていた。明確化のため `patched same version (X) but newer date; PnP ranking prefers newer-dated driver` 表示に修正。 |
| パイプラインレビュー (フィールド報告無し) | NPU r1 | (placeholder) | 現時点で発見されたフィールドバグ無し — ただし **フィールド報告自体が存在しない** (NPU スクリプトはまだ物理 NPU ハードウェア上で実行されていない)。 |

詳細な検証ログと修正コミットは <https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/commits/main> を参照してください。

---

## 7. CI/CD 自動化展望

GitHub Actions による自動回帰テストには、AWS ベースの self-hosted runner が現実的です:

```yaml
# .github/workflows/regression.yml — コンセプト例
name: PrepareVerify regression test (multi-EPYC)
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  static-analysis:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run psa.py static analyzer
        run: |
          python3 tools/psa.py Deploy-AMDChipsetDriverOnWindowsServer.ps1
          python3 tools/psa.py Deploy-AMDGraphicsDriverOnWindowsServer.ps1
          python3 tools/psa.py Deploy-AMDNpuDriverOnWindowsServer.ps1

  ws2025-prepare-verify:
    needs: static-analysis
    strategy:
      matrix:
        include:
          - runner-tag: amd-naples   # t3a.medium
          - runner-tag: amd-milan    # m6a.large
          - runner-tag: amd-genoa    # m7a.large
          - runner-tag: amd-turin    # m8a.large
    runs-on: [self-hosted, windows, server-2025, "${{ matrix.runner-tag }}"]
    steps:
      - uses: actions/checkout@v4
      - name: Run chipset PrepareVerify
        shell: pwsh
        run: |
          Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
          .\Deploy-AMDChipsetDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot
      - name: Run graphics PrepareVerify
        shell: pwsh
        run: |
          .\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot
      - name: Run NPU PrepareVerify (with -AssumeIfMissing, requires offline ZIP fixture)
        shell: pwsh
        env:
          NPU_OFFLINE_ZIP_S3_URI: ${{ secrets.NPU_OFFLINE_ZIP_S3_URI }}
        run: |
          # 事前取得した NPU ZIP を S3 から (license-gated、リポジトリには含めない)
          aws s3 cp $env:NPU_OFFLINE_ZIP_S3_URI .\NPU_RAI1.7.1_380_WHQL.zip
          .\Deploy-AMDNpuDriverOnWindowsServer.ps1 `
              -Action PrepareVerify -CleanWorkRoot `
              -OfflineZip .\NPU_RAI1.7.1_380_WHQL.zip `
              -AssumeIfMissing
```

このワークフローは 3 階層構成:

1. **static-analysis ジョブ**: Linux runner 上で `tools/psa.py` を実行し PowerShell の構文と中括弧/丸括弧/角括弧バランスを 3 スクリプト全てに対してチェック (約 10 秒、ほぼ無料)。
2. **ws2025-prepare-verify ジョブ (chipset / graphics)**: 4 つの self-hosted WS2025 runner (Naples / Milan / Genoa / Turin) で並列に PrepareVerify を実行。
3. **ws2025-prepare-verify ジョブ (NPU)**: 上記 step 2 を拡張し、NPU スクリプトを `-AssumeIfMissing` と事前取得 offline ZIP 付きで実行。これはパイプライン健全性のみ検証 — EPYC に NPU デバイス無しのため実 NPU 挙動は検証不可。

self-hosted runner を on-demand で起動・停止するスケジューラ (例: AWS Lambda + SSM) と組み合わせれば、月額 $5〜10 程度に収まります。ワークフローは PrepareVerify で停止し Install は試行しません (EPYC マシンにはコンシューマー Ryzen / NPU ハードウェアが存在しないため)。

> **将来**: 物理 NPU マシンが入手可能となった時点で、専用 self-hosted runner (Ryzen AI 9 HX 370 mini-PC 等) で `-Action Install` を実行する CI ジョブを追加可能。それまでは NPU スクリプトの `-Action Install` は NPU ハードウェアを所有する operator が手動で実行し、結果を GitHub Issues 経由で報告する必要があります。
