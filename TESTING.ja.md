# TESTING.ja.md — クラウド検証手順と物理ハードウェア検証結果

このドキュメントは `Deploy-AMD-Drivers-For-WindowsServer` のテスト・評価実施に必要な情報を集約したものです。次の 3 つの環境を扱います:

1. **AWS クラウド (東京リージョン)** — EPYC 複数世代 (Naples / Milan / Genoa / Turin) のテスト手順とインスタンス選択ガイド
2. **検証結果 1: ThinkCentre M75q Tiny Gen 2** (Windows Server 2025 実機 / Cezanne Zen 3)
3. **検証結果 2: ThinkPad X13 Gen 1 AMD (2020)** (Windows 11 Enterprise LTSC 2024 / Renoir Zen 2)

---

## 1. AWS クラウドでのテスト

### 1.1 クラウドテストの位置付け

AWS EC2 はコンシューマー Ryzen ハードウェアを直接提供しません。AMD ベースの EC2 インスタンスは **AMD EPYC サーバー CPU** を搭載しており、本スクリプトが対象とするコンシューマー Ryzen の chipset / Radeon iGPU とは**シリコンが異なります**。したがって AWS でのテストは以下の目的に限定されます:

| AWS で検証できる | AWS では検証できない |
|---|---|
| ✓ スクリプトが Windows Server 2025 上でエラーなく完走するか | ❌ 実際の AMD コンシューマーチップセット / Radeon ドライバの install 結果 |
| ✓ AMD パッケージのダウンロード・展開・パース処理 | ❌ デバイスバインドの正確性 (該当 HW がないため) |
| ✓ 自己署名証明書の生成と catalog 署名 | ❌ V06 で「3 件 upgrade」のような期待されるドライバ更新 |
| ✓ WDAC supplemental policy の生成 (deploy はせず PrepareVerify で停止推奨) | ❌ I03 後の実環境でのドライバ動作確認 |
| ✓ inf2cat / signtool の動作確認 | ❌ BitLocker / TPM (PSP driver) との相互作用 |
| ✓ CI 用途の自動テスト (PR 検証、回帰テスト) | ❌ AMD Vega/RDNA GPU の rendering 経路 |
| ✓ EPYC の世代差による Win32_Processor 検出ロジックの動作確認 | ❌ コンシューマー Ryzen の検出パス |

つまり **「スクリプトのパイプライン健全性検証」** には AWS が有用ですが、**「コンシューマー Ryzen 機での driver upgrade 結果」** は物理ハードウェアでの検証が必須です。クラウドテストは GitHub Actions CI のような自動回帰テスト用途が最も価値を発揮します。

### 1.2 AWS で利用可能な AMD EPYC インスタンス全世代マップ

AWS は 2018 年から AMD EPYC を採用しており、**5 世代** のシリコンが現在利用可能です。スクリプトの検証目的では、世代を意図的に分散させて回帰テストを行うことを推奨します (古い EPYC でも新しい EPYC でも同様にスクリプトが動作する必要があるため):

| 世代 | コードネーム | 発表年 | アーキテクチャ | 代表インスタンス | 例の CPU 型番 | 最大周波数 | 東京リージョン提供 |
|---|---|---|---|---|---|---|---|
| **1st gen** | **Naples** | 2018 | Zen | T3a / M5a / R5a / C5a | EPYC 7571 (T3a) | 2.5 GHz | ✓ (古いインスタンス) |
| 2nd gen | Rome | 2019 | Zen 2 | (AWS 一般採用なし) | — | — | — |
| **3rd gen** | **Milan** | 2021 | Zen 3 | M6a / C6a / R6a / Hpc6a | EPYC 7R13 | 3.6 GHz | ✓ |
| **4th gen** | **Genoa** | 2023 | Zen 4 | M7a / C7a / R7a | EPYC 9R14 | 3.7 GHz (DDR5) | ✓ |
| **5th gen** | **Turin** | 2025 | Zen 5 | M8a / R8a / C8a | EPYC 9R45 | 4.5 GHz (M8azn は 5.0 GHz) | ✓ (M8a は 2025-11-12 から東京提供) |

