-- ==== alone: schema supabase/schemas/900_better_supabase_091_hiring.sql
-- better-supabase module: hiring
-- @bsb-block hiring@2 managed
-- @bsb-hash sha256:35bbcb7279b04b5ecea7c250a86a6973d62fc5cd1a52f872f65197e7aae03a62
-- Jobs and applications on a pipeline per job, candidates from config.recordTypes, scorecards per stage, interviews, and hire, reject and withdraw events for the app to act on.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Hiring: jobs, applications on a pipeline per job, scorecards per stage,
-- interviews, and a hire event the app turns into an employee.

create table "better_supabase"."job_openings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "title" text not null constraint bsb_job_openings_title_check check (length("title") >= 1 and length("title") <= 200),
  "team_id" uuid,
  "location" text,
  "employment_type" text,
  "description" text,
  "hiring_manager_id" uuid,
  "status" text not null default 'draft' constraint bsb_job_openings_status_check check ("status" in ('draft', 'open', 'closed')),
  "opened_at" timestamptz,
  "closed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index jobs_tenant_status_idx on "better_supabase"."job_openings" ("tenant_id", "status");
alter table "better_supabase"."job_openings" enable row level security;
revoke all on "better_supabase"."job_openings" from public, anon, authenticated;
grant select on "better_supabase"."job_openings" to authenticated;
grant all on "better_supabase"."job_openings" to service_role;
create policy bsb_jobs_read on "better_supabase"."job_openings"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "better_supabase"."applications" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "job_id" uuid not null references "better_supabase"."job_openings" ("id") on delete cascade,
  "candidate_type" text not null,
  "candidate_id" text not null,
  "source" text,
  "owner_id" uuid,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  "state" text not null default 'active' constraint bsb_applications_state_check check ("state" in ('active', 'hired', 'rejected', 'withdrawn')),
  "rejection_reason" text,
  "hired_at" timestamptz,
  "rank" text collate "C" not null default 'V',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("job_id", "candidate_type", "candidate_id")
);
create index applications_board_idx on "better_supabase"."applications" ("pipeline_id", "stage_id", "rank");
create index applications_candidate_idx on "better_supabase"."applications" ("candidate_type", "candidate_id");
alter table "better_supabase"."applications" enable row level security;
revoke all on "better_supabase"."applications" from public, anon, authenticated;
grant select on "better_supabase"."applications" to authenticated;
grant all on "better_supabase"."applications" to service_role;
create policy bsb_applications_read on "better_supabase"."applications"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "better_supabase"."application_scorecards" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "application_id" uuid not null references "better_supabase"."applications" ("id") on delete cascade,
  "stage_id" uuid,
  "reviewer_id" uuid not null,
  "rating" smallint not null constraint bsb_application_scorecards_rating_check check ("rating" >= 1 and "rating" <= 4),
  "recommendation" text not null constraint bsb_application_scorecards_recommendation_check check ("recommendation" in ('strong_no', 'no', 'yes', 'strong_yes')),
  "notes" text,
  "submitted_at" timestamptz not null default now(),
  unique nulls not distinct ("application_id", "stage_id", "reviewer_id")
);
create index application_scorecards_reviewer_idx on "better_supabase"."application_scorecards" ("reviewer_id");
alter table "better_supabase"."application_scorecards" enable row level security;
revoke all on "better_supabase"."application_scorecards" from public, anon, authenticated;
grant select on "better_supabase"."application_scorecards" to authenticated;
grant all on "better_supabase"."application_scorecards" to service_role;
create policy bsb_application_scorecards_read on "better_supabase"."application_scorecards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "better_supabase"."interviews" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "application_id" uuid not null references "better_supabase"."applications" ("id") on delete cascade,
  "kind" text,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "location" text,
  "interviewer_user_ids" uuid[] not null default '{}',
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  constraint bsb_interviews_check check ("ends_at" > "starts_at")
);
create index interviews_application_idx on "better_supabase"."interviews" ("application_id", "starts_at");
alter table "better_supabase"."interviews" enable row level security;
revoke all on "better_supabase"."interviews" from public, anon, authenticated;
grant select on "better_supabase"."interviews" to authenticated;
grant all on "better_supabase"."interviews" to service_role;
create policy bsb_interviews_read on "better_supabase"."interviews"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')) or (select auth.uid()) = any ("interviewer_user_ids"));

-- A rejected, withdrawn or hired application records its event and its
-- time; reopening clears them.
create or replace function better_supabase.bsb_application_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."state" is not distinct from old."state" then
    new."updated_at" := now();
    return new;
  end if;
  new."hired_at" := case when new."state" = 'hired' then now() end;
  if new."state" <> 'rejected' then
    new."rejection_reason" := null;
  end if;
  case new."state"
    when 'hired' then null;
    when 'rejected' then null;
    when 'withdrawn' then null;
    else null;
  end case;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_application_guard() from public, anon, authenticated;
create trigger bsb_application_guard before update of "state" on "better_supabase"."applications"
for each row execute function better_supabase.bsb_application_guard();

-- Creates or changes a job: title, teamId, location, employmentType,
-- description, hiringManagerId, fields (the extra columns by name); and
-- status draft, open or closed.
create or replace function "better_supabase"."save_job"(tenant uuid, job uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job "better_supabase"."job_openings";
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_job.tenant, 'hiring.manage'), false)) then
    raise exception 'not allowed to manage jobs' using errcode = '42501', hint = 'HIRING_FORBIDDEN';
  end if;
  if save_job.job is not null then
    select * into v_job from "better_supabase"."job_openings" x where x."id" = save_job.job and x."tenant_id" = save_job.tenant;
    if v_job."id" is null then
      raise exception 'job not found' using errcode = 'P0002', hint = 'JOB_OPENING_NOT_FOUND';
    end if;
    v_was := v_job."status";
  end if;
  begin
    if save_job.job is null then
      insert into "better_supabase"."job_openings" ("tenant_id", "title", "team_id", "location", "employment_type", "description", "hiring_manager_id", "status")
      values (save_job.tenant, save_job.attrs ->> 'title', (save_job.attrs ->> 'teamId')::uuid, save_job.attrs ->> 'location',
        save_job.attrs ->> 'employmentType', save_job.attrs ->> 'description', (save_job.attrs ->> 'hiringManagerId')::uuid,
        coalesce(save_job.attrs ->> 'status', 'draft'))
      returning * into v_job;
    else
      update "better_supabase"."job_openings" x set
        "title" = coalesce(save_job.attrs ->> 'title', x."title"),
        "team_id" = case when save_job.attrs ? 'teamId' then (save_job.attrs ->> 'teamId')::uuid else x."team_id" end,
        "location" = case when save_job.attrs ? 'location' then save_job.attrs ->> 'location' else x."location" end,
        "employment_type" = case when save_job.attrs ? 'employmentType' then save_job.attrs ->> 'employmentType' else x."employment_type" end,
        "description" = case when save_job.attrs ? 'description' then save_job.attrs ->> 'description' else x."description" end,
        "hiring_manager_id" = case when save_job.attrs ? 'hiringManagerId' then (save_job.attrs ->> 'hiringManagerId')::uuid else x."hiring_manager_id" end,
        "status" = coalesce(save_job.attrs ->> 'status', x."status"),
        "updated_at" = now()
      where x."id" = save_job.job
      returning * into v_job;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a job needs a title and a status of draft, open or closed' using errcode = '22023', hint = 'JOB_OPENING_INVALID';
  end;
  if v_job."status" is distinct from v_was then
    if v_job."status" = 'open' then
      update "better_supabase"."job_openings" x set "opened_at" = coalesce(x."opened_at", now()), "closed_at" = null where x."id" = v_job."id" returning * into v_job;
      null;
    elsif v_job."status" = 'closed' then
      update "better_supabase"."job_openings" x set "closed_at" = now() where x."id" = v_job."id" returning * into v_job;
      null;
    end if;
  end if;
  return to_jsonb(v_job);
end;
$$;
revoke execute on function "better_supabase"."save_job"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_job"(uuid, uuid, jsonb) to authenticated, service_role;

-- An application of a candidate (a record in config.recordTypes, a person by
-- default) to an open job. Applying again returns the same application.

