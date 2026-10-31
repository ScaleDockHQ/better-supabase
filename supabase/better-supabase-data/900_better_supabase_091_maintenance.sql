-- better-supabase module: maintenance
-- @bsb-block-data maintenance
-- @bsb-hash sha256:a0ccc1da1ce32a36eafb5c579cb76ec4ab7c8d72a3f650115a74b857f4a49eaa
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

alter table better_supabase.blocks add column if not exists block text;
insert into better_supabase.blocks (name, block, version, mode)
values ('maintenance', 'tasks', 4, 'managed')
on conflict (name) do update
  set block = excluded.block, version = excluded.version, mode = excluded.mode, updated_at = now();
