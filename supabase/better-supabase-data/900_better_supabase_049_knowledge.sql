-- better-supabase module: knowledge
-- @bsb-block-data knowledge
-- @bsb-hash sha256:05390facbd6a73f50cdf4f37accedc1a3c1857d32964872afe53b4c67a940e04
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.knowledge_documents', target_type => 'knowledge_document', event_prefix => 'knowledge_document', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('knowledge', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
