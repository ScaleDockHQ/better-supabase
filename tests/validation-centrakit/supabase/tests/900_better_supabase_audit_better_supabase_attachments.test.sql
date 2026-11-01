-- better-supabase module: audit
-- @bsb-block-test audit
-- @bsb-hash sha256:3f1b049545703225913aae97c78bbd13d99e9403b279e2a09179cdab1e679ef6
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(4);

select extensions.has_trigger('better_supabase', 'attachments', 'bsb_audit', 'better_supabase.attachments has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'attachments', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.attachments calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."attachments"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.attachments is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."attachments"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.attachments is registered with its redacted columns');

select * from extensions.finish();
rollback;