create or replace function "better_supabase"."apply_to_job"(job uuid, candidate jsonb, source text, owner uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job "better_supabase"."job_openings";
  v_row "better_supabase"."applications";
  v_type text := coalesce(apply_to_job.candidate ->> 'type', 'person');
  v_id text := apply_to_job.candidate ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_job from "better_supabase"."job_openings" x where x."id" = apply_to_job.job;
  if v_job."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_job."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such job you can add applications to' using errcode = 'P0002', hint = 'JOB_OPENING_NOT_FOUND';
  end if;
  if v_job."status" <> 'open' then
    raise exception 'the job isn''t open' using errcode = '55000', hint = 'JOB_OPENING_NOT_OPEN';
  end if;
  if v_id is null or not false then
    raise exception 'the candidate is unknown or not readable in this organization' using errcode = '42501', hint = 'HIRING_CANDIDATE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."applications" x
  where x."job_id" = v_job."id" and x."candidate_type" = v_type and x."candidate_id" = v_id;
  if v_row."id" is not null then
    return to_jsonb(v_row);
  end if;
  insert into "better_supabase"."applications" ("tenant_id", "job_id", "candidate_type", "candidate_id", "source", "owner_id")
  values (v_job."tenant_id", v_job."id", v_type, v_id, nullif(trim(apply_to_job.source), ''), coalesce(apply_to_job.owner, auth.uid()))
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."apply_to_job"(uuid, jsonb, text, uuid) from public, anon;
grant execute on function "better_supabase"."apply_to_job"(uuid, jsonb, text, uuid) to authenticated, service_role;

-- Ends an application: hired, rejected (with a reason) or withdrawn. It
-- moves to the job pipeline's first stage of that category.
create or replace function "better_supabase"."close_application"(application uuid, outcome text, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = close_application.application;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such application you can change' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  if close_application.outcome not in ('hired', 'rejected', 'withdrawn') then
    raise exception 'close as hired, rejected or withdrawn' using errcode = '22023', hint = 'HIRING_OUTCOME_INVALID';
  end if;
  if close_application.outcome = 'hired' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_application_hire"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."applications" x set "rejection_reason" = nullif(trim(close_application.reason), '') where x."id" = v_row."id";
  case close_application.outcome
    when 'hired' then 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'success' and x."category" = 'hired'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
    when 'rejected' then 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'failure' and x."category" = 'rejected'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
    else 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'failure' and x."category" = 'withdrawn'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
  end case;
  if close_application.outcome = 'hired' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_application_hire"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (select to_jsonb(x) from "better_supabase"."applications" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."close_application"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."close_application"(uuid, text, text) to authenticated, service_role;

-- The caller's scorecard on an application at its current stage: a rating
-- from 1 to 4 and a recommendation. Submitting again replaces it.
create or replace function "better_supabase"."submit_scorecard"(application uuid, rating integer, recommendation text, notes text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_card "better_supabase"."application_scorecards";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = submit_scorecard.application;
  if v_row."id" is null or not (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) or exists (
    select 1 from "better_supabase"."interviews" y where y."application_id" = v_row."id" and auth.uid() = any (y."interviewer_user_ids"))) then
    raise exception 'no such application you can review' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  begin
    insert into "better_supabase"."application_scorecards" ("tenant_id", "application_id", "stage_id", "reviewer_id", "rating", "recommendation", "notes")
    values (v_row."tenant_id", v_row."id", v_row."stage_id", auth.uid(), submit_scorecard.rating, submit_scorecard.recommendation, submit_scorecard.notes)
    on conflict ("application_id", "stage_id", "reviewer_id") do update set
      "rating" = excluded."rating", "recommendation" = excluded."recommendation",
      "notes" = excluded."notes", "submitted_at" = now()
    returning * into v_card;
  exception when check_violation or not_null_violation then
    raise exception 'a scorecard needs a rating and a recommendation' using errcode = '22023', hint = 'HIRING_SCORECARD_INVALID';
  end;
  null;
  return to_jsonb(v_card);
end;
$$;
revoke execute on function "better_supabase"."submit_scorecard"(uuid, integer, text, text) from public, anon;
grant execute on function "better_supabase"."submit_scorecard"(uuid, integer, text, text) to authenticated, service_role;

-- Schedules an interview; the interviewers can read it and score the
-- application.
create or replace function "better_supabase"."schedule_interview"(application uuid, starts_at timestamptz, ends_at timestamptz, interviewers uuid[], kind text, location text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_interview "better_supabase"."interviews";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = schedule_interview.application;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such application you can change' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  begin
    insert into "better_supabase"."interviews" ("tenant_id", "application_id", "kind", "starts_at", "ends_at", "location", "interviewer_user_ids", "created_by")
    values (v_row."tenant_id", v_row."id", schedule_interview.kind, schedule_interview.starts_at, schedule_interview.ends_at,
      schedule_interview.location, coalesce(schedule_interview.interviewers, '{}'), auth.uid())
    returning * into v_interview;
  exception when check_violation or not_null_violation then
    raise exception 'an interview needs a start before its end' using errcode = '22023', hint = 'HIRING_INTERVIEW_INVALID';
  end;
  null;
  return to_jsonb(v_interview);
end;
$$;
revoke execute on function "better_supabase"."schedule_interview"(uuid, timestamptz, timestamptz, uuid[], text, text) from public, anon;
grant execute on function "better_supabase"."schedule_interview"(uuid, timestamptz, timestamptz, uuid[], text, text) to authenticated, service_role;

-- An application with its scorecards and interviews, and the average
-- rating and recommendations per stage.
create or replace function "better_supabase"."application_detail"(application uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object(
    'scorecards', coalesce((select jsonb_agg(to_jsonb(c) order by c."submitted_at") from "better_supabase"."application_scorecards" c where c."application_id" = x."id"), '[]'::jsonb),
    'interviews', coalesce((select jsonb_agg(to_jsonb(i) order by i."starts_at") from "better_supabase"."interviews" i where i."application_id" = x."id"), '[]'::jsonb),
    'averageRating', (select round(avg(c."rating"), 2) from "better_supabase"."application_scorecards" c where c."application_id" = x."id"))
  from "better_supabase"."applications" x where x."id" = application_detail.application
$$;
revoke execute on function "better_supabase"."application_detail"(uuid) from public, anon;
grant execute on function "better_supabase"."application_detail"(uuid) to authenticated, service_role;

-- The tenant's jobs, newest first, as the caller (the table's policy decides
-- who sees them). status keeps one status.
create or replace function "better_supabase"."list_jobs"(tenant uuid, status text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."job_openings" x
  where x."tenant_id" = list_jobs.tenant
    and (list_jobs.status is null or x."status" = list_jobs.status)
$$;
revoke execute on function "better_supabase"."list_jobs"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_jobs"(uuid, text) to authenticated, service_role;

-- A job's applications in board order, as the caller. state keeps one state.
create or replace function "better_supabase"."list_applications"(job uuid, state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."stage_id", x."rank" collate "C", x."id"), '[]'::jsonb)
  from "better_supabase"."applications" x
  where x."job_id" = list_applications.job
    and (list_applications.state is null or x."state" = list_applications.state)
$$;
revoke execute on function "better_supabase"."list_applications"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_applications"(uuid, text) to authenticated, service_role;

-- The applications of many jobs in one read, as the caller: the jobs in the
-- order given, each in board order. state keeps one state.
create or replace function "better_supabase"."list_applications_for_jobs"(jobs uuid[], state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by array_position(list_applications_for_jobs.jobs, x."job_id"), x."stage_id", x."rank" collate "C", x."id"), '[]'::jsonb)
  from "better_supabase"."applications" x
  where x."job_id" = any (list_applications_for_jobs.jobs)
    and (list_applications_for_jobs.state is null or x."state" = list_applications_for_jobs.state)
$$;
revoke execute on function "better_supabase"."list_applications_for_jobs"(uuid[], text) from public, anon;
grant execute on function "better_supabase"."list_applications_for_jobs"(uuid[], text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."job_openings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."job_openings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."job_openings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."job_openings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."applications" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."applications" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."applications" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."applications" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."application_scorecards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."application_scorecards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."application_scorecards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."application_scorecards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."interviews" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')) or (select auth.uid()) = any ("interviewer_user_ids"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."interviews" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."interviews" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."interviews" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_091_hiring.sql
-- better-supabase module: hiring
-- @bsb-block-data hiring
-- @bsb-hash sha256:801dba9c4c7577449f5a89527cf0b1dc34056296390ab79d15998c47b81661e1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('hiring', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_091_hiring.sql
-- better-supabase module: hiring
-- @bsb-block hiring@2 managed
-- @bsb-hash sha256:050fbfc564ed9929f66b608ac22f102499e3723e2a18383eef26aa1a275d1542
-- Jobs and applications on a pipeline per job, candidates from config.recordTypes, scorecards per stage, interviews, and hire, reject and withdraw events for the app to act on.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Hiring: jobs, applications on a pipeline per job, scorecards per stage,
-- interviews, and a hire event the app turns into an employee.

create table "better_supabase"."job_openings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "title" text not null constraint bsb_job_openings_title_check check (length("title") >= 1 and length("title") <= 200),
  "team_id" uuid,
  "location" text,
  "employment_type" text,
  "description" text,
  "hiring_manager_id" uuid,
  "status" text not null default 'draft' constraint bsb_job_openings_status_check check ("status" in ('draft', 'open', 'closed')),
  "opened_at" timestamptz,
  "closed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index jobs_tenant_status_idx on "better_supabase"."job_openings" ("tenant_id", "status");
alter table "better_supabase"."job_openings" enable row level security;
revoke all on "better_supabase"."job_openings" from public, anon, authenticated;
grant select on "better_supabase"."job_openings" to authenticated;
grant all on "better_supabase"."job_openings" to service_role;
create policy bsb_jobs_read on "better_supabase"."job_openings"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "better_supabase"."applications" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "job_id" uuid not null references "better_supabase"."job_openings" ("id") on delete cascade,
  "candidate_type" text not null,
  "candidate_id" text not null,
  "source" text,
  "owner_id" uuid,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  "state" text not null default 'active' constraint bsb_applications_state_check check ("state" in ('active', 'hired', 'rejected', 'withdrawn')),
  "rejection_reason" text,
  "hired_at" timestamptz,
  "rank" text collate "C" not null default 'V',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("job_id", "candidate_type", "candidate_id")
);
create index applications_board_idx on "better_supabase"."applications" ("pipeline_id", "stage_id", "rank");
create index applications_candidate_idx on "better_supabase"."applications" ("candidate_type", "candidate_id");
alter table "better_supabase"."applications" enable row level security;
revoke all on "better_supabase"."applications" from public, anon, authenticated;
grant select on "better_supabase"."applications" to authenticated;
grant all on "better_supabase"."applications" to service_role;
create policy bsb_applications_read on "better_supabase"."applications"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "better_supabase"."application_scorecards" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "application_id" uuid not null references "better_supabase"."applications" ("id") on delete cascade,
  "stage_id" uuid,
  "reviewer_id" uuid not null,
  "rating" smallint not null constraint bsb_application_scorecards_rating_check check ("rating" >= 1 and "rating" <= 4),
  "recommendation" text not null constraint bsb_application_scorecards_recommendation_check check ("recommendation" in ('strong_no', 'no', 'yes', 'strong_yes')),
  "notes" text,
  "submitted_at" timestamptz not null default now(),
  unique nulls not distinct ("application_id", "stage_id", "reviewer_id")
);
create index application_scorecards_reviewer_idx on "better_supabase"."application_scorecards" ("reviewer_id");
alter table "better_supabase"."application_scorecards" enable row level security;
revoke all on "better_supabase"."application_scorecards" from public, anon, authenticated;
grant select on "better_supabase"."application_scorecards" to authenticated;
grant all on "better_supabase"."application_scorecards" to service_role;
create policy bsb_application_scorecards_read on "better_supabase"."application_scorecards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "better_supabase"."interviews" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "application_id" uuid not null references "better_supabase"."applications" ("id") on delete cascade,
  "kind" text,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "location" text,
  "interviewer_user_ids" uuid[] not null default '{}',
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  constraint bsb_interviews_check check ("ends_at" > "starts_at")
);
create index interviews_application_idx on "better_supabase"."interviews" ("application_id", "starts_at");
alter table "better_supabase"."interviews" enable row level security;
revoke all on "better_supabase"."interviews" from public, anon, authenticated;
grant select on "better_supabase"."interviews" to authenticated;
grant all on "better_supabase"."interviews" to service_role;
create policy bsb_interviews_read on "better_supabase"."interviews"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')) or (select auth.uid()) = any ("interviewer_user_ids"));

-- A rejected, withdrawn or hired application records its event and its
-- time; reopening clears them.
create or replace function better_supabase.bsb_application_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."state" is not distinct from old."state" then
    new."updated_at" := now();
    return new;
  end if;
  new."hired_at" := case when new."state" = 'hired' then now() end;
  if new."state" <> 'rejected' then
    new."rejection_reason" := null;
  end if;
  case new."state"
    when 'hired' then perform "better_supabase".emit_event('application.hired', jsonb_build_object('organizationId', new."tenant_id", 'applicationId', new."id", 'subjectType', 'application', 'subjectId', new."id"::text, 'jobId', new."job_id", 'candidateType', new."candidate_type", 'candidateId', new."candidate_id"), 'applications/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/hiring');
    when 'rejected' then perform "better_supabase".emit_event('application.rejected', jsonb_build_object('organizationId', new."tenant_id", 'applicationId', new."id", 'subjectType', 'application', 'subjectId', new."id"::text, 'jobId', new."job_id", 'candidateType', new."candidate_type", 'candidateId', new."candidate_id", 'reason', new."rejection_reason"), 'applications/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/hiring');
    when 'withdrawn' then perform "better_supabase".emit_event('application.retracted', jsonb_build_object('organizationId', new."tenant_id", 'applicationId', new."id", 'subjectType', 'application', 'subjectId', new."id"::text, 'jobId', new."job_id", 'candidateType', new."candidate_type", 'candidateId', new."candidate_id"), 'applications/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/hiring');
    else null;
  end case;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_application_guard() from public, anon, authenticated;
create trigger bsb_application_guard before update of "state" on "better_supabase"."applications"
for each row execute function better_supabase.bsb_application_guard();

-- Creates or changes a job: title, teamId, location, employmentType,
-- description, hiringManagerId, fields (the extra columns by name); and
-- status draft, open or closed.
create or replace function "better_supabase"."save_job"(tenant uuid, job uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job "better_supabase"."job_openings";
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_job.tenant, 'hiring.manage'), false)) then
    raise exception 'not allowed to manage jobs' using errcode = '42501', hint = 'HIRING_FORBIDDEN';
  end if;
  if save_job.job is not null then
    select * into v_job from "better_supabase"."job_openings" x where x."id" = save_job.job and x."tenant_id" = save_job.tenant;
    if v_job."id" is null then
      raise exception 'job not found' using errcode = 'P0002', hint = 'JOB_OPENING_NOT_FOUND';
    end if;
    v_was := v_job."status";
  end if;
  begin
    if save_job.job is null then
      insert into "better_supabase"."job_openings" ("tenant_id", "title", "team_id", "location", "employment_type", "description", "hiring_manager_id", "status")
      values (save_job.tenant, save_job.attrs ->> 'title', (save_job.attrs ->> 'teamId')::uuid, save_job.attrs ->> 'location',
        save_job.attrs ->> 'employmentType', save_job.attrs ->> 'description', (save_job.attrs ->> 'hiringManagerId')::uuid,
        coalesce(save_job.attrs ->> 'status', 'draft'))
      returning * into v_job;
    else
      update "better_supabase"."job_openings" x set
        "title" = coalesce(save_job.attrs ->> 'title', x."title"),
        "team_id" = case when save_job.attrs ? 'teamId' then (save_job.attrs ->> 'teamId')::uuid else x."team_id" end,
        "location" = case when save_job.attrs ? 'location' then save_job.attrs ->> 'location' else x."location" end,
        "employment_type" = case when save_job.attrs ? 'employmentType' then save_job.attrs ->> 'employmentType' else x."employment_type" end,
        "description" = case when save_job.attrs ? 'description' then save_job.attrs ->> 'description' else x."description" end,
        "hiring_manager_id" = case when save_job.attrs ? 'hiringManagerId' then (save_job.attrs ->> 'hiringManagerId')::uuid else x."hiring_manager_id" end,
        "status" = coalesce(save_job.attrs ->> 'status', x."status"),
        "updated_at" = now()
      where x."id" = save_job.job
      returning * into v_job;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a job needs a title and a status of draft, open or closed' using errcode = '22023', hint = 'JOB_OPENING_INVALID';
  end;
  if v_job."status" is distinct from v_was then
    if v_job."status" = 'open' then
      update "better_supabase"."job_openings" x set "opened_at" = coalesce(x."opened_at", now()), "closed_at" = null where x."id" = v_job."id" returning * into v_job;
      perform "better_supabase".emit_event('job_opening.opened', jsonb_build_object('organizationId', v_job."tenant_id", 'jobId', v_job."id", 'title', v_job."title"), 'jobs/' || v_job."id"::text, (v_job."tenant_id"::text)::text, null, 'better-supabase/hiring');
    elsif v_job."status" = 'closed' then
      update "better_supabase"."job_openings" x set "closed_at" = now() where x."id" = v_job."id" returning * into v_job;
      perform "better_supabase".emit_event('job_opening.closed', jsonb_build_object('organizationId', v_job."tenant_id", 'jobId', v_job."id", 'title', v_job."title"), 'jobs/' || v_job."id"::text, (v_job."tenant_id"::text)::text, null, 'better-supabase/hiring');
    end if;
  end if;
  return to_jsonb(v_job);
end;
$$;
revoke execute on function "better_supabase"."save_job"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_job"(uuid, uuid, jsonb) to authenticated, service_role;

-- An application of a candidate (a record in config.recordTypes, a person by
-- default) to an open job. Applying again returns the same application.

