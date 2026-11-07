-- A user reference is named by its role, <role>_id (ADR 0347). Renames only: no
-- row moves. A table or column the project doesn't have is skipped.
do $$
declare
  r record;
begin
  for r in
    select * from (values
    ('activities', 'owner_user_id', 'owner_id'),
    ('ai_chat_participants', 'customer_user_id', 'customer_id'),
    ('application_scorecards', 'reviewer_user_id', 'reviewer_id'),
    ('applications', 'owner_user_id', 'owner_id'),
    ('appraisals', 'subject_user_id', 'appraisee_id'),
    ('booking_resources', 'host_user_id', 'host_id'),
    ('bookings', 'customer_user_id', 'customer_id'),
    ('companies', 'owner_user_id', 'owner_id'),
    ('consents', 'given_by_user_id', 'grantor_id'),
    ('deals', 'owner_user_id', 'owner_id'),
    ('enrollment_steps', 'assignee_user_id', 'assignee_id'),
    ('forecast_snapshot_deals', 'owner_user_id', 'owner_id'),
    ('goals', 'owner_user_id', 'owner_id'),
    ('job_openings', 'hiring_manager_user_id', 'hiring_manager_id'),
    ('passes', 'holder_user_id', 'holder_id'),
    ('people', 'owner_user_id', 'owner_id'),
    ('pipeline_stage_history', 'actor_user_id', 'actor_id'),
    ('projects', 'owner_user_id', 'owner_id'),
    ('quotes', 'decided_user_id', 'decider_id'),
    ('quotes', 'owner_user_id', 'owner_id'),
    ('referrals', 'referred_user_id', 'referred_id'),
    ('shift_swaps', 'from_user_id', 'from_id'),
    ('shift_swaps', 'to_user_id', 'to_id'),
    ('status_history', 'actor_user_id', 'actor_id'),
    ('subject_lifecycles', 'paused_by_user_id', 'paused_by'),
    ('booking_series', 'customer_user_id', 'customer_id'),
    ('engagement_transcript_segments', 'speaker_user_id', 'speaker_id'),
    ('work_projects', 'owner_user_id', 'owner_id')
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
