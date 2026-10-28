-- better-supabase module: workflow-editor
-- @bsb-block-data workflow-editor
-- @bsb-hash sha256:09d9c614c5c08b616fc80df99dd8fdf2508fa5ee576a21a3811fb7217f44e6b2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

insert into better_supabase.blocks (name, version, mode)
values ('workflow-editor', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
