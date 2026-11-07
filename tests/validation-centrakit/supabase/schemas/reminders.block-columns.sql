-- Columns the blocks add to centrakit.reminders, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "centrakit"."reminders" add column if not exists "remind_at" timestamptz;
