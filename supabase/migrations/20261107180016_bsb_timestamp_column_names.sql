-- Timestamp columns end in _at (ADR 0274). Renames only: no row moves. A table
-- or column the project doesn't have is skipped.
do $$
declare
  r record;
begin
  for r in
    select * from (values
    ('ai_harness_sessions', 'locked_until', 'lock_expires_at'),
    ('drive_nodes', 'locked_until', 'lock_expires_at'),
    ('idempotency_keys', 'locked_until', 'lock_expires_at'),
    ('inbox_inbound_events', 'locked_until', 'lock_expires_at'),
    ('webhook_inbox', 'locked_until', 'lock_expires_at'),
    ('workflow_schedules', 'locked_until', 'lock_expires_at'),
    ('ai_task_runs', 'scheduled_for', 'scheduled_at'),
    ('messages', 'scheduled_for', 'scheduled_at'),
    ('scheduled_inbox_messages', 'scheduled_for', 'scheduled_at'),
    ('api_keys', 'window_start', 'window_started_at'),
    ('rate_limits', 'window_start', 'window_started_at'),
    ('calendar_events', 'original_start', 'original_starts_at'),
    ('drive_nodes', 'legal_hold_until', 'legal_hold_expires_at'),
    ('drive_nodes', 'effective_from', 'effective_at'),
    ('import_records', 'missing_since', 'went_missing_at'),
    ('import_records', 'subject_updated_at_at_import', 'subject_imported_updated_at'),
    ('inbox_conversations', 'snoozed_until', 'snooze_expires_at'),
    ('metric_points', 'bucket_start', 'bucket_started_at'),
    ('organization_deletions', 'purge_after', 'purge_at'),
    ('trash_items', 'purge_after', 'purge_at'),
    ('outbox_consumers', 'lease_until', 'lease_expires_at'),
    ('webhook_deliveries', 'leased_until', 'lease_expires_at'),
    ('signing_keys', 'publish_until', 'publish_expires_at'),
    ('subject_lifecycles', 'paused_until', 'pause_expires_at'),
    ('webhook_endpoints', 'failing_since', 'first_failed_at'),
    ('workflow_runs', 'dispatch_until', 'dispatch_expires_at'),
    ('workflow_start_requests', 'claimed_until', 'claim_expires_at'),
    ('workflow_start_requests', 'not_before', 'not_before_at'),
    ('passes', 'valid_from', 'starts_at'),
    ('passes', 'valid_until', 'expires_at'),
    ('product_prices', 'valid_from', 'starts_at'),
    ('product_prices', 'valid_until', 'expires_at'),
    ('consents', 'valid_until', 'expires_at')
    ) as renames (table_name, old_name, new_name)
  loop
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'better_supabase' and table_name = r.table_name and column_name = r.old_name
    ) then
      execute format('alter table better_supabase.%I rename column %I to %I', r.table_name, r.old_name, r.new_name);
    end if;
  end loop;
end
$$;
