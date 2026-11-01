-- better-supabase module: quotes
-- @bsb-block-data quotes
-- @bsb-hash sha256:1826d38ca72e944d283ac6908067a101336d0a9bd52ed66fc174f8244994ed6a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."automation_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('quotes.quote_to_order', 'quotes', 'quote', 'quote.accepted', 'Order each accepted quote', 'Creates an order for the accepted quote, linked created_from the quote, so an accepted quote orders once.', '[{"kind":"orders.from_quote","config":{"targetType":"order"}}]'::jsonb, false)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.quotes', target_type => 'quote', event_prefix => 'quote', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('quotes', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
