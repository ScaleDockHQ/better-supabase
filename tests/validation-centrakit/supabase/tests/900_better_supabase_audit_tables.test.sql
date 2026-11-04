-- better-supabase module: audit
-- @bsb-block-test audit
-- @bsb-hash sha256:fcebfb36f7a5e31827964c814de8c313a1de5a68460a1ea89c7123fa5393b7a6
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(16);

select extensions.has_trigger('better_supabase', 'api_keys', 'bsb_audit', 'better_supabase.api_keys has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'api_keys', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.api_keys calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."api_keys"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.api_keys is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."api_keys"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.api_keys is registered with its redacted columns');

select extensions.has_trigger('better_supabase', 'attachments', 'bsb_audit', 'better_supabase.attachments has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'attachments', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.attachments calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."attachments"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.attachments is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."attachments"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.attachments is registered with its redacted columns');

select extensions.has_trigger('better_supabase', 'conversations', 'bsb_audit', 'better_supabase.conversations has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'conversations', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.conversations calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."conversations"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.conversations is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."conversations"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.conversations is registered with its redacted columns');

select extensions.has_trigger('better_supabase', 'messages', 'bsb_audit', 'better_supabase.messages has the bsb_audit trigger');
select extensions.trigger_is('better_supabase', 'messages', 'bsb_audit', 'better_supabase', 'audit_row_change', 'bsb_audit on better_supabase.messages calls audit_row_change()');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."messages"'::regclass) -> 'ignore', '[]'))), '{}'::text[], 'better_supabase.messages is registered with its ignored columns');
select extensions.is(array(select jsonb_array_elements_text(coalesce(better_supabase.audit_settings('"better_supabase"."messages"'::regclass) -> 'redact', '[]'))), '{}'::text[], 'better_supabase.messages is registered with its redacted columns');

select * from extensions.finish();
rollback;
