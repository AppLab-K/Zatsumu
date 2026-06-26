#!/bin/bash
# ==================================================
# Zatsumu（ザツム）プロジェクト生成スクリプト
# 実行方法: bash setup_zatsumu.sh
# ==================================================

set -e

PROJECT_NAME="zatsumu"
echo "🚀 Zatsumu プロジェクトをセットアップ中..."

# ==================================================
# ① ディレクトリ構造の作成
# ==================================================
mkdir -p $PROJECT_NAME/{app/{api/{chat,cron/reset-usage},chat},components,lib/supabase,public,.github/workflows}

cd $PROJECT_NAME

# ==================================================
# ② GitHub管理ファイル群
# ==================================================

# --- .gitignore ---
cat > .gitignore << 'EOF'
# Dependencies
node_modules/

# Build output
.next/
out/

# Environment variables（絶対にコミットしない）
.env
.env.local
.env.development.local
.env.test.local
.env.production.local

# OS
.DS_Store
Thumbs.db

# Editor
.vscode/
.idea/

# PWA
public/sw.js
public/workbox-*.js
EOF

# --- package.json ---
cat > package.json << 'EOF'
{
  "name": "zatsumu",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint"
  },
  "dependencies": {
    "@ai-sdk/openai": "^0.0.36",
    "@supabase/ssr": "^0.3.0",
    "@supabase/supabase-js": "^2.43.5",
    "ai": "^3.2.22",
    "next": "14.2.5",
    "next-pwa": "^5.6.0",
    "react": "^18",
    "react-dom": "^18",
    "stripe": "^15.12.0",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@cloudflare/next-on-pages": "^1.12.1",
    "@types/node": "^20",
    "@types/react": "^18",
    "@types/react-dom": "^18",
    "typescript": "^5",
    "vercel": "^35.1.0"
  }
}
EOF

# --- tsconfig.json ---
cat > tsconfig.json << 'EOF'
{
  "compilerOptions": {
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "plugins": [{ "name": "next" }],
    "paths": { "@/*": ["./*"] }
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
EOF

# --- next.config.js ---
cat > next.config.js << 'EOF'
const withPWA = require('next-pwa')({
  dest: 'public',
  register: true,
  skipWaiting: true,
  disable: process.env.NODE_ENV === 'development',
  runtimeCaching: [
    {
      // App Shell / 静的リソース: Cache First
      urlPattern: /^https:\/\/.*\.(js|css|woff2?|png|ico|svg)$/i,
      handler: 'CacheFirst',
      options: {
        cacheName: 'static-resources',
        expiration: { maxEntries: 64, maxAgeSeconds: 30 * 24 * 60 * 60 },
      },
    },
    {
      // チャット画面: Network Only（オフライン不可）
      urlPattern: /\/chat$/,
      handler: 'NetworkOnly',
    },
    {
      // 取引先データ: Network First（オフラインフォールバック可）
      urlPattern: /\/api\/clients/,
      handler: 'NetworkFirst',
      options: {
        cacheName: 'clients-data',
        expiration: { maxEntries: 32, maxAgeSeconds: 24 * 60 * 60 },
      },
    },
  ],
});

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Cloudflare Pages (Edge Runtime) 向け設定
};

module.exports = withPWA(nextConfig);
EOF

# --- .github/workflows/reset-usage.yml ---
cat > .github/workflows/reset-usage.yml << 'EOF'
name: Monthly Usage Reset

on:
  schedule:
    # 毎月1日 15:00 UTC = 日本時間 翌日 0:00
    - cron: '0 15 1 * *'
  workflow_dispatch: # 手動実行も可能

jobs:
  reset-usage:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger Reset API
        run: |
          curl -X POST "${{ secrets.APP_URL }}/api/cron/reset-usage" \
            -H "Authorization: Bearer ${{ secrets.CRON_SECRET_TOKEN }}" \
            --fail \
            --silent \
            --show-error
EOF

# ==================================================
# ③ ライブラリ / ユーティリティ
# ==================================================

# --- lib/supabase/server.ts ---
cat > lib/supabase/server.ts << 'EOF'
import { createServerClient, parseCookieHeader } from '@supabase/ssr';

export function createSupabaseServerClient(request: Request) {
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return parseCookieHeader(request.headers.get('Cookie') ?? '');
        },
        setAll() {},
      },
    }
  );
}
EOF

