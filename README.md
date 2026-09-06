# V-model — V字モデル・トレーサビリティ駆動開発

要件から E2E までを **採番付きトレーサビリティ**で繋いだまま実装を進めるための、Claude Code / Codex 用スキルセット。

左側（要件・設計・テスト設計）で **3回だけ**止まって承認を取り、右側（実装・テスト・レビュー・収束）は走り切る。すべての成果物が ID で相互に引ける状態を保つ。

```
US-*  ユーザーストーリー ──────────────────────── E2E-*  E2Eテスト
  SCR-* 画面仕様 ────────────────────────── IT-*   結合テスト
    REQ-F-* / REQ-N-* 要件 ──────────── UT-*   単体テスト
      ARC-* / DFD-* / ENT-* / DES-* 設計 ── 実装
```

## 何をしてくれるか

`/vmodel <機能名>` を実行すると、8フェーズを順に進める。

| Phase | 内容 | 停止 |
|---|---|---|
| 0 | 前提確認（**プロジェクト規約を検出し `/vmodel` より優先**、検証コマンド・ベースブランチ・出力先の決定） | |
| 1 | 要件（ユーザーストーリー → 画面仕様 → 要件定義 → 台帳） | ⏸ ゲート1 |
| 2 | 設計（アーキテクチャ・データフロー・ドメインモデル・詳細設計） | ⏸ ゲート2 |
| 3 | テスト設計（正常系・異常系・境界値、回帰範囲、E2Eシナリオ） | ⏸ ゲート3 |
| 4 | 実装（TDD、`// @impl REQ-F-001` で実装と要件を紐付け） | |
| 5 | テスト実装と **mutation testing**（生存 mutant = 足りない異常系テスト） | |
| 6 | **6観点の並列レビュー**（P0/P1 はその場で修正） | |
| 7 | 収束（孤立・未消化・リンク切れをゼロにする `/audit` ループ） | |
| 8 | 最終報告と **PR説明文の草案**（**コミット・PR作成はしない**） | |

### 特徴

- **利用者の7類型を必ず1周する** — 主操作者だけでなく、権限違いの同僚 / 別テナントの他人 / **データの消費者** / **運用者** / 誤操作する人 / 使えなくなる人。該当なしは `N/A: 理由` を明記させる
- **E2E は要件ではなくユーザーストーリーから起こす** — 要件から起こすと手段の写経になり導線を通さない
- **プロジェクト規約が `/vmodel` の既定より優先** — `CLAUDE.md` / `AGENTS.md` / `docs/` を読み、E2E の置き場所やコミット承認ゲートなど既存の決まりに従う
- **mutation testing で「テストが本当に欠陥を検出するか」を検証** — ツール未導入なら勝手に入れず手動反転にフォールバック
- **6観点レビューは名寄せしてから記録** — 同一欠陥が別観点から別重大度で上がるため、統合して高いほうの重大度を採る
- **PR説明文を成果物から組み立てる** — AS-IS/TO-BE・影響範囲・従属関係・結合度・テスト結果・デプロイ方法を各成果物から引き写す。ここで新しく考えないので、PR の記述と台帳がずれない

## 構成

| | |
|---|---|
| `commands/vmodel.md` | `/vmodel` — 8フェーズの本体 |
| `commands/audit.md` | `/audit` — 指摘ゼロまでレビュー→修正を反復 |
| `skills/vmodel-requirements/` | ユーザーストーリー・画面仕様書・要件定義書 |
| `skills/vmodel-design/` | アーキテクチャ・データフロー・ドメインモデル・詳細設計 |
| `skills/vmodel-test/` | テスト設計・テスト実装・mutation testing |
| `skills/vmodel-e2e/` | E2E シナリオ設計と実装（Playwright / Cypress / Selenium） |
| `skills/vmodel-trace/` | 採番規則とトレーサビリティ台帳の検証 |
| `agents/review-*.md` | 6観点レビュー（命名構造 / 局所品質 / データフロー / セキュリティ / 法令規制 / 依存関係） |

6観点のレビューエージェントは `/vmodel` の Phase 6 以外に、単独でも呼べる。

## インストール

### 前提

- **Claude Code**（`/vmodel` はスラッシュコマンドとして動く）
- Windows は **PowerShell 7 以降**、macOS / Linux は POSIX sh
- 任意: Phase 4 の実装は [superpowers](https://github.com/obra/superpowers) の
  `test-driven-development` スキルに従う。未導入でも動くが、その場合はプロジェクト既存の
  TDD 規約（`CLAUDE.md` 等）が優先される

```sh
git clone https://github.com/fjdayo/V-model-fjdayo.git
cd V-model-fjdayo
```

### Windows (PowerShell 7+)

```powershell
pwsh -File scripts/install.ps1 -Check    # まず何が起きるか確認（何も書き換えない）
pwsh -File scripts/install.ps1           # Claude Code (~/.claude) に導入
pwsh -File scripts/install.ps1 -Codex    # Codex (~/.codex) にも入れる
```

### macOS / Linux

```sh
./scripts/install.sh --check     # まず何が起きるか確認（何も書き換えない）
./scripts/install.sh             # Claude Code (~/.claude) に導入
./scripts/install.sh --codex     # Codex (~/.codex) にも入れる
```

導入後、Claude Code で `/vmodel <機能名>` が使える。

どちらのスクリプトも **冪等**（再実行しても変更が無ければ `current` と表示するだけ）で、
**インストール先に既にあるものは一切壊さない** — 自作スキル・平ファイル・自前の symlink のいずれも
`preserved` として報告し、触らない。`--check` / `-Check` は1バイトも書き込まない。

インストール先は `CLAUDE_HOME` / `CODEX_HOME` 環境変数で変更できる（Windows / macOS / Linux とも）。

動作確認:

```sh
./scripts/smoke.sh    # 一時ディレクトリ内で完結。実際の ~/.claude には触れない
```

### Codex 側の仕組み

**Windows** (`-Codex`) は `scripts/sync-claude-skills.ps1` を呼ぶ。

- **スキル**は `~/.claude/skills/` への junction を張る（実体は1つ、常に同期）
- **コマンドとエージェント**は Codex 用のアダプタ SKILL.md を生成する。アダプタは実行時に `~/.claude/` 側の原典を読むので、原典を直せば追従する

**macOS / Linux** (`--codex`) はスキルの symlink を張る。symlink が使えない環境（開発者モード無効の Git Bash 等）では自動的にコピーへフォールバックするが、**コピーは原典の更新を追わない**ため、`~/.claude` を更新したら再実行が必要（その旨は実行時に表示される）。

コマンド・エージェントのCodexアダプタ生成はPowerShell版のみ。非Windowsでは `~/.claude/commands` と `~/.claude/agents` を直接参照する。

## 使い方

```
/vmodel ユーザー招待機能
/vmodel ユーザー招待機能 --phase 3      # 特定フェーズだけ実行
/vmodel ユーザー招待機能 --resume       # 中断したところから再開
/vmodel ユーザー招待機能 --slug invite   # 出力ディレクトリ名を指定
```

成果物の既定の出力先は `docs/vmodel/<slug>/`。ただしプロジェクトの docs 構成に無いディレクトリを黙って新設せず、ゲート1で場所ごと承認を求める。

## ライセンス

MIT
