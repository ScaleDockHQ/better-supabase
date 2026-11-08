-- Every block table names its tenant column tenant_id (ADR 0348). Renames only:
-- no row moves. A table the project doesn't have is skipped.
do $$
declare
  r record;
begin
  for r in
    select unnest(array[
    'agent_installs',
    'agents',
    'ai_batch_items',
    'ai_batches',
    'ai_cache_entries',
    'ai_chats',
    'ai_documents',
    'ai_files',
    'ai_moderation_events',
    'ai_projects',
    'ai_provider_keys',
    'ai_sandboxes',
    'ai_scheduled_tasks',
    'ai_task_runs',
    'ai_tool_policies',
    'api_keys',
    'attachment_document_types',
    'attachment_versions',
    'attachments',
    'audit_events',
    'automation_evaluations',
    'automation_versions',
    'automations',
    'billing_customers',
    'billing_native_subscriptions',
    'comment_tasks',
    'connector_grants',
    'connector_servers',
    'data_exports',
    'data_subject_requests',
    'eval_datasets',
    'eval_runs',
    'flag_overrides',
    'guardrail_decisions',
    'guardrail_policies',
    'hostnames',
    'invitations',
    'invite_codes',
    'knowledge_collection_grants',
    'knowledge_collections',
    'knowledge_documents',
    'legal_holds',
    'memories',
    'memory_message_embeddings',
    'notification_deliveries',
    'notification_delivery_events',
    'notification_digests',
    'notification_events',
    'notification_preferences',
    'notification_recipients',
    'notification_subscriptions',
    'organization_deletions',
    'organization_settings',
    'outbox_events',
    'permission_overrides',
    'prompt_labels',
    'prompt_versions',
    'rate_limit_rules',
    'retention_policies',
    'scim_groups',
    'scim_users',
    'sso_domains',
    'sso_providers',
    'support_requests',
    'support_sessions',
    'timeline_entries',
    'usage_billed_periods',
    'usage_counters',
    'usage_events',
    'usage_history',
    'usage_quotas',
    'webhook_deliveries',
    'webhook_endpoint_secrets',
    'webhook_endpoints'
    ]) as table_name
  loop
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'better_supabase' and table_name = r.table_name and column_name = 'organization_id'
    ) and not exists (
      select 1 from information_schema.columns
      where table_schema = 'better_supabase' and table_name = r.table_name and column_name = 'tenant_id'
    ) then
      execute format('alter table better_supabase.%I rename column organization_id to tenant_id', r.table_name);
    end if;
  end loop;
end
$$;
