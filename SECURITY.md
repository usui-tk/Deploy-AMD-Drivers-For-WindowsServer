# Security Policy

> 🇯🇵 日本語版は本ファイル下部を参照してください。

## Scope

This repository (`Deploy-Drivers-For-WindowsServer`) ships **experimental, lab-grade PowerShell scripts** that patch AMD consumer driver INFs (and Microsoft's inbox Bluetooth PAN driver) to install on Windows Server SKUs, re-sign the resulting catalogs with a host-generated self-signed certificate, and deploy a WDAC supplemental policy to authorise that certificate as a kernel-mode signer. Because the scripts operate inside the OS-layer driver-signing trust chain, security has a high stake here.

This policy covers:

| In scope | Out of scope |
|:---|:---|
| Defects in any of the four scripts (`Deploy-AMDChipsetDriverOnWindowsServer.ps1`, `Deploy-AMDGraphicsDriverOnWindowsServer.ps1`, `Deploy-AMDNpuDriverOnWindowsServer.ps1`, `Deploy-MSBthPanInboxOnWindowsServer.ps1`) that, when executed by a user, introduce a security risk on the user's system (e.g. an INF patch that opens a privilege-escalation path, a `signtool` invocation that signs more than intended, a WDAC policy that authorises broader trust than documented, an insecure download pattern, credential exposure) | Vulnerabilities in **upstream** binaries the scripts re-sign (`amdgpio.sys`, `amdpsp.sys`, `bthpan.sys`, etc.) — report those to AMD or Microsoft via their normal security channels; this repository only re-signs the existing binaries and never modifies them |
| Documentation in `README.md` / `README.ja.md` / `SPEC.md` / `TESTING.md` (per the documentation language policy in `SPEC.md` §A.12, only `README.md` is bilingual; other docs are English only) that, if followed verbatim, would lead a reader to a clearly unsafe operational decision (e.g. instructing operators to disable Secure Boot, run `bcdedit /set testsigning on` permanently, or skip the BitLocker recovery-key capture step) | Generic discussions about self-signed kernel drivers being inherently risky — the [`README.md`](./README.md) Disclaimer section and the [`CODE_OF_CONDUCT.md`](./CODE_OF_CONDUCT.md) Safety section already cover this |
| Real secrets accidentally committed to this repository (PFX passwords, BitLocker recovery keys, AMD account credentials, API tokens that the maintainer intends to keep private) | Cryptographic thumbprints, public-key fingerprints, or WDAC policy GUIDs visible in committed logs — these are not secrets |
| Static-analysis bypasses that allow a malicious PR to pass `psa.py` checks while introducing a security regression | Static-analysis suggestions for hardening rules not yet implemented — file these as feature requests against [`ai-generated-artifacts/scripts/python/powershell-static-analyzer/`](https://github.com/usui-tk/ai-generated-artifacts) instead |

## Reporting a vulnerability

**Please do NOT open a public GitHub Issue for security-impacting reports.** Public disclosure of a defect in driver-signing logic before a fix is published gives a window where operators continue running the vulnerable version unaware.

Instead, use one of the following private channels:

1. **GitHub Security Advisory (preferred)** — open a private security advisory at <https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/security/advisories/new>. This creates a private discussion thread visible only to you and the maintainer.
2. **Direct contact** — if you cannot use GitHub's security advisory feature, you may contact the maintainer through the email address listed on their GitHub profile (<https://github.com/usui-tk>).

Please include:

- **Affected script and revision** (e.g. `Deploy-AMDChipsetDriverOnWindowsServer.ps1` r57).
- **Affected phase / function** (e.g. P08 `New-SignedDriverCatalog`, I02 `Install-WdacPolicy`).
- **Concrete reproduction** — a command sequence, an input INF, or a step-by-step description. If the issue depends on platform state (Secure Boot policy, BitLocker status, existing WDAC base policy), describe that state.
- **Observed impact** — what an attacker (or unwary operator) could do as a result. Be specific: "could sign arbitrary INFs" is more useful than "signing logic is broken".
- **Suggested fix** if you have one.

## Response expectations

- **Acknowledgement**: best effort, typically within 7 days. No SLA is guaranteed; this is a personal repository.
- **Triage outcome**: the maintainer will reply with one of: *accepted (will fix)*, *accepted (will document in SPEC.md §D, not patch)*, *out of scope (with reason)*, *duplicate*, or *won't fix (with reason)*.
- **Disclosure timeline**: coordinated disclosure is preferred. If a fix is planned, please allow a reasonable window (typically 30–90 days depending on severity) before public discussion. The maintainer will publish a SECURITY ADVISORY on this repository once the fix lands.
- **Credit**: with your permission, the reporter is credited in the relevant commit message, the `TESTING.md` §6 "Discovered bugs and fix history" table, and/or the `SPEC.md` §D entry. You may also request to remain anonymous.

## What this repository does NOT promise

- A defined turnaround time.
- Backported fixes to historical revisions (a fix lands in the current revision only; users on older revisions should upgrade).
- Compensation, bug bounty, or any monetary reward.
- That every reported issue will be acted upon — see "out of scope" above.
- Protection against malicious operators running the scripts on hosts they do not own. The threat model assumes a cooperative operator following the disclaimer.

## Hardening already in place

For completeness, the following are already enforced by the repository:

- **No real secrets in repository or scripts.** PFX passwords default to empty string; operators who want a real password are expected to change `[string]$PfxPassword = ''` in the param block themselves. See [`README.md`](./README.md) "Self-signed certificate".
- **Per-script workspace isolation.** Each script writes to a dedicated workspace path (`C:\AMD-Chipset-WS`, `C:\AMD-Graphics-WS`, `C:\AMD-NPU-WS`, `C:\MSBthPan-WS`) and uses a separate self-signed cert + WDAC supplemental policy GUID to avoid cross-script trust bleed. See [`SPEC.md`](./SPEC.md) §A.1.4 and §B per-script identification.
- **Secure Boot stays ON.** None of the scripts require, suggest, or perform `bcdedit /set testsigning on` (except behind the explicit `-UseTestSigning` opt-in, which is documented in `README.md` as a last-resort lab option). The default path is WDAC supplemental policy authorisation under Secure Boot, which is the supported Microsoft path on Windows Server 2022+ / Windows 11 22H2+.
- **PSP / TPM driver replacement is gated by an explicit BitLocker warning.** P06 never patches `amdpsp.inf` without surfacing the BitLocker recovery-prompt risk. See [`SPEC.md`](./SPEC.md) §B.1.
- **Self-signed certificate authority is scoped, not blanket.** The supplemental policy authorises ONLY the per-script self-signed cert as a kernel-mode signer for the patched INFs — it does NOT add the cert as a global trusted publisher.
- **Static analysis with `psa.py`.** All four scripts are verified with [`psa.py`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer/) which includes security-class rules (`PSA5xxx`) covering plain-text password parameters, `Invoke-Expression` usage, broken hash algorithms, hardcoded `ComputerName`, and similar foot-guns. See [`SPEC.md`](./SPEC.md) §A.11.
- **Disclaimer surfaced before any execution path.** [`README.md`](./README.md) opens with an explicit at-your-own-risk warning, and `-Action Install` prints a final confirmation banner that operators must accept.

---

# 日本語版

# セキュリティポリシー

## 対象範囲

本リポジトリ (`Deploy-Drivers-For-WindowsServer`) は、 AMD コンシューマー向けドライバ INF (および Microsoft inbox Bluetooth PAN ドライバ) を Windows Server SKU 向けにパッチし、 生成した catalog をホスト生成の自己署名証明書で再署名し、 さらにその証明書を kernel-mode signer として認可するための WDAC supplemental policy を deploy する **実験的・ラボグレードの PowerShell スクリプト群** を公開しています。 OS レイヤのドライバ署名信頼チェーン内で動作するため、 セキュリティ上の影響度は高くなります。

本ポリシーの対象は以下です:

| 対象 | 対象外 |
|:---|:---|
| 4 つのスクリプト (`Deploy-AMDChipsetDriverOnWindowsServer.ps1`、 `Deploy-AMDGraphicsDriverOnWindowsServer.ps1`、 `Deploy-AMDNpuDriverOnWindowsServer.ps1`、 `Deploy-MSBthPanInboxOnWindowsServer.ps1`) のいずれかにおいて、 利用者が実行することで利用者のシステムにセキュリティリスクをもたらす欠陥 (権限昇格を可能にする INF パッチ、 意図を超えた範囲を署名する `signtool` 呼び出し、 ドキュメント以上の信頼を認可する WDAC policy、 安全でないダウンロードパターン、 認証情報の露出 等) | スクリプトが再署名する **上流バイナリ** (`amdgpio.sys`、 `amdpsp.sys`、 `bthpan.sys` 等) の脆弱性 — AMD または Microsoft の通常セキュリティチャネルへ報告してください。 本リポジトリはバイナリを変更せず、 既存バイナリを再署名するのみです |
| `README.md` / `README.ja.md` / `SPEC.md` / `TESTING.md` (SPEC.md §A.12 のドキュメント言語ポリシーにより、 README のみバイリンガル、 他は英語のみ) のドキュメントで、 文字通り従ったときに読者が明らかに危険な運用判断を下すことになるもの (例: operator に Secure Boot 無効化を指示する、 `bcdedit /set testsigning on` を恒常的設定として推奨する、 BitLocker リカバリキー保存ステップをスキップさせる等) | 「自己署名カーネルドライバは本質的にリスキー」 という一般論 — [`README.ja.md`](./README.ja.md) 免責セクションと [`CODE_OF_CONDUCT.md`](./CODE_OF_CONDUCT.md) の安全に関する記述で網羅されています |
| 本リポジトリに誤ってコミットされた実在の機密情報 (PFX パスワード、 BitLocker リカバリキー、 AMD アカウント認証情報、 メンテナが非公開を意図した API トークン 等) | コミット済みログに含まれる暗号 thumbprint、 公開鍵 fingerprint、 WDAC policy GUID — これらは機密ではありません |
| 悪意ある PR が `psa.py` チェックを通過しつつセキュリティリグレッションを混入させる、 静的解析回避手法 | 未実装の hardening ルールに対する静的解析の改善提案 — [`ai-generated-artifacts/scripts/python/powershell-static-analyzer/`](https://github.com/usui-tk/ai-generated-artifacts) に feature request として登録してください |

## 脆弱性の報告方法

**セキュリティに影響する事項について、 公開の GitHub Issue を起票しないでください。** ドライバ署名ロジックの欠陥が修正前に公開されると、 operator が脆弱なバージョンを認識せず使い続ける時間が発生します。

代わりに以下のプライベートチャンネルを利用してください:

1. **GitHub Security Advisory (推奨)** — <https://github.com/usui-tk/Deploy-Drivers-For-WindowsServer/security/advisories/new> でプライベート advisory を作成。 報告者とメンテナのみが閲覧できるスレッドが作られます。
2. **直接連絡** — GitHub の Security Advisory が利用できない場合は、 メンテナの GitHub プロフィール (<https://github.com/usui-tk>) に記載のメールアドレスへ連絡してください。

報告時には以下を含めてください:

- **対象スクリプトとリビジョン** (例: `Deploy-AMDChipsetDriverOnWindowsServer.ps1` r57)
- **対象 phase / 関数** (例: P08 `New-SignedDriverCatalog`、 I02 `Install-WdacPolicy`)
- **具体的な再現手順** — コマンド列、 入力 INF、 ステップバイステップの説明等。 プラットフォーム状態 (Secure Boot policy、 BitLocker 状態、 既存 WDAC base policy) に依存する場合はその状態を記述してください
- **観測された影響** — 攻撃者 (または不注意な operator) が結果として何ができるか。 「署名ロジックが壊れている」 ではなく 「任意の INF を署名可能になる」 のように具体的に
- **修正案** (あれば)

## 対応の目安

- **受領確認**: ベストエフォート、 概ね 7 日以内。 SLA の保証はありません (個人リポジトリのため)
- **トリアージ結果**: メンテナは以下のいずれかで返答します — *受理 (修正予定)*、 *受理 (SPEC.md §D に文書化、 修正はしない)*、 *対象外 (理由付き)*、 *重複*、 *対応しない (理由付き)*
- **公開タイミング**: 協調的開示を希望します。 修正予定の場合、 重大度に応じて 30〜90 日程度の猶予を設けたうえでの公開議論をお願いします。 修正が適用された後、 メンテナは本リポジトリで SECURITY ADVISORY を公開します
- **クレジット**: 報告者の同意のもと、 該当コミットメッセージ、 `TESTING.md` §6 「発見されたバグと修正履歴」 テーブル、 および/または `SPEC.md` §D エントリにクレジットを記載します。 匿名希望も尊重します

## 本リポジトリが保証しないこと

- 定まった対応時間
- 過去リビジョンへの修正バックポート (修正は現行リビジョンにのみ適用。 古いリビジョンの利用者はアップグレードしてください)
- 報奨金・バグバウンティ・金銭的補償
- すべての報告に対応すること (「対象外」 を参照)
- 自身の所有していないホスト上でスクリプトを実行する悪意ある operator に対する防護。 想定脅威モデルは免責事項に従う協力的な operator を前提としています

## 既存のハードニング

参考までに、 本リポジトリではすでに以下を運用しています:

- **リポジトリ・スクリプト本体に実在の機密情報を含めない**。 PFX パスワードはデフォルト空文字列。 実パスワードを使いたい operator は param block の `[string]$PfxPassword = ''` を自身で変更する想定です。 [`README.ja.md`](./README.ja.md) 「自己署名証明書」 参照
- **スクリプト別の workspace 分離**。 各スクリプトは専用 workspace path (`C:\AMD-Chipset-WS`、 `C:\AMD-Graphics-WS`、 `C:\AMD-NPU-WS`、 `C:\MSBthPan-WS`) に書き込み、 別々の自己署名証明書 + WDAC supplemental policy GUID を使用してクロススクリプト trust リークを回避。 [`SPEC.md`](./SPEC.md) §A.1.4 および §B 各スクリプト識別欄参照
- **Secure Boot は ON のまま**。 いずれのスクリプトも `bcdedit /set testsigning on` を要求・推奨・実行しません (明示的 opt-in の `-UseTestSigning` を除く。 これは `README.md` に最終手段のラボオプションとして文書化されています)。 デフォルトパスは Secure Boot 下での WDAC supplemental policy 認可で、 これは Windows Server 2022+ / Windows 11 22H2+ における Microsoft のサポート対象パスです
- **PSP / TPM ドライバ置換は明示的 BitLocker 警告でゲート**。 P06 は BitLocker リカバリプロンプトのリスクを提示しない限り `amdpsp.inf` をパッチしません。 [`SPEC.md`](./SPEC.md) §B.1 参照
- **自己署名 CA の認可範囲は限定的、 包括的ではない**。 supplemental policy はパッチ済み INF に対する kernel-mode signer として **per-script の自己署名証明書のみ** を認可します — グローバル trusted publisher としては追加しません
- **`psa.py` による静的解析**。 4 スクリプトはすべて [`psa.py`](https://github.com/usui-tk/ai-generated-artifacts/tree/main/scripts/python/powershell-static-analyzer/) で検証され、 プレーンテキストパスワードパラメータ・ `Invoke-Expression` 使用・脆弱なハッシュアルゴリズム・ ハードコード `ComputerName` 等の foot-gun をカバーするセキュリティクラスルール (`PSA5xxx`) が適用されます。 [`SPEC.md`](./SPEC.md) §A.11 参照
- **実行パスより前に免責事項を提示**。 [`README.ja.md`](./README.ja.md) は冒頭で明示的な at-your-own-risk 警告を提示し、 `-Action Install` は operator が受諾しなければ進まない最終確認バナーを表示します
