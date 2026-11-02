-- better-supabase module: audit
-- @bsb-block-test audit
-- @bsb-hash sha256:568d18cbddb13b44aa0a296c0c0c548e92952688f6bd2aa7f70474aecb0b4cec
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(4);

select extensions.has_trigger('better_supabase', 'conversations', 'bsb_audit', 'better_supabase.conversations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'conversations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.conversations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."conversations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.conversations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."conversations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.conversations is registered with its redacted columns');

select * from extensions.finish();
rollback;