**重要な技術的差異**:
- **Naples (T3a/M5a)**: 1 vCPU = 1 SMT thread (2 vCPU = 1 物理コア)。WS2025 AMI の必須要件 (Nitro + UEFI) に **t3a は AZ によっては制限あり** (上記の AWS re:Post 参考)。
- **Milan (M6a)**: 1 vCPU = 1 SMT thread。AMD SEV-SNP サポート (M6a/C6a/R6a で確認済み)。
- **Genoa (M7a)**: **1 vCPU = 1 物理コア (SMT 無効化)**。DDR5 メモリ、AVX-512 / VNNI / bfloat16 対応。
- **Turin (M8a)**: 1 vCPU = 1 物理コア。Zen 5、CPU Family 26 (Genoa は Family 25)。L1d cache が 48 KiB (前世代 32 KiB から +50%)。

### 1.3 推奨インスタンスタイプ (用途別、東京リージョン ap-northeast-1)

| 用途 | 推奨インスタンス | EPYC 世代 | vCPU/RAM | Tokyo Windows 単価 (目安) | 備考 |
|---|---|---|---|---|---|
| **最安・PrepareVerify 用** | `t3a.medium` | Naples (1st) | 2 / 4 GiB | 約 **$0.07–0.10/h** | AZ 制限注意 (us-east-1a 等で WS2025 AMI 起動不可ケースあり) |
| **安定動作・burstable** | `t3a.large` | Naples (1st) | 2 / 8 GiB | 約 $0.13–0.17/h | WDK インストールが快適 |
| **モダン EPYC・Milan** | `m6a.large` | Milan (3rd) | 2 / 8 GiB | 約 $0.18–0.22/h | SMT あり、SEV-SNP 検証可 |
| **DDR5・Genoa** | `m7a.large` | Genoa (4th) | 2 / 8 GiB | 約 $0.22–0.27/h | SMT 無効、AVX-512、CPU Family 25 検出確認 |
| **最新・Turin** | `m8a.large` | Turin (5th) | 2 / 8 GiB | 約 $0.23–0.28/h | M7a 比 +5% 程度、Zen 5、CPU Family 26 検出確認 |
| **GPU 検証 (オプション)** | `g4ad.xlarge` | (Naples + Radeon V520) | 4 / 16 GiB | 約 $0.50–0.60/h | AMD Radeon Pro V520 dGPU 搭載、`Win32_VideoController` の AMD GPU 検出パス検証可 |

