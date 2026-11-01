-- better-supabase module: ai-files
-- @bsb-block-data ai-files
-- @bsb-hash sha256:0cce10b60a462b023b8d67a4819a819b6c4c94751e9fbf99b6f83a7a9044968c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ai-files', 'ai-files', false, 52428800, null)
on conflict (id) do nothing;

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.ai_documents', target_type => 'ai_document', event_prefix => 'ai_document', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('ai-files', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
