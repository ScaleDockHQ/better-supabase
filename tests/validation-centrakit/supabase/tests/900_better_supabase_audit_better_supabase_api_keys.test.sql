-- better-supabase module: audit
-- @bsb-block-test audit
-- @bsb-hash sha256:ced1c13af7dd16455ee78b531e522fc3cd27f13ce6d883a071d529d76cf7edc7
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(4);

select extensions.has_trigger('better_supabase', 'api_keys', 'bsb_audit', 'better_supabase.api_keys has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'api_keys', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.api_keys calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."api_keys"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.api_keys is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."api_keys"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.api_keys is registered with its redacted columns');

select * from extensions.finish();
rollback;