create or replace function "better_supabase"."apply_to_job"(job uuid, candidate jsonb, source text, owner uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job "better_supabase"."job_openings";
  v_row "better_supabase"."applications";
  v_type text := coalesce(apply_to_job.candidate ->> 'type', 'person');
  v_id text := apply_to_job.candidate ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_job from "better_supabase"."job_openings" x where x."id" = apply_to_job.job;
  if v_job."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_job."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such job you can add applications to' using errcode = 'P0002', hint = 'JOB_OPENING_NOT_FOUND';
  end if;
  if v_job."status" <> 'open' then
    raise exception 'the job isn''t open' using errcode = '55000', hint = 'JOB_OPENING_NOT_OPEN';
  end if;
  if v_id is null or not false then
    raise exception 'the candidate is unknown or not readable in this organization' using errcode = '42501', hint = 'HIRING_CANDIDATE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."applications" x
  where x."job_id" = v_job."id" and x."candidate_type" = v_type and x."candidate_id" = v_id;
  if v_row."id" is not null then
    return to_jsonb(v_row);
  end if;
  insert into "better_supabase"."applications" ("tenant_id", "job_id", "candidate_type", "candidate_id", "source", "owner_id")
  values (v_job."tenant_id", v_job."id", v_type, v_id, nullif(trim(apply_to_job.source), ''), coalesce(apply_to_job.owner, auth.uid()))
  returning * into v_row;
  perform "better_supabase".emit_event('application.created', jsonb_build_object('organizationId', v_row."tenant_id", 'applicationId', v_row."id", 'subjectType', 'application', 'subjectId', v_row."id"::text, 'jobId', v_row."job_id", 'candidateType', v_row."candidate_type", 'candidateId', v_row."candidate_id"), 'applications/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/hiring');
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."apply_to_job"(uuid, jsonb, text, uuid) from public, anon;
grant execute on function "better_supabase"."apply_to_job"(uuid, jsonb, text, uuid) to authenticated, service_role;

-- Ends an application: hired, rejected (with a reason) or withdrawn. It
-- moves to the job pipeline's first stage of that category.
create or replace function "better_supabase"."close_application"(application uuid, outcome text, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = close_application.application;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such application you can change' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  if close_application.outcome not in ('hired', 'rejected', 'withdrawn') then
    raise exception 'close as hired, rejected or withdrawn' using errcode = '22023', hint = 'HIRING_OUTCOME_INVALID';
  end if;
  if close_application.outcome = 'hired' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_application_hire"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."applications" x set "rejection_reason" = nullif(trim(close_application.reason), '') where x."id" = v_row."id";
  case close_application.outcome
    when 'hired' then 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'success' and x."category" = 'hired'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
    when 'rejected' then 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'failure' and x."category" = 'rejected'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
    else 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'failure' and x."category" = 'withdrawn'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
  end case;
  if close_application.outcome = 'hired' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_application_hire"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (select to_jsonb(x) from "better_supabase"."applications" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."close_application"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."close_application"(uuid, text, text) to authenticated, service_role;

-- The caller's scorecard on an application at its current stage: a rating
-- from 1 to 4 and a recommendation. Submitting again replaces it.
create or replace function "better_supabase"."submit_scorecard"(application uuid, rating integer, recommendation text, notes text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_card "better_supabase"."application_scorecards";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = submit_scorecard.application;
  if v_row."id" is null or not (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) or exists (
    select 1 from "better_supabase"."interviews" y where y."application_id" = v_row."id" and auth.uid() = any (y."interviewer_user_ids"))) then
    raise exception 'no such application you can review' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  begin
    insert into "better_supabase"."application_scorecards" ("tenant_id", "application_id", "stage_id", "reviewer_id", "rating", "recommendation", "notes")
    values (v_row."tenant_id", v_row."id", v_row."stage_id", auth.uid(), submit_scorecard.rating, submit_scorecard.recommendation, submit_scorecard.notes)
    on conflict ("application_id", "stage_id", "reviewer_id") do update set
      "rating" = excluded."rating", "recommendation" = excluded."recommendation",
      "notes" = excluded."notes", "submitted_at" = now()
    returning * into v_card;
  exception when check_violation or not_null_violation then
    raise exception 'a scorecard needs a rating and a recommendation' using errcode = '22023', hint = 'HIRING_SCORECARD_INVALID';
  end;
  perform "better_supabase".emit_event('scorecard.submitted', jsonb_build_object('organizationId', v_row."tenant_id", 'applicationId', v_row."id", 'subjectType', 'application', 'subjectId', v_row."id"::text, 'jobId', v_row."job_id", 'candidateType', v_row."candidate_type", 'candidateId', v_row."candidate_id", 'reviewerId', v_card."reviewer_id", 'recommendation', v_card."recommendation"), 'applications/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/hiring');
  return to_jsonb(v_card);
end;
$$;
revoke execute on function "better_supabase"."submit_scorecard"(uuid, integer, text, text) from public, anon;
grant execute on function "better_supabase"."submit_scorecard"(uuid, integer, text, text) to authenticated, service_role;

-- Schedules an interview; the interviewers can read it and score the
-- application.
create or replace function "better_supabase"."schedule_interview"(application uuid, starts_at timestamptz, ends_at timestamptz, interviewers uuid[], kind text, location text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_interview "better_supabase"."interviews";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = schedule_interview.application;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such application you can change' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  begin
    insert into "better_supabase"."interviews" ("tenant_id", "application_id", "kind", "starts_at", "ends_at", "location", "interviewer_user_ids", "created_by")
    values (v_row."tenant_id", v_row."id", schedule_interview.kind, schedule_interview.starts_at, schedule_interview.ends_at,
      schedule_interview.location, coalesce(schedule_interview.interviewers, '{}'), auth.uid())
    returning * into v_interview;
  exception when check_violation or not_null_violation then
    raise exception 'an interview needs a start before its end' using errcode = '22023', hint = 'HIRING_INTERVIEW_INVALID';
  end;
  perform "better_supabase".emit_event('interview.scheduled', jsonb_build_object('organizationId', v_row."tenant_id", 'applicationId', v_row."id", 'subjectType', 'application', 'subjectId', v_row."id"::text, 'jobId', v_row."job_id", 'candidateType', v_row."candidate_type", 'candidateId', v_row."candidate_id", 'interviewId', v_interview."id", 'startsAt', v_interview."starts_at"), 'applications/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/hiring');
  return to_jsonb(v_interview);
end;
$$;
revoke execute on function "better_supabase"."schedule_interview"(uuid, timestamptz, timestamptz, uuid[], text, text) from public, anon;
grant execute on function "better_supabase"."schedule_interview"(uuid, timestamptz, timestamptz, uuid[], text, text) to authenticated, service_role;

-- An application with its scorecards and interviews, and the average
-- rating and recommendations per stage.
create or replace function "better_supabase"."application_detail"(application uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object(
    'scorecards', coalesce((select jsonb_agg(to_jsonb(c) order by c."submitted_at") from "better_supabase"."application_scorecards" c where c."application_id" = x."id"), '[]'::jsonb),
    'interviews', coalesce((select jsonb_agg(to_jsonb(i) order by i."starts_at") from "better_supabase"."interviews" i where i."application_id" = x."id"), '[]'::jsonb),
    'averageRating', (select round(avg(c."rating"), 2) from "better_supabase"."application_scorecards" c where c."application_id" = x."id"))
  from "better_supabase"."applications" x where x."id" = application_detail.application
$$;
revoke execute on function "better_supabase"."application_detail"(uuid) from public, anon;
grant execute on function "better_supabase"."application_detail"(uuid) to authenticated, service_role;

-- The tenant's jobs, newest first, as the caller (the table's policy decides
-- who sees them). status keeps one status.
create or replace function "better_supabase"."list_jobs"(tenant uuid, status text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."job_openings" x
  where x."tenant_id" = list_jobs.tenant
    and (list_jobs.status is null or x."status" = list_jobs.status)
$$;
revoke execute on function "better_supabase"."list_jobs"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_jobs"(uuid, text) to authenticated, service_role;

-- A job's applications in board order, as the caller. state keeps one state.
create or replace function "better_supabase"."list_applications"(job uuid, state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."stage_id", x."rank" collate "C", x."id"), '[]'::jsonb)
  from "better_supabase"."applications" x
  where x."job_id" = list_applications.job
    and (list_applications.state is null or x."state" = list_applications.state)
$$;
revoke execute on function "better_supabase"."list_applications"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_applications"(uuid, text) to authenticated, service_role;

-- The applications of many jobs in one read, as the caller: the jobs in the
-- order given, each in board order. state keeps one state.
create or replace function "better_supabase"."list_applications_for_jobs"(jobs uuid[], state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by array_position(list_applications_for_jobs.jobs, x."job_id"), x."stage_id", x."rank" collate "C", x."id"), '[]'::jsonb)
  from "better_supabase"."applications" x
  where x."job_id" = any (list_applications_for_jobs.jobs)
    and (list_applications_for_jobs.state is null or x."state" = list_applications_for_jobs.state)
$$;
revoke execute on function "better_supabase"."list_applications_for_jobs"(uuid[], text) from public, anon;
grant execute on function "better_supabase"."list_applications_for_jobs"(uuid[], text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."job_openings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."job_openings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."job_openings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."job_openings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."applications" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."applications" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."applications" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."applications" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."application_scorecards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."application_scorecards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."application_scorecards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."application_scorecards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."interviews" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')) or (select auth.uid()) = any ("interviewer_user_ids"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."interviews" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."interviews" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."interviews" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.job_openings deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"job_opening","event_prefix":"job_opening"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.applications deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"application","event_prefix":"application"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.interviews deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"interview","event_prefix":"interview"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_091_hiring.sql
-- better-supabase module: hiring
-- @bsb-block-data hiring
-- @bsb-hash sha256:ecb394318a7f0a663d198da337981d9f1aaca2eb00a3f886abc543a6eb4ad201
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."automation_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('hiring.application_to_employee', 'hiring', 'application', 'application.hired', 'Preboard each hired candidate', 'Creates an employee in preboarding from the hired application''s candidate and job, linked created_from the application.', '[{"kind":"employees.from_application","config":{"targetType":"employee"}}]'::jsonb, true)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

insert into better_supabase.blocks (name, version, mode)
values ('hiring', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_091_hiring.sql
-- better-supabase module: hiring
-- @bsb-block hiring@2 managed
-- @bsb-hash sha256:0e905b9027c32b52914c4bd0cf3e3c49d09fcf7d50194d9bd995fe86aa4587e2
-- Jobs and applications on a pipeline per job, candidates from config.recordTypes, scorecards per stage, interviews, and hire, reject and withdraw events for the app to act on.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Hiring: jobs, applications on a pipeline per job, scorecards per stage,
-- interviews, and a hire event the app turns into an employee.

create table "app_private"."job_openings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "title" text not null constraint bsb_job_openings_title_check check (length("title") >= 1 and length("title") <= 200),
  "team_id" uuid,
  "location" text,
  "employment_type" text,
  "description" text,
  "hiring_manager_id" uuid,
  "status" text not null default 'draft' constraint bsb_job_openings_status_check check ("status" in ('draft', 'open', 'closed')),
  "opened_at" timestamptz,
  "closed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index jobs_tenant_status_idx on "app_private"."job_openings" ("tenant_id", "status");
alter table "app_private"."job_openings" enable row level security;
revoke all on "app_private"."job_openings" from public, anon, authenticated;
grant select on "app_private"."job_openings" to authenticated;
grant all on "app_private"."job_openings" to service_role;
create policy bsb_jobs_read on "app_private"."job_openings"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "app_private"."applications" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "job_id" uuid not null references "app_private"."job_openings" ("id") on delete cascade,
  "candidate_type" text not null,
  "candidate_id" text not null,
  "source" text,
  "owner_id" uuid,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  "state" text not null default 'active' constraint bsb_applications_state_check check ("state" in ('active', 'hired', 'rejected', 'withdrawn')),
  "rejection_reason" text,
  "hired_at" timestamptz,
  "rank" text collate "C" not null default 'V',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("job_id", "candidate_type", "candidate_id")
);
create index applications_board_idx on "app_private"."applications" ("pipeline_id", "stage_id", "rank");
create index applications_candidate_idx on "app_private"."applications" ("candidate_type", "candidate_id");
alter table "app_private"."applications" enable row level security;
revoke all on "app_private"."applications" from public, anon, authenticated;
grant select on "app_private"."applications" to authenticated;
grant all on "app_private"."applications" to service_role;
create policy bsb_applications_read on "app_private"."applications"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "app_private"."application_scorecards" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "application_id" uuid not null references "app_private"."applications" ("id") on delete cascade,
  "stage_id" uuid,
  "reviewer_id" uuid not null,
  "rating" smallint not null constraint bsb_application_scorecards_rating_check check ("rating" >= 1 and "rating" <= 4),
  "recommendation" text not null constraint bsb_application_scorecards_recommendation_check check ("recommendation" in ('strong_no', 'no', 'yes', 'strong_yes')),
  "notes" text,
  "submitted_at" timestamptz not null default now(),
  unique nulls not distinct ("application_id", "stage_id", "reviewer_id")
);
create index application_scorecards_reviewer_idx on "app_private"."application_scorecards" ("reviewer_id");
alter table "app_private"."application_scorecards" enable row level security;
revoke all on "app_private"."application_scorecards" from public, anon, authenticated;
grant select on "app_private"."application_scorecards" to authenticated;
grant all on "app_private"."application_scorecards" to service_role;
create policy bsb_application_scorecards_read on "app_private"."application_scorecards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "app_private"."interviews" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "application_id" uuid not null references "app_private"."applications" ("id") on delete cascade,
  "kind" text,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "location" text,
  "interviewer_user_ids" uuid[] not null default '{}',
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  constraint bsb_interviews_check check ("ends_at" > "starts_at")
);
create index interviews_application_idx on "app_private"."interviews" ("application_id", "starts_at");
alter table "app_private"."interviews" enable row level security;
revoke all on "app_private"."interviews" from public, anon, authenticated;
grant select on "app_private"."interviews" to authenticated;
grant all on "app_private"."interviews" to service_role;
create policy bsb_interviews_read on "app_private"."interviews"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')) or (select auth.uid()) = any ("interviewer_user_ids"));

-- A rejected, withdrawn or hired application records its event and its
-- time; reopening clears them.
create or replace function better_supabase.bsb_application_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."state" is not distinct from old."state" then
    new."updated_at" := now();
    return new;
  end if;
  new."hired_at" := case when new."state" = 'hired' then now() end;
  if new."state" <> 'rejected' then
    new."rejection_reason" := null;
  end if;
  case new."state"
    when 'hired' then null;
    when 'rejected' then null;
    when 'withdrawn' then null;
    else null;
  end case;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_application_guard() from public, anon, authenticated;
create trigger bsb_application_guard before update of "state" on "app_private"."applications"
for each row execute function better_supabase.bsb_application_guard();

-- Creates or changes a job: title, teamId, location, employmentType,
-- description, hiringManagerId, fields (the extra columns by name); and
-- status draft, open or closed.
create or replace function "app_private"."save_job"(tenant uuid, job uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job "app_private"."job_openings";
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_job.tenant, 'hiring.manage'), false)) then
    raise exception 'not allowed to manage jobs' using errcode = '42501', hint = 'HIRING_FORBIDDEN';
  end if;
  if save_job.job is not null then
    select * into v_job from "app_private"."job_openings" x where x."id" = save_job.job and x."tenant_id" = save_job.tenant;
    if v_job."id" is null then
      raise exception 'job not found' using errcode = 'P0002', hint = 'JOB_OPENING_NOT_FOUND';
    end if;
    v_was := v_job."status";
  end if;
  begin
    if save_job.job is null then
      insert into "app_private"."job_openings" ("tenant_id", "title", "team_id", "location", "employment_type", "description", "hiring_manager_id", "status")
      values (save_job.tenant, save_job.attrs ->> 'title', (save_job.attrs ->> 'teamId')::uuid, save_job.attrs ->> 'location',
        save_job.attrs ->> 'employmentType', save_job.attrs ->> 'description', (save_job.attrs ->> 'hiringManagerId')::uuid,
        coalesce(save_job.attrs ->> 'status', 'draft'))
      returning * into v_job;
    else
      update "app_private"."job_openings" x set
        "title" = coalesce(save_job.attrs ->> 'title', x."title"),
        "team_id" = case when save_job.attrs ? 'teamId' then (save_job.attrs ->> 'teamId')::uuid else x."team_id" end,
        "location" = case when save_job.attrs ? 'location' then save_job.attrs ->> 'location' else x."location" end,
        "employment_type" = case when save_job.attrs ? 'employmentType' then save_job.attrs ->> 'employmentType' else x."employment_type" end,
        "description" = case when save_job.attrs ? 'description' then save_job.attrs ->> 'description' else x."description" end,
        "hiring_manager_id" = case when save_job.attrs ? 'hiringManagerId' then (save_job.attrs ->> 'hiringManagerId')::uuid else x."hiring_manager_id" end,
        "status" = coalesce(save_job.attrs ->> 'status', x."status"),
        "updated_at" = now()
      where x."id" = save_job.job
      returning * into v_job;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a job needs a title and a status of draft, open or closed' using errcode = '22023', hint = 'JOB_OPENING_INVALID';
  end;
  if v_job."status" is distinct from v_was then
    if v_job."status" = 'open' then
      update "app_private"."job_openings" x set "opened_at" = coalesce(x."opened_at", now()), "closed_at" = null where x."id" = v_job."id" returning * into v_job;
      null;
    elsif v_job."status" = 'closed' then
      update "app_private"."job_openings" x set "closed_at" = now() where x."id" = v_job."id" returning * into v_job;
      null;
    end if;
  end if;
  return to_jsonb(v_job);