# --- lib/supabase/admin.ts ---
cat > lib/supabase/admin.ts << 'EOF'
import { createClient } from '@supabase/supabase-js';

// Service Role Keyを使用する管理クライアント（サーバーサイドのみ）
export const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);
EOF

# ==================================================
# ④ APIルート
# ==================================================

# --- app/api/chat/route.ts ---
cat > app/api/chat/route.ts << 'EOF'
import { openai } from '@ai-sdk/openai';
import { streamText } from 'ai';
import { z } from 'zod';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { supabaseAdmin } from '@/lib/supabase/admin';

export const runtime = 'edge';

export async function POST(req: Request) {
  try {
    // 1. ストリーム破損を防ぐため、最優先でリクエストBodyをパース
    const { messages } = await req.json();

    // 2. Cookieセッションからユーザーを安全に検証
    const supabase = createSupabaseServerClient(req);
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return new Response('Unauthorized', { status: 401 });
    }
    const userId = user.id;

    // 3. 取引先コンテキストを取得してシステムプロンプトに追加
    const { data: clients } = await supabaseAdmin
      .from('clients')
      .select('name, email, billing_address, default_pricing')
      .eq('user_id', userId);

    const clientContext =
      clients && clients.length > 0
        ? `\n\n【登録済み取引先情報】\n${JSON.stringify(clients, null, 2)}`
        : '';

    const systemPrompt = `あなたは1人起業家・フリーランスの雑務を支援するAIアシスタント「ザツム」です。
ユーザーの指示を聞き、請求書発行などのタスクをツールを使って実行してください。
取引先名が指定された場合、以下の登録済みデータを優先して使用してください。${clientContext}`;

    // 4. ストリーミング実行
    const result = await streamText({
      model: openai('gpt-4o-mini'),
      system: systemPrompt,
      messages,
      tools: {
        create_invoice: {
          description: 'Stripeで請求書（決済リンク）を発行します。',
          parameters: z.object({
            amount: z.number().describe('金額（日本円単位、例: 5000）'),
            description: z.string().describe('品目や請求内容（例: 6月分コンサル費用）'),
            client_name: z.string().describe('宛先となる取引先名'),
          }),
          execute: async ({ amount, description, client_name }) => {
            // Saga Step 1: アトミックに使用量を加算（TOCTOU競合対策）
            const { error: rpcError } = await supabaseAdmin.rpc('increment_usage_and_log', {
              p_user_id: userId,
              p_task_type: 'invoice',
            });

            if (rpcError) {
              if (rpcError.code === 'P0001') {
                return {
                  error:
                    '月間タスク上限（30回）に達しました。プレミアムプラン（月額980円）へのアップグレードをご検討ください。',
                };
              }
              throw rpcError;
            }

            try {
              // Saga Step 2: Stripe Price オブジェクトを生成
              const priceResponse = await fetch('https://api.stripe.com/v1/prices', {
                method: 'POST',
                headers: {
                  Authorization: `Bearer ${process.env.STRIPE_SECRET_KEY}`,
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: new URLSearchParams({
                  currency: 'jpy',
                  unit_amount: amount.toString(),
                  'product_data[name]': `${description} (宛先: ${client_name})`,
                }),
              });
              const priceData = await priceResponse.json();

              if (priceData.error) {
                throw new Error(`Stripe Price作成失敗: ${priceData.error.message}`);
              }

              // Saga Step 3: Payment Link を生成
              const linkResponse = await fetch('https://api.stripe.com/v1/payment_links', {
                method: 'POST',
                headers: {
                  Authorization: `Bearer ${process.env.STRIPE_SECRET_KEY}`,
                  'Content-Type': 'application/x-www-form-urlencoded',
                },
                body: new URLSearchParams({
                  'line_items[0][price]': priceData.id,
                  'line_items[0][quantity]': '1',
                }),
              });
              const linkData = await linkResponse.json();

              if (linkData.error) {
                throw new Error(`Stripe PaymentLink作成失敗: ${linkData.error.message}`);
              }

              return { url: linkData.url, amount, client_name, description };
            } catch (error: any) {
              console.error('Stripe処理失敗。使用量をロールバック中:', error);

              // Saga Step 4: 補償トランザクション（使用量・ログの巻き戻し）
              await supabaseAdmin.rpc('decrement_usage_and_rollback', {
                p_user_id: userId,
                p_task_type: 'invoice',
              });

              return { error: error.message || '処理中にエラーが発生しました。再度お試しください。' };
            }
          },
        },
      },
    });

    return result.toAIStreamResponse();
  } catch (error) {
    console.error('Chat API Error:', error);
    return new Response('Internal Server Error', { status: 500 });
  }
}
EOF

