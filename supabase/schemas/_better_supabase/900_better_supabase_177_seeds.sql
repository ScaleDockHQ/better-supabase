-- better-supabase module: seeds
-- @bsb-block seeds@1 managed
-- @bsb-hash sha256:95c8de0ce76682a5330244a932e580bb0aada3d5a22a9700cda1e29274f636c8
-- seed_tenant_defaults(tenant, variants, locale) applies the defaults every installed block declares, in install order. The organizations block calls it when an organization is created.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Applies the defaults of every installed module to an organization. Call it
-- from the organization's create hook or with `better-supabase db seed --defaults`.
create or replace function "better_supabase".seed_tenant_defaults(p_tenant uuid, p_variants jsonb default '{}'::jsonb, p_locale text default 'en')
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform "better_supabase"."seed_attachments_defaults"(p_tenant, p_variants ->> 'attachments', p_locale);
  perform "better_supabase"."seed_inbox_defaults"(p_tenant, p_variants ->> 'inbox', p_locale);
  perform "better_supabase"."seed_calendar_defaults"(p_tenant, p_variants ->> 'calendar', p_locale);
  perform "better_supabase"."seed_cases_defaults"(p_tenant, p_variants ->> 'cases', p_locale);
  perform "better_supabase"."seed_pipelines_defaults"(p_tenant, p_variants ->> 'pipelines', p_locale);
  perform "better_supabase"."seed_leave_defaults"(p_tenant, p_variants ->> 'leave', p_locale);
  perform "better_supabase"."seed_risks_defaults"(p_tenant, p_variants ->> 'risks', p_locale);
  perform "better_supabase"."seed_tax_defaults"(p_tenant, p_variants ->> 'tax', p_locale);
  perform "better_supabase"."seed_accounting_defaults"(p_tenant, p_variants ->> 'accounting', p_locale);
  perform "better_supabase"."seed_document_templates_defaults"(p_tenant, p_variants ->> 'document-templates', p_locale);
end;
$$;
revoke execute on function "better_supabase".seed_tenant_defaults(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase".seed_tenant_defaults(uuid, jsonb, text) to service_role;
