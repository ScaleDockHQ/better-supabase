-- better-supabase module: ai-chat
-- @bsb-block-data ai-chat
-- @bsb-hash sha256:3327d9f734c036dbbceb467ff8215e8ecf97e75a84d82950791d5d0fd5246cb5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-chat', 6, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