# --- app/api/cron/reset-usage/route.ts ---
cat > app/api/cron/reset-usage/route.ts << 'EOF'
import { supabaseAdmin } from '@/lib/supabase/admin';

export const runtime = 'edge';

export async function POST(req: Request) {
  // GitHub Actions からの秘密トークンで認証
  const authHeader = req.headers.get('authorization');
  if (authHeader !== `Bearer ${process.env.CRON_SECRET_TOKEN}`) {
    return new Response('Unauthorized', { status: 401 });
  }

  // 全ユーザーの月間使用量を一括リセット
  const { error, count } = await supabaseAdmin
    .from('profiles')
    .update({ current_month_usage: 0 })
    .neq('id', '00000000-0000-0000-0000-000000000000')
    .select('id');

  if (error) {
    console.error('Usage reset failed:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return new Response(
    JSON.stringify({ message: 'Reset completed successfully', reset_count: count }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  );
}
EOF

# ==================================================
# ⑤ フロントエンド（App Router）
# ==================================================

# --- app/layout.tsx ---
cat > app/layout.tsx << 'EOF'
import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Zatsumu（ザツム）',
  description: '1人起業家の雑務を、チャット一つで解決するAIアシスタント',
  manifest: '/manifest.json',
  themeColor: '#1a1a2e',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ja">
      <body>{children}</body>
    </html>
  );
}
EOF

# --- app/chat/page.tsx ---
cat > app/chat/page.tsx << 'EOF'
'use client';

import { useChat } from 'ai/react';
import { useState, useEffect } from 'react';

