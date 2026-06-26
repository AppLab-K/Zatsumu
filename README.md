# Zatsumu（ザツム）

> 1人起業家・フリーランスの面倒な雑務を、チャット一つで解決する AI アシスタント。

## ✨ 特徴

- **文脈の永続化**: 取引先情報を DB に登録すれば「A社にいつもの請求書」の一言だけで完結
- **Stripe 連携**: チャットから Stripe 決済リンクをその場で発行
- **Saga パターン**: 外部 API 失敗時も使用カウントを無駄に消費しない補償トランザクション
- **PWA 対応**: ホーム画面追加でスマホアプリのように動作

---

## 🛠 技術スタック

| レイヤー | 技術 |
|---|---|
| フロントエンド / バックエンド | Next.js 14 (App Router) |
| ホスティング / WAF | Cloudflare Pages |
| データベース / 認証 | Supabase (PostgreSQL) |
| AI オーケストレーション | Vercel AI SDK / OpenAI gpt-4o-mini |
| 決済 | Stripe Payment Links |
| Cron | GitHub Actions |

---

## 🚀 セットアップ

### 1. リポジトリのクローン

```bash
git clone https://github.com/your-username/zatsumu.git
cd zatsumu
npm install
```

### 2. 環境変数の設定

```bash
cp .env.example .env.local
```

`.env.local` を開いて各値を設定してください。

| 変数名 | 取得場所 |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase ダッシュボード > Settings > API |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | 同上 |
| `SUPABASE_SERVICE_ROLE_KEY` | 同上（⚠️ 絶対に公開しないこと） |
| `STRIPE_SECRET_KEY` | Stripe ダッシュボード > Developers > API keys |
| `OPENAI_API_KEY` | OpenAI Platform > API keys |
| `CRON_SECRET_TOKEN` | `openssl rand -hex 32` で生成 |

### 3. Supabase のセットアップ

Supabase の SQL エディタで `supabase/schema.sql` を実行してください。

```
Supabase ダッシュボード > SQL Editor > New query
→ schema.sql の内容をペーストして実行
```

### 4. ローカル開発サーバーの起動

```bash
npm run dev
```

http://localhost:3000 でアクセスできます。

---

## 📦 ファイル構成

```
zatsumu/
├── app/
│   └── api/
│       ├── chat/
│       │   └── route.ts          # チャットコア API（Saga パターン実装）
│       └── cron/
│           └── reset-usage/
│               └── route.ts      # 月次リセット API
├── lib/
│   └── supabase/
│       ├── client.ts             # ブラウザ用クライアント
│       └── server.ts             # サーバー用クライアント
├── types/
│   └── database.ts               # Supabase TypeScript 型定義
├── supabase/
│   └── schema.sql                # DB スキーマ・関数定義（本番 DDL）
├── public/
│   └── manifest.json             # PWA マニフェスト
├── .github/
│   └── workflows/
│       └── reset-usage.yml       # 月次リセット GitHub Actions
├── middleware.ts                  # Supabase セッション自動更新
├── next.config.js                 # Next.js + PWA 設定
├── tsconfig.json
├── package.json
├── .env.example                   # 環境変数テンプレート
└── .gitignore
```

---

## 🔒 セキュリティ設計

### TOCTOU 競合対策
月間使用量チェックと加算を `UPDATE ... WHERE ... AND current_month_usage < 30 RETURNING` で **1 ステップ** にまとめ、並列リクエストによる上限突破を防止。

### Saga パターン（補償トランザクション）
外部 API（Stripe）が失敗した場合、`decrement_usage_and_rollback` 関数でカウントとログを原子的に戻す。ユーザーは失敗したタスクで使用量を消費しない。

### RLS（Row Level Security）
`usage_logs` への直接 INSERT は RLS で禁止。書き込みは `SECURITY DEFINER` 関数経由のみ許可。

### Cloudflare WAF
`/api/chat` に対して同一 IP から **1分間に 20 リクエスト** を超えた場合、5分間ブロック。

---

## 💰 マネタイズ

| プラン | 価格 | 制限 |
|---|---|---|
| フリー | 無料 | 月 30 タスクまで |
| プレミアム | 月額 980 円 | 無制限（1日 50 回ハードリミット） |

その他: Stripe 手数料の 1% / フリープラン向けアフィリエイト広告

---

## 📅 開発ロードマップ

- **Week 1（20h）**: 環境構築 + 取引先 CRUD + Function Calling
- **Week 2（25h）**: Stripe 動的フロー + エラーハンドリング + テスト
- **Week 3（15h）**: 広告 UI + WAF 設定 + PWA + 本番デプロイ

---

## 📄 ライセンス

MIT
