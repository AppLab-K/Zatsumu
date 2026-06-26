/**
 * lib/supabase/client.ts
 *
 * クライアントサイド（ブラウザ）用 Supabase クライアント。
 * React コンポーネントや クライアントサイドのフックから呼び出す。
 *
 * 注意: このクライアントは Anon Key を使用するため RLS が適用される。
 *       管理者権限が必要な操作は API Route 内の supabaseAdmin を使うこと。
 */

import { createBrowserClient } from '@supabase/ssr';
import type { Database } from '@/types/database';

export function createClient() {
  return createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
