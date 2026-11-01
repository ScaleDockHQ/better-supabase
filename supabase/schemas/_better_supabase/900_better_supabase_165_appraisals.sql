-- better-supabase module: appraisals
-- @bsb-block appraisals@1 managed
-- @bsb-hash sha256:6a35e46a0be10e8820302db721ed884c6dc2bdb5e69fd970297cf29422292dc6
-- Performance appraisals: review cycles that can follow an enrollment program and carry a rubric of weighted competencies, one appraisal per person with self, peer and manager reviews, anonymous peer reviewers, goals, calibration sessions that keep their reason, and sign-off through approvals.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."appraisal_cycles";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."appraisal_cycles";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."appraisal_cycles";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."appraisal_cycles";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."appraisal_cycles";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."appraisals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."appraisals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."appraisals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."appraisals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."appraisals";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."appraisal_reviews";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."appraisal_reviews";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."appraisal_reviews";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."appraisal_reviews";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."appraisal_reviews";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."appraisal_calibrations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."appraisal_calibrations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."appraisal_calibrations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."appraisal_calibrations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."appraisal_calibrations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."appraisal_competencies";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."appraisal_competencies";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."appraisal_competencies";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."appraisal_competencies";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."appraisal_competencies";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."appraisal_review_ratings";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."appraisal_review_ratings";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."appraisal_review_ratings";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."appraisal_review_ratings";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."appraisal_review_ratings";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."appraisal_goals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."appraisal_goals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."appraisal_goals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."appraisal_goals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."appraisal_goals";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Performance appraisals per organization: review cycles, one appraisal per
-- person with self, peer and manager reviews (rated per weighted competency
-- when the cycle has a rubric, peer reviewers hidden when it says so),
-- calibration sessions that keep their reason, and sign-off through approvals. Cycles follow an enrollment
-- program when you name one.


-- Whether the caller must not learn who wrote a review: a peer review in a
-- cycle that hides peer reviewers, unless the caller wrote it. Read policies use
-- it, so it is granted to signed-in users.
create or replace function "better_supabase"."appraisal_review_hidden"(review_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_review "better_supabase"."appraisal_reviews";
  v_row "better_supabase"."appraisals";
  v_mode text;
begin
  select * into v_review from "better_supabase"."appraisal_reviews" x where x."id" = appraisal_review_hidden.review_id;
  if not found then
    return true;
  end if;
  if v_review."kind" <> 'peer' or v_review."reviewer_id" is not distinct from auth.uid() or coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return false;
  end if;
  select * into v_row from "better_supabase"."appraisals" x where x."id" = v_review."appraisal_id";
  select x."anonymity" into v_mode from "better_supabase"."appraisal_cycles" x where x."id" = v_row."cycle_id";
  return case v_mode
    when 'none' then false
    when 'subject' then coalesce(v_row."subject_user_id" = auth.uid(), false)
    else true
  end;
end;
$$;
revoke execute on function "better_supabase"."appraisal_review_hidden"(uuid) from public, anon;
grant execute on function "better_supabase"."appraisal_review_hidden"(uuid) to authenticated, service_role;

create table if not exists "better_supabase"."appraisal_cycles" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "starts_on" date not null,
  "ends_on" date not null,
  -- The key of the enrollment program the cycle's appraisals follow, when set.
  "program" text,
  "status" text not null default 'draft' check ("status" in ('draft', 'open', 'closed')),
  -- Who learns which peer wrote a review: everyone who sees it (none), anyone
  -- but the appraised person (subject), or only the reviewer (all).
  "anonymity" text not null default 'subject' check ("anonymity" in ('none', 'subject', 'all')),
  -- Whether the appraised person reads the manager and peer reviews once the
  -- appraisal is signed off.
  "share_feedback" boolean not null default false,
  "opened_at" timestamptz,
  "closed_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  check ("ends_on" >= "starts_on")
);
create index if not exists "appraisal_cycles_tenant_idx" on "better_supabase"."appraisal_cycles" ("tenant_id", "starts_on" desc);
alter table "better_supabase"."appraisal_cycles" enable row level security;
revoke all on "better_supabase"."appraisal_cycles" from public, anon, authenticated;
grant select on "better_supabase"."appraisal_cycles" to authenticated;
grant all on "better_supabase"."appraisal_cycles" to service_role;
drop policy if exists appraisal_cycles_read on "better_supabase"."appraisal_cycles";
create policy appraisal_cycles_read on "better_supabase"."appraisal_cycles"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('appraisals.read')));

create table if not exists "better_supabase"."appraisals" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "cycle_id" uuid not null,
  "subject_user_id" uuid not null,
  "manager_id" uuid,
  "status" text not null default 'pending' check ("status" in ('pending', 'reviewed', 'calibrated', 'awaiting_signoff', 'signed_off')),
  -- The average of the submitted reviews.
  "rating" numeric(3, 2) check ("rating" is null or "rating" between 1 and 5),
  -- The rating a calibration session set, when it moved.
  "calibrated_rating" smallint check ("calibrated_rating" is null or "calibrated_rating" between 1 and 5),
  -- Calibrated competency ratings by competency key, when a session moved them.
  "calibrated_competencies" jsonb not null default '{}'::jsonb check (jsonb_typeof("calibrated_competencies") = 'object'),
  -- The approvals request that signs the appraisal off.
  "approval_id" uuid,
  "signed_off_at" timestamptz,
  "signed_off_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "id"),
  unique ("cycle_id", "subject_user_id"),
  foreign key ("tenant_id", "cycle_id") references "better_supabase"."appraisal_cycles" ("tenant_id", "id") on delete cascade,
  check (("status" = 'signed_off') = ("signed_off_at" is not null))
);
create index if not exists "appraisals_cycle_idx" on "better_supabase"."appraisals" ("tenant_id", "cycle_id", "status");
create index if not exists "appraisals_subject_idx" on "better_supabase"."appraisals" ("tenant_id", "subject_user_id");
create index if not exists "appraisals_approval_idx" on "better_supabase"."appraisals" ("approval_id") where "approval_id" is not null;
alter table "better_supabase"."appraisals" enable row level security;
revoke all on "better_supabase"."appraisals" from public, anon, authenticated;
grant select on "better_supabase"."appraisals" to authenticated;
grant all on "better_supabase"."appraisals" to service_role;
drop policy if exists appraisals_read on "better_supabase"."appraisals";
create policy appraisals_read on "better_supabase"."appraisals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('appraisals.read')));

create table if not exists "better_supabase"."appraisal_reviews" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "appraisal_id" uuid not null,
  "reviewer_id" uuid not null,
  "kind" text not null check ("kind" in ('self', 'peer', 'manager')),
  "rating" smallint check ("rating" is null or "rating" between 1 and 5),
  "comments" text check ("comments" is null or length("comments") <= 10000),
  -- The forms submission with the longer answers, when the review uses a form.
  "submission_id" uuid,
  "submitted_at" timestamptz,
  unique ("tenant_id", "id"),
  unique ("appraisal_id", "reviewer_id", "kind"),
  foreign key ("tenant_id", "appraisal_id") references "better_supabase"."appraisals" ("tenant_id", "id") on delete cascade,
  check (("submitted_at" is not null) = ("rating" is not null))
);
create index if not exists "appraisal_reviews_parent_idx" on "better_supabase"."appraisal_reviews" ("tenant_id", "appraisal_id");
create index if not exists "appraisal_reviews_reviewer_idx" on "better_supabase"."appraisal_reviews" ("tenant_id", "reviewer_id") where "submitted_at" is null;
alter table "better_supabase"."appraisal_reviews" enable row level security;
revoke all on "better_supabase"."appraisal_reviews" from public, anon, authenticated;
grant select on "better_supabase"."appraisal_reviews" to authenticated;
grant all on "better_supabase"."appraisal_reviews" to service_role;
drop policy if exists appraisal_reviews_read on "better_supabase"."appraisal_reviews";
create policy appraisal_reviews_read on "better_supabase"."appraisal_reviews"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('appraisals.read')) and not "better_supabase"."appraisal_review_hidden"("id"));

