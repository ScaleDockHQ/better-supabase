-- better-supabase module: custom-fields
-- @bsb-block-data custom-fields
-- @bsb-hash sha256:d821d36fc5eda28c77c14382808495b444beebbddd0b01f2df822abaf1256de2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.field_definitions', target_type => 'field_definition', event_prefix => 'field_definition', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('custom-fields', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
