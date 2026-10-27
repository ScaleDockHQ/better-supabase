-- Reads the Next.js example needs that the hiring module doesn't provide
-- yet: the openings and the applications on the hiring board. SECURITY
-- INVOKER, so the hiring read policy (`hiring.read`) decides what each
-- caller sees.
create or replace function api.list_jobs(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', j.id,
    'title', j.title,
    'status', j.status,
    'location', j.location
  ) order by j.created_at desc), '[]'::jsonb)
  from better_supabase.job_openings j
  where j.tenant_id = list_jobs.tenant;
$$;

create or replace function api.list_applications(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'job_id', a.job_id,
    'stage_id', a.stage_id,
    'state', a.state,
    'candidate_type', a.candidate_type,
    'candidate_id', a.candidate_id,
    'candidate_name', better_supabase.subject_title(a.candidate_type, a.candidate_id)
  ) order by a.stage_id, a.rank collate "C"), '[]'::jsonb)
  from better_supabase.applications a
  where a.tenant_id = list_applications.tenant;
$$;

revoke all on function api.list_jobs(uuid) from public, anon;
revoke all on function api.list_applications(uuid) from public, anon;
grant execute on function api.list_jobs(uuid) to authenticated;
grant execute on function api.list_applications(uuid) to authenticated;