create table if not exists "better_supabase"."appraisal_calibrations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "appraisal_id" uuid not null,
  "from_rating" numeric(3, 2),
  "to_rating" smallint not null check ("to_rating" between 1 and 5),
  -- The competency ratings the session set, by competency key.
  "competency_ratings" jsonb not null default '{}'::jsonb check (jsonb_typeof("competency_ratings") = 'object'),
  "reason" text not null check (length("reason") between 1 and 2000),
  "calibrated_by" uuid,
  "calibrated_at" timestamptz not null default now(),
  foreign key ("tenant_id", "appraisal_id") references "better_supabase"."appraisals" ("tenant_id", "id") on delete cascade
);
create index if not exists "appraisal_calibrations_parent_idx" on "better_supabase"."appraisal_calibrations" ("tenant_id", "appraisal_id", "calibrated_at");
alter table "better_supabase"."appraisal_calibrations" enable row level security;
revoke all on "better_supabase"."appraisal_calibrations" from public, anon, authenticated;
grant select on "better_supabase"."appraisal_calibrations" to authenticated;
grant all on "better_supabase"."appraisal_calibrations" to service_role;
drop policy if exists appraisal_calibrations_read on "better_supabase"."appraisal_calibrations";
create policy appraisal_calibrations_read on "better_supabase"."appraisal_calibrations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('appraisals.read')));

-- The competencies of a cycle's rubric. Their weights weigh the ratings when
-- the appraisal's rating is computed, and they don't change once the cycle is
-- open.
create table if not exists "better_supabase"."appraisal_competencies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "cycle_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z][a-z0-9_]{0,62}$'),
  "name" text not null check (length("name") between 1 and 200),
  "weight" numeric(6, 2) not null default 1 check ("weight" > 0 and "weight" <= 1000),
  "position" integer not null default 0,
  unique ("tenant_id", "id"),
  unique ("cycle_id", "key"),
  foreign key ("tenant_id", "cycle_id") references "better_supabase"."appraisal_cycles" ("tenant_id", "id") on delete cascade
);
create index if not exists "appraisal_competencies_parent_idx" on "better_supabase"."appraisal_competencies" ("tenant_id", "cycle_id", "position");
alter table "better_supabase"."appraisal_competencies" enable row level security;
revoke all on "better_supabase"."appraisal_competencies" from public, anon, authenticated;
grant select on "better_supabase"."appraisal_competencies" to authenticated;
grant all on "better_supabase"."appraisal_competencies" to service_role;
drop policy if exists appraisal_competencies_read on "better_supabase"."appraisal_competencies";
create policy appraisal_competencies_read on "better_supabase"."appraisal_competencies"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('appraisals.read')));

-- One review's rating of one competency. A row is as hidden as its review.
create table if not exists "better_supabase"."appraisal_review_ratings" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "review_id" uuid not null,
  "competency_id" uuid not null,
  "rating" smallint not null check ("rating" between 1 and 5),
  "comment" text check ("comment" is null or length("comment") <= 2000),
  unique ("review_id", "competency_id"),
  foreign key ("tenant_id", "review_id") references "better_supabase"."appraisal_reviews" ("tenant_id", "id") on delete cascade,
  foreign key ("tenant_id", "competency_id") references "better_supabase"."appraisal_competencies" ("tenant_id", "id") on delete cascade
);
create index if not exists "appraisal_review_ratings_parent_idx" on "better_supabase"."appraisal_review_ratings" ("tenant_id", "review_id");
create index if not exists "appraisal_review_ratings_competency_idx" on "better_supabase"."appraisal_review_ratings" ("tenant_id", "competency_id");
alter table "better_supabase"."appraisal_review_ratings" enable row level security;
revoke all on "better_supabase"."appraisal_review_ratings" from public, anon, authenticated;
grant select on "better_supabase"."appraisal_review_ratings" to authenticated;
grant all on "better_supabase"."appraisal_review_ratings" to service_role;
drop policy if exists appraisal_review_ratings_read on "better_supabase"."appraisal_review_ratings";
create policy appraisal_review_ratings_read on "better_supabase"."appraisal_review_ratings"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('appraisals.read')) and not "better_supabase"."appraisal_review_hidden"("review_id"));

-- The goals an appraisal looks back on. goal_id points at the goals block's
-- goals or at a table of your own, so there is no foreign key.
create table if not exists "better_supabase"."appraisal_goals" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "appraisal_id" uuid not null,
  "goal_id" uuid not null,
  unique ("appraisal_id", "goal_id"),
  foreign key ("tenant_id", "appraisal_id") references "better_supabase"."appraisals" ("tenant_id", "id") on delete cascade
);
create index if not exists "appraisal_goals_parent_idx" on "better_supabase"."appraisal_goals" ("tenant_id", "appraisal_id");
alter table "better_supabase"."appraisal_goals" enable row level security;
revoke all on "better_supabase"."appraisal_goals" from public, anon, authenticated;
grant select on "better_supabase"."appraisal_goals" to authenticated;
grant all on "better_supabase"."appraisal_goals" to service_role;
drop policy if exists appraisal_goals_read on "better_supabase"."appraisal_goals";
create policy appraisal_goals_read on "better_supabase"."appraisal_goals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('appraisals.read')));


-- Marks a step of the appraisal's enrollment done when its cycle follows a
-- program that has the step. Not granted to anyone.
create or replace function "better_supabase"."appraisal_step"(appraisal_id uuid, step text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_enrollment uuid;
begin
  select x."id" into v_enrollment
  from "better_supabase"."appraisals" p join "better_supabase"."appraisal_cycles" c on c."id" = p."cycle_id"
  join "better_supabase"."enrollments" x
    on x."tenant_id" is not distinct from p."tenant_id" and x."program" = c."program"
    and x."subject_type" = 'appraisal' and x."subject_id" = p."id"::text
  where p."id" = appraisal_step.appraisal_id and x."status" = 'active'
    and appraisal_step.step = any(x."steps");
  if v_enrollment is not null then
    perform "better_supabase"."enrollment_mark"(v_enrollment, appraisal_step.step, true, auth.uid());
  end if;
end;
$$;
revoke execute on function "better_supabase"."appraisal_step"(uuid, text) from public, anon, authenticated;

-- The rating of an appraisal from its submitted reviews. A cycle with a rubric
-- weighs the average rating of each competency by the competency's weight;
-- overrides is { key: rating } and replaces a competency's average (a
-- calibration). A cycle without a rubric averages the review ratings. Not
-- granted to anyone.
create or replace function "better_supabase"."appraisal_score"(appraisal_id uuid, overrides jsonb default '{}')
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (select 1 from "better_supabase"."appraisal_competencies" w join "better_supabase"."appraisals" p on p."cycle_id" = w."cycle_id" where p."id" = appraisal_score.appraisal_id) then (
      select round(sum(w."weight" * coalesce((appraisal_score.overrides ->> w."key")::numeric, m.average))
          / sum(w."weight"), 2)
      from "better_supabase"."appraisal_competencies" w
      join "better_supabase"."appraisals" p on p."cycle_id" = w."cycle_id"
      cross join lateral (
        select avg(z."rating") as average
        from "better_supabase"."appraisal_review_ratings" z join "better_supabase"."appraisal_reviews" v on v."id" = z."review_id"
        where z."competency_id" = w."id" and v."appraisal_id" = p."id" and v."submitted_at" is not null
      ) m
      where p."id" = appraisal_score.appraisal_id
        and coalesce((appraisal_score.overrides ->> w."key")::numeric, m.average) is not null
    )
    else (
      select round(avg(v."rating"), 2) from "better_supabase"."appraisal_reviews" v
      where v."appraisal_id" = appraisal_score.appraisal_id and v."submitted_at" is not null
    )
  end
$$;
revoke execute on function "better_supabase"."appraisal_score"(uuid, jsonb) from public, anon, authenticated;

