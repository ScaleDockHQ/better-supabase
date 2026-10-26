-- better-supabase module: hiring
-- @bsb-block hiring@2 managed
-- @bsb-hash sha256:cc8832855a0b87b1db5883c1649afb096a7746ef98a82b2f84f2734022495dc9
-- Jobs and applications on a pipeline per job, candidates from config.subjects, scorecards per stage, interviews, and hire, reject and withdraw events for the app to act on.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."job_openings";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."job_openings";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."job_openings";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."job_openings";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."job_openings";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."applications";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."applications";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."applications";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."applications";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."applications";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."application_scorecards";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."application_scorecards";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."application_scorecards";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."application_scorecards";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."application_scorecards";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."interviews";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."interviews";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."interviews";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."interviews";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."interviews";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Hiring: jobs, applications on a pipeline per job, scorecards per stage,
-- interviews, and a hire event the app turns into an employee.

create table if not exists "better_supabase"."job_openings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "title" text not null check (length("title") between 1 and 200),
  "team_id" uuid,
  "location" text,
  "employment_type" text,
  "description" text,
  "hiring_manager_user_id" uuid,
  "status" text not null default 'draft' check ("status" in ('draft', 'open', 'closed')),
  "opened_at" timestamptz,
  "closed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists jobs_tenant_status_idx on "better_supabase"."job_openings" ("tenant_id", "status");
alter table "better_supabase"."job_openings" enable row level security;
revoke all on "better_supabase"."job_openings" from public, anon, authenticated;
grant select on "better_supabase"."job_openings" to authenticated;
grant all on "better_supabase"."job_openings" to service_role;
drop policy if exists jobs_read on "better_supabase"."job_openings";
create policy jobs_read on "better_supabase"."job_openings"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table if not exists "better_supabase"."applications" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "job_id" uuid not null references "better_supabase"."job_openings" ("id") on delete cascade,
  "candidate_type" text not null,
  "candidate_id" text not null,
  "source" text,
  "owner_user_id" uuid,
  "pipeline_id" uuid,
  "stage_id" uuid,
  "stage_entered_at" timestamptz,
  "state" text not null default 'active' check ("state" in ('active', 'hired', 'rejected', 'withdrawn')),
  "rejection_reason" text,
  "hired_at" timestamptz,
  "rank" text collate "C" not null default 'V',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("job_id", "candidate_type", "candidate_id")
);
create index if not exists applications_board_idx on "better_supabase"."applications" ("pipeline_id", "stage_id", "rank");
create index if not exists applications_candidate_idx on "better_supabase"."applications" ("candidate_type", "candidate_id");
alter table "better_supabase"."applications" enable row level security;
revoke all on "better_supabase"."applications" from public, anon, authenticated;
grant select on "better_supabase"."applications" to authenticated;
grant all on "better_supabase"."applications" to service_role;
drop policy if exists applications_read on "better_supabase"."applications";
create policy applications_read on "better_supabase"."applications"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table if not exists "better_supabase"."application_scorecards" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "application_id" uuid not null references "better_supabase"."applications" ("id") on delete cascade,
  "stage_id" uuid,
  "reviewer_user_id" uuid not null,
  "rating" smallint not null check ("rating" between 1 and 4),
  "recommendation" text not null check ("recommendation" in ('strong_no', 'no', 'yes', 'strong_yes')),
  "notes" text,
  "submitted_at" timestamptz not null default now(),
  unique nulls not distinct ("application_id", "stage_id", "reviewer_user_id")
);
create index if not exists application_scorecards_reviewer_idx on "better_supabase"."application_scorecards" ("reviewer_user_id");
alter table "better_supabase"."application_scorecards" enable row level security;
revoke all on "better_supabase"."application_scorecards" from public, anon, authenticated;
grant select on "better_supabase"."application_scorecards" to authenticated;
grant all on "better_supabase"."application_scorecards" to service_role;
drop policy if exists application_scorecards_read on "better_supabase"."application_scorecards";
create policy application_scorecards_read on "better_supabase"."application_scorecards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')));

create table if not exists "better_supabase"."interviews" (
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
  check ("ends_at" > "starts_at")
);
create index if not exists interviews_application_idx on "better_supabase"."interviews" ("application_id", "starts_at");
alter table "better_supabase"."interviews" enable row level security;
revoke all on "better_supabase"."interviews" from public, anon, authenticated;
grant select on "better_supabase"."interviews" to authenticated;
grant all on "better_supabase"."interviews" to service_role;
drop policy if exists interviews_read on "better_supabase"."interviews";
create policy interviews_read on "better_supabase"."interviews"
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
drop trigger if exists bsb_application_guard on "better_supabase"."applications";
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
      raise exception 'job not found' using errcode = 'P0002', hint = 'HIRING_JOB_NOT_FOUND';
    end if;
    v_was := v_job."status";
  end if;
  begin
    if save_job.job is null then
      insert into "better_supabase"."job_openings" ("tenant_id", "title", "team_id", "location", "employment_type", "description", "hiring_manager_user_id", "status")
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
        "hiring_manager_user_id" = case when save_job.attrs ? 'hiringManagerId' then (save_job.attrs ->> 'hiringManagerId')::uuid else x."hiring_manager_user_id" end,
        "status" = coalesce(save_job.attrs ->> 'status', x."status"),
        "updated_at" = now()
      where x."id" = save_job.job
      returning * into v_job;
    end if;
  exception when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'a job needs a title and a status of draft, open or closed' using errcode = '22023', hint = 'HIRING_JOB_INVALID';
  end;
  if v_job."status" is distinct from v_was then
    if v_job."status" = 'open' then
      update "better_supabase"."job_openings" x set "opened_at" = coalesce(x."opened_at", now()), "closed_at" = null where x."id" = v_job."id" returning * into v_job;
      perform "better_supabase".emit_event('job.opened', jsonb_build_object('organizationId', v_job."tenant_id", 'jobId', v_job."id", 'title', v_job."title"), 'jobs/' || v_job."id"::text, (v_job."tenant_id"::text)::text, null, 'better-supabase/hiring');
    elsif v_job."status" = 'closed' then
      update "better_supabase"."job_openings" x set "closed_at" = now() where x."id" = v_job."id" returning * into v_job;
      perform "better_supabase".emit_event('job.closed', jsonb_build_object('organizationId', v_job."tenant_id", 'jobId', v_job."id", 'title', v_job."title"), 'jobs/' || v_job."id"::text, (v_job."tenant_id"::text)::text, null, 'better-supabase/hiring');
    end if;
  end if;
  return to_jsonb(v_job);
