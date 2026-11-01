-- better-supabase module: documents
-- @bsb-block-data documents
-- @bsb-hash sha256:0e762a96f332ee03702c06a05d8ca9cbf1efc7db31968099740b0944d0d8acb5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.documents', target_type => 'document', event_prefix => 'document', deferred => true);
select better_supabase.audit('better_supabase.document_suggestions', target_type => 'document_suggestion', event_prefix => 'document_suggestion', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('documents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