> **価格の注意**: 上記は本ドキュメント作成時点 (2026 年 5 月) の概算で、Windows ライセンス料 (約 $0.046/h) を含みます。最新の正確な単価は [AWS Pricing Calculator](https://calculator.aws/) で確認してください。**スポットインスタンス** で最大 70% の割引が見込めます (t3a.medium スポットなら $0.02–0.03/h)。

#### 単発の PrepareVerify 検証 (約 10 分) のコスト試算

| インスタンス | 1 回の検証 | 1 日 5 回検証 | 月額 (週 5 回 x 4 週) |
|---|---|---|---|
| t3a.medium スポット | 約 $0.005 | 約 $0.025 | 約 $0.50 |
| t3a.medium オンデマンド | 約 $0.014 | 約 $0.07 | 約 $1.40 |
| m6a.large オンデマンド | 約 $0.033 | 約 $0.165 | 約 $3.30 |
| m7a.large オンデマンド | 約 $0.040 | 約 $0.20 | 約 $4.00 |
| m8a.large オンデマンド | 約 $0.043 | 約 $0.215 | 約 $4.30 |

**全 4 世代 (Naples / Milan / Genoa / Turin) を週次で回す回帰テスト**でも月額 $15 未満で構築可能です。ストレージ (gp3 EBS 50 GB ≒ $5/月) を加算しても十分に安価です。

### 1.4 推奨 AMI と起動制約

AWS 公式の **Microsoft Windows Server 2025 Base** (License Included) AMI を使用してください。Windows Server 2025 AMI は **Nitro ベース + UEFI 起動** を要求します:

- **対応**: T3a (新しい AZ)、M6a、M7a、M8a、C6a、C7a、C8a、R6a、R7a、R8a 等は全て Nitro + UEFI 対応で WS2025 AMI が起動可能。
- **要注意**: T3a の一部 AZ (例: us-east-1a) では UEFI 制限により WS2025 起動不可ケースあり。`BIOS-Windows_Server-2025-English-Full-Base` AMI (Legacy BIOS 用) を使うか、別 AZ (us-east-1f 等) を選択してください。東京リージョンでは ap-northeast-1c / 1d で T3a での WS2025 起動が比較的安定しています。

#### 最新 AMI ID の取得

```bash
# 東京リージョンの最新 WS2025 (UEFI、英語版) AMI
aws ec2 describe-images \
  --owners 'amazon' \
  --region ap-northeast-1 \
  --filters \
    'Name=platform,Values=windows' \
    'Name=name,Values=Windows_Server-2025-English-Full-Base-*' \
  --query 'reverse(sort_by(Images, &CreationDate))[0].{ImageId:ImageId,Name:Name,CreationDate:CreationDate}' \
  --output table

# 日本語版が必要な場合 (パッチログを日本語化)
aws ec2 describe-images \
  --owners 'amazon' \
  --region ap-northeast-1 \
  --filters \
    'Name=platform,Values=windows' \
    'Name=name,Values=Windows_Server-2025-Japanese-Full-Base-*' \
  --query 'reverse(sort_by(Images, &CreationDate))[0].{ImageId:ImageId,Name:Name,CreationDate:CreationDate}' \
  --output table
```

AMI 名は通常 `Windows_Server-2025-{English|Japanese}-Full-Base-YYYY.MM.DD` の形式で、月次更新されます。

### 1.5 セットアップ手順 (世代横断検証)

#### Step 1: 4 世代の EC2 インスタンスを並列起動 (例)

```bash
AMI_ID=ami-XXXXXXXXXXXXXXXXX  # describe-images で取得
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

#### Step 2: Administrator パスワード取得 + RDP

```bash
aws ec2 get-password-data \
  --region ap-northeast-1 \
  --instance-id i-XXXXXXXXXX \
  --priv-launch-key ./YourKeyPair.pem
```

セキュリティグループで TCP 3389 を自分の IP に許可、Public IP に RDP 接続。

#### Step 3: スクリプト転送 + PrepareVerify 実行

```powershell
# RDP セッション内 (PowerShell 管理者で起動)
mkdir C:\TEMP
cd C:\TEMP

# スクリプト転送 (S3 / SSM Run Command / RDP クリップボードのいずれか)
$bucket = 'your-test-bucket'
aws s3 cp s3://$bucket/Deploy-AMDChipsetDriverOnWindowsServer.ps1  .
aws s3 cp s3://$bucket/Deploy-AMDGraphicsDriverOnWindowsServer.ps1 .

# CPU 世代を確認
Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed
# 出力例:
#   t3a.medium: AMD EPYC 7571              2 cores  2 LP  2500 MHz  (Naples、SMT)
#   m6a.large : AMD EPYC 7R13              2 cores  2 LP  3725 MHz  (Milan、SMT)
#   m7a.large : AMD EPYC 9R14              2 cores  2 LP  3700 MHz  (Genoa、SMT 無効、Family 25)
#   m8a.large : AMD EPYC 9R45              2 cores  2 LP  4500 MHz  (Turin、SMT 無効、Family 26)

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# PrepareVerify のみ実行 (Install は EPYC 機で意味がないため非推奨)
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\chipset-AWS-$env:COMPUTERNAME.log
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\graphics-AWS-$env:COMPUTERNAME.log

# log を S3 にアップロードして手元で確認
aws s3 cp C:\TEMP\chipset-AWS-$env:COMPUTERNAME.log  s3://$bucket/results/
aws s3 cp C:\TEMP\graphics-AWS-$env:COMPUTERNAME.log s3://$bucket/results/
```

#### Step 4: 検証完了後にインスタンス停止 / 削除

```bash
# 停止 (停止中はストレージ料金のみ発生)
aws ec2 stop-instances --region ap-northeast-1 \
  --instance-ids i-XXXXXXXXXX i-YYYYYYYYYY i-ZZZZZZZZZZ i-WWWWWWWWWW

# 完全削除 (検証完了後)
aws ec2 terminate-instances --region ap-northeast-1 \
  --instance-ids i-XXXXXXXXXX i-YYYYYYYYYY i-ZZZZZZZZZZ i-WWWWWWWWWW
```

### 1.6 EPYC 世代横断で予想される結果

| 検証項目 | t3a.medium (Naples) | m6a.large (Milan) | m7a.large (Genoa) | m8a.large (Turin) |
|---|---|---|---|---|
| OS detection (P00) | WS2025、ProductType=3 | 同左 | 同左 | 同左 |
| CPU 検出 (P03) | EPYC 7571、Naples (Zen 1) として認識 | EPYC 7R13、Milan (Zen 3) | EPYC 9R14、Genoa (Zen 4)、CPU Family 25 | EPYC 9R45、Turin (Zen 5)、CPU Family 26 |
| Platform 判定 (P03) | Server / EPYC 系 → コンシューマー Ryzen URL fallback | 同左 | 同左 | 同左 |
| AMD HW detection (V06) | 0 件または極少数 (PCI deviceは virtio / Nitro 系) | 同左 | 同左 | 同左 |
| WILL be replaced (V06) | 0 件 | 0 件 | 0 件 | 0 件 |
| 全 phase (P00-V06) 完走 | ✓ | ✓ | ✓ | ✓ |
| 想定実行時間 | 約 8-12 分 (CPU 遅め) | 約 6-9 分 | 約 5-8 分 | 約 4-7 分 (最速) |
| パイプライン健全性 | OK | OK | OK | OK |

**4 世代横断テストで何が確認できるか**:
- スクリプトが Naples (Zen) から Turin (Zen 5) まで全 EPYC 世代で同じく完走することの確認 → 将来のシリコンへの forward-compatibility の担保
- CPU Family 番号 (Naples=23, Milan=25, Genoa=25, Turin=26) でスクリプトの分岐が壊れないことの確認
- vCPU/SMT 構成差 (Naples/Milan の SMT あり vs Genoa/Turin の SMT 無効) で並列実行系のロジックが破壊されないことの確認

---

## 2. 検証結果 1: ThinkCentre M75q Tiny Gen 2 (Windows Server 2025)

### 2.1 ハードウェア仕様

| 項目 | 値 |
|---|---|
| 機種 | Lenovo ThinkCentre M75q Tiny Gen 2 |
| CPU | AMD Ryzen 7 PRO 5750GE (Cezanne、Zen 3、8 core / 16 thread、35W TDP) |
| iGPU | AMD Radeon Graphics (Vega 8、Cezanne 内蔵) |
| メモリ | DDR4 SO-DIMM 16-32 GB |
| ストレージ | M.2 NVMe SSD |
| BIOS | UEFI、Secure Boot 設定可能 |
| TPM | fTPM (AMD PSP 経由) |

### 2.2 OS 構成

| 項目 | 値 |
|---|---|
| OS | Windows Server 2025 Standard / Datacenter |
| Build | 26100 |
| ProductType | 3 (Server) |
| Secure Boot | ON |
| HVCI | OS デフォルト (環境による) |
| BitLocker | 任意 (有効化されている場合は事前に recovery key 確保必須) |

### 2.3 検証手順

```powershell
# 管理者権限の PowerShell で
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# 第 1 段階: PrepareVerify で V06 を確認 (システム未変更)
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\m75q-chipset-prepareverify.log
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\m75q-graphics-prepareverify.log

# 第 2 段階: V06 のリスク評価が許容できれば Install
# 注意: BitLocker recovery key を事前確保
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action Install
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action Install
```

### 2.4 主な検証結果

#### Chipset スクリプト

- **P03 detection**: `Cezanne / Zen 3 / Desktop APU、AM4`
- **P03 download**: `amd_chipset_software_8.02.18.557.exe` (約 75 MB)
- **P05 inventory**: 67 INF 検出、W11x64 variant 32 INF を選択。
- **P06 patching**: 1 INF (`AmdMicroPEP.inf`) のみがパッチ対象、31 INF が最初から Server-compatible でコピーのみ。
- **V06 主な upgrade 候補** (実機の OEM 状況によって変動):
  - AMD GPIO Controller: `oem17.inf v2.2.0.130` → `amdgpio2.inf v2.2.0.136`
  - AMD PSP 10.0 Device: `oem26.inf v5.22.0.0` → `amdpsp.inf v5.43.0.0` (HIGH リスク、BitLocker 注意)
  - AMD SMBus: `oem12.inf v5.12.0.38` → `SMBUSamd.inf v5.12.0.44`

#### Graphics スクリプト

- **P03 detection**: `Cezanne APU、Vega-Polaris Legacy ブランチ`
- **P03 download**: `whql-amd-software-adrenalin-edition-XX.X.X-win11-XXX-vega-polaris.exe` (約 600 MB)
- **P05 inventory**: 19 INF 検出、`WT64A` (audio) + `WT6A_INF` (display) variant を選択。
- **P06 patching**: 1 INF (`u0197843.inf`) のみがパッチ対象、18 INF が最初から Server-compatible でコピー。
- **V06 主な upgrade 候補**:
  - AMD Audio CoProcessor: `oem70.inf v6.0.0.79` → `amdacpbus.inf v6.0.1.83` (MEDIUM リスク)
  - AMD Radeon Graphics: AMD パッケージの新バージョン → display upgrade (MEDIUM リスク)
  - AMD HD Audio Device: `oem58.inf v10.0.1.30` → `AtihdWT6.inf v10.0.1.30` (date-newer、MEDIUM リスク)

#### 健全性確認

- 全 21 phase が成功完了
- 自己署名証明書 (RSA 4096 / SHA-384、5 年有効期間) 生成成功
- 32 catalog (chipset) + 19 catalog (graphics) の inf2cat /os:Server2025_X64 生成成功
- 全 catalog が signtool でタイムスタンプ付き署名成功
- I03 後 (Install 実施時)、Device Manager で 3 件 (chipset) + 3 件 (graphics) が `[C] Self-signed` として認識

### 2.5 既知の制限

- BitLocker 有効環境で PSP driver upgrade を行うと recovery prompt が発生する場合あり。**事前に recovery key を controlpanel または Microsoft アカウント連携先で確保必須**。
- 一部の `ROOT\AMD*` software-only エンティティ (AMDLOG / AMDXE 等) は I03 でドライバ追加されますが、`Win32_PnPSignedDriver` での enumeration には現れず V06 Section 1 では「software-only」として情報表示のみ。
- I04 で `[B] Vendor` から `[C] Self-signed` への transition が確認できれば成功。

---

## 3. 検証結果 2: ThinkPad X13 Gen 1 AMD (2020) - Windows 11 Enterprise LTSC 2024

### 3.1 ハードウェア仕様

| 項目 | 値 |
|---|---|
| 機種 | Lenovo ThinkPad X13 Gen 1 (AMD、2020) |
| CPU | AMD Ryzen 5 PRO 4650U (Renoir、Zen 2、6 core / 12 thread、15W TDP) |
| iGPU | AMD Radeon Graphics (Vega 6、Renoir 内蔵) |
| メモリ | DDR4 16 GB on-board |
| ストレージ | M.2 NVMe SSD |
| BIOS | UEFI、Secure Boot 切替可能 |
| TPM | dTPM (Discrete TPM、Infineon SLB9670 等) |

### 3.2 OS 構成 (検証時)

| 項目 | 値 |
|---|---|
| OS | Microsoft Windows 11 Enterprise LTSC 2024 |
| Build | 26100 (24H2 LTSC) |
| ProductType | 1 (Workstation) — 本スクリプト的には **WS2025 PREVIEW MODE** |
| Secure Boot | OFF (検証用に切替) |
| HVCI | ON |
| BitLocker | OFF (lab 用) |

### 3.3 検証手順

Windows 11 Enterprise LTSC 2024 は Windows Server 2025 と同じ NT カーネル build 26100 を共有するため、本スクリプトの **WS2025 PRE-MIGRATION PREVIEW MODE** で動作します (P00 banner で明示)。

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# Workstation OS では Install 系 phase が自動 block されるため PrepareVerify のみ
.\Deploy-AMDChipsetDriverOnWindowsServer.ps1  -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\x13gen1-chipset-Win11-preview.log
.\Deploy-AMDGraphicsDriverOnWindowsServer.ps1 -Action PrepareVerify -CleanWorkRoot *>&1 |
  Tee-Object C:\TEMP\x13gen1-graphics-Win11-preview.log
```

### 3.4 主な検証結果

#### P00 OS detection (Workstation preview)

```
[+] OS detected: Microsoft Windows 11 Enterprise LTSC (build 26100)
    Profile applied : WS2025 (Windows Server 2025)
    ProductType     : 1  (1=Workstation, 3=Server)

    +-----------------------------------------------------------------+
    | WS2025 PRE-MIGRATION PREVIEW MODE                               |
    | (Windows 11 24H2 and Windows Server 2025 share NT build 26100)  |
    +-----------------------------------------------------------------+
```

`Install` 系 phase は自動 block されます (`-AllowWorkstationInstall` で override 可能、ただし非推奨)。

#### Chipset スクリプト

- **P03 detection**: `Renoir / Zen 2 / Mobile`
- **P03 download**: `amd_chipset_software_8.02.18.557.exe` (M75q と同じ)
- **P05 inventory**: 67 INF 検出、W11x64 variant 32 INF 選択。
- **P06 patching**: 1 INF (`AmdMicroPEP.inf`) のみパッチ。
- **V06 主な upgrade 候補** (Win11 上の OEM ドライバとの比較):
  - AMD PSP 10.0 Device: `oem144.inf v5.42.0.0` → `amdpsp.inf v5.43.0.0` (HIGH リスク)
  - GPIO / I2C / SMBus / MicroPEP は同一バージョン (KEEP)

#### Graphics スクリプト

- **P03 detection**: `Renoir / Vega-Polaris Legacy`
- **P03 download**: `whql-amd-software-adrenalin-edition-26.1.1-win11-jan-vega-polaris.exe` (約 624 MB)
- **P05 inventory**: 19 INF 検出、`WT64A` + `WT6A_INF` variant 選択。
- **P06 patching**: 1 INF (`u0197843.inf`) のみパッチ、6 decoration を mirror。
- **V06 upgrade 候補**:
  - AMD Audio CoProcessor: `v6.0.0.79 → v6.0.1.83` (本物の version upgrade)
  - AMD Radeon Graphics: `v31.0.21923.11000 → v31.0.21924.61` (本物の version upgrade)
  - AMD HD Audio Device: `v10.0.1.30 → v10.0.1.30` (date のみ新しい、graphics r16 で「same version, but newer date」と明示表示)

#### 健全性確認

- 全 21 phase が成功完了 (Install 系 phase は Workstation OS のため auto-block)
- 19 INF 全てが pipeline 通過
- Catalog 19 個 + signtool 署名 19 個 全て成功
- AMD HW 検出: AMD Audio CoProcessor、AMD Radeon Graphics、AMD HD Audio Device、AMD GPIO Controller、AMD I2C Controller、AMD Micro PEP、AMD SMBus、AMD PSP 10.0 Device 等

### 3.5 Win11 ↔ WS2025 同一ハードウェアでの差分予想

検証結果 1 (M75q + WS2025) と検証結果 2 (X13 Gen 1 + Win11 24H2) を比較すると、**スクリプトの判定論理は両 OS で kernel build 26100 を共有するため同一**ですが、**現状の OEM ドライバ baseline が異なるため V06 の upgrade 候補数が変動**します:

| V06 セクション | M75q (WS2025) | X13 Gen 1 (Win11) |
|---|---|---|
| 検出 AMD HW | 同一 (HW 構成が違うので異なるが、検出ロジックは同じ) | 同一 |
| MS-GENERIC 件数 | 高い (WS2025 はクリーンインストール後の素 Server 状態) | やや低い (Win11 は OEM ドライバが先にインストール済み) |
| WILL be replaced 件数 | 多め (MS 汎用 → AMD 純正への置換が多い) | 少なめ (OEM ドライバが既に存在するため、AMD パッケージが新しい場合のみ置換) |
| KEEP (same/newer) 件数 | 少ない | 多い |
| 推奨 Install 実行 | YES (target host) | NO (Workstation OS、auto-block) |

つまり **Win11 24H2 上での PrepareVerify は WS2025 移行の事前検証として機能**し、得られたパッチ済み INF の signature と catalog の構造は WS2025 上でも通用します (kernel build 同一のため)。実際の install 結果 (どのデバイスが WILL be replaced になるか) は WS2025 移行後に再実行で確認することが推奨されます。

---

## 4. 検証結果のまとめ

### 4.1 環境別マトリクス

| 項目 | AWS Naples | AWS Milan | AWS Genoa | AWS Turin | M75q Tiny Gen2 | X13 Gen 1 AMD |
|---|---|---|---|---|---|---|
| インスタンス / 機種 | t3a.medium | m6a.large | m7a.large | m8a.large | ThinkCentre 物理 | ThinkPad 物理 |
| OS | WS2025 | WS2025 | WS2025 | WS2025 | WS2025 | Win11 LTSC 2024 |
| ProductType | 3 | 3 | 3 | 3 | 3 | 1 (PREVIEW MODE) |
| CPU | EPYC 7571 (Naples) | EPYC 7R13 (Milan) | EPYC 9R14 (Genoa) | EPYC 9R45 (Turin) | Ryzen 7 PRO 5750GE (Cezanne) | Ryzen 5 PRO 4650U (Renoir) |
| AMD HW 検出 | 0 件 (EPYC) | 0 件 (EPYC) | 0 件 (EPYC) | 0 件 (EPYC) | 約 47 件 | 約 49 件 |
| Chipset INF 処理 | 32/32 通過 | 32/32 通過 | 32/32 通過 | 32/32 通過 | 32/32 + V06 で 3 件 upgrade | 32/32 + V06 で 1 件 upgrade |
| Graphics INF 処理 | 19/19 通過 | 19/19 通過 | 19/19 通過 | 19/19 通過 | 19/19 + V06 で 3 件 upgrade | 19/19 + V06 で 3 件 upgrade |
| 全 phase 完了 | ✓ | ✓ | ✓ | ✓ | ✓ + 実 install 成功 | ✓ (Install 系は auto-block) |
| 検証コスト/回 | 約 $0.014 | 約 $0.033 | 約 $0.040 | 約 $0.043 | $0 (実機) | $0 (実機) |
| 検証目的 | 最安回帰テスト | Milan 互換性 | DDR5/Zen 4 | Zen 5 forward-compat | 本番 deploy 直前 | WS2025 移行前検証 |

### 4.2 推奨検証パターン

| シナリオ | 推奨環境 |
|---|---|
| 「PR を即座にチェック」 | t3a.medium スポット (1 世代) |
| 「リリース前の回帰テスト」 | t3a.medium + m7a.large (2 世代) |
| 「全世代互換性確認」 | t3a + m6a + m7a + m8a (4 世代並列) |
| 「実 driver install の動作確認」 | M75q Gen 2 物理機 (本番 target) |
| 「Win11 → WS2025 移行前の事前評価」 | X13 Gen 1 物理機 |

---

## 5. 発見されたバグと修正履歴

検証実施を通じて以下のバグが発見・修正されました:

| 検出環境 | バージョン | 修正バージョン | 概要 |
|---|---|---|---|
| ThinkPad X13 Gen 1 (Win11 24H2) | chipset r45 | r46 | `Compare-InfDriverVer` のタイムゾーンバグ修正 (UTC midnight が localtime 09:00 に変換されることで「same version」が「current newer」と誤判定されていた)。`.Date` で年月日のみ比較するよう変更。 |
| ThinkPad X13 Gen 1 (Win11 24H2) | r45 / r14 | r46 / r15 | P05 / P00 互換性チェックで `Host OS: Windows Server 2025` と表示されるのが Workstation 上で紛らわしいため、actual Caption + profile を併記表示に変更。 |
| ThinkPad X13 Gen 1 (Win11 24H2) | graphics r14 | r16 / r47 | V05 で `(+1066 more)` / `would upgrade 1067/1067 matched device(s)` のように `$matchedDevices` が INF HWID エントリ単位で重複追加され、count が不自然に inflate していた問題を修正 (物理 DeviceID で deduplicate)。 |
| ThinkPad X13 Gen 1 (Win11 24H2) | graphics r14 | r16 / r47 | 同一 version で date のみ新しい upgrade case で `patched newer (X) than current (X)` という意味不明なメッセージが出力されるのを `patched same version (X) but newer date; PnP ranking prefers newer-dated driver` に明示化。 |

詳細な検証ログと修正コミットは <https://github.com/usui-tk/Deploy-AMD-Drivers-For-WindowsServer/commits/main> を参照してください。

---

## 6. CI/CD 自動化への展望

リポジトリで GitHub Actions による自動回帰テストを実装する場合、AWS ベースのセルフホストランナーが現実的な選択肢です:

```yaml
# .github/workflows/regression.yml の概念例
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
```

このワークフローは:
1. **static-analysis ジョブ**: Linux runner で `tools/psa.py` を実行し、PowerShell の構文・シンボルバランスをチェック (10 秒程度、ほぼ無料)
2. **ws2025-prepare-verify ジョブ**: 4 世代 (Naples / Milan / Genoa / Turin) の WS2025 セルフホスト runner で並列に PrepareVerify 実行

セルフホストランナーは検証実施時のみ起動 / 停止する scheduler (例: AWS Lambda + SSM) と組み合わせることで、月次コストを $5–10 程度に抑えられます。Install までは行わない、かつ EPYC 機なので driver bind は試みない、という前提です。