end;
$$;
revoke execute on function "better_supabase"."save_job"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_job"(uuid, uuid, jsonb) to authenticated, service_role;

-- An application of a candidate (a record in config.subjects, a person by
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
    raise exception 'no such job you can add applications to' using errcode = 'P0002', hint = 'HIRING_JOB_NOT_FOUND';
  end if;
  if v_job."status" <> 'open' then
    raise exception 'the job isn''t open' using errcode = '55000', hint = 'HIRING_JOB_NOT_OPEN';
  end if;
  if v_id is null or not (case v_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_id)::uuid and s."tenant_id"::text = v_job."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_id)::uuid and s."organization_id"::text = v_job."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_type, v_id, 'read')) then
    raise exception 'the candidate is unknown or not readable in this organization' using errcode = '42501', hint = 'HIRING_CANDIDATE_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."applications" x
  where x."job_id" = v_job."id" and x."candidate_type" = v_type and x."candidate_id" = v_id;
  if v_row."id" is not null then
    return to_jsonb(v_row);
  end if;
  insert into "better_supabase"."applications" ("tenant_id", "job_id", "candidate_type", "candidate_id", "source", "owner_user_id")
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
    insert into "better_supabase"."application_scorecards" ("tenant_id", "application_id", "stage_id", "reviewer_user_id", "rating", "recommendation", "notes")
    values (v_row."tenant_id", v_row."id", v_row."stage_id", auth.uid(), submit_scorecard.rating, submit_scorecard.recommendation, submit_scorecard.notes)
    on conflict ("application_id", "stage_id", "reviewer_user_id") do update set
      "rating" = excluded."rating", "recommendation" = excluded."recommendation",
      "notes" = excluded."notes", "submitted_at" = now()
    returning * into v_card;
  exception when check_violation or not_null_violation then
    raise exception 'a scorecard needs a rating from 1 to 4 and a recommendation' using errcode = '22023', hint = 'HIRING_SCORECARD_INVALID';
  end;
  perform "better_supabase".emit_event('scorecard.submitted', jsonb_build_object('organizationId', v_row."tenant_id", 'applicationId', v_row."id", 'subjectType', 'application', 'subjectId', v_row."id"::text, 'jobId', v_row."job_id", 'candidateType', v_row."candidate_type", 'candidateId', v_row."candidate_id", 'reviewerId', v_card."reviewer_user_id", 'recommendation', v_card."recommendation"), 'applications/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/hiring');
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."job_openings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."job_openings";
create policy bsb_tenant_scope_select on "better_supabase"."job_openings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."job_openings";
create policy bsb_tenant_scope_insert on "better_supabase"."job_openings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."job_openings";
create policy bsb_tenant_scope_update on "better_supabase"."job_openings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."job_openings";
create policy bsb_tenant_scope_delete on "better_supabase"."job_openings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."applications";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."applications";
create policy bsb_tenant_scope_select on "better_supabase"."applications" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."applications";
create policy bsb_tenant_scope_insert on "better_supabase"."applications" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."applications";
create policy bsb_tenant_scope_update on "better_supabase"."applications" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."applications";
create policy bsb_tenant_scope_delete on "better_supabase"."applications" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."application_scorecards";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."application_scorecards";
create policy bsb_tenant_scope_select on "better_supabase"."application_scorecards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."application_scorecards";
create policy bsb_tenant_scope_insert on "better_supabase"."application_scorecards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."application_scorecards";
create policy bsb_tenant_scope_update on "better_supabase"."application_scorecards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."application_scorecards";
create policy bsb_tenant_scope_delete on "better_supabase"."application_scorecards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."interviews";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."interviews";
create policy bsb_tenant_scope_select on "better_supabase"."interviews" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('hiring.read')) or (select auth.uid()) = any ("interviewer_user_ids"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."interviews";
create policy bsb_tenant_scope_insert on "better_supabase"."interviews" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."interviews";
create policy bsb_tenant_scope_update on "better_supabase"."interviews" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."interviews";
create policy bsb_tenant_scope_delete on "better_supabase"."interviews" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.hiring.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

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
security invoker
set search_path = ''
as $$ select "better_supabase"."application_detail"($1) $$;
revoke execute on function "api"."application_detail"(uuid) from public, anon;
grant execute on function "api"."application_detail"(uuid) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