end;
$$;
revoke execute on function "app_private"."save_job"(uuid, uuid, jsonb) from public, anon;
grant execute on function "app_private"."save_job"(uuid, uuid, jsonb) to authenticated, service_role;

-- An application of a candidate (a record in config.recordTypes, a person by
-- default) to an open job. Applying again returns the same application.

create or replace function "app_private"."apply_to_job"(job uuid, candidate jsonb, source text, owner uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job "app_private"."job_openings";
  v_row "app_private"."applications";
  v_type text := coalesce(apply_to_job.candidate ->> 'type', 'person');
  v_id text := apply_to_job.candidate ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_job from "app_private"."job_openings" x where x."id" = apply_to_job.job;
  if v_job."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_job."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such job you can add applications to' using errcode = 'P0002', hint = 'JOB_OPENING_NOT_FOUND';
  end if;
  if v_job."status" <> 'open' then
    raise exception 'the job isn''t open' using errcode = '55000', hint = 'JOB_OPENING_NOT_OPEN';
  end if;
  if v_id is null or not false then
    raise exception 'the candidate is unknown or not readable in this organization' using errcode = '42501', hint = 'HIRING_CANDIDATE_FORBIDDEN';
  end if;
  select * into v_row from "app_private"."applications" x
  where x."job_id" = v_job."id" and x."candidate_type" = v_type and x."candidate_id" = v_id;
  if v_row."id" is not null then
    return to_jsonb(v_row);
  end if;
  insert into "app_private"."applications" ("tenant_id", "job_id", "candidate_type", "candidate_id", "source", "owner_id")
  values (v_job."tenant_id", v_job."id", v_type, v_id, nullif(trim(apply_to_job.source), ''), coalesce(apply_to_job.owner, auth.uid()))
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "app_private"."apply_to_job"(uuid, jsonb, text, uuid) from public, anon;
grant execute on function "app_private"."apply_to_job"(uuid, jsonb, text, uuid) to authenticated, service_role;

-- Ends an application: hired, rejected (with a reason) or withdrawn. It
-- moves to the job pipeline's first stage of that category.
create or replace function "app_private"."close_application"(application uuid, outcome text, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."applications";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."applications" x where x."id" = close_application.application;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such application you can change' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  if close_application.outcome not in ('hired', 'rejected', 'withdrawn') then
    raise exception 'close as hired, rejected or withdrawn' using errcode = '22023', hint = 'HIRING_OUTCOME_INVALID';
  end if;
  if close_application.outcome = 'hired' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_application_hire"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "app_private"."applications" x set "rejection_reason" = nullif(trim(close_application.reason), '') where x."id" = v_row."id";
  case close_application.outcome
    when 'hired' then 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'success' and x."category" = 'hired'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "app_private"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
    when 'rejected' then 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'failure' and x."category" = 'rejected'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "app_private"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
    else 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'failure' and x."category" = 'withdrawn'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "app_private"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
  end case;
  if close_application.outcome = 'hired' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_application_hire"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (select to_jsonb(x) from "app_private"."applications" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "app_private"."close_application"(uuid, text, text) from public, anon;
grant execute on function "app_private"."close_application"(uuid, text, text) to authenticated, service_role;

-- The caller's scorecard on an application at its current stage: a rating
-- from 1 to 4 and a recommendation. Submitting again replaces it.
create or replace function "app_private"."submit_scorecard"(application uuid, rating integer, recommendation text, notes text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."applications";
  v_card "app_private"."application_scorecards";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."applications" x where x."id" = submit_scorecard.application;
  if v_row."id" is null or not (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) or exists (
    select 1 from "app_private"."interviews" y where y."application_id" = v_row."id" and auth.uid() = any (y."interviewer_user_ids"))) then
    raise exception 'no such application you can review' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  begin
    insert into "app_private"."application_scorecards" ("tenant_id", "application_id", "stage_id", "reviewer_id", "rating", "recommendation", "notes")
    values (v_row."tenant_id", v_row."id", v_row."stage_id", auth.uid(), submit_scorecard.rating, submit_scorecard.recommendation, submit_scorecard.notes)
    on conflict ("application_id", "stage_id", "reviewer_id") do update set
      "rating" = excluded."rating", "recommendation" = excluded."recommendation",
      "notes" = excluded."notes", "submitted_at" = now()
    returning * into v_card;
  exception when check_violation or not_null_violation then
    raise exception 'a scorecard needs a rating and a recommendation' using errcode = '22023', hint = 'HIRING_SCORECARD_INVALID';
  end;
  null;
  return to_jsonb(v_card);
end;
$$;
revoke execute on function "app_private"."submit_scorecard"(uuid, integer, text, text) from public, anon;
grant execute on function "app_private"."submit_scorecard"(uuid, integer, text, text) to authenticated, service_role;

-- Schedules an interview; the interviewers can read it and score the
-- application.
create or replace function "app_private"."schedule_interview"(application uuid, starts_at timestamptz, ends_at timestamptz, interviewers uuid[], kind text, location text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."applications";
  v_interview "app_private"."interviews";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."applications" x where x."id" = schedule_interview.application;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such application you can change' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  begin
    insert into "app_private"."interviews" ("tenant_id", "application_id", "kind", "starts_at", "ends_at", "location", "interviewer_user_ids", "created_by")
    values (v_row."tenant_id", v_row."id", schedule_interview.kind, schedule_interview.starts_at, schedule_interview.ends_at,
      schedule_interview.location, coalesce(schedule_interview.interviewers, '{}'), auth.uid())
    returning * into v_interview;
  exception when check_violation or not_null_violation then
    raise exception 'an interview needs a start before its end' using errcode = '22023', hint = 'HIRING_INTERVIEW_INVALID';
  end;
  null;
  return to_jsonb(v_interview);
end;
$$;
revoke execute on function "app_private"."schedule_interview"(uuid, timestamptz, timestamptz, uuid[], text, text) from public, anon;
grant execute on function "app_private"."schedule_interview"(uuid, timestamptz, timestamptz, uuid[], text, text) to authenticated, service_role;

-- An application with its scorecards and interviews, and the average
-- rating and recommendations per stage.
create or replace function "app_private"."application_detail"(application uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object(
    'scorecards', coalesce((select jsonb_agg(to_jsonb(c) order by c."submitted_at") from "app_private"."application_scorecards" c where c."application_id" = x."id"), '[]'::jsonb),
    'interviews', coalesce((select jsonb_agg(to_jsonb(i) order by i."starts_at") from "app_private"."interviews" i where i."application_id" = x."id"), '[]'::jsonb),
    'averageRating', (select round(avg(c."rating"), 2) from "app_private"."application_scorecards" c where c."application_id" = x."id"))
  from "app_private"."applications" x where x."id" = application_detail.application
$$;
revoke execute on function "app_private"."application_detail"(uuid) from public, anon;
grant execute on function "app_private"."application_detail"(uuid) to authenticated, service_role;

-- The tenant's jobs, newest first, as the caller (the table's policy decides
-- who sees them). status keeps one status.
create or replace function "app_private"."list_jobs"(tenant uuid, status text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at" desc, x."id"), '[]'::jsonb)
  from "app_private"."job_openings" x
  where x."tenant_id" = list_jobs.tenant
    and (list_jobs.status is null or x."status" = list_jobs.status)
$$;
revoke execute on function "app_private"."list_jobs"(uuid, text) from public, anon;
grant execute on function "app_private"."list_jobs"(uuid, text) to authenticated, service_role;

-- A job's applications in board order, as the caller. state keeps one state.
create or replace function "app_private"."list_applications"(job uuid, state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."stage_id", x."rank" collate "C", x."id"), '[]'::jsonb)
  from "app_private"."applications" x
  where x."job_id" = list_applications.job
    and (list_applications.state is null or x."state" = list_applications.state)
$$;
revoke execute on function "app_private"."list_applications"(uuid, text) from public, anon;
grant execute on function "app_private"."list_applications"(uuid, text) to authenticated, service_role;

-- The applications of many jobs in one read, as the caller: the jobs in the
-- order given, each in board order. state keeps one state.
create or replace function "app_private"."list_applications_for_jobs"(jobs uuid[], state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by array_position(list_applications_for_jobs.jobs, x."job_id"), x."stage_id", x."rank" collate "C", x."id"), '[]'::jsonb)
  from "app_private"."applications" x
  where x."job_id" = any (list_applications_for_jobs.jobs)
    and (list_applications_for_jobs.state is null or x."state" = list_applications_for_jobs.state)
$$;
revoke execute on function "app_private"."list_applications_for_jobs"(uuid[], text) from public, anon;
grant execute on function "app_private"."list_applications_for_jobs"(uuid[], text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."job_openings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."job_openings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."job_openings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."job_openings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."applications" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."applications" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."applications" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."applications" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."application_scorecards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "app_private"."application_scorecards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."application_scorecards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."application_scorecards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."interviews" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')) or (select auth.uid()) = any ("interviewer_user_ids"))
  );
create policy bsb_tenant_scope_insert on "app_private"."interviews" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."interviews" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."interviews" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_091_hiring.sql
-- better-supabase module: hiring
-- @bsb-block-data hiring
-- @bsb-hash sha256:801dba9c4c7577449f5a89527cf0b1dc34056296390ab79d15998c47b81661e1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('hiring', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_091_hiring.sql
-- better-supabase module: hiring
-- @bsb-block hiring@2 managed
-- @bsb-hash sha256:249748fe8f98a53f080d1cdfd30ac99485e37493220ecffb7c0103d4fd3652ee
-- Jobs and applications on a pipeline per job, candidates from config.recordTypes, scorecards per stage, interviews, and hire, reject and withdraw events for the app to act on.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Hiring: jobs, applications on a pipeline per job, scorecards per stage,
-- interviews, and a hire event the app turns into an employee.

create table "better_supabase"."job_openings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "title" text not null constraint bsb_job_openings_title_check check (length("title") >= 1 and length("title") <= 200),
  "team_id" uuid,
  "location" text,
  "employment_type" text,
  "description" text,
  "hiring_manager_id" uuid,
  "status" text not null default 'draft' constraint bsb_job_openings_status_check check ("status" in ('draft', 'open', 'closed')),
  "opened_at" timestamptz,
  "closed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index jobs_tenant_status_idx on "better_supabase"."job_openings" ("tenant_id", "status");
alter table "better_supabase"."job_openings" enable row level security;
revoke all on "better_supabase"."job_openings" from public, anon, authenticated;
grant select on "better_supabase"."job_openings" to authenticated;
grant all on "better_supabase"."job_openings" to service_role;
create policy bsb_jobs_read on "better_supabase"."job_openings"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "better_supabase"."applications" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "job_id" uuid not null references "better_supabase"."job_openings" ("id") on delete cascade,
  "candidate_type" text not null,
  "candidate_id" text not null,
  "source" text,
  "owner_id" uuid,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  "state" text not null default 'active' constraint bsb_applications_state_check check ("state" in ('active', 'hired', 'rejected', 'withdrawn')),
  "rejection_reason" text,
  "hired_at" timestamptz,
  "rank" text collate "C" not null default 'V',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("job_id", "candidate_type", "candidate_id")
);
create index applications_board_idx on "better_supabase"."applications" ("pipeline_id", "stage_id", "rank");
create index applications_candidate_idx on "better_supabase"."applications" ("candidate_type", "candidate_id");
alter table "better_supabase"."applications" enable row level security;
revoke all on "better_supabase"."applications" from public, anon, authenticated;
grant select on "better_supabase"."applications" to authenticated;
grant all on "better_supabase"."applications" to service_role;
create policy bsb_applications_read on "better_supabase"."applications"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "better_supabase"."application_scorecards" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "application_id" uuid not null references "better_supabase"."applications" ("id") on delete cascade,
  "stage_id" uuid,
  "reviewer_id" uuid not null,
  "rating" smallint not null constraint bsb_application_scorecards_rating_check check ("rating" >= 1 and "rating" <= 4),
  "recommendation" text not null constraint bsb_application_scorecards_recommendation_check check ("recommendation" in ('strong_no', 'no', 'yes', 'strong_yes')),
  "notes" text,
  "submitted_at" timestamptz not null default now(),
  unique nulls not distinct ("application_id", "stage_id", "reviewer_id")
);
create index application_scorecards_reviewer_idx on "better_supabase"."application_scorecards" ("reviewer_id");
alter table "better_supabase"."application_scorecards" enable row level security;
revoke all on "better_supabase"."application_scorecards" from public, anon, authenticated;
grant select on "better_supabase"."application_scorecards" to authenticated;
grant all on "better_supabase"."application_scorecards" to service_role;
create policy bsb_application_scorecards_read on "better_supabase"."application_scorecards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "better_supabase"."interviews" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "application_id" uuid not null references "better_supabase"."applications" ("id") on delete cascade,
  "kind" text,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "location" text,
  "interviewer_user_ids" uuid[] not null default '{}',
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  constraint bsb_interviews_check check ("ends_at" > "starts_at")
);
create index interviews_application_idx on "better_supabase"."interviews" ("application_id", "starts_at");
alter table "better_supabase"."interviews" enable row level security;
revoke all on "better_supabase"."interviews" from public, anon, authenticated;
grant select on "better_supabase"."interviews" to authenticated;
grant all on "better_supabase"."interviews" to service_role;
create policy bsb_interviews_read on "better_supabase"."interviews"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')) or (select auth.uid()) = any ("interviewer_user_ids"));

