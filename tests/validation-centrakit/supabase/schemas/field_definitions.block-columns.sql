-- Columns the blocks add to centrakit.field_definitions, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "centrakit"."field_definitions" add column if not exists "encrypted" boolean not null default false;
alter table "centrakit"."field_definitions" add column if not exists "pack" text;
alter table "centrakit"."field_definitions" add column if not exists "pack_version" integer;
