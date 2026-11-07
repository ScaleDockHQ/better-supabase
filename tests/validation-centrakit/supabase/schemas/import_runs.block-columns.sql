-- Columns the blocks add to centrakit.import_runs, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "centrakit"."import_runs" add column if not exists "dry_run" boolean not null default false;
alter table "centrakit"."import_runs" add column if not exists "full" boolean not null default false;
alter table "centrakit"."import_runs" add column if not exists "input_checksum" text;
alter table "centrakit"."import_runs" add column if not exists "correlation_id" text;
alter table "centrakit"."import_runs" add column if not exists "scope_aliases" jsonb not null default '[]'::jsonb;
alter table "centrakit"."import_runs" add column if not exists "started_at" timestamptz;
alter table "centrakit"."import_runs" add column if not exists "finished_at" timestamptz;