-- A rejected, withdrawn or hired application records its event and its
-- time; reopening clears them.
create or replace function better_supabase.bsb_application_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."state" is not distinct from old."state" then
    new."updated_at" := now();
    return new;
  end if;
  new."hired_at" := case when new."state" = 'hired' then now() end;
  if new."state" <> 'rejected' then
    new."rejection_reason" := null;
  end if;
  case new."state"
    when 'hired' then null;
    when 'rejected' then null;
    when 'withdrawn' then null;
    else null;
  end case;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_application_guard() from public, anon, authenticated;
create trigger bsb_application_guard before update of "state" on "better_supabase"."applications"
for each row execute function better_supabase.bsb_application_guard();

-- Creates or changes a job: title, teamId, location, employmentType,
-- description, hiringManagerId, fields (the extra columns by name); and
-- status draft, open or closed.
create or replace function "better_supabase"."save_job"(tenant uuid, job uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job "better_supabase"."job_openings";
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_job.tenant, 'hiring.manage'), false)) then
    raise exception 'not allowed to manage jobs' using errcode = '42501', hint = 'HIRING_FORBIDDEN';
  end if;
  if save_job.job is not null then
    select * into v_job from "better_supabase"."job_openings" x where x."id" = save_job.job and x."tenant_id" = save_job.tenant;
    if v_job."id" is null then
      raise exception 'job not found' using errcode = 'P0002', hint = 'JOB_OPENING_NOT_FOUND';
    end if;
    v_was := v_job."status";
  end if;
  begin
    if save_job.job is null then
      insert into "better_supabase"."job_openings" ("tenant_id", "title", "team_id", "location", "employment_type", "description", "hiring_manager_id", "status")
      values (save_job.tenant, save_job.attrs ->> 'title', (save_job.attrs ->> 'teamId')::uuid, save_job.attrs ->> 'location',
        save_job.attrs ->> 'employmentType', save_job.attrs ->> 'description', (save_job.attrs ->> 'hiringManagerId')::uuid,
        coalesce(save_job.attrs ->> 'status', 'draft'))
      returning * into v_job;
    else
      update "better_supabase"."job_openings" x set
        "title" = coalesce(save_job.attrs ->> 'title', x."title"),
        "team_id" = case when save_job.attrs ? 'teamId' then (save_job.attrs ->> 'teamId')::uuid else x."team_id" end,
        "location" = case when save_job.attrs ? 'location' then save_job.attrs ->> 'location' else x."location" end,
        "employment_type" = case when save_job.attrs ? 'employmentType' then save_job.attrs ->> 'employmentType' else x."employment_type" end,
        "description" = case when save_job.attrs ? 'description' then save_job.attrs ->> 'description' else x."description" end,
        "hiring_manager_id" = case when save_job.attrs ? 'hiringManagerId' then (save_job.attrs ->> 'hiringManagerId')::uuid else x."hiring_manager_id" end,
        "status" = coalesce(save_job.attrs ->> 'status', x."status"),
        "updated_at" = now()
      where x."id" = save_job.job
      returning * into v_job;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a job needs a title and a status of draft, open or closed' using errcode = '22023', hint = 'JOB_OPENING_INVALID';
  end;
  if v_job."status" is distinct from v_was then
    if v_job."status" = 'open' then
      update "better_supabase"."job_openings" x set "opened_at" = coalesce(x."opened_at", now()), "closed_at" = null where x."id" = v_job."id" returning * into v_job;
      null;
    elsif v_job."status" = 'closed' then
      update "better_supabase"."job_openings" x set "closed_at" = now() where x."id" = v_job."id" returning * into v_job;
      null;
    end if;
  end if;
  return to_jsonb(v_job);
end;
$$;
revoke execute on function "better_supabase"."save_job"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_job"(uuid, uuid, jsonb) to authenticated, service_role;

-- An application of a candidate (a record in config.recordTypes, a person by
-- default) to an open job. Applying again returns the same application.

