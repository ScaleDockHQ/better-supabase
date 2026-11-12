-- The bulk action `work.setState` (config `bulk-actions.options.actions`): sets
-- one work item's state for the bulk bar on /work/grid. Bulk rows run as the
-- caller, and `authenticated` can only read `better_supabase.work_items`, so the
-- write happens here, after the same `tasks.write` check the work block's own
-- functions make. The state trigger still checks the edge and records the
-- history row.
create or replace function public.work_bulk_state(tenant uuid, subject_type text, subject_id text, args jsonb)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_to text := work_bulk_state.args ->> 'to';
begin
  if not better_supabase.actor_may_write() then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (
    ((select auth.jwt() ->> 'role') = 'service_role')
    or coalesce(better_supabase.can('tenant', work_bulk_state.tenant, 'tasks.write'), false)
  ) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_to is null then
    raise exception 'args.to is required' using errcode = '22023', hint = 'BULK_STATE_ARGS';
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(work_bulk_state.args ->> 'reason', ''), true);
  update better_supabase.work_items x
  set state = v_to
  where x.id = work_bulk_state.subject_id::uuid
    and x.tenant_id = work_bulk_state.tenant
    and x.archived_at is null;
  if not found then
    perform set_config('better_supabase.transition_reason', '', true);
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  perform set_config('better_supabase.transition_reason', '', true);
end;
$$;

revoke execute on function public.work_bulk_state(uuid, text, text, jsonb) from public, anon;

grant execute on function public.work_bulk_state(uuid, text, text, jsonb) to authenticated, service_role;

comment on function public.work_bulk_state(uuid, text, text, jsonb) is 'Bulk action work.setState: sets a work item''s state after the tasks.write check.';
