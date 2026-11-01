-- better-supabase module: document-templates
-- @bsb-block-data document-templates
-- @bsb-hash sha256:9583aaa09d07839093d6d62721ded388961f4622fdffe43a1e36011ffc2c8765
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.document_templates', target_type => 'document_template', event_prefix => 'document_template', deferred => true);
select better_supabase.audit('better_supabase.document_text_blocks', target_type => 'document_text_block', event_prefix => 'document_text_block', deferred => true);
select better_supabase.audit('better_supabase.rendered_documents', target_type => 'document_snapshot', event_prefix => 'document_snapshot', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('document-templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
