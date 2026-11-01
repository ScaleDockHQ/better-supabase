-- better-supabase module: legal-entities
-- @bsb-block-data legal-entities
-- @bsb-hash sha256:ae7a1d1639f32d0d8f7ef760816a8911a32721546a710deaf670d52f5f250450
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.legal_entities', target_type => 'legal_entity', event_prefix => 'legal_entity', deferred => true);
select better_supabase.audit('better_supabase.legal_entity_settings', target_type => 'legal_entity_setting', event_prefix => 'legal_entity_setting', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('legal-entities', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
