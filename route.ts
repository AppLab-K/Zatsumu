/**
 * /app/api/cron/reset-usage/route.ts
 *
 * 月次使用量リセット API
 * GitHub Actions から毎月1日 15:00 UTC（= 日本時間 翌日 AM 0:00）に呼び出される。
 *
 * セキュリティ:
 *   - Authorization ヘッダーに CRON_SECRET_TOKEN が必要。
 *   - 外部からの無許可アクセスを防ぐため、トークンは強力なランダム文字列を使用すること。
 */

export const runtime = 'edge';

import { createClient } from '@supabase/supabase-js';

// RLS をバイパスするための Service Role クライアント
const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
);

export async function POST(req: Request) {
  // ──────────────────────────────────────────
  // 認証: Authorization ヘッダーのトークン検証
  // ──────────────────────────────────────────
  const authHeader = req.headers.get('authorization');

  if (authHeader !== `Bearer ${process.env.CRON_SECRET_TOKEN}`) {
    console.warn('Cron API: 不正なアクセスを検知しました。');
    return new Response('Unauthorized', { status: 401 });
  }

  // ──────────────────────────────────────────
  // 全ユーザーの使用量を 0 にリセット
  //
  // NOTE: .neq('id', '00000000-...') は
  //   Supabase の安全機能により "全行更新" を
  //   誤って実行しないようにするガード条件。
  //   実質的に全ユーザーが対象になる。
  // ──────────────────────────────────────────
  const { error, count } = await supabaseAdmin
    .from('profiles')
    .update({ current_month_usage: 0 })
    .neq('id', '00000000-0000-0000-0000-000000000000')
    .select('id', { count: 'exact', head: true });

  if (error) {
    console.error('使用量リセットに失敗しました:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  console.log(`使用量リセット完了。対象ユーザー数: ${count ?? '不明'}`);

  return new Response(
    JSON.stringify({
      message: 'Reset completed successfully',
      reset_count: count,
      executed_at: new Date().toISOString(),
    }),
    {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }
  );
}
