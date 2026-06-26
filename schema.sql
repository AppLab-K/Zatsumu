-- ============================================================
--  Zatsumu - Supabase DDL（本番用）
--
--  実行順序:
--    1. テーブル定義
--    2. RLS（Row Level Security）ポリシー定義
--    3. インデックス定義
--    4. ストアドファンクション定義
--
--  対策済みセキュリティ項目:
--    - 引数名シャドウイング防止（プレフィックス p_ を使用）
--    - SQLインジェクション対策（SET search_path = public, pg_temp）
--    - TOCTOU 競合防止（アトミックな UPDATE + RETURNING）
--    - 直接書き込み禁止（usage_logs は SECURITY DEFINER 関数経由のみ）
-- ============================================================


-- ============================================================
-- 1. テーブル定義
-- ============================================================

-- ユーザープロフィールテーブル
-- Supabase Auth の auth.users と 1:1 で紐づく。
CREATE TABLE public.profiles (
    id                   UUID        REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
    email                TEXT        UNIQUE NOT NULL,
    plan                 TEXT        DEFAULT 'free' CHECK (plan IN ('free', 'premium')),
    current_month_usage  INT         DEFAULT 0,
    stripe_customer_id   TEXT,
    created_at           TIMESTAMP WITH TIME ZONE
                         DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

COMMENT ON TABLE  public.profiles                    IS 'ユーザープロフィール（認証ユーザーと1:1対応）';
COMMENT ON COLUMN public.profiles.plan               IS 'free: 月30タスクまで / premium: 無制限（1日50回ハードリミット）';
COMMENT ON COLUMN public.profiles.current_month_usage IS '当月の使用タスク数（毎月1日 UTC 15:00 にリセット）';


-- 取引先管理テーブル（文脈永続化の核心）
-- ユーザーが「A社にいつもの請求書」と言った際、
-- AI がこのテーブルを検索して文脈を補完する。
CREATE TABLE public.clients (
    id               UUID    DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id          UUID    REFERENCES auth.users ON DELETE CASCADE NOT NULL,
    name             TEXT    NOT NULL,
    email            TEXT,
    billing_address  TEXT,
    default_pricing  INT,    -- 円単位
    created_at       TIMESTAMP WITH TIME ZONE
                     DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

COMMENT ON TABLE  public.clients                 IS '取引先情報（AIの文脈永続化ソース）';
COMMENT ON COLUMN public.clients.default_pricing IS 'この取引先への標準単価（円）。「いつもの金額で」対応に使用';


-- 利用ログテーブル
-- 直接 INSERT は禁止（RLS で SELECT のみ許可）。
-- 書き込みは increment_usage_and_log 関数（SECURITY DEFINER）経由のみ。
CREATE TABLE public.usage_logs (
    id           UUID    DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id      UUID    REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    task_type    TEXT    NOT NULL,  -- 例: 'invoice', 'email_draft'
    executed_at  TIMESTAMP WITH TIME ZONE
                 DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

COMMENT ON TABLE public.usage_logs IS '使用タスクログ（直接書き込み禁止 / SECURITY DEFINER 関数経由のみ）';


-- ============================================================
-- 2. RLS（Row Level Security）ポリシー定義
-- ============================================================

-- profiles: 自分自身のレコードのみ読み書き可
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can only read/write their own profile"
    ON public.profiles
    FOR ALL
    USING (auth.uid() = id);


-- clients: 自分が登録した取引先のみ CRUD 可
ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own clients"
    ON public.clients FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own clients"
    ON public.clients FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own clients"
    ON public.clients FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own clients"
    ON public.clients FOR DELETE
    USING (auth.uid() = user_id);


-- usage_logs: SELECT のみ許可（書き込みは関数経由）
ALTER TABLE public.usage_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can only read their own logs"
    ON public.usage_logs FOR SELECT
    USING (auth.uid() = user_id);


-- ============================================================
-- 3. インデックス定義
-- ============================================================

-- ロールバック時のログ検索高速化（最新レコード1件の特定）
CREATE INDEX IF NOT EXISTS idx_usage_logs_user_task_time
    ON public.usage_logs (user_id, task_type, executed_at DESC);

-- 取引先名の部分一致検索高速化（AI の文脈補完用）
CREATE INDEX IF NOT EXISTS idx_clients_user_name
    ON public.clients (user_id, name);


-- ============================================================
-- 4. ストアドファンクション定義
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- ① increment_usage_and_log
--    アトミックな上限チェック ＆ インクリメント ＆ ログ挿入
--
--  TOCTOU（Time-Of-Check Time-Of-Use）競合対策:
--    SELECT して確認後に UPDATE する2ステップではなく、
--    条件付き UPDATE + RETURNING の1ステップでアトミックに処理。
--    並列リクエストが来ても上限を突破できない。
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.increment_usage_and_log(
    p_user_id   UUID,
    p_task_type TEXT
) RETURNS void AS $$
DECLARE
    v_new_count INT;
BEGIN
    -- プラン判定と加算を1ステップでアトミックに実行
    UPDATE public.profiles
    SET current_month_usage = current_month_usage + 1
    WHERE id = p_user_id
      AND (
        plan = 'premium'           -- プレミアムは上限なし
        OR current_month_usage < 30  -- フリーは30未満のみ許可
      )
    RETURNING current_month_usage INTO v_new_count;

    -- UPDATE が1行も更新されなかった = 上限超え
    IF NOT FOUND THEN
        RAISE EXCEPTION 'LIMIT_EXCEEDED'
            USING ERRCODE = 'P0001';
    END IF;

    -- 使用ログを挿入
    INSERT INTO public.usage_logs (user_id, task_type)
    VALUES (p_user_id, p_task_type);
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = public, pg_temp;  -- SQLインジェクション対策

COMMENT ON FUNCTION public.increment_usage_and_log IS
    '使用量を1増やしてログを記録する。上限超えは ERRCODE=P0001 で例外を投げる。';


-- ────────────────────────────────────────────────────────────
-- ② decrement_usage_and_rollback
--    補償トランザクション（外部 API 失敗時のロールバック）
--
--  使用カウントを1戻し、直近の該当ログ1件を削除することで、
--  外部サービス（Stripe など）のエラー時にユーザーの使用量を
--  無駄に消費させない。
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.decrement_usage_and_rollback(
    p_user_id   UUID,
    p_task_type TEXT
) RETURNS void AS $$
BEGIN
    -- 使用カウントを1戻す（0 未満にはしない）
    UPDATE public.profiles
    SET current_month_usage = GREATEST(0, current_month_usage - 1)
    WHERE id = p_user_id;

    -- 直近の該当タスクログを1件だけ削除
    DELETE FROM public.usage_logs
    WHERE id = (
        SELECT id
        FROM public.usage_logs
        WHERE user_id   = p_user_id
          AND task_type = p_task_type
        ORDER BY executed_at DESC
        LIMIT 1
    );
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = public, pg_temp;  -- SQLインジェクション対策

COMMENT ON FUNCTION public.decrement_usage_and_rollback IS
    '補償トランザクション: 外部API失敗時に使用カウントとログを1件ロールバックする。';


-- ────────────────────────────────────────────────────────────
-- ③ handle_new_user（トリガー関数）
--    auth.users にユーザーが作成された際、
--    自動で public.profiles にレコードを挿入する。
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, email)
    VALUES (NEW.id, NEW.email);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = public, pg_temp;

-- トリガーをアタッチ
CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

COMMENT ON TRIGGER on_auth_user_created ON auth.users IS
    '新規ユーザー登録時に public.profiles へ自動でレコードを作成する。';