create or replace function "better_supabase"."apply_to_job"(job uuid, candidate jsonb, source text, owner uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job "better_supabase"."job_openings";
  v_row "better_supabase"."applications";
  v_type text := coalesce(apply_to_job.candidate ->> 'type', 'person');
  v_id text := apply_to_job.candidate ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_job from "better_supabase"."job_openings" x where x."id" = apply_to_job.job;
  if v_job."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_job."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such job you can add applications to' using errcode = 'P0002', hint = 'JOB_OPENING_NOT_FOUND';
  end if;
  if v_job."status" <> 'open' then
    raise exception 'the job isn''t open' using errcode = '55000', hint = 'JOB_OPENING_NOT_OPEN';
  end if;
  if v_id is null or not false then
    raise exception 'the candidate is unknown or not readable in this organization' using errcode = '42501', hint = 'HIRING_CANDIDATE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."applications" x
  where x."job_id" = v_job."id" and x."candidate_type" = v_type and x."candidate_id" = v_id;
  if v_row."id" is not null then
    return to_jsonb(v_row);
  end if;
  insert into "better_supabase"."applications" ("tenant_id", "job_id", "candidate_type", "candidate_id", "source", "owner_id")
  values (v_job."tenant_id", v_job."id", v_type, v_id, nullif(trim(apply_to_job.source), ''), coalesce(apply_to_job.owner, auth.uid()))
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."apply_to_job"(uuid, jsonb, text, uuid) from public, anon;
grant execute on function "better_supabase"."apply_to_job"(uuid, jsonb, text, uuid) to authenticated, service_role;

-- Ends an application: hired, rejected (with a reason) or withdrawn. It
-- moves to the job pipeline's first stage of that category.
create or replace function "better_supabase"."close_application"(application uuid, outcome text, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = close_application.application;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such application you can change' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  if close_application.outcome not in ('hired', 'rejected', 'withdrawn') then
    raise exception 'close as hired, rejected or withdrawn' using errcode = '22023', hint = 'HIRING_OUTCOME_INVALID';
  end if;
  if close_application.outcome = 'hired' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_application_hire"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."applications" x set "rejection_reason" = nullif(trim(close_application.reason), '') where x."id" = v_row."id";
  case close_application.outcome
    when 'hired' then 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'success' and x."category" = 'hired'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
    when 'rejected' then 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'failure' and x."category" = 'rejected'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
    else 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'failure' and x."category" = 'withdrawn'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
  end case;
  if close_application.outcome = 'hired' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_application_hire"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (select to_jsonb(x) from "better_supabase"."applications" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."close_application"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."close_application"(uuid, text, text) to authenticated, service_role;

-- The caller's scorecard on an application at its current stage: a rating
-- from 1 to 4 and a recommendation. Submitting again replaces it.
create or replace function "better_supabase"."submit_scorecard"(application uuid, rating integer, recommendation text, notes text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_card "better_supabase"."application_scorecards";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = submit_scorecard.application;
  if v_row."id" is null or not (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) or exists (
    select 1 from "better_supabase"."interviews" y where y."application_id" = v_row."id" and auth.uid() = any (y."interviewer_user_ids"))) then
    raise exception 'no such application you can review' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  begin
    insert into "better_supabase"."application_scorecards" ("tenant_id", "application_id", "stage_id", "reviewer_id", "rating", "recommendation", "notes")
    values (v_row."tenant_id", v_row."id", v_row."stage_id", auth.uid(), submit_scorecard.rating, submit_scorecard.recommendation, submit_scorecard.notes)
    on conflict ("application_id", "stage_id", "reviewer_id") do update set
      "rating" = excluded."rating", "recommendation" = excluded."recommendation",
      "notes" = excluded."notes", "submitted_at" = now()
    returning * into v_card;
  exception when check_violation or not_null_violation then
    raise exception 'a scorecard needs a rating and a recommendation' using errcode = '22023', hint = 'HIRING_SCORECARD_INVALID';
  end;
  null;
  return to_jsonb(v_card);
end;
$$;
revoke execute on function "better_supabase"."submit_scorecard"(uuid, integer, text, text) from public, anon;
grant execute on function "better_supabase"."submit_scorecard"(uuid, integer, text, text) to authenticated, service_role;

-- Schedules an interview; the interviewers can read it and score the
-- application.
create or replace function "better_supabase"."schedule_interview"(application uuid, starts_at timestamptz, ends_at timestamptz, interviewers uuid[], kind text, location text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_interview "better_supabase"."interviews";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = schedule_interview.application;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such application you can change' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  begin
    insert into "better_supabase"."interviews" ("tenant_id", "application_id", "kind", "starts_at", "ends_at", "location", "interviewer_user_ids", "created_by")
    values (v_row."tenant_id", v_row."id", schedule_interview.kind, schedule_interview.starts_at, schedule_interview.ends_at,
      schedule_interview.location, coalesce(schedule_interview.interviewers, '{}'), auth.uid())
    returning * into v_interview;
  exception when check_violation or not_null_violation then
    raise exception 'an interview needs a start before its end' using errcode = '22023', hint = 'HIRING_INTERVIEW_INVALID';
  end;
  null;
  return to_jsonb(v_interview);
end;
$$;
revoke execute on function "better_supabase"."schedule_interview"(uuid, timestamptz, timestamptz, uuid[], text, text) from public, anon;
grant execute on function "better_supabase"."schedule_interview"(uuid, timestamptz, timestamptz, uuid[], text, text) to authenticated, service_role;

-- An application with its scorecards and interviews, and the average
-- rating and recommendations per stage.
create or replace function "better_supabase"."application_detail"(application uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object(
    'scorecards', coalesce((select jsonb_agg(to_jsonb(c) order by c."submitted_at") from "better_supabase"."application_scorecards" c where c."application_id" = x."id"), '[]'::jsonb),
    'interviews', coalesce((select jsonb_agg(to_jsonb(i) order by i."starts_at") from "better_supabase"."interviews" i where i."application_id" = x."id"), '[]'::jsonb),
    'averageRating', (select round(avg(c."rating"), 2) from "better_supabase"."application_scorecards" c where c."application_id" = x."id"))
  from "better_supabase"."applications" x where x."id" = application_detail.application
$$;
revoke execute on function "better_supabase"."application_detail"(uuid) from public, anon;
grant execute on function "better_supabase"."application_detail"(uuid) to authenticated, service_role;

-- The tenant's jobs, newest first, as the caller (the table's policy decides
-- who sees them). status keeps one status.
create or replace function "better_supabase"."list_jobs"(tenant uuid, status text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."job_openings" x
  where x."tenant_id" = list_jobs.tenant
    and (list_jobs.status is null or x."status" = list_jobs.status)
$$;
revoke execute on function "better_supabase"."list_jobs"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_jobs"(uuid, text) to authenticated, service_role;

-- A job's applications in board order, as the caller. state keeps one state.
create or replace function "better_supabase"."list_applications"(job uuid, state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."stage_id", x."rank" collate "C", x."id"), '[]'::jsonb)
  from "better_supabase"."applications" x
  where x."job_id" = list_applications.job
    and (list_applications.state is null or x."state" = list_applications.state)
$$;
revoke execute on function "better_supabase"."list_applications"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_applications"(uuid, text) to authenticated, service_role;

-- The applications of many jobs in one read, as the caller: the jobs in the
-- order given, each in board order. state keeps one state.
create or replace function "better_supabase"."list_applications_for_jobs"(jobs uuid[], state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by array_position(list_applications_for_jobs.jobs, x."job_id"), x."stage_id", x."rank" collate "C", x."id"), '[]'::jsonb)
  from "better_supabase"."applications" x
  where x."job_id" = any (list_applications_for_jobs.jobs)
    and (list_applications_for_jobs.state is null or x."state" = list_applications_for_jobs.state)
$$;
revoke execute on function "better_supabase"."list_applications_for_jobs"(uuid[], text) from public, anon;
grant execute on function "better_supabase"."list_applications_for_jobs"(uuid[], text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."job_openings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."job_openings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."job_openings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."job_openings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."applications" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."applications" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."applications" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."applications" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."application_scorecards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."application_scorecards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."application_scorecards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."application_scorecards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."interviews" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')) or (select auth.uid()) = any ("interviewer_user_ids"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."interviews" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."interviews" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."interviews" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.hiring.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."save_job"(tenant uuid, job uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_job"($1, $2, $3) $$;
revoke execute on function "api"."save_job"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_job"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."apply_to_job"(job uuid, candidate jsonb, source text, owner uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."apply_to_job"($1, $2, $3, $4) $$;
revoke execute on function "api"."apply_to_job"(uuid, jsonb, text, uuid) from public, anon;
grant execute on function "api"."apply_to_job"(uuid, jsonb, text, uuid) to authenticated, service_role;

create or replace function "api"."close_application"(application uuid, outcome text, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."close_application"($1, $2, $3) $$;
revoke execute on function "api"."close_application"(uuid, text, text) from public, anon;
grant execute on function "api"."close_application"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."submit_scorecard"(application uuid, rating integer, recommendation text, notes text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."submit_scorecard"($1, $2, $3, $4) $$;
revoke execute on function "api"."submit_scorecard"(uuid, integer, text, text) from public, anon;
grant execute on function "api"."submit_scorecard"(uuid, integer, text, text) to authenticated, service_role;

create or replace function "api"."schedule_interview"(application uuid, starts_at timestamptz, ends_at timestamptz, interviewers uuid[], kind text, location text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."schedule_interview"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."schedule_interview"(uuid, timestamptz, timestamptz, uuid[], text, text) from public, anon;
grant execute on function "api"."schedule_interview"(uuid, timestamptz, timestamptz, uuid[], text, text) to authenticated, service_role;

create or replace function "api"."application_detail"(application uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."application_detail"($1) $$;
revoke execute on function "api"."application_detail"(uuid) from public, anon;
grant execute on function "api"."application_detail"(uuid) to authenticated, service_role;

create or replace function "api"."list_jobs"(tenant uuid, status text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_jobs"($1, $2) $$;
revoke execute on function "api"."list_jobs"(uuid, text) from public, anon;
grant execute on function "api"."list_jobs"(uuid, text) to authenticated, service_role;

create or replace function "api"."list_applications"(job uuid, state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_applications"($1, $2) $$;
revoke execute on function "api"."list_applications"(uuid, text) from public, anon;
grant execute on function "api"."list_applications"(uuid, text) to authenticated, service_role;

create or replace function "api"."list_applications_for_jobs"(jobs uuid[], state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_applications_for_jobs"($1, $2) $$;
revoke execute on function "api"."list_applications_for_jobs"(uuid[], text) from public, anon;
grant execute on function "api"."list_applications_for_jobs"(uuid[], text) to authenticated, service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_091_hiring.sql
-- better-supabase module: hiring
-- @bsb-block-data hiring
-- @bsb-hash sha256:801dba9c4c7577449f5a89527cf0b1dc34056296390ab79d15998c47b81661e1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('hiring', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_091_hiring.sql
-- better-supabase module: hiring
-- @bsb-block hiring@2 managed
-- @bsb-hash sha256:617998afc801616d53dd281fc820eeff82fd59ad60e0adc40c44fe9199a01f9e
-- Jobs and applications on a pipeline per job, candidates from config.recordTypes, scorecards per stage, interviews, and hire, reject and withdraw events for the app to act on.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Hiring: jobs, applications on a pipeline per job, scorecards per stage,
-- interviews, and a hire event the app turns into an employee.

-- better_supabase.job_openings is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."job_openings" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."job_openings" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."job_openings" add column if not exists "title" text constraint bsb_job_openings_title_check check (length("title") >= 1 and length("title") <= 200);
alter table "better_supabase"."job_openings" add column if not exists "team_id" uuid;
alter table "better_supabase"."job_openings" add column if not exists "location" text;
alter table "better_supabase"."job_openings" add column if not exists "employment_type" text;
alter table "better_supabase"."job_openings" add column if not exists "description" text;
alter table "better_supabase"."job_openings" add column if not exists "hiring_manager_id" uuid;
alter table "better_supabase"."job_openings" add column if not exists "status" text not null default 'draft' constraint bsb_job_openings_status_check check ("status" in ('draft', 'open', 'closed'));
alter table "better_supabase"."job_openings" add column if not exists "opened_at" timestamptz;
alter table "better_supabase"."job_openings" add column if not exists "closed_at" timestamptz;
alter table "better_supabase"."job_openings" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."job_openings" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists jobs_tenant_status_idx on "better_supabase"."job_openings" ("tenant_id", "status");
alter table "better_supabase"."job_openings" enable row level security;
grant select on "better_supabase"."job_openings" to authenticated;
grant all on "better_supabase"."job_openings" to service_role;
create policy bsb_job_openings_select on "better_supabase"."job_openings"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

-- better_supabase.applications is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."applications" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."applications" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."applications" add column if not exists "job_id" uuid references "better_supabase"."job_openings" ("id") on delete cascade;
alter table "better_supabase"."applications" add column if not exists "candidate_type" text;
alter table "better_supabase"."applications" add column if not exists "candidate_id" text;
alter table "better_supabase"."applications" add column if not exists "source" text;
alter table "better_supabase"."applications" add column if not exists "owner_id" uuid;
alter table "better_supabase"."applications" add column if not exists "pipeline_id" uuid;
alter table "better_supabase"."applications" add column if not exists "stage_id" uuid;
alter table "better_supabase"."applications" add column if not exists "stage_entered_at" timestamptz;
alter table "better_supabase"."applications" add column if not exists "state" text not null default 'active' constraint bsb_applications_state_check check ("state" in ('active', 'hired', 'rejected', 'withdrawn'));
alter table "better_supabase"."applications" add column if not exists "rejection_reason" text;
alter table "better_supabase"."applications" add column if not exists "hired_at" timestamptz;
alter table "better_supabase"."applications" add column if not exists "rank" text collate "C" not null default 'V';
alter table "better_supabase"."applications" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."applications" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists applications_board_idx on "better_supabase"."applications" ("pipeline_id", "stage_id", "rank");
create index if not exists applications_candidate_idx on "better_supabase"."applications" ("candidate_type", "candidate_id");
alter table "better_supabase"."applications" enable row level security;
grant select on "better_supabase"."applications" to authenticated;
grant all on "better_supabase"."applications" to service_role;
create policy bsb_applications_select on "better_supabase"."applications"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

-- better_supabase.application_scorecards is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."application_scorecards" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."application_scorecards" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."application_scorecards" add column if not exists "application_id" uuid references "better_supabase"."applications" ("id") on delete cascade;
alter table "better_supabase"."application_scorecards" add column if not exists "stage_id" uuid;
alter table "better_supabase"."application_scorecards" add column if not exists "reviewer_id" uuid;
alter table "better_supabase"."application_scorecards" add column if not exists "rating" smallint constraint bsb_application_scorecards_rating_check check ("rating" >= 1 and "rating" <= 4);
alter table "better_supabase"."application_scorecards" add column if not exists "recommendation" text constraint bsb_application_scorecards_recommendation_check check ("recommendation" in ('strong_no', 'no', 'yes', 'strong_yes'));
alter table "better_supabase"."application_scorecards" add column if not exists "notes" text;
alter table "better_supabase"."application_scorecards" add column if not exists "submitted_at" timestamptz not null default now();
create unique index if not exists "application_scorecards_application_id_stage_id_reviewer_id_key" on "better_supabase"."application_scorecards" ("application_id", "stage_id", "reviewer_id") nulls not distinct;
create index if not exists application_scorecards_reviewer_idx on "better_supabase"."application_scorecards" ("reviewer_id");
alter table "better_supabase"."application_scorecards" enable row level security;
grant select on "better_supabase"."application_scorecards" to authenticated;
grant all on "better_supabase"."application_scorecards" to service_role;
create policy bsb_application_scorecards_select on "better_supabase"."application_scorecards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

-- better_supabase.interviews is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."interviews" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."interviews" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."interviews" add column if not exists "application_id" uuid references "better_supabase"."applications" ("id") on delete cascade;
alter table "better_supabase"."interviews" add column if not exists "kind" text;
alter table "better_supabase"."interviews" add column if not exists "starts_at" timestamptz;
alter table "better_supabase"."interviews" add column if not exists "ends_at" timestamptz;
alter table "better_supabase"."interviews" add column if not exists "location" text;
alter table "better_supabase"."interviews" add column if not exists "interviewer_user_ids" uuid[] not null default '{}';
alter table "better_supabase"."interviews" add column if not exists "created_by" uuid;
alter table "better_supabase"."interviews" add column if not exists "created_at" timestamptz not null default now();
create index if not exists interviews_application_idx on "better_supabase"."interviews" ("application_id", "starts_at");
alter table "better_supabase"."interviews" enable row level security;
grant select on "better_supabase"."interviews" to authenticated;
grant all on "better_supabase"."interviews" to service_role;
create policy bsb_interviews_select on "better_supabase"."interviews"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')) or (select auth.uid()) = any ("interviewer_user_ids"));

-- A rejected, withdrawn or hired application records its event and its
-- time; reopening clears them.
create or replace function better_supabase.bsb_application_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."state" is not distinct from old."state" then
    new."updated_at" := now();
    return new;
  end if;
  new."hired_at" := case when new."state" = 'hired' then now() end;
  if new."state" <> 'rejected' then
    new."rejection_reason" := null;
  end if;
  case new."state"
    when 'hired' then null;
    when 'rejected' then null;
    when 'withdrawn' then null;
    else null;
  end case;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_application_guard() from public, anon, authenticated;
create trigger bsb_application_guard before update of "state" on "better_supabase"."applications"
for each row execute function better_supabase.bsb_application_guard();

-- Creates or changes a job: title, teamId, location, employmentType,
-- description, hiringManagerId, fields (the extra columns by name); and
-- status draft, open or closed.
create or replace function "better_supabase"."save_job"(tenant uuid, job uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job "better_supabase"."job_openings";
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_job.tenant, 'hiring.manage'), false)) then
    raise exception 'not allowed to manage jobs' using errcode = '42501', hint = 'HIRING_FORBIDDEN';
  end if;
  if save_job.job is not null then
    select * into v_job from "better_supabase"."job_openings" x where x."id" = save_job.job and x."tenant_id" = save_job.tenant;
    if v_job."id" is null then
      raise exception 'job not found' using errcode = 'P0002', hint = 'JOB_OPENING_NOT_FOUND';
    end if;
    v_was := v_job."status";
  end if;
  begin
    if save_job.job is null then
      insert into "better_supabase"."job_openings" ("tenant_id", "title", "team_id", "location", "employment_type", "description", "hiring_manager_id", "status")
      values (save_job.tenant, save_job.attrs ->> 'title', (save_job.attrs ->> 'teamId')::uuid, save_job.attrs ->> 'location',
        save_job.attrs ->> 'employmentType', save_job.attrs ->> 'description', (save_job.attrs ->> 'hiringManagerId')::uuid,
        better_supabase.as_column_type(coalesce(save_job.attrs ->> 'status', 'draft'), (null::"better_supabase"."job_openings")."status"))
      returning * into v_job;
    else
      update "better_supabase"."job_openings" x set
        "title" = coalesce(save_job.attrs ->> 'title', x."title"),
        "team_id" = case when save_job.attrs ? 'teamId' then (save_job.attrs ->> 'teamId')::uuid else x."team_id" end,
        "location" = case when save_job.attrs ? 'location' then save_job.attrs ->> 'location' else x."location" end,
        "employment_type" = case when save_job.attrs ? 'employmentType' then save_job.attrs ->> 'employmentType' else x."employment_type" end,
        "description" = case when save_job.attrs ? 'description' then save_job.attrs ->> 'description' else x."description" end,
        "hiring_manager_id" = case when save_job.attrs ? 'hiringManagerId' then (save_job.attrs ->> 'hiringManagerId')::uuid else x."hiring_manager_id" end,
        "status" = coalesce(better_supabase.as_column_type(save_job.attrs ->> 'status', (null::"better_supabase"."job_openings")."status"), x."status"),
        "updated_at" = now()
      where x."id" = save_job.job
      returning * into v_job;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a job needs a title and a status of draft, open or closed' using errcode = '22023', hint = 'JOB_OPENING_INVALID';
  end;
  if v_job."status"::text is distinct from v_was then
    if v_job."status" = 'open' then
      update "better_supabase"."job_openings" x set "opened_at" = coalesce(x."opened_at", now()), "closed_at" = null where x."id" = v_job."id" returning * into v_job;
      null;
    elsif v_job."status" = 'closed' then
      update "better_supabase"."job_openings" x set "closed_at" = now() where x."id" = v_job."id" returning * into v_job;
      null;
    end if;
  end if;
  return to_jsonb(v_job);
end;
$$;
revoke execute on function "better_supabase"."save_job"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_job"(uuid, uuid, jsonb) to authenticated, service_role;

-- An application of a candidate (a record in config.recordTypes, a person by
-- default) to an open job. Applying again returns the same application.

create or replace function "better_supabase"."apply_to_job"(job uuid, candidate jsonb, source text, owner uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job "better_supabase"."job_openings";
  v_row "better_supabase"."applications";
  v_type text := coalesce(apply_to_job.candidate ->> 'type', 'person');
  v_id text := apply_to_job.candidate ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_job from "better_supabase"."job_openings" x where x."id" = apply_to_job.job;
  if v_job."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_job."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such job you can add applications to' using errcode = 'P0002', hint = 'JOB_OPENING_NOT_FOUND';
  end if;
  if v_job."status" <> 'open' then
    raise exception 'the job isn''t open' using errcode = '55000', hint = 'JOB_OPENING_NOT_OPEN';
  end if;
  if v_id is null or not false then
    raise exception 'the candidate is unknown or not readable in this organization' using errcode = '42501', hint = 'HIRING_CANDIDATE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."applications" x
  where x."job_id" = v_job."id" and x."candidate_type" = v_type and x."candidate_id" = v_id;
  if v_row."id" is not null then
    return to_jsonb(v_row);
  end if;
  insert into "better_supabase"."applications" ("tenant_id", "job_id", "candidate_type", "candidate_id", "source", "owner_id")
  values (v_job."tenant_id", v_job."id", v_type, v_id, nullif(trim(apply_to_job.source), ''), coalesce(apply_to_job.owner, auth.uid()))
  returning * into v_row;
  null;
  return to_jsonb(v_row);
end;
$$;
revoke execute on function "better_supabase"."apply_to_job"(uuid, jsonb, text, uuid) from public, anon;
grant execute on function "better_supabase"."apply_to_job"(uuid, jsonb, text, uuid) to authenticated, service_role;

-- Ends an application: hired, rejected (with a reason) or withdrawn. It
-- moves to the job pipeline's first stage of that category.
create or replace function "better_supabase"."close_application"(application uuid, outcome text, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = close_application.application;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such application you can change' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  if close_application.outcome not in ('hired', 'rejected', 'withdrawn') then
    raise exception 'close as hired, rejected or withdrawn' using errcode = '22023', hint = 'HIRING_OUTCOME_INVALID';
  end if;
  if close_application.outcome = 'hired' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_application_hire"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."applications" x set "rejection_reason" = nullif(trim(close_application.reason), '') where x."id" = v_row."id";
  case close_application.outcome
    when 'hired' then 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'success' and x."category" = 'hired'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
    when 'rejected' then 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'failure' and x."category" = 'rejected'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
    else 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'failure' and x."category" = 'withdrawn'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
  end case;
  if close_application.outcome = 'hired' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_application_hire"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (select to_jsonb(x) from "better_supabase"."applications" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."close_application"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."close_application"(uuid, text, text) to authenticated, service_role;

-- The caller's scorecard on an application at its current stage: a rating
-- from 1 to 4 and a recommendation. Submitting again replaces it.
create or replace function "better_supabase"."submit_scorecard"(application uuid, rating integer, recommendation text, notes text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_card "better_supabase"."application_scorecards";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = submit_scorecard.application;
  if v_row."id" is null or not (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) or exists (
    select 1 from "better_supabase"."interviews" y where y."application_id" = v_row."id" and auth.uid() = any (y."interviewer_user_ids"))) then
    raise exception 'no such application you can review' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  if submit_scorecard.rating is null or submit_scorecard.rating not between 1 and 4
    or submit_scorecard.recommendation is null or submit_scorecard.recommendation not in ('strong_no', 'no', 'yes', 'strong_yes') then
    raise exception 'a scorecard needs a rating and a recommendation' using errcode = '22023', hint = 'HIRING_SCORECARD_INVALID';
  end if;
  begin
    insert into "better_supabase"."application_scorecards" ("tenant_id", "application_id", "stage_id", "reviewer_id", "rating", "recommendation", "notes")
    values (v_row."tenant_id", v_row."id", v_row."stage_id", auth.uid(), submit_scorecard.rating, better_supabase.as_column_type(submit_scorecard.recommendation, (null::"better_supabase"."application_scorecards")."recommendation"), submit_scorecard.notes)
    on conflict ("application_id", "stage_id", "reviewer_id") do update set
      "rating" = excluded."rating", "recommendation" = excluded."recommendation",
      "notes" = excluded."notes", "submitted_at" = now()
    returning * into v_card;
  exception when check_violation or not_null_violation then
    raise exception 'a scorecard needs a rating and a recommendation' using errcode = '22023', hint = 'HIRING_SCORECARD_INVALID';
  end;
  null;
  return to_jsonb(v_card);
end;
$$;
revoke execute on function "better_supabase"."submit_scorecard"(uuid, integer, text, text) from public, anon;
grant execute on function "better_supabase"."submit_scorecard"(uuid, integer, text, text) to authenticated, service_role;

-- Schedules an interview; the interviewers can read it and score the
-- application.
create or replace function "better_supabase"."schedule_interview"(application uuid, starts_at timestamptz, ends_at timestamptz, interviewers uuid[], kind text, location text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_interview "better_supabase"."interviews";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = schedule_interview.application;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.write'), false)) then
    raise exception 'no such application you can change' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  if not (schedule_interview.ends_at > schedule_interview.starts_at) then
    raise exception 'an interview needs a start before its end' using errcode = '22023', hint = 'HIRING_INTERVIEW_INVALID';
  end if;
  begin
    insert into "better_supabase"."interviews" ("tenant_id", "application_id", "kind", "starts_at", "ends_at", "location", "interviewer_user_ids", "created_by")
    values (v_row."tenant_id", v_row."id", schedule_interview.kind, schedule_interview.starts_at, schedule_interview.ends_at,
      schedule_interview.location, coalesce(schedule_interview.interviewers, '{}'), auth.uid())
    returning * into v_interview;
  exception when check_violation or not_null_violation then
    raise exception 'an interview needs a start before its end' using errcode = '22023', hint = 'HIRING_INTERVIEW_INVALID';
  end;
  null;
  return to_jsonb(v_interview);
end;
$$;
revoke execute on function "better_supabase"."schedule_interview"(uuid, timestamptz, timestamptz, uuid[], text, text) from public, anon;
grant execute on function "better_supabase"."schedule_interview"(uuid, timestamptz, timestamptz, uuid[], text, text) to authenticated, service_role;

-- An application with its scorecards and interviews, and the average
-- rating and recommendations per stage.
create or replace function "better_supabase"."application_detail"(application uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object(
    'scorecards', coalesce((select jsonb_agg(to_jsonb(c) order by c."submitted_at") from "better_supabase"."application_scorecards" c where c."application_id" = x."id"), '[]'::jsonb),
    'interviews', coalesce((select jsonb_agg(to_jsonb(i) order by i."starts_at") from "better_supabase"."interviews" i where i."application_id" = x."id"), '[]'::jsonb),
    'averageRating', (select round(avg(c."rating"), 2) from "better_supabase"."application_scorecards" c where c."application_id" = x."id"))
  from "better_supabase"."applications" x where x."id" = application_detail.application
$$;
revoke execute on function "better_supabase"."application_detail"(uuid) from public, anon;
grant execute on function "better_supabase"."application_detail"(uuid) to authenticated, service_role;

-- The tenant's jobs, newest first, as the caller (the table's policy decides
-- who sees them). status keeps one status.
create or replace function "better_supabase"."list_jobs"(tenant uuid, status text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."created_at" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."job_openings" x
  where x."tenant_id" = list_jobs.tenant
    and (list_jobs.status is null or x."status"::text = list_jobs.status)
$$;
revoke execute on function "better_supabase"."list_jobs"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_jobs"(uuid, text) to authenticated, service_role;

-- A job's applications in board order, as the caller. state keeps one state.
create or replace function "better_supabase"."list_applications"(job uuid, state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x."stage_id", x."rank" collate "C", x."id"), '[]'::jsonb)
  from "better_supabase"."applications" x
  where x."job_id" = list_applications.job
    and (list_applications.state is null or x."state"::text = list_applications.state)
$$;
revoke execute on function "better_supabase"."list_applications"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_applications"(uuid, text) to authenticated, service_role;

-- The applications of many jobs in one read, as the caller: the jobs in the
-- order given, each in board order. state keeps one state.
create or replace function "better_supabase"."list_applications_for_jobs"(jobs uuid[], state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by array_position(list_applications_for_jobs.jobs, x."job_id"), x."stage_id", x."rank" collate "C", x."id"), '[]'::jsonb)
  from "better_supabase"."applications" x
  where x."job_id" = any (list_applications_for_jobs.jobs)
    and (list_applications_for_jobs.state is null or x."state"::text = list_applications_for_jobs.state)
$$;
revoke execute on function "better_supabase"."list_applications_for_jobs"(uuid[], text) from public, anon;
grant execute on function "better_supabase"."list_applications_for_jobs"(uuid[], text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."job_openings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."job_openings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."job_openings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."job_openings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."applications" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."applications" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."applications" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."applications" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."application_scorecards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."application_scorecards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."application_scorecards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."application_scorecards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."interviews" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')) or (select auth.uid()) = any ("interviewer_user_ids"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."interviews" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."interviews" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."interviews" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_091_hiring.sql
-- better-supabase module: hiring
-- @bsb-block-data hiring
-- @bsb-hash sha256:801dba9c4c7577449f5a89527cf0b1dc34056296390ab79d15998c47b81661e1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('hiring', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_091_hiring.sql
-- better-supabase module: hiring
-- @bsb-block hiring@2 managed
-- @bsb-hash sha256:bd086eb829d45b2264fe0be69aa88a4aacaf8b1b3f9d02e92f87073ecb5c8e56
-- Jobs and applications on a pipeline per job, candidates from config.recordTypes, scorecards per stage, interviews, and hire, reject and withdraw events for the app to act on.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Hiring: jobs, applications on a pipeline per job, scorecards per stage,
-- interviews, and a hire event the app turns into an employee.

create table "better_supabase"."job_openings" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "title" text not null constraint bsb_job_openings_title_check check (length("title") >= 1 and length("title") <= 200),
  "team_id" uuid,
  "location" text,
  "employment_type" text,
  "description" text,
  "hiring_manager_id" uuid,
  "status" text not null default 'draft' constraint bsb_job_openings_status_check check ("status" in ('draft', 'open', 'closed')),
  "opened_at" timestamptz,
  "closed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index jobs_tenant_status_idx on "better_supabase"."job_openings" ("org_id", "status");
alter table "better_supabase"."job_openings" enable row level security;
revoke all on "better_supabase"."job_openings" from public, anon, authenticated;
grant select on "better_supabase"."job_openings" to authenticated;
grant all on "better_supabase"."job_openings" to service_role;
create policy bsb_jobs_read on "better_supabase"."job_openings"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "better_supabase"."applications" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "job_id" uuid not null references "better_supabase"."job_openings" ("id") on delete cascade,
  "candidate_type" text not null,
  "candidate_id" text not null,
  "source" text,
  "owner_id" uuid,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  "state" text not null default 'active' constraint bsb_applications_state_check check ("state" in ('active', 'hired', 'rejected', 'withdrawn')),
  "rejection_reason" text,
  "hired_at" timestamptz,
  "rank" text collate "C" not null default 'V',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("job_id", "candidate_type", "candidate_id")
);
create index applications_board_idx on "better_supabase"."applications" ("pipeline_id", "stage_id", "rank");
create index applications_candidate_idx on "better_supabase"."applications" ("candidate_type", "candidate_id");
alter table "better_supabase"."applications" enable row level security;
revoke all on "better_supabase"."applications" from public, anon, authenticated;
grant select on "better_supabase"."applications" to authenticated;
grant all on "better_supabase"."applications" to service_role;
create policy bsb_applications_read on "better_supabase"."applications"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "better_supabase"."application_scorecards" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "application_id" uuid not null references "better_supabase"."applications" ("id") on delete cascade,
  "stage_id" uuid,
  "reviewer_id" uuid not null,
  "rating" smallint not null constraint bsb_application_scorecards_rating_check check ("rating" >= 1 and "rating" <= 4),
  "recommendation" text not null constraint bsb_application_scorecards_recommendation_check check ("recommendation" in ('strong_no', 'no', 'yes', 'strong_yes')),
  "notes" text,
  "submitted_at" timestamptz not null default now(),
  unique nulls not distinct ("application_id", "stage_id", "reviewer_id")
);
create index application_scorecards_reviewer_idx on "better_supabase"."application_scorecards" ("reviewer_id");
alter table "better_supabase"."application_scorecards" enable row level security;
revoke all on "better_supabase"."application_scorecards" from public, anon, authenticated;
grant select on "better_supabase"."application_scorecards" to authenticated;
grant all on "better_supabase"."application_scorecards" to service_role;
create policy bsb_application_scorecards_read on "better_supabase"."application_scorecards"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table "better_supabase"."interviews" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "application_id" uuid not null references "better_supabase"."applications" ("id") on delete cascade,
  "kind" text,
  "starts_at" timestamptz not null,
  "ends_at" timestamptz not null,
  "location" text,
  "interviewer_user_ids" uuid[] not null default '{}',
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  constraint bsb_interviews_check check ("ends_at" > "starts_at")
);
create index interviews_application_idx on "better_supabase"."interviews" ("application_id", "starts_at");
alter table "better_supabase"."interviews" enable row level security;
revoke all on "better_supabase"."interviews" from public, anon, authenticated;
grant select on "better_supabase"."interviews" to authenticated;
grant all on "better_supabase"."interviews" to service_role;
create policy bsb_interviews_read on "better_supabase"."interviews"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('hiring.read')) or (select auth.uid()) = any ("interviewer_user_ids"));

-- A rejected, withdrawn or hired application records its event and its
-- time; reopening clears them.
create or replace function better_supabase.bsb_application_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."state" is not distinct from old."state" then
    new."updated_at" := now();
    return new;
  end if;
  new."hired_at" := case when new."state" = 'hired' then now() end;
  if new."state" <> 'rejected' then
    new."rejection_reason" := null;
  end if;
  case new."state"
    when 'hired' then null;
    when 'rejected' then null;
    when 'withdrawn' then null;
    else null;
  end case;
  new."updated_at" := now();
  return new;
end;
$$;
revoke execute on function better_supabase.bsb_application_guard() from public, anon, authenticated;
create trigger bsb_application_guard before update of "state" on "better_supabase"."applications"
for each row execute function better_supabase.bsb_application_guard();

-- Creates or changes a job: title, teamId, location, employmentType,
-- description, hiringManagerId, fields (the extra columns by name); and
-- status draft, open or closed.
create or replace function "better_supabase"."save_job"(tenant uuid, job uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job "better_supabase"."job_openings";
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', save_job.tenant, 'hiring.manage'), false)) then
    raise exception 'not allowed to manage jobs' using errcode = '42501', hint = 'HIRING_FORBIDDEN';
  end if;
  if save_job.job is not null then
    select * into v_job from "better_supabase"."job_openings" x where x."id" = save_job.job and x."org_id" = save_job.tenant;
    if v_job."id" is null then
      raise exception 'job not found' using errcode = 'P0002', hint = 'JOB_OPENING_NOT_FOUND';
    end if;
    v_was := v_job."status";
  end if;
  begin
    if save_job.job is null then
      insert into "better_supabase"."job_openings" ("org_id", "title", "team_id", "location", "employment_type", "description", "hiring_manager_id", "status")
      values (save_job.tenant, save_job.attrs ->> 'title', (save_job.attrs ->> 'teamId')::uuid, save_job.attrs ->> 'location',
        save_job.attrs ->> 'employmentType', save_job.attrs ->> 'description', (save_job.attrs ->> 'hiringManagerId')::uuid,
        coalesce(save_job.attrs ->> 'status', 'draft'))
      returning * into v_job;
    else
      update "better_supabase"."job_openings" x set
        "title" = coalesce(save_job.attrs ->> 'title', x."title"),
        "team_id" = case when save_job.attrs ? 'teamId' then (save_job.attrs ->> 'teamId')::uuid else x."team_id" end,
        "location" = case when save_job.attrs ? 'location' then save_job.attrs ->> 'location' else x."location" end,
        "employment_type" = case when save_job.attrs ? 'employmentType' then save_job.attrs ->> 'employmentType' else x."employment_type" end,
        "description" = case when save_job.attrs ? 'description' then save_job.attrs ->> 'description' else x."description" end,
        "hiring_manager_id" = case when save_job.attrs ? 'hiringManagerId' then (save_job.attrs ->> 'hiringManagerId')::uuid else x."hiring_manager_id" end,
        "status" = coalesce(save_job.attrs ->> 'status', x."status"),
        "updated_at" = now()
      where x."id" = save_job.job
      returning * into v_job;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a job needs a title and a status of draft, open or closed' using errcode = '22023', hint = 'JOB_OPENING_INVALID';
  end;
  if v_job."status" is distinct from v_was then
    if v_job."status" = 'open' then
      update "better_supabase"."job_openings" x set "opened_at" = coalesce(x."opened_at", now()), "closed_at" = null where x."id" = v_job."id" returning * into v_job;
      null;
    elsif v_job."status" = 'closed' then
      update "better_supabase"."job_openings" x set "closed_at" = now() where x."id" = v_job."id" returning * into v_job;
      null;
    end if;
  end if;
  return (to_jsonb(v_job) || jsonb_build_object('tenant_id', v_job."org_id"));
end;
$$;
revoke execute on function "better_supabase"."save_job"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_job"(uuid, uuid, jsonb) to authenticated, service_role;

-- An application of a candidate (a record in config.recordTypes, a person by
-- default) to an open job. Applying again returns the same application.

create or replace function "better_supabase"."apply_to_job"(job uuid, candidate jsonb, source text, owner uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job "better_supabase"."job_openings";
  v_row "better_supabase"."applications";
  v_type text := coalesce(apply_to_job.candidate ->> 'type', 'person');
  v_id text := apply_to_job.candidate ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_job from "better_supabase"."job_openings" x where x."id" = apply_to_job.job;
  if v_job."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_job."org_id", 'hiring.write'), false)) then
    raise exception 'no such job you can add applications to' using errcode = 'P0002', hint = 'JOB_OPENING_NOT_FOUND';
  end if;
  if v_job."status" <> 'open' then
    raise exception 'the job isn''t open' using errcode = '55000', hint = 'JOB_OPENING_NOT_OPEN';
  end if;
  if v_id is null or not false then
    raise exception 'the candidate is unknown or not readable in this organization' using errcode = '42501', hint = 'HIRING_CANDIDATE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."applications" x
  where x."job_id" = v_job."id" and x."candidate_type" = v_type and x."candidate_id" = v_id;
  if v_row."id" is not null then
    return (to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id"));
  end if;
  insert into "better_supabase"."applications" ("org_id", "job_id", "candidate_type", "candidate_id", "source", "owner_id")
  values (v_job."org_id", v_job."id", v_type, v_id, nullif(trim(apply_to_job.source), ''), coalesce(apply_to_job.owner, auth.uid()))
  returning * into v_row;
  null;
  return (to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id"));
end;
$$;
revoke execute on function "better_supabase"."apply_to_job"(uuid, jsonb, text, uuid) from public, anon;
grant execute on function "better_supabase"."apply_to_job"(uuid, jsonb, text, uuid) to authenticated, service_role;

-- Ends an application: hired, rejected (with a reason) or withdrawn. It
-- moves to the job pipeline's first stage of that category.
create or replace function "better_supabase"."close_application"(application uuid, outcome text, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_stage uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = close_application.application;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."org_id", 'hiring.write'), false)) then
    raise exception 'no such application you can change' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  if close_application.outcome not in ('hired', 'rejected', 'withdrawn') then
    raise exception 'close as hired, rejected or withdrawn' using errcode = '22023', hint = 'HIRING_OUTCOME_INVALID';
  end if;
  if close_application.outcome = 'hired' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_application_hire"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."applications" x set "rejection_reason" = nullif(trim(close_application.reason), '') where x."id" = v_row."id";
  case close_application.outcome
    when 'hired' then 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'success' and x."category" = 'hired'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
    when 'rejected' then 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'failure' and x."category" = 'rejected'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
    else 
  select x."id" into v_stage from "better_supabase"."pipeline_stages" x
  where x."pipeline_id" = v_row."pipeline_id" and x."archived_at" is null
    and x."outcome" = 'failure' and x."category" = 'withdrawn'
  order by x."rank" collate "C" limit 1;
  if v_stage is null then
    raise exception 'the job''s pipeline has no stage for that' using errcode = 'P0002', hint = 'HIRING_STAGE_MISSING';
  end if;
  update "better_supabase"."applications" x set "stage_id" = v_stage where x."id" = v_row."id";
  end case;
  if close_application.outcome = 'hired' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_application_hire"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (select (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) from "better_supabase"."applications" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."close_application"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."close_application"(uuid, text, text) to authenticated, service_role;

-- The caller's scorecard on an application at its current stage: a rating
-- from 1 to 4 and a recommendation. Submitting again replaces it.
create or replace function "better_supabase"."submit_scorecard"(application uuid, rating integer, recommendation text, notes text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_card "better_supabase"."application_scorecards";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = submit_scorecard.application;
  if v_row."id" is null or not (((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."org_id", 'hiring.write'), false)) or exists (
    select 1 from "better_supabase"."interviews" y where y."application_id" = v_row."id" and auth.uid() = any (y."interviewer_user_ids"))) then
    raise exception 'no such application you can review' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  begin
    insert into "better_supabase"."application_scorecards" ("org_id", "application_id", "stage_id", "reviewer_id", "rating", "recommendation", "notes")
    values (v_row."org_id", v_row."id", v_row."stage_id", auth.uid(), submit_scorecard.rating, submit_scorecard.recommendation, submit_scorecard.notes)
    on conflict ("application_id", "stage_id", "reviewer_id") do update set
      "rating" = excluded."rating", "recommendation" = excluded."recommendation",
      "notes" = excluded."notes", "submitted_at" = now()
    returning * into v_card;
  exception when check_violation or not_null_violation then
    raise exception 'a scorecard needs a rating and a recommendation' using errcode = '22023', hint = 'HIRING_SCORECARD_INVALID';
  end;
  null;
  return (to_jsonb(v_card) || jsonb_build_object('tenant_id', v_card."org_id"));
end;
$$;
revoke execute on function "better_supabase"."submit_scorecard"(uuid, integer, text, text) from public, anon;
grant execute on function "better_supabase"."submit_scorecard"(uuid, integer, text, text) to authenticated, service_role;

-- Schedules an interview; the interviewers can read it and score the
-- application.
create or replace function "better_supabase"."schedule_interview"(application uuid, starts_at timestamptz, ends_at timestamptz, interviewers uuid[], kind text, location text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."applications";
  v_interview "better_supabase"."interviews";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."applications" x where x."id" = schedule_interview.application;
  if v_row."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."org_id", 'hiring.write'), false)) then
    raise exception 'no such application you can change' using errcode = 'P0002', hint = 'HIRING_APPLICATION_NOT_FOUND';
  end if;
  begin
    insert into "better_supabase"."interviews" ("org_id", "application_id", "kind", "starts_at", "ends_at", "location", "interviewer_user_ids", "created_by")
    values (v_row."org_id", v_row."id", schedule_interview.kind, schedule_interview.starts_at, schedule_interview.ends_at,
      schedule_interview.location, coalesce(schedule_interview.interviewers, '{}'), auth.uid())
    returning * into v_interview;
  exception when check_violation or not_null_violation then
    raise exception 'an interview needs a start before its end' using errcode = '22023', hint = 'HIRING_INTERVIEW_INVALID';
  end;
  null;
  return (to_jsonb(v_interview) || jsonb_build_object('tenant_id', v_interview."org_id"));
end;
$$;
revoke execute on function "better_supabase"."schedule_interview"(uuid, timestamptz, timestamptz, uuid[], text, text) from public, anon;
grant execute on function "better_supabase"."schedule_interview"(uuid, timestamptz, timestamptz, uuid[], text, text) to authenticated, service_role;

-- An application with its scorecards and interviews, and the average
-- rating and recommendations per stage.
create or replace function "better_supabase"."application_detail"(application uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select (to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) || jsonb_build_object(
    'scorecards', coalesce((select jsonb_agg((to_jsonb(c) || jsonb_build_object('tenant_id', c."org_id")) order by c."submitted_at") from "better_supabase"."application_scorecards" c where c."application_id" = x."id"), '[]'::jsonb),
    'interviews', coalesce((select jsonb_agg((to_jsonb(i) || jsonb_build_object('tenant_id', i."org_id")) order by i."starts_at") from "better_supabase"."interviews" i where i."application_id" = x."id"), '[]'::jsonb),
    'averageRating', (select round(avg(c."rating"), 2) from "better_supabase"."application_scorecards" c where c."application_id" = x."id"))
  from "better_supabase"."applications" x where x."id" = application_detail.application
$$;
revoke execute on function "better_supabase"."application_detail"(uuid) from public, anon;
grant execute on function "better_supabase"."application_detail"(uuid) to authenticated, service_role;

-- The tenant's jobs, newest first, as the caller (the table's policy decides
-- who sees them). status keeps one status.
create or replace function "better_supabase"."list_jobs"(tenant uuid, status text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg((to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) order by x."created_at" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."job_openings" x
  where x."org_id" = list_jobs.tenant
    and (list_jobs.status is null or x."status" = list_jobs.status)
$$;
revoke execute on function "better_supabase"."list_jobs"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_jobs"(uuid, text) to authenticated, service_role;

-- A job's applications in board order, as the caller. state keeps one state.
create or replace function "better_supabase"."list_applications"(job uuid, state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg((to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) order by x."stage_id", x."rank" collate "C", x."id"), '[]'::jsonb)
  from "better_supabase"."applications" x
  where x."job_id" = list_applications.job
    and (list_applications.state is null or x."state" = list_applications.state)
$$;
revoke execute on function "better_supabase"."list_applications"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_applications"(uuid, text) to authenticated, service_role;

-- The applications of many jobs in one read, as the caller: the jobs in the
-- order given, each in board order. state keeps one state.
create or replace function "better_supabase"."list_applications_for_jobs"(jobs uuid[], state text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg((to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) order by array_position(list_applications_for_jobs.jobs, x."job_id"), x."stage_id", x."rank" collate "C", x."id"), '[]'::jsonb)
  from "better_supabase"."applications" x
  where x."job_id" = any (list_applications_for_jobs.jobs)
    and (list_applications_for_jobs.state is null or x."state" = list_applications_for_jobs.state)
$$;
revoke execute on function "better_supabase"."list_applications_for_jobs"(uuid[], text) from public, anon;
grant execute on function "better_supabase"."list_applications_for_jobs"(uuid[], text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."job_openings" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."job_openings" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."job_openings" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."job_openings" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."applications" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."applications" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."applications" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."applications" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."application_scorecards" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."application_scorecards" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."application_scorecards" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."application_scorecards" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."interviews" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('hiring.read')) or (select auth.uid()) = any ("interviewer_user_ids"))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."interviews" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."interviews" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."interviews" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_091_hiring.sql
-- better-supabase module: hiring
-- @bsb-block-data hiring
-- @bsb-hash sha256:801dba9c4c7577449f5a89527cf0b1dc34056296390ab79d15998c47b81661e1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('hiring', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
