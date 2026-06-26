/**
 * types/database.ts
 *
 * Supabase のテーブルスキーマに対応する TypeScript 型定義。
 * `supabase gen types typescript --project-id YOUR_PROJECT_ID` で
 * 自動生成することも可能（推奨）。
 */

export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string;
          email: string;
          plan: 'free' | 'premium';
          current_month_usage: number;
          stripe_customer_id: string | null;
          created_at: string;
        };
        Insert: {
          id: string;
          email: string;
          plan?: 'free' | 'premium';
          current_month_usage?: number;
          stripe_customer_id?: string | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          email?: string;
          plan?: 'free' | 'premium';
          current_month_usage?: number;
          stripe_customer_id?: string | null;
          created_at?: string;
        };
      };
      clients: {
        Row: {
          id: string;
          user_id: string;
          name: string;
          email: string | null;
          billing_address: string | null;
          default_pricing: number | null;
          created_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          name: string;
          email?: string | null;
          billing_address?: string | null;
          default_pricing?: number | null;
          created_at?: string;
        };
        Update: {
          id?: string;
          user_id?: string;
          name?: string;
          email?: string | null;
          billing_address?: string | null;
          default_pricing?: number | null;
          created_at?: string;
        };
      };
      usage_logs: {
        Row: {
          id: string;
          user_id: string;
          task_type: string;
          executed_at: string;
        };
        Insert: {
          id?: string;
          user_id: string;
          task_type: string;
          executed_at?: string;
        };
        Update: {
          id?: string;
          user_id?: string;
          task_type?: string;
          executed_at?: string;
        };
      };
    };
    Functions: {
      increment_usage_and_log: {
        Args: {
          p_user_id: string;
          p_task_type: string;
        };
        Returns: void;
      };
      decrement_usage_and_rollback: {
        Args: {
          p_user_id: string;
          p_task_type: string;
        };
        Returns: void;
      };
    };
  };
};

// ── 便利な型エイリアス ──────────────────────────────────────
export type Profile = Database['public']['Tables']['profiles']['Row'];
export type Client  = Database['public']['Tables']['clients']['Row'];
export type UsageLog = Database['public']['Tables']['usage_logs']['Row'];

export type ClientInsert = Database['public']['Tables']['clients']['Insert'];
export type ClientUpdate  = Database['public']['Tables']['clients']['Update'];
