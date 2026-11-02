-- better-supabase module: consents
-- @bsb-block-data consents
-- @bsb-hash sha256:27d49be5cdda34627a545e29cfe262e1684baa638d6ae3fe6c7ce16c16b662a5
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Consent purposes the installed blocks contribute (system purposes).
insert into "better_supabase"."consent_purposes" ("tenant_id", "key", "title", "legal_basis", "description")
values (null, 'notification_email', 'Notification email', 'consent', 'Notifications sent by email under a named consent purpose.')
on conflict do nothing;
insert into "better_supabase"."consent_purposes" ("tenant_id", "key", "title", "legal_basis", "description")
values (null, 'outreach_email', 'Outreach email', 'consent', 'Email steps of outreach sequences.')
on conflict do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('consents', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
