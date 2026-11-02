-- better-supabase module: audit
-- @bsb-block-test audit
-- @bsb-hash sha256:f5b8bb121ff925cbff3b3558d928764ad8275a52e93b5e6d0157272f708dca7d
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(4);

select extensions.has_trigger('better_supabase', 'messages', 'bsb_audit', 'better_supabase.messages has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'messages', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.messages calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."messages"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.messages is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."messages"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.messages is registered with its redacted columns');

select * from extensions.finish();
rollback;
