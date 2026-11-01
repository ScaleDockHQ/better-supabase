-- better-supabase module: qualifications
-- @bsb-block-data qualifications
-- @bsb-hash sha256:650c2bd75077321a10c7aedecf9c1f5e7a4a7614cc2114b510b41e78f4ddebe8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.qualifications', target_type => 'qualification', event_prefix => 'qualification', deferred => true);
select better_supabase.audit('better_supabase.qualification_types', target_type => 'qualification_type', event_prefix => 'qualification_type', deferred => true);
select better_supabase.audit('better_supabase.qualification_requirements', target_type => 'qualification_requirement', event_prefix => 'qualification_requirement', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('qualifications', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
