-- better-supabase module: mail-sync
-- @bsb-block-data mail-sync
-- @bsb-hash sha256:d6a123587cb645382f05a5bcf1646a69732f74274975711e06de8fdf256fc03f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.mail_threads', target_type => 'mail_thread', event_prefix => 'mail_thread', deferred => true);
select better_supabase.audit('better_supabase.mail_accounts', target_type => 'mail_account', event_prefix => 'mail_account', deferred => true);
select better_supabase.audit('better_supabase.mail_messages', target_type => 'mail_message', event_prefix => 'mail_message', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('mail-sync', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
