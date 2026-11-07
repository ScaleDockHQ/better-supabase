-- Columns the blocks add to centrakit.notification_preferences, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "centrakit"."notification_preferences" add column if not exists "cadence" text not null default 'immediate' check ("cadence" in ('immediate', 'daily', 'weekly', 'off'));
