SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.data_restore_tables()
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return (
  with listed as (
    select t.name, t.tbl, t.col, t.omit, to_regclass(t.tbl) as oid
    from "better_supabase"."data_lifecycle_tables"() t
    where t.subject = 'organization' and t.exported and to_regclass(t.tbl) is not null
      and t.name <> all (array['better_supabase.access_requests', 'better_supabase.agent_installs', 'better_supabase.agent_mandates', 'better_supabase.agents', 'better_supabase.ai_batch_items', 'better_supabase.ai_batches', 'better_supabase.ai_provider_keys', 'better_supabase.api_keys', 'better_supabase.approval_decisions', 'better_supabase.approval_items', 'better_supabase.approval_policies', 'better_supabase.approval_requests', 'better_supabase.audit_events', 'better_supabase.billing_customers', 'better_supabase.billing_native_subscriptions', 'better_supabase.billing_subscriptions', 'better_supabase.checkout_sessions', 'better_supabase.connector_grants', 'better_supabase.connector_servers', 'better_supabase.conversation_members', 'better_supabase.deal_members', 'better_supabase.drive_drive_grants', 'better_supabase.drive_grants', 'better_supabase.flag_overrides', 'better_supabase.guest_grants', 'better_supabase.guests', 'better_supabase.hostnames', 'better_supabase.import_chunks', 'better_supabase.import_records', 'better_supabase.import_runs', 'better_supabase.inspection_members', 'better_supabase.invitations', 'better_supabase.invoice_approval_levels', 'better_supabase.invoice_approvals', 'better_supabase.knowledge_collection_grants', 'better_supabase.outbox_events', 'better_supabase.permission_overrides', 'better_supabase.scim_groups', 'better_supabase.scim_users', 'better_supabase.service_principals', 'better_supabase.share_links', 'better_supabase.sso_domains', 'better_supabase.sso_providers', 'better_supabase.subject_members', 'better_supabase.support_requests', 'better_supabase.support_sessions', 'better_supabase.team_members', 'better_supabase.teams', 'better_supabase.usage_billed_periods', 'better_supabase.usage_counters', 'better_supabase.usage_distinct', 'better_supabase.usage_events', 'better_supabase.usage_history', 'better_supabase.usage_quotas', 'better_supabase.webhook_endpoint_secrets', 'better_supabase.workflow_credentials', 'public.memberships']::text[])
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'name', l.name,
    'tenantColumn', l.col,
    'columns', (
      select coalesce(jsonb_agg(a.attname order by a.attnum), '[]'::jsonb)
      from pg_catalog.pg_attribute a
      where a.attrelid = l.oid and a.attnum > 0 and not a.attisdropped
        and a.attgenerated = '' and a.attidentity <> 'a'
        and a.attname <> all (coalesce(l.omit, '{}'))
    ),
    'keyColumns', (
      select coalesce(jsonb_agg(a.attname order by k.ord), '[]'::jsonb)
      from pg_catalog.pg_constraint c
      cross join lateral unnest(c.conkey) with ordinality as k(attnum, ord)
      join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
      where c.conrelid = l.oid and c.contype = 'p' and a.attname <> l.col
    ),
    'references', (
      select coalesce(jsonb_agg(distinct o.name), '[]'::jsonb)
      from pg_catalog.pg_constraint c
      join listed o on o.oid = c.confrelid
      where c.conrelid = l.oid and c.contype = 'f' and c.confrelid <> c.conrelid
    )
  ) order by l.name), '[]'::jsonb)
  from listed l
  );
end
$function$;