export default function ChatPage() {
  const [isOnline, setIsOnline] = useState(true);

  useEffect(() => {
    const handleOnline = () => setIsOnline(true);
    const handleOffline = () => setIsOnline(false);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    setIsOnline(navigator.onLine);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  const { messages, input, handleInputChange, handleSubmit, isLoading } = useChat({
    api: '/api/chat',
  });

  return (
    <div style={{ maxWidth: 720, margin: '0 auto', padding: '1rem', fontFamily: 'sans-serif' }}>
      {/* オフラインバナー */}
      {!isOnline && (
        <div
          style={{
            background: '#f59e0b',
            color: '#fff',
            padding: '0.5rem 1rem',
            borderRadius: 8,
            marginBottom: '1rem',
            textAlign: 'center',
          }}
        >
          現在オフラインです。再接続をお待ちください。
        </div>
      )}

      <h1 style={{ fontSize: '1.5rem', marginBottom: '1rem' }}>ザツム</h1>

      {/* メッセージ一覧 */}
      <div
        style={{
          minHeight: 400,
          border: '1px solid #e5e7eb',
          borderRadius: 12,
          padding: '1rem',
          marginBottom: '1rem',
          overflowY: 'auto',
        }}
      >
        {messages.length === 0 && (
          <p style={{ color: '#9ca3af', textAlign: 'center', marginTop: '6rem' }}>
            「A社に5万円の請求書を発行して」などと話しかけてみてください。
          </p>
        )}
        {messages.map((m) => (
          <div
            key={m.id}
            style={{
              marginBottom: '1rem',
              display: 'flex',
              justifyContent: m.role === 'user' ? 'flex-end' : 'flex-start',
            }}
          >
            <div
              style={{
                background: m.role === 'user' ? '#4f46e5' : '#f3f4f6',
                color: m.role === 'user' ? '#fff' : '#111',
                borderRadius: 12,
                padding: '0.75rem 1rem',
                maxWidth: '80%',
                whiteSpace: 'pre-wrap',
              }}
            >
              {m.content}
              {/* ツール結果の表示（請求書URL等） */}
              {m.toolInvocations?.map((tool) => (
                <div key={tool.toolCallId} style={{ marginTop: '0.5rem' }}>
                  {tool.state === 'result' && tool.result?.url && (
                    <a
                      href={tool.result.url}
                      target="_blank"
                      rel="noopener noreferrer"
                      style={{
                        display: 'inline-block',
                        background: '#10b981',
                        color: '#fff',
                        padding: '0.5rem 1rem',
                        borderRadius: 8,
                        textDecoration: 'none',
                        fontSize: '0.875rem',
                      }}
                    >
                      💳 決済リンクを開く
                    </a>
                  )}
                  {tool.state === 'result' && tool.result?.error && (
                    <p style={{ color: '#ef4444', fontSize: '0.875rem' }}>{tool.result.error}</p>
                  )}
                </div>
              ))}
            </div>
          </div>
        ))}
        {isLoading && (
          <p style={{ color: '#9ca3af', fontSize: '0.875rem' }}>処理中...</p>
        )}
      </div>

      {/* 入力フォーム */}
      <form onSubmit={handleSubmit} style={{ display: 'flex', gap: '0.5rem' }}>
        <input
          value={input}
          onChange={handleInputChange}
          disabled={!isOnline || isLoading}
          placeholder={isOnline ? 'メッセージを入力...' : 'オフライン中'}
          style={{
            flex: 1,
            border: '1px solid #e5e7eb',
            borderRadius: 8,
            padding: '0.75rem 1rem',
            fontSize: '1rem',
            outline: 'none',
          }}
        />
        <button
          type="submit"
          disabled={!isOnline || isLoading || !input.trim()}
          style={{
            background: '#4f46e5',
            color: '#fff',
            border: 'none',
            borderRadius: 8,
            padding: '0.75rem 1.5rem',
            cursor: 'pointer',
            fontSize: '1rem',
          }}
        >
          送信
        </button>
      </form>
    </div>
  );
}
EOF

# --- public/manifest.json ---
cat > public/manifest.json << 'EOF'
{
  "name": "Zatsumu（ザツム）",
  "short_name": "ザツム",
  "description": "1人起業家の雑務を、チャット一つで解決するAIアシスタント",
  "start_url": "/chat",
  "display": "standalone",
  "background_color": "#ffffff",
  "theme_color": "#4f46e5",
  "icons": [
    { "src": "/icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
EOF

# --- README.md ---
cat > README.md << 'EOF'
# Zatsumu（ザツム）

> 1人起業家・フリーランスの面倒な雑務を、チャット一つで解決するAIアシスタント

## 技術スタック

| レイヤー | 技術 |
|---|---|
| フロントエンド / バックエンド | Next.js 14 (App Router, Edge Runtime) |
| ホスティング / WAF | Cloudflare Pages |
| データベース / 認証 | Supabase (PostgreSQL) |
| AI | Vercel AI SDK / OpenAI gpt-4o-mini |
| 決済 | Stripe Payment Links |
| Cron | GitHub Actions |

## セットアップ

### 1. 環境変数の設定

`.env.local` を作成し（`.env.example` を参考に）、各値を設定してください。

### 2. Supabaseのセットアップ

`supabase/schema.sql` を Supabase の SQL エディタで実行してください。

### 3. インストール & 起動

\`\`\`bash
npm install
npm run dev
\`\`\`

### 4. Cloudflare Pages へのデプロイ

\`\`\`bash
npx @cloudflare/next-on-pages
\`\`\`

## GitHub Actions シークレット設定

| シークレット名 | 説明 |
|---|---|
| `CRON_SECRET_TOKEN` | 月次リセットAPIの認証トークン |
| `APP_URL` | デプロイ先URL（例: https://zatsumu.pages.dev） |

## ライセンス

MIT
EOF

# ==================================================
# ⑥ .env.example（環境変数テンプレート）
# ==================================================
cat > .env.example << 'EOF'
# Supabase
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key

# OpenAI
OPENAI_API_KEY=sk-...

# Stripe
STRIPE_SECRET_KEY=sk_live_...

# Cron認証（ランダムな文字列を設定）
CRON_SECRET_TOKEN=your-random-secret-token
EOF

cd ..

echo ""
echo "✅ GitHubアップロード対象ファイルの生成が完了しました！"
echo ""
echo "📁 生成されたプロジェクト構造:"
find $PROJECT_NAME -type f | sort
echo ""
echo "次のステップ:"
echo "  cd $PROJECT_NAME"
echo "  git init"
echo "  git add ."
echo "  git commit -m 'initial commit'"
echo "  git remote add origin https://github.com/YOUR_USERNAME/zatsumu.git"
echo "  git push -u origin main"
