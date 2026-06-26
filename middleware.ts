/**
 * middleware.ts
 *
 * Supabase セッションの自動更新ミドルウェア。
 * すべてのリクエストで Cookie のセッショントークンを検証・更新する。
 *
 * Cloudflare Pages（Edge Runtime）で動作する。
 */

import { createServerClient, parseCookieHeader, serializeCookieHeader } from '@supabase/ssr';
import { type NextRequest, NextResponse } from 'next/server';

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return parseCookieHeader(request.headers.get('Cookie') ?? '');
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => {
            request.cookies.set(name, value);
          });
          response = NextResponse.next({
            request,
          });
          cookiesToSet.forEach(({ name, value, options }) => {
            response.cookies.set(name, value, options);
          });
        },
      },
    }
  );

  // セッション更新（トークンの有効期限を延長）
  await supabase.auth.getUser();

  return response;
}

export const config = {
  matcher: [
    // 認証が必要なすべてのルートにミドルウェアを適用
    // 静的ファイルと公開ページは除外
    '/((?!_next/static|_next/image|favicon.ico|icons|manifest.json|api/cron).*)',
  ],
};
