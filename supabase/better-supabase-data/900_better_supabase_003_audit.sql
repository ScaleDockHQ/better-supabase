-- better-supabase module: audit
-- @bsb-block-data audit
-- @bsb-hash sha256:fe7e8d0aa0d0ba07093b04f6d026119d93c2bd1be527f9641efec6e332bddc20
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

drop event trigger if exists bsb_audit_forget_dropped;
create event trigger bsb_audit_forget_dropped on sql_drop
  when tag in ('DROP TABLE', 'DROP SCHEMA')
  execute function better_supabase.audit_forget_dropped();

-- Registrations of tables dropped before bsb_audit_forget_dropped existed.
delete from "better_supabase"."audited_tables" a
where not exists (select 1 from pg_catalog.pg_class c where c.oid = a."target"::oid);

insert into better_supabase.blocks (name, version, mode)
values ('audit', 14, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
