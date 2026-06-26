/** @type {import('next').NextConfig} */
const nextConfig = {
  // Cloudflare Pages（Edge Runtime）向けの設定
  // @cloudflare/next-on-pages で使用
  experimental: {
    // Edge Runtime でのサーバーコンポーネント最適化
  },

  // PWA 設定（next-pwa）
  // キャッシュ戦略は public/sw.js で定義
};

// next-pwa の設定
const withPWA = require('next-pwa')({
  dest: 'public',
  disable: process.env.NODE_ENV === 'development', // 開発中は無効化
  register: true,
  skipWaiting: true,
  runtimeCaching: [
    // ──────────────────────────────────────────
    // App Shell / 静的リソース: Cache First
    // オフラインでも UI 全体が瞬時に起動
    // ──────────────────────────────────────────
    {
      urlPattern: /^https:\/\/zatsumu\.pages\.dev\/_next\/static\/.*/i,
      handler: 'CacheFirst',
      options: {
        cacheName: 'static-resources',
        expiration: {
          maxEntries: 100,
          maxAgeSeconds: 30 * 24 * 60 * 60, // 30日
        },
      },
    },
    // ──────────────────────────────────────────
    // チャット画面: Network Only
    // オフライン時はバナーを表示して入力を無効化
    // ──────────────────────────────────────────
    {
      urlPattern: /^https:\/\/zatsumu\.pages\.dev\/api\/chat.*/i,
      handler: 'NetworkOnly',
    },
    // ──────────────────────────────────────────
    // 取引先データ: Network First
    // オフラインでも IndexedDB キャッシュから閲覧可能
    // ──────────────────────────────────────────
    {
      urlPattern: /^https:\/\/[a-z]+\.supabase\.co\/rest\/v1\/clients.*/i,
      handler: 'NetworkFirst',
      options: {
        cacheName: 'clients-data',
        networkTimeoutSeconds: 5,
        expiration: {
          maxEntries: 50,
          maxAgeSeconds: 24 * 60 * 60, // 1日
        },
      },
    },
  ],
});

module.exports = withPWA(nextConfig);