-- Replaces the competencies of a cycle with the items of a json array
-- [{ key, name, weight }]. Not granted to anyone.
create or replace function "better_supabase"."appraisal_write_competencies"(cycle_id uuid, items jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_cycle "better_supabase"."appraisal_cycles";
  v_item jsonb;
  v_position bigint;
  v_key text;
  v_name text;
  v_weight numeric;
begin
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = appraisal_write_competencies.cycle_id;
  if appraisal_write_competencies.items is null or jsonb_typeof(appraisal_write_competencies.items) = 'null' then
    return;
  end if;
  if jsonb_typeof(appraisal_write_competencies.items) <> 'array' or jsonb_array_length(appraisal_write_competencies.items) > 20 then
    raise exception 'competencies is a list of at most 20 items' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  delete from "better_supabase"."appraisal_competencies" x where x."cycle_id" = v_cycle."id";
  for v_item, v_position in
    select e, o from jsonb_array_elements(appraisal_write_competencies.items) with ordinality as t(e, o)
  loop
    begin
      v_key := trim(v_item ->> 'key');
      v_name := trim(v_item ->> 'name');
      v_weight := coalesce((v_item ->> 'weight')::numeric, 1);
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'a competency weight is a number' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end;
    if v_key is null or v_key !~ '^[a-z][a-z0-9_]{0,62}$' then
      raise exception 'a competency key is lowercase letters, digits and underscores, starting with a letter' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if coalesce(length(v_name), 0) not between 1 and 200 then
      raise exception 'a competency needs a name of 1 to 200 characters' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if v_weight <= 0 or v_weight > 1000 then
      raise exception 'a competency weight is above 0 and at most 1000' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    begin
      insert into "better_supabase"."appraisal_competencies" ("tenant_id", "cycle_id", "key", "name", "weight", "position")
      values (v_cycle."tenant_id", v_cycle."id", v_key, v_name, v_weight, v_position);
    exception when unique_violation then
      raise exception 'a competency key appears once' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."appraisal_write_competencies"(uuid, jsonb) from public, anon, authenticated;

-- Replaces the rubric of a draft cycle. competencies is [{ key, name, weight }]
-- with weights above 0 (default 1). The rubric stays fixed once the cycle is
-- open. Needs appraisals.manage.
create or replace function "better_supabase"."set_appraisal_competencies"(cycle_id uuid, competencies jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_cycle "better_supabase"."appraisal_cycles";
begin
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = set_appraisal_competencies.cycle_id for update;
  if not found then
    raise exception 'no such review cycle' using errcode = 'P0002', hint = 'APPRAISALS_CYCLE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_cycle."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_cycle."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to manage review cycles' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  if v_cycle."status" <> 'draft' then
    raise exception 'the rubric of a cycle is fixed once it is open' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if set_appraisal_competencies.competencies is null or jsonb_typeof(set_appraisal_competencies.competencies) <> 'array' then
    raise exception 'competencies is a list' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  perform "better_supabase"."appraisal_write_competencies"(v_cycle."id", set_appraisal_competencies.competencies);
  return jsonb_build_object('id', v_cycle."id", 'organizationId', v_cycle."tenant_id", 'name', v_cycle."name", 'startsOn', v_cycle."starts_on", 'endsOn', v_cycle."ends_on", 'program', v_cycle."program", 'status', v_cycle."status", 'anonymity', v_cycle."anonymity", 'shareFeedback', v_cycle."share_feedback", 'openedAt', v_cycle."opened_at", 'closedAt', v_cycle."closed_at", 'createdAt', v_cycle."created_at", 'competencies', coalesce((select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight") order by w."position") from "better_supabase"."appraisal_competencies" w where w."cycle_id" = v_cycle."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."set_appraisal_competencies"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_appraisal_competencies"(uuid, jsonb) to authenticated, service_role;

-- The appraisal as json. all_reviews false keeps only the caller's own
-- reviews, plus everyone's submitted manager and peer reviews for the appraised
-- person once a cycle that shares feedback is signed off. A peer reviewer
-- stays unset where the cycle hides peer reviewers. Not granted to anyone.
create or replace function "better_supabase"."appraisal_json"(appraisal_id uuid, all_reviews boolean)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'cycleId', x."cycle_id",
    'subjectUserId', x."subject_user_id", 'managerId', x."manager_id", 'status', x."status",
    'rating', x."rating"::text, 'calibratedRating', x."calibrated_rating", 'approvalId', x."approval_id",
    'signedOffAt', x."signed_off_at", 'signedOffBy', x."signed_off_by", 'createdAt', x."created_at",
    'rubric', coalesce((
      select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight") order by w."position")
      from "better_supabase"."appraisal_competencies" w where w."cycle_id" = x."cycle_id"
    ), '[]'::jsonb),
    'competencies', case when appraisal_json.all_reviews or (x."subject_user_id" = auth.uid() and x."status" = 'signed_off'
      and (select z."share_feedback" from "better_supabase"."appraisal_cycles" z where z."id" = x."cycle_id")) then coalesce((
      select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight",
        'average', (
          select round(avg(z."rating"), 2)::text from "better_supabase"."appraisal_review_ratings" z join "better_supabase"."appraisal_reviews" v on v."id" = z."review_id"
          where z."competency_id" = w."id" and v."appraisal_id" = x."id" and v."submitted_at" is not null
        ),
        'calibrated', x."calibrated_competencies" -> w."key") order by w."position")
      from "better_supabase"."appraisal_competencies" w where w."cycle_id" = x."cycle_id"
    ), '[]'::jsonb) else '[]'::jsonb end,
    'reviews', coalesce((
      select jsonb_agg(jsonb_build_object('id', y."id",
        'reviewerId', case when "better_supabase"."appraisal_review_hidden"(y."id") then null else y."reviewer_id" end,
        'kind', y."kind", 'rating', y."rating", 'comments', y."comments", 'submissionId', y."submission_id", 'submittedAt', y."submitted_at",
        'ratings', coalesce((
          select jsonb_agg(jsonb_build_object('competency', w."key", 'rating', z."rating", 'comment', z."comment") order by w."position")
          from "better_supabase"."appraisal_review_ratings" z join "better_supabase"."appraisal_competencies" w on w."id" = z."competency_id"
          where z."review_id" = y."id"
        ), '[]'::jsonb))
        order by y."kind", y."id")
      from "better_supabase"."appraisal_reviews" y
      where y."appraisal_id" = x."id"
        and (appraisal_json.all_reviews or y."reviewer_id" = auth.uid() or ((x."subject_user_id" = auth.uid() and x."status" = 'signed_off'
      and (select z."share_feedback" from "better_supabase"."appraisal_cycles" z where z."id" = x."cycle_id")) and y."submitted_at" is not null))
    ), '[]'::jsonb),
    'calibrations', coalesce((
      select jsonb_agg(jsonb_build_object('id', z."id", 'fromRating', z."from_rating"::text, 'toRating', z."to_rating",
        'competencyRatings', z."competency_ratings",
        'reason', z."reason", 'calibratedBy', z."calibrated_by", 'calibratedAt', z."calibrated_at")
        order by z."calibrated_at", z."id")
      from "better_supabase"."appraisal_calibrations" z where z."appraisal_id" = x."id" and appraisal_json.all_reviews
    ), '[]'::jsonb),
    'goalIds', coalesce((
      select jsonb_agg(w."goal_id" order by w."goal_id") from "better_supabase"."appraisal_goals" w where w."appraisal_id" = x."id"
    ), '[]'::jsonb))
  from "better_supabase"."appraisals" x where x."id" = appraisal_json.appraisal_id
$$;
revoke execute on function "better_supabase"."appraisal_json"(uuid, boolean) from public, anon, authenticated;

-- Creates a draft review cycle. input is { name, startsOn, endsOn, program,
-- anonymity, shareFeedback, competencies }. anonymity is none, subject (default)
-- or all and says who learns which peer wrote a review; shareFeedback lets the
-- appraised person read the manager and peer reviews once signed off;
-- competencies is the rubric [{ key, name, weight }].
-- program is the key of an enrollment program whose steps may be named
-- self_review, peer_review, manager_review, calibration and sign_off; the
-- appraisals of the cycle are enrolled in it. Needs appraisals.manage.
create or replace function "better_supabase"."create_appraisal_cycle"(tenant uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisal_cycles";
  v_name text;
  v_starts date;
  v_ends date;
  v_program text;
  v_anonymity text;
  v_share boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_appraisal_cycle.tenant is not null and coalesce(better_supabase.can('tenant', create_appraisal_cycle.tenant, 'appraisals.manage'), false))) then
    raise exception 'not allowed to manage review cycles' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  if jsonb_typeof(create_appraisal_cycle.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  begin
    v_name := trim(create_appraisal_cycle.input ->> 'name');
    v_starts := (create_appraisal_cycle.input ->> 'startsOn')::date;
    v_ends := (create_appraisal_cycle.input ->> 'endsOn')::date;
    v_program := nullif(trim(create_appraisal_cycle.input ->> 'program'), '');
    v_anonymity := coalesce(nullif(trim(create_appraisal_cycle.input ->> 'anonymity'), ''), 'subject');
    v_share := coalesce((create_appraisal_cycle.input ->> 'shareFeedback')::boolean, false);
  exception when invalid_datetime_format or datetime_field_overflow then
    raise exception 'startsOn and endsOn are dates' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  when invalid_text_representation then
    raise exception 'shareFeedback is true or false' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end;
  if v_anonymity not in ('none', 'subject', 'all') then
    raise exception 'anonymity is none, subject or all' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if coalesce(length(v_name), 0) not between 1 and 200 then
    raise exception 'a cycle needs a name of 1 to 200 characters' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if v_starts is null or v_ends is null or v_ends < v_starts then
    raise exception 'a cycle needs a start date and an end date on or after it' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "better_supabase"."enrollment_programs" x
    where x."tenant_id" = create_appraisal_cycle.tenant and x."key" = v_program
  ) then
    raise exception 'no such enrollment program' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_appraisal_cycle_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_appraisal_cycle.tenant, create_appraisal_cycle.input;
    end if;
  end;
  insert into "better_supabase"."appraisal_cycles" ("tenant_id", "name", "starts_on", "ends_on", "program", "anonymity", "share_feedback", "created_by")
  values (create_appraisal_cycle.tenant, v_name, v_starts, v_ends, v_program, v_anonymity, v_share, auth.uid())
  returning * into v_row;
  perform "better_supabase"."appraisal_write_competencies"(v_row."id", create_appraisal_cycle.input -> 'competencies');
  perform "better_supabase".emit_event('appraisal_cycle.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'status', v_row."status"), 'appraisal-cycles/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal_cycle.created',
    category => 'data',
    target_type => 'appraisal_cycle',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    summary => 'review cycle created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'name', v_row."name", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_appraisal_cycle_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'program', v_row."program", 'status', v_row."status", 'anonymity', v_row."anonymity", 'shareFeedback', v_row."share_feedback", 'openedAt', v_row."opened_at", 'closedAt', v_row."closed_at", 'createdAt', v_row."created_at", 'competencies', coalesce((select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight") order by w."position") from "better_supabase"."appraisal_competencies" w where w."cycle_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."create_appraisal_cycle"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."create_appraisal_cycle"(uuid, jsonb) to authenticated, service_role;

-- Opens a cycle and creates the appraisals it names. assignments is
-- [{ subjectUserId, managerId, peerIds: [] }]: each person gets a self review,
-- a manager review when managerId is set and one review per peer. A person who
-- already has an appraisal in the cycle keeps it. Calling it again on an open
-- cycle adds people. Needs appraisals.manage.
create or replace function "better_supabase"."open_appraisal_cycle"(cycle_id uuid, assignments jsonb default '[]')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_cycle "better_supabase"."appraisal_cycles";
  v_appraisal "better_supabase"."appraisals";
  v_item jsonb;
  v_subject uuid;
  v_manager uuid;
  v_peer text;
  v_peers uuid[];
  v_version integer;
  v_steps text[];
  v_made integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = open_appraisal_cycle.cycle_id for update;
  if not found then
    raise exception 'no such review cycle' using errcode = 'P0002', hint = 'APPRAISALS_CYCLE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_cycle."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_cycle."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to manage review cycles' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  if v_cycle."status" = 'closed' then
    raise exception 'a closed cycle can''t be opened again' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if jsonb_typeof(open_appraisal_cycle.assignments) is distinct from 'array' then
    raise exception 'assignments must be a list' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  for v_item in select e from jsonb_array_elements(open_appraisal_cycle.assignments) e loop
    begin
      v_subject := (v_item ->> 'subjectUserId')::uuid;
      v_manager := nullif(v_item ->> 'managerId', '')::uuid;
      v_peers := '{}';
      if v_item ? 'peerIds' then
        for v_peer in select p from jsonb_array_elements_text(v_item -> 'peerIds') p loop
          v_peers := v_peers || v_peer::uuid;
        end loop;
      end if;
    exception when invalid_text_representation or invalid_parameter_value or null_value_not_allowed then
      raise exception 'subjectUserId, managerId and peerIds are user ids' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end;
    if v_subject is null then
      raise exception 'an assignment needs a subjectUserId' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if v_manager = v_subject then
      raise exception 'a person can''t be their own manager' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if v_subject = any(v_peers) or v_manager = any(v_peers) then
      raise exception 'a peer is neither the person nor the manager' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    insert into "better_supabase"."appraisals" ("tenant_id", "cycle_id", "subject_user_id", "manager_id")
    values (v_cycle."tenant_id", v_cycle."id", v_subject, v_manager)
    on conflict do nothing
    returning * into v_appraisal;
    if v_appraisal."id" is not null then
      v_made := v_made + 1;
      insert into "better_supabase"."appraisal_reviews" ("tenant_id", "appraisal_id", "reviewer_id", "kind")
      values (v_appraisal."tenant_id", v_appraisal."id", v_subject, 'self');
      if v_manager is not null then
        insert into "better_supabase"."appraisal_reviews" ("tenant_id", "appraisal_id", "reviewer_id", "kind")
        values (v_appraisal."tenant_id", v_appraisal."id", v_manager, 'manager');
      end if;
      insert into "better_supabase"."appraisal_reviews" ("tenant_id", "appraisal_id", "reviewer_id", "kind")
      select distinct v_appraisal."tenant_id", v_appraisal."id", p, 'peer' from unnest(v_peers) p;
      if v_cycle."program" is not null then
        select x."version", array(select s ->> 'id' from jsonb_array_elements(x."steps") s)
        into v_version, v_steps
        from "better_supabase"."enrollment_programs" x
        where x."tenant_id" = v_cycle."tenant_id" and x."key" = v_cycle."program";
        perform "better_supabase"."enrollment_ensure"(v_cycle."tenant_id", v_cycle."program", v_version, v_steps,
          'appraisal', v_appraisal."id"::text, auth.uid());
      end if;
      perform "better_supabase".emit_event('appraisal.created', jsonb_build_object('organizationId', v_appraisal."tenant_id", 'id', v_appraisal."id", 'cycleId', v_appraisal."cycle_id", 'subjectUserId', v_appraisal."subject_user_id", 'status', v_appraisal."status"), 'appraisals/' || v_appraisal."id"::text, (v_appraisal."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal.created',
    category => 'data',
    target_type => 'appraisal',
    record_id => v_appraisal."id"::text,
    summary => 'appraisal created',
    tenant => (v_appraisal."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_appraisal."tenant_id", 'id', v_appraisal."id", 'cycleId', v_appraisal."cycle_id", 'subjectUserId', v_appraisal."subject_user_id", 'status', v_appraisal."status")
  );
    end if;
    v_appraisal := null;
  end loop;
  update "better_supabase"."appraisal_cycles" x set "status" = 'open', "opened_at" = coalesce(x."opened_at", now())
  where x."id" = v_cycle."id"
  returning * into v_cycle;
  if v_made > 0 or v_cycle."opened_at" = now() then
    perform "better_supabase".emit_event('appraisal_cycle.opened', jsonb_build_object('organizationId', v_cycle."tenant_id", 'id', v_cycle."id", 'name', v_cycle."name", 'status', v_cycle."status"), 'appraisal-cycles/' || v_cycle."id"::text, (v_cycle."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal_cycle.opened',
    category => 'data',
    target_type => 'appraisal_cycle',
    record_id => v_cycle."id"::text,
    target_label => v_cycle."name",
    summary => 'review cycle opened',
    tenant => (v_cycle."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_cycle."tenant_id", 'id', v_cycle."id", 'name', v_cycle."name", 'status', v_cycle."status")
  );
  end if;
  return jsonb_build_object('id', v_cycle."id", 'organizationId', v_cycle."tenant_id", 'name', v_cycle."name", 'startsOn', v_cycle."starts_on", 'endsOn', v_cycle."ends_on", 'program', v_cycle."program", 'status', v_cycle."status", 'anonymity', v_cycle."anonymity", 'shareFeedback', v_cycle."share_feedback", 'openedAt', v_cycle."opened_at", 'closedAt', v_cycle."closed_at", 'createdAt', v_cycle."created_at", 'competencies', coalesce((select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight") order by w."position") from "better_supabase"."appraisal_competencies" w where w."cycle_id" = v_cycle."id"), '[]'::jsonb)) || jsonb_build_object('appraisalsCreated', v_made);
end;
$$;
revoke execute on function "better_supabase"."open_appraisal_cycle"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."open_appraisal_cycle"(uuid, jsonb) to authenticated, service_role;

-- Closes a cycle once every appraisal in it is signed off. Needs
-- appraisals.manage.
create or replace function "better_supabase"."close_appraisal_cycle"(cycle_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_cycle "better_supabase"."appraisal_cycles";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = close_appraisal_cycle.cycle_id for update;
  if not found then
    raise exception 'no such review cycle' using errcode = 'P0002', hint = 'APPRAISALS_CYCLE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_cycle."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_cycle."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to manage review cycles' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  if v_cycle."status" <> 'open' then
    raise exception 'only an open cycle closes' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if exists (select 1 from "better_supabase"."appraisals" x where x."cycle_id" = v_cycle."id" and x."status" <> 'signed_off') then
    raise exception 'every appraisal in the cycle must be signed off first' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  update "better_supabase"."appraisal_cycles" x set "status" = 'closed', "closed_at" = now()
  where x."id" = v_cycle."id"
  returning * into v_cycle;
  perform "better_supabase".emit_event('appraisal_cycle.closed', jsonb_build_object('organizationId', v_cycle."tenant_id", 'id', v_cycle."id", 'name', v_cycle."name", 'status', v_cycle."status"), 'appraisal-cycles/' || v_cycle."id"::text, (v_cycle."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal_cycle.closed',
    category => 'data',
    target_type => 'appraisal_cycle',
    record_id => v_cycle."id"::text,
    target_label => v_cycle."name",
    summary => 'review cycle closed',
    tenant => (v_cycle."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_cycle."tenant_id", 'id', v_cycle."id", 'name', v_cycle."name", 'status', v_cycle."status")
  );
  return jsonb_build_object('id', v_cycle."id", 'organizationId', v_cycle."tenant_id", 'name', v_cycle."name", 'startsOn', v_cycle."starts_on", 'endsOn', v_cycle."ends_on", 'program', v_cycle."program", 'status', v_cycle."status", 'anonymity', v_cycle."anonymity", 'shareFeedback', v_cycle."share_feedback", 'openedAt', v_cycle."opened_at", 'closedAt', v_cycle."closed_at", 'createdAt', v_cycle."created_at", 'competencies', coalesce((select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight") order by w."position") from "better_supabase"."appraisal_competencies" w where w."cycle_id" = v_cycle."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."close_appraisal_cycle"(uuid) from public, anon;
grant execute on function "better_supabase"."close_appraisal_cycle"(uuid) to authenticated, service_role;

-- The cycles of an organization, newest first. Needs appraisals.read.
create or replace function "better_supabase"."list_appraisal_cycles"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_appraisal_cycles.tenant is not null and coalesce(better_supabase.can('tenant', list_appraisal_cycles.tenant, 'appraisals.read'), false))) then
    raise exception 'not allowed to read review cycles' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'name', x."name", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'program', x."program", 'status', x."status", 'anonymity', x."anonymity", 'shareFeedback', x."share_feedback", 'openedAt', x."opened_at", 'closedAt', x."closed_at", 'createdAt', x."created_at", 'competencies', coalesce((select jsonb_agg(jsonb_build_object('key', w."key", 'name', w."name", 'weight', w."weight") order by w."position") from "better_supabase"."appraisal_competencies" w where w."cycle_id" = x."id"), '[]'::jsonb)) order by x."starts_on" desc, x."id")
    from "better_supabase"."appraisal_cycles" x where x."tenant_id" = list_appraisal_cycles.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_appraisal_cycles"(uuid) from public, anon;
grant execute on function "better_supabase"."list_appraisal_cycles"(uuid) to authenticated, service_role;

-- Submits a review the caller was assigned. input is { rating: 1 to 5,
-- comments, submissionId } where submissionId is the forms submission that
-- holds the longer answers. A cycle with a rubric takes
-- ratings: [{ competency, rating, comment }] for every competency instead of
-- rating, and the review's rating is their weighted average, rounded. A
-- submitted review stays. When the last review of an appraisal arrives, the
-- appraisal is reviewed and its rating is the average, or the weighted average
-- of the competencies. Needs appraisals.review.
create or replace function "better_supabase"."submit_appraisal_review"(review_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_review "better_supabase"."appraisal_reviews";
  v_row "better_supabase"."appraisals";
  v_cycle "better_supabase"."appraisal_cycles";
  v_rating integer;
  v_comments text;
  v_submission uuid;
  v_left integer;
  v_rubric integer;
  v_item jsonb;
  v_key text;
  v_value integer;
  v_note text;
  v_comp "better_supabase"."appraisal_competencies";
  v_keys text[] := '{}';
  v_sum numeric := 0;
  v_weights numeric := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_review from "better_supabase"."appraisal_reviews" x where x."id" = submit_appraisal_review.review_id for update;
  if not found then
    raise exception 'no such review' using errcode = 'P0002', hint = 'APPRAISALS_REVIEW_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."appraisals" x where x."id" = v_review."appraisal_id" for update;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = v_row."cycle_id";
  if not coalesce((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_review."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_review."tenant_id", 'appraisals.review'), false))) and v_review."reviewer_id" = auth.uid(), false) then
    raise exception 'only the assigned reviewer submits this review' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  if v_review."submitted_at" is not null then
    raise exception 'this review is already submitted' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if v_cycle."status" <> 'open' or v_row."status" <> 'pending' then
    raise exception 'reviews are open while the cycle is open and the appraisal is pending' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if jsonb_typeof(submit_appraisal_review.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  select count(*) into v_rubric from "better_supabase"."appraisal_competencies" x where x."cycle_id" = v_cycle."id";
  begin
    v_rating := (submit_appraisal_review.input ->> 'rating')::integer;
    v_comments := nullif(trim(submit_appraisal_review.input ->> 'comments'), '');
    v_submission := nullif(submit_appraisal_review.input ->> 'submissionId', '')::uuid;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'rating is a whole number and submissionId an id' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end;
  if length(v_comments) > 10000 then
    raise exception 'comments are at most 10000 characters' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if v_rubric = 0 then
    if submit_appraisal_review.input ? 'ratings' then
      raise exception 'this cycle has no rubric; send a rating' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if v_rating is null or v_rating not between 1 and 5 then
      raise exception 'the rating is a whole number from 1 to 5' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
  else
    if submit_appraisal_review.input ? 'rating' then
      raise exception 'this cycle has a rubric; send a rating for each competency' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if jsonb_typeof(submit_appraisal_review.input -> 'ratings') is distinct from 'array' then
      raise exception 'ratings is a list of { competency, rating, comment }' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
  end if;
  update "better_supabase"."appraisal_reviews" x
  set "rating" = coalesce(v_rating, 1), "comments" = v_comments, "submission_id" = v_submission, "submitted_at" = now()
  where x."id" = v_review."id"
  returning * into v_review;
  if v_rubric > 0 then
    for v_item in select e from jsonb_array_elements(submit_appraisal_review.input -> 'ratings') e loop
      begin
        v_key := v_item ->> 'competency';
        v_value := (v_item ->> 'rating')::integer;
        v_note := nullif(trim(v_item ->> 'comment'), '');
      exception when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'a competency rating is a whole number from 1 to 5' using errcode = '22023', hint = 'APPRAISALS_INVALID';
      end;
      select * into v_comp from "better_supabase"."appraisal_competencies" x where x."cycle_id" = v_cycle."id" and x."key" = v_key;
      if not found then
        raise exception 'no such competency in this cycle''s rubric' using errcode = '22023', hint = 'APPRAISALS_INVALID';
      end if;
      if v_value is null or v_value not between 1 and 5 then
        raise exception 'a competency rating is a whole number from 1 to 5' using errcode = '22023', hint = 'APPRAISALS_INVALID';
      end if;
      if length(v_note) > 2000 then
        raise exception 'a competency comment is at most 2000 characters' using errcode = '22023', hint = 'APPRAISALS_INVALID';
      end if;
      if v_key = any(v_keys) then
        raise exception 'rate each competency once' using errcode = '22023', hint = 'APPRAISALS_INVALID';
      end if;
      v_keys := v_keys || v_key;
      v_sum := v_sum + v_comp."weight" * v_value;
      v_weights := v_weights + v_comp."weight";
      insert into "better_supabase"."appraisal_review_ratings" ("tenant_id", "review_id", "competency_id", "rating", "comment")
      values (v_review."tenant_id", v_review."id", v_comp."id", v_value, v_note);
    end loop;
    if cardinality(v_keys) <> v_rubric then
      raise exception 'rate every competency of the rubric' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    update "better_supabase"."appraisal_reviews" x
    set "rating" = round(v_sum / v_weights)::integer
    where x."id" = v_review."id"
    returning * into v_review;
  end if;
  perform "better_supabase".emit_event('appraisal_review.submitted', jsonb_build_object('organizationId', v_review."tenant_id", 'id', v_review."id", 'appraisalId', v_review."appraisal_id", 'reviewerId', case when v_review."kind" = 'peer' and (select y."anonymity" from "better_supabase"."appraisal_cycles" y join "better_supabase"."appraisals" p on p."cycle_id" = y."id" where p."id" = v_review."appraisal_id") <> 'none' then null else v_review."reviewer_id" end, 'kind', v_review."kind", 'rating', v_review."rating"), 'appraisals/' || v_review."appraisal_id"::text, (v_review."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal_review.submitted',
    category => 'data',
    target_type => 'appraisal_review',
    record_id => v_review."id"::text,
    summary => 'appraisal review submitted',
    tenant => (v_review."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_review."tenant_id", 'id', v_review."id", 'appraisalId', v_review."appraisal_id", 'reviewerId', case when v_review."kind" = 'peer' and (select y."anonymity" from "better_supabase"."appraisal_cycles" y join "better_supabase"."appraisals" p on p."cycle_id" = y."id" where p."id" = v_review."appraisal_id") <> 'none' then null else v_review."reviewer_id" end, 'kind', v_review."kind", 'rating', v_review."rating")
  );
  perform "better_supabase"."appraisal_step"(v_row."id", case v_review."kind" when 'self' then 'self_review' when 'manager' then 'manager_review' end);
  select count(*) into v_left from "better_supabase"."appraisal_reviews" x
  where x."appraisal_id" = v_row."id" and x."submitted_at" is null;
  update "better_supabase"."appraisals" x
  set "rating" = "better_supabase"."appraisal_score"(x."id", '{}'::jsonb),
    "status" = case when v_left = 0 then 'reviewed' else x."status" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  if v_review."kind" = 'peer' and not exists (
    select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = v_row."id" and z."kind" = 'peer' and z."submitted_at" is null
  ) then
    perform "better_supabase"."appraisal_step"(v_row."id", 'peer_review');
  end if;
  return "better_supabase"."appraisal_json"(v_row."id", (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.read'), false))));
end;
$$;
revoke execute on function "better_supabase"."submit_appraisal_review"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."submit_appraisal_review"(uuid, jsonb) to authenticated, service_role;

-- Moves the rating of a reviewed appraisal in a calibration session and keeps
-- the reason and the previous value. Needs appraisals.manage and an open
-- cycle.
create or replace function "better_supabase"."calibrate_appraisal"(appraisal_id uuid, rating integer, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisals";
  v_cycle "better_supabase"."appraisal_cycles";
  v_reason text := nullif(trim(calibrate_appraisal.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."appraisals" x where x."id" = calibrate_appraisal.appraisal_id for update;
  if not found then
    raise exception 'no such appraisal' using errcode = 'P0002', hint = 'APPRAISALS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to calibrate appraisals' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = v_row."cycle_id";
  if v_cycle."status" <> 'open' or v_row."status" not in ('reviewed', 'calibrated') then
    raise exception 'only a reviewed appraisal in an open cycle is calibrated' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if calibrate_appraisal.rating is null or calibrate_appraisal.rating not between 1 and 5 then
    raise exception 'the rating is a whole number from 1 to 5' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if v_reason is null or length(v_reason) > 2000 then
    raise exception 'a calibration needs a reason of up to 2000 characters' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  insert into "better_supabase"."appraisal_calibrations" ("tenant_id", "appraisal_id", "from_rating", "to_rating", "reason", "calibrated_by")
  values (v_row."tenant_id", v_row."id", coalesce(v_row."calibrated_rating"::numeric, v_row."rating"), calibrate_appraisal.rating, v_reason, auth.uid());
  update "better_supabase"."appraisals" x
  set "calibrated_rating" = calibrate_appraisal.rating, "status" = 'calibrated', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('appraisal.calibrated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."subject_user_id", 'status', v_row."status", 'rating', v_row."calibrated_rating"), 'appraisals/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal.calibrated',
    category => 'data',
    target_type => 'appraisal',
    record_id => v_row."id"::text,
    summary => 'appraisal calibrated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."subject_user_id", 'status', v_row."status", 'rating', v_row."calibrated_rating")
  );
  perform "better_supabase"."appraisal_step"(v_row."id", 'calibration');
  return "better_supabase"."appraisal_json"(v_row."id", true);
end;
$$;
revoke execute on function "better_supabase"."calibrate_appraisal"(uuid, integer, text) from public, anon;
grant execute on function "better_supabase"."calibrate_appraisal"(uuid, integer, text) to authenticated, service_role;

-- Moves the competency ratings of a reviewed appraisal in a calibration
-- session. competencies is { key: 1 to 5 } for the competencies that move; the
-- rest keep their review average. The calibrated rating becomes the weighted
-- rating of the result, and the reason and previous value stay. Needs
-- appraisals.manage, an open cycle and a cycle with a rubric.
create or replace function "better_supabase"."calibrate_appraisal_competencies"(appraisal_id uuid, competencies jsonb, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisals";
  v_cycle "better_supabase"."appraisal_cycles";
  v_reason text := nullif(trim(calibrate_appraisal_competencies.reason), '');
  v_item record;
  v_merged jsonb;
  v_rating numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."appraisals" x where x."id" = calibrate_appraisal_competencies.appraisal_id for update;
  if not found then
    raise exception 'no such appraisal' using errcode = 'P0002', hint = 'APPRAISALS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to calibrate appraisals' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = v_row."cycle_id";
  if v_cycle."status" <> 'open' or v_row."status" not in ('reviewed', 'calibrated') then
    raise exception 'only a reviewed appraisal in an open cycle is calibrated' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  if jsonb_typeof(calibrate_appraisal_competencies.competencies) is distinct from 'object'
    or calibrate_appraisal_competencies.competencies = '{}'::jsonb then
    raise exception 'competencies is an object of competency ratings' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  if v_reason is null or length(v_reason) > 2000 then
    raise exception 'a calibration needs a reason of up to 2000 characters' using errcode = '22023', hint = 'APPRAISALS_INVALID';
  end if;
  for v_item in select e.key, e.value from jsonb_each(calibrate_appraisal_competencies.competencies) e loop
    if not exists (select 1 from "better_supabase"."appraisal_competencies" w where w."cycle_id" = v_cycle."id" and w."key" = v_item.key) then
      raise exception 'no such competency in this cycle''s rubric' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
    if jsonb_typeof(v_item.value) <> 'number' or v_item.value::text !~ '^[1-5]$' then
      raise exception 'a competency rating is a whole number from 1 to 5' using errcode = '22023', hint = 'APPRAISALS_INVALID';
    end if;
  end loop;
  v_merged := v_row."calibrated_competencies" || calibrate_appraisal_competencies.competencies;
  v_rating := "better_supabase"."appraisal_score"(v_row."id", v_merged);
  insert into "better_supabase"."appraisal_calibrations" ("tenant_id", "appraisal_id", "from_rating", "to_rating", "competency_ratings", "reason", "calibrated_by")
  values (v_row."tenant_id", v_row."id", coalesce(v_row."calibrated_rating"::numeric, v_row."rating"), round(v_rating)::integer,
    calibrate_appraisal_competencies.competencies, v_reason, auth.uid());
  update "better_supabase"."appraisals" x
  set "calibrated_competencies" = v_merged, "calibrated_rating" = round(v_rating)::integer,
    "status" = 'calibrated', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('appraisal.calibrated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."subject_user_id", 'status', v_row."status", 'rating', v_row."calibrated_rating"), 'appraisals/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal.calibrated',
    category => 'data',
    target_type => 'appraisal',
    record_id => v_row."id"::text,
    summary => 'appraisal calibrated',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."subject_user_id", 'status', v_row."status", 'rating', v_row."calibrated_rating")
  );
  perform "better_supabase"."appraisal_step"(v_row."id", 'calibration');
  return "better_supabase"."appraisal_json"(v_row."id", true);
end;
$$;
revoke execute on function "better_supabase"."calibrate_appraisal_competencies"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."calibrate_appraisal_competencies"(uuid, jsonb, text) to authenticated, service_role;

-- Replaces the goals an appraisal looks back on with goal ids from the goals
-- block (or your own table). Needs appraisals.manage.
create or replace function "better_supabase"."set_appraisal_goals"(appraisal_id uuid, goal_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisals";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."appraisals" x where x."id" = set_appraisal_goals.appraisal_id for update;
  if not found then
    raise exception 'no such appraisal' using errcode = 'P0002', hint = 'APPRAISALS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to manage appraisals' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  if v_row."status" = 'signed_off' then
    raise exception 'a signed-off appraisal doesn''t change' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  delete from "better_supabase"."appraisal_goals" x where x."appraisal_id" = v_row."id";
  insert into "better_supabase"."appraisal_goals" ("tenant_id", "appraisal_id", "goal_id")
  select v_row."tenant_id", v_row."id", distinct_goal
  from (select distinct unnest(coalesce(set_appraisal_goals.goal_ids, '{}')) as distinct_goal) z
  where distinct_goal is not null;
  return "better_supabase"."appraisal_json"(v_row."id", true);
end;
$$;
revoke execute on function "better_supabase"."set_appraisal_goals"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."set_appraisal_goals"(uuid, uuid[]) to authenticated, service_role;

-- One appraisal with its reviews, calibrations and goals. Its subject, its
-- reviewers and readers of appraisals see it; only readers see everyone's
-- reviews and the calibrations.
create or replace function "better_supabase"."get_appraisal"(appraisal_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisals";
begin
  select * into v_row from "better_supabase"."appraisals" x where x."id" = get_appraisal.appraisal_id;
  if not found or not coalesce((coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.read'), false))) or (v_row."subject_user_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = v_row."id" and z."reviewer_id" = auth.uid())), false) then
    raise exception 'no such appraisal' using errcode = 'P0002', hint = 'APPRAISALS_NOT_FOUND';
  end if;
  return "better_supabase"."appraisal_json"(v_row."id", (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.read'), false))));
end;
$$;
revoke execute on function "better_supabase"."get_appraisal"(uuid) from public, anon;
grant execute on function "better_supabase"."get_appraisal"(uuid) to authenticated, service_role;

-- Appraisals of an organization. filters is { cycleId, status, subjectUserId,
-- mine: true, limit, offset }. Readers see all of them; everyone else sees
-- the ones they are the subject or a reviewer of.
create or replace function "better_supabase"."list_appraisals"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_appraisals.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
  v_all boolean := (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_appraisals.tenant is not null and coalesce(better_supabase.can('tenant', list_appraisals.tenant, 'appraisals.read'), false)));
begin
  return coalesce((
    select jsonb_agg("better_supabase"."appraisal_json"(y.id, v_all) order by y.created_at desc, y.id)
    from (
      select x."id" as id, x."created_at" as created_at
      from "better_supabase"."appraisals" x
      where x."tenant_id" = list_appraisals.tenant
        and (not v_filters ? 'cycleId' or x."cycle_id" = (v_filters ->> 'cycleId')::uuid)
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
        and (not v_filters ? 'subjectUserId' or x."subject_user_id" = (v_filters ->> 'subjectUserId')::uuid)
        and ((v_all and (v_filters ->> 'mine') is distinct from 'true') or (x."subject_user_id" = auth.uid()
    or exists (select 1 from "better_supabase"."appraisal_reviews" z where z."appraisal_id" = x."id" and z."reviewer_id" = auth.uid())))
      order by x."created_at" desc, x."id"
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_appraisals"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_appraisals"(uuid, jsonb) to authenticated, service_role;

-- Signs an appraisal off once its approval is final. Approvals calls it; it
-- isn't granted to anyone.
create or replace function "better_supabase"."appraisal_approved"(appraisal_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisals";
begin
  select * into v_row from "better_supabase"."appraisals" x
  where x."id" = appraisal_approved.appraisal_id and x."status" = 'awaiting_signoff' for update;
  if not found then
    return;
  end if;
  update "better_supabase"."appraisals" x
  set "status" = 'signed_off', "signed_off_at" = now(), "signed_off_by" = auth.uid(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('appraisal.finalized', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."subject_user_id", 'status', v_row."status", 'rating', coalesce(v_row."calibrated_rating"::numeric, v_row."rating")), 'appraisals/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/appraisals');
  perform better_supabase.audit_event(
    event_type => 'appraisal.finalized',
    category => 'data',
    target_type => 'appraisal',
    record_id => v_row."id"::text,
    summary => 'appraisal signed off',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."subject_user_id", 'status', v_row."status", 'rating', coalesce(v_row."calibrated_rating"::numeric, v_row."rating"))
  );
  perform "better_supabase"."appraisal_step"(v_row."id", 'sign_off');
end;
$$;
revoke execute on function "better_supabase"."appraisal_approved"(uuid) from public, anon, authenticated;

-- Sends an appraisal back to where it was when its sign-off is rejected.
-- Approvals calls it; it isn't granted to anyone.
create or replace function "better_supabase"."appraisal_rejected"(appraisal_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update "better_supabase"."appraisals" x
  set "status" = case when x."calibrated_rating" is null then 'reviewed' else 'calibrated' end,
    "approval_id" = null, "updated_at" = now()
  where x."id" = appraisal_rejected.appraisal_id and x."status" = 'awaiting_signoff'
$$;
revoke execute on function "better_supabase"."appraisal_rejected"(uuid) from public, anon, authenticated;

-- Signs an appraisal off. With the approvals block it files the sign-off as a
-- request under the organization's policy for appraisal sign_off (default: a
-- holder of appraisals.manage) and the appraisal waits as awaiting_signoff
-- until it is approved. Without approvals, a holder of appraisals.manage
-- signs it off directly. Needs a reviewed or calibrated appraisal in an open
-- cycle.
create or replace function "better_supabase"."sign_off_appraisal"(appraisal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."appraisals";
  v_cycle "better_supabase"."appraisal_cycles";
  v_payload jsonb;
  v_approval jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."appraisals" x where x."id" = sign_off_appraisal.appraisal_id for update;
  if not found then
    raise exception 'no such appraisal' using errcode = 'P0002', hint = 'APPRAISALS_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'appraisals.manage'), false))) then
    raise exception 'not allowed to sign off appraisals' using errcode = '42501', hint = 'APPRAISALS_FORBIDDEN';
  end if;
  select * into v_cycle from "better_supabase"."appraisal_cycles" x where x."id" = v_row."cycle_id";
  if v_cycle."status" <> 'open' or v_row."status" not in ('reviewed', 'calibrated') then
    raise exception 'only a reviewed or calibrated appraisal in an open cycle is signed off' using errcode = '55000', hint = 'APPRAISALS_STATE';
  end if;
  v_payload := jsonb_build_object('appraisalId', v_row."id", 'cycleId', v_row."cycle_id", 'subjectUserId', v_row."subject_user_id",
    'rating', coalesce(v_row."calibrated_rating"::numeric, v_row."rating")::text,
    'competencies', "better_supabase"."appraisal_json"(v_row."id", true) -> 'competencies');
  v_approval := "better_supabase"."open_approval"(
    v_row."tenant_id", 'appraisal', v_row."id"::text, 'sign_off',
    coalesce("better_supabase"."approval_effective_policy"(v_row."tenant_id", 'appraisal', 'sign_off', v_payload), '{"steps":[{"approvers":{"permission":"appraisals.manage"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb),
    null, v_payload
  );
  update "better_supabase"."appraisals" x
  set "status" = 'awaiting_signoff', "approval_id" = (v_approval ->> 'id')::uuid, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return "better_supabase"."appraisal_json"(v_row."id", true);
end;
$$;
revoke execute on function "better_supabase"."sign_off_appraisal"(uuid) from public, anon;
grant execute on function "better_supabase"."sign_off_appraisal"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."appraisal_cycles";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."appraisal_cycles";
create policy bsb_tenant_scope_select on "better_supabase"."appraisal_cycles" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('appraisals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."appraisal_cycles";
create policy bsb_tenant_scope_insert on "better_supabase"."appraisal_cycles" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."appraisal_cycles";
create policy bsb_tenant_scope_update on "better_supabase"."appraisal_cycles" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."appraisal_cycles";
create policy bsb_tenant_scope_delete on "better_supabase"."appraisal_cycles" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."appraisals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."appraisals";
create policy bsb_tenant_scope_select on "better_supabase"."appraisals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('appraisals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."appraisals";
create policy bsb_tenant_scope_insert on "better_supabase"."appraisals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."appraisals";
create policy bsb_tenant_scope_update on "better_supabase"."appraisals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."appraisals";
create policy bsb_tenant_scope_delete on "better_supabase"."appraisals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."appraisal_reviews";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."appraisal_reviews";
create policy bsb_tenant_scope_select on "better_supabase"."appraisal_reviews" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('appraisals.read')) and not "better_supabase"."appraisal_review_hidden"("id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."appraisal_reviews";
create policy bsb_tenant_scope_insert on "better_supabase"."appraisal_reviews" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."appraisal_reviews";
create policy bsb_tenant_scope_update on "better_supabase"."appraisal_reviews" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."appraisal_reviews";
create policy bsb_tenant_scope_delete on "better_supabase"."appraisal_reviews" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."appraisal_calibrations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."appraisal_calibrations";
create policy bsb_tenant_scope_select on "better_supabase"."appraisal_calibrations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('appraisals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."appraisal_calibrations";
create policy bsb_tenant_scope_insert on "better_supabase"."appraisal_calibrations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."appraisal_calibrations";
create policy bsb_tenant_scope_update on "better_supabase"."appraisal_calibrations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."appraisal_calibrations";
create policy bsb_tenant_scope_delete on "better_supabase"."appraisal_calibrations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."appraisal_competencies";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."appraisal_competencies";
create policy bsb_tenant_scope_select on "better_supabase"."appraisal_competencies" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('appraisals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."appraisal_competencies";
create policy bsb_tenant_scope_insert on "better_supabase"."appraisal_competencies" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."appraisal_competencies";
create policy bsb_tenant_scope_update on "better_supabase"."appraisal_competencies" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."appraisal_competencies";
create policy bsb_tenant_scope_delete on "better_supabase"."appraisal_competencies" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."appraisal_review_ratings";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."appraisal_review_ratings";
create policy bsb_tenant_scope_select on "better_supabase"."appraisal_review_ratings" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('appraisals.read')) and not "better_supabase"."appraisal_review_hidden"("review_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."appraisal_review_ratings";
create policy bsb_tenant_scope_insert on "better_supabase"."appraisal_review_ratings" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."appraisal_review_ratings";
create policy bsb_tenant_scope_update on "better_supabase"."appraisal_review_ratings" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."appraisal_review_ratings";
create policy bsb_tenant_scope_delete on "better_supabase"."appraisal_review_ratings" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."appraisal_goals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."appraisal_goals";
create policy bsb_tenant_scope_select on "better_supabase"."appraisal_goals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('appraisals.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."appraisal_goals";
create policy bsb_tenant_scope_insert on "better_supabase"."appraisal_goals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."appraisal_goals";
create policy bsb_tenant_scope_update on "better_supabase"."appraisal_goals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."appraisal_goals";
create policy bsb_tenant_scope_delete on "better_supabase"."appraisal_goals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.appraisals.api: entry points for the Data API.
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

create or replace function "api"."appraisal_review_hidden"(review_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."appraisal_review_hidden"($1) $$;
revoke execute on function "api"."appraisal_review_hidden"(uuid) from public, anon;
grant execute on function "api"."appraisal_review_hidden"(uuid) to authenticated, service_role;

create or replace function "api"."set_appraisal_competencies"(cycle_id uuid, competencies jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_appraisal_competencies"($1, $2) $$;
revoke execute on function "api"."set_appraisal_competencies"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_appraisal_competencies"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."create_appraisal_cycle"(tenant uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_appraisal_cycle"($1, $2) $$;
revoke execute on function "api"."create_appraisal_cycle"(uuid, jsonb) from public, anon;
grant execute on function "api"."create_appraisal_cycle"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."open_appraisal_cycle"(cycle_id uuid, assignments jsonb default '[]')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."open_appraisal_cycle"($1, $2) $$;
revoke execute on function "api"."open_appraisal_cycle"(uuid, jsonb) from public, anon;
grant execute on function "api"."open_appraisal_cycle"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."close_appraisal_cycle"(cycle_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."close_appraisal_cycle"($1) $$;
revoke execute on function "api"."close_appraisal_cycle"(uuid) from public, anon;
grant execute on function "api"."close_appraisal_cycle"(uuid) to authenticated, service_role;

create or replace function "api"."list_appraisal_cycles"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_appraisal_cycles"($1) $$;
revoke execute on function "api"."list_appraisal_cycles"(uuid) from public, anon;
grant execute on function "api"."list_appraisal_cycles"(uuid) to authenticated, service_role;

create or replace function "api"."submit_appraisal_review"(review_id uuid, input jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."submit_appraisal_review"($1, $2) $$;
revoke execute on function "api"."submit_appraisal_review"(uuid, jsonb) from public, anon;
grant execute on function "api"."submit_appraisal_review"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."calibrate_appraisal"(appraisal_id uuid, rating integer, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."calibrate_appraisal"($1, $2, $3) $$;
revoke execute on function "api"."calibrate_appraisal"(uuid, integer, text) from public, anon;
grant execute on function "api"."calibrate_appraisal"(uuid, integer, text) to authenticated, service_role;

create or replace function "api"."calibrate_appraisal_competencies"(appraisal_id uuid, competencies jsonb, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."calibrate_appraisal_competencies"($1, $2, $3) $$;
revoke execute on function "api"."calibrate_appraisal_competencies"(uuid, jsonb, text) from public, anon;
grant execute on function "api"."calibrate_appraisal_competencies"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "api"."set_appraisal_goals"(appraisal_id uuid, goal_ids uuid[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_appraisal_goals"($1, $2) $$;
revoke execute on function "api"."set_appraisal_goals"(uuid, uuid[]) from public, anon;
grant execute on function "api"."set_appraisal_goals"(uuid, uuid[]) to authenticated, service_role;

create or replace function "api"."get_appraisal"(appraisal_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_appraisal"($1) $$;
revoke execute on function "api"."get_appraisal"(uuid) from public, anon;
grant execute on function "api"."get_appraisal"(uuid) to authenticated, service_role;

create or replace function "api"."list_appraisals"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_appraisals"($1, $2) $$;
revoke execute on function "api"."list_appraisals"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_appraisals"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."sign_off_appraisal"(appraisal_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."sign_off_appraisal"($1) $$;
revoke execute on function "api"."sign_off_appraisal"(uuid) from public, anon;
grant execute on function "api"."sign_off_appraisal"(uuid) to authenticated, service_role;

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
