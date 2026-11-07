-- Columns the blocks add to centrakit.share_links, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "centrakit"."share_links" add column if not exists "use_count" integer not null default 0;
alter table "centrakit"."share_links" add column if not exists "last_used_at" timestamptz;
alter table "centrakit"."share_links" add column if not exists "password_hash" text;
alter table "centrakit"."share_links" add column if not exists "download_allowed" boolean not null default true;
