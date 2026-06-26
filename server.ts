/**
 * lib/supabase/server.ts
 *
 * サーバーサイド（Server Components / Route Handlers）用 Supabase クライアント。
 * Cookie を通じてセッションを安全に読み書きする。
 *
 * 使用例:
 *   import { createClient } from '@/lib/supabase/server';
 *   const supabase = createClient();
 *   const { data: { user } } = await supabase.auth.getUser();
 */

import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { cookies } from 'next/headers';
import type { Database } from '@/types/database';

export function createClient() {
  const cookieStore = cookies();

  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return cookieStore.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          try {
            cookieStore.set({ name, value, ...options });
          } catch {
            // Server Component からの呼び出しでは set できない場合がある（無視）
          }
        },
        remove(name: string, options: CookieOptions) {
          try {
            cookieStore.set({ name, value: '', ...options });
          } catch {
            // 同上
          }
        },
      },
    }
  );
}
