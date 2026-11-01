-- better-supabase module: consents
-- @bsb-block-data consents
-- @bsb-hash sha256:4394c9ff386bb3b7bdba254f39844b9e6796de2595817774fbe313e28aa4b921
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.consents', target_type => 'consent', event_prefix => 'consent', deferred => true);
select better_supabase.audit('better_supabase.consent_purposes', target_type => 'consent_purpose', event_prefix => 'consent_purpose', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('consents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
